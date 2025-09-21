extends Node2D
class_name GridRenderer

var grid_system: GridSystem
@export var show_grid_lines: bool = true
@export var highlight_valid_positions: bool = true

var grid_line_color = Color.GRAY
var empty_cell_color = Color.WHITE
var tower_cell_color = Color.BLUE
var spawn_cell_color = Color.GREEN
var goal_cell_color = Color.RED
var valid_placement_color = Color.YELLOW
var invalid_placement_color = Color.DARK_RED

var hovering_position: Vector2i = Vector2i(-1, -1)
var placement_mode: bool = false
var selected_tower_type: String = ""

signal cell_clicked(grid_position: Vector2i)
signal cell_hovered(grid_position: Vector2i)

func _ready():
	if grid_system == null:
		grid_system = GridSystem.new()

	grid_system.grid_updated.connect(_on_grid_updated)
	Logger.ui_log("GridRenderer initialized")

func _draw():
	_draw_grid()
	_draw_cells()
	_draw_hover_highlight()

func _draw_grid():
	if not show_grid_lines:
		return

	var grid_size = grid_system.get_grid_size()

	for x in range(grid_size.x + 1):
		var start_pos = Vector2(x * GridSystem.CELL_SIZE, 0)
		var end_pos = Vector2(x * GridSystem.CELL_SIZE, grid_size.y * GridSystem.CELL_SIZE)
		draw_line(start_pos, end_pos, grid_line_color, 1.0)

	for y in range(grid_size.y + 1):
		var start_pos = Vector2(0, y * GridSystem.CELL_SIZE)
		var end_pos = Vector2(grid_size.x * GridSystem.CELL_SIZE, y * GridSystem.CELL_SIZE)
		draw_line(start_pos, end_pos, grid_line_color, 1.0)

func _draw_cells():
	var grid_size = grid_system.get_grid_size()

	for x in range(grid_size.x):
		for y in range(grid_size.y):
			var pos = Vector2i(x, y)
			var cell_type = grid_system.get_cell_type(pos)
			var color = _get_cell_color(cell_type)

			if color != Color.TRANSPARENT:
				var rect = Rect2(
					Vector2(x * GridSystem.CELL_SIZE, y * GridSystem.CELL_SIZE),
					Vector2(GridSystem.CELL_SIZE, GridSystem.CELL_SIZE)
				)
				draw_rect(rect, color)

func _draw_hover_highlight():
	if hovering_position.x < 0 or hovering_position.y < 0:
		return

	var color = Color.TRANSPARENT
	if placement_mode and selected_tower_type != "":
		if grid_system.can_place_tower(hovering_position):
			color = valid_placement_color
		else:
			color = invalid_placement_color
	else:
		color = Color.CYAN

	if color != Color.TRANSPARENT:
		color.a = 0.5
		var rect = Rect2(
			Vector2(hovering_position.x * GridSystem.CELL_SIZE, hovering_position.y * GridSystem.CELL_SIZE),
			Vector2(GridSystem.CELL_SIZE, GridSystem.CELL_SIZE)
		)
		draw_rect(rect, color)

func _get_cell_color(cell_type: GridSystem.CellType) -> Color:
	match cell_type:
		GridSystem.CellType.EMPTY:
			return Color.TRANSPARENT
		GridSystem.CellType.TOWER:
			return tower_cell_color
		GridSystem.CellType.PATH_START:
			return spawn_cell_color
		GridSystem.CellType.PATH_END:
			return goal_cell_color
		GridSystem.CellType.BLOCKED:
			return Color.BLACK
		_:
			return Color.TRANSPARENT

func _input(event):
	if event is InputEventMouseMotion:
		_handle_mouse_motion(event)
	elif event is InputEventMouseButton and event.pressed:
		_handle_mouse_click(event)

func _handle_mouse_motion(event: InputEventMouseMotion):
	var world_pos = to_local(event.position)
	var grid_pos = grid_system.world_to_grid_position(world_pos)

	if grid_pos != hovering_position:
		hovering_position = grid_pos
		cell_hovered.emit(grid_pos)
		queue_redraw()

		if grid_system.is_valid_position(grid_pos):
			Logger.ui_log("Hovering over cell: %v" % grid_pos, Logger.LogLevel.DEBUG)

func _handle_mouse_click(event: InputEventMouseButton):
	if event.button_index != MOUSE_BUTTON_LEFT:
		return

	var world_pos = to_local(event.position)
	var grid_pos = grid_system.world_to_grid_position(world_pos)

	if grid_system.is_valid_position(grid_pos):
		Logger.ui_log("Cell clicked: %v" % grid_pos)
		cell_clicked.emit(grid_pos)

func set_placement_mode(enabled: bool, tower_type: String = ""):
	placement_mode = enabled
	selected_tower_type = tower_type
	queue_redraw()

	Logger.ui_log("Placement mode: %s, Tower type: %s" % [enabled, tower_type])

func _on_grid_updated():
	queue_redraw()

func get_grid_world_size() -> Vector2:
	var grid_size = grid_system.get_grid_size()
	return Vector2(grid_size.x * GridSystem.CELL_SIZE, grid_size.y * GridSystem.CELL_SIZE)