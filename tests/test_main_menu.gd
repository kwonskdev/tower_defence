extends "res://tests/case_base.gd"
## 이슈 #26: 메인 메뉴 (앱 시작 화면).
##  [1] 앱 시작(Boot)은 메인 메뉴를 먼저 띄운다 / [혼자 하기]는 예전 시작과 똑같이 MainGame(로컬)을 열고 시작 버튼으로 시작된다
##  [2] 입력 검사: 서버 주소 모양, 방 코드 모양 (틀리면 접속하지 않고 이유를 보여 준다), 거부 사유 문구
##  [3] [방 만들기] -> 방 코드가 보이고 복사할 수 있다 / 다른 메뉴의 [방 입장]으로 그 코드로 들어와 같은 대기방을 본다 / 없는 코드는 이유가 보인다
##  [4] [빠른 시작] -> 코드 없이 공개 방 대기방으로 / 두 번째 메뉴도 같은 방으로
## (실제 폰/다른 기기와 화면 모양은 눈으로 봐야 한다. 헤드리스에는 클립보드가 없어서 복사는 안내 문구만 확인한다)

const PORT := 47295
const PROFILE := "user://test_main_menu.cfg"


func run() -> void:
	await _boot_solo()
	_inputs()
	await _online()
	DirAccess.remove_absolute(ProjectSettings.globalize_path(PROFILE))
	Engine.time_scale = 1.0


func _menu() -> MainMenu:
	var m := MainMenu.new()
	m.profile_path = PROFILE
	add_child(m)
	return m


# ---- [1] 시작 화면 / 혼자 하기 -------------------------------------------------

