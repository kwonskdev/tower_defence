extends Node2D
class_name Monster
## 몬스터. 플레이어가 조종하지 않고 자동으로 경로를 따라 이동한다.
## - 연속 좌표(cell_pos, 셀 단위)로 움직이며 웨이포인트를 향해 어느 방향으로든 직진한다.
## - 지상: 타워를 우회해서 목표(EXIT 또는 goal_cell/final_point)로 이동.
##   길이 완전히 막히면 앞을 막은 타워를 공격 (일반형 공격력 = 무한대 -> 한 방에 파괴)
## - 공중(flying): 미로/타워를 무시하고 맨 아래로 직선 이동. 대공 타워만 공격 가능.
## - 방어력(armor): 한 발 피해를 평면으로 깎는다. 재생(regen): 초당 최대체력 비율만큼 회복.
## - 보스 레인의 몬스터는 final_point(보스 주변 자리)에 도착하면 멈추고 보스를 지속 공격한다.
##   성장(ramp)과 오라(aura)는 BossController가 계산한다.
## - preview=true이면 아이콘용 미리보기: 길찾기 없이 제자리에서 애니메이션만 한다.
## - 시야: 사방 VISION_RANGE(3)칸 안의 타워만 본다. 본 타워는 기억하고, 못 본 타워는 없는 것으로 알고 길을 짠다.
##   (맵 지형은 안다.) 타워가 시야에 새로 들어오거나 사라지면 그때 길을 다시 계산한다.

signal reached_exit(monster: Monster)
signal died(monster: Monster)

const DEFAULT_SPEED := 3.0
const ARRIVE_DISTANCE := 0.1
const TOWER_ATTACK_DISTANCE := 0.95   # 웨이포인트 타워 중심까지 이 거리 이하면 타워를 공격
const FLY_LIFT := 0.42                # 공중 몬스터가 몸을 띄우는 높이(칸)
const MIN_DAMAGE_RATIO := 0.2         # 방어력이 아무리 높아도 최소한 이 비율만큼은 들어간다
const VISION_RANGE := 3               # 사방 이 칸 수 안의 타워만 본다
const VISION_INTERVAL := 0.1          # 시야를 확인하는 주기(초)

var monster_id: int = 0
var owner_id: int = -1           # 보스 레인으로 보낸 플레이어 (보스가 보낸 몬스터는 -1)
var kind_id: String = "wave"
var shape: String = "horn"       # 외형 (decor 이름)
var speed: float = DEFAULT_SPEED
var size_scale: float = 1.0
var life_damage: int = 1         # 기지에 닿았을 때 줄이는 생명
var reward: int = 2              # 처치 시 골드
var max_hp: float = 1.0
var hp: float = 1.0
var armor: float = 0.0
var regen: float = 0.0           # 초당 최대체력 회복 비율
var flying: bool = false
var body_color: Color = Color(0.85, 0.2, 0.2)

# 보스 레인에서 쓰는 값 (내가 보낸 몬스터)
var dps: float = 0.0             # 기본 초당 피해
var ramp: float = 0.0            # 보스 앞에 선 뒤 초당 dps 증가량
var ramp_cap: float = 0.0
var aura_radius: float = 0.0     # 지원형: 주변 아군 dps 증가
var aura_bonus: float = 0.0
var time_at_boss: float = 0.0    # 보스 앞에 선 뒤 지난 시간
var current_dps: float = 0.0     # 성장/오라까지 반영한 실제 dps

# 목표: goal_cell을 주면 그 칸까지 간 뒤 final_point로 이동, 주지 않으면 맨 아래 EXIT 행
var goal_cell: Vector2i = Pathfinder.NO_GOAL
var final_point: Vector2 = Vector2.ZERO
var attack_dir: Vector2 = Vector2.DOWN  # 정지 후 공격하는 방향 (보스 쪽)

var grid_pos: Vector2i           # 현재 있는 셀
var cell_pos: Vector2            # 현재 위치 (셀 단위, 셀 중심 = +0.5)
var waypoints: Array[Vector2] = []  # 앞으로 지나갈 지점들
var facing: Vector2 = Vector2.DOWN
var breaching: bool = false
var stopped: bool = false

