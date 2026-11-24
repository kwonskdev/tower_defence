extends "res://tests/case_base.gd"
## 이슈 #26: 방 코드로 모이기 (코드 발급/반납, 거부 사유, 무차별 대입 제한, 방 여러 개).
##  [1] RoomCodes 규칙: 문자셋(0/O/1/I/L 없음) / 길이 / 겹치지 않음 / 반납 뒤 재발급 / 모양 검사 / 만료 / 시도 제한(주소별, 서버 전체, 시간 지나면 풀림)
##  [2] 방 코드 서버(RoomHub): 만들기 -> 코드 -> 다른 클라이언트가 코드로 입장 / 방이 서로 독립 / 게임 모드 필드
##  [3] 거부 사유: 없는 코드 / 모양이 틀린 코드 / 가득 참 / 이미 시작 / mode 없는 hello
##  [4] 무차별 대입: 잘못된 코드를 반복하면 too_many_attempts, 그 뒤엔 맞는 코드도 막힌다, 시간이 지나면 풀린다
##  [6] 빠른 시작: 자리 있는 공개 방에 들어가고 없으면 새 공개 방 (비공개/가득/시작한 방에는 안 들어간다)
##  [5] 코드 반납: 방이 비면 / 시작 못 한 채 만료되면 / 판이 끝나면
## (폰 실기기/실제 지연은 보지 않는다. 메인 메뉴는 tests/test_main_menu.gd)

const PORT_BASE := 47280

var _fake_ms := 1000000


func run() -> void:
	_codes()
	await _hub_basic()
	await _rejects()
	await _brute_force()
	await _release()
	await _quick_start()
	Engine.time_scale = 1.0


# ---- [1] RoomCodes ---------------------------------------------------------

func _codes() -> void:
	print("[1] 방 코드 규칙")
	var bad_chars := "0O1IL"
	var clean := true
	for ch in bad_chars:
		if RoomCodes.ALPHABET.find(ch) >= 0:
			clean = false
	check(clean, "문자셋에 혼동되는 글자(0/O/1/I/L)가 없다")
	check(RoomCodes.ALPHABET.length() == 31 and RoomCodes.LENGTH == 6, "문자셋 31자, 코드 6자 (31^6 = 약 8.9억 가지)")
	var codes := RoomCodes.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var seen := {}
	var all_valid := true
	for i in range(500):
		var code := codes.issue(0, rng)
		if not RoomCodes.is_valid_format(code) or seen.has(code):
			all_valid = false
		seen[code] = true
	check(all_valid and codes.count() == 500, "코드 500개가 모두 올바른 모양이고 서로 다르다")
	var one := seen.keys()[0] as String
	codes.release(one)
	check(not codes.has(one) and codes.count() == 499, "반납하면 더는 유효한 코드가 아니다")
	check(RoomCodes.is_valid_format("ABC234") and not RoomCodes.is_valid_format("ABC23") and not RoomCodes.is_valid_format("ABC2345") and not RoomCodes.is_valid_format("ABCO34") and not RoomCodes.is_valid_format("abc234"), "모양 검사: 길이와 글자")
	check(RoomCodes.normalize(" abc-23 4 ") == "ABC234", "입력은 공백/하이픈을 빼고 대문자로 바꾼다")
	# 만료
	var c2 := RoomCodes.new()
	var made := c2.issue(1000, rng)
	check(c2.expired(1000 + int(RoomCodes.EXPIRE_SEC * 1000.0) - 1).is_empty() and c2.expired(1000 + int(RoomCodes.EXPIRE_SEC * 1000.0)) == [made], "만든 지 %d초가 지나야 만료" % int(RoomCodes.EXPIRE_SEC))
	# 시도 제한
	var lim := RoomCodes.new()
	var blocked_at := -1
	for i in range(RoomCodes.MAX_BAD_PER_KEY + 2):
		if lim.allowed("1.2.3.4", 100 + i):
			if lim.record_bad("1.2.3.4", 100 + i) and blocked_at < 0:
				blocked_at = i + 1
	check(blocked_at == RoomCodes.MAX_BAD_PER_KEY and not lim.allowed("1.2.3.4", 200), "같은 주소가 잘못된 코드를 %d번 시도하면 막힌다" % RoomCodes.MAX_BAD_PER_KEY)
	check(lim.allowed("5.6.7.8", 200), "다른 주소는 영향이 없다")
	check(lim.allowed("1.2.3.4", 100 + RoomCodes.WINDOW_MS + RoomCodes.MAX_BAD_PER_KEY + 1), "1분이 지나면 다시 시도할 수 있다")
	var glob := RoomCodes.new()
	for i in range(RoomCodes.MAX_BAD_PER_MINUTE):
		glob.record_bad("ip%d" % i, 500)  # 주소를 바꿔 가며 시도한다
	check(not glob.allowed("new-ip", 600) and glob.allowed("new-ip", 500 + RoomCodes.WINDOW_MS), "주소를 바꿔도 서버 전체 분당 한도에서 막히고, 1분 뒤 풀린다")


