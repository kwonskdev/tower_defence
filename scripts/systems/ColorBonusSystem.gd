extends RefCounted
class_name ColorBonusSystem

enum BonusType {
	DAMAGE_BOOST,
	SLOW_ENEMIES,
	ATTACK_SPEED_BOOST,
	RANGE_BOOST,
	GOLD_BONUS,
	SPECIAL_ABILITY
}

static var color_bonus_definitions = {
	TowerBase.TowerColor.RED: {
		"name": "Fire Power",
		"type": BonusType.DAMAGE_BOOST,
		"value": 1.5,
		"description": "공격력 50% 증가"
	},
	TowerBase.TowerColor.BLUE: {
		"name": "Frost Aura",
		"type": BonusType.SLOW_ENEMIES,
		"value": 0.7,
		"description": "주변 적 이동속도 30% 감소"
	},
	TowerBase.TowerColor.ORANGE: {
		"name": "Rapid Fire",
		"type": BonusType.ATTACK_SPEED_BOOST,
		"value": 1.3,
		"description": "공격속도 30% 증가"
	},
	TowerBase.TowerColor.YELLOW: {
		"name": "Extended Range",
		"type": BonusType.RANGE_BOOST,
		"value": 1.25,
		"description": "사거리 25% 증가"
	},
	TowerBase.TowerColor.GREEN: {
		"name": "Gold Rush",
		"type": BonusType.GOLD_BONUS,
		"value": 1.2,
		"description": "골드 획득 20% 증가"
	},
	TowerBase.TowerColor.INDIGO: {
		"name": "Piercing Shot",
		"type": BonusType.SPECIAL_ABILITY,
		"value": 2,
		"description": "공격이 최대 2명의 적을 관통"
	},
	TowerBase.TowerColor.VIOLET: {
		"name": "Critical Strike",
		"type": BonusType.SPECIAL_ABILITY,
		"value": 0.25,
		"description": "25% 확률로 2배 데미지"
	}
}

var grid_system: GridSystem
var active_bonuses: Dictionary = {}

signal bonus_activated(positions: Array[Vector2i], color: TowerBase.TowerColor)
signal bonus_deactivated(positions: Array[Vector2i], color: TowerBase.TowerColor)

func _init(grid_sys: GridSystem):
	grid_system = grid_sys
	grid_system.tower_placed.connect(_on_tower_placed)
	grid_system.tower_removed.connect(_on_tower_removed)
	Logger.color_system_log("ColorBonusSystem initialized")

func _on_tower_placed(position: Vector2i, tower_type: String):
	_check_for_bonuses()

func _on_tower_removed(position: Vector2i):
	_check_for_bonuses()

func _check_for_bonuses():
	var old_bonuses = active_bonuses.duplicate()
	active_bonuses.clear()

	_check_three_in_a_row_bonuses()
	_check_sequential_color_bonuses()

	for bonus_key in old_bonuses.keys():
		if not active_bonuses.has(bonus_key):
			var bonus_data = old_bonuses[bonus_key]
			bonus_deactivated.emit(bonus_data.positions, bonus_data.color)
			Logger.color_system_log("Bonus deactivated: %s at %s" % [bonus_data.name, bonus_data.positions])

	for bonus_key in active_bonuses.keys():
		if not old_bonuses.has(bonus_key):
			var bonus_data = active_bonuses[bonus_key]
			bonus_activated.emit(bonus_data.positions, bonus_data.color)
			Logger.color_system_log("Bonus activated: %s at %s" % [bonus_data.name, bonus_data.positions])

func _check_three_in_a_row_bonuses():
	var grid_size = grid_system.get_grid_size()

	for x in range(grid_size.x):
		for y in range(grid_size.y - 2):
			var positions = [Vector2i(x, y), Vector2i(x, y + 1), Vector2i(x, y + 2)]
			_check_positions_for_bonus(positions, "vertical")

	for y in range(grid_size.y):
		for x in range(grid_size.x - 2):
			var positions = [Vector2i(x, y), Vector2i(x + 1, y), Vector2i(x + 2, y)]
			_check_positions_for_bonus(positions, "horizontal")