# 아이콘 미리보기용
var preview: bool = false
var preview_cell: float = 40.0

# 상태이상 (타워 진화 스킬이 건다)
var marks: Array = []            # 표식 [{src: 타워, dmg: 추가 피해}] - 중첩되며, 타워에게 맞으면 한 번에 터진다
var death_marks: Array = []      # 죽는 순간 퍼뜨릴 표식 (표식 전파용)
var armor_break_time: float = 0.0
var slow_time: float = 0.0
var slow_mult: float = 1.0
var stun_time: float = 0.0
var captured_time: float = 0.0   # 공중 몬스터를 지상에 붙잡아 둔 남은 시간

var known_towers: Dictionary = {}  # 시야에 들어온 적 있는 타워 칸 {Vector2i: true}
var _vision_dirty := true
var _vision_timer := 0.0

var _poisons: Array = []         # [{src, stacks, dps, time}] 독 (타워별로 따로 집계)
var _empower_buffs: Array = []   # [{end_time: float, boost: float}] 강화 버프 (시간 순 정렬, 중첩 가능)
var _consumed_marks: Array = []  # 이번 타격에 터진 표식
var _captured := false
var _killer = null               # 이 몬스터를 처치한 타워 (색깔 보너스 처리용)

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _no_path_warned := false
var _dead := false
var _arrived := false
var _hit_flash := 0.0
var _anim := 0.0


## 데이터 딕셔너리(WaveTypes / SentMonsters 항목)의 공통 외형 값을 적용한다
func apply_look(data: Dictionary) -> void:
	shape = data.shape
	body_color = data.color
	size_scale = data.size
	speed = data.speed


func setup(id: int, grid: GridSystem, renderer: GridRenderer, pathfinder: Pathfinder, spawn_cell: Vector2i) -> void:
	monster_id = id
	_grid = grid
	_renderer = renderer
	_pathfinder = pathfinder
	grid_pos = spawn_cell
	cell_pos = Vector2(spawn_cell) + Vector2(0.5, 0.5)
	hp = max_hp
	_anim = randf() * TAU
	_update_position()

	# pathfinder가 먼저 연결되어 있으므로 dirty 처리 후 이 핸들러가 호출된다.
	_grid.cell_state_changed.connect(_on_grid_changed)
	_scan_vision()
	_repath()


## 타워의 직접 공격을 받는다. source: 때린 타워 (해제된 객체가 올 수 있어 타입을 안 붙임).
## - 맞은 순간 실제로 깎인 체력만큼 때린 타워의 누적 피해가 오르고, 마지막 한 방을 때린 타워만 킬이 오른다.
## - 표식이 있으면 이 타격에 한 번에 터진다. 표식 피해는 표식을 남긴 타워 몫, 킬은 때린 타워 몫.
func take_damage(amount: float, source = null) -> void:
	if _dead:
		return
	var consumed := marks
	marks = []
	_consumed_marks = consumed
	for mk in consumed:  # 표식을 먼저 터뜨린다 (이 타격이 먼저 죽이면 지원 타워의 추가 피해가 낭비되므로)
		_lose_hp(float(mk.dmg), mk.src, source)
	# 방어력: 한 발 피해를 평면으로 깎되, 최소 MIN_DAMAGE_RATIO는 들어간다 (파랑 타워는 방어력의 일부를 무시)
	var pen := 0.0
	if is_instance_valid(source) and source.has_method("armor_penetration"):
		pen = source.armor_penetration()
	_lose_hp(maxf(amount - effective_armor() * (1.0 - pen), amount * MIN_DAMAGE_RATIO), source, source)
	_hit_flash = 0.1
	if not _dead:
		_consumed_marks = []


