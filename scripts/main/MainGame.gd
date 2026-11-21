extends Control
class_name MainGame

@onready var game_field: GameField = $VBoxContainer/GameField
@onready var main_view: HBoxContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView
@onready var monster_view: GridContainer = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MonsterView

@onready var tower_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/TowerButton
@onready var monster_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/MonsterButton
@onready var empty2_button: Button = $VBoxContainer/TopUI/HBoxContainer/LeftPanel/MainView/Empty2Button
@onready var boss_button: Button = $VBoxContainer/TopUI/HBoxContainer/RightPanel/BonusButton

# 몬스터 버튼은 monster_buttons[0]이 뒤로 가기, [1]부터 지금 고른 유형의 Monsters.SLOTS 순서대로 몬스터 종류 (계열별로 묶고 사이에 빈칸).

var hud_panel: PanelContainer            # 맵 아래 별도 메시지 영역 (항상 보이고, 높이는 BOTTOM_HEIGHT로 고정)
var hud_label: Label
var hud_box: VBoxContainer               # 하단 메시지 영역 안의 세로 줄 (알림 / 설명 / 타워 정보 / 상태)
var explain_label: Label                 # 지금 고른 타워/몬스터/업그레이드 항목의 설명 (고르기만 하고 바로 실행하지 않는다)
var left_panel: Control                  # 상단 왼쪽 칸: 여기서 화면(메인/타워/몬스터/업그레이드)이 바뀐다
var map_overlay: Control                 # 맵 왼쪽 위에 겹치는 상태 표시 (생명/골드/수입 + 다음 웨이브). 입력은 통과
var tower_sel_view: HBoxContainer        # 맵에서 타워를 눌렀을 때 상단에 나오는 화면: [←] + 진화/B 스킬/색깔 바꾸기
var _view := "main"                      # 상단에 지금 보이는 화면
var _sel: Array = []                     # 고른 업그레이드 항목: [계열, "stat", 스킬, 키] 또는 [색, "color", "", ""]
var _sel_monster := ""                   # 고른 몬스터 종류 (생성 버튼으로 보낸다)
var action_buttons: Array[Button] = []   # 미니맵 바로 왼쪽 우하단의 [생성]/[업그레이드] 버튼 (화면마다 하나씩, 같은 일을 한다)
var detail_action: Button
var color_action: Button
var monster_action: Button
var pause_button: Button                 # 맵 오른쪽 위의 [시작/일시정지] 버튼 (시작 전에는 ▶, 시작한 뒤에는 ⏸ 아이콘)
var pause_icon: PauseIcon
const PAUSE_SIZE := 48.0
var confirm_dialog: ConfirmationDialog   # 타워를 지으면 길이 막힐 때 확인창
var _pending_cell := Vector2i.ZERO
var tower_buttons: Dictionary = {}       # 기본 타워 종류 -> 타워 배럭 버튼
var _highlighted_kind := ""              # 지금 강조 표시 중인 건설 타워 종류
# 왼쪽 위 상태 패널 (위에서 아래로: 생명 / 골드·수입 / 다음 웨이브)
var status_lives_label: Label
var status_gold_label: Label
var status_income_label: Label
var status_wave_title: Label
var status_affix_label: Label            # 다음 웨이브에 변형(돌격/부활/공습)이 붙으면 표시
var status_guard_label: Label            # 비늘 보호막이 보스 피해를 얼마나 줄이는지
var status_wave_rows: Array = []         # [{dot: StatusIcon, label: Label}]
var family_frames: Control               # 몬스터 배럭의 계열 묶음 외곽선
var monster_type_view: HBoxContainer     # 몬스터 1단계: [←] + 4x2 격자 (유형 4개 + 빈칸 4개)
var _monster_category := ""              # 지금 열려 있는 몬스터 유형
var _monster_slots: Array = []           # 지금 열려 있는 유형의 칸 배치 (monster_buttons[i+1] = _monster_slots[i])
var tower_info_label: Label
var evolve_buttons: Array[Button] = []   # 선택한 타워의 진화 선택 버튼 2개 (진화 전: 계열 2개 / 진화 후 B가 남았으면: B 진화 1개)
var heal_button: Button                  # 타워 화면의 [회복] 버튼 (골드로 내구도 가득)
var _view_before_tower := "main"          # 맵에서 타워를 누르기 전에 보던 상단 화면 (뒤로 가면 여기로 돌아간다)
var tower_action: Button                 # 오른쪽 아래 [진화] 버튼 (고른 진화를 실행)
var _tower_pick := ""                    # 고른 진화: 계열 이름 또는 "B"
var _pick_tower: Tower = null            # _tower_pick을 고른 타워 (다른 타워를 누르면 선택을 지운다)
var recolor_button: Button               # 선택한 타워의 색깔을 랜덤으로 바꾸는 버튼 (항상 보인다)
var evolve_ids: Array[String] = ["", ""]     # 진화 선택 버튼이 가리키는 값 ("" = 안 쓰는 칸)
var upgrade_menu: HBoxContainer          # 업그레이드 탭: [←] [타워] [색깔]
var evo_view: HBoxContainer              # 타워 업그레이드 1단계: [←] + 4x2 격자 (진화 계열 8개 중 고르기)
var evo_buttons: Dictionary = {}         # 계열 -> Button
var evo_frames: Control                  # 계열 선택 화면에서 같은 기본 타워의 두 계열을 묶는 외곽선
var detail_view: HBoxContainer           # 타워 업그레이드 2단계: [←] + 4x2 격자 (고른 계열의 업그레이드 항목들)
var detail_grid: GridContainer
var _detail_evo := ""                    # 지금 보고 있는 계열
var _detail_items: Array = []            # [{btn, stat: Dictionary}]
var color_view: HBoxContainer            # 색깔 업그레이드: [←] + 4x2 격자 (7색 중 업그레이드할 색 고르기)
var color_buttons: Dictionary = {}       # 색깔 이름 -> Button
var tower_view: GridContainer
var _hud_timer := 0.0

# 글자 크기 (화면 폭 600 기준. 폰에서는 1칸이 약 0.65dp라서 이 정도는 돼야 읽힌다)
const FONT_BODY := 20
const FONT_SMALL := 16
const FONT_TINY := 14
const TOP_HEIGHT := 180.0                # 위쪽 UI 줄 높이 (MainGame.tscn의 TopUI와 같아야 한다). 타워/몬스터/업그레이드 화면은 모두 이 안에서 해결한다
const CORNER_MARGIN := 10.0              # 폰 화면 모서리가 둥글게 잘려도 UI가 가리지 않는 최소 여백
const BOTTOM_HEIGHT := 170.0             # 맵 아래 메시지 영역 높이 (맵은 그만큼 줄어든다)
const OVERLAY_MARGIN := 6.0              # 맵 왼쪽 위 상태 표시와 맵 가장자리 사이 간격

var game_over_screen: GameOverScreen     # 승리/패배 화면
var _play_time := 0.0                    # 실제로 플레이한 시간(초). 일시정지 중에는 흐르지 않는다 (통계용)
var _play_running := false               # 시작 버튼을 눌렀는지

# 일시정지: get_tree().paused로 게임 전체를 멈추고, 항상 동작하는 PauseOverlay를 위에 띄운다
var pause_overlay: PauseOverlay
var _paused_at_ms := 0                   # 멈춘 시각 (Monster의 강화 버프 시계 보정용)

# 보스 스킬 배너: 어느 레인을 보고 있든 맵 위쪽에 뜬다. 여러 개가 겹치면 차례로 보여 준다.
const SKILL_BANNER_SECONDS := 5.0        # 알림이 떠 있는 시간 (발동까지 예고 시간이 있으면 그만큼 더)
var skill_banner: PanelContainer
var skill_banner_title: Label
var skill_banner_text: Label
var _banner_queue: Array = []            # 기다리는 알림 [{name, text, lane, delay, boss}]
var _banner_info: Dictionary = {}        # 지금 보이는 알림
var _banner_left := 0.0                  # 지금 알림이 사라질 때까지
var _banner_delay := 0.0                 # 스킬이 발동할 때까지 (0이면 카운트다운을 안 보인다)
# 경고 연출: 생명이 줄면 화면이 붉게 깜빡이고, 보스 제한시간이 30초 남으면 화면 가운데에 알린다
const BOSS_TIME_WARNING := 30.0          # 이 시간(초) 이하로 남으면 알린다 (보스 레벨마다 한 번)
const TIME_WARNING_SECONDS := 3.0        # 가운데 알림이 떠 있는 시간
var life_flash: ColorRect                # 화면 전체를 덮는 붉은 막 (평소엔 투명)
var _life_flash_tween: Tween
var _prev_lives := -1                    # 직전 생명 (줄었을 때만 깜빡이려고)
var time_warning: PanelContainer
var time_warning_label: Label
var _time_warning_tween: Tween
var _warned_level := -1                  # 30초 경고를 이미 띄운 보스 레벨
var minimap_views: Dictionary = {}       # 레인 번호 -> MiniMapView (보스 스킬이 걸리는 레인을 깜빡이려고 모아 둔다)

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


## 폰의 노치/상태바/제스처 바/둥근 모서리에 UI가 가리지 않도록 네 변 모두에 안전 여백을 둔다 (폰에서만).
## 시스템이 알려 주는 안전 영역(노치 등)에, 화면 모서리가 둥글게 잘리는 폰을 위한 최소 여백(CORNER_MARGIN)을 더한다.
func _apply_safe_area() -> void:
	if not OS.has_feature("mobile"):
		return
	var win := Vector2(DisplayServer.window_get_size())
	var safe := DisplayServer.get_display_safe_area()
	if win.x <= 0.0 or win.y <= 0.0 or safe.size.x <= 0:
		return
	var s := get_viewport_rect().size.x / win.x  # 화면 픽셀 -> 가상 화면 좌표
	apply_insets(
		maxf(CORNER_MARGIN, safe.position.x * s),
		maxf(CORNER_MARGIN, safe.position.y * s),
		maxf(CORNER_MARGIN, (win.x - safe.end.x) * s),
		maxf(CORNER_MARGIN, (win.y - safe.end.y) * s))


