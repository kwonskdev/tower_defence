class_name NetClient
extends Node
## 클라이언트 쪽 네트워크 (#20). 서버에 접속해 명령을 보내고, 서버가 보낸 스냅샷/이벤트/결과를 받아 둔다.
## 이 클래스는 화면을 모른다: 받은 스냅샷(`snapshot`)은 Snapshot.build가 만든 것과 같은 모양이라서
## MapView.sync / HUD가 지금 쓰는 그대로 읽는다 (자세한 건 NetServer.slice_for).
##
## 흐름: connect_to() -> (연결되면 hello 자동 전송) -> welcome이 오면 joined, reject가 오면 rejected 신호.

signal joined(player_id: int)
signal rejected(reason: String, info: Dictionary)   # info: {proto, snapshot} 서버 쪽 버전
signal disconnected()
signal snapshot_received(snap: Dictionary)
signal events_received(list: Array)
signal command_result(seq: int, ok: bool, reason: String, events: Array)
signal lobby_changed(lobby: Dictionary)        # 로비 상태가 왔다 (#22). {members: [{lane, name, ready, host}], host, max, can_start}
signal game_started(players: Array, names: Dictionary)   # 판이 시작됐다: 참여자(레인)와 닉네임이 확정됐다 (#22)
signal link_lost()                              # 판 중 연결이 끊겼다: 자동으로 다시 접속을 시도한다 (#23)
signal reconnected()                            # 다시 접속해서 같은 레인으로 돌아왔다 (스냅샷은 키프레임부터 다시 온다)
signal reconnect_failed(reason: String)         # 돌아오지 못했다: 유예가 지났거나("grace_expired") 서버가 거부했다 (reject 사유) (#23)
signal presence_changed(note: Dictionary)       # 끊긴/이탈한 사람이나 방장이 바뀌었다. note: {kind: away/back/left/host, lane} 또는 빈 Dictionary

enum State { IDLE, CONNECTING, HELLO_SENT, JOINED, REJECTED, CLOSED }

var peer: MultiplayerPeer
var state := State.IDLE
var player_id := -1
var players: Array = []
var names: Dictionary = {}          # 레인 번호(글자) -> 닉네임. 판이 시작되면 채워진다
var lobby: Dictionary = {}          # 가장 최근에 받은 로비 상태
var in_game := false                # started를 받았는가
var player_name := "player"       # 내가 입력한 닉네임 (서버가 정리/중복 제거해서 돌려준다: my_name)
var room_code := ""                # 서버가 알려 준 방 코드 (방 코드 서버에서만, welcome/lobby)
var join_mode := ""                 # hello에 실을 방 모드: NetProtocol.MODE_CREATE/MODE_JOIN ("" = 예전 방식)
var join_code := ""                 # MODE_JOIN일 때 입력한 방 코드
var my_name := ""                   # 서버가 정해 준 내 닉네임
var hello_disabled := false   # 테스트용: hello를 보내지 않는다 (말 없는 연결 시험)
var proto_override := -1   # 테스트용: 이 값이 -1이 아니면 hello의 proto를 이 값으로 속인다 (버전 불일치 시험)
var snapshot: Dictionary = {}       # 키프레임에 변경분을 적용해 맞춘 스냅샷 (자기 레인 + 보고 있는 레인 + 보스 HUD)
var summary: Dictionary = {}        # 나머지 레인의 요약 (타워 칸/몬스터 점). 1Hz로 통째로 바뀐다
var last_tick := 0
var snapshot_count := 0
var reject_reason := ""
var pongs := 0                      # 받은 pong 수 (테스트가 속도 제한을 볼 때 쓴다)
var rtt_ms := -1.0                  # 가장 최근 ping 왕복(밀리초)
## 재접속 (#23)
var token := ""                     # 재접속 식별용 기기 임시 토큰 (Identity). 비어 있으면 connect_to가 새로 만든다
var resumed := false                # 마지막 welcome이 재접속이었는가 (판 중간에 돌아옴)
var reconnecting := false           # 끊겨서 다시 접속을 시도하는 중
var away: Array = []                # 끊겨서 유예 중인 레인들 (서버가 알려 준다)
var left: Array = []                # 이탈한 레인들
var host_lane := -1                 # 판이 시작된 뒤의 방장 레인 (화면 표시용)
var reconnect_grace := NetProtocol.RECONNECT_GRACE_SEC   # 이만큼(초) 동안 다시 접속을 시도하고, 지나면 포기한다 (테스트가 줄인다)
var heartbeat_timeout := NetProtocol.HEARTBEAT_TIMEOUT_SEC   # 판 중 서버에게서 이만큼(초) 아무것도 못 받으면 끊긴 것으로 본다
var ping_interval := NetProtocol.HEARTBEAT_PING_SEC          # 판 중 이 간격(초)마다 ping (하트비트)

