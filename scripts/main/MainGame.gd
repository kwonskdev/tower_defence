extends Control
class_name MainGame

@onready var game_field: GameField = $VBoxContainer/GameField
@onready var main_view: HBoxContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView
@onready var monster_view: GridContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MonsterView

@onready var tower_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/TowerButton
@onready var monster_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/MonsterButton
@onready var empty2_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/Empty2Button
@onready var boss_button: Button = $VBoxContainer/TopUI/HBoxContainer/RightPanel/BonusButton

# 몬스터 버튼은 monster_buttons[0]이 뒤로 가기, [1]부터 SentMonsters.SLOTS 순서대로 몬스터 종류 (계열별로 묶고 사이에 빈칸).

var hud_label: Label
var tower_info_row: HBoxContainer
var start_button: Button
var family_frames: Control               # 몬스터 배럭의 계열 묶음 외곽선
var tower_info_label: Label
var evolve_buttons: Array[Button] = []   # 선택한 타워가 아직 진화 전이면 계열 2개 중 고르는 버튼
var evolve_ids: Array[String] = ["", ""]
var skill_hint_label: Label              # 업그레이드 탭에서 마우스를 올린 항목의 설명
var upgrade_menu: HBoxContainer          # 업그레이드 탭: [←] [타워] [색깔]
var evo_view: GridContainer              # 타워 업그레이드 1단계: 진화 계열 8개 중 고르기
var evo_buttons: Dictionary = {}         # 계열 -> Button
var detail_view: GridContainer           # 타워 업그레이드 2단계: 고른 계열의 업그레이드 항목들
var _detail_evo := ""                    # 지금 보고 있는 계열
var _detail_items: Array = []            # [{btn, kind: "stat"/"learn", stat: Dictionary}]
var _hover: Array = []                   # 마우스가 올라간 항목: [계열, 종류("evo"/"stat"/"learn"), 스킬, 키]
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

	empty2_button.text = "업그레이드"
	_setup_monster_buttons()
	_create_family_frames()
	_create_tower_view()
	_create_upgrade_views()
	_create_minimaps()
	_create_hud()

## 버튼을 "실제 모습 아이콘 + 비용 + 마우스 올리면 상세 설명" 형태로 꾸민다
func _decorate_unit_button(b: Button, icon: UnitIcon, cost: int, tooltip: String, tag: String = "", tag_color: Color = Color.WHITE):
	b.text = ""
	b.tooltip_text = tooltip
	b.clip_contents = true
	b.add_child(icon)
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var cost_label := Label.new()
	cost_label.text = str(cost)
	cost_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cost_label.add_theme_font_size_override("font_size", 11)
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cost_label.add_theme_constant_override("outline_size", 4)
	cost_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cost_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	b.add_child(cost_label)
	cost_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)

	if tag != "":  # 계열 이름표 (왼쪽 위)
		var tag_label := Label.new()
		tag_label.text = tag
		tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_label.add_theme_font_size_override("font_size", 9)
		tag_label.add_theme_color_override("font_color", tag_color)
		tag_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		tag_label.add_theme_constant_override("outline_size", 3)
		b.add_child(tag_label)
		tag_label.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
		tag_label.position += Vector2(3, 0)  # 테두리에 붙지 않게 살짝 안쪽으로

## 몬스터 배럭: 계열(수입/화력/균형/특수/지원)별로 색 테두리 + 이름표를 달고, 계열 사이는 빈칸으로 띄운다
func _setup_monster_buttons():
	for i in range(1, monster_buttons.size()):
		var b := monster_buttons[i]
		var slot_idx := i - 1
		if slot_idx >= SentMonsters.SLOTS.size():
			b.visible = false  # 쓰지 않는 칸은 숨겨서 격자가 두 줄로 커진다
			continue
		var kind_id: String = SentMonsters.SLOTS[slot_idx]
		if kind_id == "":
			b.text = ""
			b.flat = true  # 계열 사이 빈칸 (보이지 않고 눌리지도 않는다)
			b.disabled = true
			b.focus_mode = Control.FOCUS_NONE
			continue
		var data: Dictionary = SentMonsters.DATA[kind_id]
		var fam_color: Color = SentMonsters.FAMILY_COLORS[data.family]
		var icon := UnitIcon.new()
		icon.show_monster(kind_id)
		_decorate_unit_button(b, icon, data.cost, SentMonsters.tooltip(kind_id), data.family, fam_color)
		_apply_family_style(b, fam_color)


## 계열 묶음마다 굵은 외곽선 프레임을 씌운다 (버튼 격자 위에 겹쳐 그리는 안 눌리는 레이어)
func _create_family_frames() -> void:
	var left_panel: Control = main_view.get_parent()
	var frames := FamilyFrames.new()
	family_frames = frames
	frames.visible = false
	left_panel.add_child(frames)
	frames.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	# 칸 배치(SLOTS)에서 같은 계열이 이어진 구간을 한 묶음으로 본다
	var run_family := ""
	var run_buttons: Array[Button] = []
	for i in range(SentMonsters.SLOTS.size() + 1):
		var kind_id: String = SentMonsters.SLOTS[i] if i < SentMonsters.SLOTS.size() else ""
		var fam: String = SentMonsters.DATA[kind_id].family if kind_id != "" else ""
		if fam != run_family and not run_buttons.is_empty():
			frames.groups.append({"buttons": run_buttons, "color": SentMonsters.FAMILY_COLORS[run_family]})
			run_buttons = []
		run_family = fam
		if fam != "":
			run_buttons.append(monster_buttons[i + 1])


## 버튼 격자 위에 계열 묶음 외곽선만 그린다
class FamilyFrames extends Control:
	var groups: Array = []  # [{buttons: Array[Button], color: Color}]

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		z_index = 50

	func _process(_delta: float) -> void:
		if visible:
			queue_redraw()  # 격자가 배치된 뒤의 버튼 위치를 따라간다

	func _draw() -> void:
		for g in groups:
			var rect := Rect2()
			var first := true
			for b in g.buttons:
				var r := Rect2(b.global_position - global_position, b.size)
				rect = r if first else rect.merge(r)
				first = false
			draw_rect(rect.grow(1.0), g.color, false, 3.0)


func _apply_family_style(b: Button, fam_color: Color) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		var lift := 0.0 if state == "normal" else (0.12 if state == "hover" else (0.2 if state == "pressed" else -0.05))
		sb.bg_color = Color(fam_color.r * 0.2 + lift, fam_color.g * 0.2 + lift, fam_color.b * 0.2 + lift, 1.0)
		sb.border_color = Color(fam_color, 0.5)  # 버튼 테두리는 옅게 (계열 묶음 외곽선이 더 굵고 진하다)
		sb.set_border_width_all(1)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override(state, sb)

func _create_tower_view():
	# 타워 배럭: 속성 2개 조합 타워 선택 (코드로 생성, 몬스터 뷰와 같은 자리를 쓴다)
	var left_panel: Control = main_view.get_parent()
	tower_view = GridContainer.new()
	tower_view.columns = 5  # 뒤로 가기 + 기본 타워 4종
	tower_view.visible = false
	left_panel.add_child(tower_view)
	tower_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var back := Button.new()
	back.text = "←"
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_vertical = Control.SIZE_EXPAND_FILL
	back.pressed.connect(_on_tower_back_pressed)
	tower_view.add_child(back)

	for kind_id in Balance.TOWER_KINDS:
		var kind := Balance.tower_kind(kind_id)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_tower_kind_selected.bind(kind_id))
		tower_view.add_child(b)
		var icon := UnitIcon.new()
		icon.show_tower(kind)
		_decorate_unit_button(b, icon, kind.cost, Balance.tower_tooltip(kind))

## 업그레이드 탭 (타워 / 색깔).
## 타워 탭: 진화 계열 8개 중 하나를 고르면 그 계열의 업그레이드 항목(관통 수, 독 피해 ...)이 나오고,
## 항목을 올리면 그 계열로 진화한 모든 타워가 강해진다. 색깔 탭은 아직 기획이 없어서 자리만 만들어 두었다.
func _create_upgrade_views():
	var left_panel: Control = main_view.get_parent()

	upgrade_menu = HBoxContainer.new()
	upgrade_menu.visible = false
	left_panel.add_child(upgrade_menu)
	upgrade_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := _make_view_button("←")
	back.pressed.connect(_show_view.bind("main"))
	upgrade_menu.add_child(back)
	var tower_tab := _make_view_button("타워")
	tower_tab.pressed.connect(_show_view.bind("evos"))
	upgrade_menu.add_child(tower_tab)
	var color_tab := _make_view_button("색깔")
	color_tab.disabled = true
	color_tab.tooltip_text = "색깔별 업그레이드 (준비 중)"
	upgrade_menu.add_child(color_tab)

	# 1단계: [←] + 진화 계열 8개 = 9칸 한 줄
	evo_view = GridContainer.new()
	evo_view.columns = 9
	evo_view.visible = false
	left_panel.add_child(evo_view)
	evo_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var evo_back := _make_view_button("←", 12)
	evo_back.pressed.connect(_show_view.bind("upgrade"))
	evo_view.add_child(evo_back)
	for evo in Evolutions.ORDER:
		var eb := _make_view_button("", 10)
		eb.add_theme_color_override("font_color", Evolutions.DATA[evo].color)
		eb.pressed.connect(_open_evo_detail.bind(evo))
		eb.mouse_entered.connect(func(): _hover = [evo, "evo", "", ""])
		eb.mouse_exited.connect(func(): _hover = [])
		evo_view.add_child(eb)
		evo_buttons[evo] = eb

	# 2단계: 항목 버튼 (계열마다 항목이 달라서 열 때마다 새로 만든다)
	detail_view = GridContainer.new()
	detail_view.columns = 4
	detail_view.visible = false
	left_panel.add_child(detail_view)
	detail_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _make_view_button(text: String, font_size: int = 14) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", font_size)
	return b


## 왼쪽 패널에 보여줄 화면을 하나만 켠다: main / tower / monster / upgrade / evos / detail
func _show_view(view: String) -> void:
	main_view.visible = view == "main"
	tower_view.visible = view == "tower"
	monster_view.visible = view == "monster"
	family_frames.visible = view == "monster"
	upgrade_menu.visible = view == "upgrade"
	evo_view.visible = view == "evos"
	detail_view.visible = view == "detail"
	skill_hint_label.visible = view == "evos" or view == "detail"
	_hover = []


## 고른 계열의 업그레이드 항목 화면을 만든다: [←] + A 항목들 + [B 배우기] + B 항목들
func _open_evo_detail(evo: String) -> void:
	_detail_evo = evo
	_detail_items.clear()
	for c in detail_view.get_children():
		detail_view.remove_child(c)
		c.queue_free()
	var color: Color = Evolutions.DATA[evo].color

	var back := _make_view_button("←", 12)
	back.pressed.connect(_show_view.bind("evos"))
	detail_view.add_child(back)

	var learn_added := false
	for stat in Evolutions.STATS[evo]:
		if stat.s == "B" and not learn_added:
			learn_added = true
			_add_detail_button(evo, "learn", {"s": "B", "k": ""}, color)
		_add_detail_button(evo, "stat", stat, color)
	_show_view("detail")
	_refresh_now()


func _add_detail_button(evo: String, kind: String, stat: Dictionary, color: Color) -> void:
	var b := _make_view_button("", 10)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.55))
	if kind == "learn":
		b.pressed.connect(_on_learn_pressed.bind(evo))
	else:
		b.pressed.connect(_on_stat_pressed.bind(evo, stat.s, stat.k))
	b.mouse_entered.connect(func(): _hover = [evo, kind, stat.s, stat.k])
	b.mouse_exited.connect(func(): _hover = [])
	detail_view.add_child(b)
	_detail_items.append({"btn": b, "kind": kind, "stat": stat})


