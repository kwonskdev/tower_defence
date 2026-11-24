extends "res://tests/case_base.gd"
## 이슈 #20: 헤드리스 서버 1개 + 클라이언트 2개가 실제 소켓(루프백)으로 접속해 명령을 주고받고 서로의 타워를 본다.
## 전송 계층(WebSocket 기본 / wss(TLS) / ENet)을 같은 시나리오로 돌린다. 한 프로세스 안이지만 서버와 클라이언트는 각자 피어(소켓)를 가진다.
##  - 프로토콜 버전이 다르면 거부되고 자리를 차지하지 않는다 / 자리가 없으면 room_full
##  - 서버는 연결마다 플레이어 번호를 정하고, 다른 플레이어를 사칭한 명령은 실행하지 않는다
##  - 클라이언트는 자기 레인 + 보고 있는 레인 + 보스 HUD만 키프레임+변경분으로 받고, 나머지는 1Hz 요약으로 받는다
##  - 보는 레인을 바꾸면 키프레임이 오고, 보스 레인의 몬스터는 보스 레인을 볼 때만 온다
##  - 외부 전송(Steam 중계 같은)을 register()로 붙일 수 있다
##  - 받은 스냅샷만으로 MapView가 상대의 타워를 그린다
## (폰 실기기 접속과 지연/손실은 이 테스트가 보지 않는다: #28)

const PORTS := {"ws": 47211, "wss": 47212, "enet": 47210, "custom": 47213}


func run() -> void:
	check(NetTransport.DEFAULT == NetTransport.WEBSOCKET, "기본 전송 계층은 WebSocket")
	await _scenario("ws", NetTransport.WEBSOCKET, false)
	await _scenario("wss", NetTransport.WEBSOCKET, true)
	await _scenario("enet", NetTransport.ENET, false)
	await _custom_transport()
	_codec_checks()


func _client(_server: Node, player_name: String) -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	add_child(cl)
	return cl


