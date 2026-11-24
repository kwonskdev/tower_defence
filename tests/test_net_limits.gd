extends "res://tests/case_base.gd"
## 이슈 #20 후속(PR #48 리뷰): 서버가 나쁜/많은 연결과 메시지에 버틴다.
##  - 서버가 끊은 클라이언트의 자리가 비고 client_left가 한 번 나온다 (너무 큰 패킷으로 끊긴 뒤 새 클라이언트가 들어온다)
##  - 연결 수 상한 (전체, hello 전)
##  - 클라이언트 메시지 속도 제한 (명령/ping/view), 정상 플레이는 영향이 없다, 계속 퍼부으면 끊긴다
##  - --port 값이 정수가 아니면 서버가 오류로 끝난다 (종료 코드 2)

const PORTS := {"ws": 47230, "enet": 47231, "cap": 47232, "rate": 47233}


func run() -> void:
	await _drop_frees_slot("ws", NetTransport.WEBSOCKET)
	await _drop_frees_slot("enet", NetTransport.ENET)
	await _connection_caps()
	await _rate_limits()
	_port_parsing()
	_port_exit_code()


func _server(port: int, kind: String, players: Array) -> ServerMain:
	var server := ServerMain.new()
	server.session.participants.clear()
	for p in players:
		server.session.participants.append(p)
	server.session.rng.seed = 3
	server.net_port = port
	server.net_transport = kind
	get_tree().root.add_child.call_deferred(server)
	await frames(8)
	return server


func _client(kind: String, port: int, player_name := "t") -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	add_child(cl)
	cl.connect_to(kind, "127.0.0.1", port)
	return cl


func _cleanup(nodes: Array) -> void:
	for n in nodes:
		if is_instance_valid(n):
			n.queue_free()
	await frames(4)


## 항목 1: 서버가 끊은(너무 큰 패킷) 입장 클라이언트의 자리가 비고 client_left가 한 번 나온다
func _drop_frees_slot(label: String, kind: String) -> void:
	print("[서버가 끊으면 자리가 빈다: %s]" % label)
	var port: int = PORTS[label]
	var server := await _server(port, kind, [0])
	var net: NetServer = server.net
	var left := []
	net.client_left.connect(func(peer_id, player_id): left.append(player_id))
	var a := _client(kind, port, "a")
	await wait_until(func(): return a.is_joined(), 8000)
	check(a.is_joined() and net.joined_count() == 1, "(준비) A가 들어와 자리 1개를 쓴다")
	var full := _client(kind, port, "full")
	var rejected := []
	full.rejected.connect(func(reason, _i): rejected.append(reason))
	await wait_until(func(): return not rejected.is_empty(), 8000)
	check(rejected == [NetProtocol.REJECT_FULL], "(준비) 자리가 하나뿐이라 두 번째는 room_full (%s)" % [rejected])
	# A가 한도(MAX_CLIENT_PACKET)보다 큰 패킷을 보낸다
	a.peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	a.peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	a.peer.put_packet(_bytes(NetProtocol.MAX_CLIENT_PACKET + 100))
	var freed := await wait_until(func(): return net.joined_count() == 0, 8000)
	check(freed, "너무 큰 패킷을 보낸 입장 클라이언트를 서버가 끊으면 자리가 빈다 (joined_count %d)" % net.joined_count())
	check(left == [0], "client_left가 한 번, 그 플레이어 번호로 나온다 %s" % [left])
	await wait_until(func(): return a.state == NetClient.State.CLOSED, 8000)
	await frames(30)
	check(left == [0], "서버가 먼저 지운 뒤에 오는 peer_disconnected가 client_left를 또 내지 않는다 %s" % [left])
	var b := _client(kind, port, "b")
	var joined := await wait_until(func(): return b.is_joined(), 8000)
	check(joined and b.player_id == 0, "빈 자리에 새 클라이언트가 들어온다 (room_full 아님, 번호 %d)" % b.player_id)
	check(net.joined_count() == 1, "자리 수가 맞다 (%d)" % net.joined_count())
	await _cleanup([a, b, full, server])


