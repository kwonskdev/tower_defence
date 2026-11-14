extends Node
class_name BossController
## 보스 레인 담당 (협력 모드).
## - 보스는 레인 한가운데에 크게 서 있고, 몬스터들이 걸어와서 보스를 둘러싸고 공격한다.
## - 보스 체력/제한시간
## - 일정 시간마다 모든 참여 플레이어 레인에 몬스터 자동 파견 (보스 체력이 낮을수록 강해짐)
## - 플레이어가 보낸 몬스터는 보스 주변 "자리"로 걸어가 보스를 지속 공격한다 (사라지지 않음, 수 제한 없음)
## - 보스는 플레이어 몬스터를 공격하지 않는다 (현재 미정)
## TODO: 보스 스킬, 레벨 2 이후 보스, 보상, 플레이어별 기여도 UI

signal boss_defeated
signal boss_failed(reason: String)

enum State { RUNNING, VICTORY, DEFEAT }

const SLOT_RING_GAP := 0.65   # 겹겹이 둘러쌀 때 바깥 고리 간격 (칸)
const SLOT_SPACING := 0.85    # 같은 고리에서 몬스터 간 간격 (칸)

var state: State = State.RUNNING
var max_hp: float
var hp: float
var time_left: float = Balance.BOSS_TIME_LIMIT
var total_dps: float = 0.0
var damage_by_player: Dictionary = {}  # player_id -> 누적 피해

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
var _lane_visible := false
var _dmg_accum := 0.0
var _dmg_timer := 0.0


func setup(boss_grid: GridSystem, renderer: GridRenderer, lanes: Dictionary) -> void:
	_grid = boss_grid
	_renderer = renderer
	_lanes = lanes
	_pathfinder = Pathfinder.new(_grid)
	_mark_boss_body()

	max_hp = Balance.BOSS_BASE_HP + Balance.BOSS_HP_PER_EXTRA_PLAYER * (lanes.size() - 1)  # 인원수에 따른 난이도
	hp = max_hp

	_view = BossView.new()
	_view.boss = self
	_view.renderer = renderer
	_view.visible = _lane_visible
	_view.z_index = 0
	renderer.add_child(_view)

	_dispatch_timer = Timer.new()
	_dispatch_timer.wait_time = Balance.DISPATCH_INTERVAL
	_dispatch_timer.timeout.connect(_dispatch_wave)
	add_child(_dispatch_timer)
	_dispatch_timer.start()

	for lane in lanes.values():
		lane.lane_failed.connect(_on_lane_failed)

	Log.info(Log.Category.GAME, "보스 등장: hp=%.0f (참여 %d명), 제한시간=%.0fs, 파견 주기=%.1fs" % [
		max_hp, lanes.size(), time_left, Balance.DISPATCH_INTERVAL])


## 보스 몸통 자리를 통과 불가 칸으로 만들어서 몬스터가 보스를 뚫고 가지 못하게 한다
func _mark_boss_body() -> void:
	var radius := Balance.BOSS_RADIUS + 0.25
	for y in range(GridSystem.GRID_HEIGHT):
		for x in range(GridSystem.GRID_WIDTH):
			var center := Vector2(x, y) + Vector2(0.5, 0.5)
			if center.distance_to(Balance.BOSS_CENTER) <= radius:
				_grid.set_cell_state(Vector2i(x, y), GridSystem.CellState.OBSTACLE)


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return

	# 도착한 몬스터들이 보스를 지속 공격
	if total_dps > 0.0:
		var dealt := total_dps * delta
		hp -= dealt
		_dmg_accum += dealt
		for m in _attackers:
			damage_by_player[m.owner_id] = damage_by_player.get(m.owner_id, 0.0) + m.dps * delta

		_dmg_timer += delta
		if _dmg_timer >= 1.0:
			_show_damage_text()

	time_left -= delta
	_view.queue_redraw()

	if hp <= 0.0:
		hp = 0.0
		_finish(State.VICTORY, "보스 처치")
	elif time_left <= 0.0:
		time_left = 0.0
		_finish(State.DEFEAT, "제한시간 초과")


func _show_damage_text() -> void:
	var at := Balance.BOSS_CENTER + Vector2(randf_range(-1.2, 1.2), -Balance.BOSS_RADIUS - 0.3)
	Effects.float_text(_renderer, at, "-%d" % int(_dmg_accum), Color(1.0, 0.35, 0.35), _lane_visible)
	_dmg_accum = 0.0
	_dmg_timer = 0.0


