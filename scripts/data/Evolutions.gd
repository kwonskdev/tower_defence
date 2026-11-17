extends RefCounted
class_name Evolutions
## 타워 진화 계열 8종 (기본 타워 4종 x 2계열). 수치는 전부 여기서 고친다.
##
## - 타워는 지은 뒤 한 기씩 진화 계열을 하나 고른다 (골드). 진화하면 그 계열의 A 스킬이 붙는다.
## - B 스킬도 타워마다 따로 돈을 내고 배운다 (타워를 선택하면 나오는 "B 스킬 배우기" 버튼).
## - 업그레이드 탭(계열 공통): 계열마다 항목(STATS)이 따로 있고, 항목 하나하나가 레벨 1~3이다.
##   항목을 올리면 그 계열로 진화한 모든 타워가 강해진다 (타워를 진화시키기 전에도 미리 올릴 수 있다).
##   B 항목은 B 스킬을 배운 타워에만 효과가 있다.

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

# 스킬 수치: PARAMS[계열][스킬][키] = [1레벨, 2레벨, 3레벨]. 키 하나하나가 업그레이드 탭의 항목 하나다.
const PARAMS := {
	"pierce": {
		"A": {"count": [2, 3, 4], "falloff": [0.30, 0.20, 0.10]},     # 추가로 관통하는 마릿수 / 관통할 때마다 피해 감소 비율
		"B": {"dps": [0.05, 0.09, 0.15], "time": [4.0, 6.0, 8.0]},     # 독 1중첩당 초당 피해 / 마지막으로 맞은 뒤 유지 시간
	},
	"boss": {
		"A": {"chance": [0.15, 0.22, 0.30], "time": [3.0, 4.0, 5.0]},   # 방어구 파괴 확률 / 지속시간
		"B": {"chance": [0.03, 0.05, 0.08], "hp": [0.08, 0.12, 0.18]},   # 즉사 확률 / 최대 체력 대비 이 비율 이하일 때
	},
	"mass": {
		"A": {"every": [4, 3, 2], "mult": [2.0, 2.2, 2.5]},   # N번째 공격마다 / 피해 배율
		"B": {"radius": [0.5, 0.7, 0.9], "mult": [1.6, 1.8, 2.0]},   # 중심부 반경(칸) / 중심부 피해 배율
	},
	"support": {
		"A": {"radius": [1.2, 1.4, 1.6], "time": [3.0, 3.5, 4.0], "dmg": [0.4, 0.7, 1.1]},   # 구름 반경 / 지속시간 / 표식 1개당 추가 피해
		"B": {"radius": [1.5, 2.0, 2.5], "count": [2, 3, 4]},   # 전파 반경 / 전파 최대 마릿수
	},
	"barrage": {
		"A": {"chance": [0.25, 0.35, 0.50], "second": [0.8, 1.0, 1.2]},   # 한 번 더 발사할 확률 / 연발의 위력 배율
		"B": {"missiles": [2, 3, 4], "power": [1.0, 1.15, 1.3]},          # 한 번에 발사하는 미사일 수 / 미사일 한 발의 위력 배율
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
		"A": {"rate": [1.0, 1.5, 2.0], "cap": [6.0, 7.0, 8.0]},   # 충전 속도 배율 / 모을 수 있는 최대 충전량(초)
		"B": {"stun": [1.0, 1.5, 2.0]},                            # 최대 충전 폭발 시 기절 시간
	},
}