var _server_gone := false
var _next_seq := 1
var _ping_sent_at := {}            # n -> 보낸 시각(ms)
var _next_ping := 1
var _connect_started_ms := 0
var _target := {}                  # 다시 접속할 곳 {kind, host, port, tls}
var _intentional := false          # 내가 닫았다/나갔다: 자동 재접속하지 않는다
var _last_rx_ms := 0               # 서버에게서 마지막으로 뭔가 받은 시각
var _ping_left := 0.0
var _grace_left := 0.0
var _retry_in := 0.0
var _retry_delay := NetProtocol.RECONNECT_RETRY_MIN_SEC
var _attempt_age := 0.0


## 접속을 시작한다 (비동기). 소켓을 못 열면 false. tls를 주면 wss (WebSocket만).
func connect_to(kind: String, host: String, port: int, tls: TLSOptions = null) -> bool:
	if not NetTransport.is_known(kind):
		return false
	peer = NetTransport.create_client(kind, host, port, tls)
	if peer == null:
		state = State.CLOSED
		return false
	_target = {"kind": kind, "host": host, "port": port, "tls": tls}
	if token == "":
		token = Identity.new_token()
	_intentional = false
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	state = State.CONNECTING
	_connect_started_ms = Time.get_ticks_msec()
	return true


func close() -> void:
	_intentional = true  # 내가 닫았다: 끊김으로 보고 다시 접속하지 않는다
	reconnecting = false
	if peer != null:
		peer.close()
		peer = null
	if state != State.REJECTED:
		state = State.CLOSED


## 트리에서 다른 부모로 옮기는 동안(메뉴 -> Boot)은 접속을 닫지 않는다. 옮기기 전에 켜고, 다시 붙인 뒤 끈다.
var keep_open := false


func _exit_tree() -> void:
	if keep_open:
		return
	close()


func is_joined() -> bool:
	return state == State.JOINED


func _process(delta: float) -> void:
	if reconnecting and not _process_reconnect(delta):
		return
	if peer == null:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_closed()  # 끊긴 피어를 poll하면 엔진이 오류를 찍는다: 정리하고 멈춘다
		return
	peer.poll()
	while peer != null and peer.get_available_packet_count() > 0:
		var bytes := peer.get_packet()
		_last_rx_ms = Time.get_ticks_msec()
		_on_message(NetProtocol.decode(bytes))
	if _server_gone:
		_closed()
		return
	if peer != null and in_game and state == State.JOINED:  # 하트비트: 주기적으로 ping을 보내고, 서버가 너무 조용하면 끊긴 것으로 본다 (#23)
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = ping_interval
			ping()
		if Time.get_ticks_msec() - _last_rx_ms > int(heartbeat_timeout * 1000.0):
			Log.warn(Log.Category.NETWORK, "서버에게서 %.0f초 동안 아무것도 못 받아 끊긴 것으로 봄" % heartbeat_timeout)
			_lose_link()


## 재접속 중의 한 프레임: 남은 유예를 줄이고, 시도할 때가 되면 새 연결을 연다. 아래에서 연결을 읽어도 되면 true.
func _process_reconnect(delta: float) -> bool:
	_grace_left -= delta
	if _grace_left <= 0.0:
		_give_up("grace_expired")
		return false
	if peer == null:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_attempt_reconnect()
		return peer != null
	_attempt_age += delta
	if _attempt_age > NetProtocol.RECONNECT_ATTEMPT_SEC and state != State.JOINED:  # 이번 시도는 접는다
		peer.close()
		peer = null
		_schedule_retry()
		return false
	return true


