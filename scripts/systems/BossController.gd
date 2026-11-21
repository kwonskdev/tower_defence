extends Node
class_name BossController
## 보스 레인 담당 (협력 모드).
## - 보스는 총 BossLevels.COUNT(10) 라운드. 한 라운드를 깨면 보상 골드를 주고, 남은 제한시간 동안 "유령 구간"이 이어진 뒤 다음 보스가 나온다.
## - 유령 구간: 일반 웨이브는 멈추고 수입은 그대로 들어온다. 모든 참여 레인과 보스 자리에 체력 무한의 유령이 나오고, 타워가/보스 앞 몬스터가
##   유령에게 준 피해가 점수가 된다 (레인 데미지 / 보스 레인 데미지를 따로 센다. GhostScore). 마지막 보스(Lv.10)도 같고, 구간이 끝나면 승리한다.
## - 보스는 레인 한가운데에 크게 서 있고, 내가 보낸 몬스터들이 걸어와서 보스를 둘러싸고 공격한다.
##   보스 앞에 선 몬스터는 사라지지 않고 다음 라운드 보스도 계속 공격한다 (수 제한 없음).
## - 수입이 들어오는 시점(INCOME_INTERVAL)마다 모든 참여 플레이어 레인에 몬스터 웨이브가 한꺼번에 온다 (PvE).
##   보스에게도 수입(BossLevels의 income)이 있다. 웨이브마다 그 돈 안에서 이번 라운드에 나올 수 있는 몬스터(min_level)를 랜덤으로 사서 보낸다.
##   종류는 WAVE_GROUPS개까지이고, 다음 웨이브에 뭐가 오는지는 미리 정해져서 HUD에 보인다. 몬스터는 하나하나 나오는 칸이 랜덤이다.
##   종류마다 이기는 타워가 달라서 그때그때 필요한 타워가 달라진다 (Monsters.gd 상성 참고).
## - 제한시간 안에 못 잡으면 패배. 보스는 플레이어 몬스터를 공격하지 않는다 (현재 미정).
## - 보스 스킬은 BossSkills.gd에 라운드별로 정의한다. 지금 있는 것: 웨이브 주기/마릿수, 웨이브 변형(돌격/부활/공습), 비늘 보호막,
##   동상(Lv.6), 체력 조건/주기 발동형(Lv.5 분열, Lv.7 처단+환영, Lv.9 공포+봉인). 발동형은 예고(배너+표식) 뒤에 발동한다.
## - 페이즈(Lv.10): 보스 체력이 내려가면 단계가 바뀌고, 그 단계의 스킬만 켜진다 (BossSkills.PHASES).

signal level_started(level: int)
signal level_cleared(level: int)
signal boss_defeated        # 마지막 라운드까지 모두 처치
signal boss_failed(reason: String)
signal skill_announced(info: Dictionary)  # 스킬을 HUD 배너로 알린다: {name, text, lane, delay, boss}. delay>0이면 그 시간 뒤 발동

enum State { WAITING, RUNNING, VICTORY, DEFEAT }  # WAITING: 시작 버튼을 누르기 전 (시간도 몬스터 파견도 멈춰 있음)

const SLOT_RING_GAP := 0.65   # 겹겹이 둘러쌀 때 바깥 고리 간격 (칸)
const SLOT_SPACING := 0.85    # 같은 고리에서 몬스터 간 간격 (칸)
const DPS_RECALC_INTERVAL := 0.25
const AURA_BONUS_CAP := 1.5   # 지원형 오라는 아무리 겹쳐도 최대 +150%
const MAX_WAVE_MONSTERS := 80  # 한 웨이브 최대 마릿수 (싼 몬스터만 뽑혀도 화면이 터지지 않게)
const MIN_WAVE_GAP := 10.0    # 웨이브 주기를 수입 시점에 다시 맞출 때, 직전 웨이브와 최소 이만큼은 띄운다 (초)

var state: State = State.WAITING
var level: int = 1
var events := SimEvents.new()  # 연출 이벤트 통로 (GameField가 세션 것으로 바꿔 끼운다)
var rng := RandomNumberGenerator.new()  # 보스의 시뮬레이션 랜덤 (GameField가 세션 것으로 바꿔 끼운다). 화면 흔들림 같은 연출 랜덤은 전역 randf()
var level_data: Dictionary = {}
var max_hp: float
var hp: float
var time_left: float
var total_dps: float = 0.0
var damage_by_player: Dictionary = {}  # player_id -> 누적 피해
var current_wave_text: String = "-"    # HUD 표시용: 지금 파견 중인 몬스터
var level_flash: float = 0.0           # 새 보스 등장 연출
var in_ghost_phase := false            # 보스를 잡고 남은 시간 동안의 유령 구간인가 (이 동안 time_left는 "다음 보스까지"의 시간)
var ghost_length := 0.0                # 이번 유령 구간의 전체 길이 (초. 남은 시간 막대용)
var ghost_boss_damage_by_player: Dictionary = {}  # player_id -> 보스 레인 유령에게 준 피해 누적 (게임 전체. damage_by_player와 따로 센다)

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
var _next_wave: Array = []            # 다음 웨이브 [{type, count}] (보스 수입으로 미리 "사 둔다")
var damage_mult := 1.0                # 보스가 받는 피해 배율 (비늘 보호막. 1.0이면 그대로)
var _next_affix := ""                 # 다음 웨이브에 붙는 변형 (BossSkills.AFFIXES 키, 없으면 "")
var _level_wave_no := 0               # 이번 보스 라운드에서 지금까지 보낸 웨이브 수
var _guard_per_monster := 0.0         # 비늘 보호막: 웨이브 몬스터 1마리당 피해 감소 / 최대 감소
var _guard_cap := 0.0
var sent_count := 0                   # 지금까지 보낸 몬스터 수 (죽은 것 포함)
var _chill_start := 0.0               # 동상: 이 라운드에서 선 지 _chill_start초부터 dps가 줄고 _chill_full초에 _chill_max만큼 줄어 있다 (_chill_max가 0이면 없음)
var _chill_full := 1.0
var _chill_max := 0.0
var _since_wave := 999.0              # 마지막 웨이브를 보낸 뒤 지난 시간(초). 아직 안 보냈으면 큰 값
var _phase := 0                       # 지금 페이즈 (1부터. 페이즈가 없는 보스는 0)
var _triggered: Array = []            # 지금 페이즈의 발동형 스킬 [{skill, fired: Array, timer: float}]
var _pending_casts: Array = []        # 예고 중인 발동 [{skill, left, targets: Array}]
var _wave_serial := 0                 # 유령 구간이 시작될 때마다 오른다. 파견 중이던 웨이브/분열 소환은 번호가 바뀌면 멈춘다


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
		ghost_boss_damage_by_player[lane.player_id] = 0.0  # 아직 못 쳤어도 순위에 올라 있게

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
	_announce_level_skills()


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

	Log.info(Log.Category.GAME, "보스 Lv.%d/%d '%s' 등장: hp=%.0f (참여 %d명), 제한시간=%.0fs, 보스 수입=%d골드/%.0fs" % [
		level, BossLevels.COUNT, level_data.name, max_hp, _lanes.size(), time_left, level_data.income,
		Balance.INCOME_INTERVAL])
	events.text(GameField.BOSS_LANE_ID, Balance.BOSS_CENTER + Vector2(-1.2, 0.3), "BOSS Lv.%d  %s" % [level, level_data.name], Color(1.0, 0.85, 0.3))
	_apply_level_skills()
	level_started.emit(level)


