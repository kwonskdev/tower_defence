extends RefCounted
class_name PathfindingSystem

var grid_system: GridSystem
var astar: AStar2D
var point_map: Dictionary = {}
var id_counter: int = 0
var cached_paths: Dictionary = {}

signal path_calculated(start: Vector2i, goal: Vector2i, path: Array[Vector2i])
signal pathfinding_failed(start: Vector2i, goal: Vector2i)

func _init(grid_sys: GridSystem):
	grid_system = grid_sys
	grid_system.grid_updated.connect(_on_grid_updated)
	_initialize_astar()

	Logger.monster_ai_log("PathfindingSystem initialized")

func _initialize_astar():
	astar = AStar2D.new()
	point_map.clear()
	id_counter = 0
	cached_paths.clear()

	_build_navigation_graph()

func _build_navigation_graph():
	var grid_size = grid_system.get_grid_size()

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var pos = Vector2i(x, y)
			var cell_type = grid_system.get_cell_type(pos)

			if _is_walkable_cell(cell_type):
				astar.add_point(id_counter, Vector2(pos.x, pos.y))
				point_map[pos] = id_counter
				id_counter += 1

	_connect_walkable_points()

func _is_walkable_cell(cell_type: GridSystem.CellType) -> bool:
	return cell_type == GridSystem.CellType.EMPTY or \
		   cell_type == GridSystem.CellType.PATH_START or \
		   cell_type == GridSystem.CellType.PATH_END

func _connect_walkable_points():
	for pos in point_map.keys():
		var neighbors = grid_system.get_walkable_neighbors(pos)

		for neighbor in neighbors:
			if point_map.has(neighbor):
				var weight = _calculate_movement_cost(pos, neighbor)
				astar.connect_points(point_map[pos], point_map[neighbor], false)
				astar.set_point_weight_scale(point_map[neighbor], weight)

func _calculate_movement_cost(from: Vector2i, to: Vector2i) -> float:
	var base_cost = 1.0

	if abs(from.x - to.x) + abs(from.y - to.y) > 1:
		base_cost = 1.414

	return base_cost

func _on_grid_updated():
	Logger.monster_ai_log("Grid updated, rebuilding pathfinding graph")
	_initialize_astar()

func find_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var cache_key = "%v_%v" % [start, goal]

	if cached_paths.has(cache_key):
		Logger.monster_ai_log("Using cached path from %v to %v" % [start, goal], Logger.LogLevel.DEBUG)
		return cached_paths[cache_key]

	var path = _calculate_astar_path(start, goal)

	if path.size() > 0:
		cached_paths[cache_key] = path
		path_calculated.emit(start, goal, path)
		Logger.monster_ai_log("Path calculated from %v to %v: %d steps" % [start, goal, path.size()])
	else:
		pathfinding_failed.emit(start, goal)
		Logger.monster_ai_log("Pathfinding failed from %v to %v" % [start, goal], Logger.LogLevel.WARNING)

	return path

func _calculate_astar_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	if not point_map.has(start) or not point_map.has(goal):
		Logger.monster_ai_log("Start or goal position not walkable: %v -> %v" % [start, goal], Logger.LogLevel.WARNING)
		return []

	var vector_path = astar.get_point_path(point_map[start], point_map[goal])
	var grid_path: Array[Vector2i] = []

	for vector_pos in vector_path:
		grid_path.append(Vector2i(int(vector_pos.x), int(vector_pos.y)))

	return grid_path

func find_path_with_limited_vision(start: Vector2i, goal: Vector2i, vision_range: int) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var current_pos = start
	var iteration_count = 0
	var max_iterations = 1000

	Logger.monster_ai_log("Starting limited vision pathfinding from %v to %v (vision: %d)" % [start, goal, vision_range])

	while current_pos != goal and iteration_count < max_iterations:
		var visible_area = _get_visible_positions(current_pos, vision_range)
		var next_pos = _choose_next_position_in_vision(current_pos, goal, visible_area)

		if next_pos == current_pos:
			Logger.monster_ai_log("Stuck at %v, using full pathfinding" % current_pos)
			var remaining_path = _calculate_astar_path(current_pos, goal)
			if remaining_path.size() > 1:
				next_pos = remaining_path[1]
			else:
				Logger.monster_ai_log("Full pathfinding also failed", Logger.LogLevel.ERROR)
				break

		path.append(next_pos)
		current_pos = next_pos
		iteration_count += 1

	if iteration_count >= max_iterations:
		Logger.error("Limited vision pathfinding exceeded maximum iterations", "PATHFINDING")

	return path

func _get_visible_positions(center: Vector2i, vision_range: int) -> Array[Vector2i]:
	var visible: Array[Vector2i] = []

	for x in range(-vision_range, vision_range + 1):
		for y in range(-vision_range, vision_range + 1):
			var check_pos = center + Vector2i(x, y)
			if grid_system.is_valid_position(check_pos):
				var distance = abs(x) + abs(y)
				if distance <= vision_range:
					visible.append(check_pos)

	return visible

