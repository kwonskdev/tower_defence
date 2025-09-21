extends Control
class_name GameField

@export var grid_renderer_scene: PackedScene

var grid_system: GridSystem
var grid_renderer: GridRenderer
var lane_manager: LaneManager
var color_bonus_system: ColorBonusSystem
var tower_selection_ui: TowerSelectionUI

var placement_mode: bool = false
var selected_tower_type: String = ""
var camera: Camera2D
var scroll_container: ScrollContainer

signal tower_placement_completed(position: Vector2i, tower_type: String)
signal tower_selection_requested(position: Vector2i)

func _ready():
	_setup_scroll_container()
	_setup_camera()
	_initialize_systems()
	_setup_connections()

	Logger.ui_log("GameField initialized")

func _setup_scroll_container():
	scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll_container.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll_container.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	add_child(scroll_container)

func _setup_camera():
	camera = Camera2D.new()
	camera.enabled = true
	add_child(camera)

func _initialize_systems():
	grid_system = GridSystem.new()
	lane_manager = LaneManager.new()
	color_bonus_system = ColorBonusSystem.new(grid_system)

	lane_manager.initialize_lanes(1, "coop")

	_setup_grid_renderer()

func _setup_grid_renderer():
	grid_renderer = GridRenderer.new()
	grid_renderer.grid_system = grid_system
	grid_renderer.cell_clicked.connect(_on_cell_clicked)
	grid_renderer.cell_hovered.connect(_on_cell_hovered)
	scroll_container.add_child(grid_renderer)

	var grid_world_size = grid_renderer.get_grid_world_size()
	scroll_container.custom_minimum_size = grid_world_size

func _setup_connections():
	grid_system.tower_placed.connect(_on_tower_placed)
	grid_system.tower_removed.connect(_on_tower_removed)

func set_tower_selection_ui(ui: TowerSelectionUI):
	tower_selection_ui = ui
	if tower_selection_ui:
		tower_selection_ui.tower_placement_requested.connect(_on_tower_placement_requested)

func _on_tower_placement_requested(tower_type: String):
	placement_mode = true
	selected_tower_type = tower_type
	grid_renderer.set_placement_mode(true, tower_type)

	Logger.ui_log("Tower placement mode activated: %s" % tower_type)

func _on_cell_clicked(grid_position: Vector2i):
	if not grid_system.is_valid_position(grid_position):
		return

	var cell_type = grid_system.get_cell_type(grid_position)

	if placement_mode and selected_tower_type != "":
		_attempt_tower_placement(grid_position)
	elif cell_type == GridSystem.CellType.TOWER:
		_select_existing_tower(grid_position)

func _on_cell_hovered(_grid_position: Vector2i):
	pass

func _attempt_tower_placement(grid_position: Vector2i) -> bool:
	if not grid_system.can_place_tower(grid_position):
		Logger.ui_log("Cannot place tower at %v" % grid_position, Logger.LogLevel.WARNING)
		return false

	var tower_cost = TowerFactory.get_tower_cost(selected_tower_type)

	var tower = TowerFactory.create_tower(selected_tower_type)
	if tower == null:
		Logger.error("Failed to create tower: %s" % selected_tower_type, "GAME_FIELD")
		return false

	var tower_data = {
		"type": selected_tower_type,
		"node": tower,
		"cost": tower_cost,
		"position": grid_position
	}

	if grid_system.place_tower(grid_position, tower_data):
		var world_position = grid_system.grid_to_world_position(grid_position)
		tower.global_position = world_position
		grid_renderer.add_child(tower)

		color_bonus_system.apply_bonuses_to_tower(tower, grid_position)

		_exit_placement_mode()
		tower_placement_completed.emit(grid_position, selected_tower_type)

		Logger.ui_log("Tower placed successfully at %v: %s" % [grid_position, selected_tower_type])
		return true

	Logger.ui_log("Failed to place tower at %v" % grid_position, Logger.LogLevel.WARNING)
	return false

func _select_existing_tower(grid_position: Vector2i):
	var tower_data = grid_system.get_tower_at(grid_position)
	if not tower_data.is_empty():
		tower_selection_requested.emit(grid_position)
		Logger.ui_log("Tower selected at %v: %s" % [grid_position, tower_data.get("type", "Unknown")])

func _exit_placement_mode():
	placement_mode = false
	selected_tower_type = ""
	grid_renderer.set_placement_mode(false)

	if tower_selection_ui:
		tower_selection_ui.clear_selection()

func _on_tower_placed(grid_position: Vector2i, tower_type: String):
	Logger.game_state_log("Tower placed: %s at %v" % [tower_type, grid_position])

func _on_tower_removed(grid_position: Vector2i):
	Logger.game_state_log("Tower removed at %v" % grid_position)

func remove_tower(grid_position: Vector2i) -> bool:
	var tower_data = grid_system.get_tower_at(grid_position)
	if tower_data.is_empty():
		return false

	var tower_node = tower_data.get("node", null)
	if tower_node:
		tower_node.queue_free()

	return grid_system.remove_tower(grid_position)

func upgrade_tower(grid_position: Vector2i) -> bool:
	var tower_data = grid_system.get_tower_at(grid_position)
	if tower_data.is_empty():
		return false

	var tower_node = tower_data.get("node", null) as TowerBase
	if tower_node:
		return tower_node.upgrade_tower()

	return false

func evolve_tower(grid_position: Vector2i) -> bool:
	var tower_data = grid_system.get_tower_at(grid_position)
	if tower_data.is_empty():
		return false

	var tower_node = tower_data.get("node", null) as TowerBase
	if tower_node:
		return tower_node.evolve_tower()

	return false

func get_tower_info(grid_position: Vector2i) -> Dictionary:
	var tower_data = grid_system.get_tower_at(grid_position)
	if tower_data.is_empty():
		return {}

	var tower_node = tower_data.get("node", null) as TowerBase
	if tower_node:
		return tower_node.get_tower_info()

	return {}

func center_camera_on_position(grid_position: Vector2i):
	var world_position = grid_system.grid_to_world_position(grid_position)
	camera.global_position = world_position

func get_grid_system() -> GridSystem:
	return grid_system

func get_lane_manager() -> LaneManager:
	return lane_manager

func get_color_bonus_system() -> ColorBonusSystem:
	return color_bonus_system

func _input(event):
	if event.is_action_pressed("ui_cancel") and placement_mode:
		_exit_placement_mode()
		Logger.ui_log("Tower placement cancelled")