func _scenario(label: String, kind: String, secure: bool) -> void:
	print("[전송 계층: %s]" % label)
	var port: int = PORTS[label]
	var server_tls: TLSOptions = null
	var ctls: TLSOptions = null
	if secure:  # 자체 서명 인증서를 만들어 서버는 그 인증서로 열고, 클라이언트는 그것만 믿는다
		var crypto := Crypto.new()
		var key := crypto.generate_rsa(2048)
		var cert := crypto.generate_self_signed_certificate(key, "CN=localhost")
		server_tls = TLSOptions.server(key, cert)
		ctls = TLSOptions.client(cert, "localhost")
		# --tls-cert/--tls-key 인자가 쓰는 파일 읽기 경로도 같은 인증서로 확인한다
		var cert_path := "user://test_net_tls.crt"
		var key_path := "user://test_net_tls.key"
		check(cert.save(cert_path) == OK and key.save(key_path) == OK, "(준비) 인증서/키를 파일로 저장")
		check(ServerMain.load_tls(cert_path, key_path) != null, "인증서/키 파일로 서버 TLS 설정을 만든다")
		check(ServerMain.load_tls("user://없는파일.crt", key_path) == null, "파일이 없으면 null")
		DirAccess.remove_absolute(ProjectSettings.globalize_path(cert_path))
		DirAccess.remove_absolute(ProjectSettings.globalize_path(key_path))
	var server := ServerMain.new()
	server.session.participants = [0, 1]
	server.session.rng.seed = 11
	server.net_port = port
	server.net_transport = kind
	server.net_tls = server_tls
	get_tree().root.add_child.call_deferred(server)
	await frames(8)
	var net: NetServer = server.net
	check(net != null and net.peer != null, "서버가 %s 포트 %d를 열었다" % [label, port])
	if net == null or net.peer == null:
		server.queue_free()
		await frames(2)
		return
	net.hello_timeout = 0.5
	check(not server.field.bus.started, "네트워크 서버는 클라이언트가 시작할 때까지 기다린다 (자동 시작 없음)")

	# 1) 프로토콜 버전이 다른 클라이언트는 거부되고 자리를 쓰지 않는다
	var old := _client(server, "old")
	old.proto_override = NetProtocol.PROTOCOL_VERSION + 1
	var reject_info := {}
	old.rejected.connect(func(reason, info): reject_info["reason"] = reason; reject_info["info"] = info)  # 람다는 바깥 변수를 값으로 잡으니 Dictionary를 고쳐 쓴다
	check(old.connect_to(kind, "127.0.0.1", port, ctls), "(버전이 다른 클라이언트) 접속 시작")
	var got_reject := await wait_until(func(): return not reject_info.is_empty(), 8000)
	check(got_reject and reject_info.reason == NetProtocol.REJECT_PROTOCOL, "버전이 다르면 protocol_mismatch로 거부된다 (%s)" % [reject_info.get("reason")])
	check(got_reject and reject_info.info.proto == NetProtocol.PROTOCOL_VERSION and reject_info.info.snapshot == Snapshot.VERSION, "거부 메시지에 서버 버전이 담긴다 (클라이언트가 업데이트 안내를 고른다)")
	check(old.state == NetClient.State.REJECTED and old.player_id < 0, "거부된 클라이언트는 입장하지 못했다")
	await frames(10)
	check(net.joined_count() == 0, "거부된 연결은 자리를 차지하지 않았다")

	# 2) 말을 안 하는 연결은 시간이 지나면 끊긴다 (hello를 안 보냄)
	var silent := _client(server, "silent")
	silent.hello_disabled = true
	check(silent.connect_to(kind, "127.0.0.1", port, ctls), "(말 없는 연결) 접속 시작")
	var dropped := await wait_until(func(): return silent.state == NetClient.State.CLOSED, 8000)
	check(dropped, "hello를 안 보낸 연결은 서버가 끊는다")

	# 3) 정상 클라이언트 둘이 들어온다
	var a := _client(server, "alice")
	var b := _client(server, "bob")
	check(a.connect_to(kind, "127.0.0.1", port, ctls), "클라이언트 A 접속 시작")
	var a_in := await wait_until(func(): return a.is_joined(), 8000)
	check(b.connect_to(kind, "127.0.0.1", port, ctls), "클라이언트 B 접속 시작")
	var b_in := await wait_until(func(): return b.is_joined(), 8000)
	check(a_in and b_in, "두 클라이언트가 입장했다")
	check(a.player_id == 0 and b.player_id == 1, "서버가 플레이어 번호를 정해 준다 (A=%d, B=%d)" % [a.player_id, b.player_id])
	check(a.players.size() == 2, "입장 메시지에 참여자 목록이 있다 %s" % [a.players])

	# 4) 자리가 없으면 거부
	var c := _client(server, "carol")
	var full := {}
	c.rejected.connect(func(reason, _info): full["reason"] = reason)
	c.connect_to(kind, "127.0.0.1", port, ctls)
	await wait_until(func(): return not full.is_empty(), 8000)
	check(full.get("reason", "") == NetProtocol.REJECT_FULL, "자리가 없으면 room_full (%s)" % [full.get("reason")])
	check(net.joined_count() == 2, "기존 두 명은 그대로다")

	# 5) 시작 명령과 타워 건설 명령을 주고받는다
	var results := {}
	a.command_result.connect(func(seq, ok, reason, _ev): results["a%d" % seq] = [ok, reason])
	b.command_result.connect(func(seq, ok, reason, _ev): results["b%d" % seq] = [ok, reason])
	var s0 := a.send(Command.START_GAME)
	await wait_until(func(): return results.has("a%d" % s0), 5000)
	check(results.get("a%d" % s0, [false, ""])[0] and server.field.bus.started, "A의 시작 명령이 서버에서 실행됐다 (%s)" % [results.get("a%d" % s0)])
	var lane_a: LaneController = server.field.lanes[0]
	var lane_b: LaneController = server.field.lanes[1]
	var gold_a := lane_a.gold
	var sa := a.send(Command.BUILD_TOWER, {"cell": Vector2i(5, 10), "kind_id": "long", "confirmed": false})
	var sb := b.send(Command.BUILD_TOWER, {"cell": Vector2i(7, 12), "kind_id": "long", "confirmed": false})
	await wait_until(func(): return results.has("a%d" % sa) and results.has("b%d" % sb), 5000)
	check(results.get("a%d" % sa, [false])[0] and results.get("b%d" % sb, [false])[0], "A와 B의 타워 건설 명령이 성공했다 (%s / %s)" % [results.get("a%d" % sa), results.get("b%d" % sb)])
	check(lane_a.tower_at(Vector2i(5, 10)) != null and lane_b.tower_at(Vector2i(7, 12)) != null, "서버 시뮬레이션에 두 타워가 생겼다 (각자 자기 레인)")
	check(lane_a.tower_at(Vector2i(7, 12)) == null and lane_b.tower_at(Vector2i(5, 10)) == null, "남의 레인에는 생기지 않았다")
	check(lane_a.gold < gold_a, "서버가 골드를 차감했다 (%.1f -> %.1f)" % [gold_a, lane_a.gold])

	# 6) 사칭/잘못된 명령은 실행되지 않는다
	var tower_n := lane_b.towers.size()
	var gold_b := lane_b.gold
	var forged := Command.make(Command.BUILD_TOWER, 1, {"cell": Vector2i(9, 14), "kind_id": "long", "confirmed": false})  # A(0번)가 1번인 척
	a._send({"t": NetProtocol.MSG_CMD, "seq": 900, "cmd": Command.to_wire(forged)})
	a._send({"t": NetProtocol.MSG_CMD, "seq": 901, "cmd": "not json"})
	await wait_until(func(): return results.has("a900") and results.has("a901"), 5000)
	check(results.get("a900", [true, ""]) == [false, "not_your_player"], "다른 플레이어를 사칭한 명령은 거절된다 (%s)" % [results.get("a900")])
	check(results.get("a901", [true, ""]) == [false, "bad_command"], "깨진 명령은 bad_command (%s)" % [results.get("a901")])
	check(lane_b.towers.size() == tower_n and is_equal_approx(lane_b.gold, gold_b), "사칭 명령은 B의 레인을 바꾸지 않았다")

	# 7) 스냅샷: 자기 레인 + 보스 레인은 자세히, 남의 레인은 요약. 보는 레인을 바꾸면 자세히 온다
	await wait_until(func(): return a.snapshot_count > 3 and b.snapshot_count > 3 and not a.summary.is_empty() and not b.summary.is_empty(), 8000)
	var sn_a: Dictionary = a.snapshot
	check(sn_a.lanes.has("0") and not sn_a.lanes.has("1"), "A는 자기 레인만 자세히 받는다 (레인 %s)" % [sn_a.lanes.keys()])
	var own_towers: Array = sn_a.lanes["0"].towers
	check(own_towers.size() == 1 and int(own_towers[0].cell[0]) == 5 and int(own_towers[0].cell[1]) == 10, "A의 스냅샷에 자기 타워(5,10)가 있다")
	check(not sn_a.boss.is_empty() and sn_a.boss.monsters.is_empty() and sn_a.boss.has("hp"), "보스 레인을 안 보면 보스 몬스터 목록은 비어서 온다 (HUD용 보스 상태는 온다)")
	var sum_b: Array = a.summary.get("1", {}).get("towers", [])
	check(sum_b.size() == 1 and int(sum_b[0][0]) == 7 and int(sum_b[0][1]) == 12, "A는 B 레인의 타워 칸을 요약으로 받는다 (미니맵) %s" % [sum_b])
	check(a.snapshot_count > 0 and a.last_tick > 0, "스냅샷이 틱 번호와 함께 온다 (틱 %d)" % a.last_tick)
	# 변경분이 키프레임 위에 쌓여서 서버와 같은 상태가 된다 (보스 남은 시간이 흘러 서버 값과 맞는다)
	var t_before: float = a.snapshot.boss.time_left
	await wait_until(func(): return a.snapshot.boss.time_left < t_before - 0.5, 6000)
	check(a.snapshot.boss.time_left < t_before and absf(a.snapshot.boss.time_left - server.field.boss.time_left) < 1.0, "변경분이 적용되어 보스 남은 시간이 서버와 맞는다 (%.1f -> %.1f, 서버 %.1f)" % [t_before, a.snapshot.boss.time_left, server.field.boss.time_left])
	check(absf(a.snapshot.lanes["0"].gold - lane_a.gold) < 5.0, "A가 받은 골드가 서버 값과 맞는다 (%.1f / %.1f)" % [a.snapshot.lanes["0"].gold, lane_a.gold])

	a.set_view(1)
	var saw := await wait_until(func(): return a.snapshot.get("lanes", {}).has("1"), 5000)
	check(saw, "A가 B의 레인을 보면 그 레인이 자세히 온다")
	var mine: Array = a.snapshot.lanes["1"].towers if saw else []
	check(mine.size() == 1 and int(mine[0].cell[0]) == 7 and int(mine[0].cell[1]) == 12 and mine[0].kind == "long", "A가 B의 타워(7,12 장거리)를 받았다")
	b.set_view(0)
	var saw2 := await wait_until(func(): return b.snapshot.get("lanes", {}).has("0"), 5000)
	check(saw2 and b.snapshot.lanes["0"].towers.size() == 1, "B도 A의 타워를 받았다")

	# 7b) 보스 레인의 몬스터는 보스 레인을 볼 때만 온다
	var sm1 := a.send(Command.SEND_MONSTER, {"kind_id": "rusher"})
	var sm2 := a.send(Command.SEND_MONSTER, {"kind_id": "rusher"})
	await wait_until(func(): return results.has("a%d" % sm1) and results.has("a%d" % sm2), 5000)
	check(results.get("a%d" % sm1, [false])[0] and results.get("a%d" % sm2, [false])[0], "A가 몬스터 2마리를 보스 레인으로 보냈다 (%s)" % [results.get("a%d" % sm1)])
	await frames(30)
	check(a.snapshot.boss.monsters.is_empty() and server.field.boss.get_sent_monsters().size() == 2, "보스 레인을 안 보면 서버에 몬스터가 있어도 목록은 비어서 온다")
	await wait_until(func(): return a.summary.get(str(GameField.BOSS_LANE_ID), {}).get("monsters", []).size() >= 1, 4000)  # 요약은 1Hz라서 조금 기다린다
	check(a.summary.has(str(GameField.BOSS_LANE_ID)) and a.summary[str(GameField.BOSS_LANE_ID)].monsters.size() >= 1, "대신 요약에 보스 레인 점이 있다 (%d개)" % a.summary.get(str(GameField.BOSS_LANE_ID), {}).get("monsters", []).size())
	a.set_view(GameField.BOSS_LANE_ID)
	var boss_seen := await wait_until(func(): return a.snapshot.boss.monsters.size() == 2, 5000)
	check(boss_seen, "보스 레인을 보면 키프레임으로 몬스터 2마리가 온다")
	var server_ids := server.field.boss.get_sent_monsters().map(func(m): return m.monster_id)
	var client_ids: Array = a.snapshot.boss.monsters.map(func(m): return int(m.id))
	server_ids.sort()
	client_ids.sort()
	check(server_ids == client_ids, "받은 몬스터 번호가 서버와 같다 %s" % [client_ids])
	await wait_until(func(): return a.snapshot.boss.monsters.size() == 2 and a.snapshot.boss.monsters.all(func(m): return m.stopped), 15000)
	var m0: Dictionary = a.snapshot.boss.monsters[0]
	var srv_m: Monster = server.field.boss.get_sent_monsters()[0] if m0.id == server.field.boss.get_sent_monsters()[0].monster_id else server.field.boss.get_sent_monsters()[1]
	check(absf(m0.pos[0] - srv_m.cell_pos.x) < 0.1 and absf(m0.pos[1] - srv_m.cell_pos.y) < 0.1, "변경분으로 움직임을 따라간 몬스터 위치가 서버와 맞는다 (%s / %s)" % [m0.pos, srv_m.cell_pos])
	a.set_view(1)
	var back := await wait_until(func(): return a.snapshot.boss.monsters.is_empty() and a.snapshot.lanes.has("1"), 5000)
	check(back, "다른 레인으로 옮기면 보스 몬스터 목록이 다시 비워진다 (키프레임)")

	# 8) 받은 스냅샷만으로 MapView가 서로의 타워를 그린다
	var holder := Node.new()
	get_tree().root.add_child(holder)
	var r := GridRenderer.new()
	holder.add_child(r)
	var mv := MapView.new(r)
	holder.add_child(mv)
	mv.sync(a.snapshot, 1, "")  # A의 화면: 보고 있는 레인 = B의 레인
	check(mv.tower_count() == 2, "A의 화면(MapView)이 받은 스냅샷으로 타워 2기를 그린다 (%d기)" % mv.tower_count())
	check(mv.tower_node(1, Vector2i(7, 12)) != null and mv.tower_node(1, Vector2i(7, 12)).visible, "A의 화면에 B의 타워가 보인다")
	holder.queue_free()

	# 9) 지연 측정과 연결 정리
	a.ping()
	await wait_until(func(): return a.rtt_ms >= 0.0, 3000)
	check(a.rtt_ms >= 0.0, "왕복 시간을 쟀다 (루프백 %.0fms)" % a.rtt_ms)
	var bytes: Dictionary = net.sent_bytes
	print("  서버가 보낸 바이트: ", bytes)
	check(int(bytes.get("snap", 0)) > 0, "스냅샷이 전송 바이트로 집계된다")
	b.close()
	var left := await wait_until(func(): return net.joined_count() == 1, 8000)
	check(left, "B가 나가면 서버가 자리를 비운다")
	for n in [old, silent, a, b, c, server]:
		if is_instance_valid(n):
			n.queue_free()
	await frames(4)


