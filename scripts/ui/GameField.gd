extends ScrollContainer
class_name GameField

var grid_renderer: GridRenderer

const MAX_PLAYERS = Balance.MAX_PLAYERS
const BOSS_LANE_ID = 8  # grid_systems[8] = 보스 레인 (미니맵의 B)
var grid_systems: Array[GridSystem] = []
var lanes: Dictionary = {}  # player_id -> LaneController (참여한 플레이어만)
var current_player_id: int = 0  # 지금 화면에 보고 있는 레인
var local_player_id: int = 0    # 내 플레이어 (타워 건설/몬스터 생산은 내 레인에서만)
var boss: BossController
var lane_scroll_rows: Dictionary = {}  # 레인별로 마지막에 보던 위치 (맨 위 줄 번호). 레인을 바꿔도 각자 위치를 기억한다
var selected_tower_kind: String = Balance.TOWER_KINDS[0]

var current_tool: PlacementTool = PlacementTool.NONE
signal path_block_confirm(cell: Vector2i)  # 이 타워를 지으면 길이 막힌다: 사용자에게 확인을 받아야 한다
signal tower_selected(tower: Tower)           # 맵에서 지어진 타워를 눌러 선택했다 (건설 모드 중이어도: 상단이 그 타워 화면으로 바뀐다)
signal boss_ready(boss: BossController)    # 보스가 만들어졌다 (한 프레임 기다린 뒤라서 MainGame._ready 시점에는 아직 없다)

var awaiting_confirm: bool = false  # 길 막힘 확인을 기다리는 중 (이 클릭으로는 타워 선택/해제를 하지 않는다)
var game_started: bool = false  # 시작 버튼을 눌렀는지
var selected_tower: Tower = null  # 클릭해서 선택한 타워 (정보/업그레이드 대상)
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
	grid_renderer = GridRenderer.new()
	grid_renderer.name = "GridRenderer"
	add_child(grid_renderer)

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

	# PvE 임시: 1번 플레이어만 참여 (나머지 레인은 비어 있음)
	start_lane(0)
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


## 시작 버튼: 참여한 모든 레인과 보스가 동시에 시작한다 (수입, 보스 제한시간, 몬스터 파견)
func start_game() -> void:
	if game_started or boss == null:
		return
	game_started = true
	for lane in lanes.values():
		lane.begin()
	boss.begin()
	Log.info(Log.Category.GAME, "시작 버튼: 레인 %d개 동시 시작" % lanes.size())

func start_lane(player_id: int):
	var lane := LaneController.new()
	lane.name = "Lane_" + str(player_id)
	add_child(lane)
	lane.setup(player_id, grid_systems[player_id], grid_renderer)
	lane.set_lane_visible(player_id == current_player_id)
	lanes[player_id] = lane

func start_boss():
	boss = BossController.new()
	boss.name = "Boss"
	add_child(boss)
	boss.setup(grid_systems[BOSS_LANE_ID], grid_renderer, lanes)
	boss.set_lane_visible(current_player_id == BOSS_LANE_ID)
	boss_ready.emit(boss)

	# 각 레인에 boss 참조 설정 (남색 색깔 보너스용)
	for lane in lanes.values():
		lane._boss_controller = boss

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
	select_tower(_tower_at(grid_position))


## 지금 보는 레인의 grid_position 칸에 있는 타워 (없으면 null)
func _tower_at(grid_position: Vector2i) -> Tower:
	var lane: LaneController = lanes.get(current_player_id)
	if lane == null:
		return null
	for t in lane.towers:
		if t.cell == grid_position:
			return t
	return null


## 선택한 타워. 몬스터가 부수는 등으로 사라졌으면 null (해제된 객체를 타입 변수에 담으면 오류라서 꼭 이 함수로 읽는다)
func get_selected_tower() -> Tower:
	if is_instance_valid(selected_tower):
		return selected_tower
	selected_tower = null
	return null


func select_tower(tower: Tower) -> void:
	if is_instance_valid(selected_tower):
		selected_tower.selected = false
	selected_tower = tower
	if tower != null:
		tower.selected = true
		tower_selected.emit(tower)
		Log.info(Log.Category.UI, "타워 선택 %s: %s %s" % [tower.cell, tower.kind.name, Evolutions.evo_name(tower.evolution) if tower.evolution != "" else "(진화 전)"])


## 선택한 타워를 진화시킨다 (타워마다 한 번, 처음 계열을 고른다). 내 레인의 타워만 가능.
func evolve_selected_tower(evo: String) -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	return lane != null and lane.evolve_tower(get_selected_tower(), evo)


## 업그레이드 탭: 진화 항목 레벨을 올린다 (같은 계열의 모든 타워에 적용)
func upgrade_stat(evo: String, skill: String, key: String) -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	return lane != null and lane.upgrade_stat(evo, skill, key)


## 선택한 타워 1기의 색깔을 랜덤으로 바꾼다 (골드)
func recolor_selected_tower() -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	return lane != null and lane.recolor_tower(get_selected_tower())


