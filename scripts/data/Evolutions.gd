extends RefCounted
class_name Evolutions
## 타워 진화 계열 8종 (기본 타워 4종 x 2계열). 수치는 전부 여기서 고친다.
##
## - 타워는 지은 뒤 한 기씩 진화 계열을 하나 고른다 (골드). 선택하는 순간 그 계열의 A 스킬을 배운다.
## - 스킬 레벨(A/B 각각 1~3)은 업그레이드 탭에서 올리며, 같은 계열의 모든 타워에 공통 적용된다.
##   B 스킬은 레벨 0(안 배움)에서 시작해 업그레이드 탭에서 사서 배운다.

const MAX_LEVEL := 3

# 기본 타워 -> 진화 계열 2개
const TREE := {
	"long": ["pierce", "boss"],
	"splash": ["mass", "support"],
	"air": ["barrage", "skill"],
	"trap": ["growth", "charge"],
}

const ORDER := ["pierce", "boss", "mass", "support", "barrage", "skill", "growth", "charge"]

const DATA := {
	"pierce": {"tower": "long", "name": "관통형", "short": "관통", "color": Color(0.4, 0.9, 1.0),
		"a_name": "관통", "b_name": "독"},
	"boss": {"tower": "long", "name": "보스형", "short": "보스", "color": Color(1.0, 0.35, 0.35),
		"a_name": "방어구 파괴", "b_name": "처형"},
	"mass": {"tower": "splash", "name": "대량 처리형", "short": "대량", "color": Color(1.0, 0.65, 0.2),
		"a_name": "강타", "b_name": "중심부"},
	"support": {"tower": "splash", "name": "지원형", "short": "지원", "color": Color(0.75, 0.5, 1.0),
		"a_name": "표식 구름", "b_name": "표식 전파"},
	"barrage": {"tower": "air", "name": "난사형", "short": "난사", "color": Color(1.0, 0.85, 0.3),
		"a_name": "연속 발사", "b_name": "일제 사격"},
	"skill": {"tower": "air", "name": "스킬형", "short": "스킬", "color": Color(0.55, 0.8, 1.0),
		"a_name": "인스네어", "b_name": "포획"},
	"growth": {"tower": "trap", "name": "성장형", "short": "성장", "color": Color(1.0, 0.45, 0.65),
		"a_name": "성장", "b_name": "광란"},
	"charge": {"tower": "trap", "name": "충전형", "short": "충전", "color": Color(1.0, 0.95, 0.4),
		"a_name": "충전", "b_name": "과충전 기절"},
}

