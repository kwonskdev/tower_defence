extends SceneTree
## 끊김(hitch) 원인 조사용 실행기 (#28). 얇은 실행기: 실제 일은 hitch_probe_sim.gd(Node)가 한다 (-s 스크립트는 autoload(Log)보다 먼저 컴파일된다).
##   Godot --headless --path . -s res://tools/bench/hitch_probe.gd -- [--seconds=60] [--log=debug|info|error] [--no-build] [--no-send] [--players=8] [--stack=N]

func _initialize() -> void:
	var sim: GDScript = load("res://tools/bench/hitch_probe_sim.gd")
	root.add_child(sim.new())
