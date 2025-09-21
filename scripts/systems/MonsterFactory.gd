extends RefCounted
class_name MonsterFactory

static var monster_definitions = {
	"basic_grunt": {
		"name": "기본 보병",
		"type": MonsterBase.MonsterType.NORMAL,
		"stats": {"health": 80, "speed": 45, "reward": 8, "income_increase": 1, "cost": 10},
		"description": "기본적인 지상 유닛"
	},
	"heavy_grunt": {
		"name": "중장갑 보병",
		"type": MonsterBase.MonsterType.NORMAL,
		"stats": {"health": 150, "speed": 30, "reward": 15, "income_increase": 2, "cost": 20},
		"description": "느리지만 체력이 높은 유닛"
	},
	"fast_scout": {
		"name": "정찰병",
		"type": MonsterBase.MonsterType.NORMAL,
		"stats": {"health": 50, "speed": 80, "reward": 12, "income_increase": 1, "cost": 15},
		"description": "빠르지만 약한 유닛"
	},

	"berserker": {
		"name": "광전사",
		"type": MonsterBase.MonsterType.AGGRESSIVE,
		"stats": {"health": 100, "speed": 40, "damage": 20, "reward": 18, "income_increase": 1, "cost": 25},
		"description": "타워를 공격하는 근접 유닛"
	},
	"demolisher": {
		"name": "파괴병",
		"type": MonsterBase.MonsterType.AGGRESSIVE,
		"stats": {"health": 200, "speed": 25, "damage": 40, "reward": 30, "income_increase": 1, "cost": 40},
		"description": "강력한 타워 파괴 능력"
	},
	"saboteur": {
		"name": "사보타주",
		"type": MonsterBase.MonsterType.AGGRESSIVE,
		"stats": {"health": 75, "speed": 60, "damage": 15, "reward": 20, "income_increase": 1, "cost": 30},
		"description": "빠르게 이동하며 타워 공격"
	},

	"medic": {
		"name": "의무병",
		"type": MonsterBase.MonsterType.SUPPORT,
		"stats": {"health": 60, "speed": 50, "reward": 25, "income_increase": 3, "cost": 35},
		"description": "주변 유닛의 체력 회복"
	},
	"commander": {
		"name": "지휘관",
		"type": MonsterBase.MonsterType.SUPPORT,
		"stats": {"health": 120, "speed": 35, "reward": 40, "income_increase": 4, "cost": 50},
		"description": "주변 유닛 속도 증가"
	},
	"technician": {
		"name": "기술자",
		"type": MonsterBase.MonsterType.SUPPORT,
		"stats": {"health": 80, "speed": 45, "reward": 30, "income_increase": 3, "cost": 40},
		"description": "타워 공격속도 감소"
	},

	"drone": {
		"name": "드론",
		"type": MonsterBase.MonsterType.FLYING,
		"stats": {"health": 40, "speed": 90, "reward": 20, "income_increase": 2, "cost": 25},
		"description": "빠른 공중 유닛"
	},
	"fighter": {
		"name": "전투기",
		"type": MonsterBase.MonsterType.FLYING,
		"stats": {"health": 80, "speed": 70, "reward": 35, "income_increase": 2, "cost": 40},
		"description": "중간 속도의 공중 유닛"
	},
	"bomber": {
		"name": "폭격기",
		"type": MonsterBase.MonsterType.FLYING,
		"stats": {"health": 150, "speed": 50, "reward": 50, "income_increase": 3, "cost": 60},
		"description": "느리지만 강력한 공중 유닛"
	}
}

static func create_monster(monster_type: String) -> MonsterBase:
	if not monster_definitions.has(monster_type):
		Logger.error("Unknown monster type: %s" % monster_type, "MONSTER_FACTORY")
		return null

	var definition = monster_definitions[monster_type]
	var monster = preload("res://scenes/monsters/Monster.tscn").instantiate() as MonsterBase

	if monster == null:
		Logger.error("Failed to instantiate monster scene", "MONSTER_FACTORY")
		return null

	monster.monster_name = definition.name
	monster.monster_type = definition.type
	monster.base_stats = definition.stats.duplicate()

	var custom_stats = definition.stats.duplicate()
	monster.base_stats.merge(custom_stats, true)

	Logger.monster_ai_log("Created monster: %s (%s)" % [definition.name, monster_type])
	return monster

