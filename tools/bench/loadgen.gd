extends SceneTree
## 서버 부하 측정용 봇 접속기 (#24). 얇은 실행기: 실제 일은 loadgen_sim.gd(Node)가 한다 (-s 스크립트는 autoload(Log)보다 먼저 컴파일된다).
## 서버는 따로 띄운다 (tools/bench/run_bench.sh 참고):
##   Godot --headless --path . -s res://tools/bench/loadgen.gd -- --host=127.0.0.1 --port=47410 --rooms=2 --seconds=120

func _initialize() -> void:
	var sim: GDScript = load("res://tools/bench/loadgen_sim.gd")
	root.add_child(sim.new())
