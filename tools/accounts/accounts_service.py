#!/usr/bin/env python3
"""Lane Wars 계정/판 기록 서비스 (#25).

Godot 서버(방 서버)가 직접 DB에 붙지 않고 이 작은 HTTP 서비스를 거친다 (결정 근거: docs/accounts-and-db.md).
  - Python 표준 라이브러리만 쓴다 (설치할 것 없음). 저장소는 SQLite 파일 하나(WAL).
  - 127.0.0.1에만 연다. 모든 요청은 X-Api-Key 헤더(환경 변수 LANEWARS_ACCOUNTS_KEY)가 맞아야 한다.
  - 나중에 서버를 나누면 이 파일 뒤의 저장소(아래 Db 클래스)만 Postgres로 바꾸면 된다. Godot 쪽은 AccountStore 한 곳만 이 서비스를 안다.

실행:
  LANEWARS_ACCOUNTS_KEY=비밀 python tools/accounts/accounts_service.py --db data/accounts.db serve --port 47310   (--db는 항상 서브명령 앞)
관리 (서비스를 끄지 않고 쓸 수 있다):
  python tools/accounts/accounts_service.py --db data/accounts.db ban <계정ID 또는 닉네임> / unban <...> / backup / stats
  python tools/accounts/accounts_service.py --db data/accounts.db show <계정ID 또는 닉네임>                 # 삭제 요청 확인용 (토큰 해시는 보여 주지 않는다)
  python tools/accounts/accounts_service.py --db data/accounts.db delete-account <계정ID 또는 닉네임> --yes   # 삭제 요청 처리 (--yes가 없으면 미리보기만, #66)
  python tools/accounts/accounts_service.py --db data/accounts.db purge [--inactive-days 365] [--log-dir logs --log-days 30]   # 보관 기간 정리 (서비스가 매일 자동으로도 한다, #66)

엔드포인트 (JSON):
  GET  /v1/health
  POST /v1/login        {token_hash, name?, name_key?}  -> {status, account:{id,nickname,created}, name_result?}
  POST /v1/matches      {match_id, ...}                  -> {status, duplicate}  (match_id가 같으면 한 번만 저장: 재시도해도 안전)
  GET  /v1/leaderboard?period=all|week&limit=N           -> {status, rows:[...]}
"""
import argparse
import hmac
import json
import os
import re
import secrets
import shutil
import sqlite3
import sys
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import parse_qs, urlparse

SCHEMA_VERSION = 1
ACCOUNT_RETENTION_DAYS = 365             # 방침(#27): 마지막 접속 후 365일이 지나면 계정과 판 기록을 함께 삭제한다
LOG_RETENTION_DAYS = 30                  # 방침(#27): 서버 로그는 30일 후 삭제한다
PURGE_INTERVAL_HOURS = 24.0              # 서비스가 보관 기간 정리를 자동으로 도는 간격
DELETED_NICKNAME = "(삭제된 사용자)"      # 계정이 삭제된 참가자의 줄에 남는 이름 (기록 속 닉네임은 지운다)
NICK_COOLDOWN_SEC = 7 * 24 * 3600        # 닉네임 변경은 7일에 한 번 (가입 뒤 첫 변경은 바로)
NEW_ACCOUNTS_PER_MIN = 30                # 서버 전체 신규 계정 분당 한도 (계정 남발 방지)
WEEK_SEC = 7 * 24 * 3600
MAX_BODY = 64 * 1024
MAX_NICK_LEN = 32                        # 방어용 상한 (실제 길이 정책은 Godot의 Nicknames/Balance가 정한다)
MAX_PLAYERS = 8
HEX64 = re.compile(r"^[0-9a-f]{64}$")
ID_RE = re.compile(r"^[0-9a-f]{16}$")
MATCH_ID_RE = re.compile(r"^[0-9a-f]{32}$")