func _on_peer_connected(id: int) -> void:
	if id != MultiplayerPeer.TARGET_PEER_SERVER:  # 클라이언트가 보는 연결은 서버(1) 하나뿐이다
		return
	if hello_disabled:
		return
	var hello := NetProtocol.make_hello(player_name, join_mode, join_code, token)
	if proto_override >= 0:
		hello["proto"] = proto_override
	_send(hello)
	state = State.HELLO_SENT


func _on_peer_disconnected(_id: int) -> void:
	_server_gone = true  # 같은 poll에서 온 패킷(reject 등)을 다 읽은 뒤 _process가 정리한다


## 연결이 끝났다 (서버가 끊었거나, 접속에 실패했거나, 내가 닫았다). 거부당한 경우는 REJECTED 상태를 그대로 둔다.
func _closed() -> void:
	if peer == null:
		return
	peer = null
	_server_gone = false
	if reconnecting:  # 이번 재접속 시도가 실패했다: 계속 시도한다
		_schedule_retry()
		return
	if state != State.REJECTED and in_game and token != "" and not _intentional and not _target.is_empty():
		_begin_reconnect()
		return
	if state != State.REJECTED:
		state = State.CLOSED
	disconnected.emit()


# ---- 끊김 / 재접속 (#23) ----------------------------------------------------

## 연결이 죽었다고 보고 닫는다 (하트비트 시간 초과, 앱 복귀 때 오래된 연결). 판 중이면 재접속을 시작한다.
func _lose_link() -> void:
	if peer != null:
		peer.close()
		peer = null
	_server_gone = false
	if reconnecting:
		return
	if in_game and token != "" and not _intentional and not _target.is_empty():
		_begin_reconnect()
	else:
		state = State.CLOSED
		disconnected.emit()


func _begin_reconnect() -> void:
	reconnecting = true
	_grace_left = reconnect_grace
	_retry_in = 0.0   # 처음 시도는 바로
	_retry_delay = NetProtocol.RECONNECT_RETRY_MIN_SEC
	state = State.CONNECTING
	join_mode = NetProtocol.MODE_JOIN   # 판 중 돌아오기는 방 코드 + 토큰이다
	join_code = room_code
	_ping_sent_at.clear()
	Log.info(Log.Category.NETWORK, "연결 끊김: 최대 %.0f초 동안 다시 접속을 시도한다" % reconnect_grace)
	link_lost.emit()


func _attempt_reconnect() -> void:
	peer = NetTransport.create_client(_target.kind, _target.host, _target.port, _target.tls)
	if peer == null:
		_schedule_retry()
		return
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	_server_gone = false
	_attempt_age = 0.0
	state = State.CONNECTING


## 다음 시도까지 기다린다: 1초 -> 2초 -> 4초 -> 5초 ... (앱이 돌아오면 on_app_resumed가 바로 시도하게 한다)
func _schedule_retry() -> void:
	_retry_in = _retry_delay
	_retry_delay = minf(_retry_delay * 2.0, NetProtocol.RECONNECT_RETRY_MAX_SEC)


func _give_up(reason: String) -> void:
	reconnecting = false
	if peer != null:
		peer.close()
		peer = null
	if state != State.REJECTED:
		state = State.CLOSED
	Log.warn(Log.Category.NETWORK, "재접속 포기: %s" % reason)
	reconnect_failed.emit(reason)


## 남은 재접속 유예(초). 재접속 중이 아니면 0.
func reconnect_left() -> float:
	return maxf(0.0, _grace_left) if reconnecting else 0.0


## 재접속을 그만둔다 (이미 끝난 판의 결과를 보는 중 등). 연결이 끊긴 채로 닫히고 disconnected가 나온다.
func stop_reconnect() -> void:
	if not reconnecting:
		return
	_intentional = true
	reconnecting = false
	if peer != null:
		peer.close()
		peer = null
	state = State.CLOSED
	disconnected.emit()


