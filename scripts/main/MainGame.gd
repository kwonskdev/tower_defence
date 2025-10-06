extends Control
class_name MainGame

@onready var game_field: GameField = $VBoxContainer/GameField
@onready var tool_label: Label = $VBoxContainer/TopUI/HBoxContainer/ToolLabel
@onready var tower_button: Button = $VBoxContainer/TopUI/HBoxContainer/ToolButtons/TowerButton
@onready var obstacle_button: Button = $VBoxContainer/TopUI/HBoxContainer/ToolButtons/ObstacleButton
@onready var eraser_button: Button = $VBoxContainer/TopUI/HBoxContainer/ToolButtons/EraserButton
@onready var clear_button: Button = $VBoxContainer/TopUI/HBoxContainer/ToolButtons/ClearButton

func _ready():
	print("MainGame started - Grid Map System")
	setup_ui()
	connect_signals()

func setup_ui():
	if tool_label:
		tool_label.text = "Tool: NONE"

func connect_signals():
	if game_field and game_field.grid_renderer:
		game_field.grid_renderer.cell_clicked.connect(_on_cell_clicked)

	# 버튼 클릭 이벤트 연결
	if tower_button:
		tower_button.pressed.connect(_on_tower_button_pressed)
	if obstacle_button:
		obstacle_button.pressed.connect(_on_obstacle_button_pressed)
	if eraser_button:
		eraser_button.pressed.connect(_on_eraser_button_pressed)
	if clear_button:
		clear_button.pressed.connect(_on_clear_button_pressed)

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
	# 마우스 우클릭으로 도구 취소
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if game_field:
			game_field.set_current_tool(GameField.PlacementTool.NONE)
			update_tool_display()

	# 키보드 단축키 유지 (모바일에서는 사용 안 함)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				reset_game()
			KEY_ESCAPE:
				get_tree().quit()

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

# 버튼 클릭 이벤트 핸들러들
func _on_tower_button_pressed():
	if game_field:
		game_field.set_current_tool(GameField.PlacementTool.TOWER)
		update_tool_display()

func _on_obstacle_button_pressed():
	if game_field:
		game_field.set_current_tool(GameField.PlacementTool.OBSTACLE)
		update_tool_display()

func _on_eraser_button_pressed():
	if game_field:
		game_field.set_current_tool(GameField.PlacementTool.ERASER)
		update_tool_display()

func _on_clear_button_pressed():
	clear_grid()