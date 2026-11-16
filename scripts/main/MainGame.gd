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

var hud_panel: PanelContainer            # 하단 메시지 영역 (할 말이 있을 때만 보인다)
var hud_label: Label
var tower_info_row: VBoxContainer        # 선택한 타워 정보 + (진화 전이면) 진화 버튼 줄
var evolve_row: HBoxContainer
var start_button: Button
var confirm_dialog: ConfirmationDialog   # 타워를 지으면 길이 막힐 때 확인창
var _pending_cell := Vector2i.ZERO
var tower_buttons: Dictionary = {}       # 기본 타워 종류 -> 타워 배럭 버튼
var _highlighted_kind := ""              # 지금 강조 표시 중인 건설 타워 종류
# 왼쪽 위 상태 패널 (위에서 아래로: 생명 / 골드·수입 / 다음 웨이브)
var status_lives_label: Label
var status_gold_label: Label
var status_income_label: Label
var status_wave_title: Label
var status_wave_rows: Array = []         # [{dot: StatusIcon, label: Label}]
var family_frames: Control               # 몬스터 배럭의 계열 묶음 외곽선
var tower_info_label: Label
var evolve_buttons: Array[Button] = []   # 선택한 타워가 아직 진화 전이면 계열 2개 중 고르는 버튼
var learn_button: Button                 # 선택한 타워가 진화했고 B 스킬을 아직 안 배웠으면 나오는 "B 스킬 배우기" 버튼
var evolve_ids: Array[String] = ["", ""]
var skill_hint_label: Label              # 업그레이드 탭에서 마우스를 올린 항목의 설명
var upgrade_menu: HBoxContainer          # 업그레이드 탭: [←] [타워] [색깔]
var evo_view: HBoxContainer              # 타워 업그레이드 1단계: [←] + 4x2 격자 (진화 계열 8개 중 고르기)
var evo_buttons: Dictionary = {}         # 계열 -> Button
var evo_frames: Control                  # 계열 선택 화면에서 같은 기본 타워의 두 계열을 묶는 외곽선
var detail_view: HBoxContainer           # 타워 업그레이드 2단계: [←] + 4x2 격자 (고른 계열의 업그레이드 항목들)
var detail_grid: GridContainer
var _detail_evo := ""                    # 지금 보고 있는 계열
var _detail_items: Array = []            # [{btn, stat: Dictionary}]
var _hover: Array = []                   # 마우스가 올라간 항목: [계열, 종류("evo"/"stat"), 스킬, 키]
var tower_view: GridContainer
var _hud_timer := 0.0
var _flash_text := ""                    # 하단에 잠깐 띄우는 설명 (건설할 타워를 고른 직후 등. 폰에는 툴팁이 없다)
var _flash_time := 0.0

# 글자 크기 (화면 폭 600 기준. 폰에서는 1칸이 약 0.65dp라서 이 정도는 돼야 읽힌다)
const FONT_BODY := 20
const FONT_SMALL := 16
const FONT_TINY := 14
const TOP_HEIGHT := 180.0                # 위쪽 UI 줄 높이 (MainGame.tscn의 TopUI와 같아야 한다)
const SHEET_HEIGHT := 390.0              # 몬스터/업그레이드 화면 높이
const MIN_TOUCH := 56.0                  # 눌러야 하는 버튼의 최소 높이

var sheet: PanelContainer                # 위쪽 UI 아래로 내려오는 넓은 화면 (몬스터 배럭 / 업그레이드). 맵 위에 겹친다
var sheet_content: Control               # 그 안의 화면들이 들어가는 자리
var cancel_build_button: Button          # 건설 모드 취소 (폰에는 우클릭이 없다)
var restart_button: Button               # 승리/패배 후 다시 시작 (폰에는 R 키가 없다)

# 플레이어 버튼들
@onready var player_buttons: Array[Button] = []
@onready var monster_buttons: Array[Button] = []

func _ready():
	Log.info(Log.Category.GAME, "MainGame 시작")
	var ui_theme := Theme.new()
	ui_theme.default_font_size = FONT_SMALL  # 기본 글자(버튼 등)를 폰에서도 읽히는 크기로
	theme = ui_theme
	setup_ui()
	connect_signals()
	_apply_safe_area()
	get_viewport().size_changed.connect(_apply_safe_area)


