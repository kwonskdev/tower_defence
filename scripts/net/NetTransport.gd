class_name NetTransport
## 전송 계층을 고르는 곳 (#20). ENet(UDP)과 WebSocket(TCP)은 둘 다 MultiplayerPeer라서 위쪽 코드(NetServer/NetClient)는 어느 쪽인지 모른다.
## 둘을 바꿔 끼울 수 있게 해 둔 이유: 전송 계층은 호스팅(#24)에 따라 바뀔 수 있는 결정이다 (UDP가 안 열리는 호스팅이면 WebSocket).

const ENET := "enet"
const WEBSOCKET := "ws"
const DEFAULT := ENET

## 서버가 받을 수 있는 최대 연결 수 (참여자 8명 + 아직 hello를 안 보낸 연결 여유)
const MAX_CLIENTS := 16


static func is_known(kind: String) -> bool:
	return kind == ENET or kind == WEBSOCKET


## 서버 쪽 피어를 연다. 실패하면 null. port 0을 주면 엔진이 고르지 못하므로(ENet) 항상 실제 포트를 줘야 한다.
static func create_server(kind: String, port: int) -> MultiplayerPeer:
	if not is_known(kind):
		return null
	var err := ERR_INVALID_PARAMETER
	var peer: MultiplayerPeer = null
	match kind:
		ENET:
			var p := ENetMultiplayerPeer.new()
			err = p.create_server(port, MAX_CLIENTS, NetProtocol.CHANNEL_COUNT)
			peer = p
		WEBSOCKET:
			var p := WebSocketMultiplayerPeer.new()
			err = p.create_server(port)
			peer = p
	if err != OK:
		Log.error(Log.Category.NETWORK, "서버 열기 실패 (%s, 포트 %d): %s" % [kind, port, error_string(err)])
		return null
	return peer


## 클라이언트 쪽 피어를 연다 (접속은 비동기: 이어졌는지는 피어의 peer_connected 신호/연결 상태로 안다). 실패하면 null.
static func create_client(kind: String, host: String, port: int) -> MultiplayerPeer:
	if not is_known(kind):
		return null
	var err := ERR_INVALID_PARAMETER
	var peer: MultiplayerPeer = null
	match kind:
		ENET:
			var p := ENetMultiplayerPeer.new()
			err = p.create_client(host, port, NetProtocol.CHANNEL_COUNT)
			peer = p
		WEBSOCKET:
			var p := WebSocketMultiplayerPeer.new()
			err = p.create_client("ws://%s:%d" % [host, port])
			peer = p
	if err != OK:
		Log.error(Log.Category.NETWORK, "접속 시작 실패 (%s, %s:%d): %s" % [kind, host, port, error_string(err)])
		return null
	return peer


## 연결 하나를 끊는다 (force=false: ENet은 보낼 것을 보낸 뒤 끊어서 reject 메시지가 먼저 도착한다)
static func disconnect_peer(peer: MultiplayerPeer, peer_id: int) -> void:
	peer.disconnect_peer(peer_id, false)