## 새 보스 라운드가 시작됐다: 웨이브 번호와 예고를 초기화하고 첫 페이즈(페이즈가 없으면 0)의 스킬을 적용한다
func _apply_level_skills() -> void:
	_level_wave_no = 0
	_clear_pending_casts()  # 이전 라운드에서 예고만 하고 발동 못 한 스킬은 취소한다
	for m in _attackers:
		m.chill_time = 0.0  # 동상은 이 라운드가 시작된 뒤에 선 시간부터 센다
	_phase = 1 if not BossSkills.phases_of(level).is_empty() else 0
	_apply_active_skills()


## 지금 켜져 있는 스킬(이 라운드의 스킬 중 현재 페이즈에 해당하는 것)을 적용한다. 페이즈가 바뀔 때도 다시 부른다.
## 항상 켜져 있는 값(웨이브 주기, 마릿수, 보호막, 동상)은 기본값에서 다시 계산하고, 발동형은 시계를 새로 시작한다.
func _apply_active_skills() -> void:
	var interval := Balance.INCOME_INTERVAL
	_guard_per_monster = 0.0
	_guard_cap = 0.0
	_chill_max = 0.0
	_triggered.clear()
	for skill in _active_skills():
		interval = minf(interval, float(skill.get("wave_interval", interval)))
		_guard_per_monster += float(skill.get("guard_per_monster", 0.0))
		_guard_cap = maxf(_guard_cap, float(skill.get("guard_cap", 0.0)))
		if skill.has("chill_max"):
			_chill_start = float(skill.chill_start)
			_chill_full = float(skill.chill_full)
			_chill_max = float(skill.chill_max)
		if skill.has("trigger"):
			var fired: Array = []
			for _r in skill.get("hp_ratios", []):
				fired.append(false)
			_triggered.append({"skill": skill, "fired": fired, "timer": float(skill.get("first", skill.get("period", 20.0)))})
	_apply_wave_interval(interval)
	# 라운드나 페이즈가 바뀌면 보스 수입/뽑을 수 있는 종류/변형이 달라지므로 다음 웨이브를 다시 산다 (처음 setup 때는 setup이 정한다)
	if not _next_wave.is_empty():
		_plan_next_wave()
	if not _active_skills().is_empty():
		Log.info(Log.Category.GAME, "보스 스킬 적용(페이즈 %d): 웨이브 주기 %.0fs, 보호막 %.0f%%/마리(최대 %.0f%%), 발동형 %d개" % [
			_phase, interval, _guard_per_monster * 100.0, _guard_cap * 100.0, _triggered.size()])


## 이번 라운드의 스킬 중 지금 페이즈에 켜져 있는 것
func _active_skills() -> Array:
	return BossSkills.of_level(level).filter(func(s: Dictionary): return BossSkills.in_phase(s, _phase))


## 보스 체력 비율에 해당하는 페이즈 번호 (페이즈가 없는 보스는 0)
func _phase_for_ratio(ratio: float) -> int:
	var phases := BossSkills.phases_of(level)
	for i in range(phases.size() - 1, -1, -1):
		if ratio <= float(phases[i].from):
			return i + 1
	return 1 if not phases.is_empty() else 0


## 다음 페이즈로 넘어간다: 이전 페이즈의 스킬은 꺼지고 새 페이즈의 스킬이 켜진다 (예고 중인 스킬은 그대로 발동한다)
func _enter_phase(new_phase: int) -> void:
	_phase = new_phase
	level_flash = 0.6
	Log.info(Log.Category.GAME, "보스 Lv.%d 페이즈 %d 돌입 (체력 %.0f%%)" % [level, _phase, hp / max_hp * 100.0])
	_apply_active_skills()
	_announce_level_skills()


## HUD용: 페이즈가 있는 보스면 "[페이즈 2/3]", 없으면 빈 문자열
func phase_text() -> String:
	var count := BossSkills.phases_of(level).size()
	return "  [페이즈 %d/%d]" % [_phase, count] if count > 0 else ""


## 지금 스킬을 배너로 알린다 (시작 버튼을 누를 때, 새 보스가 나올 때, 페이즈가 바뀔 때).
## 페이즈가 있으면 그 페이즈의 안내문을 먼저, 그다음 quiet가 아닌 스킬을 하나씩.
func _announce_level_skills() -> void:
	if _phase > 0:
		var info: Dictionary = BossSkills.phases_of(level)[_phase - 1]
		skill_announced.emit({"name": info.name, "text": info.text, "lane": info.lane, "delay": 0.0, "boss": level_data.name})
	for skill in _active_skills():
		if not skill.get("quiet", false):
			skill_announced.emit({"name": skill.name, "text": skill.text, "lane": skill.lane, "delay": 0.0, "boss": level_data.name})


## 웨이브 주기를 바꾼다. 평소 주기(수입 주기)로 돌아올 때는 다음 수입 시점에 맞춰서 웨이브와 수입이 다시 같이 오게 한다.
func _apply_wave_interval(interval: float) -> void:
	if is_equal_approx(_dispatch_timer.wait_time, interval):
		return
	var running := not _dispatch_timer.is_stopped()
	_dispatch_timer.wait_time = interval
	if not running:
		return  # 시작 전: begin()이 이 주기로 시작한다
	var first_wait := minf(_dispatch_timer.time_left, interval)  # 주기가 짧아질 때: 곧 올 웨이브를 늦추지 않는다
	if is_equal_approx(interval, Balance.INCOME_INTERVAL):
		var left := _income_time_left()
		if left > 0.0:
			if _since_wave + left < MIN_WAVE_GAP:
				left += Balance.INCOME_INTERVAL  # 방금 웨이브가 왔는데 곧바로 또 오지 않게 그다음 수입 시점으로 미룬다
			first_wait = left
	_dispatch_timer.start(first_wait)     # start(시간)은 wait_time도 그 값으로 바꾼다
	_dispatch_timer.wait_time = interval  # 그래서 첫 대기가 끝난 뒤부터는 원래 주기로 되돌려 놓는다