func _bytes(n: int) -> PackedByteArray:
	var b := PackedByteArray()
	b.resize(n)
	b.fill(0x41)
	return b


## 항목 3: 연결 수 상한
func _connection_caps() -> void:
	print("[연결 수 상한]")
	var port: int = PORTS["cap"]
	var server := await _server(port, NetTransport.WEBSOCKET, [0, 1])
	var net: NetServer = server.net
	net.max_pending = 2
	net.max_connections = 3
	net.hello_timeout = 1.5
	var s1 := _client(NetTransport.WEBSOCKET, port, "s1")
	var s2 := _client(NetTransport.WEBSOCKET, port, "s2")
	s1.hello_disabled = true
	s2.hello_disabled = true
	await wait_until(func(): return net.connection_count() == 2, 5000)
	check(net.connection_count() == 2 and net.refused_connections == 0, "hello를 안 보내는 연결 2개는 받는다 (상한 %d)" % net.max_pending)
	var s3 := _client(NetTransport.WEBSOCKET, port, "s3")
	s3.hello_disabled = true
	var closed := await wait_until(func(): return s3.state == NetClient.State.CLOSED, 5000)
	check(closed and net.refused_connections == 1, "hello 전 연결이 상한을 넘으면 바로 끊는다 (끊긴 횟수 %d)" % net.refused_connections)
	check(net.connection_count() == 2, "상한을 넘은 연결은 목록에 남지 않는다 (%d)" % net.connection_count())
	# hello를 안 보낸 둘이 시간 초과로 끊기면 정상 클라이언트가 들어온다
	await wait_until(func(): return net.connection_count() == 0, 6000)
	var a := _client(NetTransport.WEBSOCKET, port, "a")
	var b := _client(NetTransport.WEBSOCKET, port, "b")
	await wait_until(func(): return a.is_joined() and b.is_joined(), 8000)
	check(a.is_joined() and b.is_joined(), "빈 hello 자리가 풀리면 정상 클라이언트 둘이 들어온다")
	net.max_connections = 2  # 이제 전체 연결이 상한 (참여자 둘)
	var before := net.refused_connections
	var c := _client(NetTransport.WEBSOCKET, port, "c")
	var seen_closed := await wait_until(func(): return c.state == NetClient.State.CLOSED, 5000)
	check(seen_closed and c.state == NetClient.State.CLOSED and net.refused_connections == before + 1, "전체 연결 상한을 넘으면 reject 메시지도 없이 바로 끊는다 (state %d)" % c.state)
	check(net.joined_count() == 2, "기존 둘은 그대로다")
	await _cleanup([s1, s2, s3, a, b, c, server])


