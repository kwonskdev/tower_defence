extends Control
class_name MainMenu
## 메인 메뉴 (#26). 앱을 켜면 이 화면이 먼저 나온다: [혼자 하기] / [방 만들기] / [방 입장].
##  - [혼자 하기]: solo_chosen을 낸다. Boot가 지금까지와 똑같이 MainGame(로컬 시뮬레이션)을 연다. 네트워크는 쓰지 않는다.
##  - [방 만들기]: 서버에 접속해 방을 만들고(hello mode=create) 방 코드를 받아 대기방(LobbyScreen)으로 간다. [코드 복사]로 친구에게 알려 준다.
##  - [빠른 시작]: 코드 없이 자리 있는 공개 방에 들어가고, 없으면 새 공개 방을 만든다(mode=quick). 그 뒤는 방 만들기와 같은 대기방이다.
##  - [방 입장]: 방 코드를 쳐서 들어간다(mode=join). 없는 코드/가득 참/이미 시작/너무 많이 시도는 이유를 보여 준다.
## 닉네임과 서버 주소는 이 화면에서 정하고 기기에 저장한다 (닉네임은 서버가 정리/중복 제거해서 돌려준다).
## 서버 주소 기본값은 로컬 개발 서버다. 운영 서버 주소는 호스팅(#24)이 정해지면 default_server에 넣는다.
## 방장이 시작한 뒤의 게임 화면(서버 스냅샷을 그리는 MainGame)은 이 이슈 범위 밖이다: started 신호까지만 낸다.

signal solo_chosen()
signal online_started()    # 서버가 판을 시작했다 (온라인 게임 화면으로 넘어갈 때)

const DEFAULT_PORT := 47300
const CONNECT_TIMEOUT_SEC := 8.0
## 대기방에 있는 동안 이 간격(초)마다 서버에 ping을 보낸다. 서버는 대기방에 몇 시간 동안 아무 메시지도 없으면 앱이 죽은 방으로 보고 닫는데(RoomHub.IDLE_CLOSE_SEC),
## 살아 있는 클라이언트는 이 ping으로 "기다리는 중"임을 알린다 (사람이 얼마나 오래 기다려도 방이 닫히지 않게).
const PING_SEC := 60.0
const SERVER_KEY := "server"

var default_server := "127.0.0.1:%d" % DEFAULT_PORT
var profile_path := Nicknames.SAVE_PATH   # 닉네임/서버 주소를 저장하는 파일 (테스트는 다른 경로를 쓴다)
var client: NetClient = null
var lobby_screen: LobbyScreen = null

var name_edit: LineEdit
var server_edit: LineEdit
var code_edit: LineEdit
var solo_button: Button
var create_button: Button
var quick_button: Button
var join_button: Button
var status_label: Label
var code_label: Label
var copy_button: Button

var _form: VBoxContainer
var _lobby_box: VBoxContainer
var _connecting_left := -1.0
var _ping_left := PING_SEC


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var root := VBoxContainer.new()
	root.custom_minimum_size = Vector2(340, 0)
	root.add_theme_constant_override("separation", 10)
	center.add_child(root)

	var title := Label.new()
	title.text = "Lane Wars"
	title.add_theme_font_size_override("font_size", 34)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	root.add_child(title)

	_form = VBoxContainer.new()
	_form.add_theme_constant_override("separation", 10)
	root.add_child(_form)
	solo_button = _button(_form, "혼자 하기")
	_form.add_child(HSeparator.new())
	_form.add_child(_caption("닉네임"))
	name_edit = _line(_form, "", Balance.NICKNAME_MAX_LENGTH)
	_form.add_child(_caption("서버 주소"))
	server_edit = _line(_form, default_server, 80)
	quick_button = _button(_form, "빠른 시작")
	create_button = _button(_form, "방 만들기")
	_form.add_child(_caption("방 코드"))
	code_edit = _line(_form, "", 16)
	code_edit.placeholder_text = "예: K7M2QX"
	join_button = _button(_form, "방 입장")

	_lobby_box = VBoxContainer.new()
	_lobby_box.add_theme_constant_override("separation", 10)
	_lobby_box.visible = false
	root.add_child(_lobby_box)
	code_label = Label.new()
	code_label.add_theme_font_size_override("font_size", 26)
	code_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_lobby_box.add_child(code_label)
	copy_button = _button(_lobby_box, "코드 복사")

	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	root.add_child(status_label)

	_load_profile()
	solo_button.pressed.connect(func(): solo_chosen.emit())
	quick_button.pressed.connect(func(): start_online(NetProtocol.MODE_QUICK))
	create_button.pressed.connect(func(): start_online(NetProtocol.MODE_CREATE))
	join_button.pressed.connect(func(): start_online(NetProtocol.MODE_JOIN))
	copy_button.pressed.connect(copy_code)
	code_edit.text_submitted.connect(func(_t): start_online(NetProtocol.MODE_JOIN))


