extends "res://tests/case_base.gd"
## 화면 비교용 스크린샷. 창 모드(--headless 없이)에서만 의미가 있다. 평소 실행에서는 건너뛴다.
##   Godot --path . -s res://tests/run_tests.gd -- screenshot --shot=C:/경로/before.png
## 같은 상황(타워 몇 기 + 몬스터 몇 마리 + 진화/선택)을 만들어 한 장 찍는다. 구조를 바꾼 앞뒤를 눈으로 비교할 때 쓴다.


func run() -> void:
	if not "screenshot" in OS.get_cmdline_user_args():
		print("  SKIP  스크린샷 (인자 screenshot으로 실행)")
		pass_n += 1
		await frames(1)
		return
	var path := ""
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--shot="):
			path = a.substr(7)
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(10)
	var gf: GameField = game.game_field
	var lane: LaneController = gf.lanes[0]
	lane.gold = 5000.0
	gf.session.rng.seed = 3
	var cells := [Vector2i(3, 6), Vector2i(7, 6), Vector2i(5, 9), Vector2i(2, 12), Vector2i(8, 12), Vector2i(5, 15)]
	var kinds := ["long", "splash", "air", "trap", "long", "splash"]
	for i in range(cells.size()):
		lane.try_build_tower(cells[i], kinds[i], false)
	lane.evolve_tower(lane.tower_at(cells[0]), "pierce")
	lane.evolve_tower(lane.tower_at(cells[1]), "mass")
	gf.do_command(Command.START_GAME)
	for t in ["grunt", "runner", "tank", "flyer", "swarm", "armored"]:
		lane.spawn_wave_monster(t, 1)
	await frames(1)
	gf.select_tower(lane.tower_at(cells[0]))
	if "--lane=boss" in OS.get_cmdline_user_args():  # 보스 레인: 보낸 몬스터와 보스를 본다
		for k in ["worker", "warrior", "knight", "cheer"]:
			gf.do_command(Command.SEND_MONSTER, {"kind_id": k})
		gf.switch_player(GameField.BOSS_LANE_ID)
		await wait_seconds(8.0)
	else:
		await wait_seconds(2.5)
	var img := get_viewport().get_texture().get_image()
	if path != "":
		img.save_png(path)
		print("  스크린샷 저장: ", path, " ", img.get_size())
	check(img.get_size().x > 0, "화면을 캡처했다")
	game.queue_free()
	await frames(3)


func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout
