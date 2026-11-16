extends Node
class_name BossController
## 보스 레인 담당 (협력 모드).
## - 보스는 총 BossLevels.COUNT(10) 라운드. 한 라운드를 깨면 보상 골드를 주고 다음 보스가 바로 나온다.
## - 보스는 레인 한가운데에 크게 서 있고, 내가 보낸 몬스터들이 걸어와서 보스를 둘러싸고 공격한다.
##   보스 앞에 선 몬스터는 사라지지 않고 다음 라운드 보스도 계속 공격한다 (수 제한 없음).
## - 수입이 들어오는 시점(INCOME_INTERVAL)마다 모든 참여 플레이어 레인에 몬스터 웨이브가 한꺼번에 온다 (PvE).
##   한 웨이브는 종류가 다른 몬스터 묶음 WAVE_GROUPS개이고, 다음 웨이브에 뭐가 오는지는 미리 정해져서 HUD에 보인다.
##   종류마다 이기는 타워가 달라서 그때그때 필요한 타워가 달라진다 (WaveTypes 상성 참고).
## - 제한시간 안에 못 잡으면 패배. 보스는 플레이어 몬스터를 공격하지 않는다 (현재 미정).
## TODO: 보스 스킬, 플레이어별 기여도 UI

signal level_started(level: int)
signal level_cleared(level: int)
signal boss_defeated        # 마지막 라운드까지 모두 처치
signal boss_failed(reason: String)

enum State { WAITING, RUNNING, VICTORY, DEFEAT }  # WAITING: 시작 버튼을 누르기 전 (시간도 몬스터 파견도 멈춰 있음)

const SLOT_RING_GAP := 0.65   # 겹겹이 둘러쌀 때 바깥 고리 간격 (칸)
const SLOT_SPACING := 0.85    # 같은 고리에서 몬스터 간 간격 (칸)
const DPS_RECALC_INTERVAL := 0.25
const AURA_BONUS_CAP := 1.5   # 지원형 오라는 아무리 겹쳐도 최대 +150%

var state: State = State.WAITING
var level: int = 1
var level_data: Dictionary = {}
var max_hp: float
var hp: float
var time_left: float
var total_dps: float = 0.0
var damage_by_player: Dictionary = {}  # player_id -> 누적 피해
var current_wave_text: String = "-"    # HUD 표시용: 지금 파견 중인 몬스터
var level_flash: float = 0.0           # 새 보스 등장 연출

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _lanes: Dictionary
var _dispatch_timer: Timer
var _attackers: Array[Monster] = []
var _sent_monsters: Array[Monster] = []
var _slots_taken: Dictionary = {}  # "고리:번호" -> true
var _next_monster_id := 1
var _view: BossView
var _bar: BossBar
var _lane_visible := false
var _dmg_accum := 0.0
var _dmg_timer := 0.0
var _dps_timer := 0.0
var _next_types: Array[String] = []   # 다음 웨이브에 오는 몬스터 묶음 종류 (미리 정해 둔다)


func setup(boss_grid: GridSystem, renderer: GridRenderer, lanes: Dictionary) -> void:
	_grid = boss_grid
	_renderer = renderer
	_lanes = lanes
	_pathfinder = Pathfinder.new(_grid)
	_mark_boss_body()

	_view = BossView.new()
	_view.boss = self
	_view.renderer = renderer
	_view.visible = _lane_visible
	_view.z_index = 0
	renderer.add_child(_view)

	_bar = BossBar.new()
	_bar.boss = self
	_bar.renderer = renderer
	_bar.visible = _lane_visible
	_bar.z_index = 5
	renderer.add_child(_bar)

	_dispatch_timer = Timer.new()
	_dispatch_timer.wait_time = Balance.INCOME_INTERVAL  # 수입 지급과 같은 주기: 수입이 들어올 때 웨이브도 온다
	_dispatch_timer.timeout.connect(_dispatch_wave)
	add_child(_dispatch_timer)

	for lane in lanes.values():
		lane.lane_failed.connect(_on_lane_failed)

	_start_level(1)
	_plan_next_wave()


