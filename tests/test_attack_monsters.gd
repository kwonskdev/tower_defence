extends "res://tests/case_base.gd"
## 이슈 #17 공격형 몬스터 계열 통합 회귀 테스트.
## 공격형은 계열(수입/화력/균형/특수) 없이 한 줄 계단이고, 전부 공격력과 수입을 둘 다 가진다.
## 수치를 하드코딩하지 않고 데이터에서 계산한다 (#14/#15에서 수입 값이나 종류가 바뀌어도 낡지 않게).

const OLD_WORDS := ["계열", "화력", "균형", "특수", "수입형"]
## 골드당 공격력 하한 (보스를 잡을 만한 공격력). 수입 몬스터만 모아도 피해가 거의 없던 옛 문제(0.0025/골드)를 막는다.
const MIN_DPS_PER_GOLD := 0.05
## 골드당 수입 상한: 수입에 올인한 몬스터가 다시 생기지 않게 한다 (옛 수입 계열은 0.15 이상)
const MAX_INCOME_PER_GOLD := 0.1

var game


func run() -> void:
	_data()
	_boss_pool()
	_pve()
	game = load("res://scenes/main/MainGame.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	_barracks_ui()
	await _send_each()
	game.queue_free()
	await frames(3)


func _attack_ids() -> Array:
	var ids := []
	for id in Monsters.DATA:
		if Monsters.DATA[id].category == "attack":
			ids.append(id)
	return ids


## 보스 앞에서 낼 수 있는 최대 공격력 (성장형은 상한)
func _peak_dps(id: String) -> float:
	var d: Dictionary = Monsters.DATA[id]
	return Monsters.dps(id) + float(d.get("ramp_cap", 0.0))  # 기본 + 성장 상한 (ramp_cap은 늘어나는 양의 상한)


func _data() -> void:
	var ids := _attack_ids()
	check(ids.size() > 0, "공격형이 있다")
	var no_family := true
	var both := true
	var strong := true
	var not_income_only := true
	for id in ids:
		var d: Dictionary = Monsters.DATA[id]
		if d.has("family"):
			no_family = false
		if Monsters.dps(id) <= 0.0 or int(d.income) <= 0:
			both = false
		if _peak_dps(id) / float(d.cost) < MIN_DPS_PER_GOLD:
			strong = false
		if float(d.income) / float(d.cost) > MAX_INCOME_PER_GOLD:
			not_income_only = false
	check(no_family, "몬스터 데이터에 family가 없다")
	check(not (load("res://scripts/data/Monsters.gd") as GDScript).get_script_constant_map().has("FAMILY_COLORS"), "FAMILY_COLORS가 없다")
	check(both, "공격형 전부 공격력(dps)과 수입(income)이 둘 다 있다")
	check(strong, "공격형 전부 골드당 공격력이 %s 이상이다 (화력 계열을 안 만들어도 보스를 잡을 공격력)" % MIN_DPS_PER_GOLD)
	check(not_income_only, "수입에 올인한 공격형이 없다 (골드당 수입 %s 이하)" % MAX_INCOME_PER_GOLD)

	var slots: Array = Monsters.slots_of("attack")
	check(not slots.has(""), "공격형 칸 배치에 빈칸이 없다 (한 줄 목록)")
	var sorted_ids := slots.duplicate()
	sorted_ids.sort()
	var ids_sorted := ids.duplicate()
	ids_sorted.sort()
	check(sorted_ids == ids_sorted, "칸 배치가 공격형 전부를 한 번씩 담고 있다")
	var costs := {}
	var ascending := true
	var prev := -1
	for id in slots:
		var c := int(Monsters.DATA[id].cost)
		costs[c] = true
		if c <= prev:
			ascending = false
		prev = c
	check(costs.size() == slots.size(), "가격이 겹치는 공격형이 없다")
	check(ascending, "칸 배치가 싼 것부터 비싼 순서다 (한 줄 계단)")

	var all_text := Monsters.CATEGORY_DATA.attack.desc
	for id in ids:
		all_text += Monsters.tooltip(id) + Monsters.DATA[id].desc
	for w in OLD_WORDS:
		check(not all_text.contains(w), "공격형 설명/툴팁에 '%s'가 없다" % w)


func _boss_pool() -> void:
	var ids := _attack_ids()
	var ok := true
	for level in range(1, BossLevels.COUNT + 1):
		if Monsters.candidates(level).is_empty():
			ok = false
	check(ok, "보스 라운드 1~%d마다 웨이브 후보가 있다" % BossLevels.COUNT)
	# 보스 웨이브 후보인 공격형(weight > 0)은 마지막 라운드에 전부 나올 수 있다. weight 0이면 유저 전용이다 (#15: 보스 수입으로 못 사거나 생명이 너무 큰 것)
	var last: Array = Monsters.candidates(BossLevels.COUNT)
	var max_income := int(BossLevels.get_level(BossLevels.COUNT).income)
	var all_in := true
	var affordable := true
	for id in ids:
		if float(Monsters.DATA[id].weight) > 0.0:
			if not last.has(id):
				all_in = false
			if int(Monsters.DATA[id].cost) > max_income:
				affordable = false  # 보스가 못 사는 몬스터를 후보에 두면 뽑을 수 없는 후보가 된다
	check(all_in, "마지막 라운드에는 보스 웨이브 후보인(weight > 0) 공격형이 전부 후보에 있다")
	check(affordable, "보스 웨이브 후보인 공격형은 마지막 라운드 보스 수입(%d)으로 살 수 있다" % max_income)
	# 공격형이 보스 후보에서 차지하는 가중치 비중: 일반형/공중형이 주력이어야 한다 (30% 이하)
	var worst := 0.0
	for level in range(1, BossLevels.COUNT + 1):
		var atk_w := 0.0
		var total_w := 0.0
		for id in Monsters.candidates(level):
			var w := float(Monsters.DATA[id].weight)
			total_w += w
			if Monsters.DATA[id].category == "attack":
				atk_w += w
		worst = maxf(worst, atk_w / total_w)
	check(worst <= 0.3, "보스 후보에서 공격형 가중치 비중이 30%% 이하다 (최대 %.0f%%)" % (worst * 100.0))
	# 보스 수입으로 살 수 있는가: 공격형이 나오는 첫 라운드의 보스 수입이 가장 싼 공격형 가격 이상
	var cheapest := 1000000
	var first_level := 99
	for id in ids:
		cheapest = mini(cheapest, int(Monsters.DATA[id].cost))
		first_level = mini(first_level, int(Monsters.DATA[id].min_level))
	check(BossLevels.get_level(first_level).income >= cheapest, "공격형이 처음 나오는 라운드에 보스가 가장 싼 공격형을 살 수 있다")


func _pve() -> void:
	var ok := true
	for id in _attack_ids():
		if not Monsters.can_send_in_pve(id):
			ok = false
	check(ok, "협력(PvE)에서 공격형 전부 만들 수 있다")
	check(Monsters.can_send_in_pve("cheer") and Monsters.can_send_in_pve("banner"), "협력에서 지원형도 만들 수 있다")
	check(not Monsters.can_send_in_pve("grunt") and not Monsters.can_send_in_pve("flyer"), "협력에서 일반형/공중형은 못 만든다")


func _barracks_ui() -> void:
	check(game.get("family_frames") == null, "몬스터 계열 외곽선 변수가 없다")
	game._populate_monster_buttons("attack")
	var shown := 0
	for i in range(1, game.monster_buttons.size()):
		var b: Button = game.monster_buttons[i]
		if b.visible and b.modulate.a > 0.0 and not b.disabled:
			shown += 1
	check(shown == Monsters.slots_of("attack").size(), "배럭에 공격형 버튼이 %d개 보인다" % Monsters.slots_of("attack").size())


## 게임을 시작해 공격형을 하나씩 보내 본다: 골드가 비용만큼 줄고 수입이 income만큼 늘며, 보스 앞에서 보스에게 피해를 준다.
func _send_each() -> void:
	var gf: GameField = game.game_field
	game._on_start_pressed()
	await frames(5)
	var lane: LaneController = gf.lanes[gf.session.local_player_id]
	check(gf.boss != null and gf.boss.state == BossController.State.RUNNING, "게임을 시작했다 (보스 진행 중)")
	var boss_hp0: float = gf.boss.hp
	Engine.time_scale = 8.0
	var money_ok := true
	for id in _attack_ids():
		lane.gold = 100000.0
		var inc0 := lane.income
		var ok := gf.send_monster(id)
		if not ok or absf(lane.gold - (100000.0 - float(Monsters.DATA[id].cost))) > 0.001 or lane.income != inc0 + int(Monsters.DATA[id].income):
			money_ok = false
			print("  (보내기 실패/수치 불일치: %s)" % id)
	check(money_ok, "공격형을 하나씩 보내면 골드가 비용만큼 줄고 수입이 income만큼 는다")
	var damaged := await wait_until(func(): return gf.boss.hp < boss_hp0, 60000)
	Engine.time_scale = 1.0
	check(damaged, "보낸 공격형이 보스에게 피해를 준다 (보스 체력 %.0f -> %.0f)" % [boss_hp0, gf.boss.hp])