# ---- 서버/클라이언트 도우미 ---------------------------------------------------

func _server(port: int, max_players: int = 8, auto_sec: float = 3.0) -> ServerMain:
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	server.lobby_max_players = max_players
	server.game_auto_start_sec = auto_sec
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	server.hub.clock = func(): return _fake_ms
	return server


func _client(player_name: String, port: int, mode: String, code := "") -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	cl.join_mode = mode
	cl.join_code = code
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
	return cl


## 입장하거나 거부될 때까지 기다린다. 거부 사유(없으면 "")를 돌려준다.
func _settle(cl: NetClient) -> String:
	await wait_until(func(): return cl.is_joined() or cl.state == NetClient.State.REJECTED, 8000)
	return cl.reject_reason


# ---- [2] 방 만들기 / 코드로 입장 ---------------------------------------------

func _hub_basic() -> void:
	print("[2] 방 만들기 -> 코드 -> 다른 클라이언트가 코드로 입장")
	var port := PORT_BASE
	var server := await _server(port)
	var hub: RoomHub = server.hub
	check(hub != null and hub.peer != null and server.net == null, "방 코드 서버가 열렸다 (방 0개)")
	var a := _client("방장", port, NetProtocol.MODE_CREATE)
	check(await _settle(a) == "" and a.is_joined(), "방 만들기로 입장했다")
	check(RoomCodes.is_valid_format(a.room_code) and hub.room_count() == 1 and hub.codes.has(a.room_code), "서버가 코드를 줬다: %s" % a.room_code)
	check(a.player_id == 0, "만든 사람이 0번 레인(방장)")
	var b := _client("친구", port, NetProtocol.MODE_JOIN, a.room_code.to_lower())  # 소문자로 쳐도 된다
	check(await _settle(b) == "" and b.is_joined() and b.player_id == 1 and b.room_code == a.room_code, "다른 클라이언트가 코드로 입장 (레인 %d)" % b.player_id)
	await wait_until(func(): return a.lobby.get("members", []).size() == 2 and b.lobby.get("members", []).size() == 2, 5000)
	check(a.lobby.get("members", []).size() == 2 and a.lobby.get("room") == a.room_code and b.lobby.get("host") == 0, "둘 다 같은 대기방을 본다 (방장 0번, 코드 표시)")
	check(a.lobby.get("mode") == Session.MODE_COOP and hub.room_for(a.room_code).game_mode == Session.MODE_COOP, "방/세션에 게임 모드 필드가 있다 (협력)")
	# 방이 서로 독립이다
	var c := _client("딴사람", port, NetProtocol.MODE_CREATE)
	await _settle(c)
	check(c.room_code != a.room_code and hub.room_count() == 2, "다른 사람이 만든 방은 다른 코드(%s)이고 방이 2개" % c.room_code)
	await wait_until(func(): return c.lobby.get("members", []).size() == 1, 5000)
	check(c.lobby.get("members", []).size() == 1 and a.lobby.get("members", []).size() == 2, "두 방의 참여자가 섞이지 않는다")
	# 방 하나의 판이 시작해도 다른 방은 대기 중이다
	b.set_ready(true)
	await wait_until(func(): return a.lobby.get("can_start", false), 5000)
	var started := {}
	a.game_started.connect(func(players, _n): started["a"] = players)
	b.game_started.connect(func(players, _n): started["b"] = players)
	a.request_start()
	check(await wait_until(func(): return started.has("a") and started.has("b"), 8000) and started.a == [0, 1], "방장이 시작하면 그 방 사람들만 게임 화면으로 간다")
	var room_a := hub.room_for(a.room_code)
	check(room_a.field != null and room_a.field.lanes.size() == 2 and hub.room_for(c.room_code).field == null, "그 방의 판만 만들어졌고 다른 방은 아직 대기방")
	var d := _client("늦은", port, NetProtocol.MODE_JOIN, c.room_code)
	check(await _settle(d) == "" and d.player_id == 1, "다른 방에는 계속 들어올 수 있다")
	for cl in [a, b, c, d]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [3] 거부 사유 -----------------------------------------------------------

