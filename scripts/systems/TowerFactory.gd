extends RefCounted
class_name TowerFactory

static var tower_definitions = {
	"long_range_high_damage": {
		"name": "Sniper Tower",
		"attributes": [TowerBase.TowerAttribute.LONG_RANGE, TowerBase.TowerAttribute.HIGH_DAMAGE],
		"base_stats": {"damage": 50, "range": 200, "attack_speed": 0.5, "cost": 100},
		"description": "멀리서 강력한 한 방"
	},
	"long_range_splash": {
		"name": "Artillery Tower",
		"attributes": [TowerBase.TowerAttribute.LONG_RANGE, TowerBase.TowerAttribute.SPLASH],
		"base_stats": {"damage": 30, "range": 180, "attack_speed": 0.8, "cost": 120},
		"description": "멀리서 스플래시 공격"
	},
	"long_range_trap": {
		"name": "Rapid Sniper",
		"attributes": [TowerBase.TowerAttribute.LONG_RANGE, TowerBase.TowerAttribute.TRAP],
		"base_stats": {"damage": 20, "range": 150, "attack_speed": 2.0, "cost": 80},
		"description": "사거리 길고 빠른 공격속도"
	},
	"long_range_anti_air": {
		"name": "AA Sniper",
		"attributes": [TowerBase.TowerAttribute.LONG_RANGE, TowerBase.TowerAttribute.ANTI_AIR],
		"base_stats": {"damage": 40, "range": 200, "attack_speed": 0.8, "cost": 110},
		"description": "멀리 있는 공중 몬스터 저격"
	},
	"high_damage_splash": {
		"name": "Bomb Tower",
		"attributes": [TowerBase.TowerAttribute.HIGH_DAMAGE, TowerBase.TowerAttribute.SPLASH],
		"base_stats": {"damage": 60, "range": 100, "attack_speed": 0.6, "cost": 140},
		"description": "강력한 스플래시 데미지"
	},
	"high_damage_trap": {
		"name": "Gatling Gun",
		"attributes": [TowerBase.TowerAttribute.HIGH_DAMAGE, TowerBase.TowerAttribute.TRAP],
		"base_stats": {"damage": 40, "range": 80, "attack_speed": 3.0, "cost": 90},
		"description": "강력하고 빠른 공격"
	},
	"high_damage_anti_air": {
		"name": "AA Cannon",
		"attributes": [TowerBase.TowerAttribute.HIGH_DAMAGE, TowerBase.TowerAttribute.ANTI_AIR],
		"base_stats": {"damage": 70, "range": 120, "attack_speed": 0.7, "cost": 130},
		"description": "공중 몬스터 한 방에 처치"
	},
	"splash_trap": {
		"name": "Minigun Tower",
		"attributes": [TowerBase.TowerAttribute.SPLASH, TowerBase.TowerAttribute.TRAP],
		"base_stats": {"damage": 25, "range": 90, "attack_speed": 2.5, "cost": 100},
		"description": "빠른 속도로 범위 공격"
	},
	"splash_anti_air": {
		"name": "Flak Tower",
		"attributes": [TowerBase.TowerAttribute.SPLASH, TowerBase.TowerAttribute.ANTI_AIR],
		"base_stats": {"damage": 35, "range": 110, "attack_speed": 1.0, "cost": 115},
		"description": "공중 몬스터들을 범위로 공격"
	},
	"trap_anti_air": {
		"name": "AA Gatling",
		"attributes": [TowerBase.TowerAttribute.TRAP, TowerBase.TowerAttribute.ANTI_AIR],
		"base_stats": {"damage": 20, "range": 100, "attack_speed": 4.0, "cost": 85},
		"description": "공중 몬스터를 빠르게 공격"
	},
	"buff_tower": {
		"name": "Support Tower",
		"attributes": [TowerBase.TowerAttribute.BUFF],
		"base_stats": {"damage": 0, "range": 120, "attack_speed": 0, "cost": 60},
		"description": "주변 타워 강화"
	},
	"debuff_tower": {
		"name": "Slow Tower",
		"attributes": [TowerBase.TowerAttribute.DEBUFF],
		"base_stats": {"damage": 0, "range": 100, "attack_speed": 0, "cost": 50},
		"description": "주변 적 약화"
	}
}

static func create_tower(tower_type: String) -> TowerBase:
	if not tower_definitions.has(tower_type):
		Logger.error("Unknown tower type: %s" % tower_type, "TOWER_FACTORY")
		return null

	var definition = tower_definitions[tower_type]
	var tower = preload("res://scenes/towers/Tower.tscn").instantiate() as TowerBase

	if tower == null:
		Logger.error("Failed to instantiate tower scene", "TOWER_FACTORY")
		return null

	tower.tower_type = tower_type
	tower.attributes = definition.attributes.duplicate()
	tower.base_stats = definition.base_stats.duplicate()

	Logger.tower_log("Created tower: %s (%s)" % [definition.name, tower_type])
	return tower

static func get_tower_definition(tower_type: String) -> Dictionary:
	return tower_definitions.get(tower_type, {})

static func get_all_tower_types() -> Array[String]:
	var types: Array[String] = []
	for key in tower_definitions.keys():
		types.append(key)
	return types

static func get_tower_cost(tower_type: String) -> int:
	var definition = get_tower_definition(tower_type)
	if definition.is_empty():
		return 0
	return definition.get("base_stats", {}).get("cost", 0)

static func get_tower_name(tower_type: String) -> String:
	var definition = get_tower_definition(tower_type)
	return definition.get("name", tower_type)

static func get_tower_description(tower_type: String) -> String:
	var definition = get_tower_definition(tower_type)
	return definition.get("description", "No description available")

static func get_towers_by_category() -> Dictionary:
	var categories = {
		"basic_attack": [],
		"support": []
	}

	for tower_type in tower_definitions.keys():
		var definition = tower_definitions[tower_type]
		var attributes = definition.attributes

		if TowerBase.TowerAttribute.BUFF in attributes or TowerBase.TowerAttribute.DEBUFF in attributes:
			categories.support.append(tower_type)
		else:
			categories.basic_attack.append(tower_type)

	return categories

static func get_recommended_towers_for_situation(situation: String) -> Array[String]:
	var recommendations: Array[String] = []

	match situation.to_lower():
		"early_game":
			recommendations = ["long_range_trap", "high_damage_trap", "splash_trap"]
		"heavy_armor":
			recommendations = ["high_damage_splash", "long_range_high_damage", "high_damage_anti_air"]
		"many_weak":
			recommendations = ["splash_trap", "long_range_splash", "splash_anti_air"]
		"air_units":
			recommendations = ["long_range_anti_air", "high_damage_anti_air", "trap_anti_air", "splash_anti_air"]
		"support_needed":
			recommendations = ["buff_tower", "debuff_tower"]
		_:
			recommendations = ["long_range_high_damage", "high_damage_splash", "buff_tower"]

	return recommendations