extends RefCounted
class_name Evolutions
## 타워 진화 계열 8종 (기본 타워 4종 x 2계열). 수치는 전부 여기서 고친다.
##
## - 타워는 지은 뒤 한 기씩 진화 계열을 하나 고른다 (골드). 진화하면 그 계열의 A 스킬이 붙는다.
## - B 스킬도 타워마다 따로 돈을 내고 배운다 (타워를 선택하면 나오는 "B 스킬 배우기" 버튼).
## - 업그레이드 탭(계열 공통): 계열마다 항목(STATS)이 따로 있고, 항목 하나하나가 레벨 1~MAX_LEVEL이다.
##   항목을 올리면 그 계열로 진화한 모든 타워가 강해진다 (타워를 진화시키기 전에도 미리 올릴 수 있다).
##   B 항목은 B 스킬을 배운 타워에만 효과가 있다.
## - 항목 값은 선형이다: Lv1 값에서 시작해 MAX_LEVEL에서 마지막 값이 되도록 레벨마다 똑같이 변한다 (색깔 업그레이드와 같은 방식).
##   비용은 Balance.STAT_UPGRADE_COST_STEP.

const MAX_LEVEL := 50

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

# 스킬 수치: PARAMS[계열][스킬][키] = [1레벨 값, MAX_LEVEL 값]. 그 사이는 레벨마다 똑같이 변한다 (줄어드는 값은 반대로). 키 하나하나가 업그레이드 탭의 항목 하나다.
# 값은 "Lv1 값 + 49 x 레벨당 증가량"으로 정했다 (레벨당 증가량을 주석에 적음).
# 마릿수/발 수 항목도 소수 레벨 값이 나온다: 평균으로 쓰인다 (Evolutions.roll_int).
const PARAMS := {
	"pierce": {
		"A": {"count": [2, 51], "falloff": [0.30, 0.104]},     # 한 발로 맞히는 최대 마릿수 (첫 적 포함, +1/레벨) / 한 마리 지날 때마다 피해 감소 비율 (-0.4%p/레벨)
		"B": {"tick": [0.1, 0.99], "time": [2.0, 6.9]},        # 독 1중첩의 0.1초당 피해 (방어력 무시, +0.0182/레벨) / 중첩 하나가 유지되는 시간 (+0.1초/레벨)
	},
	"boss": {
		"A": {"chance": [0.10, 0.198], "ratio": [0.20, 0.69], "time": [3.0, 4.96]},   # 방어구 파괴 확률 (+0.2%p/레벨) / 방어력 파괴 비율 (+1%p/레벨) / 지속시간 (+0.04초/레벨)
		"B": {"chance": [0.01, 0.059], "hp": [0.01, 0.059]},   # 즉사 확률 (+0.1%p/레벨) / 최대 체력 대비 이 비율 이하일 때 (+0.1%p/레벨). 명중마다 굴린다 (타워가 많으면 그만큼 자주 굴린다)
	},
	"mass": {
		"A": {"chance": [0.25, 0.495], "mult": [1.5, 2.97]},   # 강타 확률 (+0.5%p/레벨) / 강타 피해 배율 (+0.03/레벨)
		"B": {"radius": [0.5, 0.9], "mult": [1.5, 1.99]},      # 중심부 반경(칸) (미정) / 중심부 피해 배율 (+0.01/레벨)
	},
	"support": {
		"A": {"radius": [1.2, 2.18], "time": [3.0, 4.96], "dmg": [40.0, 138.0]},   # 구름 반경 (+0.02/레벨) / 지속시간 (+0.04/레벨) / 표식 1개당 추가 피해 (+2/레벨, 방어력 적용)
		"B": {"radius": [1.5, 2.48], "count": [2, 6.9]},       # 전파 반경 (+0.02/레벨) / 전파 최대 마릿수 (+0.1/레벨)
	},
	"barrage": {
		"A": {"chance": [0.25, 0.495], "second": [0.8, 1.29]},   # 한 번 더 발사할 확률 (+0.5%p/레벨) / 연발의 위력 배율 (+0.01/레벨)
		"B": {"missiles": [2, 4.45], "power": [1.0, 1.245]},     # 한 번에 발사하는 미사일 수 (+0.05/레벨) / 미사일 한 발의 위력 배율 (+0.005/레벨)
	},
	"skill": {
		"A": {"cooldown": [10.0, 5.1], "radius": [1.5, 2.48], "slow": [0.40, 0.596], "time": [2.0, 3.96]},   # 인스네어: 사용 주기 (-0.1초/레벨) / 반경 (+0.02) / 감속 비율 (+0.4%p) / 지속 (+0.04초)
		"B": {"chance": [0.10, 0.198], "time": [2.0, 3.96]},   # 포획: 확률 (+0.2%p/레벨) / 지속 (+0.04초/레벨)
	},
	"growth": {
		"A": {"per_kill": [0.010, 0.0198], "cap": [0.20, 0.69]},   # 처치 1회당 치명타 확률 증가 (+0.02%p/레벨) / 최대 치명타 확률 (+1%p/레벨)
		"B": {"time": [3.0, 4.96], "haste": [0.10, 0.149]},         # 치명타가 없으면 초기화되는 시간 (+0.04초/레벨) / 중첩당 공격속도 증가 (+0.1%p/레벨)
	},
	"charge": {
		"A": {"rate": [1.0, 1.98], "cap": [6.0, 7.96]},   # 충전 속도 배율 (+0.02/레벨) / 모을 수 있는 최대 충전량 (+0.04/레벨)
		"B": {"stun": [1.0, 1.98]},                       # 최대 충전 폭발 시 기절 시간 (+0.02초/레벨)
	},
}

