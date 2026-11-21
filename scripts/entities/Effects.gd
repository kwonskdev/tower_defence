extends RefCounted
class_name Effects
## 전투 이펙트 모음: 투사체, 표식 구름, 타격 링, 떠오르는 글자.
## 모두 GridRenderer의 자식 노드로 생성되며 스스로 사라진다.
## 좌표는 셀 단위(셀 중심 = +0.5)를 받는다.
##
## 투사체의 fx(딕셔너리)는 쏜 순간 타워가 계산해서 넣어 준다 (타워가 중간에 부서져도 효과는 그대로).
##   pierce / falloff / range : 한 발로 맞히는 최대 마릿수(첫 적 포함) / 한 마리 지날 때마다 피해 감소 비율 / 날아가는 거리(칸, 타워 사거리)
##   poison {dps,time}: 맞은 적에게 독 중첩
##   armor_break {chance,ratio,time} / execute {chance,hp}: 방어구 파괴 / 처형
##   center {radius,mult}: 폭발 중심부 강화
##   snare {chance,radius,slow,time} / capture {chance,time}: 대공 스킬형


static func spawn_projectile(renderer: GridRenderer, lane: LaneController, from_cell_pos: Vector2,
		target: Monster, kind: Dictionary, color: Color, source: Tower, damage: float, fx: Dictionary = {}) -> void:
	var p := Projectile.new()
	p.renderer = renderer
	p.lane = lane
	p.target = target
	p.source = source
	p.pos_c = from_cell_pos
	p.damage = damage
	p.splash = kind.splash
	p.anti_air = kind.anti_air
	p.color = color
	p.fx = fx
	# 타워 종류에 따라 투사체 모양/속도 결정
	match kind.id:
		"splash":
			p.style = "bomb"
			p.speed = 7.0
		"long":
			p.style = "bolt"
			p.speed = 18.0
		"air":
			p.style = "missile"
			p.speed = 14.0
		_:
			p.style = "dart"
			p.speed = 22.0
	if fx.has("snare") or fx.has("capture"):
		p.style = "orb"  # 스킬형: 피해 없는 구체
		p.speed = 12.0
	p.z_index = 3
	p.visible = lane.lane_visible
	renderer.add_child(p)
	p.launch()