# 스킬 수치: PARAMS[계열][스킬][키] = [1레벨, 2레벨, 3레벨]
const PARAMS := {
	"pierce": {
		"A": {"count": [2, 3, 4], "falloff": [0.30, 0.25, 0.20]},   # 추가로 관통하는 마릿수 / 관통할 때마다 피해 감소 비율
		"B": {"dps": [0.05, 0.08, 0.12], "time": [4.0, 5.0, 6.0]},   # 독 1중첩당 초당 피해 / 마지막으로 맞은 뒤 유지 시간
	},
	"boss": {
		"A": {"chance": [0.15, 0.22, 0.30], "time": [3.0, 4.0, 5.0]},   # 방어구 파괴 확률 / 지속시간
		"B": {"chance": [0.03, 0.05, 0.08], "hp": [0.08, 0.12, 0.18]},   # 즉사 확률 / 최대 체력 대비 이 비율 이하일 때
	},
	"mass": {
		"A": {"every": [4, 3, 3], "mult": [2.0, 2.2, 2.5]},   # N번째 공격마다 / 피해 배율
		"B": {"radius": [0.5, 0.7, 0.9], "mult": [1.6, 1.8, 2.0]},   # 중심부 반경(칸) / 중심부 피해 배율
	},
	"support": {
		"A": {"radius": [1.2, 1.4, 1.6], "time": [3.0, 3.5, 4.0], "dmg": [0.4, 0.7, 1.1]},   # 구름 반경 / 지속시간 / 표식 1개당 추가 피해
		"B": {"radius": [1.5, 2.0, 2.5], "count": [2, 3, 4]},   # 전파 반경 / 전파 최대 마릿수
	},
	"barrage": {
		"A": {"chance": [0.25, 0.35, 0.50]},   # 한 번 더 발사할 확률
		"B": {"missiles": [2, 3, 4]},          # 한 번에 발사하는 미사일 수
	},
	"skill": {
		"A": {"chance": [0.30, 0.40, 0.50], "radius": [1.5, 2.0, 2.5], "slow": [0.40, 0.50, 0.60], "time": [2.0, 2.5, 3.0]},   # 인스네어: 확률 / 반경 / 감속 비율 / 지속
		"B": {"chance": [0.10, 0.15, 0.20], "time": [2.0, 3.0, 4.0]},   # 포획: 확률 / 지속
	},
	"growth": {
		"A": {"per_kill": [0.010, 0.015, 0.020], "cap": [0.50, 0.60, 0.75]},   # 처치 1회당 치명타 확률 증가 / 최대 치명타 확률
		"B": {"time": [3.0, 4.0, 5.0], "haste": [0.10, 0.15, 0.20]},   # 치명타가 없으면 초기화되는 시간 / 중첩당 공격속도 증가
	},
	"charge": {
		"A": {"rate": [1.0, 1.5, 2.0]},          # 충전 속도 배율
		"B": {"stun": [1.0, 1.5, 2.0]},          # 최대 충전 폭발 시 기절 시간
	},
}

# 계열별 공격 간격 (없으면 기본 타워 값). 지원형은 구름이 겹쳐 쌓이지 않도록 느리게, 스킬형은 스킬 굴림 횟수를 위해 약간 느리게.
const COOLDOWN := {"support": 2.5, "skill": 1.0}

# 성장형 기본 치명타
const CRIT_BASE := 0.05
const CRIT_MULT := 2.0
const HASTE_MAX_STACKS := 10
# 충전형: 이 시간(충전량) 이상 모여야 터지고, 최대치를 넘지 않는다. 피해 = 타워 한 발 x (1 + 충전량 x 이 값)
const CHARGE_MIN := 2.0
const CHARGE_MAX := 6.0
const CHARGE_DMG_PER_SEC := 1.5


## 수치 하나: p("pierce", "A", "count", 레벨)
static func p(evo: String, skill: String, key: String, level: int) -> float:
	var arr: Array = PARAMS[evo][skill][key]
	return float(arr[clampi(level, 1, MAX_LEVEL) - 1])


static func evo_name(evo: String) -> String:
	return DATA[evo].name


static func skill_name(evo: String, skill: String) -> String:
	return DATA[evo]["a_name" if skill == "A" else "b_name"]