# 키 이름별 값의 위쪽 한계 (PARAMS를 잘못 고쳐도 확률이 100%를 넘거나 몬스터가 아예 멈추지 않게). 아래쪽 한계는 0.
# chance: 확률 / hp: 처형 기준 비율 / slow: 감속 비율 (1.0이면 몬스터가 멈춘다) / ratio: 방어력 파괴 비율
const KEY_MAX := {"chance": 1.0, "hp": 1.0, "slow": 0.9, "ratio": 1.0}

# 업그레이드 탭 항목: STATS[계열] = [{s: 스킬, k: 키, name: 항목 이름, u: 단위}] (탭에 나오는 순서)
# 단위: n=숫자, mari=마리, bal=발, pct=%, pct1=소수 %, sec=초, cell=칸, mult=배율, num=소수 숫자, cg=충전량
const STATS := {
	"pierce": [
		{"s": "A", "k": "count", "name": "관통 수", "u": "mari"},
		{"s": "A", "k": "falloff", "name": "관통 감쇠", "u": "pct"},
		{"s": "B", "k": "tick", "name": "독 피해", "u": "num"},
		{"s": "B", "k": "time", "name": "독 지속", "u": "sec"},
	],
	"boss": [
		{"s": "A", "k": "chance", "name": "파괴 확률", "u": "pct"},
		{"s": "A", "k": "ratio", "name": "파괴 비율", "u": "pct"},
		{"s": "A", "k": "time", "name": "파괴 시간", "u": "sec"},
		{"s": "B", "k": "chance", "name": "처형 확률", "u": "pct"},
		{"s": "B", "k": "hp", "name": "처형 기준", "u": "pct"},
	],
	"mass": [
		{"s": "A", "k": "chance", "name": "강타 확률", "u": "pct"},
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
		{"s": "A", "k": "cooldown", "name": "인스네어 주기", "u": "sec"},
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
		{"s": "A", "k": "cap", "name": "충전 상한", "u": "cg"},
		{"s": "B", "k": "stun", "name": "기절 시간", "u": "sec"},
	],
}

# 진화하면 한 발 피해가 이만큼 배로 늘어난다 (장거리는 진화 전에는 벽 용도라 아주 약하다)
const DAMAGE_MULT := {"pierce": 4.5, "boss": 4.5}

# 계열별 초당 공격 횟수 (없으면 기본 타워 값). 지원형은 구름이 겹쳐 쌓이지 않도록 느리게, 스킬형은 스킬 굴림 횟수를 위해 약간 느리게.
const ATTACK_RATE := {"support": 0.4, "skill": 1.0}

