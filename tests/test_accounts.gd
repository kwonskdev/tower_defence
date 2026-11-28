extends "res://tests/case_base.gd"
## 이슈 #25: 익명 계정, 판 기록, 순위 (단계 1~2). 방 코드 서버(RoomHub)에 Accounts를 붙이고 실제 소켓 클라이언트로 확인한다. 체크리스트와 대응:
##  [0] 기기 토큰: 첫 실행에 만들어 저장하고 다음에도 같은 토큰 / 메인 메뉴가 그 토큰으로 접속한다
##  [1] 첫 접속에서 계정이 만들어지고 같은 토큰으로 다시 오면 같은 계정 / 토큰은 평문으로 저장되지 않는다(해시) / 모양이 틀린 토큰은 게스트 / 차단 계정은 거부
##  [2] 닉네임: 금칙어(우회 포함) / 서버 전체 중복(대소문자, 공백) / 변경(중복 거부, 7일에 한 번, 가입 직후 첫 변경은 바로)
##  [3] 판이 끝나면 서버가 기록을 저장한다: 값은 서버 상태에서만 (클라이언트가 보낸 점수/결과 메시지는 무시), 이탈한 사람, 패배/승리, 게스트
##  [4] DB가 죽어도 진행 중인 판은 영향받지 않고(재접속 포함) 기록 저장만 재시도한다 / 서버를 다시 켜도 대기열이 이어진다 / 서비스 주소가 죽어 있어도 접속이 빨리 처리된다
##  [5] 순위(리더보드): hello mode board로 조회, 기록과 정확히 일치, 주간/전체, 방에 들어가지 않는다 / 저장소가 죽으면 unavailable
##  [8] 계정 삭제(#66): 삭제 요청 명령(CLI)이 실제 서비스의 계정과 판 기록을 지운다 / 순위 조회(방 서버 board)에 삭제된 닉네임이 안 나온다 / 다인원 판에서는 그 사람 줄만 익명 / 삭제된 계정의 늦은 기록도 익명 / 계정 없는 판은 저장 안 함
##  [6] 실제 계정 서비스(Python+SQLite)와 메모리 저장소가 같은 규칙인지(계약 시험) / 서비스를 껐다 켜도 계정·기록이 남아 있다 / 백업 사본으로 복원
## (실서버/Cloudflare/실기기는 보지 않는다. Python 서비스 자체의 시험은 tools/accounts/test_accounts_service.py)

const PORT := 47700
const SERVICE_PORT := 47790
const KEY := "test-key-0123456789abcdef"
const SPOOL := "user://test_match_spool.jsonl"

var _fake_now := 1_700_000_000   # 메모리 저장소 시계 (unix 초)
var _py := ""


func run() -> void:
	_identity_token()
	_nickname_rules()
	await _basic_accounts()
	await _nickname_flow()
	await _match_record()
	await _db_down()
	await _http_dead()
	await _leaderboard()
	await _real_service()
	await _account_deletion()
	await _main_menu_token()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SPOOL))
	Engine.time_scale = 1.0


# ---- 도우미 -----------------------------------------------------------------------

func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


## 방 코드 서버 + 메모리 계정 저장소 (시계는 _fake_now)
func _server(port: int, store: AccountStore = null) -> Dictionary:
	DirAccess.remove_absolute(ProjectSettings.globalize_path(SPOOL))
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	var s: AccountStore = store
	if s == null:
		var m := MemoryAccountStore.new()
		m.clock = func(): return _fake_now
		s = m
	var acc := Accounts.new()
	acc.spool_path = SPOOL
	acc.retry_min_sec = 0.3
	acc.retry_max_sec = 0.6
	server.add_child(acc)
	acc.set_store(s)
	server.hub.accounts = acc
	return {"server": server, "hub": server.hub, "acc": acc, "store": s}


func _client(player_name: String, port: int, mode: String, code := "", token := "") -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	cl.join_mode = mode
	cl.join_code = code
	cl.token = token if token != "" else Identity.new_token()
	cl.ping_interval = 0.3
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
	return cl


func _settle(cl: NetClient) -> void:
	await wait_until(func(): return cl.is_joined() or cl.state == NetClient.State.REJECTED, 8000)


