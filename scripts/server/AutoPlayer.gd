extends Node
class_name AutoPlayer
## 서버 스모크 테스트용 자동 플레이어. 사람이 보내는 것과 같은 명령(Command)만 CommandBus로 보낸다 (치트 경로 없음).
## 타워를 격자 모양으로 깔고, 남는 골드로 몬스터를 만들어 수입을 키운다. 잘하는 봇이 아니라 "한 판이 끝까지 돌아가는가"를 보는 용도다.
## 나중에 #28(봇, 부하 테스트)이 이 파일을 키워 쓴다.

const TICK := 1.0                               # 게임 시간 기준 판단 주기(초)
const TOWER_ROTATION := ["long", "long", "splash"]            # 공중 전용 타워(air)는 지상 몬스터를 못 맞혀서 뺐다
const EVOLUTION_PICK := {"long": "pierce", "splash": "mass", "air": "barrage"}  # 종류별로 공격력이 오르는 진화
const MAX_TOWERS := 30                           # 이 수까지만 짓는다 (몬스터가 지나갈 길을 남긴다)

var bus: CommandBus
var player_id := 0
var _cells: Array[Vector2i] = []                # 아직 안 지어 본 칸 (앞에서부터)
var _kind_i := 0
var _send_i := 0
var _timer := 0.0


func setup(p_bus: CommandBus, p_player_id: int) -> void:
	bus = p_bus
	player_id = p_player_id
	# 몬스터가 나오는 위쪽과 기지(아래쪽)를 빼고, 한 칸씩 띄운 격자로 깐다 (길을 한 번에 막지 않게)
	for y in range(8, GridSystem.GRID_HEIGHT - 6, 2):
		for x in range(1, GridSystem.GRID_WIDTH - 1, 2):
			_cells.append(Vector2i(x, y))


func _process(delta: float) -> void:
	_timer += delta
	if _timer < TICK:
		return
	_timer = 0.0
	var lane: LaneController = bus.lanes.get(player_id)
	if lane == null or not lane.active:
		return
	_build(lane, 10)  # 먼저 10기를 깔고
	_evolve(lane)     # 그다음 진화
	_build(lane, MAX_TOWERS)
	_send_monsters(lane)


func _command(type: String, args: Dictionary) -> Dictionary:
	return bus.execute(Command.make(type, player_id, args))


## 진화하지 않은 타워를 먼저 진화시킨다 (진화 전 타워는 공격력이 너무 약하다)
func _evolve(lane: LaneController) -> void:
	for t in lane.towers:
		if t.can_evolve() and EVOLUTION_PICK.has(t.kind.id):
			var r := _command(Command.EVOLVE_TOWER, {"cell": t.cell, "evo": EVOLUTION_PICK[t.kind.id]})
			if not r["ok"] and r["reason"] == "not_enough_gold":
				return


## 한 번에 몇 개씩 짓는다. 골드가 모자라면 그 칸은 다음 판단에 다시 시도한다 (칸을 버리지 않는다).
func _build(lane: LaneController, limit: int) -> void:
	var tries := 8
	while tries > 0 and not _cells.is_empty() and lane.towers.size() < limit:
		tries -= 1
		var cell: Vector2i = _cells[0]
		var kind: String = TOWER_ROTATION[_kind_i % TOWER_ROTATION.size()]
		var r := _command(Command.BUILD_TOWER, {"cell": cell, "kind_id": kind, "confirmed": false})
		if r["ok"]:
			_cells.pop_front()
			_kind_i += 1
		elif r["reason"] == "not_enough_gold":
			return
		else:
			_cells.pop_front()  # 길이 막히거나 지을 수 없는 칸은 건너뛴다


## 타워를 다 깔았거나 골드가 남으면 몬스터를 만든다 (일꾼 -> 광부 -> 전사 순으로 번갈아)
func _send_monsters(lane: LaneController) -> void:
	if lane.towers.size() < MAX_TOWERS and not _cells.is_empty() and lane.gold_shown() < 100:
		return  # 아직 타워가 우선
	var order := ["worker", "miner", "warrior"]
	for i in range(3):
		var kind: String = order[(_send_i + i) % order.size()]
		if _command(Command.SEND_MONSTER, {"kind_id": kind})["ok"]:
			_send_i += 1
			return
