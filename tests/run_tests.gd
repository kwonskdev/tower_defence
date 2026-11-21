extends SceneTree
## 헤드리스 회귀 테스트 실행기. 프로젝트 루트에서:
##   Godot --headless --path . -s res://tests/run_tests.gd              (tests/test_*.gd 전부)
##   Godot --headless --path . -s res://tests/run_tests.gd -- sell_tower (이름에 sell_tower가 들어간 것만)
## 실패가 하나라도 있으면 종료 코드 1.
## 이 파일이 직접 게임 클래스(GameField 등)를 참조하면 autoload(Log)보다 먼저 컴파일되어 깨진다.
## 그래서 얇게 두고, 실제 일은 runner.gd(Node)가 한다.

func _initialize() -> void:
	var runner: GDScript = load("res://tests/runner.gd")
	if runner == null or not runner.can_instantiate():  # 컴파일 오류면 멈춰 있지 말고 실패로 끝낸다
		printerr("tests/runner.gd를 불러오지 못했다")
		quit(2)
		return
	root.add_child(runner.new())