## 표식 구름: 지속시간 동안 안에 들어온 지상 적에게 표식을 1개씩 남긴다 (구름 1개당 적 1마리에 1회)
static func spawn_cloud(renderer: GridRenderer, lane: LaneController, at_cell_pos: Vector2, radius: float,
		duration: float, source: Tower, mark_dmg: float, color: Color) -> void:
	var c := Cloud.new()
	c.renderer = renderer
	c.lane = lane
	c.pos_c = at_cell_pos
	c.radius = radius
	c.life = duration
	c.source = source
	c.mark_dmg = mark_dmg
	c.color = color
	c.z_index = 1
	c.visible = lane.lane_visible
	renderer.add_child(c)


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
	var source  # 쏜 타워 (누적 피해/킬 집계용). 날아가는 중 부서져 해제될 수 있어서 일부러 타입을 안 붙였다
	var pos_c: Vector2
	var dest: Vector2
	var speed := 14.0
	var damage := 1.0
	var splash := 0.0
	var anti_air := false
	var color := Color.WHITE
	var style := "bolt"
	var dir := Vector2.DOWN
	var fx: Dictionary = {}
	var _total := 1.0
	# 관통: 첫 적을 맞힌 뒤 같은 방향으로 직진하며 남은 적을 차례로 맞힌다
	# 관통: 타워 사거리만큼 날아가며 길에 있는 적을 pierce마리까지 차례로 맞힌다 (한 마리 맞힐 때마다 피해가 falloff만큼 줄어든다).
	# 처음 겨눈 적은 유도로 따라가서 반드시 맞는다. 그 뒤로는 같은 방향으로 직진한다.
	var _pierce_left := 0
	var _pierce_hits := 0
	var _is_pierce := false
	var _piercing := false
	var _travel_left := 0.0
	var _start := Vector2.ZERO
	var _hit_ids: Dictionary = {}

	const PIERCE_HIT_RADIUS := 0.4

	func launch() -> void:
		dest = (target.cell_pos + target.visual_offset()) if is_instance_valid(target) else pos_c
		_total = maxf(0.1, pos_c.distance_to(dest))
		dir = (dest - pos_c).normalized()
		position = pos_c * renderer.CELL_SIZE
		_pierce_left = int(fx.get("pierce", 0))
		_is_pierce = _pierce_left > 0 and splash <= 0.0
		_start = pos_c

	func _process(delta: float) -> void:
		if _piercing:
			_process_pierce(delta)
			return
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
		if _is_pierce and _pierce_scan():
			return
		queue_redraw()

	func _impact() -> void:
		if _is_pierce:
			_impact_pierce()
			return
		if splash > 0.0:
			var center: Dictionary = fx.get("center", {})
			for m in lane.monsters.duplicate():
				# 범위 공격도 타워의 대공/지상 구분을 따른다
				if is_instance_valid(m) and not m.is_dead() and m.flying == anti_air:
					var d: float = (m.cell_pos + m.visual_offset()).distance_to(dest)
					if d <= splash:
						var dmg := damage
						if not center.is_empty() and d <= float(center.radius):
							dmg *= float(center.mult)  # 폭발 중심부는 더 아프다
						_hit(m, dmg)
			Effects.ring(renderer, dest, splash, color, visible)
			if not center.is_empty():
				Effects.ring(renderer, dest, float(center.radius), Color(1.0, 0.8, 0.3), visible)
		else:
			if is_instance_valid(target):
				_hit(target, damage)
			Effects.ring(renderer, dest, 0.35, color, visible)
		_skill_effects()
		queue_free()

	## 관통 투사체가 겨눈 적에게 닿았다: 아직 안 맞았으면 맞히고, 남은 거리만큼 직진한다
	func _impact_pierce() -> void:
		if is_instance_valid(target) and not target.is_dead() and not _hit_ids.has(target.get_instance_id()):
			_pierce_hit(target)
		_travel_left = float(fx.get("range", 5.0)) - _start.distance_to(pos_c)
		if _pierce_left <= 0 or _travel_left <= 0.0:
			queue_free()
			return
		_piercing = true

	func _process_pierce(delta: float) -> void:
		var step := speed * delta
		pos_c += dir * step
		_travel_left -= step
		position = pos_c * renderer.CELL_SIZE
		if _pierce_scan():
			return
		if _travel_left <= 0.0:
			queue_free()
			return
		queue_redraw()

	## 지금 위치 근처의 아직 안 맞은 적을 맞힌다. 마릿수를 다 채우면 사라지고 true
	func _pierce_scan() -> bool:
		for m in lane.monsters.duplicate():
			if not is_instance_valid(m) or m.is_dead() or m.flying != anti_air or _hit_ids.has(m.get_instance_id()):
				continue
			if (m.cell_pos + m.visual_offset()).distance_to(pos_c) <= PIERCE_HIT_RADIUS:
				_pierce_hit(m)
				if _pierce_left <= 0:
					queue_free()
					return true
		return false

	func _pierce_hit(m: Monster) -> void:
		_hit_ids[m.get_instance_id()] = true
		var dmg := damage * pow(maxf(0.0, 1.0 - float(fx.get("falloff", 0.0))), _pierce_hits)
		_pierce_hits += 1
		_pierce_left -= 1
		_hit(m, dmg)
		Effects.ring(renderer, m.cell_pos, 0.3, color, visible)

	## 적 1마리를 맞힌다: 피해 + 맞았을 때 걸리는 효과들
	func _hit(m: Monster, dmg: float) -> void:
		if dmg > 0.0:
			m.take_damage(dmg, source)
		if m.is_dead():
			return
		if fx.has("poison"):
			m.add_poison(source, float(fx.poison.dps), float(fx.poison.time))
		if fx.has("armor_break") and randf() < float(fx.armor_break.chance):
			m.apply_armor_break(float(fx.armor_break.time), float(fx.armor_break.ratio))
		if fx.has("execute") and m.hp <= m.max_hp * float(fx.execute.hp) and randf() < float(fx.execute.chance):
			m.execute(source)
			Effects.float_text(renderer, m.cell_pos, "처형!", Color(1.0, 0.3, 0.3), visible)

	## 대공 스킬형: 공격이 맞은 자리에서 확률로 스킬 발동
	func _skill_effects() -> void:
		if fx.has("snare") and randf() < float(fx.snare.chance):
			var sn: Dictionary = fx.snare
			for m in lane.monsters:
				if is_instance_valid(m) and not m.is_dead() and (m.cell_pos + m.visual_offset()).distance_to(dest) <= float(sn.radius):
					m.apply_slow(float(sn.slow), float(sn.time))
			Effects.ring(renderer, dest, float(sn.radius), Color(0.5, 0.8, 1.0), visible)
		if fx.has("capture") and is_instance_valid(target) and target.flying and randf() < float(fx.capture.chance):
			target.capture(float(fx.capture.time))
			Effects.float_text(renderer, target.cell_pos, "포획!", Color(1.0, 0.9, 0.3), visible)

	func _draw() -> void:
		var cell: float = renderer.CELL_SIZE
		var d := dir * cell
		match style:
			"bolt":  # 가늘고 긴 광선
				draw_line(-d * 0.55, Vector2.ZERO, color, 3.0)
				draw_line(-d * 0.55, Vector2.ZERO, Color(1, 1, 1, 0.8), 1.0)
			"missile":  # 꼬리 불꽃이 달린 미사일
				draw_line(-d * 0.4, Vector2.ZERO, Color(1.0, 0.7, 0.3, 0.8), 3.0)
				draw_line(-d * 0.15, d * 0.1, Color(0.9, 0.92, 1.0), 4.0)
				draw_circle(d * 0.1, 3.0, color)
			"orb":  # 큼직한 에너지 구
				draw_circle(Vector2.ZERO, cell * 0.2, Color(color, 0.35))
				draw_circle(Vector2.ZERO, cell * 0.12, color)
				draw_circle(Vector2.ZERO, cell * 0.05, Color.WHITE)
			"bomb":  # 포탄
				draw_circle(Vector2.ZERO, cell * 0.14, Color(0.15, 0.15, 0.2))
				draw_arc(Vector2.ZERO, cell * 0.14, 0.0, TAU, 12, color, 2.0)
			_:  # 작은 화살/침
				draw_line(-d * 0.25, Vector2.ZERO, color, 2.0)


