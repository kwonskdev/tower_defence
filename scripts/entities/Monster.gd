extends Node2D
class_name Monster
## 몬스터. 플레이어가 조종하지 않고 자동으로 경로를 따라 이동한다.
## - 연속 좌표(cell_pos, 셀 단위)로 움직이며 웨이포인트를 향해 어느 방향으로든 직진한다.
## - 지상: 타워를 우회해서 목표(EXIT 또는 goal_cell/final_point)로 이동.
##   길이 완전히 막히면 앞을 막은 타워를 공격 (일반형 공격력 = 무한대 -> 한 방에 파괴)
## - 공중(flying): 미로/타워를 무시하고 맨 아래로 직선 이동. 대공 타워만 공격 가능.
## - 방어력(armor): 한 발 피해를 평면으로 깎는다. 재생(regen): 초당 최대체력 비율만큼 회복.
## - 유령(ghost): 보스를 일찍 잡았을 때 남은 시간에 나온다. 체력이 무한이라 피해를 받아도 닳지 않고 (받은 피해는 ghost_hit로 알린다),
##   기지에 닿아도 생명을 안 깎는다 (LaneController가 처음부터 다시 내보낸다). 길이 완전히 막혔을 때(breaching)만 앞을 막은
##   타워의 내구도를 breach_dps만큼 깎고, 길이 열려 있으면 타워를 건드리지 않는다.
## - 보스 레인의 몬스터는 final_point(보스 주변 자리)에 도착하면 멈추고 보스를 지속 공격한다.
##   성장(ramp)과 오라(aura)는 BossController가 계산한다.
## - preview=true이면 아이콘용 미리보기: 길찾기 없이 제자리에서 애니메이션만 한다.
## - 시야: 사방 VISION_RANGE(3)칸 안의 타워만 본다. 본 타워는 기억하고, 못 본 타워는 없는 것으로 알고 길을 짠다.
##   (맵 지형은 안다.) 타워가 시야에 새로 들어오거나 사라지면 그때 길을 다시 계산한다.

signal reached_exit(monster: Monster)
signal died(monster: Monster)
signal gnawed(cell: Vector2i, amount: float)  # 타워를 갉는 중: 이 칸의 타워 내구도를 amount(초)만큼 깎아 달라 (LaneController가 처리). 길이 막혀 뚫는 유령도 같은 신호를 쓴다
signal ghost_hit(amount: float, source)       # 유령이 타워에게 amount만큼 피해를 받았다 (source: 때린 타워, 이미 부서졌으면 null). LaneController가 점수로 센다

const DEFAULT_SPEED := 3.0
const ARRIVE_DISTANCE := 0.1
const TOWER_ATTACK_DISTANCE := 0.95   # 웨이포인트 타워 중심까지 이 거리 이하면 타워를 공격
const FLY_LIFT := 0.42                # 공중 몬스터가 몸을 띄우는 높이(칸)
const MIN_DAMAGE_RATIO := 0.2         # 방어력이 아무리 높아도 최소한 이 비율만큼은 들어간다
const VISION_RANGE := 3               # 사방 이 칸 수 안의 타워만 본다
const VISION_INTERVAL := 0.1          # 시야를 확인하는 주기(초)
const GNAW_SEEK_RANGE := 4.0          # 갉는 몬스터가 타워를 목표로 삼는 거리 (본 적 있는 타워 중 이 안에 있는 것)
const GNAW_DISTANCE := 1.15           # 타워 중심까지 이 거리 이하면 멈춰서 갉는다