## 폰의 노치/상태바/제스처 바에 UI가 가리지 않도록 위아래에 안전 여백을 둔다 (폰에서만)
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0:
		return
	var s := get_viewport_rect().size.x / win.x  # 화면 픽셀 -> 가상 화면 좌표
	var top := maxf(0.0, safe.position.y * s)
	var bottom := maxf(0.0, (win.y - safe.end.y) * s)
	$VBoxContainer.offset_top = top
	$VBoxContainer.offset_bottom = -bottom
	sheet.offset_top = top + TOP_HEIGHT
	sheet.offset_bottom = top + TOP_HEIGHT + SHEET_HEIGHT
	cancel_build_button.offset_top = top + TOP_HEIGHT + 8.0
	cancel_build_button.offset_bottom = top + TOP_HEIGHT + 8.0 + MIN_TOUCH
	hud_panel.offset_bottom = -bottom

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
	for b in [tower_button, monster_button, empty2_button]:
		b.add_theme_font_size_override("font_size", FONT_BODY)
	_create_sheet()
	_setup_monster_buttons()
	_create_family_frames()
	_create_tower_view()
	_create_upgrade_views()
	_create_minimaps()
	_create_hud()
	_create_status_panel()
	_create_confirm_dialog()

## 위쪽 UI 줄 아래로 내려오는 넓은 화면. 몬스터 배럭과 업그레이드 화면이 여기에 뜬다
## (좁은 왼쪽 칸에 몰아 넣으면 폰에서 버튼이 너무 작아서, 화면 폭 전체를 쓴다. 맵 위에 겹치고 닫으면 사라진다)
func _create_sheet() -> void:
	sheet = PanelContainer.new()
	sheet.visible = false
	sheet.z_index = 90  # 타워/몬스터(z_index 1~4)보다 위
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.1, 0.1, 0.14)
	style.border_color = Color(0.35, 0.35, 0.45)
	style.set_border_width_all(2)
	style.set_content_margin_all(4)
	sheet.add_theme_stylebox_override("panel", style)
	sheet.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	sheet.offset_top = TOP_HEIGHT
	sheet.offset_bottom = TOP_HEIGHT + SHEET_HEIGHT
	add_child(sheet)
	var box := VBoxContainer.new()
	sheet.add_child(box)
	sheet_content = Control.new()
	sheet_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(sheet_content)
	# 설명 줄: 폰에는 마우스를 올려서 보는 툴팁이 없어서, 방금 누른 항목의 설명을 여기에 보여준다
	skill_hint_label = Label.new()
	skill_hint_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_hint_label.add_theme_font_size_override("font_size", FONT_SMALL)
	skill_hint_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
	skill_hint_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	skill_hint_label.custom_minimum_size = Vector2(0, 124)
	skill_hint_label.clip_text = true
	box.add_child(skill_hint_label)
	monster_view.reparent(sheet_content, false)
	monster_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	game_field.ui_blockers.append(sheet)


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
	cost_label.add_theme_font_size_override("font_size", FONT_SMALL)
	cost_label.add_theme_color_override("font_color", Color(1.0, 0.92, 0.4))
	cost_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	cost_label.add_theme_constant_override("outline_size", 5)
	cost_label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cost_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	b.add_child(cost_label)
	cost_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)

	if tag != "":  # 계열 이름표 (왼쪽 위)
		var tag_label := Label.new()
		tag_label.text = tag
		tag_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		tag_label.add_theme_font_size_override("font_size", FONT_TINY - 1)
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
	var left_panel: Control = sheet_content
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
	back.add_theme_font_size_override("font_size", 28)
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
		tower_buttons[kind_id] = b
		var icon := UnitIcon.new()
		icon.show_tower(kind)
		_decorate_unit_button(b, icon, kind.cost, Balance.tower_tooltip(kind))

