extends "res://tests/case_base.gd"
## 이슈 #52 투사체 속도 회귀 테스트: 투사체는 게임 내 가장 빠른 몬스터(돌격 웨이브의 돌격병)의 1.3배 이상이어야 따라잡는다.
## 몬스터 속도나 돌격 배율이 오르거나 투사체 속도가 내려가 1.3배 아래가 되면 여기서 실패한다.
## 수치는 하드코딩하지 않고 Monsters / BossSkills / Balance에서 계산한다.

var game
var gf: GameField
var lane: LaneController


func run() -> void:
	_speed_numbers()
	game = load("res://scenes/main/MainGame.tscn").instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	gf = game.game_field
	lane = gf.lanes[0]
	await _launched_speeds()
	await _hits_charge_rusher()


## 체크 1: 최고 속도는 데이터에서 계산한다
func _speed_numbers() -> void:
	print("[1] 최고 몬스터 속도")
	var base := 0.0
	for id in Monsters.DATA:
		base = maxf(base, float(Monsters.DATA[id].speed))
	var mult := 1.0
	for id in BossSkills.AFFIXES:
		mult = maxf(mult, float(BossSkills.AFFIXES[id].get("speed_mult", 1.0)))
	near(Monsters.max_speed(), base, "Monsters.max_speed()는 전 종류 speed의 최댓값")
	near(BossSkills.max_speed_mult(), mult, "BossSkills.max_speed_mult()는 변형 speed_mult의 최댓값")
	near(Balance.fastest_monster_speed(), base * mult, "가장 빠른 몬스터의 실제 속도 = 최고 speed x 최고 변형 배율")
	check(Balance.fastest_monster_speed() >= float(Monsters.DATA.rusher.speed) * float(BossSkills.AFFIXES.charge.speed_mult),
		"돌격 웨이브 돌격병(speed x 돌격 배율)보다 느리지 않다")
	check(Balance.PROJECTILE_SPEED_MARGIN >= 1.3, "여유 배율 상수 >= 1.3 (%s)" % Balance.PROJECTILE_SPEED_MARGIN)


func _fire(kind_id: String, fx: Dictionary, from: Vector2, target: Monster) -> Effects.Projectile:
	var renderer: GridRenderer = lane._renderer
	var n := renderer.get_child_count()
	Effects.spawn_projectile(renderer, lane, from, target, Balance.tower_kind(kind_id), Color.WHITE, null, 1.0, fx)
	for i in range(renderer.get_child_count() - 1, n - 1, -1):
		var c := renderer.get_child(i)
		if c is Effects.Projectile:
			return c
	return null


## 체크 2: 모든 투사체 종류(bomb/orb/missile/bolt/dart)의 속도가 최고 속도 x 1.3 이상
func _launched_speeds() -> void:
	print("[2] 투사체 종류별 속도")
	lane.spawn_wave_monster("rusher", 1, Vector2i(9, 0), "charge")
	await frames(2)
	var m: Monster = lane.monsters[0]
	var limit := Balance.fastest_monster_speed() * 1.3
	var cases := {
		"bomb": ["splash", {}], "orb": ["long", {"snare": {}}], "missile": ["air", {}],
		"bolt": ["long", {}], "dart": ["trap", {}],
	}
	var seen := 0
	for style in cases:
		var p := _fire(cases[style][0], cases[style][1], m.cell_pos + Vector2(0, -3), m)
		check(p != null and p.style == style, "%s 투사체가 만들어졌다" % style)
		if p != null:
			seen += 1
			check(p.speed >= limit - 0.000001, "%s 속도 %.2f >= 최고 몬스터 속도 x 1.3 (%.2f)" % [style, p.speed, limit])
			p.queue_free()
	check(seen == 5, "투사체 5종을 모두 확인했다 (%d)" % seen)
	m.queue_free()
	lane.monsters.clear()


## 체크 3: 돌격 웨이브의 돌격병이 달아나는 중에 쏜 투사체가 실제로 맞힌다
func _hits_charge_rusher() -> void:
	print("[3] 돌격 웨이브 돌격병 명중")
	for style_kind in ["splash", "long", "air", "trap"]:
		lane.spawn_wave_monster("rusher", 1, Vector2i(9, 0), "charge")
		await frames(2)
		var m: Monster = lane.monsters[0]
		check(is_equal_approx(m.speed * m.speed_boost, Balance.fastest_monster_speed()),
			"돌격병 실제 속도 %.2f == 최고 몬스터 속도" % (m.speed * m.speed_boost))
		var hp0 := m.hp
		var p := _fire(style_kind, {}, m.cell_pos + Vector2(0, -2.5), m)  # 등 뒤 2.5칸에서 쏜다: 따라잡아야 맞는다
		check(p != null, "%s 타워 투사체 발사" % style_kind)
		var speed := p.speed if p != null else -1.0
		var hit := await wait_until(func(): return is_instance_valid(m) and m.hp < hp0, 3000)
		check(hit, "%s 투사체(속도 %.1f)가 돌격병(%.1f)을 맞혔다" % [style_kind, speed, Balance.fastest_monster_speed()])
		if is_instance_valid(m):
			m.queue_free()
		lane.monsters.clear()
		await frames(2)
