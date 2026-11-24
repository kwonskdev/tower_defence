extends "res://tests/case_base.gd"
## 이슈 #20 후속(PR #48 리뷰): 보스 레인에 몬스터가 수백~1000마리 쌓였을 때, 그 레인을 보는 클라이언트가 받는 키프레임 하나(수백 KB)가
## 실제 소켓(WebSocket / wss / ENet)으로 끝까지 전달되어 서버와 같은 몬스터 수가 되는가. JSON 글자 수가 아니라 실제 소켓으로 잰다.
## 엔진 기본 WebSocket 버퍼(약 64KB)로는 못 보낸다는 것도 보여 준다 (그래서 NetTransport.WS_BUFFER_BYTES를 키웠다).
## 몬스터 수는 인자 --monsters=N,N,... 로 바꿔 돌릴 수 있다 (기본 300,1000).

const PORTS := {"ws": 47220, "wss": 47221, "enet": 47222, "small": 47223}
const DEFAULT_COUNTS := "300,1000"
const ENGINE_DEFAULT_WS_BUFFER := 65535


func run() -> void:
	var counts: Array = []
	for t in ServerMain.arg_value("monsters", DEFAULT_COUNTS).split(","):
		counts.append(int(t))
	for n in counts:
		await _case("ws", NetTransport.WEBSOCKET, false, n)
		await _case("wss", NetTransport.WEBSOCKET, true, n)
		await _case("enet", NetTransport.ENET, false, n)
	# 엔진 기본 버퍼로는 큰 키프레임이 안 간다: 서버가 보내기 실패를 알아채고, 작은 레인은 여전히 동작한다
	NetTransport.ws_buffer_bytes = ENGINE_DEFAULT_WS_BUFFER
	var small := await _case("small", NetTransport.WEBSOCKET, false, counts.back(), true)
	NetTransport.ws_buffer_bytes = NetTransport.WS_BUFFER_BYTES
	check(small.failed_sends > 0 or not small.synced, "엔진 기본 버퍼(%d바이트)에서는 몬스터 %d마리 키프레임이 안 간다 (보내기 실패 %d번, 동기화 %s)" % [ENGINE_DEFAULT_WS_BUFFER, counts.back(), small.failed_sends, small.synced])


## 한 경우를 돌리고 결과를 돌려준다. expect_fail이면 동기화가 안 되는 것을 기대하므로 검사를 건너뛴다.
func _case(label: String, kind: String, secure: bool, monsters: int, expect_fail := false) -> Dictionary:
	var server_tls: TLSOptions = null
	var client_tls: TLSOptions = null
	if secure:
		var crypto := Crypto.new()
		var key := crypto.generate_rsa(2048)
		var cert := crypto.generate_self_signed_certificate(key, "CN=localhost")
		server_tls = TLSOptions.server(key, cert)
		client_tls = TLSOptions.client(cert, "localhost")
	var server := ServerMain.new()
	server.session.participants = [0]
	server.session.rng.seed = 5
	server.net_port = PORTS[label]
	server.net_transport = kind
	server.net_tls = server_tls
	get_tree().root.add_child.call_deferred(server)
	await frames(8)
	var net: NetServer = server.net
	var cl := NetClient.new()
	add_child(cl)
	cl.connect_to(kind, "127.0.0.1", PORTS[label], client_tls)
	await wait_until(func(): return cl.is_joined(), 8000)
	server.field.boss.max_hp = 1e15  # 보스가 안 죽어서 몬스터가 쌓여 있는 판
	server.field.boss.hp = 1e15
	server.field.bus.execute(Command.make(Command.START_GAME, 0, {}))
	var lane: LaneController = server.field.lanes[0]
	var sent := 0
	for i in range(monsters):
		lane.gold = 1e9
		if server.field.bus.execute(Command.make(Command.SEND_MONSTER, 0, {"kind_id": "rusher"}))["ok"]:
			sent += 1
	var on_server := server.field.boss.get_sent_monsters().size()
	var t0 := Time.get_ticks_msec()
	cl.set_view(GameField.BOSS_LANE_ID)
	var synced := await wait_until(func(): return cl.snapshot.get("boss", {}).get("monsters", []).size() == on_server, 6000 if expect_fail else 20000)
	var took := Time.get_ticks_msec() - t0
	var got: int = cl.snapshot.get("boss", {}).get("monsters", []).size()
	print("  [%s] 서버 몬스터 %d마리 -> 클라이언트 %d마리, 가장 큰 메시지 %d바이트, 동기화까지 %dms, 보내기 실패 %d번, 키프레임 %d번" % [label, on_server, got, net.largest_packet, took, net.failed_sends, net.keyframes_sent])
	if not expect_fail:
		check(sent == monsters and on_server == monsters, "(준비) 보스 레인에 몬스터 %d마리" % monsters)
		check(synced and got == on_server, "[%s] 보스 레인을 보는 클라이언트가 몬스터 %d마리 전부를 받았다 (%d마리)" % [label, on_server, got])
		check(net.failed_sends == 0, "[%s] 보내기가 한 번도 실패하지 않았다 (%d번, 가장 큰 메시지 %d바이트)" % [label, net.failed_sends, net.largest_packet])
		if synced:
			# 받은 몬스터 번호가 서버와 같다
			var server_ids := server.field.boss.get_sent_monsters().map(func(m): return m.monster_id)
			var client_ids: Array = cl.snapshot.boss.monsters.map(func(m): return int(m.id))
			server_ids.sort()
			client_ids.sort()
			check(server_ids == client_ids, "[%s] 받은 몬스터 번호가 서버와 같다" % label)
	var result := {"failed_sends": net.failed_sends, "largest": net.largest_packet, "synced": synced}
	cl.queue_free()
	server.queue_free()
	await frames(6)
	return result