## 체력을 실제로 깎는다. damage_source: 누적 피해를 올려 줄 타워, kill_source: 죽였을 때 킬을 올려 줄 타워.
## 강화(남색 보너스) 중이면 받는 피해가 1/(1+강화)로 줄어든다 = 체력 +강화%. 처형은 강화를 무시한다 (ignore_empower).
func _lose_hp(amount: float, damage_source, kill_source, ignore_empower := false) -> void:
	if _dead:
		return
	if not ignore_empower and not _empower_buffs.is_empty():
		amount /= 1.0 + get_total_empower()
	var applied := minf(amount, maxf(hp, 0.0))  # 남은 체력을 넘는 초과분은 피해로 치지 않는다
	hp -= amount
	if is_instance_valid(damage_source):  # 투사체가 날아가는 사이 타워가 부서졌을 수 있다
		damage_source.record_damage(applied)
	if hp <= 0.0:
		if is_instance_valid(kill_source):
			_killer = kill_source
			kill_source.record_kill()
		_die()


func _die() -> void:
	_dead = true
	death_marks = _consumed_marks + marks  # 이번 타격에 터진 표식 + 남은 표식 (표식 전파용)
	died.emit(self)


## 처형: 남은 체력만큼의 피해로 즉사시킨다 (피해/킬은 source 몫)
func execute(source) -> void:
	if _dead:
		return
	_lose_hp(maxf(hp, 0.0) + 0.001, source, source, true)


func is_dead() -> bool:
	return _dead


func effective_armor() -> float:
	return 0.0 if armor_break_time > 0.0 else armor


func speed_mult() -> float:
	return slow_mult if slow_time > 0.0 else 1.0


# --- 상태이상 ---

func add_mark(src, dmg: float) -> void:
	marks.append({"src": src, "dmg": dmg})


## 독: 같은 타워의 독은 중첩되고 (무한), 맞을 때마다 유지 시간이 갱신된다. 방어력 무시.
func add_poison(src, dps: float, duration: float) -> void:
	for e in _poisons:
		if is_same(e.src, src):
			e.stacks += 1
			e.dps = dps
			e.time = duration
			return
	_poisons.append({"src": src, "stacks": 1, "dps": dps, "time": duration})


func apply_armor_break(duration: float) -> void:
	armor_break_time = maxf(armor_break_time, duration)


## 감속: ratio = 줄어드는 비율 (0.4 = 40% 느려짐). 더 강한 감속이 우선.
func apply_slow(ratio: float, duration: float) -> void:
	var mult := 1.0 - ratio
	slow_mult = mult if slow_time <= 0.0 else minf(slow_mult, mult)
	slow_time = maxf(slow_time, duration)


func apply_stun(duration: float) -> void:
	stun_time = maxf(stun_time, duration)


# --- 강화 시스템 (남색 색깔 보너스) ---

## 강화 버프 추가 (중첩 가능)
func add_empower(duration: float, boost: float) -> void:
	var now := Time.get_ticks_msec() / 1000.0
	_empower_buffs.append({"end_time": now + duration, "boost": boost})
	# 종료 시간 순으로 정렬
	_empower_buffs.sort_custom(func(a, b): return a.end_time < b.end_time)
	while _empower_buffs.size() > Balance.EMPOWER_MAX_STACKS:
		_empower_buffs.remove_at(0)  # 가장 먼저 끝나는 것을 밀어낸다


## 현재 적용 중인 강화 효과 총합 (만료된 버프는 제거)
func get_total_empower() -> float:
	var now := Time.get_ticks_msec() / 1000.0
	var total := 0.0
	# 만료된 버프 제거 (역순으로)
	for i in range(_empower_buffs.size() - 1, -1, -1):
		if _empower_buffs[i].end_time < now:
			_empower_buffs.remove_at(i)
		else:
			total += _empower_buffs[i].boost
	return total


## 강화가 반영된 실질 체력 (UI/계산용). 체력은 받는 피해를 줄이는 방식으로 반영된다 (_lose_hp).
func get_effective_hp() -> float:
	return hp * (1.0 + get_total_empower())


## 강화가 반영된 DPS (보스 레인 몬스터용). 기본 DPS와 성장(ramp) 증가분 모두 강화를 받는다. 오라는 BossController가 따로 곱한다.
func get_boosted_dps() -> float:
	return (dps + minf(ramp * time_at_boss, ramp_cap)) * (1.0 + get_total_empower())


