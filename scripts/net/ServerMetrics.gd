class_name ServerMetrics
extends Node
## 서버 지표 (#24): 방 수 / 접속자 수 / 틱(프레임) 시간 / 메모리를 한 줄로 주기적으로 로그에 남긴다.
## `docker logs 컨테이너 | grep METRICS` 또는 journalctl로 볼 수 있다. 방 코드 서버(RoomHub)에 붙는다.
##
## 한 줄 예: METRICS rooms=3 (대기 1, 진행 2, 끝남 0) players=9 conns=9 monsters=412 frame_avg=16.7ms frame_max=21.9ms work_avg=2.1ms work_max=6.4ms mem=212.4MB peak_rooms=3 peak_conns=9
##   - frame_*: 프레임 사이의 실제 시간(ms). 서버 프레임 상한(기본 60fps)이면 16.7 근처가 정상이고, 커지면 서버가 밀리는 것이다.
##   - work_*: 한 프레임에서 서버가 실제로 일한 시간(ms): 모든 노드의 _process와 _physics_process 호출을 처음(이 노드, 우선순위 가장 앞)과 끝(Tail, 가장 뒤)에서 재서 더한 값.
##     프레임 예산(60fps면 16.7ms) 대비 얼마나 여유가 있는지 본다. (엔진의 Performance.TIME_PROCESS는 헤드리스에서 실제 프레임 시간보다 훨씬 크게 나와서(측정: 프레임 8ms인데 150ms) 쓰지 않는다.)
##   - cpu: (Linux만) 이 프로세스가 구간 동안 쓴 CPU 시간 / 실제 시간. 100%는 코어 하나를 꽉 쓴다. rss: (Linux만) 실제 메모리. Windows/macOS에서는 줄에서 빠진다.
##   - 구간(interval) 안의 평균/최댓값이다. 이 구간이 지나면 다시 센다. peak_*는 서버를 켠 뒤의 최대.

const DEFAULT_INTERVAL_SEC := 60.0

var hub: RoomHub = null
var interval_sec := DEFAULT_INTERVAL_SEC   # 0이면 로그를 남기지 않는다 (측정은 계속)
var last := {}                              # 마지막으로 남긴 지표 (테스트/외부 점검용)
var peak_rooms := 0
var peak_conns := 0

var _elapsed := 0.0
var _frames := 0
var _frame_sum := 0.0
var _frame_max := 0.0
var _work_sum := 0.0
var _work_max := 0.0
var _prev_usec := 0
var _proc_start_usec := 0
var _phys_start_usec := 0
var _work_frame_usec := 0     # 이번 프레임에 지금까지 쌓인 일한 시간 (process + physics)
var _cpu_ticks_prev := -1.0
var _cpu_wall_prev_usec := 0


func setup(p_hub: RoomHub, p_interval_sec: float = DEFAULT_INTERVAL_SEC) -> void:
	hub = p_hub
	interval_sec = p_interval_sec


func _ready() -> void:
	# 가장 먼저/가장 나중에 불리게 해서 그 사이(= 서버가 한 일)를 잰다
	process_priority = -1000000
	process_physics_priority = -1000000
	var tail := Tail.new()
	tail.owner_metrics = self
	tail.process_priority = 1000000
	tail.process_physics_priority = 1000000
	add_child(tail)


## 우선순위가 가장 뒤인 노드: 프레임의 일이 끝난 시각을 알려 준다
class Tail extends Node:
	var owner_metrics: ServerMetrics

	func _process(_delta: float) -> void:
		owner_metrics._process_end()

	func _physics_process(_delta: float) -> void:
		owner_metrics._physics_end()


func _physics_process(_delta: float) -> void:
	_phys_start_usec = Time.get_ticks_usec()


func _physics_end() -> void:
	_work_frame_usec += Time.get_ticks_usec() - _phys_start_usec


func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	_proc_start_usec = now
	if _prev_usec != 0:
		var frame_ms := float(now - _prev_usec) / 1000.0
		_frame_sum += frame_ms
		_frame_max = maxf(_frame_max, frame_ms)
		_frames += 1
		_elapsed += frame_ms / 1000.0
	_prev_usec = now


func _process_end() -> void:
	var work_ms := float(_work_frame_usec + Time.get_ticks_usec() - _proc_start_usec) / 1000.0
	_work_frame_usec = 0
	_work_sum += work_ms
	_work_max = maxf(_work_max, work_ms)
	if interval_sec > 0.0 and _elapsed >= interval_sec:
		report()


## 지금 구간의 지표를 모아 로그에 남기고 구간을 다시 시작한다. 모은 값을 돌려준다.
func report() -> Dictionary:
	last = collect()
	if hub != null:
		Log.info(Log.Category.PERF, line_of(last))
	_reset_window()
	return last