func _button(parent: Control, text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(0, 48)  # 폰에서 손가락으로 누를 수 있는 크기
	parent.add_child(b)
	return b


func _caption(text: String) -> Label:
	var l := Label.new()
	l.text = text
	return l


func _line(parent: Control, text: String, max_len: int) -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.max_length = max_len
	e.custom_minimum_size = Vector2(0, 44)
	parent.add_child(e)
	return e


func _load_profile() -> void:
	var cfg := ConfigFile.new()
	var has := cfg.load(profile_path) == OK
	var nick := Nicknames.sanitize(str(cfg.get_value("profile", "nickname", ""))) if has else ""
	name_edit.text = nick if nick != "" else Nicknames.generate()  # 저장은 접속할 때 한다 (메뉴만 열어 보고 닫아도 파일을 만들지 않는다)
	var saved_server := str(cfg.get_value("profile", SERVER_KEY, "")) if has else ""
	if saved_server != "":
		server_edit.text = saved_server


func _save_profile(nick: String, server: String) -> void:
	var cfg := ConfigFile.new()
	cfg.load(profile_path)
	cfg.set_value("profile", "nickname", nick)
	cfg.set_value("profile", SERVER_KEY, server)
	cfg.save(profile_path)


## 서버 주소 -> {host, port, tls}. "wss://호스트[:포트]"면 TLS(기기의 인증서 목록으로 서버 확인)로, "ws://호스트[:포트]"나 접두사가 없으면 평문으로 접속한다.
## 포트가 없으면 wss는 443, 그 밖에는 기본 포트(DEFAULT_PORT). 틀린 모양이면 빈 Dictionary.
static func parse_server(text: String) -> Dictionary:
	var t := text.strip_edges()
	var tls := false
	var lower := t.to_lower()
	if lower.begins_with("wss://"):
		tls = true
		t = t.substr(6)
	elif lower.begins_with("ws://"):
		t = t.substr(5)
	if t.ends_with("/"):
		t = t.left(t.length() - 1)
	if t == "" or t.contains("/") or t.contains(" "):
		return {}
	var parts := t.rsplit(":", true, 1)
	if parts.size() == 1:
		return {"host": parts[0], "port": 443 if tls else DEFAULT_PORT, "tls": tls}
	var port := ServerMain.parse_port(parts[1])
	if parts[0] == "" or port < 0:
		return {}
	return {"host": parts[0], "port": port, "tls": tls}


## 서버가 거부한 이유를 사람이 읽는 말로
static func reject_text(reason: String) -> String:
	match reason:
		NetProtocol.REJECT_NO_ROOM:
			return "없는 방 코드입니다. 코드를 다시 확인하세요."
		NetProtocol.REJECT_FULL:
			return "방이 가득 찼습니다 (최대 %d명)." % Balance.MAX_PLAYERS
		NetProtocol.REJECT_STARTED:
			return "이미 시작한 방입니다."
		NetProtocol.REJECT_TOO_MANY:
			return "잘못된 코드를 너무 많이 입력했습니다. 잠시 뒤에 다시 시도하세요."
		NetProtocol.REJECT_BUSY:
			return "서버가 가득 찼습니다. 잠시 뒤에 다시 시도하세요."
		NetProtocol.REJECT_PROTOCOL:
			return "앱 버전이 서버와 다릅니다. 앱을 업데이트하세요."
		_:
			return "접속하지 못했습니다 (%s)." % reason


## 방 만들기/입장을 시작한다 (MODE_CREATE/MODE_JOIN). 입력이 틀렸으면 이유를 보여 주고 접속하지 않는다.
func start_online(mode: String) -> void:
	if client != null:
		return  # 접속 중
	var target := parse_server(server_edit.text)
	if target.is_empty():
		_status("서버 주소를 '호스트:포트' (또는 wss://호스트) 모양으로 쓰세요.")
		return
	var code := RoomCodes.normalize(code_edit.text)
	if mode == NetProtocol.MODE_JOIN and not RoomCodes.is_valid_format(code):
		_status("방 코드는 %d자입니다 (헷갈리는 0/O/1/I/L은 쓰지 않습니다)." % RoomCodes.LENGTH)
		return
	var nick := Nicknames.sanitize(name_edit.text)
	if nick == "":
		nick = Nicknames.generate()
		name_edit.text = nick
	_save_profile(nick, server_edit.text.strip_edges())
	client = NetClient.new()
	client.player_name = nick
	client.join_mode = mode
	client.join_code = code if mode == NetProtocol.MODE_JOIN else ""
	add_child(client)
	client.joined.connect(_on_joined)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)
	if not client.connect_to(NetTransport.DEFAULT, str(target.host), int(target.port), TLSOptions.client() if target.tls else null):
		_reset_online("서버에 연결하지 못했습니다.")
		return
	_set_busy(true)
	_connecting_left = CONNECT_TIMEOUT_SEC
	_status("자리 있는 방을 찾는 중..." if mode == NetProtocol.MODE_QUICK else "접속 중...")