## 다음 수입까지 남은 시간 (참여 중인 레인 기준, 없으면 -1)
func _income_time_left() -> float:
	for lane in _lanes.values():
		if lane.active:
			return lane.income_time_left()
	return -1.0


func _process(delta: float) -> void:
	if state != State.RUNNING:
		return

	level_flash = maxf(0.0, level_flash - delta * 1.2)
	_since_wave += delta

	# 성장형 몬스터는 보스 앞에 서 있는 시간이 길어질수록 강해진다
	for m in _attackers:
		m.time_at_boss += delta
		m.chill_time += delta
		m.dread_time = maxf(0.0, m.dread_time - delta)
	_dps_timer -= delta
	if _dps_timer <= 0.0:
		_dps_timer = DPS_RECALC_INTERVAL
		_recalc_dps()
	if in_ghost_phase:
		_process_ghost_phase(delta)  # 보스는 이미 죽었다: 스킬도 보스 체력도 제한시간 패배도 없다
		return
	_update_skills(delta)

	# 도착한 몬스터들이 보스를 지속 공격 (비늘 보호막이 있으면 필드 위 웨이브 몬스터 수만큼 피해가 줄어든다)
	damage_mult = 1.0 - _guard_reduction()
	if total_dps > 0.0:
		var dealt := total_dps * delta * damage_mult
		hp -= dealt
		_dmg_accum += dealt
		for m in _attackers:
			damage_by_player[m.owner_id] = damage_by_player.get(m.owner_id, 0.0) + m.current_dps * delta * damage_mult

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


## 비늘 보호막이 지금 줄이는 피해 비율 (0~guard_cap). 필드 위 웨이브 몬스터 수를 참여 레인 평균으로 센다.
func _guard_reduction() -> float:
	if _guard_per_monster <= 0.0:
		return 0.0
	var alive := 0
	var lane_count := 0
	for lane in _lanes.values():
		if lane.active:
			alive += lane.wave_monster_count()  # 유령은 웨이브 몬스터가 아니다
			lane_count += 1
	if lane_count == 0:
		return 0.0
	return minf(_guard_cap, _guard_per_monster * float(alive) / float(lane_count))


## 보호막까지 반영해서 보스가 실제로 깎이는 초당 피해
func effective_dps() -> float:
	return total_dps * damage_mult


## 이번 라운드에 비늘 보호막이 있는가 (HUD 표시용)
func has_guard() -> bool:
	return _guard_per_monster > 0.0


## 보스 앞에 선 몬스터들의 실제 초당 피해 합계 (성장 + 지원형 오라 반영)
func _recalc_dps() -> void:
	var supporters: Array[Monster] = []
	for m in _attackers:
		if m.aura_bonus > 0.0:
			supporters.append(m)

	var total := 0.0
	for m in _attackers:
		# 기본 DPS + 성장(ramp), 둘 다 강화 반영
		var base := m.get_boosted_dps()
		var bonus := 0.0
		for s in supporters:
			if s != m and s.cell_pos.distance_to(m.cell_pos) <= s.aura_radius:
				bonus += s.aura_bonus
		var dps_now := base * (1.0 + minf(bonus, AURA_BONUS_CAP))
		m.chill = _chill_of(m)
		m.current_dps = 0.0 if m.dread_time > 0.0 else dps_now * (1.0 - m.chill)  # 공포 중이면 0, 동상이면 그만큼 감소
		total += m.current_dps
	total_dps = total


func _show_damage_text() -> void:
	# 체력바(보스 머리 위)와 겹치지 않도록 몸통 위에서 떠오르게 한다
	var at := Balance.BOSS_CENTER + Vector2(randf_range(-1.3, 1.0), randf_range(0.0, 0.9))
	events.text(GameField.BOSS_LANE_ID, at, "-%d" % int(_dmg_accum), Color(1.0, 0.9, 0.45))
	_dmg_accum = 0.0
	_dmg_timer = 0.0


func _on_level_cleared() -> void:
	Log.info(Log.Category.GAME, "보스 Lv.%d '%s' 처치! (남은시간 %.0fs)" % [level, level_data.name, time_left])
	level_cleared.emit(level)

	# 보상 지급 (마지막 보스는 보상이 0)
	var reward: int = level_data.reward
	if reward > 0:
		for lane in _lanes.values():
			if lane.active:
				lane.gold += reward
				Log.info(Log.Category.ECONOMY, "[P%d] 보스 처치 보상 +%d골드 잔액=%.2f" % [lane.player_id + 1, reward, lane.gold])  # 골드는 소수일 수 있다 (타워 판매 환급)
		events.text(GameField.BOSS_LANE_ID, Balance.BOSS_CENTER + Vector2(-1.0, -0.8), "처치! +%d골드" % reward, Color(1.0, 0.9, 0.3))

	if time_left > 0.0:
		_enter_ghost_phase()  # 남은 시간은 버리지 않는다: 그 시간 동안 유령 구간이 이어지고, 끝나면 다음 보스(마지막이면 승리)
	else:
		_advance_level()


## 다음 보스를 내보낸다 (마지막 보스를 잡았으면 승리). 보스 앞에 선 몬스터는 그대로 남아 다음 보스를 공격한다.
func _advance_level() -> void:
	if level >= BossLevels.COUNT:
		_finish(State.VICTORY, "모든 보스 처치")
		return
	_start_level(level + 1)
	_announce_level_skills()


# --- 유령 구간 (보스를 일찍 잡고 남은 시간) ---