func _on_stat_pressed(evo: String, skill: String, key: String) -> void:
	game_field.upgrade_stat(evo, skill, key)
	_refresh_now()


func _on_learn_pressed(evo: String) -> void:
	game_field.learn_skill(evo)
	_refresh_now()


func _refresh_now() -> void:
	var lane: LaneController = game_field.lanes.get(game_field.local_player_id)
	if lane:
		_refresh_upgrade_views(lane)


## 업그레이드 화면 글자/활성 상태/설명 갱신
func _refresh_upgrade_views(lane: LaneController) -> void:
	if evo_view.visible:
		for evo in Evolutions.ORDER:
			var d: Dictionary = Evolutions.DATA[evo]
			var learned := "  B✔" if lane.has_skill(evo, "B") else ""
			evo_buttons[evo].text = "%s\n%s%s" % [d.short, Balance.TOWER_DEFS[d.tower].name, learned]
	if detail_view.visible and _detail_evo != "":
		var evo := _detail_evo
		for item in _detail_items:
			var b: Button = item.btn
			var stat: Dictionary = item.stat
			if item.kind == "learn":
				var lc := lane.learn_cost(evo)
				if lc < 0:
					b.text = "B %s\n배움 ✔" % Evolutions.skill_name(evo, "B")
					b.disabled = true
				else:
					b.text = "B %s\n배우기 %d골드" % [Evolutions.skill_name(evo, "B"), lc]
					b.disabled = lane.gold < lc
				continue
			var lv := lane.stat_level(evo, stat.s, stat.k)
			var cost := lane.stat_upgrade_cost(evo, stat.s, stat.k)
			var third := ""
			if lv >= Evolutions.MAX_LEVEL:
				third = "최대"
			elif stat.s == "B" and not lane.has_skill(evo, "B"):
				third = "B를 먼저 배우기"
			else:
				third = "→ %s  %d골드" % [Evolutions.stat_value_text(evo, stat, lv + 1), cost]
			b.text = "%s %s\nLv%d  %s\n%s" % [stat.s, stat.name, lv, Evolutions.stat_value_text(evo, stat, lv), third]
			b.disabled = cost < 0 or lane.gold < cost
	skill_hint_label.text = _hover_text(lane)


func _hover_text(lane: LaneController) -> String:
	if _hover.size() == 4:
		var evo: String = _hover[0]
		match _hover[1]:
			"evo":
				return Evolutions.tooltip(evo)
			"learn":
				return "B %s 배우기 (%d골드): %s" % [Evolutions.skill_name(evo, "B"),
					maxi(lane.learn_cost(evo), 0), Evolutions.skill_text(evo, "B", lane.levels_of(evo))]
			"stat":
				return "%s - %s: %s" % [Evolutions.evo_name(evo), _hover[2], Evolutions.skill_text(evo, _hover[2], lane.levels_of(evo))]
	if detail_view.visible:
		return "항목을 누르면 %s로 진화한 모든 타워가 강해집니다. 마우스를 올리면 설명." % Evolutions.evo_name(_detail_evo)
	return "계열을 고르면 그 계열의 업그레이드 항목이 나옵니다. 마우스를 올리면 설명."


func _create_minimaps():
	# 오른쪽 3x3 버튼 위에 축소 레인 화면을 겹쳐 그린다 (눌러서 레인 전환하는 기능은 그대로)
	for i in range(player_buttons.size()):
		_attach_minimap(player_buttons[i], i)
	_attach_minimap(boss_button, GameField.BOSS_LANE_ID)

func _attach_minimap(button: Button, lane_index: int):
	button.text = ""
	var view := MiniMapView.new()
	view.game_field = game_field
	view.lane_index = lane_index
	view.mouse_filter = Control.MOUSE_FILTER_IGNORE
	button.add_child(view)
	view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	button.gui_input.connect(_on_minimap_gui_input.bind(button, lane_index))

