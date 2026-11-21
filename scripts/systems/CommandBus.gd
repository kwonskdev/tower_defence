class_name CommandBus
## 상태를 바꾸는 모든 행동이 거치는 곳. UI와 네트워크는 명령(Command)을 만들어 execute()에 넘기기만 한다.
## execute는 검증과 적용을 한 번에 한다: 통과하면 적용하고, 어기면 아무것도 바꾸지 않고 사유를 돌려준다.
## 서버도 같은 함수를 그대로 쓴다 (화면 노드에 의존하지 않고 session / lanes / boss만 안다).
##
## 결과: {"ok": bool, "reason": String, "events": Array}
##   reason: ok=false일 때의 사유 코드 (예: "not_enough_gold"). UI가 문구로 바꿔 보여 준다.
##   events: 연출 이벤트. 서버는 무시하고, 클라이언트만 효과/소리로 재생한다. 각 항목은 {"type": ..., ...}.

var session: Session
var lanes: Dictionary          # player_id -> LaneController (GameField와 같은 Dictionary를 가리킨다)
var boss: BossController = null  # 보스는 한 프레임 늦게 만들어지므로 나중에 채운다
var started := false           # 시작 명령이 실행되었는가
var paused := false            # 일시정지 중인가 (싱글플레이에서만 켜진다)


func _init(p_session: Session, p_lanes: Dictionary) -> void:
	session = p_session
	lanes = p_lanes


static func ok(events: Array = []) -> Dictionary:
	return {"ok": true, "reason": "", "events": events}


static func fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason, "events": []}


## 명령 하나를 검증하고 실행한다.
func execute(cmd: Dictionary) -> Dictionary:
	var bad := Command.check(cmd)
	if bad != "":
		Log.warn(Log.Category.GAME, "잘못된 명령 거절: %s (%s)" % [bad, cmd])
		return fail("bad_command")
	var player_id: int = cmd["player_id"]
	if not session.is_participant(player_id):
		Log.warn(Log.Category.GAME, "참여자가 아닌 플레이어의 명령 거절: P%d %s" % [player_id, cmd["type"]])
		return fail("not_participant")

	match cmd["type"]:
		Command.START_GAME:
			return _start_game()
		Command.SET_PAUSE:
			return _set_pause(cmd["on"])

	# 여기서부터는 플레이어 자기 레인에 하는 행동이다 (남의 레인을 가리키는 명령은 존재하지 않는다)
	var lane: LaneController = lanes.get(player_id)  # 참여자는 모두 레인이 있다 (없으면 설정 오류)
	if lane == null:
		return fail("no_lane")
	match cmd["type"]:
		Command.BUILD_TOWER:
			return _result(lane.try_build_tower(cmd["cell"], cmd["kind_id"], cmd["confirmed"]))
		Command.SEND_MONSTER:
			return _send_monster(lane, player_id, cmd["kind_id"])
		Command.EVOLVE_TOWER, Command.LEARN_SKILL, Command.RECOLOR_TOWER, Command.HEAL_TOWER:
			return _tower_command(lane, player_id, cmd)
		Command.SELL_TOWER:
			return _sell_tower(lane, cmd["cell"])
		Command.UPGRADE_STAT:
			return _result(lane.upgrade_stat(cmd["evo"], cmd["skill"], cmd["key"]))
		Command.UPGRADE_COLOR:
			return _result(lane.upgrade_color(cmd["color_name"]))
	return fail("not_implemented")


## 레인 함수가 돌려주는 사유 문자열("" = 성공)을 결과로 바꾼다
static func _result(reason: String) -> Dictionary:
	return ok() if reason == "" else fail(reason)


## 시작: 참여한 모든 레인과 보스가 동시에 시작한다 (수입, 보스 제한시간, 몬스터 파견)
func _start_game() -> Dictionary:
	if started:
		return fail("already_started")
	if boss == null:
		return fail("not_ready")
	started = true
	for lane in lanes.values():
		lane.begin()
	boss.begin()
	Log.info(Log.Category.GAME, "시작 버튼: 레인 %d개 동시 시작" % lanes.size())
	return ok()


## 칸 좌표로 타워 하나를 가리키는 명령 4가지. 성공하면 연출 이벤트(링 이펙트)를 붙인다.
func _tower_command(lane: LaneController, player_id: int, cmd: Dictionary) -> Dictionary:
	var cell: Vector2i = cmd["cell"]
	var tower := lane.tower_at(cell)
	var reason := ""
	var event := {"player_id": player_id, "cell": cell}
	match cmd["type"]:
		Command.EVOLVE_TOWER:
			reason = lane.evolve_tower(tower, cmd["evo"])
			event["type"] = "tower_evolved"
			event["evo"] = cmd["evo"]
		Command.LEARN_SKILL:
			reason = lane.learn_tower_skill(tower)
			event["type"] = "skill_learned"
		Command.RECOLOR_TOWER:
			reason = lane.recolor_tower(tower)
			event["type"] = "tower_recolored"
		Command.HEAL_TOWER:
			reason = lane.heal_tower(tower)
			event["type"] = "tower_healed"
	if reason != "":
		return fail(reason)
	# 성공했으므로 tower는 null이 아니다. 결과에 따라 정해지는 값은 지금 채운다
	if cmd["type"] == Command.LEARN_SKILL:
		event["evo"] = tower.evolution
	elif cmd["type"] == Command.RECOLOR_TOWER:
		event["color_name"] = tower.color_info.name
	return ok([event])


## 칸 좌표의 타워를 판다 (투입 골드의 일부 환급). 내 레인의 타워만 가능하다 (명령이 내 레인에서만 찾는다).
func _sell_tower(lane: LaneController, cell: Vector2i) -> Dictionary:
	var tower := lane.tower_at(cell)
	if tower == null:
		return fail("no_tower")
	return ok() if lane.sell_tower(tower) else fail("lane_inactive")


## 몬스터를 생산해 보스 레인으로 보낸다 (수입 영구 증가). 검증을 모두 끝낸 뒤 차감 -> 수입 -> 파견을 이어서 한다.
func _send_monster(lane: LaneController, player_id: int, kind_id: String) -> Dictionary:
	if boss == null or boss.state != BossController.State.RUNNING:
		return fail("not_running")
	var kind: Dictionary = Monsters.DATA.get(kind_id, {})
	if kind.is_empty():
		Log.warn(Log.Category.GAME, "알 수 없는 몬스터 종류: %s" % kind_id)
		return fail("unknown_kind")
	if not Monsters.can_send_in_pve(kind_id):  # 협력에서는 공격형과 지원형만 만들 수 있다
		Log.warn(Log.Category.GAME, "협력에서는 %s(%s)를 만들 수 없음" % [kind.name, Monsters.CATEGORY_DATA[kind.category].name])
		return fail("not_sendable")
	if not boss.can_spawn_player_monster():
		return fail("no_spawn_cell")
	if not lane.try_spend(kind.cost, "%s 생산" % kind.name):
		return fail(lane.spend_failure(kind.cost))
	lane.add_income(kind.income)
	boss.spawn_player_monster(player_id, kind_id)
	return ok()


## 일시정지는 혼자 하는 판에서만 된다 (여럿이 같이 하는 판에서 한 명이 전체를 멈출 수 없다).
## 실제로 장면을 멈추는 건 클라이언트(MainGame)이고, 여기서는 허용 여부만 정한다.
func _set_pause(on: bool) -> Dictionary:
	if not session.is_solo():
		return fail("pause_not_allowed")
	if on == paused:
		return fail("already_%s" % ("paused" if on else "running"))
	paused = on
	return ok([{"type": "pause", "on": on}])