## 업그레이드 탭 (타워 / 색깔).
## 타워 탭: 진화 계열 8개 중 하나를 고르면 그 계열의 업그레이드 항목(관통 수, 독 피해 ...)이 나오고,
## 항목을 올리면 그 계열로 진화한 모든 타워가 강해진다 (계열 공통). 색깔 탭은 아직 기획이 없어서 자리만 만들어 두었다.
## (진화와 B 스킬 배우기는 타워마다 개별: 타워를 선택하면 나오는 버튼으로 한다.)
## 타워 탭의 두 화면은 모두 [←] 한 칸 + 4x2 격자로 보여준다.
func _create_upgrade_views():
	var left_panel: Control = sheet_content

	upgrade_menu = HBoxContainer.new()
	upgrade_menu.visible = false
	left_panel.add_child(upgrade_menu)
	upgrade_menu.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := _make_back_column("upgrade_back")
	back.pressed.connect(_show_view.bind("main"))
	upgrade_menu.add_child(back)
	var tower_tab := _make_view_button("타워", 26)
	tower_tab.pressed.connect(_show_view.bind("evos"))
	upgrade_menu.add_child(tower_tab)
	var color_tab := _make_view_button("색깔", 26)
	color_tab.disabled = true
	color_tab.tooltip_text = "색깔별 업그레이드 (준비 중)"
	upgrade_menu.add_child(color_tab)

	# 1단계: 진화 계열 8개 (4x2). 윗줄 = 장거리 2 + 범위 2, 아랫줄 = 대공 2 + 트랩 2
	evo_view = HBoxContainer.new()
	evo_view.visible = false
	left_panel.add_child(evo_view)
	evo_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var evo_back := _make_back_column("evos_back")
	evo_back.pressed.connect(_show_view.bind("upgrade"))
	evo_view.add_child(evo_back)
	var evo_grid := GridContainer.new()
	evo_grid.columns = 4
	evo_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	evo_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	evo_view.add_child(evo_grid)
	for evo in Evolutions.ORDER:
		var eb := _make_view_button("", FONT_SMALL)
		eb.add_theme_color_override("font_color", Evolutions.DATA[evo].color)
		eb.pressed.connect(_open_evo_detail.bind(evo))
		eb.button_down.connect(func(): _hover = [evo, "evo", "", ""])
		eb.mouse_entered.connect(func(): _hover = [evo, "evo", "", ""])
		eb.mouse_exited.connect(func(): _hover = [])
		evo_grid.add_child(eb)
		evo_buttons[evo] = eb

	# 같은 기본 타워의 두 계열(장거리 2개, 범위 2개 ...)을 그 타워 색 외곽선으로 묶는다
	var frames := FamilyFrames.new()
	evo_frames = frames
	frames.visible = false
	left_panel.add_child(frames)
	frames.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for tower_id in Evolutions.TREE:
		var pair: Array[Button] = []
		for evo in Evolutions.TREE[tower_id]:
			pair.append(evo_buttons[evo])
		frames.groups.append({"buttons": pair, "color": Balance.TOWER_DEFS[tower_id].color})

	# 2단계: 항목 버튼 (계열마다 항목이 달라서 열 때마다 새로 만든다. 4x2 격자)
	detail_view = HBoxContainer.new()
	detail_view.visible = false
	left_panel.add_child(detail_view)
	detail_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var detail_back := _make_back_column("detail_back")
	detail_back.pressed.connect(_show_view.bind("evos"))
	detail_view.add_child(detail_back)
	detail_grid = GridContainer.new()
	detail_grid.columns = 4
	detail_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	detail_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	detail_view.add_child(detail_grid)


func _make_view_button(text: String, font_size: int = FONT_BODY) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.size_flags_vertical = Control.SIZE_EXPAND_FILL
	b.clip_text = true  # 글자가 길어도 칸 폭을 넘겨서 옆 칸/미니맵을 밀어내지 않게 한다
	b.add_theme_font_size_override("font_size", font_size)
	return b


## 4x2 격자 왼쪽에 붙는 좁은 [←] 버튼 (격자 칸을 차지하지 않게 따로 둔다)
func _make_back_column(_id: String) -> Button:
	var b := _make_view_button("←", 28)
	b.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	b.custom_minimum_size = Vector2(64, 0)
	return b


