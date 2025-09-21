extends RefCounted
class_name GridSystem

const GRID_WIDTH = 10
const GRID_HEIGHT = 50
const CELL_SIZE = 64

enum CellType {
	EMPTY,
	TOWER,
	PATH_START,
	PATH_END,
	BLOCKED
}

var grid: Array[Array] = []
var towers: Dictionary = {}
var spawn_position: Vector2i
var goal_position: Vector2i

signal tower_placed(position: Vector2i, tower_type: String)
signal tower_removed(position: Vector2i)
signal grid_updated()

func _init():
	Logger.debug("Initializing grid system (%dx%d)" % [GRID_WIDTH, GRID_HEIGHT], "GRID")
	_initialize_grid()

func _initialize_grid():
	grid.clear()
	towers.clear()

	for x in range(GRID_WIDTH):
		var column: Array = []
		for y in range(GRID_HEIGHT):
			column.append(CellType.EMPTY)
		grid.append(column)

	spawn_position = Vector2i(5, 0)
	goal_position = Vector2i(5, GRID_HEIGHT - 1)

	set_cell_type(spawn_position, CellType.PATH_START)
	set_cell_type(goal_position, CellType.PATH_END)

	Logger.info("Grid initialized with spawn at %v and goal at %v" % [spawn_position, goal_position], "GRID")

func is_valid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT

func get_cell_type(pos: Vector2i) -> CellType:
	if not is_valid_position(pos):
		return CellType.BLOCKED
	return grid[pos.x][pos.y]

func set_cell_type(pos: Vector2i, type: CellType) -> bool:
	if not is_valid_position(pos):
		Logger.warning("Attempted to set cell type at invalid position: %v" % pos, "GRID")
		return false

	var old_type = grid[pos.x][pos.y]
	grid[pos.x][pos.y] = type

	Logger.debug("Cell type changed at %v from %s to %s" % [pos, _cell_type_to_string(old_type), _cell_type_to_string(type)], "GRID")
	grid_updated.emit()
	return true

func can_place_tower(pos: Vector2i) -> bool:
	if not is_valid_position(pos):
		return false

	var cell_type = get_cell_type(pos)
	if cell_type != CellType.EMPTY:
		return false

	if pos == spawn_position or pos == goal_position:
		return false

	set_cell_type(pos, CellType.TOWER)
	var path_exists = _check_path_exists()
	set_cell_type(pos, CellType.EMPTY)

	return path_exists

func place_tower(pos: Vector2i, tower_data: Dictionary) -> bool:
	if not can_place_tower(pos):
		Logger.warning("Cannot place tower at position %v" % pos, "GRID")
		return false

	set_cell_type(pos, CellType.TOWER)
	towers[pos] = tower_data

	Logger.tower_log("Tower placed at %v: %s" % [pos, tower_data.get("type", "Unknown")])
	tower_placed.emit(pos, tower_data.get("type", ""))
	return true

func remove_tower(pos: Vector2i) -> bool:
	if not is_valid_position(pos) or get_cell_type(pos) != CellType.TOWER:
		Logger.warning("Cannot remove tower at position %v" % pos, "GRID")
		return false

	var tower_data = towers.get(pos, {})
	set_cell_type(pos, CellType.EMPTY)
	towers.erase(pos)

	Logger.tower_log("Tower removed at %v: %s" % [pos, tower_data.get("type", "Unknown")])
	tower_removed.emit(pos)
	return true

func get_tower_at(pos: Vector2i) -> Dictionary:
	return towers.get(pos, {})

func grid_to_world_position(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE / 2, grid_pos.y * CELL_SIZE + CELL_SIZE / 2)

func world_to_grid_position(world_pos: Vector2) -> Vector2i:
	return Vector2i(int(world_pos.x / CELL_SIZE), int(world_pos.y / CELL_SIZE))

func get_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var neighbors: Array[Vector2i] = []
	var directions = [Vector2i(0, 1), Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, 0)]

	for direction in directions:
		var neighbor = pos + direction
		if is_valid_position(neighbor):
			neighbors.append(neighbor)

	return neighbors

func get_walkable_neighbors(pos: Vector2i) -> Array[Vector2i]:
	var walkable: Array[Vector2i] = []
	var neighbors = get_neighbors(pos)

	for neighbor in neighbors:
		var cell_type = get_cell_type(neighbor)
		if cell_type == CellType.EMPTY or cell_type == CellType.PATH_START or cell_type == CellType.PATH_END:
			walkable.append(neighbor)

	return walkable

func _check_path_exists() -> bool:
	var visited: Dictionary = {}
	var queue: Array[Vector2i] = [spawn_position]
	visited[spawn_position] = true

	while queue.size() > 0:
		var current = queue.pop_front()

		if current == goal_position:
			return true

		for neighbor in get_walkable_neighbors(current):
			if not visited.has(neighbor):
				visited[neighbor] = true
				queue.append(neighbor)

	return false

func get_spawn_position() -> Vector2i:
	return spawn_position

func get_goal_position() -> Vector2i:
	return goal_position

func get_grid_size() -> Vector2i:
	return Vector2i(GRID_WIDTH, GRID_HEIGHT)

func get_all_towers() -> Dictionary:
	return towers.duplicate()

func _cell_type_to_string(type: CellType) -> String:
	match type:
		CellType.EMPTY:
			return "EMPTY"
		CellType.TOWER:
			return "TOWER"
		CellType.PATH_START:
			return "PATH_START"
		CellType.PATH_END:
			return "PATH_END"
		CellType.BLOCKED:
			return "BLOCKED"
		_:
			return "UNKNOWN"