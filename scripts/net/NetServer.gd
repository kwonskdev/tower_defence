class_name NetServer
extends Node
## 서버 쪽 네트워크 (#20). 헤드리스 서버(ServerMain)의 시뮬레이션 곁에 붙어서
##   - 접속을 받고(hello 버전 확인, 자리 배정), 명령을 받아 CommandBus로 실행하고, 결과를 돌려주고,
##   - 일정한 주기로 스냅샷의 "변경분"을 잘라서 보낸다 (자기 레인 + 보고 있는 레인 + 보스 HUD는 10Hz, 나머지 레인은 1Hz 요약).
## 스냅샷 전송 규칙 (#20에서 정함):
##   - 틱마다 전체 스냅샷을 거칠게(SnapshotDelta.quantize) 만들고, 이전 틱과의 차이(SnapshotDelta.diff)를 "한 번만" 계산한다.
##     클라이언트마다 따로 계산하면 몬스터 1000마리에서 10ms x 클라이언트 수가 되므로, 한 번 계산한 변경분을 클라이언트별로 자르기만 한다.
##   - 변경분은 신뢰 순서 채널로 보낸다 (받는 쪽이 이전 틱 위에 적용하므로 빠지면 안 된다). 새로 들어왔거나 보는 레인을 바꾼 클라이언트에게는 키프레임(전체)을 한 번 보낸다.
##   - 미니맵용 요약은 1Hz로 따로 보낸다 (메시지 summary).
## 시뮬레이션은 건드리지 않는다: 명령은 CommandBus.execute 하나로만 들어가고, 스냅샷은 Snapshot.build 결과를 읽기만 한다.
##
## 권위: 플레이어 번호는 서버가 접속 때 정해 준다. 명령 안의 player_id가 그 연결의 번호와 다르면 실행하지 않고 거절한다.

signal client_joined(peer_id: int, player_id: int)
signal client_left(peer_id: int, player_id: int)

const SNAP_HZ := 10.0       # 자기 레인/보고 있는 레인/보스 레인 (HUD와 움직임)
const SUMMARY_HZ := 1.0     # 나머지 레인 (미니맵용 점)
const REJECT_GRACE := 1.0   # 거부 메시지를 보낸 뒤 연결을 강제로 끊기까지(초)
const SEND_WARN_INTERVAL_MS := 2000  # 같은 연결의 보내기 실패 경고는 이 간격(밀리초)에 한 번만

var field: GameField
var peer: MultiplayerPeer
var transport := NetTransport.DEFAULT
var snap_hz := SNAP_HZ
var summary_hz := SUMMARY_HZ
var start_when_full := false  # 참여자 자리가 다 차면 서버가 시작 명령을 실행한다 (로비가 생기기 전의 임시 규칙. 로비는 #22)
var max_connections := NetProtocol.MAX_CONNECTIONS  # 테스트가 줄인다
var max_pending := NetProtocol.MAX_PENDING
var hello_timeout := NetProtocol.HELLO_TIMEOUT  # hello를 이 시간(초) 안에 안 보내면 끊는다 (테스트가 줄인다)

var _clients: Dictionary = {}     # peer_id -> {player_id: int(-1 = 아직 hello 전), view: int, age: float, name: String}
var _slots: Dictionary = {}       # player_id -> peer_id
var _prev_q: Dictionary = {}      # 이전 틱의 거칠게 한 전체 스냅샷 (변경분의 기준)
var _snap_timer := 0.0
var _summary_timer := 0.0
var _tick := 0
var _pending_events: Array = []   # 이번 틱에 보낼 연출 이벤트 (SimEvents가 낸 것)

