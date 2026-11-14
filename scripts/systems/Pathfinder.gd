extends RefCounted
class_name Pathfinder
## 한 레인(GridSystem)용 길찾기.
##
## 두 개의 AStarGrid2D를 유지한다.
## - strict: 타워를 벽으로 취급 (평소 경로)
## - breach: 타워를 "통과 가능하지만 매우 비싼 칸"으로 취급 (완전 봉쇄 시 돌파 경로)
##   -> 부숴야 하는 타워 수가 가장 적은 경로가 선택된다.
## 격자가 바뀌면 dirty 표시만 하고, 다음 find_path 때 한 번에 다시 만든다.

const BREACH_COST := 1000.0

var _grid: GridSystem
var _strict := AStarGrid2D.new()
var _breach := AStarGrid2D.new()
var _dirty := true


func _init(grid: GridSystem) -> void:
	_grid = grid
	for astar in [_strict, _breach]:
		astar.region = Rect2i(0, 0, GridSystem.GRID_WIDTH, GridSystem.GRID_HEIGHT)
		astar.cell_size = Vector2.ONE
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER  # 상하좌우 이동만
		astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.update()
	_grid.cell_state_changed.connect(_on_cell_state_changed)


func _on_cell_state_changed(_position: Vector2i, _old_state, _new_state) -> void:
	_dirty = true


## start에서 가장 비용이 낮은 EXIT까지의 경로를 돌려준다.
## 반환: { "path": Array[Vector2i] (start 포함, 없으면 빈 배열), "breach": bool }
func find_path(start: Vector2i) -> Dictionary:
	if _dirty:
		_rebuild()

	var path := _best_path(_strict, start)
	if not path.is_empty():
		return {"path": path, "breach": false}

	path = _best_path(_breach, start)
	if not path.is_empty():
		Log.debug(Log.Category.MONSTER_AI, "길 봉쇄 감지: start=%s 돌파 경로 길이=%d, 부술 타워=%d" % [
			start, path.size(), _count_towers(path)])
	return {"path": path, "breach": not path.is_empty()}


func _rebuild() -> void:
	for y in range(GridSystem.GRID_HEIGHT):
		for x in range(GridSystem.GRID_WIDTH):
			var cell := Vector2i(x, y)
			var state := _grid.get_cell_state(cell)
			var is_tower := state == GridSystem.CellState.TOWER
			var is_wall := state == GridSystem.CellState.OBSTACLE

			_strict.set_point_solid(cell, is_tower or is_wall)
			_breach.set_point_solid(cell, is_wall)
			_breach.set_point_weight_scale(cell, BREACH_COST if is_tower else 1.0)
	_dirty = false
	Log.debug(Log.Category.MONSTER_AI, "[%s] 길찾기 그리드 재구성" % _grid.lane_tag())


func _best_path(astar: AStarGrid2D, start: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	if not astar.is_in_boundsv(start) or astar.is_point_solid(start):
		return best

	var best_cost := INF
	for x in range(GridSystem.GRID_WIDTH):
		var exit_cell := Vector2i(x, GridSystem.GRID_HEIGHT - 1)
		var path: Array[Vector2i] = astar.get_id_path(start, exit_cell)
		if path.is_empty():
			continue
		var cost := path.size() + _count_towers(path) * BREACH_COST
		if cost < best_cost:
			best_cost = cost
			best = path
	return best


func _count_towers(path: Array[Vector2i]) -> int:
	var count := 0
	for cell in path:
		if _grid.get_cell_state(cell) == GridSystem.CellState.TOWER:
			count += 1
	return count
