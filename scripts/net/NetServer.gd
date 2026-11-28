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
## 끊김/재접속/이탈 (#23): 판이 시작되면 접속자마다 "자리"(_seats)를 만든다. 연결이 끊기거나(하트비트 시간 초과 포함) 사라져도 레인은 그대로 싸우고(수입은 쌓이고 몬스터는 온다),
##   유예(reconnect_grace) 안에 같은 토큰(Identity)으로 hello를 보내면 같은 레인으로 복귀한다(키프레임부터 다시). 유예가 지나거나 [나가기](leave)를 보내면 이탈로 처리해 #22의 탈락과 똑같이 한다.
##   명령은 받는 즉시 실행하고 쌓아 두지 않으며, 연결이 끊긴 뒤 그 연결에서 온 것은 무시한다. 방장(host_lane)은 표시용이고, 이탈하면 입장 순서상 다음 사람에게 넘어간다.
##   화면에 보여 줄 끊김/이탈/방장 정보는 presence 메시지로 모두에게 보낸다.
## 권위: 플레이어 번호는 서버가 접속 때 정해 준다. 명령 안의 player_id가 그 연결의 번호와 다르면 실행하지 않고 거절한다.

signal client_joined(peer_id: int, player_id: int)
signal client_left(peer_id: int, player_id: int)
signal seat_away(player_id: int)        # 끊겼다 (유예 시작) (#23)
signal seat_back(player_id: int)        # 유예 안에 돌아왔다
signal seat_left(player_id: int)        # 이탈 처리됐다 (유예 끝 / 나가기)

const SNAP_HZ := 10.0       # 자기 레인/보고 있는 레인/보스 레인 (HUD와 움직임)
const SUMMARY_HZ := 1.0     # 나머지 레인 (미니맵용 점)
const REJECT_GRACE := 1.0   # 거부 메시지를 보낸 뒤 연결을 강제로 끊기까지(초)
const SEND_WARN_INTERVAL_MS := 2000  # 같은 연결의 보내기 실패 경고는 이 간격(밀리초)에 한 번만

var field: GameField
var peer: MultiplayerPeer
var transport := NetTransport.DEFAULT
var snap_hz := SNAP_HZ
var summary_hz := SUMMARY_HZ
## 로비 (#22). 주면 로비 방식이다: field 없이 start()를 부르고, 사람이 모이면 field_factory로 판을 만든다.
## 로비 방식에서는 참여자(레인)가 시작 순간 접속자로 확정된다 (session.participants/names를 이 서버가 채운다).
var lobby: Lobby = null
var session: Session = null           # 로비 방식에서 판이 시작될 때 참여자/이름을 채우는 세션 (field_factory가 만드는 GameField가 같은 것을 쓴다)
var field_factory := Callable()       # () -> GameField. 참여자가 확정된 뒤에 부른다. 만든 필드는 이미 트리에 붙어 있어야 한다
var game_started := false             # 로비 방식에서 판이 실제로 시작됐는가
var _lobby_dirty := false
## 방 모드 (#26). RoomHub가 소켓을 쥐고 연결을 방마다 나눠 준다: 이 NetServer는 방 하나이고 소켓을 열지 않는다(start_hosted).
## 연결/끊김/메시지는 hub가 admit/receive/peer_gone으로 넘겨 준다.
var hub: Node = null
var room_code := ""                  # 방 코드 (hub가 정해 준다). 로비/환영 메시지에 실어 보낸다
var public_room := false             # 공개 방: 빠른 시작이 자리 있는 공개 방을 찾아 넣는다 (#26)
var game_mode := Session.MODE_COOP   # 방의 게임 모드 (PvP는 범위 밖: 필드만 둔다)
var start_when_full := false  # 참여자 자리가 다 차면 서버가 시작 명령을 실행한다 (로비가 생기기 전의 임시 규칙. 로비는 #22)
var max_connections := NetProtocol.MAX_CONNECTIONS  # 테스트가 줄인다
var max_pending := NetProtocol.MAX_PENDING
var reconnect_grace := NetProtocol.RECONNECT_GRACE_SEC       # 끊긴 뒤 돌아올 수 있는 시간(초). 지나면 이탈 (#23). 테스트가 줄인다
var heartbeat_timeout := NetProtocol.HEARTBEAT_TIMEOUT_SEC   # 판 중 이 시간(초) 동안 그 연결에서 아무것도 못 받으면 끊김으로 본다 (#23)
var finished := false                # 판이 끝났다(전체 승리/패배) (#54). 끝난 판은 자리를 "끝남"으로 두고 끊김/이탈 판정, 이탈 배너, 방장 승계를 멈춘다. 결과 화면에서 ping을 보내든 끊든 서버는 똑같이 동작한다
var host_lane := -1                  # 판이 시작된 뒤의 방장 레인 (화면 표시용: 서버 권위형이라 방장 권한은 대기방에서만 의미가 있다). 이탈하면 입장 순서상 다음 사람으로 (#23)
var hello_timeout := NetProtocol.HELLO_TIMEOUT  # hello를 이 시간(초) 안에 안 보내면 끊는다 (테스트가 줄인다)
## 판 기록용 (#25): 판이 시작된 시각(unix 초)과 시작 뒤 흐른 게임 시간(초). 판 기록(MatchRecord)이 읽는다 (서버가 센 값만 쓴다)
var started_unix := 0
var game_seconds := 0.0