## 공중 몬스터를 지상에 붙잡는다. 그동안 제자리에 정지하고 지상 몬스터로 취급된다 (끝나면 다시 공중).
func capture(duration: float) -> void:
	if captured_time > 0.0:
		captured_time = maxf(captured_time, duration)
	elif flying:
		captured_time = duration
		flying = false
		_captured = true


func _update_status(delta: float) -> void:
	armor_break_time = maxf(0.0, armor_break_time - delta)
	slow_time = maxf(0.0, slow_time - delta)
	stun_time = maxf(0.0, stun_time - delta)
	if captured_time > 0.0:
		captured_time -= delta
		if captured_time <= 0.0 and _captured:
			_captured = false
			flying = true  # 풀려나면 다시 날아간다 (경로는 그대로 직진)
	for i in range(_poisons.size() - 1, -1, -1):
		var e: Dictionary = _poisons[i]
		e.time -= delta
		if e.time <= 0.0:
			_poisons.remove_at(i)
			continue
		_lose_hp(e.stacks * e.dps * delta, e.src, e.src)  # 독 피해와 킬은 독을 건 타워 몫
		if _dead:
			return


## 공중 몬스터는 몸이 떠 있으므로 투사체/표시는 이만큼 위를 기준으로 한다 (셀 단위)
func visual_offset() -> Vector2:
	return Vector2(0.0, -FLY_LIFT) if flying else Vector2.ZERO


## 이동 중단 (보스 앞 자리에 도착했을 때)
func stop(look_at: Vector2) -> void:
	stopped = true
	waypoints.clear()
	attack_dir = (look_at - cell_pos).normalized()
	facing = attack_dir


## 남은 이동 거리 (타워가 기지에 가장 가까운 몬스터를 노릴 때 사용)
func remaining_distance() -> float:
	var total := 0.0
	var p := cell_pos
	for w in waypoints:
		total += p.distance_to(w)
		p = w
	return total


func _on_grid_changed(_position: Vector2i, _old_state, _new_state) -> void:
	if stopped or flying or _captured:
		return
	if _uses_vision():
		_vision_dirty = true  # 멀리서 바뀐 건 모른다. 시야 안이면 곧 알아채고 그때 길을 다시 짠다
	else:
		_repath()


## 시야 제한을 받는가 (일반 웨이브 지상 몬스터. 보스 레인 몬스터는 목표가 정해져 있어 전부 안다)
func _uses_vision() -> bool:
	return goal_cell == Pathfinder.NO_GOAL and not flying and not _captured


## 사방 VISION_RANGE칸을 훑어서 본 타워를 기억하고, 사라진 타워는 잊는다. 바뀐 게 있으면 true.
func _scan_vision() -> bool:
	var changed := false
	for dy in range(-VISION_RANGE, VISION_RANGE + 1):
		for dx in range(-VISION_RANGE, VISION_RANGE + 1):
			var c := grid_pos + Vector2i(dx, dy)
			var is_tower := _grid.get_cell_state(c) == GridSystem.CellState.TOWER
			if is_tower and not known_towers.has(c):
				known_towers[c] = true
				changed = true
			elif not is_tower and known_towers.has(c):
				known_towers.erase(c)
				changed = true
	return changed


func _repath() -> void:
	if flying:
		# 공중: 미로를 무시하고 지금 위치에서 맨 아래까지 직선
		waypoints.clear()
		waypoints.append(Vector2(cell_pos.x, GridSystem.GRID_HEIGHT - 0.5))
		breaching = false
		return

	# 지금 서 있는 위치에서 다시 계산하므로 뒤로 되돌아가는 일이 없다.
	var result := _pathfinder.find_route(cell_pos, goal_cell, known_towers if _uses_vision() else null)
	waypoints.assign(result.waypoints)
	breaching = result.breach

	if result.ok and goal_cell != Pathfinder.NO_GOAL:
		waypoints.append(final_point)

	if not result.ok:
		if not _no_path_warned:
			Log.warn(Log.Category.MONSTER_AI, "[%s] 몬스터#%d 경로 없음 (위치=%s)" % [
				_grid.lane_tag(), monster_id, cell_pos])
			_no_path_warned = true
	else:
		_no_path_warned = false
		Log.debug(Log.Category.MONSTER_AI, "[%s] 몬스터#%d 경로 계산: 위치=(%.1f, %.1f) 웨이포인트=%d 돌파=%s" % [
			_grid.lane_tag(), monster_id, cell_pos.x, cell_pos.y, waypoints.size(), breaching])


