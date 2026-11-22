extends "res://tests/case_base.gd"
## 이슈 #21: 몬스터가 아주 많을 때 스냅샷을 만드는 비용이 프레임 예산 안에 있는가. 숫자를 출력하고 넉넉한 상한(프레임 예산 16ms의 절반)만 검사한다.


func run() -> void:
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	var gf: GameField = game.game_field
	var lane: LaneController = gf.lanes[0]
	lane.gold = 100000.0
	for i in range(40):
		lane.try_build_tower(Vector2i(1 + (i % 5) * 2, 6 + (i / 5) * 2), "long", false)
	gf.do_command(Command.START_GAME)
	for i in range(300):
		lane.spawn_wave_monster("swarm", 1)
	await frames(5)
	var n := 30
	var t0 := Time.get_ticks_usec()
	for i in range(n):
		Snapshot.build(gf.session, gf.lanes, gf.boss)
	var build_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / n
	var snap := gf.snapshot(true)
	t0 = Time.get_ticks_usec()
	for i in range(n):
		gf.map_view.sync(snap, 0, "")
	var sync_ms := float(Time.get_ticks_usec() - t0) / 1000.0 / n
	var bytes := JSON.stringify(snap).length()
	print("  스냅샷 몬스터 %d마리, 타워 %d기: 만들기 %.2fms, 껍데기 맞추기 %.2fms, JSON %d바이트" % [lane.monsters.size(), lane.towers.size(), build_ms, sync_ms, bytes])
	check(build_ms < 8.0, "스냅샷 만들기 %.2fms < 8ms" % build_ms)
	check(sync_ms < 8.0, "껍데기 맞추기 %.2fms < 8ms" % sync_ms)
	game.queue_free()
	await frames(3)