## 화면 가장자리에서 left/top/right/bottom 만큼 안쪽에 UI를 배치한다 (가상 화면 좌표)
func apply_insets(left: float, top: float, right: float, bottom: float) -> void:
	var box: Control = $VBoxContainer
	box.offset_left = left
	box.offset_top = top
	box.offset_right = -right
	box.offset_bottom = -bottom
	game_field.set_side_inset(left + right)  # 칸 크기는 맵이 실제로 쓰는 폭으로 정한다

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
	left_panel = main_view.get_parent()
	monster_view.move_child(monster_buttons[0], BACK_CELL)  # 뒤로 가기는 왼쪽 아래 칸
	_create_family_frames()
	_create_monster_type_view()
	_create_tower_view()
	_create_upgrade_views()
	_create_minimaps()
	_create_hud()
	_create_tower_sel_view()
	_create_status_panel()
	_create_confirm_dialog()
	_create_skill_banner()
	_create_game_over_screen()
	_create_pause_ui()
	_create_alerts()

## 미니맵 바로 왼쪽 우하단에 놓는 실행 버튼 ([생성] / [업그레이드]). 고르기만 해서는 아무 일도 일어나지 않고 이 버튼을 눌러야 실행된다.
func _make_action_button() -> Button:
	var b := _make_view_button("", FONT_SMALL)  # "업그레이드" 5글자가 칸 폭(약 97px)에 들어가는 크기
	b.pressed.connect(_on_action_pressed)
	b.focus_mode = Control.FOCUS_NONE
	action_buttons.append(b)
	return b


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

## 몬스터 배럭은 두 단계다. 1단계: 유형 버튼(공격형/일반형/공중형). 2단계: 고른 유형의 몬스터 종류 버튼.
## 보스가 보내는 몬스터(일반형/공중형)도 여기서 볼 수 있다. 협력(PvE)에서 만들 수 없는 것은 회색이고, 눌러도 설명만 나온다.
func _create_monster_type_view() -> void:
	monster_type_view = HBoxContainer.new()
	monster_type_view.visible = false
	left_panel.add_child(monster_type_view)
	monster_type_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := _make_back_column("monster_back")
	back.pressed.connect(_show_view.bind("main"))
	monster_type_view.add_child(back)
	var grid := GridContainer.new()
	grid.columns = 4
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	monster_type_view.add_child(grid)
	var cats := Monsters.CATEGORIES
	for i in range(8):  # 4x2 격자: 유형을 왼쪽 위부터 채우고 나머지는 비운다
		if i >= cats.size():
			var spacer := Control.new()
			spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
			spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
			grid.add_child(spacer)
			continue
		var cat: String = cats[i]
		var info: Dictionary = Monsters.CATEGORY_DATA[cat]
		var b := _make_view_button(info.name, FONT_BODY)
		b.add_theme_color_override("font_color", info.color)
		_apply_family_style(b, info.color)
		b.pressed.connect(_on_monster_type_selected.bind(cat))
		grid.add_child(b)


const TILE_COLS := 9
const TILE_CELLS := 27                   # 9열 x 3줄
const BACK_CELL := 18                    # 뒤로 가기: 왼쪽 아래 1칸

## 타워/몬스터 화면의 9x3 타일 격자: 빈 칸으로 채워 두고, 왼쪽 아래(18번)에 [←]를 놓는다. 나머지 칸은 _set_tile로 채운다.
func _make_tile_grid(on_back: Callable) -> GridContainer:
	var grid := GridContainer.new()
	grid.columns = TILE_COLS
	grid.visible = false
	left_panel.add_child(grid)
	grid.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for c in range(TILE_CELLS):
		var spacer := Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		grid.add_child(spacer)
	var back := Button.new()
	back.text = "←"
	back.add_theme_font_size_override("font_size", 24)
	back.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	back.size_flags_vertical = Control.SIZE_EXPAND_FILL
	back.pressed.connect(on_back)
	_set_tile(grid, BACK_CELL, back)
	return grid


## 격자의 cell번 칸에 노드를 놓는다 (원래 있던 빈 칸은 지운다)
func _set_tile(grid: GridContainer, cell: int, node: Control) -> void:
	var old := grid.get_child(cell)
	grid.remove_child(old)
	old.queue_free()
	grid.add_child(node)
	grid.move_child(node, cell)


## 내용 번호 -> 격자 칸 번호 (뒤로 가기 칸을 건너뜀)
func _slot_cell(slot_idx: int) -> int:
	return slot_idx if slot_idx < BACK_CELL else slot_idx + 1


## 고른 유형의 몬스터 종류 버튼들을 채운다 (9열 격자의 monster_buttons를 다시 쓴다: [0]은 뒤로 가기)
func _populate_monster_buttons(cat: String) -> void:
	_monster_category = cat
	_monster_slots = Monsters.slots_of(cat)
	var cat_color: Color = Monsters.CATEGORY_DATA[cat].color
	for i in range(1, monster_buttons.size()):
		var b := monster_buttons[i]
		for c in b.get_children():  # 이전 유형에서 붙인 아이콘/라벨
			b.remove_child(c)
			c.queue_free()
		b.modulate = Color.WHITE
		b.text = ""
		b.tooltip_text = ""
		b.mouse_filter = Control.MOUSE_FILTER_STOP
		var slot_idx := i - 1
		b.visible = true
		var kind_id: String = _monster_slots[slot_idx] if slot_idx < _monster_slots.size() else ""
		if kind_id == "":
			b.disabled = true  # 계열 사이 빈칸 / 모자라는 칸 채움 (보이지 않고 눌리지도 않는다)
			b.focus_mode = Control.FOCUS_NONE
			b.modulate = Color(1, 1, 1, 0)
			b.mouse_filter = Control.MOUSE_FILTER_IGNORE
			continue
		b.disabled = false
		b.focus_mode = Control.FOCUS_ALL
		var data: Dictionary = Monsters.DATA[kind_id]
		var fam_color: Color = Monsters.FAMILY_COLORS.get(data.get("family", ""), cat_color)
		b.set_meta("fam_color", fam_color)
		var icon := UnitIcon.new()
		icon.show_monster(kind_id)
		_decorate_unit_button(b, icon, data.cost, "", data.get("family", ""), fam_color)  # 설명은 하단 메시지 칸에 나온다
		_apply_family_style(b, fam_color)
		if not Monsters.can_send_in_pve(kind_id):
			b.modulate = Color(0.45, 0.45, 0.45)  # 협력에서는 만들 수 없다: 회색 (눌러서 설명은 볼 수 있다)
	_rebuild_family_frames(cat)
	_refresh_monster_highlight()


## 고른 몬스터를 굵은 노란 테두리로 강조한다 (나머지는 계열 색 테두리)
func _refresh_monster_highlight() -> void:
	for i in range(1, monster_buttons.size()):
		var slot_idx := i - 1
		if slot_idx >= _monster_slots.size() or _monster_slots[slot_idx] == "":
			continue
		var b := monster_buttons[i]
		if _monster_slots[slot_idx] == _sel_monster:
			_style_selected(b)
		else:
			_apply_family_style(b, b.get_meta("fam_color", Color.WHITE))