func _boot_solo() -> void:
	print("[1] 앱 시작은 메인 메뉴, [혼자 하기]는 지금과 똑같이 동작")
	var boot := (load("res://scenes/main/Boot.tscn") as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(boot)
	await frames(3)
	var menus := boot.find_children("*", "MainMenu", true, false)
	check(menus.size() == 1 and boot.find_children("*", "GameField", true, false).is_empty(), "앱을 켜면 메인 메뉴가 먼저 나오고 게임 화면은 아직 없다")
	var menu: MainMenu = menus[0]
	check(menu.solo_button.visible and menu.create_button.visible and menu.join_button.visible, "[혼자 하기] / [방 만들기] / [방 입장]이 보인다")
	menu.solo_button.pressed.emit()
	await frames(5)
	var fields := boot.find_children("*", "GameField", true, false)
	check(fields.size() == 1 and boot.find_children("*", "MainMenu", true, false).is_empty(), "[혼자 하기]를 누르면 메뉴가 사라지고 게임 화면(MainGame)이 열린다")
	var gf: GameField = fields[0]
	await wait_until(func(): return gf.boss != null, 5000)
	var main_game: Node = boot.get_child(boot.get_child_count() - 1)
	check(gf.session.is_solo() and gf.session.participants == [0] and gf.session.local_player_id == 0, "1인 세션이다 (참여자 [0])")
	await frames(5)
	check(not gf.bus.started and main_game.pause_button.visible, "카운트다운 없이 시작 버튼을 기다린다 (지금과 같다)")
	main_game._on_start_pressed()
	check(gf.bus.started and gf.boss.state == BossController.State.RUNNING, "시작 버튼으로 시작한다")
	boot.queue_free()
	await frames(3)


# ---- [2] 입력 검사 ---------------------------------------------------------

func _inputs() -> void:
	print("[2] 입력 검사와 거부 문구")
	check(MainMenu.parse_server("127.0.0.1:47300") == {"host": "127.0.0.1", "port": 47300}, "서버 주소 호스트:포트")
	check(MainMenu.parse_server(" game.example.com ") == {"host": "game.example.com", "port": MainMenu.DEFAULT_PORT}, "포트가 없으면 기본 포트")
	check(MainMenu.parse_server("").is_empty() and MainMenu.parse_server("host:abc").is_empty() and MainMenu.parse_server(":80").is_empty() and MainMenu.parse_server("h:70000").is_empty(), "틀린 주소는 거절")
	var all_text := true
	for reason in [NetProtocol.REJECT_NO_ROOM, NetProtocol.REJECT_FULL, NetProtocol.REJECT_STARTED, NetProtocol.REJECT_TOO_MANY, NetProtocol.REJECT_BUSY, NetProtocol.REJECT_PROTOCOL]:
		var t := MainMenu.reject_text(reason)
		if t == "" or t.contains(reason):
			all_text = false  # 사유 글자를 그대로 보이면 안 된다
	check(all_text, "거부 사유마다 사람이 읽는 문구가 있다")
	check(MainMenu.reject_text(NetProtocol.REJECT_FULL).contains(str(Balance.MAX_PLAYERS)) and MainMenu.reject_text(NetProtocol.REJECT_NO_ROOM) != MainMenu.reject_text(NetProtocol.REJECT_STARTED), "문구가 사유별로 다르다")


# ---- [3] 방 만들기 / 입장 --------------------------------------------------

func _online() -> void:
	print("[3] 방 만들기 -> 코드 표시/복사 -> 다른 메뉴에서 코드로 입장")
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = PORT
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	var a := _menu()
	await frames(2)
	a.server_edit.text = "127.0.0.1:%d" % PORT
	a.name_edit.text = "방장"
	a.join_button.pressed.emit()  # 코드를 안 쳤다
	check(a.client == null and a.status_label.text.contains(str(RoomCodes.LENGTH)), "코드를 안 치면 접속하지 않고 안내한다 (%s)" % a.status_label.text)
	a.server_edit.text = "127.0.0.1:abc"
	a.create_button.pressed.emit()
	check(a.client == null and a.status_label.text.contains("호스트:포트"), "틀린 서버 주소는 접속하지 않고 안내한다")
	a.server_edit.text = "127.0.0.1:%d" % PORT
	a.create_button.pressed.emit()
	check(await wait_until(func(): return a.lobby_screen != null, 8000), "[방 만들기]로 대기방에 들어왔다")
	var code: String = a.client.room_code
	check(RoomCodes.is_valid_format(code) and a.code_label.text.contains(code) and a.code_label.is_visible_in_tree(), "방 코드가 화면에 보인다: %s" % code)
	var copied := a.copy_code()
	check(copied == code or (copied == "" and a.status_label.text.contains(code)), "코드 복사: 클립보드가 있으면 복사하고, 없으면 코드를 직접 알려 준다 (%s)" % a.status_label.text)
	check(not a.solo_button.is_visible_in_tree() and a.copy_button.is_visible_in_tree(), "대기방에서는 만들기/입장 입력이 숨고 [코드 복사]가 보인다")

	var b := _menu()
	await frames(2)
	b.server_edit.text = "127.0.0.1:%d" % PORT
	b.name_edit.text = "친구"
	b.code_edit.text = "ZZZZZZ" if code != "ZZZZZZ" else "YYYYYY"
	b.join_button.pressed.emit()
	await wait_until(func(): return b.client == null and b.status_label.text != "", 8000)
	check(b.lobby_screen == null and b.status_label.text == MainMenu.reject_text(NetProtocol.REJECT_NO_ROOM), "없는 코드: 이유가 보이고 입력 화면으로 돌아온다 (%s)" % b.status_label.text)
	check(b.join_button.is_visible_in_tree() and not b.join_button.disabled, "다시 시도할 수 있다")
	b.code_edit.text = " " + code.substr(0, 3).to_lower() + "-" + code.substr(3) + " "  # 사람이 친 모양 (소문자, 하이픈, 공백)
	b.join_button.pressed.emit()
	check(await wait_until(func(): return b.lobby_screen != null, 8000), "다른 메뉴에서 그 코드로 입장했다")
	check(b.client.room_code == code and b.client.player_id == 1, "같은 방(%s)의 두 번째 사람" % b.client.room_code)
	await wait_until(func(): return a.client.lobby.get("members", []).size() == 2 and b.client.lobby.get("members", []).size() == 2, 5000)
	check(a.client.lobby.get("members", []).size() == 2 and b.client.lobby.get("members", []).size() == 2, "두 기기가 같은 대기방(2명)을 본다")

	var cfg := ConfigFile.new()
	check(cfg.load(PROFILE) == OK and cfg.get_value("profile", "nickname") == "친구" and cfg.get_value("profile", "server") == "127.0.0.1:%d" % PORT, "닉네임과 서버 주소가 기기에 저장된다")

	# 대기방에서 나가기
	b.lobby_screen.leave_requested.emit()
	await frames(3)
	check(b.client == null and b.join_button.is_visible_in_tree() and b.lobby_screen == null, "[나가기]를 누르면 입력 화면으로 돌아온다")
	await wait_until(func(): return a.client.lobby.get("members", []).size() == 1, 5000)
	check(a.client.lobby.get("members", []).size() == 1, "나간 사람이 방 목록에서 빠진다")
	# [4] 빠른 시작
	print("[4] [빠른 시작]")
	var c := _menu()
	var d := _menu()
	await frames(2)
	for m in [c, d]:
		m.server_edit.text = "127.0.0.1:%d" % PORT
		m.quick_button.pressed.emit()
	check(c.quick_button != null, "[빠른 시작] 버튼이 있다")
	check(await wait_until(func(): return c.lobby_screen != null and d.lobby_screen != null, 8000), "코드를 안 쳐도 대기방에 들어왔다")
	check(c.client.room_code == d.client.room_code and c.client.room_code != code, "두 메뉴가 같은 공개 방에 모였다 (%s)" % c.client.room_code)
	await wait_until(func(): return c.code_label.text.contains("공개 방"), 5000)
	check(c.code_label.text.contains("공개 방") and not a.code_label.text.contains("공개 방"), "공개 방 표시")
	for m in [a, b, c, d]:
		m.queue_free()
	server.queue_free()
	await frames(4)
