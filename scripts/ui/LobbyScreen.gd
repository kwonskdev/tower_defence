extends PanelContainer
class_name LobbyScreen
## 시작 전 대기방 화면 (#22). NetClient가 받은 로비 상태(lobby)로 참여자 목록과 준비 상태를 보여 주고, [준비] / [시작] / [나가기]를 서버로 보낸다.
## [준비]는 방장이 아닌 사람에게, [시작]은 방장에게만 보이고 모두 준비해야 눌린다. 시작하면 게임 화면으로 넘어가고 거기서 30초 카운트다운이 돈다.
## 접속(방 만들기/입장)과 메인 메뉴는 #26이 만든다. 그 메뉴가 접속을 마친 뒤 이 화면을 띄우고 setup(client)를 부른다.
## 닉네임은 접속(hello) 때 서버에 알려 주므로 메뉴에서 정한다 (Nicknames.load_saved() / Nicknames.save()).

signal leave_requested()
signal started()   # 서버가 판을 시작했다 (이 화면을 닫고 게임 화면으로 넘어간다)

var client: NetClient
var _title: Label
var _list: VBoxContainer
var _hint: Label
var _ready_button: Button
var _start_button: Button
var _leave_button: Button
var _ready_on := false


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
	_hint = Label.new()
	_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_hint.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	box.add_child(_hint)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	box.add_child(row)
	_ready_button = _button(row, "준비")
	_start_button = _button(row, "시작")
	_leave_button = _button(row, "나가기")
	_ready_button.pressed.connect(_on_ready_pressed)
	_start_button.pressed.connect(func(): if client != null: client.request_start())
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


func _on_ready_pressed() -> void:
	_ready_on = not _ready_on
	if client != null:
		client.set_ready(_ready_on)
	_ready_button.text = "준비 취소" if _ready_on else "준비"


## 서버가 준 로비 상태를 그린다 ({members: [{lane, name, ready, host}], host, max, can_start})
func show_lobby(view: Dictionary) -> void:
	var members: Array = view.get("members", [])
	_title.text = "대기방 %d/%d" % [members.size(), int(view.get("max", Balance.MAX_PLAYERS))]
	for child in _list.get_children():
		child.queue_free()
	var my_lane: int = client.player_id if client != null else -1
	var i_am_host := false
	for m in members:
		var lane := int(m.get("lane", -1))
		var label := Label.new()
		label.text = row_text(m, lane == my_lane)
		_list.add_child(label)
		if lane == my_lane and m.get("host", false):
			i_am_host = true
	_start_button.visible = i_am_host                      # 시작은 방장만
	_start_button.disabled = not view.get("can_start", false)  # 모두 준비해야 눌린다
	_ready_button.visible = not i_am_host                  # 방장은 늘 준비된 것으로 본다
	_hint.text = hint_text(view.get("can_start", false), i_am_host, members.size())


## 참여자 한 줄: "1  아름다운사과 (방장)  ◀ 나", "2  더러운컴퓨터 ✔ 준비"
static func row_text(member: Dictionary, is_me: bool) -> String:
	var text := "%d  %s" % [int(member.get("lane", 0)) + 1, str(member.get("name", ""))]
	if member.get("host", false):
		text += " (방장)"
	elif member.get("ready", false):
		text += " ✔ 준비"
	if is_me:
		text += "  ◀ 나"
	return text


## 안내 문구: 방장은 모두 준비할 때까지 기다리고, 나머지는 준비를 누른다. 시작하면 게임 화면에서 30초 뒤 자동 시작한다고 알린다.
static func hint_text(can_start: bool, i_am_host: bool, member_count: int) -> String:
	if i_am_host:
		if not can_start:
			return "모두 준비하면 시작할 수 있습니다"
		if member_count > 1:
			return "[시작]을 누르면 게임 화면에서 %d초 뒤 자동으로 시작합니다" % int(Balance.GAME_AUTO_START_SEC)
		return "[시작]을 누르면 게임 화면으로 넘어갑니다"
	return "[준비]를 누르고 방장이 시작하기를 기다리세요"
