extends Control
class_name MainGame

@onready var game_field: GameField = $VBoxContainer/GameField
@onready var main_view: HBoxContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView
@onready var monster_view: GridContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MonsterView

@onready var tower_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/TowerButton
@onready var monster_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/MonsterButton
@onready var empty2_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/Empty2Button
@onready var boss_button: Button = $VBoxContainer/TopUI/HBoxContainer/RightPanel/BonusButton

# 몬스터 버튼 인덱스(monster_buttons 기준) -> 생산할 몬스터 종류. 0번은 뒤로 가기.
const MONSTER_KIND_BY_INDEX := {1: "income", 2: "balanced", 3: "power"}

var hud_label: Label
var tower_view: GridContainer
var _hud_timer := 0.0

# 플레이어 버튼들
@onready var player_buttons: Array[Button] = []
@onready var monster_buttons: Array[Button] = []

func _ready():
	Log.info(Log.Category.GAME, "MainGame 시작")
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

	# 몬스터 버튼에 종류 이름 표시
	for idx in MONSTER_KIND_BY_INDEX:
		if idx < monster_buttons.size():
			var kind: Dictionary = Balance.SENT_MONSTERS[MONSTER_KIND_BY_INDEX[idx]]
			monster_buttons[idx].text = kind.short
			monster_buttons[idx].tooltip_text = "%s  비용 %d / 수입 +%d / 보스 DPS %.1f" % [
				kind.name, kind.cost, kind.income, kind.dps]

	_create_tower_view()
	_create_hud()

func _create_tower_view():
	# 타워 배럭: 속성 2개 조합 타워 선택 (코드로 생성, 몬스터 뷰와 같은 자리를 쓴다)
	var left_panel: Control = main_view.get_parent()
	tower_view = GridContainer.new()
	tower_view.columns = Balance.TOWER_COMBOS.size() + 1
	tower_view.visible = false
	left_panel.add_child(tower_view)
	tower_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var back := Button.new()
	back.text = "←"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_vertical = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_on_tower_back_pressed)
	tower_view.add_child(back)

	for kind_id in Balance.TOWER_COMBOS:
		var kind := Balance.tower_kind(kind_id)
		var b := Button.new()
		var short := ""
		for a in kind.attrs:
			short += Balance.TOWER_ATTRS[a].short
		b.text = short + "\n" + str(kind.cost)
		b.tooltip_text = "%s  비용 %d / 사거리 %.1f / 공격력 %.1f / 쿨다운 %.2fs%s%s" % [
			kind.name, kind.cost, kind.range, kind.damage, kind.cooldown,
			" / 범위 %.1f" % kind.splash if kind.splash > 0.0 else "",
			"" if kind.blocks else " / 길을 막지 못함"]
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_tower_kind_selected.bind(kind_id))
		tower_view.add_child(b)

func _create_hud():
	# 하단 상태 표시줄 (골드/생명/보스). 입력은 통과시킨다.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_label = Label.new()
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_label.add_theme_font_size_override("font_size", 12)
	panel.add_child(hud_label)
	add_child(panel)

func _process(delta):
	_hud_timer -= delta
	if _hud_timer > 0.0:
		return
	_hud_timer = 0.1
	_update_hud()

func _update_hud():
	if not hud_label or not game_field:
		return
	var lane: LaneController = game_field.lanes.get(game_field.local_player_id)
	var boss: BossController = game_field.boss
	if lane == null or boss == null:
		return

	var state_text := ""
	match boss.state:
		BossController.State.VICTORY: state_text = "  [승리]"
		BossController.State.DEFEAT: state_text = "  [패배]"
	var selected := Balance.tower_kind(game_field.selected_tower_kind)
	hud_label.text = "골드 %d (+%d/%.0fs)  생명 %d  타워 %d개%s\n선택 타워: %s (%d골드)\n보스 %d/%d  남은 %ds  보스DPS %.1f" % [
		lane.gold, lane.income, Balance.INCOME_INTERVAL, lane.lives, lane.towers.size(), state_text,
		selected.name, selected.cost, int(boss.hp), int(boss.max_hp), int(boss.time_left), boss.total_dps]

func connect_signals():
	# 버튼 클릭 이벤트 연결
	if tower_button:
		tower_button.pressed.connect(_on_tower_button_pressed)
	if monster_button:
		monster_button.pressed.connect(_on_monster_button_pressed)
	if empty2_button:
		empty2_button.pressed.connect(_on_empty2_button_pressed)
	if boss_button:
		boss_button.pressed.connect(_on_boss_button_pressed)

	# 플레이어 버튼 클릭 이벤트 연결
	for i in range(player_buttons.size()):
		player_buttons[i].pressed.connect(_on_player_button_pressed.bind(i))

	# 몬스터 버튼 클릭 이벤트 연결 (첫 번째는 뒤로 가기)
	if monster_buttons.size() > 0:
		monster_buttons[0].pressed.connect(_on_back_button_pressed)
	for i in range(1, monster_buttons.size()):
		monster_buttons[i].pressed.connect(_on_monster_selected.bind(i))

func _input(event):
	# 마우스 우클릭으로 도구 취소
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		if game_field:
			game_field.set_current_tool(GameField.PlacementTool.NONE)

	# 키보드 단축키 유지 (모바일에서는 사용 안 함)
	if event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_R:
				reset_game()
			KEY_ESCAPE:
				get_tree().quit()

func reset_game():
	Log.info(Log.Category.GAME, "게임 리셋")
	get_tree().reload_current_scene()

# 버튼 클릭 이벤트 핸들러들
func _on_tower_button_pressed():
	# 타워 배럭으로 전환
	Log.info(Log.Category.UI, "타워 배럭 열기")
	main_view.visible = false
	tower_view.visible = true

func _on_tower_back_pressed():
	tower_view.visible = false
	main_view.visible = true

func _on_tower_kind_selected(kind_id: String):
	if game_field:
		game_field.set_tower_kind(kind_id)
		game_field.set_current_tool(GameField.PlacementTool.TOWER)
	tower_view.visible = false
	main_view.visible = true

func _on_monster_button_pressed():
	# 몬스터 뷰로 전환
	Log.info(Log.Category.UI, "몬스터 배럭 열기")
	main_view.visible = false
	monster_view.visible = true

func _on_empty2_button_pressed():
	if game_field:
		game_field.set_current_tool(GameField.PlacementTool.NONE)

# 플레이어 전환 핸들러
func _on_player_button_pressed(player_id: int):
	if game_field:
		game_field.switch_player(player_id)

# 보너스 맵 버튼 핸들러
func _on_boss_button_pressed():
	if game_field:
		game_field.switch_player(GameField.BOSS_LANE_ID)

# 뒤로 가기 버튼 핸들러
func _on_back_button_pressed():
	# 메인 뷰로 돌아가기
	Log.info(Log.Category.UI, "몬스터 배럭 닫기")
	monster_view.visible = false
	main_view.visible = true

# 몬스터 선택 핸들러
func _on_monster_selected(button_index: int):
	var kind_id: String = MONSTER_KIND_BY_INDEX.get(button_index, "")
	if kind_id.is_empty():
		Log.info(Log.Category.UI, "몬스터 M%d 선택 (미구현)" % (button_index + 1))
		return
	Log.info(Log.Category.UI, "몬스터 생산 요청: %s" % kind_id)
	game_field.send_monster(kind_id)