## 측정용: 보낸 바이트 합 (종류별). 테스트/부하 측정이 읽는다.
var sent_bytes := {}
var sent_packets := 0
var largest_packet := 0           # 지금까지 보낸 가장 큰 메시지(바이트)
var keyframes_sent := 0
var failed_sends := 0             # put_packet이 실패한 횟수
var refused_connections := 0      # 상한 때문에 바로 끊은 연결 수
var ignored_messages := 0         # 속도 제한 때문에 무시한 메시지 수
var _send_warn_at := {}           # peer_id -> 마지막으로 보내기 실패를 로그한 시각(ms). 같은 연결의 반복 로그를 줄인다


## 소켓을 열고 시뮬레이션 곁에 붙는다. 실패하면 오류 코드. tls를 주면 wss (WebSocket만).
func start(p_field: GameField, kind: String, port: int, tls: TLSOptions = null) -> Error:
	if not NetTransport.is_known(kind):
		return ERR_INVALID_PARAMETER
	field = p_field
	transport = kind
	peer = NetTransport.create_server(kind, port, tls)
	if peer == null:
		return ERR_CANT_CREATE
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	field.session.events.emitted.connect(_on_sim_event)
	Log.info(Log.Category.NETWORK, "서버 열림: %s 포트 %d (프로토콜 %d, 스냅샷 %.0fHz + 요약 %.1fHz)" % [kind, port, NetProtocol.PROTOCOL_VERSION, snap_hz, summary_hz])
	return OK


func stop() -> void:
	if peer != null:
		peer.close()
		peer = null
	_clients.clear()
	_slots.clear()


func _exit_tree() -> void:
	if field != null and is_instance_valid(field) and field.session.events.emitted.is_connected(_on_sim_event):
		field.session.events.emitted.disconnect(_on_sim_event)
	stop()


## 지금 연결 중인 클라이언트 수 (hello를 통과한 것만)
func joined_count() -> int:
	return _slots.size()


func player_of(peer_id: int) -> int:
	return _clients.get(peer_id, {}).get("player_id", -1)


func _process(delta: float) -> void:
	if peer == null:
		return
	peer.poll()
	_read_packets()
	for id in _clients.keys():
		var c: Dictionary = _clients[id]
		c.age += delta
		c.tokens = minf(NetProtocol.RATE_BURST, c.tokens + NetProtocol.RATE_PER_SEC * delta)
		c.view_tokens = minf(NetProtocol.VIEW_BURST, c.view_tokens + NetProtocol.VIEW_PER_SEC * delta)
		c.ignored = maxf(0.0, c.ignored - NetProtocol.RATE_IGNORED_DECAY * delta)
		if c.has("kick_in"):  # 거부한 연결: 클라이언트가 reject를 읽고 스스로 끊을 시간을 준 뒤에도 남아 있으면 끊는다
			c.kick_in -= delta
			if c.kick_in <= 0.0:
				_drop(id)
		elif c.player_id < 0 and c.age > hello_timeout:  # hello를 안 보내는 연결
			Log.warn(Log.Category.NETWORK, "hello가 안 와서 끊음: 연결 %d" % id)
			_drop(id)
	_snap_timer += delta
	_summary_timer += delta
	if _snap_timer >= 1.0 / snap_hz:
		_snap_timer = 0.0
		var with_summary := _summary_timer >= 1.0 / summary_hz
		if with_summary:
			_summary_timer = 0.0
		_broadcast(with_summary)


func _on_peer_connected(id: int) -> void:
	if _clients.size() >= max_connections or _pending_count() >= max_pending:
		refused_connections += 1
		Log.warn(Log.Category.NETWORK, "연결 수 상한이라 바로 끊음: 연결 %d (전체 %d/%d, hello 전 %d/%d)" % [id, _clients.size(), max_connections, _pending_count(), max_pending])
		NetTransport.disconnect_peer(peer, id)
		return
	_clients[id] = {"player_id": -1, "view": -1, "age": 0.0, "name": "", "need_key": true,
		"tokens": NetProtocol.RATE_BURST, "view_tokens": NetProtocol.VIEW_BURST, "ignored": 0.0}
	Log.info(Log.Category.NETWORK, "연결 %d 들어옴 (hello 기다림)" % id)