## 고른 항목 강조 (굵은 노란 테두리)
func _style_selected(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		var sb := StyleBoxFlat.new()
		sb.bg_color = Color(0.32, 0.27, 0.05)
		sb.border_color = Color(1.0, 0.9, 0.2)
		sb.set_border_width_all(4)
		sb.set_corner_radius_all(4)
		b.add_theme_stylebox_override(state, sb)


func _clear_selected_style(b: Button) -> void:
	for state in ["normal", "hover", "pressed", "disabled"]:
		b.remove_theme_stylebox_override(state)


## 같은 계열이 이어진 칸들을 한 묶음으로 굵은 외곽선 프레임을 씌운다 (버튼 격자 위에 겹쳐 그리는 안 눌리는 레이어).
## 계열이 없는 유형(일반형/공중형)은 유형 전체가 한 묶음이다.
func _rebuild_family_frames(cat: String) -> void:
	var frames := family_frames as FamilyFrames
	frames.groups.clear()
	var run_key := ""
	var run_color := Color.WHITE
	var run_buttons: Array[Button] = []
	var run_row := 0
	for i in range(_monster_slots.size() + 1):
		var kind_id: String = _monster_slots[i] if i < _monster_slots.size() else ""
		var key := ""
		var color := Color.WHITE
		if kind_id != "":
			key = Monsters.DATA[kind_id].get("family", cat)
			color = Monsters.FAMILY_COLORS.get(key, Monsters.CATEGORY_DATA[cat].color)
		var row := floori(_slot_cell(i) / float(TILE_COLS))
		if (key != run_key or (kind_id != "" and row != run_row)) and not run_buttons.is_empty():  # 줄이 바뀌면 묶음 외곽선도 끊는다
			frames.groups.append({"buttons": run_buttons, "color": run_color})
			run_buttons = []
		run_key = key
		run_color = color
		if kind_id != "":
			run_row = row
			run_buttons.append(monster_buttons[i + 1])


func _create_family_frames() -> void:
	var frames := FamilyFrames.new()
	family_frames = frames
	frames.visible = false
	left_panel.add_child(frames)
	frames.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


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
	# 타워 배럭: 9x3 타일. 기본 타워를 왼쪽 위부터 차례대로, 뒤로 가기는 왼쪽 아래
	tower_view = _make_tile_grid(_on_tower_back_pressed)
	var i := 0
	for kind_id in Balance.TOWER_KINDS:
		var kind := Balance.tower_kind(kind_id)
		var b := Button.new()
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.size_flags_vertical = Control.SIZE_EXPAND_FILL
		b.pressed.connect(_on_tower_kind_selected.bind(kind_id))
		_set_tile(tower_view, _slot_cell(i), b)
		i += 1
		tower_buttons[kind_id] = b
		var icon := UnitIcon.new()
		icon.show_tower(kind)
		_decorate_unit_button(b, icon, kind.cost, "")  # 설명은 하단 메시지 칸에 나온다


## 업그레이드 탭 (타워 / 색깔).
## 타워 탭: 진화 계열 8개 중 하나를 고르면 그 계열의 업그레이드 항목(관통 수, 독 피해 ...)이 나온다.
## 항목을 고르면 하단 메시지 칸에 설명이 나오고, 오른쪽 아래 [업그레이드] 버튼을 눌러야 올라간다 (같은 계열의 모든 타워에 적용).
## 색깔 탭: 7색 중 하나를 고르면 설명이 나오고, [업그레이드]를 누르면 그 색 타워의 고유 보너스 레벨이 오른다 (레인 공유).
## (진화와 B 스킬 배우기는 타워마다 개별: 맵에서 타워를 누르면 상단에 나오는 버튼으로 한다.)
## 모든 화면은 상단 왼쪽 칸(180px) 안에서 해결한다: [←] 한 칸 + 4x2 격자, 격자 8번째(오른쪽 아래) 칸이 [업그레이드] 버튼.
func _create_upgrade_views():
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
	color_tab.tooltip_text = "색깔별 업그레이드: 색을 고르면 그 색 타워의 고유 보너스가 강해진다"
	color_tab.pressed.connect(_show_view.bind("colors"))
	upgrade_menu.add_child(color_tab)

	# 색깔 화면: 7색 버튼 (4x2 격자) + 8번째 칸의 [업그레이드]
	color_view = HBoxContainer.new()
	color_view.visible = false
	left_panel.add_child(color_view)
	color_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var color_back := _make_back_column("colors_back")
	color_back.pressed.connect(_show_view.bind("upgrade"))
	color_view.add_child(color_back)
	var color_grid := GridContainer.new()
	color_grid.columns = 4
	color_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	color_view.add_child(color_grid)
	for info in Balance.TOWER_COLORS:
		var cname: String = info.name
		var cb := _make_view_button("", 11)
		var font_col: Color = info.color.lightened(0.35)  # 남색처럼 어두운 색도 글자가 보이게
		cb.add_theme_color_override("font_color", font_col)
		cb.add_theme_color_override("font_disabled_color", Color(font_col, 0.55))
		cb.pressed.connect(_on_color_pressed.bind(cname))
		color_grid.add_child(cb)
		color_buttons[cname] = cb
	color_action = _make_action_button()
	color_grid.add_child(color_action)

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
		var eb := _make_view_button("", 12)
		eb.add_theme_color_override("font_color", Evolutions.DATA[evo].color)
		eb.pressed.connect(_open_evo_detail.bind(evo))
		eb.clip_contents = true
		var evo_icon := UnitIcon.new()  # 진화한 타워의 모습 (맵에서와 같다)
		evo_icon.show_evolution(evo)
		eb.add_child(evo_icon)
		evo_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		evo_icon.offset_bottom = -18.0
		var evo_name := Label.new()
		evo_name.text = Evolutions.DATA[evo].name
		evo_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		evo_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		evo_name.add_theme_font_size_override("font_size", 13)
		evo_name.add_theme_color_override("font_color", Evolutions.DATA[evo].color)
		evo_name.add_theme_color_override("font_outline_color", Color(0, 0, 0))
		evo_name.add_theme_constant_override("outline_size", 4)
		eb.add_child(evo_name)
		evo_name.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
		evo_name.grow_vertical = Control.GROW_DIRECTION_BEGIN
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

	# 2단계: 항목 버튼 (계열마다 항목이 달라서 열 때마다 새로 만든다. 4x2 격자, 8번째 칸이 [업그레이드])
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
	detail_action = _make_action_button()

	# 몬스터 종류 화면의 [생성] 버튼: 9열 격자 2줄 중 아랫줄 오른쪽 3칸 자리
	monster_action = _make_action_button()
	left_panel.add_child(monster_action)
	monster_action.visible = false
	monster_action.anchor_left = 7.0 / 9.0  # 9x3 격자의 오른쪽 아래 2칸
	monster_action.anchor_right = 1.0
	monster_action.anchor_top = 2.0 / 3.0
	monster_action.anchor_bottom = 1.0
	monster_action.offset_left = 0.0
	monster_action.offset_right = 0.0
	monster_action.offset_top = 0.0
	monster_action.offset_bottom = 0.0
	monster_action.z_index = 60  # 계열 외곽선(50)보다 위


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
	b.custom_minimum_size = Vector2(56, 0)
	return b


## 상단 왼쪽 칸에 보여줄 화면을 하나만 켠다: main / tower / tower_sel(맵에서 고른 타워) / monster(유형 고르기) / monster_kinds(종류 고르기) / upgrade / evos / detail / colors.
## 화면은 전부 상단 안에서 바뀐다 (맵 위에 아무것도 뜨지 않는다).
## 타워 화면을 떠나면 건설 모드도 꺼진다: 타워를 골라 둔 상태(타워 화면)에서만 맵 타일을 눌러 지을 수 있다.
func _show_view(view: String) -> void:
	_view = view
	if view != "tower" and game_field.current_tool == GameField.PlacementTool.TOWER:
		game_field.set_current_tool(GameField.PlacementTool.NONE)
	main_view.visible = view == "main"
	tower_view.visible = view == "tower"
	tower_sel_view.visible = view == "tower_sel"
	monster_type_view.visible = view == "monster"
	monster_view.visible = view == "monster_kinds"
	family_frames.visible = view == "monster_kinds"
	monster_action.visible = view == "monster_kinds"
	upgrade_menu.visible = view == "upgrade"
	evo_view.visible = view == "evos"
	evo_frames.visible = view == "evos"
	detail_view.visible = view == "detail"
	color_view.visible = view == "colors"
	_sel = []
	_tower_pick = ""
	if view != "monster_kinds":
		_sel_monster = ""
		_refresh_monster_highlight()
	_refresh_item_highlight()
	_refresh_tower_highlight()
	_request_refresh()


## 고른 계열의 업그레이드 항목 화면을 만든다. 4x2 격자의 왼쪽 2x2는 A 스킬 항목, 오른쪽 2x2는 B 스킬 항목 (각각 1 2 / 3 4 순서).
## 없는 칸은 비우고, 오른쪽 아래 칸이 [업그레이드] 버튼이다.
const DETAIL_A_CELLS := [0, 1, 4, 5]
const DETAIL_B_CELLS := [2, 3, 6, 7]

func _open_evo_detail(evo: String) -> void:
	_detail_evo = evo
	_detail_items.clear()
	if detail_action.get_parent() == detail_grid:
		detail_grid.remove_child(detail_action)
	for c in detail_grid.get_children():
		detail_grid.remove_child(c)
		c.queue_free()
	var cells: Array[Control] = []
	for i in range(8):
		var spacer := Control.new()
		spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
		cells.append(spacer)
	var color: Color = Evolutions.DATA[evo].color
	var a_n := 0
	var b_n := 0
	for stat in Evolutions.STATS[evo]:
		var b := _make_detail_button(evo, stat, color)
		var cell: int
		if stat.s == "A":
			cell = DETAIL_A_CELLS[a_n]
			a_n += 1
		else:
			cell = DETAIL_B_CELLS[b_n]
			b_n += 1
		cells[cell].queue_free()
		cells[cell] = b
	cells[7].queue_free()  # B 항목은 최대 3개라 오른쪽 아래 칸은 늘 비어 있다
	cells[7] = detail_action
	for c in cells:
		detail_grid.add_child(c)
	_show_view("detail")
	_refresh_now()


func _make_detail_button(evo: String, stat: Dictionary, color: Color) -> Button:
	var b := _make_view_button("", 11)
	b.add_theme_color_override("font_color", color)
	b.add_theme_color_override("font_disabled_color", Color(color, 0.55))
	b.pressed.connect(_on_stat_pressed.bind(evo, stat.s, stat.k))
	_detail_items.append({"btn": b, "stat": stat})
	return b


## 업그레이드 항목을 골랐다: 하단에 설명이 나온다 (아직 올리지 않는다)
func _on_stat_pressed(evo: String, skill: String, key: String) -> void:
	_sel = [evo, "stat", skill, key]
	_refresh_item_highlight()
	_refresh_now()


func _on_color_pressed(color_name: String) -> void:
	_sel = [color_name, "color", "", ""]
	_refresh_item_highlight()
	_refresh_now()


## 고른 업그레이드 항목(또는 색)만 노란 테두리로 강조한다
func _refresh_item_highlight() -> void:
	for item in _detail_items:
		var stat: Dictionary = item.stat
		var on: bool = _sel.size() == 4 and _sel[1] == "stat" and _sel[0] == _detail_evo and _sel[2] == stat.s and _sel[3] == stat.k
		if on:
			_style_selected(item.btn)
		else:
			_clear_selected_style(item.btn)
	for cname in color_buttons:
		if _sel.size() == 4 and _sel[1] == "color" and _sel[0] == cname:
			_style_selected(color_buttons[cname])
		else:
			_clear_selected_style(color_buttons[cname])


func _refresh_now() -> void:
	var lane: LaneController = game_field.lanes.get(game_field.local_player_id)
	var boss: BossController = game_field.boss
	if lane:
		_refresh_upgrade_views(lane)
		_update_explain(lane)
		if boss:
			_refresh_action_buttons(lane, boss)


## 다음 프레임에 상단/하단을 바로 갱신한다 (0.1초 주기를 기다리지 않게)
func _request_refresh() -> void:
	_hud_timer = 0.0


## 업그레이드 화면 글자 갱신 (설명은 하단 메시지 칸: _update_explain)
func _refresh_upgrade_views(lane: LaneController) -> void:
	if detail_view.visible and _detail_evo != "":
		var evo := _detail_evo
		for item in _detail_items:
			var b: Button = item.btn
			var stat: Dictionary = item.stat
			var lv := lane.stat_level(evo, stat.s, stat.k)
			var cost := lane.stat_upgrade_cost(evo, stat.s, stat.k)
			b.text = "%s %s\nLv%d  %s\n%s" % [stat.s, stat.name, lv, Evolutions.stat_value_text(evo, stat, lv), "최대" if lv >= Evolutions.MAX_LEVEL else "%d골드" % cost]
	if color_view.visible:
		for cname in color_buttons:
			var b: Button = color_buttons[cname]
			var lv := lane.color_level(cname)
			var cost := lane.color_upgrade_cost(cname)
			var type: String = Balance.COLOR_BONUS_TYPES[cname]
			b.text = "%s\n%s\nLv%d/%d  %s\n%s" % [cname, Balance.COLOR_BONUS_LABELS[type], lv, Balance.COLOR_MAX_LEVEL, Balance.color_bonus_value_text(cname, lv), "최대" if cost < 0 else "%d골드" % cost]


## 하단 메시지 칸에 보여줄 설명: 지금 고른 타워/몬스터/업그레이드 항목 (폰에는 툴팁이 없다)
func _update_explain(lane: LaneController) -> void:
	var text := _explain_text(lane)
	explain_label.text = text
	explain_label.visible = text != ""


func _explain_text(lane: LaneController) -> String:
	match _view:
		"tower":
			if game_field.current_tool == GameField.PlacementTool.TOWER:
				return "%s\n맵의 빈 타일을 눌러 건설" % Balance.tower_tooltip(Balance.tower_kind(game_field.selected_tower_kind))
			return "지을 타워를 고르세요."
		"monster":
			return "몬스터 유형을 고르세요."
		"monster_kinds":
			if _sel_monster == "":
				return "몬스터를 고르세요." if _monster_category in Monsters.PVE_SENDABLE else "협력에서는 볼 수만 있는 유형입니다."
			return Monsters.tooltip(_sel_monster)
		"tower_sel":
			var t := game_field.get_selected_tower()
			if t == null or _tower_pick == "":
				return "진화를 고르세요." if t != null and (t.can_evolve() or (t.evolution != "" and not t.b_learned)) else ""
			if _tower_pick == "B":
				return "B 진화\n%s" % Evolutions.skill_text(t.evolution, "B", lane.levels_of(t.evolution))
			var bonus := " · 한 발 피해 x%.1f" % Evolutions.DAMAGE_MULT[_tower_pick] if Evolutions.DAMAGE_MULT.has(_tower_pick) else ""
			return "%s 진화%s\n%s" % [Evolutions.evo_name(_tower_pick), bonus, Evolutions.skill_text(_tower_pick, "A", lane.levels_of(_tower_pick))]
		"upgrade":
			return "종류를 고르세요."
		"evos":
			return "계열을 고르세요."
		"detail":
			if _sel.size() == 4 and _sel[1] == "stat":
				var evo: String = _sel[0]
				var stat := _find_stat(evo, _sel[2], _sel[3])
				var lv := lane.stat_level(evo, stat.s, stat.k)
				var text := Evolutions.skill_text(evo, _sel[2], lane.levels_of(evo))
				if lv >= Evolutions.MAX_LEVEL:
					return "%s\n%s 최대 레벨" % [text, stat.name]
				return "%s\n%s Lv%d → Lv%d: %s → %s" % [text, stat.name, lv, lv + 1,
					Evolutions.stat_value_text(evo, stat, lv), Evolutions.stat_value_text(evo, stat, lv + 1)]
			return Evolutions.tooltip(_detail_evo)
		"colors":
			if _sel.size() == 4 and _sel[1] == "color":
				return Balance.color_tooltip(_sel[0], lane.color_level(_sel[0]))
			return "색을 고르세요."
	return ""


func _find_stat(evo: String, skill: String, key: String) -> Dictionary:
	for stat in Evolutions.STATS[evo]:
		if stat.s == skill and stat.k == key:
			return stat
	return {}


## [생성]/[업그레이드] 버튼: 고른 것이 있고 살 수 있을 때만 눌린다
func _refresh_action_buttons(lane: LaneController, boss: BossController) -> void:
	var text := ""
	var enabled := false
	match _view:
		"monster_kinds":
			if _sel_monster == "":
				text = "생성"
			else:
				var cost: int = Monsters.DATA[_sel_monster].cost
				text = "생성\n%d골드" % cost
				enabled = Monsters.can_send_in_pve(_sel_monster) and lane.gold >= cost and boss.state == BossController.State.RUNNING
		"detail":
			if _sel.size() == 4 and _sel[1] == "stat":
				var cost := lane.stat_upgrade_cost(_sel[0], _sel[2], _sel[3])
				text = "업그레이드\n최대" if cost < 0 else "업그레이드\n%d골드" % cost
				enabled = cost >= 0 and lane.gold >= cost
			else:
				text = "업그레이드"
		"tower_sel":
			var t := game_field.get_selected_tower()
			var cost := _pick_cost(t, lane)
			if cost < 0:
				text = "진화"
			else:
				text = "진화\n%d골드" % cost
				enabled = t.lane == lane and lane.gold >= cost
		"colors":
			if _sel.size() == 4 and _sel[1] == "color":
				var cost := lane.color_upgrade_cost(_sel[0])
				text = "업그레이드\n최대" if cost < 0 else "업그레이드\n%d골드" % cost
				enabled = cost >= 0 and lane.gold >= cost
			else:
				text = "업그레이드"
		_:
			return
	for b in action_buttons:
		b.text = text
		b.disabled = not enabled


## [생성]/[업그레이드] 버튼을 눌렀다: 지금 화면에서 고른 것을 실행한다
func _on_action_pressed() -> void:
	match _view:
		"monster_kinds":
			if _sel_monster != "":
				Log.info(Log.Category.UI, "몬스터 생산 요청: %s" % _sel_monster)
				game_field.send_monster(_sel_monster)
		"detail":
			if _sel.size() == 4 and _sel[1] == "stat":
				game_field.upgrade_stat(_sel[0], _sel[2], _sel[3])
		"colors":
			if _sel.size() == 4 and _sel[1] == "color":
				game_field.upgrade_color(_sel[0])
		"tower_sel":
			if _tower_pick == "B":
				game_field.learn_selected_tower_skill()
			elif _tower_pick != "":
				game_field.evolve_selected_tower(_tower_pick)
			_tower_pick = ""
	_refresh_now()


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
	minimap_views[lane_index] = view
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
	# 맵 아래의 별도 메시지 영역 (사용자 안내). 맵은 이 영역만큼 줄어들어서 맵을 가리지 않는다.
	# 높이가 고정이라 타워를 고르거나 풀어도 맵 크기가 바뀌지 않는다. 내용이 넘치면 위아래로 밀어서 본다.
	# 위에서 아래로: 알림(보스 스킬/제한시간) / 고른 것의 설명 / 선택한 타워 정보 / 상태
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, BOTTOM_HEIGHT)
	var hud_style := StyleBoxFlat.new()
	hud_style.bg_color = Color(0.1, 0.1, 0.14)
	hud_style.border_color = Color(0.35, 0.35, 0.45)
	hud_style.border_width_top = 2
	hud_style.set_content_margin_all(6)
	panel.add_theme_stylebox_override("panel", hud_style)
	$VBoxContainer.add_child(panel)  # GameField 다음 = 맨 아래 줄
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	hud_box = box

	explain_label = Label.new()
	explain_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	explain_label.add_theme_font_size_override("font_size", FONT_SMALL)
	explain_label.add_theme_color_override("font_color", Color(0.7, 1.0, 0.8))
	explain_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	explain_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	explain_label.visible = false
	box.add_child(explain_label)

	tower_info_label = Label.new()  # 선택한 타워 정보 (타워를 선택했을 때만 보인다)
	tower_info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tower_info_label.add_theme_font_size_override("font_size", FONT_SMALL)
	tower_info_label.add_theme_color_override("font_color", Color(1.0, 1.0, 0.6))
	tower_info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	tower_info_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tower_info_label.visible = false
	box.add_child(tower_info_label)

	hud_label = Label.new()
	hud_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud_label.add_theme_font_size_override("font_size", FONT_SMALL)
	hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(hud_label)

	hud_panel = panel