func _rejects() -> void:
	print("[3] 거부 사유")
	var port := PORT_BASE + 1
	var server := await _server(port, 2)
	var hub: RoomHub = server.hub
	var a := _client("방장", port, NetProtocol.MODE_CREATE)
	await _settle(a)
	var code := a.room_code
	var unknown := "ZZZZZZ" if code != "ZZZZZZ" else "YYYYYY"
	var r1 := _client("x", port, NetProtocol.MODE_JOIN, unknown)
	check(await _settle(r1) == NetProtocol.REJECT_NO_ROOM, "없는 코드: room_not_found (%s)" % r1.reject_reason)
	var r2 := _client("x", port, NetProtocol.MODE_JOIN, "AB")
	check(await _settle(r2) == NetProtocol.REJECT_NO_ROOM, "모양이 틀린 코드(짧음): room_not_found (%s)" % r2.reject_reason)
	var r3 := _client("x", port, NetProtocol.MODE_JOIN, "")
	check(await _settle(r3) == NetProtocol.REJECT_NO_ROOM, "코드를 안 쓰면: room_not_found (%s)" % r3.reject_reason)
	var r4 := _client("x", port, "")  # 예전 클라이언트: mode가 없다
	check(await _settle(r4) == NetProtocol.REJECT_BAD_HELLO, "mode가 없는 hello: bad_hello (%s)" % r4.reject_reason)
	var b := _client("친구", port, NetProtocol.MODE_JOIN, code)
	await _settle(b)
	var full := _client("셋째", port, NetProtocol.MODE_JOIN, code)  # 이 서버는 방 최대 2명
	check(await _settle(full) == NetProtocol.REJECT_FULL, "가득 찬 방: room_full (%s)" % full.reject_reason)
	check(hub.room_for(code).joined_count() == 2, "거부된 연결이 자리를 쓰지 않았다")
	b.set_ready(true)
	await wait_until(func(): return a.lobby.get("can_start", false), 5000)
	a.request_start()
	await wait_until(func(): return hub.room_for(code).game_started, 5000)
	await wait_until(func(): return hub.room_for(code).field != null, 5000)
	var late := _client("늦은", port, NetProtocol.MODE_JOIN, code)
	check(await _settle(late) == NetProtocol.REJECT_STARTED, "이미 시작한 방: already_started (%s)" % late.reject_reason)
	for cl in [a, b, r1, r2, r3, r4, full, late]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [4] 무차별 대입 ---------------------------------------------------------

