extends "res://tests/case_base.gd"
## 이슈 #18 공중 몬스터 위협 회귀 테스트.
## 대공 타워를 난사형으로 진화해서 업그레이드를 올려도 공중 웨이브(공습)가 쉽게 막히지 않는지, 그렇다고 돈을 다 써도 못 막을 만큼
## 어렵지도 않은지, 대공 타워는 지상을 못 때리고 지상 타워는 공중을 못 때리는 제한이 그대로인지 본다.
## 몬스터 체력/타워 수치를 하드코딩하지 않고 데이터(Monsters, Balance, Evolutions, BossLevels)에서 계산한다.
##
## 측정 방식 (PR 본문의 측정과 같다): 보스 Lv.8의 공습 웨이브(BossController가 실제로 계획한 것)를 대공 타워가 있는 레인에 보내고,
## 기지에 닿은 공중 몬스터 수/잃은 생명을 센다. 대공 타워는 두 줄로 모아 짓는다 (x=2~3, x=8~9, y=42~). 타워 색 보너스는 쓰지 않는다.
## 돈은 전부 공중 방어에 쓴다고 보고, 항목은 비용 대비 효과가 큰 것부터 올린다 (_plan_levels).
## 시뮬레이션은 무작위(웨이브 구성, 난사/연발 굴림)가 있어서 기준을 넉넉히 잡는다.

const STATS := ["A.chance", "A.second", "B.missiles", "B.power"]
const TRIALS := 2
const LEVEL := 8                     # 공습 웨이브가 처음 나오는 보스 라운드
const GENEROUS_INCOME_MULT := 10.0   # "수입이 기본의 10배"를 넉넉한 경제로 본다 (최대 업그레이드 합계는 이보다 훨씬 비싸서 한 판 안에 못 산다)
const FEW_TOWERS := 8
const MANY_TOWERS := 24
const SIM_TIME_SCALE := 8.0
const WAVE_TIMEOUT := 200.0          # 웨이브가 끝나기를 기다리는 최대 게임 시간(초)
const BIG_LIVES := 100000.0          # 시뮬레이션 중 패배하지 않게 생명을 크게 잡고, 잃은 생명은 몬스터의 life로 센다

var game
var gf: GameField
var lane: LaneController


func run() -> void:
	seed(18)
	_data_checks()
	await _restrictions()
	# 체크 1: 최대 업그레이드 + 타워 몇 기로도 공습이 쉽게 안 막힌다
	var maxed := await _scenario("max", FEW_TOWERS)
	check(maxed.leaked >= TRIALS, "최대 업그레이드(전 항목 Lv%d) 난사형 %d기도 공습 웨이브를 다 막지 못한다 (%d회 평균 %.1f마리가 기지에 닿음)" % [
		Evolutions.MAX_LEVEL, FEW_TOWERS, TRIALS, float(maxed.leaked) / TRIALS])
	# 체크 2: 현실적인(넉넉한) 돈을 전부 공중 방어에 써도 공습은 생명을 깎는다
	var rich := await _scenario("rich", FEW_TOWERS)
	check(rich.lives >= TRIALS, "넉넉한 수입(x%.0f)을 전부 쓴 난사형 %d기도 공습에 생명을 잃는다 (평균 -%.1f)" % [
		GENEROUS_INCOME_MULT, FEW_TOWERS, float(rich.lives) / TRIALS])
	# 너무 어렵지도 않다: 같은 돈으로 타워를 많이 지으면 공습 한 번에 시작 생명을 다 잃지는 않는다
	var many := await _scenario("rich", MANY_TOWERS)
	check(float(many.lives) / TRIALS < float(Balance.START_LIVES), "넉넉한 수입으로 대공 타워를 %d기 지으면 공습 한 번에 시작 생명(%d)을 다 잃지는 않는다 (평균 -%.1f)" % [
		MANY_TOWERS, Balance.START_LIVES, float(many.lives) / TRIALS])
	Engine.time_scale = 1.0


# --- 데이터 확인 ---

func _data_checks() -> void:
	# 체크 4: 공중 몬스터 툴팁/상성 설명 (공중 전용 새 종류를 만들었다면 여기 걸린다)
	var tip_ok := true
	var air_ids := []
	for id in Monsters.DATA:
		if bool(Monsters.DATA[id].get("flying", false)):
			air_ids.append(id)
			var tip := Monsters.tooltip(id)
			if not (tip.contains("공중") or tip.contains("비행")):
				tip_ok = false
				print("  (공중 몬스터 툴팁에 공중/대공 안내가 없음: %s)" % tip.replace("\n", " / "))
	check(air_ids.size() >= 3 and tip_ok, "공중 몬스터 %d종 툴팁에 공중/비행 안내가 있다" % air_ids.size())
	var src := FileAccess.get_file_as_string("res://scripts/data/Monsters.gd")
	check(src.contains("공중(flyer/flock/bomber)"), "Monsters.gd 상성 요약에 공중 몬스터 줄이 있다")
	# 공중 종류는 전부 공중형 유형이고 공습 후보에 들어간다 (Lv.8: 후보가 비지 않는다)
	var all_air_category := air_ids.all(func(id): return Monsters.DATA[id].category == "air")
	check(all_air_category, "flying 몬스터는 전부 공중형(air) 유형이다")
	check(not Monsters.candidates(LEVEL, true).is_empty(), "Lv.%d 공습 웨이브 후보가 있다" % LEVEL)
	# 체크 5(데이터): 대공만 공중을 때리고, 대공은 지상을 때리지 않는다
	for kind_id in Balance.TOWER_KINDS:
		check(bool(Balance.TOWER_DEFS[kind_id].anti_air) == (kind_id == "air"), "%s 타워의 anti_air는 대공만 true다" % kind_id)


