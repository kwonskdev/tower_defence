class_name NetTransport
## 전송 계층을 고르는 곳 (#20). WebSocket(TCP)과 ENet(UDP)은 둘 다 MultiplayerPeer라서 위쪽 코드(NetServer/NetClient)는 어느 쪽인지 모른다.
##
## 결정: 기본은 WebSocket (wss). 통신사/회사 Wi-Fi 방화벽에서 막힐 위험이 적고, TLS가 표준이라 계정 토큰(#25)을 실을 수 있고, 클라우드 호스팅(#24)이 쉽다.
## ENet(UDP)은 개발/LAN용 옵션으로 남긴다 (--transport=enet).
##
## 새 전송 계층(예: Steam 중계)을 붙이려면 MultiplayerPeer를 돌려주는 함수 두 개를 register()로 등록하면 된다. NetServer/NetClient는 고치지 않는다.
## 위쪽 코드가 기대하는 것: 신뢰 순서 전달(채널은 없어도 된다), peer_connected(클라이언트 쪽에서 서버는 1번)/peer_disconnected 신호, 패킷 하나 = 메시지 하나.

const WEBSOCKET := "ws"
const ENET := "enet"
const DEFAULT := WEBSOCKET

## 서버가 받을 수 있는 최대 연결 수 (참여자 8명 + 아직 hello를 안 보낸 연결 여유)
const MAX_CLIENTS := 16

## WebSocket 송수신 버퍼 크기(바이트). 엔진 기본값은 약 64KB라서 보스 레인 몬스터가 수백 마리인 키프레임(1000마리에서 약 490KB)이
## 한 메시지로 안 들어가 보내기가 실패한다 (측정은 tests/test_net_big_keyframe.gd). 2MB는 보스 레인 몬스터 약 4300마리까지의 JSON 키프레임이 들어가는 크기다 (3000마리 = 1.43MB로 실측).
## 연결마다 송신/수신 버퍼를 따로 잡으므로 2MB x 2 x 최대 연결 수(16)가 최대 메모리다. 이보다 큰 키프레임은 보내기가 실패하고 서버가 경고를 남기며 매 틱 다시 시도한다 (PR #48에 적은 한계).
const WS_BUFFER_BYTES := 2 * 1024 * 1024
## 테스트가 기본값(작은 버퍼)에서 어떻게 되는지 보려고 바꿀 수 있게 변수로 둔다
static var ws_buffer_bytes := WS_BUFFER_BYTES

## 등록된 외부 전송: 이름 -> {"server": Callable(port: int) -> MultiplayerPeer, "client": Callable(host: String, port: int) -> MultiplayerPeer}
static var _custom: Dictionary = {}


static func register(kind: String, server_factory: Callable, client_factory: Callable) -> void:
	_custom[kind] = {"server": server_factory, "client": client_factory}


static func unregister(kind: String) -> void:
	_custom.erase(kind)


static func is_known(kind: String) -> bool:
	return kind == ENET or kind == WEBSOCKET or _custom.has(kind)


## 서버 쪽 피어를 연다. 실패하면 null.
## tls: WebSocket에서만. 주면 wss로 연다 (TLSOptions.server(키, 인증서)). 운영에서는 보통 리버스 프록시가 TLS를 맡고 서버는 ws로 둔다.
static func create_server(kind: String, port: int, tls: TLSOptions = null) -> MultiplayerPeer:
	var err := ERR_INVALID_PARAMETER
	var peer: MultiplayerPeer = null
	if _custom.has(kind):
		peer = _custom[kind]["server"].call(port)
		err = OK if peer != null else ERR_CANT_CREATE
	elif kind == ENET and tls == null:
		var p := ENetMultiplayerPeer.new()
		err = p.create_server(port, MAX_CLIENTS, NetProtocol.CHANNEL_COUNT)
		peer = p
	elif kind == WEBSOCKET:
		var p := WebSocketMultiplayerPeer.new()
		p.inbound_buffer_size = ws_buffer_bytes
		p.outbound_buffer_size = ws_buffer_bytes
		err = p.create_server(port, "*", tls)
		peer = p
	else:
		return null  # 모르는 전송 계층이거나 ENet에 TLS를 줬다
	if err != OK:
		Log.error(Log.Category.NETWORK, "서버 열기 실패 (%s, 포트 %d): %s" % [kind, port, error_string(err)])
		return null
	return peer


## 클라이언트 쪽 피어를 연다 (접속은 비동기: 이어졌는지는 피어의 peer_connected 신호/연결 상태로 안다). 실패하면 null.
## tls: WebSocket에서만. 주면 wss://로 접속한다 (TLSOptions.client()는 기기의 인증서 목록으로 서버를 확인한다).
static func create_client(kind: String, host: String, port: int, tls: TLSOptions = null) -> MultiplayerPeer:
	var err := ERR_INVALID_PARAMETER
	var peer: MultiplayerPeer = null
	if _custom.has(kind):
		peer = _custom[kind]["client"].call(host, port)
		err = OK if peer != null else ERR_CANT_CREATE
	elif kind == ENET and tls == null:
		var p := ENetMultiplayerPeer.new()
		err = p.create_client(host, port, NetProtocol.CHANNEL_COUNT)
		peer = p
	elif kind == WEBSOCKET:
		var p := WebSocketMultiplayerPeer.new()
		p.inbound_buffer_size = ws_buffer_bytes
		p.outbound_buffer_size = ws_buffer_bytes
		err = p.create_client("%s://%s:%d" % ["wss" if tls != null else "ws", host, port], tls)
		peer = p
	else:
		return null
	if err != OK:
		Log.error(Log.Category.NETWORK, "접속 시작 실패 (%s, %s:%d): %s" % [kind, host, port, error_string(err)])
		return null
	return peer


## 이 메시지가 송신 버퍼에 안 들어가는가 (WebSocket만). 엔진 4.6.3의 WebSocketMultiplayerPeer.put_packet은 버퍼가 모자라도 OK를 돌려주고
## 오류 로그만 남기며 메시지를 버리므로(측정: tests/test_net_big_keyframe.gd), 반환값 대신 보내기 전에 남은 공간을 직접 본다.
## peer_id는 서버 쪽에서는 연결 번호, 클라이언트 쪽에서는 1(서버)이다.
static func would_overflow(peer: MultiplayerPeer, peer_id: int, size: int) -> bool:
	if not peer is WebSocketMultiplayerPeer:
		return false  # ENet은 큰 신뢰 메시지를 알아서 쪼개 보낸다
	var ws: WebSocketPeer = peer.get_peer(peer_id)
	return ws != null and ws.get_current_outbound_buffered_amount() + size > peer.outbound_buffer_size


## 연결 하나를 끊는다 (force=false: ENet은 보낼 것을 보낸 뒤 끊는다)
static func disconnect_peer(peer: MultiplayerPeer, peer_id: int) -> void:
	peer.disconnect_peer(peer_id, false)


## 연결 상대의 주소 글자 (시도 횟수 제한의 구별값). 알 수 없으면 "". 리버스 프록시 뒤에서는 프록시 주소가 나온다.
static func address_of(peer: MultiplayerPeer, peer_id: int) -> String:
	if peer is WebSocketMultiplayerPeer:
		return str((peer as WebSocketMultiplayerPeer).get_peer_address(peer_id))
	if peer is ENetMultiplayerPeer:
		var p: ENetPacketPeer = (peer as ENetMultiplayerPeer).get_peer(peer_id)
		return "" if p == null else str(p.get_remote_address())
	return ""
