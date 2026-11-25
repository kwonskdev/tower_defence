extends "res://tests/case_base.gd"
## 이슈 #54: 판이 끝난 뒤의 연결 처리. 서버(방 코드 서버)에 클라이언트를 붙여 실제 소켓으로 확인한다. 체크리스트와 대응:
##  [1] 판이 끝난 뒤 한 명이 끊겨도 다른 사람 화면에 끊김/이탈 배너(presence)가 뜨지 않는다 / 끊겨 있던 사람의 끊김은 취소되고 이탈로 넘어가지 않는다
##  [2] 판이 끝난 방은 모두 나가면(끊겨서 유예 중인 사람이 있어도) 유예를 기다리지 않고 닫힌다
##  [3] 결과 화면 ping 규칙: 서버는 끝난 판에서 ping 유무와 상관없이 같게 동작한다 (조용한 연결도 끊지 않는다). 클라이언트는 ping을 계속 보낸다
##  [4] 끝난 판으로 돌아가려 하면 "판이 끝났다"(game_finished)로 거부되고 문구가 나온다 (자리 주인이 아닌 사람에게는 방이 있는지 알리지 않는다)

const PORT := 47360
const GRACE := 3.0
const HEARTBEAT := 1.0


func run() -> void:
	await _no_banners_after_finish()
	await _away_before_finish()
	await _closes_without_grace()
	await _ping_rule()
	await _return_to_finished()


func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _server(port: int, grace: float) -> ServerMain:
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	server.hub.reconnect_grace = grace
	server.hub.heartbeat_timeout = HEARTBEAT
	return server


func _client(player_name: String, port: int, mode: String, code := "") -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	cl.join_mode = mode
	cl.join_code = code
	cl.ping_interval = 0.3
	cl.reconnect_grace = GRACE + 4.0
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
	return cl


func _own_lane(cl: NetClient) -> bool:
	return cl.snapshot.get("lanes", {}).has(str(cl.player_id))


## 서버 + 2명이 시작한 판. {server, hub, room, clients}
func _game(port: int, grace := GRACE) -> Dictionary:
	var server := await _server(port, grace)
	var clients: Array = []
	var host := _client("방장", port, NetProtocol.MODE_CREATE)
	await wait_until(func(): return host.is_joined(), 8000)
	clients.append(host)
	var c := _client("친구", port, NetProtocol.MODE_JOIN, host.room_code)
	await wait_until(func(): return c.is_joined(), 8000)
	c.set_ready(true)
	clients.append(c)
	await wait_until(func(): return host.lobby.get("can_start", false), 5000)
	host.request_start()
	await wait_until(func(): return clients.all(func(x): return x.in_game and _own_lane(x)), 8000)
	return {"server": server, "hub": server.hub, "room": server.hub._rooms[host.room_code], "clients": clients}


