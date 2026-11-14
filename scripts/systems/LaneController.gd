extends Node
class_name LaneController
## 한 플레이어 레인의 진행(몬스터 자동 스폰, 생명)을 담당한다.
## 협력(PvE)에서는 참여한 플레이어의 레인에만 만든다. (참여 안 한 레인은 비어 있음)
## TODO: 몬스터 파견 주기/강화, 보스 연동, 골드/수입

signal lives_changed(lives: int)
signal lane_failed

const START_LIVES := 10
const SPAWN_INTERVAL := 2.0  # 임시 값 (밸런싱 대상)

var player_id: int = 0
var lives: int = START_LIVES
var monsters: Array[Monster] = []

var _grid: GridSystem
var _renderer: GridRenderer
var _pathfinder: Pathfinder
var _timer: Timer
var _next_monster_id := 1
var _failed := false
var _lane_visible := true


func setup(p_player_id: int, grid: GridSystem, renderer: GridRenderer) -> void:
	player_id = p_player_id
	_grid = grid
	_renderer = renderer
	_pathfinder = Pathfinder.new(grid)

	_timer = Timer.new()
	_timer.wait_time = SPAWN_INTERVAL
	_timer.timeout.connect(_spawn_monster)
	add_child(_timer)
	_timer.start()
	Log.info(Log.Category.GAME, "[P%d] 레인 시작: 생명=%d, 스폰 간격=%.1fs" % [player_id + 1, lives, SPAWN_INTERVAL])


func _spawn_monster() -> void:
	var spawn_cells := _grid.get_spawn_cells()
	if spawn_cells.is_empty():
		Log.error(Log.Category.GAME, "[P%d] 스폰 셀이 없음" % (player_id + 1))
		return

	var monster := Monster.new()
	monster.visible = _lane_visible
	monster.setup(_next_monster_id, _grid, _renderer, _pathfinder, spawn_cells.pick_random())
	monster.reached_exit.connect(_on_monster_reached_exit)
	_renderer.add_child(monster)
	monsters.append(monster)
	Log.debug(Log.Category.GAME, "[P%d] 몬스터#%d 스폰 %s (필드 위 %d마리)" % [
		player_id + 1, _next_monster_id, monster.grid_pos, monsters.size()])
	_next_monster_id += 1


func _on_monster_reached_exit(monster: Monster) -> void:
	monsters.erase(monster)
	monster.queue_free()
	lives -= 1
	Log.info(Log.Category.GAME, "[P%d] 몬스터#%d 기지 도달! 생명 %d" % [player_id + 1, monster.monster_id, lives])
	lives_changed.emit(lives)

	if lives <= 0 and not _failed:
		_failed = true
		_timer.stop()
		for m in monsters:
			m.queue_free()
		monsters.clear()
		Log.warn(Log.Category.GAME, "[P%d] 생명 0 - 게임 오버" % (player_id + 1))
		lane_failed.emit()


## 타워를 지을 수 없는 칸인지 (몬스터가 서 있거나 곧 들어갈 칸)
func is_cell_occupied(cell: Vector2i) -> bool:
	for m in monsters:
		if m.grid_pos == cell or (not m.path.is_empty() and m.path[0] == cell):
			return true
	return false


## 현재 화면에 보이는 레인인지에 따라 몬스터 표시/숨김
func set_lane_visible(is_shown: bool) -> void:
	_lane_visible = is_shown
	for m in monsters:
		m.visible = is_shown
