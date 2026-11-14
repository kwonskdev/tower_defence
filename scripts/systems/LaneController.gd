extends Node
class_name LaneController
## 한 플레이어 레인의 진행을 담당한다.
## - 경제: 골드 / 수입(주기적 지급) / 생명
## - 타워: 건설(종류 + 랜덤 색깔), 타워 노드 관리
## - 보스가 보내는 몬스터(wave)를 스폰하고, 죽이면 골드, 기지에 닿으면 생명 -1
## 협력(PvE)에서는 참여한 플레이어의 레인에만 만든다. (참여 안 한 레인은 비어 있음)

signal lives_changed(lives: int)
signal lane_failed(player_id: int)

var player_id: int = 0
var gold: int = Balance.START_GOLD
var income: int = Balance.BASE_INCOME   # 수입 틱마다 받는 골드
var lives: int = Balance.START_LIVES
var active := true
var lane_visible := true
var monsters: Array[Monster] = []
var towers: Dictionary = {}  # Vector2i(셀) -> Tower

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _income_timer: Timer
var _next_monster_id := 1


func setup(p_player_id: int, grid: GridSystem, renderer: GridRenderer) -> void:
	player_id = p_player_id
	_grid = grid
	_renderer = renderer
	_pathfinder = Pathfinder.new(grid)
	_grid.cell_state_changed.connect(_on_cell_changed)

	_income_timer = Timer.new()
	_income_timer.wait_time = Balance.INCOME_INTERVAL
	_income_timer.timeout.connect(_on_income_tick)
	add_child(_income_timer)
	_income_timer.start()

	Log.info(Log.Category.GAME, "[P%d] 레인 시작: 골드=%d, 수입=%d/%.0fs, 생명=%d" % [
		player_id + 1, gold, income, Balance.INCOME_INTERVAL, lives])


# --- 타워 ---

## 타워를 짓는다. 검증/골드 차감은 호출하는 쪽(GameField)에서 끝낸 뒤 부른다.
func build_tower(cell: Vector2i, kind_id: String) -> Tower:
	var kind := Balance.tower_kind(kind_id)
	var color_info: Dictionary = Balance.TOWER_COLORS.pick_random()  # 모든 색 동일 확률
	var state := GridSystem.CellState.TOWER if kind.blocks else GridSystem.CellState.TRAP_TOWER
	_grid.set_cell_state(cell, state)

	var tower := Tower.new()
	tower.setup(cell, kind, color_info, self, _renderer)
	tower.visible = lane_visible
	tower.z_index = 1
	_renderer.add_child(tower)
	towers[cell] = tower

	Log.info(Log.Category.COLOR, "[P%d] 타워 %s 색깔 할당: %s" % [player_id + 1, cell, color_info.name])
	return tower


## 사거리 안의 몬스터 중 기지에 가장 가까운(남은 이동거리가 짧은) 몬스터
func find_target(from_cell_pos: Vector2, range_cells: float) -> Monster:
	var best: Monster = null
	var best_dist := INF
	for m in monsters:
		if m.cell_pos.distance_to(from_cell_pos) > range_cells:
			continue
		var d := m.remaining_distance()
		if d < best_dist:
			best_dist = d
			best = m
	return best


func _on_cell_changed(position: Vector2i, _old_state, new_state) -> void:
	# 몬스터가 타워를 부수면 칸이 EMPTY가 된다
	if new_state == GridSystem.CellState.EMPTY and towers.has(position):
		var tower: Tower = towers[position]
		Effects.ring(_renderer, tower.center_cell_pos(), 0.8, Color(1.0, 0.5, 0.2), lane_visible)
		Effects.float_text(_renderer, tower.center_cell_pos(), "파괴!", Color(1.0, 0.4, 0.3), lane_visible)
		tower.queue_free()
		towers.erase(position)


# --- 경제 ---

## 다음 수입 지급까지 남은 시간(초)
func income_time_left() -> float:
	return _income_timer.time_left


