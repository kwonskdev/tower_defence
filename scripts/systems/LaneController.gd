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
var gold: float = float(Balance.START_GOLD)  # 소수점까지 들고 있다 (판매 환급 70% 등). 화면/구매 가능 판정은 gold_shown() (내림)
var income: int = Balance.BASE_INCOME   # 수입 틱마다 받는 골드
var lives: float = float(Balance.START_LIVES)  # 소수점까지 들고 있다. 화면/패배 판정은 lives_shown() (내림)
var active := true
var started := false  # 시작 버튼을 눌렀는가 (누르기 전에는 타워를 전액 환급으로 팔 수 있다)
var lane_visible := true
var events := SimEvents.new()  # 연출 이벤트 통로 (GameField가 세션 것으로 바꿔 끼운다)
var rng := RandomNumberGenerator.new()  # 이 레인의 시뮬레이션 랜덤 (GameField가 세션 것으로 바꿔 끼운다. 서버만 뽑는다)
var monsters: Array[Monster] = []  # 필드 위 몬스터 (유령 구간의 유령도 들어 있다: 타워가 똑같이 조준한다)
var towers: Array[Tower] = []  # 한 칸에 타워 1개
var ghost_active := false      # 지금 유령 구간인가 (보스를 일찍 잡은 뒤 남은 시간). 켜져 있는 동안 유령 1마리가 끝까지 가면 다시 나온다
var ghost_damage := 0.0        # 이 레인의 타워들이 유령에게 준 피해 누적 (게임 전체, 구간마다 쌓인다. 부서진 타워가 준 몫도 남는다)

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
var _cluster_sizes: Dictionary = {}   # 칸 -> 그 칸 타워가 속한 같은 색 덩어리의 크기 (타워가 바뀌면 다시 계산)
var _cluster_dirty := true
var _rewarded_patterns: Dictionary = {}  # 이미 보상을 준 패턴 종류 (ColorPatterns.PATTERNS 키)


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

	Log.info(Log.Category.GAME, "[P%d] 레인 시작: 골드=%.2f, 수입=%d/%.0fs, 생명=%d" % [
		player_id + 1, gold, income, Balance.INCOME_INTERVAL, lives])


## 시작 버튼: 수입 지급이 시작된다
func begin() -> void:
	started = true
	if active and _income_timer.is_stopped():
		_income_timer.start()


# --- 타워 ---

## 타워 건설 한 번: 검증과 골드 차감과 건설을 한 번에 한다. 성공하면 "", 실패하면 사유 (아무것도 바뀌지 않는다).
## confirmed: 길이 완전히 막히는 걸 알고도 짓겠다고 이미 확인받았는가
func try_build_tower(cell: Vector2i, kind_id: String, confirmed: bool) -> String:
	if not Balance.TOWER_DEFS.has(kind_id):
		return "unknown_kind"
	if not _grid.is_valid_position(cell):
		return "invalid_cell"
	var kind := Balance.tower_kind(kind_id)
	# 한 칸에는 타워 1개만 (트랩도 겹쳐 지을 수 없다)
	var cell_state := _grid.get_cell_state(cell)
	if cell_state != GridSystem.CellState.EMPTY:
		Log.debug(Log.Category.TOWER, "[P%d] 타워 건설 실패 %s: 빈 칸 아님(%s)" % [player_id + 1, cell, _grid.get_state_name(cell_state)])
		return "cell_not_empty"
	# 길을 막는 타워는 몬스터와 몸이 겹친 칸에 지을 수 없다 (트랩은 위로 지나가므로 가능)
	if kind.blocks and is_cell_occupied(cell):
		Log.debug(Log.Category.TOWER, "[P%d] 타워 건설 실패 %s: 몬스터가 있는 칸" % [player_id + 1, cell])
		return "monster_on_cell"
	# 이 타워 때문에 길이 완전히 막히면 한 번 확인한다 (막히면 몬스터가 타워를 부수며 돌파한다)
	if kind.blocks and not confirmed and would_block_path(cell):
		return "path_blocked"
	# 차감과 건설은 사이에 실패할 곳 없이 이어서 한다 (골드만 빠지고 건설이 안 되는 일이 없다)
	if not try_spend(kind.cost, "타워 건설 %s(%s)" % [cell, kind.name]):
		return spend_failure(kind.cost)
	build_tower(cell, kind_id)
	Log.info(Log.Category.TOWER, "[P%d] 타워 건설 %s: %s" % [player_id + 1, cell, kind.name])
	return ""