## 시작 버튼: 보스 제한시간과 몬스터 파견이 동시에 시작된다
func begin() -> void:
	if state != State.WAITING:
		return
	state = State.RUNNING
	level_flash = 1.0
	_dispatch_timer.start()  # 레인의 수입 타이머와 같은 순간에 돌기 시작해서 첫 수입과 첫 웨이브가 함께 온다
	Log.info(Log.Category.GAME, "게임 시작: 보스 Lv.%d '%s'" % [level, level_data.name])


## 보스 몸통 자리를 통과 불가 칸으로 만들어서 몬스터가 보스를 뚫고 가지 못하게 한다
func _mark_boss_body() -> void:
	var radius := Balance.BOSS_RADIUS + 0.25
	for y in range(GridSystem.GRID_HEIGHT):
		for x in range(GridSystem.GRID_WIDTH):
			var center := Vector2(x, y) + Vector2(0.5, 0.5)
			if center.distance_to(Balance.BOSS_CENTER) <= radius:
				_grid.set_cell_state(Vector2i(x, y), GridSystem.CellState.OBSTACLE)


func _start_level(new_level: int) -> void:
	level = new_level
	level_data = BossLevels.get_level(level)
	var players_scale := 1.0 + Balance.BOSS_HP_PER_EXTRA_PLAYER * (_lanes.size() - 1)  # 인원수에 따른 난이도
	max_hp = float(level_data.hp) * players_scale
	hp = max_hp
	time_left = level_data.time
	level_flash = 1.0
	current_wave_text = "-"

	Log.info(Log.Category.GAME, "보스 Lv.%d/%d '%s' 등장: hp=%.0f (참여 %d명), 제한시간=%.0fs, 압박 기준 %.1f, 몬스터 체력x%.1f 마릿수x%.1f" % [
		level, BossLevels.COUNT, level_data.name, max_hp, _lanes.size(), time_left, level_data.interval,
		level_data.wave_hp, level_data.count_mult])
	Effects.float_text(_renderer, Balance.BOSS_CENTER + Vector2(-1.2, 0.3), "BOSS Lv.%d  %s" % [level, level_data.name],
		Color(1.0, 0.85, 0.3), _lane_visible)
	level_started.emit(level)


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return

	level_flash = maxf(0.0, level_flash - delta * 1.2)

	# 성장형 몬스터는 보스 앞에 서 있는 시간이 길어질수록 강해진다
	for m in _attackers:
		m.time_at_boss += delta
	_dps_timer -= delta
	if _dps_timer <= 0.0:
		_dps_timer = DPS_RECALC_INTERVAL
		_recalc_dps()

	# 도착한 몬스터들이 보스를 지속 공격
	if total_dps > 0.0:
		var dealt := total_dps * delta
		hp -= dealt
		_dmg_accum += dealt
		for m in _attackers:
			damage_by_player[m.owner_id] = damage_by_player.get(m.owner_id, 0.0) + m.current_dps * delta

		_dmg_timer += delta
		if _dmg_timer >= 1.0:
			_show_damage_text()

	time_left -= delta
	_view.queue_redraw()

	if hp <= 0.0:
		hp = 0.0
		_on_level_cleared()
	elif time_left <= 0.0:
		time_left = 0.0
		_finish(State.DEFEAT, "제한시간 초과 (Lv.%d)" % level)


## 보스 앞에 선 몬스터들의 실제 초당 피해 합계 (성장 + 지원형 오라 반영)
func _recalc_dps() -> void:
	var supporters: Array[Monster] = []
	for m in _attackers:
		if m.aura_bonus > 0.0:
			supporters.append(m)

	var total := 0.0
	for m in _attackers:
		# 강화 효과 반영된 기본 DPS + 성장형 램프
		var base := m.get_boosted_dps() + minf(m.ramp * m.time_at_boss, m.ramp_cap)
		var bonus := 0.0
		for s in supporters:
			if s != m and s.cell_pos.distance_to(m.cell_pos) <= s.aura_radius:
				bonus += s.aura_bonus
		m.current_dps = base * (1.0 + minf(bonus, AURA_BONUS_CAP))
		total += m.current_dps
	total_dps = total


