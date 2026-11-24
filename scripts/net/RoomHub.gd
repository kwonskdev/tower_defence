class_name RoomHub
extends Node
## 방 코드 서버 (#26). 소켓 하나를 쥐고, 접속한 사람을 방 코드로 방(NetServer 방 모드)에 나눠 준다.
##   - 빠른 시작(mode "quick")은 코드 없이 자리 있는 공개 방에 넣고(사람이 가장 많은 방부터 채운다), 없으면 새 공개 방을 만든다.
##     대기/시작은 일반 방과 같은 #22 규칙이다 (모두 준비하면 방장이 시작, 2명 이상이면 게임 화면에서 30초 뒤 자동 시작).
##   - 첫 메시지 hello의 mode가 "create"면 새 방과 코드를 만들어 그 방 첫 사람(방장)으로 넣고,
##     "join"이면 code의 방에 넣는다 (없는 코드 / 너무 많이 시도 / 방 수 상한은 이유와 함께 거부).
##   - 방에 들어간 연결의 메시지는 그 방(NetServer.receive)으로 넘기고, 끊김도 알린다. 방 안의 일(로비, 판, 스냅샷)은 모두 NetServer가 한다.
##   - 방이 비거나(모두 나감) 시작 못 한 채 만료되거나 끝난 뒤 정리 시간이 지나면 방을 닫고 코드를 돌려받는다.
## 방마다 판(GameField)이 따로 있어서 한 프로세스에서 여러 방이 동시에 돈다. 방이 서로 상태를 공유하지 않는다.
## 무차별 대입은 RoomCodes가 막는다: 잘못된 코드를 접속 주소마다 1분에 5번, 서버 전체로 분당 60번 넘으면 거부하고 그 연결을 끊는다.
## 연결을 끊는 것은 그 소켓만 닫는 것이고 계정과는 상관없다 (계정은 #25).

signal room_opened(code: String)
signal room_closed(code: String)

const REJECT_GRACE := 1.0
const FINISHED_KEEP_SEC := 120.0     # 판이 끝난 방을 이만큼 두었다가 닫는다 (결과 화면을 볼 시간)
const MAX_ROOMS := 64
const MAX_CONNECTIONS := 512
const MAX_PENDING := 64

var peer: MultiplayerPeer
var transport := NetTransport.DEFAULT
var codes := RoomCodes.new()
var max_rooms := MAX_ROOMS
var max_connections := MAX_CONNECTIONS
var max_pending := MAX_PENDING
var hello_timeout := NetProtocol.HELLO_TIMEOUT
var room_max_players := Balance.MAX_PLAYERS
var game_auto_start_sec := Balance.GAME_AUTO_START_SEC
var clock := Callable()              # () -> 지금(ms). 테스트가 만료/시도 제한 시계를 조작한다. 비면 엔진 시계

var _rooms: Dictionary = {}          # 코드 -> NetServer (방 모드)
var _conn_room: Dictionary = {}      # 연결 -> 방 코드
var _pending: Dictionary = {}        # hello 전 연결 -> {age, addr, kick_in?}
var _finished_at: Dictionary = {}    # 코드 -> 끝난 시각(ms)


func start(kind: String, port: int, tls: TLSOptions = null) -> Error:
	if not NetTransport.is_known(kind):
		return ERR_INVALID_PARAMETER
	transport = kind
	peer = NetTransport.create_server(kind, port, tls)
	if peer == null:
		return ERR_CANT_CREATE
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	Log.info(Log.Category.NETWORK, "방 코드 서버 열림: %s 포트 %d (프로토콜 %d)" % [kind, port, NetProtocol.PROTOCOL_VERSION])
	return OK


func stop() -> void:
	if peer != null:
		peer.close()
		peer = null


func _exit_tree() -> void:
	stop()


func now_ms() -> int:
	return int(clock.call()) if clock.is_valid() else Time.get_ticks_msec()


func room_count() -> int:
	return _rooms.size()


func room_for(code: String) -> NetServer:
	return _rooms.get(code)


func connection_count() -> int:
	return _pending.size() + _conn_room.size()


