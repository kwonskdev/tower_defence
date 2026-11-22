class_name MapView
extends Node
## 맵 위의 타워/몬스터를 서버 스냅샷만으로 그린다 (#21). 시뮬레이션 객체(LaneController의 Tower/Monster)는 읽지 않는다.
## 스냅샷의 항목마다 "껍데기(puppet)" 노드를 하나씩 만들어 그리기만 시키고, 스냅샷에서 사라진 항목은 치운다.
## 껍데기는 Tower/Monster와 같은 클래스의 puppet 모드라서 모양(그리기 코드)은 예전과 똑같다.
## 서버에는 없다: 화면이 있는 클라이언트(GameField)만 만든다.

var renderer: GridRenderer
var _towers: Dictionary = {}    # "레인:x:y" -> Tower(puppet)
var _monsters: Dictionary = {}  # "레인:id" -> Monster(puppet)


func _init(p_renderer: GridRenderer) -> void:
	renderer = p_renderer


## 스냅샷에 맞춰 껍데기를 만들고/고치고/치운다. current_lane: 지금 보고 있는 레인 (그것만 보인다). selected_key: 선택한 타워 "레인:x:y" ("" = 없음)
func sync(snap: Dictionary, current_lane: int, selected_key: String) -> void:
	var seen_towers := {}
	var seen_monsters := {}
	for lane_key in snap.lanes:
		var lane_id := int(lane_key)
		var lane: Dictionary = snap.lanes[lane_key]
		var shown := lane_id == current_lane
		for t in lane.towers:
			var key := "%d:%d:%d" % [lane_id, t.cell[0], t.cell[1]]
			seen_towers[key] = true
			_sync_tower(key, t, shown, key == selected_key)
		for m in lane.monsters:
			var mkey := "%d:%d" % [lane_id, m.id]
			seen_monsters[mkey] = true
			_sync_monster(mkey, m, shown)
	var boss: Dictionary = snap.boss
	if not boss.is_empty():
		var shown_boss := current_lane == GameField.BOSS_LANE_ID
		for m in boss.monsters:
			var bkey := "%d:%d" % [GameField.BOSS_LANE_ID, m.id]
			seen_monsters[bkey] = true
			_sync_monster(bkey, m, shown_boss)
	_prune(_towers, seen_towers)
	_prune(_monsters, seen_monsters)


func _sync_tower(key: String, v: Dictionary, shown: bool, selected: bool) -> void:
	var tower: Tower = _towers.get(key)
	if tower == null:
		tower = Tower.new()
		tower.puppet = true
		tower.setup(Vector2i(v.cell[0], v.cell[1]), Balance.tower_kind(v.kind), Balance.color_info_by_name(v.color), null, renderer)
		tower.z_index = 1
		renderer.add_child(tower)
		_towers[key] = tower
	tower.apply_view(v)
	tower.selected = selected
	tower.visible = shown


func _sync_monster(key: String, v: Dictionary, shown: bool) -> void:
	var monster: Monster = _monsters.get(key)
	if monster == null:
		monster = Monster.new()
		monster.setup_puppet(renderer)
		monster.z_index = 2
		renderer.add_child(monster)
		_monsters[key] = monster
	monster.apply_view(v)
	monster.visible = shown


func _prune(nodes: Dictionary, seen: Dictionary) -> void:
	for key in nodes.keys():
		if not seen.has(key):
			nodes[key].queue_free()
			nodes.erase(key)


## 지금 그려지고 있는 껍데기 수 (테스트용)
func tower_count() -> int:
	return _towers.size()


func monster_count() -> int:
	return _monsters.size()


func monster_node(lane_id: int, monster_id: int) -> Monster:
	return _monsters.get("%d:%d" % [lane_id, monster_id])


func tower_node(lane_id: int, cell: Vector2i) -> Tower:
	return _towers.get("%d:%d:%d" % [lane_id, cell.x, cell.y])