func _choose_next_position_in_vision(current: Vector2i, goal: Vector2i, visible_area: Array[Vector2i]) -> Vector2i:
	var best_pos = current
	var best_distance = float(current.distance_squared_to(goal))

	var neighbors = grid_system.get_walkable_neighbors(current)

	for neighbor in neighbors:
		if neighbor in visible_area:
			var cell_type = grid_system.get_cell_type(neighbor)
			if _is_walkable_cell(cell_type):
				var distance = float(neighbor.distance_squared_to(goal))
				if distance < best_distance:
					best_distance = distance
					best_pos = neighbor

	return best_pos

func find_alternative_path(start: Vector2i, goal: Vector2i, blocked_positions: Array[Vector2i]) -> Array[Vector2i]:
	var temp_astar = AStar2D.new()
	var temp_point_map: Dictionary = {}
	var temp_id_counter = 0

	var grid_size = grid_system.get_grid_size()

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var pos = Vector2i(x, y)
			var cell_type = grid_system.get_cell_type(pos)

			if _is_walkable_cell(cell_type) and pos not in blocked_positions:
				temp_astar.add_point(temp_id_counter, Vector2(pos.x, pos.y))
				temp_point_map[pos] = temp_id_counter
				temp_id_counter += 1

	for pos in temp_point_map.keys():
		var neighbors = grid_system.get_walkable_neighbors(pos)

		for neighbor in neighbors:
			if temp_point_map.has(neighbor) and neighbor not in blocked_positions:
				temp_astar.connect_points(temp_point_map[pos], temp_point_map[neighbor])

	if not temp_point_map.has(start) or not temp_point_map.has(goal):
		return []

	var vector_path = temp_astar.get_point_path(temp_point_map[start], temp_point_map[goal])
	var grid_path: Array[Vector2i] = []

	for vector_pos in vector_path:
		grid_path.append(Vector2i(int(vector_pos.x), int(vector_pos.y)))

	Logger.monster_ai_log("Alternative path calculated avoiding %d blocked positions" % blocked_positions.size())
	return grid_path

func check_path_blocked(path: Array[Vector2i]) -> bool:
	for pos in path:
		var cell_type = grid_system.get_cell_type(pos)
		if not _is_walkable_cell(cell_type):
			return true
	return false

func get_nearest_walkable_position(target: Vector2i) -> Vector2i:
	if _is_walkable_cell(grid_system.get_cell_type(target)):
		return target

	var search_radius = 1
	var max_radius = 10

	while search_radius <= max_radius:
		for x in range(-search_radius, search_radius + 1):
			for y in range(-search_radius, search_radius + 1):
				if abs(x) == search_radius or abs(y) == search_radius:
					var check_pos = target + Vector2i(x, y)
					if grid_system.is_valid_position(check_pos) and _is_walkable_cell(grid_system.get_cell_type(check_pos)):
						return check_pos
		search_radius += 1

	Logger.warning("Could not find walkable position near %v" % target, "PATHFINDING")
	return target

func optimize_path(path: Array[Vector2i]) -> Array[Vector2i]:
	if path.size() <= 2:
		return path

	var optimized: Array[Vector2i] = [path[0]]
	var i = 0

	while i < path.size() - 1:
		var j = path.size() - 1

		while j > i + 1:
			if _has_clear_line_of_sight(path[i], path[j]):
				optimized.append(path[j])
				i = j
				break
			j -= 1

		if j == i + 1:
			optimized.append(path[i + 1])
			i += 1

	Logger.monster_ai_log("Path optimized from %d to %d steps" % [path.size(), optimized.size()], Logger.LogLevel.DEBUG)
	return optimized

func _has_clear_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var diff = to - from
	var steps = max(abs(diff.x), abs(diff.y))

	if steps == 0:
		return true

	for i in range(1, steps):
		var t = float(i) / float(steps)
		var check_pos = Vector2i(
			int(from.x + diff.x * t),
			int(from.y + diff.y * t)
		)

		if not _is_walkable_cell(grid_system.get_cell_type(check_pos)):
			return false

	return true

func clear_cache():
	cached_paths.clear()
	Logger.monster_ai_log("Pathfinding cache cleared")

func get_path_cost(path: Array[Vector2i]) -> float:
	if path.size() <= 1:
		return 0.0

	var total_cost = 0.0

	for i in range(path.size() - 1):
		var from = path[i]
		var to = path[i + 1]
		total_cost += _calculate_movement_cost(from, to)

	return total_cost

func get_cache_stats() -> Dictionary:
	return {
		"cached_paths": cached_paths.size(),
		"total_points": point_map.size(),
		"astar_points": astar.get_point_count()
	}