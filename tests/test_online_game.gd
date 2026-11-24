extends "res://tests/case_base.gd"
## 이슈 #26: 온라인 게임 화면 (방장 시작 -> 모두 서버 스냅샷을 그리는 MainGame -> 명령이 서버로 -> 결과 화면 -> 메뉴로).
##  [1] 서버 1개 + 클라이언트 2개: 방 만들기/입장/준비/시작 -> 둘 다 온라인 MainGame을 연다 (시뮬레이션 없이 스냅샷만 그린다)
##  [2] 건설 명령이 서버로 가서 서버 레인에 생기고, 스냅샷으로 내 화면(MapView/격자)과 상대 화면(보는 레인, 미니맵 요약)에 반영된다
##  [3] 거절 사유가 서버에서 와서 안내된다 / 온라인에서는 일시정지/시작 버튼이 없고 [나가기]가 있다 / 서버에 일시정지 명령은 거절
##  [4] 판 종료(game_over 이벤트) -> 결과 화면(재도전 없음, [메뉴로]) -> exit_requested
##  [5] Boot: 메뉴에서 방 만들기 -> 방장 시작 -> 온라인 게임 화면 -> 메뉴로 복귀 / 연결이 끊기면 사유와 함께 메뉴로 복귀 / 혼자 하기는 그대로
## (폰 화면 모양과 실제 지연은 눈으로 보지 못한다)

const PORT := 47320


func run() -> void:
	await _two_players()
	await _boot_flow()
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


func _client(player_name: String, port: int, mode: String, code := "") -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	cl.join_mode = mode
	cl.join_code = code
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
	return cl


func _own_lane(cl: NetClient) -> bool:
	return cl.snapshot.get("lanes", {}).has(str(cl.player_id))


