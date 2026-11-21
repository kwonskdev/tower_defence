extends RefCounted
class_name Monsters
## 몬스터 전체 목록 (한 곳). 유저가 만드는 몬스터와 보스가 웨이브로 보내는 몬스터가 모두 이 풀에서 나온다.
## 몬스터마다 비용 / 수입 / 체력 / 공격력이 고정이다 (라운드에 따라 변하지 않는다. 라운드 보정은 나중에).
##
## 공통 값
##   cost: 생산 비용 / income: 생산하면 수입 틱 골드가 영구히 이만큼 오른다 / hp: 체력
##   dps: 공격력 = 초당 피해. 보스 레인에서는 보스에게, 타워 레인에서는 타워(내구도)에게 똑같이 적용된다.
##        일반형/공중형은 타워를 때리지 않아(길이 막히면 한 방에 부순다) null. 슬라임 새끼만 갉으니 값이 있다
##   speed: 이동 속도(칸/초) / size, shape, color: 겉모습 / desc: 설명
## 있을 때만 쓰는 값
##   life: 기지에 닿았을 때 줄이는 생명(기본 1) / armor: 방어력 (받는 피해 = 공격력 x 100 / (100 + 방어력)) / flat_reduce: 방어력으로 줄인 최종 피해에서 추가로 빼는 양 / regen: 초당 최대체력 회복 비율 / flying: 공중
##   reward: 처치 골드 (없으면 비용의 1/10) / gnaws: true면 시야 안의 벽 타워를 찾아가 dps만큼 갉는다 (공격형은 모두 갉는다)
##   ramp, ramp_cap: 보스 앞에 선 뒤 초당 dps가 늘어나는 양과 상한 / aura_radius, aura_bonus: 주변(칸) 몬스터의 dps를 늘려 준다
##   보스가 웨이브로 뽑을 때: weight(가중치) / min_level(이 보스 라운드부터) / count(한 묶음 마릿수) / summon_only(스킬로만 나옴)
##   ghost: true면 유령 (보스를 일찍 잡았을 때 남은 시간에 나온다). 체력이 무한이라 죽지 않고 hp 값은 안 쓴다. 생명을 깎지 않는다.
##          breach_dps: 길이 완전히 막혔을 때만 앞을 막은 타워 내구도(Balance.TOWER_DURABILITY)를 초당 이만큼 깎는다. 길이 열려 있으면 타워를 안 건드린다.
##
## 유형(category)
##   attack 공격형: 보스를 때리러 가는 몬스터 (수입/화력/균형/특수 계열). 유저는 PvE에서 공격형과 지원형만 만들 수 있다.
##   support 지원형: 주변 몬스터의 공격력을 올리는 몬스터 (응원단/군기병).
##   normal 일반형 / air 공중형: 보스가 웨이브로 보내는 몬스터 (종류마다 이기는 타워가 다르다. 상성은 아래).
##
## 상성 요약 (일반형/공중형)
## - 무리(swarm/flock): 마릿수가 많고 약하다 -> 범위 타워.
## - 갑옷(armored/tank/juggernaut): 방어력만큼 받는 피해 비율이 줄어든다 -> 방어구 파괴(장거리 보스형), 방어력 관통(파랑), 방어력을 무시하는 독(관통형).
## - 재생(regen): 초당 체력을 회복한다 -> 한곳에 화력을 집중.
## - 질주(runner): 빨라서 사거리 안에 머무는 시간이 짧다 -> 장거리.
## - 공중(flyer/flock/bomber): 미로를 무시하고 직선으로 온다 -> 대공 타워만 공격 가능.

const CATEGORIES := ["attack", "normal", "support", "air"]

# 유형 정보 (몬스터 배럭의 유형 버튼)
const CATEGORY_DATA := {
	"attack": {"name": "공격형", "color": Color(0.95, 0.4, 0.3),
		"desc": "보스를 공격하러 가는 몬스터 (수입/화력/균형/특수). 협력(PvE)에서도 만들 수 있다."},
	"normal": {"name": "일반형", "color": Color(0.6, 0.7, 0.85),
		"desc": "기본 지상 몬스터. 보스가 웨이브로 보낸다 (협력에서는 만들 수 없다)."},
	"support": {"name": "지원형", "color": Color(0.45, 0.9, 0.55),
		"desc": "스스로는 안 싸우고 주변 몬스터를 강하게 한다. 보스 레인에서 아군 공격력을 올린다 (협력에서도 만들 수 있다)."},
	"air": {"name": "공중형", "color": Color(0.5, 0.8, 1.0),
		"desc": "미로를 무시하고 직선으로 날아온다. 대공 타워만 공격 가능. 보스가 웨이브로 보낸다 (협력에서는 만들 수 없다)."},
}