# 성장형 기본 치명타
const CRIT_BASE := 0.05
const CRIT_MULT := 2.0
const HASTE_MAX_STACKS := 10
# 충전형: 이 충전량 이상 모여야 터진다. 피해 = 타워 한 발 x (1 + 충전량 x 이 값). 최대 충전량은 "충전 상한" 항목.
const CHARGE_MIN := 2.0
const CHARGE_DMG_PER_SEC := 1.5


# fmt()의 기본 소수점 자리 (단위별. pct는 % 값의 자리)
const DEFAULT_DIGITS := {"pct1": 1, "sec": 1, "cell": 1, "mult": 2, "num": 1}


## 수치 하나: p("pierce", "A", "count", 레벨). 1레벨 값에서 MAX_LEVEL 값까지 선형. 정수 항목도 소수가 나올 수 있다.
static func p(evo: String, skill: String, key: String, level: int) -> float:
	var arr: Array = PARAMS[evo][skill][key]
	var t := float(clampi(level, 1, MAX_LEVEL) - 1) / float(MAX_LEVEL - 1)
	return limit(key, lerpf(float(arr[0]), float(arr[1]), t))


## 키에 정해진 한계 안으로 자른다 (0 이상, KEY_MAX가 있으면 그 이하)
static func limit(key: String, value: float) -> float:
	return clampf(value, 0.0, float(KEY_MAX.get(key, INF)))


## 소수 값을 정수로: 정수 부분은 확정, 소수 부분은 그 확률로 하나 더 (2.3이면 70%는 2, 30%는 3. 평균이 2.3)
## 시뮬레이션 안에서는 레인의 rng를 넘긴다 (같은 씨앗이면 같은 결과가 나오도록).
static func roll_int(value: float, rng: RandomNumberGenerator) -> int:
	var n := int(floorf(value))
	return n + 1 if rng.randf() < value - n else n


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


## 값 하나를 단위에 맞춰 글자로. digits: 소수점 아래 자리 (pct는 %의 소수점. -1이면 단위마다 정해진 자리)
static func fmt(unit: String, value: float, digits: int = -1) -> String:
	var d := digits if digits >= 0 else int(DEFAULT_DIGITS.get(unit, 0))
	match unit:
		"mari": return _num(value, d) + "마리"
		"bal": return _num(value, d) + "발"
		"pct", "pct1": return _num(value * 100.0, d) + "%"
		"sec": return _num(value, d) + "초"
		"cell": return _num(value, d) + "칸"
		"mult": return "x" + _num(value, d)
		"num": return _num(value, d)
		"cg": return _num(value, d) + "충전"
	return "%d" % roundi(value)


## 소수점 아래 d자리까지 (d=0이면 정수)
static func _num(value: float, d: int) -> String:
	return ("%." + str(d) + "f") % value


## 항목 하나를 한 레벨 올릴 때 바뀌는 크기 (단위가 pct면 %p)
static func level_step(evo: String, stat: Dictionary) -> float:
	var arr: Array = PARAMS[evo][stat.s][stat.k]
	var step := absf(float(arr[1]) - float(arr[0])) / float(MAX_LEVEL - 1)
	return step * 100.0 if stat.u == "pct" or stat.u == "pct1" else step


## 한 레벨 차이가 글자에 보이게 하는 소수점 자리 (최대 3). 레벨이 많아 한 단계가 작은 항목은 자리가 늘어난다.
static func stat_digits(evo: String, stat: Dictionary) -> int:
	var step := level_step(evo, stat)
	var d := 0
	while d < 3 and pow(10.0, -d) > step + 1e-9:
		d += 1
	return d


## 항목 하나의 특정 레벨 값 글자 (업그레이드 탭 버튼용).
static func stat_value_text(evo: String, stat: Dictionary, level: int) -> String:
	var value := p(evo, stat.s, stat.k, level)
	var d := stat_digits(evo, stat)
	return fmt(stat.u, value, d)


static func find_stat(evo: String, skill: String, key: String) -> Dictionary:
	for stat in STATS[evo]:
		if stat.s == skill and stat.k == key:
			return stat
	return {}


## 설명 문구용 값 글자 (lv: v()와 같다)
static func _t(evo: String, skill: String, key: String, lv) -> String:
	var stat := find_stat(evo, skill, key)
	return fmt(stat.u, v(evo, skill, key, lv), stat_digits(evo, stat))


