extends "res://tests/case_base.gd"
## 이슈 #21: 서버 상태 스냅샷은 순수 데이터이고, JSON을 거쳐도 클라이언트가 그릴 값이 그대로 남는다.


func run() -> void:
	var field := (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	field.session.participants = [0, 1]
	get_tree().root.add_child.call_deferred(field)
	await frames(8)
	var lane: LaneController = field.lanes[0]
	lane.gold = 500.0
	check(lane.try_build_tower(Vector2i(5, 10), "long", false) == "", "(준비) 타워 건설")
	check(lane.evolve_tower(lane.tower_at(Vector2i(5, 10)), "pierce") == "", "(준비) 진화")
	field.bus.execute(Command.make(Command.START_GAME, 0, {}))
	lane.spawn_wave_monster("grunt", 1)
	await frames(30)

	var snap := Snapshot.build(field.session, field.lanes, field.boss)
	var l: Dictionary = snap.lanes["0"]
	check(snap.v == Snapshot.VERSION and snap.players == [0, 1], "버전과 참여자")
	near(l.gold, lane.gold, "골드")
	near(l.lives, lane.lives, "생명")
	check(l.income == lane.income and l.started and l.active, "수입/시작/활성")
	check(l.income_left > 0.0 and l.income_left <= Balance.INCOME_INTERVAL, "수입까지 남은 시간 %.1f" % l.income_left)
	check(l.towers.size() == 1 and l.towers[0].kind == "long" and l.towers[0].evo == "pierce" and l.towers[0].cell == [5, 10], "타워 1기: 종류/진화/칸")
	check(l.towers[0].invested == lane.tower_at(Vector2i(5, 10)).invested, "타워 투입 골드")
	check(l.monsters.size() == lane.monsters.size() and l.monsters.size() >= 1, "몬스터 %d마리" % l.monsters.size())
	check(snap.lanes.has("1") and snap.lanes["1"].towers.is_empty(), "다른 참여 레인도 담긴다")
	var b: Dictionary = snap.boss
	near(b.hp, field.boss.hp, "보스 체력")
	near(b.time_left, field.boss.time_left, "보스 남은 시간")
	check(b.level == 1 and b.state == int(field.boss.state), "보스 레벨/상태")

	# JSON을 거쳐도 같다 (네트워크로 보낼 수 있다는 뜻). 숫자는 JSON에서 float가 되므로 값으로 비교한다.
	var back: Variant = JSON.parse_string(JSON.stringify(snap))
	check(back is Dictionary, "JSON으로 바뀐다")
	check(back.lanes["0"].towers[0].cell == [5.0, 10.0] and back.lanes["0"].towers[0].evo == "pierce", "JSON 왕복 후 타워 값")
	near(back.boss.hp, b.hp, "JSON 왕복 후 보스 체력")
	check(_has_no_objects(snap), "스냅샷에 노드/객체가 없다")

	field.queue_free()
	await frames(3)


## Dictionary/Array/기본형만 들어 있는가
func _has_no_objects(v: Variant) -> bool:
	match typeof(v):
		TYPE_DICTIONARY:
			for k in v:
				if not _has_no_objects(k) or not _has_no_objects(v[k]):
					return false
			return true
		TYPE_ARRAY:
			for x in v:
				if not _has_no_objects(x):
					return false
			return true
		TYPE_OBJECT, TYPE_VECTOR2, TYPE_VECTOR2I, TYPE_COLOR:
			return false
	return true
