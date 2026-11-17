extends Node2D
class_name Tower
## 타워 1기. 사거리 안에서 기지에 가장 가까운 몬스터를 조준해 공격한다.
## - 기본 4종: 장거리 / 범위 / 대공 / 트랩. 대공 타워는 공중 몬스터만, 그 외 타워는 지상 몬스터만 공격한다.
## - 지은 뒤 진화 계열(evolution)을 하나 고르면 그 계열의 스킬이 붙는다 (Evolutions.gd).
##   항목 레벨은 레인 전체가 공유한다 (LaneController.stat_level).
## 외형: 바닥판 테두리 = 랜덤 배정된 색깔, 포신 모양 = 기본 종류, 오른쪽 아래 마름모 = 진화 계열 색.
## preview=true이면 아이콘용 미리보기: 가만히 서 있다 (선택창이 산만하지 않도록 아무것도 움직이지 않는다).

var cell: Vector2i
var kind: Dictionary      # Balance.tower_kind() 결과
var color_info: Dictionary  # Balance.TOWER_COLORS 항목
var lane: LaneController

var evolution: String = ""     # 진화 계열 ID ("" = 아직 진화 안 함)
var b_learned: bool = false    # B 스킬을 배웠는가 (진화처럼 타워마다 돈을 내고 따로 배운다. 항목 업그레이드만 계열 공통)

# 전적
var total_damage: float = 0.0  # 누적 피해 (맞은 시점에 오른다. 독/표식 피해도 건 타워 몫)
var kills: int = 0             # 처치 수 (마지막 한 방을 때린 타워만 오른다. 독으로 죽이면 독을 건 타워)
var selected: bool = false     # 선택되면 사거리를 보여준다

# 내구도: 슬라임 새끼 같은 몬스터가 갉으면 닳고, 한 번 닳으면 회복되지 않는다. 0이 되면 부서진다 (LaneController가 처리).
# (길이 막혀서 뚫고 오는 일반 몬스터는 지금처럼 한 번에 부순다)
var durability: float = Balance.TOWER_DURABILITY

# 보스 스킬 봉인: 남은 시간 동안 조준, 공격, 충전을 못 한다. seal_warn은 봉인 예고 표식.
var sealed_time: float = 0.0
var seal_warn: bool = false

# 아이콘 미리보기용
var preview: bool = false
var preview_cell: float = 40.0
var preview_aim: float = -PI * 0.25  # 아이콘에서 포신이 가리키는 방향 (오른쪽 위)

# 진화 스킬 상태
var charge: float = 0.0         # 충전형: 모아 둔 에너지(초)
var haste_stacks: int = 0       # 성장형 B: 광란 중첩
var _haste_timer := 0.0
var _shot_count := 0            # 대량 처리형 A: 몇 번째 공격인지

const TRAP_ALPHA := 0.55   # 트랩(길을 막지 않는 타워)의 투명도

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
	position = center_cell_pos() * _renderer.CELL_SIZE


func center_cell_pos() -> Vector2:
	return Vector2(cell) + Vector2(0.5, 0.5)


## 진화 계열을 정한다 (골드 처리는 LaneController.evolve_tower가 한다)
func set_evolution(evo: String) -> void:
	evolution = evo
	b_learned = false
	charge = 0.0
	haste_stacks = 0
	_shot_count = 0
	queue_redraw()


func can_evolve() -> bool:
	return evolution == ""


## 몬스터가 amount(초)만큼 갉았다. 내구도가 바닥나서 부서져야 하면 true.
func gnaw(amount: float) -> bool:
	durability = maxf(0.0, durability - amount)
	return durability <= 0.0


## 보스 스킬 예고 표식 (알파 0이면 없음). Monster도 같은 이름으로 받는다.
func set_warn(color: Color) -> void:
	seal_warn = color.a > 0.0


func clear_warn() -> void:
	seal_warn = false


# --- 전적 (Monster가 부른다) ---

func record_damage(applied: float) -> void:
	total_damage += applied


func record_kill() -> void:
	kills += 1


# --- 스킬 수치 ---

## 이 타워가 그 스킬을 쓸 수 있는가 (A는 진화하면 바로, B는 이 타워가 돈을 내고 배워야 한다)
func has_skill(skill: String) -> bool:
	if evolution == "":
		return false
	return skill == "A" or b_learned


## 스킬 수치 하나. 업그레이드 탭에서 올린 항목 레벨(계열 공통)이 반영된다.
func _p(skill: String, key: String) -> float:
	return Evolutions.p(evolution, skill, key, lane.stat_level(evolution, skill, key))