## 타워를 짓는다 (골드는 건드리지 않는다). 검증과 차감은 try_build_tower가 한다.
func build_tower(cell: Vector2i, kind_id: String) -> Tower:
	var kind := Balance.tower_kind(kind_id)
	var color_info: Dictionary = SimRandom.pick(rng, Balance.TOWER_COLORS)  # 모든 색 동일 확률
	var state := GridSystem.CellState.TOWER if kind.blocks else GridSystem.CellState.TRAP_TOWER
	_grid.set_cell_state(cell, state)

	var tower := Tower.new()
	tower.setup(cell, kind, color_info, self, _renderer)
	tower.visible = lane_visible
	tower.z_index = 1
	tower.invested = int(kind.cost)  # 건설 골드는 호출한 쪽(GameField.place_tower)이 이미 냈다
	_renderer.add_child(tower)
	towers.append(tower)

	Log.info(Log.Category.COLOR, "[P%d] 타워 %s 색깔 할당: %s" % [player_id + 1, cell, color_info.name])
	_on_tower_colors_changed()
	return tower


## 이 칸에 있는 타워 (없으면 null). 명령은 타워 객체 대신 칸 좌표로 타워를 가리킨다.
func tower_at(cell: Vector2i) -> Tower:
	for t in towers:
		if t.cell == cell:
			return t
	return null


## 타워 색깔을 다시 뽑는다 (골드). 지금 색을 뺀 나머지 6색 중 랜덤이라 돈을 내면 반드시 색이 바뀐다.
## 성공하면 "", 실패하면 사유 (아무것도 바뀌지 않는다).
func recolor_tower(tower: Tower) -> String:
	if tower == null or tower.lane != self:
		return "no_tower"
	if not try_spend(Balance.RECOLOR_COST, "타워 색깔 바꾸기 %s" % tower.cell):
		return spend_failure(Balance.RECOLOR_COST)
	var candidates: Array = Balance.TOWER_COLORS.filter(func(c): return c.name != tower.color_info.name)
	var old_name: String = tower.color_info.name
	var new_info: Dictionary = SimRandom.pick(rng, candidates)
	tower.set_color_info(new_info)
	Log.info(Log.Category.COLOR, "[P%d] 타워 %s 색깔 변경: %s -> %s" % [player_id + 1, tower.cell, old_name, new_info.name])
	_on_tower_colors_changed()
	return ""


## 타워 내구도를 가득 채운다 (골드). 이미 가득이면 돈을 쓰지 않는다. 성공하면 "", 실패하면 사유.
func heal_tower(tower: Tower) -> String:
	if tower == null or tower.lane != self:
		return "no_tower"
	if tower.durability >= Balance.TOWER_DURABILITY - 0.001:
		return "already_full"
	if not try_spend(Balance.HEAL_COST, "타워 회복 %s" % tower.cell):
		return spend_failure(Balance.HEAL_COST)
	tower.durability = Balance.TOWER_DURABILITY
	Log.info(Log.Category.TOWER, "[P%d] 타워 회복 %s" % [player_id + 1, tower.cell])
	return ""


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


