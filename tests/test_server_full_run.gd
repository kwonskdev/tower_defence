extends "res://tests/case_base.gd"
## 이슈 #21 체크리스트: 서버 프로세스가 UI 없이 보스 Lv.1~10을 끝까지 돌려 결과를 낸다.
## 오래 걸려서(배속 10에서 약 3분) 평소 전체 실행에서는 건너뛴다. 돌릴 때:
##   Godot --headless --path . -s res://tests/run_tests.gd -- full_run
## 골드 치트는 서버 쪽 테스트 봇(AutoPlayer.cheat_gold)에만 있다. 클라이언트 명령에는 골드를 바꾸는 것이 없다.


func run() -> void:
	if not "full_run" in OS.get_cmdline_user_args():
		print("  SKIP  서버 전체 한 판 (오래 걸려서 건너뜀. 인자 full_run으로 실행)")
		pass_n += 1
		return
	var players := 2
	var server := ServerMain.new()
	server.session.participants.clear()
	for i in range(players):
		server.session.participants.append(i)
	server.session.rng.seed = 7
	get_tree().root.add_child.call_deferred(server)
	await frames(8)
	for pid in server.session.participants:
		var bot := AutoPlayer.new()
		bot.cheat_gold = true
		server.add_child(bot)
		bot.setup(server.field.bus, pid)
	Engine.time_scale = 10.0
	var levels: Array = []
	server.field.boss.level_started.connect(func(l): levels.append(l))
	var done := await wait_until(func(): return not server.result.is_empty(), 600000)
	Engine.time_scale = 1.0
	check(done, "한 판이 끝났다")
	check(server.result.get("victory", false), "승리로 끝났다 (결과 %s)" % [server.result])
	check(server.result.get("boss_level", 0) == BossLevels.COUNT, "보스 Lv.%d까지 갔다" % BossLevels.COUNT)
	check(get_tree().root.find_children("*", "MainGame", true, false).is_empty(), "그동안 화면(MainGame)은 없었다")
	server.queue_free()
	await frames(3)
