extends RefCounted
class_name SentMonsters
## 내가 생산해서 보스 레인으로 보내는 몬스터. 보스 앞에 서서 사라지지 않고 계속 공격한다.
## 컨셉: 수입(비쌀수록 수입 효율이 좋지만 회수가 오래 걸림) / 화력 / 균형 / 특수 / 지원.
##
## cost: 비용 / income: 수입 틱 골드 영구 증가 / dps: 보스에게 주는 초당 피해 / speed: 보스까지 걷는 속도
## ramp, ramp_cap: 보스 앞에 선 뒤 초당 dps가 늘어나는 양과 그 상한 (대기만성형)
## aura_radius, aura_bonus: 주변(칸) 몬스터의 dps를 늘려주는 지원형

# 체력: 항목에 hp를 적으면 그 값, 없으면 비용 x HP_PER_COST. 지금은 보스 스킬(처단 등)과 PvP(상대 타워의 공격)에서만 깎인다.
# 비싼 몬스터가 더 단단하다. 수치는 전부 첫 시도값.
const HP_PER_COST := 1.5

# 계열 색 (버튼 테두리/이름표). 같은 계열끼리 한눈에 묶여 보이도록 쓴다.
const FAMILY_COLORS := {
	"수입": Color(0.95, 0.8, 0.25),
	"화력": Color(0.95, 0.35, 0.3),
	"균형": Color(0.4, 0.75, 0.95),
	"특수": Color(0.7, 0.45, 0.95),
	"지원": Color(0.45, 0.9, 0.55),
}

# 몬스터 배럭 칸 배치 (9열 격자의 두 번째 칸부터: 첫 칸은 뒤로 가기). ""는 계열 사이를 띄우는 빈칸.
# 윗줄 = 수입 4 + 화력 4 / 아랫줄 = 균형 2, 빈칸, 특수 3, 빈칸, 지원 2
const SLOTS := [
	"worker", "miner", "vault", "banker", "warrior", "knight", "crusher", "giant",
	"scout", "mercenary", "", "berserker", "rusher", "sprout", "", "cheer", "banner",
]