# --- 체크 5: 대공 타워는 지상을 못 때린다 (실제 조준) ---

func _restrictions() -> void:
	await _new_game()
	var tower := _build_air_tower(Vector2i(5, 20))
	check(tower != null, "대공 타워를 지었다")
	var center := tower.center_cell_pos()
	var ground_pos := Vector2(5.5, 20.5)
	var fly_pos := Vector2(5.5, 21.5)
	lane.spawn_wave_monster("grunt", 1, Vector2i(5, 0))
	lane.spawn_wave_monster("flyer", 1, Vector2i(5, 0))
	await frames(2)
	var grunt: Monster = null
	var flyer: Monster = null
	for m in lane.monsters:
		if m.kind_id == "grunt":
			grunt = m
		elif m.kind_id == "flyer":
			flyer = m
	check(grunt != null and flyer != null, "지상(일반)과 공중(비행) 몬스터를 하나씩 내보냈다")
	# 둘을 타워 바로 옆에 세워서 조준만 본다
	grunt.cell_pos = ground_pos
	flyer.cell_pos = fly_pos
	check(lane.find_target(center, tower.cur_range(), true) == flyer, "대공 타워는 공중 몬스터만 조준한다")
	check(lane.find_target(center, tower.cur_range(), false) == grunt, "지상 타워는 지상 몬스터만 조준한다")
	flyer.cell_pos = Vector2(5.5, 0.5)
	check(lane.find_target(center, tower.cur_range(), true) == null, "대공 타워는 사거리 안에 지상 몬스터만 있으면 조준하지 않는다")
	flyer.cell_pos = fly_pos
	grunt.cell_pos = Vector2(5.5, 0.5)
	check(lane.find_target(center, tower.cur_range(), false) == null, "지상 타워는 사거리 안에 공중 몬스터만 있으면 조준하지 않는다")
	# 실제로 쏘는지: 지상 몬스터만 사거리 안에 두고 몇 초 지나도 체력이 그대로다
	lane.monsters.erase(flyer)
	flyer.queue_free()
	grunt.cell_pos = ground_pos
	grunt.speed = 0.0
	var hp0 := grunt.hp
	Engine.time_scale = SIM_TIME_SCALE
	var t := 0.0
	while t < 4.0:
		await get_tree().process_frame
		t += get_process_delta_time()
		grunt.cell_pos = ground_pos
	Engine.time_scale = 1.0
	check(grunt.hp == hp0, "대공 타워가 4초 동안 사거리 안의 지상 몬스터를 못 때렸다 (체력 %s)" % grunt.hp)
	await _free_game()


# --- 시뮬레이션 ---

## 한 시나리오를 TRIALS번 돌려서 합계를 돌려준다. kind: "max"(전 항목 최대) / "rich"(넉넉한 수입을 다 쓴 업그레이드)
func _scenario(kind: String, max_towers: int) -> Dictionary:
	var sum := {"leaked": 0, "lives": 0, "spawned": 0}
	for i in range(TRIALS):
		await _new_game()
		var levels := {}
		var n := max_towers
		if kind == "max":
			for s in STATS:
				levels[s] = Evolutions.MAX_LEVEL
		else:
			var per_tower := Balance.TOWER_DEFS.air.cost + Balance.EVOLVE_COST + Balance.SKILL_LEARN_COST
			var gold := _rich_gold(LEVEL)
			n = clampi(int(gold / float(per_tower)), 1, max_towers)
			levels = _plan_levels(gold - float(n * per_tower))
		for s in STATS:
			var kv: PackedStringArray = s.split(".")
			lane.stat_levels["barrage.%s.%s" % [kv[0], kv[1]]] = levels[s]
		for k in range(n):
			var cell := Vector2i((2 if k % 2 == 0 else 8) + (k / 2) % 2, 42 + k / 4)
			var tower := _build_air_tower(cell)
			if tower != null:
				lane.evolve_tower(tower, "barrage")
				lane.learn_tower_skill(tower)
		var wave := _air_raid_wave()
		var res: Dictionary = await _run_wave(wave)
		sum.leaked += int(res.leaked)
		sum.lives += int(res.lives)
		sum.spawned += int(res.spawned)
		print("  [%s %d기 Lv%s -> 공습 %d마리 중 %d마리 도달, 생명 -%d (%s)]" % [
			kind, n, str(levels.values()), res.spawned, res.leaked, res.lives, str(res.by_kind)])
		await _free_game()
	return sum


