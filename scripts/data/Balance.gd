extends RefCounted
class_name Balance
## 밸런스 수치 모음. 전부 임시값이며, 밸런스 패치는 data 폴더의 파일들만 고치면 된다.
## - Balance.gd     : 경제, 기본 타워 4종, 보스 레인 크기
## - Evolutions.gd  : 타워 진화 계열 8종과 스킬 수치 (A/B 스킬, 항목마다 레벨 1~50)
## - BossLevels.gd  : 보스 10라운드
## - Monsters.gd     : 모든 몬스터 (공격형/일반형/공중형). 유저가 만드는 것도 보스가 보내는 것도 같은 목록. 비용/수입/체력/공격력 고정

# --- 경제 ---
const START_GOLD := 150
const BASE_INCOME := 30            # 수입 틱마다 기본으로 들어오는 골드
const INCOME_INTERVAL := 30.0      # 수입 지급 주기(초)
const START_LIVES := 10
const MAX_PLAYERS := 8             # 최대 참여 인원 (레인 수). 유령 점수를 인원이 달라도 비교되게 환산할 때 기준이 된다

# --- 타워 ---
# 기본 타워 4종. 지은 뒤 타워마다 진화 계열을 하나 골라 진화한다 (Evolutions.gd).
const TOWER_KINDS := ["long", "splash", "air", "trap"]

const TOWER_DEFS := {
	"long": {
		"name": "장거리", "cost": 4, "range": 5.5, "damage": 30.0, "attack_rate": 0.7, "splash": 0.0,
		"blocks": true, "anti_air": false, "color": Color(0.35, 0.75, 1.0),
		"desc": "사거리가 길고 느리다. 진화 전엔 길을 막는 벽, 진화하면 한 발이 강해진다.",
	},
	"splash": {
		"name": "범위", "cost": 7, "range": 3.0, "damage": 50.0, "attack_rate": 1.4, "splash": 1.5,
		"blocks": true, "anti_air": false, "color": Color(0.45, 0.9, 0.45),
		"desc": "공격이 폭발해서 주변 적에게 모두 들어간다.",
	},
	"air": {
		"name": "대공", "cost": 6, "range": 3.5, "damage": 80.0, "attack_rate": 1.4, "splash": 0.0,
		"blocks": true, "anti_air": true, "color": Color(1.0, 0.55, 0.85),
		"desc": "공중 몬스터만 공격한다 (지상은 못 때림).",
	},
	"trap": {
		"name": "트랩", "cost": 5, "range": 1.8, "damage": 80.0, "attack_rate": 2.5, "splash": 0.0,
		"blocks": false, "anti_air": false, "color": Color(0.9, 0.85, 0.3),
		"desc": "길을 막지 못하고 사거리가 짧지만 강하고 빠르다.",
	},
}

# 방어력: 받는 피해 = 공격력 x ARMOR_SCALE / (ARMOR_SCALE + 방어력). 방어력 100이면 피해 50%, 400이면 20%.
const ARMOR_SCALE := 100.0

# 타워 내구도: 타워를 갉아 먹는 몬스터(공격형, 슬라임 새끼)가 자기 공격력(초당)만큼 깎는다. 0이 되면 부서지고, 한 번 닳으면 회복되지 않는다.
# 가장 센 공격형(거인, 공격력 95)도 3초 이상 걸리도록 300으로 둔다.
# (길이 막혀서 뚫고 오는 일반 몬스터는 지금처럼 타워를 한 번에 부순다)
const TOWER_DURABILITY := 300.0

# 타워 건설 시 완전 랜덤으로 배정되는 7색
const TOWER_COLORS := [
	{"name": "빨강", "color": Color(0.92, 0.2, 0.2)},
	{"name": "주황", "color": Color(1.0, 0.6, 0.15)},
	{"name": "노랑", "color": Color(1.0, 0.9, 0.2)},
	{"name": "초록", "color": Color(0.25, 0.8, 0.3)},
	{"name": "파랑", "color": Color(0.25, 0.5, 1.0)},
	{"name": "남색", "color": Color(0.3, 0.25, 0.7)},
	{"name": "보라", "color": Color(0.7, 0.3, 0.85)},
]

# --- 색깔 시스템 ---
# 각 색깔의 고유 보너스 타입
const COLOR_BONUS_TYPES := {
	"빨강": "damage",       # 공격력 증가
	"주황": "cooldown",     # 공격속도 증가
	"노랑": "range",        # 사거리 증가
	"초록": "income",       # 처치 시 골드 보너스
	"파랑": "penetration",  # 방어력 관통 (적 방어력을 이만큼 무시. 0까지만)
	"남색": "empower",      # 처치 시 보낸 몬스터 N마리 랜덤 강화
	"보라": "lifegain",     # 처치 시 확률로 체력 +1
}