func _process(delta: float) -> void:
	if preview and not is_visible_in_tree():
		return
	_anim += delta
	if _hit_flash > 0.0:
		_hit_flash -= delta
	queue_redraw()
	if preview:
		return

	if regen > 0.0 and hp < max_hp and not _dead:
		hp = minf(max_hp, hp + max_hp * regen * delta)

	_update_status(delta)
	if _dead:
		return
	if stun_time > 0.0 or captured_time > 0.0:
		return  # 기절/포획 중에는 제자리에 멈춘다

	# 시야: 주기적으로(또는 격자가 바뀌었을 때) 주변을 훑고, 새로 보이거나 사라진 타워가 있을 때만 길을 다시 계산
	if not stopped and _uses_vision():
		_vision_timer -= delta
		if _vision_dirty or _vision_timer <= 0.0:
			_vision_dirty = false
			_vision_timer = VISION_INTERVAL
			if _scan_vision():
				_repath()

	if stopped:
		return
	if waypoints.is_empty():
		_check_arrival()
		return

	var target := waypoints[0]
	var target_cell := Vector2i(target.floor())

	# 다음 목적지가 타워 칸이면 가까워졌을 때 공격 (일반형: 공격력 무한대 -> 즉시 파괴, 환급 0원)
	if not flying and _grid.get_cell_state(target_cell) == GridSystem.CellState.TOWER \
			and cell_pos.distance_to(target) <= TOWER_ATTACK_DISTANCE:
		Log.info(Log.Category.TOWER, "[%s] 몬스터#%d가 타워 파괴 %s" % [_grid.lane_tag(), monster_id, target_cell])
		_grid.set_cell_state(target_cell, GridSystem.CellState.EMPTY)  # 경로 재계산은 신호로 처리됨
		return

	var to_target := target - cell_pos
	var step := speed * speed_mult() * delta
	if to_target.length() <= step:
		cell_pos = target
		waypoints.pop_front()
	else:
		facing = to_target.normalized()
		cell_pos += facing * step

	grid_pos = Vector2i(cell_pos.floor())
	_update_position()

	if waypoints.is_empty():
		_check_arrival()


func _check_arrival() -> void:
	if _arrived:
		return
	var arrived := false
	if goal_cell == Pathfinder.NO_GOAL:
		arrived = _grid.get_cell_state(grid_pos) == GridSystem.CellState.EXIT
	else:
		arrived = cell_pos.distance_to(final_point) <= ARRIVE_DISTANCE
	if arrived:
		_arrived = true
		reached_exit.emit(self)


func _cell_px() -> float:
	return preview_cell if _renderer == null else float(_renderer.CELL_SIZE)


func _update_position() -> void:
	position = cell_pos * _cell_px()


