extends Node
## 시작점. `--server` 인자가 있으면 화면 없이 서버만, `--connect=호스트:포트`가 있으면 접속 확인용 클라이언트(NetProbe, #20), 아니면 메인 메뉴를 띄운다 (#26).
## 메인 메뉴의 [혼자 하기]는 예전 시작과 똑같이 MainGame.tscn 하나를 자식으로 붙이는 것뿐이다 (#21). `--solo` 인자를 주면 메뉴 없이 바로 MainGame (개발/스크립트용).


func _ready() -> void:
	if ServerMain.requested():
		add_child(ServerMain.new())
	elif NetProbe.requested():
		add_child(NetProbe.new())
	elif "--solo" in OS.get_cmdline_args() or "--solo" in OS.get_cmdline_user_args():
		_start_solo()
	else:
		var menu := MainMenu.new()
		menu.solo_chosen.connect(func():
			menu.queue_free()
			_start_solo())
		add_child(menu)


func _start_solo() -> void:
	add_child((load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate())