## 타워 1기를 진화시킨다 (골드). 같은 기본 타워가 가진 계열 2개 중 하나를 고르며, 한 번 고르면 바꿀 수 없다. 성공하면 "", 실패하면 사유.
func evolve_tower(tower: Tower, evo: String) -> String:
	if tower == null or tower.lane != self:
		return "no_tower"
	if not tower.can_evolve():
		return "cannot_evolve"
	if evo not in Evolutions.TREE[tower.kind.id]:
		return "invalid_evolution"
	if not try_spend(Balance.EVOLVE_COST, "타워 진화 %s(%s) -> %s" % [tower.cell, tower.kind.name, Evolutions.evo_name(evo)]):
		return spend_failure(Balance.EVOLVE_COST)
	tower.set_evolution(evo)
	tower.invested += Balance.EVOLVE_COST
	tower.durability = Balance.TOWER_DURABILITY  # 진화하면 항상 풀피
	Log.info(Log.Category.TOWER, "[P%d] 타워 진화 %s: %s -> %s" % [player_id + 1, tower.cell, tower.kind.name, Evolutions.evo_name(evo)])
	return ""


## 타워 1기가 B 스킬을 배우는 비용. 진화 전이거나 이미 배웠으면 -1.
func learn_cost(tower: Tower) -> int:
	if tower == null or tower.evolution == "" or tower.b_learned:
		return -1
	return Balance.SKILL_LEARN_COST


## 타워 1기의 B 스킬을 배운다 (진화처럼 타워마다 따로, 골드). 성공하면 "", 실패하면 사유.
func learn_tower_skill(tower: Tower) -> String:
	if tower == null or tower.lane != self:
		return "no_tower"
	var cost := learn_cost(tower)
	if cost < 0:
		return "cannot_learn"
	var evo := tower.evolution
	if not try_spend(cost, "타워 %s(%s) B 진화: %s" % [tower.cell, Evolutions.evo_name(evo), Evolutions.skill_name(evo, "B")]):
		return spend_failure(cost)
	tower.b_learned = true
	tower.invested += cost
	tower.durability = Balance.TOWER_DURABILITY  # B 스킬을 배워도 풀피
	Log.info(Log.Category.TOWER, "[P%d] B 진화 %s: %s %s" % [player_id + 1, tower.cell, Evolutions.evo_name(evo), Evolutions.skill_name(evo, "B")])
	return ""


## 항목 레벨을 한 단계 올리는 비용. 올릴 수 없으면 -1 (최대 레벨). 계열의 모든 타워에 적용되고, B 항목은 B를 배운 타워에만 효과가 있다.
func stat_upgrade_cost(evo: String, skill: String, key: String) -> int:
	var lv := stat_level(evo, skill, key)
	if lv >= Evolutions.MAX_LEVEL:
		return -1
	return int(Balance.STAT_UPGRADE_COSTS[lv - 1])


## 업그레이드 탭: 항목 하나를 올린다. 그 계열로 진화한 모든 타워가 바로 강해진다. 성공하면 "", 실패하면 사유.
func upgrade_stat(evo: String, skill: String, key: String) -> String:
	if not Evolutions.PARAMS.has(evo) or not Evolutions.PARAMS[evo].has(skill) or not Evolutions.PARAMS[evo][skill].has(key):
		return "invalid_stat"
	var cost := stat_upgrade_cost(evo, skill, key)
	if cost < 0:
		return "max_level"
	var next := stat_level(evo, skill, key) + 1
	if not try_spend(cost, "%s %s Lv%d" % [Evolutions.evo_name(evo), key, next]):
		return spend_failure(cost)
	stat_levels["%s.%s.%s" % [evo, skill, key]] = next
	Log.info(Log.Category.TOWER, "[P%d] 업그레이드: %s %s.%s -> Lv%d" % [player_id + 1, Evolutions.evo_name(evo), skill, key, next])
	return ""


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


## 골드를 화면에 보이는 정수로 (소수점은 내림. 2.8이면 2). 부동소수 오차로 3.0이 2.9999999가 되어 2로 보이지 않도록 아주 작은 값을 더한다.
static func whole(amount: float) -> int:
	return floori(amount + 0.000001)


## 화면에 보이고 구매 가능 판정에 쓰는 골드 (소수점은 내림)
func gold_shown() -> int:
	return whole(gold)