## 맵에서 내 타워를 눌렀을 때 상단에 나오는 화면: [←] + 격자(진화 2개 / B 스킬 배우기 / 색깔 바꾸기).
## 타워 정보는 하단 메시지 칸에 나온다. [←]를 누르면 선택이 풀린다.
func _create_tower_sel_view() -> void:
	tower_sel_view = HBoxContainer.new()
	tower_sel_view.visible = false
	left_panel.add_child(tower_sel_view)
	tower_sel_view.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var back := _make_back_column("tower_sel_back")
	back.pressed.connect(_on_tower_sel_back_pressed)
	tower_sel_view.add_child(back)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tower_sel_view.add_child(grid)
	for i in range(2):  # 윗줄: 진화 선택 (누르면 하단에 설명만 나온다)
		var eb := _make_view_button("", FONT_SMALL)
		eb.pressed.connect(_on_evolve_pressed.bind(i))
		grid.add_child(eb)
		evolve_buttons.append(eb)
	heal_button = _make_view_button("", FONT_SMALL)  # 윗줄 오른쪽: 내구도 회복 (바로 실행)
	heal_button.pressed.connect(func(): game_field.heal_selected_tower())
	grid.add_child(heal_button)
	recolor_button = _make_view_button("", FONT_SMALL)  # 아랫줄 왼쪽: 색깔 바꾸기 (바로 실행)
	recolor_button.pressed.connect(_on_recolor_selected_pressed)
	grid.add_child(recolor_button)
	var gap := Control.new()
	gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid.add_child(gap)
	tower_action = _make_action_button()  # 아랫줄 오른쪽: [진화]
	grid.add_child(tower_action)


## 맵에서 지어진 타워를 눌렀다: 건설 모드 중이어도 상단이 그 타워 화면으로 바뀌고 건설 모드는 꺼진다.
## 다시 지으려면 타워를 새로 골라야 하고, 그동안 빈 칸을 눌러도 짓지 않는다.
func _on_tower_selected(_tower: Tower) -> void:
	_enter_tower_sel()


## 어떤 화면을 보고 있든 타워 화면으로 넘어간다 (보던 화면은 기억해 둔다)
func _enter_tower_sel() -> void:
	if _view == "tower_sel":
		return
	_view_before_tower = _view if _view != "tower" else "main"
	_show_view("tower_sel")


func _on_tower_sel_back_pressed() -> void:
	game_field.select_tower(null)
	_leave_tower_sel()


func _leave_tower_sel() -> void:
	var prev := _view_before_tower
	_view_before_tower = "main"
	_show_view(prev)

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


## 맵 왼쪽 위에 겹치는 상태 표시. 맵 위에는 이것만 올린다 (입력은 통과시켜서 맵 조작을 막지 않는다).
## 맨 왼쪽 위: 생명(하트) / 골드 / 수입. 그 바로 오른쪽: 다음 웨이브.
func _create_status_panel() -> void:
	map_overlay = Control.new()
	map_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	map_overlay.z_index = 85  # 타워/몬스터(1~4)보다 위, 일시정지(500)/승패 화면(1000)보다 아래
	add_child(map_overlay)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 6)
	map_overlay.add_child(row)

	var box := _make_overlay_panel(row)
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

	var wave_box := _make_overlay_panel(row)
	status_wave_title = _status_label(FONT_TINY)
	status_wave_title.add_theme_color_override("font_color", Color(0.75, 0.9, 1.0))
	wave_box.add_child(status_wave_title)
	status_affix_label = _status_label(11)
	status_affix_label.visible = false
	wave_box.add_child(status_affix_label)
	for i in range(Balance.WAVE_GROUPS):
		var wave_row := HBoxContainer.new()
		wave_box.add_child(wave_row)
		var dot := _status_icon("dot", Color.WHITE, 12)
		wave_row.add_child(dot)
		var label := _status_label(FONT_TINY)
		wave_row.add_child(label)
		status_wave_rows.append({"row": wave_row, "dot": dot, "label": label})

	status_guard_label = _status_label(10)
	status_guard_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.35))
	status_guard_label.visible = false
	wave_box.add_child(status_guard_label)


