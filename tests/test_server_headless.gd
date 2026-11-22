extends "res://tests/case_base.gd"
## 이슈 #21 회귀 테스트: UI 없이 서버로 한 판이 끝까지 돈다 / 시뮬레이션 랜덤은 세션 하나를 쓴다 / 강화 버프는 delta로 만료된다.


func run() -> void:
	await _server_runs_without_ui()
	await _rng_is_shared()
	await _empower_expires_by_delta()
	await _pause_only_solo()
	Engine.time_scale = 1.0


## ServerMain은 MainGame/HUD 없이 GameField(레인+보스)만 만들고, 사람이 없어도 한 판이 결과(승/패)로 끝난다.
func _server_runs_without_ui() -> void:
	print("[1] 서버: UI 없이 한 판이 끝난다")
	var server := ServerMain.new()
	server.session.rng.seed = 7
	var events: Array = []
	server.session.events.emitted.connect(func(ev): events.append(ev))
	get_tree().root.add_child.call_deferred(server)
	await frames(8)
	check(server.field != null and server.field.boss != null, "GameField와 보스가 만들어졌다")
	check(get_tree().root.find_children("*", "MainGame", true, false).is_empty(), "MainGame(화면)은 만들어지지 않았다")
	check(server.field.bus.started, "서버가 시작 명령을 실행했다")
	check(server.field.map_view == null and server.field.boss_view == null, "서버에는 타워/몬스터/보스를 그리는 껍데기가 없다")
	Engine.time_scale = 20.0
	var done := await wait_until(func(): return not server.result.is_empty(), 60000)
	Engine.time_scale = 1.0
	check(done, "한 판이 끝났다 (결과: %s)" % [server.result])
	check(server.result.has("victory") and server.result.has("boss_level"), "결과에 승패와 보스 레벨이 있다")
	check(events.size() > 0, "시뮬레이션이 연출 이벤트를 내보냈다 (%d개)" % events.size())
	check(events.all(func(ev): return ev.has("type") and (ev.type not in ["fx_ring", "fx_text"] or (ev.has("lane") and ev.has("pos") and ev.has("color")))), "이벤트는 type을 가진 순수 데이터 (링/글자는 레인/위치/색도)")
	check(JSON.parse_string(JSON.stringify(events[0])) is Dictionary, "이벤트는 JSON이 된다")
	var drawn := 0
	for c in server.field.grid_renderer.get_children():
		if c is Effects.FloatText or c is Effects.Ring:
			drawn += 1
	check(drawn == 0, "서버는 연출을 그리지 않는다 (그려진 이펙트 %d개)" % drawn)
	server.queue_free()
	await frames(3)


## 레인과 보스는 세션이 가진 RandomNumberGenerator 하나를 같이 쓴다 (서버만 뽑는다)
func _rng_is_shared() -> void:
	print("[2] 시뮬레이션 랜덤은 세션 하나")
	var field := (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	field.session.participants = [0, 1]
	get_tree().root.add_child.call_deferred(field)
	await frames(8)
	check(field.lanes[0].rng == field.session.rng and field.lanes[1].rng == field.session.rng, "레인들이 세션 rng를 쓴다")
	check(field.boss.rng == field.session.rng, "보스도 세션 rng를 쓴다")
	# 같은 시드면 같은 순서로 뽑힌다
	var a := RandomNumberGenerator.new()
	var b := RandomNumberGenerator.new()
	a.seed = 42
	b.seed = 42
	var xs := [1, 2, 3, 4, 5, 6]
	var ys := [1, 2, 3, 4, 5, 6]
	SimRandom.shuffle(a, xs)
	SimRandom.shuffle(b, ys)
	check(xs == ys, "같은 시드면 같은 섞임 %s" % [xs])
	check(SimRandom.pick(a, []) == null, "빈 배열에서 고르면 null")
	field.queue_free()
	await frames(3)


## 강화 버프는 벽시계가 아니라 시뮬레이션 delta로만 줄어든다 (일시정지/서버 시간과 항상 맞는다)
func _empower_expires_by_delta() -> void:
	print("[3] 강화 버프는 delta로 만료")
	var m := Monster.new()
	m.add_empower(1.0, 0.5)
	near(m.get_total_empower(), 0.5, "걸린 직후 강화 +0.5")
	m._tick_empower(0.6)
	near(m.get_total_empower(), 0.5, "0.6초 뒤에도 유지")
	m._tick_empower(0.6)
	near(m.get_total_empower(), 0.0, "1.2초 뒤에는 만료")
	m.free()


## 멀티(참여자 2명 이상)에서는 전체 일시정지가 없고, 혼자 하는 판에서는 예전처럼 멈춘다
func _pause_only_solo() -> void:
	print("[4] 일시정지는 혼자 하는 판에서만")
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(game)
	await frames(8)
	game._on_start_pressed()
	await frames(3)
	game._set_paused(true)
	check(get_tree().paused, "혼자 하는 판: 일시정지가 된다")
	game._set_paused(false)
	check(not get_tree().paused and game.pause_button.visible, "혼자 하는 판: 풀리고 버튼이 보인다")
	game.game_field.session.participants.append(1)  # 둘이 하는 판이 되었다
	game._set_paused(true)
	check(not get_tree().paused, "멀티: 일시정지 요청이 거절된다")
	game._notification(NOTIFICATION_WM_WINDOW_FOCUS_OUT)  # 창이 포커스를 잃어도 멈추지 않는다
	check(not get_tree().paused, "멀티: 포커스를 잃어도 멈추지 않는다")
	game._refresh_start_button()
	check(not game.pause_button.visible, "멀티: 시작한 뒤에는 일시정지 버튼이 숨는다")
	game.queue_free()
	await frames(3)