## 스킬 하나의 효과 설명 (한 줄). lv: 정수(모든 항목 같은 레벨) 또는 Dictionary(항목별 레벨)
static func skill_text(evo: String, skill: String, lv) -> String:
	match evo + skill:
		"pierceA":
			return "관통: 한 발로 사거리 안 일직선의 적 %s까지 맞힘 (첫 적 포함, 한 마리 지날 때마다 피해 -%s)" % [
				_t(evo, skill, "count", lv), _t(evo, skill, "falloff", lv)]
		"pierceB":
			return "독: 맞은 적에게 독 중첩 (1중첩 0.1초당 %s, 방어력 무시, 중첩마다 %s 뒤 사라짐)" % [
				_t(evo, skill, "tick", lv), _t(evo, skill, "time", lv)]
		"bossA":
			return "방어구 파괴: %s 확률로 %s간 적 방어력 %s 감소" % [
				_t(evo, skill, "chance", lv), _t(evo, skill, "time", lv), _t(evo, skill, "ratio", lv)]
		"bossB":
			return "처형: %s 확률로 체력 %s 이하 적 즉사 (보스 포함)" % [
				_t(evo, skill, "chance", lv), _t(evo, skill, "hp", lv)]
		"massA":
			return "강타: %s 확률로 피해 %s" % [_t(evo, skill, "chance", lv), _t(evo, skill, "mult", lv)]
		"massB":
			return "중심부: 폭발 중심 %s 안은 피해 %s" % [_t(evo, skill, "radius", lv), _t(evo, skill, "mult", lv)]
		"supportA":
			return "표식 구름: 구름(%s, %s)이 적에게 표식을 남김. 다른 타워가 때리면 표식당 추가 피해 %s (방어력 적용)" % [
				_t(evo, skill, "radius", lv), _t(evo, skill, "time", lv), _t(evo, skill, "dmg", lv)]
		"supportB":
			return "표식 전파: 표식 걸린 적이 죽으면 %s 안 %s에게 표식 이동" % [
				_t(evo, skill, "radius", lv), _t(evo, skill, "count", lv)]
		"barrageA":
			return "연속 발사: %s 확률로 한 번 더 발사 (위력 %s)" % [
				_t(evo, skill, "chance", lv), _t(evo, skill, "second", lv)]
		"barrageB":
			return "일제 사격: 미사일 %s 동시 발사 (발당 %s)" % [
				_t(evo, skill, "missiles", lv), _t(evo, skill, "power", lv)]
		"skillA":
			return "인스네어: %s마다 %s 안 적을 %s간 이동 -%s" % [
				_t(evo, skill, "cooldown", lv), _t(evo, skill, "radius", lv),
				_t(evo, skill, "time", lv), _t(evo, skill, "slow", lv)]
		"skillB":
			return "포획: %s 확률로 공중 몬스터를 %s간 지상에 붙잡음" % [
				_t(evo, skill, "chance", lv), _t(evo, skill, "time", lv)]
		"growthA":
			return "성장: 처치마다 치명타 확률 +%s (최대 %s, 치명타 x%.0f)" % [
				_t(evo, skill, "per_kill", lv), _t(evo, skill, "cap", lv), CRIT_MULT]
		"growthB":
			return "광란: 치명타 시 초당 공격 횟수 +%s (최대 %d중첩)" % [
				_t(evo, skill, "haste", lv), HASTE_MAX_STACKS]
		"chargeA":
			return "충전: 에너지를 모아, 충전량 %.0f 이상이면 적이 있을 때 폭발 (충전량 비례, 터지면 0)" % CHARGE_MIN
		"chargeB":
			return "과충전 기절: 최대 충전 폭발 시 %s 기절" % _t(evo, skill, "stun", lv)
	return ""


## 계열 설명 (진화 전 기준 한 줄씩)
static func tooltip(evo: String) -> String:
	var d: Dictionary = DATA[evo]
	var head := "%s (%s)" % [d.name, Balance.TOWER_DEFS[d.tower].name]
	if DAMAGE_MULT.has(evo):
		head += " · 한 발 피해 x%.1f" % DAMAGE_MULT[evo]
	return "%s\nA %s\nB %s" % [head, skill_text(evo, "A", 1), skill_text(evo, "B", 1)]