func _draw() -> void:
	var cell := _cell_px()
	var r: float = cell * 0.32 * size_scale
	var moving := preview or (not stopped and not waypoints.is_empty())

	# 걷는 동안 통통 튀고, 멈추면 숨쉬듯 흔들림. 보스 앞에서는 보스 쪽으로 달려들었다 물러남.
	var bob := absf(sin(_anim * speed * 3.0)) * cell * 0.09 if moving else sin(_anim * 3.0) * cell * 0.015
	var lunge := Vector2.ZERO
	if stopped:
		lunge = attack_dir * maxf(0.0, sin(_anim * 9.0)) * cell * 0.14
	var lift := Vector2(0.0, -cell * FLY_LIFT) if flying else Vector2.ZERO
	var c := Vector2(0, -bob) + lunge + lift

	var color := body_color
	if breaching:
		color = Color(1.0, 0.85, 0.2)
	if _hit_flash > 0.0:
		color = Color.WHITE

	# 지원형: 오라 범위 표시
	if aura_radius > 0.0 and stopped and not preview:
		var ar := aura_radius * cell
		draw_circle(Vector2.ZERO, ar, Color(body_color, 0.07))
		draw_arc(Vector2.ZERO, ar, 0.0, TAU, 40, Color(body_color, 0.35), 2.0)

	# 그림자 (공중 몬스터는 바닥에 작고 흐리게)
	draw_set_transform(Vector2(0, r * 0.95), 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2.ZERO, r * (0.7 if flying else 1.0), Color(0, 0, 0, 0.18 if flying else 0.3))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	_draw_decor_back(c, r, color)

	# 몸통
	draw_circle(c, r, color)
	draw_arc(c, r, 0.0, TAU, 24, color.darkened(0.45), 2.0)
	draw_circle(c + Vector2(-r * 0.3, -r * 0.35), r * 0.28, color.lightened(0.35))  # 하이라이트

	_draw_decor_front(c, r, color)

	# 눈 (이동 방향을 쳐다봄)
	var dir := facing if facing.length() > 0.01 else Vector2.DOWN
	var perp := Vector2(-dir.y, dir.x)
	var eye_center := c + dir * r * 0.3
	for side in [-1.0, 1.0]:
		var e: Vector2 = eye_center + perp * r * 0.38 * side
		draw_circle(e, r * 0.24, Color.WHITE)
		draw_circle(e + dir * r * 0.09, r * 0.12, Color(0.05, 0.05, 0.1))

	# 상태이상 표시: 독=초록 / 감속=하늘 / 기절·포획=노랑 고리, 방어구 파괴=빨간 조각, 표식=보라 마름모
	if not preview:
		var rr := r * 1.3
		if not _poisons.is_empty():
			draw_arc(c, rr, 0.0, TAU, 20, Color(0.4, 0.95, 0.3, 0.9), 2.0)
		if slow_time > 0.0:
			draw_arc(c, rr + 3.0, 0.0, TAU, 20, Color(0.5, 0.8, 1.0, 0.9), 2.0)
		if stun_time > 0.0 or captured_time > 0.0:
			draw_arc(c, rr + 6.0, 0.0, TAU, 20, Color(1.0, 0.9, 0.2, 0.95), 2.5)
		if armor_break_time > 0.0:
			draw_arc(c, r * 1.05, PI * 0.1, PI * 0.9, 8, Color(1.0, 0.25, 0.2), 3.0)
		for i in range(mini(marks.size(), 8)):
			var mp := c + Vector2((i - minf(marks.size(), 8.0) * 0.5 + 0.5) * 8.0, -r - cell * 0.38)
			draw_colored_polygon(PackedVector2Array([
				mp + Vector2(0, -4), mp + Vector2(3.5, 0), mp + Vector2(0, 4), mp + Vector2(-3.5, 0)]), Color(0.8, 0.5, 1.0))

	# 체력이 깎인 몬스터만 체력바 표시
	if not preview and hp < max_hp and max_hp > 0.0:
		var w := cell * 0.62
		var y := -r - cell * 0.22 + lift.y
		draw_rect(Rect2(-w * 0.5, y, w, 4.0), Color(0, 0, 0, 0.65))
		draw_rect(Rect2(-w * 0.5, y, w * clampf(hp / max_hp, 0.0, 1.0), 4.0), Color(0.3, 0.95, 0.3))