func _brute_force() -> void:
	print("[4] 잘못된 코드를 반복하면 막힌다")
	var port := PORT_BASE + 2
	var server := await _server(port)
	var hub: RoomHub = server.hub
	var host := _client("방장", port, NetProtocol.MODE_CREATE)
	await _settle(host)
	var results: Array = []
	for i in range(RoomCodes.MAX_BAD_PER_KEY + 1):
		var t := _client("시도", port, NetProtocol.MODE_JOIN, "ZZZZ%d%d" % [2 + i, 2])
		results.append(await _settle(t))
		t.queue_free()
	var expected: Array = []
	for i in range(RoomCodes.MAX_BAD_PER_KEY - 1):
		expected.append(NetProtocol.REJECT_NO_ROOM)
	expected.append(NetProtocol.REJECT_TOO_MANY)  # 한도에 닿은 시도
	expected.append(NetProtocol.REJECT_TOO_MANY)  # 그 뒤
	check(results == expected, "%d번째 잘못된 시도부터 too_many_attempts %s" % [RoomCodes.MAX_BAD_PER_KEY, results])
	var good := _client("친구", port, NetProtocol.MODE_JOIN, host.room_code)
	check(await _settle(good) == NetProtocol.REJECT_TOO_MANY, "막힌 뒤에는 맞는 코드도 거부된다 (코드를 맞혀 보는 것을 의미 없게)")
	check(hub.room_for(host.room_code).joined_count() == 1, "막힌 연결은 방에 들어가지 못했다")
	var create := _client("방 만들기도", port, NetProtocol.MODE_CREATE)
	check(await _settle(create) == "" and create.is_joined(), "방 만들기는 코드를 맞히는 시도가 아니라서 막히지 않는다")
	_fake_ms += RoomCodes.WINDOW_MS + 1000
	var again := _client("친구", port, NetProtocol.MODE_JOIN, host.room_code)
	check(await _settle(again) == "" and again.is_joined(), "1분이 지나면 다시 입장할 수 있다")
	for cl in [host, good, create, again]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [5] 코드 반납 -----------------------------------------------------------

func _release() -> void:
	print("[5] 방이 비거나 끝나거나 만료되면 코드를 돌려받는다")
	var port := PORT_BASE + 3
	var server := await _server(port)
	var hub: RoomHub = server.hub
	# 비면 반납
	var a := _client("방장", port, NetProtocol.MODE_CREATE)
	await _settle(a)
	var code := a.room_code
	a.close()
	check(await wait_until(func(): return not hub.codes.has(code) and hub.room_count() == 0, 5000), "모두 나가 방이 비면 코드가 반납되고 방이 닫힌다")
	var back := _client("누군가", port, NetProtocol.MODE_JOIN, code)
	check(await _settle(back) == NetProtocol.REJECT_NO_ROOM, "반납된 코드로는 들어갈 수 없다")
	# 한 명 나가도 남아 있으면 유지
	var h := _client("방장", port, NetProtocol.MODE_CREATE)
	await _settle(h)
	var f := _client("친구", port, NetProtocol.MODE_JOIN, h.room_code)
	await _settle(f)
	f.close()
	await frames(20)
	check(hub.codes.has(h.room_code) and hub.room_count() == 1, "한 명이 나가도 남은 사람이 있으면 방과 코드가 유지된다")
	await wait_until(func(): return h.lobby.get("members", []).size() == 1, 5000)
	check(h.lobby.get("members", []).size() == 1, "나간 사람은 대기방 목록에서 빠진다")
	# 만료
	var hcode := h.room_code
	var dropped := {"v": false}
	h.disconnected.connect(func(): dropped["v"] = true)
	_fake_ms += int(RoomCodes.EXPIRE_SEC * 1000.0) + 1000
	check(await wait_until(func(): return not hub.codes.has(hcode) and hub.room_count() == 0, 5000), "시작 못 한 채 만료 시간이 지나면 방이 닫히고 코드가 반납된다")
	check(await wait_until(func(): return dropped.v, 5000), "만료된 방의 접속자는 연결이 끊긴다 (그 소켓만)")
	# 판이 끝나면 반납
	var g := _client("방장", port, NetProtocol.MODE_CREATE)
	await _settle(g)
	var gcode := g.room_code
	g.request_start()
	await wait_until(func(): return hub.room_for(gcode).field != null, 8000)
	check(hub.codes.has(gcode), "판 중에는 코드가 유지된다")
	hub._on_room_finished(gcode)
	check(not hub.codes.has(gcode) and hub.room_for(gcode) != null, "판이 끝나면 코드는 바로 반납되고 (결과 화면을 위해) 방은 잠시 남는다")
	var late := _client("늦은", port, NetProtocol.MODE_JOIN, gcode)
	check(await _settle(late) == NetProtocol.REJECT_NO_ROOM, "끝난 방의 코드로는 들어갈 수 없다")
	_fake_ms += int(RoomHub.FINISHED_KEEP_SEC * 1000.0) + 1000
	check(await wait_until(func(): return hub.room_count() == 0, 5000), "끝난 뒤 정리 시간이 지나면 방이 닫힌다")
	for cl in [a, back, h, f, g, late]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [6] 빠른 시작 -----------------------------------------------------------

