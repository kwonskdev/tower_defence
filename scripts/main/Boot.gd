extends Node
## 시작점. `--server` 인자가 있으면 화면 없이 서버만, `--connect=호스트:포트`가 있으면 접속 확인용 클라이언트(NetProbe, #20), 아니면 메인 메뉴를 띄운다 (#26).
## 메인 메뉴의 [혼자 하기]는 예전 시작과 똑같이 MainGame.tscn 하나를 자식으로 붙이는 것뿐이다 (#21). `--solo` 인자를 주면 메뉴 없이 바로 MainGame (개발/스크립트용).
## 온라인: 메뉴에서 방장이 시작하면(online_started) 메뉴의 접속을 넘겨 받아, 서버 스냅샷을 그리는 온라인 게임 화면(MainGame.create_online)으로 간다.
## 판이 끝나 [메뉴로]를 누르거나, 나가거나, 연결이 끊기면(결과 화면을 보는 중이 아니면) 접속을 닫고 메인 메뉴로 돌아온다 (끊겼으면 사유와 함께).

const FIRST_SNAPSHOT_TIMEOUT := 8.0   # 시작 메시지를 받은 뒤 첫 스냅샷을 이만큼 기다린다

var online_client: NetClient = null
var online_game: MainGame = null
var menu: MainMenu = null


func _ready() -> void:
	if ServerMain.requested():
		add_child(ServerMain.new())
	elif NetProbe.requested():
		add_child(NetProbe.new())
	elif "--solo" in OS.get_cmdline_args() or "--solo" in OS.get_cmdline_user_args():
		_start_solo()
	else:
		show_menu()


func show_menu(message := "") -> void:
	menu = MainMenu.new()
	menu.solo_chosen.connect(func():
		menu.queue_free()
		menu = null
		_start_solo())
	menu.online_started.connect(_enter_online)
	add_child(menu)
	if message != "":
		menu.show_message(message)


func _start_solo() -> void:
	add_child((load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate())


## 메뉴가 방장 시작을 알렸다: 접속을 넘겨 받고, 내 레인의 첫 스냅샷이 오면 온라인 게임 화면을 연다
func _enter_online() -> void:
	online_client = menu.take_client()
	menu.queue_free()
	menu = null
	add_child(online_client)
	online_client.keep_open = false
	online_client.disconnected.connect(_on_online_disconnected)
	online_client.link_lost.connect(_on_online_link_lost)
	online_client.reconnect_failed.connect(_on_reconnect_failed)
	if _has_own_lane():
		_start_online_game()
		return
	online_client.snapshot_received.connect(_on_first_snapshot)
	get_tree().create_timer(FIRST_SNAPSHOT_TIMEOUT).timeout.connect(func():
		if online_client != null and online_game == null:
			leave_online("서버에서 게임 화면을 받지 못했습니다."))


func _has_own_lane() -> bool:
	return online_client != null and online_client.snapshot.get("lanes", {}).has(str(online_client.player_id))


func _on_first_snapshot(_snap: Dictionary) -> void:
	if online_game == null and _has_own_lane():
		_start_online_game()


func _start_online_game() -> void:
	online_game = MainGame.create_online(online_client)
	online_game.exit_requested.connect(func(): leave_online(""))
	add_child(online_game)


## 판 중 연결이 끊겼다: 결과를 보는 중이면 다시 접속할 필요가 없다. 아니면 NetClient가 자동으로 다시 접속하고 MainGame이 "재접속 중" 화면을 띄운다 (#23)
func _on_online_link_lost() -> void:
	if online_game != null and online_game.is_game_over():
		online_client.stop_reconnect()


## 유예 안에 돌아오지 못했다 (유예 끝 / 서버가 거부): 메뉴로 돌아간다
func _on_reconnect_failed(reason: String) -> void:
	if online_game != null and online_game.is_game_over():
		leave_online("")
		return
	leave_online(MainMenu.reconnect_fail_text(reason))


func _on_online_disconnected() -> void:
	if online_game != null and online_game.is_game_over():
		return  # 결과를 보고 있는 중: 서버가 끝난 방을 닫아도 [메뉴로]를 누를 때까지 둔다
	leave_online("서버와 연결이 끊겼습니다.")


## 온라인 판/접속을 정리하고 메인 메뉴로 돌아온다
func leave_online(message: String) -> void:
	Identity.clear_resume()  # 나갔으니 이 판으로 돌아올 일이 없다 (앱 재시작 복귀 정보도 지운다)
	if online_client != null:
		online_client.disconnected.disconnect(_on_online_disconnected)
		online_client.link_lost.disconnect(_on_online_link_lost)
		online_client.reconnect_failed.disconnect(_on_reconnect_failed)
		online_client.leave()  # 서버에 나간다고 알려 유예 없이 바로 이탈로 처리하게 한다 (연결이 없으면 그냥 닫는다)
		online_client.queue_free()
		online_client = null
	if online_game != null:
		online_game.queue_free()
		online_game = null
	if menu == null:
		show_menu(message)