## 앱이 포그라운드로 돌아왔다 (APPLICATION_RESUMED / 창 포커스). 재접속 중이면 기다리지 않고 바로 시도하고,
## 연결이 살아 있는 줄 알지만 서버에게서 한동안 아무것도 못 받았으면(백그라운드에서 죽은 연결) 바로 다시 접속한다.
func on_app_resumed() -> void:
	if not in_game or _intentional:
		return
	if reconnecting:
		if peer != null and state != State.JOINED:
			peer.close()
			peer = null
		_retry_in = 0.0
	elif state == State.JOINED and Time.get_ticks_msec() - _last_rx_ms > NetProtocol.RESUME_STALE_MS:
		Log.info(Log.Category.NETWORK, "앱 복귀: 서버 소식이 오래돼 다시 접속한다")
		_lose_link()


## 의도적으로 나간다 (나가기 버튼): 서버에 알려 유예 없이 바로 이탈로 처리하게 하고, 보낸 것이 나간 뒤에 연결을 닫는다.
## 재접속 중이거나 연결이 없으면 알릴 길이 없어서 그냥 닫는다 (서버는 유예 뒤에 이탈로 처리한다).
func leave() -> void:
	var p := peer
	if p != null and state == State.JOINED:
		_send({"t": NetProtocol.MSG_LEAVE})
		peer = null
		_intentional = true
		reconnecting = false
		state = State.CLOSED
		_flush_and_close(p)
		return
	close()


## 보낸 패킷이 소켓으로 나가도록 잠깐 poll한 뒤 닫는다 (바로 닫으면 마지막 메시지가 버려질 수 있다). 이 노드가 사라져도 계속된다.
static func _flush_and_close(p: MultiplayerPeer) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	for i in range(5):
		p.poll()
		if tree == null:
			break
		await tree.create_timer(0.05).timeout
	p.close()


func _on_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		NetProtocol.MSG_WELCOME:
			player_id = int(msg.get("player_id", -1))
			players = _as_ints(msg.get("players", []))
			my_name = str(msg.get("name", player_name))
			room_code = str(msg.get("room", ""))
			resumed = bool(msg.get("resumed", false))
			state = State.JOINED
			_last_rx_ms = Time.get_ticks_msec()
			_ping_left = ping_interval
			var was_reconnecting := reconnecting
			if resumed:  # 판 중간에 돌아옴: 로컬에 남은 옛 상태는 버리고 서버가 보내는 키프레임으로 다시 만든다
				in_game = true
				names = msg.get("names", {})
				snapshot = {}
				summary = {}
				last_tick = 0
				_ping_sent_at.clear()
				reconnecting = false
			joined.emit(player_id)
			if was_reconnecting and resumed:
				reconnected.emit()
		NetProtocol.MSG_REJECT:
			reject_reason = str(msg.get("reason", ""))
			var was_reconnecting := reconnecting
			state = State.REJECTED
			rejected.emit(reject_reason, {"proto": int(msg.get("proto", -1)), "snapshot": int(msg.get("snapshot", -1))})
			close()  # 서버가 끊기 전에 내가 먼저 끊는다 (state는 REJECTED로 남는다)
			if was_reconnecting:
				reconnect_failed.emit(reject_reason)
		NetProtocol.MSG_PRESENCE:
			away = _as_ints(msg.get("away", []))
			left = _as_ints(msg.get("left", []))
			host_lane = int(msg.get("host", -1))
			var note = msg.get("note", {})
			if typeof(note) == TYPE_DICTIONARY and note.has("lane"):
				note = {"kind": str(note.get("kind", "")), "lane": int(note["lane"])}
			else:
				note = {}
			presence_changed.emit(note)
		NetProtocol.MSG_SNAP:
			var tick := int(msg.get("tick", 0))
			if tick <= last_tick:
				return  # 늦게 온 옛 스냅샷은 버린다
			last_tick = tick
			var snap = msg.get("snap")
			if typeof(snap) != TYPE_DICTIONARY:
				return
			if msg.get("key", false):
				snapshot = snap  # 키프레임: 통째로 교체
			elif snapshot.is_empty():
				return  # 키프레임 전에 온 변경분은 적용할 곳이 없다
			else:
				snapshot = SnapshotDelta.apply(snapshot, snap)
			snapshot_count += 1
			snapshot_received.emit(snapshot)
		NetProtocol.MSG_SUMMARY:
			if typeof(msg.get("summary")) == TYPE_DICTIONARY:
				summary = msg["summary"]
		NetProtocol.MSG_EVENTS:
			events_received.emit(msg.get("list", []))
		NetProtocol.MSG_LOBBY:
			lobby = msg
			if str(msg.get("room", "")) != "":
				room_code = str(msg["room"])
			lobby_changed.emit(lobby)
		NetProtocol.MSG_STARTED:
			players = _as_ints(msg.get("players", []))
			names = msg.get("names", {})
			in_game = true
			game_started.emit(players, names)
		NetProtocol.MSG_RESULT:
			command_result.emit(int(msg.get("seq", 0)), bool(msg.get("ok", false)), str(msg.get("reason", "")), msg.get("events", []))
		NetProtocol.MSG_PONG:
			pongs += 1
			var n := int(msg.get("n", 0))
			if _ping_sent_at.has(n):
				rtt_ms = float(Time.get_ticks_msec() - _ping_sent_at[n])
				_ping_sent_at.erase(n)


