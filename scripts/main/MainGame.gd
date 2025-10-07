extends Control
class_name MainGame

@onready var game_field: GameField = $VBoxContainer/GameField
@onready var main_view: HBoxContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView
@onready var monster_view: GridContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MonsterView

@onready var tower_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/TowerButton
@onready var monster_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/MonsterButton
@onready var empty2_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/Empty2Button
@onready var bonus_button: Button = $VBoxContainer/TopUI/HBoxContainer/RightPanel/BonusButton

# 플레이어 버튼들
@onready var player_buttons: Array[Button] = []
@onready var monster_buttons: Array[Button] = []

func _ready():
	print("MainGame started - Grid Map System")
	setup_ui()
	connect_signals()

func setup_ui():
	# RightPanel 플레이어 버튼들 초기화 (고정 미니맵)
	var player_order = [1, 2, 3, 4, 5, 6, 7, 8]
	for player_num in player_order:
		var button = get_node_or_null("VBoxContainer/TopUI/HBoxContainer/RightPanel/Player" + str(player_num))
		if button:
			player_buttons.append(button)

	# LeftPanel MonsterView 몬스터 버튼들 초기화
	for i in range(1, 28):
		var button = get_node_or_null("VBoxContainer/TopUI/HBoxContainer/LeftPanel/MonsterView/Monster" + str(i))
		if button:
			monster_buttons.append(button)

func connect_signals():
	if game_field and game_field.grid_renderer:
		game_field.grid_renderer.cell_clicked.connect(_on_cell_clicked)

	# 버튼 클릭 이벤트 연결
	if tower_button:
		tower_button.pressed.connect(_on_tower_button_pressed)
	if monster_button:
		monster_button.pressed.connect(_on_monster_button_pressed)
	if empty2_button:
		empty2_button.pressed.connect(_on_empty2_button_pressed)
	if bonus_button:
		bonus_button.pressed.connect(_on_bonus_button_pressed)

	# 플레이어 버튼 클릭 이벤트 연결
	for i in range(player_buttons.size()):
		player_buttons[i].pressed.connect(_on_player_button_pressed.bind(i))

	# 몬스터 버튼 클릭 이벤트 연결 (첫 번째는 뒤로 가기)
	if monster_buttons.size() > 0:
		monster_buttons[0].pressed.connect(_on_back_button_pressed)
	for i in range(1, monster_buttons.size()):
		monster_buttons[i].pressed.connect(_on_monster_selected.bind(i))

func _on_cell_clicked(grid_position: Vector2i):
	if game_field:
		game_field._on_grid_cell_clicked(grid_position)
		update_tool_display()

func update_tool_display():
	# UI 업데이트 (라벨 제거됨)
	pass

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

func _on_monster_button_pressed():
	# 몬스터 뷰로 전환
	main_view.visible = false
	monster_view.visible = true

func _on_empty2_button_pressed():
	if game_field:
		game_field.set_current_tool(GameField.PlacementTool.NONE)
		update_tool_display()

# 플레이어 전환 핸들러
func _on_player_button_pressed(player_id: int):
	if game_field:
		game_field.switch_player(player_id)
		update_tool_display()

# 보너스 맵 버튼 핸들러
func _on_bonus_button_pressed():
	print("Bonus map button pressed - 나중에 구현")

# 뒤로 가기 버튼 핸들러
func _on_back_button_pressed():
	# 메인 뷰로 돌아가기
	monster_view.visible = false
	main_view.visible = true

# 몬스터 선택 핸들러
func _on_monster_selected(monster_id: int):
	print("Monster ", monster_id, " selected")