## 왼쪽 패널에 보여줄 화면을 하나만 켠다: main / tower / monster / upgrade / evos / detail
func _show_view(view: String) -> void:
	var in_sheet := view in ["monster", "upgrade", "evos", "detail"]
	main_view.visible = view == "main" or in_sheet  # 넓은 화면이 열려 있어도 윗줄 버튼으로 바로 다른 화면으로 갈 수 있다
	tower_view.visible = view == "tower"
	sheet.visible = in_sheet
	monster_view.visible = view == "monster"
	family_frames.visible = view == "monster"
	upgrade_menu.visible = view == "upgrade"
	evo_view.visible = view == "evos"
	evo_frames.visible = view == "evos"
	detail_view.visible = view == "detail"
	_hover = []
	if view == "monster":
		skill_hint_label.text = "몬스터를 누르면 바로 보냅니다.
누른 몬스터의 설명이 여기에 나옵니다."
	elif view == "upgrade":
		skill_hint_label.text = "업그레이드 종류를 고르세요."


## 고른 계열의 업그레이드 항목 화면을 만든다 (A 항목들, 이어서 B 항목들)
func _open_evo_detail(evo: String) -> void:
	_detail_evo = evo
	_detail_items.clear()
	for c in detail_grid.get_children():
		detail_grid.remove_child(c)
		c.queue_free()
	var color: Color = Evolutions.DATA[evo].color
	for stat in Evolutions.STATS[evo]:
		_add_detail_button(evo, stat, color)
	_show_view("detail")
	_refresh_now()


func _add_detail_button(evo: String, stat: Dictionary, color: Color) -> void:
	var b := _make_view_button("", FONT_SMALL - 1)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.55))
	b.pressed.connect(_on_stat_pressed.bind(evo, stat.s, stat.k))
	b.button_down.connect(func(): _hover = [evo, "stat", stat.s, stat.k])  # 폰: 누르면 그 항목 설명이 뜬다
	b.mouse_entered.connect(func(): _hover = [evo, "stat", stat.s, stat.k])
	b.mouse_exited.connect(func(): _hover = [])
	detail_grid.add_child(b)
	_detail_items.append({"btn": b, "stat": stat})


func _on_stat_pressed(evo: String, skill: String, key: String) -> void:
	game_field.upgrade_stat(evo, skill, key)
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
			evo_buttons[evo].text = "%s\n(%s)\nA %s\nB %s" % [d.name, Balance.TOWER_DEFS[d.tower].name, d.a_name, d.b_name]
	if detail_view.visible and _detail_evo != "":
		var evo := _detail_evo
		for item in _detail_items:
			var b: Button = item.btn
			var stat: Dictionary = item.stat
			var lv := lane.stat_level(evo, stat.s, stat.k)
			var cost := lane.stat_upgrade_cost(evo, stat.s, stat.k)
			var nxt := "최대" if lv >= Evolutions.MAX_LEVEL else "→ %s\n%d골드" % [Evolutions.stat_value_text(evo, stat, lv + 1), cost]
			b.text = "%s %s\nLv%d  %s\n%s" % [stat.s, stat.name, lv, Evolutions.stat_value_text(evo, stat, lv), nxt]
			b.disabled = cost < 0 or lane.gold < cost
	skill_hint_label.text = _hover_text(lane)


func _hover_text(lane: LaneController) -> String:
	if _hover.size() == 4:
		var evo: String = _hover[0]
		match _hover[1]:
			"evo":
				return Evolutions.tooltip(evo)
			"stat":
				var text := "%s - %s: %s" % [Evolutions.evo_name(evo), _hover[2], Evolutions.skill_text(evo, _hover[2], lane.levels_of(evo))]
				if _hover[2] == "B":
					text += "\n(B 스킬을 배운 타워에만 효과가 있다)"
				return text
	if detail_view.visible:
		return "%s
