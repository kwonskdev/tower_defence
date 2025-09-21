extends Control
class_name MainGame

@onready var ui_container: VBoxContainer = $UIContainer
@onready var top_ui: Control = $UIContainer/TopUI
@onready var bottom_ui: Control = $UIContainer/BottomUI

var tower_selection_ui: TowerSelectionUI
var game_field: GameField
var game_manager: GameManager

var screen_height: float
var top_ui_height: float
var bottom_ui_height: float

func _ready():
	Logger.get_instance()
	Logger.info("MainGame started")

	_setup_screen_layout()
	_initialize_game_manager()
	_initialize_ui_components()
	_setup_connections()

	Logger.game_state_log("Game initialized successfully")

func _setup_screen_layout():
	screen_height = get_viewport().get_visible_rect().size.y
	top_ui_height = screen_height * 0.2
	bottom_ui_height = screen_height * 0.8

	top_ui.custom_minimum_size.y = top_ui_height
	bottom_ui.custom_minimum_size.y = bottom_ui_height

	Logger.info("Screen layout: Total=%d, Top=%d, Bottom=%d" % [screen_height, top_ui_height, bottom_ui_height])

func _initialize_game_manager():
	game_manager = GameManager.new()
	add_child(game_manager)

	game_manager.start_game(GameManager.GameMode.COOP, 1)

func _initialize_ui_components():
	_create_tower_selection_ui()
	_create_game_field()

func _create_tower_selection_ui():
	tower_selection_ui = TowerSelectionUI.new()
	tower_selection_ui.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tower_selection_ui.size_flags_vertical = Control.SIZE_EXPAND_FILL
	top_ui.add_child(tower_selection_ui)

	Logger.ui_log("Tower selection UI created")

func _create_game_field():
	game_field = GameField.new()
	game_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	game_field.size_flags_vertical = Control.SIZE_EXPAND_FILL
	bottom_ui.add_child(game_field)

	game_field.set_tower_selection_ui(tower_selection_ui)

	Logger.ui_log("Game field created")

func _setup_connections():
	if tower_selection_ui:
		tower_selection_ui.tower_selected.connect(_on_tower_selected)
		tower_selection_ui.barrack_changed.connect(_on_barrack_changed)

	if game_field:
		game_field.tower_placement_completed.connect(_on_tower_placement_completed)
		game_field.tower_selection_requested.connect(_on_tower_selection_requested)

	if game_manager:
		game_manager.game_state_changed.connect(_on_game_state_changed)
		game_manager.economy_manager.gold_changed.connect(_on_gold_changed)
		game_manager.economy_manager.lives_changed.connect(_on_lives_changed)
		game_manager.economy_manager.income_changed.connect(_on_income_changed)

func _on_tower_selected(tower_type: String):
	Logger.ui_log("Tower selected from UI: %s" % tower_type)

func _on_barrack_changed(barrack_type: TowerSelectionUI.BarrackType):
	Logger.ui_log("Barrack changed: %s" % barrack_type)

func _on_tower_placement_completed(grid_position: Vector2i, tower_type: String):
	var tower_cost = TowerFactory.get_tower_cost(tower_type)
	Logger.game_state_log("Tower placement completed: %s at %v (cost: %d)" % [tower_type, grid_position, tower_cost])

func _on_tower_selection_requested(grid_position: Vector2i):
	var tower_info = game_field.get_tower_info(grid_position)
	Logger.ui_log("Tower info requested at %v: %s" % [grid_position, tower_info])

func _on_game_state_changed(new_state: GameManager.GameState):
	Logger.game_state_log("Game state changed: %s" % new_state)

func _on_gold_changed(new_amount: int):
	if tower_selection_ui:
		tower_selection_ui.update_tower_affordability(new_amount)

func _on_lives_changed(_new_amount: int):
	_update_resource_display()

func _on_income_changed(_new_income: float):
	_update_resource_display()

func _update_resource_display():
	if tower_selection_ui and game_manager:
		var economy = game_manager.get_economy_manager()
		tower_selection_ui.update_resources(
			economy.get_gold(),
			economy.get_lives(),
			economy.get_income_per_second()
		)

func _notification(what):
	if what == NOTIFICATION_WM_CLOSE_REQUEST:
		Logger.info("Game closing")
		Logger.close_logger()
		get_tree().quit()

func _exit_tree():
	Logger.info("MainGame exiting")
	Logger.close_logger()