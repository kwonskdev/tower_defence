class_name RoomHub
extends Node
## 방 코드 서버 (#26). 소켓 하나를 쥐고, 접속한 사람을 방 코드로 방(NetServer 방 모드)에 나눠 준다.
##   - 빠른 시작(mode "quick")은 코드 없이 자리 있는 공개 방에 넣고(사람이 가장 많은 방부터 채운다), 없으면 새 공개 방을 만든다.
##     대기/시작은 일반 방과 같은 규칙이다 (대기 시간 제한 없음, 모두 준비하면 방장이 [시작]).
##   - 첫 메시지 hello의 mode가 "create"면 새 방과 코드를 만들어 그 방 첫 사람(방장)으로 넣고,
##     "join"이면 code의 방에 넣는다 (없는 코드 / 너무 많이 시도 / 방 수 상한은 이유와 함께 거부).
##   - 방에 들어간 연결의 메시지는 그 방(NetServer.receive)으로 넘기고, 끊김도 알린다. 방 안의 일(로비, 판, 스냅샷)은 모두 NetServer가 한다.
##   - 방이 비거나(모두 나감) 끝난 뒤 정리 시간이 지나면 방을 닫고 코드를 돌려받는다. 접속자가 있는 대기방은 만료가 없다 (아주 오래 아무 메시지도 없는 방만 IDLE_CLOSE_SEC 뒤 닫는다).
##   - 방 만들기/빠른 시작은 접속 주소당 동시에 방장으로 쥘 수 있는 방 수(MAX_ROOMS_PER_ADDR)와 전체 방 수(MAX_ROOMS)로 막고 server_busy로 거부한다. 방장 연결이 끊기면 그 자리는 풀린다.
## 방마다 판(GameField)이 따로 있어서 한 프로세스에서 여러 방이 동시에 돈다. 방이 서로 상태를 공유하지 않는다.
## 무차별 대입은 RoomCodes가 막는다: 잘못된 코드를 접속 주소마다 1분에 5번, 서버 전체로 분당 60번 넘으면 거부하고 그 연결을 끊는다.
## 연결을 끊는 것은 그 소켓만 닫는 것이고 계정과는 상관없다 (계정은 #25).

signal room_opened(code: String)
signal room_closed(code: String)

const REJECT_GRACE := 1.0
const FINISHED_KEEP_SEC := 120.0     # 판이 끝난 방을 이만큼 두었다가 닫는다 (결과 화면을 볼 시간)
const MAX_ROOMS := 64
const MAX_ROOMS_PER_ADDR := 3        # 한 접속 주소가 동시에 "방장으로" 쥘 수 있는 방 수 (방장 연결이 끊기면 풀린다). 방을 쌓아 방 상한을 채우는 것을 막는다
## 대기방 유휴 정리: 사람이 모여 기다리는 시간은 제한이 없다. 다만 어떤 메시지(준비/시작/ping 등)도 이 시간 동안 하나도 없으면
## 앱이 죽은 채 연결만 남은 방으로 보고 닫는다. 살아 있는 클라이언트는 대기방에서 주기적으로 ping을 보내므로(MainMenu) 이 정리에 걸리지 않는다.
const IDLE_CLOSE_SEC := 6.0 * 3600.0
const MAX_CONNECTIONS := 512
const MAX_PENDING := 64

var peer: MultiplayerPeer
var transport := NetTransport.DEFAULT
var codes := RoomCodes.new()
var max_rooms := MAX_ROOMS
var max_rooms_per_addr := MAX_ROOMS_PER_ADDR
var idle_close_sec := IDLE_CLOSE_SEC
var max_connections := MAX_CONNECTIONS
var max_pending := MAX_PENDING
var hello_timeout := NetProtocol.HELLO_TIMEOUT
var reconnect_grace := NetProtocol.RECONNECT_GRACE_SEC       # 방에 넘기는 값 (#23): 끊긴 뒤 돌아올 수 있는 시간
var heartbeat_timeout := NetProtocol.HEARTBEAT_TIMEOUT_SEC   # 방에 넘기는 값 (#23): 판 중 이만큼 아무것도 못 받으면 끊김
var room_max_players := Balance.MAX_PLAYERS
var clock := Callable()              # () -> 지금(ms). 테스트가 만료/시도 제한 시계를 조작한다. 비면 엔진 시계

var _rooms: Dictionary = {}          # 코드 -> NetServer (방 모드)
var _conn_room: Dictionary = {}      # 연결 -> 방 코드
var _pending: Dictionary = {}        # hello 전 연결 -> {age, addr, kick_in?}
var _finished_at: Dictionary = {}    # 코드 -> 끝난 시각(ms). 끝난 방은 입장을 거부하지만 코드는 방을 닫을 때 돌려받는다 (새 방이 같은 코드를 받아 덮어쓰지 않게)
var _room_owner: Dictionary = {}     # 코드 -> {conn, addr}: 방장으로 방을 만든 연결 (방 수 한도 계산용)
var _last_msg: Dictionary = {}       # 코드 -> 마지막으로 이 방 연결의 메시지가 온 시각(ms)


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