SCHEMA = """
CREATE TABLE IF NOT EXISTS players (
    id              TEXT PRIMARY KEY,
    token_hash      TEXT NOT NULL UNIQUE,
    nickname        TEXT NOT NULL,
    nick_key        TEXT NOT NULL UNIQUE,
    nick_changed_at INTEGER,
    created_at      INTEGER NOT NULL,
    last_seen_at    INTEGER NOT NULL,
    banned          INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS matches (
    id           TEXT PRIMARY KEY,
    started_at   INTEGER NOT NULL,
    ended_at     INTEGER NOT NULL,
    player_count INTEGER NOT NULL,
    result       TEXT NOT NULL CHECK (result IN ('win', 'lose')),
    boss_level   INTEGER NOT NULL,
    duration_s   REAL NOT NULL,
    version      TEXT NOT NULL
);
CREATE INDEX IF NOT EXISTS matches_ended ON matches (ended_at);
CREATE TABLE IF NOT EXISTS match_players (
    match_id          TEXT NOT NULL REFERENCES matches (id) ON DELETE CASCADE,
    lane              INTEGER NOT NULL,
    player_id         TEXT,
    nickname          TEXT NOT NULL,
    boss_damage       REAL NOT NULL,
    lane_damage       REAL NOT NULL,
    ghost_boss_damage REAL NOT NULL,
    left_early        INTEGER NOT NULL,
    PRIMARY KEY (match_id, lane)
);
CREATE INDEX IF NOT EXISTS match_players_player ON match_players (player_id);
"""


def now() -> int:
    return int(time.time())


def _readable(info: dict) -> dict:
    """show 출력용: unix 초를 사람이 읽는 시각으로"""
    out = dict(info)
    for k in ("created_at", "last_seen_at", "last_match_at"):
        if out.get(k):
            out[k] = datetime.fromtimestamp(out[k]).strftime("%Y-%m-%d %H:%M:%S")
    return out