## 보스를 잡았는데 제한시간이 남았다: 남은 시간만큼 유령 구간을 연다.
## 웨이브는 멈추고 (수입 타이머는 레인 것이라 그대로 돈다), 보스의 스킬은 모두 꺼지고, 모든 참여 레인과 보스 자리에 유령이 나온다.
func _enter_ghost_phase() -> void:
	in_ghost_phase = true
	ghost_length = time_left
	hp = 0.0
	level_flash = 0.6
	_wave_serial += 1          # 파견 중이던 웨이브와 분열 소환이 더 나오지 않게 끊는다
	_dispatch_timer.stop()
	_clear_pending_casts()
	_triggered.clear()
	_guard_per_monster = 0.0   # 죽은 보스의 보호막/동상은 더 이상 없다
	_guard_cap = 0.0
	_chill_max = 0.0
	damage_mult = 1.0
	_dmg_accum = 0.0
	_dmg_timer = 0.0
	_recalc_dps()
	for lane in _lanes.values():
		lane.start_ghost()
	var is_last := level >= BossLevels.COUNT
	skill_announced.emit({
		"name": "유령 구간",
		"text": "보스를 일찍 잡아서 남은 %d초 동안 유령이 나옵니다. 웨이브는 쉬고 수입은 그대로 들어옵니다. 타워가 유령에게 입힌 피해(레인 데미지)와 보스 앞 몬스터가 입힌 피해(보스 레인 데미지)가 점수가 됩니다. %s" % [
			ceili(time_left), "구간이 끝나면 승리합니다." if is_last else "구간이 끝나면 다음 보스가 나옵니다."],
		"lane": "both", "delay": 0.0, "boss": level_data.name})
	Log.info(Log.Category.GAME, "유령 구간 시작: 보스 Lv.%d 처치 후 남은 %.1fs 동안 (참여 %d명, %s)" % [
		level, time_left, _lanes.size(), "구간이 끝나면 승리" if is_last else "구간이 끝나면 Lv.%d" % (level + 1)])


## 유령 구간 한 프레임: 보스 앞에 선 몬스터들이 보스 자리의 유령을 때린다 (피해는 보스 레인 데미지로 따로 센다). 시간이 다 되면 다음 보스.
func _process_ghost_phase(delta: float) -> void:
	damage_mult = 1.0
	if total_dps > 0.0:
		_dmg_accum += total_dps * delta
		for m in _attackers:
			ghost_boss_damage_by_player[m.owner_id] = ghost_boss_damage_by_player.get(m.owner_id, 0.0) + m.current_dps * delta
		_dmg_timer += delta
		if _dmg_timer >= 1.0:
			_show_damage_text()
	time_left -= delta
	_view.queue_redraw()
	if time_left <= 0.0:
		time_left = 0.0
		_end_ghost_phase()


## 유령 구간이 끝났다: 유령을 치우고 다음 보스를 내보낸다 (마지막 보스면 승리). 웨이브는 수입 시점에 맞춰 다시 시작한다.
func _end_ghost_phase() -> void:
	in_ghost_phase = false
	for lane in _lanes.values():
		lane.stop_ghost()
	Log.info(Log.Category.GAME, "유령 구간 끝: 레인 데미지 %s / 보스 레인 데미지 %s" % [ghost_lane_damage_by_player(), ghost_boss_damage_by_player])
	_advance_level()
	if state == State.RUNNING:
		_resume_waves()


## 멈춰 있던 웨이브 타이머를 다시 켠다. _advance_level -> _start_level이 이 보스의 웨이브 주기를 wait_time에 이미 넣어 두었다.
## 평소 주기(수입 주기)면 다음 수입 시점에 맞춰 첫 웨이브가 오게 한다 (직전 웨이브와 MIN_WAVE_GAP보다 가까우면 그다음 수입 시점으로 미룬다).
func _resume_waves() -> void:
	var interval := _dispatch_timer.wait_time
	var first_wait := interval
	if is_equal_approx(interval, Balance.INCOME_INTERVAL):
		var left := _income_time_left()
		if left > 0.0:
			if _since_wave + left < MIN_WAVE_GAP:
				left += Balance.INCOME_INTERVAL
			first_wait = left
	_dispatch_timer.start(first_wait)     # start(시간)은 wait_time도 그 값으로 바꾼다
	_dispatch_timer.wait_time = interval  # 첫 대기가 끝난 뒤부터는 원래 주기로 되돌려 놓는다


## 지금 유령 구간이 진행 중인가 (구간 중에 패배해서 끝난 게임은 아니다). HUD 안내는 이 값을 본다.
func ghost_running() -> bool:
	return in_ghost_phase and state == State.RUNNING


## 플레이어별 레인 데미지 누적 {player_id: 피해}. 각 레인의 타워들이 유령에게 준 피해 (부서진 타워의 몫 포함)
func ghost_lane_damage_by_player() -> Dictionary:
	var result := {}
	for lane in _lanes.values():
		result[lane.player_id] = lane.ghost_damage
	return result


## 플레이어별 보스 레인 데미지 누적 {player_id: 피해} (참여한 모든 플레이어가 들어 있다)
func ghost_boss_damage_totals() -> Dictionary:
	var result := ghost_boss_damage_by_player.duplicate()
	for pid in _lanes:
		result[pid] = result.get(pid, 0.0)
	return result


## 유령 점수 요약 (GhostScore.summary). 실시간 랭킹과 결과 화면이 같은 값을 쓴다.
func ghost_summary() -> Dictionary:
	return GhostScore.summary(ghost_lane_damage_by_player(), ghost_boss_damage_totals(), _lanes.size())


## 다음 웨이브를 미리 정한다 (HUD 미리보기용). 보스에게는 수입이 있어서, 그 돈 안에서 이번 라운드에 살 수 있는 몬스터를
## 가중치로 랜덤하게 뽑아 더 살 수 없을 때까지 산다. 공습 변형이면 공중 종류만 산다.
## 종류는 WAVE_GROUPS개까지만 (HUD 칸 수). 같은 종류는 한 묶음(count마리)씩 산다 (살 돈이 모자라면 그만큼만).
func _plan_next_wave() -> void:
	_next_affix = _affix_for_wave(_level_wave_no + 1)
	var air_only := _next_affix != "" and bool(BossSkills.AFFIXES[_next_affix].get("air_only", false))
	var pool := Monsters.candidates(level, air_only)
	if pool.is_empty():
		pool = Monsters.candidates(level)
	var budget := wave_budget()
	var counts := {}
	var order: Array[String] = []
	var total := 0
	while total < MAX_WAVE_MONSTERS:
		var options: Array[String] = []
		var weight_sum := 0.0
		for id in pool:
			if int(Monsters.DATA[id].cost) > budget:
				continue  # 못 산다
			if order.size() >= Balance.WAVE_GROUPS and not counts.has(id):
				continue  # 이미 종류가 꽉 찼다
			options.append(id)
			weight_sum += float(Monsters.DATA[id].weight)
		if options.is_empty():
			break
		var roll := rng.randf() * weight_sum
		var chosen: String = options[options.size() - 1]
		for id in options:
			roll -= float(Monsters.DATA[id].weight)
			if roll <= 0.0:
				chosen = id
				break
		var cost := int(Monsters.DATA[chosen].cost)
		var bundle := mini(mini(int(Monsters.DATA[chosen].get("count", 1)), budget / cost), MAX_WAVE_MONSTERS - total)
		budget -= bundle * cost
		total += bundle
		if not counts.has(chosen):
			order.append(chosen)
			counts[chosen] = 0
		counts[chosen] += bundle
	_next_wave.clear()
	for id in order:
		_next_wave.append({"type": id, "count": counts[id]})


