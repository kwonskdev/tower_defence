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
var towers: Array[Tower] = []  # 한 칸에 타워 1개

# 진화 업그레이드 (레인 전체 공유, 같은 계열의 모든 타워에 적용)
var stat_levels: Dictionary = {} # "계열.스킬.키" -> 레벨 1~3 (없으면 1). B 스킬은 타워마다 배우지만 항목 레벨은 계열 공통

# 색깔 시스템 (레인 전체 공유)
var color_levels: Dictionary = {} # "색깔이름" -> 레벨 0~5 (0=업그레이드 안 함, 1~5=업그레이드 레벨)

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _income_timer: Timer
var _next_monster_id := 1
var _boss_controller = null  # BossController 참조 (남색 강화 보너스용)


func setup(p_player_id: int, grid: GridSystem, renderer: GridRenderer) -> void:
	player_id = p_player_id
	_grid = grid
	_renderer = renderer
	_pathfinder = Pathfinder.new(grid)
	_grid.cell_state_changed.connect(_on_cell_changed)

	_income_timer = Timer.new()
	_income_timer.wait_time = Balance.INCOME_INTERVAL
	_income_timer.timeout.connect(_on_income_tick)
	add_child(_income_timer)  # 수입 타이머는 시작 버튼을 누를 때 돈다 (begin)

	Log.info(Log.Category.GAME, "[P%d] 레인 시작: 골드=%d, 수입=%d/%.0fs, 생명=%d" % [
		player_id + 1, gold, income, Balance.INCOME_INTERVAL, lives])


## 시작 버튼: 수입 지급이 시작된다
func begin() -> void:
	if active and _income_timer.is_stopped():
		_income_timer.start()


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
	towers.append(tower)

	Log.info(Log.Category.COLOR, "[P%d] 타워 %s 색깔 할당: %s" % [player_id + 1, cell, color_info.name])
	return tower


# --- 진화 / 업그레이드 ---

## 업그레이드 항목 하나의 현재 레벨 (1~3). 안 올렸으면 1.
func stat_level(evo: String, skill: String, key: String) -> int:
	return int(stat_levels.get("%s.%s.%s" % [evo, skill, key], 1))


## 설명 문구용: 이 계열의 항목별 레벨 {"A.count": 2, ...}
func levels_of(evo: String) -> Dictionary:
	var levels := {}
	for skill in ["A", "B"]:
		for key in Evolutions.PARAMS[evo][skill]:
			levels["%s.%s" % [skill, key]] = stat_level(evo, skill, key)
	return levels


## 타워 1기를 진화시킨다 (골드). 같은 기본 타워가 가진 계열 2개 중 하나를 고르며, 한 번 고르면 바꿀 수 없다.
func evolve_tower(tower: Tower, evo: String) -> bool:
	if tower == null or tower.lane != self or not tower.can_evolve():
		return false
	if evo not in Evolutions.TREE[tower.kind.id]:
		return false
	if not try_spend(Balance.EVOLVE_COST, "타워 진화 %s(%s) -> %s" % [tower.cell, tower.kind.name, Evolutions.evo_name(evo)]):
		return false
	tower.set_evolution(evo)
	Effects.ring(_renderer, tower.center_cell_pos(), 0.8, Evolutions.DATA[evo].color, lane_visible)
	Log.info(Log.Category.TOWER, "[P%d] 타워 진화 %s: %s -> %s" % [player_id + 1, tower.cell, tower.kind.name, Evolutions.evo_name(evo)])
	return true


## 타워 1기가 B 스킬을 배우는 비용. 진화 전이거나 이미 배웠으면 -1.
func learn_cost(tower: Tower) -> int:
	if tower == null or tower.evolution == "" or tower.b_learned:
		return -1
	return Balance.SKILL_LEARN_COST


## 타워 1기의 B 스킬을 배운다 (진화처럼 타워마다 따로, 골드).
func learn_tower_skill(tower: Tower) -> bool:
	if tower == null or tower.lane != self:
		return false
	var cost := learn_cost(tower)
	if cost < 0:
		return false
	var evo := tower.evolution
	if not try_spend(cost, "타워 %s(%s) B 스킬 배우기: %s" % [tower.cell, Evolutions.evo_name(evo), Evolutions.skill_name(evo, "B")]):
		return false
	tower.b_learned = true
	Effects.ring(_renderer, tower.center_cell_pos(), 0.8, Evolutions.DATA[evo].color, lane_visible)
	Log.info(Log.Category.TOWER, "[P%d] B 스킬 습득 %s: %s %s" % [player_id + 1, tower.cell, Evolutions.evo_name(evo), Evolutions.skill_name(evo, "B")])
	return true


