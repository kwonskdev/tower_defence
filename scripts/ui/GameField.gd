extends ScrollContainer
class_name GameField

var grid_renderer: GridRenderer

const MAX_PLAYERS = Balance.MAX_PLAYERS
const BOSS_LANE_ID = 8  # grid_systems[8] = 보스 레인 (미니맵의 B)
var grid_systems: Array[GridSystem] = []
var lanes: Dictionary = {}  # player_id -> LaneController (참여한 플레이어만)
var current_player_id: int = 0  # 지금 화면에 보고 있는 레인
var session := Session.new()    # 내 플레이어 번호와 참여자 목록 (add_child 전에 바꿔 끼울 수 있다. 기본값은 1인 플레이)
var boss: BossController
var lane_scroll_rows: Dictionary = {}  # 레인별로 마지막에 보던 위치 (맨 위 줄 번호). 레인을 바꿔도 각자 위치를 기억한다
var selected_tower_kind: String = Balance.TOWER_KINDS[0]

var current_tool: PlacementTool = PlacementTool.NONE
signal path_block_confirm(cell: Vector2i)  # 이 타워를 지으면 길이 막힌다: 사용자에게 확인을 받아야 한다
signal command_failed(type: String, reason: String)  # 내가 보낸 명령이 거절됐다 (UI가 사유를 안내한다)
signal tower_selected()           # 맵에서 지어진 타워를 눌러 선택했다 (건설 모드 중이어도: 상단이 그 타워 화면으로 바뀐다)
signal boss_ready(boss: BossController)    # 보스가 만들어졌다 (한 프레임 기다린 뒤라서 MainGame._ready 시점에는 아직 없다)

var awaiting_confirm: bool = false  # 길 막힘 확인을 기다리는 중 (이 클릭으로는 타워 선택/해제를 하지 않는다)
var bus: CommandBus  # 상태를 바꾸는 행동은 모두 여기를 지난다 (setup_game_field에서 만든다)
var selected_lane := -1                 # 클릭해서 선택한 타워의 레인 번호 (-1 = 선택 없음)
var selected_cell := Vector2i(-1, -1)   # 클릭해서 선택한 타워의 칸. 타워 정보는 스냅샷에서 읽는다 (정보/업그레이드 대상)
var side_inset: float = 0.0  # 화면 좌우 안전 여백의 합 (폰 노치/둥근 모서리). 맵이 쓰는 폭 = 화면 폭 - 이 값
var ui_blockers: Array[Control] = []  # 이 영역 위의 클릭은 맵 클릭으로 처리하지 않는다 (필드 위에 겹친 UI)

# 마우스 드래그 스크롤 변수들
var is_dragging: bool = false
var drag_start_position: Vector2
var drag_start_scroll: Vector2
var drag_threshold: float = 20.0  # 드래그로 인식할 최소 거리

enum PlacementTool {
	NONE,
	TOWER
}

func _ready():
	setup_game_field()
	setup_scroll_container()

func setup_game_field():
	current_player_id = session.local_player_id  # 처음에는 내 레인을 본다
	bus = CommandBus.new(session, lanes)
	session.events.emitted.connect(_on_sim_event)
	grid_renderer = GridRenderer.new()
	grid_renderer.name = "GridRenderer"
	add_child(grid_renderer)
	if play_effects:  # 화면이 있는 클라이언트만: 서버 스냅샷으로 타워/몬스터를 그린다
		map_view = MapView.new(grid_renderer)
		add_child(map_view)

	# 8명의 플레이어를 위한 그리드 시스템 생성
	for i in range(MAX_PLAYERS + 1):
		var grid_system = GridSystem.new()
		grid_system.name = "GridSystem_" + str(i)
		grid_system.player_id = i
		grid_system.is_boss_lane = (i == BOSS_LANE_ID)
		add_child(grid_system)
		grid_systems.append(grid_system)

	# 첫 번째 플레이어의 그리드를 표시
	get_current_grid_system().connect_renderer(grid_renderer)

	await get_tree().process_frame

	# 모든 플레이어의 맵 초기화
	for grid_system in grid_systems:
		grid_system.setup_game_path()

	# 화면 크기에 맞춰 그리드 조정
	if grid_renderer:
		var container_width = _field_width()
		grid_renderer.set_container_width(container_width)

	# 창/화면 크기가 나중에 바뀌어도(폰 회전, 시작 직후 창 크기 확정 등) 칸 크기를 화면 폭에 맞춘다
	get_viewport().size_changed.connect(func():
		var w := _field_width()
		if w > 0.0 and int(w / GridRenderer.GRID_WIDTH) != grid_renderer.CELL_SIZE:
			grid_renderer.set_container_width(w))

	if remote != null:
		_setup_remote()
		return

	# 참여자의 레인만 만든다 (나머지 레인은 비어 있음)
	for player_id in session.participants:
		start_lane(player_id)
	start_boss()