(항목을 누르면 이 계열 모든 타워가 강해집니다)" % Evolutions.tooltip(_detail_evo)
	return "계열을 고르면 그 계열의 업그레이드 항목이 나옵니다."


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
	hud_label.add_theme_font_size_override("font_size", FONT_SMALL)
	hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_label.custom_minimum_size = Vector2(540, 0)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(box)
	box.add_child(hud_label)

	# 선택한 타워 정보 (타워를 선택했을 때만 보인다). 진화 버튼 2개는 정보 아래 별도 줄에 반반씩 놓는다
	# (같은 줄에 두면 이름이 긴 계열에서 두 번째 버튼이 화면 밖으로 밀려난다)
	tower_info_row = VBoxContainer.new()
	tower_info_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower_info_row.visible = false
	box.add_child(tower_info_row)
	tower_info_label = Label.new()
	tower_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower_info_label.add_theme_font_size_override("font_size", FONT_SMALL)
	tower_info_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	tower_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tower_info_label.custom_minimum_size = Vector2(540, 0)
	tower_info_row.add_child(tower_info_label)
	evolve_row = HBoxContainer.new()
	evolve_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower_info_row.add_child(evolve_row)
	for i in range(2):
		var eb := Button.new()
		eb.add_theme_font_size_override("font_size", FONT_SMALL)
		eb.custom_minimum_size = Vector2(0, MIN_TOUCH)
		eb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		eb.clip_text = true
		eb.pressed.connect(_on_evolve_pressed.bind(i))
		evolve_row.add_child(eb)
		evolve_buttons.append(eb)
	learn_button = Button.new()
	learn_button.add_theme_font_size_override("font_size", FONT_SMALL)
	learn_button.custom_minimum_size = Vector2(0, MIN_TOUCH)
	learn_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	learn_button.clip_text = true
	learn_button.visible = false
	learn_button.pressed.connect(_on_learn_selected_pressed)
	evolve_row.add_child(learn_button)
	game_field.ui_blockers.append(tower_info_row)  # 버튼을 눌렀을 때 뒤의 맵이 클릭되지 않도록

	hud_panel = panel
	add_child(panel)

	# 시작 버튼: 누르기 전에는 시간도 수입도 몬스터도 멈춰 있어서 미리 타워를 지어 둘 수 있다
	start_button = Button.new()
	start_button.text = "▶ 시작"
	start_button.add_theme_font_size_override("font_size", 32)
	start_button.z_index = 101
	start_button.custom_minimum_size = Vector2(260, 100)
	_center_button(start_button)
	start_button.pressed.connect(_on_start_pressed)
	add_child(start_button)
	game_field.ui_blockers.append(start_button)

	# 승리/패배 뒤 다시 시작 (폰에는 R 키가 없다)
	restart_button = Button.new()
	restart_button.text = "↻ 다시 하기"
	restart_button.visible = false
	restart_button.add_theme_font_size_override("font_size", 32)
	restart_button.z_index = 101
	restart_button.custom_minimum_size = Vector2(260, 100)
	_center_button(restart_button)
	restart_button.pressed.connect(reset_game)
	add_child(restart_button)
	game_field.ui_blockers.append(restart_button)

	# 건설 모드 취소 (폰에는 우클릭이 없다). 건설 모드일 때만 위쪽 UI 줄 아래 오른쪽에 뜬다
	cancel_build_button = Button.new()
	cancel_build_button.text = "✕ 건설 취소"
	cancel_build_button.visible = false
	cancel_build_button.add_theme_font_size_override("font_size", FONT_BODY)
	cancel_build_button.z_index = 95
	cancel_build_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	cancel_build_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	cancel_build_button.offset_left = -190
	cancel_build_button.offset_right = -8
	cancel_build_button.offset_top = TOP_HEIGHT + 8.0
	cancel_build_button.offset_bottom = TOP_HEIGHT + 8.0 + MIN_TOUCH
	cancel_build_button.pressed.connect(func(): game_field.set_current_tool(GameField.PlacementTool.NONE))
	add_child(cancel_build_button)
	game_field.ui_blockers.append(cancel_build_button)

func _center_button(b: Button) -> void:
	b.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	b.grow_horizontal = Control.GROW_DIRECTION_BOTH
	b.grow_vertical = Control.GROW_DIRECTION_BOTH


