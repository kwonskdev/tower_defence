extends Control
class_name GameOverScreen
## 게임 종료 화면 (승리/패배). 통계를 보여주고 재도전/종료 버튼을 제공한다.
## UI는 _ready에서 이 클래스가 직접 만든다 (밖에서 자식을 붙이면 @onready 시점에 아직 없어서 null이 된다).
## 화면 전체를 덮고 클릭을 막으며, 평소에는 숨어 있다가 show_result()로 나타난다.

signal restart_requested
signal quit_requested

enum Result { VICTORY, DEFEAT }

var result: Result = Result.DEFEAT
var stats: Dictionary = {}  # 게임 통계

var title_label: Label
var stats_label: Label
var contribution_label: Label
var ghost_label: Label      # 유령 구간 점수 (레인 데미지 / 보스 레인 데미지, 환산값)
var copy_button: Button     # 결과를 텍스트로 클립보드에 복사한다 (공유용)
var restart_button: Button
var quit_button: Button


func _ready() -> void:
	visible = false
	z_index = 1000  # 다른 UI(HUD 100, 시작 버튼 101)보다 위
	mouse_filter = Control.MOUSE_FILTER_STOP  # 뒤의 버튼이 눌리지 않게
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()


func _build_ui() -> void:
	# 뒤 화면을 어둡게
	var dim := ColorRect.new()
	dim.color = Color(0, 0, 0, 0.65)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(dim)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	# 가운데 정렬
	var center := CenterContainer.new()
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	var panel := PanelContainer.new()
	var panel_style := StyleBoxFlat.new()
	panel_style.bg_color = Color(0.1, 0.1, 0.15, 0.95)
	panel_style.border_color = Color(0.4, 0.4, 0.5)
	panel_style.set_border_width_all(3)
	panel_style.set_corner_radius_all(8)
	panel_style.content_margin_left = 30
	panel_style.content_margin_right = 30
	panel_style.content_margin_top = 24
	panel_style.content_margin_bottom = 24
	panel.add_theme_stylebox_override("panel", panel_style)
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 16)
	panel.add_child(vbox)

	title_label = Label.new()
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.add_theme_font_size_override("font_size", 36)
	vbox.add_child(title_label)

	stats_label = Label.new()
	stats_label.add_theme_font_size_override("font_size", 18)
	stats_label.add_theme_color_override("font_color", Color(0.9, 0.9, 1.0))
	vbox.add_child(stats_label)

	contribution_label = Label.new()  # 참여 인원이 2명 이상일 때만 보인다
	contribution_label.add_theme_font_size_override("font_size", 14)
	contribution_label.add_theme_color_override("font_color", Color(0.8, 0.9, 1.0))
	contribution_label.visible = false
	vbox.add_child(contribution_label)

	ghost_label = Label.new()  # 유령 구간 점수. 길어질 수 있어서 줄을 바꿔 가며 보여 준다
	ghost_label.add_theme_font_size_override("font_size", 14)
	ghost_label.add_theme_color_override("font_color", Color(0.8, 0.88, 1.0))
	ghost_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ghost_label.visible = false
	vbox.add_child(ghost_label)

	var buttons := HBoxContainer.new()
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	buttons.add_theme_constant_override("separation", 20)
	vbox.add_child(buttons)

	copy_button = _make_button("결과 복사")  # 재도전/종료와 같은 줄에 둔다 (줄이 늘면 인원이 많은 판에서 화면 높이를 넘긴다)
	copy_button.pressed.connect(_on_copy_pressed)
	buttons.add_child(copy_button)

	restart_button = _make_button("재도전")
	restart_button.pressed.connect(_on_restart_pressed)
	buttons.add_child(restart_button)

	quit_button = _make_button("종료")
	quit_button.pressed.connect(_on_quit_pressed)
	buttons.add_child(quit_button)


func _make_button(text: String) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(150, 56)  # 폰: 터치하기 쉬운 높이
	b.add_theme_font_size_override("font_size", 20)
	return b


## 게임 종료 화면 표시
func show_result(is_victory: bool, game_stats: Dictionary) -> void:
	result = Result.VICTORY if is_victory else Result.DEFEAT
	stats = game_stats
	_update_ui()
	visible = true