class Db:
    """저장소. 요청마다 락을 잡고 한 연결을 쓴다 (쓰기는 판이 끝날 때뿐이라 충분하다)."""

    def __init__(self, path: str, clock=now, new_accounts_per_min: int = NEW_ACCOUNTS_PER_MIN):
        self.path = path
        self.clock = clock
        self.new_accounts_per_min = new_accounts_per_min
        self._lock = threading.RLock()
        self._recent_creates = []
        if path != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self.conn = sqlite3.connect(path, check_same_thread=False, isolation_level=None)
        self.conn.row_factory = sqlite3.Row
        self.conn.execute("PRAGMA foreign_keys = ON")
        self.conn.execute("PRAGMA secure_delete = ON")   # 지운 닉네임/계정 정보가 빈 페이지에 글자 그대로 남지 않게 0으로 덮어쓴다 (#66)
        if path != ":memory:":
            self.conn.execute("PRAGMA journal_mode = WAL")
        self._migrate()

    def _migrate(self) -> None:
        with self._lock:
            version = self.conn.execute("PRAGMA user_version").fetchone()[0]
            if version > SCHEMA_VERSION:
                raise RuntimeError(f"DB 스키마 {version}이 이 서비스({SCHEMA_VERSION})보다 새 것이다")
            self.conn.executescript(SCHEMA)
            self.conn.execute(f"PRAGMA user_version = {SCHEMA_VERSION}")

    def close(self) -> None:
        with self._lock:
            self.conn.close()

    # ---- 계정 ----------------------------------------------------------------

    def login(self, token_hash: str, name: str = "", name_key: str = "") -> dict:
        """토큰 해시로 계정을 찾고, 없으면 만든다. name은 원하는 닉네임(없으면 바꾸지 않는다).
        status: ok / banned / rate_limited / nick_taken(새 계정인데 닉네임이 겹침: 호출자가 다른 이름으로 다시 부른다)"""
        with self._lock:
            t = self.clock()
            row = self.conn.execute("SELECT * FROM players WHERE token_hash = ?", (token_hash,)).fetchone()
            if row is None:
                if not name or not name_key:
                    return {"status": "error", "reason": "name_required"}
                self._recent_creates = [x for x in self._recent_creates if t - x < 60]
                if len(self._recent_creates) >= self.new_accounts_per_min:
                    return {"status": "rate_limited"}
                if self.conn.execute("SELECT 1 FROM players WHERE nick_key = ?", (name_key,)).fetchone():
                    return {"status": "nick_taken"}
                pid = secrets.token_hex(8)
                self.conn.execute(
                    "INSERT INTO players (id, token_hash, nickname, nick_key, created_at, last_seen_at) VALUES (?,?,?,?,?,?)",
                    (pid, token_hash, name, name_key, t, t))
                self._recent_creates.append(t)
                return {"status": "ok", "account": {"id": pid, "nickname": name, "created": True}, "name_result": "ok"}
            if row["banned"]:
                return {"status": "banned", "account": {"id": row["id"], "nickname": row["nickname"], "created": False}}
            result = "same"
            nickname = row["nickname"]
            if name and name_key and name_key != row["nick_key"]:
                result = self._rename(row, name, name_key, t)
                if result == "ok":
                    nickname = name
            self.conn.execute("UPDATE players SET last_seen_at = ? WHERE id = ?", (t, row["id"]))
            return {"status": "ok", "account": {"id": row["id"], "nickname": nickname, "created": False}, "name_result": result}

    def _rename(self, row, name: str, name_key: str, t: int) -> str:
        changed = row["nick_changed_at"]
        if changed is not None and t - changed < NICK_COOLDOWN_SEC:
            return "cooldown"
        if self.conn.execute("SELECT 1 FROM players WHERE nick_key = ? AND id <> ?", (name_key, row["id"])).fetchone():
            return "taken"
        self.conn.execute("UPDATE players SET nickname = ?, nick_key = ?, nick_changed_at = ? WHERE id = ?", (name, name_key, t, row["id"]))
        return "ok"

    def find_player(self, ident: str):
        with self._lock:
            return self.conn.execute("SELECT * FROM players WHERE id = ? OR nickname = ? COLLATE NOCASE", (ident, ident)).fetchone()

    def set_banned(self, ident: str, banned: bool) -> bool:
        with self._lock:
            row = self.find_player(ident)
            if row is None:
                return False
            self.conn.execute("UPDATE players SET banned = ? WHERE id = ?", (1 if banned else 0, row["id"]))
            return True

    # ---- 판 기록 -------------------------------------------------------------

    def record_match(self, m: dict) -> dict:
        """판 기록을 저장한다. 방침(#27): 판 기록은 계정과 함께 삭제되므로 **살아 있는 계정이 한 명도 없는 판은 저장하지 않는다**
        (전원 게스트이거나 참가 계정이 이미 삭제됨: 지워 줄 계정이 없어 영원히 남게 된다). 줄 단위로는 계정이 이미 삭제됐으면(대기열에서 늦게 도착한 기록)
        닉네임을 DELETED_NICKNAME으로 바꿔 익명으로 저장한다. 게스트 줄은 닉네임 그대로(판 기록이 지워질 때 같이 사라진다)."""
        with self._lock:
            if self.conn.execute("SELECT 1 FROM matches WHERE id = ?", (m["match_id"],)).fetchone():
                return {"status": "ok", "duplicate": True}
            rows = []
            for p in m["players"]:
                pid = p["account_id"] or None
                nickname = p["nickname"]
                if pid is not None and not self.conn.execute("SELECT 1 FROM players WHERE id = ?", (pid,)).fetchone():
                    pid, nickname = None, DELETED_NICKNAME
                rows.append((p, pid, nickname))
            if not any(pid is not None for _, pid, _ in rows):
                return {"status": "ok", "duplicate": False, "stored": False}
            self.conn.execute("BEGIN")
            try:
                self.conn.execute(
                    "INSERT INTO matches (id, started_at, ended_at, player_count, result, boss_level, duration_s, version) VALUES (?,?,?,?,?,?,?,?)",
                    (m["match_id"], m["started_at"], m["ended_at"], m["player_count"], m["result"], m["boss_level"], m["duration_s"], m["version"]))
                for p, pid, nickname in rows:
                    self.conn.execute(
                        "INSERT INTO match_players (match_id, lane, player_id, nickname, boss_damage, lane_damage, ghost_boss_damage, left_early) VALUES (?,?,?,?,?,?,?,?)",
                        (m["match_id"], p["lane"], pid, nickname, p["boss_damage"], p["lane_damage"], p["ghost_boss_damage"], 1 if p["left"] else 0))
                self.conn.execute("COMMIT")
            except Exception:
                self.conn.execute("ROLLBACK")
                raise
            return {"status": "ok", "duplicate": False, "stored": True}

    def leaderboard(self, period: str, limit: int) -> list:
        """방(팀) 기록 순위: 보스 도달 레벨 높은 순 -> 승리 먼저 -> 걸린 시간 짧은 순 -> 먼저 끝난 순."""
        with self._lock:
            where, args = "", []
            if period == "week":
                where, args = "WHERE ended_at >= ?", [self.clock() - WEEK_SEC]
            rows = self.conn.execute(
                f"SELECT * FROM matches {where} ORDER BY boss_level DESC, (result = 'win') DESC, duration_s ASC, ended_at ASC, id ASC LIMIT ?",
                args + [limit]).fetchall()
            out = []
            for i, r in enumerate(rows):
                players = self.conn.execute(
                    "SELECT nickname, boss_damage, lane_damage, left_early FROM match_players WHERE match_id = ? ORDER BY lane", (r["id"],)).fetchall()
                out.append({
                    "rank": i + 1, "match_id": r["id"], "boss_level": r["boss_level"], "result": r["result"],
                    "duration_s": r["duration_s"], "ended_at": r["ended_at"], "player_count": r["player_count"],
                    "players": [{"nickname": p["nickname"], "boss_damage": p["boss_damage"], "lane_damage": p["lane_damage"], "left": bool(p["left_early"])} for p in players],
                })
            return out

    # ---- 운영 ----------------------------------------------------------------

    def stats(self) -> dict:
        with self._lock:
            one = lambda sql: self.conn.execute(sql).fetchone()[0]
            return {"players": one("SELECT COUNT(*) FROM players"), "banned": one("SELECT COUNT(*) FROM players WHERE banned = 1"),
                    "matches": one("SELECT COUNT(*) FROM matches")}

    def backup(self, directory: str, keep: int) -> str:
        """SQLite 스냅샷(VACUUM INTO)을 directory에 남기고 오래된 것은 keep개만 남긴다. 쓰는 중에도 일관된 사본이다."""
        Path(directory).mkdir(parents=True, exist_ok=True)
        stamp = datetime.fromtimestamp(self.clock()).strftime("%Y%m%d-%H%M%S")
        target = Path(directory) / f"accounts-{stamp}.db"
        n = 1
        while target.exists():
            target = Path(directory) / f"accounts-{stamp}-{n}.db"
            n += 1
        with self._lock:
            self.conn.execute("VACUUM INTO ?", (str(target),))
        old = sorted(Path(directory).glob("accounts-*.db"), key=lambda p: (p.stat().st_mtime, p.name))
        for p in old[:-keep] if keep > 0 else []:
            p.unlink()
        return str(target)

    # ---- 삭제 (#66) ----------------------------------------------------------

    def describe_player(self, ident: str):
        """삭제 요청 확인용 요약 (토큰 해시는 내보내지 않는다). 없으면 None."""
        with self._lock:
            row = self.find_player(ident)
            if row is None:
                return None
            matches = self.conn.execute("SELECT COUNT(DISTINCT match_id) FROM match_players WHERE player_id = ?", (row["id"],)).fetchone()[0]
            last = self.conn.execute(
                "SELECT MAX(m.ended_at) FROM matches m JOIN match_players mp ON mp.match_id = m.id WHERE mp.player_id = ?", (row["id"],)).fetchone()[0]
            doomed = len(self._orphaned_if_erased(row["id"]))
            return {"id": row["id"], "nickname": row["nickname"], "created_at": row["created_at"], "last_seen_at": row["last_seen_at"],
                    "banned": bool(row["banned"]), "matches": matches, "last_match_at": last,
                    "matches_deleted": doomed, "matches_anonymized": matches - doomed}

    def _orphaned_if_erased(self, pid: str) -> list:
        """이 계정이 지워지면 계정이 연결된 참가자가 한 명도 안 남아 통째로 지워질 판 ID들."""
        return [r[0] for r in self.conn.execute(
            "SELECT DISTINCT match_id FROM match_players WHERE player_id = ? AND match_id NOT IN "
            "(SELECT match_id FROM match_players WHERE player_id IS NOT NULL AND player_id <> ?)", (pid, pid)).fetchall()]

    def _erase_player(self, pid: str) -> dict:
        """계정 하나와 그 판 기록을 지운다 (호출하는 쪽이 트랜잭션을 잡는다).
        - 그 계정의 참가자 줄: 닉네임을 DELETED_NICKNAME으로 바꾸고 계정 연결을 끊는다 (판의 숫자는 누구 것인지 알 수 없게 남는다).
        - 계정이 연결된 참가자가 한 명도 안 남은 판은 통째로 삭제한다 (게스트 줄도 같이 사라진다)."""
        doomed = self._orphaned_if_erased(pid)
        touched = self.conn.execute("SELECT COUNT(DISTINCT match_id) FROM match_players WHERE player_id = ?", (pid,)).fetchone()[0]
        self.conn.execute("UPDATE match_players SET player_id = NULL, nickname = ? WHERE player_id = ?", (DELETED_NICKNAME, pid))
        self.conn.execute("DELETE FROM players WHERE id = ?", (pid,))
        for mid in doomed:
            self.conn.execute("DELETE FROM matches WHERE id = ?", (mid,))   # match_players는 ON DELETE CASCADE
        return {"matches_deleted": len(doomed), "matches_anonymized": touched - len(doomed)}

    def delete_account(self, ident: str):
        """삭제 요청 처리: 계정 ID 또는 닉네임으로 계정을 지운다. 없으면 None. (보관 기간 정리와 달리 운영자가 직접 요청을 처리하는 것이므로 차단 계정도 지울 수 있다.)"""
        with self._lock:
            row = self.find_player(ident)
            if row is None:
                return None
            self.conn.execute("BEGIN IMMEDIATE")
            try:
                res = self._erase_player(row["id"])
                self.conn.execute("COMMIT")
            except Exception:
                self.conn.execute("ROLLBACK")
                raise
            return {"id": row["id"], **res}

    def purge(self, inactive_days: int = ACCOUNT_RETENTION_DAYS) -> dict:
        """방침(#27)의 보관 기간 정리: 마지막 접속 후 inactive_days가 지난 계정을 그 판 기록과 함께 지운다 (_erase_player).
        **차단(banned) 계정은 지우지 않고 계속 보관한다** (소유자 결정 #66: 차단 기록을 남기려고. 방침 쪽 예외 문구는 #27에서 추가한다).
        별도 판 기록 보관 기간은 없다 (판 기록은 계정과 함께만 사라진다). 어느 계정과도 이어지지 않는 판(이전 버전이 남긴 전원 게스트/연결 끊긴 판)도 같이 지운다.
        inactive_days <= 0이면 계정 정리는 건너뛴다."""
        with self._lock:
            t = self.clock()
            out = {"players": 0, "matches_deleted": 0, "matches_anonymized": 0}
            self.conn.execute("BEGIN IMMEDIATE")
            try:
                if inactive_days > 0:
                    ids = [r[0] for r in self.conn.execute("SELECT id FROM players WHERE banned = 0 AND last_seen_at < ?", (t - inactive_days * 86400,)).fetchall()]
                    for pid in ids:
                        res = self._erase_player(pid)
                        out["players"] += 1
                        out["matches_deleted"] += res["matches_deleted"]
                        out["matches_anonymized"] += res["matches_anonymized"]
                cur = self.conn.execute("DELETE FROM matches WHERE id NOT IN (SELECT match_id FROM match_players WHERE player_id IS NOT NULL)")
                out["matches_deleted"] += cur.rowcount
                self.conn.execute("COMMIT")
            except Exception:
                self.conn.execute("ROLLBACK")
                raise
            return out