func _show_damage_text() -> void:
	# 체력바(보스 머리 위)와 겹치지 않도록 몸통 위에서 떠오르게 한다
	var at := Balance.BOSS_CENTER + Vector2(randf_range(-1.3, 1.0), randf_range(0.0, 0.9))
	Effects.float_text(_renderer, at, "-%d" % int(_dmg_accum), Color(1.0, 0.9, 0.45), _lane_visible)
	_dmg_accum = 0.0
	_dmg_timer = 0.0


func _on_level_cleared() -> void:
	Log.info(Log.Category.GAME, "보스 Lv.%d '%s' 처치! (남은시간 %.0fs)" % [level, level_data.name, time_left])
	level_cleared.emit(level)

	if level >= BossLevels.COUNT:
		_finish(State.VICTORY, "모든 보스 처치")
		return

	# 보상 지급 -> 다음 보스 즉시 등장 (보스 앞에 선 몬스터는 그대로 남아 다음 보스를 공격)
	var reward: int = level_data.reward
	for lane in _lanes.values():
		if lane.active:
			lane.gold += reward
			Log.info(Log.Category.ECONOMY, "[P%d] 보스 처치 보상 +%d골드 잔액=%d" % [lane.player_id + 1, reward, lane.gold])
	Effects.float_text(_renderer, Balance.BOSS_CENTER + Vector2(-1.0, -0.8), "처치! +%d골드" % reward,
		Color(1.0, 0.9, 0.3), _lane_visible)
	_start_level(level + 1)


## 다음 웨이브의 몬스터 묶음 종류를 미리 정한다 (HUD 미리보기용). 종류는 라운드에 맞게 가중치로 뽑는다.
func _plan_next_wave() -> void:
	_next_types.clear()
	for i in range(Balance.WAVE_GROUPS):
		_next_types.append(WaveTypes.pick(level))


## 묶음 하나의 마릿수. 라운드가 오를수록(파견 압박 interval이 짧아질수록, count_mult가 클수록) 늘어난다.
func _group_count(type_id: String) -> int:
	var wave_type: Dictionary = WaveTypes.TYPES[type_id]
	var scale := Balance.INCOME_INTERVAL / float(level_data.interval) / float(Balance.WAVE_GROUPS)
	return maxi(1, roundi(float(wave_type.count) * float(level_data.count_mult) * scale))


## HUD용: 다음 웨이브에 뭐가 몇 마리 오는지. 같은 종류는 합친다. [{type, name, count, flying, color}]
func get_next_wave_preview() -> Array:
	var order: Array[String] = []
	var counts := {}
	for t in _next_types:
		if not counts.has(t):
			order.append(t)
			counts[t] = 0
		counts[t] += _group_count(t)
	var preview: Array = []
	for t in order:
		var wt: Dictionary = WaveTypes.TYPES[t]
		preview.append({"type": t, "name": wt.name, "count": counts[t], "flying": wt.flying, "color": wt.color})
	return preview


## 다음 웨이브까지 남은 시간(초). 시작 전이거나 끝났으면 -1.
func time_to_next_wave() -> float:
	if state != State.RUNNING or _dispatch_timer.is_stopped():
		return -1.0
	return _dispatch_timer.time_left


