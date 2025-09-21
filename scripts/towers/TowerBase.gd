extends Node2D
class_name TowerBase

enum TowerAttribute {
	LONG_RANGE,
	HIGH_DAMAGE,
	SPLASH,
	TRAP,
	ANTI_AIR,
	BUFF,
	DEBUFF
}

enum TowerColor {
	RED,
	ORANGE,
	YELLOW,
	GREEN,
	BLUE,
	INDIGO,
	VIOLET
}

@export var tower_type: String = ""
@export var attributes: Array[TowerAttribute] = []
@export var color: TowerColor = TowerColor.RED

var base_stats = {
	"damage": 10,
	"range": 100,
	"attack_speed": 1.0,
	"cost": 50
}

var current_stats = {}
var level: int = 1
var upgrade_count: int = 0
var can_evolve: bool = false

var targets_in_range: Array[Node2D] = []
var current_target: Node2D = null
var attack_timer: Timer
var range_area: Area2D
var visual_range_indicator: Node2D

signal target_acquired(target: Node2D)
signal target_lost(target: Node2D)
signal attack_performed(target: Node2D, damage: float)
signal tower_upgraded(new_level: int)
signal tower_evolved()

func _ready():
	_initialize_tower()
	_setup_components()
	_apply_attribute_bonuses()

func _initialize_tower():
	current_stats = base_stats.duplicate()

	attack_timer = Timer.new()
	attack_timer.timeout.connect(_perform_attack)
	add_child(attack_timer)

	range_area = Area2D.new()
	var collision_shape = CollisionShape2D.new()
	var circle_shape = CircleShape2D.new()
	circle_shape.radius = current_stats.range
	collision_shape.shape = circle_shape
	range_area.add_child(collision_shape)
	range_area.area_entered.connect(_on_target_entered_range)
	range_area.area_exited.connect(_on_target_exited_range)
	add_child(range_area)

	Logger.tower_log("Tower initialized: %s with attributes %s" % [tower_type, _attributes_to_string()])

func _setup_components():
	color = TowerColor.values()[randi() % TowerColor.size()]
	Logger.color_system_log("Tower assigned color: %s" % _color_to_string(color))

func _apply_attribute_bonuses():
	for attribute in attributes:
		match attribute:
			TowerAttribute.LONG_RANGE:
				current_stats.range *= 1.5
				Logger.tower_log("Long Range bonus applied: range = %d" % current_stats.range)

			TowerAttribute.HIGH_DAMAGE:
				current_stats.damage *= 2.0
				Logger.tower_log("High Damage bonus applied: damage = %d" % current_stats.damage)

			TowerAttribute.SPLASH:
				current_stats.damage *= 0.8
				Logger.tower_log("Splash damage penalty applied: damage = %d" % current_stats.damage)

			TowerAttribute.TRAP:
				current_stats.attack_speed *= 2.0
				Logger.tower_log("Trap bonus applied: attack_speed = %.1f" % current_stats.attack_speed)

			TowerAttribute.ANTI_AIR:
				current_stats.damage *= 1.2
				Logger.tower_log("Anti-Air bonus applied: damage = %d" % current_stats.damage)

	_update_range_visual()

func _update_range_visual():
	if range_area:
		var collision_shape = range_area.get_child(0) as CollisionShape2D
		if collision_shape and collision_shape.shape is CircleShape2D:
			(collision_shape.shape as CircleShape2D).radius = current_stats.range

func _on_target_entered_range(area: Area2D):
	var target = area.get_parent()
	if _is_valid_target(target):
		targets_in_range.append(target)
		Logger.tower_log("Target entered range: %s" % target.name, Logger.LogLevel.DEBUG)

		if current_target == null:
			_acquire_target()

func _on_target_exited_range(area: Area2D):
	var target = area.get_parent()
	if target in targets_in_range:
		targets_in_range.erase(target)
		Logger.tower_log("Target exited range: %s" % target.name, Logger.LogLevel.DEBUG)

		if current_target == target:
			current_target = null
			target_lost.emit(target)
			_acquire_target()

func _is_valid_target(target: Node2D) -> bool:
	if not target.has_method("get_monster_type"):
		return false

	var monster_type = target.get_monster_type()

	if TowerAttribute.ANTI_AIR in attributes:
		return monster_type == "flying"
	else:
		return monster_type != "flying"

func _acquire_target():
	if targets_in_range.is_empty():
		return

	current_target = _select_best_target()
	if current_target:
		target_acquired.emit(current_target)
		_start_attacking()

func _select_best_target() -> Node2D:
	if targets_in_range.is_empty():
		return null

	var best_target = targets_in_range[0]
	var best_progress = 0.0

	for target in targets_in_range:
		if target.has_method("get_path_progress"):
			var progress = target.get_path_progress()
			if progress > best_progress:
				best_progress = progress
				best_target = target

	return best_target

