class_name NetBot
extends Node
## 네트워크 봇 (#28): 진짜 NetClient로 서버에 접속해 사람과 똑같은 명령(건설/몬스터 보내기)만 보내는 자동 플레이어.
## AutoPlayer는 서버 안에서 CommandBus를 직접 부르는 봇이고(서버 단독 시험용), 이 봇은 소켓을 거치는 클라이언트 쪽이다.
## 규칙은 단순하다: 1초마다 격자 칸 하나에 타워를 짓고 몬스터 하나를 보낸다 (골드가 모자라면 서버가 거절한다. 그것도 시험 대상이다).
## 쓰는 곳: tests/test_mp_*.gd(다인원 시험), tools/bench/loadgen_sim.gd(부하 측정).
## 스스로 재는 값: 명령 결과(성공/사유별 실패 수), 내 레인 골드의 최저값(마이너스 방지 확인), 스냅샷 간격(화면 튐), 끝난 판의 결과.

const TOWER_ROTATION := ["long", "long", "splash"]   # 공중 전용 타워는 지상 몬스터를 못 맞혀서 뺐다 (AutoPlayer와 같다)
const SEND_ORDER := ["rusher", "warrior", "knight"]
const RICH_SEND_ORDER := ["giant", "crusher", "knight", "warrior"]   # 골드가 넉넉할 때(테스트가 서버 쪽에서 채워 줄 때) 보내는 비싼 몬스터 (AutoPlayer와 같다)
const EVOLUTION_PICK := {"long": "pierce", "splash": "mass", "air": "barrage"}   # AutoPlayer와 같다: 종류별로 공격력이 오르는 진화
const SMART_FIRST := 10       # 똑똑한 봇: 먼저 이만큼 짓고 진화시킨 뒤 더 짓는다
const SMART_MAX := 30

var client: NetClient
var is_host := false
var play_interval := 1.0        # 이 간격(초, 게임 시간)마다 한 번 둔다
var send_order: Array = SEND_ORDER
var smart := false              # true면 AutoPlayer처럼 둔다(타워 10기 -> 진화 -> 30기, 남는 골드로 몬스터). false면 1초마다 타워 하나 + 몬스터 하나 (부하 측정이 쓰던 단순한 규칙)
var view_lane := -1             # 0 이상이면 판이 시작될 때 이 레인을 "보는 중"으로 서버에 알린다 (보스 레인이면 GameField.BOSS_LANE_ID: 몬스터 목록 전체가 스냅샷으로 온다 = 최대 대역폭)
var build_enabled := true
var send_enabled := true
var cells: Array[Vector2i] = []
var over := {}                  # game_over 이벤트를 받으면 {victory, reason}

## 센 값
var sent := 0
var results := 0
var ok_count := 0
var fail_reasons := {}          # 사유 -> 횟수
var min_gold := INF             # 내 레인 골드가 스냅샷에서 가장 낮았던 값
var negative_gold_seen := false
var snapshots := 0
var max_gap_ms := 0.0           # 연속한 스냅샷 사이의 가장 긴 간격 (실제 시간, ms). 화면이 얼마나 멈췄다 튀는가
var gap_sum_ms := 0.0
var gap_count := 0
var tick_jump_max := 0          # 연속한 스냅샷의 틱 번호 차이의 최댓값 (1이 정상. 늘어나면 중간 스냅샷을 못 받고 건너뛴 것)
var _last_snap_ms := -1
var _last_tick := 0
var _timer := 0.0
var _kind_i := 0
var _send_i := 0
var _ready_sent := false
var _view_sent := false


func setup(p_client: NetClient) -> void:
	client = p_client
	_fill_cells()
	client.snapshot_received.connect(_on_snapshot)
	client.command_result.connect(_on_result)
	client.events_received.connect(_on_events)
	client.reconnected.connect(func(): _last_snap_ms = -1)  # 재접속 직후의 첫 스냅샷은 간격에 넣지 않는다 (끊긴 시간은 따로 잰다)


func _fill_cells() -> void:
	cells.clear()
	for y in range(8, GridSystem.GRID_HEIGHT - 6, 2):
		for x in range(1, GridSystem.GRID_WIDTH - 1, 2):
			cells.append(Vector2i(x, y))


## 간격/명령 통계를 0으로 돌린다 (구간별로 따로 재려고). 판 상태(over, cells)는 그대로.
func reset_stats() -> void:
	sent = 0
	results = 0
	ok_count = 0
	fail_reasons = {}
	snapshots = 0
	max_gap_ms = 0.0
	gap_sum_ms = 0.0
	gap_count = 0
	tick_jump_max = 0
	_last_snap_ms = -1


func average_gap_ms() -> float:
	return gap_sum_ms / gap_count if gap_count > 0 else 0.0