## 모든 참여 레인에 웨이브를 보낸다 (수입 시점마다).
## 웨이브 = 종류가 다른 묶음 WAVE_GROUPS개. 묶음은 한 칸에서 촘촘히 연달아 나와서 한 덩어리로 온다.
## 체력은 라운드/보스 체력에 따라 커진다.
func _dispatch_wave() -> void:
	if state != State.RUNNING:
		return
	var types := _next_types.duplicate()
	var preview := get_next_wave_preview()
	_plan_next_wave()  # 그다음 웨이브를 미리 정해 둔다
	var parts: Array[String] = []
	for e in preview:
		parts.append("%s x%d%s" % [e.name, e.count, "(공중)" if e.flying else ""])
	current_wave_text = ", ".join(parts)
	Log.debug(Log.Category.GAME, "보스 파견: %s (Lv.%d)" % [current_wave_text, level])

	var dispatch_level := level
	var ratio := hp / max_hp
	# 레인마다 이번 웨이브가 나오는 칸을 하나 정해서 한 덩어리로 내보낸다
	var spawn_cells := {}
	for lane in _lanes.values():
		spawn_cells[lane] = lane.pick_spawn_cell()
	var first := true
	for type_id in types:
		var wave_type: Dictionary = WaveTypes.TYPES[type_id]
		var count := _group_count(type_id)
		var hp_value: float = Balance.WAVE_MONSTER_HP * float(wave_type.hp) * float(level_data.wave_hp) \
			* (1.0 + Balance.WAVE_HP_BONUS_AT_LOW_BOSS * (1.0 - ratio))
		for i in range(count):
			if not first:
				var gap := Balance.WAVE_SPAWN_GAP if i > 0 else Balance.WAVE_GROUP_GAP
				await get_tree().create_timer(gap).timeout  # 촘촘하게 연달아 나온다 (묶음 사이는 조금 더 띄운다)
				if state != State.RUNNING:
					return
			first = false
			for lane in _lanes.values():
				lane.spawn_wave_monster(hp_value, type_id, dispatch_level, spawn_cells[lane])


## 플레이어가 생산한 몬스터를 보스 레인으로 보낸다
func spawn_player_monster(owner_id: int, kind_id: String) -> void:
	var data: Dictionary = SentMonsters.DATA[kind_id]
	var spawn_cells := _grid.get_spawn_cells()
	if spawn_cells.is_empty():
		Log.error(Log.Category.GAME, "보스 레인 스폰 셀이 없음")
		return

	var spawn_cell: Vector2i = spawn_cells.pick_random()
	var spawn_pos := Vector2(spawn_cell) + Vector2(0.5, 0.5)
	var slot := _allocate_slot(spawn_pos)

	var monster := Monster.new()
	monster.apply_look(data)
	monster.owner_id = owner_id
	monster.kind_id = kind_id
	monster.dps = float(data.dps)
	monster.ramp = float(data.get("ramp", 0.0))
	monster.ramp_cap = float(data.get("ramp_cap", 0.0))
	monster.aura_radius = float(data.get("aura_radius", 0.0))
	monster.aura_bonus = float(data.get("aura_bonus", 0.0))
	monster.goal_cell = _walkable_cell_near(slot)
	monster.final_point = slot
	monster.visible = _lane_visible
	monster.z_index = 2
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cell)
	monster.reached_exit.connect(_on_monster_arrived)
	_renderer.add_child(monster)
	_sent_monsters.append(monster)
	Log.info(Log.Category.GAME, "[P%d] %s 파견 (보스 레인 몬스터#%d, 목표 자리 %s)" % [
		owner_id + 1, data.name, _next_monster_id, slot.snapped(Vector2(0.01, 0.01))])
	_next_monster_id += 1


