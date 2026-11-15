extends RefCounted
class_name Balance
## 밸런스 수치 모음. 전부 임시값이며, 밸런스 패치는 data 폴더의 파일들만 고치면 된다.
## - Balance.gd     : 경제, 기본 타워 4종, 보스 레인 크기
## - Evolutions.gd  : 타워 진화 계열 8종과 스킬 수치 (A/B 스킬, 레벨 1~3)
## - BossLevels.gd  : 보스 10라운드
## - WaveTypes.gd   : 보스가 내 레인으로 보내는 몬스터 종류(상성)
## - SentMonsters.gd: 내가 보스 레인으로 보내는 몬스터 종류

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

# --- 진화 / 스킬 업그레이드 비용 ---
# 타워 1기를 진화시키는 비용. 선택하는 순간 A 스킬을 배운다 (그 계열을 처음 진화하면 A 스킬 1레벨).
const EVOLVE_COST := 30
# 업그레이드 탭 (같은 계열의 모든 타워에 적용):
#  - B 스킬 배우기: 계열마다 한 번
#  - 항목 레벨 올리기: 현재 레벨 1 -> 2, 2 -> 3 일 때의 비용 (항목마다 따로)
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
const WAVE_MONSTER_HP := 10.0      # 일반 몬스터 기준 체력 (종류/라운드별 배율은 WaveTypes, BossLevels)
const WAVE_HP_BONUS_AT_LOW_BOSS := 1.5   # 보스 체력이 0에 가까울수록 몬스터 체력이 (1 + 이 값)배
const BOSS_HP_PER_EXTRA_PLAYER := 0.8    # 참여 인원이 1명 늘 때마다 보스 체력 +80%
const BOSS_CENTER := Vector2(6.0, 25.0)  # 보스 레인 한가운데 (셀 좌표)
const BOSS_RADIUS := 2.0                 # 칸