## 이번 웨이브에 보스가 쓸 수 있는 돈: 보스 수입(라운드별 income) 그대로. 웨이브 주기나 스킬과 상관없다 (주기가 짧으면 그만큼 더 어렵다).
func wave_budget() -> int:
	return level_data.income


## 이번 라운드의 wave_no번째 웨이브에 붙는 변형 (없으면 ""). "N웨이브마다"는 N, 2N, ... 번째에 붙는다.
func _affix_for_wave(wave_no: int) -> String:
	for skill in _active_skills():
		if not skill.has("wave_affix"):
			continue
		var k := wave_no - int(skill.get("affix_offset", 0))  # 번갈아 붙일 때는 번호를 밀어서 겹치지 않게 한다
		if k >= 0 and k % int(skill.affix_every) == 0:
			return skill.wave_affix
	return ""


## HUD용: 다음 웨이브에 붙는 변형 {id, name, color}. 없으면 빈 딕셔너리.
func get_next_wave_affix() -> Dictionary:
	if _next_affix == "":
		return {}
	var a: Dictionary = BossSkills.AFFIXES[_next_affix]
	return {"id": _next_affix, "name": a.name, "color": a.color}


## HUD용: 다음 웨이브에 뭐가 몇 마리 오는지. [{type, name, count, flying, color}]
func get_next_wave_preview() -> Array:
	var preview: Array = []
	for e in _next_wave:
		var wt: Dictionary = Monsters.DATA[e.type]
		preview.append({"type": e.type, "name": wt.name, "count": e.count, "flying": bool(wt.get("flying", false)), "color": wt.color})
	return preview


## 다음 웨이브까지 남은 시간(초). 시작 전이거나 끝났으면 -1.
func time_to_next_wave() -> float:
	if state != State.RUNNING or _dispatch_timer.is_stopped():
		return -1.0
	return _dispatch_timer.time_left


## 모든 참여 레인에 웨이브를 보낸다 (수입 시점마다).
## 웨이브 = 종류가 다른 묶음 WAVE_GROUPS개. 묶음은 한 칸에서 촘촘히 연달아 나와서 한 덩어리로 온다.
## 체력/공격력은 몬스터마다 고정이다 (Monsters.gd).
func _dispatch_wave() -> void:
	if state != State.RUNNING:
		return
	_since_wave = 0.0
	var serial := _wave_serial
	var wave := _next_wave.duplicate()
	var preview := get_next_wave_preview()
	var affix_id := _next_affix
	_level_wave_no += 1
	_plan_next_wave()  # 그다음 웨이브를 미리 정해 둔다
	var parts: Array[String] = []
	for e in preview:
		parts.append("%s x%d%s" % [e.name, e.count, "(공중)" if e.flying else ""])
	current_wave_text = ", ".join(parts)
	Log.debug(Log.Category.GAME, "보스 파견: %s%s (Lv.%d, %d번째 웨이브)" % [
		"[%s] " % affix_id if affix_id != "" else "", current_wave_text, level, _level_wave_no])
	if affix_id != "":  # 변형 웨이브는 도착할 때 한 번 더 알린다 (미리보기는 이미 한 웨이브 전부터 떠 있다)
		var a: Dictionary = BossSkills.AFFIXES[affix_id]
		skill_announced.emit({"name": "%s 웨이브" % a.name, "text": a.text, "lane": "player", "delay": 0.0, "boss": level_data.name})

	var dispatch_level := level
	# 몬스터마다 나오는 칸을 따로 랜덤으로 뽑는다 (spawn_cell을 안 주면 레인이 뽑는다). 같은 종류끼리는 연달아 나온다.
	var first := true
	for entry in wave:
		for i in range(int(entry.count)):
			if not first:
				var gap := Balance.WAVE_SPAWN_GAP if i > 0 else Balance.WAVE_GROUP_GAP
				await get_tree().create_timer(gap, false).timeout  # (false: 일시정지 중에는 멈춘다) 촘촘하게 연달아 나온다 (종류 사이는 조금 더 띄운다)
				if state != State.RUNNING or serial != _wave_serial:  # 보스를 잡아서 유령 구간이 되면 남은 몬스터는 더 나오지 않는다
					return
			first = false
			for lane in _lanes.values():
				lane.spawn_wave_monster(entry.type, dispatch_level, Pathfinder.NO_GOAL, affix_id)


## 몬스터를 보낼 수 있는가 (스폰 칸이 있는가). 골드를 쓰기 전에 확인하는 용도 -> spawn_player_monster는 이때 실패하지 않는다.
func can_spawn_player_monster() -> bool:
	return not _grid.get_spawn_cells().is_empty()


## 플레이어가 생산한 몬스터를 보스 레인으로 보낸다
func spawn_player_monster(owner_id: int, kind_id: String) -> void:
	var data: Dictionary = Monsters.DATA[kind_id]
	var spawn_cells := _grid.get_spawn_cells()
	if spawn_cells.is_empty():
		Log.error(Log.Category.GAME, "보스 레인 스폰 셀이 없음")
		return

	var spawn_cell: Vector2i = SimRandom.pick(rng, spawn_cells)
	var spawn_pos := Vector2(spawn_cell) + Vector2(0.5, 0.5)
	var slot_info := _allocate_slot(spawn_pos)
	var slot: Vector2 = slot_info.pos

	var monster := Monster.new()
	monster.apply_look(data)
	monster.events = events
	monster.fx_lane_id = GameField.BOSS_LANE_ID
	monster.owner_id = owner_id
	monster.kind_id = kind_id
	monster.max_hp = Monsters.max_hp(kind_id)  # setup()이 hp를 가득 채운다
	monster.slot_key = slot_info.key
	monster.dps = Monsters.dps(kind_id)
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
	monster.died.connect(_on_sent_monster_died)
	_renderer.add_child(monster)
	_sent_monsters.append(monster)
	sent_count += 1
	Log.info(Log.Category.GAME, "[P%d] %s 파견 (보스 레인 몬스터#%d, 목표 자리 %s)" % [
		owner_id + 1, data.name, _next_monster_id, slot.snapped(Vector2(0.01, 0.01))])
	_next_monster_id += 1