var keepalive_sec := NetProtocol.KEEPALIVE_SEC   # 테스트가 줄인다 (#24)
var _clients: Dictionary = {}     # peer_id -> {player_id: int(-1 = 아직 hello 전), view: int, age: float, name: String, token_hash, account: 계정 ID("" = 게스트), silent}
var _seats: Dictionary = {}       # 판이 시작될 때 만든 자리: 레인 -> {hash: 토큰 해시, account: 계정 ID, name, away: 끊겨서 유예 중, left: 이탈, away_sec: 남은 유예}. 재접속은 이 자리의 주인(Identity)만 한다 (#23)
var _join_order: Array[int] = []  # 입장 순서의 레인 (방장 승계 순서)
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
## 방송(_broadcast) 구간별 걸린 시간 (마이크로초) (#28 부하 측정): 키 snapshot(전체 스냅샷 만들기) / quantize / diff / send(클라이언트별 자르기+인코딩+보내기) / total.
## 각 값은 {n, sum, max, last}. 측정 도구(tools/bench/measure_load.gd)와 테스트가 읽는다. 켜 둬도 비용은 틱당 시계 읽기 몇 번뿐이다.
var perf := {}
var window_largest := 0          # take_perf 이후 보낸 가장 큰 메시지(바이트)
var window_snap_bytes := 0       # take_perf 이후 보낸 스냅샷(snap) 메시지 바이트 합 (모든 클라이언트)
var window_snap_clients := 0     # take_perf 이후 방송 때 스냅샷을 받을 수 있는 클라이언트 수의 합 (틱 x 클라이언트): 클라이언트당 값을 구하려고
var _send_warn_at := {}           # peer_id -> 마지막으로 보내기 실패를 로그한 시각(ms). 같은 연결의 반복 로그를 줄인다


## 소켓을 열고 시뮬레이션 곁에 붙는다. 실패하면 오류 코드. tls를 주면 wss (WebSocket만).
func start(p_field: GameField, kind: String, port: int, tls: TLSOptions = null) -> Error:
	if not NetTransport.is_known(kind):
		return ERR_INVALID_PARAMETER
	field = p_field
	if field == null and (lobby == null or session == null or not field_factory.is_valid()):
		return ERR_UNCONFIGURED  # field도 없고 로비 설정도 없다
	transport = kind
	peer = NetTransport.create_server(kind, port, tls)
	if peer == null:
		return ERR_CANT_CREATE
	peer.peer_connected.connect(_on_peer_connected)
	peer.peer_disconnected.connect(_on_peer_disconnected)
	if field != null:
		field.session.events.emitted.connect(_on_sim_event)
	if lobby != null:
		lobby.changed.connect(func(): _lobby_dirty = true)
	Log.info(Log.Category.NETWORK, "서버 열림: %s 포트 %d (프로토콜 %d, 스냅샷 %.0fHz + 요약 %.1fHz)" % [kind, port, NetProtocol.PROTOCOL_VERSION, snap_hz, summary_hz])
	return OK