func evo_color() -> Color:
	return Evolutions.DATA[evolution].color if evolution != "" else Color(0.9, 0.9, 1.0)


## 한 발 피해 (진화하면 계열에 따라 배율이 붙는다 + 색깔 보너스)
func cur_damage() -> float:
	return kind.damage * Evolutions.DAMAGE_MULT.get(evolution, 1.0) * color_damage_mult()


## 빨강 색깔 보너스: 공격력 배율 (다른 색이면 1.0)
func color_damage_mult() -> float:
	return 1.0 + lane.color_bonus_value("빨강") if color_info.name == "빨강" else 1.0


## 주황 색깔 보너스: 공격속도 배율 (다른 색이면 1.0)
func color_speed_mult() -> float:
	return 1.0 + lane.color_bonus_value("주황") if color_info.name == "주황" else 1.0


## 다음 공격까지의 시간 (광란 중첩만큼 빨라진다 + 색깔 보너스)
func cur_cooldown() -> float:
	var cd: float = Evolutions.COOLDOWN.get(evolution, kind.cooldown)
	if evolution == "growth" and haste_stacks > 0 and has_skill("B"):
		cd /= 1.0 + haste_stacks * _p("B", "haste")
	return cd / color_speed_mult()


## 실제 사거리 (색깔 보너스 반영)
func cur_range() -> float:
	var r: float = kind.range
	# 노랑 색깔 보너스: 사거리 증가
	if color_info.name == "노랑":
		var bonus := lane.color_bonus_value("노랑")
		r *= (1.0 + bonus)
	return r


## 색깔을 바꾼다 (LaneController.recolor_tower가 골드 처리를 한 뒤 부른다)
func set_color_info(info: Dictionary) -> void:
	color_info = info
	queue_redraw()


## 선택한 타워 정보창에 보여줄 색깔 보너스 한 줄
func color_bonus_text() -> String:
	var cname: String = color_info.name
	var lv := lane.color_level(cname)
	var type: String = Balance.COLOR_BONUS_TYPES[cname]
	if lv == 0:
		return "색깔 %s Lv0: %s -" % [cname, Balance.COLOR_BONUS_LABELS[type]]
	var text := "색깔 %s Lv%d: %s %s" % [cname, lv, Balance.COLOR_BONUS_LABELS[type], Balance.color_bonus_value_text(cname, lv)]
	if type == "damage" and evolution == "skill":
		text += " (스킬형은 공격력이 없어 효과 없음)"
	return text


## 방어력 관통 비율 (파랑 색깔 보너스). Monster.take_damage가 맞은 타워에게 물어본다.
func armor_penetration() -> float:
	return lane.color_bonus_value("파랑") if color_info.name == "파랑" else 0.0


## 치명타 확률 (성장형: 처치할 때마다 오른다)
func crit_chance() -> float:
	if evolution != "growth":
		return 0.0
	return minf(_p("A", "cap"), Evolutions.CRIT_BASE + _p("A", "per_kill") * kills)


## 충전형이 모을 수 있는 최대 충전량 ("충전 상한" 업그레이드)
func charge_max() -> float:
	return _p("A", "cap") if evolution == "charge" else Evolutions.CHARGE_MIN


func charge_ratio() -> float:
	return clampf(charge / charge_max(), 0.0, 1.0)


func _process(delta: float) -> void:
	if preview:
		return  # 아이콘은 가만히 둔다

	_t += delta
	_recoil = maxf(0.0, _recoil - delta * 5.0)
	# 트랩은 바닥에 깔린 함정이라 살짝 투명하게 (선택하면 또렷하게)
	modulate.a = 1.0 if (kind.blocks or selected) else TRAP_ALPHA
	position = center_cell_pos() * _renderer.CELL_SIZE

	if lane.active:
		if _haste_timer > 0.0:
			_haste_timer -= delta
			if _haste_timer <= 0.0:
				haste_stacks = 0  # 치명타가 한동안 안 터지면 광란 초기화
		if sealed_time > 0.0:
			sealed_time = maxf(0.0, sealed_time - delta)  # 봉인된 동안은 조준도 공격도 충전도 하지 않는다
		else:
			var target := lane.find_target(center_cell_pos(), cur_range(), kind.anti_air)
			if target:
				var want := (target.cell_pos - center_cell_pos()).angle()
				_aim = lerp_angle(_aim, want, minf(1.0, delta * 14.0))

			if evolution == "charge":
				_process_charge(delta, target)
			else:
				_cooldown -= delta
				if target and _cooldown <= 0.0:
					_fire(target)
	queue_redraw()