## 맵이 쓰는 폭. 레이아웃이 끝나기 전에도 틀리지 않도록 노드 크기 대신 화면 폭에서 좌우 여백을 뺀다
func _field_width() -> float:
	return get_viewport_rect().size.x - side_inset


## 좌우 안전 여백이 바뀌면 칸 크기를 다시 맞춘다
func set_side_inset(value: float) -> void:
	side_inset = value
	if grid_renderer != null:
		var w := _field_width()
		if w > 0.0 and int(w / GridRenderer.GRID_WIDTH) != grid_renderer.CELL_SIZE:
			grid_renderer.set_container_width(w)


## 명령을 실행하고 결과({ok, reason, events})를 돌려준다. UI는 상태를 바꾸는 모든 행동을 여기로 보낸다.
## 연출 이벤트는 여기(클라이언트)에서만 재생한다. 서버는 CommandBus를 직접 쓰고 이벤트를 무시한다.
func execute(cmd: Dictionary) -> Dictionary:
	if remote != null:
		return _execute_remote(cmd)
	var result := bus.execute(cmd)
	_snapshot_frame = -1  # 명령이 상태를 바꿨으니 캐시된 스냅샷은 낡았다
	_play_events(result["events"])
	return result


## 지금 서버 상태 스냅샷. 화면(HUD)은 시뮬레이션 객체 대신 이것을 읽는다. 같은 프레임 안에서는 한 번만 만든다.
var _snapshot: Dictionary = {}
var _snapshot_frame := -1

func snapshot(fresh := false) -> Dictionary:
	if remote != null:
		return _remote_snapshot()
	var frame := Engine.get_process_frames()
	if fresh or frame != _snapshot_frame:
		_snapshot = Snapshot.build(session, lanes, boss)
		_snapshot_frame = frame
	return _snapshot


## 연출을 그릴지 (= 화면이 있는 클라이언트인지). 서버(ServerMain)는 화면이 없으니 끈다: 시뮬레이션은 이벤트를 내보내기만 하고 그리지 않는다.
var play_effects := true

## 온라인 모드 (#26): 주면 이 화면은 시뮬레이션을 만들지 않고 서버에 접속한 NetClient의 스냅샷/이벤트를 그린다.
## 명령은 서버로 보내고(결과는 command_result로 늦게 온다), 보는 레인을 바꾸면 서버에 알린다. add_child 전에 정한다.
var remote: NetClient = null
var _remote_pending: Dictionary = {}   # seq -> 보낸 명령 (결과가 오면 사유 안내/길 막힘 확인에 쓴다)
var _grid_mirror: Dictionary = {}      # 레인 -> {Vector2i: CellState}: 서버 스냅샷의 타워 칸을 이쪽 격자에도 칠한다 (칸 색)
var _warnings: Array = []  # 떠 있는 슬라임 예고 표식
var map_view: MapView = null  # 스냅샷으로 타워/몬스터를 그리는 껍데기들 (서버에는 없다)
var boss_view: BossController.BossView = null  # 보스 몸통 (스냅샷으로 그린다)
var boss_bar: BossController.BossBar = null    # 보스 체력바/기여도 (스냅샷으로 그린다)


