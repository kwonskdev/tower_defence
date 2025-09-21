extends Control
class_name TowerSelectionUI

enum BarrackType {
	TOWER,
	MONSTER,
	UPGRADE,
	NONE
}

@export var tower_button_scene: PackedScene
@export var barrack_button_scene: PackedScene

var current_barrack: BarrackType = BarrackType.NONE
var selected_tower_type: String = ""
var tower_buttons: Array[Button] = []
var barrack_buttons: Array[Button] = []

var main_container: VBoxContainer
var barrack_selection: HBoxContainer
var content_area: Control
var resource_display: HBoxContainer

signal tower_selected(tower_type: String)
signal barrack_changed(barrack_type: BarrackType)
signal tower_placement_requested(tower_type: String)

func _ready():
	_create_ui_structure()
	_setup_barrack_buttons()
	_setup_resource_display()
	_switch_to_barrack(BarrackType.TOWER)

	Logger.ui_log("TowerSelectionUI initialized")

func _create_ui_structure():
	main_container = VBoxContainer.new()
	main_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(main_container)

	barrack_selection = HBoxContainer.new()
	barrack_selection.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_child(barrack_selection)

	content_area = Control.new()
	content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	main_container.add_child(content_area)

	resource_display = HBoxContainer.new()
	resource_display.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_container.add_child(resource_display)

func _setup_barrack_buttons():
	var barrack_types = [
		{"type": BarrackType.TOWER, "text": "타워", "icon": null},
		{"type": BarrackType.MONSTER, "text": "몬스터", "icon": null},
		{"type": BarrackType.UPGRADE, "text": "업그레이드", "icon": null}
	]

	for barrack_data in barrack_types:
		var button = Button.new()
		button.text = barrack_data.text
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(_on_barrack_button_pressed.bind(barrack_data.type))
		barrack_selection.add_child(button)
		barrack_buttons.append(button)

func _setup_resource_display():
	var gold_label = Label.new()
	gold_label.text = "골드: 0"
	gold_label.name = "GoldLabel"
	resource_display.add_child(gold_label)

	var lives_label = Label.new()
	lives_label.text = "생명: 10"
	lives_label.name = "LivesLabel"
	resource_display.add_child(lives_label)

	var income_label = Label.new()
	income_label.text = "수입: 0/초"
	income_label.name = "IncomeLabel"
	resource_display.add_child(income_label)

func _on_barrack_button_pressed(barrack_type: BarrackType):
	_switch_to_barrack(barrack_type)

func _switch_to_barrack(barrack_type: BarrackType):
	if current_barrack == barrack_type:
		return

	current_barrack = barrack_type
	_clear_content_area()
	_update_barrack_button_states()

	match barrack_type:
		BarrackType.TOWER:
			_setup_tower_selection()
		BarrackType.MONSTER:
			_setup_monster_selection()
		BarrackType.UPGRADE:
			_setup_upgrade_selection()

	barrack_changed.emit(barrack_type)
	Logger.ui_log("Switched to barrack: %s" % _barrack_type_to_string(barrack_type))

func _update_barrack_button_states():
	for i in range(barrack_buttons.size()):
		var button = barrack_buttons[i]
		button.disabled = (i == current_barrack)

func _clear_content_area():
	for child in content_area.get_children():
		child.queue_free()
	tower_buttons.clear()
	selected_tower_type = ""

func _setup_tower_selection():
	var scroll_container = ScrollContainer.new()
	scroll_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(scroll_container)

	var grid_container = GridContainer.new()
	grid_container.columns = 2
	grid_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll_container.add_child(grid_container)

	var tower_categories = TowerFactory.get_towers_by_category()

	var basic_label = Label.new()
	basic_label.text = "기본 공격 타워"
	basic_label.add_theme_font_size_override("font_size", 16)
	grid_container.add_child(basic_label)
	grid_container.add_child(Control.new())

	for tower_type in tower_categories.basic_attack:
		_create_tower_button(tower_type, grid_container)

	var support_label = Label.new()
	support_label.text = "지원 타워"
	support_label.add_theme_font_size_override("font_size", 16)
	grid_container.add_child(support_label)
	grid_container.add_child(Control.new())

	for tower_type in tower_categories.support:
		_create_tower_button(tower_type, grid_container)

func _create_tower_button(tower_type: String, parent: Control):
	var button_container = VBoxContainer.new()

	var button = Button.new()
	button.text = TowerFactory.get_tower_name(tower_type)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.set_meta("tower_type", tower_type)
	button.pressed.connect(_on_tower_button_pressed.bind(tower_type))

	var cost_label = Label.new()
	cost_label.text = "비용: %d" % TowerFactory.get_tower_cost(tower_type)
	cost_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER

	var description_label = Label.new()
	description_label.text = TowerFactory.get_tower_description(tower_type)
	description_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	description_label.custom_minimum_size.y = 40

	button_container.add_child(button)
	button_container.add_child(cost_label)
	button_container.add_child(description_label)

	parent.add_child(button_container)
	tower_buttons.append(button)

func _setup_monster_selection():
	var label = Label.new()
	label.text = "몬스터 시스템 (구현 예정)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(label)

func _setup_upgrade_selection():
	var label = Label.new()
	label.text = "업그레이드 시스템 (구현 예정)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content_area.add_child(label)

func _on_tower_button_pressed(tower_type: String):
	selected_tower_type = tower_type
	_update_tower_button_states()

	tower_selected.emit(tower_type)
	tower_placement_requested.emit(tower_type)

	Logger.ui_log("Tower selected: %s" % TowerFactory.get_tower_name(tower_type))

func _update_tower_button_states():
	for button in tower_buttons:
		button.disabled = false
		var button_tower_type = button.get_meta("tower_type", "")
		if button_tower_type == selected_tower_type:
			button.disabled = true

func update_resources(gold: int, lives: int, income: float):
	var gold_label = resource_display.get_node("GoldLabel") as Label
	var lives_label = resource_display.get_node("LivesLabel") as Label
	var income_label = resource_display.get_node("IncomeLabel") as Label

	if gold_label:
		gold_label.text = "골드: %d" % gold
	if lives_label:
		lives_label.text = "생명: %d" % lives
	if income_label:
		income_label.text = "수입: %.1f/초" % income

func can_afford_tower(tower_type: String, current_gold: int) -> bool:
	var cost = TowerFactory.get_tower_cost(tower_type)
	return current_gold >= cost

func update_tower_affordability(current_gold: int):
	for button in tower_buttons:
		var tower_type = button.get_meta("tower_type", "")
		if tower_type != "":
			var can_afford = can_afford_tower(tower_type, current_gold)
			button.modulate = Color.WHITE if can_afford else Color.GRAY

func get_selected_tower_type() -> String:
	return selected_tower_type

func clear_selection():
	selected_tower_type = ""
	_update_tower_button_states()

func _barrack_type_to_string(barrack_type: BarrackType) -> String:
	match barrack_type:
		BarrackType.TOWER:
			return "TOWER"
		BarrackType.MONSTER:
			return "MONSTER"
		BarrackType.UPGRADE:
			return "UPGRADE"
		BarrackType.NONE:
			return "NONE"
		_:
			return "UNKNOWN"