func _free(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await frames(4)


func _own_lane(cl: NetClient) -> bool:
	return cl.snapshot.get("lanes", {}).has(str(cl.player_id))


## 판 시작까지: 첫 토큰이 방장. {room, clients}
func _game(g: Dictionary, port: int, names: Array, tokens: Array) -> Dictionary:
	var clients: Array = []
	var host := _client(names[0], port, NetProtocol.MODE_CREATE, "", tokens[0])
	await _settle(host)
	clients.append(host)
	for i in range(1, names.size()):
		var c := _client(names[i], port, NetProtocol.MODE_JOIN, host.room_code, tokens[i])
		await _settle(c)
		c.set_ready(true)
		clients.append(c)
	await wait_until(func(): return host.lobby.get("members", []).size() == names.size() and host.lobby.get("can_start", false), 8000)  # 모두 들어와 준비한 상태(혼자일 때의 can_start와 헷갈리지 않게 인원도 본다)
	host.request_start()
	await wait_until(func(): return clients.all(func(x): return x.in_game and _own_lane(x)), 8000)
	return {"room": g.hub._rooms[host.room_code], "clients": clients}


func _victory(room: NetServer) -> void:
	room.field.boss._finish(BossController.State.VICTORY, "test")
	await frames(2)


func _defeat(room: NetServer) -> void:
	room.field.boss._finish(BossController.State.DEFEAT, "test")
	await frames(2)


func _hash_ok(token: String, store: MemoryAccountStore) -> bool:
	return store.players.has(Identity.hash_of(token))


# ---- [0] 기기 토큰 ----------------------------------------------------------------

func _identity_token() -> void:
	print("[0] 기기 계정 토큰: 첫 실행에 만들어 저장, 다음에도 같은 토큰")
	DirAccess.remove_absolute(ProjectSettings.globalize_path(Identity.account_path))
	var t1 := Identity.account_token()
	check(Identity.valid_token(t1), "첫 실행에 128비트 토큰(16진수 32글자)을 만든다")
	var t2 := Identity.account_token()
	check(t2 == t1 and FileAccess.file_exists(Identity.account_path), "다음 실행에도 같은 토큰이고 기기에 저장되어 있다")
	var cfg := ConfigFile.new()
	cfg.set_value("account", "token", "zz-not-a-token")
	cfg.save(Identity.account_path)
	var t3 := Identity.account_token()
	check(Identity.valid_token(t3) and t3 != "zz-not-a-token", "저장된 값이 망가졌으면 새 토큰을 만든다")
	check(NetProtocol.make_hello("a", NetProtocol.MODE_BOARD, "", t3, "week")["period"] == "week" and not NetProtocol.make_hello("a").has("period"), "hello에 period는 board 조회에만 실린다")
	check(NetProtocol.PROTOCOL_VERSION == 5, "프로토콜 버전 5 (계정)")


# ---- [2] 닉네임 규칙 (단위) ----------------------------------------------------------

func _nickname_rules() -> void:
	print("[2a] 닉네임: 금칙어와 중복 비교 키")
	for bad in ["씨발", "시 발", "시.발", "너시발너", "FUCK", "f u c k", "s.h.i.t", "운영자", "운영 자", "GM", "Admin", "LaneWars", "나는관리자"]:
		check(not Nicknames.is_clean(bad), "금칙어: '%s'" % bad)
	for ok in ["아름다운사과", "김철수", "gmail", "새끼손가락", "Kim", "철수2", "ㅋㅋ", "Player 1"]:
		check(Nicknames.is_clean(ok), "정상 이름: '%s'" % ok)
	check(Nicknames.key("Kim") == Nicknames.key("kim") and Nicknames.key("철 수") == Nicknames.key("철수") and Nicknames.key("철수") != Nicknames.key("철수2"), "중복 비교 키는 대소문자와 공백을 무시한다")
	check(Nicknames.sanitize("a".repeat(40)).length() == Balance.NICKNAME_MAX_LENGTH, "길이 제한은 기존 값(%d)이다" % Balance.NICKNAME_MAX_LENGTH)


# ---- [1] 계정 만들기/인증 ----------------------------------------------------------

func _basic_accounts() -> void:
	print("[1] 첫 접속에서 계정이 만들어지고, 같은 토큰으로 다시 오면 같은 계정")
	var g := await _server(PORT)
	var store: MemoryAccountStore = g.store
	var ta := Identity.new_token()
	var a := _client("철수", PORT, NetProtocol.MODE_CREATE, "", ta)
	await _settle(a)
	check(a.is_joined() and a.my_name == "철수" and not a.is_guest and store.players.size() == 1, "첫 접속: 계정이 하나 만들어졌고 닉네임은 철수")
	check(_hash_ok(ta, store) and not store.players.has(ta), "서버는 토큰 원문이 아니라 해시(SHA-256)로 계정을 찾는다")
	var dump := JSON.stringify(store.players)
	check(not dump.contains(ta), "저장소 내용 어디에도 토큰 원문이 없다")
	var id_a: String = store.players[Identity.hash_of(ta)].id
	check(id_a.length() == 16 and id_a.is_valid_hex_number(false) and not id_a.contains(ta.substr(0, 8)), "계정 ID는 서버가 무작위로 만든 16자리다 (토큰과 무관)")
	var code := a.room_code
	a.leave()
	await wait_seconds(0.3)
	var a2 := _client("딴이름", PORT, NetProtocol.MODE_CREATE, "", ta)  # 같은 기기, 다른 닉네임을 쳐도
	await _settle(a2)
	check(a2.is_joined() and store.players.size() == 1 and store.players[Identity.hash_of(ta)].id == id_a, "같은 토큰: 같은 계정이다 (새로 안 만들어졌다)")
	check(a2.my_name == "딴이름" and a2.name_result == "ok" and store.players[Identity.hash_of(ta)].nickname == "딴이름", "같은 계정이 다른 이름을 보내면 닉네임 변경이다 (가입 뒤 첫 변경은 바로 된다)")
	var tb := Identity.new_token()
	var b := _client("영희", PORT, NetProtocol.MODE_JOIN, a2.room_code, tb)
	await _settle(b)
	check(b.is_joined() and store.players.size() == 2 and store.players[Identity.hash_of(tb)].id != id_a, "다른 토큰은 다른 계정")
	# 모양이 틀린 토큰은 게스트
	var g1 := _client("손님", PORT, NetProtocol.MODE_JOIN, a2.room_code, "zz-not-hex")
	await _settle(g1)
	check(g1.is_joined() and g1.is_guest and store.players.size() == 2 and g1.my_name == "손님", "모양이 틀린 토큰은 계정 없이(게스트) 입장하고 계정이 생기지 않는다")
	# 차단
	store.set_banned(store.players[Identity.hash_of(tb)].id, true)
	var b2 := _client("영희", PORT, NetProtocol.MODE_JOIN, a2.room_code, tb)
	await _settle(b2)
	check(b2.state == NetClient.State.REJECTED and b2.reject_reason == NetProtocol.REJECT_BANNED, "차단된 계정은 account_banned로 거부된다")
	check(MainMenu.reject_text(NetProtocol.REJECT_BANNED) != "" and not MainMenu.reject_text(NetProtocol.REJECT_BANNED).contains("account_banned"), "거부 문구가 있다")
	# 신규 계정 한도
	var players_before: int = store.players.size()
	(store as MemoryAccountStore).new_accounts_per_min = players_before
	var flood := _client("폭주", PORT, NetProtocol.MODE_JOIN, a2.room_code, Identity.new_token())
	await _settle(flood)
	check(flood.is_joined() and flood.is_guest and flood.name_result == "unavailable" and store.players.size() == players_before, "분당 신규 계정 한도를 넘으면 계정을 안 만들고 임시(게스트)로 입장시킨다 (정상 신규 플레이어를 쫓아내지 않는다)")
	var a3 := _client("딴이름", PORT, NetProtocol.MODE_JOIN, a2.room_code, ta)
	await _settle(a3)
	check(a3.is_joined(), "이미 있는 계정은 신규 한도에 걸리지 않는다")
	await _free([a, a2, b, b2, g1, flood, a3, g.server])


# ---- [2] 닉네임 흐름 ---------------------------------------------------------------

func _nickname_flow() -> void:
	print("[2b] 닉네임: 서버 전체 중복, 금칙어, 변경 규칙")
	var g := await _server(PORT + 1)
	var acc: Accounts = g.acc
	var store: MemoryAccountStore = g.store
	var t1 := Identity.new_token()
	var t2 := Identity.new_token()
	var t3 := Identity.new_token()
	var r1: Dictionary = await acc.login(t1, "철수")
	check(r1.ok and r1.nickname == "철수" and not r1.guest, "첫 계정 닉네임 철수")
	var r2: Dictionary = await acc.login(t2, "철수")
	check(r2.ok and r2.nickname == "철수2", "다른 사람이 같은 이름을 원하면 서버 전체에서 겹치지 않게 숫자가 붙는다 (%s)" % r2.nickname)
	var r2b: Dictionary = await acc.login(Identity.new_token(), "철수")
	check(r2b.nickname == "철수3", "세 번째는 철수3 (%s)" % r2b.nickname)
	var rk: Dictionary = await acc.login(Identity.new_token(), "KIM")
	var rk2: Dictionary = await acc.login(Identity.new_token(), "kim")
	check(rk.nickname == "KIM" and rk2.nickname == "kim2", "대소문자만 다른 이름도 겹친 것이다 (%s, %s)" % [rk.nickname, rk2.nickname])
	var rs: Dictionary = await acc.login(Identity.new_token(), "철 수")
	check(rs.ok and rs.nickname == "철 수4", "공백만 다른 이름도 겹친 것이다: 철수/철수2/철수3이 이미 있어 철 수4 (%s)" % rs.nickname)
	var long_name := "가".repeat(Balance.NICKNAME_MAX_LENGTH)
	var l1: Dictionary = await acc.login(Identity.new_token(), long_name)
	var l2: Dictionary = await acc.login(Identity.new_token(), long_name)
	check(l1.nickname == long_name and l2.nickname.length() <= Balance.NICKNAME_MAX_LENGTH and l2.nickname != long_name, "최대 길이 이름이 겹쳐도 길이 제한 안에서 구별된다 (%s)" % l2.nickname)
	# 금칙어
	var bw: Dictionary = await acc.login(Identity.new_token(), "시 발")
	check(bw.ok and Nicknames.is_clean(bw.nickname) and bw.name_result == "banned_word", "금칙어 이름으로는 계정이 안 만들어지고 자동 이름이 붙는다 (%s)" % bw.nickname)
	# 변경 규칙
	var again: Dictionary = await acc.login(t1, "")
	check(again.nickname == "철수" and again.account_id == r1.account_id, "이름을 안 보내면 그대로")
	var ren: Dictionary = await acc.login(t1, "민수")
	check(ren.nickname == "민수" and ren.name_result == "ok", "가입 직후 첫 변경은 바로 된다")
	var taken: Dictionary = await acc.login(t2, "민수")
	check(taken.nickname == "철수2" and taken.name_result == "taken", "남이 쓰는 이름으로는 못 바꾼다 (기존 이름 유지)")
	var cool: Dictionary = await acc.login(t1, "지수")
	check(cool.nickname == "민수" and cool.name_result == "cooldown", "7일 안에는 또 못 바꾼다")
	_fake_now += MemoryAccountStore.NICK_COOLDOWN_SEC + 1
	var after: Dictionary = await acc.login(t1, "지수")
	check(after.nickname == "지수" and after.name_result == "ok", "7일이 지나면 바꿀 수 있다")
	var banned_rename: Dictionary = await acc.login(t3, "씨발")
	check(Nicknames.is_clean(banned_rename.nickname), "(새 토큰) 금칙어 요청: 깨끗한 이름이 붙는다")
	var old_free: Dictionary = await acc.login(t2, "철수")
	check(old_free.nickname == "철수" and old_free.name_result == "ok", "예전 이름이 비면(철수는 민수로 바뀌었다) 다른 사람이 가질 수 있다")
	# 소켓으로: 서버가 정한 이름이 welcome에 온다
	var c := _client("철수", PORT + 1, NetProtocol.MODE_CREATE, "", Identity.new_token())
	await _settle(c)
	check(c.is_joined() and c.my_name != "철수" and c.my_name.begins_with("철수"), "접속 때 서버가 정한 닉네임이 welcome으로 온다 (%s)" % c.my_name)
	var c2 := _client("씨발", PORT + 1, NetProtocol.MODE_JOIN, c.room_code, Identity.new_token())
	await _settle(c2)
	check(c2.is_joined() and Nicknames.is_clean(c2.my_name) and c2.name_result == "banned_word", "금칙어 이름은 거부되고 알림(name_result)이 온다 (%s)" % c2.my_name)
	check(MainMenu.name_result_text("banned_word") != "" and MainMenu.name_result_text("") == "" and MainMenu.name_result_text("cooldown").contains("7일"), "화면 알림 문구")
	check(store.players.size() >= 9, "(참고) 저장소 계정 %d개" % store.players.size())
	await _free([c, c2, g.server])


# ---- [3] 판 기록 -------------------------------------------------------------------

func _match_record() -> void:
	print("[3] 판이 끝나면 서버가 기록을 저장한다 (서버가 계산한 값만)")
	var g := await _server(PORT + 2)
	var store: MemoryAccountStore = g.store
	var tokens := [Identity.new_token(), Identity.new_token(), Identity.new_token()]
	var game := await _game(g, PORT + 2, ["방장", "친구", "손님"], [tokens[0], tokens[1], "zz-guest"])
	var room: NetServer = game.room
	var clients: Array = game.clients
	check(clients.size() == 3 and room.field != null and room.started_unix > 0, "(전제) 3명이 판을 시작했다 (한 명은 게스트)")
	var boss: BossController = room.field.boss
	# 시뮬레이션 상태: 기여도와 유령 구간 점수가 쌓였다고 하자 (서버 안의 값)
	boss.damage_by_player = {0: 1234.5, 1: 77.0}
	boss.ghost_boss_damage_by_player = {0: 10.0, 1: 20.0, 2: 30.0}
	room.field.lanes[0].ghost_damage = 55.0
	room.field.lanes[1].ghost_damage = 66.0
	var level_before: int = boss.level
	# 클라이언트가 점수/결과를 보내도 서버는 받지 않는다 (알 수 없는 메시지)
	for cl in clients:
		cl._send({"t": "score", "boss_level": 99, "result": "win", "boss_damage": 1e12})
		cl._send({"t": "match", "match_id": "f".repeat(32), "result": "win", "boss_level": 99})
		cl._send({"t": NetProtocol.MSG_CMD, "seq": 1, "cmd": "{\"boss_level\":99}"})
	await wait_seconds(0.5)
	check(store.matches.is_empty(), "기록은 판이 끝나기 전에는 없다")
	clients[1].leave()  # 친구는 판 중에 나간다
	check(await wait_until(func(): return room.has_left(1), 3000), "(전제) 친구가 이탈했다")
	await wait_seconds(1.0)
	var secs_before_end := room.game_seconds
	await _victory(room)
	check(await wait_until(func(): return store.matches.size() == 1, 5000), "판이 끝나면 기록이 하나 저장된다")
	var rec: Dictionary = store.matches.values()[0]
	check(rec.result == "win" and rec.boss_level == level_before and rec.boss_level != 99, "결과(승)와 도달 레벨은 서버 값이다 (클라이언트가 보낸 99/win이 아니다): Lv.%d" % rec.boss_level)
	check(rec.player_count == 3 and rec.players.size() == 3, "방 인원 3명")
	check(rec.duration_s > 0.9 and rec.duration_s >= snappedf(secs_before_end, 0.1) - 0.1 and rec.duration_s < 30.0, "걸린 시간은 서버가 센 게임 시간이다 (%.1f초)" % rec.duration_s)
	check(rec.started_at > 0 and rec.ended_at >= rec.started_at and str(rec.match_id).length() == 32 and str(rec.version) != "", "시각/버전/기록 ID가 있다")
	var by_lane := {}
	for p in rec.players:
		by_lane[int(p.lane)] = p
	check(by_lane[0].account_id == store.players[Identity.hash_of(tokens[0])].id and by_lane[0].nickname == "방장", "레인 0: 방장의 계정 ID와 닉네임")
	check(by_lane[1].account_id == store.players[Identity.hash_of(tokens[1])].id and by_lane[1].left, "레인 1: 친구의 계정 ID, 판 중 이탈(left)로 표시")
	check(by_lane[2].account_id == "" and not by_lane[2].left, "레인 2: 게스트는 계정 ID가 비어 있다 (기록은 남되 계정에 안 묶인다)")
	near(by_lane[0].boss_damage, 1234.5, "레인 0 보스 피해(기여도)")
	near(by_lane[1].boss_damage, 77.0, "레인 1 보스 피해")
	near(by_lane[2].boss_damage, 0.0, "한 번도 못 친 레인 2는 0")
	near(by_lane[0].lane_damage, 55.0, "레인 0 유령 구간 레인 데미지")
	near(by_lane[1].ghost_boss_damage, 20.0, "레인 1 유령 구간 보스 레인 데미지")
	check(rec.match_id != "f".repeat(32), "클라이언트가 보낸 기록 ID가 아니다")
	# 두 번 기록되지 않는다 (끝난 방에서 다시 끝남 신호가 와도)
	boss.boss_defeated.emit()
	await frames(3)
	check(store.matches.size() == 1, "같은 판이 두 번 기록되지 않는다")
	await _free(clients + [g.server])

	# 패배 + 대기방에서 끝난 방은 기록 없음
	var g2 := await _server(PORT + 3)
	var store2: MemoryAccountStore = g2.store
	var t := [Identity.new_token(), Identity.new_token()]
	var game2 := await _game(g2, PORT + 3, ["가", "나"], t)
	await _defeat(game2.room)
	check(await wait_until(func(): return store2.matches.size() == 1, 5000), "패배한 판도 기록된다")
	var rec2: Dictionary = store2.matches.values()[0]
	check(rec2.result == "lose" and rec2.player_count == 2 and not rec2.players.any(func(p): return p.left), "결과 패, 2명, 아무도 안 나감")
	var lobby_only := _client("대기", PORT + 3, NetProtocol.MODE_CREATE, "", Identity.new_token())
	await _settle(lobby_only)
	lobby_only.leave()
	await wait_seconds(0.5)
	check(store2.matches.size() == 1, "시작도 안 한 대기방은 기록이 없다")
	await _free(game2.clients + [lobby_only, g2.server])


# ---- [4] DB가 죽어도 ---------------------------------------------------------------

func _db_down() -> void:
	print("[4] 저장소가 죽어도 진행 중인 판은 영향받지 않는다 (기록 저장만 재시도)")
	var g := await _server(PORT + 4)
	var store: MemoryAccountStore = g.store
	var acc: Accounts = g.acc
	var ta := Identity.new_token()
	var tb := Identity.new_token()
	var game := await _game(g, PORT + 4, ["가", "나"], [ta, tb])
	var room: NetServer = game.room
	var a: NetClient = game.clients[0]
	var b: NetClient = game.clients[1]
	store.fail = true   # DB 죽음
	var snaps0 := a.snapshot_count
	var secs0 := room.game_seconds
	await wait_seconds(1.0)
	check(a.snapshot_count > snaps0 + 3 and room.game_seconds > secs0 + 0.5 and room.field.boss.state == BossController.State.RUNNING, "DB가 죽어도 판은 계속 돈다 (스냅샷이 계속 오고 시간이 흐른다)")
	# 재접속: 아는 계정은 저장소 없이도 같은 자리로 돌아온다
	var back := _client("나", PORT + 4, NetProtocol.MODE_JOIN, room.room_code, tb)
	await _settle(back)
	check(back.is_joined() and back.resumed and back.player_id == 1, "진행 중인 판으로의 재접속은 저장소가 죽어도 된다 (같은 레인 %d)" % back.player_id)
	check(acc.is_down(), "저장소 실패를 한 번 겪으면 한동안 부르지 않는다")
	# 새 사람은 임시(게스트)로 입장
	var calls_before := store.calls
	var fresh := _client("신입", PORT + 4, NetProtocol.MODE_CREATE, "", Identity.new_token())
	await _settle(fresh)
	check(fresh.is_joined() and fresh.is_guest and store.calls == calls_before and fresh.name_result == "unavailable", "모르는 토큰은 기록이 안 남는 임시(게스트)로 입장하고, 죽은 저장소를 또 부르지 않는다")
	# 판이 끝나도 기록 저장은 대기열에서 재시도
	await _victory(room)
	check(await wait_until(func(): return acc.queue_size() == 1, 3000) and store.matches.is_empty(), "저장소가 죽은 동안 기록은 대기열에 쌓인다")
	check(FileAccess.file_exists(SPOOL), "대기열은 디스크에도 적힌다 (서버가 꺼져도 남는다)")
	await wait_seconds(1.0)
	check(acc.queue_size() == 1 and store.matches.is_empty(), "계속 실패하는 동안은 대기열을 유지한다")
	# 서버가 꺼졌다 켜진 것처럼: 새 Accounts가 디스크 대기열을 읽는다
	var acc2 := Accounts.new()
	acc2.spool_path = SPOOL
	acc2.retry_min_sec = 0.3
	g.server.add_child(acc2)
	var store2 := MemoryAccountStore.new()
	store2.players = store.players   # 같은 계정 서비스에 다시 붙은 것처럼 (계정이 없는 판은 저장하지 않으므로 계정을 공유한다)
	store2.fail = true
	acc2.set_store(store2)
	check(acc2.load_spool() == 1 and acc2.queue_size() == 1, "서버를 다시 켜면 못 보낸 기록을 대기열로 읽어 온다")
	store.fail = false
	store2.fail = false
	check(await wait_until(func(): return store.matches.size() == 1 and acc.queue_size() == 0, 5000), "저장소가 돌아오면 대기열이 비워지고 기록이 저장된다")
	check(await wait_until(func(): return store2.matches.size() == 1 and acc2.queue_size() == 0, 5000), "다시 켠 서버의 대기열도 같은 기록을 보낸다 (기록 ID가 같아 한 번만 저장된다)")
	check(not FileAccess.file_exists(SPOOL), "다 보내면 대기열 파일이 지워진다")
	check(store.matches.keys() == store2.matches.keys(), "(두 저장소의 기록 ID가 같다)")
	await _free(game.clients + [back, fresh, g.server])

	# 대기열이 넘치면 오래된 것부터
	var acc3 := Accounts.new()
	acc3.spool_path = "user://test_spool_full.jsonl"
	add_child(acc3)
	var dead := MemoryAccountStore.new()
	dead.fail = true
	acc3.set_store(dead)
	acc3.retry_min_sec = 100.0
	for i in range(Accounts.MAX_SPOOL + 5):
		acc3.record_match({"match_id": "%032x" % i, "players": [{}]})
	check(acc3.queue_size() == Accounts.MAX_SPOOL and acc3.dropped_matches == 5, "대기열이 한도(%d)를 넘으면 오래된 것부터 버린다" % Accounts.MAX_SPOOL)
	acc3.queue_free()
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_spool_full.jsonl"))


func _http_dead() -> void:
	print("[4b] 계정 서비스 주소가 죽어 있어도 접속은 빨리 처리된다 (판 진행은 저장소와 무관)")
	var http := HttpAccountStore.new()
	http.base_url = "http://127.0.0.1:1"
	http.api_key = KEY
	var g := await _server(PORT + 5, http)
	var t0 := Time.get_ticks_msec()
	var c := _client("가", PORT + 5, NetProtocol.MODE_CREATE, "", Identity.new_token())
	await _settle(c)
	var took := Time.get_ticks_msec() - t0
	check(c.is_joined() and c.is_guest and took < 4500, "서비스에 닿지 못하면 임시로 입장한다 (%d ms, hello 제한 %.0f초 안)" % [took, NetProtocol.HELLO_TIMEOUT])
	t0 = Time.get_ticks_msec()
	var c2 := _client("나", PORT + 5, NetProtocol.MODE_CREATE, "", Identity.new_token())
	await _settle(c2)
	check(c2.is_joined() and c2.is_guest and Time.get_ticks_msec() - t0 < 2500, "한 번 실패한 뒤에는 기다리지 않고 바로 입장한다 (%d ms)" % (Time.get_ticks_msec() - t0))
	await _free([c, c2, g.server])


# ---- [5] 순위 ----------------------------------------------------------------------

## ids: 참여자별 계정 ID (비면 게스트). 계정이 하나도 없는 판은 저장되지 않는다 (#66)
func _rec(i: int, level: int, result: String, dur: float, ended: int, names: Array, ids: Array = []) -> Dictionary:
	var ps: Array = []
	for lane in range(names.size()):
		ps.append({"account_id": ids[lane] if lane < ids.size() else "", "lane": lane, "nickname": names[lane], "boss_damage": 10.0 * (lane + 1), "lane_damage": 1.0, "ghost_boss_damage": 0.0, "left": false})
	return {"match_id": "%032x" % i, "started_at": ended - 100, "ended_at": ended, "player_count": names.size(), "result": result,
		"boss_level": level, "duration_s": dur, "version": "t", "players": ps}


## 저장소에 계정을 만들고 ID를 돌려준다 (판 기록은 계정이 있어야 저장된다)
func _make_accounts(s: AccountStore, names: Array) -> Array:
	var ids: Array = []
	for n in names:
		var r: Dictionary = await s.login(Identity.hash_of(Identity.new_token()), n, n)
		ids.append(str(r.account.id))
	return ids


func _leaderboard() -> void:
	print("[5] 리더보드: 서버 기록과 정확히 일치")
	var g := await _server(PORT + 6)
	var store: MemoryAccountStore = g.store
	var now := _fake_now
	var week_ago := now - 8 * 86400
	var names := ["가", "나", "다", "라", "마", "바", "사", "옛날"]
	var ids: Array = await _make_accounts(store, names)
	await store.record_match(_rec(1, 5, "lose", 300.0, now - 10, ["가"], [ids[0]]))
	await store.record_match(_rec(2, 10, "lose", 900.0, now - 10, ["나", "다"], [ids[1], ids[2]]))
	await store.record_match(_rec(3, 10, "win", 1200.0, now - 10, ["라"], [ids[3]]))
	await store.record_match(_rec(4, 10, "win", 1000.0, now - 10, ["마", "바", "사"], [ids[4], ids[5], ids[6]]))
	await store.record_match(_rec(5, 10, "win", 1000.0, week_ago, ["옛날"], [ids[7]]))
	var accounts_before := store.players.size()
	var rooms_before: int = g.hub.room_count()
	var cl := NetClient.new()
	cl.join_mode = NetProtocol.MODE_BOARD
	cl.board_period = "all"
	cl.player_name = "관전"
	var got := {}
	cl.board_received.connect(func(period, status, list): got["all"] = {"period": period, "status": status, "rows": list})
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT + 6)
	check(await wait_until(func(): return got.has("all"), 5000), "mode board로 접속하면 순위가 온다")
	var rows: Array = got.all.rows
	check(got.all.status == "ok" and rows.size() == 5, "전체 기록 5개 (%d)" % rows.size())
	var order: Array = rows.map(func(r): return str(r.match_id))
	check(order == ["%032x" % 5, "%032x" % 4, "%032x" % 3, "%032x" % 2, "%032x" % 1], "순서: 레벨 높은 순 -> 승리 먼저 -> 시간 짧은 순 -> 먼저 끝난 순")
	check(rows[0].rank == 1 and rows[4].rank == 5 and rows[1].players.size() == 3 and rows[1].players[2].nickname == "사", "순위 번호와 참여자 닉네임")
	near(float(rows[1].players[1].boss_damage), 20.0, "참여자별 보스 피해가 기록 그대로")
	check(g.hub.room_count() == rooms_before and store.players.size() == accounts_before, "조회는 방에 들어가거나 계정을 만들지 않는다")
	check(cl.state == NetClient.State.CLOSED, "결과를 받고 연결을 닫는다")
	var wk := NetClient.new()
	wk.join_mode = NetProtocol.MODE_BOARD
	wk.board_period = "week"
	wk.player_name = "관전"
	add_child(wk)
	wk.board_received.connect(func(period, status, list): got["week"] = {"period": period, "status": status, "rows": list})
	wk.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT + 6)
	check(await wait_until(func(): return got.has("week"), 5000) and got.week.period == "week" and got.week.rows.size() == 4, "주간은 최근 7일 기록만 (4개)")
	check(not got.week.rows.any(func(r): return r.match_id == "%032x" % 5), "지난주 기록은 주간에서 빠진다")
	# 캐시: 새 기록이 들어와도 캐시 시간 안에는 같은 결과 (저장소 부하가 일정)
	var calls := store.calls
	var ac: Accounts = g.acc
	var again: Dictionary = await ac.leaderboard("all")
	check(again.rows.size() == 5 and store.calls == calls, "같은 조회는 캐시에서 준다 (저장소를 다시 부르지 않는다)")
	# 저장소가 죽으면 unavailable
	var fresh := Accounts.new()
	g.server.add_child(fresh)
	var dead := MemoryAccountStore.new()
	dead.fail = true
	fresh.set_store(dead)
	var res: Dictionary = await fresh.leaderboard("all")
	check(res.status == "unavailable" and res.rows.is_empty(), "저장소가 죽으면 빈 순위와 unavailable")
	# 잘못된 period는 all
	var odd: Dictionary = await ac.leaderboard("year")
	check(odd.period == "all", "모르는 기간은 전체로")
	await _free([cl, wk, g.server])
	# 계정 없는 서버는 unavailable
	var plain := ServerMain.new()
	plain.use_rooms = true
	plain.net_port = PORT + 7
	get_tree().root.add_child.call_deferred(plain)
	await frames(6)
	var nb := NetClient.new()
	nb.join_mode = NetProtocol.MODE_BOARD
	nb.player_name = "관전"
	var nbres := {}
	nb.board_received.connect(func(_period, status, _list): nbres["r"] = status)
	add_child(nb)
	nb.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT + 7)
	check(await wait_until(func(): return nbres.has("r"), 5000) and nbres.r == "unavailable", "계정이 꺼진 서버는 순위 조회에 unavailable로 답한다")
	await _free([nb, plain])