func _process(delta: float) -> void:
	if client != null and client.is_joined():
		_ping_left -= delta
		if _ping_left <= 0.0:
			_ping_left = PING_SEC
			client.ping()
	if _connecting_left < 0.0:
		return
	_connecting_left -= delta
	if _connecting_left <= 0.0:
		_reset_online("서버에 연결하지 못했습니다. 주소와 네트워크를 확인하세요.")


func _set_busy(busy: bool) -> void:
	for b in [solo_button, quick_button, create_button, join_button]:
		b.disabled = busy


func _status(text: String) -> void:
	status_label.text = text


func _on_joined(_player_id: int) -> void:
	_connecting_left = -1.0
	_form.visible = false
	_lobby_box.visible = true
	_refresh_code()
	client.lobby_changed.connect(func(_v): _refresh_code())
	_status("")
	lobby_screen = LobbyScreen.new()
	_lobby_box.add_child(lobby_screen)
	lobby_screen.setup(client)
	lobby_screen.leave_requested.connect(func(): _reset_online(""))
	lobby_screen.started.connect(func():
		_status("방장이 시작했습니다. (온라인 게임 화면은 아직 연결되지 않았습니다)")
		online_started.emit())


func _refresh_code() -> void:
	if client != null:
		code_label.text = "방 코드  %s%s" % [client.room_code, "  (공개 방)" if bool(client.lobby.get("public", false)) else ""]


func _on_rejected(reason: String, _info: Dictionary) -> void:
	_reset_online(reject_text(reason))


func _on_disconnected() -> void:
	if client != null and client.state != NetClient.State.REJECTED:
		_reset_online("서버와 연결이 끊겼습니다. 방이 닫혔을 수 있습니다.")


## 접속/대기방에서 처음 화면으로 돌아간다 (message가 있으면 보여 준다)
func _reset_online(message: String) -> void:
	_connecting_left = -1.0
	if client != null:
		client.close()
		client.queue_free()
		client = null
	if lobby_screen != null:
		lobby_screen.queue_free()
		lobby_screen = null
	_lobby_box.visible = false
	_form.visible = true
	_set_busy(false)
	_status(message)


## 방 코드를 클립보드에 복사한다. 복사한 글자를 돌려준다 (헤드리스에서는 클립보드가 없어 빈 글자).
func copy_code() -> String:
	if client == null or client.room_code == "":
		return ""
	if not DisplayServer.has_feature(DisplayServer.FEATURE_CLIPBOARD):
		_status("이 기기에서는 복사할 수 없습니다. 코드를 직접 알려 주세요: %s" % client.room_code)
		return ""
	DisplayServer.clipboard_set(client.room_code)
	_status("방 코드를 복사했습니다: %s" % client.room_code)
	return client.room_code
