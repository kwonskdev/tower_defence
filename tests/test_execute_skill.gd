extends "res://tests/case_base.gd"
## 이슈 #13 처형(장거리 보스형 B 스킬) 회귀 테스트.
## 처형은 명중마다, 기준 체력 아래인 몬스터에게 확률로 굴린다. 확률과 기준은 둘 다 1% -> 5.9% (Lv1~50)라 낮게 유지해 쉽게 안 터지게 한다.
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

	_threshold_and_ghost()
	_chance_per_hit()
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

## 기준 체력 위에서는 굴리지 않고, 경계(같음)는 대상이며, 유령은 처형되지 않는다
func _threshold_and_ghost() -> void:
	print("[1] 기준 체력 위/경계/유령")
	var m := _monster()
	m.hp = m.max_hp * 0.5
	_hit(m, 1.0, 0.1)  # 기준 10%인데 체력 50%
	check(not m.is_dead(), "기준보다 체력이 많으면 확률 100%여도 처형되지 않는다")
	m.hp = m.max_hp * 0.1  # 경계: 기준과 같으면 대상
	_hit(m, 1.0, 0.1)
	check(m.is_dead(), "체력이 기준과 같으면 처형 대상")
	_drop(m)
	var m2 := _monster()
	_hit(m2, 0.0, 1.0)
	check(not m2.is_dead(), "확률 0이면 기준 안이어도 안 죽는다")
	_drop(m2)

	var gid := ""
	for id in Monsters.DATA:
		if bool(Monsters.DATA[id].get("ghost", false)):
			gid = id
			break
	check(gid != "", "유령 몬스터 종류가 있다")
	var g := _monster(gid)
	g.hp = 0.0001
	_hit(g, 1.0, 1.0)
	check(not g.is_dead(), "유령은 처형되지 않는다")
	_drop(g)


## 한 번 맞을 때마다 확률대로 굴린다 (확률 50%로 400마리를 한 번씩 맞히면 약 절반이 죽는다)
func _chance_per_hit() -> void:
	print("[2] 명중당 확률 굴림")
	var trials := 400
	var dead := 0
	for i in range(trials):
		var m := _monster()
		_hit(m, 0.5, 1.0)
		if m.is_dead():
			dead += 1
		_drop(m)
	var ratio := float(dead) / trials
	check(ratio > 0.4 and ratio < 0.6, "확률 50%% 한 번씩: 처형 비율 %.2f (기대 약 0.5)" % ratio)


## 보스 스킬 처단은 Monster.execute를 직접 부른다 (처형 확률/기준과 무관)
func _boss_skill_execute_unaffected() -> void:
	print("[3] 보스 스킬 처단(Monster.execute)")
	var m := _monster()
	m.execute(null)
	check(m.is_dead(), "처단은 확률 없이 바로 죽인다")
	_drop(m)


## 수치/문구: 확률과 기준이 둘 다 1% -> 5.9% (예전 확률 3->7.9%, 기준 8/12/18% 보다 낮다)
func _numbers_and_text() -> void:
	print("[4] 수치와 설명 문구")
	var last := Evolutions.MAX_LEVEL
	for key in ["chance", "hp"]:
		var lv1 := Evolutions.p("boss", "B", key, 1)
		var lv_max := Evolutions.p("boss", "B", key, last)
		near(lv1, 0.01, "%s 1레벨 1%%" % key)
		near(lv_max, 0.059, "%s 최대 레벨 5.9%%" % key)
		check(Evolutions.p("boss", "B", key, 2) > lv1, "%s: 레벨이 오르면 커진다" % key)
	var text := Evolutions.skill_text("boss", "B", 1)
	check(text.contains("1.0%"), "Lv1 설명에 1.0%%가 나온다: %s" % text)
	check(Evolutions.skill_text("boss", "B", last).contains("5.9%"), "Lv50 설명에 5.9%가 나온다")
	check(text.contains("처형") and text.contains("보스 포함"), "설명에 처형/보스 포함이 나온다")
