extends Node
## 전역 로깅 시스템 (오토로드 이름: Log)
##
## 사용 예:
##   Log.info(Log.Category.TOWER, "타워 건설 pos=%s" % pos)
##   Log.error(Log.Category.NETWORK, "연결 실패")
##
## - 레벨: DEBUG < INFO < WARNING < ERROR
## - 카테고리별로 최소 레벨을 따로 지정 가능 (set_category_level)
## - 콘솔 + 파일(user://logs/)에 동시에 기록, 오래된 로그 파일은 자동 삭제
## - WARNING/ERROR는 Godot 디버거 패널에도 표시(push_warning/push_error)
## - 디버그 빌드에서는 주기적으로 FPS/메모리 로그를 남김

signal log_emitted(level: Level, category: Category, message: String)

enum Level { DEBUG, INFO, WARNING, ERROR }

# 기획서의 필수 로깅 영역에 대응
enum Category { SYSTEM, GRID, TOWER, MONSTER_AI, ECONOMY, COLOR, UI, NETWORK, GAME, PERF }

const LOG_DIR := "user://logs"
const MAX_LOG_FILES := 10
## 방침(#27, #67): 서버 로그는 30일 후 삭제한다. 서버는 닉네임이 든 같은 출력을 이 폴더에도 남기므로 개수(MAX_LOG_FILES)뿐 아니라 기간으로도 지운다.
## 기준은 파일의 마지막 수정 시각이다 (오래 켜 둔 서버의 현재 파일은 계속 쓰이므로 지워지지 않는다).
const MAX_LOG_AGE_DAYS := 30
const PERF_INTERVAL_SEC := 30.0

# 최근 로그 보관 (디버그 오버레이 등에서 사용 예정)
const RECENT_LIMIT := 200
var recent_logs: Array[String] = []

var min_level: Level = Level.DEBUG if OS.is_debug_build() else Level.INFO
var _category_levels: Dictionary = {}  # Category -> Level (전역 설정보다 우선)
var _file: FileAccess
var _perf_timer: Timer


func _ready() -> void:
	_open_log_file()
	info(Category.SYSTEM, "로거 시작 (빌드=%s, 최소레벨=%s, Godot %s)" % [
		"debug" if OS.is_debug_build() else "release",
		Level.keys()[min_level],
		Engine.get_version_info().string,
	])

	if OS.is_debug_build():
		_perf_timer = Timer.new()
		_perf_timer.wait_time = PERF_INTERVAL_SEC
		_perf_timer.timeout.connect(_log_performance)
		add_child(_perf_timer)
		_perf_timer.start()


func _exit_tree() -> void:
	if _file:
		info(Category.SYSTEM, "로거 종료")
		_file.close()
		_file = null


func debug(category: Category, message: String) -> void:
	_log(Level.DEBUG, category, message)


func info(category: Category, message: String) -> void:
	_log(Level.INFO, category, message)


func warn(category: Category, message: String) -> void:
	_log(Level.WARNING, category, message)


func error(category: Category, message: String) -> void:
	_log(Level.ERROR, category, message)


## 특정 카테고리의 최소 레벨을 따로 지정 (예: 길찾기만 DEBUG로 보기)
func set_category_level(category: Category, level: Level) -> void:
	_category_levels[category] = level


func clear_category_level(category: Category) -> void:
	_category_levels.erase(category)


func _log(level: Level, category: Category, message: String) -> void:
	var threshold: Level = _category_levels.get(category, min_level)
	if level < threshold:
		return

	var line := "[%s][%-7s][%-10s] %s" % [
		_timestamp(),
		Level.keys()[level],
		Category.keys()[category],
		message,
	]

	print(line)
	match level:
		Level.WARNING:
			push_warning(line)
		Level.ERROR:
			push_error(line)

	if _file:
		_file.store_line(line)
		# 크래시 직전 로그가 유실되지 않도록 WARNING 이상은 즉시 flush
		if level >= Level.WARNING:
			_file.flush()

	recent_logs.append(line)
	if recent_logs.size() > RECENT_LIMIT:
		recent_logs.pop_front()

	log_emitted.emit(level, category, message)


func _timestamp() -> String:
	var t := Time.get_time_dict_from_system()
	return "%02d:%02d:%02d.%03d" % [t.hour, t.minute, t.second, Time.get_ticks_msec() % 1000]


func _open_log_file() -> void:
	DirAccess.make_dir_recursive_absolute(LOG_DIR)
	_cleanup_old_logs()

	var d := Time.get_datetime_dict_from_system()
	var path := "%s/game_%04d%02d%02d_%02d%02d%02d.log" % [
		LOG_DIR, d.year, d.month, d.day, d.hour, d.minute, d.second,
	]
	_file = FileAccess.open(path, FileAccess.WRITE)
	if _file == null:
		# 파일 로깅 실패해도 콘솔 로깅은 계속 동작
		push_warning("로그 파일을 열 수 없음: %s (err=%d)" % [path, FileAccess.get_open_error()])
	else:
		print("로그 파일: ", ProjectSettings.globalize_path(path))


func _cleanup_old_logs() -> void:
	cleanup_old_logs(LOG_DIR, int(Time.get_unix_time_from_system()))


## dir의 game_*.log 중 (1) 마지막 수정이 MAX_LOG_AGE_DAYS일보다 오래된 것, (2) 그걸 빼고도 새 파일 하나를 더하면 MAX_LOG_FILES개를 넘는 오래된 것을 지운다.
## now_unix를 받는 이유는 시험에서 시각을 앞당겨 보기 위해서다. 지운 개수를 돌려준다.
func cleanup_old_logs(dir: String, now_unix: int) -> int:
	var files: Array[String] = []
	for f in DirAccess.get_files_at(dir):
		if f.begins_with("game_") and f.ends_with(".log"):
			files.append(f)
	files.sort()  # 파일명에 날짜가 있어 오름차순 = 오래된 순

	var removed := 0
	var kept: Array[String] = []
	var cutoff := now_unix - MAX_LOG_AGE_DAYS * 86400
	for f in files:
		var path := "%s/%s" % [dir, f]
		if FileAccess.get_modified_time(path) < cutoff:
			if DirAccess.remove_absolute(path) == OK:
				removed += 1
				continue
		kept.append(f)

	# 새 파일 하나가 추가될 것이므로 MAX-1개만 남김
	var to_delete := kept.size() - (MAX_LOG_FILES - 1)
	for i in range(maxi(to_delete, 0)):
		if DirAccess.remove_absolute("%s/%s" % [dir, kept[i]]) == OK:
			removed += 1
	return removed


func _log_performance() -> void:
	debug(Category.PERF, "FPS=%d, 정적메모리=%.1fMB, 노드=%d" % [
		Engine.get_frames_per_second(),
		OS.get_static_memory_usage() / 1048576.0,
		get_tree().get_node_count(),
	])