## 보스 주변 빈 자리를 하나 예약한다. 안쪽 고리부터 채우고, 가득 차면 바깥 고리로 넓어진다.
## 같은 고리 안에서는 몬스터가 오는 방향과 가장 가까운 자리를 고른다.
## 돌려주는 값: {pos: 자리 좌표, key: 자리 이름}. 몬스터가 죽으면 key로 자리를 비운다 (안전장치 자리는 key가 "").
func _allocate_slot(approach_from: Vector2) -> Dictionary:
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
			var key := "%d:%d" % [ring_idx, best_j]
			_slots_taken[key] = true
			return {"pos": best_pos, "key": key}

	# 극단적으로 많을 때의 안전장치
	return {"pos": Balance.BOSS_CENTER + Vector2(0, first_radius), "key": ""}


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


## 보스 레인 몬스터가 죽었다 (보스 스킬 처단, 앞으로는 PvP에서 상대 타워에게 맞아서 등)
func _on_sent_monster_died(monster: Monster) -> void:
	_attackers.erase(monster)
	_sent_monsters.erase(monster)
	if monster.slot_key != "":
		_slots_taken.erase(monster.slot_key)  # 비운 자리는 다음에 오는 몬스터가 쓴다
	events.ring(GameField.BOSS_LANE_ID, monster.cell_pos, 0.6, monster.body_color)
	Log.info(Log.Category.GAME, "[P%d] 보스 레인 몬스터#%d(%s) 사망 (공격 중 %d마리 남음)" % [
		monster.owner_id + 1, monster.monster_id, monster.kind_id, _attackers.size()])
	monster.queue_free()
	_recalc_dps()


# --- 발동형 보스 스킬 (체력 조건 / 주기) ---

## 조건이 되면 예고를 시작하고, 예고 시간이 끝나면 발동한다
func _update_skills(delta: float) -> void:
	var ratio := hp / max_hp
	var new_phase := _phase_for_ratio(ratio)
	if new_phase > _phase:  # 페이즈는 앞으로만 간다 (체력은 줄기만 한다)
		_enter_phase(new_phase)
	for entry in _triggered:
		var skill: Dictionary = entry.skill
		if skill.trigger == "hp_below":
			var ratios: Array = skill.hp_ratios
			for i in range(ratios.size()):
				if not entry.fired[i] and ratio <= float(ratios[i]):
					entry.fired[i] = true
					_cast_skill(skill)
		elif skill.trigger == "every":
			entry.timer -= delta
			if entry.timer <= 0.0:
				entry.timer = float(skill.period)
				_cast_skill(skill)
	for i in range(_pending_casts.size() - 1, -1, -1):
		var cast: Dictionary = _pending_casts[i]
		cast.left -= delta
		if cast.left <= 0.0:
			_pending_casts.remove_at(i)
			_resolve_skill(cast)


## 스킬 예고: 대상을 정해서 표식을 붙이고, 어떤 몬스터가 어떻게 되는지 배너로 알린다
func _cast_skill(skill: Dictionary) -> void:
	var targets: Array = []
	var cells := {}       # 분열: 레인 -> 새끼가 나올 칸 (예고 때 정해서 그 칸에 표식을 띄우고, 발동 때 그대로 쓴다)
	var warnings: Array = []  # 분열: 그 칸에 띄운 표식 노드
	var text: String = skill.text
	var warn := Color(0, 0, 0, 0)
	match skill.effect:
		"execute":
			targets = _top_dps_attackers(1)
			warn = Color(1.0, 0.15, 0.15)
			if targets.is_empty():
				text = "처단할 몬스터가 없습니다. 환영만 나타납니다."
			else:
				var victim: Monster = targets[0]
				text = "DPS 1위 %s(P%d)가 제거됩니다 (비용의 %d%% 환급). 동시에 각 레인에 환영이 나타납니다." % [
					Monsters.DATA[victim.kind_id].name, victim.owner_id + 1, roundi(float(skill.refund) * 100.0)]
		"dread":
			targets = _top_dps_attackers(int(skill.count))
			if targets.is_empty():
				return  # 아직 보스 앞에 아무도 없다
			warn = Color(0.75, 0.35, 0.95)
			var names: Array[String] = []
			for target in targets:
				names.append(Monsters.DATA[target.kind_id].name)
			text = "DPS 상위 %d마리(%s)의 DPS가 %.0f초간 0이 됩니다." % [targets.size(), ", ".join(names), float(skill.duration)]
		"split":
			text = "슬라임 대장이 분열합니다! 표시된 칸에 슬라임 새끼 %d마리가 나타나 벽 타워를 갉습니다 (트랩 타워는 못 봅니다)." % int(skill.count)
			for lane in _lanes.values():
				var spawn_cell: Vector2i = lane.pick_spawn_cell()
				cells[lane] = spawn_cell
				if spawn_cell != Pathfinder.NO_GOAL:
					warnings.append(_add_spawn_warning(lane, spawn_cell, float(skill.get("delay", 0.0))))
		"seal":
			for lane in _lanes.values():
				if not lane.active:
					continue
				var by_damage: Array = lane.towers.duplicate()
				by_damage.sort_custom(func(a: Tower, b: Tower): return a.total_damage > b.total_damage)
				targets.append_array(by_damage.slice(0, int(skill.count)))
			if targets.is_empty():
				return  # 봉인할 타워가 없다
			warn = Color(0.75, 0.35, 0.95)
			text = "각 레인의 누적 피해 상위 타워 %d기(총 %d기)가 %.0f초간 사격하지 못합니다." % [int(skill.count), targets.size(), float(skill.duration)]
	for target in targets:
		target.set_warn(warn)
	var delay := float(skill.get("delay", 0.0))
	_pending_casts.append({"skill": skill, "left": delay, "targets": targets, "cells": cells, "warnings": warnings})
	skill_announced.emit({"name": skill.name, "text": text, "lane": skill.lane, "delay": delay, "boss": level_data.name})
	Log.info(Log.Category.GAME, "보스 스킬 예고: %s (%.0f초 뒤, 대상 %d마리)" % [skill.name, delay, targets.size()])


