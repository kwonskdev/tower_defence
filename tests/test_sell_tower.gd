extends "res://tests/case_base.gd"
## 이슈 #8 타워 판매 회귀 테스트: 체크리스트 11개 + 소수 골드 계산/정수 표시 + 확인창/이중 판매/일시정지 경계.
## 환급은 반올림하지 않고 소수까지 gold에 더한다 (4골드 타워 70% = 2.8). 화면에는 정수(내림)만 보인다.

var game
var gf: GameField
var lane: LaneController


func run() -> void:
	game = load("res://scenes/main/MainGame.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)  # _ready 안에서 직접 add_child하면 "busy setting up children" 오류
	await frames(8)
	gf = game.game_field
	lane = gf.lanes[0]

	check(gf.boss != null and lane != null, "게임이 떴다 (레인/보스 있음)")
	check(not lane.started, "시작 전: lane.started == false")
	lane.gold = 1000.0

	await _sell_before_start()
	await _destroyed_by_monster()
	await _trap_tower()
	await _invested_gold()
	await _cluster_recalc()
	await _pattern_not_rewarded_twice()
	await _opens_path()
	await _monster_on_cell()
	await _other_lanes()
	await _ui_flow()
	await _after_start_ratio()
	await _fractional_gold()

	game.queue_free()
	await frames(3)


# --- 도우미 ---

## 렌더러 위에 떠 있는 떠다니는 글자(FloatText)의 문구들
func _float_texts() -> Array[String]:
	var out: Array[String] = []
	for c in gf.grid_renderer.get_children():
		if c is Effects.FloatText:
			out.append(c.text)
	return out


func _has_prefix(texts: Array[String], prefix: String) -> bool:
	for x in texts:
		if x.begins_with(prefix):
			return true
	return false


func _clear_float_texts() -> void:
	for c in gf.grid_renderer.get_children():
		if c is Effects.FloatText:
			c.free()


func _state(cell: Vector2i) -> int:
	return gf.grid_systems[0].get_cell_state(cell)


func _build(cell: Vector2i, kind := "long", confirmed := false) -> Tower:
	gf.set_tower_kind(kind)
	if not gf.place_tower(cell, confirmed):
		return null
	return _find_tower(cell)


func _find_tower(cell: Vector2i) -> Tower:
	for t in lane.towers:
		if t.cell == cell:
			return t
	return null


func _sell_all() -> void:
	for t in lane.towers.duplicate():
		lane.sell_tower(t)


# --- 시나리오 ---

## 시작 전 전액 환급, 칸이 비고 다시 지을 수 있다, 선택 해제, "파괴!" 없음, 이중 판매
func _sell_before_start() -> void:
	print("[1] 시작 전 전액 환급 / 칸 비움 / 재건설 / 선택 해제")
	var c := Vector2i(3, 10)
	var g0 := lane.gold
	var t := _build(c)
	near(lane.gold, g0 - 4, "장거리 타워(4골드) 건설")
	check(t.invested == 4, "invested == 건설가 4")
	near(lane.sell_value(t), 4.0, "시작 전 환급 = 전액 4")
	check(_state(c) == GridSystem.CellState.TOWER, "칸 상태 TOWER")
	gf.select_tower(t)
	check(t.selected and gf.get_selected_tower() == t, "타워 선택됨")
	_clear_float_texts()
	check(gf.sell_selected_tower(), "sell_selected_tower() 성공")
	near(lane.gold, g0, "골드가 원래대로 (전액 환급)")
	check(lane.towers.is_empty(), "towers에서 빠짐")
	check(_state(c) == GridSystem.CellState.EMPTY, "칸이 EMPTY")
	check(gf.selected_tower == null and gf.get_selected_tower() == null, "선택이 풀림")
	var texts := _float_texts()
	check(not ("파괴!" in texts), "판매에는 '파괴!' 연출이 없다 (texts=%s)" % [texts])
	check("판매 +4" in texts, "판매 글자 '판매 +4'가 뜬다")
	await frames(3)
	check(not is_instance_valid(t), "타워 노드가 해제됨")
	var again := _build(c)
	check(again != null, "같은 칸에 새 타워를 지을 수 있다")
	check(lane.sell_tower(again), "다시 판매")
	# 이중 판매: 같은 프레임에 두 번 팔아도 골드는 한 번만
	var dbl := _build(c)
	var gd := lane.gold
	check(lane.sell_tower(dbl), "이중 판매 1회째 성공")
	check(not lane.sell_tower(dbl), "이중 판매 2회째 실패")
	near(lane.gold, gd + 4, "이중 판매에도 골드는 한 번만 (+4)")
	await frames(3)


## 몬스터가 부수면 "파괴!" 연출이 그대로 나오고 환급은 없다
func _destroyed_by_monster() -> void:
	print("[2] 몬스터가 부술 때는 '파괴!' 연출 + 환급 없음")
	var c := Vector2i(5, 10)
	_build(c)
	var g := lane.gold
	_clear_float_texts()
	gf.grid_systems[0].set_cell_state(c, GridSystem.CellState.EMPTY)  # 몬스터가 부수는 경로와 같다 (Monster._process)
	var texts := _float_texts()
	check("파괴!" in texts, "부서지면 '파괴!' 글자가 뜬다 (texts=%s)" % [texts])
	check(not _has_prefix(texts, "판매"), "부서질 때 '판매' 글자는 없다")
	check(lane.towers.is_empty() and _state(c) == GridSystem.CellState.EMPTY, "부서진 타워가 치워짐")
	near(lane.gold, g, "부서지면 환급 없음")
	await frames(3)


func _trap_tower() -> void:
	print("[3] 트랩 타워(길을 막지 않는 타워)도 판매")
	var c := Vector2i(6, 12)
	var t := _build(c, "trap")
	check(t != null and _state(c) == GridSystem.CellState.TRAP_TOWER, "트랩 건설 (TRAP_TOWER 칸)")
	var g := lane.gold
	check(lane.sell_tower(t), "트랩 판매 성공")
	near(lane.gold, g + 5, "트랩 가격 5골드 환급 (시작 전 전액)")
	check(_state(c) == GridSystem.CellState.EMPTY and lane.towers.is_empty(), "트랩 칸이 EMPTY")
	await frames(3)


## 진화 + B 스킬 투자액 합산. 레인 공유 업그레이드/색깔 바꾸기/회복은 환급 대상이 아니다.
func _invested_gold() -> void:
	print("[4] 진화/B 스킬 투자액 합산")
	var g := lane.gold
	var t := _build(Vector2i(7, 14))
	var evo: String = Evolutions.TREE["long"][0]
	check(lane.evolve_tower(t, evo), "진화 성공")
	check(t.invested == 4 + Balance.EVOLVE_COST, "진화 후 invested = 4 + 30 (실제 %d)" % t.invested)
	check(lane.learn_tower_skill(t), "B 스킬 배우기 성공")
	check(t.invested == 4 + Balance.EVOLVE_COST + Balance.SKILL_LEARN_COST, "B 후 invested = 74 (실제 %d)" % t.invested)
	near(lane.gold, g - 74, "총 74골드 썼다")
	var before := t.invested
	lane.recolor_tower(t)
	t.durability = 10.0
	lane.heal_tower(t)
	var stat0: Dictionary = Evolutions.STATS[evo][0]
	check(lane.upgrade_stat(evo, stat0.s, stat0.k), "(준비) 레인 스탯 업그레이드 구매")
	check(t.invested == before, "색깔 바꾸기/회복/스탯 업그레이드는 invested에 안 더해진다")
	check(lane.sell_needs_confirm(t), "진화한 타워는 판매 확인 필요")
	near(lane.sell_value(t), 74.0, "시작 전이라 환급 74 (전액)")
	var g2 := lane.gold
	check(lane.sell_tower(t), "진화 타워 판매")
	near(lane.gold, g2 + 74, "골드 +74")
	await frames(3)


## 판매 후 같은 색 덩어리 크기와 색깔 보너스가 다시 계산된다
func _cluster_recalc() -> void:
	print("[5] 판매 후 군집 재계산")
	var green: Dictionary = Balance.TOWER_COLORS[3]
	var ts: Array[Tower] = []
	for c in [Vector2i(3, 16), Vector2i(4, 16), Vector2i(5, 16)]:
		var x := _build(c)
		x.set_color_info(green)
		ts.append(x)
	lane._on_tower_colors_changed()
	check(lane.cluster_size(ts[0]) == 3 and lane.cluster_size(ts[1]) == 3 and lane.cluster_size(ts[2]) == 3, "3개 이어진 같은 색 = 덩어리 3")
	near(lane.cluster_multiplier(ts[0]), 1.0 + Balance.CLUSTER_BONUS_PER_TOWER * 3, "군집 배율 1.03")
	check(lane.sell_tower(ts[1]), "가운데 타워 판매")
	check(lane.cluster_size(ts[0]) == 1 and lane.cluster_size(ts[2]) == 1, "가운데를 팔면 양쪽 덩어리가 1로 갈라진다")
	near(lane.cluster_multiplier(ts[0]), 1.01, "군집 배율 1.01로 재계산")
	_sell_all()
	check(lane.towers.is_empty(), "정리")
	await frames(3)


## 이미 보상을 받은 패턴은 팔고 다시 지어도 중복 지급되지 않는다
func _pattern_not_rewarded_twice() -> void:
	print("[6] 패턴 보상 중복 지급 없음")
	var red: Dictionary = Balance.TOWER_COLORS[0]
	var blue: Dictionary = Balance.TOWER_COLORS[4]
	var cells := [Vector2i(3, 20), Vector2i(4, 20), Vector2i(3, 21), Vector2i(4, 21)]
	var colors := [red, blue, blue, red]  # 태극기: 빨파/파빨
	var ts: Array[Tower] = []
	for i in range(4):
		ts.append(_build(cells[i]))
	# 짓는 순간 색은 랜덤이라 마지막 칸이 우연히 정답 색일 수 있다: 중립색(초록)으로 두고 먼저 평가한 뒤, 마지막에 맞춰서 완성한다
	for i in range(3):
		ts[i].set_color_info(colors[i])
	ts[3].set_color_info(Balance.TOWER_COLORS[3])
	lane._on_tower_colors_changed()
	var already: bool = lane._rewarded_patterns.has("taegeuk")  # 짓는 도중 우연히 완성된 극히 드문 경우만 건너뛴다
	var g := lane.gold
	ts[3].set_color_info(colors[3])
	lane._on_tower_colors_changed()
	if not already:
		check(lane._rewarded_patterns.has("taegeuk"), "태극기 완성이 기록됨")
		near(lane.gold, g + 31, "태극기 완성 보상 +31골드")
	check(lane.sell_tower(ts[3]), "태극기 한 칸 판매")
	var g2 := lane.gold
	var rebuilt := _build(cells[3])
	near(lane.gold, g2 - 4, "같은 칸에 다시 건설")
	rebuilt.set_color_info(colors[3])
	lane._on_tower_colors_changed()
	near(lane.gold, g2 - 4, "다시 완성해도 보상 없음 (골드 변화 = 건설비만)")
	_sell_all()
	await frames(3)


## 길을 완전히 막은 벽에서, 몬스터가 보는 칸의 타워를 팔면 부수지 않고 열린 칸으로 지나간다.
## (몬스터는 사방 3칸 안의 타워만 갱신해서 안다: Monster._scan_vision. 먼 곳의 판매는 가까이 올 때까지 모른다.)
func _opens_path() -> void:
	print("[7] 길을 막던 타워를 팔면 몬스터가 열린 길로 간다")
	var wall_y := 8
	for x in range(GridSystem.GRID_WIDTH):
		_build(Vector2i(x, wall_y), "long", true)
	check(lane.towers.size() == GridSystem.GRID_WIDTH, "12칸 벽 완성 (%d)" % lane.towers.size())
	lane.spawn_wave_monster("grunt", 1, Vector2i(9, 0))
	var m: Monster = lane.monsters[0]
	m._base_max_hp = 1.0e9  # 벽 타워에 맞아 죽지 않게 (max_hp만 올리면 강화 동기화가 되돌린다)
	m.max_hp = 1.0e9
	m.hp = 1.0e9
	var box := [m]  # 람다가 해제된 몬스터를 붙들고 있지 않게 상자에 담는다
	var saw_breach: bool = await wait_until(func(): return is_instance_valid(box[0]) and box[0].breaching, 20000)
	check(saw_breach, "벽이 완전히 막혀 있으면 몬스터가 돌파 경로(breaching)를 짠다")
	m.stun_time = 100.0  # 부수러 가기 전에 붙잡아 둔다 (벽은 아직 12칸)
	check(lane.towers.size() == GridSystem.GRID_WIDTH, "아직 벽 타워는 12개 (몬스터가 부수기 전)")
	var gap_x := int(floor(m.cell_pos.x))  # 몬스터 시야 안에 있는, 부수려던 바로 그 벽 칸
	check(lane.sell_tower(_find_tower(Vector2i(gap_x, wall_y))), "벽 한 칸(%d,%d) 판매" % [gap_x, wall_y])
	m.stun_time = 0.0
	var repathed: bool = await wait_until(func(): return is_instance_valid(box[0]) and not box[0].breaching, 5000)
	check(repathed, "판매 직후 몬스터 경로가 다시 계산되어 돌파(breaching)가 풀린다")
	var cross := [-1.0]
	var crossed: bool = await wait_until(func():
		if not is_instance_valid(box[0]):
			return true
		if box[0].cell_pos.y >= wall_y + 0.5:
			cross[0] = box[0].cell_pos.x
			return true
		return false, 30000)
	check(crossed and cross[0] >= 0.0, "몬스터가 벽 아래까지 내려갔다 (x=%.2f)" % cross[0])
	check(int(floor(cross[0])) == gap_x, "열린 칸(x=%d)으로 지나갔다 (도착 x=%.2f)" % [gap_x, cross[0]])
	check(lane.towers.size() == GridSystem.GRID_WIDTH - 1, "몬스터가 다른 벽 타워를 부수지 않았다 (남은 %d)" % lane.towers.size())
	_sell_all()
	for mm in lane.monsters.duplicate():
		lane.monsters.erase(mm)
		if is_instance_valid(mm):
			mm.queue_free()
	await frames(3)


## 판매 순간 몬스터가 그 칸 위에 있어도, 그 타워를 갉는 중이어도 오류 없이 이어진다
func _monster_on_cell() -> void:
	print("[8] 몬스터가 칸 위에 있거나 갉는 중에 판매")
	var c := Vector2i(5, 12)
	var t := _build(c)
	lane.spawn_wave_monster("grunt", 1, Vector2i(5, 0))
	var over: Monster = lane.monsters[0]
	over._base_max_hp = 1.0e9
	over.max_hp = 1.0e9
	over.hp = 1.0e9
	over.cell_pos = Vector2(c) + Vector2(0.5, 0.5)
	over.grid_pos = c
	check(lane.sell_tower(t), "몬스터가 올라간 칸의 타워 판매")
	await frames(20)
	check(is_instance_valid(over) and lane.monsters.has(over), "몬스터는 멀쩡히 계속 움직인다")
	lane.monsters.erase(over)
	over.queue_free()

	var t2 := _build(Vector2i(4, 12))
	lane.spawn_wave_monster("warrior", 1, Vector2i(4, 0))  # 공격형: 시야 안의 벽 타워를 갉는다
	var gnawer: Monster = lane.monsters[0]
	gnawer._base_max_hp = 1.0e9
	gnawer.max_hp = 1.0e9
	gnawer.hp = 1.0e9
	var gnawing: bool = await wait_until(func(): return is_instance_valid(gnawer) and gnawer._gnawing, 20000)
	check(gnawing, "공격형 몬스터가 타워를 갉기 시작했다")
	check(lane.sell_tower(t2), "갉히는 타워 판매")
	await frames(30)
	check(is_instance_valid(gnawer) and not gnawer._gnawing and gnawer._gnaw_cell == Pathfinder.NO_GOAL, "판매 뒤 몬스터가 목표를 버리고 원래 길로")
	check(lane.towers.is_empty(), "갉던 타워가 다시 생겨나지 않음")
	lane.monsters.erase(gnawer)
	gnawer.queue_free()
	await frames(3)


func _other_lanes() -> void:
	print("[9] 다른 플레이어 레인과 보스 레인의 타워는 판매 불가")
	gf.start_lane(1)
	var lane1: LaneController = gf.lanes[1]
	var t := lane1.build_tower(Vector2i(3, 3), "long")
	var g := lane.gold
	check(not lane.sell_tower(t), "내 레인이 남의 타워를 못 판다 (sell_tower)")
	gf.select_tower(t)
	check(not gf.sell_selected_tower(), "sell_selected_tower도 실패")
	check(lane1.towers.has(t) and gf.grid_systems[1].get_cell_state(Vector2i(3, 3)) == GridSystem.CellState.TOWER, "남의 타워와 칸이 그대로")
	check(lane.gold == g and gf.get_selected_tower() == t, "골드/선택 변화 없음")
	await frames(15)
	check(game.sell_button.disabled, "남의 타워를 선택하면 판매 버튼 비활성")
	game._on_sell_pressed()
	check(lane1.towers.has(t) and not game.sell_confirm_dialog.visible, "버튼 핸들러를 직접 불러도 안 팔리고 창도 안 뜬다")
	gf.select_tower(null)
	check(not gf.lanes.has(GameField.BOSS_LANE_ID), "보스 레인에는 LaneController가 없어 판매할 수 있는 타워가 없다")
	gf.switch_player(GameField.BOSS_LANE_ID)
	check(gf._tower_at(Vector2i(6, 25)) == null, "보스 레인에서는 어떤 칸도 타워로 선택되지 않는다")
	gf.switch_player(0)
	var mine := _build(Vector2i(8, 3))
	lane.active = false
	var g2 := lane.gold
	check(not lane.sell_tower(mine) and lane.gold == g2, "레인이 끝난(active=false) 뒤에는 판매 불가")
	lane.active = true
	lane.sell_tower(mine)
	await frames(3)


## 타워 화면의 판매 버튼: 환급액 표시, 바로 판매 / 확인창, 취소, 일시정지 충돌
func _ui_flow() -> void:
	print("[10] 타워 화면: 판매 버튼, 환급액 표시, 확인창")
	var c := Vector2i(3, 30)
	var t := _build(c)
	gf.select_tower(t)
	await frames(15)
	check(game._view == "tower_sel" and game.sell_button.is_visible_in_tree(), "타워 화면에 판매 버튼이 보인다")
	check(game.sell_button.text == "판매 (4골드)", "버튼 문구 '%s' (시작 전 전액 4)" % game.sell_button.text.replace("\n", " "))
	check(not game.sell_button.disabled, "내 타워라 버튼 활성")
	var g := lane.gold
	game.sell_button.pressed.emit()
	check(not game.sell_confirm_dialog.visible, "건설만 한 타워는 확인창 없이 바로 판매")
	check(absf(lane.gold - (g + 4)) < 0.000001 and _find_tower(c) == null, "바로 판매됨 (+4)")
	check(gf.get_selected_tower() == null, "선택 해제")
	await frames(15)
	check(game._view != "tower_sel", "타워 화면에서 메인으로 돌아왔다 (view=%s)" % game._view)

	var t2 := _build(Vector2i(4, 30))
	lane.evolve_tower(t2, Evolutions.TREE["long"][0])
	lane.learn_tower_skill(t2)
	gf.select_tower(t2)
	await frames(15)
	check(game.sell_button.text == "판매 (74골드)", "진화+B 타워 버튼 '%s'" % game.sell_button.text.replace("\n", " "))
	var g2 := lane.gold
	game.sell_button.pressed.emit()
	check(game.sell_confirm_dialog.visible, "진화한 타워는 확인창이 뜬다")
	check(game.sell_confirm_dialog.dialog_text.contains("74"), "확인창에 환급액이 보인다: %s" % game.sell_confirm_dialog.dialog_text.replace("\n", " / "))
	check(lane.towers.has(t2) and lane.gold == g2, "확인 전에는 안 팔린다")
	game._set_paused(true)
	check(not get_tree().paused, "판매 확인창이 떠 있으면 일시정지로 갇히지 않는다")
	game.sell_confirm_dialog.hide()  # 취소
	check(lane.towers.has(t2) and lane.gold == g2 and gf.get_selected_tower() == t2, "취소하면 그대로")
	game.sell_button.pressed.emit()
	game.sell_confirm_dialog.confirmed.emit()
	game.sell_confirm_dialog.hide()
	check(not lane.towers.has(t2), "확인하면 판매")
	near(lane.gold, g2 + 74, "확인하면 골드 +74")
	check(gf.get_selected_tower() == null, "선택 해제")
	await frames(15)


## 시작 후에는 70%. 환급은 반올림 없이 소수 그대로, 화면에는 내림한 정수만 보인다.
func _after_start_ratio() -> void:
	print("[11] 시작 후 70% (소수 그대로 계산, 표시는 정수)")
	gf.start_game()
	check(lane.started, "시작 버튼 후 lane.started")
	var t := _build(Vector2i(6, 30))
	near(lane.sell_value(t), 2.8, "건설만(4골드) 환급 = 4 x 0.7 = 2.8 (반올림 안 함)")
	check(lane.sell_value_shown(t) == 2, "표시는 내림한 정수 2")
	lane.evolve_tower(t, Evolutions.TREE["long"][0])
	lane.learn_tower_skill(t)
	check(t.invested == 74, "투입 74골드")
	near(lane.sell_value(t), 51.8, "74골드 투입 -> 환급 51.8 (반올림 안 함)")
	check(lane.sell_value_shown(t) == 51, "표시는 내림한 정수 51")
	gf.select_tower(t)
	await frames(15)
	check(game.sell_button.text == "판매 (51골드)", "버튼 '%s'" % game.sell_button.text.replace("\n", " "))
	var g := lane.gold
	check(lane.sell_tower(t), "시작 후 판매")
	near(lane.gold, g + 51.8, "골드에 51.8이 그대로 더해졌다")
	gf.select_tower(null)
	await frames(5)


## 골드는 소수까지 들고 있고 화면/구매 판정은 내림한 정수로 한다
func _fractional_gold() -> void:
	print("[12] 소수 골드: 정수 표시, 구매 판정, 누적 오차")
	check(LaneController.whole(2.8) == 2, "whole(2.8) == 2")
	check(LaneController.whole(2.9999999999) == 3, "whole(2.9999999999) == 3 (부동소수 오차로 한 칸 밀리지 않는다)")
	lane.gold = 10.0
	var t := _build(Vector2i(2, 36))  # 4골드 -> 6.0
	near(lane.gold, 6.0, "건설 후 6.0")
	check(lane.sell_tower(t), "판매")
	near(lane.gold, 8.8, "6.0 + 2.8 = 8.8")
	check(lane.gold_shown() == 8, "gold_shown() == 8")
	await frames(15)
	check(game.status_gold_label.text == "8", "왼쪽 위 골드 표시는 정수 '8' (실제 '%s')" % game.status_gold_label.text)
	# 보이는 돈으로 산다: 2.8골드로는 3골드짜리를 못 사고, 3.0 직전(부동소수 오차)은 산다
	lane.gold = 2.8
	check(not lane.try_spend(3, "테스트"), "2.8골드로 3골드를 못 산다")
	near(lane.gold, 2.8, "못 샀으면 골드는 그대로")
	lane.gold = 3.0 - 0.000000001
	check(lane.gold_shown() == 3 and lane.try_spend(3, "테스트"), "2.999999999골드(오차)는 3으로 보이고 3골드를 살 수 있다")
	# 여러 번 팔아도 오차가 쌓여 한 칸 밀리지 않는다
	lane.gold = 100.0
	var ts: Array[Tower] = []
	for i in range(5):
		ts.append(_build(Vector2i(i, 38)))
	near(lane.gold, 80.0, "5기 건설 후 80")
	for x in ts:
		lane.sell_tower(x)
	near(lane.gold, 94.0, "5기 판매 후 80 + 5 x 2.8 = 94")
	check(lane.gold_shown() == 94, "표시 94 (오차로 93이 되지 않는다)")
	await frames(3)
