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
	var has_long := "long" in attrs
	var has_power := "power" in attrs
	var has_splash := "splash" in attrs

	# 바닥판 + 색깔 테두리 (테두리 색은 색깔 보너스용으로 건설할 때 랜덤 배정된 색)
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(0.13, 0.13, 0.17))
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(c, 0.28))
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), c, false, 3.0)

	# 타워의 생김새 자체가 속성을 말한다 (별도의 표시 없이 한눈에 구분되도록)
	#  장거리 = 아주 긴 가는 포신 / 고화력 = 굵은 대포 + 포구 블록
	#  범위   = 나팔 모양 포구 + 둥근 포탄(박격포) / 대공 = 쌍둥이 미사일(분홍 머리)
	#  트랩   = 포신 없이 납작하게 깔린 가시판
	if not kind.blocks:
		_draw_trap_plate(s, has_long, has_power, has_splash, kind.anti_air)
	elif kind.anti_air:
		_draw_missiles(s, has_long, has_power, has_splash)
	else:
		_draw_gun(s, has_long, has_power, has_splash)


func _aim_angle() -> float:
	return preview_aim if preview else _aim


## 포신(대포/박격포): 길이=장거리, 굵기+포구 블록=고화력, 나팔 포구+포탄=범위
func _draw_gun(s: float, has_long: bool, has_power: bool, has_splash: bool) -> void:
	var steel := Color(0.78, 0.8, 0.88)
	var dark := Color(0.16, 0.17, 0.24)
	var length := s * (0.95 if has_long else 0.5) - _recoil * s * 0.1
	var width := s * (0.3 if has_power else (0.1 if has_long else 0.15))
	var hub := s * (0.3 if has_power else 0.22)

	draw_set_transform(Vector2.ZERO, _aim_angle(), Vector2.ONE)
	draw_rect(Rect2(0, -width * 0.5, length, width), steel)
	draw_rect(Rect2(0, -width * 0.5, length, width), dark, false, 1.5)
	# 속성 색 띠 두 줄 (포신에 두른 줄무늬)
	draw_rect(Rect2(length * 0.2, -width * 0.5 - 1, maxf(3.0, length * 0.09), width + 2), _attr_color(0))
	draw_rect(Rect2(length * 0.38, -width * 0.5 - 1, maxf(3.0, length * 0.09), width + 2), _attr_color(1))
	if has_power:
		# 묵직한 포구 블록
		draw_rect(Rect2(length - s * 0.17, -width * 0.72, s * 0.17, width * 1.44), dark)
		draw_rect(Rect2(length - s * 0.17, -width * 0.72, s * 0.17, width * 1.44), steel, false, 1.5)
	if has_splash:
		# 나팔처럼 벌어진 포구 + 그 앞의 둥근 포탄
		draw_colored_polygon(PackedVector2Array([
			Vector2(length * 0.68, -width * 0.5), Vector2(length, -width * 1.2),
			Vector2(length, width * 1.2), Vector2(length * 0.68, width * 0.5),
		]), steel)
		draw_polyline(PackedVector2Array([
			Vector2(length * 0.68, -width * 0.5), Vector2(length, -width * 1.2),
			Vector2(length, width * 1.2), Vector2(length * 0.68, width * 0.5),
		]), dark, 1.5)
		var bomb := Vector2(length + s * 0.14, 0)
		draw_circle(bomb, s * 0.15, Color(0.1, 0.1, 0.14))
		draw_arc(bomb, s * 0.15, 0.0, TAU, 14, Balance.TOWER_ATTRS["splash"].color, 2.0)
		draw_circle(bomb + Vector2(s * 0.05, -s * 0.12), s * 0.04, Color(1.0, 0.7, 0.2))  # 도화선 불꽃
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_circle(Vector2.ZERO, hub, Color(0.28, 0.3, 0.38))
	draw_arc(Vector2.ZERO, hub, 0.0, TAU, 18, dark, 2.0)
	draw_circle(Vector2.ZERO, hub * 0.5, color_info.color)