## JSON은 정수도 실수(0.0)로 돌려준다: 레인 번호 목록은 정수로 되돌린다
static func _as_ints(list) -> Array:
	var out: Array = []
	if list is Array:
		for v in list:
			out.append(int(v))
	return out


## 보내기가 실패하면(버퍼가 가득 참 등) 경고를 남기고 false
func _send(msg: Dictionary) -> bool:
	if peer == null:
		return false
	peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	peer.transfer_channel = NetProtocol.CHANNEL_RELIABLE
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var bytes := NetProtocol.encode(msg)
	var err := ERR_OUT_OF_MEMORY if NetTransport.would_overflow(peer, MultiplayerPeer.TARGET_PEER_SERVER, bytes.size()) else peer.put_packet(bytes)
	if err != OK:
		Log.warn(Log.Category.NETWORK, "서버로 보내기 실패: %s (%s)" % [msg.get("t", "?"), error_string(err)])
		return false
	return true


## 명령을 서버로 보낸다. 돌려주는 값은 seq: command_result 신호가 같은 seq로 결과를 알려 준다. 가입 전이면 -1.
func send_command(cmd: Dictionary) -> int:
	if state != State.JOINED or cmd.is_empty():
		return -1
	var seq := _next_seq
	_next_seq += 1
	if not _send({"t": NetProtocol.MSG_CMD, "seq": seq, "cmd": Command.to_wire(cmd)}):
		return -1
	return seq


## 내 플레이어 번호로 명령을 만들어 보낸다
func send(type: String, args: Dictionary = {}) -> int:
	return send_command(Command.make(type, player_id, args))


## 로비에서 준비/준비 취소 (#22)
func set_ready(on: bool) -> void:
	if state == State.JOINED:
		_send({"t": NetProtocol.MSG_READY, "on": on})


## 로비에서 방장이 시작한다. 방장이 아니거나 모두 준비하지 않았으면 서버가 무시한다 (#22)
func request_start() -> void:
	if state == State.JOINED:
		_send({"t": NetProtocol.MSG_START})


## 지금 보고 있는 레인을 서버에 알린다 (그 레인은 스냅샷에 자세히 담겨 온다)
func set_view(lane: int) -> void:
	if state == State.JOINED:
		_send({"t": NetProtocol.MSG_VIEW, "lane": lane})


func ping() -> void:
	if state != State.JOINED:
		return
	var n := _next_ping
	_next_ping += 1
	_ping_sent_at[n] = Time.get_ticks_msec()
	_send({"t": NetProtocol.MSG_PING, "n": n})
