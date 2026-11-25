extends Node
## 방 1개 + 봇 8명(tools/bench/loadgen_sim.gd와 같은 규칙)을 한 프로세스에서 돌리면서 프레임마다 걸린 시간을 재고,
## 100ms를 넘긴 프레임(끊김)의 수/최댓값/상위 목록과, 서버 방송/명령 구간별 시간(NetServer.perf)을 출력한다 (#28, #24의 0.4~0.6초 끊김 원인 조사).
## 같은 조건에서 인자만 바꿔 비교한다:
##   --log=debug|info|error  로그 최소 레벨 (기본 debug: 디버그 빌드의 기본값. 운영 릴리스는 info)
##   --no-build              봇이 타워를 짓지 않는다 (건설 = 길 찾기 재계산이 끊김 원인인지)
##   --no-send               봇이 몬스터를 보내지 않는다
##   --stack=N               방의 보스 레인에 몬스터를 N마리 쌓는다 (최대 몬스터 시험)
##   --players=N --seconds=S
## 이 도구는 서버와 봇이 한 프로세스라서 프레임 시간에 봇(클라이언트) 일도 섞인다. 봇 일은 프레임당 1ms 안팎이다.

const PORT := 47690

var seconds := 60.0
var players := 8
var server: ServerMain
var bots: Array = []
var _t := 0.0
var _started_at := -1.0
var _prev_usec := 0
var _frames: Array = []       # [시각(초, 판 시작 기준), 프레임 ms]
var _room: NetServer = null
var _invited := false
var _phase_at_hitch := {}     # 프레임 인덱스 -> 그 프레임의 방송 total last(ms)


func _ready() -> void:
	seconds = float(ServerMain.arg_value("seconds", "60"))
	players = clampi(int(ServerMain.arg_value("players", "8")), 1, 8)
	var lv := ServerMain.arg_value("log", "debug")
	Log.min_level = {"debug": Log.Level.DEBUG, "info": Log.Level.INFO, "error": Log.Level.ERROR}.get(lv, Log.Level.DEBUG)
	Engine.max_fps = 60  # 운영 서버와 같은 프레임 상한
	server = ServerMain.new()
	server.use_rooms = true
	server.net_port = PORT
	add_child(server)
	if server.metrics != null:
		server.metrics.interval_sec = 0.0  # 지표 구간이 NetServer.perf를 비우지 않게 (이 도구가 직접 읽는다)
	var stack := int(ServerMain.arg_value("stack", "0"))
	if stack > 0:
		var inj: Node = load("res://tools/bench/stack_injector.gd").new()
		inj.server = server
		inj.target = stack
		add_child(inj)
	_add_bot(true, "")
	print("PROBE 시작: 봇 %d명, 로그=%s, 건설=%s, 몬스터 보내기=%s, 쌓기=%d, %.0f초" % [players, lv, not "--no-build" in OS.get_cmdline_user_args(), not "--no-send" in OS.get_cmdline_user_args(), stack, seconds])


func _add_bot(is_host: bool, code: String) -> void:
	var cl := NetClient.new()
	cl.player_name = "p%d" % bots.size()
	cl.join_mode = NetProtocol.MODE_CREATE if is_host else NetProtocol.MODE_JOIN
	cl.join_code = code
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT)
	var bot := NetBot.new()
	bot.is_host = is_host
	bot.build_enabled = not "--no-build" in OS.get_cmdline_user_args()
	bot.send_enabled = not "--no-send" in OS.get_cmdline_user_args()
	bot.setup(cl)
	add_child(bot)
	bots.append(bot)


func _process(delta: float) -> void:
	var now := Time.get_ticks_usec()
	if _started_at >= 0.0 and _prev_usec != 0:
		_frames.append([_t - _started_at, float(now - _prev_usec) / 1000.0, _count_monsters()])
	_prev_usec = now
	_t += delta
	var all_in := true
	for b in bots:
		if b.is_host and b.client.is_joined() and b.client.room_code != "" and not _invited:
			_invited = true
			for i in range(players - 1):
				_add_bot(false, b.client.room_code)
		if not b.lobby_step(players):
			all_in = false
	if _started_at < 0.0 and all_in and bots.size() == players:
		_started_at = _t
		_room = server.hub.room_for(bots[0].client.room_code)
		print("PROBE 판 시작 (%.1fs)" % _t)
	elif _started_at >= 0.0 and _t - _started_at >= seconds:
		_report()
	elif _started_at < 0.0 and _t > 60.0:
		print("PROBE 실패: 60초 안에 전원이 판에 들어가지 못함")
		get_tree().quit(1)


## 모든 레인(보스 레인 포함)의 몬스터 수. 끊긴 프레임과 몬스터 수의 관계를 본다
func _count_monsters() -> int:
	if _room == null or _room.field == null:
		return 0
	var n := 0
	for lane in _room.field.lanes.values():
		n += lane.monsters.size()
	if _room.field.boss != null:
		n += _room.field.boss.get_sent_monsters().size()
	return n


func _report() -> void:
	var ms: Array = _frames.map(func(f): return f[1])
	var n := ms.size()
	var sum := 0.0
	var worst := 0.0
	var over100 := 0
	var over250 := 0
	for v in ms:
		sum += v
		worst = maxf(worst, v)
		if v > 100.0:
			over100 += 1
		if v > 250.0:
			over250 += 1
	print("PROBE 프레임 %d개: 평균 %.1fms 최대 %.1fms, 100ms 초과 %d개, 250ms 초과 %d개" % [n, sum / maxi(n, 1), worst, over100, over250])
	var top: Array = _frames.duplicate()
	top.sort_custom(func(a, b): return a[1] > b[1])
	for i in range(mini(8, top.size())):
		print("PROBE   상위 %d: 판 시작 후 %.1f초에 %.0fms (그때 몬스터 %d마리)" % [i + 1, top[i][0], top[i][1], top[i][2]])
	# 몬스터 수 구간별 평균 프레임 시간: 끊김이 몬스터 수에 비례하는가 (시뮬레이션 비용인가)
	var buckets := {}
	for f in _frames:
		var b := int(f[2] / 20) * 20
		var e: Array = buckets.get(b, [0, 0.0, 0.0])
		e[0] += 1
		e[1] += f[1]
		e[2] = maxf(e[2], f[1])
		buckets[b] = e
	var keys := buckets.keys()
	keys.sort()
	for k in keys:
		print("PROBE   몬스터 %d~%d마리: 프레임 %d개, 평균 %.1fms, 최대 %.0fms" % [k, k + 19, buckets[k][0], buckets[k][1] / buckets[k][0], buckets[k][2]])
	if _room != null:
		var line := []
		for k in _room.perf:
			var p: Dictionary = _room.perf[k]
			line.append("%s 평균 %.2f/최대 %.1fms (%d번)" % [k, float(p.sum) / maxi(1, p.n) / 1000.0, float(p.max) / 1000.0, p.n])
		line.sort()
		print("PROBE 서버 구간별 (방 1개, 판 시작 전 포함):\n  " + "\n  ".join(line))
		print("PROBE 가장 큰 메시지 %.0fKB, 키프레임 %d번, 보낸 바이트 %s" % [float(_room.largest_packet) / 1024.0, _room.keyframes_sent, _room.sent_bytes])
		print("PROBE 몬스터 (보스 레인) %d마리" % _room.field.boss.get_sent_monsters().size())
	get_tree().quit(0)