## 방 모드로 붙는다 (#26): 소켓은 hub의 것이라 열지 않고 공유한다. 로비 설정이 있어야 한다.
func start_hosted(p_hub: Node, shared_peer: MultiplayerPeer, kind: String) -> Error:
	if lobby == null or session == null or not field_factory.is_valid():
		return ERR_UNCONFIGURED
	hub = p_hub
	peer = shared_peer
	transport = kind
	lobby.changed.connect(func(): _lobby_dirty = true)
	return OK


func stop() -> void:
	if peer != null:
		if hub == null:  # 방 모드의 소켓은 hub가 닫는다
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


## 이 방에 아직 있는 사람 수: 접속 중 + 끊겼지만 유예 중인 사람 (방을 닫을지 정할 때 쓴다) (#23)
## 끝난 판은 유예 중인 사람을 세지 않는다: 접속자가 없으면 유예를 기다리지 않고 바로 닫힌다 (#54).
func alive_count() -> int:
	var n := _slots.size()
	if finished:
		return n
	for lane in _seats:
		if _seats[lane].away and not _seats[lane].left:
			n += 1
	return n


## 이 레인의 자리가 끊겨서 유예 중인가 / 이탈했는가 (테스트와 화면 표시용)
func is_away(lane: int) -> bool:
	return not finished and _seats.has(lane) and _seats[lane].away and not _seats[lane].left


func has_left(lane: int) -> bool:
	return _seats.has(lane) and _seats[lane].left


## 판이 끝났다 (#54): 모든 자리는 "끝남"이다. 유예 중이던 끊김은 취소하고(이탈로 넘어가지 않는다), 하트비트로 끊지도 않고,
## 이탈 배너/방장 승계도 하지 않는다. 화면의 끊김 배너는 지워진다(presence). 한 번만 동작한다.
func mark_finished() -> void:
	if finished:
		return
	finished = true
	Log.info(Log.Category.NETWORK, "판 끝: 자리를 끝남으로 두고 끊김/이탈 판정을 멈춘다 (접속 %d명)" % _slots.size())
	_send_presence()


## 판(GameField)의 보스가 끝나면(전체 승리/패배) mark_finished를 부른다. 보스는 한 프레임 뒤에 만들어져서 신호로 기다린다.
func _watch_finish(f: GameField) -> void:
	var hook := func(boss: BossController):
		if boss == null:
			return
		boss.boss_defeated.connect(mark_finished)
		boss.boss_failed.connect(func(_reason: String): mark_finished())
	if f.boss != null:
		hook.call(f.boss)
	else:
		f.boss_ready.connect(hook, CONNECT_ONE_SHOT)


## 이 레인의 자리 정보 {hash, account, name, away, left, ...} (없으면 빈 Dictionary). 판 기록이 읽는다 (#25)
func seat_of(lane: int) -> Dictionary:
	return _seats.get(lane, {})


## 같은 계정의 다른 연결이 이 방에 이미 들어와 있으면 내보낸다 (판 시작 전 대기방. 시작된 뒤의 같은 계정은 _resume이 옛 연결을 대체한다) (#25)
func _replace_old_connection(new_id: int, account: String) -> void:
	for old in _clients.keys():
		if old != new_id and _clients[old].get("account", "") == account and _clients[old].player_id >= 0:
			Log.info(Log.Category.NETWORK, "같은 계정의 옛 연결 %d를 내보냄 (새 연결 %d)" % [old, new_id])
			_drop(old)


## 이 토큰이 이 판의 자리 주인인가 (RoomHub가 끝난 방에서 "판이 끝났다"를 알려 줄 사람을 가릴 때 쓴다) (#54)
func owns_seat(token) -> bool:
	return _seat_for_token(token) >= 0


func player_of(peer_id: int) -> int:
	return _clients.get(peer_id, {}).get("player_id", -1)


func _process(delta: float) -> void:
	if peer == null:
		return
	if hub == null:
		peer.poll()
		_read_packets()
	for id in _clients.keys():
		var c: Dictionary = _clients[id]
		c.age += delta
		c.tx_idle += delta
		if c.player_id >= 0 and c.tx_idle >= keepalive_sec:
			_send(id, {"t": NetProtocol.MSG_PONG, "n": 0}, true)  # 데이터가 오가게 해서 유휴 연결로 끊기지 않게 한다. 클라이언트는 n=0 pong을 그냥 센다
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
		elif c.player_id >= 0 and not _seats.is_empty() and not finished:  # 판 중 하트비트 (끝난 판은 안 본다 #54): 클라이언트는 3초마다 ping을 보낸다 (#23)
			c.silent += delta
			if c.silent > heartbeat_timeout:
				Log.warn(Log.Category.NETWORK, "P%d에게서 %.0f초 동안 아무것도 못 받아 끊김으로 봄 (연결 %d)" % [c.player_id + 1, c.silent, id])
				_drop(id)
	_tick_away(delta)
	if field != null and game_started and not finished:
		game_seconds += delta
	if lobby != null and field == null:
		_process_lobby(delta)
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
	_clients[id] = _new_client()
	Log.info(Log.Category.NETWORK, "연결 %d 들어옴 (hello 기다림)" % id)