# ---- [6] 실제 계정 서비스 ------------------------------------------------------------

func _python() -> String:
	if _py != "":
		return _py
	for cand in ["python", "py", "python3"]:
		var out := []
		if OS.execute(cand, ["--version"], out) == 0 and str(out[0]).begins_with("Python 3"):
			_py = cand
			return _py
	return ""


func _service_script() -> String:
	return ProjectSettings.globalize_path("res://tools/accounts/accounts_service.py")


func _start_service(db: String, port: int) -> int:
	OS.set_environment("LANEWARS_ACCOUNTS_KEY", KEY)
	return OS.create_process(_python(), [_service_script(), "--db", db, "serve", "--port", str(port), "--backup-interval-hours", "0", "--purge-interval-hours", "0"])


func _http_store(port: int) -> HttpAccountStore:
	var s := HttpAccountStore.new()
	s.base_url = "http://127.0.0.1:%d" % port
	s.api_key = KEY
	add_child(s)
	return s


func _wait_service(s: HttpAccountStore) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < 10000:
		var r: Dictionary = await s.leaderboard("all", 1)
		if r.status == "ok":
			return true
		await wait_seconds(0.3)
	return false


## 같은 시나리오를 어느 저장소에 돌려도 같은 결과여야 한다 (시간이 필요한 규칙은 뺀다: 서비스는 실제 시계를 쓴다)
func _contract(s: AccountStore, label: String) -> void:
	var h1 := Identity.hash_of(Identity.new_token())
	var h2 := Identity.hash_of(Identity.new_token())
	var h3 := Identity.hash_of(Identity.new_token())
	var r: Dictionary = await s.login(h1, "철수", "철수")
	check(r.status == "ok" and r.account.created and r.account.nickname == "철수" and str(r.account.id).length() == 16, "[%s] 첫 로그인: 계정 생성" % label)
	var id1: String = r.account.id
	r = await s.login(h1, "", "")
	check(r.status == "ok" and not r.account.created and r.account.id == id1 and r.name_result == "same", "[%s] 같은 토큰 해시: 같은 계정" % label)
	r = await s.login(h2, "철수", "철수")
	check(r.status == "nick_taken", "[%s] 새 계정이 겹치는 이름을 원하면 nick_taken" % label)
	r = await s.login(h2, "영희", "영희")
	check(r.status == "ok" and r.account.created, "[%s] 다른 이름으로 계정 생성" % label)
	r = await s.login(h2, "철수", "철수")
	check(r.status == "ok" and r.name_result == "taken" and r.account.nickname == "영희", "[%s] 남의 이름으로 변경은 거부, 기존 이름 유지" % label)
	r = await s.login(h2, "민수", "민수")
	check(r.status == "ok" and r.name_result == "ok" and r.account.nickname == "민수", "[%s] 가입 뒤 첫 변경은 바로" % label)
	r = await s.login(h2, "지수", "지수")
	check(r.status == "ok" and r.name_result == "cooldown", "[%s] 7일 안의 두 번째 변경은 cooldown" % label)
	r = await s.login(h3, "", "")
	check(r.status == "error" and r.get("reason", "") == "name_required", "[%s] 없는 계정을 이름 없이 부르면 name_required" % label)
	var now := int(Time.get_unix_time_from_system())
	var base := _rec(1, 5, "lose", 300.0, now - 10, ["철수"])
	base.players[0]["account_id"] = id1
	base.match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	var m1: String = base.match_id
	r = await s.record_match(base)
	check(r.status == "ok" and not r.duplicate, "[%s] 판 기록 저장" % label)
	r = await s.record_match(base)
	check(r.status == "ok" and r.duplicate, "[%s] 같은 기록 ID를 다시 보내도 한 번만 (재시도 안전)" % label)
	var bad := base.duplicate(true)
	bad.match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	bad.players = []
	r = await s.record_match(bad)
	check(r.status == "bad_request", "[%s] 모양이 틀린 기록은 bad_request (다시 보내도 소용없음)" % label)
	var more: Array = await _make_accounts(s, ["옛날", "최근", "둘"])
	var m2 := _rec(2, 10, "win", 900.0, now - 9 * 86400, ["옛날"], [more[0]])
	m2.match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	await s.record_match(m2)
	var m3 := _rec(3, 10, "win", 800.0, now - 5, ["최근", "둘"], [more[1], more[2]])
	m3.match_id = Crypto.new().generate_random_bytes(16).hex_encode()
	await s.record_match(m3)
	var all: Dictionary = await s.leaderboard("all", 10)
	var ids: Array = all.rows.map(func(x): return x.match_id)
	check(all.status == "ok" and ids == [m3.match_id, m2.match_id, m1], "[%s] 전체 순위: 레벨/승리/시간 순" % label)
	var week: Dictionary = await s.leaderboard("week", 10)
	check(week.rows.map(func(x): return x.match_id) == [m3.match_id, m1], "[%s] 주간 순위: 9일 전 기록 제외" % label)
	check(all.rows[0].players.size() == 2 and all.rows[0].players[1].nickname == "둘" and all.rows[0].player_count == 2, "[%s] 순위 행에 참여자 닉네임" % label)
	var top1: Dictionary = await s.leaderboard("all", 1)
	check(top1.rows.size() == 1, "[%s] 개수 제한" % label)


