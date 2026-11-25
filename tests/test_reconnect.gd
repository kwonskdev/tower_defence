extends "res://tests/case_base.gd"
## 이슈 #23: 연결 끊김 / 재접속 / 이탈. 서버 1개(방 코드 서버)에 클라이언트를 붙여 실제 소켓으로 확인한다. 체크리스트와 대응:
##  [1] 끊김 감지(하트비트): 조용해진 연결을 서버가 끊김으로 보고, 다른 사람이 그것을 알게 된다 / 정상 연결은 ping으로 끊기지 않는다
##  [2] 유예 안 재접속: 같은 레인으로 돌아오고 상태(골드, 타워, 보스 시간)가 서버와 맞다. 로컬에 남은 옛 상태는 버려진다. 끊긴 동안에도 서버는 멈추지 않는다
##  [3] 옛 명령: 끊긴 연결/대체된 연결의 명령은 실행되지 않는다
##  [4] 유예가 지나면 이탈: #22 탈락과 같다(레인 무너짐, 그 사람 몬스터 철수). 유예 중에는 몬스터가 남는다. 이탈 뒤 재접속은 거부(seat_released)
##  [5] 앱 백그라운드: 복귀하면 바로 다시 접속(옛 연결을 대체)하고, 온라인 판은 백그라운드로 가도 일시정지하지 않는다
##  [6] 방장 이탈: 방이 유지되고 방장이 다음 사람으로 바뀐다 / 의도적 이탈(나가기)은 유예 없이 바로 이탈
##  [7] 자리 가로채기: 같은 닉네임이나 틀린 토큰으로는 자리를 못 얻는다. 서버는 토큰 원문을 갖고 있지 않다
##  [8] 화면: 끊기면 "재접속 중" 오버레이, 돌아오면 닫힘, 다른 사람의 끊김/이탈은 배너, 앱 재시작 뒤 메뉴에서 복귀, 돌아오지 못하면 메뉴로
## (실제 비행기 모드 전환과 폰에서 보이는 모양은 눈으로 보지 못한다: 연결을 얼리거나 닫아서 같은 상황을 만든다)

const PORT := 47340
const GRACE := 3.0       # 서버 유예 (테스트용으로 줄인다)
const HEARTBEAT := 1.0   # 서버 하트비트 시간 초과 (테스트용)


func run() -> void:
	Identity.resume_path = "user://test_reconnect_resume.cfg"
	Identity.clear_resume()
	await _identity_and_lobby_units()
	await _heartbeat_and_away()
	await _reconnect_state()
	await _old_commands()
	await _grace_expiry()
	await _app_background()
	await _host_and_leave()
	await _seat_hijack()
	await _screens()
	await _menu_resume()
	Identity.clear_resume()
	Engine.time_scale = 1.0


func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _server(port: int, grace := GRACE, heartbeat := HEARTBEAT) -> ServerMain:
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	server.hub.reconnect_grace = grace
	server.hub.heartbeat_timeout = heartbeat
	return server


func _client(player_name: String, port: int, mode: String, code := "") -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	cl.join_mode = mode
	cl.join_code = code
	cl.ping_interval = 0.3          # 서버 하트비트(1초)보다 자주
	cl.reconnect_grace = GRACE + 4.0
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
	return cl


func _own_lane(cl: NetClient) -> bool:
	return cl.snapshot.get("lanes", {}).has(str(cl.player_id))


## 서버 + n명이 접속해서 시작한 판. {server, hub, room, clients}
func _game(port: int, n: int, grace := GRACE, heartbeat := HEARTBEAT) -> Dictionary:
	var server := await _server(port, grace, heartbeat)
	var clients: Array = []
	var host := _client("방장", port, NetProtocol.MODE_CREATE)
	await wait_until(func(): return host.is_joined(), 8000)
	clients.append(host)
	for i in range(1, n):
		var c := _client("친구%d" % i, port, NetProtocol.MODE_JOIN, host.room_code)
		await wait_until(func(): return c.is_joined(), 8000)
		c.set_ready(true)
		clients.append(c)
	await wait_until(func(): return host.lobby.get("can_start", false), 5000)
	host.request_start()
	await wait_until(func(): return clients.all(func(c): return c.in_game and _own_lane(c)), 8000)
	var room: NetServer = server.hub.room_for(host.room_code)
	# 서버 판의 골드를 넉넉히 (타워를 지을 수 있게)
	for lane in room.field.lanes.values():
		lane.gold = 1000.0
	return {"server": server, "hub": server.hub, "room": room, "clients": clients}