func _start_attacking():
	if attack_timer and current_target:
		attack_timer.wait_time = 1.0 / current_stats.attack_speed
		attack_timer.start()

func _perform_attack():
	if not current_target or not current_target.is_valid():
		_acquire_target()
		return

	var damage = current_stats.damage

	if TowerAttribute.SPLASH in attributes:
		_perform_splash_attack(damage)
	else:
		_perform_single_attack(current_target, damage)

func _perform_single_attack(target: Node2D, damage: float):
	if target.has_method("take_damage"):
		target.take_damage(damage)
		attack_performed.emit(target, damage)
		Logger.tower_log("Single attack: %d damage to %s" % [damage, target.name], Logger.LogLevel.DEBUG)

func _perform_splash_attack(damage: float):
	var splash_radius = 80.0
	var splash_targets: Array[Node2D] = []

	for target in targets_in_range:
		var distance = global_position.distance_to(target.global_position)
		if distance <= splash_radius:
			splash_targets.append(target)

	for target in splash_targets:
		if target.has_method("take_damage"):
			target.take_damage(damage)
			attack_performed.emit(target, damage)

	Logger.tower_log("Splash attack: %d damage to %d targets" % [damage, splash_targets.size()], Logger.LogLevel.DEBUG)

func upgrade_tower() -> bool:
	var upgrade_cost = _calculate_upgrade_cost()

	upgrade_count += 1
	current_stats.damage = int(current_stats.damage * 1.2)
	current_stats.range = int(current_stats.range * 1.1)
	current_stats.attack_speed *= 1.1

	_update_range_visual()
	tower_upgraded.emit(level)

	Logger.tower_log("Tower upgraded to level %d: damage=%d, range=%d, attack_speed=%.1f" %
		[level, current_stats.damage, current_stats.range, current_stats.attack_speed])

	if upgrade_count >= 5:
		can_evolve = true
		Logger.tower_log("Tower can now evolve!")

	return true

func evolve_tower() -> bool:
	if not can_evolve:
		return false

	level += 1
	upgrade_count = 0
	can_evolve = false

	current_stats.damage = int(current_stats.damage * 2.0)
	current_stats.range = int(current_stats.range * 1.5)
	current_stats.attack_speed *= 1.5

	_update_range_visual()
	tower_evolved.emit()

	Logger.tower_log("Tower evolved to level %d: damage=%d, range=%d, attack_speed=%.1f" %
		[level, current_stats.damage, current_stats.range, current_stats.attack_speed])

	return true

func _calculate_upgrade_cost() -> int:
	return base_stats.cost * (upgrade_count + 1)

func _calculate_evolution_cost() -> int:
	return base_stats.cost * 10

func apply_debuff(debuff: Dictionary):
	Logger.tower_log("Debuff applied to tower: %s" % debuff.get("type", "unknown"))

func change_color(new_color: TowerColor):
	color = new_color
	Logger.color_system_log("Tower color changed to: %s" % _color_to_string(color))

func get_tower_info() -> Dictionary:
	return {
		"type": tower_type,
		"attributes": attributes,
		"color": color,
		"level": level,
		"upgrade_count": upgrade_count,
		"can_evolve": can_evolve,
		"stats": current_stats.duplicate(),
		"base_stats": base_stats.duplicate()
	}

func get_sell_value() -> int:
	var total_cost = base_stats.cost
	for i in range(upgrade_count):
		total_cost += _calculate_upgrade_cost()
	return int(total_cost * 0.5)

func _attributes_to_string() -> String:
	var attr_names: Array[String] = []
	for attr in attributes:
		match attr:
			TowerAttribute.LONG_RANGE:
				attr_names.append("LongRange")
			TowerAttribute.HIGH_DAMAGE:
				attr_names.append("HighDamage")
			TowerAttribute.SPLASH:
				attr_names.append("Splash")
			TowerAttribute.TRAP:
				attr_names.append("Trap")
			TowerAttribute.ANTI_AIR:
				attr_names.append("AntiAir")
			TowerAttribute.BUFF:
				attr_names.append("Buff")
			TowerAttribute.DEBUFF:
				attr_names.append("Debuff")
	return "[" + ", ".join(attr_names) + "]"

func _color_to_string(tower_color: TowerColor) -> String:
	match tower_color:
		TowerColor.RED:
			return "Red"
		TowerColor.ORANGE:
			return "Orange"
		TowerColor.YELLOW:
			return "Yellow"
		TowerColor.GREEN:
			return "Green"
		TowerColor.BLUE:
			return "Blue"
		TowerColor.INDIGO:
			return "Indigo"
		TowerColor.VIOLET:
			return "Violet"
		_:
			return "Unknown"