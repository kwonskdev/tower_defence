extends RefCounted
class_name Balance
## 밸런스 수치 모음. 전부 임시값이며, 밸런스 패치는 data 폴더의 파일들만 고치면 된다.
## - Balance.gd     : 경제, 기본 타워 4종, 보스 레인 크기
## - Evolutions.gd  : 타워 진화 계열 8종과 스킬 수치 (A/B 스킬, 레벨 1~3)
## - BossLevels.gd  : 보스 10라운드
## - Monsters.gd     : 모든 몬스터 (공격형/일반형/공중형). 유저가 만드는 것도 보스가 보내는 것도 같은 목록. 비용/수입/체력/공격력 고정

# --- 경제 ---
const START_GOLD := 150
const BASE_INCOME := 30            # 수입 틱마다 기본으로 들어오는 골드
const INCOME_INTERVAL := 30.0      # 수입 지급 주기(초)
const START_LIVES := 10

# --- 타워 ---
# 기본 타워 4종. 지은 뒤 타워마다 진화 계열을 하나 골라 진화한다 (Evolutions.gd).
const TOWER_KINDS := ["long", "splash", "air", "trap"]

const TOWER_DEFS := {
	"long": {
		"name": "장거리", "cost": 4, "range": 5.5, "damage": 0.2, "cooldown": 1.4, "splash": 0.0,
		"blocks": true, "anti_air": false, "color": Color(0.35, 0.75, 1.0),
		"desc": "사정거리가 길지만 공격속도가 느리다. 진화 전에는 거의 못 잡는다: 미로를 만드는 벽 용도. 적을 잡는 건 범위/트랩 몫이고, 진화하면 한 발이 훨씬 강해진다.",
	},
	"splash": {
		"name": "범위", "cost": 7, "range": 3.0, "damage": 0.4, "cooldown": 0.7, "splash": 1.5,
		"blocks": true, "anti_air": false, "color": Color(0.45, 0.9, 0.45),
		"desc": "나머지는 평범하지만 공격이 폭발해서 주변 적에게 모두 들어간다.",
	},
	"air": {
		"name": "대공", "cost": 6, "range": 3.5, "damage": 0.7, "cooldown": 0.7, "splash": 0.0,
		"blocks": true, "anti_air": true, "color": Color(1.0, 0.55, 0.85),
		"desc": "지상을 공격하지 못하는 대신 공중 몬스터를 공격한다.",
	},
	"trap": {
		"name": "트랩", "cost": 5, "range": 1.8, "damage": 0.7, "cooldown": 0.4, "splash": 0.0,
		"blocks": false, "anti_air": false, "color": Color(0.9, 0.85, 0.3),
		"desc": "길을 막지 못하고 사거리도 짧지만, 한 발이 강력하고 공격이 빠르다.",
	},
}

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
	"파랑": "penetration",  # 방어력 관통 (방어력 무시 %)
	"남색": "empower",      # 처치 시 보낸 몬스터 N마리 랜덤 강화
	"보라": "lifegain",     # 처치 시 확률로 체력 +1
}

# 색깔 업그레이드 레벨당 보너스 증가량 [레벨1, 레벨2, 레벨3, 레벨4, 레벨5]
# 보너스는 "그 색 타워에만" 적용되고 타워 색은 랜덤이라 전체의 약 1/7에만 효과가 있다. 그래서 수치는 넉넉하게 잡았다.
const COLOR_LEVEL_BONUS := {
	"damage": [0.10, 0.22, 0.36, 0.52, 0.70],      # 공격력 +10%, 22%, 36%, 52%, 70%
	"cooldown": [0.08, 0.17, 0.28, 0.41, 0.56],    # 공격속도 +8%, 17%, 28%, 41%, 56% (충전형은 충전 속도)
	"range": [0.10, 0.20, 0.30, 0.40, 0.50],       # 사거리 +10% ... +50% (+96%는 장거리 타워가 맵 전체를 덮어서 낮췄다)
	"income": [0.15, 0.30, 0.50, 0.75, 1.00],      # 처치 골드 +15% ... +100%
	"penetration": [0.15, 0.25, 0.35, 0.45, 0.60], # 방어력 15%, 25%, 35%, 45%, 60% 무시
	"empower_count": [1, 2, 3, 4, 5],              # 강화할 몬스터 마리수
	"lifegain": [0.02, 0.04, 0.06, 0.09, 0.12],    # 처치당 생명 +1 확률 (웨이브 한 번에 수십 마리를 잡아서 처음보다 낮췄다)
}

# 색깔 업그레이드 비용: 레벨 N으로 올리는 비용 = COLOR_UPGRADE_COSTS[N-1] (0→1, 1→2, ..., 4→5)
const COLOR_MAX_LEVEL := 5
const COLOR_UPGRADE_COSTS := [20, 30, 45, 65, 90]   # 합계 250골드 (진화 항목 하나가 80골드, 타워 진화 30골드 기준)

# 타워 색깔 바꾸기: 비용을 내면 지금 색을 뺀 6색 중 랜덤으로 바뀐다
const RECOLOR_COST := 10

# 생명 상한 (보라 보너스로 늘어나는 생명이 이 값을 넘지 못한다)
const MAX_LIVES := 20

# UI 표시용 보너스 이름
const COLOR_BONUS_LABELS := {
	"damage": "공격력", "cooldown": "공격속도", "range": "사거리", "income": "처치 골드",
	"penetration": "방어력 관통", "empower": "몬스터 강화", "lifegain": "생명 +1 확률",
}


