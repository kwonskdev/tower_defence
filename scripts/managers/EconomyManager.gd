extends Node
class_name EconomyManager

var current_gold: int = 100
var current_lives: int = 10
var income_per_second: float = 2.0
var base_income: float = 2.0

var income_timer: Timer
var income_interval: float = 30.0

signal gold_changed(new_amount: int)
signal lives_changed(new_amount: int)
signal income_changed(new_income: float)
signal income_received(amount: int)
signal purchase_attempted(item_type: String, cost: int, success: bool)

func _ready():
	_setup_income_timer()
	Logger.economy_log("EconomyManager initialized with %d gold, %d lives, %.1f income/sec" % [current_gold, current_lives, income_per_second])

func _setup_income_timer():
	income_timer = Timer.new()
	income_timer.wait_time = income_interval
	income_timer.timeout.connect(_on_income_timer_timeout)
	income_timer.autostart = true
	add_child(income_timer)

func _on_income_timer_timeout():
	var income_amount = int(income_per_second * income_interval)
	add_gold(income_amount)
	income_received.emit(income_amount)
	Logger.economy_log("Periodic income received: %d gold (%.1f/sec)" % [income_amount, income_per_second])

func get_gold() -> int:
	return current_gold

func get_lives() -> int:
	return current_lives

func get_income_per_second() -> float:
	return income_per_second

func add_gold(amount: int):
	if amount <= 0:
		return

	current_gold += amount
	gold_changed.emit(current_gold)
	Logger.economy_log("Gold added: +%d (total: %d)" % [amount, current_gold])

func spend_gold(amount: int) -> bool:
	if amount <= 0:
		Logger.warning("Cannot spend negative or zero gold: %d" % amount, "ECONOMY")
		return false

	if current_gold < amount:
		Logger.economy_log("Insufficient gold: need %d, have %d" % [amount, current_gold], Logger.LogLevel.WARNING)
		return false

	current_gold -= amount
	gold_changed.emit(current_gold)
	Logger.economy_log("Gold spent: -%d (remaining: %d)" % [amount, current_gold])
	return true

func add_lives(amount: int):
	if amount <= 0:
		return

	current_lives += amount
	lives_changed.emit(current_lives)
	Logger.economy_log("Lives added: +%d (total: %d)" % [amount, current_lives])

func lose_lives(amount: int):
	if amount <= 0:
		return

	current_lives -= amount
	current_lives = max(0, current_lives)
	lives_changed.emit(current_lives)
	Logger.game_state_log("Lives lost: -%d (remaining: %d)" % [amount, current_lives])

func increase_income(amount: float):
	if amount <= 0:
		return

	income_per_second += amount
	income_changed.emit(income_per_second)
	Logger.economy_log("Income increased: +%.1f (total: %.1f/sec)" % [amount, income_per_second])

func can_afford(cost: int) -> bool:
	return current_gold >= cost

func purchase_tower(tower_type: String) -> bool:
	var cost = TowerFactory.get_tower_cost(tower_type)
	var success = spend_gold(cost)

	purchase_attempted.emit("tower", cost, success)

	if success:
		Logger.economy_log("Tower purchased: %s for %d gold" % [tower_type, cost])
	else:
		Logger.economy_log("Tower purchase failed: %s (cost: %d, have: %d)" % [tower_type, cost, current_gold], Logger.LogLevel.WARNING)

	return success

func purchase_monster(monster_type: String) -> bool:
	var cost = MonsterFactory.get_monster_cost(monster_type)
	var success = spend_gold(cost)

	if success:
		var monster_def = MonsterFactory.get_monster_definition(monster_type)
		var income_increase = monster_def.get("stats", {}).get("income_increase", 0)
		increase_income(income_increase)

		Logger.economy_log("Monster purchased: %s for %d gold (+%.1f income)" % [monster_type, cost, income_increase])
	else:
		Logger.economy_log("Monster purchase failed: %s (cost: %d, have: %d)" % [monster_type, cost, current_gold], Logger.LogLevel.WARNING)

	purchase_attempted.emit("monster", cost, success)
	return success

func purchase_upgrade(upgrade_type: String, cost: int) -> bool:
	var success = spend_gold(cost)

	purchase_attempted.emit("upgrade", cost, success)

	if success:
		Logger.economy_log("Upgrade purchased: %s for %d gold" % [upgrade_type, cost])
	else:
		Logger.economy_log("Upgrade purchase failed: %s (cost: %d, have: %d)" % [upgrade_type, cost, current_gold], Logger.LogLevel.WARNING)

	return success

func purchase_extra_life() -> bool:
	var life_cost = _calculate_life_cost()
	var success = spend_gold(life_cost)

	if success:
		add_lives(1)
		Logger.economy_log("Extra life purchased for %d gold" % life_cost)
	else:
		Logger.economy_log("Extra life purchase failed (cost: %d, have: %d)" % [life_cost, current_gold], Logger.LogLevel.WARNING)

	purchase_attempted.emit("life", life_cost, success)
	return success

func _calculate_life_cost() -> int:
	var base_life_cost = 50
	var lives_bought = 10 - current_lives
	return base_life_cost + (lives_bought * 25)

func sell_tower(tower_type: String, upgrade_level: int) -> int:
	var base_cost = TowerFactory.get_tower_cost(tower_type)
	var upgrade_cost = base_cost * upgrade_level * 0.5
	var sell_value = int((base_cost + upgrade_cost) * 0.5)

	add_gold(sell_value)
	Logger.economy_log("Tower sold: %s for %d gold (level %d)" % [tower_type, sell_value, upgrade_level])

	return sell_value

func monster_killed_reward(monster_type: String):
	var monster_def = MonsterFactory.get_monster_definition(monster_type)
	var reward = monster_def.get("stats", {}).get("reward", 0)

	if reward > 0:
		add_gold(reward)
		Logger.economy_log("Monster kill reward: %d gold for %s" % [reward, monster_type])

func get_economy_state() -> Dictionary:
	return {
		"gold": current_gold,
		"lives": current_lives,
		"income_per_second": income_per_second,
		"base_income": base_income
	}

func set_economy_state(state: Dictionary):
	current_gold = state.get("gold", current_gold)
	current_lives = state.get("lives", current_lives)
	income_per_second = state.get("income_per_second", income_per_second)
	base_income = state.get("base_income", base_income)

	gold_changed.emit(current_gold)
	lives_changed.emit(current_lives)
	income_changed.emit(income_per_second)

	Logger.economy_log("Economy state loaded: %d gold, %d lives, %.1f income/sec" % [current_gold, current_lives, income_per_second])

func reset_economy():
	current_gold = 100
	current_lives = 10
	income_per_second = base_income

	gold_changed.emit(current_gold)
	lives_changed.emit(current_lives)
	income_changed.emit(income_per_second)

	Logger.economy_log("Economy reset to initial state")