func _process(_delta: float) -> void:
	if remote != null:
		_mirror_grid(remote.snapshot)
	if map_view == null or (boss == null and remote == null):
		return
	var sel_key := ""
	if selected_lane >= 0:
		sel_key = "%d:%d:%d" % [selected_lane, selected_cell.x, selected_cell.y]
	var snap := snapshot()
	map_view.sync(snap, current_player_id, sel_key)
	if boss_view != null:
		boss_view.state = snap.boss
		boss_bar.state = snap.boss
		boss_view.visible = current_player_id == BOSS_LANE_ID
		boss_bar.visible = boss_view.visible


## 시뮬레이션이 내보낸 연출 이벤트(SimEvents)를 받아 그린다. 레인이 지금 보이는지는 여기(클라이언트)가 정한다.
func _on_sim_event(ev: Dictionary) -> void:
	if not play_effects:
		return
	if ev["type"] in ["skill_announced", "game_over"]:
		return  # 배너와 결과 창은 화면(MainGame)이 받아서 보여 준다
	if ev["type"] == "fx_warn_clear":
		for w in _warnings:
			if is_instance_valid(w):
				w.queue_free()
		_warnings.clear()
		return
	var lane_id: int = ev["lane"]
	var shown := lane_id == current_player_id  # 보고 있는 레인에서만 보인다 (화면이 정한다)
	match ev["type"]:
		"fx_ring":
			Effects.ring(grid_renderer, Vector2(ev["pos"][0], ev["pos"][1]), ev["radius"], Color.html(ev["color"]), shown)
		"fx_text":
			Effects.float_text(grid_renderer, Vector2(ev["pos"][0], ev["pos"][1]), ev["text"], Color.html(ev["color"]), shown)
		"fx_shot":
			var target: Monster = map_view.monster_node(lane_id, ev["target"]) if map_view != null else null
			Effects.view_projectile(grid_renderer, ev, target, shown)
		"fx_cloud":
			Effects.view_cloud(grid_renderer, ev, shown)
		"fx_warn":
			var warning := BossController.SpawnWarning.new()
			warning.renderer = grid_renderer
			warning.cell = Vector2i(ev["cell"][0], ev["cell"][1])
			warning.total = ev["seconds"]
			warning.left = warning.total
			warning.z_index = 3
			warning.is_shown = func(): return current_player_id == lane_id
			warning.visible = shown
			grid_renderer.add_child(warning)
			_warnings.append(warning)
		_:
			pass


## 연출 이벤트 재생. 모르는 이벤트(예: pause)는 무시한다 (MainGame이 직접 처리한다).
func _play_events(events: Array) -> void:
	for ev in events:
		var cell: Vector2i = ev.get("cell", Vector2i.ZERO)
		var center := Vector2(cell) + Vector2(0.5, 0.5)
		var shown: bool = ev.get("player_id", -1) == current_player_id  # 보고 있는 레인에서만 보인다
		match ev["type"]:
			"tower_evolved", "skill_learned":
				Effects.ring(grid_renderer, center, 0.8, Evolutions.DATA[ev["evo"]].color, shown)
			"tower_recolored":
				Effects.ring(grid_renderer, center, 0.8, _tower_color(ev["color_name"]), shown)
			"tower_healed":
				Effects.ring(grid_renderer, center, 0.8, Color(0.4, 1.0, 0.5), shown)
			"tower_sold":  # "파괴!" 없이 얻은 골드만 띄운다
				Effects.float_text(grid_renderer, center, "판매 +%d" % ev["gold"], Color(1.0, 0.9, 0.3), shown)


func _tower_color(color_name: String) -> Color:
	for c in Balance.TOWER_COLORS:
		if c.name == color_name:
			return c.color
	return Color.WHITE


