extends Node2D
class_name Monster
## 몬스터. 플레이어가 조종하지 않고 자동으로 경로를 따라 이동한다.
## - 평소: 타워를 우회해서 EXIT로 이동
## - 길이 완전히 막힘: 앞을 막은 타워를 공격 (일반형 공격력 = 무한대 -> 한 방에 파괴)
## - 보스 레인의 몬스터는 stop_at_row에 도착하면 멈추고 보스를 지속 공격한다 (BossController가 처리)
## TODO: 시야(사방 3칸) 제한, 공격형/지원형/공중형

signal reached_exit(monster: Monster)
signal died(monster: Monster)

var monster_id: int = 0
var owner_id: int = -1           # 보스 레인으로 보낸 플레이어 (보스가 보낸 몬스터는 -1)
var kind_id: String = "wave"
var speed: float = Balance.MONSTER_SPEED
var max_hp: float = 1.0
var hp: float = 1.0
var dps: float = 0.0             # 보스에게 주는 초당 피해
var body_color: Color = Color.RED
var stop_at_row: int = -1        # 0 이상이면 이 행에 도착했을 때 reached_exit
var draw_offset: Vector2 = Vector2.ZERO  # 겹쳐 서 있을 때 구분용 (셀 단위)

var grid_pos: Vector2i           # 마지막으로 도착한 셀
var cell_pos: Vector2            # 현재 위치 (셀 단위, 셀 중심 = +0.5)
var path: Array[Vector2i] = []   # 앞으로 지나갈 셀들 (현재 셀 제외)
var breaching: bool = false
var stopped: bool = false

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _no_path_warned := false
var _dead := false
var _hit_flash := 0.0


func setup(id: int, grid: GridSystem, renderer: GridRenderer, pathfinder: Pathfinder, spawn_cell: Vector2i) -> void:
	monster_id = id
	_grid = grid
	_renderer = renderer
	_pathfinder = pathfinder
	grid_pos = spawn_cell
	cell_pos = Vector2(spawn_cell) + Vector2(0.5, 0.5)
	hp = max_hp
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


## 이동 중단 (보스 앞에 도착했을 때)
func stop() -> void:
	stopped = true
	path.clear()
	queue_redraw()


func _on_grid_changed(_position: Vector2i, _old_state, _new_state) -> void:
	if not stopped:
		_repath()


func _repath() -> void:
	var result := _pathfinder.find_path(grid_pos)
	path = result.path
	breaching = result.breach
	if not path.is_empty() and path[0] == grid_pos:
		path.pop_front()

	if path.is_empty() and _grid.get_cell_state(grid_pos) != GridSystem.CellState.EXIT:
		if not _no_path_warned:
			Log.warn(Log.Category.MONSTER_AI, "[%s] 몬스터#%d 경로 없음 (위치=%s)" % [
				_grid.lane_tag(), monster_id, grid_pos])
			_no_path_warned = true
	else:
		_no_path_warned = false
		Log.debug(Log.Category.MONSTER_AI, "[%s] 몬스터#%d 경로 계산: 위치=%s 남은칸=%d 돌파=%s" % [
			_grid.lane_tag(), monster_id, grid_pos, path.size(), breaching])


func _process(delta: float) -> void:
	if _hit_flash > 0.0:
		_hit_flash -= delta
		queue_redraw()

	if stopped or path.is_empty():
		return

	var next_cell := path[0]

	# 다음 칸이 타워면 공격 (일반형: 공격력 무한대 -> 즉시 파괴, 환급 0원)
	if _grid.get_cell_state(next_cell) == GridSystem.CellState.TOWER:
		Log.info(Log.Category.TOWER, "[%s] 몬스터#%d가 타워 파괴 %s" % [
			_grid.lane_tag(), monster_id, next_cell])
		_grid.set_cell_state(next_cell, GridSystem.CellState.EMPTY)  # 경로 재계산은 신호로 처리됨
		return

	var target := Vector2(next_cell) + Vector2(0.5, 0.5)
	var step := speed * delta
	var to_target := target - cell_pos

	if to_target.length() <= step:
		cell_pos = target
		grid_pos = next_cell
		path.pop_front()
		_update_position()
		if _grid.get_cell_state(grid_pos) == GridSystem.CellState.EXIT \
				or (stop_at_row >= 0 and grid_pos.y >= stop_at_row):
			reached_exit.emit(self)
			return
	else:
		cell_pos += to_target.normalized() * step
		_update_position()

	queue_redraw()


func _update_position() -> void:
	position = (cell_pos + draw_offset) * _renderer.CELL_SIZE


func _draw() -> void:
	var cell: float = _renderer.CELL_SIZE
	var radius: float = cell * 0.3
	var color := body_color
	if breaching:
		color = Color.YELLOW
	if _hit_flash > 0.0:
		color = Color.WHITE
	draw_circle(Vector2.ZERO, radius, color)

	# 체력이 깎인 몬스터만 체력바 표시
	if hp < max_hp and max_hp > 0.0:
		var w := cell * 0.6
		var y := -radius - 4.0
		draw_rect(Rect2(-w * 0.5, y, w, 3.0), Color(0, 0, 0, 0.6))
		draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 3.0), Color.LIME)