## 메시지 부호화: 깨진 입력은 빈 결과, 버전 확인은 값으로 비교
func _codec_checks() -> void:
	print("[메시지 부호화]")
	check(NetProtocol.decode("garbage".to_utf8_buffer()).is_empty(), "JSON이 아닌 바이트는 빈 메시지")
	check(NetProtocol.decode(PackedByteArray([0xff, 0xfe, 0x00])).is_empty(), "UTF-8이 아닌 바이트도 빈 메시지")
	check(NetProtocol.decode("[1,2]".to_utf8_buffer()).is_empty(), "객체가 아닌 JSON은 빈 메시지")
	check(NetProtocol.decode('{"x":1}'.to_utf8_buffer()).is_empty(), "t가 없으면 빈 메시지")
	var hello := NetProtocol.make_hello("x")
	check(NetProtocol.check_hello(NetProtocol.decode(NetProtocol.encode(hello))) == "", "정상 hello는 JSON을 거쳐도 통과한다")
	var bad := hello.duplicate()
	bad["snapshot"] = Snapshot.VERSION + 1
	check(NetProtocol.check_hello(bad) == NetProtocol.REJECT_PROTOCOL, "스냅샷 버전만 달라도 거부")
	bad = hello.duplicate()
	bad["proto"] = "1"
	check(NetProtocol.check_hello(bad) == NetProtocol.REJECT_BAD_HELLO, "버전이 숫자가 아니면 bad_hello")
	bad = hello.duplicate()
	bad["proto"] = NetProtocol.PROTOCOL_VERSION + 0.5
	check(NetProtocol.check_hello(bad) == NetProtocol.REJECT_BAD_HELLO, "버전이 정수가 아니면(1.5) 잘라서 통과시키지 않는다")
	check(NetProtocol.check_hello({"t": "cmd"}) == NetProtocol.REJECT_BAD_HELLO, "첫 메시지가 hello가 아니면 bad_hello")
	check(not NetTransport.is_known("udp") and NetTransport.create_server("udp", 1) == null, "모르는 전송 계층은 열지 않는다")