LOG_SUFFIXES = (".log", ".log.out", ".log.err")   # run-server/run-accounts.ps1이 프로세스가 끝날 때 .out/.err를 날짜 .log에 합친다. 강제 종료로 못 합친 조각도 같은 보관 기간을 따른다


def purge_logs(log_dir, days: int, at=None) -> int:
    """방침(#27): 서버 로그는 30일 후 삭제한다. log_dir의 로그 파일(*.log, 합치지 못한 *.log.out/.err) 중 마지막 수정이 days일 전보다 오래된 것을 지운다. 지운 개수.
    기준이 파일의 마지막 수정 시각이라, 오래 켜 둔 프로세스의 현재 출력 파일은 계속 쓰이는 동안 지워지지 않는다 (방침 문구도 '파일 단위, 마지막 기록 후 30일')."""
    if not log_dir or days <= 0:
        return 0
    d = Path(log_dir)
    if not d.is_dir():
        return 0
    cutoff = (time.time() if at is None else at) - days * 86400
    n = 0
    for f in d.iterdir():
        try:
            if f.name.endswith(LOG_SUFFIXES) and f.is_file() and f.stat().st_mtime < cutoff:
                f.unlink()
                n += 1
        except OSError as e:   # 쓰는 중이거나 권한 문제: 다음에 다시 시도한다
            print("로그 삭제 실패:", f.name, repr(e), file=sys.stderr, flush=True)
    return n