func _process(delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	_read_packets()
	for id in _pending.keys():
		var p: Dictionary = _pending[id]
		p.age += delta
		if p.has("kick_in"):
			p.kick_in -= delta
			if p.kick_in <= 0.0:
				_drop(id)
		elif p.age > hello_timeout:
			Log.warn(Log.Category.NETWORK, "hello가 안 와서 끊음: 연결 %d" % id)
			_drop(id)
	_housekeeping()


func _on_peer_connected(id: int) -> void:
	if connection_count() >= max_connections or _pending.size() >= max_pending:
		Log.warn(Log.Category.NETWORK, "연결 수 상한이라 바로 끊음: 연결 %d" % id)
		NetTransport.disconnect_peer(peer, id)
		return
	_pending[id] = {"age": 0.0, "addr": NetTransport.address_of(peer, id)}


func _on_peer_disconnected(id: int) -> void:
	_pending.erase(id)
	if _conn_room.has(id):
		var room: NetServer = _rooms.get(_conn_room[id])
		_conn_room.erase(id)
		if room != null:
			room.peer_gone(id)


func _drop(id: int) -> void:
	if _conn_room.has(id):
		var room: NetServer = _rooms.get(_conn_room[id])
		_conn_room.erase(id)
		if room != null:
			room.peer_gone(id)
	_pending.erase(id)
	NetTransport.disconnect_peer(peer, id)


func _read_packets() -> void:
	while peer != null and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()
		var bytes := peer.get_packet()
		if not _pending.has(from) and not _conn_room.has(from):
			continue
		if bytes.size() > NetProtocol.MAX_CLIENT_PACKET:
			Log.warn(Log.Category.NETWORK, "너무 큰 패킷 (%d바이트): 연결 %d 끊음" % [bytes.size(), from])
			_drop(from)
			continue
		var msg := NetProtocol.decode(bytes)
		if _conn_room.has(from):
			var room: NetServer = _rooms.get(_conn_room[from])
			if room != null:
				room.receive(from, msg)
		else:
			_on_hello(from, msg)


## hello를 받아 방을 정하고(만들기/입장) 그 방에 넣는다. 거부하면 이유를 보내고 곧 끊는다.
func _on_hello(id: int, msg: Dictionary) -> void:
	var p: Dictionary = _pending[id]
	if p.has("kick_in"):
		return  # 이미 거부한 연결의 메시지는 무시한다
	var bad := NetProtocol.check_hello(msg)
	var room: NetServer = null
	if bad == "":
		match msg.get("mode"):
			NetProtocol.MODE_CREATE:
				if _rooms.size() >= max_rooms:
					bad = NetProtocol.REJECT_BUSY
				else:
					room = _create_room()
					if room == null:
						bad = NetProtocol.REJECT_BUSY
			NetProtocol.MODE_QUICK:
				room = _open_public_room()
				if room == null:
					if _rooms.size() >= max_rooms:
						bad = NetProtocol.REJECT_BUSY
					else:
						room = _create_room(true)
						if room == null:
							bad = NetProtocol.REJECT_BUSY
			NetProtocol.MODE_JOIN:
				var t := now_ms()
				var code := RoomCodes.normalize(str(msg.get("code", "")).left(32))
				if not codes.allowed(p.addr, t):
					bad = NetProtocol.REJECT_TOO_MANY
				elif not RoomCodes.is_valid_format(code) or not codes.has(code) or not _rooms.has(code):
					bad = NetProtocol.REJECT_TOO_MANY if codes.record_bad(p.addr, t) else NetProtocol.REJECT_NO_ROOM
					Log.warn(Log.Category.NETWORK, "없는 방 코드 시도: 연결 %d (%s)" % [id, bad])
				else:
					room = _rooms[code]
			_:
				bad = NetProtocol.REJECT_BAD_HELLO
	if bad != "":
		_send(id, {"t": NetProtocol.MSG_REJECT, "reason": bad, "proto": NetProtocol.PROTOCOL_VERSION, "snapshot": Snapshot.VERSION})
		p["kick_in"] = REJECT_GRACE  # 클라이언트가 reject를 읽고 스스로 끊게 두고, 안 끊으면 끊는다
		return
	_pending.erase(id)
	_conn_room[id] = room.room_code
	room.admit(id, msg)


func _send(id: int, msg: Dictionary) -> void:
	if peer == null:
		return
	peer.set_target_peer(id)
	peer.transfer_channel = NetProtocol.CHANNEL_RELIABLE
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	peer.put_packet(NetProtocol.encode(msg))


# ---- 방 ----------------------------------------------------------------------

## 자리가 있는 공개 방 중 사람이 가장 많은 방 (먼저 채워서 방이 흩어지지 않게). 같으면 먼저 만든 방. 없으면 null.
func _open_public_room() -> NetServer:
	var best: NetServer = null
	for code in _rooms:
		var r: NetServer = _rooms[code]
		if r.public_room and codes.has(code) and r.is_open() and (best == null or r.lobby.size() > best.lobby.size()):
			best = r
	return best


func _create_room(public := false) -> NetServer:
	var code := codes.issue(now_ms())
	if code == "":
		return null
	var room := NetServer.new()
	room.room_code = code
	room.public_room = public
	room.session = Session.new()
	room.session.participants.clear()  # 참여자는 방장이 시작할 때 접속자로 정해진다
	room.lobby = Lobby.new()
	room.lobby.max_players = room_max_players
	room.game_auto_start_sec = game_auto_start_sec
	room.game_mode = room.session.game_mode
	room.field_factory = func() -> GameField: return _make_field(room)
	add_child(room)
	if room.start_hosted(self, peer, transport) != OK:
		room.queue_free()
		codes.release(code)
		return null
	_rooms[code] = room
	Log.info(Log.Category.NETWORK, "방 열림: %s%s (방 %d개)" % [code, " (공개)" if public else "", _rooms.size()])
	room_opened.emit(code)
	return room


## 방의 판(레인 + 보스)을 만든다. 서버는 화면이 없어서 연출은 그리지 않는다. 판이 끝나면 코드를 돌려받는다.
func _make_field(room: NetServer) -> GameField:
	var f := (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	f.session = room.session
	f.play_effects = false
	room.add_child(f)
	f.boss_ready.connect(func(boss: BossController):
		boss.boss_defeated.connect(func(): _on_room_finished(room.room_code))
		boss.boss_failed.connect(func(_reason: String): _on_room_finished(room.room_code)), CONNECT_ONE_SHOT)
	return f


func _on_room_finished(code: String) -> void:
	if not _rooms.has(code) or _finished_at.has(code):
		return
	_finished_at[code] = now_ms()
	codes.release(code)  # 끝난 방의 코드는 바로 돌려받는다 (같은 코드로 들어와 보지 못한다)
	Log.info(Log.Category.NETWORK, "방 판 끝: %s (코드 반납)" % code)


## 비었거나(모두 나감), 시작 못 한 채 만료되었거나, 끝난 지 오래된 방을 닫는다.
func _housekeeping() -> void:
	var now := now_ms()
	for code in _rooms.keys():
		var room: NetServer = _rooms[code]
		var starting := room.game_started and room.field == null  # 판을 만드는 중(몇 프레임)에는 닫지 않는다
		if starting:
			continue
		if room.joined_count() == 0:
			_close_room(code, "비었음")
		elif _finished_at.has(code) and now - int(_finished_at[code]) >= int(FINISHED_KEEP_SEC * 1000.0):
			_close_room(code, "끝난 뒤 시간이 지남")
	for code in codes.expired(now):
		if _rooms.has(code) and not _rooms[code].game_started:
			_close_room(code, "시작 못 한 채 만료")


func _close_room(code: String, why: String) -> void:
	var room: NetServer = _rooms.get(code)
	if room == null:
		return
	_rooms.erase(code)
	_finished_at.erase(code)
	codes.release(code)
	for id in _conn_room.keys():
		if _conn_room[id] == code:
			_conn_room.erase(id)
			NetTransport.disconnect_peer(peer, id)
	room.queue_free()
	Log.info(Log.Category.NETWORK, "방 닫힘: %s (%s, 방 %d개)" % [code, why, _rooms.size()])
	room_closed.emit(code)
