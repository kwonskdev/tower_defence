"""계정 삭제와 보관 기간 자동 정리 테스트 (#66). 실행: python -m unittest discover -s tools/accounts -p "test_*.py"
방침(#27): 계정은 마지막 접속 후 365일에 삭제, 판 기록은 계정과 함께 삭제(별도 보관 없음), 서버 로그 30일, 삭제 요청 처리.
이슈 체크리스트와 대응:
  - 365일 지난 계정이 자동으로 삭제된다: RetentionJobTest, PurgeTest
  - 계정이 삭제되면 그 계정의 판 기록(닉네임 포함)도 함께 삭제된다: DeleteAccountTest
  - 삭제 요청으로 계정을 지우는 명령이 있다: CliTest
  - 삭제된 계정이 순위/기록 조회에 나오지 않는다: DeleteAccountTest, HttpDeletionTest
"""
import contextlib
import hashlib
import io
import json
import os
import socket
import subprocess
import sys
import tempfile
import time
import threading
import unittest
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

import accounts_service as svc

KEY = "test-key-0123456789abcdef"
DAY = 86400


def h(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def player(account_id="", lane=0, nickname="게스트", left=False):
    return {"account_id": account_id, "lane": lane, "nickname": nickname, "boss_damage": 1.5, "lane_damage": 2.5, "ghost_boss_damage": 0, "left": left}


def match(match_id="a" * 32, level=3, ended=1_999_999_990, players=None):
    players = players or [player()]
    return svc.parse_match({
        "match_id": match_id, "started_at": ended - 100, "ended_at": ended, "player_count": len(players), "result": "lose",
        "boss_level": level, "duration_s": 100.0, "version": "0.1", "players": players,
    })


class PurgeTest(unittest.TestCase):
    def setUp(self):
        self.t = [2_000_000_000]
        self.db = svc.Db(":memory:", clock=lambda: self.t[0])

    def test_retention_constants_match_the_policy(self):
        self.assertEqual(svc.ACCOUNT_RETENTION_DAYS, 365)
        self.assertEqual(svc.LOG_RETENTION_DAYS, 30)

    def test_account_deleted_after_365_days_without_login(self):
        self.db.login(h("old"), "옛날", "옛날")
        self.t[0] += 366 * DAY
        self.db.login(h("new"), "최근", "최근")
        self.assertEqual(self.db.purge(), {"players": 1, "matches_deleted": 0, "matches_anonymized": 0})
        self.assertEqual(self.db.stats()["players"], 1)
        self.assertEqual(self.db.login(h("new"))["account"]["nickname"], "최근")

    def test_boundary_uses_last_seen_not_created(self):
        self.db.login(h("a"), "가", "가")
        self.db.login(h("b"), "나", "나")
        self.t[0] += 364 * DAY
        self.db.login(h("a"))                      # 가는 364일 만에 다시 접속: 마지막 접속이 갱신된다
        self.t[0] += 2 * DAY                       # 나는 마지막 접속 후 366일, 가는 2일
        self.assertEqual(self.db.purge()["players"], 1)
        self.assertIsNotNone(self.db.find_player("가"))
        self.assertIsNone(self.db.find_player("나"))
        self.t[0] -= 2 * DAY + 1                   # 정확히 365일 안(364일 + 소량)에서는 안 지운다
        self.assertEqual(self.db.purge()["players"], 0)

    def test_banned_accounts_are_purged_too_and_zero_disables(self):
        self.db.login(h("b"), "차단", "차단")
        self.db.set_banned("차단", True)
        self.t[0] += 400 * DAY
        self.assertEqual(self.db.purge(0)["players"], 0)        # 0이면 계정 정리는 건너뛴다
        self.assertEqual(self.db.purge()["players"], 1)         # 방침에 예외가 없으므로 차단 계정도 지운다
        self.assertEqual(self.db.stats()["players"], 0)

    def test_match_records_go_with_the_account_without_a_separate_retention(self):
        old = self.db.login(h("old"), "옛날", "옛날")["account"]["id"]
        self.db.record_match(match("1" * 32, players=[player(old, nickname="옛날")]))
        self.t[0] += 366 * DAY
        new = self.db.login(h("new"), "최근", "최근")["account"]["id"]
        self.db.record_match(match("2" * 32, ended=self.t[0] - 5, players=[player(new, nickname="최근")]))
        self.assertEqual(self.db.purge(), {"players": 1, "matches_deleted": 1, "matches_anonymized": 0})
        self.assertEqual([r["match_id"] for r in self.db.leaderboard("all", 10)], ["2" * 32])
        self.assertEqual(self.db.conn.execute("SELECT COUNT(*) FROM match_players").fetchone()[0], 1)

    def test_old_match_of_an_active_account_is_kept(self):
        """판 기록은 계정과 함께만 사라진다: 계정이 살아 있으면 오래된 판도 남는다 (별도 보관 기간 없음)."""
        a = self.db.login(h("a"), "철수", "철수")["account"]["id"]
        self.db.record_match(match(ended=self.t[0] - 700 * DAY, players=[player(a, nickname="철수")]))
        self.t[0] += 300 * DAY
        self.db.login(h("a"))
        self.assertEqual(self.db.purge()["players"], 0)
        self.assertEqual(self.db.stats()["matches"], 1)

    def test_purge_anonymizes_in_shared_match_and_removes_when_last_account_goes(self):
        a = self.db.login(h("a"), "철수", "철수")["account"]["id"]
        self.t[0] += 100 * DAY
        b = self.db.login(h("b"), "영희", "영희")["account"]["id"]
        self.db.record_match(match(players=[player(a, 0, "철수"), player(b, 1, "영희"), player("", 2, "손님")]))
        self.t[0] += 300 * DAY                     # 철수는 마지막 접속 후 400일, 영희는 300일
        self.assertEqual(self.db.purge(), {"players": 1, "matches_deleted": 0, "matches_anonymized": 1})
        self.assertEqual([p["nickname"] for p in self.db.leaderboard("all", 10)[0]["players"]], [svc.DELETED_NICKNAME, "영희", "손님"])
        self.t[0] += 100 * DAY
        self.assertEqual(self.db.purge(), {"players": 1, "matches_deleted": 1, "matches_anonymized": 0})
        self.assertEqual(self.db.conn.execute("SELECT COUNT(*) FROM match_players").fetchone()[0], 0)

    def test_matches_with_no_account_link_are_swept(self):
        """이전 버전이 남긴 전원 게스트/연결 끊긴 판 기록은 어느 계정과도 같이 지워질 수 없어서 정리 때 지운다."""
        self.db.conn.execute("INSERT INTO matches VALUES ('" + "9" * 32 + "', 1, 2, 1, 'win', 3, 10, 'x')")
        self.db.conn.execute("INSERT INTO match_players VALUES ('" + "9" * 32 + "', 0, NULL, '손님', 1, 1, 0, 0)")
        self.assertEqual(self.db.purge()["matches_deleted"], 1)
        self.assertEqual(self.db.stats()["matches"], 0)


class DeleteAccountTest(unittest.TestCase):
    """삭제가 실제로 일어나고, 삭제 뒤 순위/기록에 안 나온다."""

    def setUp(self):
        self.t = [2_000_000_000]
        self.db = svc.Db(":memory:", clock=lambda: self.t[0])
        self.a = self.db.login(h("a"), "철수", "철수")["account"]["id"]
        self.b = self.db.login(h("b"), "영희", "영희")["account"]["id"]

    def names_on_board(self, period="all"):
        return [p["nickname"] for r in self.db.leaderboard(period, 50) for p in r["players"]]

    def test_solo_match_is_deleted_with_account(self):
        self.db.record_match(match(players=[player(self.a, nickname="철수")]))
        self.assertEqual(self.db.delete_account("철수"), {"id": self.a, "matches_deleted": 1, "matches_anonymized": 0})
        self.assertIsNone(self.db.find_player(self.a))
        self.assertEqual(self.db.stats(), {"players": 1, "banned": 0, "matches": 0})
        self.assertEqual(self.db.leaderboard("all", 10), [])
        self.assertEqual(self.db.leaderboard("week", 10), [])
        self.assertEqual(self.db.conn.execute("SELECT COUNT(*) FROM match_players").fetchone()[0], 0)

    def test_team_match_keeps_other_players_and_anonymizes_the_deleted_one(self):
        self.db.record_match(match(players=[player(self.a, 0, "철수"), player(self.b, 1, "영희"), player("", 2, "손님")]))
        self.assertEqual(self.db.delete_account(self.a), {"id": self.a, "matches_deleted": 0, "matches_anonymized": 1})
        self.assertEqual(self.names_on_board(), [svc.DELETED_NICKNAME, "영희", "손님"])
        self.assertEqual(self.names_on_board("week"), [svc.DELETED_NICKNAME, "영희", "손님"])
        self.assertNotIn("철수", "\n".join(self.db.conn.iterdump()))                      # 닉네임이 DB 어디에도 없다
        self.assertEqual(self.db.leaderboard("all", 10)[0]["player_count"], 3)            # 판 인원수(방 기록)는 그대로
        self.assertIsNone(self.db.conn.execute("SELECT player_id FROM match_players WHERE lane = 0").fetchone()[0])   # 계정 연결 끊김

    def test_last_account_deleted_removes_the_whole_match_including_guests(self):
        self.db.record_match(match(players=[player(self.a, 0, "철수"), player(self.b, 1, "영희"), player("", 2, "손님")]))
        self.db.delete_account(self.a)
        self.assertEqual(self.db.stats()["matches"], 1)
        self.assertEqual(self.db.delete_account("영희")["matches_deleted"], 1)
        self.assertEqual(self.db.stats()["matches"], 0)
        self.assertEqual(self.db.conn.execute("SELECT COUNT(*) FROM match_players").fetchone()[0], 0)   # 게스트 줄도 같이 사라졌다
        self.assertNotIn("손님", "\n".join(self.db.conn.iterdump()))

    def test_other_accounts_matches_are_untouched(self):
        self.db.record_match(match("1" * 32, players=[player(self.a, nickname="철수")]))
        self.db.record_match(match("2" * 32, players=[player(self.b, nickname="영희")]))
        self.db.delete_account(self.a)
        self.assertEqual([r["match_id"] for r in self.db.leaderboard("all", 10)], ["2" * 32])
        self.assertEqual(self.names_on_board(), ["영희"])

    def test_banned_and_unknown_accounts(self):
        self.db.set_banned("철수", True)
        self.assertIsNotNone(self.db.delete_account("철수"))     # 차단 계정도 삭제 요청으로 지운다
        self.assertIsNone(self.db.delete_account("철수"))
        self.assertIsNone(self.db.delete_account("없는사람"))
        self.assertIsNone(self.db.delete_account(""))
        self.assertEqual(self.db.stats()["players"], 1)

    def test_same_token_after_deletion_is_a_new_account(self):
        self.db.delete_account(self.a)
        again = self.db.login(h("a"), "철수", "철수")
        self.assertTrue(again["account"]["created"])
        self.assertNotEqual(again["account"]["id"], self.a)

    def test_late_record_of_deleted_account_is_stored_anonymously(self):
        """계정이 삭제된 뒤 방 서버 대기열에서 늦게 도착한 판 기록이 닉네임을 되살리면 안 된다."""
        self.db.delete_account(self.a)
        res = self.db.record_match(match(players=[player(self.a, 0, "철수"), player(self.b, 1, "영희")]))
        self.assertTrue(res["stored"])
        self.assertEqual(self.names_on_board(), [svc.DELETED_NICKNAME, "영희"])
        self.assertNotIn("철수", "\n".join(self.db.conn.iterdump()))

    def test_match_with_no_living_account_is_not_stored(self):
        res = self.db.record_match(match("1" * 32, players=[player("", 0, "손님")]))
        self.assertEqual(res, {"status": "ok", "duplicate": False, "stored": False})           # 전원 게스트
        self.db.delete_account(self.a)
        self.assertFalse(self.db.record_match(match("2" * 32, players=[player(self.a, 0, "철수")]))["stored"])    # 참가 계정이 이미 삭제됨
        self.assertEqual(self.db.stats()["matches"], 0)

    def test_describe_previews_what_deletion_would_do(self):
        self.db.record_match(match("1" * 32, ended=500, players=[player(self.a, 0, "철수"), player(self.b, 1, "영희")]))
        self.db.record_match(match("2" * 32, ended=900, players=[player(self.a, 0, "철수")]))
        info = self.db.describe_player("철수")
        self.assertEqual((info["id"], info["matches"], info["matches_deleted"], info["matches_anonymized"], info["last_match_at"]), (self.a, 2, 1, 1, 900))
        self.assertNotIn("token_hash", info)
        self.assertEqual(self.db.stats()["players"], 2)                # 미리보기는 아무것도 안 지운다
        self.assertEqual(self.db.stats()["matches"], 2)
        self.assertIsNone(self.db.describe_player("없는사람"))

    def test_deleted_text_is_really_gone_from_the_database_file(self):
        """SQLite는 지운 글자를 빈 페이지에 남긴다. secure_delete로 0으로 덮어쓰는지 파일을 직접 읽어 확인한다."""
        with tempfile.TemporaryDirectory() as d:
            path = str(Path(d) / "a.db")
            db = svc.Db(path)
            acc = db.login(h("z"), "지워질이름", "지워질이름")["account"]["id"]
            db.login(h("y"), "남는이름", "남는이름")
            db.record_match(match(players=[player(acc, 0, "지워질이름"), player("", 1, "지워질손님")]))
            db.conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            self.assertIn("지워질이름".encode(), Path(path).read_bytes())    # 검사 자체가 유효한지: 지우기 전에는 파일에 있다
            db.delete_account(acc)
            db.conn.execute("PRAGMA wal_checkpoint(TRUNCATE)")
            raw = Path(path).read_bytes()
            wal = Path(path + "-wal")
            if wal.exists():
                raw += wal.read_bytes()
            for gone in ("지워질이름", "지워질손님", acc):
                self.assertNotIn(gone.encode(), raw, gone)
            self.assertIn("남는이름".encode(), raw)
            db.close()


class RetentionJobTest(unittest.TestCase):
    """365일 지난 계정이 서비스 안의 정기 작업으로 자동 삭제된다 + 로그 30일 정리."""

    def test_purge_logs_removes_only_old_log_files(self):
        with tempfile.TemporaryDirectory() as d:
            now_ts = 10_000_000.0
            for name, age_days in (("server-old.log", 31), ("accounts-old.log", 40), ("server-new.log", 29), ("keep.txt", 99)):
                f = Path(d) / name
                f.write_text("x")
                os.utime(f, (now_ts - age_days * DAY, now_ts - age_days * DAY))
            self.assertEqual(svc.purge_logs(d, 30, at=now_ts), 2)
            self.assertEqual(sorted(p.name for p in Path(d).iterdir()), ["keep.txt", "server-new.log"])
            self.assertEqual(svc.purge_logs(d, 0, at=now_ts), 0)
            self.assertEqual(svc.purge_logs(None, 30), 0)
            self.assertEqual(svc.purge_logs(str(Path(d) / "없는폴더"), 30), 0)

    def test_timer_runs_purge_at_start_then_every_interval(self):
        t = [1_000_000]
        db = svc.Db(":memory:", clock=lambda: t[0])
        mono = [0.0]
        lines = []
        job = svc.Maintenance(db, purge_hours=24, backup_hours=0, mono=lambda: mono[0], out=lines.append)
        db.login(h("old"), "옛날", "옛날")
        t[0] += 366 * DAY
        job.tick()                                                  # 서비스가 켜질 때: 밀린 정리를 바로 한다
        self.assertEqual(db.stats()["players"], 0)
        db.login(h("later"), "나중", "나중")
        t[0] += 366 * DAY                                           # 이 계정도 오래됐지만
        mono[0] += 23 * 3600
        job.tick()
        self.assertEqual(db.stats()["players"], 1)                  # 24시간이 안 됐으니 아직 안 돈다
        mono[0] += 3600
        job.tick()
        self.assertEqual(db.stats()["players"], 0)                  # 24시간 뒤에 자동으로 지워진다
        self.assertEqual(len(lines), 2)
        self.assertTrue(all(line.startswith("보관 기간 정리: ") for line in lines))
        self.assertNotIn("나중", "".join(lines))                    # 로그에는 개수만 남고 닉네임/ID는 안 남는다

    def test_timer_can_be_disabled_and_cleans_logs_too(self):
        db = svc.Db(":memory:")
        with tempfile.TemporaryDirectory() as d:
            f = Path(d) / "server-1.log"
            f.write_text("x")
            os.utime(f, (1, 1))
            svc.Maintenance(db, purge_hours=0, backup_hours=0, log_dir=d, mono=lambda: 0.0, out=lambda _l: None).tick()
            self.assertTrue(f.exists())                             # purge_hours=0: 자동 정리 끔
            svc.Maintenance(db, purge_hours=24, backup_hours=0, log_dir=d, mono=lambda: 0.0, out=lambda _l: None).tick()
            self.assertFalse(f.exists())                            # 30일 지난 로그가 지워졌다

    def test_backup_still_runs_on_the_same_timer(self):
        db = svc.Db(":memory:")
        with tempfile.TemporaryDirectory() as d:
            svc.Maintenance(db, backup_dir=d, backup_hours=24, purge_hours=0, mono=lambda: 0.0, out=lambda _l: None).tick()
            self.assertEqual(len(list(Path(d).glob("accounts-*.db"))), 1)

    def test_failed_purge_does_not_stop_the_timer(self):
        db = svc.Db(":memory:")
        db.close()                                                  # 닫힌 DB: purge가 예외를 낸다
        job = svc.Maintenance(db, purge_hours=24, backup_hours=0, mono=lambda: 0.0, out=lambda _l: None)
        with contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(job.run_retention(), {})


class ServiceProcessTest(unittest.TestCase):
    """실제 서비스 프로세스가 스스로 365일 지난 계정을 지운다 (사람이 purge를 실행하지 않아도)."""

    def test_running_service_deletes_old_accounts_by_itself(self):
        with tempfile.TemporaryDirectory() as d:
            path = str(Path(d) / "a.db")
            logs = Path(d) / "logs"
            logs.mkdir()
            (logs / "server-old.log").write_text("x")
            os.utime(logs / "server-old.log", (1, 1))
            (logs / "server-new.log").write_text("x")
            real_now = int(time.time())
            db = svc.Db(path, clock=lambda: real_now - 400 * DAY)
            old = db.login(h("old"), "옛날", "옛날")["account"]["id"]
            db.record_match(match(players=[player(old, nickname="옛날")]))
            db.close()
            db = svc.Db(path)                                               # 지금 시계: 이 계정은 방금 접속
            keep = db.login(h("keep"), "최근", "최근")["account"]["id"]
            db.record_match(match("2" * 32, players=[player(keep, nickname="최근")]))
            db.close()
            with socket.socket() as sk:
                sk.bind(("127.0.0.1", 0))
                port = sk.getsockname()[1]
            env = dict(os.environ, LANEWARS_ACCOUNTS_KEY=KEY, PYTHONDONTWRITEBYTECODE="1")
            proc = subprocess.Popen([sys.executable, "-I", svc.__file__, "--db", path, "serve", "--port", str(port), "--tick-sec", "0.2",
                                     "--backup-interval-hours", "0", "--log-dir", str(logs)], env=env, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)
            try:
                deadline = time.time() + 15
                left = None
                while time.time() < deadline:
                    probe = svc.Db(path)
                    left = probe.stats()
                    probe.close()
                    if left["players"] == 1 and (logs / "server-old.log").exists() is False:
                        break
                    time.sleep(0.2)
                self.assertEqual(left, {"players": 1, "banned": 0, "matches": 1})
                self.assertFalse((logs / "server-old.log").exists())      # 30일 지난 로그도 같이
                self.assertTrue((logs / "server-new.log").exists())
            finally:
                proc.terminate()
                out = proc.communicate(timeout=10)[0].decode("utf-8", "replace")
            self.assertIn("보관 기간 정리: ", out)
            self.assertNotIn("옛날", out.split("계정 서비스 열림")[1] if "계정 서비스 열림" in out else out)    # 로그에 지운 계정의 닉네임은 안 남는다


class CliTest(unittest.TestCase):
    """삭제 요청 처리 명령"""

    def run_cli(self, *argv):
        out = io.StringIO()
        with contextlib.redirect_stdout(out):
            code = svc.main(list(argv))
        return code, out.getvalue()

    def test_show_preview_and_delete(self):
        with tempfile.TemporaryDirectory() as d:
            path = str(Path(d) / "a.db")
            db = svc.Db(path)
            acc = db.login(h("a"), "철수", "철수")["account"]["id"]
            db.record_match(match(players=[player(acc, 0, "철수")]))
            db.close()
            code, out = self.run_cli("--db", path, "show", "철수")
            self.assertEqual(code, 0)
            self.assertIn(acc, out)
            self.assertNotIn(h("a"), out)                           # 토큰 해시는 보여 주지 않는다
            code, out = self.run_cli("--db", path, "delete-account", "철수")      # --yes 없음: 미리보기만
            self.assertEqual(code, 2)
            self.assertIn("--yes", out)
            db = svc.Db(path)
            self.assertEqual(db.stats()["players"], 1)
            db.close()
            code, out = self.run_cli("--db", path, "delete-account", acc, "--yes")
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(out), {"id": acc, "matches_deleted": 1, "matches_anonymized": 0})
            db = svc.Db(path)
            self.assertEqual(db.stats(), {"players": 0, "banned": 0, "matches": 0})
            db.close()
            code, _ = self.run_cli("--db", path, "delete-account", acc, "--yes")        # 이미 없다
            self.assertEqual(code, 1)
            code, _ = self.run_cli("--db", path, "show", "없는사람")
            self.assertEqual(code, 1)

    def test_purge_command_defaults_to_365_days_and_cleans_logs(self):
        with tempfile.TemporaryDirectory() as d:
            path = str(Path(d) / "a.db")
            db = svc.Db(path, clock=lambda: 1_000_000)                # 1970년에 마지막으로 접속한 계정
            db.login(h("a"), "철수", "철수")
            db.close()
            logs = Path(d) / "logs"
            logs.mkdir()
            (logs / "old.log").write_text("x")
            os.utime(logs / "old.log", (1, 1))
            code, out = self.run_cli("--db", path, "purge", "--log-dir", str(logs))
            self.assertEqual(code, 0)
            self.assertEqual(json.loads(out), {"players": 1, "matches_deleted": 0, "matches_anonymized": 0, "logs": 1})


