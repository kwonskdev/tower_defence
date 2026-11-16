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
## (체력 조건/주기 발동 스킬은 해당 보스를 만들 때 이 파일에 항목을 추가한다)

const BY_LEVEL := {
	2: [
		{"id": "howl", "name": "울부짖음", "lane": "player",
			"text": "웨이브가 20초마다 옵니다 (수입은 30초). 한 번에 오는 수는 줄어듭니다.",
			"wave_interval": 20.0, "count_mult": 0.75},
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
