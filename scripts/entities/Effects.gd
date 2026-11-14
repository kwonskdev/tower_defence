extends RefCounted
class_name Effects
## 전투 이펙트 모음: 투사체, 타격 링, 떠오르는 글자.
## 모두 GridRenderer의 자식 노드로 생성되며 스스로 사라진다.
## 좌표는 셀 단위(셀 중심 = +0.5)를 받는다.


static func spawn_projectile(renderer: GridRenderer, lane: LaneController, from_cell_pos: Vector2,
		target: Monster, kind: Dictionary, color: Color) -> void:
	var attrs: PackedStringArray = kind.attrs
	var p := Projectile.new()
	p.renderer = renderer
	p.lane = lane
	p.target = target
	p.pos_c = from_cell_pos
	p.damage = kind.damage
	p.splash = kind.splash
	p.anti_air = kind.anti_air
	p.color = color
	# 속성 조합에 따라 투사체 모양/속도 결정
	if "splash" in attrs:
		p.style = "bomb"
		p.speed = 7.0
	elif "power" in attrs:
		p.style = "orb"
		p.speed = 9.0
	elif "long" in attrs:
		p.style = "bolt"
		p.speed = 18.0
	else:
		p.style = "dart"
		p.speed = 20.0
	p.z_index = 3
	p.visible = lane.lane_visible
	renderer.add_child(p)
	p.launch()


static func ring(renderer: GridRenderer, at_cell_pos: Vector2, radius_cells: float, color: Color, shown: bool) -> void:
	var r := Ring.new()
	r.renderer = renderer
	r.pos_c = at_cell_pos
	r.max_radius = radius_cells
	r.color = color
	r.z_index = 3
	r.visible = shown
	renderer.add_child(r)


static func float_text(renderer: GridRenderer, at_cell_pos: Vector2, text: String, color: Color, shown: bool) -> void:
	var t := FloatText.new()
	t.renderer = renderer
	t.pos_c = at_cell_pos
	t.text = text
	t.color = color
	t.z_index = 4
	t.visible = shown
	renderer.add_child(t)


class Projectile extends Node2D:
	var renderer: GridRenderer
	var lane: LaneController
	var target: Monster
	var pos_c: Vector2
	var dest: Vector2
	var speed := 14.0
	var damage := 1.0
	var splash := 0.0
	var anti_air := false
	var color := Color.WHITE
	var style := "bolt"
	var dir := Vector2.DOWN
	var _total := 1.0

	func launch() -> void:
		dest = (target.cell_pos + target.visual_offset()) if is_instance_valid(target) else pos_c
		_total = maxf(0.1, pos_c.distance_to(dest))
		dir = (dest - pos_c).normalized()
		position = pos_c * renderer.CELL_SIZE

	func _process(delta: float) -> void:
		if is_instance_valid(target):
			dest = target.cell_pos + target.visual_offset()  # 유도: 살아있는 동안 계속 따라간다
		var to := dest - pos_c
		var step := speed * delta
		if to.length() <= step:
			_impact()
			return

		dir = to.normalized()
		pos_c += dir * step
		var arc := 0.0
		if style == "bomb":  # 포물선
			var progress := 1.0 - clampf(to.length() / _total, 0.0, 1.0)
			arc = sin(progress * PI) * renderer.CELL_SIZE * 1.2
		position = pos_c * renderer.CELL_SIZE + Vector2(0, -arc)
		queue_redraw()

	func _impact() -> void:
		if splash > 0.0:
			for m in lane.monsters.duplicate():
				# 범위 공격도 타워의 대공/지상 구분을 따른다
				if is_instance_valid(m) and m.flying == anti_air \
						and (m.cell_pos + m.visual_offset()).distance_to(dest) <= splash:
					m.take_damage(damage)
			Effects.ring(renderer, dest, splash, color, visible)
		else:
			if is_instance_valid(target):
				target.take_damage(damage)
			Effects.ring(renderer, dest, 0.35, color, visible)
		queue_free()

	func _draw() -> void:
		var cell: float = renderer.CELL_SIZE
		var d := dir * cell
		match style:
			"bolt":  # 가늘고 긴 광선
				draw_line(-d * 0.55, Vector2.ZERO, color, 3.0)
				draw_line(-d * 0.55, Vector2.ZERO, Color(1, 1, 1, 0.8), 1.0)
			"orb":  # 큼직한 에너지 구
				draw_circle(Vector2.ZERO, cell * 0.2, Color(color, 0.35))
				draw_circle(Vector2.ZERO, cell * 0.12, color)
				draw_circle(Vector2.ZERO, cell * 0.05, Color.WHITE)
			"bomb":  # 포탄
				draw_circle(Vector2.ZERO, cell * 0.14, Color(0.15, 0.15, 0.2))
				draw_arc(Vector2.ZERO, cell * 0.14, 0.0, TAU, 12, color, 2.0)
			_:  # 작은 화살/침
				draw_line(-d * 0.25, Vector2.ZERO, color, 2.0)


class Ring extends Node2D:
	var renderer: GridRenderer
	var pos_c: Vector2
	var max_radius := 0.5
	var color := Color.WHITE
	var _t := 0.0
	const LIFE := 0.25

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		position = pos_c * renderer.CELL_SIZE
		queue_redraw()

	func _draw() -> void:
		var k := _t / LIFE
		var r := max_radius * renderer.CELL_SIZE * (0.3 + 0.7 * k)
		draw_circle(Vector2.ZERO, r, Color(color, 0.25 * (1.0 - k)))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 24, Color(color, 1.0 - k), 2.5)


class FloatText extends Node2D:
	var renderer: GridRenderer
	var pos_c: Vector2
	var text := ""
	var color := Color.WHITE
	var _t := 0.0
	const LIFE := 0.9

	func _process(delta: float) -> void:
		_t += delta
		if _t >= LIFE:
			queue_free()
			return
		position = pos_c * renderer.CELL_SIZE + Vector2(0, -_t * renderer.CELL_SIZE * 0.9)
		queue_redraw()

	func _draw() -> void:
		var a := 1.0 - clampf((_t - LIFE * 0.5) / (LIFE * 0.5), 0.0, 1.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(-10, 0), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(0, 0, 0, a))
		draw_string(font, Vector2(-11, -1), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color(color, a))