func _check_sequential_color_bonuses():
	var color_sequence = [
		TowerBase.TowerColor.RED,
		TowerBase.TowerColor.ORANGE,
		TowerBase.TowerColor.YELLOW,
		TowerBase.TowerColor.GREEN,
		TowerBase.TowerColor.BLUE,
		TowerBase.TowerColor.INDIGO,
		TowerBase.TowerColor.VIOLET
	]

	var grid_size = grid_system.get_grid_size()

	for x in range(grid_size.x):
		for y in range(grid_size.y - 6):
			var positions: Array[Vector2i] = []
			for i in range(7):
				positions.append(Vector2i(x, y + i))
			_check_positions_for_sequential_bonus(positions, color_sequence)

	for y in range(grid_size.y):
		for x in range(grid_size.x - 6):
			var positions: Array[Vector2i] = []
			for i in range(7):
				positions.append(Vector2i(x + i, y))
			_check_positions_for_sequential_bonus(positions, color_sequence)

func _check_positions_for_bonus(positions: Array[Vector2i], direction: String):
	if not _all_positions_have_towers(positions):
		return

	var towers = _get_towers_at_positions(positions)
	var first_color = towers[0].color

	for tower in towers:
		if tower.color != first_color:
			return

	var bonus_key = "%s_%s_%s" % [first_color, direction, positions[0]]
	var bonus_definition = color_bonus_definitions.get(first_color, {})

	if not bonus_definition.is_empty():
		active_bonuses[bonus_key] = {
			"type": "three_in_a_row",
			"color": first_color,
			"positions": positions,
			"bonus_type": bonus_definition.type,
			"value": bonus_definition.value,
			"name": bonus_definition.name,
			"description": bonus_definition.description
		}

func _check_positions_for_sequential_bonus(positions: Array[Vector2i], color_sequence: Array):
	if not _all_positions_have_towers(positions):
		return

	var towers = _get_towers_at_positions(positions)

	for i in range(towers.size()):
		if towers[i].color != color_sequence[i]:
			return

	var bonus_key = "rainbow_%s" % positions[0]
	active_bonuses[bonus_key] = {
		"type": "rainbow",
		"color": TowerBase.TowerColor.RED,
		"positions": positions,
		"bonus_type": BonusType.SPECIAL_ABILITY,
		"value": 2.0,
		"name": "Rainbow Power",
		"description": "모든 스탯 100% 증가"
	}

func _all_positions_have_towers(positions: Array[Vector2i]) -> bool:
	for pos in positions:
		if grid_system.get_cell_type(pos) != GridSystem.CellType.TOWER:
			return false
	return true

func _get_towers_at_positions(positions: Array[Vector2i]) -> Array:
	var towers: Array = []
	for pos in positions:
		var tower_data = grid_system.get_tower_at(pos)
		if not tower_data.is_empty() and tower_data.has("node"):
			towers.append(tower_data.node)
	return towers

func get_active_bonuses() -> Dictionary:
	return active_bonuses.duplicate()

func get_bonuses_affecting_tower(tower_position: Vector2i) -> Array:
	var affecting_bonuses: Array = []

	for bonus_data in active_bonuses.values():
		if tower_position in bonus_data.positions:
			affecting_bonuses.append(bonus_data)

	return affecting_bonuses

func apply_bonuses_to_tower(tower: TowerBase, tower_position: Vector2i):
	var bonuses = get_bonuses_affecting_tower(tower_position)

	for bonus in bonuses:
		match bonus.bonus_type:
			BonusType.DAMAGE_BOOST:
				tower.current_stats.damage = int(tower.current_stats.damage * bonus.value)

			BonusType.ATTACK_SPEED_BOOST:
				tower.current_stats.attack_speed *= bonus.value

			BonusType.RANGE_BOOST:
				tower.current_stats.range = int(tower.current_stats.range * bonus.value)

		Logger.color_system_log("Applied %s bonus to tower at %v" % [bonus.name, tower_position])

func get_color_bonus_definition(color: TowerBase.TowerColor) -> Dictionary:
	return color_bonus_definitions.get(color, {})

func get_all_color_bonus_definitions() -> Dictionary:
	return color_bonus_definitions.duplicate()