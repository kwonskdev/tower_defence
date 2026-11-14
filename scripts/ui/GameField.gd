extends ScrollContainer
class_name GameField

var grid_renderer: GridRenderer

const MAX_PLAYERS = 8
var grid_systems: Array[GridSystem] = []
var lanes: Dictionary = {}  # player_id -> LaneController (참여한 플레이어만)
var current_player_id: int = 0

var current_tool: PlacementTool = PlacementTool.NONE

# 마우스 드래그 스크롤 변수들
var is_dragging: bool = false
var drag_start_position: Vector2
var drag_start_scroll: Vector2
var drag_threshold: float = 10.0  # 드래그로 인식할 최소 거리

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
	for i in range(MAX_PLAYERS):
		var grid_system = GridSystem.new()
		grid_system.name = "GridSystem_" + str(i)
		grid_system.player_id = i
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
		var container_width = get_size().x
		grid_renderer.set_container_width(container_width)

	# PvE 임시: 1번 플레이어만 참여 (나머지 레인은 비어 있음)
	start_lane(0)

func start_lane(player_id: int):
	var lane := LaneController.new()
	lane.name = "Lane_" + str(player_id)
	add_child(lane)
	lane.setup(player_id, grid_systems[player_id], grid_renderer)
	lane.set_lane_visible(player_id == current_player_id)
	lanes[player_id] = lane

func setup_scroll_container():
	# 가로 스크롤 비활성화 (세로 드래그 스크롤만 사용)
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	follow_focus = true

func _input(event):
	if not get_global_rect().has_point(get_global_mouse_position()):
		return

	handle_mouse_input(event)
	# 키보드 입력은 모두 제거 (버튼으로만 제어)

func handle_mouse_input(event):
	if event is InputEventMouseButton:
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
	if current_tool == PlacementTool.NONE:
		return

	match current_tool:
		PlacementTool.TOWER:
			place_tower(grid_position)

func get_current_grid_system() -> GridSystem:
	return grid_systems[current_player_id]

func switch_player(player_id: int):
	if player_id < 0 or player_id >= MAX_PLAYERS:
		Log.warn(Log.Category.UI, "잘못된 플레이어 전환 요청: %d" % player_id)
		return

	# 이전 플레이어의 렌더러 연결 해제
	get_current_grid_system().disconnect_renderer()

	# 새 플레이어로 전환
	current_player_id = player_id

	# 새 플레이어의 렌더러 연결
	get_current_grid_system().connect_renderer(grid_renderer)

	# 보고 있는 레인의 몬스터만 표시
	for id in lanes:
		lanes[id].set_lane_visible(id == player_id)

	Log.info(Log.Category.UI, "플레이어 맵 전환 -> P%d" % (player_id + 1))

func place_tower(grid_position: Vector2i) -> bool:
	var grid_system = get_current_grid_system()
	var lane: LaneController = lanes.get(current_player_id)
	if lane and lane.is_cell_occupied(grid_position):
		Log.debug(Log.Category.TOWER, "[P%d] 타워 건설 실패 %s: 몬스터가 있는 칸" % [current_player_id + 1, grid_position])
		return false
	if grid_system.is_cell_empty(grid_position):
		grid_system.set_cell_state(grid_position, GridSystem.CellState.TOWER)
		Log.info(Log.Category.TOWER, "[P%d] 타워 건설 %s" % [current_player_id + 1, grid_position])
		return true
	Log.debug(Log.Category.TOWER, "[P%d] 타워 건설 실패 %s: 빈 칸 아님(%s)" % [
		current_player_id + 1, grid_position, grid_system.get_state_name(grid_system.get_cell_state(grid_position))])
	return false

func get_current_tool() -> PlacementTool:
	return current_tool

func set_current_tool(tool: PlacementTool):
	current_tool = tool
	Log.info(Log.Category.UI, "도구 변경: %s" % PlacementTool.keys()[tool])