## 방/접속자 수(지금 값)와 이번 구간의 프레임 시간을 모은다
func collect() -> Dictionary:
	var stats := hub.stats() if hub != null else {}
	var n := maxi(1, _frames)
	var m := {
		"rooms": int(stats.get("rooms", 0)),
		"waiting": int(stats.get("waiting", 0)),
		"playing": int(stats.get("playing", 0)),
		"finished": int(stats.get("finished", 0)),
		"players": int(stats.get("players", 0)),
		"conns": int(stats.get("conns", 0)),
		"monsters": int(stats.get("monsters", 0)),
		"frame_avg_ms": _frame_sum / n,
		"frame_max_ms": _frame_max,
		"work_avg_ms": _work_sum / n,
		"work_max_ms": _work_max,
		"mem_mb": float(OS.get_static_memory_usage()) / 1048576.0,
	}
	var cpu := _cpu_percent()
	if cpu >= 0.0:
		m["cpu_pct"] = cpu
		m["rss_mb"] = rss_mb()
	peak_rooms = maxi(peak_rooms, m.rooms)
	peak_conns = maxi(peak_conns, m.conns)
	m["peak_rooms"] = peak_rooms
	m["peak_conns"] = peak_conns
	return m


static func line_of(m: Dictionary) -> String:
	var extra := ""
	if float(m.get("mem_mb", 0.0)) > 0.0:  # 엔진 정적 메모리: 릴리스 템플릿에서는 0이라 줄에서 뺀다 (Linux는 아래 rss를 쓴다)
		extra += " mem=%.1fMB" % m.mem_mb
	if m.has("cpu_pct"):
		extra += " cpu=%.0f%% rss=%.1fMB" % [m.cpu_pct, m.rss_mb]
	return _base_line(m) + extra


static func _base_line(m: Dictionary) -> String:
	return "METRICS rooms=%d (대기 %d, 진행 %d, 끝남 %d) players=%d conns=%d monsters=%d frame_avg=%.1fms frame_max=%.1fms work_avg=%.1fms work_max=%.1fms peak_rooms=%d peak_conns=%d" % [
		m.rooms, m.waiting, m.playing, m.finished, m.players, m.conns, m.monsters,
		m.frame_avg_ms, m.frame_max_ms, m.work_avg_ms, m.work_max_ms, m.peak_rooms, m.peak_conns,
	]


func _reset_window() -> void:
	_elapsed = 0.0
	_frames = 0
	_frame_sum = 0.0
	_frame_max = 0.0
	_work_sum = 0.0
	_work_max = 0.0


## /proc/self/stat 글자에서 utime+stime (clock tick 단위)을 읽는다. 못 읽으면 -1.
## 두 번째 칸(프로세스 이름)에 공백/괄호가 들어갈 수 있어서 마지막 ')' 뒤부터 자른다. ')' 뒤 첫 칸이 state(3번째 칸)이고, utime/stime은 14/15번째 칸이다.
static func parse_cpu_ticks(stat_text: String) -> float:
	var close := stat_text.rfind(")")
	if close < 0:
		return -1.0
	var parts := stat_text.substr(close + 2).split(" ", false)
	if parts.size() < 13:
		return -1.0
	return float(parts[11]) + float(parts[12])   # parts[0]=state(3번째 칸) -> utime(14번째)=parts[11], stime(15번째)=parts[12]


## /proc/self/status 글자에서 VmRSS(kB)를 MB로. 못 읽으면 0.
static func parse_rss_mb(status_text: String) -> float:
	for line in status_text.split("\n"):
		if line.begins_with("VmRSS:"):
			return float(line.substr(6).strip_edges().split(" ")[0]) / 1024.0
	return 0.0


static func rss_mb() -> float:
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	return 0.0 if f == null else parse_rss_mb(f.get_as_text())


## 지난 호출 이후 CPU 사용률(%). 처음이거나 /proc이 없으면 -1.
func _cpu_percent() -> float:
	var f := FileAccess.open("/proc/self/stat", FileAccess.READ)
	if f == null:
		return -1.0
	var ticks := parse_cpu_ticks(f.get_as_text())
	var now := Time.get_ticks_usec()
	var result := -1.0
	if ticks >= 0.0 and _cpu_ticks_prev >= 0.0 and now > _cpu_wall_prev_usec:
		result = (ticks - _cpu_ticks_prev) / 100.0 / (float(now - _cpu_wall_prev_usec) / 1000000.0) * 100.0
	_cpu_ticks_prev = ticks
	_cpu_wall_prev_usec = now
	return result
