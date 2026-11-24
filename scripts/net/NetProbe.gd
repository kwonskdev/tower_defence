extends Node
class_name NetProbe
## 서버에 접속해서 타워 하나를 짓고, 다른 참여자의 타워가 스냅샷에 보이면 끝나는 화면 없는 클라이언트 (#20 프로토타입 확인용).
## 서버와 다른 프로세스로 돌려서 "헤드리스 서버 1개 + 클라이언트 2개"를 손으로 확인할 때 쓴다 (자동 테스트는 tests/test_net_prototype.gd).
##
##   Godot --headless --path . -- --server --port=47300 --players=2 --start-when-full
##   Godot --headless --path . -- --connect=127.0.0.1:47300 --cell=5,10 --name=A
##   Godot --headless --path . -- --connect=127.0.0.1:47300 --cell=7,12 --name=B
##
## 인자: --connect=호스트:포트 (필수)  --transport=enet|ws  --cell=x,y (지을 칸)  --name=이름  --timeout=초 (기본 30)
## 끝나면 한 줄 요약을 찍고 종료한다 (모든 참여자의 타워를 봤으면 0, 아니면 1, 거부당하면 2).

var client := NetClient.new()
var _cell := Vector2i(5, 10)
var _t := 0.0
var _timeout := 30.0
var _built := false
var _seen_all := false
var _seen := {}        # 레인 번호(글자) -> 본 타워 수
var _view_sent := -1


static func requested() -> bool:
	return ServerMain.arg_value("connect") != ""


func _ready() -> void:
	var target := ServerMain.arg_value("connect").rsplit(":", true, 1)
	var cell_parts := ServerMain.arg_value("cell", "5,10").split(",")
	if cell_parts.size() == 2:
		_cell = Vector2i(int(cell_parts[0]), int(cell_parts[1]))
	_timeout = float(ServerMain.arg_value("timeout", "30"))
	client.player_name = ServerMain.arg_value("name", "probe")
	add_child(client)
	client.joined.connect(_on_joined)
	client.rejected.connect(func(reason, info):
		print("PROBE 거부됨: %s (서버 프로토콜 %d, 스냅샷 %d / 내 프로토콜 %d, 스냅샷 %d)" % [reason, info.proto, info.snapshot, NetProtocol.PROTOCOL_VERSION, Snapshot.VERSION])
		get_tree().quit(2))
	client.disconnected.connect(func():
		if client.state != NetClient.State.REJECTED and not _seen_all:
			print("PROBE 연결이 끊김")
			get_tree().quit(1))
	var host: String = target[0] if target.size() == 2 else "127.0.0.1"
	var port := int(target[1]) if target.size() == 2 else int(target[0])
	if not client.connect_to(ServerMain.arg_value("transport", NetTransport.DEFAULT), host, port):
		print("PROBE 접속을 시작하지 못함")
		get_tree().quit(1)


func _on_joined(player_id: int) -> void:
	print("PROBE %s: 입장 P%d (참여자 %s)" % [client.player_name, player_id + 1, client.players])
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