# 협력(PvE)에서 유저가 만들 수 있는 유형
const PVE_SENDABLE := ["attack", "support"]

# 공격형 계열 색 (버튼 테두리/이름표). 같은 계열끼리 한눈에 묶여 보이도록 쓴다.
const FAMILY_COLORS := {
	"수입": Color(0.95, 0.8, 0.25),
	"화력": Color(0.95, 0.35, 0.3),
	"균형": Color(0.4, 0.75, 0.95),
	"특수": Color(0.7, 0.45, 0.95),
}

# 유형 화면의 칸 배치 (9열 격자를 왼쪽 위부터 차례대로 채운다). ""는 계열 사이를 띄우는 빈칸.
# 공격형: 윗줄 = 수입 4 + 화력 4 + 빈칸 / 아랫줄 = 균형 2, 빈칸, 특수 3
const SLOTS := {
	"attack": [
		"worker", "miner", "vault", "banker", "warrior", "knight", "crusher", "giant", "",
		"scout", "mercenary", "", "berserker", "rusher", "sprout",
	],
	"support": ["cheer", "banner"],
	"normal": ["grunt", "runner", "swarm", "tank", "armored", "regen", "juggernaut", "slimeling"],
	"air": ["flyer", "flock", "bomber"],
}

const DATA := {
	# --- 공격형: 수입 계열 ---
	"worker": {"name": "일꾼", "category": "attack", "family": "수입", "cost": 20, "income": 3, "hp": 3000.0, "dps": 0.3, "speed": 3.0, "size": 0.85, "shape": "hat",
		"color": Color(0.85, 0.8, 0.3), "weight": 0.6, "min_level": 3, "desc": "싸고 가볍게 수입을 올린다."},
	"miner": {"name": "광부", "category": "attack", "family": "수입", "cost": 60, "income": 10, "hp": 9000.0, "dps": 0.5, "speed": 2.6, "size": 1.0, "shape": "pick",
		"color": Color(0.6, 0.5, 0.35), "weight": 0.4, "min_level": 3, "desc": "일꾼보다 비싸지만 골드당 수입이 더 좋다."},
	"vault": {"name": "금고지기", "category": "attack", "family": "수입", "cost": 150, "income": 28, "hp": 22500.0, "dps": 0.8, "speed": 2.2, "size": 1.2, "shape": "vault",
		"life": 2, "color": Color(0.55, 0.6, 0.65), "weight": 0.3, "min_level": 5, "desc": "아주 비싸지만 골드당 수입이 훨씬 좋다. 오래 가는 판에서 이득."},
	"banker": {"name": "투자자", "category": "attack", "family": "수입", "cost": 400, "income": 90, "hp": 60000.0, "dps": 1.0, "speed": 2.0, "size": 1.3, "shape": "tophat",
		"life": 2, "color": Color(0.25, 0.25, 0.3), "weight": 0.2, "min_level": 8, "desc": "초고가 수입 몬스터. 골드당 수입이 최고지만 본전 회수가 느리다."},
	# --- 공격형: 화력 계열 ---
	"warrior": {"name": "전사", "category": "attack", "family": "화력", "cost": 40, "income": 1, "hp": 6000.0, "dps": 4.0, "speed": 3.0, "size": 1.0, "shape": "horn",
		"color": Color(0.8, 0.35, 0.3), "weight": 0.6, "min_level": 3, "desc": "기본 화력 몬스터."},
	"knight": {"name": "기사", "category": "attack", "family": "화력", "cost": 100, "income": 2, "hp": 15000.0, "dps": 11.0, "speed": 2.8, "size": 1.1, "shape": "armor",
		"color": Color(0.35, 0.5, 0.8), "weight": 0.4, "min_level": 3, "desc": "골드당 화력이 전사보다 좋다."},
	"crusher": {"name": "파괴자", "category": "attack", "family": "화력", "cost": 260, "income": 4, "hp": 39000.0, "dps": 32.0, "speed": 2.4, "size": 1.25, "shape": "spike",
		"life": 2, "color": Color(0.7, 0.3, 0.9), "weight": 0.3, "min_level": 6, "desc": "높은 화력. 가시가 달린 거대 몬스터."},
	"giant": {"name": "거인", "category": "attack", "family": "화력", "cost": 700, "income": 8, "hp": 105000.0, "dps": 95.0, "speed": 1.8, "size": 1.6, "shape": "spike",
		"life": 3, "color": Color(0.6, 0.15, 0.15), "weight": 0.2, "min_level": 9, "desc": "최강 화력. 아주 비싸고 느리다."},
	# --- 공격형: 균형 계열 ---
	"scout": {"name": "정찰병", "category": "attack", "family": "균형", "cost": 30, "income": 2, "hp": 4500.0, "dps": 1.5, "speed": 4.5, "size": 0.8, "shape": "runner",
		"color": Color(0.5, 0.8, 0.95), "weight": 0.6, "min_level": 3, "desc": "빨리 도착한다. 수입과 화력이 모두 낮지만 값이 싸다."},
	"mercenary": {"name": "용병", "category": "attack", "family": "균형", "cost": 80, "income": 5, "hp": 12000.0, "dps": 5.0, "speed": 3.2, "size": 1.0, "shape": "shield",
		"color": Color(0.95, 0.65, 0.2), "weight": 0.4, "min_level": 3, "desc": "수입과 화력이 고루 괜찮다."},
	# --- 공격형: 특수 ---
	"berserker": {"name": "광전사", "category": "attack", "family": "특수", "cost": 50, "income": 0, "hp": 7500.0, "dps": 8.0, "speed": 3.5, "size": 1.0, "shape": "flame",
		"color": Color(0.9, 0.25, 0.1), "weight": 0.4, "min_level": 3, "desc": "수입은 전혀 안 오르지만 골드당 화력이 매우 좋다."},
	"rusher": {"name": "돌격병", "category": "attack", "family": "특수", "cost": 45, "income": 1, "hp": 6750.0, "dps": 3.0, "speed": 7.0, "size": 0.8, "shape": "runner",
		"color": Color(1.0, 0.9, 0.3), "weight": 0.4, "min_level": 3, "desc": "거의 즉시 도착한다. 시간이 급할 때 쓴다."},
	"sprout": {"name": "대기만성", "category": "attack", "family": "특수", "cost": 120, "income": 3, "hp": 18000.0, "dps": 1.0, "speed": 2.8, "size": 1.0, "shape": "sprout",
		"ramp": 0.12, "ramp_cap": 18.0, "color": Color(0.4, 0.75, 0.3), "weight": 0.3, "min_level": 4,
		"desc": "처음엔 약하지만 보스 앞에 서 있을수록 점점 강해진다 (초당 +0.12, 최대 18)."},
	# --- 지원형 ---
	"cheer": {"name": "응원단", "category": "support", "cost": 90, "income": 3, "hp": 13500.0, "dps": 0.0, "speed": 3.0, "size": 1.0, "shape": "flag",
		"aura_radius": 2.2, "aura_bonus": 0.3, "color": Color(0.95, 0.5, 0.7), "weight": 0.3, "min_level": 3,
		"desc": "스스로는 안 싸우지만 주변(2.2칸) 몬스터의 공격력을 +30%."},
	"banner": {"name": "군기병", "category": "support", "cost": 220, "income": 4, "hp": 33000.0, "dps": 0.0, "speed": 2.6, "size": 1.15, "shape": "banner",
		"aura_radius": 3.0, "aura_bonus": 0.5, "color": Color(0.9, 0.75, 0.25), "weight": 0.2, "min_level": 6,
		"desc": "스스로는 안 싸우지만 주변(3칸) 몬스터의 공격력을 +50%."},

	# --- 일반형 (보스 웨이브) ---
	"grunt": {"name": "일반", "category": "normal", "cost": 15, "income": 1, "hp": 1000.0, "dps": null, "speed": 3.0, "size": 1.0, "shape": "horn",
		"reward": 2, "color": Color(0.85, 0.2, 0.2), "weight": 5.0, "count": 1, "min_level": 1,
		"desc": "평범한 몬스터."},
	"runner": {"name": "질주", "category": "normal", "cost": 12, "income": 1, "hp": 500.0, "dps": null, "speed": 5.5, "size": 0.85, "shape": "runner",
		"reward": 2, "color": Color(0.95, 0.55, 0.15), "weight": 3.0, "count": 1, "min_level": 1,
		"desc": "빠르다. 사거리 안에 머무는 시간이 짧아서 장거리 타워가 유리."},
	"swarm": {"name": "무리", "category": "normal", "cost": 6, "income": 0, "hp": 300.0, "dps": null, "speed": 3.8, "size": 0.65, "shape": "horn",
		"reward": 1, "color": Color(0.75, 0.4, 0.6), "weight": 3.0, "count": 6, "min_level": 2,
		"desc": "작은 몬스터가 떼로 몰려온다. 범위 타워가 필요."},
	"tank": {"name": "중장갑", "category": "normal", "cost": 60, "income": 3, "hp": 3500.0, "dps": null, "speed": 1.8, "size": 1.4, "shape": "armor",
		"life": 2, "armor": 100.0, "reward": 6, "color": Color(0.4, 0.5, 0.65), "weight": 2.0, "count": 1, "min_level": 7,
		"desc": "체력이 많고 느리다. 기지에 닿으면 생명 -2."},
	"armored": {"name": "갑옷병", "category": "normal", "cost": 35, "income": 2, "hp": 1600.0, "dps": null, "speed": 2.6, "size": 1.0, "shape": "armor",
		"armor": 200.0, "flat_reduce": 10.0, "reward": 4, "color": Color(0.75, 0.6, 0.3), "weight": 3.0, "count": 2, "min_level": 5,
		"desc": "갑옷이 단단하다. 방어력으로 줄어든 피해에서 10을 더 뺀다 (방어구 파괴, 방어력 관통이 유효)."},
	"regen": {"name": "재생체", "category": "normal", "cost": 45, "income": 2, "hp": 2200.0, "dps": null, "speed": 2.8, "size": 1.1, "shape": "cross",
		"regen": 0.07, "reward": 5, "color": Color(0.3, 0.8, 0.5), "weight": 3.0, "count": 1, "min_level": 5,
		"desc": "체력을 계속 회복한다. 화력이 흩어져 있으면 못 잡는다. 한곳에 집중 필요."},
	"juggernaut": {"name": "거신병", "category": "normal", "cost": 200, "income": 8, "hp": 8000.0, "dps": null, "speed": 1.3, "size": 1.7, "shape": "armor",
		"life": 3, "armor": 400.0, "regen": 0.02, "reward": 20, "color": Color(0.25, 0.28, 0.35), "weight": 1.0, "count": 1, "min_level": 8,
		"desc": "엄청나게 단단하고 느리다. 기지에 닿으면 생명 -3."},
	# 보스 스킬로만 나온다 (웨이브에 뽑히지 않는다: summon_only). gnaws: 시야 안의 벽 타워를 찾아가 dps만큼 갉아 먹는다.
	"slimeling": {"name": "슬라임 새끼", "category": "normal", "cost": 8, "income": 0, "hp": 400.0, "dps": 30.0, "speed": 3.4, "size": 0.7, "shape": "spike",
		"reward": 1, "color": Color(0.3, 0.8, 0.35), "weight": 0.0, "count": 1, "min_level": 99, "summon_only": true, "gnaws": true,
		"desc": "슬라임 대장이 분열하면 나온다. 시야 안의 벽 타워를 갉아 먹는다 (트랩 타워는 보지 못한다)."},
	# 보스를 제한시간이 남은 채로 잡으면 그 시간 동안 나온다 (웨이브에 뽑히지 않는다: summon_only). 몬스터 배럭 칸(SLOTS)에는 없다.
	# 공격하지 않고 미로 길만 따라간다. 길이 완전히 막혔을 때만 breach_dps로 앞을 막은 타워를 부순다 (150: 가득 찬 타워(내구도 300)를 2초에, 가장 센 공격형 거인이 95).
	# 속도는 일반(grunt)과 같다. 그림은 GhostArt (보스 레인의 큰 유령과 똑같고 크기만 다르다).
	"ghost": {"name": "유령", "category": "normal", "cost": 0, "income": 0, "hp": 1.0, "dps": null, "speed": 3.0, "size": 1.0, "shape": "ghost",
		"life": 0, "reward": 0, "ghost": true, "breach_dps": 150.0, "color": Color(0.97, 0.98, 1.0), "weight": 0.0, "count": 1, "min_level": 99, "summon_only": true,
		"desc": "보스를 일찍 잡으면 남은 시간에 나온다. 죽지 않고, 기지에 닿으면 처음부터 다시 나온다. 타워가 입힌 피해가 점수가 된다."},

	# --- 공중형 (보스 웨이브) ---
	"flyer": {"name": "비행", "category": "air", "cost": 20, "income": 1, "hp": 700.0, "dps": null, "speed": 4.0, "size": 0.9, "shape": "bird",
		"flying": true, "reward": 3, "color": Color(0.5, 0.75, 0.95), "weight": 3.0, "count": 2, "min_level": 4,
		"desc": "공중으로 미로를 무시하고 직선으로 온다. 대공 타워만 공격 가능."},
	"flock": {"name": "비행 무리", "category": "air", "cost": 5, "income": 0, "hp": 250.0, "dps": null, "speed": 3.5, "size": 0.6, "shape": "bird",
		"flying": true, "reward": 1, "color": Color(0.95, 0.9, 0.5), "weight": 2.0, "count": 8, "min_level": 6,
		"desc": "작은 비행 몬스터 떼. 범위 + 대공 타워가 필요."},
	"bomber": {"name": "폭격기", "category": "air", "cost": 70, "income": 3, "hp": 3500.0, "dps": null, "speed": 2.4, "size": 1.4, "shape": "bird",
		"flying": true, "life": 2, "armor": 50.0, "reward": 8, "color": Color(0.7, 0.25, 0.25), "weight": 2.0, "count": 1, "min_level": 7,
		"desc": "튼튼한 대형 비행 몬스터. 대공 타워를 모아야 한다 (스킬형 포획이 유용). 기지에 닿으면 생명 -2."},
}