## 맵 위에 겹치는 반투명 패널 하나를 만들고 그 안의 세로 줄을 돌려준다
func _make_overlay_panel(parent: Control) -> VBoxContainer:
	var panel := PanelContainer.new()
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.size_flags_vertical = Control.SIZE_SHRINK_BEGIN  # 옆 패널이 더 길어도 늘어나지 않게
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.06, 0.06, 0.1, 0.72)  # 맵이 비쳐 보이게
	style.set_corner_radius_all(6)
	style.content_margin_left = 6
	style.content_margin_right = 6
	style.content_margin_top = 3
	style.content_margin_bottom = 3
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_theme_constant_override("separation", 1)
	panel.add_child(box)
	return box


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
	status_lives_label.text = "%d" % lane.lives_shown()
	status_gold_label.text = "%d" % lane.gold_shown()
	var left := lane.income_time_left() if boss.state == BossController.State.RUNNING else -1.0
	status_income_label.text = "수입 +%d\n%s" % [lane.income, "%d초 뒤" % ceili(left) if left >= 0.0 else "대기"]

	var preview := boss.get_next_wave_preview()
	var wave_left := boss.time_to_next_wave()
	status_wave_title.text = "다음 웨이브\n%s" % ("%d초 뒤" % ceili(wave_left) if wave_left >= 0.0 else "대기")
	for i in range(status_wave_rows.size()):
		var r: Dictionary = status_wave_rows[i]
		r.row.visible = i < preview.size()
		if i < preview.size():
			var e: Dictionary = preview[i]
			r.dot.color = e.color
			r.dot.queue_redraw()
			r.label.text = "%s x%d%s" % [e.name, e.count, "(공)" if e.flying else ""]

	var affix := boss.get_next_wave_affix()
	status_affix_label.visible = not affix.is_empty()
	if not affix.is_empty():
		status_affix_label.text = "%s 웨이브!" % affix.name
		status_affix_label.add_theme_color_override("font_color", affix.color)

	status_guard_label.visible = boss.has_guard()
	if boss.has_guard():
		status_guard_label.text = "보스 보호막 -%d%%" % roundi((1.0 - boss.damage_mult) * 100.0)


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


## 승리/패배 화면 생성 (화면의 UI는 GameOverScreen이 스스로 만든다)
func _create_game_over_screen() -> void:
	game_over_screen = GameOverScreen.new()
	add_child(game_over_screen)
	game_over_screen.restart_requested.connect(_on_game_over_restart)
	game_over_screen.quit_requested.connect(_on_game_over_quit)
	game_field.ui_blockers.append(game_over_screen)  # 화면이 떠 있는 동안 뒤의 맵이 클릭되지 않도록

	# 보스는 GameField가 한 프레임 기다린 뒤에 만들어서 지금은 아직 없다: 만들어지는 순간 연결한다
	if game_field.boss != null:
		_connect_boss(game_field.boss)
	else:
		game_field.boss_ready.connect(_connect_boss)


func _connect_boss(boss: BossController) -> void:
	var my_lane: LaneController = game_field.lanes.get(game_field.local_player_id)
	if my_lane != null:
		_prev_lives = my_lane.lives
		my_lane.lives_changed.connect(_on_lives_changed)
	boss.boss_defeated.connect(_on_boss_defeated)
	boss.boss_failed.connect(_on_boss_failed)
	boss.skill_announced.connect(_on_skill_announced)


## 보스 스킬 알림 배너 (하단 메시지 칸 맨 위에 뜬다)
func _create_skill_banner() -> void:
	skill_banner = PanelContainer.new()
	skill_banner.visible = false
	skill_banner.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.16, 0.05, 0.05, 0.92)
	style.border_color = Color(1.0, 0.7, 0.2)
	style.set_border_width_all(2)
	style.set_corner_radius_all(6)
	style.content_margin_left = 10
	style.content_margin_right = 10
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	skill_banner.add_theme_stylebox_override("panel", style)

	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	skill_banner.add_child(box)
	skill_banner_title = _status_label(FONT_SMALL)
	skill_banner_title.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(skill_banner_title)
	skill_banner_text = _status_label(FONT_TINY)
	skill_banner_text.add_theme_color_override("font_color", Color(1.0, 0.95, 0.9))
	skill_banner_text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(skill_banner_text)
	hud_box.add_child(skill_banner)  # 맵 위가 아니라 하단 메시지 칸 맨 위에 뜬다
	hud_box.move_child(skill_banner, 0)


## 경고 연출 노드 만들기 (붉은 막은 화면 전체를 잠깐 덮고, 제한시간 경고는 하단 메시지 칸에 뜬다)
func _create_alerts() -> void:
	life_flash = ColorRect.new()
	life_flash.color = Color(1.0, 0.1, 0.1, 0.0)
	life_flash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	life_flash.z_index = 120  # 배너(110)보다 위, 일시정지(500)/승패 화면(1000)보다 아래
	add_child(life_flash)
	life_flash.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	time_warning = PanelContainer.new()
	time_warning.visible = false
	time_warning.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.2, 0.03, 0.03, 0.93)
	style.border_color = Color(1.0, 0.3, 0.2)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(8)
	time_warning.add_theme_stylebox_override("panel", style)
	time_warning_label = Label.new()
	time_warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	time_warning_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	time_warning_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	time_warning_label.add_theme_font_size_override("font_size", FONT_BODY)
	time_warning_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.7))
	time_warning.add_child(time_warning_label)
	hud_box.add_child(time_warning)  # 맵 가운데가 아니라 하단 메시지 칸 맨 위에 뜬다
	hud_box.move_child(time_warning, 0)


## 내 레인의 생명이 줄면 화면을 붉게 두 번 깜빡인다 (보라 보너스로 늘어날 때는 깜빡이지 않는다)
func _on_lives_changed(lives: int) -> void:
	var lost := lives < _prev_lives
	_prev_lives = lives
	if lost:
		_flash_life_loss()


func _flash_life_loss() -> void:
	if _life_flash_tween != null:
		_life_flash_tween.kill()
	life_flash.color.a = 0.0
	_life_flash_tween = create_tween()
	for i in range(2):
		_life_flash_tween.tween_property(life_flash, "color:a", 0.4, 0.07)
		_life_flash_tween.tween_property(life_flash, "color:a", 0.0, 0.2)


## 보스 제한시간이 30초 이하로 남으면 레벨마다 한 번 화면 가운데에 알린다
func _check_boss_time_warning(boss: BossController) -> void:
	if boss.state != BossController.State.RUNNING or boss.level == _warned_level:
		return
	if boss.time_left > BOSS_TIME_WARNING:
		return
	_warned_level = boss.level
	time_warning_label.text = "보스 제한시간 %d초 남았습니다!
제한시간이 끝나면 패배합니다" % int(BOSS_TIME_WARNING)
	time_warning.visible = true
	time_warning.modulate.a = 1.0
	if _time_warning_tween != null:
		_time_warning_tween.kill()
	_time_warning_tween = create_tween()
	_time_warning_tween.tween_interval(TIME_WARNING_SECONDS - 0.5)
	_time_warning_tween.tween_property(time_warning, "modulate:a", 0.0, 0.5)
	_time_warning_tween.tween_callback(func(): time_warning.visible = false)


func _on_skill_announced(info: Dictionary) -> void:
	_banner_queue.append(info)


## 대기 중인 알림을 하나씩 보여 주고, 예고 시간이 있으면 발동까지 카운트다운을 붙인다
func _update_skill_banner(delta: float) -> void:
	if _banner_left > 0.0:
		_banner_left -= delta
		_banner_delay = maxf(0.0, _banner_delay - delta)
		if _banner_left <= 0.0:
			skill_banner.visible = false
		else:
			_refresh_skill_banner_text()
	if _banner_left <= 0.0 and not _banner_queue.is_empty():
		_show_skill_banner(_banner_queue.pop_front())


func _show_skill_banner(info: Dictionary) -> void:
	_banner_info = info
	_banner_delay = float(info.get("delay", 0.0))
	_banner_left = SKILL_BANNER_SECONDS + _banner_delay
	skill_banner_title.text = "[%s] %s  -  BOSS %s" % [BossSkills.lane_tag(info.lane), info.name, info.get("boss", "")]
	_refresh_skill_banner_text()
	_alert_minimaps(info.lane, _banner_left)
	skill_banner.visible = true


func _refresh_skill_banner_text() -> void:
	var text: String = _banner_info.text
	if _banner_delay > 0.0:
		text += "\n%d초 뒤 발동" % ceili(_banner_delay)
	skill_banner_text.text = text


## 이 스킬이 영향을 주는 레인의 미니맵을 알림이 떠 있는 동안 깜빡이게 한다.
## lane: BossSkills의 lane 값 ("player"=내 레인 / "boss"=보스 레인 / "both"). 지금 보고 있는 레인은 깜빡이지 않는다.
func _alert_minimaps(lane: String, seconds: float) -> void:
	var targets: Array[int] = []
	if lane == "player" or lane == "both":
		targets.append(game_field.local_player_id)
	if lane == "boss" or lane == "both":
		targets.append(GameField.BOSS_LANE_ID)
	for lane_id in targets:
		var view: MiniMapView = minimap_views.get(lane_id)
		if view != null:
			view.alert_left = seconds


## 게임이 끝나면 남은 알림을 지운다
func _clear_skill_banner() -> void:
	time_warning.visible = false
	_banner_queue.clear()
	_banner_left = 0.0
	skill_banner.visible = false
	for view in minimap_views.values():
		view.alert_left = 0.0


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
	_play_running = true
	_refresh_start_button()


## 일시정지 화면 (일시정지 버튼은 위쪽 메인 줄의 [시작] 버튼이 시작 뒤에 바뀐 것)
func _create_pause_ui() -> void:
	pause_button = Button.new()
	pause_button.z_index = 85  # 상태 표시와 같은 높이: 타워/몬스터(1~4)보다 위
	pause_button.custom_minimum_size = Vector2(PAUSE_SIZE, PAUSE_SIZE)
	pause_button.size = Vector2(PAUSE_SIZE, PAUSE_SIZE)
	pause_button.tooltip_text = "시작 / 일시정지 (P / Esc)"
	pause_button.focus_mode = Control.FOCUS_NONE  # 스페이스/엔터가 이 버튼을 누르지 않게
	pause_button.pressed.connect(_on_pause_button_pressed)
	pause_icon = PauseIcon.new()
	pause_button.add_child(pause_icon)
	pause_icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(pause_button)
	game_field.ui_blockers.append(pause_button)  # 이 버튼을 눌러도 뒤의 맵이 클릭되지 않게

	pause_overlay = PauseOverlay.new()
	add_child(pause_overlay)
	pause_overlay.resume_requested.connect(func(): _set_paused(false))
	pause_overlay.restart_requested.connect(reset_game)
	pause_overlay.quit_requested.connect(func(): get_tree().quit())
	game_field.ui_blockers.append(pause_overlay)
	game_field.tower_selected.connect(_on_tower_selected)