## 지금 열려 있는 연결 수 (hello 전 연결 포함)
func connection_count() -> int:
	return _clients.size()


## hello를 아직 안 보낸(자리를 안 가진) 연결 수
func _pending_count() -> int:
	return _clients.size() - _slots.size()


func _on_peer_disconnected(id: int) -> void:
	var c: Dictionary = _clients.get(id, {})
	_clients.erase(id)
	_send_warn_at.erase(id)
	if c.is_empty():
		return
	if c.player_id >= 0:
		_slots.erase(c.player_id)
		Log.info(Log.Category.NETWORK, "P%d 연결 끊김 (연결 %d)" % [c.player_id + 1, id])
		client_left.emit(id, c.player_id)


## 연결을 서버가 끊는다. 입장했던 클라이언트면 자리를 비우고 client_left를 낸다 (한 번만: 이 함수가 목록에서 먼저 지우므로
## 곧 오는 peer_disconnected는 아무것도 안 한다).
func _drop(id: int) -> void:
	var c: Dictionary = _clients.get(id, {})
	_clients.erase(id)  # 끊기는 중에 온 패킷은 무시한다
	_send_warn_at.erase(id)
	NetTransport.disconnect_peer(peer, id)
	if not c.is_empty() and c.player_id >= 0:
		_slots.erase(c.player_id)
		Log.info(Log.Category.NETWORK, "P%d를 서버가 끊음 (연결 %d)" % [c.player_id + 1, id])
		client_left.emit(id, c.player_id)


# ---- 받기 ------------------------------------------------------------------

func _read_packets() -> void:
	while peer != null and peer.get_available_packet_count() > 0:
		var from := peer.get_packet_peer()  # 순서 주의: 보낸 이는 get_packet() 전에 읽는다
		var bytes := peer.get_packet()
		if not _clients.has(from):
			continue
		if bytes.size() > NetProtocol.MAX_CLIENT_PACKET:
			Log.warn(Log.Category.NETWORK, "너무 큰 패킷 (%d바이트): 연결 %d 끊음" % [bytes.size(), from])
			_drop(from)
			continue
		_on_message(from, NetProtocol.decode(bytes))


func _on_message(id: int, msg: Dictionary) -> void:
	var c: Dictionary = _clients[id]
	if c.has("kick_in"):
		return  # 이미 거부한 연결의 메시지는 무시한다
	if not _take_token(id, c, msg.get("t", "") == NetProtocol.MSG_VIEW):
		if msg.get("t", "") == NetProtocol.MSG_CMD and c.player_id >= 0:  # 명령은 기다리는 쪽이 있으니 거절 사유를 알려 준다
			_send(id, {"t": NetProtocol.MSG_RESULT, "seq": msg.get("seq", 0), "ok": false, "reason": "rate_limited", "events": []})
		return
	if c.player_id < 0:  # hello 전에는 hello만 받는다
		_on_hello(id, c, msg)
		return
	match msg.get("t", ""):
		NetProtocol.MSG_CMD:
			_on_cmd(id, c, msg)
		NetProtocol.MSG_VIEW:
			var lane = msg.get("lane")
			if typeof(lane) in [TYPE_INT, TYPE_FLOAT] and _is_lane(int(lane)) and int(lane) != c.view:
				c.view = int(lane)
				c.need_key = true  # 새로 보는 레인은 전체를 한 번 받아야 한다
		NetProtocol.MSG_PING:
			_send(id, {"t": NetProtocol.MSG_PONG, "n": msg.get("n", 0)}, true)
		_:
			Log.debug(Log.Category.NETWORK, "모르는 메시지 무시: %s (연결 %d)" % [str(msg.get("t", "?")).left(20), id])