## 예고가 끝났다: 아직 살아서 보스 앞에 있는 대상에게만 효과를 준다
func _resolve_skill(cast: Dictionary) -> void:
	var skill: Dictionary = cast.skill
	var victims: Array = []
	for warning in cast.warnings:  # 예고 표식은 발동과 함께 사라진다
		if is_instance_valid(warning):
			warning.queue_free()
	for target in cast.targets:
		if not is_instance_valid(target):  # 예고 중에 죽거나 부서져서 해제됐다
			continue
		target.clear_warn()
		if skill.effect == "seal":
			if target.lane.towers.has(target):
				victims.append(target)
		elif not target.is_dead() and _attackers.has(target):
			victims.append(target)
	match skill.effect:
		"seal":
			for victim in victims:
				victim.sealed_time = float(skill.duration)
				events.ring(victim.lane.player_id, victim.center_cell_pos(), 0.9, Color(0.75, 0.35, 0.95))
		"split":
			_spawn_slimelings(skill, cast.cells)
		"execute":
			for victim in victims:
				_execute_attacker(victim, float(skill.refund))
			_spawn_phantoms(skill)
		"dread":
			for victim in victims:
				victim.dread_time = float(skill.duration)
				events.ring(GameField.BOSS_LANE_ID, victim.cell_pos, 0.8, Color(0.75, 0.35, 0.95))
			_recalc_dps()
	Log.info(Log.Category.GAME, "보스 스킬 발동: %s (대상 %d마리)" % [skill.name, victims.size()])


## 보스 앞에서 싸우는 몬스터 중 지금 DPS가 높은 순서로 최대 count마리 (DPS 0인 지원형은 제외)
func _top_dps_attackers(count: int) -> Array:
	var list: Array = []
	for m in _attackers:
		if m.current_dps > 0.0 and not m.is_dead():
			list.append(m)
	list.sort_custom(func(a: Monster, b: Monster): return a.current_dps > b.current_dps)
	return list.slice(0, count)


## 처단: 몬스터를 제거하고 비용의 일부를 주인에게 돌려준다
func _execute_attacker(monster: Monster, refund_ratio: float) -> void:
	var cost := int(Monsters.DATA[monster.kind_id].cost)
	var refund := roundi(float(cost) * refund_ratio)
	var lane: LaneController = _lanes.get(monster.owner_id)
	if lane != null and lane.active and refund > 0:
		lane.gold += refund
	events.ring(GameField.BOSS_LANE_ID, monster.cell_pos, 1.0, Color(1.0, 0.2, 0.2))
	events.text(GameField.BOSS_LANE_ID, monster.cell_pos, "처단! +%d골드" % refund, Color(1.0, 0.5, 0.4))
	Log.info(Log.Category.ECONOMY, "[P%d] %s 처단됨: 환급 +%d골드 (비용 %d)" % [monster.owner_id + 1, monster.kind_id, refund, cost])
	monster.execute(null)  # 죽음 처리(자리 비우기, DPS 다시 계산)는 died 시그널을 받는 쪽이 한다


## 환영: 모든 참여 레인에 중장갑 몬스터를 보낸다
func _spawn_phantoms(skill: Dictionary) -> void:
	for lane in _lanes.values():
		for i in range(int(skill.get("phantoms", 1))):
			lane.spawn_wave_monster("tank", level, lane.pick_spawn_cell())


## 분열: 모든 참여 레인의, 예고 때 정해 둔 칸(cells)에서 슬라임 새끼가 촘촘히 연달아 나온다 (웨이브와 같은 방식)
func _spawn_slimelings(skill: Dictionary, cells: Dictionary) -> void:
	var wave_type: Dictionary = Monsters.DATA["slimeling"]
	var serial := _wave_serial
	for lane in _lanes.values():
		var cell: Vector2i = cells.get(lane, Pathfinder.NO_GOAL)
		if cell != Pathfinder.NO_GOAL:
			events.ring(lane.player_id, Vector2(cell) + Vector2(0.5, 0.5), 1.0, wave_type.color)
	for i in range(int(skill.count)):
		if i > 0:
			await get_tree().create_timer(Balance.WAVE_SPAWN_GAP, false).timeout  # false: 일시정지 중에는 멈춘다
			if state != State.RUNNING or serial != _wave_serial:  # 유령 구간이 되면 남은 새끼는 더 나오지 않는다
				return
		for lane in _lanes.values():
			lane.spawn_wave_monster("slimeling", level, cells.get(lane, Pathfinder.NO_GOAL))


## 새끼가 나올 칸에 예고 표식을 띄운다 (그 레인을 보고 있을 때만 보인다). seconds 뒤에 저절로 사라진다.
func _add_spawn_warning(lane: LaneController, cell: Vector2i, seconds: float) -> SpawnWarning:
	var warning := SpawnWarning.new()
	warning.lane = lane
	warning.renderer = _renderer
	warning.cell = cell
	warning.total = maxf(seconds, 0.1)
	warning.left = warning.total
	warning.z_index = 3
	warning.visible = lane.lane_visible
	_renderer.add_child(warning)
	return warning


## 예고만 하고 발동하지 못한 스킬을 취소한다 (표식도 지운다)
func _clear_pending_casts() -> void:
	for cast in _pending_casts:
		for target in cast.targets:
			if is_instance_valid(target):
				target.clear_warn()
		for warning in cast.warnings:
			if is_instance_valid(warning):
				warning.queue_free()
	_pending_casts.clear()


## 동상: 이 라운드에서 보스 앞에 선 시간에 따라 dps가 줄어드는 비율
func _chill_of(monster: Monster) -> float:
	if _chill_max <= 0.0:
		return 0.0
	var span := maxf(_chill_full - _chill_start, 0.001)
	return _chill_max * clampf((monster.chill_time - _chill_start) / span, 0.0, 1.0)


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
	_clear_pending_casts()
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

	## 유령 구간: 죽은 보스 자리에 보스 몸통과 같은 크기(BOSS_RADIUS)의 큰 유령이 선다. 보스 앞의 몬스터들이 이 유령을 때린다.
	func _draw_ghost() -> void:
		var cell: float = renderer.CELL_SIZE
		var R: float = Balance.BOSS_RADIUS * cell
		var pressure := minf(1.0, boss.total_dps / 12.0)
		var shake := Vector2(randf_range(-1.0, 1.0), randf_range(-1.0, 1.0)) * cell * 0.04 * pressure  # 맞을수록 몸을 떤다
		var c: Vector2 = Balance.BOSS_CENTER * cell + Vector2(0.0, sin(_t * 2.0) * R * 0.06) + shake
		draw_circle(c, R * 1.3, Color(GhostArt.BODY, 0.10 + 0.06 * sin(_t * 3.0)))  # 기운
		GhostArt.draw_ghost(self, c, R, _t)  # 플레이어 레인의 유령과 똑같은 그림을 보스 크기로
		if boss.level_flash > 0.0:
			draw_circle(c, R * 1.3, Color(1, 1, 1, 0.6 * boss.level_flash))

	func _draw() -> void:
		if boss.level_data.is_empty():
			return
		if boss.in_ghost_phase:
			_draw_ghost()
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