## 보스 체력이 낮을수록 강한 몬스터를 모든 참여 레인에 파견
func _dispatch_wave() -> void:
	var ratio := hp / max_hp
	var monster_hp := Balance.WAVE_MONSTER_HP * (1.0 + Balance.WAVE_HP_BONUS_AT_LOW_BOSS * (1.0 - ratio))
	Log.debug(Log.Category.GAME, "보스 파견: 보스hp=%.0f%% 몬스터hp=%.1f" % [ratio * 100.0, monster_hp])
	for lane in _lanes.values():
		lane.spawn_wave_monster(monster_hp)


## 플레이어가 생산한 몬스터를 보스 레인으로 보낸다
func spawn_player_monster(owner_id: int, kind_id: String) -> void:
	var kind: Dictionary = Balance.SENT_MONSTERS[kind_id]
	var spawn_cells := _grid.get_spawn_cells()
	if spawn_cells.is_empty():
		Log.error(Log.Category.GAME, "보스 레인 스폰 셀이 없음")
		return

	var spawn_cell: Vector2i = spawn_cells.pick_random()
	var spawn_pos := Vector2(spawn_cell) + Vector2(0.5, 0.5)
	var slot := _allocate_slot(spawn_pos)

	var monster := Monster.new()
	monster.owner_id = owner_id
	monster.kind_id = kind_id
	monster.shape = kind.shape
	monster.dps = kind.dps
	monster.body_color = kind.color
	monster.goal_cell = _walkable_cell_near(slot)
	monster.final_point = slot
	monster.visible = _lane_visible
	monster.z_index = 2
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cell)
	monster.reached_exit.connect(_on_monster_arrived)
	_renderer.add_child(monster)
	_sent_monsters.append(monster)
	Log.info(Log.Category.GAME, "[P%d] %s 파견 (보스 레인 몬스터#%d, 목표 자리 %s)" % [
		owner_id + 1, kind.name, _next_monster_id, slot.snapped(Vector2(0.01, 0.01))])
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
	total_dps += monster.dps
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
		Log.info(Log.Category.GAME, "승리! %s (남은시간 %.0fs) 기여도=%s" % [reason, time_left, damage_by_player])
		boss_defeated.emit()
	else:
		Log.warn(Log.Category.GAME, "패배: %s (보스 남은 hp=%.0f/%.0f)" % [reason, hp, max_hp])
		boss_failed.emit(reason)


func set_lane_visible(is_shown: bool) -> void:
	_lane_visible = is_shown
	if _view:
		_view.visible = is_shown
	for m in _sent_monsters:
		m.visible = is_shown


## 보스 레인 한가운데의 커다란 보스
class BossView extends Node2D:
	var boss: BossController
	var renderer: GridRenderer
	var _t := 0.0

	func _process(delta: float) -> void:
		_t += delta
		queue_redraw()

	func _draw() -> void:
		var cell: float = renderer.CELL_SIZE
		var R: float = Balance.BOSS_RADIUS * cell
		var pressure := minf(1.0, boss.total_dps / 12.0)  # 공격받을수록 몸을 떤다
		var shake := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * cell * 0.04 * pressure
		var breathe := 1.0 + 0.03 * sin(_t * 2.0)
		var c: Vector2 = Balance.BOSS_CENTER * cell + shake
		var body := Color(0.5, 0.08, 0.14)

		# 바닥 그림자 + 기운
		draw_set_transform(c + Vector2(0, R * 0.95), 0.0, Vector2(1.0, 0.3))
		draw_circle(Vector2.ZERO, R * 1.1, Color(0, 0, 0, 0.35))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		draw_circle(c, R * 1.25 * breathe, Color(0.8, 0.1, 0.1, 0.10 + 0.08 * sin(_t * 3.0)))

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

		# 체력바 + 이름
		var bar_w := R * 2.2
		var bar_y := c.y - R * 1.7
		var ratio := clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		draw_rect(Rect2(c.x - bar_w * 0.5 - 2, bar_y - 2, bar_w + 4, 14), Color(0, 0, 0, 0.75))
		draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w * ratio, 10), Color(0.9, 0.15, 0.15))
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(c.x - bar_w * 0.5, bar_y - 6), "BOSS Lv.1   %d / %d" % [int(boss.hp), int(boss.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