var monster_id: int = 0
var events: SimEvents = null     # 연출 이벤트 통로 (없으면 연출 없이 시뮬레이션만)
var fx_lane_id: int = -1         # 연출이 나올 레인 번호 (보스 레인이면 GameField.BOSS_LANE_ID)
var owner_id: int = -1           # 보스 레인으로 보낸 플레이어 (보스가 보낸 몬스터는 -1)
var kind_id: String = "wave"
var shape: String = "horn"       # 외형 (decor 이름)
var speed: float = DEFAULT_SPEED
var size_scale: float = 1.0
var life_damage: int = 1         # 기지에 닿았을 때 줄이는 생명
var reward: int = 2              # 처치 시 골드
var max_hp: float = 1.0
var _base_max_hp: float = 1.0   # 강화가 없을 때의 최대 체력 (setup에서 정해진다)
var hp: float = 1.0
var armor: float = 0.0
var regen: float = 0.0           # 초당 최대체력 회복 비율
var flying: bool = false
var body_color: Color = Color(0.85, 0.2, 0.2)

# 타워를 갉아 먹는 몬스터 (슬라임 새끼). 시야 안의 벽 타워를 찾아가 멈춰서 갉는다. 트랩 타워는 시야에 안 잡혀 목표가 되지 않는다.
var gnaws_towers: bool = false
var gnaw_rate: float = 1.0         # 초당 갉는 양 (타워 내구도 Balance.TOWER_DURABILITY 기준)
var _gnaw_cell: Vector2i = Pathfinder.NO_GOAL   # 지금 노리는 타워 칸 (없으면 NO_GOAL)
var _gnaw_retarget := 0.0
var _gnaw_skip: Dictionary = {}    # 곁으로 갈 길이 없어서 포기한 타워 칸
var _gnawing := false

# 유령 (Monsters.DATA의 ghost: true). 체력이 무한이고, 길이 막혔을 때만 breach_dps로 타워 내구도를 깎아 부순다
var ghost: bool = false
var breach_dps: float = 0.0

# 웨이브 변형 (보스 스킬이 웨이브 전체에 붙인다. BossSkills.AFFIXES)
var speed_boost: float = 1.0     # 이동속도 배율 (돌격)
var revive_ratio: float = 0.0    # 처음 죽을 때 이 비율의 체력으로 되살아난다 (부활). 0이면 없음
var _revived := false

# 보스 레인에서 쓰는 값 (내가 보낸 몬스터)
var dps: float = 0.0             # 기본 초당 피해
var ramp: float = 0.0            # 보스 앞에 선 뒤 초당 dps 증가량
var ramp_cap: float = 0.0
var aura_radius: float = 0.0     # 지원형: 주변 아군 dps 증가
var aura_bonus: float = 0.0
var time_at_boss: float = 0.0    # 보스 앞에 선 뒤 지난 시간
var current_dps: float = 0.0     # 성장/오라까지 반영한 실제 dps
var slot_key: String = ""        # 보스 주변에서 차지한 자리 (죽으면 비운다)
# 보스 스킬이 거는 상태 (BossController가 관리)
var chill_time: float = 0.0      # 동상: 이 라운드에서 보스 앞에 서 있던 시간
var chill: float = 0.0           # 동상: dps가 줄어든 비율 (0~1)
var dread_time: float = 0.0      # 공포: 남은 시간 동안 dps 0
var warn_color: Color = Color(0, 0, 0, 0)  # 예고 표식 (처단=빨강, 공포=보라). 알파 0이면 없음

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

# 클라이언트 껍데기 모드(puppet): 서버 스냅샷을 받아 그리기만 한다. 길찾기/전투/상태 시간은 흐르지 않는다 (#21).
var puppet: bool = false
var puppet_moving: bool = false  # 걷는 중인가 (서버의 "정지/갉기/경로 없음"이 아닌 상태)

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
var _empower_buffs: Array = []   # [{time_left: float, boost: float}] 강화 버프 (남은 시간 순 정렬, 중첩 가능)
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