## 보스 주변 빈 자리를 하나 예약한다. 안쪽 고리부터 채우고, 가득 차면 바깥 고리로 넓어진다.
## 같은 고리 안에서는 몬스터가 오는 방향과 가장 가까운 자리를 고른다.
func _allocate_slot(approach_from: Vector2) -> Vector2:
	var approach_angle := (approach_from - Balance.BOSS_CENTER).angle()
	var first_radius := Balance.BOSS_RADIUS + 0.55

	for ring_idx in range(40):
		var r := first_radius + ring_idx * SLOT_RING_GAP
		var count := maxi(8, int(TAU * r / SLOT_SPACING))
		var best_j := -1
		var best_diff := INF
		var best_pos := Vector2.ZERO
		for j in range(count):
			if _slots_taken.has("%d:%d" % [ring_idx, j]):
				continue
			var a := j * TAU / count + ring_idx * 0.4
			var p := Balance.BOSS_CENTER + Vector2.from_angle(a) * r
			if not _slot_in_bounds(p):
				continue
			var diff := absf(angle_difference(a, approach_angle))
			if diff < best_diff:
				best_diff = diff
				best_j = j
				best_pos = p
		if best_j >= 0:
			_slots_taken["%d:%d" % [ring_idx, best_j]] = true
			return best_pos

	# 극단적으로 많을 때의 안전장치
	return Balance.BOSS_CENTER + Vector2(0, first_radius)


func _slot_in_bounds(p: Vector2) -> bool:
	return p.x >= 0.5 and p.x <= GridSystem.GRID_WIDTH - 0.5 \
		and p.y >= 0.5 and p.y <= GridSystem.GRID_HEIGHT - 1.5


## 자리 근처에서 걸어갈 수 있는 가장 가까운 칸 (길찾기 목표용)
func _walkable_cell_near(p: Vector2) -> Vector2i:
	var base := Vector2i(p.floor())
	var best := base
	var best_d := INF
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var c := base + Vector2i(dx, dy)
			if not _grid.is_valid_position(c):
				continue
			var state_c := _grid.get_cell_state(c)
			if state_c == GridSystem.CellState.OBSTACLE or state_c == GridSystem.CellState.TOWER:
				continue
			var d := (Vector2(c) + Vector2(0.5, 0.5)).distance_to(p)
			if d < best_d:
				best_d = d
				best = c
	return best


func _on_monster_arrived(monster: Monster) -> void:
	monster.stop(Balance.BOSS_CENTER)
	_attackers.append(monster)
	_recalc_dps()
	Log.info(Log.Category.GAME, "보스 레인: 몬스터#%d(P%d, %s) 도착 -> 보스 공격 시작. 총 DPS=%.1f (공격 중 %d마리)" % [
		monster.monster_id, monster.owner_id + 1, monster.kind_id, total_dps, _attackers.size()])


func _on_lane_failed(player_id: int) -> void:
	# 모든 참여 플레이어가 패배하면 전체 패배
	for lane in _lanes.values():
		if lane.active:
			return
	_finish(State.DEFEAT, "모든 플레이어 레인 붕괴 (마지막: P%d)" % (player_id + 1))


func _finish(result: State, reason: String) -> void:
	if state != State.RUNNING:
		return
	state = result
	_dispatch_timer.stop()
	for lane in _lanes.values():
		lane.shutdown()
	for m in _sent_monsters:
		m.set_process(false)

	if result == State.VICTORY:
		Log.info(Log.Category.GAME, "승리! %s 기여도=%s" % [reason, damage_by_player])
		boss_defeated.emit()
	else:
		Log.warn(Log.Category.GAME, "패배: %s (보스 Lv.%d 남은 hp=%.0f/%.0f)" % [reason, level, hp, max_hp])
		boss_failed.emit(reason)


func get_sent_monsters() -> Array[Monster]:
	return _sent_monsters


## 보스 앞에 도착해서 공격 중인 몬스터들
func get_attackers() -> Array[Monster]:
	return _attackers


func get_attacker_count() -> int:
	return _attackers.size()


func set_lane_visible(is_shown: bool) -> void:
	_lane_visible = is_shown
	if _view:
		_view.visible = is_shown
	if _bar:
		_bar.visible = is_shown
	for m in _sent_monsters:
		m.visible = is_shown