## 색깔 보너스 수치 글자 (level 0이면 "-"). 예: "+22%", "2마리"
static func color_bonus_value_text(color_name: String, level: int) -> String:
	if level <= 0:
		return "-"
	var type: String = COLOR_BONUS_TYPES[color_name]
	if type == "empower":
		return "%d마리" % COLOR_LEVEL_BONUS["empower_count"][level - 1]
	return "+%d%%" % roundi(float(COLOR_LEVEL_BONUS[type][level - 1]) * 100.0)


## 색깔 보너스 설명 (마우스를 올렸을 때)
static func color_tooltip(color_name: String, level: int) -> String:
	var type: String = COLOR_BONUS_TYPES[color_name]
	var text := "%s: %s (이 색 타워에 적용, 레인 전체 공유)\n" % [color_name, COLOR_BONUS_LABELS[type]]
	match type:
		"damage": text += "이 색 타워의 공격력이 오른다."
		"cooldown": text += "이 색 타워의 공격 간격이 짧아진다."
		"range": text += "이 색 타워의 사거리가 늘어난다."
		"income": text += "이 색 타워가 처치한 몬스터의 골드 보상이 늘어난다."
		"penetration": text += "이 색 타워의 공격이 적 방어력의 일부를 무시한다."
		"empower": text += "이 색 타워가 적을 처치하면 내가 보낸 몬스터 N마리가 %d초간 공격력 +%d%% (같은 몬스터에게 겹치면 효과가 쌓인다)." % [
			roundi(EMPOWER_DURATION), roundi(EMPOWER_BOOST * 100.0)]
		"lifegain": text += "이 색 타워가 적을 처치하면 확률로 생명 +1."
	text += "\n현재 %s" % color_bonus_value_text(color_name, level)
	if level < COLOR_MAX_LEVEL:
		text += " -> 다음 %s" % color_bonus_value_text(color_name, level + 1)
	return text


# 강화 효과 상수
const EMPOWER_DURATION := 8.0      # 강화 지속시간 (초)
const EMPOWER_BOOST := 0.05        # 강화 1회당 +5% (중첩 가능, DPS/성장/체력에 적용)
const EMPOWER_MAX_STACKS := 10     # 한 몬스터에 동시에 쌓이는 최대 중첩 (+50%). 넘으면 가장 먼저 끝날 것이 밀려난다

# --- 진화 / 스킬 업그레이드 비용 ---
# 타워 1기를 진화시키는 비용. 선택하는 순간 A 스킬을 배운다 (그 계열을 처음 진화하면 A 스킬 1레벨).
const EVOLVE_COST := 30
# B 스킬 배우기: 타워 1기마다 (진화처럼 개별).
# 업그레이드 탭(같은 계열의 모든 타워에 적용): 항목 레벨 올리기 비용 (현재 레벨 1 -> 2, 2 -> 3, 항목마다 따로)
const SKILL_LEARN_COST := 40
const STAT_UPGRADE_COSTS := [30, 50]


## 기본 타워 종류 ID("long" 등)로 능력치 딕셔너리를 만든다.
static func tower_kind(kind_id: String) -> Dictionary:
	var d: Dictionary = TOWER_DEFS[kind_id]
	return {
		"id": kind_id,
		"name": d.name,
		"cost": d.cost,
		"range": d.range,
		"damage": d.damage,
		"cooldown": d.cooldown,
		"splash": d.splash,
		"blocks": d.blocks,
		"anti_air": d.anti_air,
		"color": d.color,
		"desc": d.desc,
	}


## 마우스를 올렸을 때 보여줄 타워 상세 설명
static func tower_tooltip(kind: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("%s 타워   [%d골드]" % [kind.name, kind.cost])
	lines.append(kind.desc)
	lines.append("사거리 %.1f칸 / 한 발 %.2f / %.2f초마다 발사 (초당 %.2f)" % [
		kind.range, kind.damage, kind.cooldown, kind.damage / kind.cooldown])
	if kind.splash > 0.0:
		lines.append("- 폭발 범위 %.1f칸 안의 적을 모두 공격" % kind.splash)
	if not kind.blocks:
		lines.append("- 길을 막지 못함 (몬스터가 위로 지나감)")
	if kind.anti_air:
		lines.append("- 공중 몬스터만 공격 (지상 몬스터는 공격 불가)")
	else:
		lines.append("- 지상 몬스터만 공격 (공중 몬스터는 공격 불가)")
	lines.append("지은 뒤 클릭해서 진화 계열을 고를 수 있다: %s" % " / ".join(
		Evolutions.TREE[kind.id].map(func(e): return Evolutions.DATA[e].name)))
	return "\n".join(lines)


# --- 웨이브 ---
# PvE: 수입이 들어오는 시점(INCOME_INTERVAL)마다 웨이브가 한꺼번에 온다. 한 웨이브는 종류가 다른 묶음 WAVE_GROUPS개.
# 묶음은 한 칸에서 촘촘히 쏟아져 나와서 뭉쳐서 온다 (그래야 범위 타워가 값어치를 한다).
# 마릿수는 BossLevels의 interval(압박 기준)과 count_mult로 정해진다 (BossController._group_count).
# (PvP는 다른 레인이 보내는 즉시 몬스터가 오는 방식이라 이 웨이브와는 별개다.)
const WAVE_GROUPS := 3
const WAVE_SPAWN_GAP := 0.18       # 같은 묶음 몬스터가 한 마리씩 나오는 간격(초). 지상 기본 속도면 몸 하나 정도 간격
const WAVE_GROUP_GAP := 0.8        # 묶음과 묶음 사이 간격(초)

# --- 보스 레인 ---
const BOSS_HP_PER_EXTRA_PLAYER := 0.8    # 참여 인원이 1명 늘 때마다 보스 체력 +80%
const BOSS_CENTER := Vector2(6.0, 25.0)  # 보스 레인 한가운데 (셀 좌표)
const BOSS_RADIUS := 2.0                 # 칸
