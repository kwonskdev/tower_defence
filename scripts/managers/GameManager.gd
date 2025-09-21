extends Node
class_name GameManager

enum GameState {
	MENU,
	PLAYING,
	PAUSED,
	GAME_OVER,
	VICTORY
}

enum GameMode {
	COOP,
	PVP
}

var current_state: GameState = GameState.MENU
var game_mode: GameMode = GameMode.COOP
var player_count: int = 1
var current_player_id: int = 0

var economy_manager: EconomyManager
var lane_manager: LaneManager
var pathfinding_system: PathfindingSystem
var color_bonus_system: ColorBonusSystem

var monsters_spawned: int = 0
var monsters_killed: int = 0
var towers_built: int = 0
var game_start_time: float
var game_duration: float = 0.0

var monster_spawn_timer: Timer
var performance_monitor_timer: Timer

signal game_state_changed(new_state: GameState)
signal game_over(victory: bool)
signal monster_spawned(monster: MonsterBase)
signal tower_built(position: Vector2i, tower_type: String)
signal performance_update(fps: int, memory: int)

func _ready():
	_initialize_managers()
	_setup_timers()
	_setup_connections()

	Logger.game_state_log("GameManager initialized")

func _initialize_managers():
	economy_manager = EconomyManager.new()
	add_child(economy_manager)

	lane_manager = LaneManager.new()
	add_child(lane_manager)

func _setup_timers():
	monster_spawn_timer = Timer.new()
	monster_spawn_timer.wait_time = 5.0
	monster_spawn_timer.timeout.connect(_spawn_test_monster)
	add_child(monster_spawn_timer)

	performance_monitor_timer = Timer.new()
	performance_monitor_timer.wait_time = 1.0
	performance_monitor_timer.timeout.connect(_update_performance_stats)
	performance_monitor_timer.autostart = true
	add_child(performance_monitor_timer)

func _setup_connections():
	if economy_manager:
		economy_manager.gold_changed.connect(_on_gold_changed)
		economy_manager.lives_changed.connect(_on_lives_changed)

	if lane_manager:
		lane_manager.lane_added.connect(_on_lane_added)
		lane_manager.active_lane_changed.connect(_on_active_lane_changed)

func start_game(mode: GameMode, players: int):
	game_mode = mode
	player_count = players
	current_state = GameState.PLAYING
	game_start_time = Time.get_ticks_msec() / 1000.0

	_reset_game_stats()

	var mode_string = "COOP" if mode == GameMode.COOP else "PVP"
	lane_manager.initialize_lanes(players, mode_string.to_lower())

	if economy_manager:
		economy_manager.reset_economy()

	monster_spawn_timer.start()

	game_state_changed.emit(current_state)
	Logger.game_state_log("Game started: %s mode with %d players" % [mode_string, players])

func pause_game():
	if current_state == GameState.PLAYING:
		current_state = GameState.PAUSED
		get_tree().paused = true
		game_state_changed.emit(current_state)
		Logger.game_state_log("Game paused")

func resume_game():
	if current_state == GameState.PAUSED:
		current_state = GameState.PLAYING
		get_tree().paused = false
		game_state_changed.emit(current_state)
		Logger.game_state_log("Game resumed")

func end_game(victory: bool):
	current_state = GameState.VICTORY if victory else GameState.GAME_OVER
	game_duration = _calculate_game_duration()

	monster_spawn_timer.stop()
	_log_game_statistics()

	game_state_changed.emit(current_state)
	game_over.emit(victory)

	var result = "Victory" if victory else "Defeat"
	Logger.game_state_log("Game ended: %s (duration: %.1f seconds)" % [result, game_duration])

func _reset_game_stats():
	monsters_spawned = 0
	monsters_killed = 0
	towers_built = 0
	game_duration = 0.0

func _calculate_game_duration() -> float:
	var current_time = Time.get_ticks_msec() / 1000.0
	return current_time - game_start_time

func _spawn_test_monster():
	if current_state != GameState.PLAYING:
		return

	var current_lane = lane_manager.get_current_player_lane()
	if current_lane.is_empty():
		return

	var grid_system = current_lane.get("grid_system", null) as GridSystem
	if grid_system == null:
		return

	var monster_types = ["basic_grunt", "fast_scout", "berserker", "drone"]
	var monster_type = monster_types[randi() % monster_types.size()]

	var monster = MonsterFactory.create_monster(monster_type)
	if monster:
		var spawn_pos = grid_system.get_spawn_position()
		var goal_pos = grid_system.get_goal_position()

		monster.initialize(grid_system, spawn_pos, goal_pos)
		monster.monster_died.connect(_on_monster_died)
		monster.goal_reached.connect(_on_monster_reached_goal)

		add_child(monster)

		monsters_spawned += 1
		monster_spawned.emit(monster)

		Logger.game_state_log("Monster spawned: %s (%d total)" % [monster_type, monsters_spawned])