func _quick_start() -> void:
	print("[6] 빠른 시작: 자리 있는 공개 방에 들어가고, 없으면 새 공개 방")
	var port := PORT_BASE + 4
	var server := await _server(port, 2)  # 방 최대 2명
	var hub: RoomHub = server.hub
	var priv := _client("비공개", port, NetProtocol.MODE_CREATE)
	await _settle(priv)
	var q1 := _client("하나", port, NetProtocol.MODE_QUICK)
	check(await _settle(q1) == "" and q1.is_joined() and hub.room_count() == 2, "공개 방이 없으면 새로 만든다 (비공개 방에는 들어가지 않는다)")
	check(q1.room_code != priv.room_code and hub.room_for(q1.room_code).public_room and not hub.room_for(priv.room_code).public_room, "새 방은 공개 방이고 만든 비공개 방은 그대로")
	await wait_until(func(): return q1.lobby.get("public", false), 5000)
	check(q1.lobby.get("public", false) and not priv.lobby.get("public", true), "대기방 상태에 공개 여부가 실려 온다")
	var q2 := _client("둘", port, NetProtocol.MODE_QUICK)
	check(await _settle(q2) == "" and q2.room_code == q1.room_code and q2.player_id == 1 and hub.room_count() == 2, "자리 있는 공개 방에 들어간다 (같은 방, 레인 %d)" % q2.player_id)
	var q3 := _client("셋", port, NetProtocol.MODE_QUICK)  # 공개 방이 가득 찼다
	check(await _settle(q3) == "" and q3.room_code != q1.room_code and hub.room_count() == 3 and hub.room_for(q3.room_code).public_room, "가득 찬 공개 방은 건너뛰고 새 공개 방을 만든다")
	var q4 := _client("넷", port, NetProtocol.MODE_QUICK)
	check(await _settle(q4) == "" and q4.room_code == q3.room_code and hub.room_count() == 3, "다음 사람은 자리 있는 새 방으로 들어간다")
	# 시작한 방에는 안 들어간다
	q2.set_ready(true)
	await wait_until(func(): return q1.lobby.get("can_start", false), 5000)
	q1.request_start()
	await wait_until(func(): return hub.room_for(q1.room_code).game_started, 5000)
	await wait_until(func(): return hub.room_for(q3.room_code).lobby.size() == 2, 5000)
	q4.close()  # q3 방에 한 자리를 만든다
	await wait_until(func(): return hub.room_for(q3.room_code).lobby.size() == 1, 5000)
	var q5 := _client("다섯", port, NetProtocol.MODE_QUICK)
	check(await _settle(q5) == "" and q5.room_code == q3.room_code, "이미 시작한 공개 방은 건너뛰고 대기 중인 공개 방에 들어간다")
	for cl in [priv, q1, q2, q3, q4, q5]:
		cl.queue_free()
	server.queue_free()
	await frames(4)
