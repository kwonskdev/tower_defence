"""계정 서비스 테스트 (#25). 실행: python -m unittest discover -s tools/accounts -p "test_*.py"
서비스를 실제 HTTP로 띄워 확인한다 (표준 라이브러리만)."""
import hashlib
import json
import tempfile
import threading
import unittest
import urllib.error
import urllib.request
from http.server import ThreadingHTTPServer
from pathlib import Path

import accounts_service as svc

KEY = "test-key-0123456789abcdef"


def h(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def match(match_id="a" * 32, level=3, result="lose", duration=100.0, ended=1000, players=None):
    return {
        "match_id": match_id, "started_at": ended - 100, "ended_at": ended, "player_count": len(players or [1]), "result": result,
        "boss_level": level, "duration_s": duration, "version": "0.1",
        "players": players or [{"account_id": "", "lane": 0, "nickname": "게스트", "boss_damage": 1.5, "lane_damage": 2.5, "ghost_boss_damage": 0, "left": False}],
    }


class DbTest(unittest.TestCase):
    def setUp(self):
        self.t = [1_000_000]
        self.db = svc.Db(":memory:", clock=lambda: self.t[0])

    def test_first_login_creates_account_and_second_finds_same(self):
        a = self.db.login(h("t1"), "철수", "철수")
        self.assertEqual(a["status"], "ok")
        self.assertTrue(a["account"]["created"])
        self.assertRegex(a["account"]["id"], r"^[0-9a-f]{16}$")
        b = self.db.login(h("t1"), "철수", "철수")
        self.assertFalse(b["account"]["created"])
        self.assertEqual(b["account"]["id"], a["account"]["id"])
        self.assertEqual(self.db.stats()["players"], 1)

    def test_token_is_stored_only_as_hash(self):
        self.db.login(h("secret-token"), "철수", "철수")
        rows = self.db.conn.execute("SELECT token_hash FROM players").fetchall()
        self.assertEqual(rows[0][0], h("secret-token"))
        dump = "\n".join(self.db.conn.iterdump())
        self.assertNotIn("secret-token", dump)

    def test_nickname_unique_for_new_account(self):
        self.db.login(h("t1"), "철수", "철수")
        self.assertEqual(self.db.login(h("t2"), "철수", "철수")["status"], "nick_taken")
        self.assertEqual(self.db.stats()["players"], 1)

    def test_rename_rules(self):
        self.db.login(h("t1"), "철수", "철수")
        self.db.login(h("t2"), "영희", "영희")
        self.assertEqual(self.db.login(h("t1"), "영희", "영희")["name_result"], "taken")       # 겹침: 거부, 기존 이름 유지
        self.assertEqual(self.db.login(h("t1"), "영희", "영희")["account"]["nickname"], "철수")
        first = self.db.login(h("t1"), "민수", "민수")                                           # 가입 뒤 첫 변경은 바로
        self.assertEqual((first["name_result"], first["account"]["nickname"]), ("ok", "민수"))
        self.t[0] += svc.NICK_COOLDOWN_SEC - 1
        self.assertEqual(self.db.login(h("t1"), "지수", "지수")["name_result"], "cooldown")      # 7일 안에는 못 바꾼다
        self.t[0] += 2
        self.assertEqual(self.db.login(h("t1"), "지수", "지수")["name_result"], "ok")
        self.assertEqual(self.db.login(h("t1"))["name_result"], "same")                           # 이름을 안 주면 그대로

    def test_new_account_rate_limit_and_recovery(self):
        db = svc.Db(":memory:", clock=lambda: self.t[0], new_accounts_per_min=3)
        for i in range(3):
            self.assertEqual(db.login(h(f"t{i}"), f"n{i}", f"n{i}")["status"], "ok")
        self.assertEqual(db.login(h("t9"), "n9", "n9")["status"], "rate_limited")
        self.assertEqual(db.login(h("t0"), "n0", "n0")["status"], "ok")                           # 이미 있는 계정은 한도와 상관없다
        self.t[0] += 61
        self.assertEqual(db.login(h("t9"), "n9", "n9")["status"], "ok")

    def test_banned_account(self):
        a = self.db.login(h("t1"), "철수", "철수")
        self.assertTrue(self.db.set_banned("철수", True))
        self.assertEqual(self.db.login(h("t1"), "철수", "철수")["status"], "banned")
        self.assertTrue(self.db.set_banned(a["account"]["id"], False))
        self.assertEqual(self.db.login(h("t1"), "철수", "철수")["status"], "ok")
        self.assertFalse(self.db.set_banned("없는사람", True))

    def test_record_match_idempotent_and_guest(self):
        a = self.db.login(h("t1"), "철수", "철수")["account"]["id"]
        m = match(players=[
            {"account_id": a, "lane": 0, "nickname": "철수", "boss_damage": 10, "lane_damage": 4, "ghost_boss_damage": 1, "left": False},
            {"account_id": "", "lane": 1, "nickname": "게스트", "boss_damage": 0, "lane_damage": 0, "ghost_boss_damage": 0, "left": True}])
        self.assertEqual(self.db.record_match(svc.parse_match(m)), {"status": "ok", "duplicate": False})
        self.assertEqual(self.db.record_match(svc.parse_match(m)), {"status": "ok", "duplicate": True})  # 재시도해도 한 번만
        self.assertEqual(self.db.stats()["matches"], 1)
        rows = self.db.conn.execute("SELECT lane, player_id, left_early FROM match_players ORDER BY lane").fetchall()
        self.assertEqual([tuple(r) for r in rows], [(0, a, 0), (1, None, 1)])

    def test_leaderboard_order_and_week(self):
        def add(i, level, result, dur, ended):
            self.db.record_match(svc.parse_match(match(match_id=f"{i:032x}", level=level, result=result, duration=dur, ended=ended)))
        now = self.t[0]
        add(1, 5, "lose", 300, now - 10)
        add(2, 10, "lose", 900, now - 10)
        add(3, 10, "win", 1200, now - 10)
        add(4, 10, "win", 1000, now - 10)
        add(5, 10, "win", 1000, now - 8 * 86400)   # 지난주: 전체에만
        ids = [r["match_id"] for r in self.db.leaderboard("all", 10)]
        self.assertEqual(ids, [f"{5:032x}", f"{4:032x}", f"{3:032x}", f"{2:032x}", f"{1:032x}"])  # 4와 5는 레벨/승리/시간이 같아 먼저 끝난 5가 위
        self.assertEqual([r["rank"] for r in self.db.leaderboard("all", 10)], [1, 2, 3, 4, 5])
        week = [r["match_id"] for r in self.db.leaderboard("week", 10)]
        self.assertEqual(week, [f"{4:032x}", f"{3:032x}", f"{2:032x}", f"{1:032x}"])
        self.assertEqual(len(self.db.leaderboard("all", 2)), 2)

    def test_backup_keeps_n_and_restores(self):
        self.db.login(h("t1"), "철수", "철수")
        with tempfile.TemporaryDirectory() as d:
            for _ in range(4):
                self.t[0] += 1
                self.db.backup(d, 2)
            files = sorted(Path(d).glob("accounts-*.db"))
            self.assertEqual(len(files), 2)
            restored = svc.Db(str(files[-1]))
            self.assertEqual(restored.stats()["players"], 1)
            restored.close()

    def test_purge(self):
        self.db.login(h("old"), "옛날", "옛날")
        self.t[0] += 200 * 86400
        self.db.login(h("new"), "최근", "최근")
        self.assertEqual(self.db.purge(180, 0), {"players": 1, "matches": 0})
        self.assertEqual(self.db.stats()["players"], 1)


class PersistenceTest(unittest.TestCase):
    def test_data_survives_reopen(self):
        with tempfile.TemporaryDirectory() as d:
            path = str(Path(d) / "a.db")
            db = svc.Db(path)
            acc = db.login(h("t1"), "철수", "철수")["account"]["id"]
            db.record_match(svc.parse_match(match()))
            db.close()
            db = svc.Db(path)
            again = db.login(h("t1"), "철수", "철수")
            self.assertEqual(again["account"]["id"], acc)
            self.assertFalse(again["account"]["created"])
            self.assertEqual(db.stats()["matches"], 1)
            db.close()


class ValidationTest(unittest.TestCase):
    def test_bad_inputs_rejected(self):
        for body in [{}, {"token_hash": "zz"}, {"token_hash": h("a"), "name": "x"}, {"token_hash": h("a"), "name": "x" * 99, "name_key": "x"}]:
            with self.assertRaises(svc.BadRequest):
                svc.parse_login(body)
        bad = match()
        bad["result"] = "draw"
        with self.assertRaises(svc.BadRequest):
            svc.parse_match(bad)
        bad = match()
        bad["players"][0]["boss_damage"] = -1
        with self.assertRaises(svc.BadRequest):
            svc.parse_match(bad)
        bad = match()
        bad["players"][0]["lane"] = 8
        with self.assertRaises(svc.BadRequest):
            svc.parse_match(bad)
        bad = match()
        bad["match_id"] = "short"
        with self.assertRaises(svc.BadRequest):
            svc.parse_match(bad)


class HttpTest(unittest.TestCase):
    def setUp(self):
        self.db = svc.Db(":memory:")
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), svc.make_handler(self.db, KEY))
        self.server.daemon_threads = True
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()

    def call(self, method, path, body=None, key=KEY):
        req = urllib.request.Request(f"http://127.0.0.1:{self.port}{path}", method=method, data=None if body is None else json.dumps(body).encode(),
                                     headers={"X-Api-Key": key, "Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(req, timeout=5) as r:
                return r.status, json.loads(r.read())
        except urllib.error.HTTPError as e:
            return e.code, json.loads(e.read())

    def test_key_required(self):
        self.assertEqual(self.call("GET", "/v1/health", key="wrong")[0], 401)
        self.assertEqual(self.call("GET", "/v1/health")[0], 200)

    def test_login_match_leaderboard_over_http(self):
        code, r = self.call("POST", "/v1/login", {"token_hash": h("t1"), "name": "철수", "name_key": "철수"})
        self.assertEqual((code, r["status"], r["account"]["nickname"]), (200, "ok", "철수"))
        code, r = self.call("POST", "/v1/matches", match(players=[{"account_id": r["account"]["id"], "lane": 0, "nickname": "철수", "boss_damage": 1, "lane_damage": 1, "ghost_boss_damage": 0, "left": False}]))
        self.assertEqual((code, r["status"]), (200, "ok"))
        code, r = self.call("GET", "/v1/leaderboard?period=all&limit=5")
        self.assertEqual((code, len(r["rows"]), r["rows"][0]["players"][0]["nickname"]), (200, 1, "철수"))
        self.assertEqual(self.call("GET", "/v1/leaderboard?period=year")[0], 400)
        self.assertEqual(self.call("POST", "/v1/login", {"token_hash": "x"})[0], 400)
        self.assertEqual(self.call("GET", "/v1/nope")[0], 404)


if __name__ == "__main__":
    unittest.main()