func _real_service() -> void:
	print("[6] 실제 계정 서비스(Python + SQLite)")
	if _python() == "":
		check(false, "Python 3가 필요하다 (python/py/python3 중 하나)")
		return
	var db := ProjectSettings.globalize_path("user://test_accounts.db")
	var backups := ProjectSettings.globalize_path("user://test_accounts_backups")
	for f in [db, db + "-wal", db + "-shm"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	if DirAccess.dir_exists_absolute(backups):
		for f in DirAccess.get_files_at(backups):
			DirAccess.remove_absolute(backups.path_join(f))
	# 서비스 자체의 시험(SQLite 규칙, 백업, 보관 기간 정리, 입력 검사)도 같이 돌린다
	OS.set_environment("PYTHONDONTWRITEBYTECODE", "1")
	var py_out := []
	var py_code := OS.execute(_python(), ["-m", "unittest", "discover", "-s", _service_script().get_base_dir(), "-p", "test_*.py"], py_out, true)
	check(py_code == 0, "tools/accounts/test_accounts_service.py 통과 (%s)" % str(py_out[0]).strip_edges().get_slice("
", str(py_out[0]).strip_edges().get_slice_count("
") - 1) if py_code == 0 else str(py_out))
	var pid := _start_service(db, SERVICE_PORT)
	var store := _http_store(SERVICE_PORT)
	check(pid > 0 and await _wait_service(store), "서비스가 떴다 (127.0.0.1:%d)" % SERVICE_PORT)
	# 키가 틀리면 거부
	var wrong := _http_store(SERVICE_PORT)
	wrong.api_key = "wrong-key-0123456789abcdef"
	var wr: Dictionary = await wrong.login(Identity.hash_of(Identity.new_token()), "해커", "해커")
	check(wr.status == "error" and wr.get("reason", "") == "http_401", "API 키가 틀리면 서비스가 거부한다 (401)")
	await _contract(store, "HTTP")
	var mem := MemoryAccountStore.new()
	add_child(mem)
	await _contract(mem, "Memory")
	mem.queue_free()

	# 방 서버 전체 흐름: 접속 -> 판 -> 끝 -> 서비스에 저장 -> 순위
	var g := await _server(PORT + 8, store)
	var ta := Identity.new_token()
	var tb := Identity.new_token()
	var game := await _game(g, PORT + 8, ["서비스가", "서비스나"], [ta, tb])
	await wait_seconds(1.0)
	await _victory(game.room)
	var top: Dictionary = {}
	var found := false
	var deadline := Time.get_ticks_msec() + 6000
	while Time.get_ticks_msec() < deadline:
		var lb: Dictionary = await store.leaderboard("all", 10)
		if lb.rows.any(func(x): return x.players.any(func(p): return p.nickname == "서비스가")):
			top = lb
			found = true
			break
		await wait_seconds(0.3)
	check(found, "방 서버가 끝난 판을 서비스에 저장했고 순위에 나온다")
	var row: Dictionary = {}
	for rw in top.get("rows", []):
		if rw.players.any(func(p): return p.nickname == "서비스가"):
			row = rw
	check(not row.is_empty() and row.player_count == 2 and row.result == "win" and row.duration_s > 0.9, "저장된 기록: 2명, 승, 걸린 시간 %.1f초" % float(row.get("duration_s", 0)))
	await _free(game.clients + [g.server])

	# 서비스를 껐다 켜도 계정/기록이 남는다
	var id_before: Dictionary = await store.login(Identity.hash_of(ta), "", "")
	check(id_before.status == "ok" and id_before.account.nickname == "서비스가", "(껐다 켜기 전) 계정 조회 성공")
	OS.kill(pid)
	await wait_seconds(0.8)
	var down: Dictionary = await store.login(Identity.hash_of(ta), "", "")
	check(down.status == "error", "서비스가 꺼지면 요청은 error다 (방 서버는 계속 돈다)")
	pid = _start_service(db, SERVICE_PORT)
	check(await _wait_service(store), "서비스를 다시 켰다")
	var id_after: Dictionary = await store.login(Identity.hash_of(ta), "", "")
	check(id_after.status == "ok" and id_after.account.id == id_before.account.id and not id_after.account.created, "다시 켠 뒤에도 같은 토큰은 같은 계정이다")
	var lb2: Dictionary = await store.leaderboard("all", 10)
	check(lb2.rows.size() >= 4 and lb2.rows.any(func(x): return x.players.any(func(p): return p.nickname == "서비스가")), "다시 켠 뒤에도 판 기록이 남아 있다 (%d개)" % lb2.rows.size())
	OS.kill(pid)
	await wait_seconds(0.8)

	# 백업: 서비스를 끄고(또는 켠 채로) backup 명령 -> 사본으로 복원
	var out := []
	var code := OS.execute(_python(), [_service_script(), "--db", db, "backup", "--backup-dir", backups, "--backup-keep", "3"], out)
	var made := str(out[0]).strip_edges()
	check(code == 0 and made != "" and FileAccess.file_exists(made), "backup 명령이 사본을 만든다 (%s)" % made.get_file())
	var port2 := SERVICE_PORT + 1
	var pid2 := _start_service(made, port2)
	var restored := _http_store(port2)
	check(await _wait_service(restored), "사본으로 서비스를 띄웠다 (복원)")
	var rid: Dictionary = await restored.login(Identity.hash_of(ta), "", "")
	var rlb: Dictionary = await restored.leaderboard("all", 10)
	check(rid.status == "ok" and rid.account.id == id_before.account.id and rlb.rows.size() == lb2.rows.size(), "백업 사본에 계정과 기록이 그대로 들어 있다")
	# 차단: 서비스 CLI로
	OS.kill(pid2)
	await wait_seconds(0.8)
	var ban_out := []
	var ban_code := OS.execute(_python(), [_service_script(), "--db", db, "ban", id_before.account.id], ban_out)
	check(ban_code == 0, "차단 도구(서비스 CLI)가 계정을 차단했다")
	pid = _start_service(db, SERVICE_PORT)
	check(await _wait_service(store), "서비스 재시작")
	var banned: Dictionary = await store.login(Identity.hash_of(ta), "", "")
	check(banned.status == "banned", "차단된 계정의 로그인은 banned")
	OS.kill(pid)
	await wait_seconds(0.5)
	await _free([store, wrong, restored])
	for f in [db, db + "-wal", db + "-shm"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


# ---- [8] 계정 삭제 (#66) -------------------------------------------------------------

func _board_rows(port: int) -> Array:
	var cl := NetClient.new()
	cl.join_mode = NetProtocol.MODE_BOARD
	cl.board_period = "all"
	cl.player_name = "관전"
	var got := {}
	cl.board_received.connect(func(_period, status, list): got["r"] = {"status": status, "rows": list})
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
	var ok := await wait_until(func(): return got.has("r"), 5000)
	cl.queue_free()
	return got.r.rows if ok and got.r.status == "ok" else []


func _nicknames(rows: Array) -> Array:
	var out: Array = []
	for r in rows:
		for p in r.players:
			out.append(str(p.nickname))
	return out


func _account_deletion() -> void:
	print("[8] 계정 삭제: 삭제 요청 명령, 판 기록 함께 삭제, 순위에서 사라짐")
	if _python() == "":
		check(false, "Python 3가 필요하다")
		return
	var db := ProjectSettings.globalize_path("user://test_deletion.db")
	for f in [db, db + "-wal", db + "-shm"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)
	var port := SERVICE_PORT + 2
	var pid := _start_service(db, port)
	var store := _http_store(port)
	check(pid > 0 and await _wait_service(store), "서비스가 떴다")
	var gone_token := Identity.new_token()
	var first: Dictionary = await store.login(Identity.hash_of(gone_token), "지울사람", "지울사람")
	var second: Dictionary = await store.login(Identity.hash_of(Identity.new_token()), "남을사람", "남을사람")
	var ids: Array = [str(first.account.id), str(second.account.id)]
	var now := int(Time.get_unix_time_from_system())
	var team := _rec(1, 10, "win", 1000.0, now - 10, ["지울사람", "남을사람", "손님"], [ids[0], ids[1], ""])
	var solo := _rec(2, 5, "lose", 300.0, now - 10, ["지울사람"], [ids[0]])
	var guests := _rec(3, 9, "win", 500.0, now - 10, ["손님만"])
	check((await store.record_match(team)).stored == true and (await store.record_match(solo)).stored == true, "다인원 판과 혼자 한 판이 저장됐다")
	var gr: Dictionary = await store.record_match(guests)
	check(gr.status == "ok" and gr.stored == false, "계정이 한 명도 없는(전원 게스트) 판은 저장하지 않는다 (계정과 함께 지워 줄 수 없어서)")
	var g := await _server(PORT + 10, store)
	var before := await _board_rows(PORT + 10)
	check(before.size() == 2 and _nicknames(before).has("지울사람"), "삭제 전: 순위에 두 판이 있고 지울사람이 나온다 (%d)" % before.size())
	# 삭제 요청 명령: 미리보기(--yes 없음)는 지우지 않는다
	var out := []
	var code := OS.execute(_python(), [_service_script(), "--db", db, "delete-account", "지울사람"], out)
	check(code == 2 and str(out[0]).contains("--yes"), "--yes가 없으면 미리보기만 하고 종료 코드 2 (%d)" % code)
	var still := await store.leaderboard("all", 10)
	check(still.rows.size() == 2, "미리보기는 아무것도 지우지 않았다")
	# 서비스가 떠 있는 채로 삭제
	out = []
	code = OS.execute(_python(), [_service_script(), "--db", db, "delete-account", ids[0], "--yes"], out)
	var res: Dictionary = JSON.parse_string(str(out[0]).strip_edges()) if code == 0 else {}
	check(code == 0 and res.get("id", "") == ids[0] and res.get("matches_deleted", -1) == 1 and res.get("matches_anonymized", -1) == 1, "삭제 명령: 계정을 지웠고 혼자 한 판 1개는 삭제, 다인원 판 1개는 익명 처리 %s" % str(out[0]).strip_edges())
	# 서버의 순위 캐시(30초)를 지나서 다시 조회: 실제로는 캐시 시간 안의 조회도 곧 갱신된다
	g.acc._boards.clear()
	var after := await _board_rows(PORT + 10)
	var names := _nicknames(after)
	check(after.size() == 1 and after[0].match_id == team.match_id, "삭제 뒤 순위(서버 board 조회): 혼자 한 판은 사라지고 다인원 판만 남는다")
	check(not names.has("지울사람") and names.has("남을사람") and names.has("손님") and names.has("(삭제된 사용자)"), "삭제된 닉네임은 안 나오고 남은 참가자와 (삭제된 사용자) 줄만 나온다 %s" % str(names))
	check(after[0].player_count == 3, "방(팀) 기록의 인원수는 그대로")
	var gone: Dictionary = await store.login(Identity.hash_of(gone_token), "", "")
	check(gone.status == "error" and gone.get("reason", "") == "name_required", "삭제된 계정의 토큰으로는 더 이상 계정이 조회되지 않는다")
	var reborn: Dictionary = await store.login(Identity.hash_of(gone_token), "새로운", "새로운")
	check(reborn.status == "ok" and reborn.account.created and reborn.account.id != ids[0], "같은 토큰으로 다시 접속하면 새 계정이 만들어진다")
	# 삭제된 뒤 늦게 도착한 기록: 닉네임이 되살아나지 않는다
	var late := _rec(4, 12, "win", 700.0, now - 5, ["지울사람", "남을사람"], [ids[0], ids[1]])
	var lr: Dictionary = await store.record_match(late)
	check(lr.stored == true, "삭제된 계정이 낀 늦은 기록도 남은 참가자 때문에 저장된다")
	g.acc._boards.clear()
	var late_rows := await _board_rows(PORT + 10)
	check(late_rows.size() == 2 and not _nicknames(late_rows).has("지울사람"), "늦은 기록에서도 삭제된 닉네임은 나오지 않는다")
	# 보관 기간 정리 명령: 방금 접속한 계정은 안 지운다
	out = []
	code = OS.execute(_python(), [_service_script(), "--db", db, "purge"], out)
	var pr: Dictionary = JSON.parse_string(str(out[0]).strip_edges()) if code == 0 else {}
	check(code == 0 and pr.get("players", -1) == 0 and pr.get("matches_deleted", -1) == 0, "purge 명령(기본 365일): 방금 접속한 계정은 지우지 않는다 %s" % str(out[0]).strip_edges())
	# 마지막 참가 계정까지 지워지면 판 전체가 사라진다
	out = []
	code = OS.execute(_python(), [_service_script(), "--db", db, "delete-account", "남을사람", "--yes"], out)
	check(code == 0, "닉네임으로도 삭제할 수 있다")
	g.acc._boards.clear()
	check((await _board_rows(PORT + 10)).is_empty(), "참가 계정이 모두 삭제되면 판 기록이 전부 사라진다 (게스트 줄 포함)")
	OS.kill(pid)
	await wait_seconds(0.5)
	await _free([store, g.server])
	for f in [db, db + "-wal", db + "-shm"]:
		if FileAccess.file_exists(f):
			DirAccess.remove_absolute(f)


# ---- [0b] 메인 메뉴가 계정 토큰으로 접속한다 ------------------------------------------

func _main_menu_token() -> void:
	print("[7] 메인 메뉴는 기기의 계정 토큰으로 접속한다")
	var g := await _server(PORT + 9)
	var menu := MainMenu.new()
	menu.profile_path = "user://test_profile_accounts.cfg"
	add_child(menu)
	await frames(2)
	menu.server_edit.text = "127.0.0.1:%d" % (PORT + 9)
	menu.name_edit.text = "메뉴철수"
	menu.create_button.pressed.emit()
	check(await wait_until(func(): return menu.lobby_screen != null, 8000), "방 만들기로 입장했다")
	check(menu.client.token == Identity.account_token(), "접속 토큰은 기기의 계정 토큰이다")
	var store: MemoryAccountStore = g.store
	check(_hash_ok(Identity.account_token(), store) and store.players[Identity.hash_of(Identity.account_token())].nickname == "메뉴철수", "서버에 그 토큰의 계정이 만들어졌다")
	await _free([menu, g.server])
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_profile_accounts.cfg"))