# 업그레이드 탭 항목: STATS[계열] = [{s: 스킬, k: 키, name: 항목 이름, u: 단위}] (탭에 나오는 순서)
# 단위: n=숫자, mari=마리, bal=발, beon=번마다, pct=%, pct1=소수 %, sec=초, cell=칸, mult=배율, num=소수 숫자
const STATS := {
	"pierce": [
		{"s": "A", "k": "count", "name": "관통 수", "u": "mari"},
		{"s": "A", "k": "falloff", "name": "관통 감쇠", "u": "pct"},
		{"s": "B", "k": "dps", "name": "독 피해", "u": "num"},
		{"s": "B", "k": "time", "name": "독 지속", "u": "sec"},
	],
	"boss": [
		{"s": "A", "k": "chance", "name": "파괴 확률", "u": "pct"},
		{"s": "A", "k": "time", "name": "파괴 시간", "u": "sec"},
		{"s": "B", "k": "chance", "name": "처형 확률", "u": "pct"},
		{"s": "B", "k": "hp", "name": "처형 기준", "u": "pct"},
	],
	"mass": [
		{"s": "A", "k": "every", "name": "강타 주기", "u": "beon"},
		{"s": "A", "k": "mult", "name": "강타 위력", "u": "mult"},
		{"s": "B", "k": "radius", "name": "중심부 크기", "u": "cell"},
		{"s": "B", "k": "mult", "name": "중심부 위력", "u": "mult"},
	],
	"support": [
		{"s": "A", "k": "radius", "name": "구름 범위", "u": "cell"},
		{"s": "A", "k": "time", "name": "구름 지속", "u": "sec"},
		{"s": "A", "k": "dmg", "name": "표식 피해", "u": "num"},
		{"s": "B", "k": "radius", "name": "전파 범위", "u": "cell"},
		{"s": "B", "k": "count", "name": "전파 수", "u": "mari"},
	],
	"barrage": [
		{"s": "A", "k": "chance", "name": "연발 확률", "u": "pct"},
		{"s": "A", "k": "second", "name": "연발 위력", "u": "mult"},
		{"s": "B", "k": "missiles", "name": "미사일 수", "u": "bal"},
		{"s": "B", "k": "power", "name": "미사일 위력", "u": "mult"},
	],
	"skill": [
		{"s": "A", "k": "chance", "name": "인스네어 확률", "u": "pct"},
		{"s": "A", "k": "radius", "name": "인스네어 범위", "u": "cell"},
		{"s": "A", "k": "slow", "name": "감속 정도", "u": "pct"},
		{"s": "A", "k": "time", "name": "감속 시간", "u": "sec"},
		{"s": "B", "k": "chance", "name": "포획 확률", "u": "pct"},
		{"s": "B", "k": "time", "name": "포획 시간", "u": "sec"},
	],
	"growth": [
		{"s": "A", "k": "per_kill", "name": "처치당 치명타", "u": "pct1"},
		{"s": "A", "k": "cap", "name": "치명타 상한", "u": "pct"},
		{"s": "B", "k": "time", "name": "광란 유지", "u": "sec"},
		{"s": "B", "k": "haste", "name": "중첩당 공속", "u": "pct"},
	],
	"charge": [
		{"s": "A", "k": "rate", "name": "충전 속도", "u": "mult"},
		{"s": "A", "k": "cap", "name": "충전 상한", "u": "sec"},
		{"s": "B", "k": "stun", "name": "기절 시간", "u": "sec"},
	],
}

# 진화하면 한 발 피해가 이만큼 배로 늘어난다 (장거리는 진화 전에는 벽 용도라 아주 약하다)
const DAMAGE_MULT := {"pierce": 4.5, "boss": 4.5}

# 계열별 공격 간격 (없으면 기본 타워 값). 지원형은 구름이 겹쳐 쌓이지 않도록 느리게, 스킬형은 스킬 굴림 횟수를 위해 약간 느리게.
const COOLDOWN := {"support": 2.5, "skill": 1.0}

# 성장형 기본 치명타
const CRIT_BASE := 0.05
const CRIT_MULT := 2.0
const HASTE_MAX_STACKS := 10
# 충전형: 이 시간(충전량) 이상 모여야 터진다. 피해 = 타워 한 발 x (1 + 충전량 x 이 값). 최대 충전량은 "충전 상한" 항목.
const CHARGE_MIN := 2.0
const CHARGE_DMG_PER_SEC := 1.5


## 수치 하나: p("pierce", "A", "count", 레벨)
static func p(evo: String, skill: String, key: String, level: int) -> float:
	var arr: Array = PARAMS[evo][skill][key]
	return float(arr[clampi(level, 1, MAX_LEVEL) - 1])


## 설명 문구용: lv가 정수면 모든 항목이 그 레벨, Dictionary("A.count" -> 레벨)면 항목마다 그 레벨 (없으면 1레벨)
static func v(evo: String, skill: String, key: String, lv) -> float:
	var level := 1
	if lv is Dictionary:
		level = int(lv.get("%s.%s" % [skill, key], 1))
	else:
		level = int(lv)
	return p(evo, skill, key, level)


static func evo_name(evo: String) -> String:
	return DATA[evo].name


static func skill_name(evo: String, skill: String) -> String:
	return DATA[evo]["a_name" if skill == "A" else "b_name"]


## 값 하나를 단위에 맞춰 글자로
static func fmt(unit: String, value: float) -> String:
	match unit:
		"mari": return "%d마리" % roundi(value)
		"bal": return "%d발" % roundi(value)
		"beon": return "%d번마다" % roundi(value)
		"pct": return "%d%%" % roundi(value * 100.0)
		"pct1": return "%.1f%%" % (value * 100.0)
		"sec": return "%.1f초" % value
		"cell": return "%.1f칸" % value
		"mult": return "x%.2f" % value
		"num": return "%.2f" % value
	return "%d" % roundi(value)


