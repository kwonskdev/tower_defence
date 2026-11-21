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
	return fail("not_implemented")  # 나머지 명령은 뒤 커밋에서 붙인다


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


## 일시정지는 혼자 하는 판에서만 된다 (여럿이 같이 하는 판에서 한 명이 전체를 멈출 수 없다).
## 실제로 장면을 멈추는 건 클라이언트(MainGame)이고, 여기서는 허용 여부만 정한다.
func _set_pause(on: bool) -> Dictionary:
	if not session.is_solo():
		return fail("pause_not_allowed")
	if on == paused:
		return fail("already_%s" % ("paused" if on else "running"))
	paused = on
	return ok([{"type": "pause", "on": on}])