## 보스 체력바 + 이름 + 플레이어 기여도. 몬스터들이 보스 위쪽에 몰려 서도 가려지지 않게 몬스터(z_index 2)보다 위에 그린다.
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
		if boss.in_ghost_phase:  # 보스 체력 대신 유령 구간이 끝날 때까지 남은 시간을 보여 준다
			var left_ratio := clampf(boss.time_left / maxf(boss.ghost_length, 0.001), 0.0, 1.0)
			draw_rect(Rect2(c.x - bar_w * 0.5 - 3, bar_y - 20, bar_w + 6, 36), Color(0, 0, 0, 0.8))
			draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w, 10), Color(0.1, 0.12, 0.25))
			draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w * left_ratio, 10), Color(0.6, 0.7, 1.0))
			draw_string(ThemeDB.fallback_font, Vector2(c.x - bar_w * 0.5, bar_y - 6), "Lv.%d 처치!  유령 구간 %d초" % [
				boss.level, ceili(boss.time_left)], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.85, 0.9, 1.0))
			_draw_contribution(c, R, cell)
			return
		var ratio := clampf(boss.hp / boss.max_hp, 0.0, 1.0)
		draw_rect(Rect2(c.x - bar_w * 0.5 - 3, bar_y - 20, bar_w + 6, 36), Color(0, 0, 0, 0.8))
		draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w, 10), Color(0.25, 0.05, 0.05))
		draw_rect(Rect2(c.x - bar_w * 0.5, bar_y, bar_w * ratio, 10), Color(0.9, 0.15, 0.15))
		# 페이즈가 있는 보스는 단계가 바뀌는 체력 위치에 흰 눈금을 그린다
		var phases := BossSkills.phases_of(boss.level)
		for i in range(1, phases.size()):
			var tick_x: float = c.x - bar_w * 0.5 + bar_w * float(phases[i].from)
			draw_line(Vector2(tick_x, bar_y - 2.0), Vector2(tick_x, bar_y + 12.0), Color(1, 1, 1, 0.9), 2.0)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(c.x - bar_w * 0.5, bar_y - 6), "Lv.%d %s   %d / %d" % [
			boss.level, boss.level_data.name, int(boss.hp), int(boss.max_hp)],
			HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color.WHITE)

		# 플레이어 기여도 표시 (보스 오른쪽에 세로로 나열)
		_draw_contribution(c, R, cell)

	func _draw_contribution(c: Vector2, R: float, _cell: float) -> void:
		# 전체 피해 계산 (유령 구간에는 보스 레인 유령에게 준 피해를 보여 준다)
		var source: Dictionary = boss.ghost_boss_damage_by_player if boss.in_ghost_phase else boss.damage_by_player
		var total_dmg := 0.0
		for dmg in source.values():
			total_dmg += dmg

		if total_dmg <= 0.0:
			return

		# 플레이어별 기여도 정렬 (내림차순)
		var entries: Array = []
		for player_id in source:
			var dmg: float = source[player_id]
			entries.append({"player_id": player_id, "damage": dmg, "percent": dmg / total_dmg * 100.0})
		entries.sort_custom(func(a, b): return a.damage > b.damage)

		# 보스 오른쪽에 표시
		var font := ThemeDB.fallback_font
		var start_x := c.x + R * 1.6
		var start_y := c.y - R * 1.5
		var line_h := 16.0

		# 제목
		draw_string(font, Vector2(start_x, start_y), "유령 피해 (보스 레인)" if boss.in_ghost_phase else "플레이어 기여도",
			HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.8, 0.9, 1.0))
		start_y += line_h

		# 각 플레이어
		for entry in entries:
			var color := Color(1.0, 0.95, 0.6) if entry.player_id == 0 else Color(0.85, 0.85, 0.85)
			var text := "P%d: %.1f%% (%s)" % [entry.player_id + 1, entry.percent, _format_damage(entry.damage)]
			draw_string(font, Vector2(start_x, start_y), text, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, color)
			start_y += line_h

	func _format_damage(dmg: float) -> String:
		if dmg >= 1000000.0:
			return "%.1fM" % (dmg / 1000000.0)
		elif dmg >= 1000.0:
			return "%.1fK" % (dmg / 1000.0)
		else:
			return "%d" % int(dmg)


## 슬라임 새끼가 나올 칸의 예고 표식. 예고 시간 동안 바깥 고리가 칸 쪽으로 오므라들어서 "곧 나온다"는 걸 보여 준다.
## 그 레인을 보고 있을 때만 보이고, 시간이 다 되면 저절로 사라진다 (발동 때 BossController가 먼저 치우기도 한다).
class SpawnWarning extends Node2D:
	var lane: LaneController
	var renderer: GridRenderer
	var cell: Vector2i
	var color := Color(0.35, 0.9, 0.4)
	var total := 3.0   # 예고 시간
	var left := 3.0    # 남은 시간

	func _process(delta: float) -> void:
		left -= delta
		if left <= 0.0:
			queue_free()
			return
		visible = lane.lane_visible
		position = (Vector2(cell) + Vector2(0.5, 0.5)) * float(renderer.CELL_SIZE)
		queue_redraw()

	func _draw() -> void:
		var px := float(renderer.CELL_SIZE)
		var progress := 1.0 - clampf(left / total, 0.0, 1.0)  # 0 = 방금 예고, 1 = 곧 나온다
		var ring_r := lerpf(1.6, 0.5, progress) * px
		draw_arc(Vector2.ZERO, ring_r, 0.0, TAU, 32, Color(color, 0.9), 3.0)
		var pulse := 0.3 + 0.25 * sin(progress * 30.0)
		draw_circle(Vector2.ZERO, 0.45 * px, Color(color, pulse))
		draw_arc(Vector2.ZERO, 0.45 * px, 0.0, TAU, 20, Color(1, 1, 1, 0.85), 2.0)