func _update_ui() -> void:
	# 제목 (글꼴에 이모지가 없을 수 있어 글자만 쓴다)
	if result == Result.VICTORY:
		title_label.text = "승리!"
		title_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		title_label.text = "패배"
		title_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	var stat_lines: Array[String] = []

	if stats.has("boss_level"):
		var total: int = stats.get("total_boss_levels", 10)
		stat_lines.append("도달 보스 레벨: %d / %d" % [stats.boss_level, total])

	if stats.has("play_time"):
		var total_sec := int(stats.play_time)
		stat_lines.append("플레이 시간: %d분 %d초" % [floori(total_sec / 60.0), total_sec % 60])

	# 종료 시점에 남아 있는 타워만 센다 (부서진 타워는 빠진다)
	if stats.has("towers_built"):
		stat_lines.append("보유 타워: %d개" % stats.towers_built)

	if stats.has("total_tower_damage"):
		stat_lines.append("타워 총 피해: %s" % _format_number(stats.total_tower_damage))

	if stats.has("total_tower_kills"):
		stat_lines.append("타워 총 처치: %d" % stats.total_tower_kills)

	if stats.has("monsters_sent"):
		stat_lines.append("파견한 몬스터: %d마리" % stats.monsters_sent)

	if stats.has("boss_damage"):
		stat_lines.append("보스 피해: %s" % _format_number(stats.boss_damage))

	if stats.has("final_gold"):
		stat_lines.append("최종 골드: %d" % stats.final_gold)

	if stats.has("final_income"):
		stat_lines.append("최종 수입: +%d/%.0f초" % [stats.final_income, Balance.INCOME_INTERVAL])

	stats_label.text = "\n".join(stat_lines)

	# 플레이어 기여도 (2명 이상일 때)
	if stats.has("contributions") and stats.contributions.size() > 1:
		var contrib_lines: Array[String] = ["", "플레이어 기여도:"]
		for entry in stats.contributions:
			contrib_lines.append("  %s%s: %.1f%% (%s)%s" % [
				"▶ " if entry.get("me", false) else "", entry.get("name", "P%d" % (entry.player_id + 1)),
				entry.percent, _format_number(entry.damage), " - 탈락" if entry.get("eliminated", false) else ""])
		contribution_label.text = "\n".join(contrib_lines)
		contribution_label.visible = true
	else:
		contribution_label.visible = false

	# 유령 구간 점수: 보스를 일찍 잡은 구간마다 쌓인 값이 게임이 끝날 때까지 누적된 것 (마지막 보스의 구간 포함).
	# 인원이 달라도 같은 척도로 비교되도록 누적 ÷ 참여 인원 × 최대 인원으로 환산해서 보여 준다.
	if stats.has("ghost"):
		var g: Dictionary = stats.ghost
		var lines: Array[String] = ["유령 구간 점수 (누적 ÷ 참여 %d명 × %d로 환산)" % [g.participants, Balance.MAX_PLAYERS]]
		lines.append("  레인 데미지: %s  (누적 %s)" % [GhostScore.short_number(g.lane_scaled), GhostScore.short_number(g.lane_total)])
		lines.append("  보스 레인 데미지: %s  (누적 %s)" % [GhostScore.short_number(g.boss_scaled), GhostScore.short_number(g.boss_total)])
		if g.participants > 1:
			lines.append("  레인 순위: %s" % GhostScore.ranking_text(g.lane_ranking))
			lines.append("  보스 레인 순위: %s" % GhostScore.ranking_text(g.boss_ranking))
		ghost_label.text = "\n".join(lines)
		ghost_label.visible = true
	else:
		ghost_label.visible = false
	copy_button.text = "결과 복사"


func _format_number(num: float) -> String:
	if num >= 1000000.0:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000.0:
		return "%.1fK" % (num / 1000.0)
	else:
		return "%d" % int(num)


## 결과를 공유할 수 있게 텍스트로 클립보드에 복사한다
func _on_copy_pressed() -> void:
	DisplayServer.clipboard_set(GhostScore.share_text(result == Result.VICTORY, stats))
	copy_button.text = "복사됨!"


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