func _new_client() -> Dictionary:
	return {"player_id": -1, "view": -1, "age": 0.0, "name": "", "need_key": true, "token_hash": "", "account": "", "silent": 0.0, "tx_idle": 0.0,
		"tokens": NetProtocol.RATE_BURST, "view_tokens": NetProtocol.VIEW_BURST, "ignored": 0.0}


## 방 모드: 지금 새 사람이 들어올 수 있는 대기방인가 (시작 전이고 자리가 있다)
func is_open() -> bool:
	return lobby != null and field == null and not game_started and lobby.phase == Lobby.Phase.OPEN and lobby.size() < lobby.max_players


## 방 모드: hub가 이 방으로 보낸 연결의 hello를 받는다 (hub가 버전/방 코드는 이미 확인했다). 방이 거부하면(가득/이미 시작) reject를 보내고 곧 끊는다.
## auth는 계정 확인 결과 (Accounts.login: {account_id, nickname, name_result, guest}). 비어 있으면 계정 없이 hello의 이름/토큰을 그대로 쓴다.
func admit(id: int, hello: Dictionary, auth: Dictionary = {}) -> void:
	_clients[id] = _new_client()
	_clients[id]["auth"] = auth
	_on_hello(id, _clients[id], hello)


## 방 모드: hub가 이 방 연결의 메시지를 넘겨 준다
func receive(id: int, msg: Dictionary) -> void:
	if _clients.has(id):
		_on_message(id, msg)


## 방 모드: 이 방 연결이 끊겼다
func peer_gone(id: int) -> void:
	_on_peer_disconnected(id)


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
		Log.info(Log.Category.NETWORK, "P%d 연결 끊김 (연결 %d)" % [c.player_id + 1, id])
		_release(id, c, false)


## 연결을 서버가 끊는다. 입장했던 클라이언트면 자리를 비우고 client_left를 낸다 (한 번만: 이 함수가 목록에서 먼저 지우므로
## 곧 오는 peer_disconnected는 아무것도 안 한다).
func _drop(id: int) -> void:
	var c: Dictionary = _clients.get(id, {})
	_clients.erase(id)  # 끊기는 중에 온 패킷은 무시한다
	_send_warn_at.erase(id)
	NetTransport.disconnect_peer(peer, id)
	if not c.is_empty() and c.player_id >= 0:
		Log.info(Log.Category.NETWORK, "P%d를 서버가 끊음 (연결 %d)" % [c.player_id + 1, id])
		_release(id, c, false)