## 메시지 하나를 받아 줄지 정한다 (토큰 통). 모자라면 무시하고, 계속 퍼부으면 연결을 끊는다.
## view는 일반 통에 더해 view 전용 통도 통과해야 한다 (키프레임이 비싸서).
func _take_token(id: int, c: Dictionary, is_view: bool) -> bool:
	var ok: bool = c.tokens >= 1.0 and (not is_view or c.view_tokens >= 1.0)
	if ok:
		c.tokens -= 1.0
		if is_view:
			c.view_tokens -= 1.0
		return true
	ignored_messages += 1
	c.ignored += 1.0
	if c.ignored > NetProtocol.RATE_IGNORED_LIMIT:
		Log.warn(Log.Category.NETWORK, "메시지를 너무 많이 보내서 끊음: 연결 %d (무시한 메시지 누적 %.0f)" % [id, c.ignored])
		_drop(id)
	return false


func _is_lane(lane: int) -> bool:
	return lane == GameField.BOSS_LANE_ID or field.session.is_participant(lane)


func _on_hello(id: int, c: Dictionary, msg: Dictionary) -> void:
	var bad := NetProtocol.check_hello(msg)
	if bad == "" and field.bus.started:
		bad = NetProtocol.REJECT_STARTED
	var slot := -1
	if bad == "":
		for pid in field.session.participants:
			if not _slots.has(pid):
				slot = pid
				break
		if slot < 0:
			bad = NetProtocol.REJECT_FULL
	if bad != "":
		Log.warn(Log.Category.NETWORK, "접속 거부: 연결 %d (%s) 클라이언트 프로토콜 %s / 스냅샷 %s / 앱 '%s'" % [id, bad, str(msg.get("proto", "?")), str(msg.get("snapshot", "?")), str(msg.get("game", "")).left(20)])
		_send(id, {"t": NetProtocol.MSG_REJECT, "reason": bad, "proto": NetProtocol.PROTOCOL_VERSION, "snapshot": Snapshot.VERSION}, true)
		# 바로 끊으면 엔진이 그 연결에서 아직 안 읽힌 패킷(reject)을 버려서 클라이언트가 이유를 모른다.
		# 그래서 클라이언트가 reject를 읽고 스스로 끊게 두고, 안 끊으면 REJECT_GRACE초 뒤에 끊는다.
		c["kick_in"] = REJECT_GRACE
		return
	c.player_id = slot
	c.view = slot
	c.name = str(msg.get("name", "")).left(24)
	_slots[slot] = id
	_send(id, {"t": NetProtocol.MSG_WELCOME, "proto": NetProtocol.PROTOCOL_VERSION, "player_id": slot,
		"players": field.session.participants.duplicate(), "snap_hz": snap_hz, "summary_hz": summary_hz}, true)
	Log.info(Log.Category.NETWORK, "P%d 입장: 연결 %d '%s' (앱 '%s')" % [slot + 1, id, c.name, str(msg.get("game", "")).left(20)])
	client_joined.emit(id, slot)
	if start_when_full and not field.bus.started and _slots.size() == field.session.participants.size():
		Log.info(Log.Category.NETWORK, "자리가 다 차서 시작")
		field.bus.execute(Command.make(Command.START_GAME, field.session.participants[0], {}))


func _on_cmd(id: int, c: Dictionary, msg: Dictionary) -> void:
	var seq = msg.get("seq", 0)
	var cmd := Command.from_wire(str(msg.get("cmd", "")))
	var result: Dictionary
	if cmd.is_empty():
		result = CommandBus.fail("bad_command")
	elif cmd["player_id"] != c.player_id:
		# 다른 플레이어를 사칭한 명령: 실행하지 않는다 (번호는 서버가 정해 준 것만 인정)
		Log.warn(Log.Category.NETWORK, "사칭 명령 거절: 연결 %d는 P%d인데 P%d로 보냄 (%s)" % [id, c.player_id + 1, cmd["player_id"] + 1, cmd["type"]])
		result = CommandBus.fail("not_your_player")
	else:
		result = field.bus.execute(cmd)
	_send(id, {"t": NetProtocol.MSG_RESULT, "seq": seq, "ok": result["ok"], "reason": result["reason"], "events": _wire_events(result["events"])}, true)


