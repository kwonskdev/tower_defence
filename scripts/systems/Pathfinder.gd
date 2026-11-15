extends RefCounted
class_name Pathfinder
## 한 레인(GridSystem)용 길찾기.
##
## 1) 칸 단위 A*로 대략적인 경로를 구하고 (상하좌우)
## 2) 그 경로를 "직선으로 볼 수 있는 구간은 곧장 가도록" 펴서(any-angle) 연속 좌표 웨이포인트로 돌려준다.
##    -> 몬스터가 360도 방향으로 자연스럽게 움직인다.
##
## 두 개의 AStarGrid2D를 유지한다.
## - strict: 타워를 벽으로 취급 (평소 경로)
## - breach: 타워를 "통과 가능하지만 매우 비싼 칸"으로 취급 (완전 봉쇄 시 돌파 경로)
##   -> 부숴야 하는 타워 수가 가장 적은 경로가 선택된다.
## 트랩 타워(TRAP_TOWER)는 길을 막지 않으므로 둘 다 통과 가능.
## 격자가 바뀌면 dirty 표시만 하고, 다음 find_path 때 한 번에 다시 만든다.

const BREACH_COST := 1000.0
const NO_GOAL := Vector2i(-1, -1)   # goal을 주지 않으면 맨 아래 EXIT 행이 목표
const BODY_RADIUS := 0.3            # 몬스터 몸 반지름 (직선 이동 가능 여부 판정용)

const _CENTER_ONLY := [Vector2.ZERO]
const _BODY_OFFSETS := [
	Vector2.ZERO,
	Vector2(BODY_RADIUS, BODY_RADIUS), Vector2(-BODY_RADIUS, BODY_RADIUS),
	Vector2(BODY_RADIUS, -BODY_RADIUS), Vector2(-BODY_RADIUS, -BODY_RADIUS),
]

var _grid: GridSystem
var _strict := AStarGrid2D.new()
var _breach := AStarGrid2D.new()
var _dirty := true
var _tower_cells: Array[Vector2i] = []   # 지금 격자에 있는 (길을 막는) 타워 칸 목록
# 시야 제한 길찾기 중에만 쓰는 값: 몬스터가 "본 적 있는" 타워만 벽으로 안다
var _use_vision := false
var _vision_known: Dictionary = {}


func _init(grid: GridSystem) -> void:
	_grid = grid
	for astar in [_strict, _breach]:
		astar.region = Rect2i(0, 0, GridSystem.GRID_WIDTH, GridSystem.GRID_HEIGHT)
		astar.cell_size = Vector2.ONE
		astar.diagonal_mode = AStarGrid2D.DIAGONAL_MODE_NEVER  # 칸 경로는 상하좌우, 이후 직선화
		astar.default_compute_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.default_estimate_heuristic = AStarGrid2D.HEURISTIC_MANHATTAN
		astar.update()
	_grid.cell_state_changed.connect(_on_cell_state_changed)


func _on_cell_state_changed(_position: Vector2i, _old_state, _new_state) -> void:
	_dirty = true


## 현재 위치(연속 좌표, 셀 중심 = +0.5)에서 목표까지의 이동 경로.
## 반환: { "waypoints": Array[Vector2], "breach": bool, "ok": bool }
## breach가 true이면 마지막 웨이포인트 근처에 부숴야 할 타워가 있다.
## known: 몬스터가 본 적 있는 타워 칸 {Vector2i: true}. 주면 시야 제한 길찾기 (못 본 타워는 없는 것으로 친다). null이면 전부 안다.
func find_route(from_pos: Vector2, goal: Vector2i = NO_GOAL, known = null) -> Dictionary:
	var waypoints: Array[Vector2] = []
	var start := Vector2i(from_pos.floor())
	var result := find_path(start, goal, known)
	var cells: Array[Vector2i] = result.path
	if cells.is_empty():
		return {"waypoints": waypoints, "breach": false, "ok": false}

	waypoints = _smooth(from_pos, cells)
	return {"waypoints": waypoints, "breach": result.breach, "ok": true}


## 칸 단위 경로. start에서 가장 비용이 낮은 EXIT(또는 goal)까지.
## 반환: { "path": Array[Vector2i] (start 포함, 없으면 빈 배열), "breach": bool }
func find_path(start: Vector2i, goal: Vector2i = NO_GOAL, known = null) -> Dictionary:
	if _dirty:
		_rebuild()

	# 시야 제한: 못 본 타워 칸은 잠깐 지나갈 수 있는 칸으로 바꿔 놓고 길을 찾은 뒤 되돌린다
	var unseen: Array[Vector2i] = []
	_use_vision = known != null
	_vision_known = known if known != null else {}
	if _use_vision:
		for c in _tower_cells:
			if not _vision_known.has(c):
				unseen.append(c)
		for c in unseen:
			_strict.set_point_solid(c, false)
			_breach.set_point_weight_scale(c, 1.0)

	var result := _find_path_inner(start, goal)

	for c in unseen:
		_strict.set_point_solid(c, true)
		_breach.set_point_weight_scale(c, BREACH_COST)
	_use_vision = false
	_vision_known = {}
	return result


