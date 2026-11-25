class_name NetProtocol
## 클라이언트와 서버가 주고받는 메시지의 약속 (#20). 전송 계층(ENet/WebSocket)과 상관없이 같다.
##
## 메시지는 JSON 글자 하나(UTF-8)이고 {"t": 종류, ...} 모양이다. 객체/Variant 직렬화(`bytes_to_var`)는 쓰지 않는다:
## 밖에서 온 바이트가 객체를 만들 수 없게 하려는 것이고, 명령(Command.to_wire/from_wire)과 같은 방식이다.
##
## 클라이언트 -> 서버
##   hello   {proto, snapshot, game, name, mode?, code?}   접속 직후 첫 메시지. 버전이 다르면 서버가 reject하고 끊는다.
##                                           방 코드 서버(RoomHub)에서는 mode가 "create"(방 만들기) / "join"(code로 입장) / "quick"(빠른 시작: 공개 방) (#26)
##   cmd     {seq, cmd: Command.to_wire 글자}  명령 하나. 서버는 결과를 같은 seq로 돌려준다
##   view    {lane}                          지금 보고 있는 레인 (이 레인은 자주 받고 나머지는 드물게 받는다)
##   ping    {n}                             왕복 시간 재기용 (서버가 같은 n으로 pong)
##   ready   {on}                            로비에서 준비/준비 취소 (방장은 늘 준비됨) (#22)
##   start   {}                              로비에서 방장이 시작한다. 모두 준비했을 때만 받아 준다 (#22)
##   leave   {}                              게임 중 의도적으로 나간다 (#23). 서버는 유예 없이 바로 이탈로 처리한다
##   (hello의 token: 재접속 식별용 기기 임시 토큰. 판이 시작된 방에 같은 token으로 다시 들어오면 같은 레인으로 복귀한다 (#23))
## 서버 -> 클라이언트
##   welcome {proto, player_id, players, snap_hz, summary_hz, room, mode, resumed?, names?}   접속 허가. player_id는 서버가 정한다. resumed=true면 재접속이다 (같은 레인 복귀, 곧 키프레임이 온다) (#23)
##   reject  {reason, proto, snapshot}       접속 거부 (REJECT_* 중 하나). 이 뒤에 서버가 연결을 끊는다
##   snap    {tick, key, snap: {...}}        내가 받기로 한 범위(자기 레인, 보고 있는 레인, 보스 HUD)의 스냅샷. key=true면 전체(키프레임: 그대로 교체),
##                                           false면 이전 틱 위에 적용할 변경분(SnapshotDelta.apply). 모두 신뢰 순서로 오므로 빠지지 않는다
##   summary {tick, summary: {"<레인>": {towers, monsters}}}  나머지 레인의 미니맵용 요약 (1Hz). 올 때마다 통째로 바꾼다
##   result  {seq, ok, reason}               내 명령의 결과
##   events  {list: [...]}                   연출 이벤트 (SimEvents 모양 그대로)
##   pong    {n}
##   lobby   {members: [{lane, name, ready, host}], host, max, can_start, room, mode, public}   로비 상태 (바뀔 때마다) (#22)
##   presence {away: [레인], left: [레인], host: 방장 레인, note?: {kind, lane}}   끊긴/이탈한 사람과 방장 (바뀔 때마다). note.kind는 away(끊김)/back(돌아옴)/left(이탈)/host(방장 바뀜) (#23)
##   started {players, names: {"<레인>": 닉네임}}   방장이 시작해서 게임이 시작됐다 (서버가 바로 start_game을 한다. 첫 몬스터는 30초 뒤). 이 뒤로 snap이 온다. 이때 참여자(레인)가 확정된다.

## 선로 형식(메시지 모양)이 바뀌면 올린다. 클라이언트와 서버가 같은 값이어야만 접속된다 (큰 호환 규칙: 다르면 거부).
const PROTOCOL_VERSION := 4  # 2: 로비(lobby/started), 닉네임 (#22) / 3: 방 코드(hello mode/code, welcome/lobby room) (#26) / 4: 재접속(hello token, leave, presence, welcome resumed) (#23)

const MSG_HELLO := "hello"
const MSG_CMD := "cmd"
const MSG_VIEW := "view"
const MSG_PING := "ping"
const MSG_WELCOME := "welcome"
const MSG_REJECT := "reject"
const MSG_SNAP := "snap"
const MSG_SUMMARY := "summary"
const MSG_RESULT := "result"
const MSG_EVENTS := "events"
const MSG_PONG := "pong"
const MSG_LOBBY := "lobby"
const MSG_STARTED := "started"
const MSG_READY := "ready"
const MSG_START := "start"
const MSG_LEAVE := "leave"
const MSG_PRESENCE := "presence"

