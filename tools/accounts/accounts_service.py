#!/usr/bin/env python3
"""Lane Wars 계정/판 기록 서비스 (#25).

Godot 서버(방 서버)가 직접 DB에 붙지 않고 이 작은 HTTP 서비스를 거친다 (결정 근거: docs/accounts-and-db.md).
  - Python 표준 라이브러리만 쓴다 (설치할 것 없음). 저장소는 SQLite 파일 하나(WAL).
  - 127.0.0.1에만 연다. 모든 요청은 X-Api-Key 헤더(환경 변수 LANEWARS_ACCOUNTS_KEY)가 맞아야 한다.
  - 나중에 서버를 나누면 이 파일 뒤의 저장소(아래 Db 클래스)만 Postgres로 바꾸면 된다. Godot 쪽은 AccountStore 한 곳만 이 서비스를 안다.

실행:
  LANEWARS_ACCOUNTS_KEY=비밀 python tools/accounts/accounts_service.py --db data/accounts.db serve --port 47310   (--db는 항상 서브명령 앞)
관리 (서비스를 끄지 않고 쓸 수 있다):
  python tools/accounts/accounts_service.py --db data/accounts.db ban <계정ID 또는 닉네임> / unban <...> / backup / purge --inactive-days 180 --match-days 365 / stats

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
        with self._lock:
            if self.conn.execute("SELECT 1 FROM matches WHERE id = ?", (m["match_id"],)).fetchone():
                return {"status": "ok", "duplicate": True}
            self.conn.execute("BEGIN")
            try:
                self.conn.execute(
                    "INSERT INTO matches (id, started_at, ended_at, player_count, result, boss_level, duration_s, version) VALUES (?,?,?,?,?,?,?,?)",
                    (m["match_id"], m["started_at"], m["ended_at"], m["player_count"], m["result"], m["boss_level"], m["duration_s"], m["version"]))
                for p in m["players"]:
                    pid = p["account_id"] or None
                    if pid is not None and not self.conn.execute("SELECT 1 FROM players WHERE id = ?", (pid,)).fetchone():
                        pid = None  # 지워진 계정: 기록만 남긴다
                    self.conn.execute(
                        "INSERT INTO match_players (match_id, lane, player_id, nickname, boss_damage, lane_damage, ghost_boss_damage, left_early) VALUES (?,?,?,?,?,?,?,?)",
                        (m["match_id"], p["lane"], pid, p["nickname"], p["boss_damage"], p["lane_damage"], p["ghost_boss_damage"], 1 if p["left"] else 0))
                self.conn.execute("COMMIT")
            except Exception:
                self.conn.execute("ROLLBACK")
                raise
            return {"status": "ok", "duplicate": False}

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

    def purge(self, inactive_days: int, match_days: int) -> dict:
        """보관 기간(초안)을 넘긴 것을 지운다. 오래 안 들어온 계정(차단 계정 제외)과 오래된 판 기록.
        지워진 계정이 낀 판 기록은 남기되 계정 연결(player_id)만 끊는다 (닉네임 글자는 기록에 남는다: 판 기록을 지울 때 같이 사라진다)."""
        with self._lock:
            t = self.clock()
            out = {"players": 0, "matches": 0}
            if inactive_days > 0:
                cur = self.conn.execute("DELETE FROM players WHERE banned = 0 AND last_seen_at < ?", (t - inactive_days * 86400,))
                out["players"] = cur.rowcount
                self.conn.execute("UPDATE match_players SET player_id = NULL WHERE player_id IS NOT NULL AND player_id NOT IN (SELECT id FROM players)")
            if match_days > 0:
                cur = self.conn.execute("DELETE FROM matches WHERE ended_at < ?", (t - match_days * 86400,))
                out["matches"] = cur.rowcount
            return out


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

    def maintenance() -> None:
        last = 0.0
        while not stop.wait(60):
            if time.time() - last >= args.backup_interval_hours * 3600 and args.backup_interval_hours > 0:
                last = time.time()
                try:
                    print("백업:", db.backup(args.backup_dir, args.backup_keep), flush=True)
                except Exception as e:
                    print("백업 실패:", repr(e), file=sys.stderr, flush=True)

    threading.Thread(target=maintenance, daemon=True).start()
    print(f"계정 서비스 열림: http://{args.host}:{args.port} (DB {args.db}, 백업 {args.backup_dir} 매 {args.backup_interval_hours}시간 {args.backup_keep}개)", flush=True)
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
    for name in ("ban", "unban"):
        b = sub.add_parser(name)
        b.add_argument("who", help="계정 ID 또는 닉네임")
    bk = sub.add_parser("backup")
    bk.add_argument("--backup-dir", default=None)
    bk.add_argument("--backup-keep", type=int, default=14)
    pg = sub.add_parser("purge")
    pg.add_argument("--inactive-days", type=int, default=0)
    pg.add_argument("--match-days", type=int, default=0)
    sub.add_parser("stats")
    args = ap.parse_args(argv)
    cmd = args.cmd or "serve"
    if cmd == "serve" and args.cmd is None:
        args = ap.parse_args(["--db", args.db, "serve"])
    if getattr(args, "backup_dir", None) is None and cmd in ("serve", "backup"):
        args.backup_dir = str(Path(args.db).parent / "backups")
    if cmd == "serve":
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
            print(json.dumps(db.purge(args.inactive_days, args.match_days)))
        elif cmd == "stats":
            print(json.dumps(db.stats()))
        return 0
    finally:
        db.close()


if __name__ == "__main__":
    sys.exit(main())
