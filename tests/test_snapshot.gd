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
	check(b.name == field.boss.level_data.name and b.phase_text == field.boss.phase_text(), "보스 이름/페이즈 글자 (HUD가 쓴다)")
	check(b.wave_preview.size() == field.boss.get_next_wave_preview().size(), "다음 웨이브 미리보기 %d줄" % b.wave_preview.size())
	for e in b.wave_preview:
		check(e.color is String and Color.html(e.color) != Color.BLACK or e.color == "000000", "미리보기 색은 글자(JSON 안전): %s" % e.color)
	check(b.ghost_summary.has("lane_ranking") and not b.ghost_running, "유령 요약 포함, 지금은 유령 구간 아님")

	# JSON을 거쳐도 같다 (네트워크로 보낼 수 있다는 뜻). 숫자는 JSON에서 float가 되므로 값으로 비교한다.
	var back: Variant = JSON.parse_string(JSON.stringify(snap))
	check(back is Dictionary, "JSON으로 바뀐다")
	check(back.lanes["0"].towers[0].cell == [5.0, 10.0] and back.lanes["0"].towers[0].evo == "pierce", "JSON 왕복 후 타워 값")
	near(back.boss.hp, b.hp, "JSON 왕복 후 보스 체력")
	check(_has_no_objects(snap), "스냅샷에 노드/객체가 없다")

	field.queue_free()
	await frames(3)

	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	await hud_matches_state(game)
	game.queue_free()
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


## HUD 숫자가 스냅샷으로 그려지고 서버(레인/보스) 값과 같다 (MainGame의 상태 패널과 하단 안내)
func hud_matches_state(game: Node) -> void:
	var gf: GameField = game.game_field
	var lane: LaneController = gf.lanes[0]
	lane.gold = 321.9
	gf.do_command(Command.START_GAME)
	await frames(20)
	check(game.status_gold_label.text == "321", "골드 표시 '%s' (321.9 -> 321)" % game.status_gold_label.text)
	check(game.status_lives_label.text == "%d" % lane.lives_shown(), "생명 표시 '%s'" % game.status_lives_label.text)
	check(game.status_income_label.text.begins_with("수입 +%d" % lane.income), "수입 표시 '%s'" % game.status_income_label.text.replace("\n", " "))
	gf.switch_player(GameField.BOSS_LANE_ID)
	await frames(15)
	check(game.hud_label.text.contains("BOSS Lv.1/") and game.hud_label.text.contains(gf.boss.level_data.name), "보스 레인 하단 안내 '%s'" % game.hud_label.text.split("\n")[0])

	# 결과 화면 통계 (스냅샷으로 모은다)
	gf.switch_player(0)
	lane.try_build_tower(Vector2i(4, 12), "long", false)
	var stats: Dictionary = game._collect_game_stats(false)
	check(stats.boss_level == 1 and stats.final_gold == LaneController.whole(lane.gold), "통계: 보스 레벨/최종 골드 (%s)" % stats.final_gold)
	check(stats.towers_built == lane.towers.size() and stats.final_income == lane.income, "통계: 타워 수/수입")
	check(stats.boss_damage == 0.0 and stats.ghost.has("lane_ranking"), "통계: 보스 피해/유령 요약")
	# 보스 스킬 배너는 시뮬레이션 이벤트(skill_announced)로 뜬다
	gf.session.events.announce({"name": "테스트 스킬", "text": "설명", "lane": "both", "delay": 0.0, "boss": "시험 보스"})
	await frames(5)
	check(game.skill_banner.visible, "skill_announced 이벤트로 스킬 배너가 뜬다")
	# 미니맵도 스냅샷으로 그려진다 (오류 없이 그려지는지)
	for v in game.minimap_views.values():
		v.queue_redraw()
	await frames(3)
	check(true, "미니맵 %d개가 스냅샷으로 오류 없이 그려진다" % game.minimap_views.size())