func _two_players() -> void:
	print("[1] 서버 1개 + 클라이언트 2개: 시작 -> 온라인 화면")
	var server := await _server(PORT)
	var hub: RoomHub = server.hub
	var a := _client("방장", PORT, NetProtocol.MODE_CREATE)
	await wait_until(func(): return a.is_joined(), 8000)
	var b := _client("친구", PORT, NetProtocol.MODE_JOIN, a.room_code)
	await wait_until(func(): return b.is_joined(), 8000)
	b.set_ready(true)
	await wait_until(func(): return a.lobby.get("can_start", false), 5000)
	a.request_start()
	check(await wait_until(func(): return a.in_game and b.in_game and _own_lane(a) and _own_lane(b), 8000), "방장이 시작하면 둘 다 게임에 들어오고 첫 스냅샷(내 레인)을 받는다")
	var room := hub.room_for(a.room_code)
	check(room.field.bus.started and room.field.lanes.size() == 2, "서버 판이 바로 시작했다 (레인 2개)")

	var ma := MainGame.create_online(a)
	var mb := MainGame.create_online(b)
	get_tree().root.add_child.call_deferred(ma)
	get_tree().root.add_child.call_deferred(mb)
	var ga: GameField = ma.find_children("*", "GameField", true, false)[0]
	var gb: GameField = mb.find_children("*", "GameField", true, false)[0]
	await wait_until(func(): return ma.is_inside_tree() and mb.is_inside_tree() and ga.map_view != null and gb.map_view != null, 5000)
	await frames(10)
	check(ga.lanes.is_empty() and ga.boss == null and gb.lanes.is_empty(), "온라인 화면에는 시뮬레이션(레인/보스)이 없다 (서버만 돌린다)")
	check(ga.session.local_player_id == 0 and gb.session.local_player_id == 1 and ga.session.participants == [0, 1], "내 레인 번호와 참여자는 서버가 정한 값")
	check(ga.session.name_of(1) == b.my_name and ma.online and mb.online, "닉네임이 서버가 정한 값으로 세션에 들어 있다")
	check(not ma.pause_button.visible and ma.leave_button.visible and ma._play_running, "온라인: 시작/일시정지 버튼은 없고 [나가기]가 있다")
	ma._set_paused(true)
	check(not get_tree().paused, "온라인에서는 일시정지가 되지 않는다")
	var pause_res := {}
	a.command_result.connect(func(seq, ok, reason, _ev): pause_res[seq] = [ok, reason])
	var sp := a.send(Command.SET_PAUSE, {"on": true})
	await wait_until(func(): return pause_res.has(sp), 5000)
	check(pause_res.get(sp, [true, ""]) == [false, "pause_not_allowed"] and not room.field.bus.paused, "서버도 온라인 방의 일시정지 명령을 거절한다")

	print("[2] 건설 명령이 서버로 가고 스냅샷이 화면에 반영된다")
	var cell := Vector2i(5, 10)
	var gold_before: float = room.field.lanes[0].gold
	check(ga.place_tower(cell), "건설 명령을 보냈다 (결과는 서버가 알려 준다)")
	check(await wait_until(func(): return room.field.lanes[0].tower_at(cell) != null, 5000), "서버 레인 0에 타워가 생겼다")
	check(await wait_until(func(): return ga.map_view.tower_count() == 1, 5000), "내 화면(MapView)이 받은 스냅샷으로 타워를 그린다")
	check(ga.snapshot().lanes["0"].towers.size() == 1 and ga.snapshot().lanes["0"].gold < gold_before, "스냅샷의 타워와 골드(줄어듦)가 반영된다")
	var blocks: bool = Balance.tower_kind(Balance.TOWER_KINDS[0]).blocks
	check(ga.grid_systems[0].get_cell_state(cell) == (GridSystem.CellState.TOWER if blocks else GridSystem.CellState.TRAP_TOWER), "격자의 그 칸이 타워 칸으로 칠해진다")
	check(await wait_until(func(): return not gb.summary_of(0).get("towers", []).is_empty(), 4000), "상대 화면의 미니맵 요약(1Hz)에 그 타워 칸이 온다")
	gb.switch_player(0)  # 상대 레인을 본다: 서버가 그 레인을 자세히 보내 준다
	check(await wait_until(func(): return gb.map_view.tower_count() == 1, 5000), "상대 레인을 보면 그 레인의 타워가 그려진다")
	check(gb.snapshot().lanes.has("0") and gb.snapshot().lanes.has("1"), "스냅샷에 내 레인과 보고 있는 레인이 있다")

	print("[3] 거절 사유")
	var failed := {"reason": ""}
	ga.command_failed.connect(func(_t, reason): failed["reason"] = reason)
	ga.do_command(Command.EVOLVE_TOWER, {"cell": Vector2i(9, 9), "evo": "pierce"})  # 타워가 없는 칸
	check(await wait_until(func(): return failed.reason != "", 5000), "서버가 거절하면 사유가 화면에 알려진다 (%s)" % failed.reason)
	ga.select_tower_at(0, cell)
	check(not ga.get_selected_tower().is_empty(), "스냅샷의 타워를 눌러 선택할 수 있다")
	check(await wait_until(func(): return ma.game_field.snapshot().boss.get("state", -1) == BossController.State.RUNNING, 3000), "스냅샷의 보스 상태가 진행 중이다")

	print("[4] 판 종료 -> 결과 화면 -> 메뉴로")
	var exited := {"v": false}
	ma.exit_requested.connect(func(): exited["v"] = true)
	room.field.session.events.game_over(false, "test")  # 서버 판이 끝났다
	check(await wait_until(func(): return ma.game_over_screen.visible and mb.game_over_screen.visible, 5000), "game_over 이벤트로 두 화면 모두 결과 화면이 뜬다")
	check(not ma.game_over_screen.restart_button.visible and ma.game_over_screen.quit_button.text == "메뉴로", "온라인 결과 화면: 재도전 없음, [메뉴로]")
	check(await wait_until(func(): return not ma.leave_button.visible, 3000), "결과 화면에서는 [나가기]가 숨는다")
	ma.game_over_screen.quit_button.pressed.emit()
	await frames(2)
	check(exited.v, "[메뉴로]를 누르면 exit_requested가 나온다 (Boot가 메뉴로 돌아간다)")
	for n in [ma, mb, a, b, server]:
		n.queue_free()
	await frames(4)


func _boot_flow() -> void:
	print("[5] Boot: 메뉴 -> 방장 시작 -> 온라인 화면 -> 메뉴로 / 연결 끊김 / 혼자 하기")
	var port := PORT + 1
	var server := await _server(port)
	var hub: RoomHub = server.hub
	var boot := (load("res://scenes/main/Boot.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(boot)
	await frames(3)
	var menu: MainMenu = boot.menu
	check(menu != null, "Boot가 메인 메뉴를 띄운다")
	menu.profile_path = "user://test_online_game.cfg"
	menu.server_edit.text = "127.0.0.1:%d" % port
	menu.name_edit.text = "방장"
	menu.create_button.pressed.emit()
	await wait_until(func(): return menu.lobby_screen != null, 8000)
	var code: String = menu.client.room_code
	var friend := _client("친구", port, NetProtocol.MODE_JOIN, code)
	await wait_until(func(): return friend.is_joined(), 8000)
	friend.set_ready(true)
	await wait_until(func(): return menu.client.lobby.get("can_start", false), 5000)
	menu.lobby_screen._start_button.pressed.emit()
	check(await wait_until(func(): return boot.online_game != null and boot.online_game.is_inside_tree(), 8000), "방장이 [시작]을 누르면 메뉴가 사라지고 온라인 게임 화면으로 넘어간다")
	check(boot.menu == null and boot.online_client != null and boot.online_client.in_game and boot.online_game.online, "메뉴의 접속을 그대로 넘겨 받았다")
	check(await wait_until(func(): return boot.online_game.game_field.map_view != null and hub.room_for(code).field != null, 5000), "화면과 서버 판이 준비됐다")
	var game: MainGame = boot.online_game
	game.exit_requested.emit()  # [나가기] 확인 또는 결과 화면의 [메뉴로]
	await frames(3)
	check(boot.online_game == null and boot.online_client == null and boot.menu != null, "나가면 접속을 닫고 메인 메뉴로 돌아온다")
	check(await wait_until(func(): return hub.room_for(code) != null and hub.room_for(code).joined_count() == 1, 5000), "서버 방에서 그 사람이 빠졌다 (친구만 남음)")

	# 연결이 끊기면 사유와 함께 메뉴로
	menu = boot.menu
	menu.profile_path = "user://test_online_game.cfg"
	menu.server_edit.text = "127.0.0.1:%d" % port
	menu.create_button.pressed.emit()
	await wait_until(func(): return menu.lobby_screen != null, 8000)
	var code2: String = menu.client.room_code
	menu.lobby_screen._start_button.pressed.emit()  # 혼자 방: 방장 혼자 시작
	check(await wait_until(func(): return boot.online_game != null, 8000), "혼자 만든 방도 시작하면 온라인 화면")
	await frames(5)
	hub._close_room(code2, "test")  # 서버가 방을 닫는다 (연결이 끊긴다)
	check(await wait_until(func(): return boot.online_game == null and boot.menu != null, 5000), "연결이 끊기면 메뉴로 돌아온다")
	check(boot.menu.status_label.text.contains("끊"), "끊긴 사유가 메뉴에 보인다 (%s)" % boot.menu.status_label.text)

	# 혼자 하기는 그대로
	boot.menu.solo_button.pressed.emit()
	await frames(5)
	var fields := boot.find_children("*", "GameField", true, false)
	check(fields.size() == 1 and fields[0].remote == null and not fields[0].lanes.is_empty(), "[혼자 하기]는 로컬 시뮬레이션(MainGame)이다")
	DirAccess.remove_absolute(ProjectSettings.globalize_path("user://test_online_game.cfg"))
	friend.queue_free()
	boot.queue_free()
	server.queue_free()
	await frames(4)