func _free(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await frames(4)


## 연결을 얼린다 (비행기 모드처럼: 보내지도 받지도 않는다. 소켓은 그대로)
func _freeze(c: NetClient) -> void:
	c.set_process(false)


func _identity_and_lobby_units() -> void:
	print("[0] 토큰/방장 순서 단위")
	var t := Identity.new_token()
	check(Identity.valid_token(t) and t.length() == Identity.TOKEN_HEX_LENGTH, "토큰은 128비트(16진수 32글자)")
	check(Identity.new_token() != t, "토큰은 매번 다르다")
	var h := Identity.hash_of(t)
	check(h != t and Identity.authorize(h, t) and not Identity.authorize(h, Identity.new_token()), "해시로 주인을 확인하고, 다른 토큰은 거부")
	check(not Identity.authorize("", t) and not Identity.authorize(h, "") and not Identity.authorize(h, 5) and not Identity.valid_token("zz" + t.substr(2)), "빈 해시/빈 토큰/모양이 틀린 토큰은 주인이 아니다")
	var lobby := Lobby.new()
	lobby.join(5, "a")
	lobby.join(9, "b")
	lobby.join(7, "c")
	check(lobby.lanes_in_join_order() == [0, 1, 2], "입장 순서의 레인 목록 (방장 승계 순서)")
	var hello := NetProtocol.make_hello("x", NetProtocol.MODE_JOIN, "ABCDEF", t)
	check(hello["token"] == t and not NetProtocol.make_hello("x").has("token"), "hello에 토큰이 실린다 (없으면 필드 없음)")
	check(NetProtocol.PROTOCOL_VERSION == 4, "프로토콜 버전 4 (재접속)")


func _heartbeat_and_away() -> void:
	print("[1] 끊김 감지: 하트비트")
	var g := await _game(PORT, 2)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	var seen := []
	a.presence_changed.connect(func(note): seen.append(note))
	await wait_seconds(HEARTBEAT * 2.5)
	check(a.is_joined() and b.is_joined() and not room.is_away(0) and not room.is_away(1), "정상 연결은 ping을 보내서 하트비트 시간(%.0f초)이 지나도 끊기지 않는다" % HEARTBEAT)
	var tick0: int = room._tick
	_freeze(b)
	check(await wait_until(func(): return room.is_away(1), 6000), "B가 조용해지면 서버가 끊김으로 본다")
	check(not room.is_away(0) and room.alive_count() == 2, "A는 정상이고, 끊긴 B도 방에 남은 사람으로 센다 (방이 닫히지 않는다)")
	check(await wait_until(func(): return a.away == [1], 3000), "다른 사람(A)에게 끊긴 사람이 알려진다 (presence away=[1])")
	check(seen.any(func(n): return n.get("kind") == "away" and n.get("lane") == 1), "끊김 알림(note)이 왔다")
	check(room._tick > tick0 and room.field.bus.started and not get_tree().paused, "끊긴 동안에도 서버는 돈다 (틱이 늘고 일시정지 없음)")
	check(room.field.lanes[1].active, "끊긴 B의 레인은 유예 동안 그대로 살아 있다")
	await _free([a, b, g.server])


func _reconnect_state() -> void:
	print("[2] 유예 안 재접속: 같은 레인, 정확한 상태")
	var g := await _game(PORT + 1, 2)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	# B가 타워를 짓고 골드를 쓴다
	var cell := Vector2i(5, 10)
	var res := {}
	b.command_result.connect(func(seq, ok, reason, _e): res[seq] = [ok, reason])
	var seq := b.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": Balance.TOWER_KINDS[0], "confirmed": true})
	await wait_until(func(): return res.has(seq), 5000)
	check(res.get(seq, [false, ""])[0] and room.field.lanes[1].tower_at(cell) != null, "끊기기 전: B의 타워가 서버에 있다 (%s)" % [res.get(seq)])
	await wait_until(func(): return b.snapshot.get("lanes", {}).get("1", {}).get("towers", []).size() == 1, 3000)
	var token := b.token
	var ids_before := [room._slots[1]]
	b.snapshot["stale_marker"] = true   # 로컬에 남은 옛 상태: 재접속하면 버려져야 한다
	var came_back := {"n": 0}
	b.reconnected.connect(func(): came_back["n"] += 1)
	var lost := {"n": 0}
	b.link_lost.connect(func(): lost["n"] += 1)
	var gold_at_drop: float = room.field.lanes[1].gold
	var boss_time0: float = room.field.boss.time_left
	b.peer.close()  # 연결이 갑자기 사라졌다 (B 쪽 소켓을 닫는다. 앱은 그대로)
	check(await wait_until(func(): return lost.n == 1, 3000), "B의 클라이언트가 끊김을 알고 자동 재접속을 시작한다 (link_lost)")
	check(await wait_until(func(): return came_back.n == 1, 8000), "자동으로 다시 접속해서 같은 레인으로 복귀했다 (reconnected)")
	check(b.player_id == 1 and b.resumed and b.token == token and not b.reconnecting, "같은 레인(1)이고 같은 토큰이다")
	check(room._slots[1] != ids_before[0] and not room.is_away(1) and room.alive_count() == 2, "서버는 새 연결을 같은 자리에 붙였다 (끊김 해제)")
	check(await wait_until(func(): return b.snapshot.has("lanes") and not b.snapshot.has("stale_marker") and _own_lane(b), 5000), "옛 로컬 상태는 버려지고 서버 키프레임으로 다시 만들어졌다")
	await wait_seconds(0.4)
	var sl: Dictionary = b.snapshot.lanes["1"]
	var server_lane: LaneController = room.field.lanes[1]
	check(sl.towers.size() == 1 and server_lane.tower_at(cell) != null, "타워가 그대로다")
	check(absf(float(sl.gold) - server_lane.gold) < 2.0 and sl.gold >= gold_at_drop - 0.01, "골드가 서버와 맞다 (돌아온 값 %.2f / 서버 %.2f)" % [sl.gold, server_lane.gold])
	var snap_boss: Dictionary = b.snapshot.boss
	check(absf(float(snap_boss.time_left) - room.field.boss.time_left) < 1.5 and room.field.boss.time_left < boss_time0, "남은 시간이 서버와 맞고, 끊긴 사이에도 흘렀다 (%.1f / %.1f)" % [snap_boss.time_left, room.field.boss.time_left])
	check(absf(float(snap_boss.hp) - room.field.boss.hp) <= maxf(1.0, room.field.boss.max_hp * 0.01), "보스 체력이 서버와 맞다")
	await wait_until(func(): return a.away.is_empty(), 3000)
	check(a.away.is_empty() and a.left.is_empty(), "A 화면의 끊김 표시도 사라졌다")
	var res2 := {}
	b.command_result.connect(func(seq2, ok, reason, _e): res2[seq2] = [ok, reason])
	var s2 := b.send(Command.SELL_TOWER, {"cell": cell})
	await wait_until(func(): return res2.has(s2), 5000)
	check(res2.get(s2, [false])[0] and room.field.lanes[1].tower_at(cell) == null, "돌아온 뒤 명령이 정상적으로 실행된다")
	await _free([a, b, g.server])


func _old_commands() -> void:
	print("[3] 끊긴 동안/대체된 연결의 옛 명령은 실행되지 않는다")
	var g := await _game(PORT + 2, 2)
	var room: NetServer = g.room
	var b: NetClient = g.clients[1]
	var cell := Vector2i(6, 11)
	var gold0: float = room.field.lanes[1].gold
	var old_id: int = room._slots[1]
	_freeze(b)  # 앱이 얼었다: 서버는 하트비트로 B를 끊는데, B는 아직 그 사실을 모른다
	check(await wait_until(func(): return room.is_away(1), 6000), "B가 끊김으로 처리됐다")
	var queued := b.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": Balance.TOWER_KINDS[0], "confirmed": true})
	check(queued > 0 and b.is_joined(), "(전제) B는 아직 연결된 줄 알고 끊긴 연결로 명령을 보냈다 (서버에는 닿지 않는다)")
	_freeze_off(b)
	check(await wait_until(func(): return b.resumed and room._slots.get(1, old_id) != old_id and not room.is_away(1), 10000), "B가 돌아왔다")
	await wait_seconds(0.5)
	check(room.field.lanes[1].tower_at(cell) == null and room.field.lanes[1].towers.is_empty(), "끊긴 동안 쌓인 명령은 복귀 뒤에도 실행되지 않았다")
	check(room.field.lanes[1].gold >= gold0, "골드도 안 빠졌다 (%.2f -> %.2f)" % [gold0, room.field.lanes[1].gold])
	# 옛 연결 번호로 오는 늦은 명령 (서버가 이미 정리한 연결)
	room.receive(old_id, {"t": NetProtocol.MSG_CMD, "seq": 99, "cmd": Command.to_wire(Command.make(Command.BUILD_TOWER, 1, {"cell": cell, "kind_id": Balance.TOWER_KINDS[0], "confirmed": true}))})
	await wait_seconds(0.2)
	check(room.field.lanes[1].tower_at(cell) == null, "정리된 옛 연결에서 늦게 온 명령도 무시된다")
	await _free([b, g.clients[0], g.server])


func _freeze_off(c: NetClient) -> void:
	c.set_process(true)


func _grace_expiry() -> void:
	print("[4] 유예가 지나면 이탈 (#22 탈락과 같다)")
	var g := await _game(PORT + 3, 3)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	var c: NetClient = g.clients[2]
	var boss: BossController = room.field.boss
	boss.spawn_player_monster(1, Monsters.DATA.keys()[0])
	var owned := func() -> int:
		return boss.get_sent_monsters().filter(func(m): return is_instance_valid(m) and m.owner_id == 1).size()
	check(owned.call() > 0, "(전제) B가 보스 레인에 보낸 몬스터가 있다 (%d마리)" % owned.call())
	_freeze(b)
	check(await wait_until(func(): return room.is_away(1), 6000), "B가 끊겼다")
	await wait_seconds(GRACE * 0.5)
	check(room.is_away(1) and room.field.lanes[1].active and owned.call() > 0, "유예 중에는 레인이 살아 있고 B의 몬스터가 보스 앞에 남아 있다")
	var notes := []
	a.presence_changed.connect(func(n): notes.append(n))
	check(await wait_until(func(): return room.has_left(1), GRACE * 1000 + 4000), "유예가 지나면 이탈로 처리된다")
	check(not room.field.lanes[1].active and owned.call() == 0, "B의 레인이 탈락(무너짐)하고 그 사람 몬스터가 철수했다")
	check(room.alive_count() == 2 and boss.state == BossController.State.RUNNING, "다른 두 명이 남아 판이 이어진다")
	check(await wait_until(func(): return a.left == [1] and a.away.is_empty(), 3000), "다른 사람 화면에 이탈이 알려진다 (left=[1])")
	check(notes.any(func(n): return n.get("kind") == "left" and n.get("lane") == 1), "이탈 알림(note)이 왔다")
	var fails := []
	b.reconnect_failed.connect(func(reason): fails.append(reason))
	_freeze_off(b)
	b.peer.close()
	check(await wait_until(func(): return not fails.is_empty(), 8000), "이탈한 뒤 돌아오려 하면 거부된다")
	check(fails[0] == NetProtocol.REJECT_LEFT and MainMenu.reconnect_fail_text(fails[0]).contains("이탈"), "사유는 seat_released이고 이탈 안내가 나온다 (%s)" % [fails])
	# 남은 사람이 모두 이탈하면 전체 패배 (#22)
	_freeze(a)
	_freeze(c)
	check(await wait_until(func(): return boss.state == BossController.State.DEFEAT, GRACE * 1000 + 8000), "모두 이탈하면 판이 끝난다 (전체 패배)")
	check(await wait_until(func(): return room.alive_count() == 0, 3000), "아무도 남지 않으면 방은 비었다")
	await _free([a, b, c, g.server])


func _app_background() -> void:
	print("[5] 앱 백그라운드: 복귀하면 바로 재접속, 서버는 멈추지 않는다")
	# 서버 하트비트를 길게 둬서 서버는 B가 끊긴 줄 모른다: 앱 복귀 쪽 감지만 확인한다
	var g := await _game(PORT + 4, 2, GRACE, 30.0)
	var room: NetServer = g.room
	var b: NetClient = g.clients[1]
	var old_id: int = room._slots[1]
	var tick0: int = room._tick
	var time0: float = room.field.boss.time_left
	_freeze(b)  # 앱이 백그라운드로 가서 멈췄다
	await wait_seconds(NetProtocol.RESUME_STALE_MS / 1000.0 + 0.6)
	check(room._tick > tick0 and room.field.boss.time_left < time0 and not room.is_away(1), "그동안 서버는 멈추지 않았고, B는 아직 끊김으로 안 보였다 (틱 +%d)" % (room._tick - tick0))
	var came := {"n": 0}
	b.reconnected.connect(func(): came["n"] += 1)
	_freeze_off(b)
	b.on_app_resumed()  # 앱 복귀
	check(await wait_until(func(): return came.n == 1, 8000), "앱이 돌아오면 바로 다시 접속해서 같은 레인으로 복귀한다")
	check(room._slots[1] != old_id and b.player_id == 1 and not room.is_away(1) and room.joined_count() == 2, "옛 연결은 새 연결로 대체됐다 (자리는 하나)")
	check(await wait_until(func(): return _own_lane(b), 5000), "전체 스냅샷을 다시 받았다")
	# 정상 연결에서 앱 복귀는 아무 일도 안 한다
	var n_before: int = came.n
	b.on_app_resumed()
	await wait_seconds(0.5)
	check(came.n == n_before and b.is_joined(), "연결이 멀쩡하면 앱 복귀는 재접속하지 않는다")
	# 온라인 MainGame은 백그라운드로 가도 멈추지 않는다
	var main := MainGame.create_online(b)
	get_tree().root.add_child.call_deferred(main)
	await wait_until(func(): return main.is_inside_tree() and main.game_field.map_view != null, 5000)
	main._notification(MainGame.NOTIFICATION_APPLICATION_PAUSED)
	main._notification(MainGame.NOTIFICATION_WM_WINDOW_FOCUS_OUT)
	check(not get_tree().paused and main.online, "온라인 판은 앱이 백그라운드로 가도 일시정지하지 않는다")
	await _free([main, b, g.clients[0], g.server])


func _host_and_leave() -> void:
	print("[6] 방장 이탈 / 의도적 이탈")
	var g := await _game(PORT + 5, 3)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	var c: NetClient = g.clients[2]
	check(room.host_lane == 0 and b.host_lane == 0, "시작 직후 방장은 레인 0 (방을 만든 사람)")
	var notes := []
	b.presence_changed.connect(func(n): notes.append(n))
	var t0 := Time.get_ticks_msec()
	a.leave()  # 방장이 [나가기]
	check(await wait_until(func(): return room.has_left(0), 3000), "나가기는 유예 없이 바로 이탈이다")
	check(Time.get_ticks_msec() - t0 < GRACE * 1000.0 - 500.0 and not room.is_away(0), "유예(%.0f초)를 기다리지 않았다" % GRACE)
	check(not room.field.lanes[0].active, "나간 사람의 레인이 탈락했다")
	check(room.host_lane == 1 and await wait_until(func(): return b.host_lane == 1 and c.host_lane == 1, 3000), "방장이 입장 순서상 다음 사람(레인 1)으로 바뀌었다")
	check(notes.any(func(n): return n.get("kind") == "host" and n.get("lane") == 1), "방장 변경 알림(note)이 왔다")
	check(g.hub.room_for(room.room_code) == room and room.alive_count() == 2 and room.field.boss.state == BossController.State.RUNNING, "방이 유지되고 판이 이어진다")
	# 나간 사람이 같은 토큰으로 돌아오려 해도 이미 이탈이다
	var back := NetClient.new()
	back.player_name = "방장"
	back.join_mode = NetProtocol.MODE_JOIN
	back.join_code = room.room_code
	back.token = a.token
	add_child(back)
	back.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT + 5)
	check(await wait_until(func(): return back.state == NetClient.State.REJECTED, 5000) and back.reject_reason == NetProtocol.REJECT_LEFT, "나간 사람은 다시 못 들어온다 (seat_released)")
	# 방장(레인 1)도 끊겼다가 유예가 지나면 다음 사람(레인 2)에게
	_freeze(b)
	check(await wait_until(func(): return room.has_left(1), GRACE * 1000 + 6000), "다음 방장도 유예가 지나면 이탈한다")
	check(room.host_lane == 2 and await wait_until(func(): return c.host_lane == 2, 3000), "방장이 레인 2로 바뀌었다")
	await _free([a, b, c, back, g.server])