## 운영 지표용 현재 값 (#24): 방 수(대기/진행/끝남), 방에 앉은 사람 수, 연결 수, 몬스터 수(모든 방의 레인 + 보스 레인)
func stats() -> Dictionary:
	var waiting := 0
	var playing := 0
	var finished := 0
	var players := 0
	var monsters := 0
	for code in _rooms:
		var room: NetServer = _rooms[code]
		players += room.alive_count()
		if _finished_at.has(code) or room.finished:
			finished += 1
		elif room.game_started:
			playing += 1
		else:
			waiting += 1
		if room.field != null:
			for lane in room.field.lanes.values():
				monsters += lane.monsters.size()
			if room.field.boss != null:
				monsters += room.field.boss.get_sent_monsters().size()
	return {"rooms": _rooms.size(), "waiting": waiting, "playing": playing, "finished": finished, "players": players, "conns": connection_count(), "monsters": monsters}


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
	_release_claims(id)
	if _conn_room.has(id):
		var room: NetServer = _rooms.get(_conn_room[id])
		_conn_room.erase(id)
		if room != null:
			room.peer_gone(id)


func _drop(id: int) -> void:
	_release_claims(id)
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
				_last_msg[room.room_code] = now_ms()
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
				if not _may_create(p.addr):
					bad = NetProtocol.REJECT_BUSY
				else:
					room = _create_room()
					if room == null:
						bad = NetProtocol.REJECT_BUSY
					else:
						_room_owner[room.room_code] = {"conn": id, "addr": p.addr}
			NetProtocol.MODE_QUICK:
				room = _open_public_room()
				if room == null:
					if not _may_create(p.addr):
						bad = NetProtocol.REJECT_BUSY
					else:
						room = _create_room(true)
						if room == null:
							bad = NetProtocol.REJECT_BUSY
						else:
							_room_owner[room.room_code] = {"conn": id, "addr": p.addr}
			NetProtocol.MODE_JOIN:
				var t := now_ms()
				var code := RoomCodes.normalize(str(msg.get("code", "")).left(32))
				if not codes.allowed(p.addr, t):
					bad = NetProtocol.REJECT_TOO_MANY
				elif RoomCodes.is_valid_format(code) and _finished_at.has(code) and _rooms.has(code) and _rooms[code].owns_seat(msg.get("token")):
					room = _rooms[code]  # 끝난 판의 자리 주인: 방이 "판이 끝났다"(game_finished)로 거부한다 (#54)
				elif not RoomCodes.is_valid_format(code) or not _rooms.has(code) or _finished_at.has(code):  # 끝난 방은 코드가 아직 남아 있어도 없는 방처럼 거부한다
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

## 이 주소가 방을 더 만들 수 있는가 (전체 방 상한과 주소별 한도). 주소를 모르면(""; 사용자 정의 전송) 주소별 한도는 보지 않는다.
func _may_create(addr: String) -> bool:
	if _rooms.size() >= max_rooms:
		return false
	if addr == "":
		return true
	var n := 0
	for code in _room_owner:
		if _room_owner[code].addr == addr:
			n += 1
	return n < max_rooms_per_addr


## 이 연결이 방장으로 쥔 방 자리를 푼다 (방은 남은 사람들과 계속된다)
func _release_claims(id: int) -> void:
	for code in _room_owner.keys():
		if _room_owner[code].conn == id:
			_room_owner.erase(code)


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
	room.game_mode = room.session.game_mode
	room.reconnect_grace = reconnect_grace
	room.heartbeat_timeout = heartbeat_timeout
	room.field_factory = func() -> GameField: return _make_field(room)
	add_child(room)
	if room.start_hosted(self, peer, transport) != OK:
		room.queue_free()
		codes.release(code)
		return null
	_rooms[code] = room
	_last_msg[code] = now_ms()
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
	_rooms[code].mark_finished()  # 끊김/이탈 판정을 멈추고, 접속자가 없으면 유예 없이 닫힐 수 있게 한다 (#54)
	# 코드는 방을 닫을 때(_close_room) 돌려받는다: 지금 돌려주면 새 방이 같은 코드를 받아 _rooms[code]를 덮어쓸 수 있다.
	# 그동안 끝난 방은 join 검사에서 _finished_at으로 거부한다 (room_not_found).
	Log.info(Log.Category.NETWORK, "방 판 끝: %s (입장 거부, 코드는 방을 닫을 때 반납)" % code)


## 빈 방(모두 나감)과 끝난 지 오래된 방을 닫는다. 사람이 있는 동안은 대기 시간 제한이 없다 (몇 시간이든 기다릴 수 있다).
func _housekeeping() -> void:
	var now := now_ms()
	for code in _rooms.keys():
		var room: NetServer = _rooms[code]
		var starting := room.game_started and room.field == null  # 판을 만드는 중(몇 프레임)에는 닫지 않는다
		if starting:
			continue
		if room.alive_count() == 0:  # 끊겨서 유예 중인 사람도 아직 방에 있는 사람이다 (#23)
			_close_room(code, "비었음")
		elif not room.game_started and now - int(_last_msg.get(code, now)) >= int(idle_close_sec * 1000.0):
			_close_room(code, "대기방에 오래 아무 메시지도 없음")
		elif _finished_at.has(code) and now - int(_finished_at[code]) >= int(FINISHED_KEEP_SEC * 1000.0):
			_close_room(code, "끝난 뒤 시간이 지남")


func _close_room(code: String, why: String) -> void:
	var room: NetServer = _rooms.get(code)
	if room == null:
		return
	_rooms.erase(code)
	_finished_at.erase(code)
	_room_owner.erase(code)
	_last_msg.erase(code)
	codes.release(code)
	for id in _conn_room.keys():
		if _conn_room[id] == code:
			_conn_room.erase(id)
			NetTransport.disconnect_peer(peer, id)
	room.queue_free()
	Log.info(Log.Category.NETWORK, "방 닫힘: %s (%s, 방 %d개)" % [code, why, _rooms.size()])
	room_closed.emit(code)
