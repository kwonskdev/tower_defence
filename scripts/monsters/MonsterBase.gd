extends CharacterBody2D
class_name MonsterBase

enum MonsterType {
	NORMAL,
	AGGRESSIVE,
	SUPPORT,
	FLYING
}

@export var monster_type: MonsterType = MonsterType.NORMAL
@export var monster_name: String = ""

var base_stats = {
	"health": 100,
	"max_health": 100,
	"speed": 50,
	"damage": 10,
	"reward": 10,
	"income_increase": 1
}

var current_stats = {}
var current_path: Array[Vector2i] = []
var current_path_index: int = 0
var target_position: Vector2
var path_progress: float = 0.0

var grid_system: GridSystem
var vision_range: int = 3
var is_alive: bool = true
var reached_goal: bool = false

var special_abilities: Array[String] = []
var buffs: Array[Dictionary] = []
var debuffs: Array[Dictionary] = []

signal health_changed(new_health: int, max_health: int)
signal monster_died(monster: MonsterBase)
signal goal_reached(monster: MonsterBase)
signal tower_attacked(tower_position: Vector2i, damage: int)
signal buff_applied(target: MonsterBase, buff_type: String)

func _ready():
	current_stats = base_stats.duplicate()
	_initialize_monster_type()
	_setup_collision()
	_setup_visual()

	Logger.monster_ai_log("Monster initialized: %s (Type: %s)" % [monster_name, _type_to_string(monster_type)])

func _setup_visual():
	var sprite = get_node("Sprite2D") as Sprite2D
	if sprite:
		var texture = ImageTexture.new()
		var image = Image.create(40, 40, false, Image.FORMAT_RGB8)

		var monster_color = _get_monster_display_color()
		image.fill(monster_color)

		texture.set_image(image)
		sprite.texture = texture

		Logger.monster_ai_log("Monster visual setup: %s (%s)" % [monster_name, _type_to_string(monster_type)])

func _get_monster_display_color() -> Color:
	match monster_type:
		MonsterType.NORMAL:
			return Color.WHITE
		MonsterType.AGGRESSIVE:
			return Color.DARK_RED
		MonsterType.SUPPORT:
			return Color.CYAN
		MonsterType.FLYING:
			return Color.LIGHT_BLUE
		_:
			return Color.GRAY

func _initialize_monster_type():
	match monster_type:
		MonsterType.NORMAL:
			_setup_normal_monster()
		MonsterType.AGGRESSIVE:
			_setup_aggressive_monster()
		MonsterType.SUPPORT:
			_setup_support_monster()
		MonsterType.FLYING:
			_setup_flying_monster()

func _setup_normal_monster():
	current_stats.health = 100
	current_stats.max_health = 100
	current_stats.speed = 50
	current_stats.reward = 10
	current_stats.income_increase = 2

func _setup_aggressive_monster():
	current_stats.health = 120
	current_stats.max_health = 120
	current_stats.speed = 40
	current_stats.damage = 25
	current_stats.reward = 15
	current_stats.income_increase = 1
	special_abilities.append("tower_attack")

func _setup_support_monster():
	current_stats.health = 80
	current_stats.max_health = 80
	current_stats.speed = 60
	current_stats.damage = 0
	current_stats.reward = 20
	current_stats.income_increase = 3
	special_abilities.append("buff_allies")
	special_abilities.append("debuff_towers")

func _setup_flying_monster():
	current_stats.health = 70
	current_stats.max_health = 70
	current_stats.speed = 80
	current_stats.reward = 25
	current_stats.income_increase = 2
	special_abilities.append("ignore_maze")

func _setup_collision():
	var collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = 20
	collision_shape.shape = circle_shape
	add_child(collision_shape)

	var area = Area2D.new()
	var area_collision = CollisionShape2D.new()
	var area_circle = CircleShape2D.new()
	area_circle.radius = 25
	area_collision.shape = area_circle
	area.add_child(area_collision)
	add_child(area)

func initialize(grid_sys: GridSystem, start_position: Vector2i, goal_position: Vector2i):
	grid_system = grid_sys
	global_position = grid_system.grid_to_world_position(start_position)

	if monster_type == MonsterType.FLYING:
		_create_direct_path(start_position, goal_position)
	else:
		_find_path_to_goal(start_position, goal_position)

	Logger.monster_ai_log("Monster initialized at %v, path length: %d" % [start_position, current_path.size()])

func _physics_process(delta):
	if not is_alive or reached_goal:
		return

	_move_along_path(delta)
	_update_special_abilities(delta)
	_apply_buffs_and_debuffs(delta)