func _seat_hijack() -> void:
	print("[7] 남이 같은 닉네임으로 자리를 가로챌 수 없다")
	var g := await _game(PORT + 6, 2)
	var room: NetServer = g.room
	var b: NetClient = g.clients[1]
	check(room._seats[1].hash != b.token and Identity.authorize(room._seats[1].hash, b.token), "서버는 토큰 원문이 아니라 해시만 갖고 있다")
	_freeze(b)
	check(await wait_until(func(): return room.is_away(1), 6000), "B가 끊겼다 (자리는 유예 중)")
	var thief := NetClient.new()
	thief.player_name = b.my_name  # 같은 닉네임
	thief.join_mode = NetProtocol.MODE_JOIN
	thief.join_code = room.room_code
	add_child(thief)
	thief.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT + 6)
	check(await wait_until(func(): return thief.state == NetClient.State.REJECTED, 5000) and thief.reject_reason == NetProtocol.REJECT_STARTED, "닉네임만 같고 토큰이 다르면 들어오지 못한다 (already_started)")
	var thief2 := NetClient.new()
	thief2.player_name = b.my_name
	thief2.join_mode = NetProtocol.MODE_JOIN
	thief2.join_code = room.room_code
	thief2.token = Identity.new_token()  # 틀린 토큰
	add_child(thief2)
	thief2.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT + 6)
	check(await wait_until(func(): return thief2.state == NetClient.State.REJECTED, 5000) and thief2.reject_reason == NetProtocol.REJECT_STARTED, "틀린 토큰으로도 못 들어온다")
	check(room.is_away(1) and room._slots.get(1, -1) == -1, "자리는 그대로 B의 것이다")
	# 진짜 주인(토큰)은 닉네임이 달라도 돌아온다
	var owner := NetClient.new()
	owner.player_name = "다른닉"
	owner.join_mode = NetProtocol.MODE_JOIN
	owner.join_code = room.room_code
	owner.token = b.token
	add_child(owner)
	owner.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT + 6)
	check(await wait_until(func(): return owner.is_joined() and owner.resumed, 8000) and owner.player_id == 1, "토큰의 주인은 같은 레인(1)으로 돌아온다")
	check(owner.my_name == room._seats[1].name and not room.is_away(1), "닉네임은 자리의 것을 그대로 쓴다")
	await _free([owner, thief, thief2, b, g.clients[0], g.server])