## 항목 하나의 특정 레벨 값 글자 (업그레이드 탭 버튼용)
static func stat_value_text(evo: String, stat: Dictionary, level: int) -> String:
	return fmt(stat.u, p(evo, stat.s, stat.k, level))


## 스킬 하나의 효과 설명 (한 줄). lv: 정수(모든 항목 같은 레벨) 또는 Dictionary(항목별 레벨)
static func skill_text(evo: String, skill: String, lv) -> String:
	match evo + skill:
		"pierceA":
			return "관통: 뒤의 적 %d마리까지 관통 (관통할 때마다 피해 -%d%%)" % [
				int(v(evo, skill, "count", lv)), roundi(v(evo, skill, "falloff", lv) * 100.0)]
		"pierceB":
			return "독: 맞은 적에게 중첩 독 (1중첩 초당 %.2f, %d초 유지)" % [
				v(evo, skill, "dps", lv), int(v(evo, skill, "time", lv))]
		"bossA":
			return "방어구 파괴: %d%% 확률로 %d초간 적 방어력 0" % [
				roundi(v(evo, skill, "chance", lv) * 100.0), int(v(evo, skill, "time", lv))]
		"bossB":
			return "처형: %d%% 확률로 체력 %d%% 이하 적 즉사 (보스 포함)" % [
				roundi(v(evo, skill, "chance", lv) * 100.0), roundi(v(evo, skill, "hp", lv) * 100.0)]
		"massA":
			return "강타: %d번째 공격마다 피해 x%.1f" % [int(v(evo, skill, "every", lv)), v(evo, skill, "mult", lv)]
		"massB":
			return "중심부: 폭발 중심 %.1f칸 안은 피해 x%.1f" % [v(evo, skill, "radius", lv), v(evo, skill, "mult", lv)]
		"supportA":
			return "표식 구름: 구름(%.1f칸, %.1f초)이 적에게 표식을 남김. 다른 타워가 때리면 표식당 추가 피해 %.1f" % [
				v(evo, skill, "radius", lv), v(evo, skill, "time", lv), v(evo, skill, "dmg", lv)]
		"supportB":
			return "표식 전파: 표식 걸린 적이 죽으면 %.1f칸 안 %d마리에게 표식 이동" % [
				v(evo, skill, "radius", lv), int(v(evo, skill, "count", lv))]
		"barrageA":
			return "연속 발사: %d%% 확률로 한 번 더 발사 (위력 x%.1f)" % [
				roundi(v(evo, skill, "chance", lv) * 100.0), v(evo, skill, "second", lv)]
		"barrageB":
			return "일제 사격: 미사일 %d발 동시 발사 (발당 x%.2f)" % [
				int(v(evo, skill, "missiles", lv)), v(evo, skill, "power", lv)]
		"skillA":
			return "인스네어: %d%% 확률로 %.1f칸 안 적을 %.1f초간 이동 -%d%%" % [
				roundi(v(evo, skill, "chance", lv) * 100.0), v(evo, skill, "radius", lv),
				v(evo, skill, "time", lv), roundi(v(evo, skill, "slow", lv) * 100.0)]
		"skillB":
			return "포획: %d%% 확률로 공중 몬스터를 %d초간 지상에 붙잡음" % [
				roundi(v(evo, skill, "chance", lv) * 100.0), int(v(evo, skill, "time", lv))]
		"growthA":
			return "성장: 처치마다 치명타 확률 +%.1f%% (최대 %d%%, 치명타 x%.0f)" % [
				v(evo, skill, "per_kill", lv) * 100.0, roundi(v(evo, skill, "cap", lv) * 100.0), CRIT_MULT]
		"growthB":
			return "광란: 치명타 시 공격속도 +%d%% (최대 %d중첩)" % [
				roundi(v(evo, skill, "haste", lv) * 100.0), HASTE_MAX_STACKS]
		"chargeA":
			return "충전: 적이 없을 때 에너지를 모아, %.0f초 이상이면 적이 올 때 폭발 (충전량 비례)" % CHARGE_MIN
		"chargeB":
			return "과충전 기절: 최대 충전 폭발 시 %.1f초 기절" % v(evo, skill, "stun", lv)
	return ""


## 계열 설명 (진화 전 기준 한 줄씩)
static func tooltip(evo: String) -> String:
	var d: Dictionary = DATA[evo]
	var head := "%s (%s)" % [d.name, Balance.TOWER_DEFS[d.tower].name]
	if DAMAGE_MULT.has(evo):
		head += " · 한 발 피해 x%.1f" % DAMAGE_MULT[evo]
	return "%s\nA %s\nB %s" % [head, skill_text(evo, "A", 1), skill_text(evo, "B", 1)]
