extends Node
class_name ServerMain
## UI 없이 시뮬레이션만 돌리는 서버 진입점. `--headless --server`로 시작하면 MainGame 화면을 만들지 않고 세션만 연다 (#21).
## 지금은 한 프로세스 안에서 돈다. 네트워크는 #20 이후에 이 위에 얹는다 (스냅샷/이벤트는 CommandBus 결과와 같은 모양으로).
##
## 인자 (모두 선택):
##   --server            서버 모드 (Boot가 이것을 보고 이 노드를 띄운다)
##   --players=N         참여 인원 1~8 (기본 1)
##   --seed=N            시뮬레이션 랜덤 시드. 주지 않으면 매번 다른 판
##   --time-scale=N      게임 속도 배율 (기본 1). 테스트로 빨리 끝낼 때
##   --bot               자동 플레이어를 붙인다 (참여자 모두). 사람 없이 한 판을 끝까지 돌릴 때
##   --bot-rich          --bot에 더해 서버 쪽에서 골드를 채워 준다 (스모크 테스트 전용. 보스 Lv.1~10을 끝까지 도는지 볼 때)
##   --port=N            네트워크로 클라이언트를 받는다 (#20). 주면 자동 시작/봇 없이 접속과 시작 명령을 기다린다
##   --transport=ws|enet 전송 계층 (기본 ws = WebSocket/TCP, enet = UDP. 개발/LAN용)
##   --tls-cert=경로 --tls-key=경로  주면 서버가 직접 wss로 연다 (ws 전용). 운영에서는 보통 리버스 프록시가 TLS를 맡아서 필요 없다
##   --max-rooms=N       (방 코드 서버) 동시에 열 수 있는 방 수 (기본 64)
##   --max-rooms-per-addr=N  (방 코드 서버) 한 접속 주소가 동시에 방장으로 쥘 수 있는 방 수 (기본 3). 리버스 프록시 뒤에서는 모든 접속이 프록시 주소로 보이니 크게 올려야 한다 (#24)
##   --single-room       (대기방 방식) 방 코드 없이 프로세스 하나가 방 하나만 연다 (#22 방식. 개발/부하 측정용)
##   --start-when-full   (고정 인원 모드) --players=N 자리가 다 차면 자동으로 시작한다. 주면 로비를 쓰지 않는다 (개발/부하 측정용)
##   --max-fps=N         서버 프레임 상한 (기본 60). 헤드리스는 안 걸면 CPU 한 코어를 다 쓰며 돈다 (#24). 0이면 제한 없음(부하 측정용)
##   --metrics-interval=N  방 수/접속자 수/프레임 시간 지표를 N초마다 로그에 남긴다 (기본 60, 0이면 끔) (#24)
## --port=가 있고 --start-when-full/--single-room이 없으면 방 코드 서버다 (#26): 한 프로세스가 방 코드로 여러 방을 연다 (RoomHub).
##   접속한 사람이 [방 만들기]로 코드를 받고, 친구가 그 코드로 입장한다. 방마다 아래 로비 방식이 따로 돈다.
## --port=가 있고 --start-when-full이 없으면 로비 방식이다 (#22): 접속한 사람이 먼저 로비에 모이고(방장 = 첫 입장자),
##   모두 [준비]하면 방장이 [시작]해서 그 접속자들로 게임 화면에 들어간다 (참여자/레인이 그때 확정). 이때 --players=N은 최대 인원(기본 8)이다.
##   대기 시간 제한은 없고 자동 시작도 없다: 방장이 [시작]을 누르면 서버가 바로 start_game을 한다 (첫 몬스터는 그 30초 뒤).
## 한 판이 끝나면 결과를 로그에 한 줄 남기고 종료한다 (승리 0, 패배 1).

const DEFAULT_MAX_FPS := 60

signal finished(victory: bool, info: Dictionary)

