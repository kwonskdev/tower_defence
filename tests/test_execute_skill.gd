extends "res://tests/case_base.gd"
## 이슈 #13 처형(장거리 보스형 B 스킬) 회귀 테스트.
## 처형은 기준 체력 아래인 몬스터에게 몬스터당 Evolutions.EXECUTE_COOLDOWN초에 한 번만 굴린다 (타워 수/명중 횟수와 무관).
## 투사체의 _hit()를 직접 불러서 판정만 검사한다 (날아가는 시간에 흔들리지 않게).

var game
var gf: GameField
var lane: LaneController
var proj: Effects.Projectile


func run() -> void:
	game = load("res://scenes/main/MainGame.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)  # _ready 안에서 직접 add_child하면 "busy setting up children" 오류
	await frames(8)
	gf = game.game_field
	lane = gf.lanes[0]
	check(gf.boss != null and lane != null, "게임이 떴다 (레인/보스 있음)")

	proj = Effects.Projectile.new()
	proj.renderer = gf.grid_renderer
	proj.lane = lane

	_cooldown_gates_rolls()
	_same_monster_many_hits()
	_threshold_and_ghost()
	_statistics()
	_boss_skill_execute_unaffected()
	_numbers_and_text()

	proj.free()
	game.queue_free()
	await frames(3)


# --- 도우미 ---

## 체력이 가득 찬 몬스터 하나 (처형 판정만 보므로 위치는 상관없다). 체력은 큰 값으로 고정해서 맞아도 안 죽게 한다.
func _monster(type_id := "grunt") -> Monster:
	lane.spawn_wave_monster(type_id, 1, Vector2i(5, 0))
	var m: Monster = lane.monsters.back()
	m._base_max_hp = 1.0e9
	m.max_hp = 1.0e9
	m.hp = 1.0e9
	return m


func _drop(m: Monster) -> void:
	lane.monsters.erase(m)
	if is_instance_valid(m):
		m.queue_free()


## 처형 효과(chance/hp)를 담아 monster를 한 번 맞힌다 (피해 0이라 순수하게 처형 판정만)
func _hit(m: Monster, chance: float, hp_ratio: float) -> void:
	proj.fx = {"execute": {"chance": chance, "hp": hp_ratio}}
	proj._hit(m, 0.0)


# --- 시나리오 ---

## 쿨타임 안에는 확률이 1.0이어도 다시 굴리지 않고, 쿨타임이 지나면 다시 굴린다
func _cooldown_gates_rolls() -> void:
	print("[1] 쿨타임: 굴린 뒤 EXECUTE_COOLDOWN 동안은 판정 없음")
	var cd := Evolutions.EXECUTE_COOLDOWN
	check(cd > 0.0, "EXECUTE_COOLDOWN > 0 (%s)" % cd)
	var m := _monster()
	check(m.execute_cd == 0.0, "처음에는 쿨타임 0")
	_hit(m, 0.0, 1.0)  # 기준 안 + 확률 0: 굴리기만 하고 안 죽는다
	check(not m.is_dead(), "확률 0이면 안 죽는다")
	near(m.execute_cd, cd, "굴린 뒤 쿨타임이 EXECUTE_COOLDOWN으로")
	_hit(m, 1.0, 1.0)  # 확률 100%지만 쿨타임 중
	check(not m.is_dead(), "쿨타임 중에는 확률 100%여도 처형되지 않는다")
	m._update_status(cd + 0.01)
	near(m.execute_cd, 0.0, "시간이 지나면 쿨타임이 0으로")
	_hit(m, 1.0, 1.0)
	check(m.is_dead(), "쿨타임이 끝나면 다시 굴려서 처형된다")
	_drop(m)


## 체크리스트: 같은 몬스터에 여러 번(여러 타워가) 맞혀도 굴림은 쿨타임마다 한 번
func _same_monster_many_hits() -> void:
	print("[2] 같은 몬스터를 연달아 맞혀도 쿨타임이 다시 시작되지 않는다 (= 굴리지 않았다)")
	var cd := Evolutions.EXECUTE_COOLDOWN
	var m := _monster()
	_hit(m, 0.0, 1.0)  # 첫 굴림
	m._update_status(cd * 0.5)
	var left := m.execute_cd
	for i in range(30):  # 타워 여러 기가 같은 몬스터를 동시에 때리는 상황
		_hit(m, 0.0, 1.0)
	near(m.execute_cd, left, "30번 더 맞혀도 쿨타임이 그대로 (굴림 없음)")
	m._update_status(cd)
	_hit(m, 0.0, 1.0)
	near(m.execute_cd, cd, "쿨타임이 끝난 뒤 첫 명중에서만 다시 굴린다")
	_drop(m)


## 기준 체력 위에서는 굴리지 않고, 유령은 처형/쿨타임 대상이 아니다
func _threshold_and_ghost() -> void:
	print("[3] 기준 체력 위/유령")
	var m := _monster()
	m.hp = m.max_hp * 0.5
	_hit(m, 1.0, 0.1)  # 기준 10%인데 체력 50%
	check(not m.is_dead() and m.execute_cd == 0.0, "기준보다 체력이 많으면 굴리지 않는다 (쿨타임도 안 건드림)")
	m.hp = m.max_hp * 0.1  # 경계: 기준과 같으면 대상
	_hit(m, 1.0, 0.1)
	check(m.is_dead(), "체력이 기준과 같으면 처형 대상")
	_drop(m)

	var gid := ""
	for id in Monsters.DATA:
		if bool(Monsters.DATA[id].get("ghost", false)):
			gid = id
			break
	check(gid != "", "유령 몬스터 종류가 있다")
	var g := _monster(gid)
	g.hp = 0.0001
	_hit(g, 1.0, 1.0)
	check(not g.is_dead() and g.execute_cd == 0.0, "유령은 처형되지 않고 쿨타임도 없다")
	_drop(g)


## 확률 폭발 방지: 확률 50%인 처형을 한 몬스터에 10번 동시에 맞혀도 죽는 비율은 약 50% (예전 방식이면 99.9%)
func _statistics() -> void:
	print("[4] 통계: 10타워 동시 명중에도 처형 비율은 확률 근처")
	var trials := 100
	var dead := 0
	for i in range(trials):
		var m := _monster()
		for k in range(10):
			_hit(m, 0.5, 1.0)
		if m.is_dead():
			dead += 1
		_drop(m)
	var ratio := float(dead) / trials
	check(ratio > 0.25 and ratio < 0.75, "10번 맞혀도 처형 비율 %.2f (기대 약 0.5, 예전 방식은 약 1.0)" % ratio)


## 체크리스트: 보스 스킬 처단은 쿨타임과 무관하게 그대로 (Monster.execute를 직접 부른다)
func _boss_skill_execute_unaffected() -> void:
	print("[5] 보스 스킬 처단(Monster.execute)은 쿨타임과 무관")
	var m := _monster()
	m.execute_cd = 99.0
	m.execute(null)
	check(m.is_dead(), "execute_cd가 남아 있어도 처단으로는 죽는다")
	_drop(m)


## 수치/문구: 기준이 예전(최대 18%, 1레벨 8%)보다 낮고, 쿨타임이 설명에 나온다
func _numbers_and_text() -> void:
	print("[6] 수치와 설명 문구")
	var lv1 := Evolutions.p("boss", "B", "hp", 1)
	var lv_max := Evolutions.p("boss", "B", "hp", Evolutions.MAX_LEVEL)
	check(lv1 < 0.08, "1레벨 기준 %.3f < 예전 1레벨(0.08)" % lv1)
	check(lv_max < 0.18 and lv_max <= 0.06, "최대 레벨 기준 %.3f < 예전 최대(0.18), 6%% 이하" % lv_max)
	check(Evolutions.p("boss", "B", "chance", Evolutions.MAX_LEVEL) <= 0.08, "최대 레벨 확률은 8% 이하")
	check(lv1 < lv_max, "레벨이 오르면 기준도 오른다")
	var text := Evolutions.skill_text("boss", "B", 1)
	check(text.contains(Evolutions.fmt("sec", Evolutions.EXECUTE_COOLDOWN)), "설명에 판정 간격이 나온다: %s" % text)
	check(text.contains("몬스터당") and text.contains("처형"), "설명에 '몬스터당' 쿨타임 규칙이 나온다")
	check(not text.contains("초초"), "'초초' 중복 없음")
	check(text.contains(Evolutions.fmt("pct", lv1, Evolutions.stat_digits("boss", Evolutions.find_stat("boss", "B", "hp"))).replace(" ", "")), "설명의 기준 값이 PARAMS와 같다")