# --- 공격 ---

func _fire(target: Monster) -> void:
	_cooldown = cur_cooldown()
	_recoil = 1.0
	match evolution:
		"support":
			_fire_cloud(target)
		"barrage":
			_fire_volley(target)
			# 연속 발사: 확률로 한 번 더 (위력은 "연발 위력" 항목)
			if randf() < _p("A", "chance"):
				_second_volley()
		_:
			_shoot(target)


## 투사체 1발 (진화 계열에 따라 피해/효과가 붙는다)
func _shoot(target: Monster, power: float = 1.0) -> void:
	var dmg: float = cur_damage() * power
	var fx := {}
	match evolution:
		"pierce":
			fx.pierce = int(_p("A", "count"))
			fx.falloff = _p("A", "falloff")
			if has_skill("B"):
				fx.poison = {"dps": _p("B", "dps"), "time": _p("B", "time")}
		"boss":
			fx.armor_break = {"chance": _p("A", "chance"), "time": _p("A", "time")}
			if has_skill("B"):
				fx.execute = {"chance": _p("B", "chance"), "hp": _p("B", "hp")}
		"mass":
			_shot_count += 1
			if _shot_count >= int(_p("A", "every")):
				_shot_count = 0
				dmg *= _p("A", "mult")  # N번에 한 번 더 강한 공격
				Effects.float_text(_renderer, center_cell_pos(), "강타!", evo_color(), lane.lane_visible)
			if has_skill("B"):
				fx.center = {"radius": _p("B", "radius"), "mult": _p("B", "mult")}
		"skill":
			dmg = 0.0  # 스킬형은 공격력이 없다. 공격이 맞을 때 확률로 스킬만 터진다
			fx.snare = {"chance": _p("A", "chance"), "radius": _p("A", "radius"), "slow": _p("A", "slow"), "time": _p("A", "time")}
			if has_skill("B"):
				fx.capture = {"chance": _p("B", "chance"), "time": _p("B", "time")}
		"growth":
			if randf() < crit_chance():
				dmg *= Evolutions.CRIT_MULT
				Effects.float_text(_renderer, center_cell_pos(), "치명!", evo_color(), lane.lane_visible)
				if has_skill("B"):  # 광란: 치명타가 터지면 공격속도 중첩, 일정 시간 치명타가 없으면 초기화
					haste_stacks = mini(haste_stacks + 1, Evolutions.HASTE_MAX_STACKS)
					_haste_timer = _p("B", "time")

	var muzzle := center_cell_pos() + Vector2.from_angle(_aim) * 0.45
	var color: Color = evo_color() if fx.has("snare") else kind.color
	Effects.spawn_projectile(_renderer, lane, muzzle, target, kind, color, self, dmg, fx)


## 난사형: 한 번에 N발 (가능하면 서로 다른 적을 조준, 적이 모자라면 같은 적에게 겹쳐 쏜다)
func _fire_volley(target: Monster, power: float = 1.0) -> void:
	var count := int(_p("B", "missiles")) if has_skill("B") else 1
	if has_skill("B"):
		power *= _p("B", "power")  # 일제 사격 미사일 한 발의 위력
	if count <= 1:
		_shoot(target, power)
		return
	var targets := lane.find_targets(center_cell_pos(), cur_range(), kind.anti_air, count)
	if targets.is_empty():
		targets.append(target)
	for i in range(count):
		_shoot(targets[i % targets.size()], power)


func _second_volley() -> void:
	await get_tree().create_timer(0.18, false).timeout  # false: 일시정지 중에는 멈춘다
	if not is_instance_valid(self) or lane == null or not lane.active:
		return
	var t := lane.find_target(center_cell_pos(), cur_range(), kind.anti_air)
	if t:
		_recoil = 1.0
		_fire_volley(t, _p("A", "second"))


## 지원형: 공격 대신 표식 구름을 깐다
func _fire_cloud(target: Monster) -> void:
	Effects.spawn_cloud(_renderer, lane, target.cell_pos, _p("A", "radius"), _p("A", "time"), self, _p("A", "dmg") * color_damage_mult(), evo_color())


## 충전형: 기본 공격 없음. 에너지를 모으다가 적이 들어오면 부비 트랩 폭발
func _process_charge(delta: float, target: Monster) -> void:
	charge = minf(charge_max(), charge + delta * _p("A", "rate") * color_speed_mult())
	if target and charge >= Evolutions.CHARGE_MIN:
		_detonate()