## 미니맵 조작
## - 다른 레인을 누르면: 그 레인으로 전환 (그 레인에서 마지막으로 보던 위치로 돌아간다)
## - 지금 보는 레인을 누르거나 누른 채 끌면: 누른 위치로 이동
func _on_minimap_gui_input(event: InputEvent, button: Button, lane_index: int):
	if event is InputEventMouseButton:
		if event.button_index != MOUSE_BUTTON_LEFT or not event.pressed:
			return
		if game_field.current_player_id != lane_index:
			game_field.switch_player(lane_index)
			return
	elif event is InputEventMouseMotion:
		if (event.button_mask & MOUSE_BUTTON_MASK_LEFT) == 0 or game_field.current_player_id != lane_index:
			return
	else:
		return

	# 미니맵 안에서 누른 높이 -> 레인의 몇 번째 줄인지 (MiniMapView의 안쪽 여백 2px 반영)
	var inner_h := button.size.y - 4.0
	var row := clampf((event.position.y - 2.0) / inner_h, 0.0, 1.0) * GridSystem.GRID_HEIGHT
	game_field.scroll_to_row(row)

func _create_hud():
	# 하단 상태 표시줄 (골드/생명/보스). 입력은 통과시킨다.
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.z_index = 100  # 타워/몬스터/이펙트(z_index 1~4)보다 항상 위에 그린다
	panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	hud_label = Label.new()
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_label.add_theme_font_size_override("font_size", 12)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	box.add_child(hud_label)

	# 선택한 타워 정보 + 업그레이드 버튼 (타워를 선택했을 때만 보인다)
	tower_info_row = HBoxContainer.new()
	tower_info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower_info_row.visible = false
	box.add_child(tower_info_row)
	tower_info_label = Label.new()
	tower_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower_info_label.add_theme_font_size_override("font_size", 12)
	tower_info_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	tower_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tower_info_label.custom_minimum_size = Vector2(230, 0)
	tower_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tower_info_row.add_child(tower_info_label)
	for i in range(2):
		var eb := Button.new()
		eb.add_theme_font_size_override("font_size", 12)
		eb.pressed.connect(_on_evolve_pressed.bind(i))
		tower_info_row.add_child(eb)
		evolve_buttons.append(eb)
	game_field.ui_blockers.append(tower_info_row)  # 버튼을 눌렀을 때 뒤의 맵이 클릭되지 않도록

	skill_hint_label = Label.new()
	skill_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_hint_label.visible = false
	skill_hint_label.add_theme_font_size_override("font_size", 12)
	skill_hint_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
	skill_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_hint_label.custom_minimum_size = Vector2(400, 0)
	box.add_child(skill_hint_label)

	add_child(panel)

	# 시작 버튼: 누르기 전에는 시간도 수입도 몬스터도 멈춰 있어서 미리 타워를 지어 둘 수 있다
	start_button = Button.new()
	start_button.text = "▶ 시작"
	start_button.add_theme_font_size_override("font_size", 28)
	start_button.z_index = 101
	start_button.custom_minimum_size = Vector2(200, 80)
	start_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)
	game_field.ui_blockers.append(start_button)

func _on_start_pressed():
	game_field.start_game()
	start_button.visible = false

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
	_update_tower_info(lane)
	if evo_view.visible or detail_view.visible:
		_refresh_upgrade_views(lane)

	var state_text := ""
	match boss.state:
		BossController.State.WAITING: state_text = "  [시작 대기]"
		BossController.State.VICTORY: state_text = "  [전체 승리!]"
		BossController.State.DEFEAT: state_text = "  [패배]"
	var selected := Balance.tower_kind(game_field.selected_tower_kind)
	# 보스 공격 현황: 보스 앞에 서 있는 몬스터들이 1초에 주는 피해의 합
	var attack_text := "보스를 공격 중인 몬스터 없음"
	if boss.total_dps > 0.0:
		var eta := boss.hp / boss.total_dps
		attack_text = "보스에게 초당 %.1f 피해 (%d마리) -> %d초 뒤 처치%s" % [
			boss.total_dps, boss.get_attacker_count(), ceili(eta), " (시간 부족!)" if eta > boss.time_left else ""]
	hud_label.text = "골드 %d (+%d/%.0fs, 다음 수입 %d초)  생명 %d  타워 %d개%s\n선택 타워: %s (%d골드)\nBOSS Lv.%d/%d %s  %d/%d  남은 %d초\n%s\n지금 오는 몬스터: %s" % [
		lane.gold, lane.income, Balance.INCOME_INTERVAL, ceili(lane.income_time_left()), lane.lives, lane.towers.size(), state_text,
		selected.name, selected.cost, boss.level, BossLevels.COUNT, boss.level_data.name,
		int(boss.hp), int(boss.max_hp), int(boss.time_left), attack_text, boss.current_wave_text]