func _move_along_path(delta):
	if current_path.is_empty() or current_path_index >= current_path.size():
		_reach_goal()
		return

	var target_grid_pos = current_path[current_path_index]
	target_position = grid_system.grid_to_world_position(target_grid_pos)

	var direction = (target_position - global_position).normalized()
	var move_speed = current_stats.speed * _get_speed_multiplier()

	velocity = direction * move_speed
	move_and_slide()

	var distance_to_target = global_position.distance_to(target_position)
	if distance_to_target < 10:
		current_path_index += 1
		path_progress = float(current_path_index) / float(current_path.size())

		if current_path_index >= current_path.size():
			_reach_goal()

func _update_special_abilities(delta):
	if "tower_attack" in special_abilities:
		_attack_nearby_towers()

	if "buff_allies" in special_abilities:
		_buff_nearby_allies()

	if "debuff_towers" in special_abilities:
		_debuff_nearby_towers()

func _attack_nearby_towers():
	var nearby_towers = _get_nearby_towers()

	for tower_pos in nearby_towers:
		var tower_data = grid_system.get_tower_at(tower_pos)
		if not tower_data.is_empty():
			var tower_node = tower_data.get("node", null)
			if tower_node and tower_node.has_method("take_damage"):
				tower_node.take_damage(current_stats.damage)
				tower_attacked.emit(tower_pos, current_stats.damage)
				Logger.monster_ai_log("Monster attacked tower at %v for %d damage" % [tower_pos, current_stats.damage])

func _buff_nearby_allies():
	var nearby_monsters = _get_nearby_monsters()

	for monster in nearby_monsters:
		if monster != self and monster.is_alive:
			var buff = {
				"type": "speed_boost",
				"value": 1.3,
				"duration": 3.0
			}
			monster.apply_buff(buff)
			buff_applied.emit(monster, "speed_boost")

func _debuff_nearby_towers():
	var nearby_towers = _get_nearby_towers()

	for tower_pos in nearby_towers:
		var tower_data = grid_system.get_tower_at(tower_pos)
		if not tower_data.is_empty():
			var tower_node = tower_data.get("node", null)
			if tower_node and tower_node.has_method("apply_debuff"):
				var debuff = {
					"type": "attack_speed_reduction",
					"value": 0.7,
					"duration": 5.0
				}
				tower_node.apply_debuff(debuff)

func _get_nearby_towers() -> Array[Vector2i]:
	var nearby_towers: Array[Vector2i] = []
	var current_grid_pos = grid_system.world_to_grid_position(global_position)

	for x in range(-2, 3):
		for y in range(-2, 3):
			var check_pos = current_grid_pos + Vector2i(x, y)
			if grid_system.get_cell_type(check_pos) == GridSystem.CellType.TOWER:
				nearby_towers.append(check_pos)

	return nearby_towers

func _get_nearby_monsters() -> Array[MonsterBase]:
	var nearby_monsters: Array[MonsterBase] = []
	var monsters_in_area = get_tree().get_nodes_in_group("monsters")

	for monster in monsters_in_area:
		if monster is MonsterBase and monster.global_position.distance_to(global_position) < 100:
			nearby_monsters.append(monster)

	return nearby_monsters

func _get_speed_multiplier() -> float:
	var multiplier = 1.0

	for buff in buffs:
		if buff.type == "speed_boost":
			multiplier *= buff.value

	for debuff in debuffs:
		if debuff.type == "slow":
			multiplier *= debuff.value

	return multiplier

func take_damage(damage: int):
	if not is_alive:
		return

	current_stats.health -= damage
	current_stats.health = max(0, current_stats.health)

	health_changed.emit(current_stats.health, current_stats.max_health)
	Logger.monster_ai_log("Monster took %d damage, health: %d/%d" % [damage, current_stats.health, current_stats.max_health])

	if current_stats.health <= 0:
		_die()

func apply_buff(buff: Dictionary):
	buffs.append(buff)
	Logger.monster_ai_log("Buff applied: %s (value: %s, duration: %s)" % [buff.type, buff.value, buff.duration])

func apply_debuff(debuff: Dictionary):
	debuffs.append(debuff)
	Logger.monster_ai_log("Debuff applied: %s (value: %s, duration: %s)" % [debuff.type, debuff.value, debuff.duration])

