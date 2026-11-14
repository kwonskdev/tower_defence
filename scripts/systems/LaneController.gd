extends Node
class_name LaneController
## 한 플레이어 레인의 진행을 담당한다.
## - 경제: 골드 / 수입(주기적 지급) / 생명
## - 타워: 사거리 안의 몬스터를 자동 공격
## - 보스가 보내는 몬스터(wave)를 스폰하고, 죽이면 골드, 기지에 닿으면 생명 -1
## 협력(PvE)에서는 참여한 플레이어의 레인에만 만든다. (참여 안 한 레인은 비어 있음)

signal lives_changed(lives: int)
signal lane_failed(player_id: int)

var player_id: int = 0
var gold: int = Balance.START_GOLD
var income: int = Balance.BASE_INCOME   # 수입 틱마다 받는 골드
var lives: int = Balance.START_LIVES
var active := true
var monsters: Array[Monster] = []

var towers: Dictionary = {}  # Vector2i(셀) -> 남은 쿨다운(초)

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _income_timer: Timer
var _next_monster_id := 1
var _lane_visible := true


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


func _process(delta: float) -> void:
	if not active:
		return

	# 타워 공격
	for cell in towers:
		var cooldown: float = towers[cell] - delta
		if cooldown <= 0.0:
			var target := _find_target(cell)
			if target:
				target.take_damage(Balance.TOWER_DAMAGE)
				cooldown = Balance.TOWER_COOLDOWN
			else:
				cooldown = 0.0  # 대기 상태 유지 (적이 들어오면 바로 발사)
		towers[cell] = cooldown


## 사거리 안의 몬스터 중 기지에 가장 가까운(남은 경로가 짧은) 몬스터
func _find_target(tower_cell: Vector2i) -> Monster:
	var center := Vector2(tower_cell) + Vector2(0.5, 0.5)
	var best: Monster = null
	for m in monsters:
		if m.cell_pos.distance_to(center) > Balance.TOWER_RANGE:
			continue
		if best == null or m.path.size() < best.path.size():
			best = m
	return best


func _on_cell_changed(position: Vector2i, old_state, new_state) -> void:
	if new_state == GridSystem.CellState.TOWER:
		towers[position] = 0.0
	elif old_state == GridSystem.CellState.TOWER:
		towers.erase(position)


# --- 경제 ---

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
func spawn_wave_monster(hp_value: float) -> void:
	if not active:
		return
	var spawn_cells := _grid.get_spawn_cells()
	if spawn_cells.is_empty():
		Log.error(Log.Category.GAME, "[P%d] 스폰 셀이 없음" % (player_id + 1))
		return

	var monster := Monster.new()
	monster.max_hp = hp_value
	monster.visible = _lane_visible
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cells.pick_random())
	monster.reached_exit.connect(_on_monster_reached_exit)
	monster.died.connect(_on_monster_died)
	_renderer.add_child(monster)
	monsters.append(monster)
	Log.debug(Log.Category.GAME, "[P%d] 몬스터#%d 스폰 hp=%.1f (필드 위 %d마리)" % [
		player_id + 1, _next_monster_id, hp_value, monsters.size()])
	_next_monster_id += 1


func _on_monster_died(monster: Monster) -> void:
	monsters.erase(monster)
	monster.queue_free()
	gold += Balance.KILL_REWARD
	Log.debug(Log.Category.ECONOMY, "[P%d] 몬스터#%d 처치 +%d골드 잔액=%d" % [
		player_id + 1, monster.monster_id, Balance.KILL_REWARD, gold])


func _on_monster_reached_exit(monster: Monster) -> void:
	monsters.erase(monster)
	monster.queue_free()
	lives -= 1
	Log.info(Log.Category.GAME, "[P%d] 몬스터#%d 기지 도달! 생명 %d" % [player_id + 1, monster.monster_id, lives])
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


## 타워를 지을 수 없는 칸인지 (몬스터가 서 있거나 곧 들어갈 칸)
func is_cell_occupied(cell: Vector2i) -> bool:
	for m in monsters:
		if m.grid_pos == cell or (not m.path.is_empty() and m.path[0] == cell):
			return true
	return false


## 현재 화면에 보이는 레인인지에 따라 몬스터 표시/숨김
func set_lane_visible(is_shown: bool) -> void:
	_lane_visible = is_shown
	for m in monsters:
		m.visible = is_shown
