extends Node2D
class_name Tower
## 타워 1기. 사거리 안에서 기지에 가장 가까운 몬스터를 조준해 투사체를 발사한다.
## - 대공 속성 타워는 공중 몬스터만, 그 외 타워는 지상 몬스터만 공격한다.
## 외형: 바닥판 테두리 = 랜덤 배정된 색깔, 아래 두 점 = 속성 색, 포신 모양 = 속성 조합.
## preview=true이면 아이콘용 미리보기: 가만히 서 있다 (선택창이 산만하지 않도록 아무것도 움직이지 않는다).

var cell: Vector2i
var kind: Dictionary      # Balance.tower_kind() 결과
var color_info: Dictionary  # Balance.TOWER_COLORS 항목
var lane: LaneController
var stack_index: int = 0  # 같은 칸에 겹친 트랩 중 몇 번째인지

# 아이콘 미리보기용
var preview: bool = false
var preview_cell: float = 40.0
var preview_aim: float = -PI * 0.25  # 아이콘에서 포신이 가리키는 방향 (오른쪽 위)

# 한 칸에 트랩이 여러 개일 때 칸 안에서의 위치 (셀 단위)
const STACK_OFFSETS := [
	Vector2(-0.22, -0.22), Vector2(0.22, -0.22), Vector2(-0.22, 0.22), Vector2(0.22, 0.22), Vector2(0.0, 0.0),
]

var _renderer: GridRenderer
var _cooldown := 0.0
var _aim := -PI * 0.5
var _recoil := 0.0
var _t := 0.0


func setup(p_cell: Vector2i, p_kind: Dictionary, p_color_info: Dictionary, p_lane: LaneController, renderer: GridRenderer) -> void:
	cell = p_cell
	kind = p_kind
	color_info = p_color_info
	lane = p_lane
	_renderer = renderer
	position = _visual_cell_pos() * _renderer.CELL_SIZE


func _is_stacked() -> bool:
	return lane != null and not kind.blocks and lane.trap_count(cell) > 1


func _visual_cell_pos() -> Vector2:
	if _is_stacked():
		return center_cell_pos() + STACK_OFFSETS[stack_index % STACK_OFFSETS.size()]
	return center_cell_pos()


func center_cell_pos() -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


func _process(delta: float) -> void:
	if preview:
		return  # 아이콘은 가만히 둔다

	_t += delta
	_recoil = maxf(0.0, _recoil - delta * 5.0)
	position = _visual_cell_pos() * _renderer.CELL_SIZE

	if lane.active:
		_cooldown -= delta
		var target := lane.find_target(center_cell_pos(), kind.range, kind.anti_air)
		if target:
			var want := (target.cell_pos - center_cell_pos()).angle()
			_aim = lerp_angle(_aim, want, minf(1.0, delta * 14.0))
			if _cooldown <= 0.0:
				_fire(target)
	queue_redraw()


func _fire(target: Monster) -> void:
	_cooldown = kind.cooldown
	_recoil = 1.0
	var muzzle := center_cell_pos() + Vector2.from_angle(_aim) * 0.45
	Effects.spawn_projectile(_renderer, lane, muzzle, target, kind, _attr_color(0))


func _attr_color(i: int) -> Color:
	return Balance.TOWER_ATTRS[kind.attrs[i]].color


func _cell_px() -> float:
	return preview_cell if _renderer == null else float(_renderer.CELL_SIZE)


