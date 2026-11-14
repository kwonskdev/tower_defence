extends Node
class_name BossController
## 보스 레인 담당 (협력 모드).
## - 보스 체력/제한시간
## - 일정 시간마다 모든 참여 플레이어 레인에 몬스터 자동 파견 (보스 체력이 낮을수록 강해짐)
## - 플레이어가 보낸 몬스터는 보스 레인을 걸어가 보스 앞에 서서 보스를 지속 공격한다 (사라지지 않음)
## - 보스는 플레이어 몬스터를 공격하지 않는다 (현재 미정)
## TODO: 보스 스킬, 레벨 2 이후 보스, 보상, 플레이어별 기여도 UI

signal boss_defeated
signal boss_failed(reason: String)

enum State { RUNNING, VICTORY, DEFEAT }

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
var _next_monster_id := 1
var _view: Node2D
var _lane_visible := false


func setup(boss_grid: GridSystem, renderer: GridRenderer, lanes: Dictionary) -> void:
	_grid = boss_grid
	_renderer = renderer
	_lanes = lanes
	_pathfinder = Pathfinder.new(_grid)

	max_hp = Balance.BOSS_BASE_HP + Balance.BOSS_HP_PER_EXTRA_PLAYER * (lanes.size() - 1)  # 인원수에 따른 난이도
	hp = max_hp

	_view = BossView.new()
	_view.boss = self
	_view.renderer = renderer
	_view.visible = _lane_visible
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


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return

	# 도착한 몬스터들이 보스를 지속 공격
	if total_dps > 0.0:
		hp -= total_dps * delta
		for m in _attackers:
			damage_by_player[m.owner_id] = damage_by_player.get(m.owner_id, 0.0) + m.dps * delta

	time_left -= delta
	_view.queue_redraw()

	if hp <= 0.0:
		hp = 0.0
		_finish(State.VICTORY, "보스 처치")
	elif time_left <= 0.0:
		time_left = 0.0
		_finish(State.DEFEAT, "제한시간 초과")


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

	var monster := Monster.new()
	monster.owner_id = owner_id
	monster.kind_id = kind_id
	monster.dps = kind.dps
	monster.body_color = kind.color
	monster.stop_at_row = GridSystem.GRID_HEIGHT - 2  # 보스는 맨 아래 행에 있음
	monster.draw_offset = Vector2(randf_range(-0.3, 0.3), randf_range(-0.25, 0.1))
	monster.visible = _lane_visible
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cells.pick_random())
	monster.reached_exit.connect(_on_monster_arrived)
	_renderer.add_child(monster)
	_sent_monsters.append(monster)
	Log.info(Log.Category.GAME, "[P%d] %s 파견 (보스 레인 몬스터#%d)" % [owner_id + 1, kind.name, _next_monster_id])
	_next_monster_id += 1


func _on_monster_arrived(monster: Monster) -> void:
	monster.stop()
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


## 보스 레인 맨 아래 행에 보스를 그린다
class BossView extends Node2D:
	var boss: BossController
	var renderer: GridRenderer

	func _draw() -> void:
		var cell: float = renderer.CELL_SIZE
		var top := (GridSystem.GRID_HEIGHT - 1) * cell
		var width := GridSystem.GRID_WIDTH * cell
		draw_rect(Rect2(0, top, width, cell), Color(0.5, 0.05, 0.05, 0.9))

		var ratio := clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		draw_rect(Rect2(0, top, width * ratio, cell * 0.25), Color.RED)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(6, top + cell * 0.85), "BOSS  %d / %d" % [int(boss.hp), int(boss.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
