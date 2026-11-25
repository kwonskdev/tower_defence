extends Node
## 방 R개 x 8명의 봇이 방 코드 서버에 접속해 판을 한다 (#24). 사람과 같은 명령(건설/몬스터 보내기)만 보낸다 (골드 치트 없음).
## 인자: --host --port --rooms=N (기본 1) --players=N (방당 인원, 기본 8) --seconds=S (시작 뒤 이만큼 돌리고 끝, 기본 60)
## --view-boss: 봇이 모두 보스 레인을 보고 있는 것으로 한다 (몬스터 전체가 스냅샷에 실려 오는 최대 대역폭 경우. 기본은 자기 레인만 본다)
## 방 하나가 끝나거나 접속이 끊긴 봇은 그냥 둔다. 끝나면 방 수/봇 수/받은 스냅샷 수를 한 줄로 출력한다.

var rooms := 1
var players := 8
var seconds := 60.0
var host := "127.0.0.1"
var port := 47410
var _bots: Array = []        # {bot: NetBot, client, room, host(bool)}
var _t := 0.0
var _started_at := -1.0
var _joined_lanes := {}


func _ready() -> void:
	host = ServerMain.arg_value("host", host)
	port = int(ServerMain.arg_value("port", str(port)))
	rooms = int(ServerMain.arg_value("rooms", "1"))
	players = clampi(int(ServerMain.arg_value("players", "8")), 1, 8)
	seconds = float(ServerMain.arg_value("seconds", "60"))
	for r in range(rooms):
		_add_bot(r, true, "")
	print("LOADGEN 시작: 방 %d개 x %d명 -> %s:%d, %.0f초" % [rooms, players, host, port, seconds])


func _add_bot(room_i: int, is_host: bool, code: String) -> void:
	var cl := NetClient.new()
	cl.player_name = "bot%d_%d" % [room_i, _bots.size()]
	cl.join_mode = NetProtocol.MODE_CREATE if is_host else NetProtocol.MODE_JOIN
	cl.join_code = code
	add_child(cl)
	if not cl.connect_to(NetTransport.DEFAULT, host, port):
		print("LOADGEN 접속 실패: 방 %d" % room_i)
		return
	var bot := NetBot.new()  # 봇 규칙은 scripts/server/NetBot.gd (#28: 테스트와 같은 봇)
	bot.is_host = is_host
	if "--view-boss" in OS.get_cmdline_args() or "--view-boss" in OS.get_cmdline_user_args():
		bot.view_lane = GameField.BOSS_LANE_ID
	bot.setup(cl)
	add_child(bot)
	_bots.append({"bot": bot, "client": cl, "room": room_i, "host": is_host})


func _process(delta: float) -> void:
	_t += delta
	var all_in_game := true
	for b in _bots:
		var cl: NetClient = b.client
		if cl.is_joined() and cl.room_code != "" and b.host and not b.get("invited", false):
			b["invited"] = true
			for i in range(players - 1):
				_add_bot(b.room, false, cl.room_code)
		if not b.bot.lobby_step(players):
			all_in_game = false
	if _started_at < 0.0 and all_in_game and _bots.size() == rooms * players:
		_started_at = _t
		print("LOADGEN game start: all joined (%.1fs)" % _t)
	if _started_at >= 0.0 and _t - _started_at >= seconds:
		_finish()
	elif _started_at < 0.0 and _t > 60.0 + seconds:
		print("LOADGEN 실패: 60초 안에 전원이 판에 들어가지 못함 (접속 %d명)" % _bots.size())
		_finish()


func _finish() -> void:
	var snaps := 0
	var in_game := 0
	for b in _bots:
		snaps += b.client.snapshot_count
		if b.client.in_game and b.client.is_joined():
			in_game += 1
	print("LOADGEN 끝: 봇 %d명 중 판 중 %d명, 받은 스냅샷 합 %d" % [_bots.size(), in_game, snaps])
	get_tree().quit(0)