func place_tower(position: Vector2i, tower_type: String) -> bool:
	if current_state != GameState.PLAYING:
		Logger.warning("Cannot place tower: game not in playing state", "GAME_MANAGER")
		return false

	if not economy_manager.can_afford(TowerFactory.get_tower_cost(tower_type)):
		Logger.economy_log("Cannot afford tower: %s" % tower_type, Logger.LogLevel.WARNING)
		return false

	var current_lane = lane_manager.get_current_player_lane()
	if current_lane.is_empty():
		return false

	var grid_system = current_lane.get("grid_system", null) as GridSystem
	if grid_system == null or not grid_system.can_place_tower(position):
		return false

	if economy_manager.purchase_tower(tower_type):
		towers_built += 1
		tower_built.emit(position, tower_type)
		Logger.game_state_log("Tower placed: %s at %v (%d total)" % [tower_type, position, towers_built])
		return true

	return false

func _on_monster_died(monster: MonsterBase):
	monsters_killed += 1
	economy_manager.monster_killed_reward(monster.get_monster_type())
	Logger.game_state_log("Monster killed: %s (%d total)" % [monster.monster_name, monsters_killed])

func _on_monster_reached_goal(monster: MonsterBase):
	economy_manager.lose_lives(1)
	Logger.game_state_log("Monster reached goal: %s" % monster.monster_name)

	if economy_manager.get_lives() <= 0:
		end_game(false)

func _on_gold_changed(new_amount: int):
	Logger.economy_log("Gold updated: %d" % new_amount, Logger.LogLevel.DEBUG)

func _on_lives_changed(new_amount: int):
	Logger.game_state_log("Lives updated: %d" % new_amount)

	if new_amount <= 0:
		end_game(false)

func _on_lane_added(lane_index: int):
	Logger.game_state_log("Lane added: %d" % lane_index)

func _on_active_lane_changed(lane_index: int):
	Logger.game_state_log("Active lane changed: %d" % lane_index)

func _update_performance_stats():
	var fps = Engine.get_frames_per_second()
	var memory = OS.get_static_memory_usage()

	performance_update.emit(fps, memory)
	Logger.performance_log("Performance: FPS=%d, Memory=%d bytes" % [fps, memory])

	if fps < 30:
		Logger.warning("Low FPS detected: %d" % fps, "PERFORMANCE")

func _log_game_statistics():
	Logger.info("=== GAME STATISTICS ===")
	Logger.info("Game Mode: %s" % ("COOP" if game_mode == GameMode.COOP else "PVP"))
	Logger.info("Players: %d" % player_count)
	Logger.info("Duration: %.1f seconds" % game_duration)
	Logger.info("Monsters Spawned: %d" % monsters_spawned)
	Logger.info("Monsters Killed: %d" % monsters_killed)
	Logger.info("Towers Built: %d" % towers_built)
	Logger.info("Final Gold: %d" % economy_manager.get_gold())
	Logger.info("Final Lives: %d" % economy_manager.get_lives())
	Logger.info("Final Income: %.1f/sec" % economy_manager.get_income_per_second())
	Logger.info("======================")

func get_game_state() -> GameState:
	return current_state

func get_game_mode() -> GameMode:
	return game_mode

func get_player_count() -> int:
	return player_count

func get_game_statistics() -> Dictionary:
	return {
		"monsters_spawned": monsters_spawned,
		"monsters_killed": monsters_killed,
		"towers_built": towers_built,
		"game_duration": _calculate_game_duration(),
		"final_gold": economy_manager.get_gold() if economy_manager else 0,
		"final_lives": economy_manager.get_lives() if economy_manager else 0
	}

func get_economy_manager() -> EconomyManager:
	return economy_manager

func get_lane_manager() -> LaneManager:
	return lane_manager

func set_pathfinding_system(system: PathfindingSystem):
	pathfinding_system = system

func set_color_bonus_system(system: ColorBonusSystem):
	color_bonus_system = system