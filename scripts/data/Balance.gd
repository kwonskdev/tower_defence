extends RefCounted
class_name Balance
## 밸런스 수치 모음. 전부 임시값이며, 밸런스 패치는 data 폴더의 파일들만 고치면 된다.
## - Balance.gd     : 경제, 타워(속성 5개 -> 조합 10종), 보스 레인 크기
## - BossLevels.gd  : 보스 10라운드
## - WaveTypes.gd   : 보스가 내 레인으로 보내는 몬스터 종류(상성)
## - SentMonsters.gd: 내가 보스 레인으로 보내는 몬스터 종류

# --- 경제 ---
const START_GOLD := 150
const BASE_INCOME := 30            # 수입 틱마다 기본으로 들어오는 골드
const INCOME_INTERVAL := 30.0      # 수입 지급 주기(초)
const START_LIVES := 10

# --- 타워 ---
# 기본 능력치에 속성 2개를 조합해서 종류가 만들어진다 (tower_kind 참고).
const TOWER_BASE_COST := 4
const TOWER_BASE_RANGE := 3.0      # 칸
const TOWER_BASE_DAMAGE := 0.4
const TOWER_BASE_COOLDOWN := 0.7   # 초

const TOWER_ATTRS := {
	"long": {"name": "장거리", "short": "장", "cost": 2, "color": Color(0.35, 0.75, 1.0)},
	"power": {"name": "고화력", "short": "고", "cost": 3, "color": Color(1.0, 0.45, 0.2)},
	"splash": {"name": "범위", "short": "범", "cost": 3, "color": Color(0.45, 0.9, 0.45)},
	"trap": {"name": "트랩", "short": "트", "cost": 1, "color": Color(0.9, 0.85, 0.3)},
	"air": {"name": "대공", "short": "공", "cost": 3, "color": Color(1.0, 0.55, 0.85)},
}

# 속성 2개 조합 = 5C2 = 10가지
const TOWER_COMBOS := [
	"long+power", "long+splash", "long+trap", "long+air", "power+splash",
	"power+trap", "power+air", "splash+trap", "splash+air", "trap+air",
]

# 트랩을 같은 칸에 겹쳐 지을 때, 이미 있는 트랩 1개당 건설비가 이만큼 비싸진다 (한 칸에 몰빵 방지)
const TRAP_STACK_COST_STEP := 0.25

# 타워 건설 시 완전 랜덤으로 배정되는 7색 (보너스 효과는 추후 구현)
const TOWER_COLORS := [
	{"name": "빨강", "color": Color(0.92, 0.2, 0.2)},
	{"name": "주황", "color": Color(1.0, 0.6, 0.15)},
	{"name": "노랑", "color": Color(1.0, 0.9, 0.2)},
	{"name": "초록", "color": Color(0.25, 0.8, 0.3)},
	{"name": "파랑", "color": Color(0.25, 0.5, 1.0)},
	{"name": "남색", "color": Color(0.3, 0.25, 0.7)},
	{"name": "보라", "color": Color(0.7, 0.3, 0.85)},
]


## "long+power" 같은 종류 ID로 능력치를 계산한다.
static func tower_kind(kind_id: String) -> Dictionary:
	var parts := kind_id.split("+")
	var range_v := TOWER_BASE_RANGE
	var damage := TOWER_BASE_DAMAGE
	var cooldown := TOWER_BASE_COOLDOWN
	var splash := 0.0
	var cost := TOWER_BASE_COST
	var range_mult := 1.0
	var blocks := true      # 트랩 속성은 길을 막을 수 없다 (몬스터가 위로 지나감)
	var anti_air := false   # 대공 속성은 공중 몬스터만 공격한다 (지상 몬스터는 공격 불가)
	var names: Array[String] = []

	for a in parts:
		var attr: Dictionary = TOWER_ATTRS[a]
		cost += int(attr.cost)
		names.append(attr.name)
		match a:
			"long":
				range_v += 2.0
			"power":
				damage *= 4.0
				cooldown *= 2.2
			"splash":
				damage *= 0.8
				splash = 1.5
			"trap":
				range_mult = 0.6   # 사거리는 짧지만
				damage *= 0.7      # 한 발이 강하고
				cooldown *= 0.5    # 공격 속도가 빠르다
				blocks = false
			"air":
				damage *= 1.6      # 공중만 때릴 수 있는 대신 한 발이 강하다
				anti_air = true

	return {
		"id": kind_id,
		"attrs": parts,
		"name": "+".join(names),
		"cost": cost,
		"range": range_v * range_mult,
		"damage": damage,
		"cooldown": cooldown,
		"splash": splash,
		"blocks": blocks,
		"anti_air": anti_air,
	}


## 마우스를 올렸을 때 보여줄 타워 상세 설명
static func tower_tooltip(kind: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("%s 타워   [%d골드]" % [kind.name, kind.cost])
	lines.append("사거리 %.1f칸 / 한 발 %.2f / %.2f초마다 발사 (초당 %.2f)" % [
		kind.range, kind.damage, kind.cooldown, kind.damage / kind.cooldown])
	var notes: Array[String] = []
	if kind.splash > 0.0:
		notes.append("폭발 범위 %.1f칸 안의 적을 모두 공격" % kind.splash)
	if not kind.blocks:
		notes.append("길을 막지 못함 (몬스터가 위로 지나감). 한 칸에 겹쳐 지을 수 있지만 겹칠수록 비용 +%d%%씩" % int(TRAP_STACK_COST_STEP * 100.0))
	if kind.anti_air:
		notes.append("공중 몬스터만 공격 (지상 몬스터는 공격 불가)")
	else:
		notes.append("지상 몬스터만 공격 (공중 몬스터는 공격 불가)")
	for n in notes:
		lines.append("- " + n)
	for a in kind.attrs:
		lines.append("%s: %s" % [TOWER_ATTRS[a].name, _attr_desc(a)])
	return "\n".join(lines)


static func _attr_desc(attr_id: String) -> String:
	match attr_id:
		"long": return "사거리가 길다. 미로 안을 오래 계속 때릴 수 있다"
		"power": return "한 발이 강하다. 갑옷 입은 적에게 필수"
		"splash": return "범위 공격. 떼로 몰려오는 적에게 좋다"
		"trap": return "길을 못 막는 대신 사거리가 짧고 강하고 빠르다"
		"air": return "공중 몬스터 전용. 한 발이 강하다"
	return ""


# --- 보스 레인 ---
const WAVE_MONSTER_HP := 10.0      # 일반 몬스터 기준 체력 (종류/라운드별 배율은 WaveTypes, BossLevels)
const WAVE_HP_BONUS_AT_LOW_BOSS := 1.5   # 보스 체력이 0에 가까울수록 몬스터 체력이 (1 + 이 값)배
const BOSS_HP_PER_EXTRA_PLAYER := 0.8    # 참여 인원이 1명 늘 때마다 보스 체력 +80%
const BOSS_CENTER := Vector2(6.0, 25.0)  # 보스 레인 한가운데 (셀 좌표)
const BOSS_RADIUS := 2.0                 # 칸