# 색깔 업그레이드는 선형이다: 레벨 L의 보너스 = L x 레벨당 증가량 (상한 없음).
# 보너스는 "그 색 타워에만" 적용되고 타워 색은 랜덤이라 전체의 약 1/7에만 효과가 있다.
const COLOR_LEVEL_STEP := {
	"damage": 0.01,       # 공격력 +1%씩
	"cooldown": 0.01,     # 초당 공격 횟수 +1%씩 (충전형은 충전 속도)
	"range": 0.01,        # 사거리 +1%씩
	"income": 0.05,       # 처치 골드 +5%씩
	"penetration": 1.0,   # 적 방어력을 1씩 무시 (방어력은 0까지만 깎인다. 몬스터 방어력은 100이 피해 50% 감소인 척도)
	"empower": 0.1,       # 처치 시 강화할 내 몬스터 0.1마리씩 (정수 부분은 확정, 소수 부분은 그 확률로 한 마리 더)
	"lifegain": 0.001,    # 처치당 생명 +1 확률 +0.1%p씩
}

# 색깔 업그레이드 비용: 레벨 N으로 올리는 비용 = N x COLOR_UPGRADE_COST_STEP (10, 20, 30, ... 500골드. 50단계 합계 12,750)
const COLOR_MAX_LEVEL := 50
const COLOR_UPGRADE_COST_STEP := 10

# 타워 색깔 바꾸기: 비용을 내면 지금 색을 뺀 6색 중 랜덤으로 바뀐다
const RECOLOR_COST := 10
const HEAL_COST := 10                 # 타워 내구도 완전 회복

# 타워 판매: 타워가 지금까지 쓴 골드(건설 + 진화 + B 스킬 배우기)의 이 비율을 돌려준다.
# 레인 공유 업그레이드(스탯/색깔)와 소모성(색깔 바꾸기/회복)은 환급 대상이 아니다.
# 시작 버튼을 누르기 전(미리 짓는 단계)에는 배치를 부담 없이 실험하도록 전액 돌려준다.
const SELL_REFUND_RATIO := 0.7
const SELL_REFUND_RATIO_BEFORE_START := 1.0

# 색깔 군집: 같은 색 타워가 상하좌우로 끊기지 않고 N개 이어지면, 그 타워들의 색깔 업그레이드 효과가
# (1 + CLUSTER_BONUS_PER_TOWER * N)배가 된다 (곱연산). 0.01 = 타워 1개당 1%. 혼자(N=1)도 N에 센다.
# N은 길을 막는 타워만 센다. 같은 색 트랩(길을 막지 않는 타워)은 군집에 안 세지만, 군집 바로 옆(상하좌우)에 있으면
# 그 군집의 배율을 똑같이 받는다 (여러 군집에 닿으면 가장 큰 군집).
const CLUSTER_BONUS_PER_TOWER := 0.01

# 생명 상한 (보라 보너스, 패턴 보상으로 늘어나는 생명이 이 값을 넘지 못한다)
# 생명은 소수점까지 들고 있되, 화면과 패배 판정은 내림한 값을 쓴다 (3.6이면 3).
const MAX_LIVES := 20

# UI 표시용 보너스 이름
const COLOR_BONUS_LABELS := {
	"damage": "공격력", "cooldown": "공격속도", "range": "사거리", "income": "처치 골드",
	"penetration": "방어력 관통", "empower": "몬스터 강화", "lifegain": "생명 +1 확률",
}


## 색깔 업그레이드 레벨의 보너스 값 (군집 배율 전). type: COLOR_BONUS_TYPES의 값
static func color_level_bonus(type: String, level: int) -> float:
	return float(COLOR_LEVEL_STEP[type]) * level


## 색깔을 level-1에서 level로 올리는 비용
static func color_upgrade_cost_for(level: int) -> int:
	return COLOR_UPGRADE_COST_STEP * level


## 업그레이드 탭 항목을 level-1에서 level로 올리는 비용 (level은 2 이상)
static func stat_upgrade_cost_for(level: int) -> int:
	return STAT_UPGRADE_COST_STEP * level


## 색깔 보너스 수치 글자 (level 0이면 "-"). 예: "+22%", "2.3마리", "5 무시"
static func color_bonus_value_text(color_name: String, level: int) -> String:
	if level <= 0:
		return "-"
	var type: String = COLOR_BONUS_TYPES[color_name]
	var value := color_level_bonus(type, level)
	match type:
		"empower": return "%.1f마리" % value
		"penetration": return "%d 무시" % roundi(value)
		"lifegain": return "+%.1f%%" % (value * 100.0)
	return "+%d%%" % roundi(value * 100.0)


## 색깔 보너스가 어떤 효과인지 한 문장
static func color_effect(type: String) -> String:
	match type:
		"damage": return "공격력이 오른다."
		"cooldown": return "초당 공격 횟수가 늘어난다."
		"range": return "사거리가 늘어난다."
		"income": return "처치 골드가 늘어난다."
		"penetration": return "적 방어력을 그만큼 무시한다 (0까지만)."
		"empower": return "처치하면 내 몬스터 몇 마리가 %d초간 공격력과 최대 체력 +%d%%." % [roundi(EMPOWER_DURATION), roundi(EMPOWER_BOOST * 100.0)]
		"lifegain": return "처치하면 확률로 생명 +1."
	return ""