func _toggle_pause() -> void:
	_set_paused(not get_tree().paused)


func _set_paused(on: bool) -> void:
	if on == get_tree().paused:
		return
	if on:
		# 끝난 게임, 길 막힘 확인창이 떠 있을 때는 멈추지 않는다 (확인창은 멈춘 화면에서 눌리지 않아 갇힌다)
		if game_over_screen.visible or confirm_dialog.visible:
			return
		_paused_at_ms = Time.get_ticks_msec()
	else:
		Monster.pause_offset_ms += Time.get_ticks_msec() - _paused_at_ms
	get_tree().paused = on
	pause_overlay.show_menu(on)
	Log.info(Log.Category.GAME, "일시정지 %s" % ("켬" if on else "끔"))


## 맵 오른쪽 위 버튼: 시작 전에는 재생(▶) 아이콘으로 [시작], 시작한 뒤에는 막대(⏸) 아이콘으로 [일시정지]. 게임이 끝나면 숨긴다
func _refresh_start_button() -> void:
	pause_button.visible = not game_over_screen.visible
	if pause_icon.playing == _play_running:  # 아이콘이 상태와 다르면 갱신
		pause_icon.playing = not _play_running
		pause_icon.queue_redraw()
	pause_button.tooltip_text = "일시정지 (P / Esc)" if _play_running else "시작"


func _on_pause_button_pressed() -> void:
	if _play_running:
		_toggle_pause()
	else:
		_on_start_pressed()


## 시작/일시정지 버튼 아이콘 (재생 삼각형 / 막대 두 개. 글꼴에 기호가 없을 수 있어 직접 그린다)
class PauseIcon extends Control:
	var playing := true  # true: 시작 전이라 재생(▶) 모양

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE

	func _draw() -> void:
		if playing:
			var c := size * 0.5
			var r := minf(size.x, size.y) * 0.27
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(-r * 0.7, -r * 1.1), c + Vector2(-r * 0.7, r * 1.1), c + Vector2(r * 1.15, 0)]), Color(0.6, 1.0, 0.65))
			return
		var bar := Vector2(size.x * 0.16, size.y * 0.46)
		var top := (size.y - bar.y) * 0.5
		draw_rect(Rect2(Vector2(size.x * 0.5 - bar.x * 1.6, top), bar), Color.WHITE)
		draw_rect(Rect2(Vector2(size.x * 0.5 + bar.x * 0.6, top), bar), Color.WHITE)


## 일시정지 화면: 게임이 멈춘 동안에도 눌리고 키를 받아야 하므로 PROCESS_MODE_ALWAYS.
## 다시 시작/종료는 진행 상황이 사라지므로 화면 가운데 확인창에서 [확인]을 눌러야 실행된다.
class PauseOverlay extends Control:
	signal resume_requested
	signal restart_requested
	signal quit_requested

	var _topics: Array = []   # 설명서 항목: [{name, color, text, children: [{name, color, text}]}] (게임 데이터로 만든다)
	var _stack: Array = []        # 설명서에서 들어와 있는 경로 (항목 -> 세부 항목 -> ...)

	var restart_button: Button
	var quit_button: Button
	var confirm_layer: Control      # 다시 시작/종료 확인창 (화면 가운데)
	var confirm_label: Label
	var _confirm_signal: Signal     # [확인]을 누르면 보낼 신호
	var title_label: Label
	var menu_box: VBoxContainer     # 1단계: 계속하기 / 설명서 / 다시 시작 / 종료
	var guide_box: VBoxContainer    # 2단계: 설명서 항목 버튼들
	var page_box: VBoxContainer     # 3단계: 항목 하나의 설명 (+ 세부 항목 버튼)
	var page_text: RichTextLabel
	var child_grid: GridContainer   # 세부 항목 버튼 (타워 종류 / 진화 계열 / 색깔)
	var page_back: Button
	var _page := "menu"             # 지금 보이는 단계: menu / guide / page / sub(세부 항목)

	func _init() -> void:
		process_mode = Node.PROCESS_MODE_ALWAYS
		visible = false
		z_index = 500  # 시작 버튼(101)·배너(110)보다 위, 승리/패배 화면(1000)보다 아래
		mouse_filter = Control.MOUSE_FILTER_STOP  # 뒤의 맵/버튼이 눌리지 않게

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.65)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
		style.border_color = Color(0.4, 0.4, 0.5)
		style.set_border_width_all(3)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(24)
		panel.add_theme_stylebox_override("panel", style)
		panel.custom_minimum_size = Vector2(540, 0)
		center.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 14)
		panel.add_child(box)
		title_label = Label.new()
		title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		title_label.add_theme_font_size_override("font_size", 32)
		box.add_child(title_label)

		menu_box = VBoxContainer.new()
		menu_box.add_theme_constant_override("separation", 14)
		box.add_child(menu_box)
		var guide := _make_button("설명서")
		guide.pressed.connect(_show_page.bind("guide"))
		menu_box.add_child(guide)
		var resume := _make_button("계속하기")
		resume.pressed.connect(func(): resume_requested.emit())
		menu_box.add_child(resume)
		restart_button = _make_button("다시 시작")
		restart_button.pressed.connect(_ask.bind("다시 시작하시겠습니까?", restart_requested))
		menu_box.add_child(restart_button)
		quit_button = _make_button("종료")
		quit_button.pressed.connect(_ask.bind("종료하시겠습니까?", quit_requested))
		menu_box.add_child(quit_button)

		# 설명서 항목 버튼 (2열)
		guide_box = VBoxContainer.new()
		guide_box.add_theme_constant_override("separation", 14)
		box.add_child(guide_box)
		var grid := GridContainer.new()
		grid.columns = 2
		grid.add_theme_constant_override("h_separation", 12)
		grid.add_theme_constant_override("v_separation", 12)
		guide_box.add_child(grid)
		_topics = _build_topics()
		for i in range(_topics.size()):
			grid.add_child(_make_topic_button(_topics[i], _show_topic.bind(i)))
		var guide_back := _make_button("← 뒤로")
		guide_back.pressed.connect(_show_page.bind("menu"))
		guide_box.add_child(guide_back)

		# 항목 하나의 설명
		page_box = VBoxContainer.new()
		page_box.add_theme_constant_override("separation", 14)
		box.add_child(page_box)
		page_text = RichTextLabel.new()
		page_text.bbcode_enabled = true
		page_text.fit_content = true
		page_text.scroll_active = false
		page_text.custom_minimum_size = Vector2(0, 150)
		page_text.add_theme_font_size_override("normal_font_size", 20)
		page_text.add_theme_constant_override("line_separation", 6)
		page_box.add_child(page_text)
		child_grid = GridContainer.new()
		child_grid.columns = 2
		child_grid.add_theme_constant_override("h_separation", 12)
		child_grid.add_theme_constant_override("v_separation", 10)
		page_box.add_child(child_grid)
		page_back = _make_button("← 목록")
		page_back.pressed.connect(go_back)
		page_box.add_child(page_back)
		_show_page("menu")
		_create_confirm()

	## 확인창: 화면 정가운데에 질문 한 줄과 [확인] [취소]
	func _create_confirm() -> void:
		confirm_layer = Control.new()
		confirm_layer.visible = false
		confirm_layer.mouse_filter = Control.MOUSE_FILTER_STOP  # 뒤의 일시정지 버튼이 눌리지 않게
		add_child(confirm_layer)
		confirm_layer.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var dim := ColorRect.new()
		dim.color = Color(0, 0, 0, 0.5)
		dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
		confirm_layer.add_child(dim)
		dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var center := CenterContainer.new()
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		confirm_layer.add_child(center)
		center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var panel := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.12, 0.12, 0.18, 1.0)
		style.border_color = Color(0.5, 0.5, 0.65)
		style.set_border_width_all(3)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(24)
		panel.add_theme_stylebox_override("panel", style)
		panel.custom_minimum_size = Vector2(420, 0)
		center.add_child(panel)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 20)
		panel.add_child(box)
		confirm_label = Label.new()
		confirm_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		confirm_label.add_theme_font_size_override("font_size", 26)
		box.add_child(confirm_label)
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 14)
		box.add_child(row)
		var ok := _make_button("확인")
		ok.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		ok.pressed.connect(_on_confirm_ok)
		row.add_child(ok)
		var cancel := _make_button("취소")
		cancel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		cancel.pressed.connect(_close_confirm)
		row.add_child(cancel)

	func _ask(question: String, sig: Signal) -> void:
		confirm_label.text = question
		_confirm_signal = sig
		confirm_layer.visible = true

	func _on_confirm_ok() -> void:
		var sig := _confirm_signal
		_close_confirm()
		sig.emit()

	func _close_confirm() -> void:
		confirm_layer.visible = false

	## 단계 전환: menu(일시정지) / guide(설명서 항목 목록) / page(항목 하나)
	func _show_page(page: String) -> void:
		_page = page
		title_label.remove_theme_color_override("font_color")
		menu_box.visible = page == "menu"
		guide_box.visible = page == "guide"
		page_box.visible = page == "page"
		if confirm_layer != null:
			_close_confirm()
		match page:
			"menu": title_label.text = "일시정지"
			"guide": title_label.text = "설명서"

	func _make_topic_button(info: Dictionary, on_press: Callable) -> Button:
		var b := _make_button(info.name)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		b.add_theme_color_override("font_color", info.color)
		b.pressed.connect(on_press)
		return b

	## 목록에서 항목을 연다
	func _show_topic(index: int) -> void:
		_stack = [_topics[index]]
		_show_page("page")
		_render_node()

	## 지금 경로의 맨 끝 항목을 보여준다: 설명 + (있으면) 세부 항목 버튼. 세부 항목은 몇 단계든 들어갈 수 있다.
	func _render_node() -> void:
		var node: Dictionary = _stack.back()
		var kids: Array = node.get("children", [])
		title_label.text = node.name
		title_label.add_theme_color_override("font_color", node.color)
		page_text.text = node.text
		for c in child_grid.get_children():
			child_grid.remove_child(c)
			c.queue_free()
		child_grid.columns = 2 if kids.size() <= 8 else 3  # 몬스터처럼 많으면 3열로 줄여서 화면에 들어오게
		for kid in kids:
			var b := _make_topic_button(kid, _open_child.bind(kid))
			if kids.size() > 8:
				b.custom_minimum_size.y = 46
				b.add_theme_font_size_override("font_size", 18)
			child_grid.add_child(b)
		child_grid.visible = not kids.is_empty()
		page_back.text = "← 목록" if _stack.size() == 1 else "← 뒤로"

	func _open_child(kid: Dictionary) -> void:
		_stack.append(kid)
		_render_node()

	## 설명서 내용. 타워/진화/색깔은 게임 데이터에서 만들어서 수치가 바뀌어도 맞는다.
	func _build_topics() -> Array:
		var gold := Color(1.0, 0.85, 0.4)
		var towers: Array = []
		for id in Balance.TOWER_KINDS:
			var kind := Balance.tower_kind(id)
			var evos: Array = Evolutions.TREE[id].map(func(e): return Evolutions.DATA[e].name)
			towers.append({"name": kind.name, "color": kind.color,
				"text": "%s\n\n진화: %s" % [Balance.tower_tooltip(kind), " / ".join(evos)]})
		var upgrades: Array = []
		for evo in Evolutions.ORDER:
			var d: Dictionary = Evolutions.DATA[evo]
			var lines: Array[String] = [Evolutions.tooltip(evo), "", "업그레이드 (Lv1 → Lv%d)" % Evolutions.MAX_LEVEL]
			for stat in Evolutions.STATS[evo]:
				lines.append("%s %s: %s → %s" % [stat.s, stat.name, Evolutions.stat_value_text(evo, stat, 1), Evolutions.stat_value_text(evo, stat, Evolutions.MAX_LEVEL)])
			upgrades.append({"name": d.name, "color": d.color, "text": "\n".join(lines)})
		var monsters: Array = []  # 유형 -> 몬스터 하나하나
		for cat in Monsters.CATEGORIES:
			var cat_info: Dictionary = Monsters.CATEGORY_DATA[cat]
			var kinds: Array = []
			for kind_id in Monsters.slots_of(cat):
				if kind_id == "":
					continue
				var md: Dictionary = Monsters.DATA[kind_id]
				kinds.append({"name": md.name, "color": Monsters.FAMILY_COLORS.get(md.get("family", ""), cat_info.color).lightened(0.2),
					"text": Monsters.tooltip(kind_id)})
			monsters.append({"name": cat_info.name, "color": cat_info.color, "children": kinds, "text": "%s\n\n몬스터를 눌러 자세히 보세요." % cat_info.desc})
		var colors: Array = []
		for info in Balance.TOWER_COLORS:
			colors.append({"name": info.name, "color": info.color.lightened(0.35), "text": Balance.color_guide(info.name)})
		return [
			{"name": "목표", "color": gold, "children": [],
				"text": "제한시간 안에 보스를 무찌르세요.\n보스가 보내는 몬스터가 끝까지 가지 못하게 막아야 해요.\n생명이 0이 되거나 시간이 끝나면 패배예요."},
			{"name": "진행", "color": gold, "children": [],
				"text": "게임을 시작하면 %d초마다 수입이 들어오고,\n보스가 몬스터들을 보내와요.\n시작 전에는 타워를 미리 지을 수 있어요." % int(Balance.INCOME_INTERVAL)},
			{"name": "타워", "color": Color(0.5, 0.85, 1.0), "children": towers,
				"text": "타워를 고르고 맵의 빈 타일을 누르면 지어져요.\n지은 타워를 누르면 진화와 색깔 바꾸기를 할 수 있어요.\n길을 완전히 막으면 몬스터가 타워를 부수며 와요.\n\n타워 종류를 눌러 자세히 보세요."},
			{"name": "몬스터", "color": Color(1.0, 0.6, 0.55), "children": monsters,
				"text": "몬스터 → 유형 선택 → 몬스터 선택 → [생성].\n보스를 공격하고, 수입도 늘어나요.\n\n유형을 눌러 몬스터를 확인하세요."},
			{"name": "업그레이드", "color": Color(0.7, 0.9, 0.5), "children": upgrades,
				"text": "계열을 고르고 항목을 올리면 그 계열 타워가 모두 강해져요.\n항목마다 Lv%d까지 올릴 수 있어요.\n\n계열을 눌러 자세히 보세요." % Evolutions.MAX_LEVEL},
			{"name": "색깔 보너스", "color": Color(0.85, 0.65, 1.0), "children": colors,
				"text": "타워 색은 지을 때 랜덤으로 정해져요 (바꾸기 %d골드).\n같은 색 타워가 상하좌우로 이어질수록 효과가 커져요 (타워 1개당 +%d%%).\n\n색을 눌러 효과를 확인하세요." % [Balance.RECOLOR_COST, roundi(Balance.CLUSTER_BONUS_PER_TOWER * 100.0)]},
			{"name": "미니맵", "color": Color(0.6, 0.66, 1.0), "children": [],
				"text": "1~8은 각자의 레인, B는 보스 레인이에요.\n누르면 그 레인으로 이동해요."},
			{"name": "숨은 요소", "color": Color(0.75, 0.75, 0.75), "children": [],
				"text": "게임 곳곳에 이스터에그가 숨어 있어요.\n직접 찾아보세요!"},
		]

	## 뒤로: 항목 -> 목록 -> 일시정지 -> 계속하기
	func go_back() -> void:
		if confirm_layer.visible:  # 확인창이 떠 있으면 취소
			_close_confirm()
			return
		match _page:
			"page":
				if _stack.size() > 1:
					_stack.pop_back()
					_render_node()
				else:
					_show_page("guide")
			"guide": _show_page("menu")
			_: resume_requested.emit()

	func _make_button(text: String) -> Button:
		var b := Button.new()
		b.text = text
		b.custom_minimum_size = Vector2(0, 56)  # 폰: 터치하기 쉬운 높이
		b.add_theme_font_size_override("font_size", 22)
		return b

	func show_menu(on: bool) -> void:
		_show_page("menu")
		visible = on

	func _input(event: InputEvent) -> void:
		if visible and event is InputEventKey and event.pressed and not event.echo \
				and (event.keycode == KEY_ESCAPE or event.keycode == KEY_P):
			if event.keycode == KEY_ESCAPE:
				go_back()  # Esc는 한 단계씩 뒤로, P는 바로 계속하기
			else:
				resume_requested.emit()
			get_viewport().set_input_as_handled()

	func _notification(what: int) -> void:
		if what == NOTIFICATION_WM_GO_BACK_REQUEST and visible:  # 폰의 뒤로 가기 = 한 단계 뒤로 (처음 화면이면 계속하기)
			go_back()


