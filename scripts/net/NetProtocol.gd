class_name NetProtocol
## 클라이언트와 서버가 주고받는 메시지의 약속 (#20). 전송 계층(ENet/WebSocket)과 상관없이 같다.
##
## 메시지는 JSON 글자 하나(UTF-8)이고 {"t": 종류, ...} 모양이다. 객체/Variant 직렬화(`bytes_to_var`)는 쓰지 않는다:
## 밖에서 온 바이트가 객체를 만들 수 없게 하려는 것이고, 명령(Command.to_wire/from_wire)과 같은 방식이다.
##
## 클라이언트 -> 서버
##   hello   {proto, snapshot, game, name}   접속 직후 첫 메시지. 버전이 다르면 서버가 reject하고 끊는다
##   cmd     {seq, cmd: Command.to_wire 글자}  명령 하나. 서버는 결과를 같은 seq로 돌려준다
##   view    {lane}                          지금 보고 있는 레인 (이 레인은 자주 받고 나머지는 드물게 받는다)
##   ping    {n}                             왕복 시간 재기용 (서버가 같은 n으로 pong)
## 서버 -> 클라이언트
##   welcome {proto, player_id, players, snap_hz, summary_hz}   접속 허가. player_id는 서버가 정한다
##   reject  {reason, proto, snapshot}       접속 거부 (REJECT_* 중 하나). 이 뒤에 서버가 연결을 끊는다
##   snap    {tick, snap: {...}}             서버 상태 스냅샷 (내가 받기로 한 범위만, 아래 SNAPSHOT 참고)
##   result  {seq, ok, reason}               내 명령의 결과
##   events  {list: [...]}                   연출 이벤트 (SimEvents 모양 그대로)
##   pong    {n}

## 선로 형식(메시지 모양)이 바뀌면 올린다. 클라이언트와 서버가 같은 값이어야만 접속된다 (큰 호환 규칙: 다르면 거부).
const PROTOCOL_VERSION := 1

const MSG_HELLO := "hello"
const MSG_CMD := "cmd"
const MSG_VIEW := "view"
const MSG_PING := "ping"
const MSG_WELCOME := "welcome"
const MSG_REJECT := "reject"
const MSG_SNAP := "snap"
const MSG_RESULT := "result"
const MSG_EVENTS := "events"
const MSG_PONG := "pong"

## 접속 거부 사유
const REJECT_PROTOCOL := "protocol_mismatch"   # 프로토콜/스냅샷 버전이 다르다
const REJECT_FULL := "room_full"                # 자리가 없다
const REJECT_BAD_HELLO := "bad_hello"           # 첫 메시지가 hello가 아니거나 모양이 틀렸다
const REJECT_STARTED := "already_started"       # 판이 이미 시작했다 (재접속은 #23에서)

## 서버가 받아 주는 클라이언트 메시지의 최대 크기(바이트). 명령 하나는 100바이트 안팎이다.
const MAX_CLIENT_PACKET := 2048
## 접속하고 hello를 안 보내는 연결을 끊기까지(초)
const HELLO_TIMEOUT := 5.0

## 채널: 0 = 믿을 수 있게(reliable) 보내는 것(접속/명령 결과/이벤트), 1 = 스냅샷(unreliable ordered: 늦은 것은 버려도 된다)
const CHANNEL_RELIABLE := 0
const CHANNEL_SNAPSHOT := 1
const CHANNEL_COUNT := 2


## 메시지를 바이트로 (JSON)
static func encode(msg: Dictionary) -> PackedByteArray:
	return JSON.stringify(msg).to_utf8_buffer()


## 바이트를 메시지로. 글자가 아니거나 JSON이 아니거나 {"t": 글자}가 아니면 빈 Dictionary.
## (parse_string은 잘못된 입력에서 엔진 오류를 찍는다: 밖에서 온 쓰레기가 로그를 어지럽히지 않게 parse()를 쓴다)
static func decode(bytes: PackedByteArray) -> Dictionary:
	var json := JSON.new()
	if json.parse(bytes.get_string_from_utf8()) != OK:
		return {}
	var msg = json.data
	if typeof(msg) != TYPE_DICTIONARY or typeof(msg.get("t")) != TYPE_STRING:
		return {}
	return msg


## 클라이언트가 보낼 hello
static func make_hello(player_name: String) -> Dictionary:
	return {"t": MSG_HELLO, "proto": PROTOCOL_VERSION, "snapshot": Snapshot.VERSION, "game": game_version(), "name": player_name}


## 앱 버전 글자 (project.godot의 application/config/version. 없으면 빈 글자). 안내/로그용이고 호환 판정은 PROTOCOL_VERSION이 한다.
static func game_version() -> String:
	return str(ProjectSettings.get_setting("application/config/version", ""))


## hello가 이 서버와 맞는가. 맞으면 "", 아니면 REJECT_* 사유.
## JSON은 정수도 실수로 읽으므로 값으로 비교한다.
static func check_hello(msg: Dictionary) -> String:
	if msg.get("t") != MSG_HELLO:
		return REJECT_BAD_HELLO
	var proto = msg.get("proto")
	var snap = msg.get("snapshot")
	if not (typeof(proto) in [TYPE_INT, TYPE_FLOAT]) or not (typeof(snap) in [TYPE_INT, TYPE_FLOAT]):
		return REJECT_BAD_HELLO
	if float(proto) != floorf(float(proto)) or float(snap) != floorf(float(snap)):
		return REJECT_BAD_HELLO  # 1.5 같은 값은 정수로 잘라서 통과시키지 않는다
	if int(proto) != PROTOCOL_VERSION or int(snap) != Snapshot.VERSION:
		return REJECT_PROTOCOL
	return ""