## 색깔 보너스 설명 (업그레이드 화면에서 색을 골랐을 때)
static func color_tooltip(color_name: String, level: int) -> String:
	var type: String = COLOR_BONUS_TYPES[color_name]
	var text := "%s · %s\n이 색 타워는 %s 같은 색이 붙을수록 더 강해진다.\n현재 Lv%d/%d %s" % [
		color_name, COLOR_BONUS_LABELS[type], color_effect(type), level, COLOR_MAX_LEVEL, color_bonus_value_text(color_name, level)]
	if level < COLOR_MAX_LEVEL:
		text += " → 다음 %s" % color_bonus_value_text(color_name, level + 1)
	return text


## 설명서용 색깔 설명: 효과와 레벨별 범위
static func color_guide(color_name: String) -> String:
	var type: String = COLOR_BONUS_TYPES[color_name]
	return "%s · %s\n이 색 타워는 %s\n\n업그레이드: Lv1 %s → Lv%d %s\n(올릴 때마다 비용 +%d골드, 10골드부터)" % [
		color_name, COLOR_BONUS_LABELS[type], color_effect(type),
		color_bonus_value_text(color_name, 1), COLOR_MAX_LEVEL, color_bonus_value_text(color_name, COLOR_MAX_LEVEL),
		COLOR_UPGRADE_COST_STEP]


# 강화 효과 상수
const EMPOWER_DURATION := 8.0      # 강화 지속시간 (초)
const EMPOWER_BOOST := 0.05        # 강화 1회당 +5% (중첩 가능, DPS/성장/체력에 적용)
const EMPOWER_MAX_STACKS := 10     # 한 몬스터에 동시에 쌓이는 최대 중첩 (+50%). 넘으면 가장 먼저 끝날 것이 밀려난다

# --- 진화 / 스킬 업그레이드 비용 ---
# 타워 1기를 진화시키는 비용. 선택하는 순간 A 스킬을 배운다 (그 계열을 처음 진화하면 A 스킬 1레벨).
const EVOLVE_COST := 30
# B 스킬 배우기: 타워 1기마다 (진화처럼 개별).
const SKILL_LEARN_COST := 50
# 업그레이드 탭(같은 계열의 모든 타워에 적용): 항목 레벨 올리기 비용. 레벨 N으로 올리는 비용 = N x STAT_UPGRADE_COST_STEP
# (20, 30, ... 500골드. 항목 하나를 Lv50까지 올리는 합계 12,740골드. 항목마다 따로 올린다. 최대 레벨은 Evolutions.MAX_LEVEL)
const STAT_UPGRADE_COST_STEP := 10


## 기본 타워 종류 ID("long" 등)로 능력치 딕셔너리를 만든다.
## 이름으로 타워 색깔 항목을 찾는다 (없으면 첫 색)
static func color_info_by_name(color_name: String) -> Dictionary:
	for c in TOWER_COLORS:
		if c.name == color_name:
			return c
	return TOWER_COLORS[0]


static func tower_kind(kind_id: String) -> Dictionary:
	var d: Dictionary = TOWER_DEFS[kind_id]
	return {
		"id": kind_id,
		"name": d.name,
		"cost": d.cost,
		"range": d.range,
		"damage": d.damage,
		"attack_rate": d.attack_rate,
		"splash": d.splash,
		"blocks": d.blocks,
		"anti_air": d.anti_air,
		"color": d.color,
		"desc": d.desc,
	}


## 마우스를 올렸을 때 보여줄 타워 상세 설명
static func tower_tooltip(kind: Dictionary) -> String:
	return "%s 타워 · %d골드\n%s\n사거리 %.1f · 피해 %.0f · 초당 %.2f회" % [
		kind.name, kind.cost, kind.desc, kind.range, kind.damage, kind.attack_rate]


# --- 웨이브 ---
# PvE: 수입이 들어오는 시점(INCOME_INTERVAL)마다 웨이브가 한꺼번에 온다. 한 웨이브는 종류가 다른 몬스터 최대 WAVE_GROUPS가지.
# 보스는 수입(BossLevels의 income) 안에서 몬스터를 랜덤으로 사서 보낸다 (BossController._plan_next_wave). 몬스터마다 나오는 칸은 따로 랜덤.
# (PvP는 다른 레인이 보내는 즉시 몬스터가 오는 방식이라 이 웨이브와는 별개다.)
const WAVE_GROUPS := 3
const WAVE_SPAWN_GAP := 0.18       # 같은 묶음 몬스터가 한 마리씩 나오는 간격(초). 지상 기본 속도면 몸 하나 정도 간격
const WAVE_GROUP_GAP := 0.8        # 묶음과 묶음 사이 간격(초)

# --- 보스 레인 ---
const BOSS_HP_PER_EXTRA_PLAYER := 0.8    # 참여 인원이 1명 늘 때마다 보스 체력 +80%
const BOSS_CENTER := Vector2(6.0, 25.0)  # 보스 레인 한가운데 (셀 좌표)
const BOSS_RADIUS := 2.0                 # 칸