func _free(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await frames(4)


## 판을 끝낸다 (전체 승리). 보스가 끝났다고 알리는 것과 같은 경로다.
func _finish(room: NetServer) -> void:
	room.field.boss.boss_defeated.emit()
	await frames(2)


func _no_banners_after_finish() -> void:
	print("[1] 판이 끝난 뒤 끊겨도 배너가 없다")
	var g := await _game(PORT)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	var seen := []
	a.presence_changed.connect(func(note): seen.append(note))
	var signals := []
	room.seat_away.connect(func(l): signals.append(l))
	room.seat_left.connect(func(l): signals.append(l))
	await _finish(room)
	check(room.finished and g.hub._finished_at.has(room.room_code), "(전제) 판이 끝났다고 서버가 알고 있다")
	b.set_process(false)  # B가 조용해진다 (결과 화면에서 앱이 멈춘 것과 같다)
	await wait_seconds(HEARTBEAT * 2.5)
	check(not room.is_away(1) and signals.is_empty(), "끝난 판에서는 조용한 B를 서버가 끊김으로 보지 않는다 (하트비트 정지)")
	check(room.joined_count() == 2, "B의 연결도 서버가 끊지 않는다")
	b.peer.close()  # B의 연결이 사라진다
	await wait_seconds(0.5)
	check(not room.is_away(1) and not room.has_left(1) and signals.is_empty(), "연결이 사라져도 끊김/이탈로 세지 않는다")
	await wait_seconds(GRACE + 1.0)
	check(not room.has_left(1) and a.away.is_empty() and a.left.is_empty(), "유예 시간이 지나도 이탈이 되지 않고 A의 화면(presence)에 끊김/이탈이 없다")
	check(not seen.any(func(n): return n.get("kind") in ["away", "left", "host"]), "끊김/이탈/방장 알림(note)이 오지 않았다 (%s)" % [seen])
	check(room.host_lane == 0, "방장 승계도 일어나지 않았다")
	await _free([a, b, g.server])


func _away_before_finish() -> void:
	print("[1b] 끊겨 유예 중이던 사람은 판이 끝나면 끊김이 취소된다")
	var g := await _game(PORT + 1, 30.0)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	b.set_process(false)
	check(await wait_until(func(): return room.is_away(1), 6000), "(전제) B가 끊겨 유예 중이다")
	check(await wait_until(func(): return a.away == [1], 3000), "(전제) A 화면에 끊김 배너 정보가 있다")
	await _finish(room)
	check(not room.is_away(1) and room.alive_count() == 1, "끝나면 B의 끊김은 취소되고 방에 남은 사람으로 세지 않는다 (alive %d)" % room.alive_count())
	check(await wait_until(func(): return a.away.is_empty(), 3000), "A 화면의 끊김 배너가 사라진다")
	room._tick_away(1000.0)
	check(not room.has_left(1), "유예 시간이 지나도 이탈로 넘어가지 않는다")
	await _free([a, b, g.server])


func _closes_without_grace() -> void:
	print("[2] 끝난 방은 접속자가 없으면 유예 없이 닫힌다")
	var g := await _game(PORT + 2, 60.0)
	var room: NetServer = g.room
	var hub: RoomHub = g.hub
	var code := room.room_code
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	b.set_process(false)
	check(await wait_until(func(): return room.is_away(1), 6000), "(전제) B가 끊겨 유예(60초) 중이다")
	await _finish(room)
	check(hub._rooms.has(code), "(전제) A가 접속 중이라 방은 열려 있다")
	a.leave()
	check(await wait_until(func(): return not hub._rooms.has(code), 8000), "A가 나가면 끊겨 있던 B의 유예(60초)를 기다리지 않고 방이 닫힌다")
	# 비교: 판이 끝나기 전이면 같은 상황에서 방이 유지된다 (유예 중인 사람이 있어서)
	var g2 := await _game(PORT + 3, 60.0)
	var room2: NetServer = g2.room
	g2.clients[1].set_process(false)
	check(await wait_until(func(): return room2.is_away(1), 6000), "(비교) 끝나지 않은 판에서 B가 끊겼다")
	g2.clients[0].leave()
	await wait_seconds(2.0)
	check(g2.hub._rooms.has(room2.room_code) and room2.alive_count() == 1, "(비교) 끝나지 않은 판은 유예 중인 B 때문에 방이 유지된다")
	await _free([a, b, g.server, g2.clients[0], g2.clients[1], g2.server])


func _ping_rule() -> void:
	print("[3] 결과 화면 ping 규칙: 서버는 ping 유무와 무관하다, 클라이언트는 계속 보낸다")
	var g := await _game(PORT + 4)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	await _finish(room)
	var n0: int = a._next_ping
	await wait_seconds(1.0)
	check(a._next_ping > n0 and a.is_joined(), "판이 끝나도 클라이언트는 ping을 계속 보낸다 (ping %d -> %d)" % [n0, a._next_ping])
	check(a.rtt_ms >= 0.0, "서버도 계속 pong으로 답한다 (rtt %.0fms)" % a.rtt_ms)
	await _free([a, g.clients[1], g.server])


func _return_to_finished() -> void:
	print("[4] 끝난 판으로 돌아가려 하면 판이 끝났다고 알려 준다")
	var g := await _game(PORT + 5)
	var room: NetServer = g.room
	var a: NetClient = g.clients[0]
	var b: NetClient = g.clients[1]
	var token := b.token
	await _finish(room)
	b.leave()
	b.queue_free()
	await wait_seconds(0.5)
	var back := _client("친구", PORT + 5, NetProtocol.MODE_JOIN, room.room_code)
	back.token = token
	check(await wait_until(func(): return back.state == NetClient.State.REJECTED, 6000), "자리 주인이 끝난 판으로 돌아가려 하면 거부된다")
	check(back.reject_reason == NetProtocol.REJECT_FINISHED, "사유는 game_finished다 (%s)" % back.reject_reason)
	check(MainMenu.reconnect_fail_text(back.reject_reason).contains("끝났") and MainMenu.reject_text(back.reject_reason).contains("끝났"), "화면 문구에 판이 끝났다고 나온다 (%s)" % MainMenu.reconnect_fail_text(back.reject_reason))
	var stranger := _client("낯선이", PORT + 5, NetProtocol.MODE_JOIN, room.room_code)
	check(await wait_until(func(): return stranger.state == NetClient.State.REJECTED, 6000) and stranger.reject_reason == NetProtocol.REJECT_NO_ROOM, "자리 주인이 아닌 사람에게는 끝난 방이 없는 방처럼 보인다 (%s)" % stranger.reject_reason)
	await _free([a, back, stranger, g.server])
