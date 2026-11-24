extends Node
## 시작점. `--server` 인자가 있으면 화면 없이 서버만, `--connect=호스트:포트`가 있으면 접속 확인용 클라이언트(NetProbe, #20), 아니면 평소처럼 MainGame을 띄운다 (#21).
## 클라이언트 경로는 예전과 똑같이 MainGame.tscn 하나를 자식으로 붙이는 것뿐이다.


func _ready() -> void:
	if ServerMain.requested():
		add_child(ServerMain.new())
	elif NetProbe.requested():
		add_child(NetProbe.new())
	else:
		add_child((load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate())