## 내 플레이어의 명령을 만들어 실행한다 (UI에서 가장 흔한 경우)
func do_command(type: String, args: Dictionary = {}) -> Dictionary:
	var result := execute(Command.make(type, session.local_player_id, args))
	if not result["ok"]:
		Log.debug(Log.Category.UI, "명령 거절: %s -> %s" % [type, result["reason"]])
		command_failed.emit(type, result["reason"])
	return result

func start_lane(player_id: int):
	var lane := LaneController.new()
	lane.name = "Lane_" + str(player_id)
	lane.rng = session.rng  # 시뮬레이션 랜덤은 세션 하나를 같이 쓴다
	lane.events = session.events
	lane.show_nodes = not play_effects  # 그리는 쪽은 MapView 껍데기
	add_child(lane)
	lane.setup(player_id, grid_systems[player_id], grid_renderer)
	lane.set_lane_visible(player_id == current_player_id)
	lanes[player_id] = lane
	_snapshot_frame = -1  # 레인이 늘었으니 캐시된 스냅샷은 낡았다

func start_boss():
	boss = BossController.new()
	boss.name = "Boss"
	boss.rng = session.rng
	boss.events = session.events
	boss.show_nodes = not play_effects
	add_child(boss)
	bus.boss = boss
	boss.setup(grid_systems[BOSS_LANE_ID], grid_renderer, lanes)
	boss.set_lane_visible(current_player_id == BOSS_LANE_ID)
	_snapshot_frame = -1
	if play_effects:  # 화면이 있는 클라이언트: 보스 몸통과 체력바는 스냅샷으로 그린다
		_make_boss_views()
	boss_ready.emit(boss)

	# 각 레인에 boss 참조 설정 (남색 색깔 보너스용)
	for lane in lanes.values():
		lane._boss_controller = boss

func _make_boss_views() -> void:
	boss_view = BossController.BossView.new()
	boss_view.renderer = grid_renderer
	boss_view.z_index = 0
	grid_renderer.add_child(boss_view)
	boss_bar = BossController.BossBar.new()
	boss_bar.renderer = grid_renderer
	boss_bar.z_index = 5
	grid_renderer.add_child(boss_bar)


# ---- 온라인 모드 (#26) -------------------------------------------------------

## 시뮬레이션 없이 서버 스냅샷으로 그릴 준비. 보스 레인의 몸통 칸은 서버와 같게 막힌 칸으로 칠한다.
func _setup_remote() -> void:
	var boss_grid := grid_systems[BOSS_LANE_ID]
	var radius := Balance.BOSS_RADIUS + 0.25
	for y in range(GridSystem.GRID_HEIGHT):
		for x in range(GridSystem.GRID_WIDTH):
			if (Vector2(x, y) + Vector2(0.5, 0.5)).distance_to(Balance.BOSS_CENTER) <= radius:
				boss_grid.set_cell_state(Vector2i(x, y), GridSystem.CellState.OBSTACLE)
	_make_boss_views()
	remote.events_received.connect(_on_remote_events)
	remote.command_result.connect(_on_remote_result)
	boss_ready.emit(null)  # 보스 객체는 서버에만 있다. MainGame은 이 신호로 이벤트 연결을 시작한다


## 서버가 보내 준 스냅샷 (아직 못 받았으면 빈 모양). 화면은 이것만 읽는다.
func _remote_snapshot() -> Dictionary:
	if remote.snapshot.is_empty():
		return {"v": Snapshot.VERSION, "boss_lane": BOSS_LANE_ID, "players": session.participants, "names": {}, "lanes": {}, "boss": {}}
	return remote.snapshot


## 지금 보고 있는 레인을 서버에 다시 알린다 (재접속 뒤: 서버는 새 연결의 보는 레인을 내 레인으로 시작한다)
func set_view_remote() -> void:
	if remote != null:
		remote.set_view(current_player_id)
		_remote_pending.clear()  # 끊긴 동안 보낸 명령의 결과는 오지 않는다 (옛 명령은 서버가 실행하지 않았다)


## 미니맵용 요약 (자기/보고 있는 레인을 뺀 나머지 레인. 1Hz). 온라인이 아니거나 없으면 빈 Dictionary
func summary_of(lane_id: int) -> Dictionary:
	if remote == null:
		return {}
	return remote.summary.get(str(lane_id), {})


