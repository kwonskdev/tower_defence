class_name CommandMessages
## 명령이 거절된 사유(CommandBus가 돌려주는 reason 코드)를 플레이어에게 보여 줄 문구로 바꾼다.
## 서버는 사유 코드만 보내고, 문구는 클라이언트가 정한다.

## 화면에 알리지 않는 사유: 길 막힘은 확인창이 따로 있고, already_*는 같은 동작을 두 번 눌렀을 뿐이다.
const SILENT := ["path_blocked", "already_started", "already_paused", "already_running"]

const TEXTS := {
	"not_enough_gold": "골드가 부족합니다.",
	"lane_inactive": "이 레인은 더 이상 행동할 수 없습니다.",
	"cell_not_empty": "이 칸에는 지을 수 없습니다.",
	"invalid_cell": "이 칸에는 지을 수 없습니다.",
	"monster_on_cell": "몬스터가 있는 칸에는 지을 수 없습니다.",
	"not_my_lane": "내 레인에서만 지을 수 있습니다.",
	"no_tower": "타워를 먼저 선택하세요.",
	"cannot_evolve": "이미 진화한 타워입니다.",
	"invalid_evolution": "이 타워가 고를 수 없는 진화입니다.",
	"cannot_learn": "B 스킬을 배울 수 없습니다. (진화 전이거나 이미 배웠습니다)",
	"already_full": "내구도가 이미 가득 찼습니다.",
	"max_level": "이미 최대 레벨입니다.",
	"invalid_stat": "올릴 수 없는 항목입니다.",
	"invalid_color": "올릴 수 없는 색깔입니다.",
	"unknown_kind": "알 수 없는 종류입니다.",
	"not_running": "시작 버튼을 눌러야 만들 수 있습니다.",
	"not_sendable": "협력에서는 만들 수 없는 몬스터입니다.",
	"no_spawn_cell": "몬스터가 나올 자리가 없습니다.",
	"not_ready": "아직 준비 중입니다.",
	"pause_not_allowed": "여럿이 하는 판에서는 일시정지할 수 없습니다.",
	"not_participant": "이 판의 참여자가 아닙니다.",
	"no_lane": "내 레인이 없습니다.",
	"not_implemented": "아직 지원하지 않는 행동입니다.",
	"bad_command": "잘못된 요청입니다.",
}


## 사유 코드의 안내 문구. 알리지 않을 사유면 "". 모르는 사유는 코드를 그대로 보여 준다 (문구를 빠뜨려도 원인을 알 수 있게).
static func text(reason: String) -> String:
	if reason in SILENT:
		return ""
	return TEXTS.get(reason, "실행할 수 없습니다. (%s)" % reason)
