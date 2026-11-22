extends "res://tests/case_base.gd"
## 이슈 #14 몬스터 수입 증가 속도 회귀 테스트.
## 수입 몬스터의 본전(비용/수입, 수입 틱 단위)이 충분히 길고,
## 비싼 몬스터가 무조건 효율이 좋은 구조가 아닌지, 보스 웨이브 구매가 몬스터 income과 상관없는지, 툴팁 표시가 맞는지 본다.
## 수치를 하드코딩하지 않고 데이터(Monsters, Balance, BossLevels)에서 계산한다.

## 본전 하한(수입 틱). 이보다 빨리 본전을 뽑는 몬스터가 있으면 눈덩이 문제(옛 4~7틱)가 돌아온 것이다.
const MIN_PAYBACK_TICKS := 15.0

var game


func run() -> void:
	_payback()
	_efficiency_shape()
	_tooltip()
	game = load("res://scenes/main/MainGame.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	await _boss_wave()
	game.queue_free()
	await frames(3)


## 유저가 만들 수 있는 몬스터(공격형, 지원형) id
func _buildable_ids() -> Array:
	var ids := []
	for id in Monsters.DATA:
		if Monsters.can_send_in_pve(id):
			ids.append(id)
	return ids


## 한 판(보스 10라운드)의 수입 틱 수
func _game_ticks() -> int:
	var total := 0.0
	for level in range(1, BossLevels.COUNT + 1):
		total += float(BossLevels.get_level(level).time)
	return int(total / Balance.INCOME_INTERVAL)


func _payback() -> void:
	var ids := _buildable_ids()
	check(ids.size() > 0, "만들 수 있는 몬스터가 있다")
	var slow_enough := true
	var pays_back_in_game := true
	for id in ids:
		var t := Monsters.payback_ticks(id)
		if t < MIN_PAYBACK_TICKS:
			slow_enough = false
			print("  (본전이 너무 빠름: %s %.1f틱)" % [id, t])
		if Monsters.DATA[id].category == "attack" and t > float(_game_ticks()):
			pays_back_in_game = false
			print("  (한 판 안에 본전을 못 뽑음: %s %.1f틱)" % [id, t])
	check(slow_enough, "만들 수 있는 몬스터 전부 본전이 %.0f틱 이상이다 (옛 일꾼 6.7틱, 투자자 4.4틱)" % MIN_PAYBACK_TICKS)
	check(pays_back_in_game, "공격형은 한 판(%d틱) 안에 본전을 뽑을 수 있다 (일찍 사야 이득)" % _game_ticks())
	check(Monsters.payback_ticks("swarm") == 0.0, "수입이 0이면 본전 틱도 0이다")

## 비싼 몬스터가 무조건 효율이 좋은 구조가 아니다: 가장 효율 좋은 공격형이 가장 비싼 공격형이 아니고,
## 가장 효율 좋은 것부터는 비쌀수록 본전이 느려진다.
func _efficiency_shape() -> void:
	var attack := []
	for id in Monsters.DATA:
		if Monsters.DATA[id].category == "attack":
			attack.append(id)
	attack.sort_custom(func(a, b): return int(Monsters.DATA[a].cost) < int(Monsters.DATA[b].cost))
	var best: String = attack[0]
	for id in attack:
		if Monsters.payback_ticks(id) < Monsters.payback_ticks(best):
			best = id
	var priciest: String = attack[attack.size() - 1]
	check(best != priciest, "가장 효율 좋은 공격형(%s)이 가장 비싼 공격형(%s)이 아니다" % [best, priciest])
	check(Monsters.payback_ticks(priciest) > Monsters.payback_ticks(best), "가장 비싼 공격형이 가장 효율 좋은 공격형보다 본전이 느리다")
	var monotone := true
	var prev := -1.0
	for id in attack.slice(attack.find(best)):
		var t := Monsters.payback_ticks(id)
		if t < prev:
			monotone = false
			print("  (비싼데 본전이 더 빠름: %s %.1f틱 < %.1f틱)" % [id, t, prev])
		prev = t
	check(monotone, "가장 효율 좋은 공격형부터는 비쌀수록 본전이 느려지거나 같다")
	# 지원형은 오라가 본업이라 같은 값의 공격형보다 수입 효율이 나쁘다 (수입으로 쓰는 게 이득이 아니다)
	var slowest_support := 0.0
	for id in Monsters.DATA:
		if Monsters.DATA[id].category == "support":
			slowest_support = maxf(slowest_support, Monsters.payback_ticks(id))
	check(slowest_support > Monsters.payback_ticks(best), "지원형이 가장 효율 좋은 공격형보다 수입 효율이 나쁜 것이 있다")


func _tooltip() -> void:
	var ok := true
	for id in _buildable_ids():
		var d: Dictionary = Monsters.DATA[id]
		var secs := roundi(float(d.cost) / float(d.income) * Balance.INCOME_INTERVAL)
		var tip := Monsters.tooltip(id)
		if not tip.contains("수입 +%d (본전 %d초)" % [d.income, secs]):
			ok = false
			print("  (툴팁 불일치: %s -> %s)" % [id, tip.replace("\n", " / ")])
	check(ok, "툴팁에 수입 +N과 본전 시간(비용/수입 x 수입 주기)이 맞게 나온다")
	check(not Monsters.tooltip("swarm").contains("본전"), "수입이 0인 몬스터 툴팁에는 본전이 안 나온다")
	check(Monsters.tooltip("swarm").contains("수입 +0"), "수입이 0인 몬스터 툴팁에도 수입 +0은 나온다")


## 보스가 웨이브로 몬스터를 살 때는 몬스터의 income을 쓰지 않고 cost만 쓴다 (보스 수입은 BossLevels.income).
func _boss_wave() -> void:
	var src := FileAccess.get_file_as_string("res://scripts/systems/BossController.gd")
	var rx := RegEx.new()
	rx.compile("DATA\\[[^\\]]*\\]\\.income|\\bkind\\.income|\\bwt\\.income|\\bd\\.income")
	check(rx.search(src) == null, "BossController가 몬스터 income을 읽지 않는다 (cost와 level_data.income만)")
	var gf: GameField = game.game_field
	game._on_start_pressed()
	await frames(5)
	var boss: BossController = gf.boss
	check(boss != null and boss.state == BossController.State.RUNNING, "게임을 시작했다 (보스 진행 중)")
	var preview := boss.get_next_wave_preview()
	var spent := 0
	for e in preview:
		spent += int(Monsters.DATA[e.type].cost) * int(e.count)
	check(preview.size() > 0, "다음 웨이브가 계획돼 있다 (%d종)" % preview.size())
	check(spent > 0 and spent <= boss.wave_budget(), "웨이브가 보스 수입(%d) 안에서 cost로 구매됐다 (사용 %d)" % [boss.wave_budget(), spent])
	# 실제로 웨이브가 와서 몬스터가 나온다
	var lane: LaneController = gf.lanes[gf.session.local_player_id]
	Engine.time_scale = 8.0
	var came := await wait_until(func(): return boss.current_wave_text != "-" and lane.wave_monster_count() > 0, 40000)
	Engine.time_scale = 1.0
	check(came, "웨이브가 도착한다 (%s)" % boss.current_wave_text)