class Maintenance:
    """서비스 안에서 도는 정기 작업: 백업과 보관 기간 정리(#66). tick()을 주기적으로(기본 60초) 부르면 때가 된 일을 한다.
    첫 tick에 바로 한 번 하고(서비스가 꺼져 있던 동안 밀린 정리를 따라잡는다) 그 뒤 간격마다 한다."""

    def __init__(self, db, *, backup_dir=None, backup_keep=14, backup_hours=24.0, purge_hours=PURGE_INTERVAL_HOURS,
                 inactive_days=ACCOUNT_RETENTION_DAYS, log_dir=None, log_days=LOG_RETENTION_DAYS, mono=time.monotonic, out=None):
        self.db, self.backup_dir, self.backup_keep, self.backup_hours = db, backup_dir, backup_keep, backup_hours
        self.purge_hours, self.inactive_days, self.log_dir, self.log_days = purge_hours, inactive_days, log_dir, log_days
        self.mono = mono
        self.out = out or (lambda line: print(line, flush=True))
        self._last_backup = None
        self._last_purge = None

    def _due(self, last, hours) -> bool:
        return hours > 0 and (last is None or self.mono() - last >= hours * 3600)

    def tick(self) -> None:
        if self.backup_dir and self._due(self._last_backup, self.backup_hours):
            self._last_backup = self.mono()
            try:
                self.out("백업: " + self.db.backup(self.backup_dir, self.backup_keep))
            except Exception as e:
                print("백업 실패:", repr(e), file=sys.stderr, flush=True)
        if self._due(self._last_purge, self.purge_hours):
            self._last_purge = self.mono()
            self.run_retention()

    def run_retention(self) -> dict:
        """보관 기간 정리 한 번. 결과는 개수만 로그에 남긴다 (삭제한 계정의 ID/닉네임은 남기지 않는다)."""
        try:
            res = self.db.purge(self.inactive_days)
            res["logs"] = purge_logs(self.log_dir, self.log_days)
            self.out("보관 기간 정리: " + json.dumps(res))
            return res
        except Exception as e:
            print("보관 기간 정리 실패:", repr(e), file=sys.stderr, flush=True)
            return {}