## 선택한 타워 1기의 내구도를 가득 채운다 (골드)
func heal_selected_tower() -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	return lane != null and lane.heal_tower(get_selected_tower())


## 선택한 타워를 판다 (투입 골드의 일부 환급). 내 레인의 타워만 가능하고, 팔고 나면 선택이 풀린다.
func sell_selected_tower() -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	var tower := get_selected_tower()
	if lane == null or tower == null or not lane.sell_tower(tower):
		return false
	select_tower(null)  # 사라진 타워를 계속 선택하고 있지 않게 (사거리 표시, 타워 화면)
	return true


## 색깔 업그레이드 (골드, 그 색 타워 전체에 적용)
func upgrade_color(color_name: String) -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	return lane != null and lane.upgrade_color(color_name)


## 선택한 타워 1기의 B 스킬을 배운다 (골드, 타워마다 따로)
func learn_selected_tower_skill() -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	return lane != null and lane.learn_tower_skill(get_selected_tower())

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

	select_tower(null)  # 다른 레인으로 가면 선택 해제

	# 이전 플레이어의 렌더러 연결 해제
	get_current_grid_system().disconnect_renderer()

	# 새 플레이어로 전환
	current_player_id = player_id

	# 새 플레이어의 렌더러 연결
	get_current_grid_system().connect_renderer(grid_renderer)

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

## confirmed: 길이 막히는 걸 알고도 짓겠다고 사용자가 확인한 경우 true
func place_tower(grid_position: Vector2i, confirmed: bool = false) -> bool:
	if current_player_id != local_player_id:
		Log.debug(Log.Category.TOWER, "내 레인이 아니라서 건설 불가 (보는 레인=%s)" % get_current_grid_system().lane_tag())
		return false

	var lane: LaneController = lanes.get(local_player_id)
	if lane == null:
		return false
	var grid_system := get_current_grid_system()
	var tag := grid_system.lane_tag()
	var kind := Balance.tower_kind(selected_tower_kind)

	var cell_state := grid_system.get_cell_state(grid_position)
	# 한 칸에는 타워 1개만 (트랩도 겹쳐 지을 수 없다)
	if cell_state != GridSystem.CellState.EMPTY:
		Log.debug(Log.Category.TOWER, "[%s] 타워 건설 실패 %s: 빈 칸 아님(%s)" % [
			tag, grid_position, grid_system.get_state_name(cell_state)])
		return false
	# 길을 막는 타워는 몬스터와 몸이 겹친 칸에 지을 수 없다 (트랩은 위로 지나가므로 가능)
	if kind.blocks and lane.is_cell_occupied(grid_position):
		Log.debug(Log.Category.TOWER, "[%s] 타워 건설 실패 %s: 몬스터가 있는 칸" % [tag, grid_position])
		return false
	# 이 타워 때문에 길이 완전히 막히면 한 번 확인한다 (막히면 몬스터가 타워를 부수며 돌파한다)
	if kind.blocks and not confirmed and lane.would_block_path(grid_position):
		awaiting_confirm = true
		path_block_confirm.emit(grid_position)
		return false
	var cost: int = kind.cost
	if not lane.try_spend(cost, "타워 건설 %s(%s)" % [grid_position, kind.name]):
		return false

	lane.build_tower(grid_position, selected_tower_kind)
	Log.info(Log.Category.TOWER, "[%s] 타워 건설 %s: %s" % [tag, grid_position, kind.name])
	return true

func set_tower_kind(kind_id: String):
	selected_tower_kind = kind_id
	Log.info(Log.Category.UI, "타워 종류 선택: %s" % Balance.tower_kind(kind_id).name)

## 몬스터를 생산해 보스 레인으로 보낸다 (수입 영구 증가)
func send_monster(kind_id: String) -> bool:
	var lane: LaneController = lanes.get(local_player_id)
	if lane == null or boss == null or boss.state != BossController.State.RUNNING:
		return false
	var kind: Dictionary = Monsters.DATA.get(kind_id, {})
	if kind.is_empty():
		Log.warn(Log.Category.GAME, "알 수 없는 몬스터 종류: %s" % kind_id)
		return false
	if not Monsters.can_send_in_pve(kind_id):  # 협력에서는 공격형과 지원형만 만들 수 있다
		Log.warn(Log.Category.GAME, "협력에서는 %s(%s)를 만들 수 없음" % [kind.name, Monsters.CATEGORY_DATA[kind.category].name])
		return false
	if not lane.try_spend(kind.cost, "%s 생산" % kind.name):
		return false

	lane.add_income(kind.income)
	boss.spawn_player_monster(local_player_id, kind_id)
	return true

func get_current_tool() -> PlacementTool:
	return current_tool

func set_current_tool(tool: PlacementTool):
	current_tool = tool
	Log.info(Log.Category.UI, "도구 변경: %s" % PlacementTool.keys()[tool])