var session := Session.new()
var field: GameField
var result := {}   # 끝난 뒤의 요약. {victory, boss_level, reason}
var net: NetServer = null            # 클라이언트를 받는 네트워크 (포트를 주었을 때만)
var net_port := 0                    # 0이 아니면 이 포트로 연다 (--port= 인자가 있으면 그 값이 우선)
var net_transport := NetTransport.DEFAULT
var net_tls: TLSOptions = null       # 주면 wss (--tls-cert/--tls-key 인자가 있으면 그 파일로 만든다)
var use_rooms := false               # 방 코드 서버 (RoomHub). --port가 있고 --start-when-full/--single-room이 없으면 _ready가 켠다. 테스트는 직접 켠다
var hub: RoomHub = null
var metrics: ServerMetrics = null    # 방 코드 서버의 운영 지표 로그 (#24)
var use_lobby := false               # 로비 방식 (위 설명). --port가 있고 --start-when-full이 없으면 _ready가 켠다. 테스트는 직접 켠다
var lobby_max_players := Balance.MAX_PLAYERS


## 이 프로세스를 서버로 시작해야 하는가
static func requested() -> bool:
	return "--server" in OS.get_cmdline_args() or "--server" in OS.get_cmdline_user_args()


## 인증서(.crt)와 개인 키(.key) 파일로 서버용 TLS 설정을 만든다. 못 읽으면 null.
static func load_tls(cert_path: String, key_path: String) -> TLSOptions:
	var cert := X509Certificate.new()
	var key := CryptoKey.new()
	if cert.load(cert_path) != OK or key.load(key_path) != OK:
		return null
	return TLSOptions.server(key, cert)


## --port= 값을 포트 번호로 바꾼다. 1~65535의 정수 글자가 아니면 -1 ("abc", "0", "70000", "12a", " 80", "-5").
static func parse_port(text: String) -> int:
	if not text.is_valid_int():
		return -1
	var port := text.to_int()
	return port if port >= 1 and port <= 65535 and str(port) == text else -1


## "--name=값" 인자의 값 (없으면 fallback)
static func arg_value(name: String, fallback: String = "") -> String:
	var prefix := "--%s=" % name
	for a in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		if a.begins_with(prefix):
			return a.substr(prefix.length())
	return fallback


func _ready() -> void:
	if arg_value("port") != "" and parse_port(arg_value("port")) < 0:
		# 틀린 포트를 0으로 읽어 조용히 네트워크 없는 서버로 도는 것을 막는다
		Log.error(Log.Category.NETWORK, "--port 값이 1~65535의 정수가 아님: '%s'" % arg_value("port"))
		result = {"victory": false, "boss_level": 0, "reason": "bad_port"}
		if requested():
			get_tree().quit(2)
		return
	var fixed_roster := "--start-when-full" in OS.get_cmdline_args() or "--start-when-full" in OS.get_cmdline_user_args()
	if arg_value("port") != "" and not fixed_roster:
		use_lobby = true
		use_rooms = not ("--single-room" in OS.get_cmdline_args() or "--single-room" in OS.get_cmdline_user_args())
	if use_rooms:
		use_lobby = true
	if use_lobby:  # 로비 방식: --players는 최대 인원이고, 참여자는 시작할 때 접속자로 정해진다
		if arg_value("players") != "":
			lobby_max_players = clampi(int(arg_value("players")), 1, Balance.MAX_PLAYERS)
		session.participants.clear()
	elif arg_value("players") != "":  # 인자가 없으면 세션에 이미 들어 있는 참여자를 그대로 쓴다 (기본은 혼자)
		session.participants.clear()
		for i in range(clampi(int(arg_value("players")), 1, Balance.MAX_PLAYERS)):
			session.participants.append(i)
	var players := session.participants.size()
	var seed_text := arg_value("seed")
	if seed_text != "":
		session.rng.seed = int(seed_text)
	Engine.time_scale = maxf(0.1, float(arg_value("time-scale", "1")))
	if requested() and arg_value("port") != "":
		Engine.max_fps = maxi(0, int(arg_value("max-fps", str(DEFAULT_MAX_FPS))))  # 안 걸면 서버가 쉬지 않고 돌아 CPU를 다 쓴다
	Log.info(Log.Category.GAME, "서버 시작: 참여 %d명, 시드 %s, 배속 x%s" % [players, seed_text if seed_text != "" else "(무작위)", Engine.time_scale])

	if not use_lobby:
		_make_field()
	if arg_value("port") != "":
		net_port = parse_port(arg_value("port"))
	net_transport = arg_value("transport", net_transport)
	if arg_value("tls-cert") != "":
		net_tls = load_tls(arg_value("tls-cert"), arg_value("tls-key"))
		if net_tls == null:
			net_port = 0
			Log.error(Log.Category.NETWORK, "TLS 인증서/키를 읽지 못해 네트워크를 열지 않음")
			if requested():
				get_tree().quit.call_deferred(2)
	if net_port > 0 and use_rooms:
		hub = RoomHub.new()
		hub.room_max_players = lobby_max_players
		hub.max_rooms = maxi(1, int(arg_value("max-rooms", str(hub.max_rooms))))
		hub.max_rooms_per_addr = maxi(1, int(arg_value("max-rooms-per-addr", str(hub.max_rooms_per_addr))))
		add_child(hub)
		metrics = ServerMetrics.new()
		add_child(metrics)
		metrics.setup(hub, float(arg_value("metrics-interval", str(ServerMetrics.DEFAULT_INTERVAL_SEC))))
		var herr := hub.start(net_transport, net_port, net_tls)
		if herr != OK:
			Log.error(Log.Category.NETWORK, "네트워크를 열지 못해 서버를 끝냄 (포트 %d, %s)" % [net_port, net_transport])
			result = {"victory": false, "boss_level": 0, "reason": "net_open_failed"}
			if requested():
				get_tree().quit.call_deferred(2)
		return
	if net_port > 0:
		net = NetServer.new()
		if use_lobby:
			net.lobby = Lobby.new()
			net.lobby.max_players = lobby_max_players
			net.session = session
			net.field_factory = _make_field
		net.start_when_full = "--start-when-full" in OS.get_cmdline_args() or "--start-when-full" in OS.get_cmdline_user_args()
		add_child(net)
		var err := net.start(field, net_transport, net_port, net_tls)
		if err != OK:
			Log.error(Log.Category.NETWORK, "네트워크를 열지 못해 서버를 끝냄 (포트 %d, %s)" % [net_port, net_transport])
			result = {"victory": false, "boss_level": 0, "reason": "net_open_failed"}
			if requested():
				get_tree().quit.call_deferred(2)


