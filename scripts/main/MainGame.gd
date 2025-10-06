extends Control
class_name MainGame

@onready var game_field: GameField = $VBoxContainer/GameField
@onready var tool_label: Label = $VBoxContainer/TopUI/HBoxContainer/ToolLabel
@onready var instructions_label: Label = $VBoxContainer/TopUI/HBoxContainer/InstructionsLabel

func _ready():
	print("MainGame started - Grid Map System")
	setup_ui()
	connect_signals()

func setup_ui():
	if tool_label:
		tool_label.text = "Tool: NONE"

	if instructions_label:
		instructions_label.text = "1:Tower 2:Obstacle 3:Path E:Eraser ESC:None | WASD:Scroll | R:Reset C:Clear"

func connect_signals():
	if game_field and game_field.grid_renderer:
		game_field.grid_renderer.cell_clicked.connect(_on_cell_clicked)

func _on_cell_clicked(grid_position: Vector2i):
	if game_field:
		game_field._on_grid_cell_clicked(grid_position)
		update_tool_display()

func update_tool_display():
	if not tool_label or not game_field:
		return

	var current_tool = game_field.get_current_tool()
	tool_label.text = "Tool: " + GameField.PlacementTool.keys()[current_tool]

func _input(event):
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				reset_game()
			KEY_C:
				clear_grid()
			KEY_ESCAPE:
				get_tree().quit()

	if game_field:
		update_tool_display()

func reset_game():
	print("Resetting game...")
	get_tree().reload_current_scene()

func clear_grid():
	if game_field:
		game_field.clear_all_cells()
		print("Grid cleared")

func center_view_on_spawn():
	if game_field:
		game_field.center_view_on_cell(Vector2i(0, 5))