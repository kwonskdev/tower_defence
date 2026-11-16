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
## (체력 조건/주기 발동 스킬은 해당 보스를 만들 때 이 파일에 항목을 추가한다)

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
	8: [
		{"id": "airraid", "name": "공습", "lane": "player",
			"text": "2웨이브마다 한 번, 그 웨이브가 전부 공중 몬스터입니다. 대공 타워가 없으면 막을 수 없습니다.",
			"wave_affix": "airraid", "affix_every": 2},
		{"id": "scale_guard", "name": "비늘 보호막", "lane": "both",
			"text": "필드 위 웨이브 몬스터 1마리당 보스가 받는 피해가 2% 줄어듭니다 (최대 40%). 웨이브를 빨리 잡아야 합니다.",
			"guard_per_monster": 0.02, "guard_cap": 0.4},
	],
}


static func of_level(level: int) -> Array:
	return BY_LEVEL.get(level, [])


## 배너에 붙는 레인 표시
static func lane_tag(lane: String) -> String:
	match lane:
		"player":
			return "내 레인"
		"boss":
			return "보스 레인"
		_:
			return "내 레인 + 보스 레인"