## 명령을 서버로 보낸다. 결과는 늦게 오므로 일단 보냈다는 뜻으로 성공을 돌려주고, 거절은 command_result가 알린다 (_on_remote_result).
func _execute_remote(cmd: Dictionary) -> Dictionary:
	var seq := remote.send_command(cmd)
	if seq < 0:
		return {"ok": false, "reason": "not_connected", "events": []}
	_remote_pending[seq] = cmd
	return {"ok": true, "reason": "", "events": []}


func _on_remote_result(seq: int, ok: bool, reason: String, events: Array) -> void:
	var cmd: Dictionary = _remote_pending.get(seq, {})
	_remote_pending.erase(seq)
	if cmd.is_empty():
		return
	if ok:
		var evs: Array = []
		for ev in events:
			var e: Dictionary = ev.duplicate()
			if e.has("cell") and e["cell"] is Array and e["cell"].size() == 2:
				e["cell"] = Vector2i(int(e["cell"][0]), int(e["cell"][1]))  # 선로에서는 [x, y]로 왔다
			evs.append(e)
		_play_events(evs)
		return
	Log.debug(Log.Category.UI, "명령 거절(서버): %s -> %s" % [cmd["type"], reason])
	command_failed.emit(cmd["type"], reason)
	if reason == "path_blocked" and cmd["type"] == Command.BUILD_TOWER:  # 길이 막힌다: 확인받은 뒤 confirmed=true로 다시 보낸다
		awaiting_confirm = true
		path_block_confirm.emit(cmd["cell"])


## 서버가 보낸 연출 이벤트를 시뮬레이션이 내보낸 것과 똑같이 흘려 보낸다 (JSON이라 정수가 실수로 온 것은 바로잡는다)
func _on_remote_events(list: Array) -> void:
	for ev in list:
		var e: Dictionary = ev.duplicate()
		for key in ["lane", "target"]:
			if e.has(key) and (e[key] is float or e[key] is int):
				e[key] = int(e[key])
		session.events.emitted.emit(e)


## 스냅샷의 타워 칸을 이쪽 격자에도 칠한다 (시뮬레이션이 없어서 타워가 격자 상태를 바꾸지 않는다)
func _mirror_grid(snap: Dictionary) -> void:
	for lane_key in snap.get("lanes", {}):
		var lane_id := int(lane_key)
		if lane_id < 0 or lane_id >= grid_systems.size():
			continue
		var now := {}
		for t in snap.lanes[lane_key].towers:
			now[Vector2i(int(t.cell[0]), int(t.cell[1]))] = GridSystem.CellState.TOWER if Balance.tower_kind(t.kind).blocks else GridSystem.CellState.TRAP_TOWER
		var before: Dictionary = _grid_mirror.get(lane_id, {})
		for cell in before:
			if not now.has(cell):
				grid_systems[lane_id].set_cell_state(cell, GridSystem.CellState.EMPTY)
		for cell in now:
			if before.get(cell, -1) != now[cell]:
				grid_systems[lane_id].set_cell_state(cell, now[cell])
		_grid_mirror[lane_id] = now


func setup_scroll_container():
	# 가로 스크롤 비활성화 (세로 드래그 스크롤만 사용)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	# 세로 스크롤바는 숨긴다 (스크롤은 드래그/휠로 하고 위치는 미니맵이 보여 준다).
	# 보이는 스크롤바가 폭을 8px 차지해서 맵 최소 폭이 화면 폭(600)을 넘어 상단 UI까지 좌우 4px씩 잘렸다.
	vertical_scroll_mode = ScrollContainer.SCROLL_MODE_SHOW_NEVER
	follow_focus = true
	# 스크롤은 handle_mouse_input()이 직접 한다. ScrollContainer 자체의 터치 스크롤까지 같이 켜져 있으면
	# 폰에서 손가락 하나로 두 번 스크롤되어 떨리므로 이 노드는 입력을 직접 받지 않게 한다 (_input은 그대로 받는다).
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func _input(event):
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return
	var pos: Vector2 = event.position  # 터치도 마우스 이벤트로 바뀌어 들어온다 (project.godot: emulate_mouse_from_touch)
	if not get_global_rect().has_point(pos):
		return
	for blocker in ui_blockers:
		if blocker.is_visible_in_tree() and blocker.get_global_rect().has_point(pos):
			return

	handle_mouse_input(event)
	# 키보드 입력은 모두 제거 (버튼으로만 제어)