## 입장했던 연결이 사라졌다. 판이 시작된 뒤면 자리를 비우지 않고 "끊김(유예)"으로 두고, 의도적으로 나간 것(leave)이면 바로 이탈로 처리한다.
## 시작 전(대기방)이면 로비에서 빠진다. 이 연결의 명령은 서버에 쌓아 두지 않으므로(받는 즉시 실행) 돌아와도 옛 명령이 실행되지 않는다.
func _release(id: int, c: Dictionary, intentional: bool) -> void:
	var pid: int = c.player_id
	if _slots.get(pid, -1) == id:
		_slots.erase(pid)
	if _seats.has(pid):
		if intentional:
			_leave_seat(pid, "나가기")
		else:
			_go_away(pid)
	else:
		_leave_lobby(id)
	client_left.emit(id, pid)


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
	c.silent = 0.0  # 무슨 메시지든 살아 있다는 뜻이다 (하트비트)
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
		NetProtocol.MSG_READY:
			if lobby != null and field == null and typeof(msg.get("on")) == TYPE_BOOL:
				lobby.set_ready(id, msg["on"])
		NetProtocol.MSG_START:
			if lobby != null and field == null and lobby.host_start(id):
				Log.info(Log.Category.NETWORK, "방장(P%d)이 시작했다 (%d명)" % [c.player_id + 1, lobby.size()])
				_begin_game()
		NetProtocol.MSG_VIEW:
			var lane = msg.get("lane")
			if field != null and typeof(lane) in [TYPE_INT, TYPE_FLOAT] and _is_lane(int(lane)) and int(lane) != c.view:
				c.view = int(lane)
				c.need_key = true  # 새로 보는 레인은 전체를 한 번 받아야 한다
		NetProtocol.MSG_PING:
			_send(id, {"t": NetProtocol.MSG_PONG, "n": msg.get("n", 0)}, true)
		NetProtocol.MSG_LEAVE:  # 의도적 이탈: 유예 없이 바로 이탈 (#23)
			_clients.erase(id)
			_send_warn_at.erase(id)
			NetTransport.disconnect_peer(peer, id)
			Log.info(Log.Category.NETWORK, "P%d가 나갔다 (연결 %d)" % [c.player_id + 1, id])
			_release(id, c, true)
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
	if field == null:
		return false
	return lane == GameField.BOSS_LANE_ID or field.session.is_participant(lane)


func _on_hello(id: int, c: Dictionary, msg: Dictionary) -> void:
	var bad := NetProtocol.check_hello(msg)
	if bad == "" and (game_started or (field != null and field.bus.started)):
		# 이미 시작한 판: 이 판의 자리 주인(토큰이 맞는 사람)만 같은 레인으로 돌아온다 (#23)
		var seat_lane := _seat_for_token(msg.get("token"))
		if finished and seat_lane >= 0:  # 끝난 판의 자리 주인이 돌아오려 한다: 판이 끝났다고 알린다 (#54)
			bad = NetProtocol.REJECT_FINISHED
		elif seat_lane >= 0 and not _seats[seat_lane].left:
			_resume(id, c, seat_lane)
			return
		if bad == "":
			bad = NetProtocol.REJECT_LEFT if seat_lane >= 0 else NetProtocol.REJECT_STARTED
	var slot := -1
	var auth: Dictionary = c.get("auth", {})
	var account := str(auth.get("account_id", ""))
	if bad == "" and account != "":
		_replace_old_connection(id, account)  # 같은 계정의 옛 연결(앱이 죽었는데 서버는 아직 모른다)이 대기방에 남아 있으면 그것을 내보낸다: 한 계정이 한 방에 두 번 앉지 않게
	var nick := Nicknames.unique(str(auth.get("nickname", msg.get("name", ""))), _taken_names())
	if bad == "" and lobby != null:
		var joined := lobby.join(id, nick)
		if joined.ok:
			slot = joined.lane
		else:
			bad = joined.reason
	elif bad == "":
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
	c.name = nick
	c.token_hash = Identity.hash_of(str(msg["token"])) if Identity.valid_token(msg.get("token")) else ""
	c.account = account
	_slots[slot] = id
	var roster: Array = [] if field == null else field.session.participants.duplicate()
	if field != null:
		field.session.names[slot] = nick
	_send(id, {"t": NetProtocol.MSG_WELCOME, "proto": NetProtocol.PROTOCOL_VERSION, "player_id": slot, "name": nick,
		"players": roster, "snap_hz": snap_hz, "summary_hz": summary_hz, "room": room_code, "mode": game_mode,
		"name_result": str(auth.get("name_result", "")), "guest": bool(auth.get("guest", false))}, true)
	Log.info(Log.Category.NETWORK, "P%d 입장: 연결 %d '%s' (앱 '%s')" % [slot + 1, id, c.name, str(msg.get("game", "")).left(20)])
	client_joined.emit(id, slot)
	if lobby != null:
		_lobby_dirty = true
		return
	if start_when_full and not field.bus.started and _slots.size() == field.session.participants.size():
		Log.info(Log.Category.NETWORK, "자리가 다 차서 시작")
		field.bus.execute(Command.make(Command.START_GAME, field.session.participants[0], {}))