func _process(delta):
	if _play_running and not game_over_screen.visible:
		_play_time += delta
	if map_overlay != null:  # 맵 왼쪽 위 모서리를 따라간다 (맵 크기/위치가 바뀌어도)
		map_overlay.global_position = game_field.global_position + Vector2(OVERLAY_MARGIN, OVERLAY_MARGIN)
	if pause_button != null:  # 맵 오른쪽 위 모서리
		var rect := game_field.get_global_rect()
		pause_button.global_position = Vector2(rect.end.x - PAUSE_SIZE - OVERLAY_MARGIN, rect.position.y + OVERLAY_MARGIN)
	_update_skill_banner(delta)
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
	# 맵에서 타워를 누르면 상단이 그 타워 화면으로 바뀌고, 선택이 풀리면 메인으로 돌아온다
	var picked := game_field.get_selected_tower()
	if picked != null:
		_enter_tower_sel()
	elif _view == "tower_sel":
		_leave_tower_sel()
	_update_tower_info(lane)
	_refresh_upgrade_views(lane)
	_update_explain(lane)
	_refresh_action_buttons(lane, boss)

	_update_status_panel(lane, boss)
	_refresh_tower_highlight()
	_refresh_start_button()
	_check_boss_time_warning(boss)

	# 하단 메시지: 상태, 그리고 보스 정보는 보스 레인을 보고 있을 때만 (다른 건 왼쪽 위 상태 패널로 옮겼다)
	var lines: Array[String] = []
	match boss.state:
		BossController.State.WAITING: lines.append("[시작 대기]")
		BossController.State.VICTORY: lines.append("[전체 승리!]")
		BossController.State.DEFEAT: lines.append("[패배]")
	if game_field.current_player_id == GameField.BOSS_LANE_ID:
		lines.append("BOSS Lv.%d/%d %s%s  %d/%d  남은 %d초" % [
			boss.level, BossLevels.COUNT, boss.level_data.name, boss.phase_text(), int(boss.hp), int(boss.max_hp), int(boss.time_left)])
		if boss.total_dps > 0.0:  # 보스 앞에 서 있는 몬스터들이 1초에 주는 피해
			var eta := boss.hp / boss.effective_dps()
			lines.append("초당 %.1f 피해 (%d마리) → %d초 뒤 처치%s" % [
				boss.effective_dps(), boss.get_attacker_count(), ceili(eta), " (시간 부족!)" if eta > boss.time_left else ""])
		else:
			lines.append("보스를 공격 중인 몬스터 없음")
	hud_label.text = "\n".join(lines)
	hud_label.visible = not lines.is_empty()