func handle_mouse_input(event):
	if event is InputEventMouseButton:
		if event.pressed and (event.button_index == MOUSE_BUTTON_WHEEL_UP or event.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step := -80 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 80  # PC 휠 스크롤 (이 노드가 입력을 안 받으므로 직접)
			set_v_scroll(clampi(get_v_scroll() + step, 0, int(get_v_scroll_bar().max_value)))
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				# 드래그 준비
				drag_start_position = event.global_position
				drag_start_scroll = Vector2(get_h_scroll(), get_v_scroll())
				is_dragging = false  # 아직 드래그가 아님
			else:
				# 마우스 버튼을 뗐을 때
				if not is_dragging:
					# 드래그하지 않았으면 클릭으로 처리
					handle_cell_click(event)
				is_dragging = false
				drag_start_position = Vector2.ZERO

	elif event is InputEventMouseMotion:
		if drag_start_position != Vector2.ZERO:
			var distance = drag_start_position.distance_to(event.global_position)
			if distance > drag_threshold and not is_dragging:
				# 드래그 시작
				is_dragging = true

			if is_dragging:
				# 드래그 중 세로 스크롤만 업데이트 (좌우 스크롤 비활성화)
				var delta = drag_start_position - event.global_position
				var new_scroll_y = drag_start_scroll.y + delta.y

				var max_scroll_v = get_v_scroll_bar().max_value if get_v_scroll_bar() else 0
				new_scroll_y = clamp(new_scroll_y, 0, max_scroll_v)

				set_v_scroll(int(new_scroll_y))

func handle_cell_click(event):
	if grid_renderer:
		# ScrollContainer의 스크롤 위치를 고려한 실제 클릭 위치 계산
		var scroll_offset = Vector2(get_h_scroll(), get_v_scroll())
		var container_rect = get_global_rect()
		var relative_pos = event.global_position - container_rect.position
		var actual_pos = relative_pos + scroll_offset
		var grid_pos = grid_renderer.screen_to_grid(actual_pos)
		if grid_renderer.is_valid_grid_position(grid_pos):
			_on_grid_cell_clicked(grid_pos)


func _on_grid_cell_clicked(grid_position: Vector2i):
	Log.debug(Log.Category.UI, "셀 클릭 %s (도구=%s)" % [grid_position, PlacementTool.keys()[current_tool]])
	awaiting_confirm = false
	if current_tool == PlacementTool.TOWER and place_tower(grid_position):
		return
	if awaiting_confirm:
		return

	# 건설 도구가 꺼져 있거나 건설할 수 없는 칸이면: 그 칸의 타워를 선택 (타워가 없으면 선택 해제)
	if _tower_view_at(current_player_id, grid_position).is_empty():
		clear_selection()
	else:
		select_tower_at(current_player_id, grid_position)


## 레인의 cell 칸에 있는 타워의 스냅샷 항목 (없으면 빈 Dictionary). 방금 일어난 변화도 보이게 새 스냅샷으로 찾는다.
func _tower_view_at(lane_id: int, cell: Vector2i) -> Dictionary:
	var lane: Dictionary = snapshot(true).lanes.get(str(lane_id), {})
	for t in lane.get("towers", []):
		if t.cell[0] == cell.x and t.cell[1] == cell.y:
			return t
	return {}


## 선택한 타워의 스냅샷 항목 (lane, cell, kind, evo, ... 은 Snapshot 참고). 선택이 없거나 몬스터가 부수는 등으로 사라졌으면 빈 Dictionary (선택도 풀린다).
func get_selected_tower() -> Dictionary:
	if selected_lane < 0:
		return {}
	var lane: Dictionary = snapshot().lanes.get(str(selected_lane), {})
	for t in lane.get("towers", []):
		if t.cell[0] == selected_cell.x and t.cell[1] == selected_cell.y:
			return t
	selected_lane = -1
	return {}


## lane_id 레인의 cell 칸 타워를 선택한다 (없는 칸이면 선택 해제)
func select_tower_at(lane_id: int, cell: Vector2i) -> void:
	var t := _tower_view_at(lane_id, cell)
	if t.is_empty():
		clear_selection()
		return
	selected_lane = lane_id
	selected_cell = cell
	tower_selected.emit()
	Log.info(Log.Category.UI, "타워 선택 %s: %s %s" % [cell, Balance.tower_kind(t.kind).name, Evolutions.evo_name(t.evo) if t.evo != "" else "(진화 전)"])


func clear_selection() -> void:
	selected_lane = -1


## 선택한 타워를 가리키는 칸 좌표 인자. 선택이 없거나 남의 레인의 타워면 빈 Dictionary (명령은 내 레인의 타워만 가리킬 수 있다)
func _selected_cell_args() -> Dictionary:
	var t := get_selected_tower()
	if t.is_empty() or t.lane != session.local_player_id:
		return {}
	return {"cell": Vector2i(t.cell[0], t.cell[1])}


## 선택한 타워에 하는 명령을 보낸다 (선택한 타워가 없으면 보내지 않고 false)
func _do_on_selected(type: String, extra: Dictionary = {}) -> bool:
	var args := _selected_cell_args()
	if args.is_empty():
		command_failed.emit(type, "no_tower")
		return false
	args.merge(extra)
	return do_command(type, args)["ok"]


## 선택한 타워를 진화시킨다 (타워마다 한 번, 처음 계열을 고른다). 내 레인의 타워만 가능.
func evolve_selected_tower(evo: String) -> bool:
	return _do_on_selected(Command.EVOLVE_TOWER, {"evo": evo})


## 업그레이드 탭: 진화 항목 레벨을 올린다 (같은 계열의 모든 타워에 적용)
func upgrade_stat(evo: String, skill: String, key: String) -> bool:
	return do_command(Command.UPGRADE_STAT, {"evo": evo, "skill": skill, "key": key})["ok"]


## 선택한 타워 1기의 색깔을 랜덤으로 바꾼다 (골드)
func recolor_selected_tower() -> bool:
	return _do_on_selected(Command.RECOLOR_TOWER)


## 선택한 타워 1기의 내구도를 가득 채운다 (골드)
func heal_selected_tower() -> bool:
	return _do_on_selected(Command.HEAL_TOWER)


## 선택한 타워를 판다 (투입 골드의 일부 환급). 내 레인의 타워만 가능하고, 팔고 나면 선택이 풀린다.
func sell_selected_tower() -> bool:
	if not _do_on_selected(Command.SELL_TOWER):
		return false
	clear_selection()  # 사라진 타워를 계속 선택하고 있지 않게 (사거리 표시, 타워 화면)
	return true


## 색깔 업그레이드 (골드, 그 색 타워 전체에 적용)
func upgrade_color(color_name: String) -> bool:
	return do_command(Command.UPGRADE_COLOR, {"color_name": color_name})["ok"]


## 선택한 타워 1기의 B 스킬을 배운다 (골드, 타워마다 따로)
func learn_selected_tower_skill() -> bool:
	return _do_on_selected(Command.LEARN_SKILL)

func get_current_grid_system() -> GridSystem:
	return grid_systems[current_player_id]

func switch_player(player_id: int):
	if player_id < 0 or player_id > BOSS_LANE_ID:
		Log.warn(Log.Category.UI, "잘못된 플레이어 전환 요청: %d" % player_id)
		return
	if player_id == current_player_id:
		return

	# 떠나는 레인의 스크롤 위치를 기억해 둔다 (칸 크기가 바뀌어도 되도록 줄 번호로 저장)
	lane_scroll_rows[current_player_id] = get_v_scroll() / float(grid_renderer.CELL_SIZE)

	clear_selection()  # 다른 레인으로 가면 선택 해제

	# 이전 플레이어의 렌더러 연결 해제
	get_current_grid_system().disconnect_renderer()

	# 새 플레이어로 전환
	current_player_id = player_id

	# 새 플레이어의 렌더러 연결
	get_current_grid_system().connect_renderer(grid_renderer)
	if remote != null:
		remote.set_view(player_id)  # 서버는 보고 있는 레인을 자세히 보내 준다

	# 보고 있는 레인의 몬스터만 표시
	for id in lanes:
		lanes[id].set_lane_visible(id == player_id)
	if boss:
		boss.set_lane_visible(player_id == BOSS_LANE_ID)

	# 새 레인에서 마지막으로 보던 위치로 돌아간다
	var row: float = lane_scroll_rows.get(player_id, _default_scroll_row(player_id))
	set_v_scroll(maxi(0, int(row * grid_renderer.CELL_SIZE)))

	Log.info(Log.Category.UI, "레인 전환 -> %s (스크롤 %d번째 줄)" % [get_current_grid_system().lane_tag(), int(row)])

## 처음 보는 레인의 시작 위치. 보스 레인은 보스가 화면 가운데에 오도록 한다.
func _default_scroll_row(lane_id: int) -> float:
	if lane_id == BOSS_LANE_ID:
		var visible_rows := size.y / float(grid_renderer.CELL_SIZE)
		return maxf(0.0, Balance.BOSS_CENTER.y - visible_rows * 0.5)
	return 0.0

## 레인의 row번째 줄이 화면 가운데에 오도록 스크롤한다 (미니맵 클릭/드래그용)
func scroll_to_row(row: float):
	var target := row * grid_renderer.CELL_SIZE - size.y * 0.5
	set_v_scroll(maxi(0, int(target)))

## 건설 명령을 보낸다. confirmed: 길이 막히는 걸 알고도 짓겠다고 사용자가 확인한 경우 true
func place_tower(grid_position: Vector2i, confirmed: bool = false) -> bool:
	# 이미 타워가 있는 칸을 누른 건 건설 실패가 아니라 타워 선택이다 (호출한 쪽이 선택한다). 거절 안내를 띄우지 않는다.
	if not _tower_view_at(current_player_id, grid_position).is_empty():
		return false
	# 보고 있는 레인이 남의 레인이면 클릭한 칸은 내 레인의 칸이 아니다 (명령은 내 레인만 가리킨다)
	if current_player_id != session.local_player_id:
		Log.debug(Log.Category.TOWER, "내 레인이 아니라서 건설 불가 (보는 레인=%s)" % get_current_grid_system().lane_tag())
		command_failed.emit(Command.BUILD_TOWER, "not_my_lane")
		return false
	var result := do_command(Command.BUILD_TOWER, {"cell": grid_position, "kind_id": selected_tower_kind, "confirmed": confirmed})
	if result["reason"] == "path_blocked":  # 길이 막힌다: 사용자에게 확인받은 뒤 confirmed=true로 다시 보낸다
		awaiting_confirm = true
		path_block_confirm.emit(grid_position)
	return result["ok"]

func set_tower_kind(kind_id: String):
	selected_tower_kind = kind_id
	Log.info(Log.Category.UI, "타워 종류 선택: %s" % Balance.tower_kind(kind_id).name)

## 몬스터 생산 명령을 보낸다
func send_monster(kind_id: String) -> bool:
	return do_command(Command.SEND_MONSTER, {"kind_id": kind_id})["ok"]

func get_current_tool() -> PlacementTool:
	return current_tool

func set_current_tool(tool: PlacementTool):
	current_tool = tool
	Log.info(Log.Category.UI, "도구 변경: %s" % PlacementTool.keys()[tool])