func _on_cmd(id: int, c: Dictionary, msg: Dictionary) -> void:
	var seq = msg.get("seq", 0)
	var cmd := Command.from_wire(str(msg.get("cmd", "")))
	var result: Dictionary
	if field == null:
		result = CommandBus.fail("not_started")  # 로비 중: 아직 판이 없다
	elif cmd.is_empty():
		result = CommandBus.fail("bad_command")
	elif cmd["type"] == Command.SET_PAUSE and lobby != null:
		result = CommandBus.fail("pause_not_allowed")  # 온라인 방의 시뮬레이션은 한 사람이 멈출 수 없다 (서버는 여러 방을 같이 돌린다)
	elif cmd["player_id"] != c.player_id:
		# 다른 플레이어를 사칭한 명령: 실행하지 않는다 (번호는 서버가 정해 준 것만 인정)
		Log.warn(Log.Category.NETWORK, "사칭 명령 거절: 연결 %d는 P%d인데 P%d로 보냄 (%s)" % [id, c.player_id + 1, cmd["player_id"] + 1, cmd["type"]])
		result = CommandBus.fail("not_your_player")
	else:
		var t0 := Time.get_ticks_usec()
		result = field.bus.execute(cmd)
		_note_perf("cmd_" + str(cmd["type"]), Time.get_ticks_usec() - t0)  # 명령 종류별 실행 시간 (건설이 길 찾기를 다시 해서 오래 걸리는지 등)
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

## 지금 쓰는 닉네임들 (중복을 피하려고)
func _taken_names() -> Array:
	var out: Array = []
	for c in _clients.values():
		if c.player_id >= 0:
			out.append(c.name)
	return out


# ---- 로비 (#22) ------------------------------------------------------------

func _leave_lobby(id: int) -> void:
	if lobby != null and field == null:
		lobby.leave(id)


func _process_lobby(_delta: float) -> void:
	if _lobby_dirty and lobby.phase == Lobby.Phase.OPEN:
		_lobby_dirty = false
		_send_lobby()


func _send_lobby() -> void:
	var msg := lobby.view()
	msg["t"] = NetProtocol.MSG_LOBBY
	msg["room"] = room_code
	msg["mode"] = game_mode
	msg["public"] = public_room
	for id in _clients:
		if _clients[id].player_id >= 0:
			_send(id, msg, true)


## 참여자를 확정하고 판(GameField)을 만들어 시작한다. 판이 준비되려면 프레임이 몇 개 걸려서 코루틴이다.
## 그동안 lobby.phase는 STARTING이라 새 입장은 거부된다.
func _begin_game() -> void:
	if game_started:
		return
	game_started = true
	var lanes := lobby.lanes()
	session.participants.clear()
	for lane in lanes:
		session.participants.append(lane)
	session.names = lobby.names_by_lane()
	_make_seats()
	Log.info(Log.Category.NETWORK, "판 시작: 참여 %d명 레인 %s" % [lanes.size(), lanes])
	var f: GameField = field_factory.call()
	if f == null:
		# 판을 못 만들면 시작 중인 채로 멈춰 있지 않게 대기방을 다시 연다 (참여자 확정을 되돌리고, 모두에게 대기방 상태를 다시 보낸다)
		Log.error(Log.Category.NETWORK, "판을 만들지 못함: 대기방으로 되돌린다")
		game_started = false
		session.participants.clear()
		session.names = {}
		lobby.reopen()
		_lobby_dirty = true
		return
	_watch_finish(f)
	await f.boss_ready  # 보스는 한 프레임 뒤에 만들어진다
	field = f
	started_unix = int(Time.get_unix_time_from_system())
	game_seconds = 0.0
	for lane in _seats:  # 판을 만드는 동안 이탈한 사람의 레인은 바로 무너뜨린다
		if _seats[lane].left:
			_forfeit_lane(lane)
	field.session.events.emitted.connect(_on_sim_event)
	_prev_q = {}
	for c in _clients.values():
		c.need_key = true
	lobby.mark_started()
	var names := {}
	for lane in lanes:
		names[str(lane)] = session.name_of(lane)
	for id in _clients:
		if _clients[id].player_id >= 0:
			_send(id, {"t": NetProtocol.MSG_STARTED, "players": lanes, "names": names}, true)
	_send_presence()
	# 방장이 [시작]을 누르면 바로 시작한다 (입장 후 자동 시작 대기는 없다). 첫 몬스터는 웨이브 주기(Balance.INCOME_INTERVAL, 30초) 뒤에 나온다.
	var started := field.bus.execute(Command.make(Command.START_GAME, field.session.participants[0], {}))
	if not started["ok"]:
		Log.error(Log.Category.NETWORK, "시작 실패: %s" % started["reason"])


