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

enum State { IDLE, CONNECTING, HELLO_SENT, JOINED, REJECTED, CLOSED }

var peer: MultiplayerPeer
var state := State.IDLE
var player_id := -1
var players: Array = []
var player_name := "player"
var hello_disabled := false   # 테스트용: hello를 보내지 않는다 (말 없는 연결 시험)
var proto_override := -1   # 테스트용: 이 값이 -1이 아니면 hello의 proto를 이 값으로 속인다 (버전 불일치 시험)
var snapshot: Dictionary = {}       # 가장 최근에 받은 스냅샷 (자기 레인 + 보고 있는 레인 + 보스)
var summary: Dictionary = {}        # 나머지 레인의 요약 (타워 칸/몬스터 점). 요약이 올 때마다 갱신
var last_tick := 0
var snapshot_count := 0
var reject_reason := ""
var rtt_ms := -1.0                  # 가장 최근 ping 왕복(밀리초)

var _server_gone := false
var _next_seq := 1
var _ping_sent_at := {}            # n -> 보낸 시각(ms)
var _next_ping := 1
var _connect_started_ms := 0


## 접속을 시작한다 (비동기). 소켓을 못 열면 false.
func connect_to(kind: String, host: String, port: int) -> bool:
	if not NetTransport.is_known(kind):
		return false
	peer = NetTransport.create_client(kind, host, port)
	if peer == null:
		state = State.CLOSED
		return false
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	state = State.CONNECTING
	_connect_started_ms = Time.get_ticks_msec()
	return true


func close() -> void:
	if peer != null:
		peer.close()
		peer = null
	if state != State.REJECTED:
		state = State.CLOSED


func _exit_tree() -> void:
	close()


func is_joined() -> bool:
	return state == State.JOINED


func _process(_delta: float) -> void:
	if peer == null:
		return
	if peer.get_connection_status() == MultiplayerPeer.CONNECTION_DISCONNECTED:
		_closed()  # 끊긴 피어를 poll하면 엔진이 오류를 찍는다: 정리하고 멈춘다
		return
	peer.poll()
	while peer != null and peer.get_available_packet_count() > 0:
		var bytes := peer.get_packet()
		_on_message(NetProtocol.decode(bytes))
	if _server_gone:
		_closed()


func _on_peer_connected(id: int) -> void:
	if id != MultiplayerPeer.TARGET_PEER_SERVER:  # 클라이언트가 보는 연결은 서버(1) 하나뿐이다
		return
	if hello_disabled:
		return
	var hello := NetProtocol.make_hello(player_name)
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
	if state != State.REJECTED:
		state = State.CLOSED
	disconnected.emit()


func _on_message(msg: Dictionary) -> void:
	match msg.get("t", ""):
		NetProtocol.MSG_WELCOME:
			player_id = int(msg.get("player_id", -1))
			players = msg.get("players", [])
			state = State.JOINED
			joined.emit(player_id)
		NetProtocol.MSG_REJECT:
			reject_reason = str(msg.get("reason", ""))
			state = State.REJECTED
			rejected.emit(reject_reason, {"proto": int(msg.get("proto", -1)), "snapshot": int(msg.get("snapshot", -1))})
			close()  # 서버가 끊기 전에 내가 먼저 끊는다 (state는 REJECTED로 남는다)
		NetProtocol.MSG_SNAP:
			var tick := int(msg.get("tick", 0))
			if tick <= last_tick:
				return  # 늦게 온 옛 스냅샷은 버린다
			last_tick = tick
			var snap = msg.get("snap")
			if typeof(snap) != TYPE_DICTIONARY:
				return
			snapshot_count += 1
			if snap.has("summary"):
				summary = snap["summary"]
			snapshot = snap
			snapshot_received.emit(snap)
		NetProtocol.MSG_EVENTS:
			events_received.emit(msg.get("list", []))
		NetProtocol.MSG_RESULT:
			command_result.emit(int(msg.get("seq", 0)), bool(msg.get("ok", false)), str(msg.get("reason", "")), msg.get("events", []))
		NetProtocol.MSG_PONG:
			var n := int(msg.get("n", 0))
			if _ping_sent_at.has(n):
				rtt_ms = float(Time.get_ticks_msec() - _ping_sent_at[n])
				_ping_sent_at.erase(n)


func _send(msg: Dictionary, reliable := true) -> void:
	if peer == null:
		return
	peer.set_target_peer(MultiplayerPeer.TARGET_PEER_SERVER)
	peer.transfer_channel = NetProtocol.CHANNEL_RELIABLE if reliable else NetProtocol.CHANNEL_SNAPSHOT
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE if reliable else MultiplayerPeer.TRANSFER_MODE_UNRELIABLE_ORDERED
	peer.put_packet(NetProtocol.encode(msg))


## 명령을 서버로 보낸다. 돌려주는 값은 seq: command_result 신호가 같은 seq로 결과를 알려 준다. 가입 전이면 -1.
func send_command(cmd: Dictionary) -> int:
	if state != State.JOINED or cmd.is_empty():
		return -1
	var seq := _next_seq
	_next_seq += 1
	_send({"t": NetProtocol.MSG_CMD, "seq": seq, "cmd": Command.to_wire(cmd)})
	return seq


## 내 플레이어 번호로 명령을 만들어 보낸다
func send(type: String, args: Dictionary = {}) -> int:
	return send_command(Command.make(type, player_id, args))


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