## 데이터 딕셔너리(Monsters.DATA 항목)의 공통 외형 값을 적용한다
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
	_base_max_hp = max_hp  # 강화 전 기본 최대 체력 (강화는 max_hp를 이 값의 배수로 바꾼다)
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
## 강화(남색 보너스)는 최대 체력을 늘리는 방식이라 피해는 그대로 hp에서 깎는다 (_sync_empower_max_hp).
func _lose_hp(amount: float, damage_source, kill_source) -> void:
	if _dead:
		return
	if ghost:  # 체력이 무한이라 닳지도 죽지도 않는다. 받은 피해만 점수로 센다
		ghost_hit.emit(amount, damage_source if is_instance_valid(damage_source) else null)
		return
	var applied := minf(amount, maxf(hp, 0.0))  # 남은 체력을 넘는 초과분은 피해로 치지 않는다
	hp -= amount
	if is_instance_valid(damage_source):  # 투사체가 날아가는 사이 타워가 부서졌을 수 있다
		damage_source.record_damage(applied)
	if hp <= 0.0:
		if revive_ratio > 0.0 and not _revived:  # 처음 죽는 순간: 킬로 치지 않고 되살아난다
			_revive()
			return
		if is_instance_valid(kill_source):
			_killer = kill_source
			kill_source.record_kill()
		_die()


## 부활: 체력 일부로 되살아난다 (한 번뿐). 독은 그대로 이어지고, 이번 타격에 터진 표식은 이미 쓰였다.
func _revive() -> void:
	_revived = true
	hp = max_hp * revive_ratio
	_hit_flash = 0.25
	if events != null:
		events.ring(fx_lane_id, cell_pos, 0.8, Color(0.9, 0.9, 0.8))
		events.text(fx_lane_id, cell_pos, "부활!", Color(0.9, 0.9, 0.8))


func _die() -> void:
	_dead = true
	death_marks = _consumed_marks + marks  # 이번 타격에 터진 표식 + 남은 표식 (표식 전파용)
	died.emit(self)


## 처형: 남은 체력만큼의 피해로 즉사시킨다 (피해/킬은 source 몫)
func execute(source) -> void:
	if _dead or ghost:  # 유령은 처형되지 않는다
		return
	_lose_hp(maxf(hp, 0.0) + 0.001, source, source)


func is_dead() -> bool:
	return _dead


## 보스 스킬 예고 표식 (알파 0이면 없음). Tower도 같은 이름으로 받는다.
func set_warn(color: Color) -> void:
	warn_color = color


func clear_warn() -> void:
	warn_color = Color(0, 0, 0, 0)


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
	_empower_buffs.append({"time_left": duration, "boost": boost})
	# 먼저 끝나는 순으로 정렬
	_empower_buffs.sort_custom(func(a, b): return a.time_left < b.time_left)
	while _empower_buffs.size() > Balance.EMPOWER_MAX_STACKS:
		_empower_buffs.remove_at(0)  # 가장 먼저 끝나는 것을 밀어낸다
	_sync_empower_max_hp()


## 강화 총합에 맞춰 최대 체력을 다시 계산한다. 체력 비율은 유지한다 (100/100 → 105/105, 52.5/105 → 50/100).
## 강화가 걸리거나 끝나거나 밀려날 때마다 불린다.
func _sync_empower_max_hp() -> void:
	var new_max := _base_max_hp * (1.0 + get_total_empower())
	if is_equal_approx(new_max, max_hp):
		return
	if hp > 0.0 and max_hp > 0.0:
		hp = maxf(hp / max_hp * new_max, 0.001)  # 비율이 유지되므로 0이 되진 않지만, 강화가 끝나도 죽지 않게 하한을 둔다
	max_hp = new_max


## 강화 버프의 남은 시간을 줄인다. 시뮬레이션이 넘겨주는 delta로만 흐르므로 일시정지/서버 시간과 항상 맞는다 (벽시계를 쓰지 않는다).
func _tick_empower(delta: float) -> void:
	for b in _empower_buffs:
		b.time_left -= delta