func _detonate() -> void:
	var dmg: float = kind.damage * (1.0 + charge * Evolutions.CHARGE_DMG_PER_SEC) * color_damage_mult()
	var full := charge >= charge_max() - 0.001
	var stun := _p("B", "stun") if (full and has_skill("B")) else 0.0
	var r := cur_range()
	for m in lane.monsters.duplicate():
		if is_instance_valid(m) and not m.is_dead() and m.flying == kind.anti_air \
				and m.cell_pos.distance_to(center_cell_pos()) <= r:
			m.take_damage(dmg, self)
			if stun > 0.0 and not m.is_dead():
				m.apply_stun(stun)
	Effects.ring(_renderer, center_cell_pos(), r, evo_color(), lane.lane_visible)
	Effects.float_text(_renderer, center_cell_pos(), "과충전!" if stun > 0.0 else "폭발!", evo_color(), lane.lane_visible)
	charge = 0.0
	_recoil = 1.0


# --- 그리기 ---

func _stripe2() -> Color:
	return evo_color()


func _cell_px() -> float:
	return preview_cell if _renderer == null else float(_renderer.CELL_SIZE)


func _draw() -> void:
	var cell_px := _cell_px()
	var s := cell_px * 0.88
	var c: Color = color_info.color

	# 선택됨: 사거리 원 + 선택 테두리
	if selected and not preview:
		var r := cur_range()
		draw_circle(Vector2.ZERO, r * cell_px, Color(1, 1, 1, 0.07))
		draw_arc(Vector2.ZERO, r * cell_px, 0.0, TAU, 48, Color(1, 1, 1, 0.5), 2.0)
		draw_rect(Rect2(-cell_px * 0.5, -cell_px * 0.5, cell_px, cell_px).grow(-1.0), Color(1, 1, 0.4), false, 2.0)

	# 바닥판 + 색깔 테두리 (테두리 색은 색깔 보너스용으로 건설할 때 랜덤 배정된 색)
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(0.13, 0.13, 0.17))
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(c, 0.28))
	draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), c, false, 3.0)

	# 기본 종류가 생김새로 구분된다
	#  장거리 = 아주 긴 가는 포신 / 범위 = 나팔 모양 포구 + 둥근 포탄(박격포)
	#  대공 = 쌍둥이 미사일(분홍 머리) / 트랩 = 포신 없이 납작하게 깔린 가시판
	match kind.id:
		"long":
			_draw_gun(s, true, false)
		"splash":
			_draw_gun(s, false, true)
		"air":
			_draw_missiles(s)
		_:
			_draw_trap_plate(s)

	if not preview:
		_draw_evolution_marks(s)
		_draw_damage_marks(s)


## 내구도가 닳은 타워는 아래에 막대와 균열을, 봉인 예고/봉인 중인 타워는 보라색 표식을 그린다
func _draw_damage_marks(s: float) -> void:
	var ratio := clampf(durability / Balance.TOWER_DURABILITY, 0.0, 1.0)
	if ratio < 0.999:
		var bar_y := s * 0.5 + 2.0
		draw_rect(Rect2(-s * 0.5, bar_y, s, 4.0), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(-s * 0.5, bar_y, s * ratio, 4.0), Color(1.0, 0.25 + 0.5 * ratio, 0.1))
		var cracks := ceili((1.0 - ratio) * 3.0)  # 많이 닳을수록 금이 늘어난다
		var crack_col := Color(0.04, 0.04, 0.06)
		if cracks >= 1:
			draw_polyline(PackedVector2Array([Vector2(-s * 0.35, -s * 0.45), Vector2(-s * 0.15, -s * 0.1), Vector2(-s * 0.3, s * 0.1)]), crack_col, 2.0)
		if cracks >= 2:
			draw_polyline(PackedVector2Array([Vector2(s * 0.4, -s * 0.2), Vector2(s * 0.1, 0.0), Vector2(s * 0.25, s * 0.35)]), crack_col, 2.0)
		if cracks >= 3:
			draw_polyline(PackedVector2Array([Vector2(-s * 0.1, s * 0.45), Vector2(s * 0.05, s * 0.2), Vector2(-s * 0.05, -s * 0.3)]), crack_col, 2.0)
	var purple := Color(0.75, 0.35, 0.95)
	if sealed_time > 0.0:
		draw_rect(Rect2(-s * 0.5, -s * 0.5, s, s), Color(purple, 0.4))
		draw_line(Vector2(-s * 0.35, -s * 0.35), Vector2(s * 0.35, s * 0.35), purple, 3.0)
		draw_line(Vector2(s * 0.35, -s * 0.35), Vector2(-s * 0.35, s * 0.35), purple, 3.0)
	elif seal_warn:
		var pulse := 0.55 + 0.45 * sin(_t * 12.0)
		draw_rect(Rect2(-s * 0.5 - 2.0, -s * 0.5 - 2.0, s + 4.0, s + 4.0), Color(purple, pulse), false, 3.5)