func _apply_buffs_and_debuffs(delta):
	for i in range(buffs.size() - 1, -1, -1):
		buffs[i].duration -= delta
		if buffs[i].duration <= 0:
			buffs.remove_at(i)

	for i in range(debuffs.size() - 1, -1, -1):
		debuffs[i].duration -= delta
		if debuffs[i].duration <= 0:
			debuffs.remove_at(i)

func _die():
	if not is_alive:
		return

	is_alive = false
	monster_died.emit(self)
	Logger.monster_ai_log("Monster died: %s" % monster_name)

	add_to_group("dead_monsters")
	queue_free()

func _reach_goal():
	if reached_goal:
		return

	reached_goal = true
	goal_reached.emit(self)
	Logger.game_state_log("Monster reached goal: %s" % monster_name)

	queue_free()

func _find_path_to_goal(start: Vector2i, goal: Vector2i):
	current_path = _calculate_path_with_limited_vision(start, goal)

func _create_direct_path(start: Vector2i, goal: Vector2i):
	current_path = [start, goal]

func _calculate_path_with_limited_vision(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var path: Array[Vector2i] = [start]
	var current_pos = start

	while current_pos != goal:
		var visible_area = _get_visible_positions(current_pos)
		var next_pos = _choose_next_position(current_pos, goal, visible_area)

		if next_pos == current_pos:
			var full_path = _calculate_full_path(current_pos, goal)
			if full_path.size() > 1:
				next_pos = full_path[1]
			else:
				break

		path.append(next_pos)
		current_pos = next_pos

		if path.size() > 1000:
			Logger.error("Path calculation exceeded maximum iterations", "MONSTER_AI")
			break

	return path

func _get_visible_positions(pos: Vector2i) -> Array[Vector2i]:
	var visible: Array[Vector2i] = []

	for x in range(-vision_range, vision_range + 1):
		for y in range(-vision_range, vision_range + 1):
			var check_pos = pos + Vector2i(x, y)
			if grid_system.is_valid_position(check_pos):
				visible.append(check_pos)

	return visible

func _choose_next_position(current: Vector2i, goal: Vector2i, visible_area: Array[Vector2i]) -> Vector2i:
	var best_pos = current
	var best_distance = current.distance_to(goal)

	var neighbors = grid_system.get_walkable_neighbors(current)

	for neighbor in neighbors:
		if neighbor in visible_area:
			var cell_type = grid_system.get_cell_type(neighbor)
			if cell_type != GridSystem.CellType.TOWER:
				var distance = neighbor.distance_to(goal)
				if distance < best_distance:
					best_distance = distance
					best_pos = neighbor

	return best_pos

func _calculate_full_path(start: Vector2i, goal: Vector2i) -> Array[Vector2i]:
	var astar = AStar2D.new()
	var point_map: Dictionary = {}
	var id_counter = 0

	var grid_size = grid_system.get_grid_size()

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var pos = Vector2i(x, y)
			var cell_type = grid_system.get_cell_type(pos)

			if cell_type != GridSystem.CellType.TOWER and cell_type != GridSystem.CellType.BLOCKED:
				astar.add_point(id_counter, Vector2(pos.x, pos.y))
				point_map[pos] = id_counter
				id_counter += 1

	for pos in point_map.keys():
		var neighbors = grid_system.get_walkable_neighbors(pos)
		for neighbor in neighbors:
			if point_map.has(neighbor):
				astar.connect_points(point_map[pos], point_map[neighbor])

	if point_map.has(start) and point_map.has(goal):
		var vector_path = astar.get_point_path(point_map[start], point_map[goal])
		var grid_path: Array[Vector2i] = []

		for vector_pos in vector_path:
			grid_path.append(Vector2i(int(vector_pos.x), int(vector_pos.y)))

		return grid_path

	return [start]

func get_monster_type() -> String:
	match monster_type:
		MonsterType.NORMAL:
			return "normal"
		MonsterType.AGGRESSIVE:
			return "aggressive"
		MonsterType.SUPPORT:
			return "support"
		MonsterType.FLYING:
			return "flying"
		_:
			return "unknown"

func get_path_progress() -> float:
	return path_progress

func get_current_stats() -> Dictionary:
	return current_stats.duplicate()

func is_valid() -> bool:
	return is_alive and is_inside_tree()

func _type_to_string(type: MonsterType) -> String:
	match type:
		MonsterType.NORMAL:
			return "NORMAL"
		MonsterType.AGGRESSIVE:
			return "AGGRESSIVE"
		MonsterType.SUPPORT:
			return "SUPPORT"
		MonsterType.FLYING:
			return "FLYING"
		_:
			return "UNKNOWN"