func _update_tower_info(lane: LaneController):
	var t := game_field.get_selected_tower()
	if t == null:
		tower_info_label.visible = false
		return
	tower_info_label.visible = _view == "tower_sel"  # 타워 화면일 때만 (몬스터/업그레이드 화면에서는 하단을 비운다)
	var title: String = t.kind.name
	if t.evolution != "":
		title += " · " + Evolutions.evo_name(t.evolution)
	var text := "%s · 피해 %.1f · 초당 %.2f회 · 사거리 %.1f\n처치 %d · 누적 %.0f" % [
		title, t.cur_damage(), t.cur_attack_rate(), t.cur_range(), t.kills, t.total_damage]
	if t.durability < Balance.TOWER_DURABILITY - 0.001:  # 슬라임 새끼에게 갉인 타워 (회복되지 않는다)
		text += "\n내구도 %d / %d" % [roundi(t.durability), roundi(Balance.TOWER_DURABILITY)]
	if t.sealed_time > 0.0:
		text += "\n봉인 %d초" % ceili(t.sealed_time)
	match t.evolution:
		"growth":
			text += "\n치명타 %.1f%% · 광란 x%d" % [t.crit_chance() * 100.0, t.haste_stacks]
		"charge":
			text += "\n충전 %.1f / %.0f초" % [t.charge, t.charge_max()]
	text += "\n" + t.color_bonus_text()
	var b_known := t.evolution != "" and t.b_learned
	tower_info_label.text = text.get_slice("\n", 0) if _tower_pick != "" else text  # 진화를 고르는 중에는 설명이 잘 보이게 첫 줄만

	recolor_button.text = "색깔 바꾸기\n(%d골드)" % Balance.RECOLOR_COST  # 한 줄이면 칸 폭에서 잘린다 (회복 버튼과 같은 두 줄 형식)
	recolor_button.tooltip_text = "이 타워의 색깔을 지금 색을 뺀 6색 중 랜덤으로 바꿉니다. 색깔 보너스는 그 색의 업그레이드를 따라갑니다."
	recolor_button.disabled = t.lane != lane or lane.gold < Balance.RECOLOR_COST
	var hurt := t.durability < Balance.TOWER_DURABILITY - 0.001
	heal_button.text = "회복 (%d골드)
내구도 %d/%d" % [Balance.HEAL_COST, roundi(t.durability), roundi(Balance.TOWER_DURABILITY)]
	heal_button.disabled = t.lane != lane or not hurt or lane.gold < Balance.HEAL_COST

	# 진화 선택: 진화 전이면 계열 2개 중 하나, 진화했는데 B가 남았으면 B 진화 하나. 고르면 하단에 설명이 나오고 [진화]를 눌러야 진화한다.
	if _pick_tower != t:
		_tower_pick = ""
		_pick_tower = t
	var can_pick := t.can_evolve()
	var can_b := t.evolution != "" and not b_known
	var choices: Array = Evolutions.TREE[t.kind.id]
	for i in range(evolve_buttons.size()):
		var eb := evolve_buttons[i]
		var id := ""
		if can_pick:
			id = choices[i]
			eb.text = "%s 진화" % Evolutions.evo_name(id)
			eb.add_theme_color_override("font_color", Evolutions.DATA[id].color)
		elif can_b and i == 0:
			id = "B"
			eb.text = "B 진화\n%s" % Evolutions.skill_name(t.evolution, "B")
			eb.add_theme_color_override("font_color", Evolutions.DATA[t.evolution].color)
		evolve_ids[i] = id
		eb.modulate = Color.WHITE if id != "" else Color(1, 1, 1, 0)  # 안 쓰는 칸은 투명하게 (격자 배치 유지)
		eb.mouse_filter = Control.MOUSE_FILTER_STOP if id != "" else Control.MOUSE_FILTER_IGNORE
		eb.disabled = id == ""
		if id != "" and id == _tower_pick:
			_style_selected(eb)
		else:
			_clear_selected_style(eb)
	if _tower_pick != "" and not (_tower_pick in evolve_ids):
		_tower_pick = ""  # 진화가 끝나서 고른 것이 사라졌다


## 고른 진화의 비용 (-1: 고른 것 없음)
func _pick_cost(t: Tower, lane: LaneController) -> int:
	if t == null or _tower_pick == "":
		return -1
	return lane.learn_cost(t) if _tower_pick == "B" else Balance.EVOLVE_COST


## 선택한 타워의 색깔 바꾸기 (골드, 랜덤)
func _on_recolor_selected_pressed():
	game_field.recolor_selected_tower()


## 진화 선택 버튼: 고르기만 한다 (하단에 설명). 실제 진화는 오른쪽 아래 [진화] 버튼
func _on_evolve_pressed(index: int):
	if evolve_ids[index] != "":
		_tower_pick = evolve_ids[index]
	_request_refresh()


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
			KEY_ESCAPE, KEY_P:
				_toggle_pause()  # 종료는 일시정지 화면의 [종료] 버튼으로

## 폰의 뒤로 가기: 상단 화면을 한 단계 뒤로 (타워 화면이면 건설도 끝) -> 타워 선택 해제 -> 그래도 없으면 일시정지 화면
## (일시정지 중의 뒤로 가기는 PauseOverlay가 "계속하기"로 처리한다)
## 앱이 백그라운드로 가거나 창이 포커스를 잃으면 진행 중인 게임을 자동으로 멈춘다.
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# [업그레이드] 버튼은 항목 화면을 처음 열 때 트리에 붙는다. 한 번도 안 열고 끝나면 부모 없이 남아 누수가 되므로 직접 정리한다
		if detail_action != null and is_instance_valid(detail_action) and detail_action.get_parent() == null:
			detail_action.free()
		return
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _play_running and pause_overlay != null:
			_set_paused(true)
		return
	if what != NOTIFICATION_WM_GO_BACK_REQUEST or get_tree().paused:
		return
	match _view:
		"monster_kinds":
			_show_view("monster")
			return
		"detail":
			_show_view("evos")
			return
		"evos", "colors":
			_show_view("upgrade")
			return
		"tower_sel":
			_on_tower_sel_back_pressed()
			return
		"tower", "monster", "upgrade":
			_show_view("main")
			return
	if game_field.current_tool != GameField.PlacementTool.NONE:
		game_field.set_current_tool(GameField.PlacementTool.NONE)
	elif game_field.get_selected_tower() != null:
		game_field.select_tower(null)
	elif _play_running:
		_set_paused(true)
	else:
		get_tree().quit()  # 시작 전에는 바로 종료


func reset_game():
	Log.info(Log.Category.GAME, "게임 리셋")
	if get_tree().paused:
		_set_paused(false)  # 멈춘 채로 다시 불러오면 새 장면도 멈춰 있다
	get_tree().reload_current_scene()

# 버튼 클릭 이벤트 핸들러들
func _on_tower_button_pressed():
	# 타워 배럭으로 전환
	Log.info(Log.Category.UI, "타워 배럭 열기")
	_show_view("tower")

## 타워 화면의 [←]: 메인으로 돌아가고 건설 모드도 끝난다 (_show_view가 건설 도구를 끈다)
func _on_tower_back_pressed():
	_show_view("main")

## 건설할 타워를 고른다. 바로 짓지 않고, 하단 메시지 칸에 설명이 나온다. 이 상태에서 맵의 빈 타일을 누르면 지어진다.
## [←]로 타워 화면을 나가면 더는 지어지지 않는다.
func _on_tower_kind_selected(kind_id: String):
	if game_field:
		# 이미 고른 타워를 한 번 더 누르면 건설 모드 해제 (폰에는 우클릭이 없다)
		if game_field.current_tool == GameField.PlacementTool.TOWER and game_field.selected_tower_kind == kind_id:
			game_field.set_current_tool(GameField.PlacementTool.NONE)
		else:
			game_field.set_tower_kind(kind_id)
			game_field.set_current_tool(GameField.PlacementTool.TOWER)
	_refresh_tower_highlight()
	_request_refresh()

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
	# 몬스터 종류 화면 -> 유형 화면으로 돌아가기
	Log.info(Log.Category.UI, "몬스터 유형 화면으로")
	_show_view("monster")


## 몬스터 유형을 골랐다: 그 유형의 몬스터 종류를 보여 준다
func _on_monster_type_selected(cat: String) -> void:
	Log.info(Log.Category.UI, "몬스터 유형 선택: %s" % cat)
	_populate_monster_buttons(cat)
	_show_view("monster_kinds")


## 몬스터를 골랐다: 하단에 설명이 나온다. 미니맵 왼쪽 아래 [생성] 버튼을 눌러야 만들어진다 (누를 때마다 1마리).
func _on_monster_selected(button_index: int):
	var slot_idx := button_index - 1
	if slot_idx < 0 or slot_idx >= _monster_slots.size() or _monster_slots[slot_idx] == "":
		return  # 쓰지 않는 칸 / 계열 사이 빈칸
	_sel_monster = _monster_slots[slot_idx]
	_refresh_monster_highlight()
	_refresh_now()


## 보스 전체 승리
func _on_boss_defeated() -> void:
	_clear_skill_banner()
	var stats := _collect_game_stats(true)
	game_over_screen.show_result(true, stats)


## 보스 패배
func _on_boss_failed(reason: String) -> void:
	Log.info(Log.Category.GAME, "패배 사유: %s" % reason)
	_clear_skill_banner()
	var stats := _collect_game_stats(false)
	game_over_screen.show_result(false, stats)


## 게임 통계 수집
func _collect_game_stats(is_victory: bool) -> Dictionary:
	var stats := {}
	var lane: LaneController = game_field.lanes.get(game_field.local_player_id)
	var boss: BossController = game_field.boss

	if boss:
		stats.boss_level = boss.level if is_victory else boss.level
		stats.total_boss_levels = BossLevels.COUNT

	# 플레이 시간
	if _play_running:
		stats.play_time = _play_time

	if lane:
		# 타워 통계
		var tower_count := 0
		var total_dmg := 0.0
		var total_kills := 0
		for tower in lane.towers:
			tower_count += 1
			total_dmg += tower.total_damage
			total_kills += tower.kills
		stats.towers_built = tower_count
		stats.total_tower_damage = total_dmg
		stats.total_tower_kills = total_kills

		# 경제
		stats.final_gold = lane.gold_shown()
		stats.final_income = lane.income

	# 몬스터 파견 통계
	if boss:
		stats.monsters_sent = boss.sent_count  # 죽은 몬스터도 센다

		# 보스 피해 (내 기여도)
		if boss.damage_by_player.has(game_field.local_player_id):
			stats.boss_damage = boss.damage_by_player[game_field.local_player_id]
		else:
			stats.boss_damage = 0.0

		# 플레이어별 기여도 (전체)
		var total_dmg := 0.0
		for dmg in boss.damage_by_player.values():
			total_dmg += dmg

		if total_dmg > 0.0:
			var contributions: Array = []
			for player_id in boss.damage_by_player:
				var dmg: float = boss.damage_by_player[player_id]
				contributions.append({
					"player_id": player_id,
					"damage": dmg,
					"percent": dmg / total_dmg * 100.0
				})
			contributions.sort_custom(func(a, b): return a.damage > b.damage)
			stats.contributions = contributions

	return stats


## 재도전 버튼
func _on_game_over_restart() -> void:
	reset_game()


## 종료 버튼
func _on_game_over_quit() -> void:
	get_tree().quit()