## 명령 결과의 이벤트에는 Vector2i가 들어 있다: JSON으로 보내도록 [x, y]로 바꾼다
static func _wire_events(events: Array) -> Array:
	var out: Array = []
	for ev in events:
		var e := {}
		for k in ev:
			e[k] = [ev[k].x, ev[k].y] if ev[k] is Vector2i else ev[k]
		out.append(e)
	return out


# ---- 보내기 ----------------------------------------------------------------

func _on_sim_event(ev: Dictionary) -> void:
	if not _clients.is_empty():
		_pending_events.append(ev)


## 모든 메시지를 신뢰 순서로 보낸다. 스냅샷/요약은 별도 채널(ENet에서 다른 메시지와 서로 안 막히게)이고, WebSocket은 채널이 없다.
## 보내기가 실패하면(버퍼보다 큰 메시지, 대기열이 가득 참) false. 스냅샷/요약이 실패하면 그 클라이언트는 이전 틱 위에 변경분을 쌓을 수 없으니
## 다음 틱에 키프레임으로 다시 맞춘다 (조용히 어긋난 채로 남지 않게).
func _send(id: int, msg: Dictionary, general := true) -> bool:
	if peer == null:
		return false
	var bytes := NetProtocol.encode(msg)
	peer.set_target_peer(id)
	peer.transfer_channel = NetProtocol.CHANNEL_RELIABLE if general else NetProtocol.CHANNEL_SNAPSHOT
	peer.transfer_mode = MultiplayerPeer.TRANSFER_MODE_RELIABLE
	var err := ERR_OUT_OF_MEMORY if NetTransport.would_overflow(peer, id, bytes.size()) else peer.put_packet(bytes)
	var kind: String = msg["t"]
	if err != OK:
		failed_sends += 1
		var now := Time.get_ticks_msec()
		if now - _send_warn_at.get(id, -SEND_WARN_INTERVAL_MS) >= SEND_WARN_INTERVAL_MS:
			_send_warn_at[id] = now
			Log.warn(Log.Category.NETWORK, "보내기 실패: 연결 %d, %s %d바이트 (%s). 키프레임으로 다시 맞춘다" % [id, kind, bytes.size(), error_string(err)])
		if _clients.has(id) and kind in [NetProtocol.MSG_SNAP, NetProtocol.MSG_SUMMARY]:
			_clients[id].need_key = true
		return false
	sent_packets += 1
	largest_packet = maxi(largest_packet, bytes.size())
	sent_bytes[kind] = sent_bytes.get(kind, 0) + bytes.size()
	return true


func _broadcast(with_summary: bool) -> void:
	_tick += 1
	var q := SnapshotDelta.quantize(field.snapshot(true))
	var delta := SnapshotDelta.diff(_prev_q, q) if not _prev_q.is_empty() else {}
	_prev_q = q
	var events := _pending_events
	_pending_events = []
	for id in _clients:
		var c: Dictionary = _clients[id]
		if c.player_id < 0:
			continue
		if c.need_key:
			c.need_key = false  # 보내기가 실패하면 _send가 다시 켠다
			if _send(id, {"t": NetProtocol.MSG_SNAP, "tick": _tick, "key": true, "snap": slice_for(q, c.player_id, c.view)}, false):
				keyframes_sent += 1
		else:
			var part := slice_delta(delta, c.player_id, c.view)
			if not part.is_empty():
				_send(id, {"t": NetProtocol.MSG_SNAP, "tick": _tick, "key": false, "snap": part}, false)
		if with_summary:
			_send(id, {"t": NetProtocol.MSG_SUMMARY, "tick": _tick, "summary": summary_for(q, c.player_id, c.view)}, false)
		var mine := events.filter(func(ev): return _event_for(ev, c.player_id, c.view))
		if not mine.is_empty():
			_send(id, {"t": NetProtocol.MSG_EVENTS, "list": mine})


