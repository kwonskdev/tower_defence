class_name MemoryAccountStore
extends AccountStore
## 메모리에만 저장하는 계정 저장소 (#25). 테스트와, 계정 서비스 없이 서버를 돌릴 때(개발) 쓴다. 규칙은 계정 서비스(tools/accounts)와 같다
## (tests/test_accounts.gd가 같은 시나리오를 둘 다에 돌려 맞는지 확인한다). 프로세스가 끝나면 사라진다.

const NICK_COOLDOWN_SEC := 7 * 24 * 3600
const NEW_ACCOUNTS_PER_MIN := 30
const WEEK_SEC := 7 * 24 * 3600

var clock := Callable()                 # () -> 지금(unix 초). 테스트가 시간을 조작한다
var new_accounts_per_min := NEW_ACCOUNTS_PER_MIN
var fail := false                       # 테스트: true면 DB가 죽은 것처럼 {status:"error"}
var calls := 0                          # 부른 횟수 (테스트용)
var players := {}                       # 토큰 해시 -> {id, nickname, key, nick_changed_at, banned, last_seen}
var matches := {}                       # match_id -> 기록
var _creates: Array = []


func _now() -> int:
	return int(clock.call()) if clock.is_valid() else int(Time.get_unix_time_from_system())


func login(token_hash: String, player_name: String, name_key: String) -> Dictionary:
	calls += 1
	if fail:
		return {"status": "error"}
	var t := _now()
	if not players.has(token_hash):
		if player_name == "" or name_key == "":
			return {"status": "error", "reason": "name_required"}
		_creates = _creates.filter(func(x): return t - x < 60)
		if _creates.size() >= new_accounts_per_min:
			return {"status": "rate_limited"}
		if _key_owner(name_key, "") != "":
			return {"status": "nick_taken"}
		var id := Crypto.new().generate_random_bytes(8).hex_encode()
		players[token_hash] = {"id": id, "nickname": player_name, "key": name_key, "nick_changed_at": -1, "banned": false, "last_seen": t}
		_creates.append(t)
		return {"status": "ok", "account": {"id": id, "nickname": player_name, "created": true}, "name_result": "ok"}
	var p: Dictionary = players[token_hash]
	if p.banned:
		return {"status": "banned", "account": {"id": p.id, "nickname": p.nickname, "created": false}}
	var result := "same"
	if player_name != "" and name_key != "" and name_key != p.key:
		if p.nick_changed_at >= 0 and t - p.nick_changed_at < NICK_COOLDOWN_SEC:
			result = "cooldown"
		elif _key_owner(name_key, p.id) != "":
			result = "taken"
		else:
			p.nickname = player_name
			p.key = name_key
			p.nick_changed_at = t
			result = "ok"
	p.last_seen = t
	return {"status": "ok", "account": {"id": p.id, "nickname": p.nickname, "created": false}, "name_result": result}


func _key_owner(name_key: String, except_id: String) -> String:
	for p in players.values():
		if p.key == name_key and p.id != except_id:
			return p.id
	return ""


func set_banned(account_id: String, banned: bool) -> bool:
	for p in players.values():
		if p.id == account_id:
			p.banned = banned
			return true
	return false


func record_match(record: Dictionary) -> Dictionary:
	calls += 1
	if fail:
		return {"status": "error"}
	var id := str(record.get("match_id", ""))
	if id == "" or record.get("players", []).is_empty():
		return {"status": "bad_request"}
	if matches.has(id):
		return {"status": "ok", "duplicate": true}
	# 계정 서비스와 같은 규칙 (#66): 살아 있는 계정이 한 명도 없는 판(전원 게스트)은 계정과 함께 지워 줄 수 없으니 저장하지 않는다
	var live := false
	for p in record.get("players", []):
		if str(p.get("account_id", "")) != "" and _has_account(str(p.account_id)):
			live = true
	if not live:
		return {"status": "ok", "duplicate": false, "stored": false}
	matches[id] = record.duplicate(true)
	return {"status": "ok", "duplicate": false, "stored": true}


func _has_account(account_id: String) -> bool:
	for p in players.values():
		if p.id == account_id:
			return true
	return false


func leaderboard(period: String, limit: int) -> Dictionary:
	calls += 1
	if fail:
		return {"status": "error", "rows": []}
	var t := _now()
	var list: Array = []
	for m in matches.values():
		if period == "week" and int(m.ended_at) < t - WEEK_SEC:
			continue
		list.append(m)
	list.sort_custom(func(a, b):
		if int(a.boss_level) != int(b.boss_level):
			return int(a.boss_level) > int(b.boss_level)
		if (a.result == "win") != (b.result == "win"):
			return a.result == "win"
		if not is_equal_approx(float(a.duration_s), float(b.duration_s)):
			return float(a.duration_s) < float(b.duration_s)
		if int(a.ended_at) != int(b.ended_at):
			return int(a.ended_at) < int(b.ended_at)
		return str(a.match_id) < str(b.match_id))
	var rows: Array = []
	for i in range(mini(limit, list.size())):
		var m: Dictionary = list[i]
		var ps: Array = []
		var sorted_players: Array = m.players.duplicate()
		sorted_players.sort_custom(func(a, b): return int(a.lane) < int(b.lane))
		for p in sorted_players:
			ps.append({"nickname": p.nickname, "boss_damage": p.boss_damage, "lane_damage": p.lane_damage, "left": bool(p.left)})
		rows.append({"rank": i + 1, "match_id": m.match_id, "boss_level": m.boss_level, "result": m.result, "duration_s": m.duration_s,
			"ended_at": m.ended_at, "player_count": m.player_count, "players": ps})
	return {"status": "ok", "rows": rows}