## 이 타워를 지금 팔면 받는 골드. 반올림하지 않고 소수까지 그대로 더한다 (2.8골드면 gold에 2.8이 들어간다).
func sell_value(tower: Tower) -> float:
	var ratio := Balance.SELL_REFUND_RATIO if started else Balance.SELL_REFUND_RATIO_BEFORE_START
	return tower.invested * ratio


## 판매 버튼/확인창에 보이는 환급액 (소수점은 내림)
func sell_value_shown(tower: Tower) -> int:
	return whole(sell_value(tower))


## 팔 때 한 번 더 확인해야 하는가 (진화/B 스킬에 골드를 쓴 타워. 건설만 한 타워는 바로 판다)
func sell_needs_confirm(tower: Tower) -> bool:
	return tower.evolution != ""


## 타워를 판다: 투입 골드의 일부를 돌려받고 타워를 치운 뒤 칸을 비운다. 내 레인의 타워만 가능.
## 몬스터가 부술 때와 달리 "파괴!" 연출이 뜨지 않는다.
func sell_tower(tower: Tower) -> bool:
	if not active or not is_instance_valid(tower) or tower.lane != self or not towers.has(tower):
		return false
	var refund := sell_value(tower)
	gold += refund
	Log.info(Log.Category.ECONOMY, "[P%d] 타워 판매 %s(%s%s): +%.2f골드 (투입 %d) 잔액=%.2f" % [
		player_id + 1, tower.cell, tower.kind.name,
		" · " + Evolutions.evo_name(tower.evolution) if tower.evolution != "" else "", refund, tower.invested, gold])
	_remove_tower(tower, false)
	return true


## 타워를 치운다. destroyed=true(몬스터가 부숨)이면 "파괴!" 연출을 띄우고, false(판매)이면 조용히 치운다.
func _remove_tower(tower: Tower, destroyed: bool) -> void:
	towers.erase(tower)  # 칸을 비우기 전에 뺀다: 칸이 바뀌는 신호(_on_cell_changed)가 같은 타워를 또 치우지 않게
	if destroyed:
		events.ring(player_id, tower.center_cell_pos(), 0.8, Color(1.0, 0.5, 0.2))
		events.text(player_id, tower.center_cell_pos(), "파괴!", Color(1.0, 0.4, 0.3))
	tower.queue_free()
	_grid.set_cell_state(tower.cell, GridSystem.CellState.EMPTY)  # 부서져서 온 경우는 이미 EMPTY라 아무 일도 없다. 판매면 몬스터가 신호를 받아 길을 다시 짠다
	_on_tower_colors_changed()


func _on_cell_changed(position: Vector2i, _old_state, new_state) -> void:
	# 몬스터가 타워를 부수면 칸이 EMPTY가 된다 (부술 수 있는 건 길을 막는 타워뿐)
	if new_state != GridSystem.CellState.EMPTY:
		return
	for tower in towers:
		if tower.cell == position:
			_remove_tower(tower, true)
			break


# --- 경제 ---

## 다음 수입 지급까지 남은 시간(초)
func income_time_left() -> float:
	return _income_timer.time_left


## amount 골드를 지금 쓸 수 있으면 "", 못 쓰면 사유 ("lane_inactive" / "not_enough_gold")
func spend_failure(amount: int) -> String:
	if not active:
		return "lane_inactive"
	if gold < amount:
		return "not_enough_gold"
	return ""


func try_spend(amount: int, reason: String) -> bool:
	if not active:
		return false
	if gold_shown() < amount:  # 화면에 보이는 정수 골드로 판정 (보이는 돈으로 살 수 있으면 산다)
		Log.info(Log.Category.ECONOMY, "[P%d] 골드 부족: %s 필요=%d 보유=%d" % [player_id + 1, reason, amount, gold_shown()])
		return false
	gold -= amount
	Log.info(Log.Category.ECONOMY, "[P%d] -%d골드 (%s) 잔액=%.2f" % [player_id + 1, amount, reason, gold])
	return true


