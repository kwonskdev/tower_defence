extends RefCounted
class_name Balance
## 밸런스 수치 모음. 전부 임시값이며, 밸런스 패치는 이 파일만 고치면 된다.

# --- 경제 ---
const START_GOLD := 150
const BASE_INCOME := 30            # 수입 틱마다 기본으로 들어오는 골드
const INCOME_INTERVAL := 30.0      # 수입 지급 주기(초)
const START_LIVES := 10

# --- 타워 ---
# 기본 능력치에 속성 2개를 조합해서 종류가 만들어진다 (tower_kind 참고).
# 대공 속성은 공중 몬스터가 생길 때 추가한다.
const TOWER_BASE_COST := 4
const TOWER_BASE_RANGE := 3.0      # 칸
const TOWER_BASE_DAMAGE := 0.4
const TOWER_BASE_COOLDOWN := 0.7   # 초

const TOWER_ATTRS := {
	"long": {"name": "장거리", "short": "장", "cost": 2, "color": Color(0.35, 0.75, 1.0)},
	"power": {"name": "고화력", "short": "고", "cost": 3, "color": Color(1.0, 0.45, 0.2)},
	"splash": {"name": "범위", "short": "범", "cost": 3, "color": Color(0.45, 0.9, 0.45)},
	"trap": {"name": "트랩", "short": "트", "cost": 0, "color": Color(0.9, 0.85, 0.3)},
}

# 속성 2개 조합 (대공 제외 6가지)
const TOWER_COMBOS := [
	"long+power", "long+splash", "long+trap",
	"power+splash", "power+trap", "splash+trap",
]

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
	var blocks := true  # 트랩 속성은 길을 막을 수 없다 (몬스터가 위로 지나감)
	var names: Array[String] = []

	for a in parts:
		var attr: Dictionary = TOWER_ATTRS[a]
		cost += int(attr.cost)
		names.append(attr.name)
		match a:
			"long":
				range_v += 2.5
			"power":
				damage *= 2.5
				cooldown *= 1.6
			"splash":
				damage *= 0.7
				splash = 1.2
			"trap":
				range_mult = 0.6   # 사거리는 짧지만
				damage *= 0.8      # 한 발이 강하고
				cooldown *= 0.4    # 공격 속도가 빠르다
				blocks = false

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
	}


# --- 보스가 내 레인으로 보내는 몬스터 (일반형) ---
const MONSTER_SPEED := 3.0         # 초당 이동 칸
const WAVE_MONSTER_HP := 10.0      # 일반 몬스터 기준 체력 (종류별 배율은 WAVE_TYPES)
const WAVE_HP_BONUS_AT_LOW_BOSS := 3.0   # 보스 체력이 0에 가까울수록 몬스터 체력이 (1 + 이 값)배
const WAVE_HP_GROWTH_PER_MIN := 0.15     # 시간이 지날수록 몬스터 체력이 분당 이만큼 증가
const KILL_REWARD := 2
const DISPATCH_INTERVAL := 2.5     # 보스의 자동 파견 주기(초)

# 보스가 보내는 몬스터 종류. unlock: 이 시간(초)이 지나야 등장 / weight: 등장 확률 가중치
# hp: 기준 체력 배율 / life: 기지에 닿았을 때 줄이는 생명 / count: 한 번에 보내는 마릿수
const WAVE_TYPES := {
	"grunt": {"name": "일반", "hp": 1.0, "speed": 3.0, "life": 1, "reward": 2, "size": 1.0,
		"shape": "horn", "color": Color(0.85, 0.2, 0.2), "weight": 5.0, "unlock": 0.0, "count": 1},
	"runner": {"name": "질주", "hp": 0.5, "speed": 5.5, "life": 1, "reward": 2, "size": 0.85,
		"shape": "runner", "color": Color(0.95, 0.55, 0.15), "weight": 3.0, "unlock": 25.0, "count": 1},
	"swarm": {"name": "무리", "hp": 0.3, "speed": 3.8, "life": 1, "reward": 1, "size": 0.65,
		"shape": "horn", "color": Color(0.75, 0.4, 0.6), "weight": 2.0, "unlock": 50.0, "count": 4},
	"tank": {"name": "중장갑", "hp": 4.5, "speed": 1.8, "life": 2, "reward": 6, "size": 1.4,
		"shape": "armor", "color": Color(0.4, 0.5, 0.65), "weight": 2.0, "unlock": 80.0, "count": 1},
}


## 경과 시간(초)에 맞는 파견 몬스터 종류를 가중치로 뽑는다
static func pick_wave_type(elapsed: float) -> String:
	var total := 0.0
	for id in WAVE_TYPES:
		if elapsed >= WAVE_TYPES[id].unlock:
			total += WAVE_TYPES[id].weight
	var roll := randf() * total
	for id in WAVE_TYPES:
		var t: Dictionary = WAVE_TYPES[id]
		if elapsed < t.unlock:
			continue
		roll -= t.weight
		if roll <= 0.0:
			return id
	return "grunt"

# --- 보스 ---
const BOSS_BASE_HP := 8000.0
const BOSS_HP_PER_EXTRA_PLAYER := 5000.0
const BOSS_TIME_LIMIT := 600.0     # 초
const BOSS_CENTER := Vector2(6.0, 25.0)   # 보스 레인 한가운데 (셀 좌표)
const BOSS_RADIUS := 2.0                  # 칸

# --- 플레이어가 보스 레인으로 보내는 몬스터 (공격형) ---
# cost: 생산 비용 / income: 수입 틱 골드 영구 증가량 / dps: 보스에게 주는 초당 피해(지속)
const SENT_MONSTERS := {
	"income": {"name": "수입형", "short": "수입", "cost": 30, "income": 4, "dps": 0.5, "shape": "coin", "color": Color(0.3, 0.8, 0.3)},
	"balanced": {"name": "균형형", "short": "균형", "cost": 40, "income": 2, "dps": 2.0, "shape": "shield", "color": Color(0.95, 0.7, 0.2)},
	"power": {"name": "화력형", "short": "화력", "cost": 60, "income": 1, "dps": 6.0, "shape": "spike", "color": Color(0.7, 0.3, 0.9)},
}
