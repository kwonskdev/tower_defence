extends Node
class_name GridSystem

signal cell_state_changed(position: Vector2i, old_state: CellState, new_state: CellState)
signal grid_initialized()

enum CellState {
	EMPTY,
	TOWER,
	OBSTACLE,
	PATH,
	SPAWN,
	EXIT
}

const GRID_WIDTH = 12
const GRID_HEIGHT = 50

var grid_data: Array[Array] = []
var grid_renderer: GridRenderer

func _ready():
	initialize_grid()

func initialize_grid():
	grid_data.clear()
	grid_data.resize(GRID_HEIGHT)

	for y in range(GRID_HEIGHT):
		grid_data[y] = []
		grid_data[y].resize(GRID_WIDTH)
		for x in range(GRID_WIDTH):
			grid_data[y][x] = CellState.EMPTY

	grid_initialized.emit()
	print("Grid System initialized: ", GRID_WIDTH, "x", GRID_HEIGHT)

func connect_renderer(renderer: GridRenderer):
	if grid_renderer:
		disconnect_renderer()

	grid_renderer = renderer

	if grid_renderer:
		grid_renderer.cell_clicked.connect(_on_cell_clicked)
		grid_renderer.cell_hovered.connect(_on_cell_hovered)
		update_all_visuals()

func disconnect_renderer():
	if grid_renderer:
		if grid_renderer.cell_clicked.is_connected(_on_cell_clicked):
			grid_renderer.cell_clicked.disconnect(_on_cell_clicked)
		if grid_renderer.cell_hovered.is_connected(_on_cell_hovered):
			grid_renderer.cell_hovered.disconnect(_on_cell_hovered)
		grid_renderer = null

func _on_cell_clicked(grid_position: Vector2i):
	print("Cell clicked: ", grid_position, " - State: ", get_state_name(get_cell_state(grid_position)))

func _on_cell_hovered(grid_position: Vector2i):
	pass

func get_cell_state(position: Vector2i) -> CellState:
	if not is_valid_position(position):
		return CellState.OBSTACLE

	return grid_data[position.y][position.x]

func set_cell_state(position: Vector2i, new_state: CellState) -> bool:
	if not is_valid_position(position):
		return false

	var old_state = grid_data[position.y][position.x]
	if old_state == new_state:
		return true

	grid_data[position.y][position.x] = new_state
	cell_state_changed.emit(position, old_state, new_state)
	update_cell_visual(position, new_state)

	return true

func update_cell_visual(position: Vector2i, state: CellState):
	if not grid_renderer:
		return

	var color: Color
	match state:
		CellState.EMPTY:
			grid_renderer.clear_cell_highlight(position)
			return
		CellState.TOWER:
			color = Color.BLUE
			color.a = 0.6
		CellState.OBSTACLE:
			color = Color.RED
			color.a = 0.6
		CellState.PATH:
			color = Color.GREEN
			color.a = 0.4
		CellState.SPAWN:
			color = Color.ORANGE
			color.a = 0.7
		CellState.EXIT:
			color = Color.PURPLE
			color.a = 0.7

	grid_renderer.highlight_cell(position, color)

func update_all_visuals():
	if not grid_renderer:
		return

	grid_renderer.clear_all_highlights()

	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var pos = Vector2i(x, y)
			var state = get_cell_state(pos)
			if state != CellState.EMPTY:
				update_cell_visual(pos, state)

func is_valid_position(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < GRID_WIDTH and position.y >= 0 and position.y < GRID_HEIGHT

func is_cell_empty(position: Vector2i) -> bool:
	return get_cell_state(position) == CellState.EMPTY

func is_cell_walkable(position: Vector2i) -> bool:
	var state = get_cell_state(position)
	return state == CellState.EMPTY or state == CellState.PATH or state == CellState.SPAWN or state == CellState.EXIT

func get_neighbors(position: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions: Array[Vector2i] = []

	if include_diagonals:
		directions = [
			Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
			Vector2i(-1, 0),                   Vector2i(1, 0),
			Vector2i(-1, 1),  Vector2i(0, 1),  Vector2i(1, 1)
		]
	else:
		directions = [
			Vector2i(0, -1),  # Up
			Vector2i(1, 0),   # Right
			Vector2i(0, 1),   # Down
			Vector2i(-1, 0)   # Left
		]

	for dir in directions:
		var neighbor = position + dir
		if is_valid_position(neighbor):
			neighbors.append(neighbor)

	return neighbors

func get_walkable_neighbors(position: Vector2i, include_diagonals: bool = false) -> Array[Vector2i]:
	var walkable: Array[Vector2i] = []
	var neighbors = get_neighbors(position, include_diagonals)

	for neighbor in neighbors:
		if is_cell_walkable(neighbor):
			walkable.append(neighbor)

	return walkable

func get_cells_with_state(state: CellState) -> Array[Vector2i]:
	var cells: Array[Vector2i] = []

	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var pos = Vector2i(x, y)
			if get_cell_state(pos) == state:
				cells.append(pos)

	return cells

func clear_all_cells():
	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var pos = Vector2i(x, y)
			var current_state = get_cell_state(pos)
			# SPAWN과 EXIT는 유지, 나머지만 삭제
			if current_state != CellState.SPAWN and current_state != CellState.EXIT:
				set_cell_state(pos, CellState.EMPTY)

func create_horizontal_path(y_position: int, start_x: int = 0, end_x: int = GRID_WIDTH - 1):
	if y_position < 0 or y_position >= GRID_HEIGHT:
		return

	for x in range(start_x, end_x + 1):
		set_cell_state(Vector2i(x, y_position), CellState.PATH)

func create_vertical_path(x_position: int, start_y: int = 0, end_y: int = GRID_HEIGHT - 1):
	if x_position < 0 or x_position >= GRID_WIDTH:
		return

	for y in range(start_y, end_y + 1):
		set_cell_state(Vector2i(x_position, y), CellState.PATH)

func setup_game_path():
	# 맨 위 행 전체를 시작점(SPAWN)으로 설정
	for x in range(GRID_WIDTH):
		set_cell_state(Vector2i(x, 0), CellState.SPAWN)

	# 맨 아래 행 전체를 도착점(EXIT)으로 설정
	for x in range(GRID_WIDTH):
		set_cell_state(Vector2i(x, GRID_HEIGHT - 1), CellState.EXIT)

	# 나머지는 모두 EMPTY로 유지 (몬스터가 자유롭게 이동 가능)

func get_state_name(state: CellState) -> String:
	match state:
		CellState.EMPTY: return "EMPTY"
		CellState.TOWER: return "TOWER"
		CellState.OBSTACLE: return "OBSTACLE"
		CellState.PATH: return "PATH"
		CellState.SPAWN: return "SPAWN"
		CellState.EXIT: return "EXIT"
		_: return "UNKNOWN"

func get_grid_size() -> Vector2i:
	return Vector2i(GRID_WIDTH, GRID_HEIGHT)