func _find_path_inner(start: Vector2i, goal: Vector2i) -> Dictionary:
	var path := _best_path(_strict, start, goal)
	if not path.is_empty():
		return {"path": path, "breach": false}

	path = _best_path(_breach, start, goal)
	if not path.is_empty():
		Log.debug(Log.Category.MONSTER_AI, "길 봉쇄 감지: start=%s 돌파 경로 길이=%d, 부술 타워=%d" % [
			start, path.size(), _count_towers(path)])
	return {"path": path, "breach": not path.is_empty()}


func _rebuild() -> void:
	_tower_cells.clear()
	for y in range(GridSystem.GRID_HEIGHT):
		for x in range(GridSystem.GRID_WIDTH):
			var cell := Vector2i(x, y)
			var state := _grid.get_cell_state(cell)
			var is_tower := state == GridSystem.CellState.TOWER
			var is_wall := state == GridSystem.CellState.OBSTACLE

			if is_tower:
				_tower_cells.append(cell)
			_strict.set_point_solid(cell, is_tower or is_wall)
			_breach.set_point_solid(cell, is_wall)
			_breach.set_point_weight_scale(cell, BREACH_COST if is_tower else 1.0)
	_dirty = false
	Log.debug(Log.Category.MONSTER_AI, "[%s] 길찾기 그리드 재구성" % _grid.lane_tag())


func _best_path(astar: AStarGrid2D, start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var best: Array[Vector2i] = []
	if not astar.is_in_boundsv(start) or astar.is_point_solid(start):
		return best

	if goal != NO_GOAL:
		if not astar.is_in_boundsv(goal) or astar.is_point_solid(goal):
			return best
		best = astar.get_id_path(start, goal)
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
		if _is_known_tower(cell):
			count += 1
	return count


## 이 칸이 (이 길찾기에서 아는) 타워인가. 시야 제한 중이면 본 적 없는 타워는 없는 것과 같다.
func _is_known_tower(cell: Vector2i) -> bool:
	if _grid.get_cell_state(cell) != GridSystem.CellState.TOWER:
		return false
	return not _use_vision or _vision_known.has(cell)


## 칸 경로를 직선으로 갈 수 있는 구간끼리 이어서 웨이포인트로 만든다 (string pulling).
func _smooth(from_pos: Vector2, cells: Array[Vector2i]) -> Array[Vector2]:
	var result: Array[Vector2] = []
	var anchor := from_pos
	var i := 0
	var last := cells.size() - 1
	while i < last:
		var furthest := i + 1  # 바로 옆 칸은 항상 갈 수 있다고 본다
		for j in range(i + 2, last + 1):
			if _line_clear(anchor, _center(cells[j])):
				furthest = j
			else:
				break
		anchor = _center(cells[furthest])
		result.append(anchor)
		i = furthest
	return result


## a에서 b까지 몸통(반지름 BODY_RADIUS)이 벽(타워/장애물)에 걸리지 않고 직선으로 갈 수 있는가.
## 출발 칸과 도착 칸은 검사에서 제외한다 (도착 칸은 부술 타워일 수 있음).
func _line_clear(a: Vector2, b: Vector2) -> bool:
	var start_cell := Vector2i(a.floor())
	var end_cell := Vector2i(b.floor())
	var dist := a.distance_to(b)
	var steps := maxi(1, int(ceil(dist / 0.2)))

	for s in range(steps + 1):
		var t := float(s) / steps
		var p := a.lerp(b, t)
		# 출발 직후 구간은 이미 몸이 있는 곳이므로 중심점만 검사
		var offsets: Array = _CENTER_ONLY if dist * t < 0.35 else _BODY_OFFSETS
		for off in offsets:
			var c := Vector2i((p + off).floor())
			if c == start_cell or c == end_cell:
				continue
			if _is_wall(c):
				return false
	return true


func _is_wall(cell: Vector2i) -> bool:
	var state := _grid.get_cell_state(cell)  # 격자 밖은 OBSTACLE로 돌아온다
	if state == GridSystem.CellState.TOWER:
		return not _use_vision or _vision_known.has(cell)
	return state == GridSystem.CellState.OBSTACLE


func _center(cell: Vector2i) -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)
