extends PanelContainer
class_name LobbyScreen
## 시작 전 대기실 화면 (#22). NetClient가 받은 로비 상태(lobby)로 참여자 목록과 자동 시작까지 남은 시간만 보여 준다.
## 준비/시작 버튼은 없다 (오너 결정): 첫 입장 뒤 30초가 지나면 서버가 알아서 시작한다. 버튼은 [나가기]뿐이다.
## 접속(방 만들기/입장)과 메인 메뉴는 #26이 만든다. 그 메뉴가 접속을 마친 뒤 이 화면을 띄우고 setup(client)를 부른다.
## 닉네임은 접속(hello) 때 서버에 알려 주므로 메뉴에서 정한다 (Nicknames.load_saved() / Nicknames.save()).

signal leave_requested()
signal started()   # 서버가 판을 시작했다 (이 화면을 닫고 게임 화면으로 넘어간다)

var client: NetClient
var _title: Label
var _list: VBoxContainer
var _countdown: Label
var _leave_button: Button


func _init() -> void:
	custom_minimum_size = Vector2(320, 300)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	add_child(box)
	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 20)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(_title)
	_list = VBoxContainer.new()
	_list.size_flags_vertical = Control.SIZE_EXPAND_FILL
	box.add_child(_list)
	_countdown = Label.new()
	_countdown.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(_countdown)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_leave_button = _button(row, "나가기")
	_leave_button.pressed.connect(func(): leave_requested.emit())
	show_lobby({})


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.custom_minimum_size = Vector2(0, 44)  # 폰에서 손가락으로 누를 수 있는 크기
	parent.add_child(b)
	return b


func setup(p_client: NetClient) -> void:
	client = p_client
	client.lobby_changed.connect(show_lobby)
	client.game_started.connect(func(_players, _names): started.emit())
	if not client.lobby.is_empty():
		show_lobby(client.lobby)


## 서버가 준 로비 상태를 그린다 ({members: [{lane, name}], max, countdown})
func show_lobby(view: Dictionary) -> void:
	var members: Array = view.get("members", [])
	_title.text = "대기실 %d/%d" % [members.size(), int(view.get("max", Balance.MAX_PLAYERS))]
	for child in _list.get_children():
		child.queue_free()
	var my_lane: int = client.player_id if client != null else -1
	for m in members:
		var lane := int(m.get("lane", -1))
		var label := Label.new()
		label.text = row_text(m, lane == my_lane)
		_list.add_child(label)
	_countdown.text = countdown_text(float(view.get("countdown", -1.0)), members.size())


## 참여자 한 줄: "1  아름다운사과  ◀ 나"
static func row_text(member: Dictionary, is_me: bool) -> String:
	var text := "%d  %s" % [int(member.get("lane", 0)) + 1, str(member.get("name", ""))]
	if is_me:
		text += "  ◀ 나"
	return text


## 자동 시작 안내 문구. seconds < 0: 아직 안 셈, 0이고 혼자: 다른 사람 기다리는 중
static func countdown_text(seconds: float, member_count: int) -> String:
	if seconds < 0.0:
		return ""
	if seconds <= 0.0:
		return "다른 사람을 기다리는 중 (2명 이상이면 시작합니다)"
	if member_count < 2:
		return "%d초 뒤 자동 시작 (2명 이상일 때)" % int(ceilf(seconds))
	return "%d초 뒤 자동 시작" % int(ceilf(seconds))
