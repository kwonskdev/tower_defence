extends Node2D
class_name Monster
## 몬스터. 플레이어가 조종하지 않고 자동으로 경로를 따라 이동한다.
## - 연속 좌표(cell_pos, 셀 단위)로 움직이며 웨이포인트를 향해 어느 방향으로든 직진한다.
## - 평소: 타워를 우회해서 목표(EXIT 또는 goal_cell/final_point)로 이동
## - 길이 완전히 막힘: 앞을 막은 타워를 공격 (일반형 공격력 = 무한대 -> 한 방에 파괴)
## - 보스 레인의 몬스터는 final_point(보스 주변 자리)에 도착하면 멈추고 보스를 지속 공격한다
## TODO: 시야(사방 3칸) 제한, 지원형/공중형

signal reached_exit(monster: Monster)
signal died(monster: Monster)

const ARRIVE_DISTANCE := 0.1
const TOWER_ATTACK_DISTANCE := 0.95   # 웨이포인트 타워 중심까지 이 거리 이하면 타워를 공격

var monster_id: int = 0
var owner_id: int = -1           # 보스 레인으로 보낸 플레이어 (보스가 보낸 몬스터는 -1)
var kind_id: String = "wave"
var shape: String = "horn"       # 외형: horn(일반형) / coin / shield / spike
var speed: float = Balance.MONSTER_SPEED
var max_hp: float = 1.0
var hp: float = 1.0
var dps: float = 0.0             # 보스에게 주는 초당 피해
var body_color: Color = Color(0.85, 0.2, 0.2)

# 목표: goal_cell을 주면 그 칸까지 간 뒤 final_point로 이동, 주지 않으면 맨 아래 EXIT 행
var goal_cell: Vector2i = Pathfinder.NO_GOAL
var final_point: Vector2 = Vector2.ZERO
var attack_dir: Vector2 = Vector2.DOWN  # 정지 후 공격하는 방향 (보스 쪽)

var grid_pos: Vector2i           # 현재 있는 셀
var cell_pos: Vector2            # 현재 위치 (셀 단위, 셀 중심 = +0.5)
var waypoints: Array[Vector2] = []  # 앞으로 지나갈 지점들
var facing: Vector2 = Vector2.DOWN
var breaching: bool = false
var stopped: bool = false

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _no_path_warned := false
var _dead := false
var _arrived := false
var _hit_flash := 0.0
var _anim := 0.0


func setup(id: int, grid: GridSystem, renderer: GridRenderer, pathfinder: Pathfinder, spawn_cell: Vector2i) -> void:
	monster_id = id
	_grid = grid
	_renderer = renderer
	_pathfinder = pathfinder
	grid_pos = spawn_cell
	cell_pos = Vector2(spawn_cell) + Vector2(0.5, 0.5)
	hp = max_hp
	_anim = randf() * TAU
	_update_position()

	# pathfinder가 먼저 연결되어 있으므로 dirty 처리 후 이 핸들러가 호출된다.
	_grid.cell_state_changed.connect(_on_grid_changed)
	_repath()


func take_damage(amount: float) -> void:
	if _dead:
		return
	hp -= amount
	_hit_flash = 0.1
	if hp <= 0.0:
		_dead = true
		died.emit(self)


## 이동 중단 (보스 앞 자리에 도착했을 때)
func stop(look_at: Vector2) -> void:
	stopped = true
	waypoints.clear()
	attack_dir = (look_at - cell_pos).normalized()
	facing = attack_dir


## 남은 이동 거리 (타워가 기지에 가장 가까운 몬스터를 노릴 때 사용)
func remaining_distance() -> float:
	var total := 0.0
	var p := cell_pos
	for w in waypoints:
		total += p.distance_to(w)
		p = w
	return total


func _on_grid_changed(_position: Vector2i, _old_state, _new_state) -> void:
	if not stopped:
		_repath()


func _repath() -> void:
	# 지금 서 있는 위치에서 다시 계산하므로 뒤로 되돌아가는 일이 없다.
	var result := _pathfinder.find_route(cell_pos, goal_cell)
	waypoints.assign(result.waypoints)
	breaching = result.breach

	if result.ok and goal_cell != Pathfinder.NO_GOAL:
		waypoints.append(final_point)

	if not result.ok:
		if not _no_path_warned:
			Log.warn(Log.Category.MONSTER_AI, "[%s] 몬스터#%d 경로 없음 (위치=%s)" % [
				_grid.lane_tag(), monster_id, cell_pos])
			_no_path_warned = true
	else:
		_no_path_warned = false
		Log.debug(Log.Category.MONSTER_AI, "[%s] 몬스터#%d 경로 계산: 위치=(%.1f, %.1f) 웨이포인트=%d 돌파=%s" % [
			_grid.lane_tag(), monster_id, cell_pos.x, cell_pos.y, waypoints.size(), breaching])