func _screens() -> void:
	print("[8] 화면: 재접속 오버레이, 배너, 돌아오지 못하면 메뉴로")
	var port := PORT + 7
	var server := await _server(port)
	var boot := (load("res://scenes/main/Boot.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(boot)
	await frames(3)
	var menu: MainMenu = boot.menu
	menu.profile_path = "user://test_reconnect.cfg"
	menu.server_edit.text = "127.0.0.1:%d" % port
	menu.name_edit.text = "방장"
	menu.create_button.pressed.emit()
	await wait_until(func(): return menu.lobby_screen != null, 8000)
	var code: String = menu.client.room_code
	var friend := _client("친구", port, NetProtocol.MODE_JOIN, code)
	await wait_until(func(): return friend.is_joined(), 8000)
	friend.set_ready(true)
	await wait_until(func(): return menu.client.lobby.get("can_start", false), 5000)
	menu.lobby_screen._start_button.pressed.emit()
	await wait_until(func(): return boot.online_game != null and boot.online_game.is_inside_tree() and boot.online_game.game_field.map_view != null, 8000)
	check(Identity.load_resume().get("room", "") == code and Identity.load_resume().get("token", "") == boot.online_client.token, "시작하면 앱 재시작 복귀용 (방, 토큰)이 기기에 저장된다")
	var game: MainGame = boot.online_game
	var client: NetClient = boot.online_client
	var room: NetServer = server.hub.room_for(code)
	await wait_until(func(): return friend.in_game and _own_lane(friend), 5000)
	check(game.reconnect_overlay != null and not game.reconnect_overlay.visible, "평소에는 재접속 오버레이가 없다")
	var shown := {"v": false}
	client.link_lost.connect(func(): shown["v"] = game.reconnect_overlay.visible)
	var back := {"n": 0}
	client.reconnected.connect(func(): back["n"] += 1)
	client.peer.close()  # 내 연결이 끊겼다
	check(await wait_until(func(): return back.n == 1, 8000), "자동으로 돌아왔다")
	check(shown.v, "끊긴 동안 \"재접속 중\" 오버레이가 떴다")
	check(not game.reconnect_overlay.visible and boot.online_game == game, "돌아오면 오버레이가 닫히고 같은 판 화면이다")
	check(game._banner_queue.any(func(i): return str(i.name).contains("다시 연결")) or game.skill_banner.visible, "돌아왔다는 안내가 뜬다")
	# 다른 사람의 끊김/이탈은 배너
	game._banner_queue.clear()
	friend.peer.close()
	friend.set_process(false)  # 친구는 다시 못 돌아온다
	check(await wait_until(func(): return client.away == [1], 6000), "친구가 끊기면 내 화면에 끊김 표시 정보가 온다")
	check(game._banner_queue.any(func(i): return str(i.name).contains("연결 끊김")) or str(game.skill_banner_title.text).contains("연결 끊김"), "친구의 끊김이 배너로 알려진다")
	check(await wait_until(func(): return client.left == [1], GRACE * 1000 + 5000), "유예가 지나면 이탈로 표시된다")
	check(game._banner_queue.any(func(i): return str(i.name).contains("이탈")) or str(game.skill_banner_title.text).contains("이탈"), "친구의 이탈이 배너로 알려진다")
	# 나는 이탈 처리된 뒤 돌아오려 하면: 메뉴로 + 안내
	room._leave_seat(0, "test")
	client.peer.close()
	check(await wait_until(func(): return boot.online_game == null and boot.menu != null, 8000), "유예가 지났거나 이탈 처리됐으면 재접속이 거부돼 메뉴로 돌아간다")
	check(boot.menu.status_label.text.contains("끝났"), "돌아갈 수 없다는 안내가 메뉴에 보인다 (둘 다 이탈해 판이 끝났다: %s)" % boot.menu.status_label.text)
	check(Identity.load_resume().is_empty(), "나가면 앱 재시작 복귀 정보는 지워진다")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_reconnect.cfg"))
	await _free([friend, boot, server])


func _menu_resume() -> void:
	print("[9] 앱이 꺼졌다 켜지면 메인 메뉴에서 같은 판으로 돌아간다")
	var port := PORT + 8
	var g := await _game(port, 2)
	var room: NetServer = g.room
	var b: NetClient = g.clients[1]
	var token := b.token
	var info := {"server": "127.0.0.1:%d" % port, "room": room.room_code, "token": token, "name": b.my_name}
	Identity.save_resume(info)
	# 앱이 죽었다: 소켓도 닫고 클라이언트 객체도 없다 (나가기 메시지 없이)
	b.close()
	b.queue_free()
	check(await wait_until(func(): return room.is_away(1), 6000), "앱이 죽으면 서버는 끊김(유예)으로 둔다")
	var menu := MainMenu.new()
	menu.profile_path = "user://test_reconnect.cfg"
	add_child(menu)
	await frames(3)
	check(menu.resume_button.visible and menu.resume_button.text.contains(room.room_code), "메뉴에 [진행 중인 판으로 돌아가기]가 보인다 (%s)" % menu.resume_button.text)
	var started := {"v": false}
	menu.online_started.connect(func(): started["v"] = true)
	menu.resume_button.pressed.emit()
	check(await wait_until(func(): return started.v, 8000), "누르면 대기방 없이 바로 게임으로 넘어간다 (online_started)")
	var client := menu.take_client()
	check(client != null and client.player_id == 1 and client.resumed and client.in_game and client.token == token, "같은 레인(1)과 같은 토큰으로 복귀했다")
	add_child(client)
	client.keep_open = false
	check(await wait_until(func(): return _own_lane(client), 5000) and not room.is_away(1), "전체 스냅샷을 받았고 끊김이 해제됐다")
	# 돌아갈 판이 없으면(끝남/이탈) 저장 정보가 지워지고 안내한다
	var menu2 := MainMenu.new()
	menu2.profile_path = "user://test_reconnect.cfg"
	add_child(menu2)
	await frames(3)
	room._leave_seat(1, "test")
	menu2.resume_button.pressed.emit()
	check(await wait_until(func(): return menu2.status_label.text.contains("이탈"), 8000), "이탈 처리된 판으로는 못 돌아가고 이유를 안내한다 (%s)" % menu2.status_label.text)
	check(Identity.load_resume().is_empty() and not menu2.resume_button.visible, "저장 정보가 지워지고 버튼이 사라진다")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_reconnect.cfg"))
	await _free([menu, menu2, client, g.clients[0], g.server])
