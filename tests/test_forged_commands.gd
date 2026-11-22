extends "res://tests/case_base.gd"
## 이슈 #21: 클라이언트가 위조한 명령(골드/체력을 직접 바꾸려는 것, 남의 레인, 잘못된 모양)을 서버가 거부하고 상태를 바꾸지 않는다.

var field: GameField
var lane: LaneController


func run() -> void:
	field = (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	field.session.participants = [0, 1]
	get_tree().root.add_child.call_deferred(field)
	await frames(8)
	lane = field.lanes[0]
	field.bus.execute(Command.make(Command.START_GAME, 0, {}))
	lane.gold = 100.0
	lane.try_build_tower(Vector2i(5, 10), "long", false)
	var before := _state()

	_reject({"type": "set_gold", "player_id": 0, "amount": 99999}, "bad_command", "골드를 직접 바꾸는 명령은 없다")
	_reject({"type": "set_lives", "player_id": 0, "lives": 999}, "bad_command", "생명을 직접 바꾸는 명령은 없다")
	_reject({"type": "build_tower", "player_id": 0, "cell": Vector2i(7, 10), "kind_id": "long", "confirmed": true, "cost": 0}, "bad_command", "비용 인자를 끼워 넣으면 거부")
	_reject({"type": "build_tower", "player_id": 0, "cell": Vector2i(7, 10), "kind_id": "long"}, "bad_command", "인자를 빠뜨리면 거부")
	_reject({"type": "build_tower", "player_id": 0, "cell": [7, 10], "kind_id": "long", "confirmed": false}, "bad_command", "칸 타입이 틀리면 거부")
	_reject({"type": "build_tower", "player_id": "0", "cell": Vector2i(7, 10), "kind_id": "long", "confirmed": false}, "bad_command", "플레이어 번호 타입이 틀리면 거부")
	_reject({"type": "build_tower", "player_id": 5, "cell": Vector2i(7, 10), "kind_id": "long", "confirmed": false}, "not_participant", "참여자가 아니면 거부")
	_reject({"type": "build_tower", "player_id": 0, "cell": Vector2i(7, 10), "kind_id": "free_tower", "confirmed": false}, "unknown_kind", "없는 타워 종류")
	_reject({"type": "build_tower", "player_id": 0, "cell": Vector2i(-3, 999), "kind_id": "long", "confirmed": false}, "invalid_cell", "격자 밖 칸")
	_reject({"type": "build_tower", "player_id": 0, "cell": Vector2i(5, 10), "kind_id": "long", "confirmed": false}, "cell_not_empty", "이미 타워가 있는 칸")
	_reject({"type": "send_monster", "player_id": 0, "kind_id": "grunt"}, "not_sendable", "협력에서 못 만드는 몬스터")
	_reject({"type": "send_monster", "player_id": 0, "kind_id": "nonexistent"}, "unknown_kind", "없는 몬스터 종류")
	_reject({"type": "sell_tower", "player_id": 0, "cell": Vector2i(1, 1)}, "no_tower", "타워 없는 칸 판매")
	_reject({"type": "evolve_tower", "player_id": 0, "cell": Vector2i(5, 10), "evo": "mass"}, "invalid_evolution", "그 타워가 고를 수 없는 진화")
	_reject({"type": "upgrade_color", "player_id": 0, "color_name": "투명"}, "invalid_color", "없는 색깔 업그레이드")
	_reject({"type": "set_pause", "player_id": 0, "on": true}, "pause_not_allowed", "멀티에서는 일시정지 불가")
	check(_state() == before, "위조 명령을 모두 거부한 뒤에도 골드/생명/타워가 그대로다 %s" % [_state()])

	# 내 레인에 대한 명령만 있다: 1번 플레이어가 0번 레인의 타워를 팔 수는 없다 (명령은 자기 레인만 가리킨다)
	var other: LaneController = field.lanes[1]
	var other_gold := other.gold
	var r := field.bus.execute(Command.make(Command.SELL_TOWER, 1, {"cell": Vector2i(5, 10)}))
	check(not r["ok"] and r["reason"] == "no_tower", "1번 플레이어가 0번 레인의 타워(5,10)를 팔려 하면 거부 (%s)" % r["reason"])
	check(_state() == before and other.gold == other_gold, "남의 레인 타워는 그대로, 내 골드도 그대로")

	# 네트워크로 온 글자(JSON)가 쓰레기여도 명령이 되지 않는다
	for junk in ["", "not json", "[1,2]", "{\"type\": \"set_gold\", \"player_id\": 0}", "{\"type\": \"build_tower\", \"player_id\": 0, \"cell\": \"x\"}"]:
		check(Command.from_wire(junk).is_empty(), "쓰레기 입력은 명령이 되지 않는다: %s" % junk.left(30))

	# 정상 명령은 그대로 통한다 (거부가 과해서 막힌 게 아님을 확인)
	var ok := field.bus.execute(Command.make(Command.BUILD_TOWER, 0, {"cell": Vector2i(7, 10), "kind_id": "long", "confirmed": false}))
	check(ok["ok"] and lane.gold < 100.0, "정상 건설은 통과하고 골드가 줄어든다 (%.1f)" % lane.gold)

	field.queue_free()
	await frames(3)


## 거부되어야 하는 명령: 결과가 실패이고 사유가 맞다
func _reject(cmd: Dictionary, reason: String, what: String) -> void:
	var r := field.bus.execute(cmd)
	check(not r["ok"] and r["reason"] == reason, "%s (사유 %s)" % [what, r["reason"]])


func _state() -> Dictionary:
	return {"gold": lane.gold, "lives": lane.lives, "towers": lane.towers.size(), "income": lane.income}