class Cloud extends Node2D:
	var renderer: GridRenderer
	var lane: LaneController
	var source
	var pos_c: Vector2
	var radius := 1.2
	var life := 3.0
	var mark_dmg := 40.0
	var color := Color(0.75, 0.5, 1.0)
	var _t := 0.0
	var _marked: Dictionary = {}  # 이 구름이 이미 표식을 남긴 몬스터

	func _process(delta: float) -> void:
		_t += delta
		if _t >= life:
			queue_free()
			return
		position = pos_c * renderer.CELL_SIZE
		for m in lane.monsters:
			if not is_instance_valid(m) or m.is_dead() or m.flying:
				continue
			var id: int = m.get_instance_id()
			if _marked.has(id):
				continue
			if m.cell_pos.distance_to(pos_c) <= radius:
				_marked[id] = true
				m.add_mark(source, mark_dmg)
		queue_redraw()

	func _draw() -> void:
		var cell: float = renderer.CELL_SIZE
		var fade := clampf((life - _t) / 0.6, 0.0, 1.0)  # 사라지기 직전에 흐려진다
		var r := radius * cell
		draw_circle(Vector2.ZERO, r, Color(color, 0.16 * fade))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 32, Color(color, 0.55 * fade), 2.0)
		# 일렁이는 구름 덩어리
		for i in range(5):
			var a := _t * 0.8 + i * TAU / 5.0
			var off := Vector2.from_angle(a) * r * 0.5
			draw_circle(off, r * 0.3, Color(color, 0.22 * fade))


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