## 현재 적용 중인 강화 효과 총합 (만료된 버프는 제거)
func get_total_empower() -> float:
	var total := 0.0
	# 만료된 버프 제거 (역순으로)
	for i in range(_empower_buffs.size() - 1, -1, -1):
		if _empower_buffs[i].time_left < 0.0:
			_empower_buffs.remove_at(i)
		else:
			total += _empower_buffs[i].boost
	return total


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

	# 노리는 타워가 있으면 그 곁으로 간다 (길이 없으면 목표를 버리고 원래 목적지로)
	if _gnaw_cell != Pathfinder.NO_GOAL and _route_to_gnaw_target():
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
	if puppet:
		_update_position()
		return
	if preview:
		return

	_tick_empower(delta)
	if not _empower_buffs.is_empty() or not is_equal_approx(max_hp, _base_max_hp):
		_sync_empower_max_hp()  # 만료된 강화를 바로 반영 (끝난 시점에 체력 비율대로 되돌린다)
	if regen > 0.0 and hp < max_hp and not _dead:
		hp = minf(max_hp, hp + max_hp * regen * delta)

	_update_status(delta)
	if _dead:
		return
	if ghost:
		_gnawing = false  # 타워를 뚫는 중인지는 아래에서 매 프레임 다시 정한다 (기절하거나 타워가 사라지면 풀린다)
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
	if gnaws_towers and not flying and _process_gnaw(delta):
		return  # 타워를 갉는 중이라 제자리에 서 있다
	if waypoints.is_empty():
		_check_arrival()
		return

	var target := waypoints[0]
	var target_cell := Vector2i(target.floor())

	# 다음 목적지가 타워 칸이면 가까워졌을 때 공격 (일반형: 공격력 무한대 -> 즉시 파괴, 환급 0원)
	if not flying and _grid.get_cell_state(target_cell) == GridSystem.CellState.TOWER \
			and cell_pos.distance_to(target) <= TOWER_ATTACK_DISTANCE:
		if ghost:
			# 유령: 길이 막혀서 뚫어야 할 때만 멈춰서 내구도를 깎는다 (타워가 부서지면 LaneController가 칸을 비우고 길을 다시 짠다).
			# 길이 열려 있으면(breaching이 아니면) 타워를 건드리지 않고 그냥 지나간다.
			if breaching:
				facing = (target - cell_pos).normalized()
				_gnawing = true
				gnawed.emit(target_cell, breach_dps * delta)
				return
		else:
			Log.info(Log.Category.TOWER, "[%s] 몬스터#%d가 타워 파괴 %s" % [_grid.lane_tag(), monster_id, target_cell])
			_grid.set_cell_state(target_cell, GridSystem.CellState.EMPTY)  # 경로 재계산은 신호로 처리됨
			return

	var to_target := target - cell_pos
	var step := speed * speed_mult() * speed_boost * delta
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


## 타워를 갉아 먹는 몬스터의 행동. 이번 프레임에 제자리에서 갉았으면 true (이동하지 않는다).
## 시야 안(GNAW_SEEK_RANGE)에서 가장 가까운 벽 타워를 목표로 삼아 곁으로 가고, 가까워지면 멈춰서 갉는다.
## 기절하면 _process가 먼저 멈추므로 갉지 못한다.
func _process_gnaw(delta: float) -> bool:
	_gnawing = false
	if _gnaw_cell != Pathfinder.NO_GOAL:
		if _grid.get_cell_state(_gnaw_cell) != GridSystem.CellState.TOWER:
			_gnaw_cell = Pathfinder.NO_GOAL  # 목표 타워가 사라졌다 (다른 새끼가 부숨)
			_repath()                        # 원래 목적지로 다시 간다
			return false
		var tower_center := Vector2(_gnaw_cell) + Vector2(0.5, 0.5)
		if cell_pos.distance_to(tower_center) <= GNAW_DISTANCE:
			facing = (tower_center - cell_pos).normalized()
			_gnawing = true
			gnawed.emit(_gnaw_cell, gnaw_rate * delta)
			return true
		return false  # 아직 그 곁으로 가는 중

	_gnaw_retarget -= delta
	if _gnaw_retarget > 0.0:
		return false
	_gnaw_retarget = 0.3
	var found := _nearest_gnaw_target()
	if found != Pathfinder.NO_GOAL:
		_gnaw_cell = found
		_repath()  # 목표가 생겼으니 그 곁으로 가는 길을 짠다 (길이 없으면 목표를 버린다)
	return false