func try_spend(amount: int, reason: String) -> bool:
	if not active:
		return false
	if gold < amount:
		Log.info(Log.Category.ECONOMY, "[P%d] 골드 부족: %s 필요=%d 보유=%d" % [player_id + 1, reason, amount, gold])
		return false
	gold -= amount
	Log.info(Log.Category.ECONOMY, "[P%d] -%d골드 (%s) 잔액=%d" % [player_id + 1, amount, reason, gold])
	return true


func add_income(amount: int) -> void:
	income += amount
	Log.info(Log.Category.ECONOMY, "[P%d] 수입 +%d -> %d/%.0fs" % [player_id + 1, amount, income, Balance.INCOME_INTERVAL])


func _on_income_tick() -> void:
	if not active:
		return
	gold += income
	Log.info(Log.Category.ECONOMY, "[P%d] 수입 지급 +%d 잔액=%d" % [player_id + 1, income, gold])


# --- 몬스터 ---

## 보스의 자동 파견: 이 레인에 몬스터를 보낸다
func spawn_wave_monster(hp_value: float, type_id: String = "grunt") -> void:
	if not active:
		return
	var spawn_cells := _grid.get_spawn_cells()
	if spawn_cells.is_empty():
		Log.error(Log.Category.GAME, "[P%d] 스폰 셀이 없음" % (player_id + 1))
		return

	var wave_type: Dictionary = Balance.WAVE_TYPES[type_id]
	var monster := Monster.new()
	monster.kind_id = type_id
	monster.max_hp = hp_value
	monster.speed = wave_type.speed
	monster.size_scale = wave_type.size
	monster.life_damage = wave_type.life
	monster.reward = wave_type.reward
	monster.shape = wave_type.shape
	monster.body_color = wave_type.color
	monster.visible = lane_visible
	monster.z_index = 2
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cells.pick_random())
	monster.reached_exit.connect(_on_monster_reached_exit)
	monster.died.connect(_on_monster_died)
	_renderer.add_child(monster)
	monsters.append(monster)
	Log.debug(Log.Category.GAME, "[P%d] 몬스터#%d(%s) 스폰 hp=%.1f (필드 위 %d마리)" % [
		player_id + 1, _next_monster_id, wave_type.name, hp_value, monsters.size()])
	_next_monster_id += 1


func _on_monster_died(monster: Monster) -> void:
	monsters.erase(monster)
	gold += monster.reward
	Effects.float_text(_renderer, monster.cell_pos, "+%d" % monster.reward, Color(1.0, 0.9, 0.3), lane_visible)
	Effects.ring(_renderer, monster.cell_pos, 0.6, monster.body_color, lane_visible)
	monster.queue_free()
	Log.debug(Log.Category.ECONOMY, "[P%d] 몬스터#%d 처치 +%d골드 잔액=%d" % [
		player_id + 1, monster.monster_id, monster.reward, gold])


func _on_monster_reached_exit(monster: Monster) -> void:
	monsters.erase(monster)
	monster.queue_free()
	lives -= monster.life_damage
	Log.info(Log.Category.GAME, "[P%d] 몬스터#%d(%s) 기지 도달! 생명 -%d -> %d" % [
		player_id + 1, monster.monster_id, monster.kind_id, monster.life_damage, lives])
	lives_changed.emit(lives)

	if lives <= 0 and active:
		Log.warn(Log.Category.GAME, "[P%d] 생명 0 - 이 레인 패배" % (player_id + 1))
		shutdown()
		lane_failed.emit(player_id)


## 게임이 끝났거나 이 레인이 패배했을 때 모든 진행을 멈춘다
func shutdown() -> void:
	active = false
	_income_timer.stop()
	for m in monsters:
		m.set_process(false)


## 몸이 겹쳐 있어서 타워를 지을 수 없는 칸인지
func is_cell_occupied(cell: Vector2i) -> bool:
	var center := Vector2(cell) + Vector2(0.5, 0.5)
	for m in monsters:
		if absf(m.cell_pos.x - center.x) < 0.85 and absf(m.cell_pos.y - center.y) < 0.85:
			return true
	return false


## 현재 화면에 보이는 레인인지에 따라 몬스터/타워 표시/숨김
func set_lane_visible(is_shown: bool) -> void:
	lane_visible = is_shown
	for m in monsters:
		m.visible = is_shown
	for t in towers.values():
		t.visible = is_shown