static func get_monster_definition(monster_type: String) -> Dictionary:
	return monster_definitions.get(monster_type, {})

static func get_all_monster_types() -> Array[String]:
	var types: Array[String] = []
	for key in monster_definitions.keys():
		types.append(key)
	return types

static func get_monster_cost(monster_type: String) -> int:
	var definition = get_monster_definition(monster_type)
	if definition.is_empty():
		return 0
	return definition.get("stats", {}).get("cost", 0)

static func get_monster_name(monster_type: String) -> String:
	var definition = get_monster_definition(monster_type)
	return definition.get("name", monster_type)

static func get_monster_description(monster_type: String) -> String:
	var definition = get_monster_definition(monster_type)
	return definition.get("description", "No description available")

static func get_monsters_by_category() -> Dictionary:
	var categories = {
		"normal": [],
		"aggressive": [],
		"support": [],
		"flying": []
	}

	for monster_type in monster_definitions.keys():
		var definition = monster_definitions[monster_type]
		var type = definition.type

		match type:
			MonsterBase.MonsterType.NORMAL:
				categories.normal.append(monster_type)
			MonsterBase.MonsterType.AGGRESSIVE:
				categories.aggressive.append(monster_type)
			MonsterBase.MonsterType.SUPPORT:
				categories.support.append(monster_type)
			MonsterBase.MonsterType.FLYING:
				categories.flying.append(monster_type)

	return categories

static func get_monsters_for_coop() -> Array[String]:
	var coop_monsters: Array[String] = []

	for monster_type in monster_definitions.keys():
		var definition = monster_definitions[monster_type]
		if definition.type == MonsterBase.MonsterType.AGGRESSIVE:
			coop_monsters.append(monster_type)

	return coop_monsters

static func get_monsters_for_pvp() -> Array[String]:
	var pvp_monsters: Array[String] = []

	for monster_type in monster_definitions.keys():
		pvp_monsters.append(monster_type)

	return pvp_monsters

static func get_recommended_monsters_for_situation(situation: String) -> Array[String]:
	var recommendations: Array[String] = []

	match situation.to_lower():
		"early_rush":
			recommendations = ["fast_scout", "basic_grunt", "drone"]
		"tank_push":
			recommendations = ["heavy_grunt", "demolisher", "bomber"]
		"swarm_attack":
			recommendations = ["basic_grunt", "fast_scout", "drone"]
		"support_push":
			recommendations = ["commander", "medic", "technician"]
		"air_strike":
			recommendations = ["drone", "fighter", "bomber"]
		"tower_destroy":
			recommendations = ["berserker", "demolisher", "saboteur"]
		_:
			recommendations = ["basic_grunt", "berserker", "medic", "drone"]

	return recommendations

static func calculate_wave_cost(monster_types: Array[String], quantities: Array[int]) -> int:
	var total_cost = 0

	for i in range(min(monster_types.size(), quantities.size())):
		var monster_type = monster_types[i]
		var quantity = quantities[i]
		var unit_cost = get_monster_cost(monster_type)
		total_cost += unit_cost * quantity

	return total_cost

static func get_monster_stats_preview(monster_type: String) -> Dictionary:
	var definition = get_monster_definition(monster_type)
	if definition.is_empty():
		return {}

	var preview = {
		"name": definition.name,
		"type": _monster_type_to_string(definition.type),
		"health": definition.stats.get("health", 0),
		"speed": definition.stats.get("speed", 0),
		"damage": definition.stats.get("damage", 0),
		"reward": definition.stats.get("reward", 0),
		"cost": definition.stats.get("cost", 0),
		"income_increase": definition.stats.get("income_increase", 0),
		"description": definition.description
	}

	return preview

static func _monster_type_to_string(type: MonsterBase.MonsterType) -> String:
	match type:
		MonsterBase.MonsterType.NORMAL:
			return "일반형"
		MonsterBase.MonsterType.AGGRESSIVE:
			return "공격형"
		MonsterBase.MonsterType.SUPPORT:
			return "지원형"
		MonsterBase.MonsterType.FLYING:
			return "공중형"
		_:
			return "알 수 없음"