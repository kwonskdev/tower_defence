extends Control
class_name MiniMapView
## 미니맵 버튼 하나에 겹쳐 그리는 축소 레인 화면.
## 타워(회색 네모), 몬스터(흰 점), 보스를 단색으로 보여준다 (색깔별로 그리면 너무 난잡해서 뺐다). 버튼을 누르면 해당 레인으로 전환된다 (버튼 자체의 기능).
## 지금 보고 있는 레인은 노란 테두리 + 화면에 보이는 구간을 흰 사각형으로 표시한다.

const TOWER_COLOR := Color(0.5, 0.53, 0.6)
const MONSTER_COLOR := Color(1.0, 1.0, 1.0)

var game_field: GameField
var lane_index: int = 0

var _refresh := 0.0


func _process(delta: float) -> void:
	_refresh -= delta
	if _refresh <= 0.0:
		_refresh = 0.15
		queue_redraw()


func _draw() -> void:
	if game_field == null:
		return

	var is_boss_lane := lane_index == GameField.BOSS_LANE_ID
	var lane: LaneController = game_field.lanes.get(lane_index)
	var participating := is_boss_lane or lane != null

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
			if game_field.boss:
				for m in game_field.boss.get_sent_monsters():
					_dot(area, m.cell_pos, sx, sy, MONSTER_COLOR)
		else:
			for t in lane.towers:
				var cell: Vector2i = t.cell
				var p := area.position + Vector2(cell.x * sx, cell.y * sy)
				draw_rect(Rect2(p, Vector2(maxf(sx, 2.0), maxf(sy, 2.0))), TOWER_COLOR)
			for m in lane.monsters:
				_dot(area, m.cell_pos, sx, sy, MONSTER_COLOR)

	# 레인 번호
	var label := "B" if is_boss_lane else str(lane_index + 1)
	draw_string(ThemeDB.fallback_font, Vector2(4, 11), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(1, 1, 1, 0.9 if participating else 0.35))

	# 지금 보고 있는 레인 표시
	if game_field.current_player_id == lane_index:
		var total_h := float(GridSystem.GRID_HEIGHT * game_field.grid_renderer.CELL_SIZE)
		if total_h > 0.0:
			var top := minf(game_field.get_v_scroll() / total_h * area.size.y, area.size.y)
			var h := minf(game_field.size.y / total_h * area.size.y, area.size.y - top)
			draw_rect(Rect2(area.position + Vector2(0, top), Vector2(area.size.x, h)), Color.WHITE, false, 1.0)
		draw_rect(Rect2(Vector2.ZERO, size), Color(1.0, 0.9, 0.2), false, 2.0)


func _dot(area: Rect2, cell_pos: Vector2, sx: float, sy: float, color: Color) -> void:
	var p := area.position + Vector2(cell_pos.x * sx, cell_pos.y * sy)
	draw_rect(Rect2(p - Vector2(1.0, 1.0), Vector2(2.5, 2.5)), color)