const DATA := {
	# --- 수입 계열 ---
	"worker": {"name": "일꾼", "family": "수입", "cost": 20, "income": 3, "dps": 0.3, "speed": 3.0, "size": 0.85, "shape": "hat",
		"color": Color(0.85, 0.8, 0.3), "desc": "싸고 가볍게 수입을 올린다."},
	"miner": {"name": "광부", "family": "수입", "cost": 60, "income": 10, "dps": 0.5, "speed": 2.6, "size": 1.0, "shape": "pick",
		"color": Color(0.6, 0.5, 0.35), "desc": "일꾼보다 비싸지만 골드당 수입이 더 좋다."},
	"vault": {"name": "금고지기", "family": "수입", "cost": 150, "income": 28, "dps": 0.8, "speed": 2.2, "size": 1.2, "shape": "vault",
		"color": Color(0.55, 0.6, 0.65), "desc": "아주 비싸지만 골드당 수입이 훨씬 좋다. 오래 가는 판에서 이득."},
	"banker": {"name": "투자자", "family": "수입", "cost": 400, "income": 90, "dps": 1.0, "speed": 2.0, "size": 1.3, "shape": "tophat",
		"color": Color(0.25, 0.25, 0.3), "desc": "초고가 수입 몬스터. 골드당 수입이 최고지만 본전 회수가 느리다."},
	# --- 화력 계열 ---
	"warrior": {"name": "전사", "family": "화력", "cost": 40, "income": 1, "dps": 4.0, "speed": 3.0, "size": 1.0, "shape": "horn",
		"color": Color(0.8, 0.35, 0.3), "desc": "기본 화력 몬스터."},
	"knight": {"name": "기사", "family": "화력", "cost": 100, "income": 2, "dps": 11.0, "speed": 2.8, "size": 1.1, "shape": "armor",
		"color": Color(0.35, 0.5, 0.8), "desc": "골드당 화력이 전사보다 좋다."},
	"crusher": {"name": "파괴자", "family": "화력", "cost": 260, "income": 4, "dps": 32.0, "speed": 2.4, "size": 1.25, "shape": "spike",
		"color": Color(0.7, 0.3, 0.9), "desc": "높은 화력. 가시가 달린 거대 몬스터."},
	"giant": {"name": "거인", "family": "화력", "cost": 700, "income": 8, "dps": 95.0, "speed": 1.8, "size": 1.6, "shape": "spike",
		"color": Color(0.6, 0.15, 0.15), "desc": "최강 화력. 아주 비싸고 느리다."},
	# --- 균형 계열 ---
	"scout": {"name": "정찰병", "family": "균형", "cost": 30, "income": 2, "dps": 1.5, "speed": 4.5, "size": 0.8, "shape": "runner",
		"color": Color(0.5, 0.8, 0.95), "desc": "빨리 도착한다. 수입과 화력이 모두 낮지만 값이 싸다."},
	"mercenary": {"name": "용병", "family": "균형", "cost": 80, "income": 5, "dps": 5.0, "speed": 3.2, "size": 1.0, "shape": "shield",
		"color": Color(0.95, 0.65, 0.2), "desc": "수입과 화력이 고루 괜찮다."},
	# --- 특수 ---
	"berserker": {"name": "광전사", "family": "특수", "cost": 50, "income": 0, "dps": 8.0, "speed": 3.5, "size": 1.0, "shape": "flame",
		"color": Color(0.9, 0.25, 0.1), "desc": "수입은 전혀 안 오르지만 골드당 화력이 매우 좋다."},
	"rusher": {"name": "돌격병", "family": "특수", "cost": 45, "income": 1, "dps": 3.0, "speed": 7.0, "size": 0.8, "shape": "runner",
		"color": Color(1.0, 0.9, 0.3), "desc": "거의 즉시 도착한다. 시간이 급할 때 쓴다."},
	"sprout": {"name": "대기만성", "family": "특수", "cost": 120, "income": 3, "dps": 1.0, "speed": 2.8, "size": 1.0, "shape": "sprout",
		"ramp": 0.12, "ramp_cap": 18.0, "color": Color(0.4, 0.75, 0.3),
		"desc": "처음엔 약하지만 보스 앞에 서 있을수록 점점 강해진다 (초당 +0.12, 최대 18)."},
	# --- 지원 ---
	"cheer": {"name": "응원단", "family": "지원", "cost": 90, "income": 3, "dps": 0.0, "speed": 3.0, "size": 1.0, "shape": "flag",
		"aura_radius": 2.2, "aura_bonus": 0.3, "color": Color(0.95, 0.5, 0.7),
		"desc": "스스로는 안 싸우지만 주변(2.2칸) 몬스터의 공격력을 +30%."},
	"banner": {"name": "군기병", "family": "지원", "cost": 220, "income": 4, "dps": 0.0, "speed": 2.6, "size": 1.15, "shape": "banner",
		"aura_radius": 3.0, "aura_bonus": 0.5, "color": Color(0.9, 0.75, 0.25),
		"desc": "스스로는 안 싸우지만 주변(3칸) 몬스터의 공격력을 +50%."},
}


## 몬스터의 최대 체력
static func max_hp(kind_id: String) -> float:
	var d: Dictionary = DATA[kind_id]
	return float(d.get("hp", float(d.cost) * HP_PER_COST))


## 마우스를 올렸을 때 보여줄 상세 설명
static func tooltip(kind_id: String) -> String:
	var d: Dictionary = DATA[kind_id]
	var lines: Array[String] = []
	lines.append("%s (%s)   [%d골드]" % [d.name, d.family, d.cost])
	if d.income > 0:
		lines.append("수입 +%d / %.0f초  (본전 회수 약 %d초)" % [d.income, Balance.INCOME_INTERVAL, ceili(float(d.cost) / d.income * Balance.INCOME_INTERVAL)])
	else:
		lines.append("수입 증가 없음")
	if d.dps > 0.0:
		lines.append("보스 공격력 초당 %.1f" % d.dps)
	lines.append("체력 %d / 이동 속도 %.1f칸/초" % [roundi(max_hp(kind_id)), d.speed])
	if d.has("ramp"):
		lines.append("성장: 초당 +%.2f (최대 +%.0f)" % [d.ramp, d.ramp_cap])
	if d.has("aura_bonus"):
		lines.append("지원: 반경 %.1f칸 아군 +%d%%" % [d.aura_radius, int(d.aura_bonus * 100.0)])
	lines.append(d.desc)
	return "\n".join(lines)
