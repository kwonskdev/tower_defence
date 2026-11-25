extends Node
## 최대 몬스터 시험용 (#24, 측정 전용): 방 코드 서버의 진행 중인 방마다 보스 레인에 몬스터를 목표 수까지 쌓고 보스가 안 죽게 한다.
## 서버 코드는 그대로고(RoomHub/NetServer/스냅샷 경로 전부 실제), 몬스터를 쌓는 것만 이 노드가 한다. 운영 서버에는 붙지 않는다.
## 인자: --stack=N (방마다 보스 레인에 쌓을 몬스터 수)

var server: ServerMain
var target := 1000
var _timer := 0.0


func _process(delta: float) -> void:
	_timer += delta
	if _timer < 0.5 or server == null or server.hub == null:
		return
	_timer = 0.0
	for code in server.hub._rooms:
		var room: NetServer = server.hub._rooms[code]
		var field: GameField = room.field
		if field == null or field.boss == null or not field.bus.started:
			continue
		field.boss.max_hp = 1e15
		field.boss.hp = 1e15
		var lane: LaneController = field.lanes[field.session.participants[0]]
		var need := target - field.boss.get_sent_monsters().size()
		for i in range(mini(need, 200)):
			lane.gold = 1e9
			field.bus.execute(Command.make(Command.SEND_MONSTER, lane.player_id, {"kind_id": "rusher"}))
