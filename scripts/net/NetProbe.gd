extends Node
class_name NetProbe
## 서버에 접속해서 타워 하나를 짓고, 다른 참여자의 타워가 스냅샷에 보이면 끝나는 화면 없는 클라이언트 (#20 프로토타입 확인용).
## 서버와 다른 프로세스로 돌려서 "헤드리스 서버 1개 + 클라이언트 2개"를 손으로 확인할 때 쓴다 (자동 테스트는 tests/test_net_prototype.gd).
##
##   Godot --headless --path . -- --server --port=47300 --players=2 --start-when-full   (고정 인원)
##   Godot --headless --path . -- --server --port=47300                                   (대기방: 방장 = 첫 입장자, 모두 준비 -> 방장 시작 -> 바로 시작, 첫 몬스터는 30초 뒤. 자동 시작 없음)
##   (대기방 서버에는 방장 쪽 프로브를 --expect=2로 먼저 띄운다: 나머지는 자동으로 준비하고, 방장은 2명이 모여 모두 준비하면 시작한다)
##   Godot --headless --path . -- --connect=127.0.0.1:47300 --cell=5,10 --name=A
##   Godot --headless --path . -- --connect=127.0.0.1:47300 --cell=7,12 --name=B
##
## 방 코드 서버(기본 서버)에는 --create(방 만들기: 입장하면 "PROBE ROOM 코드"를 찍는다) 또는 --room=코드(그 방에 입장)를 줘야 한다 (#26).
##   Godot --headless --path . -- --connect=127.0.0.1:47300 --create --expect=2 --name=A     (방장: 코드를 찍고 2명이 모이면 시작)
##   Godot --headless --path . -- --connect=127.0.0.1:47300 --room=ABC234 --name=B
## 인자: --connect=호스트:포트 (필수)  --transport=ws|enet (기본 ws)  --tls (wss로 접속, 기기의 인증서 목록으로 서버 확인)  --cell=x,y (지을 칸)  --name=이름  --timeout=초 (기본 30)
## 끝나면 한 줄 요약을 찍고 종료한다 (모든 참여자의 타워를 봤으면 0, 아니면 1, 거부당하면 2).

var client := NetClient.new()
var _cell := Vector2i(5, 10)
var _t := 0.0
var _timeout := 30.0
var _built := false
var _seen_all := false
var _seen := {}        # 레인 번호(글자) -> 본 타워 수
var _view_sent := -1
var _ready_sent := false
var _started_sent := false


static func requested() -> bool:
	return ServerMain.arg_value("connect") != ""


func _ready() -> void:
	var target := ServerMain.arg_value("connect").rsplit(":", true, 1)
	var cell_parts := ServerMain.arg_value("cell", "5,10").split(",")
	if cell_parts.size() == 2:
		_cell = Vector2i(int(cell_parts[0]), int(cell_parts[1]))
	_timeout = float(ServerMain.arg_value("timeout", "30"))
	client.player_name = ServerMain.arg_value("name", "probe")
	if "--create" in OS.get_cmdline_args() + OS.get_cmdline_user_args():
		client.join_mode = NetProtocol.MODE_CREATE
	elif ServerMain.arg_value("room") != "":
		client.join_mode = NetProtocol.MODE_JOIN
		client.join_code = ServerMain.arg_value("room")
	add_child(client)
	client.joined.connect(_on_joined)
	client.game_started.connect(func(_players, _names): _build())  # 로비 방식 서버: 방장이 시작해서 게임 화면에 들어간 뒤에 짓는다 (#22)
	client.lobby_changed.connect(_on_lobby)
	client.rejected.connect(func(reason, info):
		print("PROBE 거부됨: %s (서버 프로토콜 %d, 스냅샷 %d / 내 프로토콜 %d, 스냅샷 %d)" % [reason, info.proto, info.snapshot, NetProtocol.PROTOCOL_VERSION, Snapshot.VERSION])
		get_tree().quit(2))
	client.disconnected.connect(func():
		if client.state != NetClient.State.REJECTED and not _seen_all:
			print("PROBE 연결이 끊김")
			get_tree().quit(1))
	var host: String = target[0] if target.size() == 2 else "127.0.0.1"
	var port := int(target[1]) if target.size() == 2 else int(target[0])
	var tls: TLSOptions = TLSOptions.client() if "--tls" in OS.get_cmdline_args() + OS.get_cmdline_user_args() else null
	if not client.connect_to(ServerMain.arg_value("transport", NetTransport.DEFAULT), host, port, tls):
		print("PROBE 접속을 시작하지 못함")
		get_tree().quit(1)


func _on_joined(player_id: int) -> void:
	if client.room_code != "":
		print("PROBE ROOM %s" % client.room_code)
	print("PROBE %s: 입장 P%d (%s)" % [client.player_name, player_id + 1, "참여자 %s" % [client.players] if not client.players.is_empty() else "로비에서 시작을 기다림"])
	if not client.players.is_empty():  # 고정 인원 서버: 참여자가 이미 정해져 있으니 바로 짓는다
		_build()


## 대기방: 방장이 아니면 준비하고, 방장(--host)이면 --expect=N명이 모여 모두 준비했을 때 시작한다
func _on_lobby(view: Dictionary) -> void:
	var members: Array = view.get("members", [])
	if int(view.get("host", -1)) == client.player_id:
		if view.get("can_start", false) and members.size() >= int(ServerMain.arg_value("expect", "2")) and not _started_sent:
			_started_sent = true
			client.request_start()
	elif not _ready_sent:
		_ready_sent = true
		client.set_ready(true)


func _build() -> void:
	client.send(Command.BUILD_TOWER, {"cell": _cell, "kind_id": "long", "confirmed": false})
	_built = true


func _process(delta: float) -> void:
	_t += delta
	if _t > _timeout:
		print("PROBE 시간 초과: 다른 참여자의 타워를 못 봄")
		get_tree().quit(1)
		return
	if not client.is_joined() or not _built:
		return
	# 스냅샷에 담겨 온 타워를 레인별로 모은다. 아직 못 본 참여자의 레인으로 보는 곳을 옮겨 가며 모든 참여자의 타워가 모일 때까지 기다린다
	for lane_key in client.snapshot.get("lanes", {}):
		var n: int = client.snapshot.lanes[lane_key].towers.size()
		if n > 0:
			_seen[lane_key] = n
	var missing := -1
	for pid in client.players:
		if not _seen.has(str(int(pid))):
			missing = int(pid)
			break
	if missing >= 0:
		if missing != _view_sent:
			_view_sent = missing
			client.set_view(missing)
		return
	_seen_all = true
	print("PROBE %s: 모든 참여자의 타워를 봄 %s (스냅샷 %d장, 틱 %d)" % [client.player_name, _seen, client.snapshot_count, client.last_tick])
	get_tree().quit(0)