## 지금 건설하려고 고른 타워를 타워 배럭에서 굵은 노란 테두리로 강조한다 (건설 도구가 꺼지면 해제).
## 메인 화면의 "타워" 버튼에도 고른 타워 이름을 보여준다.
func _refresh_tower_highlight() -> void:
	if game_field == null or tower_buttons.is_empty():
		return
	var kind := ""
	if game_field.current_tool == GameField.PlacementTool.TOWER:
		kind = game_field.selected_tower_kind
	if kind == _highlighted_kind:
		return
	_highlighted_kind = kind
	for k in tower_buttons:
		var b: Button = tower_buttons[k]
		for state in ["normal", "hover", "pressed"]:
			if k == kind:
				var sb := StyleBoxFlat.new()
				sb.bg_color = Color(0.32, 0.27, 0.05)
				sb.border_color = Color(1.0, 0.9, 0.2)
				sb.set_border_width_all(4)
				sb.set_corner_radius_all(4)
				b.add_theme_stylebox_override(state, sb)
			else:
				b.remove_theme_stylebox_override(state)
	tower_button.text = "타워" if kind == "" else "타워\n(%s)" % Balance.TOWER_DEFS[kind].name


## 왼쪽 위 상태 패널: 위에서 아래로 생명(하트) / 골드와 수입 / 다음 웨이브
func _create_status_panel() -> void:
	var top_row: HBoxContainer = $VBoxContainer/TopUI/HBoxContainer
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(160, 0)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	var panel_style := StyleBoxFlat.new()  # 글자가 가장자리에 붙지 않도록 안쪽 여백
	panel_style.bg_color = Color(0.1, 0.1, 0.14)
	panel_style.content_margin_left = 6
	panel_style.content_margin_right = 4
	panel_style.content_margin_top = 4
	panel_style.content_margin_bottom = 4
	panel.add_theme_stylebox_override("panel", panel_style)
	top_row.add_child(panel)
	top_row.move_child(panel, 0)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)

	var heart_row := HBoxContainer.new()
	box.add_child(heart_row)
	heart_row.add_child(_status_icon("heart", Color(0.95, 0.2, 0.3)))
	status_lives_label = _status_label(FONT_BODY)
	status_lives_label.add_theme_color_override("font_color", Color(1.0, 0.55, 0.6))
	heart_row.add_child(status_lives_label)

	var gold_row := HBoxContainer.new()
	box.add_child(gold_row)
	gold_row.add_child(_status_icon("coin", Color(1.0, 0.85, 0.2)))
	status_gold_label = _status_label(FONT_BODY)
	status_gold_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.35))
	gold_row.add_child(status_gold_label)
	status_income_label = _status_label(FONT_TINY)
	status_income_label.add_theme_color_override("font_color", Color(0.9, 0.85, 0.5))
	box.add_child(status_income_label)

	status_wave_title = _status_label(FONT_TINY)
	status_wave_title.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	box.add_child(status_wave_title)
	for i in range(Balance.WAVE_GROUPS):
		var row := HBoxContainer.new()
		box.add_child(row)
		var dot := _status_icon("dot", Color.WHITE, 12)
		row.add_child(dot)
		var label := _status_label(FONT_TINY)
		row.add_child(label)
		status_wave_rows.append({"row": row, "dot": dot, "label": label})


func _status_label(size: int) -> Label:
	var l := Label.new()
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_font_size_override("font_size", size)
	return l


func _status_icon(kind: String, color: Color, px: int = 24) -> StatusIcon:
	var icon := StatusIcon.new()
	icon.kind = kind
	icon.color = color
	icon.custom_minimum_size = Vector2(px, px)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return icon


func _update_status_panel(lane: LaneController, boss: BossController) -> void:
	status_lives_label.text = "%d" % lane.lives
	status_gold_label.text = "%d" % lane.gold
	var left := lane.income_time_left() if boss.state == BossController.State.RUNNING else -1.0
	status_income_label.text = "수입 +%d %s" % [lane.income, "(%d초)" % ceili(left) if left >= 0.0 else "(대기)"]

	var preview := boss.get_next_wave_preview()
	var wave_left := boss.time_to_next_wave()
	status_wave_title.text = "다음 웨이브 %s" % ("%d초" % ceili(wave_left) if wave_left >= 0.0 else "(대기)")
	for i in range(status_wave_rows.size()):
		var r: Dictionary = status_wave_rows[i]
		r.row.visible = i < preview.size()
		if i < preview.size():
			var e: Dictionary = preview[i]
			r.dot.color = e.color
			r.dot.queue_redraw()
			r.label.text = "%s x%d%s" % [e.name, e.count, "(공)" if e.flying else ""]