## 접속 거부 사유
const REJECT_PROTOCOL := "protocol_mismatch"   # 프로토콜/스냅샷 버전이 다르다
const REJECT_FULL := "room_full"                # 자리가 없다
const REJECT_BAD_HELLO := "bad_hello"           # 첫 메시지가 hello가 아니거나 모양이 틀렸다
const REJECT_STARTED := "already_started"       # 판이 이미 시작했다 (토큰이 없거나 이 판의 자리 주인이 아니면 재접속도 못 한다)
const REJECT_LEFT := "seat_released"            # 이 판의 내 자리가 이미 이탈로 처리됐다 (유예가 지났거나 내가 나갔다) (#23)
const REJECT_FINISHED := "game_finished"        # 이 판이 이미 끝났다 (끝난 판으로 돌아가려 할 때) (#54)
const REJECT_NO_ROOM := "room_not_found"        # 없는 방 코드 (모양이 틀린 코드, 반납/만료된 코드 포함) (#26)
const REJECT_TOO_MANY := "too_many_attempts"    # 잘못된 코드를 너무 많이 시도했다 (그 연결을 끊는다) (#26)
const REJECT_BUSY := "server_busy"              # 방을 더 만들 수 없다 (방 수 상한) (#26)

## hello의 mode (방 코드 서버). 없거나 다르면 bad_hello
const MODE_CREATE := "create"
const MODE_JOIN := "join"
const MODE_QUICK := "quick"      # 빠른 시작: 자리 있는 공개 방에 들어가고, 없으면 새 공개 방을 만든다 (코드 없이)

## 연결 끊김 감지 (#23, 오너 결정). 게임 중 클라이언트가 이 간격(초)마다 ping을 보내고, 서버는 그 연결에서 이 시간(초) 동안
## 아무것도 못 받으면 끊김으로 본다 (TCP는 망이 바뀌어도 한참 동안 안 끊긴 것처럼 보인다). 클라이언트도 서버에서 이만큼 아무것도 못 받으면 끊긴 것으로 본다.
const HEARTBEAT_PING_SEC := 3.0
const HEARTBEAT_TIMEOUT_SEC := 10.0
## 끊긴 뒤 같은 자리로 돌아올 수 있는 시간(초). 지나면 이탈로 처리한다 (오너 결정: 90초)
const RECONNECT_GRACE_SEC := 90.0
## 클라이언트가 자동으로 다시 접속을 시도하는 간격(초): 1, 2, 4, 5, 5 ...
const RECONNECT_RETRY_MIN_SEC := 1.0
const RECONNECT_RETRY_MAX_SEC := 5.0
## 재접속 시도 하나가 이 시간(초) 안에 입장하지 못하면 접고 다음 시도로 넘어간다
const RECONNECT_ATTEMPT_SEC := 4.0
## 앱이 돌아왔을 때 서버에서 이 시간(ms) 넘게 아무것도 못 받았으면 죽은 연결로 보고 바로 다시 접속한다 (스냅샷은 초당 10번 온다)
const RESUME_STALE_MS := 2000

## 서버가 받아 주는 클라이언트 메시지의 최대 크기(바이트). 명령 하나는 100바이트 안팎이다.
const MAX_CLIENT_PACKET := 2048
## 접속하고 hello를 안 보내는 연결을 끊기까지(초)
const HELLO_TIMEOUT := 5.0

## 동시에 열 수 있는 연결 수 (hello 전 연결 포함). WebSocket에는 엔진 쪽 상한이 없어서 서버가 직접 막는다 (ENet은 NetTransport.MAX_CLIENTS)
const MAX_CONNECTIONS := 16
## 그중 아직 hello를 안 보낸 연결 수. 이것만 가득 채워서 자리를 막는 접속을 줄인다 (참여자 8명이 한꺼번에 들어와도 넉넉하다)
const MAX_PENDING := 8

## 클라이언트 메시지 속도 제한 (연결마다 토큰 통). 정상 플레이는 초당 몇 번이라 한참 아래다 (건설을 연타해도 초당 10번 안팎).
const RATE_BURST := 30.0        # 통 크기: 한꺼번에 이만큼까지는 받는다
const RATE_PER_SEC := 20.0      # 초당 채워지는 양
## 보는 레인 바꾸기(view)는 바꿀 때마다 서버가 키프레임(최대 수백 KB)을 만들어 보내므로 따로 더 엄격하게 막는다
const VIEW_BURST := 4.0
const VIEW_PER_SEC := 2.0
## 제한을 넘어 무시한 메시지가 이만큼 쌓이면(1초에 RATE_IGNORED_DECAY개씩 줄어든다) 계속 퍼붓는 것으로 보고 연결을 끊는다
const RATE_IGNORED_LIMIT := 100.0
const RATE_IGNORED_DECAY := 10.0

## 채널(ENet만 의미가 있다): 0 = 접속/명령 결과/이벤트, 1 = 스냅샷/요약. 둘 다 신뢰 순서이고, 나눈 건 서로 기다리게 하지 않으려는 것이다
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
## mode/code는 방 코드 서버용 (#26): MODE_CREATE면 code 없이, MODE_JOIN이면 방 코드를 준다. 안 주면 필드를 싣지 않는다 (예전 서버와 같은 모양).
static func make_hello(player_name: String, mode := "", code := "", token := "") -> Dictionary:
	var hello := {"t": MSG_HELLO, "proto": PROTOCOL_VERSION, "snapshot": Snapshot.VERSION, "game": game_version(), "name": player_name}
	if mode != "":
		hello["mode"] = mode
	if code != "":
		hello["code"] = code
	if token != "":
		hello["token"] = token
	return hello


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