func _process(delta: float) -> void:
	_anim += delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
	queue_redraw()

	if stopped:
		return
	if waypoints.is_empty():
		_check_arrival()
		return

	var target := waypoints[0]
	var target_cell := Vector2i(target.floor())

	# 다음 목적지가 타워 칸이면 가까워졌을 때 공격 (일반형: 공격력 무한대 -> 즉시 파괴, 환급 0원)
	if _grid.get_cell_state(target_cell) == GridSystem.CellState.TOWER \
			and cell_pos.distance_to(target) <= TOWER_ATTACK_DISTANCE:
		Log.info(Log.Category.TOWER, "[%s] 몬스터#%d가 타워 파괴 %s" % [_grid.lane_tag(), monster_id, target_cell])
		_grid.set_cell_state(target_cell, GridSystem.CellState.EMPTY)  # 경로 재계산은 신호로 처리됨
		return

	var to_target := target - cell_pos
	var step := speed * delta
	if to_target.length() <= step:
		cell_pos = target
		waypoints.pop_front()
	else:
		facing = to_target.normalized()
		cell_pos += facing * step

	grid_pos = Vector2i(cell_pos.floor())
	_update_position()

	if waypoints.is_empty():
		_check_arrival()


func _check_arrival() -> void:
	if _arrived:
		return
	var arrived := false
	if goal_cell == Pathfinder.NO_GOAL:
		arrived = _grid.get_cell_state(grid_pos) == GridSystem.CellState.EXIT
	else:
		arrived = cell_pos.distance_to(final_point) <= ARRIVE_DISTANCE
	if arrived:
		_arrived = true
		reached_exit.emit(self)


func _update_position() -> void:
	position = cell_pos * _renderer.CELL_SIZE


func _draw() -> void:
	var cell: float = _renderer.CELL_SIZE
	var r: float = cell * 0.32
	var moving := not stopped and not waypoints.is_empty()

	# 걷는 동안 통통 튀고, 멈추면 숨쉬듯 흔들림. 보스 앞에서는 보스 쪽으로 달려들었다 물러남.
	var bob := absf(sin(_anim * speed * 3.0)) * cell * 0.09 if moving else sin(_anim * 3.0) * cell * 0.015
	var lunge := Vector2.ZERO
	if stopped:
		lunge = attack_dir * maxf(0.0, sin(_anim * 9.0)) * cell * 0.14
	var c := Vector2(0, -bob) + lunge

	var color := body_color
	if breaching:
		color = Color(1.0, 0.85, 0.2)
	if _hit_flash > 0.0:
		color = Color.WHITE

	# 그림자
	draw_set_transform(Vector2(0, r * 0.95), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, r, Color(0, 0, 0, 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_decor_back(c, r, color)

	# 몸통
	draw_circle(c, r, color)
	draw_arc(c, r, 0.0, TAU, 24, color.darkened(0.45), 2.0)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.28, color.lightened(0.35))  # 하이라이트

	_draw_decor_front(c, r)

	# 눈 (이동 방향을 쳐다봄)
	var dir := facing if facing.length() > 0.01 else Vector2.DOWN
	var perp := Vector2(-dir.y, dir.x)
	var eye_center := c + dir * r * 0.3
	for side in [-1.0, 1.0]:
		var e: Vector2 = eye_center + perp * r * 0.38 * side
		draw_circle(e, r * 0.24, Color.WHITE)
		draw_circle(e + dir * r * 0.09, r * 0.12, Color(0.05, 0.05, 0.1))

	# 체력이 깎인 몬스터만 체력바 표시
	if hp < max_hp and max_hp > 0.0:
		var w := cell * 0.62
		var y := -r - cell * 0.22
		draw_rect(Rect2(-w * 0.5, y, w, 4.0), Color(0, 0, 0, 0.65))
		draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 4.0), Color(0.3, 0.95, 0.3))


## 몸통 뒤에 그려지는 장식 (뿔, 가시)
func _draw_decor_back(c: Vector2, r: float, color: Color) -> void:
	match shape:
		"horn":
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(side * r * 0.75, -r * 0.45),
					c + Vector2(side * r * 0.35, -r * 1.2),
					c + Vector2(side * r * 0.1, -r * 0.8),
				]), color.darkened(0.3))
		"spike":
			for i in range(8):
				var a := i * TAU / 8.0 + _anim * 0.6
				var base := Vector2.from_angle(a)
				var side := Vector2.from_angle(a + PI * 0.5)
				draw_colored_polygon(PackedVector2Array([
					c + base * r * 0.8 + side * r * 0.22,
					c + base * r * 1.45,
					c + base * r * 0.8 - side * r * 0.22,
				]), color.darkened(0.2))


## 몸통 위에 그려지는 장식 (동전, 방패)
func _draw_decor_front(c: Vector2, r: float) -> void:
	match shape:
		"coin":
			var p := c + Vector2(0, -r * 1.25)
			draw_circle(p, r * 0.42, Color(1.0, 0.85, 0.2))
			draw_arc(p, r * 0.42, 0.0, TAU, 16, Color(0.7, 0.5, 0.0), 2.0)
			draw_line(p + Vector2(0, -r * 0.2), p + Vector2(0, r * 0.2), Color(0.7, 0.5, 0.0), 2.0)
		"shield":
			draw_arc(c, r * 1.18, -PI * 0.15, PI * 1.15, 20, Color(0.85, 0.9, 1.0), 3.0)
			draw_arc(c, r * 1.18, PI * 1.15, PI * 1.85, 10, Color(0.85, 0.9, 1.0, 0.35), 3.0)
