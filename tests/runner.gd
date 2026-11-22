extends Node
## tests/test_*.gd를 하나씩 돌린다. 각 테스트는 CaseBase(case_base.gd)를 상속하고, 끝나면 finished 신호를 보낸다.

func _ready() -> void:
	var filters: Array = Array(OS.get_cmdline_user_args())
	var files: Array[String] = []
	for f in DirAccess.get_files_at("res://tests"):
		if f.begins_with("test_") and f.ends_with(".gd"):
			if filters.is_empty() or filters.any(func(x): return f.contains(x)):
				files.append(f)
	files.sort()
	var failed := 0
	var total := 0
	for f in files:
		print("=== ", f, " ===")
		var script: GDScript = load("res://tests/" + f)
		if script == null or not script.can_instantiate():  # 파싱/컴파일 오류: 멈춰 있지 말고 실패로 세고 다음 파일로 간다
			printerr("  FAIL  테스트를 불러오지 못했다 (파싱 오류): ", f)
			failed += 1
			total += 1
			continue
		var test: Node = script.new()
		add_child(test)
		await test.finished
		failed += test.fail_n
		total += test.pass_n + test.fail_n
		test.queue_free()
	print("ALL: %d checks, %d failed (%d files)" % [total, failed, files.size()])
	get_tree().quit(1 if failed > 0 or files.is_empty() else 0)