# ---- 입력 검사 ------------------------------------------------------------------

class BadRequest(Exception):
    pass


def _num(v, lo, hi, what, integer=False):
    if isinstance(v, bool) or not isinstance(v, (int, float)) or v != v or v < lo or v > hi:
        raise BadRequest(what)
    return int(v) if integer else float(v)


def _text(v, max_len, what, allow_empty=False):
    if not isinstance(v, str) or len(v) > max_len or (not v and not allow_empty):
        raise BadRequest(what)
    return v


def parse_login(body: dict):
    token_hash = body.get("token_hash")
    if not isinstance(token_hash, str) or not HEX64.match(token_hash):
        raise BadRequest("token_hash")
    name = _text(body.get("name", ""), MAX_NICK_LEN, "name", allow_empty=True)
    name_key = _text(body.get("name_key", ""), MAX_NICK_LEN * 2, "name_key", allow_empty=True)
    if bool(name) != bool(name_key):
        raise BadRequest("name/name_key")
    return token_hash, name, name_key


def parse_match(body: dict) -> dict:
    match_id = body.get("match_id")
    if not isinstance(match_id, str) or not MATCH_ID_RE.match(match_id):
        raise BadRequest("match_id")
    result = body.get("result")
    if result not in ("win", "lose"):
        raise BadRequest("result")
    players_in = body.get("players")
    if not isinstance(players_in, list) or not 1 <= len(players_in) <= MAX_PLAYERS:
        raise BadRequest("players")
    players, lanes = [], set()
    big = 1e12
    for p in players_in:
        if not isinstance(p, dict):
            raise BadRequest("player")
        lane = _num(p.get("lane"), 0, MAX_PLAYERS - 1, "lane", integer=True)
        if lane in lanes:
            raise BadRequest("lane duplicate")
        lanes.add(lane)
        account_id = p.get("account_id", "")
        if account_id != "" and not (isinstance(account_id, str) and ID_RE.match(account_id)):
            raise BadRequest("account_id")
        players.append({
            "lane": lane, "account_id": account_id, "nickname": _text(p.get("nickname"), MAX_NICK_LEN, "nickname"),
            "boss_damage": _num(p.get("boss_damage"), 0, big, "boss_damage"), "lane_damage": _num(p.get("lane_damage"), 0, big, "lane_damage"),
            "ghost_boss_damage": _num(p.get("ghost_boss_damage"), 0, big, "ghost_boss_damage"), "left": bool(p.get("left", False)),
        })
    return {
        "match_id": match_id, "result": result, "players": players,
        "started_at": _num(body.get("started_at"), 0, 4e9, "started_at", integer=True), "ended_at": _num(body.get("ended_at"), 0, 4e9, "ended_at", integer=True),
        "player_count": _num(body.get("player_count"), 1, MAX_PLAYERS, "player_count", integer=True),
        "boss_level": _num(body.get("boss_level"), 1, 1000, "boss_level", integer=True),
        "duration_s": _num(body.get("duration_s"), 0, 1e7, "duration_s"), "version": _text(body.get("version", ""), 32, "version", allow_empty=True) or "?",
    }