## 대공: 나란한 쌍둥이 미사일. 길이=장거리, 굵기=고화력, 둥근 머리=범위 (아니면 분홍 뾰족 머리)
func _draw_missiles(s: float, has_long: bool, has_power: bool, has_splash: bool) -> void:
	var steel := Color(0.85, 0.87, 0.93)
	var dark := Color(0.16, 0.17, 0.24)
	var air: Color = Balance.TOWER_ATTRS["air"].color
	var ml := s * (0.85 if has_long else 0.52) - _recoil * s * 0.1
	var mw := s * (0.2 if has_power else 0.1)
	var off := s * (0.17 if has_power else 0.13)
	var x0 := s * 0.06

	draw_set_transform(Vector2.ZERO, _aim_angle(), Vector2.ONE)
	for side in [-1.0, 1.0]:
		var y: float = side * off
		draw_rect(Rect2(x0, y - mw * 0.5, ml, mw), steel)
		draw_rect(Rect2(x0, y - mw * 0.5, ml, mw), dark, false, 1.2)
		draw_rect(Rect2(x0 + ml * 0.35, y - mw * 0.5 - 1, maxf(2.5, ml * 0.1), mw + 2), _attr_color(0 if kind.attrs[0] != "air" else 1))
		if has_splash:
			var head := Vector2(x0 + ml + mw * 0.2, y)
			draw_circle(head, mw * 0.95, Balance.TOWER_ATTRS["splash"].color)
			draw_arc(head, mw * 0.95, 0.0, TAU, 12, dark, 1.2)
		else:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0 + ml, y - mw * 0.55), Vector2(x0 + ml + mw * 1.7, y), Vector2(x0 + ml, y + mw * 0.55),
			]), air)
		# 꼬리 날개
		for fin in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([
				Vector2(x0, y + fin * mw * 0.5), Vector2(x0 - mw * 0.9, y + fin * mw * 1.2), Vector2(x0 + mw * 0.7, y + fin * mw * 0.5),
			]), dark)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	var hub := s * 0.2
	draw_circle(Vector2.ZERO, hub, Color(0.28, 0.3, 0.38))
	draw_arc(Vector2.ZERO, hub, 0.0, TAU, 16, dark, 2.0)
	draw_circle(Vector2.ZERO, hub * 0.5, color_info.color)


## 트랩: 포신 없이 납작하게 깔린 가시판. 가시 길이=장거리, 굵기=고화력, 파동=범위, 위로 솟은 침=대공
func _draw_trap_plate(s: float, has_long: bool, has_power: bool, has_splash: bool, has_air: bool) -> void:
	var spike: Color = Balance.TOWER_ATTRS["trap"].color
	var dark := Color(0.16, 0.17, 0.24)

	if has_splash:
		var splash: Color = Balance.TOWER_ATTRS["splash"].color
		draw_arc(Vector2.ZERO, s * 0.44, 0.0, TAU, 24, Color(splash, 0.75), 2.5)
		draw_arc(Vector2.ZERO, s * 0.3, 0.0, TAU, 20, Color(splash, 0.55), 2.0)

	if has_air:
		# 위로 솟은 침 (대공 트랩): 분홍 끝이 하늘을 향한다
		var air: Color = Balance.TOWER_ATTRS["air"].color
		var w := s * (0.12 if has_power else 0.075)
		for i in range(5):
			var x := (i - 2) * s * 0.18
			var h := s * (0.78 if has_long else 0.55) * (1.0 if i % 2 == 0 else 0.72)
			var base_y := s * 0.32
			draw_colored_polygon(PackedVector2Array([
				Vector2(x - w, base_y), Vector2(x, base_y - h), Vector2(x + w, base_y),
			]), spike)
			draw_circle(Vector2(x, base_y - h), w * 0.7, air)
		draw_rect(Rect2(-s * 0.42, s * 0.3, s * 0.84, s * 0.1), dark)
		return

	# 사방으로 뻗은 가시
	var count := 8
	var spike_len := s * (0.5 if has_long else 0.34)
	var spike_w := s * (0.22 if has_power else 0.1)
	for i in range(count):
		var a := i * TAU / count + PI / count
		var d := Vector2.from_angle(a)
		var perp := Vector2(-d.y, d.x)
		var base := d * s * 0.14
		draw_colored_polygon(PackedVector2Array([
			base + perp * spike_w * 0.5, d * spike_len, base - perp * spike_w * 0.5,
		]), spike)
		draw_polyline(PackedVector2Array([base + perp * spike_w * 0.5, d * spike_len, base - perp * spike_w * 0.5]), dark, 1.2)
	draw_circle(Vector2.ZERO, s * 0.15, Color(0.3, 0.3, 0.2))
	draw_arc(Vector2.ZERO, s * 0.15, 0.0, TAU, 14, dark, 2.0)