## 그 유형의 몬스터 목록 (버튼 칸 배치 순서)
static func slots_of(category: String) -> Array:
	return SLOTS[category]


## 유저가 협력(PvE)에서 만들 수 있는 몬스터인가
static func can_send_in_pve(kind_id: String) -> bool:
	return DATA[kind_id].category in PVE_SENDABLE


## 공격력(초당 피해). 없으면(null) 0. 일반형/공중형은 타워를 때리지 않고(길이 막히면 한 방에 부순다) 보스 레인에도 못 가서 값이 없다.
## 슬라임 새끼처럼 타워를 갉는 몬스터와 공격형/지원형만 값이 있다.
static func dps(kind_id: String) -> float:
	var v = DATA[kind_id].get("dps")
	return 0.0 if v == null else float(v)


static func max_hp(kind_id: String) -> float:
	return float(DATA[kind_id].hp)


## 처치 골드 (적어 두지 않았으면 비용의 1/10)
static func reward(kind_id: String) -> int:
	var d: Dictionary = DATA[kind_id]
	return int(d.get("reward", maxi(1, roundi(float(d.cost) / 10.0))))


## 보스가 이 라운드에 살 수 있는 몬스터 종류 (min_level이 라운드 이하). flying_only이면 공중 종류만 (공습 웨이브).
## 뽑는 건 BossController가 보스의 수입 안에서 weight(가중치)로 한다.
static func candidates(level: int, flying_only: bool = false) -> Array[String]:
	var list: Array[String] = []
	for id in DATA:
		if _can_pick(id, level, flying_only):
			list.append(id)
	return list


