extends Control
class_name GameOverScreen
## 게임 종료 화면 (승리/패배). 통계를 보여주고 재도전/종료 버튼을 제공한다.

signal restart_requested
signal quit_requested

enum Result { VICTORY, DEFEAT }

var result: Result = Result.DEFEAT
var stats: Dictionary = {}  # 게임 통계

@onready var title_label: Label = $Panel/VBox/Title
@onready var stats_label: Label = $Panel/VBox/Stats
@onready var contribution_label: Label = $Panel/VBox/Contribution
@onready var restart_button: Button = $Panel/VBox/Buttons/RestartButton
@onready var quit_button: Button = $Panel/VBox/Buttons/QuitButton


func _ready() -> void:
	restart_button.pressed.connect(_on_restart_pressed)
	quit_button.pressed.connect(_on_quit_pressed)
	visible = false


## 게임 종료 화면 표시
func show_result(is_victory: bool, game_stats: Dictionary) -> void:
	result = Result.VICTORY if is_victory else Result.DEFEAT
	stats = game_stats
	_update_ui()
	visible = true
	# 화면을 맨 위로 (다른 UI 위에 표시)
	z_index = 1000


func _update_ui() -> void:
	# 제목
	if result == Result.VICTORY:
		title_label.text = "🎉 승리! 🎉"
		title_label.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	else:
		title_label.text = "패배..."
		title_label.add_theme_color_override("font_color", Color(1.0, 0.3, 0.3))

	# 통계
	var stat_lines: Array[String] = []

	# 보스 진행도
	if stats.has("boss_level"):
		var total := stats.get("total_boss_levels", 10)
		stat_lines.append("도달 보스 레벨: %d / %d" % [stats.boss_level, total])

	# 시간
	if stats.has("play_time"):
		var minutes := int(stats.play_time) / 60
		var seconds := int(stats.play_time) % 60
		stat_lines.append("플레이 시간: %d분 %d초" % [minutes, seconds])

	# 타워 통계
	if stats.has("towers_built"):
		stat_lines.append("건설한 타워: %d개" % stats.towers_built)

	if stats.has("total_tower_damage"):
		stat_lines.append("타워 총 피해: %s" % _format_number(stats.total_tower_damage))

	if stats.has("total_tower_kills"):
		stat_lines.append("타워 총 처치: %d" % stats.total_tower_kills)

	# 몬스터 통계
	if stats.has("monsters_sent"):
		stat_lines.append("파견한 몬스터: %d마리" % stats.monsters_sent)

	if stats.has("boss_damage"):
		stat_lines.append("보스 피해: %s" % _format_number(stats.boss_damage))

	# 경제
	if stats.has("final_gold"):
		stat_lines.append("최종 골드: %d" % stats.final_gold)

	if stats.has("final_income"):
		stat_lines.append("최종 수입: +%d/30초" % stats.final_income)

	stats_label.text = "\n".join(stat_lines)

	# 플레이어 기여도 (멀티플레이 시)
	if stats.has("contributions") and stats.contributions.size() > 1:
		var contrib_lines: Array[String] = ["", "플레이어 기여도:"]
		for entry in stats.contributions:
			contrib_lines.append("  P%d: %.1f%% (%s)" % [
				entry.player_id + 1, entry.percent, _format_number(entry.damage)])
		contribution_label.text = "\n".join(contrib_lines)
		contribution_label.visible = true
	else:
		contribution_label.visible = false


func _format_number(num: float) -> String:
	if num >= 1000000.0:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000.0:
		return "%.1fK" % (num / 1000.0)
	else:
		return "%d" % int(num)


func _on_restart_pressed() -> void:
	restart_requested.emit()


func _on_quit_pressed() -> void:
	quit_requested.emit()