func _on_snapshot(snap: Dictionary) -> void:
	snapshots += 1
	var now := Time.get_ticks_msec()
	if _last_snap_ms >= 0:
		var gap := float(now - _last_snap_ms)
		max_gap_ms = maxf(max_gap_ms, gap)
		gap_sum_ms += gap
		gap_count += 1
		if client.last_tick > _last_tick:
			tick_jump_max = maxi(tick_jump_max, client.last_tick - _last_tick)
	_last_snap_ms = now
	_last_tick = client.last_tick
	var lane: Dictionary = snap.get("lanes", {}).get(str(client.player_id), {})
	if lane.has("gold"):
		min_gold = minf(min_gold, float(lane.gold))
		if float(lane.gold) < 0.0:
			negative_gold_seen = true


func _on_result(_seq: int, ok: bool, reason: String, _events: Array) -> void:
	results += 1
	if ok:
		ok_count += 1
	else:
		fail_reasons[reason] = fail_reasons.get(reason, 0) + 1


func _on_events(list: Array) -> void:
	for ev in list:
		if ev.get("type", "") == "game_over":
			over = {"victory": bool(ev.get("victory", false)), "reason": str(ev.get("reason", ""))}


func _process(delta: float) -> void:
	if client == null or not client.in_game or not client.is_joined() or not over.is_empty():
		return
	if view_lane >= 0 and not _view_sent:
		_view_sent = true
		client.set_view(view_lane)
	_timer += delta
	if _timer < play_interval:
		return
	_timer = 0.0
	play_once()


## 한 번 둔다: 타워 하나 + 몬스터 하나 (보낸 명령 수는 sent)
func play_once() -> void:
	if smart:
		_play_smart()
		return
	if build_enabled and not cells.is_empty():
		var kind: String = TOWER_ROTATION[_kind_i % TOWER_ROTATION.size()]
		if client.send(Command.BUILD_TOWER, {"cell": cells[0], "kind_id": kind, "confirmed": false}) >= 0:
			sent += 1
			cells.pop_front()  # 실패해도 다음 칸으로 (칸을 붙들고 있지 않는다)
			_kind_i += 1
	if send_enabled:
		if client.send(Command.SEND_MONSTER, {"kind_id": send_order[_send_i % send_order.size()]}) >= 0:
			sent += 1
		_send_i += 1


## 로비에서 준비하고, 방장이면 전원이 모였을 때 시작한다. in_game이 되면 true.
## 대기방 사람들을 모으는 쪽(테스트/부하 도구)이 매 프레임 불러도 된다.
func lobby_step(expected_players: int) -> bool:
	if client == null:
		return false
	if client.in_game:
		return true
	if not client.is_joined():
		return false
	if not _ready_sent:
		_ready_sent = true
		client.set_ready(true)
	elif is_host and client.lobby.get("can_start", false) and client.lobby.get("members", []).size() >= expected_players:
		client.request_start()  # 전원이 모여 준비한 뒤에만 시작한다
	return false


## 똑똑한 규칙: 내 레인 스냅샷을 보고 둔다 (사람이 화면을 보고 누르는 것과 같다).
func _play_smart() -> void:
	var lane: Dictionary = client.snapshot.get("lanes", {}).get(str(client.player_id), {})
	if lane.is_empty() or not lane.get("active", true):
		return
	var towers: Array = lane.get("towers", [])
	if towers.size() < SMART_FIRST:
		_build_some(SMART_FIRST - towers.size())
		return
	var evolved := 0
	for t in towers:
		if t.get("evo", "x") == "" and EVOLUTION_PICK.has(t.get("kind", "")) and evolved < 3:
			if client.send(Command.EVOLVE_TOWER, {"cell": Vector2i(int(t.cell[0]), int(t.cell[1])), "evo": EVOLUTION_PICK[t.kind]}) >= 0:
				sent += 1
				evolved += 1
	if evolved > 0:
		return
	if towers.size() < SMART_MAX and not cells.is_empty():
		_build_some(SMART_MAX - towers.size())
		return
	if float(lane.get("gold", 0.0)) >= 60.0 or towers.size() >= SMART_MAX:
		if client.send(Command.SEND_MONSTER, {"kind_id": send_order[_send_i % send_order.size()]}) >= 0:
			sent += 1
		_send_i += 1


func _build_some(want: int) -> void:
	for i in range(mini(want, 4)):
		if cells.is_empty():
			return
		var kind: String = TOWER_ROTATION[_kind_i % TOWER_ROTATION.size()]
		if client.send(Command.BUILD_TOWER, {"cell": cells[0], "kind_id": kind, "confirmed": false}) >= 0:
			sent += 1
			cells.pop_front()
			_kind_i += 1