static func _can_pick(id: String, level: int, flying_only: bool) -> bool:
	var d: Dictionary = DATA[id]
	return not d.get("summon_only", false) and float(d.get("weight", 0.0)) > 0.0 and level >= int(d.min_level) \
		and (not flying_only or bool(d.get("flying", false)))


## 몬스터를 골랐을 때 하단에 보여줄 설명: 이름 / 한 줄 설명(이동 속도·공중 여부 포함) / 수치 한 줄
static func tooltip(kind_id: String) -> String:
	var d: Dictionary = DATA[kind_id]
	var cat: Dictionary = CATEGORY_DATA[d.category]
	var desc: String = d.desc
	if d.get("flying", false) and not desc.contains("공중") and not desc.contains("비행"):
		desc += " 공중으로 온다."
	if not (desc.contains("빠") or desc.contains("느리") or desc.contains("도착")):
		desc += " 이동 %s." % ("빠름" if d.speed >= 4.0 else ("느림" if d.speed <= 2.0 else "보통"))
	var atk := "공격 %s" % _num(dps(kind_id)) if dps(kind_id) > 0.0 else "공격 없음"
	if d.category in ["normal", "air"] and not d.get("gnaws", false):
		atk = "타워 공격 안 함 (길이 막히면 한 방에 파괴)"  # dps는 보스 레인에서만 쓰이고, 웨이브로 올 땐 타워를 때리지 않는다
	var text := "%s (%s%s)\n%s\n비용 %d · 수입 +%d · %s · 체력 %s" % [
		d.name, cat.name, " · " + d.family if d.has("family") else "", desc, d.cost, d.income, atk, _num(max_hp(kind_id))]
	if not can_send_in_pve(kind_id):
		text += "\n협력에서는 만들 수 없음"
	return text


static func _num(v: float) -> String:
	return "%d" % roundi(v) if absf(v - roundf(v)) < 0.05 else "%.1f" % v
