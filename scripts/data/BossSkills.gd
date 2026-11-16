extends RefCounted
class_name BossSkills
## 보스 라운드별 스킬. 수치는 전부 첫 시도값이라 테스트하면서 여기서만 고친다.
##
## 키: 보스 라운드(1~10). 값: 그 라운드의 스킬 목록. 없으면 스킬 없는 보스.
## 공통 항목
##   id: 스킬 식별자 / name: 배너에 나오는 이름 / text: 배너 설명
##   lane: 영향을 주는 레인. "player"(내 레인) / "boss"(보스 레인) / "both"
## 항상 켜져 있는 스킬(보스가 나오면 바로 적용)이 쓰는 항목
##   wave_interval: 웨이브 주기(초). 없으면 수입 주기(Balance.INCOME_INTERVAL)
##   count_mult: 웨이브 한 묶음의 마릿수 배율. 없으면 1.0
##   wave_affix + affix_every: N번째 웨이브마다(N, 2N, ...) 그 웨이브에 AFFIXES의 변형을 붙인다. 다음 웨이브 미리보기에 먼저 뜬다.
##   guard_per_monster + guard_cap: 비늘 보호막. 필드 위 웨이브 몬스터(참여 레인 평균) 1마리당 보스가 받는 피해가 이만큼 줄고, 최대 guard_cap까지
##   chill_start / chill_full / chill_max: 동상. 이 라운드에서 보스 앞에 선 지 chill_start초부터 dps가 줄기 시작해 chill_full초에 chill_max(비율)가 된다
## 페이즈가 있는 보스(PHASES에 적은 라운드)의 스킬이 쓰는 항목
##   phase: 이 스킬이 켜져 있는 페이즈 번호(1부터). 숫자 하나 또는 배열. 없으면 모든 페이즈에서 켜져 있다
##   quiet: true이면 켜질 때 배너를 따로 띄우지 않는다 (페이즈 안내문이 대신 설명한다)
##   affix_offset: wave_affix가 붙는 웨이브 번호를 밀어 준다. (번호 - offset)이 affix_every의 배수일 때 붙는다 (번갈아 붙일 때 쓴다)
## 발동형 스킬(조건이 되면 예고 후 발동)이 쓰는 항목
##   trigger: "hp_below"(보스 체력이 hp_ratios의 각 비율 이하가 될 때 한 번씩) / "every"(first초 뒤부터 period초마다)
##   delay: 예고 시간(초). 발동 전에 배너와 몬스터 표식으로 알린다
##   effect: "execute"(보스 앞 DPS 1위 제거 + 환영) / "dread"(보스 앞 DPS 상위 count마리의 dps를 duration초 동안 0)
##           "split"(각 레인에 슬라임 새끼 count마리) / "seal"(각 레인에서 누적 피해 상위 타워 count기를 duration초 동안 사격 불가)
##   execute: refund(비용 환급 비율), phantoms(레인마다 나오는 환영 수), phantom_hp(환영 체력 배율)
##   dread, seal: count, duration / split: count

## 웨이브 변형. 웨이브 전체에 붙는다.
##   speed_mult: 이동속도 배율 / revive: 처음 죽을 때 이 비율의 체력으로 한 번 되살아남 / air_only: 공중 몬스터 종류만 뽑는다
const AFFIXES := {
	"charge": {"name": "돌격", "color": Color(1.0, 0.6, 0.2), "speed_mult": 1.5,
		"text": "이번 웨이브는 돌격: 이동속도 +50%. 느리게 만들거나 미로를 길게 쓰자."},
	"undead": {"name": "부활", "color": Color(0.85, 0.85, 0.75), "revive": 0.5,
		"text": "이번 웨이브는 부활: 처음 죽으면 체력 50%로 한 번 되살아난다 (골드는 마지막에만)."},
	"airraid": {"name": "공습", "color": Color(0.5, 0.75, 0.95), "air_only": true,
		"text": "이번 웨이브는 공습: 전부 공중 몬스터. 대공 타워만 공격할 수 있다."},
}