## 본 적 있는 타워(벽 타워만) 중 GNAW_SEEK_RANGE 안에서 가장 가까운 것
func _nearest_gnaw_target() -> Vector2i:
	var best := Pathfinder.NO_GOAL
	var best_d := GNAW_SEEK_RANGE
	for c in known_towers:
		if _gnaw_skip.has(c):
			continue
		var d := cell_pos.distance_to(Vector2(c) + Vector2(0.5, 0.5))
		if d <= best_d:
			best_d = d
			best = c
	return best


## 노리는 타워의 빈 곁 칸까지 가는 길을 짠다. 곁으로 갈 길이 없으면 그 타워를 포기하고 false.
func _route_to_gnaw_target() -> bool:
	var goal := Pathfinder.NO_GOAL
	var best_d := INF
	for off in [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]:
		var n: Vector2i = _gnaw_cell + off
		var state := _grid.get_cell_state(n)  # 격자 밖은 OBSTACLE
		if state == GridSystem.CellState.TOWER or state == GridSystem.CellState.OBSTACLE:
			continue
		var d := cell_pos.distance_to(Vector2(n) + Vector2(0.5, 0.5))
		if d < best_d:
			best_d = d
			goal = n
	if goal != Pathfinder.NO_GOAL:
		var result := _pathfinder.find_route(cell_pos, goal)  # known을 안 주면 타워를 전부 아는 길찾기
		if result.ok:
			waypoints.assign(result.waypoints)
			if waypoints.is_empty():  # 이미 그 칸 안이면 칸 중심까지만 간다
				waypoints.append(Vector2(goal) + Vector2(0.5, 0.5))
			breaching = false
			return true
	_gnaw_skip[_gnaw_cell] = true
	_gnaw_cell = Pathfinder.NO_GOAL
	return false


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


## 그릴 때 필요한 값들 (스냅샷에 실려 클라이언트 껍데기로 간다)
func view_state() -> Dictionary:
	return {
		"id": monster_id, "kind": kind_id, "owner": owner_id, "pos": [snappedf(cell_pos.x, 0.001), snappedf(cell_pos.y, 0.001)],
		"hp": hp, "max_hp": max_hp, "flying": flying, "ghost": ghost,
		"shape": shape, "color": body_color.to_html(false), "size": size_scale, "speed": speed,
		"facing": [facing.x, facing.y], "attack_dir": [attack_dir.x, attack_dir.y],
		"stopped": stopped, "gnawing": _gnawing, "moving": not stopped and not _gnawing and not waypoints.is_empty(),
		"breaching": breaching, "hit": _hit_flash > 0.0, "aura": aura_radius, "time_at_boss": time_at_boss,
		"poison": not _poisons.is_empty(), "slow": slow_time > 0.0, "stun": stun_time > 0.0 or captured_time > 0.0,
		"armor_break": armor_break_time > 0.0, "boost": speed_boost > 1.0, "revive": revive_ratio > 0.0 and not _revived,
		"chill": chill, "dread": dread_time > 0.0, "warn": warn_color.to_html(true) if warn_color.a > 0.0 else "",
		"marks": marks.size(),
	}