## 항목 레벨을 한 단계 올리는 비용. 올릴 수 없으면 -1 (최대 레벨). 계열의 모든 타워에 적용되고, B 항목은 B를 배운 타워에만 효과가 있다.
func stat_upgrade_cost(evo: String, skill: String, key: String) -> int:
	var lv := stat_level(evo, skill, key)
	if lv >= Evolutions.MAX_LEVEL:
		return -1
	return int(Balance.STAT_UPGRADE_COSTS[lv - 1])


## 업그레이드 탭: 항목 하나를 올린다. 그 계열로 진화한 모든 타워가 바로 강해진다.
func upgrade_stat(evo: String, skill: String, key: String) -> bool:
	var cost := stat_upgrade_cost(evo, skill, key)
	if cost < 0:
		return false
	var next := stat_level(evo, skill, key) + 1
	if not try_spend(cost, "%s %s Lv%d" % [Evolutions.evo_name(evo), key, next]):
		return false
	stat_levels["%s.%s.%s" % [evo, skill, key]] = next
	Log.info(Log.Category.TOWER, "[P%d] 업그레이드: %s %s.%s -> Lv%d" % [player_id + 1, Evolutions.evo_name(evo), skill, key, next])
	return true


## 사거리 안의 몬스터 중 기지에 가까운 순서로 최대 count마리 (난사형이 서로 다른 적을 노릴 때 사용)
func find_targets(from_cell_pos: Vector2, range_cells: float, anti_air: bool, count: int) -> Array[Monster]:
	var found: Array[Monster] = []
	for m in monsters:
		if m.flying == anti_air and m.cell_pos.distance_to(from_cell_pos) <= range_cells:
			found.append(m)
	found.sort_custom(func(a: Monster, b: Monster): return a.remaining_distance() < b.remaining_distance())
	var picked: Array[Monster] = []
	for i in range(mini(count, found.size())):
		picked.append(found[i])
	return picked


## 사거리 안의 몬스터 중 기지에 가장 가까운(남은 이동거리가 짧은) 몬스터
## 대공 타워(anti_air)는 공중 몬스터만, 그 외 타워는 지상 몬스터만 노린다.
func find_target(from_cell_pos: Vector2, range_cells: float, anti_air: bool = false) -> Monster:
	var best: Monster = null
	var best_dist := INF
	for m in monsters:
		if m.flying != anti_air:
			continue
		if m.cell_pos.distance_to(from_cell_pos) > range_cells:
			continue
		var d := m.remaining_distance()
		if d < best_dist:
			best_dist = d
			best = m
	return best


func _on_cell_changed(position: Vector2i, _old_state, new_state) -> void:
	# 몬스터가 타워를 부수면 칸이 EMPTY가 된다 (부술 수 있는 건 길을 막는 타워뿐)
	if new_state != GridSystem.CellState.EMPTY:
		return
	for tower in towers:
		if tower.cell == position:
			Effects.ring(_renderer, tower.center_cell_pos(), 0.8, Color(1.0, 0.5, 0.2), lane_visible)
			Effects.float_text(_renderer, tower.center_cell_pos(), "파괴!", Color(1.0, 0.4, 0.3), lane_visible)
			tower.queue_free()
			towers.erase(tower)
			break


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

## 이 칸에 길을 막는 타워를 지으면 몬스터가 지나갈 길이 완전히 막히는가
func would_block_path(cell: Vector2i) -> bool:
	return _pathfinder.would_block(cell, _grid.get_spawn_cells())


## 몬스터가 나오는 칸 하나 (없으면 NO_GOAL). 한 웨이브는 같은 칸에서 뭉쳐서 나온다.
func pick_spawn_cell() -> Vector2i:
	var cells := _grid.get_spawn_cells()
	return cells.pick_random() if not cells.is_empty() else Pathfinder.NO_GOAL


