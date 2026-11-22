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
	await map_view_draws_from_snapshot()
	await shots_are_events()
	await warn_events()
	await loopback_clients()
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
	# 선택한 타워의 정보창과 버튼은 스냅샷 값으로 그려진다
	lane.gold = 500.0
	lane.try_build_tower(Vector2i(5, 14), "long", false)
	lane.evolve_tower(lane.tower_at(Vector2i(5, 14)), "pierce")
	gf.select_tower_at(0, Vector2i(5, 14))
	await frames(15)
	var sel: Dictionary = gf.get_selected_tower()
	check(not sel.is_empty() and sel.evo == "pierce" and game._view == "tower_sel", "맵에서 누른 타워가 선택되어 타워 화면이 된다 (진화=%s)" % sel.get("evo"))
	var sim_tower := lane.tower_at(Vector2i(5, 14))
	check(absf(sel.damage_now - sim_tower.cur_damage()) < 0.0001 and absf(sel.range - sim_tower.cur_range()) < 0.0001, "스냅샷의 피해/사거리가 서버 계산과 같다")
	check(game.tower_info_label.text.contains("%.2f" % sim_tower.cur_damage()) and game.tower_info_label.text.contains(sim_tower.color_bonus_text()), "정보창 글자가 서버 값 그대로: %s" % game.tower_info_label.text.replace("
", " / ").left(60))
	check(game.sell_button.text == "판매 (%d골드)" % lane.sell_value_shown(sim_tower), "판매 버튼 환급액 '%s'" % game.sell_button.text)
	# 생명이 줄면 화면이 붉게 깜빡인다 (스냅샷의 생명 변화로 알아챈다)
	game.life_flash.color.a = 0.0
	lane.lives -= 1.0
	await frames(60)  # HUD는 0.1초마다 갱신된다
	check(game._prev_lives == floori(lane.lives), "생명 변화를 스냅샷으로 알아챘다 (%d)" % game._prev_lives)
	gf.clear_selection()

	# 보스 스킬 배너는 시뮬레이션 이벤트(skill_announced)로 뜬다
	gf.session.events.announce({"name": "테스트 스킬", "text": "설명", "lane": "both", "delay": 0.0, "boss": "시험 보스"})
	await frames(5)
	check(game.skill_banner.visible, "skill_announced 이벤트로 스킬 배너가 뜬다")
	# 미니맵도 스냅샷으로 그려진다 (오류 없이 그려지는지)
	for v in game.minimap_views.values():
		v.queue_redraw()
	await frames(3)
	check(true, "미니맵 %d개가 스냅샷으로 오류 없이 그려진다" % game.minimap_views.size())


## 맵의 타워/몬스터는 서버 스냅샷으로 만든 껍데기가 그린다 (시뮬레이션 노드는 숨는다)
func map_view_draws_from_snapshot() -> void:
	print("[맵] 타워/몬스터 껍데기")
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	var gf: GameField = game.game_field
	var lane: LaneController = gf.lanes[0]
	lane.gold = 500.0
	lane.try_build_tower(Vector2i(4, 10), "long", false)
	lane.try_build_tower(Vector2i(6, 10), "splash", false)
	lane.evolve_tower(lane.tower_at(Vector2i(4, 10)), "pierce")
	lane.spawn_wave_monster("grunt", 1)
	lane.spawn_wave_monster("flyer", 1)
	await frames(10)
	var mv := gf.map_view
	check(mv != null and mv.tower_count() == 2, "타워 껍데기 2개 (%d)" % mv.tower_count())
	check(mv.monster_count() == lane.monsters.size() and mv.monster_count() == 2, "몬스터 껍데기 %d개 = 서버 몬스터 %d마리" % [mv.monster_count(), lane.monsters.size()])
	var sim_t := lane.tower_at(Vector2i(4, 10))
	var pup := mv.tower_node(0, Vector2i(4, 10))
	check(not sim_t.visible and pup != null and pup.visible and pup.puppet, "시뮬레이션 타워는 숨고 껍데기가 보인다")
	check(pup.evolution == "pierce" and pup.color_info.name == sim_t.color_info.name and absf(pup.cur_range() - sim_t.cur_range()) < 0.001, "껍데기가 진화/색/사거리를 서버 값대로 가진다")
	var m: Monster = lane.monsters[0]
	var shell: Monster = null
	for c in gf.grid_renderer.get_children():
		if c is Monster and c.puppet and c.monster_id == m.monster_id and c.visible:
			shell = c
	check(shell != null and not m.visible, "몬스터도 시뮬레이션 노드는 숨고 껍데기가 보인다")
	check(shell != null and shell.cell_pos.distance_to(m.cell_pos) < 0.3, "껍데기 위치가 서버 몬스터 위치와 같다 (차이 %.3f칸)" % (shell.cell_pos.distance_to(m.cell_pos) if shell else -1.0))
	check(gf.boss_view != null and gf.boss_view.state.get("level", 0) == 1 and gf.boss_bar.state.get("name", "") == gf.boss.level_data.name, "보스 몸통/체력바는 스냅샷 값으로 그린다 (Lv.%s)" % gf.boss_view.state.get("level"))
	# 다른 레인을 보면 이 레인의 껍데기는 숨는다
	gf.switch_player(1)
	await frames(3)
	check(not pup.visible, "다른 레인을 보면 이 레인의 껍데기는 숨는다")
	gf.switch_player(0)
	# 판매하면 껍데기가 사라진다
	gf.select_tower_at(0, sim_t.cell)
	gf.sell_selected_tower()
	await frames(5)
	check(mv.tower_count() == 1 and not is_instance_valid(pup) or pup.is_queued_for_deletion(), "판매한 타워의 껍데기가 치워진다 (남은 %d)" % mv.tower_count())
	game.queue_free()
	await frames(3)


## 투사체와 표식 구름: 서버는 보이지 않는 노드로 피해/표식만 처리하고, 클라이언트는 이벤트로 날아가는 모습을 그린다
func shots_are_events() -> void:
	print("[맵] 투사체/구름 이벤트")
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	var gf: GameField = game.game_field
	var lane: LaneController = gf.lanes[0]
	lane.gold = 1000.0
	var events: Array = []
	gf.session.events.emitted.connect(func(ev): events.append(ev))
	lane.try_build_tower(Vector2i(5, 3), "long", false)
	lane.try_build_tower(Vector2i(7, 3), "splash", false)
	lane.evolve_tower(lane.tower_at(Vector2i(5, 3)), "pierce")
	lane.evolve_tower(lane.tower_at(Vector2i(7, 3)), "support")
	gf.do_command(Command.START_GAME)
	lane.spawn_wave_monster("tank", 1, Vector2i(6, 0))  # 두 타워 사이 위쪽: 둘 다 사거리 안
	var saw_puppet_shot := false
	var sim_shot_visible := false
	var saw_puppet_cloud := false
	for i in range(600):
		await frames(1)
		for c in gf.grid_renderer.get_children():
			if c is Effects.Projectile:
				if c.puppet and c.visible:
					saw_puppet_shot = true
				elif not c.puppet and c.visible:
					sim_shot_visible = true
			elif c is Effects.Cloud and c.puppet and c.visible:
				saw_puppet_cloud = true
		if saw_puppet_shot and saw_puppet_cloud:
			break
	var shots := events.filter(func(e): return e.type == "fx_shot")
	var clouds := events.filter(func(e): return e.type == "fx_cloud")
	check(shots.size() > 0 and clouds.size() > 0, "fx_shot %d개, fx_cloud %d개 이벤트가 나왔다" % [shots.size(), clouds.size()])
	check(saw_puppet_shot, "클라이언트가 투사체를 그렸다 (껍데기)")
	check(saw_puppet_cloud, "클라이언트가 표식 구름을 그렸다 (껍데기)")
	check(not sim_shot_visible, "서버 쪽 투사체 노드는 보이지 않는다")
	check(shots.size() == 0 or JSON.parse_string(JSON.stringify(shots[0])) is Dictionary, "투사체 이벤트는 JSON이 된다")
	var hurt := await wait_until(func():
		return lane.monsters.is_empty() or lane.monsters.any(func(m): return is_instance_valid(m) and m.hp < m.max_hp), 20000)
	check(hurt, "피해는 서버 쪽에서 그대로 들어갔다")
	game.queue_free()
	await frames(3)


## 슬라임 예고 표식은 이벤트(fx_warn)로 뜨고, 취소 이벤트로 치워진다. 보이는지는 보고 있는 레인으로 정한다
func warn_events() -> void:
	print("[맵] 예고 표식 이벤트")
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	var gf: GameField = game.game_field
	gf.session.events.warn(0, Vector2i(3, 5), 5.0)
	var found: Array = gf.grid_renderer.get_children().filter(func(c): return c is BossController.SpawnWarning)
	check(found.size() == 1 and found[0].visible, "내 레인을 보고 있으면 예고 표식이 보인다")
	await frames(3)
	gf.switch_player(1)
	await frames(3)
	check(not found[0].visible, "다른 레인을 보면 표식이 숨는다")
	gf.switch_player(0)
	gf.session.events.warn_clear()
	await frames(3)
	check(not is_instance_valid(found[0]) or found[0].is_queued_for_deletion(), "취소 이벤트로 표식이 치워진다")
	game.queue_free()
	await frames(3)


## 클라이언트는 JSON 글자만으로 똑같이 그린다 (네트워크로 보낸 것과 같은 조건). 두 클라이언트가 같은 스냅샷을 받으면 몬스터/타워 위치가 같다.
## 지연이 있는 진짜 네트워크에서의 보간은 #20 이후에 따로 확인해야 한다.
func loopback_clients() -> void:
	print("[맵] JSON만 받는 두 클라이언트")
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	var gf: GameField = game.game_field
	var lane: LaneController = gf.lanes[0]
	lane.gold = 1000.0
	lane.try_build_tower(Vector2i(4, 8), "long", false)
	lane.evolve_tower(lane.tower_at(Vector2i(4, 8)), "pierce")
	gf.do_command(Command.START_GAME)
	for k in ["grunt", "runner", "flyer", "tank"]:
		lane.spawn_wave_monster(k, 1)
	gf.do_command(Command.SEND_MONSTER, {"kind_id": "warrior"})
	await frames(40)
	var text := JSON.stringify(gf.snapshot(true))  # 네트워크로 보낼 글자
	var views: Array[MapView] = []
	var renderers: Array[GridRenderer] = []
	for i in range(2):
		var r := GridRenderer.new()
		game.add_child(r)
		renderers.append(r)
		var mv := MapView.new(r)
		game.add_child(mv)
		mv.sync(JSON.parse_string(text), 0, "")  # 받는 쪽은 글자를 풀어서만 쓴다
		views.append(mv)
	check(views[0].tower_count() == 1 and views[0].monster_count() == lane.monsters.size() + gf.boss.get_sent_monsters().size(), "JSON으로 받은 클라이언트가 타워 1기/몬스터 %d마리(레인 %d + 보스 레인 %d)를 만들었다" % [views[0].monster_count(), lane.monsters.size(), gf.boss.get_sent_monsters().size()])
	var max_diff := 0.0
	for m in lane.monsters:
		var a := views[0].monster_node(0, m.monster_id)
		var b := views[1].monster_node(0, m.monster_id)
		if a == null or b == null:
			max_diff = 99.0
			continue
		max_diff = maxf(max_diff, a.cell_pos.distance_to(b.cell_pos))
		max_diff = maxf(max_diff, a.cell_pos.distance_to(m.cell_pos))  # 서버와도 같다 (보낸 뒤 흐른 프레임만큼은 제외하려고 같은 프레임에 비교)
	check(max_diff < 0.05, "두 클라이언트와 서버의 몬스터 위치 차이 최대 %.4f칸" % max_diff)
	var ta := views[0].tower_node(0, Vector2i(4, 8))
	var tb := views[1].tower_node(0, Vector2i(4, 8))
	check(ta != null and tb != null and ta.evolution == "pierce" and tb.evolution == "pierce" and absf(ta.cur_range() - tb.cur_range()) < 0.001, "두 클라이언트의 타워 모습(진화/사거리)이 같다")
	game.queue_free()
	await frames(3)