class HttpDeletionTest(unittest.TestCase):
    def setUp(self):
        self.db = svc.Db(":memory:")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), svc.make_handler(self.db, KEY))
        self.server.daemon_threads = True
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def call(self, method, path, body=None):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method=method, data=None if body is None else json.dumps(body).encode(),
                                     headers={"X-Api-Key": KEY, "Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=5) as r:
            return json.loads(r.read())

    def test_deleted_account_is_gone_from_leaderboard_and_login_over_http(self):
        a = self.call("POST", "/v1/login", {"token_hash": h("ta"), "name": "철수", "name_key": "철수"})["account"]["id"]
        b = self.call("POST", "/v1/login", {"token_hash": h("tb"), "name": "영희", "name_key": "영희"})["account"]["id"]
        self.call("POST", "/v1/matches", dict(match("1" * 32, level=9, players=[player(a, 0, "철수"), player(b, 1, "영희")])))
        self.call("POST", "/v1/matches", dict(match("2" * 32, level=5, players=[player(a, 0, "철수")])))
        self.assertEqual(self.db.delete_account(a)["matches_deleted"], 1)
        for period in ("all", "week"):
            r = self.call("GET", f"/v1/leaderboard?period={period}&limit=10")
            self.assertEqual([[p["nickname"] for p in row["players"]] for row in r["rows"]], [[svc.DELETED_NICKNAME, "영희"]])
        again = self.call("POST", "/v1/login", {"token_hash": h("ta"), "name": "철수", "name_key": "철수"})     # 삭제된 계정의 토큰: 새 계정
        self.assertTrue(again["account"]["created"])
        self.assertNotEqual(again["account"]["id"], a)


if __name__ == "__main__":
    unittest.main()