## 스냅샷의 몬스터 항목을 받아 모습을 맞춘다. 껍데기(puppet)용.
func apply_view(v: Dictionary) -> void:
	monster_id = v.id
	kind_id = v.kind
	shape = v.shape
	body_color = Color.html(v.color)
	size_scale = v.size
	speed = v.speed
	cell_pos = Vector2(v.pos[0], v.pos[1])
	facing = Vector2(v.facing[0], v.facing[1])
	attack_dir = Vector2(v.attack_dir[0], v.attack_dir[1])
	hp = v.hp
	max_hp = v.max_hp
	flying = v.flying
	ghost = v.ghost
	stopped = v.stopped
	_gnawing = v.gnawing
	puppet_moving = v.moving
	breaching = v.breaching
	_hit_flash = 0.1 if v.hit else 0.0
	aura_radius = v.aura
	time_at_boss = v.time_at_boss
	_poisons = [{}] if v.poison else []
	slow_time = 1.0 if v.slow else 0.0
	stun_time = 1.0 if v.stun else 0.0
	armor_break_time = 1.0 if v.armor_break else 0.0
	speed_boost = 1.5 if v.boost else 1.0
	revive_ratio = 1.0 if v.revive else 0.0
	_revived = not v.revive
	chill = v.chill
	dread_time = 1.0 if v.dread else 0.0
	warn_color = Color.html(v.warn) if v.warn != "" else Color(0, 0, 0, 0)
	marks.resize(int(v.marks))


## 껍데기로 쓴다: 시뮬레이션 없이 그리기만 한다 (setup()은 길찾기까지 하므로 부르지 않는다)
func setup_puppet(renderer: GridRenderer) -> void:
	puppet = true
	_renderer = renderer


func _cell_px() -> float:
	return preview_cell if _renderer == null else float(_renderer.CELL_SIZE)


func _update_position() -> void:
	position = cell_pos * _cell_px()


func _draw() -> void:
	var cell := _cell_px()
	var r: float = cell * 0.32 * size_scale
	var moving := preview or (puppet_moving if puppet else (not stopped and not _gnawing and not waypoints.is_empty()))

	# 걷는 동안 통통 튀고, 멈추면 숨쉬듯 흔들림. 보스 앞에서는 보스 쪽으로 달려들었다 물러남. 타워를 갉을 때도 타워 쪽으로 달려든다.
	var bob := absf(sin(_anim * speed * 3.0)) * cell * 0.09 if moving else sin(_anim * 3.0) * cell * 0.015
	var lunge := Vector2.ZERO
	if stopped:
		lunge = attack_dir * maxf(0.0, sin(_anim * 9.0)) * cell * 0.14
	elif _gnawing:
		lunge = facing * maxf(0.0, sin(_anim * 9.0)) * cell * 0.14
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

	if ghost:
		# 유령은 보스 레인의 큰 유령과 똑같은 그림이다 (GhostArt). 길을 뚫는 중이면 노랗게, 맞으면 붉게 물든다
		var ghost_body := GhostArt.BODY
		if breaching:
			ghost_body = Color(1.0, 0.92, 0.55)
		if _hit_flash > 0.0:
			ghost_body = Color(1.0, 0.8, 0.8)
		GhostArt.draw_ghost(self, c, r, _anim, facing, ghost_body)
	else:
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
		# 웨이브 변형 표시: 돌격=주황 고리, 부활(아직 안 되살아남)=뼈색 고리
		if speed_boost > 1.0:
			draw_arc(c, rr + 9.0, 0.0, TAU, 20, Color(1.0, 0.6, 0.2, 0.9), 2.0)
		if revive_ratio > 0.0 and not _revived:
			draw_arc(c, rr + 9.0, 0.0, TAU, 20, Color(0.9, 0.9, 0.8, 0.9), 2.0)
		# 보스 스킬 표시: 동상=얼음색 고리(짙을수록 많이 얼음), 공포=보라 굵은 고리, 예고 표식=깜빡이는 고리
		if chill > 0.05:
			draw_arc(c, rr + 12.0, 0.0, TAU, 20, Color(0.6, 0.85, 1.0, 0.35 + 0.55 * chill), 2.0)
		if dread_time > 0.0:
			draw_arc(c, rr + 15.0, 0.0, TAU, 20, Color(0.75, 0.35, 0.95, 0.95), 3.5)
		if warn_color.a > 0.0:
			var pulse := 0.55 + 0.45 * sin(_anim * 12.0)
			draw_arc(c, rr + 15.0, 0.0, TAU, 24, Color(warn_color, pulse), 3.5)
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