func add_income(amount: int) -> void:
	income += amount
	Log.info(Log.Category.ECONOMY, "[P%d] 수입 +%d -> %d/%.0fs" % [player_id + 1, amount, income, Balance.INCOME_INTERVAL])


func _on_income_tick() -> void:
	if not active:
		return
	gold += income
	Log.info(Log.Category.ECONOMY, "[P%d] 수입 지급 +%d 잔액=%.2f" % [player_id + 1, income, gold])


# --- 몬스터 ---

## 이 칸에 길을 막는 타워를 지으면 몬스터가 지나갈 길이 완전히 막히는가
func would_block_path(cell: Vector2i) -> bool:
	return _pathfinder.would_block(cell, _grid.get_spawn_cells())


## 몬스터가 나오는 칸 하나 (없으면 NO_GOAL). 한 웨이브는 같은 칸에서 뭉쳐서 나온다.
func pick_spawn_cell() -> Vector2i:
	var cells := _grid.get_spawn_cells()
	return SimRandom.pick(rng, cells) if not cells.is_empty() else Pathfinder.NO_GOAL


## 보스의 자동 파견: 이 레인에 몬스터를 보낸다 (level: 보스 라운드. 보상/방어력이 라운드에 따라 오른다)
## affix: 웨이브 변형 (BossSkills.AFFIXES 키, 없으면 "")
func spawn_wave_monster(type_id: String = "grunt", level: int = 1, spawn_cell: Vector2i = Pathfinder.NO_GOAL, affix: String = "") -> void:
	if not active:
		return
	if spawn_cell == Pathfinder.NO_GOAL:
		spawn_cell = pick_spawn_cell()
	if spawn_cell == Pathfinder.NO_GOAL:
		Log.error(Log.Category.GAME, "[P%d] 스폰 셀이 없음" % (player_id + 1))
		return

	# 체력/공격력은 몬스터마다 고정 (Monsters.gd). 공격형(또는 gnaws)은 시야 안의 벽 타워를 dps만큼 갉는다.
	var wave_type: Dictionary = Monsters.DATA[type_id]
	var monster := Monster.new()
	monster.events = events
	monster.fx_lane_id = player_id
	monster.apply_look(wave_type)
	monster.kind_id = type_id
	monster.max_hp = Monsters.max_hp(type_id)
	monster.life_damage = int(wave_type.get("life", 1))
	monster.armor = float(wave_type.get("armor", 0.0))
	monster.regen = float(wave_type.get("regen", 0.0))
	monster.flying = bool(wave_type.get("flying", false))
	monster.reward = roundi(Monsters.reward(type_id) * (1.0 + 0.15 * (level - 1)))
	monster.dps = Monsters.dps(type_id)
	monster.gnaws_towers = monster.dps > 0.0 and (bool(wave_type.get("gnaws", false)) or wave_type.category == "attack")  # 공격력 0(응원단 등)은 갉을 게 없다
	monster.gnaw_rate = monster.dps
	monster.ghost = bool(wave_type.get("ghost", false))
	monster.breach_dps = float(wave_type.get("breach_dps", 0.0))
	monster.gnawed.connect(_on_tower_gnawed)
	monster.ghost_hit.connect(_on_ghost_hit)
	if affix != "":
		var affix_data: Dictionary = BossSkills.AFFIXES[affix]
		monster.speed_boost = float(affix_data.get("speed_mult", 1.0))
		monster.revive_ratio = float(affix_data.get("revive", 0.0))
	monster.visible = lane_visible
	monster.z_index = 2
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cell)
	monster.reached_exit.connect(_on_monster_reached_exit)
	monster.died.connect(_on_monster_died)
	_renderer.add_child(monster)
	monsters.append(monster)
	Log.debug(Log.Category.GAME, "[P%d] 몬스터#%d(%s) 스폰 hp=%.1f 방어=%.2f (필드 위 %d마리)" % [
		player_id + 1, _next_monster_id, wave_type.name, monster.max_hp, monster.armor, monsters.size()])
	_next_monster_id += 1