## 보스 레인 한가운데의 커다란 보스. 라운드마다 색이 다르다.
class BossView extends Node2D:
	var boss: BossController
	var renderer: GridRenderer
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		if boss.level_data.is_empty():
			return
		var cell: float = renderer.CELL_SIZE
		var R: float = Balance.BOSS_RADIUS * cell
		var pressure := minf(1.0, boss.total_dps / 12.0)  # 공격받을수록 몸을 떤다
		var shake := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * cell * 0.04 * pressure
		var breathe := 1.0 + 0.03 * sin(_t * 2.0)
		var c: Vector2 = Balance.BOSS_CENTER * cell + shake
		var body: Color = boss.level_data.color

		# 바닥 그림자 + 기운
		draw_set_transform(c + Vector2(0, R * 0.95), 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, R * 1.1, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(c, R * 1.25 * breathe, Color(body.lightened(0.2), 0.10 + 0.08 * sin(_t * 3.0)))

		# 뿔
		for side in [-1.0, 1.0]:
			draw_colored_polygon(PackedVector2Array([
				c + Vector2(side * R * 0.45, -R * 0.75),
				c + Vector2(side * R * 0.95, -R * 1.45),
				c + Vector2(side * R * 0.85, -R * 0.55),
			]), Color(0.85, 0.8, 0.65))

		# 몸통
		draw_circle(c, R * breathe, body)
		draw_arc(c, R * breathe, 0.0, TAU, 40, body.darkened(0.5), 4.0)
		draw_circle(c + Vector2(0, R * 0.25), R * 0.7 * breathe, body.lightened(0.15))  # 배

		# 화난 눈 + 눈썹
		for side in [-1.0, 1.0]:
			var e := c + Vector2(side * R * 0.42, -R * 0.22)
			draw_circle(e, R * 0.2, Color(1.0, 0.95, 0.6))
			draw_circle(e + Vector2(0, R * 0.04), R * 0.09, Color(0.1, 0.0, 0.0))
			draw_line(e + Vector2(-side * R * 0.25, -R * 0.2), e + Vector2(side * R * 0.2, -R * 0.33), Color(0.1, 0.0, 0.0), 5.0)

		# 입 + 이빨
		var mouth := c + Vector2(0, R * 0.38)
		draw_arc(mouth, R * 0.42, 0.15, PI - 0.15, 20, Color(0.08, 0.0, 0.02), 6.0)
		for i in range(5):
			var tx := lerpf(-R * 0.34, R * 0.34, i / 4.0)
			draw_colored_polygon(PackedVector2Array([
				mouth + Vector2(tx - R * 0.05, R * 0.2),
				mouth + Vector2(tx + R * 0.05, R * 0.2),
				mouth + Vector2(tx, R * 0.33),
			]), Color(0.95, 0.95, 0.9))

		# 새 보스 등장 연출: 하얗게 번쩍임
		if boss.level_flash > 0.0:
			draw_circle(c, R * 1.3, Color(1, 1, 1, 0.6 * boss.level_flash))


## 보스 체력바 + 이름. 몬스터들이 보스 위쪽에 몰려 서도 가려지지 않게 몬스터(z_index 2)보다 위에 그린다.
class BossBar extends Node2D:
	var boss: BossController
	var renderer: GridRenderer

	func _process(_delta: float) -> void:
		queue_redraw()

	func _draw() -> void:
		if boss.level_data.is_empty():
			return
		var cell: float = renderer.CELL_SIZE
		var R: float = Balance.BOSS_RADIUS * cell
		var c: Vector2 = Balance.BOSS_CENTER * cell
		var bar_w := R * 2.2
		var bar_y := c.y - R * 1.7
		var ratio := clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		draw_rect(Rect2(c.x - bar_w * 0.5 - 3, bar_y - 20, bar_w + 6, 36), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w, 10), Color(0.25, 0.05, 0.05))
		draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w * ratio, 10), Color(0.9, 0.15, 0.15))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(c.x - bar_w * 0.5, bar_y - 6), "Lv.%d %s   %d / %d" % [
			boss.level, boss.level_data.name, int(boss.hp), int(boss.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)