## 페이즈: 보스 체력이 내려가면서 단계가 바뀐다. 키는 라운드, 값은 단계 목록 (from: 이 단계가 시작되는 체력 비율)
## 단계가 바뀌면 그 단계의 스킬만 켜지고 이전 단계의 스킬은 꺼진다 (주기 스킬의 시계도 새로 시작한다).
const PHASES := {
	10: [
		{"from": 1.0, "name": "페이즈 1: 파멸의 압박", "lane": "player",
			"text": "웨이브가 25초마다 오고 2웨이브마다 돌격합니다. 체력이 66% 아래로 내려가면 페이즈 2."},
		{"from": 0.66, "name": "페이즈 2: 심판", "lane": "both",
			"text": "웨이브가 부활과 공습으로 번갈아 오고, 체력 60/40%에서 보스 앞 DPS 1위가 처단됩니다. 체력이 33% 아래로 내려가면 페이즈 3."},
		{"from": 0.33, "name": "페이즈 3: 종말", "lane": "both",
			"text": "웨이브가 20초마다 오고, 슬라임 새끼가 분열하고, 공포와 봉인이 이어집니다."},
	],
}

const BY_LEVEL := {
	2: [
		{"id": "howl", "name": "울부짖음", "lane": "player",
			"text": "웨이브가 20초마다 옵니다 (수입은 30초). 한 번에 오는 수는 줄어듭니다.",
			"wave_interval": 20.0, "count_mult": 0.75},
	],
	3: [
		{"id": "charge", "name": "돌격 북소리", "lane": "player",
			"text": "2웨이브마다 한 번, 그 웨이브 전체의 이동속도가 +50%입니다. 다음 웨이브 미리보기에 '돌격'이 먼저 뜹니다.",
			"wave_affix": "charge", "affix_every": 2},
	],
	4: [
		{"id": "undead", "name": "되살아나는 뼈", "lane": "player",
			"text": "3웨이브마다 한 번, 그 웨이브 몬스터는 처음 죽으면 체력 50%로 한 번 되살아납니다. 골드는 마지막에 죽을 때만 줍니다.",
			"wave_affix": "undead", "affix_every": 3},
	],
	5: [
		{"id": "split", "name": "분열", "lane": "player",
			"text": "보스 체력이 50% 아래로 내려가면 한 번, 각 레인에 슬라임 새끼 4마리가 나타납니다. 새끼는 시야 안의 벽 타워를 갉아 부숩니다 (트랩 타워는 못 봅니다).",
			"trigger": "hp_below", "hp_ratios": [0.5], "delay": 3.0, "effect": "split", "count": 4},
	],
	6: [
		{"id": "chill", "name": "동상", "lane": "boss",
			"text": "보스 앞에 10초 넘게 서 있으면 DPS가 줄기 시작해 40초에 -50%가 됩니다. 새로 도착한 몬스터는 다시 100%이니 계속 보강하세요.",
			"chill_start": 10.0, "chill_full": 40.0, "chill_max": 0.5},
	],
	7: [
		{"id": "execute", "name": "처단", "lane": "both",
			"text": "체력 75/50/25%에서 보스 앞 DPS 1위 몬스터가 3초 예고 뒤 제거됩니다 (비용의 50% 환급). 동시에 각 레인에 환영(중장갑)이 나타납니다.",
			"trigger": "hp_below", "hp_ratios": [0.75, 0.5, 0.25], "delay": 3.0,
			"effect": "execute", "refund": 0.5, "phantoms": 1, "phantom_hp": 1.5},
	],
	8: [
		{"id": "airraid", "name": "공습", "lane": "player",
			"text": "2웨이브마다 한 번, 그 웨이브가 전부 공중 몬스터입니다. 대공 타워가 없으면 막을 수 없습니다.",
			"wave_affix": "airraid", "affix_every": 2},
		{"id": "scale_guard", "name": "비늘 보호막", "lane": "both",
			"text": "필드 위 웨이브 몬스터 1마리당 보스가 받는 피해가 2% 줄어듭니다 (최대 40%). 웨이브를 빨리 잡아야 합니다.",
			"guard_per_monster": 0.02, "guard_cap": 0.4},
	],
	9: [
		{"id": "dread", "name": "공포", "lane": "boss",
			"text": "25초마다 보스 앞 DPS 상위 3마리가 3초 예고 뒤 6초간 DPS 0이 됩니다. 한두 마리에 화력을 몰아주지 마세요.",
			"trigger": "every", "first": 15.0, "period": 25.0, "delay": 3.0,
			"effect": "dread", "count": 3, "duration": 6.0},
		{"id": "seal", "name": "봉인", "lane": "player",
			"text": "25초마다 각 레인에서 누적 피해가 가장 큰 타워 3기가 3초 예고 뒤 8초간 사격하지 못합니다. 한 타워에만 의존하지 마세요.",
			"trigger": "every", "first": 27.0, "period": 25.0, "delay": 3.0,
			"effect": "seal", "count": 3, "duration": 8.0},
	],
	# Lv.10 파멸의 왕: 새 스킬 없이 앞 라운드의 스킬을 페이즈별로 조합한다 (설명은 PHASES의 안내문이 대신한다)
	10: [
		{"id": "p1_pressure", "name": "파멸의 압박", "lane": "player", "phase": 1, "quiet": true,
			"text": "웨이브 25초 주기, 2웨이브마다 돌격.",
			"wave_interval": 25.0, "count_mult": 0.85, "wave_affix": "charge", "affix_every": 2},
		{"id": "p2_undead", "name": "되살아나는 뼈", "lane": "player", "phase": 2, "quiet": true,
			"text": "짝수 웨이브는 부활.", "wave_affix": "undead", "affix_every": 2, "affix_offset": 0},
		{"id": "p2_airraid", "name": "공습", "lane": "player", "phase": 2, "quiet": true,
			"text": "홀수 웨이브는 공습.", "wave_affix": "airraid", "affix_every": 2, "affix_offset": 1},
		{"id": "p2_execute", "name": "처단", "lane": "both", "phase": 2, "quiet": true,
			"text": "보스 앞 DPS 1위 제거 + 환영.",
			"trigger": "hp_below", "hp_ratios": [0.6, 0.4], "delay": 3.0,
			"effect": "execute", "refund": 0.5, "phantoms": 1, "phantom_hp": 1.5},
		{"id": "p3_pressure", "name": "종말의 압박", "lane": "player", "phase": 3, "quiet": true,
			"text": "웨이브 20초 주기.", "wave_interval": 20.0, "count_mult": 0.75},
		{"id": "p3_split", "name": "분열", "lane": "player", "phase": 3, "quiet": true,
			"text": "슬라임 새끼 4마리.",
			"trigger": "hp_below", "hp_ratios": [0.3], "delay": 3.0, "effect": "split", "count": 4},
		{"id": "p3_dread", "name": "공포", "lane": "boss", "phase": 3, "quiet": true,
			"text": "DPS 상위 3마리 DPS 0.",
			"trigger": "every", "first": 10.0, "period": 25.0, "delay": 3.0,
			"effect": "dread", "count": 3, "duration": 6.0},
		{"id": "p3_seal", "name": "봉인", "lane": "player", "phase": 3, "quiet": true,
			"text": "상위 타워 3기 봉인.",
			"trigger": "every", "first": 22.0, "period": 25.0, "delay": 3.0,
			"effect": "seal", "count": 3, "duration": 8.0},
	],
}


static func of_level(level: int) -> Array:
	return BY_LEVEL.get(level, [])


## 이 라운드의 페이즈 목록 (페이즈가 없는 보스는 빈 배열)
static func phases_of(level: int) -> Array:
	return PHASES.get(level, [])


## 이 스킬이 phase 페이즈에서 켜져 있는가. phase 키가 없으면 항상 켜져 있다 (페이즈 없는 보스는 phase 0)
static func in_phase(skill: Dictionary, phase: int) -> bool:
	if not skill.has("phase"):
		return true
	var p = skill.phase
	if p is Array:
		return phase in p
	return int(p) == phase


## 배너에 붙는 레인 표시
static func lane_tag(lane: String) -> String:
	match lane:
		"player":
			return "내 레인"
		"boss":
			return "보스 레인"
		_:
			return "내 레인 + 보스 레인"