# ---- 끊김 / 재접속 / 이탈 (#23) --------------------------------------------

## 판이 시작될 때 접속자마다 자리를 만든다 (토큰 해시로 재접속 주인을 가린다). 지금 접속 중인 사람이 처음 주인이다.
func _make_seats() -> void:
	_seats.clear()
	_join_order = lobby.lanes_in_join_order()
	host_lane = -1 if _join_order.is_empty() else _join_order[0]
	for id in _clients:
		var c: Dictionary = _clients[id]
		c.silent = 0.0
		if c.player_id >= 0:
			_seats[c.player_id] = {"hash": c.token_hash, "account": c.account, "name": c.name, "away": false, "left": false, "away_sec": 0.0}


## 이 토큰의 주인인 자리의 레인 (이탈한 자리 포함). 없으면 -1.
func _seat_for_token(token) -> int:
	for lane in _seats:
		if Identity.authorize(_seats[lane].hash, token):
			return lane
	return -1


## 끊김: 레인은 그대로 둔다 (수입은 쌓이고 몬스터는 오고 타워는 자동으로 싸운다). 유예 시간 안에 돌아오지 않으면 이탈.
func _go_away(lane: int) -> void:
	var seat: Dictionary = _seats[lane]
	if finished or seat.left or seat.away:  # 끝난 판에서는 끊겨도 아무 일도 아니다 (배너/유예 없음) (#54)
		return
	seat.away = true
	seat.away_sec = reconnect_grace
	Log.info(Log.Category.NETWORK, "P%d 끊김: %.0f초 안에 돌아오지 않으면 이탈" % [lane + 1, reconnect_grace])
	seat_away.emit(lane)
	_send_presence({"kind": "away", "lane": lane})


func _tick_away(delta: float) -> void:
	if finished:
		return
	for lane in _seats.keys():
		var seat: Dictionary = _seats[lane]
		if seat.away and not seat.left:
			seat.away_sec -= delta
			if seat.away_sec <= 0.0:
				_leave_seat(lane, "유예 시간 끝")


## 이탈: #22의 탈락과 똑같이 처리한다 (레인이 무너지고 보스 레인의 그 사람 몬스터는 철수. 난이도 인원과 기여도 기록은 그대로).
## 방장이 이탈하면 입장 순서상 다음 사람이 방장이 된다.
func _leave_seat(lane: int, why: String) -> void:
	var seat: Dictionary = _seats[lane]
	if seat.left or finished:  # 끝난 판에서 나가는 것은 이탈이 아니다: 레인/방장/배너를 건드리지 않는다 (#54)
		return
	seat.left = true
	seat.away = false
	Log.info(Log.Category.NETWORK, "P%d 이탈 (%s)" % [lane + 1, why])
	_forfeit_lane(lane)
	seat_left.emit(lane)
	var notes: Array = [{"kind": "left", "lane": lane}]
	if lane == host_lane:
		host_lane = -1
		for next in _join_order:
			if not _seats[next].left:
				host_lane = next
				break
		if host_lane >= 0:
			Log.info(Log.Category.NETWORK, "방장이 P%d로 바뀜" % [host_lane + 1])
			notes.append({"kind": "host", "lane": host_lane})
	for note in notes:
		_send_presence(note)


func _forfeit_lane(lane: int) -> void:
	if field == null or not field.lanes.has(lane):
		return
	var l: LaneController = field.lanes[lane]
	if l.active:
		l.shutdown()
		l.lane_failed.emit(lane)  # 보스(BossController)가 철수/전체 패배를 판단한다