func _update_tower_info(lane: LaneController):
	var t := game_field.get_selected_tower()
	if t == null:
		tower_info_row.visible = false
		return
	tower_info_row.visible = true
	var title: String = t.kind.name
	if t.evolution != "":
		title += " · " + Evolutions.evo_name(t.evolution)
	var text := "[%s] 한 발 %.2f / %.2f초 / 사거리 %.1f칸\n누적 피해 %.1f  킬 %d" % [
		title, t.cur_damage(), t.cur_cooldown(), t.kind.range, t.total_damage, t.kills]
	match t.evolution:
		"support":
			text += "\n공격력 없음: 표식 구름을 깐다"
		"skill":
			text += "\n공격력 없음: 공격이 맞으면 확률로 스킬 발동"
		"growth":
			text += "\n치명타 %.1f%%  광란 x%d" % [t.crit_chance() * 100.0, t.haste_stacks]
		"charge":
			text += "\n충전 %.1f / %.0f초 (%.0f초 이상이면 발동)" % [t.charge, t.charge_max(), Evolutions.CHARGE_MIN]
	tower_info_label.text = text

	# 아직 진화 전이면 계열 2개 중 하나를 고른다 (골드). 고르는 순간 A 스킬을 배운다.
	var can_pick := t.can_evolve()
	var choices: Array = Evolutions.TREE[t.kind.id]
	for i in range(evolve_buttons.size()):
		var eb := evolve_buttons[i]
		eb.visible = can_pick
		if not can_pick:
			continue
		var evo: String = choices[i]
		evolve_ids[i] = evo
		eb.text = "%s 진화 (%d골드)" % [Evolutions.evo_name(evo), Balance.EVOLVE_COST]
		eb.tooltip_text = Evolutions.tooltip(evo)
		eb.disabled = t.lane != lane or lane.gold < Balance.EVOLVE_COST


func _on_evolve_pressed(index: int):
	game_field.evolve_selected_tower(evolve_ids[index])


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
	_show_view("tower")

func _on_tower_back_pressed():
	_show_view("main")

func _on_tower_kind_selected(kind_id: String):
	if game_field:
		game_field.set_tower_kind(kind_id)
		game_field.set_current_tool(GameField.PlacementTool.TOWER)
	_show_view("main")

func _on_monster_button_pressed():
	# 몬스터 뷰로 전환
	Log.info(Log.Category.UI, "몬스터 배럭 열기")
	_show_view("monster")

func _on_empty2_button_pressed():
	# 업그레이드 탭 열기 (건설 도구 취소는 마우스 우클릭)
	Log.info(Log.Category.UI, "업그레이드 탭 열기")
	_show_view("upgrade")

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
	_show_view("main")

# 몬스터 선택 핸들러
func _on_monster_selected(button_index: int):
	var slot_idx := button_index - 1
	if slot_idx < 0 or slot_idx >= SentMonsters.SLOTS.size() or SentMonsters.SLOTS[slot_idx] == "":
		return  # 쓰지 않는 칸 / 계열 사이 빈칸
	var kind_id: String = SentMonsters.SLOTS[slot_idx]
	Log.info(Log.Category.UI, "몬스터 생산 요청: %s" % kind_id)
	game_field.send_monster(kind_id)