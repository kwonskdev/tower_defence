extends Node
## 가짜 네트워크 레이어 (#28): 클라이언트와 서버 사이에 끼는 TCP 중계. 외부 도구(clumsy, tc netem) 없이 지연/지터/손실/갑작스런 끊김을 흉내낸다.
## 서버와 클라이언트 코드는 하나도 바뀌지 않는다: 클라이언트는 서버 포트 대신 이 중계의 포트로 접속하고, 중계가 진짜 서버 포트로 이어 준다.
## (진짜 WebSocket 연결 위에서 도는 그대로의 NetClient/NetServer를 시험한다.)
##
## 흉내 내는 방식 (TCP는 순서와 전달이 보장되므로 "패킷 손실"은 메시지가 사라지는 것이 아니라 재전송 지연으로 나타난다):
##   - latency_ms: 한쪽 방향 지연 (왕복 = 2배). jitter_ms: 지연에 0~jitter_ms를 더 얹는다. 순서는 지키므로 앞 조각을 추월하지 않는다.
##   - loss: 조각(한 번에 읽은 바이트 덩어리)이 손실될 확률. 손실된 조각은 재전송 시간(rto)만큼 늦게 도착하고, 뒤따르는 조각도 같이 밀린다 (head-of-line blocking).
##     rto는 max(rto_min_ms, 3 x 한쪽 지연) (리눅스 TCP 최소 RTO 200ms 기준).
##   - freeze(true): 선이 먹통이 된다. 양쪽 다 연결은 열려 있는데 아무것도 오가지 않는다 (와이파이가 잡히지만 통신이 안 될 때, 터널/엘리베이터). 풀면 쌓인 것이 한꺼번에 간다.
##   - refusing = true: 새 연결도 거부한다 (cut() 뒤 한참 동안 네트워크가 없는 상태).
##   - cut(): 모든 연결을 갑자기 닫는다 (비행기 모드, 와이파이 <-> 모바일 데이터 전환). 중계는 계속 새 연결을 받는다.
## 시계는 실제 시간(Time.get_ticks_msec)이다: Engine.time_scale을 올린 시험에서는 쓰지 않는다 (서버/클라이언트 하트비트는 게임 시간이다).

var listen_port := 0
var upstream_host := "127.0.0.1"
var upstream_port := 0
var latency_ms := 0.0
var jitter_ms := 0.0
var loss := 0.0
var rto_min_ms := 200.0
var frozen := false
var refusing := false          # true면 새 연결을 받자마자 닫는다 (서버/네트워크가 아예 안 되는 동안)
var rng := RandomNumberGenerator.new()

## 센 값 (테스트가 읽는다)
var chunks := 0
var delayed_chunks := 0        # 손실로 재전송 지연이 붙은 조각 수
var bytes_up := 0              # 클라이언트 -> 서버
var bytes_down := 0            # 서버 -> 클라이언트
var accepted := 0              # 지금까지 받은 연결 수
var cut_count := 0

var _server := TCPServer.new()
var _conns: Array = []         # {client: StreamPeerTCP, up: StreamPeerTCP, q_up: [], q_down: [], last_up: int, last_down: int}


## 포트를 열어 받기 시작한다. 실패하면 false.
func open(p_upstream_port: int, p_listen_port: int) -> bool:
	upstream_port = p_upstream_port
	listen_port = p_listen_port
	rng.seed = 12345 + p_listen_port  # 같은 조건이면 같은 손실 모양이 나오게 (재현)
	return _server.listen(listen_port, "127.0.0.1") == OK


func is_open() -> bool:
	return _server.is_listening()


func connection_count() -> int:
	return _conns.size()


## 모든 연결을 갑자기 닫는다 (양쪽 모두). 서버는 소켓이 닫힌 것으로 보고, 클라이언트는 연결이 끊긴 것으로 본다.
func cut() -> void:
	cut_count += 1
	for c in _conns:
		c.client.disconnect_from_host()
		c.up.disconnect_from_host()
	_conns.clear()


func freeze(on: bool) -> void:
	frozen = on


func stop() -> void:
	cut()
	_server.stop()


func _exit_tree() -> void:
	stop()


func _process(_delta: float) -> void:
	if _server.is_listening():
		while _server.is_connection_available():
			var client := _server.take_connection()
			if refusing:
				client.disconnect_from_host()
				continue
			var up := StreamPeerTCP.new()
			if up.connect_to_host(upstream_host, upstream_port) != OK:
				client.disconnect_from_host()
				continue
			accepted += 1
			_conns.append({"client": client, "up": up, "q_up": [], "q_down": [], "last_up": 0, "last_down": 0})
	var now := Time.get_ticks_msec()
	for c in _conns.duplicate():
		c.client.poll()
		c.up.poll()
		_pump(c, c.client, c.up, c.q_up, "last_up", now, true)
		_pump(c, c.up, c.client, c.q_down, "last_down", now, false)
		var cs: int = c.client.get_status()
		var us: int = c.up.get_status()
		var dead_client := cs == StreamPeerTCP.STATUS_NONE or cs == StreamPeerTCP.STATUS_ERROR
		var dead_up := us == StreamPeerTCP.STATUS_NONE or us == StreamPeerTCP.STATUS_ERROR
		# 한쪽이 닫혔고 그쪽에서 온 것을 다 넘겼으면 다른 쪽도 닫는다 (TCP의 FIN 전달)
		if (dead_client and c.q_up.is_empty()) or (dead_up and c.q_down.is_empty()):
			c.client.disconnect_from_host()
			c.up.disconnect_from_host()
			_conns.erase(c)


## from에서 읽은 것을 지연 시간표(queue)에 넣고, 때가 된 것을 to로 보낸다
func _pump(_c: Dictionary, from: StreamPeerTCP, to: StreamPeerTCP, queue: Array, last_key: String, now: int, is_up: bool) -> void:
	if from.get_status() == StreamPeerTCP.STATUS_CONNECTED:
		var n := from.get_available_bytes()
		if n > 0:
			var res := from.get_data(n)
			if res[0] == OK and not (res[1] as PackedByteArray).is_empty():
				var data: PackedByteArray = res[1]
				chunks += 1
				if is_up:
					bytes_up += data.size()
				else:
					bytes_down += data.size()
				var delay := latency_ms + (rng.randf() * jitter_ms if jitter_ms > 0.0 else 0.0)
				if loss > 0.0 and rng.randf() < loss:
					delayed_chunks += 1
					delay += maxf(rto_min_ms, 3.0 * latency_ms)
				var due := maxi(int(_c[last_key]), now + int(delay))  # 앞 조각을 추월하지 못한다 (TCP는 순서를 지킨다)
				_c[last_key] = due
				queue.append({"due": due, "data": data})
	if frozen or to.get_status() != StreamPeerTCP.STATUS_CONNECTED:
		return
	while not queue.is_empty() and queue[0].due <= now:
		var item: Dictionary = queue.pop_front()
		to.put_data(item.data)