## 보스의 자동 파견: 이 레인에 몬스터를 보낸다 (level: 보스 라운드. 보상/방어력이 라운드에 따라 오른다)
func spawn_wave_monster(hp_value: float, type_id: String = "grunt", level: int = 1, spawn_cell: Vector2i = Pathfinder.NO_GOAL) -> void:
	if not active:
		return
	if spawn_cell == Pathfinder.NO_GOAL:
		spawn_cell = pick_spawn_cell()
	if spawn_cell == Pathfinder.NO_GOAL:
		Log.error(Log.Category.GAME, "[P%d] 스폰 셀이 없음" % (player_id + 1))
		return

	var wave_type: Dictionary = WaveTypes.TYPES[type_id]
	var monster := Monster.new()
	monster.apply_look(wave_type)
	monster.kind_id = type_id
	monster.max_hp = hp_value
	monster.life_damage = wave_type.life
	monster.armor = wave_type.armor
	monster.regen = wave_type.regen
	monster.flying = wave_type.flying
	monster.reward = roundi(wave_type.reward * (1.0 + 0.15 * (level - 1)))
	monster.visible = lane_visible
	monster.z_index = 2
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cell)
	monster.reached_exit.connect(_on_monster_reached_exit)
	monster.died.connect(_on_monster_died)
	_renderer.add_child(monster)
	monsters.append(monster)
	Log.debug(Log.Category.GAME, "[P%d] 몬스터#%d(%s) 스폰 hp=%.1f 방어=%.2f (필드 위 %d마리)" % [
		player_id + 1, _next_monster_id, wave_type.name, hp_value, monster.armor, monsters.size()])
	_next_monster_id += 1


## 지원형 B: 표식이 걸린 적이 죽으면 근처 표식 없는 적에게 표식을 옮긴다
func _spread_marks(monster: Monster) -> void:
	# B(표식 전파)를 배운 지원형 타워가 남긴 표식만 퍼진다
	var spreadable: Array = []
	for mk in monster.death_marks:
		if is_instance_valid(mk.src) and mk.src.has_skill("B"):
			spreadable.append(mk)
	if spreadable.is_empty():
		return
	var radius := Evolutions.p("support", "B", "radius", stat_level("support", "B", "radius"))
	var count := int(Evolutions.p("support", "B", "count", stat_level("support", "B", "count")))
	var near: Array[Monster] = []
	for m in monsters:
		if m != monster and not m.is_dead() and m.flying == monster.flying and m.marks.is_empty() \
				and m.cell_pos.distance_to(monster.cell_pos) <= radius:
			near.append(m)
	near.sort_custom(func(a: Monster, b: Monster): return a.cell_pos.distance_to(monster.cell_pos) < b.cell_pos.distance_to(monster.cell_pos))
	for m in near.slice(0, count):
		var mk: Dictionary = spreadable.pick_random()
		m.add_mark(mk.src, float(mk.dmg))
		Effects.ring(_renderer, m.cell_pos, 0.5, Color(0.8, 0.5, 1.0), lane_visible)


func _on_monster_died(monster: Monster) -> void:
	monsters.erase(monster)
	_spread_marks(monster)

	# 기본 보상
	var base_reward := monster.reward
	var actual_reward := base_reward

	# 색깔 보너스 처리
	if is_instance_valid(monster._killer):
		var killer_tower = monster._killer
		match killer_tower.color_info.name:
			"초록":  # 처치 시 골드 보너스
				var bonus := color_bonus_value("초록")
				if bonus > 0.0:
					actual_reward = roundi(base_reward * (1.0 + bonus))

			"남색":  # 처치 시 보낸 몬스터 N마리 강화
				var count := int(color_bonus_value("남색"))
				if count > 0:
					_empower_sent_monsters(count)

			"보라":  # 처치 시 확률로 체력 +1
				var chance := color_bonus_value("보라")
				if randf() < chance:
					lives += 1
					lives_changed.emit(lives)
					Effects.float_text(_renderer, monster.cell_pos, "+1 생명!", killer_tower.color_info.color, lane_visible)
					Log.info(Log.Category.GAME, "[P%d] 보라 보너스: 체력 +1 (현재 %d)" % [player_id + 1, lives])

	gold += actual_reward
	var text := "+%d" % actual_reward if actual_reward == base_reward else "+%d (보너스!)" % actual_reward
	Effects.float_text(_renderer, monster.cell_pos, text, Color(1.0, 0.9, 0.3), lane_visible)
	Effects.ring(_renderer, monster.cell_pos, 0.6, monster.body_color, lane_visible)
	monster.queue_free()
	Log.debug(Log.Category.ECONOMY, "[P%d] 몬스터#%d 처치 +%d골드 잔액=%d" % [
		player_id + 1, monster.monster_id, actual_reward, gold])


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
		if m.flying:
			continue  # 공중 몬스터는 땅의 건설을 막지 않는다
		if absf(m.cell_pos.x - center.x) < 0.85 and absf(m.cell_pos.y - center.y) < 0.85:
			return true
	return false


## 현재 화면에 보이는 레인인지에 따라 몬스터/타워 표시/숨김
func set_lane_visible(is_shown: bool) -> void:
	lane_visible = is_shown
	for m in monsters:
		m.visible = is_shown
	for t in towers:
		t.visible = is_shown


# --- 색깔 시스템 ---

## 색깔의 현재 레벨 (0~5). 0=업그레이드 안 함.
func color_level(color_name: String) -> int:
	return int(color_levels.get(color_name, 0))


## 색깔 업그레이드 비용 (현재 레벨에서 다음 레벨로). 최대 레벨이면 -1.
func color_upgrade_cost(color_name: String) -> int:
	var cur := color_level(color_name)
	if cur >= Balance.COLOR_MAX_LEVEL:
		return -1
	return Balance.COLOR_UPGRADE_COSTS[cur]  # 현재 레벨 cur -> cur+1 비용


## 색깔을 업그레이드한다 (골드). 성공하면 true.
func upgrade_color(color_name: String) -> bool:
	var cost := color_upgrade_cost(color_name)
	if cost < 0:
		return false
	var cur := color_level(color_name)
	var next := cur + 1
	if not try_spend(cost, "색깔 업그레이드: %s %d->%d레벨" % [color_name, cur, next]):
		return false
	color_levels[color_name] = next
	Log.info(Log.Category.TOWER, "[P%d] 색깔 업그레이드: %s %d레벨 (비용=%d골드)" % [player_id + 1, color_name, next, cost])
	return true


## 색깔 보너스 타입 가져오기
func color_bonus_type(color_name: String) -> String:
	return Balance.COLOR_BONUS_TYPES.get(color_name, "")


## 색깔 보너스 값 가져오기 (현재 레벨 기준)
func color_bonus_value(color_name: String) -> float:
	var level := color_level(color_name)
	if level == 0:
		return 0.0
	var bonus_type := color_bonus_type(color_name)
	if bonus_type == "empower":
		# 강화는 마리수를 반환
		return float(Balance.COLOR_LEVEL_BONUS["empower_count"][level - 1])
	else:
		# 나머지는 비율 반환
		var key := bonus_type
		if not Balance.COLOR_LEVEL_BONUS.has(key):
			return 0.0
		return Balance.COLOR_LEVEL_BONUS[key][level - 1]


## 보스 레인에 보낸 몬스터 중 랜덤 N마리 강화 (남색 색깔 보너스)
func _empower_sent_monsters(count: int) -> void:
	if _boss_controller == null:
		return
	# 보스 앞에 도착한 몬스터들 중 이 플레이어가 보낸 것만 필터링
	var my_monsters: Array[Monster] = []
	for m in _boss_controller._sent_monsters:
		if is_instance_valid(m) and m.owner_id == player_id:
			my_monsters.append(m)

	if my_monsters.is_empty():
		return

	# 랜덤으로 N마리 선택하여 강화
	my_monsters.shuffle()
	var actual_count := mini(count, my_monsters.size())
	for i in range(actual_count):
		my_monsters[i].add_empower(Balance.EMPOWER_DURATION, Balance.EMPOWER_BOOST)
		Effects.float_text(_renderer, my_monsters[i].cell_pos, "강화!", Color(0.5, 0.5, 1.0), _boss_controller._lane_visible)
	Log.debug(Log.Category.GAME, "[P%d] 남색 보너스: 몬스터 %d마리 강화" % [player_id + 1, actual_count])
