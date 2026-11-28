extends "res://tests/case_base.gd"
## 이슈 #67: 방침 3절 "서버 로그는 30일 후 삭제"가 서버 PC의 게임 로그 폴더(user://logs)에도 지켜진다.
##  [1] 마지막 수정이 30일 안인 game_*.log는 남고, 30일이 지나면 지워진다 (시각을 앞당겨서 본다)
##  [2] game_ 로그가 아닌 파일은 건드리지 않는다
##  [3] 30일 안이어도 개수 한도(MAX_LOG_FILES-1개만 남김)는 그대로 지켜진다


func run() -> void:
	await get_tree().process_frame
	var dir := "user://test_log_retention"
	DirAccess.make_dir_recursive_absolute(dir)
	_wipe(dir)
	var now := int(Time.get_unix_time_from_system())
	var day := 86400

	for n in ["game_20260101_000001.log", "game_20260101_000002.log"]:
		_touch("%s/%s" % [dir, n])
	_touch("%s/notes.txt" % dir)

	check(Log.cleanup_old_logs(dir, now + (Log.MAX_LOG_AGE_DAYS - 1) * day) == 0, "30일 안이면 아무것도 안 지운다")
	check(DirAccess.get_files_at(dir).size() == 3, "파일 3개가 그대로 있다")

	var removed: int = Log.cleanup_old_logs(dir, now + (Log.MAX_LOG_AGE_DAYS + 1) * day)
	check(removed == 2, "30일이 지난 게임 로그 2개를 지운다 (지운 수 %d)" % removed)
	check(DirAccess.get_files_at(dir) == PackedStringArray(["notes.txt"]), "게임 로그가 아닌 파일은 남는다 (%s)" % str(DirAccess.get_files_at(dir)))

	for i in range(Log.MAX_LOG_FILES + 3):
		_touch("%s/game_20260102_%06d.log" % [dir, i])
	var removed2: int = Log.cleanup_old_logs(dir, now)
	var games := 0
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("game_"):
			games += 1
	check(games == Log.MAX_LOG_FILES - 1, "30일 안이어도 개수 한도는 지킨다 (남은 %d개, 지운 %d개)" % [games, removed2])

	_wipe(dir)
	DirAccess.remove_absolute(ProjectSettings.globalize_path(dir))


func _touch(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_line("x")
	f.close()


func _wipe(dir: String) -> void:
	for f in DirAccess.get_files_at(dir):
		DirAccess.remove_absolute("%s/%s" % [dir, f])