func _new_game() -> void:
	game = load("res://scenes/main/MainGame.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)  # _ready 안에서 직접 add_child하면 "busy setting up children" 오류
	await frames(8)
	gf = game.game_field
	lane = gf.lanes[gf.session.local_player_id]
	lane.gold = 1.0e9
	lane.lives = BIG_LIVES


func _free_game() -> void:
	game.queue_free()
	await frames(4)


func _build_air_tower(cell: Vector2i) -> Tower:
	gf.set_tower_kind("air")
	if not gf.place_tower(cell, true):
		return null
	for t in lane.towers:
		if t.cell == cell:
			return t
	return null


## 보스가 Lv.LEVEL 공습 웨이브를 실제로 계획하게 해서 그 구성을 받는다 (BossController._plan_next_wave: 수입 안에서 가중치 랜덤)
func _air_raid_wave() -> Array:
	var boss: BossController = gf.boss
	boss.level = LEVEL
	boss.level_data = BossLevels.get_level(LEVEL)
	boss._level_wave_no = 1  # 다음이 2번째 웨이브: 공습은 2웨이브마다
	boss._plan_next_wave()
	check(boss._next_affix == "airraid", "Lv.%d 2번째 웨이브는 공습이다" % LEVEL)
	return boss._next_wave.duplicate(true)


## 한 웨이브를 BossController._dispatch_wave처럼 (묶음 사이 WAVE_GROUP_GAP, 같은 묶음은 WAVE_SPAWN_GAP) 내보내고 끝날 때까지 기다린다.
func _run_wave(wave: Array) -> Dictionary:
	var res := {"spawned": 0, "leaked": 0, "lives": 0, "by_kind": {}}
	var queue := []
	var first := true
	for e in wave:
		for i in range(int(e.count)):
			var gap := 0.0
			if not first:
				gap = Balance.WAVE_SPAWN_GAP if i > 0 else Balance.WAVE_GROUP_GAP
			first = false
			queue.append({"gap": gap, "type": e.type})
	Engine.time_scale = SIM_TIME_SCALE
	var timer := 0.0
	var elapsed := 0.0
	var idx := 0
	while elapsed < WAVE_TIMEOUT:
		await get_tree().process_frame
		var d := minf(get_process_delta_time(), 0.25)
		elapsed += d
		timer += d
		while idx < queue.size() and timer >= float(queue[idx].gap):
			timer -= float(queue[idx].gap)
			var type: String = queue[idx].type
			var before: int = lane.monsters.size()
			lane.spawn_wave_monster(type, LEVEL)
			if lane.monsters.size() > before:
				var m: Monster = lane.monsters[lane.monsters.size() - 1]
				m.reached_exit.connect(func(_mm):
					res.leaked += 1
					res.lives += int(Monsters.DATA[type].get("life", 1))
					res.by_kind[type] = int(res.by_kind.get(type, 0)) + 1)
			res.spawned += 1
			idx += 1
		if idx >= queue.size() and lane.monsters.is_empty():
			break
	Engine.time_scale = 1.0
	check(idx >= queue.size() and lane.monsters.is_empty(), "공습 웨이브가 시간 안에 끝났다 (게임 시간 %.0f초)" % elapsed)
	return res


## "넉넉한 수입"으로 Lv.level 한가운데까지 모은 골드: 시작 골드 + (기본 수입 x 배수) x 지난 수입 틱 수
func _rich_gold(level: int) -> float:
	var t := 0.0
	for i in range(1, level):
		t += float(BossLevels.get_level(i).time)
	t += float(BossLevels.get_level(level).time) * 0.5
	return float(Balance.START_GOLD) + GENEROUS_INCOME_MULT * float(Balance.BASE_INCOME) * t / Balance.INCOME_INTERVAL


## 난사형 한 타워의 위력 배율 (미사일 수 x 미사일 위력 x (1 + 연발 확률 x 연발 위력))
func _factor(lv: Dictionary) -> float:
	return Evolutions.p("barrage", "B", "missiles", lv["B.missiles"]) * Evolutions.p("barrage", "B", "power", lv["B.power"]) \
		* (1.0 + Evolutions.p("barrage", "A", "chance", lv["A.chance"]) * Evolutions.p("barrage", "A", "second", lv["A.second"]))


## 골드로 올릴 수 있는 만큼, 비용 대비 위력이 가장 많이 느는 항목부터 올린다
func _plan_levels(gold_left: float) -> Dictionary:
	var lv := {}
	for s in STATS:
		lv[s] = 1
	while true:
		var best := ""
		var best_score := 0.0
		for s in STATS:
			if lv[s] >= Evolutions.MAX_LEVEL:
				continue
			var cost := float(Balance.stat_upgrade_cost_for(lv[s] + 1))
			if cost > gold_left:
				continue
			var cur := _factor(lv)
			lv[s] += 1
			var nxt := _factor(lv)
			lv[s] -= 1
			var score := (nxt / cur - 1.0) / cost
			if score > best_score:
				best_score = score
				best = s
		if best == "":
			break
		gold_left -= float(Balance.stat_upgrade_cost_for(lv[best] + 1))
		lv[best] += 1
	return lv