## 슬라임 새끼가 갉거나 길이 막혀서 유령이 뚫는 중이다: 내구도를 깎고, 바닥나면 타워를 부순다 (칸을 비우면 _on_cell_changed가 타워를 치운다)
func _on_tower_gnawed(cell: Vector2i, amount: float) -> void:
	for tower in towers:
		if tower.cell == cell:
			if tower.gnaw(amount):
				Log.info(Log.Category.TOWER, "[P%d] 타워 %s 내구도 바닥나 부서짐" % [player_id + 1, cell])
				_grid.set_cell_state(cell, GridSystem.CellState.EMPTY)
			return


# --- 유령 구간 (보스를 일찍 잡고 남은 시간) ---

## 유령 구간을 시작한다: 이 레인에 유령 1마리가 나온다. BossController가 부른다.
func start_ghost() -> void:
	if not active:
		return  # 이미 무너진 레인에는 나오지 않는다
	ghost_active = true
	spawn_ghost()


## 유령 구간이 끝났다: 필드의 유령을 치운다 (남은 일반 몬스터는 그대로)
func stop_ghost() -> void:
	ghost_active = false
	for m in monsters.duplicate():
		if m.ghost:
			monsters.erase(m)
			m.queue_free()


## 출발점에서 유령 1마리를 내보낸다 (참여 중인 레인만). 유령은 일반(grunt)과 같은 속도로 끝까지 가고, 닿으면 다시 이 함수로 나온다.
func spawn_ghost(level: int = 1) -> void:
	spawn_wave_monster("ghost", level)


## 유령이 타워에게 맞았다: 레인 점수에 더하고, 때린 타워의 몫도 센다 (source가 null이면 이미 부서진 타워)
func _on_ghost_hit(amount: float, source) -> void:
	ghost_damage += amount
	if source != null and is_instance_valid(source):
		source.record_ghost_damage(amount)


## 필드 위 몬스터 수 (유령 제외). 비늘 보호막처럼 "웨이브 몬스터가 얼마나 남았나"를 볼 때 쓴다.
func wave_monster_count() -> int:
	var count := 0
	for m in monsters:
		if not m.ghost:
			count += 1
	return count


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
		var mk: Dictionary = SimRandom.pick(rng, spreadable)
		m.add_mark(mk.src, float(mk.dmg))
		events.ring(player_id, m.cell_pos, 0.5, Color(0.8, 0.5, 1.0))


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
				var bonus := color_bonus_value("초록", killer_tower)
				if bonus > 0.0:
					actual_reward = roundi(base_reward * (1.0 + bonus))

			"남색":  # 처치 시 보낸 몬스터 N마리 강화
				var count := int(color_bonus_value("남색", killer_tower))
				if count > 0:
					_empower_sent_monsters(count)

			"보라":  # 처치 시 확률로 체력 +1
				# 확률은 업그레이드 값 그대로, 성공하면 생명 1 x 군집 배율 (소수로 쌓인다)
				var chance := color_bonus_value("보라")
				if lives < Balance.MAX_LIVES and rng.randf() < chance:
					var gain := cluster_multiplier(killer_tower)
					add_lives(gain)
					events.text(player_id, monster.cell_pos, "+%s 생명!" % String.num(gain, 2), killer_tower.color_info.color)
					Log.info(Log.Category.GAME, "[P%d] 보라 보너스: 체력 +%.2f (현재 %.2f)" % [player_id + 1, gain, lives])

	gold += actual_reward
	var text := "+%d" % actual_reward if actual_reward == base_reward else "+%d (보너스!)" % actual_reward
	events.text(player_id, monster.cell_pos, text, Color(1.0, 0.9, 0.3))
	events.ring(player_id, monster.cell_pos, 0.6, monster.body_color)
	monster.queue_free()
	Log.debug(Log.Category.ECONOMY, "[P%d] 몬스터#%d 처치 +%d골드 잔액=%.2f" % [
		player_id + 1, monster.monster_id, actual_reward, gold])


