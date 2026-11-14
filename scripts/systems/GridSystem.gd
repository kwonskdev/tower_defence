extends Node
class_name GridSystem

signal cell_state_changed(position: Vector2i, old_state: CellState, new_state: CellState)

enum CellState {
	EMPTY,
	TOWER,
	OBSTACLE,
	PATH,
	SPAWN,
	EXIT
}

const GRID_WIDTH = 12
const GRID_HEIGHT = 50

var grid_data: Array[Array] = []
var grid_renderer: GridRenderer
var player_id: int = 0  # 로그 식별용 (0-based)

# 초기 배치처럼 한꺼번에 바꿀 때 셀 단위 로그가 쏟아지는 것을 막기 위한 플래그
var _suppress_cell_log: bool = false

func _ready():
	initialize_grid()

func initialize_grid():
	grid_data.clear()
	grid_data.resize(GRID_HEIGHT)

	for y in range(GRID_HEIGHT):
		grid_data[y] = []
		grid_data[y].resize(GRID_WIDTH)
		for x in range(GRID_WIDTH):
			grid_data[y][x] = CellState.EMPTY

	Log.info(Log.Category.GRID, "[P%d] 그리드 초기화 %dx%d" % [player_id + 1, GRID_WIDTH, GRID_HEIGHT])

func connect_renderer(renderer: GridRenderer):
	grid_renderer = renderer
	if grid_renderer:
		update_all_visuals()

func disconnect_renderer():
	grid_renderer = null

func get_cell_state(position: Vector2i) -> CellState:
	if not is_valid_position(position):
		return CellState.OBSTACLE

	return grid_data[position.y][position.x]

func set_cell_state(position: Vector2i, new_state: CellState) -> bool:
	if not is_valid_position(position):
		Log.warn(Log.Category.GRID, "[P%d] 범위 밖 셀 변경 시도: %s" % [player_id + 1, position])
		return false

	var old_state = grid_data[position.y][position.x]
	if old_state == new_state:
		return true

	grid_data[position.y][position.x] = new_state
	if not _suppress_cell_log:
		Log.debug(Log.Category.GRID, "[P%d] 셀 %s: %s -> %s" % [
			player_id + 1, position, get_state_name(old_state), get_state_name(new_state)])
	cell_state_changed.emit(position, old_state, new_state)
	update_cell_visual(position, new_state)

	return true

func update_cell_visual(position: Vector2i, state: CellState):
	if not grid_renderer:
		return

	var color: Color
	match state:
		CellState.EMPTY:
			grid_renderer.clear_cell_highlight(position)
			return
		CellState.TOWER:
			color = Color.BLUE
			color.a = 0.6
		CellState.OBSTACLE:
			color = Color.RED
			color.a = 0.6
		CellState.PATH:
			color = Color.GREEN
			color.a = 0.4
		CellState.SPAWN:
			color = Color.ORANGE
			color.a = 0.7
		CellState.EXIT:
			color = Color.PURPLE
			color.a = 0.7

	grid_renderer.highlight_cell(position, color)

func update_all_visuals():
	if not grid_renderer:
		return

	grid_renderer.clear_all_highlights()

	for y in range(GRID_HEIGHT):
		for x in range(GRID_WIDTH):
			var pos = Vector2i(x, y)
			var state = get_cell_state(pos)
			if state != CellState.EMPTY:
				update_cell_visual(pos, state)

func is_valid_position(position: Vector2i) -> bool:
	return position.x >= 0 and position.x < GRID_WIDTH and position.y >= 0 and position.y < GRID_HEIGHT

func is_cell_empty(position: Vector2i) -> bool:
	return get_cell_state(position) == CellState.EMPTY

func setup_game_path():
	_suppress_cell_log = true
	# 맨 위 행 전체를 시작점(SPAWN)으로 설정
	for x in range(GRID_WIDTH):
		set_cell_state(Vector2i(x, 0), CellState.SPAWN)

	# 맨 아래 행 전체를 도착점(EXIT)으로 설정
	for x in range(GRID_WIDTH):
		set_cell_state(Vector2i(x, GRID_HEIGHT - 1), CellState.EXIT)
	_suppress_cell_log = false

	# 나머지는 모두 EMPTY로 유지 (몬스터가 자유롭게 이동 가능)
	Log.info(Log.Category.GRID, "[P%d] 스폰(y=0)/도착(y=%d) 라인 설정 완료" % [player_id + 1, GRID_HEIGHT - 1])

func get_state_name(state: CellState) -> String:
	match state:
		CellState.EMPTY: return "EMPTY"
		CellState.TOWER: return "TOWER"
		CellState.OBSTACLE: return "OBSTACLE"
		CellState.PATH: return "PATH"
		CellState.SPAWN: return "SPAWN"
		CellState.EXIT: return "EXIT"
		_: return "UNKNOWN"
