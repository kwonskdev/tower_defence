extends Control
class_name MiniMapView
## 미니맵 버튼 하나에 겹쳐 그리는 축소 레인 화면.
## 타워(회색 네모), 몬스터(흰 점), 보스를 단색으로 보여준다 (색깔별로 그리면 너무 난잡해서 뺐다). 버튼을 누르면 해당 레인으로 전환된다 (버튼 자체의 기능).
## 지금 보고 있는 레인은 노란 테두리 + 화면에 보이는 구간을 흰 사각형으로 표시한다.

const TOWER_COLOR := Color(0.5, 0.53, 0.6)
const MONSTER_COLOR := Color(1.0, 1.0, 1.0)

var game_field: GameField
var lane_index: int = 0
## 보스 스킬이 이 레인에 영향을 주는 동안의 남은 시간(초). 0보다 크고 이 레인을 보고 있지 않으면 테두리가 깜빡인다.
var alert_left := 0.0

const ALERT_COLOR := Color(1.0, 0.45, 0.1)

var _refresh := 0.0
var _alert_t := 0.0


func _process(delta: float) -> void:
	if alert_left > 0.0:
		alert_left = maxf(0.0, alert_left - delta)
		_alert_t += delta
		queue_redraw()  # 깜빡임이 끊기지 않게 매 프레임 그린다
		return
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.15
		queue_redraw()


func _draw() -> void:
	if game_field == null:
		return

	var is_boss_lane := lane_index == GameField.BOSS_LANE_ID
	var snap := game_field.snapshot()  # 서버 스냅샷만 읽는다 (시뮬레이션 객체를 직접 읽지 않는다)
	var lane: Dictionary = snap.lanes.get(str(lane_index), {})
	var summarized := false   # 온라인: 자기/보고 있는 레인이 아니면 서버가 요약(타워 칸/몬스터 점)만 보낸다
	if lane.is_empty() and game_field.remote != null:
		lane = game_field.summary_of(lane_index)
		summarized = not lane.is_empty()
	var participating := is_boss_lane or not lane.is_empty()

	var area := Rect2(Vector2(2, 2), size - Vector2(4, 4))
	var sx := area.size.x / GridSystem.GRID_WIDTH
	var sy := area.size.y / GridSystem.GRID_HEIGHT

	draw_rect(area, Color(0.07, 0.07, 0.11) if participating else Color(0.03, 0.03, 0.04))
	# 스폰(위)과 도착(아래) 라인
	draw_line(area.position, area.position + Vector2(area.size.x, 0), Color(1.0, 0.6, 0.1, 0.8), 1.0)
	draw_line(area.position + Vector2(0, area.size.y), area.end, Color(0.7, 0.3, 0.9, 0.8), 1.0)

	if participating:
		if is_boss_lane:
			var c := area.position + Balance.BOSS_CENTER * Vector2(sx, sy)
			draw_circle(c, Balance.BOSS_RADIUS * sx, Color(0.8, 0.12, 0.15))
			var boss_dots: Array = snap.boss.get("monsters", [])
			var boss_dots_summary := boss_dots.is_empty() and game_field.remote != null
			if boss_dots_summary:
				boss_dots = game_field.summary_of(GameField.BOSS_LANE_ID).get("monsters", [])
			for m in boss_dots:
				_dot(area, Vector2(m[0], m[1]) if boss_dots_summary else Vector2(m.pos[0], m.pos[1]), sx, sy, MONSTER_COLOR)
		else:
			for t in lane.towers:
				var cell: Array = t if summarized else t.cell
				var p := area.position + Vector2(cell[0] * sx, cell[1] * sy)
				draw_rect(Rect2(p, Vector2(maxf(sx, 2.0), maxf(sy, 2.0))), TOWER_COLOR)
			for m in lane.monsters:
				_dot(area, Vector2(m[0], m[1]) if summarized else Vector2(m.pos[0], m.pos[1]), sx, sy, MONSTER_COLOR)

	# 탈락한 레인은 어둡게 (관전만 된다)
	var eliminated: bool = participating and not is_boss_lane and not lane.get("active", true)
	if eliminated:
		draw_rect(area, Color(0.0, 0.0, 0.0, 0.55))

	# 레인 번호
	var label := "B" if is_boss_lane else str(lane_index + 1)
	draw_string(ThemeDB.fallback_font, Vector2(4, 15), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
		Color(1, 1, 1, 0.9 if participating else 0.35))

	# 여럿이 하는 판: 닉네임과 생명 (탈락이면 "탈락"). 혼자 하는 판은 이름이 없으니 그리지 않는다 (#22)
	if participating and not is_boss_lane and snap.players.size() > 1:
		var nick := str(snap.get("names", {}).get(str(lane_index), ""))
		var status := "탈락" if eliminated else "♥%d" % int(floorf(lane.lives))
		var font_size := 10
		var tag := "%s %s" % [nick, status]
		draw_rect(Rect2(Vector2(2, size.y - 15), Vector2(size.x - 4, 13)), Color(0, 0, 0, 0.6))
		draw_string(ThemeDB.fallback_font, Vector2(4, size.y - 5), tag, HORIZONTAL_ALIGNMENT_LEFT, size.x - 6, font_size,
			Color(1.0, 0.5, 0.45) if eliminated else Color(1, 1, 1, 0.95))

	# 지금 보고 있는 레인 표시
	if game_field.current_player_id == lane_index:
		var total_h := float(GridSystem.GRID_HEIGHT * game_field.grid_renderer.CELL_SIZE)
		if total_h > 0.0:
			var top := minf(game_field.get_v_scroll() / total_h * area.size.y, area.size.y)
			var h := minf(game_field.size.y / total_h * area.size.y, area.size.y - top)
			draw_rect(Rect2(area.position + Vector2(0, top), Vector2(area.size.x, h)), Color.WHITE, false, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.9, 0.2), false, 2.0)
	elif alert_left > 0.0:
		# 보고 있지 않은 레인에 보스 스킬이 걸리는 중: 주황 테두리와 느낌표가 깜빡인다
		var pulse := 0.5 + 0.5 * sin(_alert_t * 10.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(ALERT_COLOR, 0.12 + 0.25 * pulse))
		draw_rect(Rect2(Vector2.ZERO, size), Color(ALERT_COLOR, 0.5 + 0.5 * pulse), false, 3.0)
		draw_string(ThemeDB.fallback_font, Vector2(size.x - 12.0, 13.0), "!", HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
			Color(1.0, 0.95, 0.8, 0.6 + 0.4 * pulse))


func _dot(area: Rect2, cell_pos: Vector2, sx: float, sy: float, color: Color) -> void:
	var p := area.position + Vector2(cell_pos.x * sx, cell_pos.y * sy)
	draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.5, 2.5)), color)
