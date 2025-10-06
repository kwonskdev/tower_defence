extends ScrollContainer
class_name GameField

@onready var grid_renderer: GridRenderer
@onready var grid_system: GridSystem

var current_tool: PlacementTool = PlacementTool.NONE
var scroll_speed: float = 500.0

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

	grid_system = GridSystem.new()
	grid_system.name = "GridSystem"
	add_child(grid_system)

	grid_system.connect_renderer(grid_renderer)
	grid_system.cell_state_changed.connect(_on_cell_state_changed)

	await get_tree().process_frame
	grid_system.setup_game_path()

func setup_scroll_container():
	scroll_horizontal = true
	scroll_vertical = true
	follow_focus = true

	# ScrollContainer 자체는 뷰포트 크기에 맞춰야 함
	# 내부 컨텐츠(GridRenderer)만 실제 그리드 크기로 설정

func _on_cell_state_changed(position: Vector2i, old_state: GridSystem.CellState, new_state: GridSystem.CellState):
	print("Cell [", position.x, ",", position.y, "] changed from ", grid_system.get_state_name(old_state), " to ", grid_system.get_state_name(new_state))

func _input(event):
	if not get_global_rect().has_point(get_global_mouse_position()):
		return

	handle_keyboard_input(event)
	handle_tool_selection(event)

func handle_keyboard_input(event):
	if event is InputEventKey and event.pressed:
		var scroll_delta = Vector2.ZERO

		match event.keycode:
			KEY_W, KEY_UP:
				scroll_delta.y = -scroll_speed
			KEY_S, KEY_DOWN:
				scroll_delta.y = scroll_speed
			KEY_A, KEY_LEFT:
				scroll_delta.x = -scroll_speed
			KEY_D, KEY_RIGHT:
				scroll_delta.x = scroll_speed

		if scroll_delta != Vector2.ZERO:
			apply_scroll(scroll_delta)

func handle_tool_selection(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_1:
				current_tool = PlacementTool.TOWER
				print("Tool: TOWER selected")
			KEY_2:
				current_tool = PlacementTool.OBSTACLE
				print("Tool: OBSTACLE selected")
			KEY_3:
				current_tool = PlacementTool.PATH
				print("Tool: PATH selected")
			KEY_E:
				current_tool = PlacementTool.ERASER
				print("Tool: ERASER selected")
			KEY_ESCAPE:
				current_tool = PlacementTool.NONE
				print("Tool: NONE selected")

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

func place_tower(grid_position: Vector2i) -> bool:
	if grid_system.is_cell_empty(grid_position):
		grid_system.set_cell_state(grid_position, GridSystem.CellState.TOWER)
		return true
	return false

func place_obstacle(grid_position: Vector2i) -> bool:
	if grid_system.is_cell_empty(grid_position):
		grid_system.set_cell_state(grid_position, GridSystem.CellState.OBSTACLE)
		return true
	return false

func place_path(grid_position: Vector2i) -> bool:
	if grid_system.is_cell_empty(grid_position):
		grid_system.set_cell_state(grid_position, GridSystem.CellState.PATH)
		return true
	return false

func clear_cell(grid_position: Vector2i) -> bool:
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
	return grid_system

func get_grid_renderer() -> GridRenderer:
	return grid_renderer

func clear_all_cells():
	if grid_system:
		grid_system.clear_all_cells()

func get_current_tool() -> PlacementTool:
	return current_tool

func set_current_tool(tool: PlacementTool):
	current_tool = tool
	print("Tool changed to: ", PlacementTool.keys()[tool])