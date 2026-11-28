extends "res://tests/case_base.gd"
## 이슈 #28 요구사항 1: 다인원 헤드리스 스모크. 서버(방 코드 서버) 1개 + 봇 클라이언트 N개(1, 2, 8)가 진짜 WebSocket으로 접속해
## 건설/몬스터 보내기 명령만 보내며 판을 끝까지 돌린다 (골드 치트 없음: 사람과 같은 명령). 승/패가 결정되고 크래시/오류가 없는지 본다.
## 오래 걸린다(배속 10에서 인원 수에 따라 몇 분): 평소 전체 실행에서는 건너뛰고, 돌릴 때는
##   Godot --headless --path . -s res://tests/run_tests.gd -- mp_bots          (1/2/8명 전부)
##   Godot --headless --path . -s res://tests/run_tests.gd -- mp_bots n=2      (한 가지 인원만: n=1, n=2, n=8)
## 두 가지 판을 돌린다: "보통"(골드 치트 없음: 봇이 약해서 대개 패배로 끝난다)와 "부자"(서버 쪽에서 골드를 계속 채워 줘서 보스 Lv.10까지 간다: 오래 걸린다).
##   인자 rich를 주면 부자 판만, normal을 주면 보통 판만 돈다.
## 평소 실행에서는 대신 1명짜리 짧은 판(판 시작 뒤 몇 초: 접속/시작/명령/스냅샷)만 확인한다.
## 이 파일이 확인하는 것: 접속 -> 시작 -> 판 끝(game_over 이벤트를 모든 봇이 받음) -> 모든 레인 골드가 한 번도 마이너스가 아님 -> 서버 결과와 봇이 받은 결과가 같음.

const PORT := 47600
const SPEED := 10.0
const MAX_REAL_SEC := 900.0   # 한 판 상한 (실제 시간). 넘으면 "타임아웃"으로 실패


func run() -> void:
	var args := OS.get_cmdline_user_args()
	if not "mp_bots" in args:
		await _short_smoke()
		return
	var sizes: Array = [1, 2, 8]
	for a in args:
		if a.begins_with("n="):
			sizes = [int(a.substr(2))]
	var i := 0
	for n in sizes:
		if not "rich" in args:
			await _full_game(n, PORT + 1 + i, false)
			i += 1
		if not "normal" in args:
			await _full_game(n, PORT + 1 + i, true)
			i += 1
	Engine.time_scale = 1.0


func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _server(port: int) -> ServerMain:
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	return server


## 방장 1 + 손님 n-1명을 접속시켜 모두 판에 들어가게 한다. 봇 목록(방장이 첫째)을 돌려준다.
func _join_all(port: int, n: int, rich := false) -> Array:
	var bots: Array = []
	var code := ""
	for i in range(n):
		var cl := NetClient.new()
		cl.player_name = "봇%d" % i
		cl.join_mode = NetProtocol.MODE_CREATE if i == 0 else NetProtocol.MODE_JOIN
		cl.join_code = code
		add_child(cl)
		cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
		var bot := NetBot.new()
		bot.is_host = i == 0
		bot.smart = true
		if rich:
			bot.send_order = NetBot.RICH_SEND_ORDER
		bot.setup(cl)
		add_child(bot)
		bots.append(bot)
		await wait_until(func(): return cl.is_joined(), 8000)
		if i == 0:
			code = cl.room_code
	await wait_until(func():
		for b in bots:
			b.lobby_step(n)
		return bots.all(func(b): return b.client.in_game), 20000)
	return bots


func _short_smoke() -> void:
	print("[1] 1명 짧은 판: 접속 -> 시작 -> 명령 -> 스냅샷 (전체 판은 인자 mp_bots)")
	var server := await _server(PORT)
	var bots := await _join_all(PORT, 1)
	var bot: NetBot = bots[0]
	check(bot.client.in_game, "봇이 접속해 판에 들어갔다")
	var room := server.hub.room_for(bot.client.room_code)
	check(room != null and room.game_started and room.field.bus.started, "서버 판이 시작됐다")
	check(await wait_until(func(): return bot.ok_count >= 4, 20000), "봇이 보낸 건설/몬스터 보내기가 서버에서 성공한다 (성공 %d, 실패 %s)" % [bot.ok_count, bot.fail_reasons])
	check(bot.snapshots >= 5 and not bot.negative_gold_seen, "스냅샷이 계속 오고 골드는 마이너스가 아니다 (스냅샷 %d)" % bot.snapshots)
	for n in [bot.client, bot, server]:
		n.queue_free()
	await frames(4)


func _full_game(n: int, port: int, rich: bool) -> void:
	print("[봇 %d명, %s] 판 끝까지 (배속 x%s)" % [n, "부자(골드 채움)" if rich else "보통", SPEED])
	var server := await _server(port)
	var bots := await _join_all(port, n, rich)
	check(bots.all(func(b): return b.client.in_game), "봇 %d명이 모두 판에 들어갔다" % n)
	var room: NetServer = server.hub.room_for(bots[0].client.room_code)
	check(room != null and room.field != null and room.field.lanes.size() == n, "서버 판의 레인이 %d개다" % n)
	var gold := {"min": INF}   # 람다는 지역 변수를 값으로 잡으므로 Dictionary에 담는다
	var t0 := Time.get_ticks_msec()
	Engine.time_scale = SPEED
	var done := await wait_until(func():
		for lane in room.field.lanes.values():
			gold.min = minf(gold.min, lane.gold)
			if rich and lane.gold < 3000.0:
				lane.gold = 3000.0  # 서버 쪽 채움 (클라이언트 명령에는 골드를 바꾸는 것이 없다). 채우기 전의 값으로 마이너스를 본다  # 서버 쪽 진짜 값 (스냅샷은 10Hz라서 사이를 놓칠 수 있다)
		return room.finished and bots.all(func(b): return not b.over.is_empty()), int(MAX_REAL_SEC * 1000))
	Engine.time_scale = 1.0
	var secs := (Time.get_ticks_msec() - t0) / 1000.0
	var level: int = room.field.boss.level
	check(done, "판이 끝났다 (실제 %.0f초, 보스 Lv.%d까지)" % [secs, level])
	if done:
		var first: Dictionary = bots[0].over
		check(bots.all(func(b): return b.over == first), "모든 봇이 같은 결과를 받았다 (%s)" % [first])
		check(not first.victory or level == BossLevels.COUNT, "승리는 보스 Lv.%d까지 간 판에서만 나온다" % BossLevels.COUNT)
	check(gold.min >= 0.0 and gold.min < INF, "서버 레인 골드가 한 번도 마이너스가 아니었다 (최저 %.2f)" % gold.min)
	check(not bots.any(func(b): return b.negative_gold_seen), "봇이 받은 스냅샷의 골드도 마이너스가 없다")
	check(bots.all(func(b): return b.ok_count > 0 and b.client.is_joined()), "모든 봇의 명령이 성공했고 연결이 끝까지 유지됐다")
	print("  INFO  봇 %d명 결과 %s, 스냅샷 평균 %d개, 명령 성공/전송 %d/%d, 실패 사유 %s" % [n, bots[0].over, bots.map(func(b): return b.snapshots).reduce(func(a, b): return a + b, 0) / n, bots.map(func(b): return b.ok_count).reduce(func(a, b): return a + b, 0), bots.map(func(b): return b.sent).reduce(func(a, b): return a + b, 0), bots[0].fail_reasons])
	for b in bots:
		b.client.queue_free()
		b.queue_free()
	server.queue_free()
	await frames(4)