func _on_monster_reached_exit(monster: Monster) -> void:
	monsters.erase(monster)
	monster.queue_free()
	if monster.ghost:  # 유령은 생명을 깎지 않는다. 끝까지 갔으니 출발점에서 다시 나온다
		if ghost_active and active:
			spawn_ghost()
		return
	lives -= monster.life_damage
	Log.info(Log.Category.GAME, "[P%d] 몬스터#%d(%s) 기지 도달! 생명 -%d -> %.2f" % [
		player_id + 1, monster.monster_id, monster.kind_id, monster.life_damage, lives])
	lives_changed.emit(lives_shown())

	if lives_shown() <= 0 and active:
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


## 색깔을 업그레이드한다 (골드). 성공하면 "", 실패하면 사유.
func upgrade_color(color_name: String) -> String:
	if not Balance.COLOR_BONUS_TYPES.has(color_name):
		return "invalid_color"
	var cost := color_upgrade_cost(color_name)
	if cost < 0:
		return "max_level"
	var cur := color_level(color_name)
	var next := cur + 1
	if not try_spend(cost, "색깔 업그레이드: %s %d->%d레벨" % [color_name, cur, next]):
		return spend_failure(cost)
	color_levels[color_name] = next
	Log.info(Log.Category.TOWER, "[P%d] 색깔 업그레이드: %s %d레벨 (비용=%d골드)" % [player_id + 1, color_name, next, cost])
	return ""


## 색깔 보너스 타입 가져오기
func color_bonus_type(color_name: String) -> String:
	return Balance.COLOR_BONUS_TYPES.get(color_name, "")


## 색깔 보너스 값 가져오기 (현재 레벨 기준). tower를 주면 그 타워의 같은 색 군집 배율이 곱해진다.
func color_bonus_value(color_name: String, tower: Tower = null) -> float:
	var level := color_level(color_name)
	if level == 0:
		return 0.0
	var bonus_type := color_bonus_type(color_name)
	var base := 0.0
	if bonus_type == "empower":
		# 강화는 마리수를 반환
		base = float(Balance.COLOR_LEVEL_BONUS["empower_count"][level - 1])
	elif Balance.COLOR_LEVEL_BONUS.has(bonus_type):
		# 나머지는 비율 반환
		base = Balance.COLOR_LEVEL_BONUS[bonus_type][level - 1]
	return base * cluster_multiplier(tower)


## 생명을 올린다 (소수 가능, 상한 MAX_LIVES)
func add_lives(amount: float) -> void:
	lives = minf(lives + amount, float(Balance.MAX_LIVES))
	lives_changed.emit(lives_shown())


## 화면에 보이고 패배 판정에 쓰는 생명 (소수점은 내림. 3.6이면 3)
func lives_shown() -> int:
	return floori(lives)


# --- 색깔 군집 ---

## 이 타워의 같은 색 군집 배율 (타워를 안 주면 1.0)
func cluster_multiplier(tower: Tower) -> float:
	if tower == null:
		return 1.0
	return 1.0 + Balance.CLUSTER_BONUS_PER_TOWER * cluster_size(tower)


## 이 타워와 상하좌우로 끊기지 않고 이어진 같은 색 타워의 수 (자기 자신 포함)
func cluster_size(tower: Tower) -> int:
	if _cluster_dirty:
		_rebuild_clusters()
	return int(_cluster_sizes.get(tower.cell, 0))


