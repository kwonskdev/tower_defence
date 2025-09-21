extends RefCounted
class_name Logger

enum LogLevel {
	DEBUG = 0,
	INFO = 1,
	WARNING = 2,
	ERROR = 3
}

static var _instance: Logger
static var _log_level: LogLevel = LogLevel.INFO
static var _log_to_file: bool = true
static var _log_file: FileAccess

static func get_instance() -> Logger:
	if _instance == null:
		_instance = Logger.new()
		_init_logger()
	return _instance

static func _init_logger():
	if _log_to_file:
		var log_dir = "user://logs/"
		if not DirAccess.dir_exists_absolute(log_dir):
			DirAccess.open("user://").make_dir_recursive("logs")

		var time = Time.get_datetime_string_from_system().replace(":", "-")
		var log_file_path = log_dir + "game_" + time + ".log"
		_log_file = FileAccess.open(log_file_path, FileAccess.WRITE)

		if _log_file == null:
			push_error("Failed to create log file: " + log_file_path)
		else:
			_log_file.store_line("=== Tower Defense Game Log Started ===")
			_log_file.store_line("Time: " + Time.get_datetime_string_from_system())
			_log_file.store_line("=====================================\n")
			_log_file.flush()

static func set_log_level(level: LogLevel):
	_log_level = level

static func debug(message: String, category: String = "GENERAL"):
	_log(LogLevel.DEBUG, message, category)

static func info(message: String, category: String = "GENERAL"):
	_log(LogLevel.INFO, message, category)

static func warning(message: String, category: String = "GENERAL"):
	_log(LogLevel.WARNING, message, category)

static func error(message: String, category: String = "GENERAL"):
	_log(LogLevel.ERROR, message, category)

static func network_log(message: String, level: LogLevel = LogLevel.INFO):
	_log(level, message, "NETWORK")

static func monster_ai_log(message: String, level: LogLevel = LogLevel.DEBUG):
	_log(level, message, "MONSTER_AI")

static func tower_log(message: String, level: LogLevel = LogLevel.INFO):
	_log(level, message, "TOWER")

static func economy_log(message: String, level: LogLevel = LogLevel.INFO):
	_log(level, message, "ECONOMY")

static func color_system_log(message: String, level: LogLevel = LogLevel.INFO):
	_log(level, message, "COLOR_SYSTEM")

static func ui_log(message: String, level: LogLevel = LogLevel.DEBUG):
	_log(level, message, "UI")

static func game_state_log(message: String, level: LogLevel = LogLevel.INFO):
	_log(level, message, "GAME_STATE")

static func performance_log(message: String):
	var fps = Engine.get_frames_per_second()
	var memory = OS.get_static_memory_usage()
	var full_message = "%s | FPS: %d | Memory: %d bytes" % [message, fps, memory]
	_log(LogLevel.INFO, full_message, "PERFORMANCE")

static func _log(level: LogLevel, message: String, category: String):
	if level < _log_level:
		return

	var timestamp = Time.get_datetime_string_from_system()
	var level_str = _get_level_string(level)
	var formatted_message = "[%s] [%s] [%s] %s" % [timestamp, level_str, category, message]

	match level:
		LogLevel.DEBUG:
			print(formatted_message)
		LogLevel.INFO:
			print(formatted_message)
		LogLevel.WARNING:
			print_rich("[color=yellow]%s[/color]" % formatted_message)
		LogLevel.ERROR:
			print_rich("[color=red]%s[/color]" % formatted_message)
			push_error(message)

	if _log_file != null:
		_log_file.store_line(formatted_message)
		_log_file.flush()

static func _get_level_string(level: LogLevel) -> String:
	match level:
		LogLevel.DEBUG:
			return "DEBUG"
		LogLevel.INFO:
			return "INFO"
		LogLevel.WARNING:
			return "WARNING"
		LogLevel.ERROR:
			return "ERROR"
		_:
			return "UNKNOWN"

static func close_logger():
	if _log_file != null:
		_log_file.store_line("\n=== Tower Defense Game Log Ended ===")
		_log_file.store_line("Time: " + Time.get_datetime_string_from_system())
		_log_file.store_line("===================================")
		_log_file.close()
		_log_file = null