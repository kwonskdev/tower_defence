extends ScrollContainer
class_name GameField

@onready var grid_renderer: GridRenderer

const MAX_PLAYERS = 8
var grid_systems: Array[GridSystem] = []
var current_player_id: int = 0

var current_tool: PlacementTool = PlacementTool.NONE
var scroll_speed: float = 500.0

# 마우스 드래그 스크롤 변수들
var is_dragging: bool = false
var drag_start_position: Vector2
var drag_start_scroll: Vector2
var drag_threshold: float = 10.0  # 드래그로 인식할 최소 거리

enum PlacementTool {
	NONE,
	TOWER,
	OBSTACLE,
	PATH,
	ERASER
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
		add_child(grid_system)
		grid_systems.append(grid_system)
		grid_system.cell_state_changed.connect(_on_cell_state_changed)

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

func setup_scroll_container():
	scroll_horizontal = false  # 가로 스크롤 완전 비활성화
	scroll_vertical = true
	follow_focus = true

func _on_cell_state_changed(position: Vector2i, old_state: GridSystem.CellState, new_state: GridSystem.CellState):
	var grid_system = get_current_grid_system()
	print("Cell [", position.x, ",", position.y, "] changed from ", grid_system.get_state_name(old_state), " to ", grid_system.get_state_name(new_state))

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


func apply_scroll(delta: Vector2):
	var current_scroll = Vector2(get_h_scroll(), get_v_scroll())
	var new_scroll = current_scroll + delta * get_process_delta_time()

	var max_scroll_h = get_h_scroll_bar().max_value if get_h_scroll_bar() else 0
	var max_scroll_v = get_v_scroll_bar().max_value if get_v_scroll_bar() else 0

	new_scroll.x = clamp(new_scroll.x, 0, max_scroll_h)
	new_scroll.y = clamp(new_scroll.y, 0, max_scroll_v)

	set_h_scroll(int(new_scroll.x))
	set_v_scroll(int(new_scroll.y))

func _on_grid_cell_clicked(grid_position: Vector2i):
	if current_tool == PlacementTool.NONE:
		return

	match current_tool:
		PlacementTool.TOWER:
			place_tower(grid_position)
		PlacementTool.OBSTACLE:
			place_obstacle(grid_position)
		PlacementTool.PATH:
			place_path(grid_position)
		PlacementTool.ERASER:
			clear_cell(grid_position)

func get_current_grid_system() -> GridSystem:
	return grid_systems[current_player_id]

func switch_player(player_id: int):
	if player_id < 0 or player_id >= MAX_PLAYERS:
		return

	# 이전 플레이어의 렌더러 연결 해제
	get_current_grid_system().disconnect_renderer()

	# 새 플레이어로 전환
	current_player_id = player_id

	# 새 플레이어의 렌더러 연결
	get_current_grid_system().connect_renderer(grid_renderer)
	get_current_grid_system().update_all_visuals()

	print("Switched to Player ", player_id + 1)

func place_tower(grid_position: Vector2i) -> bool:
	var grid_system = get_current_grid_system()
	if grid_system.is_cell_empty(grid_position):
		grid_system.set_cell_state(grid_position, GridSystem.CellState.TOWER)
		return true
	return false

func place_obstacle(grid_position: Vector2i) -> bool:
	var grid_system = get_current_grid_system()
	if grid_system.is_cell_empty(grid_position):
		grid_system.set_cell_state(grid_position, GridSystem.CellState.OBSTACLE)
		return true
	return false

func place_path(grid_position: Vector2i) -> bool:
	var grid_system = get_current_grid_system()
	if grid_system.is_cell_empty(grid_position):
		grid_system.set_cell_state(grid_position, GridSystem.CellState.PATH)
		return true
	return false

func clear_cell(grid_position: Vector2i) -> bool:
	var grid_system = get_current_grid_system()
	grid_system.set_cell_state(grid_position, GridSystem.CellState.EMPTY)
	return true

func center_view_on_cell(grid_position: Vector2i):
	if not grid_renderer or not is_inside_tree():
		return

	var world_pos = grid_renderer.grid_to_screen(grid_position)
	var viewport_size = get_viewport_rect().size

	var target_scroll = Vector2(
		world_pos.x - viewport_size.x * 0.5,
		world_pos.y - viewport_size.y * 0.5
	)

	var max_scroll_h = get_h_scroll_bar().max_value if get_h_scroll_bar() else 0
	var max_scroll_v = get_v_scroll_bar().max_value if get_v_scroll_bar() else 0

	target_scroll.x = clamp(target_scroll.x, 0, max_scroll_h)
	target_scroll.y = clamp(target_scroll.y, 0, max_scroll_v)

	set_h_scroll(int(target_scroll.x))
	set_v_scroll(int(target_scroll.y))

func get_grid_system() -> GridSystem:
	return get_current_grid_system()

func get_grid_renderer() -> GridRenderer:
	return grid_renderer

func clear_all_cells():
	var grid_system = get_current_grid_system()
	if grid_system:
		grid_system.clear_all_cells()

func get_current_tool() -> PlacementTool:
	return current_tool

func set_current_tool(tool: PlacementTool):
	current_tool = tool
	print("Tool changed to: ", PlacementTool.keys()[tool])
