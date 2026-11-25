extends SceneTree
## 부하 측정용 서버 실행기 (#24): 운영과 같은 ServerMain(방 코드 서버)을 띄우고, --stack=N이 있으면 몬스터 적체 주입기를 붙인다.
## 인자는 운영 서버와 같다 (--port --max-rooms --max-rooms-per-addr --max-fps --metrics-interval ...). 얇은 실행기라 실제 일은 bench_server_sim.gd가 한다.

func _initialize() -> void:
	var sim: GDScript = load("res://tools/bench/bench_server_sim.gd")
	root.add_child(sim.new())