## 외부 전송을 register()로 붙여도 NetServer/NetClient가 그대로 돈다 (여기서는 WebSocket을 이름만 바꿔 등록한다. Steam 중계 같은 것도 같은 자리에 붙는다)
func _custom_transport() -> void:
	print("[외부 전송 등록]")
	var port: int = PORTS["custom"]
	NetTransport.register("custom", func(p: int):
		var peer := WebSocketMultiplayerPeer.new()
		return peer if peer.create_server(p) == OK else null,
		func(host: String, p: int):
			var peer := WebSocketMultiplayerPeer.new()
			return peer if peer.create_client("ws://%s:%d" % [host, p]) == OK else null)
	check(NetTransport.is_known("custom"), "등록한 전송은 알려진 전송이다")
	var server := ServerMain.new()
	server.session.participants = [0]
	server.net_port = port
	server.net_transport = "custom"
	get_tree().root.add_child.call_deferred(server)
	await frames(8)
	var cl := _client(server, "custom")
	check(cl.connect_to("custom", "127.0.0.1", port), "등록한 전송으로 접속을 시작했다")
	var in_ := await wait_until(func(): return cl.is_joined(), 8000)
	check(in_, "등록한 전송으로 입장했다 (NetServer/NetClient는 그대로)")
	NetTransport.unregister("custom")
	check(not NetTransport.is_known("custom"), "등록을 지우면 모르는 전송이 된다")
	cl.queue_free()
	server.queue_free()
	await frames(4)