# ---- HTTP -----------------------------------------------------------------------

def make_handler(db: Db, api_key: str):
    class Handler(BaseHTTPRequestHandler):
        server_version = "LaneWarsAccounts"
        protocol_version = "HTTP/1.1"

        def log_message(self, fmt, *args):  # 요청 로그는 표준 출력에 한 줄 (닉네임/토큰은 남기지 않는다)
            sys.stdout.write("%s %s\n" % (self.log_date_time_string(), fmt % args))
            sys.stdout.flush()

        def _send(self, code: int, payload: dict) -> None:
            data = json.dumps(payload, ensure_ascii=False).encode("utf-8")
            self.send_response(code)
            self.send_header("Content-Type", "application/json; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def _authorized(self) -> bool:
            return hmac.compare_digest(self.headers.get("X-Api-Key", "").encode("utf-8"), api_key.encode("utf-8"))

        def _body(self) -> dict:
            n = int(self.headers.get("Content-Length", "0") or 0)
            if n <= 0 or n > MAX_BODY:
                raise BadRequest("body size")
            try:
                body = json.loads(self.rfile.read(n).decode("utf-8"))
            except (ValueError, UnicodeDecodeError):
                raise BadRequest("json")
            if not isinstance(body, dict):
                raise BadRequest("json object")
            return body

        def _route(self, method: str) -> None:
            url = urlparse(self.path)
            if not self._authorized():
                self._send(401, {"status": "unauthorized"})
                return
            try:
                if method == "GET" and url.path == "/v1/health":
                    self._send(200, {"status": "ok", "schema": SCHEMA_VERSION})
                elif method == "GET" and url.path == "/v1/leaderboard":
                    q = parse_qs(url.query)
                    period = q.get("period", ["all"])[0]
                    if period not in ("all", "week"):
                        raise BadRequest("period")
                    limit = int(q.get("limit", ["10"])[0])
                    self._send(200, {"status": "ok", "period": period, "rows": db.leaderboard(period, max(1, min(limit, 50)))})
                elif method == "POST" and url.path == "/v1/login":
                    token_hash, name, name_key = parse_login(self._body())
                    self._send(200, db.login(token_hash, name, name_key))
                elif method == "POST" and url.path == "/v1/matches":
                    self._send(200, db.record_match(parse_match(self._body())))
                else:
                    self._send(404, {"status": "not_found"})
            except (BadRequest, ValueError) as e:
                self._send(400, {"status": "bad_request", "reason": str(e)})
            except Exception as e:  # 서비스가 죽지 않게: 이유만 알리고 계속
                sys.stderr.write("오류: %r\n" % (e,))
                self._send(500, {"status": "error"})

        def do_GET(self):
            self._route("GET")

        def do_POST(self):
            self._route("POST")

    return Handler


def serve(args) -> int:
    key = os.environ.get("LANEWARS_ACCOUNTS_KEY", "")
    if len(key) < 16:
        print("환경 변수 LANEWARS_ACCOUNTS_KEY(16자 이상)가 필요하다", file=sys.stderr)
        return 2
    db = Db(args.db, new_accounts_per_min=args.new_accounts_per_min)
    server = ThreadingHTTPServer((args.host, args.port), make_handler(db, key))
    server.daemon_threads = True
    stop = threading.Event()

    maint = Maintenance(db, backup_dir=args.backup_dir, backup_keep=args.backup_keep, backup_hours=args.backup_interval_hours,
                        purge_hours=args.purge_interval_hours, inactive_days=args.inactive_days, log_dir=args.log_dir, log_days=args.log_days)

    def maintenance() -> None:
        while True:
            maint.tick()
            if stop.wait(args.tick_sec):
                return

    threading.Thread(target=maintenance, daemon=True).start()
    print(f"계정 서비스 열림: http://{args.host}:{args.port} (DB {args.db}, 백업 {args.backup_dir} 매 {args.backup_interval_hours}시간 {args.backup_keep}개, 보관 기간 정리 매 {args.purge_interval_hours}시간: 계정 {args.inactive_days}일, 로그 {args.log_dir or '안 함'} {args.log_days}일)", flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        stop.set()
        server.server_close()
        db.close()
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description="Lane Wars 계정/판 기록 서비스")
    ap.add_argument("--db", default="data/accounts.db")
    sub = ap.add_subparsers(dest="cmd")
    s = sub.add_parser("serve")
    s.add_argument("--host", default="127.0.0.1")
    s.add_argument("--port", type=int, default=47310)
    s.add_argument("--new-accounts-per-min", type=int, default=NEW_ACCOUNTS_PER_MIN)
    s.add_argument("--backup-dir", default=None)
    s.add_argument("--backup-keep", type=int, default=14)
    s.add_argument("--backup-interval-hours", type=float, default=24.0)
    s.add_argument("--tick-sec", type=float, default=60.0, help="정기 작업(백업/정리)이 때가 됐는지 보는 간격 (시험용으로 줄일 수 있다)")
    s.add_argument("--purge-interval-hours", type=float, default=PURGE_INTERVAL_HOURS, help="보관 기간 정리 간격 (0이면 자동 정리 끔)")
    s.add_argument("--inactive-days", type=int, default=ACCOUNT_RETENTION_DAYS)
    s.add_argument("--log-dir", default=None, help="이 폴더의 *.log를 --log-days 지나면 지운다 (없으면 로그는 안 건드린다)")
    s.add_argument("--log-days", type=int, default=LOG_RETENTION_DAYS)
    for name in ("ban", "unban"):
        b = sub.add_parser(name)
        b.add_argument("who", help="계정 ID 또는 닉네임")
    bk = sub.add_parser("backup")
    bk.add_argument("--backup-dir", default=None)
    bk.add_argument("--backup-keep", type=int, default=14)
    pg = sub.add_parser("purge")
    pg.add_argument("--inactive-days", type=int, default=ACCOUNT_RETENTION_DAYS)
    pg.add_argument("--log-dir", default=None)
    pg.add_argument("--log-days", type=int, default=LOG_RETENTION_DAYS)
    sh = sub.add_parser("show", help="삭제 요청 확인용: 계정 요약")
    sh.add_argument("who", help="계정 ID 또는 닉네임")
    da = sub.add_parser("delete-account", help="삭제 요청 처리: 계정과 판 기록 삭제")
    da.add_argument("who", help="계정 ID 또는 닉네임")
    da.add_argument("--yes", action="store_true", help="이게 없으면 지우지 않고 미리보기만 한다")
    sub.add_parser("stats")
    args = ap.parse_args(argv)
    cmd = args.cmd or "serve"
    if cmd == "serve" and args.cmd is None:
        args = ap.parse_args(["--db", args.db, "serve"])
    if getattr(args, "backup_dir", None) is None and cmd in ("serve", "backup"):
        args.backup_dir = str(Path(args.db).parent / "backups")
    if cmd == "serve":
        for stream in (sys.stdout, sys.stderr):   # 로그를 파일로 돌릴 때(run-accounts.ps1은 UTF-8로 읽는다) 한글이 깨지지 않게
            if hasattr(stream, "reconfigure"):
                stream.reconfigure(encoding="utf-8")
        return serve(args)
    db = Db(args.db)
    try:
        if cmd in ("ban", "unban"):
            ok = db.set_banned(args.who, cmd == "ban")
            print(("차단함" if cmd == "ban" else "차단 풀었음") if ok else "그런 계정이 없다", args.who if ok else "")
            return 0 if ok else 1
        if cmd == "backup":
            print(db.backup(args.backup_dir, args.backup_keep))
        elif cmd == "purge":
            res = db.purge(args.inactive_days)
            res["logs"] = purge_logs(args.log_dir, args.log_days)
            print(json.dumps(res))
        elif cmd == "show":
            info = db.describe_player(args.who)
            if info is None:
                print("그런 계정이 없다", args.who)
                return 1
            print(json.dumps(_readable(info), ensure_ascii=False, indent=2))
        elif cmd == "delete-account":
            info = db.describe_player(args.who)
            if info is None:
                print("그런 계정이 없다", args.who)
                return 1
            if not args.yes:
                print(json.dumps(_readable(info), ensure_ascii=False, indent=2))
                print(f"미리보기: 계정 {info['id']}을 지우면 판 기록 {info['matches_deleted']}개가 삭제되고 {info['matches_anonymized']}개는 이 사람의 줄만 익명이 된다. 지우려면 --yes를 붙여 다시 실행한다.")
                return 2
            res = db.delete_account(info["id"])
            print(json.dumps(res, ensure_ascii=False))
        elif cmd == "stats":
            print(json.dumps(db.stats()))
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
