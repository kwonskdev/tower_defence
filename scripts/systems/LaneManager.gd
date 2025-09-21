extends Node
class_name LaneManager

const MAX_LANES = 8

var lanes: Array[Dictionary] = []
var active_lane_count: int = 1
var current_player_lane: int = 0

signal lane_added(lane_index: int)
signal lane_removed(lane_index: int)
signal active_lane_changed(lane_index: int)

func _ready():
	Logger.info("LaneManager initialized", "LANE")

func initialize_lanes(player_count: int, game_mode: String):
	Logger.info("Initializing lanes for %d players in %s mode" % [player_count, game_mode], "LANE")

	lanes.clear()
	active_lane_count = player_count

	match game_mode.to_lower():
		"coop":
			_setup_coop_lanes(player_count)
		"pvp":
			_setup_pvp_lanes(player_count)
		_:
			Logger.error("Unknown game mode: %s" % game_mode, "LANE")

func _setup_coop_lanes(player_count: int):
	for i in range(player_count):
		var lane_data = {
			"index": i,
			"type": "player",
			"grid_system": GridSystem.new(),
			"active": true,
			"player_id": i
		}
		lanes.append(lane_data)
		lane_added.emit(i)

	var boss_lane_data = {
		"index": player_count,
		"type": "boss",
		"grid_system": GridSystem.new(),
		"active": true,
		"player_id": -1
	}
	lanes.append(boss_lane_data)
	lane_added.emit(player_count)

	Logger.info("Coop mode: Created %d player lanes + 1 boss lane" % player_count, "LANE")

func _setup_pvp_lanes(player_count: int):
	if player_count != 8:
		Logger.error("PvP mode requires exactly 8 players, got %d" % player_count, "LANE")
		return

	for i in range(8):
		var lane_data = {
			"index": i,
			"type": "player",
			"grid_system": GridSystem.new(),
			"active": true,
			"player_id": i,
			"target_lane": (i + 1) % 8,
			"source_lane": (i - 1 + 8) % 8
		}
		lanes.append(lane_data)
		lane_added.emit(i)

	Logger.info("PvP mode: Created 8 player lanes", "LANE")

func get_lane(lane_index: int) -> Dictionary:
	if lane_index < 0 or lane_index >= lanes.size():
		Logger.warning("Invalid lane index: %d" % lane_index, "LANE")
		return {}
	return lanes[lane_index]

func get_current_player_lane() -> Dictionary:
	return get_lane(current_player_lane)

func get_lane_grid_system(lane_index: int) -> GridSystem:
	var lane = get_lane(lane_index)
	if lane.is_empty():
		return null
	return lane.get("grid_system", null)

func set_current_player_lane(lane_index: int):
	if lane_index < 0 or lane_index >= lanes.size():
		Logger.warning("Cannot set current player lane to invalid index: %d" % lane_index, "LANE")
		return

	current_player_lane = lane_index
	active_lane_changed.emit(lane_index)
	Logger.info("Current player lane changed to: %d" % lane_index, "LANE")

func get_lane_count() -> int:
	return lanes.size()

func get_active_lane_count() -> int:
	return active_lane_count

func is_lane_active(lane_index: int) -> bool:
	var lane = get_lane(lane_index)
	return lane.get("active", false)

func deactivate_lane(lane_index: int):
	var lane = get_lane(lane_index)
	if not lane.is_empty():
		lane["active"] = false
		Logger.info("Lane %d deactivated" % lane_index, "LANE")

func get_player_lanes() -> Array[Dictionary]:
	var player_lanes: Array[Dictionary] = []
	for lane in lanes:
		if lane.get("type", "") == "player":
			player_lanes.append(lane)
	return player_lanes

func get_boss_lane() -> Dictionary:
	for lane in lanes:
		if lane.get("type", "") == "boss":
			return lane
	return {}

func get_target_lane_for_player(player_lane_index: int) -> int:
	var lane = get_lane(player_lane_index)
	return lane.get("target_lane", -1)

func get_source_lane_for_player(player_lane_index: int) -> int:
	var lane = get_lane(player_lane_index)
	return lane.get("source_lane", -1)

func remove_player_from_pvp(player_lane_index: int):
	deactivate_lane(player_lane_index)

	for i in range(lanes.size()):
		var lane = lanes[i]
		if lane.get("target_lane", -1) == player_lane_index:
			var next_active_lane = _find_next_active_lane(player_lane_index)
			lane["target_lane"] = next_active_lane
			Logger.info("Lane %d target updated from %d to %d" % [i, player_lane_index, next_active_lane], "LANE")

func _find_next_active_lane(start_index: int) -> int:
	for offset in range(1, lanes.size()):
		var check_index = (start_index + offset) % lanes.size()
		if is_lane_active(check_index):
			return check_index
	return -1

func get_lane_world_offset(lane_index: int) -> Vector2:
	var grid_size = GridSystem.GRID_WIDTH * GridSystem.CELL_SIZE
	var spacing = 50
	return Vector2(lane_index * (grid_size + spacing), 0)