## 같은 토큰의 사람이 돌아왔다: 같은 레인에 새 연결을 붙인다. 이미 접속 중인 연결(끊긴 줄 모르는 옛 연결)이 있으면 그것을 끊는다.
func _resume(id: int, c: Dictionary, lane: int) -> void:
	var seat: Dictionary = _seats[lane]
	var old: int = _slots.get(lane, -1)
	if old >= 0 and old != id:
		_clients.erase(old)  # 옛 연결이 늦게 보내는 것은 무시된다 (옛 명령이 실행되지 않는다)
		_send_warn_at.erase(old)
		NetTransport.disconnect_peer(peer, old)
	var was_away: bool = seat.away
	seat.away = false
	c.player_id = lane
	c.view = lane
	c.name = seat.name
	c.token_hash = seat.hash
	c.account = seat.get("account", "")
	c.need_key = true  # 전체 스냅샷(키프레임)을 다시 보낸다
	c.silent = 0.0
	_slots[lane] = id
	var names := {}
	for l in session.participants:
		names[str(l)] = session.name_of(l)
	_send(id, {"t": NetProtocol.MSG_WELCOME, "proto": NetProtocol.PROTOCOL_VERSION, "player_id": lane, "name": seat.name,
		"players": lobby.lanes(), "names": names, "resumed": true, "snap_hz": snap_hz, "summary_hz": summary_hz, "room": room_code, "mode": game_mode}, true)
	Log.info(Log.Category.NETWORK, "P%d 재접속: 연결 %d (%s)" % [lane + 1, id, "유예 안" if was_away else "옛 연결을 대체"])
	client_joined.emit(id, lane)
	if was_away:
		seat_back.emit(lane)
	_send_presence({"kind": "back", "lane": lane} if was_away else {})


func _presence_msg(note: Dictionary) -> Dictionary:
	var away: Array = []
	var left: Array = []
	for lane in _seats:
		if _seats[lane].left:
			left.append(lane)
		elif _seats[lane].away:
			away.append(lane)
	away.sort()
	left.sort()
	if finished:
		away = []  # 끝난 판: 끊김 표시는 없다 (#54)
	var msg := {"t": NetProtocol.MSG_PRESENCE, "away": away, "left": left, "host": host_lane}
	if not note.is_empty():
		msg["note"] = note
	return msg


func _send_presence(note := {}) -> void:
	var msg := _presence_msg(note)
	for id in _clients:
		if _clients[id].player_id >= 0:
			_send(id, msg, true)


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
	if _clients.has(id):
		_clients[id].tx_idle = 0.0
	sent_packets += 1
	largest_packet = maxi(largest_packet, bytes.size())
	window_largest = maxi(window_largest, bytes.size())
	if kind == NetProtocol.MSG_SNAP:
		window_snap_bytes += bytes.size()
	sent_bytes[kind] = sent_bytes.get(kind, 0) + bytes.size()
	return true


func _broadcast(with_summary: bool) -> void:
	if field == null:
		return  # 로비 중: 보낼 판이 없다
	_tick += 1
	var t0 := Time.get_ticks_usec()
	var raw := field.snapshot(true)
	var t1 := Time.get_ticks_usec()
	var q := SnapshotDelta.quantize(raw)
	var t2 := Time.get_ticks_usec()
	var delta := SnapshotDelta.diff(_prev_q, q) if not _prev_q.is_empty() else {}
	var t3 := Time.get_ticks_usec()
	_prev_q = q
	var events := _pending_events
	_pending_events = []
	for id in _clients:
		var c: Dictionary = _clients[id]
		if c.player_id < 0:
			continue
		window_snap_clients += 1
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
	var t4 := Time.get_ticks_usec()
	_note_perf("snapshot", t1 - t0)
	_note_perf("quantize", t2 - t1)
	_note_perf("diff", t3 - t2)
	_note_perf("send", t4 - t3)
	_note_perf("total", t4 - t0)


## 지금까지 모은 방송 시간과 가장 큰 메시지를 돌려주고 비운다 (ServerMetrics가 구간마다 부른다)
func take_perf() -> Dictionary:
	var out := {"perf": perf, "largest": window_largest, "snap_bytes": window_snap_bytes, "snap_clients": window_snap_clients}
	perf = {}
	window_largest = 0
	window_snap_bytes = 0
	window_snap_clients = 0
	return out


func _note_perf(key: String, usec: int) -> void:
	var p: Dictionary = perf.get(key, {"n": 0, "sum": 0, "max": 0, "last": 0})
	p.n += 1
	p.sum += usec
	p.max = maxi(p.max, usec)
	p.last = usec
	perf[key] = p


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
	return {"v": snap.v, "boss_lane": snap.boss_lane, "players": snap.players, "names": snap.get("names", {}), "lanes": lanes, "boss": boss}


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
	return {"towers": towers, "monsters": _dots(lane.monsters), "lives": lane.lives, "active": lane.active}


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
