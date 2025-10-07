extends Control
class_name GridRenderer

signal cell_clicked(grid_position: Vector2i)
signal cell_hovered(grid_position: Vector2i)

const GRID_WIDTH = 12
const GRID_HEIGHT = 50
var CELL_SIZE = 40

var grid_color = Color.WHITE
var highlight_color = Color.YELLOW
var path_color = Color.GREEN
var tower_color = Color.BLUE
var obstacle_color = Color.RED

var highlighted_cells: Dictionary = {}

func _ready():
	update_grid_size()
	mouse_filter = Control.MOUSE_FILTER_IGNORE

func update_grid_size():
	custom_minimum_size = Vector2(GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE)

func set_container_width(width: float):
	CELL_SIZE = int(width / GRID_WIDTH)
	update_grid_size()
	queue_redraw()

func _draw():
	draw_grid_background()
	draw_cell_highlights()
	draw_grid_lines()

func draw_grid_background():
	var bg_color = Color.BLACK
	bg_color.a = 0.1
	draw_rect(Rect2(Vector2.ZERO, Vector2(GRID_WIDTH * CELL_SIZE, GRID_HEIGHT * CELL_SIZE)), bg_color)

func draw_cell_highlights():
	for pos in highlighted_cells:
		var color = highlighted_cells[pos]
		var rect = Rect2(Vector2(pos.x * CELL_SIZE, pos.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))
		draw_rect(rect, color)

func draw_grid_lines():
	# Vertical lines
	for x in range(GRID_WIDTH + 1):
		var start_pos = Vector2(x * CELL_SIZE, 0)
		var end_pos = Vector2(x * CELL_SIZE, GRID_HEIGHT * CELL_SIZE)
		draw_line(start_pos, end_pos, grid_color, 1.0)

	# Horizontal lines
	for y in range(GRID_HEIGHT + 1):
		var start_pos = Vector2(0, y * CELL_SIZE)
		var end_pos = Vector2(GRID_WIDTH * CELL_SIZE, y * CELL_SIZE)
		draw_line(start_pos, end_pos, grid_color, 1.0)


func screen_to_grid(screen_pos: Vector2) -> Vector2i:
	return Vector2i(int(screen_pos.x / CELL_SIZE), int(screen_pos.y / CELL_SIZE))

func grid_to_screen(grid_pos: Vector2i) -> Vector2:
	return Vector2(grid_pos.x * CELL_SIZE + CELL_SIZE * 0.5, grid_pos.y * CELL_SIZE + CELL_SIZE * 0.5)

func is_valid_grid_position(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.x < GRID_WIDTH and pos.y >= 0 and pos.y < GRID_HEIGHT

func highlight_cell(grid_pos: Vector2i, color: Color):
	if is_valid_grid_position(grid_pos):
		highlighted_cells[grid_pos] = color
		queue_redraw()

func clear_cell_highlight(grid_pos: Vector2i):
	if grid_pos in highlighted_cells:
		highlighted_cells.erase(grid_pos)
		queue_redraw()

func clear_all_highlights():
	highlighted_cells.clear()
	queue_redraw()

func set_cell_color(grid_pos: Vector2i, color: Color):
	highlight_cell(grid_pos, color)

func get_grid_size() -> Vector2i:
	return Vector2i(GRID_WIDTH, GRID_HEIGHT)

func get_cell_size() -> int:
	return CELL_SIZE

func set_grid_color(color: Color):
	grid_color = color
	queue_redraw()

func get_cell_rect(grid_pos: Vector2i) -> Rect2:
	if not is_valid_grid_position(grid_pos):
		return Rect2()

	return Rect2(Vector2(grid_pos.x * CELL_SIZE, grid_pos.y * CELL_SIZE), Vector2(CELL_SIZE, CELL_SIZE))