func _rebuild_clusters() -> void:
	_cluster_dirty = false
	_cluster_sizes.clear()
	var color_at: Dictionary = _tower_color_map(true)  # 군집은 길을 막는 타워만 센다
	for start in color_at:
		if _cluster_sizes.has(start):
			continue
		# 넓이 우선 탐색으로 같은 색 덩어리를 모은다
		var group: Array[Vector2i] = [start]
		var seen := {start: true}
		var i := 0
		while i < group.size():
			var c: Vector2i = group[i]
			i += 1
			for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
				var n: Vector2i = c + d
				if not seen.has(n) and color_at.get(n, "") == color_at[start]:
					seen[n] = true
					group.append(n)
		for c in group:
			_cluster_sizes[c] = group.size()

	# 트랩: 군집엔 안 세지만, 옆에 같은 색 군집이 있으면 그 군집의 크기(여러 개면 가장 큰 것)를 받는다
	for t in towers:
		if t.kind.blocks:
			continue
		var best := 0
		for d in [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]:
			var n: Vector2i = t.cell + d
			if color_at.get(n, "") == t.color_info.name:
				best = maxi(best, int(_cluster_sizes[n]))
		if best > 0:
			_cluster_sizes[t.cell] = best


## 칸 -> 색 이름 (blocking_only면 길을 막는 타워만)
func _tower_color_map(blocking_only: bool = false) -> Dictionary:
	var m := {}
	for t in towers:
		if blocking_only and not t.kind.blocks:
			continue
		m[t.cell] = t.color_info.name
	return m


# --- 색깔 패턴 이스터에그 ---

## 타워가 지어지거나, 색이 바뀌거나, 부서졌다: 군집을 다시 계산하고 새로 완성된 패턴에 보상을 준다
func _on_tower_colors_changed() -> void:
	_cluster_dirty = true
	if not active:
		return
	for p in ColorPatterns.find(_tower_color_map()):
		if _rewarded_patterns.has(p.id):
			continue  # 패턴 종류마다 한 게임에 한 번만
		_rewarded_patterns[p.id] = true
		_reward_pattern(p)


func _reward_pattern(p: Dictionary) -> void:
	var data: Dictionary = ColorPatterns.PATTERNS[p.id]
	var gold_bonus := int(data.gold)
	var life_bonus := int(data.lives)
	gold += gold_bonus
	if life_bonus > 0:
		add_lives(float(life_bonus))

	# 연출: 조합에 든 타워마다 그 타워 색의 링, 가운데에 이름과 보상
	var color_at := {}
	for t in towers:
		color_at[t.cell] = t.color_info.color
	var center := Vector2.ZERO
	for c in p.cells:
		center += Vector2(c) + Vector2(0.5, 0.5)
		events.ring(player_id, Vector2(c) + Vector2(0.5, 0.5), 0.9, color_at.get(c, Color.WHITE))
	center /= float(p.cells.size())
	events.text(player_id, center, "%s! %s" % [data.name, ColorPatterns.reward_text(p.id)], Color(1.0, 0.95, 0.5))
	Log.info(Log.Category.COLOR, "[P%d] 패턴 완성: %s %s (골드=%.2f 생명=%.2f)" % [
		player_id + 1, data.name, ColorPatterns.reward_text(p.id), gold, lives])


## 보스 레인에 보낸 몬스터 중 랜덤 N마리 강화 (남색 색깔 보너스)
func _empower_sent_monsters(count: int) -> void:
	if _boss_controller == null:
		return
	# 보스 앞에서 싸우는 몬스터 중 이 플레이어가 보낸 것만 (아직 걸어오는 중인 몬스터는 강화해도 의미가 없다)
	var my_monsters: Array[Monster] = []
	for m in _boss_controller.get_attackers():
		if is_instance_valid(m) and m.owner_id == player_id:
			my_monsters.append(m)

	if my_monsters.is_empty():
		return

	# 랜덤으로 N마리 선택하여 강화
	SimRandom.shuffle(rng, my_monsters)
	var actual_count := mini(count, my_monsters.size())
	for i in range(actual_count):
		my_monsters[i].add_empower(Balance.EMPOWER_DURATION, Balance.EMPOWER_BOOST)
		events.text(GameField.BOSS_LANE_ID, my_monsters[i].cell_pos, "강화!", Color(0.5, 0.5, 1.0))
	Log.debug(Log.Category.GAME, "[P%d] 남색 보너스: 몬스터 %d마리 강화" % [player_id + 1, actual_count])