## 스킬 레벨 하나의 효과 설명 (level >= 1)
static func skill_text(evo: String, skill: String, lv: int) -> String:
	match evo + skill:
		"pierceA":
			return "관통: 맞은 적 뒤의 적까지 최대 %d마리 더 관통. 관통할 때마다 피해 -%d%%" % [
				int(p(evo, skill, "count", lv)), roundi(p(evo, skill, "falloff", lv) * 100.0)]
		"pierceB":
			return "독: 맞은 적에게 독이 무한 중첩 (1중첩 초당 %.2f 피해, 마지막으로 맞은 뒤 %d초 유지). 독 피해/킬은 이 타워 몫" % [
				p(evo, skill, "dps", lv), int(p(evo, skill, "time", lv))]
		"bossA":
			return "방어구 파괴: %d%% 확률로 %d초간 적의 방어력이 0이 됨" % [
				roundi(p(evo, skill, "chance", lv) * 100.0), int(p(evo, skill, "time", lv))]
		"bossB":
			return "처형: %d%% 확률로 최대 체력의 %d%% 이하인 적을 즉사 (보스 포함)" % [
				roundi(p(evo, skill, "chance", lv) * 100.0), roundi(p(evo, skill, "hp", lv) * 100.0)]
		"massA":
			return "강타: %d번째 공격마다 피해 x%.1f" % [int(p(evo, skill, "every", lv)), p(evo, skill, "mult", lv)]
		"massB":
			return "중심부: 폭발 중심 %.1f칸 안의 적은 피해 x%.1f" % [p(evo, skill, "radius", lv), p(evo, skill, "mult", lv)]
		"supportA":
			return "표식 구름: 공격 대신 구름(반경 %.1f칸, %.1f초)을 깔아 닿은 적에게 표식을 1개씩 남김 (구름 1개당 1회, 중첩 가능). 표식 1개당 다른 타워에게 맞을 때 추가 피해 %.1f, 한 번 맞으면 표식이 전부 터짐" % [
				p(evo, skill, "radius", lv), p(evo, skill, "time", lv), p(evo, skill, "dmg", lv)]
		"supportB":
			return "표식 전파: 표식이 걸린 적이 죽으면 반경 %.1f칸 안의 표식 없는 적 최대 %d마리에게 표식을 옮김" % [
				p(evo, skill, "radius", lv), int(p(evo, skill, "count", lv))]
		"barrageA":
			return "연속 발사: %d%% 확률로 미사일을 한 번 더 발사" % roundi(p(evo, skill, "chance", lv) * 100.0)
		"barrageB":
			return "일제 사격: 한 번에 미사일 %d발 (가능하면 서로 다른 적을 조준)" % int(p(evo, skill, "missiles", lv))
		"skillA":
			return "인스네어: 공격이 %d%% 확률로 반경 %.1f칸의 적을 %.1f초간 이동속도 -%d%%" % [
				roundi(p(evo, skill, "chance", lv) * 100.0), p(evo, skill, "radius", lv),
				p(evo, skill, "time", lv), roundi(p(evo, skill, "slow", lv) * 100.0)]
		"skillB":
			return "포획: 공격이 %d%% 확률로 공중 몬스터를 %d초간 지상에 붙잡음 (제자리 정지, 지상 타워도 공격 가능)" % [
				roundi(p(evo, skill, "chance", lv) * 100.0), int(p(evo, skill, "time", lv))]
		"growthA":
			return "성장: 처치할 때마다 치명타 확률 +%.1f%% (기본 %d%%, 최대 %d%%). 치명타 피해 x%.0f" % [
				p(evo, skill, "per_kill", lv) * 100.0, roundi(CRIT_BASE * 100.0),
				roundi(p(evo, skill, "cap", lv) * 100.0), CRIT_MULT]
		"growthB":
			return "광란: 치명타가 터지면 공격속도 +%d%% (중첩, 최대 %d회). %d초 동안 치명타가 없으면 초기화" % [
				roundi(p(evo, skill, "haste", lv) * 100.0), HASTE_MAX_STACKS, int(p(evo, skill, "time", lv))]
		"chargeA":
			return "충전: 기본 공격 없음. 적이 없는 동안 에너지를 모아(속도 x%.1f), %.0f초 이상 모이면 적이 들어올 때 부비 트랩 폭발 (피해는 충전량에 비례, 최대 %.0f초분)" % [
				p(evo, skill, "rate", lv), CHARGE_MIN, CHARGE_MAX]
		"chargeB":
			return "과충전 기절: 최대 충전 상태로 터지면 맞은 적을 %.1f초 기절" % p(evo, skill, "stun", lv)
	return ""


## 업그레이드 탭 / 진화 버튼에 붙이는 설명
static func tooltip(evo: String) -> String:
	var d: Dictionary = DATA[evo]
	return "%s (%s 타워)\nA %s: %s\nB %s: %s" % [
		d.name, Balance.TOWER_DEFS[d.tower].name,
		d.a_name, skill_text(evo, "A", 1), d.b_name, skill_text(evo, "B", 1)]