## 몸통 뒤에 그려지는 장식 (뿔, 가시, 날개, 속도선)
func _draw_decor_back(c: Vector2, r: float, color: Color) -> void:
	match shape:
		"horn":
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(side * r * 0.75, -r * 0.45),
					c + Vector2(side * r * 0.35, -r * 1.2),
					c + Vector2(side * r * 0.1, -r * 0.8),
				]), color.darkened(0.3))
		"runner":
			# 속도선 (뒤쪽으로 흩날림)
			var back := -facing if facing.length() > 0.01 else Vector2.UP
			var side_v := Vector2(-back.y, back.x)
			for i in range(3):
				var off := side_v * (i - 1) * r * 0.55
				draw_line(c + back * r * 1.1 + off, c + back * r * (1.9 + i * 0.25) + off, Color(color, 0.55), 2.0)
		"spike":
			for i in range(8):
				var a := i * TAU / 8.0 + _anim * 0.6
				var base := Vector2.from_angle(a)
				var side := Vector2.from_angle(a + PI * 0.5)
				draw_colored_polygon(PackedVector2Array([
					c + base * r * 0.8 + side * r * 0.22,
					c + base * r * 1.45,
					c + base * r * 0.8 - side * r * 0.22,
				]), color.darkened(0.2))
		"bird":
			# 펄럭이는 날개
			var flap := sin(_anim * 16.0)
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(side * r * 0.5, -r * 0.1),
					c + Vector2(side * r * 1.9, -r * (0.9 + 0.6 * flap)),
					c + Vector2(side * r * 1.5, r * 0.35),
				]), color.lightened(0.25))