## 시뮬레이션 필드(레인 + 보스)를 만든다. 고정 인원 모드는 시작할 때, 로비 방식은 참여자가 확정된 뒤에 부른다.
func _make_field() -> GameField:
	field = (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	field.session = session
	field.play_effects = false  # 서버는 화면이 없다: 연출 이벤트는 그리지 않는다
	add_child(field)
	field.boss_ready.connect(_on_boss_ready, CONNECT_ONE_SHOT)
	return field


func _on_boss_ready(boss: BossController) -> void:
	boss.boss_defeated.connect(func(): _finish(true, boss, ""))
	boss.boss_failed.connect(func(reason: String): _finish(false, boss, reason))
	if net != null:
		return  # 네트워크 판: 시작은 접속한 클라이언트의 START_GAME 명령으로 한다 (봇/자동 시작 없음)
	if "--bot" in OS.get_cmdline_args() or "--bot" in OS.get_cmdline_user_args() or "--bot-rich" in OS.get_cmdline_args() or "--bot-rich" in OS.get_cmdline_user_args():
		for pid in session.participants:
			var bot := AutoPlayer.new()
			add_child(bot)
			bot.setup(field.bus, pid)
			bot.cheat_gold = "--bot-rich" in OS.get_cmdline_args() or "--bot-rich" in OS.get_cmdline_user_args()
	var started := field.bus.execute(Command.make(Command.START_GAME, session.local_player_id, {}))
	if not started["ok"]:
		Log.warn(Log.Category.GAME, "서버 시작 실패: %s" % started["reason"])
		_finish(false, boss, started["reason"])


func _finish(victory: bool, boss: BossController, reason: String) -> void:
	if not result.is_empty():
		return
	result = {"victory": victory, "boss_level": boss.level, "reason": reason}
	Log.info(Log.Category.GAME, "서버 한 판 끝: %s (보스 Lv.%d)%s" % ["승리" if victory else "패배", boss.level, "" if reason == "" else " - " + reason])
	finished.emit(victory, result)
	if net != null:  # 끝난 사실(game_over 이벤트)이 클라이언트에게 가도록 한 틱 이상 기다린다
		await get_tree().create_timer(0.5).timeout
	if requested():  # 테스트가 이 노드를 직접 만든 경우에는 프로세스를 끝내지 않는다
		get_tree().quit(0 if victory else 1)