## 진화 표시: 오른쪽 아래 마름모(계열 색), 충전형은 충전 게이지, 성장형은 광란 중첩 점
func _draw_evolution_marks(s: float) -> void:
	if evolution == "":
		return
	var col := evo_color()
	var p := Vector2(s * 0.5 - 6.0, s * 0.5 - 6.0)
	draw_colored_polygon(PackedVector2Array([
		p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0)]), col)
	draw_polyline(PackedVector2Array([
		p + Vector2(0, -6), p + Vector2(6, 0), p + Vector2(0, 6), p + Vector2(-6, 0), p + Vector2(0, -6)]), Color(0.1, 0.1, 0.15), 1.2)

	if evolution == "charge":
		var ready := charge >= Evolutions.CHARGE_MIN
		var ring_col := col if ready else Color(col, 0.45)
		draw_arc(Vector2.ZERO, s * 0.5 + 3.0, -PI * 0.5, -PI * 0.5 + TAU * charge_ratio(), 32, ring_col, 3.0)
	elif evolution == "growth":
		for i in range(haste_stacks):
			draw_circle(Vector2(-s * 0.5 + 4.0 + i * 5.0, s * 0.5 - 4.0), 2.0, col)


func _aim_angle() -> float:
	return preview_aim if preview else _aim


## 포신(대포/박격포): 길이=장거리, 나팔 포구+포탄=범위
func _draw_gun(s: float, has_long: bool, has_splash: bool) -> void:
	var steel := Color(0.78, 0.8, 0.88)
	var dark := Color(0.16, 0.17, 0.24)
	var length := s * (0.95 if has_long else 0.5) - _recoil * s * 0.1
	var width := s * (0.1 if has_long else 0.15)
	var hub := s * 0.22

	draw_set_transform(Vector2.ZERO, _aim_angle(), Vector2.ONE)
	draw_rect(Rect2(0, -width * 0.5, length, width), steel)
	draw_rect(Rect2(0, -width * 0.5, length, width), dark, false, 1.5)
	# 색 띠 두 줄 (포신에 두른 줄무늬: 기본 종류 색 + 진화 계열 색)
	draw_rect(Rect2(length * 0.2, -width * 0.5 - 1, maxf(3.0, length * 0.09), width + 2), kind.color)
	draw_rect(Rect2(length * 0.38, -width * 0.5 - 1, maxf(3.0, length * 0.09), width + 2), _stripe2())
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
		draw_arc(bomb, s * 0.15, 0.0, TAU, 14, kind.color, 2.0)
		draw_circle(bomb + Vector2(s * 0.05, -s * 0.12), s * 0.04, Color(1.0, 0.7, 0.2))  # 도화선 불꽃
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	draw_circle(Vector2.ZERO, hub, Color(0.28, 0.3, 0.38))
	draw_arc(Vector2.ZERO, hub, 0.0, TAU, 18, dark, 2.0)
	draw_circle(Vector2.ZERO, hub * 0.5, color_info.color)


## 대공: 나란한 쌍둥이 미사일 (분홍 뾰족 머리)
func _draw_missiles(s: float) -> void:
	var steel := Color(0.85, 0.87, 0.93)
	var dark := Color(0.16, 0.17, 0.24)
	var air: Color = kind.color
	var ml := s * 0.52 - _recoil * s * 0.1
	var mw := s * 0.1
	var off := s * 0.13
	var x0 := s * 0.06

	draw_set_transform(Vector2.ZERO, _aim_angle(), Vector2.ONE)
	for side in [-1.0, 1.0]:
		var y: float = side * off
		draw_rect(Rect2(x0, y - mw * 0.5, ml, mw), steel)
		draw_rect(Rect2(x0, y - mw * 0.5, ml, mw), dark, false, 1.2)
		draw_rect(Rect2(x0 + ml * 0.35, y - mw * 0.5 - 1, maxf(2.5, ml * 0.1), mw + 2), _stripe2())
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


## 트랩: 포신 없이 납작하게 깔린 가시판
func _draw_trap_plate(s: float) -> void:
	var spike: Color = kind.color
	var dark := Color(0.16, 0.17, 0.24)

	# 사방으로 뻗은 가시
	var count := 8
	var spike_len := s * 0.34
	var spike_w := s * 0.1
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