## 몸통 위에 그려지는 장식 (동전, 방패, 갑옷, 모자, 곡괭이, 금고, 불꽃, 깃발, 새싹, 십자)
func _draw_decor_front(c: Vector2, r: float, color: Color) -> void:
	match shape:
		"coin":
			var p := c + Vector2(0, -r * 1.25)
			draw_circle(p, r * 0.42, Color(1.0, 0.85, 0.2))
			draw_arc(p, r * 0.42, 0.0, TAU, 16, Color(0.7, 0.5, 0.0), 2.0)
			draw_line(p + Vector2(0, -r * 0.2), p + Vector2(0, r * 0.2), Color(0.7, 0.5, 0.0), 2.0)
		"armor":
			var steel := Color(0.82, 0.87, 0.95)
			var dark := Color(0.2, 0.24, 0.32)
			for side in [-1.0, 1.0]:  # 어깨 보호대
				var sp: Vector2 = c + Vector2(side * r * 0.98, r * 0.15)
				draw_circle(sp, r * 0.38, steel)
				draw_arc(sp, r * 0.38, 0.0, TAU, 14, dark, 2.5)
			var plate := PackedVector2Array([  # 투구형 윗판
				c + Vector2(-r * 0.95, -r * 0.1), c + Vector2(r * 0.95, -r * 0.1),
				c + Vector2(r * 0.6, -r * 1.0), c + Vector2(-r * 0.6, -r * 1.0),
			])
			draw_colored_polygon(plate, steel)
			draw_polyline(PackedVector2Array([plate[0], plate[3], plate[2], plate[1]]), dark, 3.0)
			draw_line(c + Vector2(0, -r * 1.0), c + Vector2(0, -r * 0.1), dark, 2.5)
			for rx in [-0.5, 0.5]:
				draw_circle(c + Vector2(r * rx, -r * 0.6), r * 0.09, dark)
			draw_arc(c, r * 1.02, 0.0, TAU, 28, steel, 4.0)
		"shield":
			draw_arc(c, r * 1.18, -PI * 0.15, PI * 1.15, 20, Color(0.85, 0.9, 1.0), 3.0)
			draw_arc(c, r * 1.18, PI * 1.15, PI * 1.85, 10, Color(0.85, 0.9, 1.0, 0.35), 3.0)
		"hat":
			var pts := PackedVector2Array()
			for i in range(9):
				var a := PI + i * PI / 8.0
				pts.append(c + Vector2(cos(a) * r * 0.95, sin(a) * r * 0.8 - r * 0.2))
			draw_colored_polygon(pts, Color(1.0, 0.85, 0.2))
			draw_line(c + Vector2(-r * 1.1, -r * 0.2), c + Vector2(r * 1.1, -r * 0.2), Color(0.8, 0.6, 0.1), 3.0)
		"pick":
			var hand := c + Vector2(r * 0.95, r * 0.5)
			var tip := c + Vector2(r * 1.55, -r * 0.95)
			draw_line(hand, tip, Color(0.5, 0.35, 0.2), 3.0)
			draw_line(tip + Vector2(-r * 0.45, r * 0.1), tip + Vector2(r * 0.4, -r * 0.2), Color(0.8, 0.82, 0.88), 4.0)
		"vault":
			var box := Rect2(c + Vector2(-r * 0.5, r * 0.05), Vector2(r * 1.0, r * 0.75))
			draw_rect(box, Color(0.75, 0.78, 0.85))
			draw_rect(box, Color(0.25, 0.28, 0.35), false, 2.5)
			draw_circle(box.get_center(), r * 0.2, Color(1.0, 0.85, 0.2))
			draw_arc(box.get_center(), r * 0.2, 0.0, TAU, 12, Color(0.4, 0.3, 0.0), 2.0)
		"tophat":
			draw_rect(Rect2(c.x - r * 0.5, c.y - r * 1.7, r * 1.0, r * 1.0), Color(0.1, 0.1, 0.12))
			draw_rect(Rect2(c.x - r * 0.5, c.y - r * 0.95, r * 1.0, r * 0.18), Color(1.0, 0.85, 0.2))
			draw_line(c + Vector2(-r * 0.9, -r * 0.7), c + Vector2(r * 0.9, -r * 0.7), Color(0.1, 0.1, 0.12), 4.0)
		"flame":
			for i in range(3):
				var x := (i - 1) * r * 0.5
				var h := r * (0.9 + 0.4 * sin(_anim * 9.0 + i * 2.0))
				var col := Color(1.0, 0.8, 0.2) if i == 1 else Color(1.0, 0.45, 0.1)
				draw_colored_polygon(PackedVector2Array([
					c + Vector2(x - r * 0.25, -r * 0.7),
					c + Vector2(x, -r * 0.7 - h),
					c + Vector2(x + r * 0.25, -r * 0.7),
				]), col)
		"flag":
			var base := c + Vector2(0, -r * 0.9)
			var wave := sin(_anim * 6.0) * r * 0.15
			draw_line(base, base + Vector2(0, -r * 1.2), Color(0.8, 0.8, 0.8), 2.5)
			draw_colored_polygon(PackedVector2Array([
				base + Vector2(0, -r * 1.2), base + Vector2(r * 0.9, -r * 1.0 + wave), base + Vector2(0, -r * 0.7),
			]), Color(1.0, 0.5, 0.7))
		"banner":
			var base := c + Vector2(0, -r * 0.9)
			var wave := sin(_anim * 5.0) * r * 0.15
			draw_line(base, base + Vector2(0, -r * 1.7), Color(0.6, 0.5, 0.3), 3.0)
			draw_colored_polygon(PackedVector2Array([
				base + Vector2(0, -r * 1.7), base + Vector2(r * 1.1, -r * 1.6 + wave),
				base + Vector2(r * 1.1, -r * 0.95 + wave), base + Vector2(0, -r * 1.0),
			]), Color(0.9, 0.75, 0.25))
			draw_circle(base + Vector2(r * 0.55, -r * 1.3 + wave * 0.5), r * 0.18, Color(0.6, 0.1, 0.1))
		"sprout":
			var g := 1.0 if preview else 0.6 + 0.4 * clampf(time_at_boss / 40.0, 0.0, 1.0)  # 서 있을수록 자란다
			var base := c + Vector2(0, -r * 0.85)
			draw_line(base, base + Vector2(0, -r * 0.5 * g), Color(0.3, 0.6, 0.2), 3.0)
			for side in [-1.0, 1.0]:
				draw_colored_polygon(PackedVector2Array([
					base + Vector2(0, -r * 0.5 * g),
					base + Vector2(side * r * 0.9 * g, -r * 0.9 * g),
					base + Vector2(side * r * 0.5 * g, -r * 0.2 * g),
				]), Color(0.45, 0.85, 0.3))
		"cross":
			var p := c + Vector2(0, r * 0.45)
			draw_rect(Rect2(p.x - r * 0.12, p.y - r * 0.38, r * 0.24, r * 0.76), Color(0.95, 1.0, 0.95))
			draw_rect(Rect2(p.x - r * 0.38, p.y - r * 0.12, r * 0.76, r * 0.24), Color(0.95, 1.0, 0.95))
