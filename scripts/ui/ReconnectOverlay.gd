extends Control
class_name ReconnectOverlay
## 온라인 판 중 연결이 끊겼을 때 판 화면 위에 뜨는 "재접속 중" 안내 (#23). 자동으로 다시 접속을 시도하는 동안 남은 유예 시간을 보여 주고,
## 아래의 [나가기]로 포기할 수 있다 (서버에는 유예가 지나야 이탈로 전해진다: 이미 끊긴 연결로는 알릴 길이 없다).
## 서버는 멈추지 않으니 이 화면 뒤에서도 판은 계속된다 (타워는 자동으로 싸우고 수입은 쌓인다).

signal leave_requested()

var client: NetClient
var title_label: Label
var time_label: Label
var leave_button: Button


func _init() -> void:
	visible = false
	z_index = 600  # 일시정지 화면(500)보다 위, 결과 화면(1000)보다 아래
	mouse_filter = Control.MOUSE_FILTER_STOP  # 뒤의 맵/버튼이 눌리지 않게


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.7)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 14)
	box.custom_minimum_size = Vector2(420, 0)
	center.add_child(box)
	title_label = Label.new()
	title_label.text = "연결이 끊겼습니다. 재접속 중…"
	title_label.add_theme_font_size_override("font_size", 28)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(title_label)
	time_label = Label.new()
	time_label.add_theme_font_size_override("font_size", 20)
	time_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	time_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.add_child(time_label)
	leave_button = Button.new()
	leave_button.text = "나가기"
	leave_button.custom_minimum_size = Vector2(0, 64)
	leave_button.add_theme_font_size_override("font_size", 22)
	leave_button.pressed.connect(func(): leave_requested.emit())
	box.add_child(leave_button)


func show_overlay() -> void:
	visible = true
	_refresh()


func hide_overlay() -> void:
	visible = false


func _process(_delta: float) -> void:
	if visible:
		_refresh()


func _refresh() -> void:
	if client == null or time_label == null:
		return
	time_label.text = "서버는 계속 돌아가고 타워는 자동으로 싸웁니다.\n%d초 안에 돌아오지 못하면 이 판에서 이탈됩니다." % ceili(client.reconnect_left())
