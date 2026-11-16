extends RefCounted
class_name WaveTypes
## 보스가 내 레인으로 보내는 몬스터 종류. 종류마다 이기는 타워가 다르도록(상성) 만들었다.
##
## 상성 요약
## - 무리(swarm/flock): 마릿수가 많고 약하다 -> 범위 타워. 단일 타워는 쌓이는 속도를 못 따라간다.
## - 갑옷(armored/tank/juggernaut): armor 만큼 한 발 피해가 깎인다 -> 한 발이 센 타워, 방어구 파괴(장거리 보스형), 독(관통형). 약한 타격은 거의 안 먹힌다.
## - 재생(regen): 초당 체력을 회복한다 -> 한곳에 화력을 집중. 흩어진 타워로는 회복을 못 이긴다.
## - 질주(runner): 빨라서 사거리 안에 머무는 시간이 짧다 -> 장거리.
## - 공중(flyer/flock/bomber): 미로를 무시하고 직선으로 온다 -> 대공 타워만 공격 가능.
##
## hp: 기준 체력 배율 / armor: 한 발 피해 감소(평면) / regen: 초당 최대체력 회복 비율
## count: 한 번에 보내는 마릿수 / min_level: 이 보스 라운드부터 등장 / weight: 등장 가중치

const TYPES := {
	"grunt": {"name": "일반", "hp": 1.0, "speed": 3.0, "life": 1, "reward": 2, "size": 1.0, "shape": "horn",
		"color": Color(0.85, 0.2, 0.2), "weight": 5.0, "count": 1, "min_level": 1, "armor": 0.0, "regen": 0.0, "flying": false,
		"desc": "평범한 몬스터."},
	"runner": {"name": "질주", "hp": 0.5, "speed": 5.5, "life": 1, "reward": 2, "size": 0.85, "shape": "runner",
		"color": Color(0.95, 0.55, 0.15), "weight": 3.0, "count": 1, "min_level": 1, "armor": 0.0, "regen": 0.0, "flying": false,
		"desc": "빠르다. 사거리 안에 머무는 시간이 짧아서 장거리 타워가 유리."},
	"swarm": {"name": "무리", "hp": 0.3, "speed": 3.8, "life": 1, "reward": 1, "size": 0.65, "shape": "horn",
		"color": Color(0.75, 0.4, 0.6), "weight": 3.0, "count": 6, "min_level": 2, "armor": 0.0, "regen": 0.0, "flying": false,
		"desc": "작은 몬스터가 떼로 몰려온다. 범위 타워가 필요."},
	"tank": {"name": "중장갑", "hp": 3.5, "speed": 1.8, "life": 2, "reward": 6, "size": 1.4, "shape": "armor",
		"color": Color(0.4, 0.5, 0.65), "weight": 2.0, "count": 1, "min_level": 3, "armor": 0.25, "regen": 0.0, "flying": false,
		"desc": "체력이 많고 느리다. 기지에 닿으면 생명 -2."},
	"armored": {"name": "갑옷병", "hp": 1.6, "speed": 2.6, "life": 1, "reward": 4, "size": 1.0, "shape": "armor",
		"color": Color(0.75, 0.6, 0.3), "weight": 3.0, "count": 2, "min_level": 4, "armor": 0.5, "regen": 0.0, "flying": false,
		"desc": "갑옷이 단단해서 약한 타격은 거의 안 먹힌다. 한 발이 센 타워나 방어구 파괴가 필요."},
	"flyer": {"name": "비행", "hp": 0.7, "speed": 4.0, "life": 1, "reward": 3, "size": 0.9, "shape": "bird",
		"color": Color(0.5, 0.75, 0.95), "weight": 3.0, "count": 2, "min_level": 4, "armor": 0.0, "regen": 0.0, "flying": true,
		"desc": "공중으로 미로를 무시하고 직선으로 온다. 대공 타워만 공격 가능."},
	"regen": {"name": "재생체", "hp": 2.2, "speed": 2.8, "life": 1, "reward": 5, "size": 1.1, "shape": "cross",
		"color": Color(0.3, 0.8, 0.5), "weight": 3.0, "count": 1, "min_level": 5, "armor": 0.0, "regen": 0.07, "flying": false,
		"desc": "체력을 계속 회복한다. 화력이 흩어져 있으면 못 잡는다. 한곳에 집중 필요."},
	"flock": {"name": "비행 무리", "hp": 0.25, "speed": 3.5, "life": 1, "reward": 1, "size": 0.6, "shape": "bird",
		"color": Color(0.95, 0.9, 0.5), "weight": 2.0, "count": 8, "min_level": 6, "armor": 0.0, "regen": 0.0, "flying": true,
		"desc": "작은 비행 몬스터 떼. 범위 + 대공 타워가 필요."},
	"bomber": {"name": "폭격기", "hp": 3.5, "speed": 2.4, "life": 2, "reward": 8, "size": 1.4, "shape": "bird",
		"color": Color(0.7, 0.25, 0.25), "weight": 2.0, "count": 1, "min_level": 7, "armor": 0.2, "regen": 0.0, "flying": true,
		"desc": "튼튼한 대형 비행 몬스터. 대공 타워를 모아야 한다 (스킬형 포획이 유용). 기지에 닿으면 생명 -2."},
	"juggernaut": {"name": "거신병", "hp": 8.0, "speed": 1.3, "life": 3, "reward": 20, "size": 1.7, "shape": "armor",
		"color": Color(0.25, 0.28, 0.35), "weight": 1.0, "count": 1, "min_level": 8, "armor": 0.8, "regen": 0.02, "flying": false,
		"desc": "엄청나게 단단하고 느리다. 기지에 닿으면 생명 -3."},
}


## 보스 라운드에 맞는 종류를 가중치로 뽑는다. flying_only이면 공중 종류만 (공습 웨이브).
static func pick(level: int, flying_only: bool = false) -> String:
	var total := 0.0
	for id in TYPES:
		if _can_pick(id, level, flying_only):
			total += TYPES[id].weight
	var roll := randf() * total
	for id in TYPES:
		if not _can_pick(id, level, flying_only):
			continue
		roll -= TYPES[id].weight
		if roll <= 0.0:
			return id
	return "flyer" if flying_only else "grunt"


static func _can_pick(id: String, level: int, flying_only: bool) -> bool:
	var t: Dictionary = TYPES[id]
	return level >= t.min_level and (not flying_only or t.flying)