## 타워를 지으면 길이 완전히 막힐 때 한 번 확인하는 창
func _create_confirm_dialog() -> void:
	confirm_dialog = ConfirmationDialog.new()
	confirm_dialog.title = "길이 막힙니다"
	confirm_dialog.dialog_text = "이 타워를 지으면 몬스터가 지나갈 길이 완전히 막힙니다.\n막히면 몬스터가 타워를 부수면서 뚫고 옵니다.\n그래도 지을까요?"
	confirm_dialog.dialog_autowrap = true
	confirm_dialog.ok_button_text = "지을래요"
	confirm_dialog.cancel_button_text = "취소"
	confirm_dialog.min_size = Vector2i(520, 0)
	confirm_dialog.add_theme_constant_override("buttons_min_width", 160)
	confirm_dialog.add_theme_constant_override("buttons_min_height", 64)
	confirm_dialog.get_label().add_theme_font_size_override("font_size", FONT_BODY)
	for b in [confirm_dialog.get_ok_button(), confirm_dialog.get_cancel_button()]:
		b.add_theme_font_size_override("font_size", FONT_BODY)
		b.custom_minimum_size = Vector2(160, 64)
	confirm_dialog.confirmed.connect(_on_path_block_confirmed)
	add_child(confirm_dialog)
	game_field.path_block_confirm.connect(_on_path_block_confirm)


func _on_path_block_confirm(cell: Vector2i) -> void:
	_pending_cell = cell
	confirm_dialog.popup_centered()


func _on_path_block_confirmed() -> void:
	game_field.place_tower(_pending_cell, true)


## 상태 패널용 작은 아이콘 (하트 / 금화 / 점). 글꼴에 이모지가 없어도 보이도록 직접 그린다.
class StatusIcon extends Control:
	var kind := "dot"
	var color := Color.WHITE

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		var c := size * 0.5
		var r := minf(size.x, size.y) * 0.5
		match kind:
			"heart":
				draw_circle(c + Vector2(-r * 0.42, -r * 0.25), r * 0.5, color)
				draw_circle(c + Vector2(r * 0.42, -r * 0.25), r * 0.5, color)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(-r * 0.88, -r * 0.05), c + Vector2(r * 0.88, -r * 0.05), c + Vector2(0, r * 0.9)]), color)
			"coin":
				draw_circle(c, r * 0.9, color)
				draw_arc(c, r * 0.9, 0.0, TAU, 20, Color(0.55, 0.4, 0.0), 1.5)
				draw_arc(c, r * 0.5, 0.0, TAU, 16, Color(0.75, 0.55, 0.05), 1.5)
			_:
				draw_circle(c, r * 0.8, color)
				draw_arc(c, r * 0.8, 0.0, TAU, 12, Color(0, 0, 0, 0.5), 1.0)


func _on_start_pressed():
	game_field.start_game()
	start_button.visible = false