## 이 이벤트를 이 클라이언트에게 보내는가. 레인이 붙은 연출(fx_*)은 그 레인을 보고 있을 때만, 나머지(배너, 게임 끝)는 모두에게.
static func _event_for(ev: Dictionary, player_id: int, view: int) -> bool:
	if ev.has("lane") and ev["type"].begins_with("fx_"):
		return ev["lane"] == view
	return true


## 전체 스냅샷(키프레임)에서 한 클라이언트가 받을 부분만 자른다.
##   - 자기 레인(own)과 보고 있는 레인(view)은 전부, 보스 레인(HUD용 보스 상태)은 항상
##   - 보스 레인을 보고 있지 않으면 보스의 몬스터 목록은 비운다 (미니맵 점은 요약으로 대신)
static func slice_for(snap: Dictionary, own: int, view: int) -> Dictionary:
	var lanes := {}
	for key in snap.lanes:
		var lane_id := int(key)
		if lane_id == own or lane_id == view:
			lanes[key] = snap.lanes[key]
	var boss: Dictionary = snap.boss
	if not boss.is_empty() and view != GameField.BOSS_LANE_ID:
		boss = boss.duplicate()
		boss["monsters"] = []
	return {"v": snap.v, "boss_lane": snap.boss_lane, "players": snap.players, "lanes": lanes, "boss": boss}


## 틱 사이의 변경분(SnapshotDelta.diff 결과 전체)에서 한 클라이언트가 받을 부분만 자른다. slice_for와 같은 범위여야 한다.
static func slice_delta(delta: Dictionary, own: int, view: int) -> Dictionary:
	var out := {}
	for key in delta:
		match key:
			"lanes":
				var lanes := {}
				for lane_key in delta.lanes:
					if lane_key != SnapshotDelta.REMOVED and (int(lane_key) == own or int(lane_key) == view):
						lanes[lane_key] = delta.lanes[lane_key]
				if not lanes.is_empty():
					out["lanes"] = lanes
			"boss":
				var boss: Dictionary = delta.boss
				if view != GameField.BOSS_LANE_ID and boss.has("monsters"):
					boss = boss.duplicate()
					boss.erase("monsters")  # 보스 레인을 안 보는 클라이언트의 기준 몬스터 목록은 늘 비어 있다
				if not boss.is_empty():
					out["boss"] = boss
			_:
				out[key] = delta[key]
	return out


## 미니맵이 그리는 값: 자기/보고 있는 레인을 뺀 나머지 레인의 타워 칸과 몬스터 점.
## 몬스터 점은 칸 하나에 하나만 남긴다 (미니맵 점은 2.5픽셀이라 한 칸 안의 여럿은 구별이 안 된다. 보스 레인에 수백 마리가 서 있을 때 크기를 줄인다).
static func summary_for(snap: Dictionary, own: int, view: int) -> Dictionary:
	var out := {}
	for key in snap.lanes:
		var lane_id := int(key)
		if lane_id != own and lane_id != view:
			out[key] = lane_summary(snap.lanes[key])
	if not snap.boss.is_empty() and view != GameField.BOSS_LANE_ID:
		out[str(GameField.BOSS_LANE_ID)] = {"towers": [], "monsters": _dots(snap.boss.monsters)}
	return out


## 미니맵이 그리는 값만: 타워 칸과 몬스터 위치
static func lane_summary(lane: Dictionary) -> Dictionary:
	var towers: Array = []
	for t in lane.towers:
		towers.append(t.cell)
	return {"towers": towers, "monsters": _dots(lane.monsters)}


static func _dots(monsters: Array) -> Array:
	var seen := {}
	var dots: Array = []
	for m in monsters:
		var cell := [floori(m.pos[0]), floori(m.pos[1])]
		var key: int = cell[0] * 1000 + cell[1]
		if not seen.has(key):
			seen[key] = true
			dots.append([cell[0] + 0.5, cell[1] + 0.5])
	return dots