## 항목 4: 메시지 속도 제한
func _rate_limits() -> void:
	print("[메시지 속도 제한]")
	var port: int = PORTS["rate"]
	var server := await _server(port, NetTransport.WEBSOCKET, [0, 1])
	var net: NetServer = server.net
	var a := _client(NetTransport.WEBSOCKET, port, "a")
	await wait_until(func(): return a.is_joined(), 8000)
	await frames(10)

	# 정상 플레이: 건설 연타(초당 10번)는 하나도 거절되지 않는다
	var reasons := {}
	a.command_result.connect(func(seq, ok, reason, _ev): reasons[seq] = reason)
	var seqs: Array = []
	for i in range(20):
		seqs.append(a.send(Command.SELL_TOWER, {"cell": Vector2i(1, 1)}))  # 빈 칸 판매: 거절되지만 속도 제한이 아니라 no_tower로
		await wait_until(func(): return false, 100)
	await wait_until(func(): return reasons.size() == 20, 3000)
	check(reasons.size() == 20 and not reasons.values().has("rate_limited"), "초당 10번씩 명령을 보내도 속도 제한에 걸리지 않는다 (사유 %s)" % [reasons.values().slice(0, 3)])

	# 한꺼번에 몰아서 보내면 통 크기까지만 받는다
	await wait_until(func(): return false, 2000)  # 통이 다시 찬다
	var base_pongs := a.pongs
	var ignored_before := net.ignored_messages
	var burst := int(NetProtocol.RATE_BURST) * 2
	for i in range(burst):
		a.ping()
	await wait_until(func(): return false, 800)
	var got := a.pongs - base_pongs
	check(got >= int(NetProtocol.RATE_BURST) and got < burst, "한 프레임에 ping %d개를 보내면 통 크기(%d) 근처만 답한다 (pong %d개)" % [burst, int(NetProtocol.RATE_BURST), got])
	check(net.ignored_messages - ignored_before >= burst - got - 3 and net.joined_count() == 1, "넘친 메시지는 무시하고 연결은 유지한다 (무시 %d개)" % (net.ignored_messages - ignored_before))

	# 명령은 거절 사유를 돌려받는다
	await wait_until(func(): return false, 2000)
	reasons.clear()
	for i in range(int(NetProtocol.RATE_BURST) + 20):
		a.send(Command.SELL_TOWER, {"cell": Vector2i(1, 1)})
	await wait_until(func(): return false, 800)
	check(reasons.values().has("rate_limited") and reasons.values().has("no_tower"), "한도를 넘은 명령은 rate_limited로 답이 오고 앞의 명령은 정상 처리된다 (%d개 응답)" % reasons.size())

	# view 전환은 키프레임을 부르므로 따로 더 엄격하다
	await wait_until(func(): return false, 3000)
	var keys_before := net.keyframes_sent
	var ignored2 := net.ignored_messages
	for i in range(30):
		a.set_view(GameField.BOSS_LANE_ID if i % 2 == 0 else 0)
	await wait_until(func(): return false, 1200)
	var keys := net.keyframes_sent - keys_before
	check(keys >= 1 and keys <= int(NetProtocol.VIEW_BURST) + 2, "view를 30번 번갈아 보내도 키프레임은 %d번 이하만 만든다 (%d번)" % [int(NetProtocol.VIEW_BURST) + 2, keys])
	check(net.ignored_messages - ignored2 >= 30 - int(NetProtocol.VIEW_BURST) - 2, "넘친 view는 무시됐다 (무시 %d개)" % (net.ignored_messages - ignored2))

	# 계속 퍼부으면 끊는다
	await wait_until(func(): return false, 2000)
	for i in range(int(NetProtocol.RATE_BURST + NetProtocol.RATE_IGNORED_LIMIT) + 80):
		a.ping()
	var dropped := await wait_until(func(): return net.joined_count() == 0, 5000)
	check(dropped, "속도 제한을 크게 넘겨 계속 보내면 서버가 끊고 자리를 비운다")
	await _cleanup([a, server])


## 항목 5: --port 값 해석
func _port_parsing() -> void:
	print("[--port 해석]")
	check(ServerMain.parse_port("47300") == 47300 and ServerMain.parse_port("1") == 1 and ServerMain.parse_port("65535") == 65535, "정상 포트(1, 47300, 65535)")
	for bad in ["abc", "", "0", "65536", "70000", "12a", " 80", "-5", "80.5", "08"]:
		check(ServerMain.parse_port(bad) == -1, "잘못된 포트 '%s'는 -1" % bad)


## 항목 5: 틀린 --port로 서버를 실제로 띄우면 오류 코드 2로 끝난다 (예전에는 조용히 네트워크 없는 서버로 돌았다)
func _port_exit_code() -> void:
	var output := []
	var code := OS.execute(OS.get_executable_path(), ["--headless", "--path", ProjectSettings.globalize_path("res://"), "--", "--server", "--port=abc"], output, true)
	check(code == 2, "--port=abc로 서버를 띄우면 종료 코드 2 (실제 %d)" % code)
	var text := "\n".join(output)
	check(text.contains("--port"), "원인을 로그에 남긴다")