func _process(delta):
	_flash_time -= delta
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

	_update_status_panel(lane, boss)
	_refresh_tower_highlight()

	# 하단 메시지: 상태, 그리고 보스 정보는 보스 레인을 보고 있을 때만 (다른 건 왼쪽 위 상태 패널로 옮겼다)
	var lines: Array[String] = []
	match boss.state:
		BossController.State.WAITING: lines.append("[시작 대기]")
		BossController.State.VICTORY: lines.append("[전체 승리!]")
		BossController.State.DEFEAT: lines.append("[패배]")
	if game_field.current_player_id == GameField.BOSS_LANE_ID:
		lines.append("BOSS Lv.%d/%d %s  %d/%d  남은 %d초" % [
			boss.level, BossLevels.COUNT, boss.level_data.name, int(boss.hp), int(boss.max_hp), int(boss.time_left)])
		# 보스 공격 현황: 보스 앞에 서 있는 몬스터들이 1초에 주는 피해의 합
		if boss.total_dps > 0.0:
			var eta := boss.hp / boss.total_dps
			lines.append("보스에게 초당 %.1f 피해 (%d마리) -> %d초 뒤 처치%s" % [
				boss.total_dps, boss.get_attacker_count(), ceili(eta), " (시간 부족!)" if eta > boss.time_left else ""])
		else:
			lines.append("보스를 공격 중인 몬스터 없음")
	if _flash_time > 0.0 and game_field.current_tool == GameField.PlacementTool.TOWER:
		lines.append(_flash_text)
	hud_label.text = "\n".join(lines)
	hud_label.visible = not lines.is_empty()
	hud_panel.visible = hud_label.visible or tower_info_row.visible
	cancel_build_button.visible = game_field.current_tool == GameField.PlacementTool.TOWER and not sheet.visible
	restart_button.visible = boss.state == BossController.State.VICTORY or boss.state == BossController.State.DEFEAT

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
	# 스킬 현황: 진화하면 A 스킬이 붙고, B 스킬은 돈을 내고 배워야 한다 (계열 전체 타워에 적용)
	var b_known := t.evolution != "" and t.b_learned
	if t.evolution != "":
		var evo_data: Dictionary = Evolutions.DATA[t.evolution]
		text += "\nA %s ✔   B %s %s" % [evo_data.a_name, evo_data.b_name, "✔" if b_known else "(아직 안 배움)"]
	tower_info_label.text = text

	# 아직 진화 전이면 계열 2개 중 하나를 고른다 (골드). 진화하면 그 계열의 A 스킬이 붙는다.
	var can_pick := t.can_evolve()
	# 진화했는데 B 스킬을 안 배웠으면 여기서 바로 배울 수 있다 (업그레이드 탭에서도 가능)
	var can_learn := t.evolution != "" and not b_known
	learn_button.visible = can_learn
	if can_learn:
		var lc := lane.learn_cost(t)
		learn_button.text = "B %s 배우기 (%d골드)" % [Evolutions.skill_name(t.evolution, "B"), lc]
		learn_button.tooltip_text = "B %s: %s\n이 타워만 배웁니다 (타워마다 따로). 항목 업그레이드는 계열 공통." % [
			Evolutions.skill_name(t.evolution, "B"), Evolutions.skill_text(t.evolution, "B", lane.levels_of(t.evolution))]
		learn_button.disabled = t.lane != lane or lane.gold < lc
	evolve_row.visible = can_pick or can_learn
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


## 선택한 타워의 "B 스킬 배우기" (진화처럼 타워마다 개별, 골드)
func _on_learn_selected_pressed():
	game_field.learn_selected_tower_skill()


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
		monster_buttons[0].text = "←"
		monster_buttons[0].add_theme_font_size_override("font_size", 28)
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

## 폰의 뒤로 가기: 열린 화면 닫기 -> 건설 모드 끄기 -> 타워 선택 해제 -> 그래도 없으면 종료
func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_GO_BACK_REQUEST:
		return
	if sheet.visible or tower_view.visible:
		_show_view("main")
	elif game_field.current_tool != GameField.PlacementTool.NONE:
		game_field.set_current_tool(GameField.PlacementTool.NONE)
	elif game_field.get_selected_tower() != null:
		game_field.select_tower(null)
	else:
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

## 건설할 타워를 고른다. 화면은 그대로 두고 고른 타워를 강조해서 보여준다 (← 로 돌아간다).
func _on_tower_kind_selected(kind_id: String):
	if game_field:
		# 이미 고른 타워를 한 번 더 누르면 건설 모드 해제 (폰에는 우클릭이 없다)
		if game_field.current_tool == GameField.PlacementTool.TOWER and game_field.selected_tower_kind == kind_id:
			game_field.set_current_tool(GameField.PlacementTool.NONE)
		else:
			game_field.set_tower_kind(kind_id)
			game_field.set_current_tool(GameField.PlacementTool.TOWER)
			_flash_text = Balance.tower_tooltip(Balance.tower_kind(kind_id))
			_flash_time = 6.0
	_refresh_tower_highlight()

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
	skill_hint_label.text = SentMonsters.tooltip(kind_id)
	Log.info(Log.Category.UI, "몬스터 생산 요청: %s" % kind_id)
	game_field.send_monster(kind_id)