func _draw() -> void:
	var cell_px := _cell_px()
	var s := cell_px * (0.55 if _is_stacked() else 0.88)
	var c: Color = color_info.color
	var attrs: PackedStringArray = kind.attrs

	# 바닥판 + 색깔 테두리
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(0.13, 0.13, 0.17))
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(c, 0.28))
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), c, false, 3.0)

	# 속성 배지 (아래 두 개): 그림으로 어떤 속성인지 바로 알아보게 한다
	var badge_r := s * 0.2
	_draw_attr_badge(kind.attrs[0], Vector2(-s * 0.27, s * 0.27), badge_r)
	_draw_attr_badge(kind.attrs[1], Vector2(s * 0.27, s * 0.27), badge_r)

	var barrel_color := Color(0.75, 0.78, 0.85)
	if not kind.blocks:
		# 트랩: 낮은 돔 + 가시 (포신 없음, 몬스터가 위로 지나갈 수 있음)
		draw_circle(Vector2.ZERO, s * 0.26, Color(0.3, 0.3, 0.2))
		for i in range(6):
			var a := i * TAU / 6.0 + _t * 0.8
			draw_line(Vector2.from_angle(a) * s * 0.2, Vector2.from_angle(a) * s * 0.36, _attr_color(0), 2.5)
		if kind.anti_air:
			_draw_air_dish(s)
		return

	# 포탑 + 회전하는 포신 (속성에 따라 모양이 다름)
	var length := s * 0.5
	var width := s * 0.13
	if "long" in attrs:
		length = s * 0.75
		width = s * 0.1
	if "power" in attrs:
		width = s * 0.22
	if "splash" in attrs:
		length = s * 0.38
		width = s * 0.28
	length -= _recoil * s * 0.1

	draw_set_transform(Vector2.ZERO, preview_aim if preview else _aim, Vector2.ONE)
	draw_rect(Rect2(0, -width * 0.5, length, width), barrel_color)
	draw_rect(Rect2(length - s * 0.06, -width * 0.5 - 1, s * 0.06, width + 2), _attr_color(0))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_circle(Vector2.ZERO, s * 0.24, Color(0.28, 0.3, 0.38))
	draw_circle(Vector2.ZERO, s * 0.13, c)
	if kind.anti_air:
		_draw_air_dish(s)


## 속성을 나타내는 둥근 배지. 속성마다 모양이 달라서 글자 없이도 구분된다.
##  장거리 = 조준경(십자선) / 고화력 = 폭발 별 / 범위 = 퍼지는 파동 / 트랩 = 가시 / 대공 = 위로 향한 화살표
func _draw_attr_badge(attr_id: String, center: Vector2, rad: float) -> void:
	var col: Color = Balance.TOWER_ATTRS[attr_id].color
	draw_circle(center, rad, Color(0.05, 0.05, 0.09, 0.92))
	draw_arc(center, rad, 0.0, TAU, 20, col, maxf(1.5, rad * 0.12))
	var g := rad * 0.62
	match attr_id:
		"long":
			draw_arc(center, g * 0.75, 0.0, TAU, 16, col, maxf(1.5, g * 0.18))
			for i in range(4):
				var d := Vector2.from_angle(i * PI * 0.5)
				draw_line(center + d * g * 0.4, center + d * g * 1.2, col, maxf(1.5, g * 0.18))
			draw_circle(center, g * 0.16, col)
		"power":
			var star := PackedVector2Array()
			for i in range(10):
				var rr := g * 1.15 if i % 2 == 0 else g * 0.5
				star.append(center + Vector2.from_angle(-PI * 0.5 + i * PI * 0.2) * rr)
			draw_colored_polygon(star, col)
		"splash":
			draw_circle(center, g * 0.2, col)
			draw_arc(center, g * 0.6, 0.0, TAU, 16, col, maxf(1.5, g * 0.16))
			draw_arc(center, g * 1.05, 0.0, TAU, 20, Color(col, 0.65), maxf(1.5, g * 0.14))
		"trap":
			for i in range(-1, 2):
				var x := i * g * 0.62
				draw_colored_polygon(PackedVector2Array([
					center + Vector2(x - g * 0.3, g * 0.75),
					center + Vector2(x, -g * 0.8),
					center + Vector2(x + g * 0.3, g * 0.75),
				]), col)
		"air":
			draw_colored_polygon(PackedVector2Array([
				center + Vector2(0, -g * 1.15),
				center + Vector2(g * 0.85, g * 0.0),
				center + Vector2(g * 0.3, g * 0.0),
				center + Vector2(g * 0.3, g * 0.95),
				center + Vector2(-g * 0.3, g * 0.95),
				center + Vector2(-g * 0.3, g * 0.0),
				center + Vector2(-g * 0.85, g * 0.0),
			]), col)


## 대공 속성 표시: 포탑 위의 레이더 접시 + 위로 솟은 미사일 핀
func _draw_air_dish(s: float) -> void:
	var air := Balance.TOWER_ATTRS["air"].color
	var p := Vector2(-s * 0.28, -s * 0.28)
	draw_arc(p, s * 0.17, PI * 0.1, PI * 1.1, 10, air, 3.0)
	draw_line(p, p + Vector2(0, -s * 0.2), air, 2.0)
	draw_circle(p + Vector2(0, -s * 0.2), s * 0.04, Color.WHITE)
