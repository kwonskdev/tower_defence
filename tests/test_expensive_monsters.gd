extends "res://tests/case_base.gd"
## 이슈 #15 비싼 몬스터 종류 회귀 테스트.
## 거인(700원) 위에 1000원 이상 공격형이 계단식으로 있고, 배럭에서 고를 수 있으며, 한 번에 큰돈을 쓸 수 있고,
## 싼 것 여러 마리보다 확실히 쓸모가 있고(골드당 공격력/생명), 툴팁과 칸 배치와 협력 제한이 맞는지 본다.
## 수치를 하드코딩하지 않고 데이터(Monsters, Balance, BossLevels)에서 계산한다.
## (거인 가격 등은 "비싼 몬스터" 기준선을 데이터에서 찾는다: 1000원 이상이면 비싼 몬스터)

## 이 값 이상이면 "비싼 몬스터" (이슈 #15: 지금 최고가 700원 위로 1000원부터)
const EXPENSIVE := 1000

var game


func run() -> void:
	_exists_and_ladder()
	_worth_it()
	_tooltip()
	_boss_pool()
	_pve()
	game = load("res://scenes/main/MainGame.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	_barracks_layout()
	await _spend_big()
	game.queue_free()
	await frames(3)


## 공격형 id를 싼 것부터
func _attack_sorted() -> Array:
	var ids := []
	for id in Monsters.DATA:
		if Monsters.DATA[id].category == "attack":
			ids.append(id)
	ids.sort_custom(func(a, b): return int(Monsters.DATA[a].cost) < int(Monsters.DATA[b].cost))
	return ids


func _expensive_ids() -> Array:
	return _attack_sorted().filter(func(id): return int(Monsters.DATA[id].cost) >= EXPENSIVE)


## 기존 최고가 공격형 (비싼 몬스터를 빼고 가장 비싼 것) = 기준선
func _baseline() -> String:
	var cheap := _attack_sorted().filter(func(id): return int(Monsters.DATA[id].cost) < EXPENSIVE)
	return cheap[cheap.size() - 1]


func _peak_dps(id: String) -> float:
	return Monsters.dps(id) + float(Monsters.DATA[id].get("ramp_cap", 0.0))


## 체크 1: 1000원 이상이 새로 생겼고 계단식이다
func _exists_and_ladder() -> void:
	var ids := _expensive_ids()
	check(ids.size() >= 3, "1000원 이상 공격형이 3종 이상 있다 (%d종: %s)" % [ids.size(), ", ".join(ids.map(func(id): return Monsters.DATA[id].name))])
	check(int(Monsters.DATA[ids[0]].cost) == EXPENSIVE, "가장 싼 비싼 몬스터가 %d원 (계단 시작)" % EXPENSIVE)
	var doubling := true
	for i in range(1, ids.size()):
		if int(Monsters.DATA[ids[i]].cost) < int(Monsters.DATA[ids[i - 1]].cost) * 2:
			doubling = false
	check(doubling, "비싼 몬스터는 한 칸마다 가격이 2배 이상이다 (계단식)")
	check(int(Monsters.DATA[ids[ids.size() - 1]].cost) >= 4000, "가장 비싼 몬스터가 4000원 이상이다")
	var base := _baseline()
	check(int(Monsters.DATA[base].cost) < EXPENSIVE and int(Monsters.DATA[ids[0]].cost) > int(Monsters.DATA[base].cost), "기준선(%s)보다 비싸다" % Monsters.DATA[base].name)


## 체크 3: 싼 것 여러 마리보다 확실히 쓸모가 있다
func _worth_it() -> void:
	var ids := _expensive_ids()
	var chain := [_baseline()] + ids
	var dps_up := true
	var life_up := true
	var hp_ok := true
	var income_ok := true
	var payback_slow := true
	var all_cheaper_beaten := true
	for i in range(1, chain.size()):
		var prev: Dictionary = Monsters.DATA[chain[i - 1]]
		var cur: Dictionary = Monsters.DATA[chain[i]]
		if _peak_dps(chain[i]) / float(cur.cost) <= _peak_dps(chain[i - 1]) / float(prev.cost):
			dps_up = false
			print("  (골드당 공격력이 안 오름: %s)" % chain[i])
		if int(cur.get("life", 1)) <= int(prev.get("life", 1)):
			life_up = false
		# 체력은 골드당 같은 수준 이상 (싼 것 여러 마리를 사는 것보다 손해가 아니다)
		if float(cur.hp) / float(cur.cost) < float(prev.hp) / float(prev.cost) - 0.001:
			hp_ok = false
		# 수입은 화력 담당이라 골드당 수입이 더 좋아지지 않고, 본전은 더 느려진다 (#14)
		if float(cur.income) / float(cur.cost) > float(prev.income) / float(prev.cost) + 0.0001:
			income_ok = false
		if Monsters.payback_ticks(chain[i]) < Monsters.payback_ticks(chain[i - 1]):
			payback_slow = false
	# 같은 돈으로 싼 몬스터(기준선)를 살 수 있는 만큼 사는 것보다, 비싼 한 마리가 골드당 공격력이 좋다
	for id in ids:
		var base := _baseline()
		if _peak_dps(id) / float(Monsters.DATA[id].cost) <= _peak_dps(base) / float(Monsters.DATA[base].cost):
			all_cheaper_beaten = false
	check(dps_up, "비쌀수록 골드당 공격력이 오른다 (싼 것 여러 마리보다 한 마리가 낫다)")
	check(all_cheaper_beaten, "비싼 몬스터 전부 기준선(거인)보다 골드당 공격력이 좋다")
	check(life_up, "비쌀수록 기지에 닿았을 때 생명이 더 크다 (거인 life %d 기준)" % int(Monsters.DATA[_baseline()].get("life", 1)))
	check(hp_ok, "비싼 몬스터의 골드당 체력이 기준선 이하로 떨어지지 않는다")
	check(income_ok, "비싼 몬스터는 골드당 수입이 더 좋아지지 않는다 (화력 담당, #14와 충돌 없음)")
	check(payback_slow, "비쌀수록 본전이 같거나 더 느리다")
	for id in ids:
		check(Monsters.payback_ticks(id) >= 15.0 and Monsters.payback_ticks(id) <= _game_ticks(), "%s 본전 %.1f틱이 15틱 이상 한 판(%d틱) 이내다" % [Monsters.DATA[id].name, Monsters.payback_ticks(id), _game_ticks()])


func _game_ticks() -> int:
	var total := 0.0
	for level in range(1, BossLevels.COUNT + 1):
		total += float(BossLevels.get_level(level).time)
	return int(total / Balance.INCOME_INTERVAL)


## 체크 4: 툴팁에 비용/수입/공격/체력이 맞게 나온다
func _tooltip() -> void:
	var ok := true
	for id in _expensive_ids():
		var d: Dictionary = Monsters.DATA[id]
		var tip := Monsters.tooltip(id)
		var secs := roundi(float(d.cost) / float(d.income) * Balance.INCOME_INTERVAL)
		for part in [d.name, "비용 %d" % d.cost, "수입 +%d (본전 %d초)" % [d.income, secs], "공격 %d" % roundi(Monsters.dps(id)), "체력 %d" % roundi(Monsters.max_hp(id))]:
			if not tip.contains(part):
				ok = false
				print("  (툴팁에 '%s'가 없음: %s)" % [part, tip.replace("\n", " / ")])
		if tip.contains("협력에서는 만들 수 없음"):
			ok = false
	check(ok, "비싼 몬스터 툴팁에 이름/비용/수입+본전/공격/체력이 맞게 나온다")


## 체크 6(보스 후보): 보스는 수입 안에서만 살 수 있다 -> 후보는 마지막 라운드 수입으로 살 수 있는 것만, 후반 라운드부터
func _boss_pool() -> void:
	var max_income := int(BossLevels.get_level(BossLevels.COUNT).income)
	var ok := true
	var late := true
	var any_candidate := false
	for id in _expensive_ids():
		var d: Dictionary = Monsters.DATA[id]
		var in_last: bool = Monsters.candidates(BossLevels.COUNT).has(id)
		any_candidate = any_candidate or in_last
		if in_last and int(d.cost) > max_income:
			ok = false
			print("  (보스가 못 사는데 후보: %s)" % id)
		if not in_last and int(d.cost) <= max_income and float(d.weight) > 0.0:
			ok = false
		if int(d.min_level) < BossLevels.COUNT - 1:
			late = false
	check(ok, "보스 후보는 마지막 라운드 수입(%d)으로 살 수 있는 비싼 몬스터뿐이다" % max_income)
	check(late, "비싼 몬스터는 후반 라운드(마지막 2라운드)부터 나온다")
	check(any_candidate, "살 수 있는 비싼 몬스터가 마지막 라운드 보스 웨이브 후보에 하나는 있다")
	var early := false
	for level in range(1, BossLevels.COUNT):
		for id in _expensive_ids():
			if Monsters.candidates(level).has(id):
				early = true
	check(not early, "마지막 라운드 전에는 비싼 몬스터가 웨이브 후보에 없다")


## 체크 6: 협력(PvE)에서 만들 수 있는 유형 제한이 새 몬스터에도 맞게 걸린다
func _pve() -> void:
	var ok := true
	for id in _expensive_ids():
		if Monsters.can_send_in_pve(id) != (Monsters.DATA[id].category in Monsters.PVE_SENDABLE):
			ok = false
	check(ok, "비싼 몬스터의 협력(PvE) 제한이 PVE_SENDABLE(유형)과 일치한다")
	check(not _expensive_ids().is_empty() and _expensive_ids().all(func(id): return Monsters.can_send_in_pve(id)), "비싼 공격형은 협력에서도 만들 수 있다")


## 체크 5: 배럭 칸 배치가 깨지지 않는다
func _barracks_layout() -> void:
	var back: int = game.BACK_CELL
	for cat in Monsters.CATEGORIES:
		var slots: Array = Monsters.slots_of(cat)
		check(slots.size() <= back, "%s 칸 %d개가 뒤로 가기 칸(%d) 앞에 들어간다" % [cat, slots.size(), back])
		var seen := {}
		var dup := false
		for id in slots:
			if seen.has(id) or not Monsters.DATA.has(id):
				dup = true
			seen[id] = true
		check(not dup, "%s 칸 배치에 중복/없는 종류가 없다" % cat)
	game._populate_monster_buttons("attack")
	var shown := 0
	for i in range(1, game.monster_buttons.size()):
		var b: Button = game.monster_buttons[i]
		if b.visible and b.modulate.a > 0.0 and not b.disabled:
			shown += 1
	check(shown == Monsters.slots_of("attack").size(), "배럭에 공격형 버튼이 %d개 보인다" % Monsters.slots_of("attack").size())
	for id in _expensive_ids():
		var slot_idx: int = Monsters.slots_of("attack").find(id)
		check(slot_idx >= 0, "배럭 공격형 칸에 %s 칸이 있다 (%d번째)" % [Monsters.DATA[id].name, slot_idx + 1])
		var b: Button = game.monster_buttons[slot_idx + 1]
		var cost_ok := false
		for c in b.get_children():
			if c is Label and (c as Label).text == str(Monsters.DATA[id].cost):
				cost_ok = true
		check(b.visible and not b.disabled and cost_ok, "%s 버튼이 보이고 눌리며 가격 %d이 적혀 있다" % [Monsters.DATA[id].name, Monsters.DATA[id].cost])
		check(b.modulate == Color.WHITE, "%s 버튼은 협력에서 막혀 회색이 아니다" % Monsters.DATA[id].name)


## 체크 2: 돈이 쌓이면 한 번에 큰돈을 쓸 수 있다 (게임에서 실제로 보낸다)
func _spend_big() -> void:
	var gf: GameField = game.game_field
	game._on_start_pressed()
	await frames(5)
	var lane: LaneController = gf.lanes[gf.session.local_player_id]
	check(gf.boss != null and gf.boss.state == BossController.State.RUNNING, "게임을 시작했다 (보스 진행 중)")
	var max_cost := 0
	for id in _expensive_ids():
		max_cost = maxi(max_cost, int(Monsters.DATA[id].cost))
	for id in _expensive_ids():
		var d: Dictionary = Monsters.DATA[id]
		# 돈이 모자라면 못 산다 (골드/수입 그대로)
		lane.gold = float(d.cost) - 1.0
		var inc0 := lane.income
		var sent_poor := gf.send_monster(id)
		check(not sent_poor and absf(lane.gold - (float(d.cost) - 1.0)) < 0.001 and lane.income == inc0, "%s: 골드 %d로는 못 산다" % [d.name, int(d.cost) - 1])
		# 돈이 쌓이면 한 번에 산다
		lane.gold = float(max_cost) + 500.0
		var sent := gf.send_monster(id)
		var spent := float(max_cost) + 500.0 - lane.gold
		check(sent and absf(spent - float(d.cost)) < 0.001, "%s: 한 번에 %d골드를 쓴다 (쓴 돈 %.0f)" % [d.name, d.cost, spent])
		check(lane.income == inc0 + int(d.income), "%s: 수입이 +%d 오른다" % [d.name, d.income])
