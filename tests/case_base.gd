extends Node
## 테스트 공통 도구. 테스트는 이 파일을 상속하고 run()을 구현한다 (class_name을 쓰지 않아 전역 클래스를 늘리지 않는다).

signal finished

var pass_n := 0
var fail_n := 0


func _ready() -> void:
	Identity.resume_path = "user://test_resume.cfg"  # 테스트가 실제 앱의 복귀 정보(user://resume.cfg)를 건드리지 않게 (#23)
	await run()
	print("RESULT: pass=%d fail=%d" % [pass_n, fail_n])
	finished.emit()


func run() -> void:
	pass


func check(cond: bool, what: String) -> void:
	if cond:
		pass_n += 1
		print("  PASS  ", what)
	else:
		fail_n += 1
		print("  FAIL  ", what)


## 소수 비교 (골드는 소수점까지 들고 있다)
func near(actual: float, expected: float, what: String) -> void:
	check(absf(actual - expected) < 0.000001, "%s (기대 %s, 실제 %s)" % [what, expected, actual])


func frames(n: int) -> void:
	for i in range(n):
		await get_tree().process_frame


## cond가 참이 될 때까지 프레임을 돈다. timeout_ms 안에 안 되면 false.
func wait_until(cond: Callable, timeout_ms: int = 15000) -> bool:
	var t0 := Time.get_ticks_msec()
	while Time.get_ticks_msec() - t0 < timeout_ms:
		if cond.call():
			return true
		await get_tree().process_frame
	return false
