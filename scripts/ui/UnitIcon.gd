extends Control
class_name UnitIcon
## 버튼 안에 넣는 아이콘. 글자 대신 실제로 게임에 나타나는 모습(몬스터/타워)을 그대로 보여준다.
## 몬스터/타워 노드를 "미리보기 모드"로 자식에 두어서 게임 화면과 같은 그림, 같은 애니메이션이 나온다.

var _node: Node2D
var _tall_decor := false  # 깃발/모자처럼 머리 위로 길게 올라오는 장식이 있으면 살짝 아래로 내려서 그린다


func _ready() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	resized.connect(_layout)


## 몬스터의 모습
func show_monster(kind_id: String) -> void:
	var data: Dictionary = Monsters.DATA[kind_id]
	var m := Monster.new()
	m.preview = true
	m.apply_look(data)
	m.kind_id = kind_id
	m.aura_radius = 0.0  # 아이콘에서는 오라 원을 그리지 않는다
	_tall_decor = data.shape in ["flag", "banner", "tophat", "flame", "sprout", "coin"]
	_set_node(m)


## 타워의 모습 (색깔은 건설할 때 랜덤으로 정해지므로 아이콘에서는 중립색)
func show_tower(kind: Dictionary) -> void:
	var t := Tower.new()
	t.preview = true
	t.kind = kind
	t.color_info = {"name": "미리보기", "color": Color(0.8, 0.82, 0.9)}
	_tall_decor = false
	_set_node(t)


## 진화한 타워의 모습 (계열마다 다르다)
func show_evolution(evo: String) -> void:
	var t := Tower.new()
	t.preview = true
	t.kind = Balance.tower_kind(Evolutions.DATA[evo].tower)
	t.evolution = evo
	t.color_info = {"name": "미리보기", "color": Color(0.8, 0.82, 0.9)}
	_tall_decor = false
	_set_node(t)


func _set_node(n: Node2D) -> void:
	if _node:
		_node.queue_free()
	_node = n
	add_child(n)
	_layout()


func _layout() -> void:
	if _node == null:
		return
	var s := minf(size.x, size.y)
	var center := size * 0.5
	if _node is Monster:
		var m: Monster = _node
		# 덩치가 큰 몬스터도 아이콘 안에 들어오도록 크기를 맞춘다
		m.preview_cell = s * 0.9 / maxf(1.0, m.size_scale)
		center.y += s * (0.12 if _tall_decor else 0.02)
	elif _node is Tower:
		var t: Tower = _node
		t.preview_cell = s * 0.72  # 긴 포신/미사일이 아이콘 밖으로 잘리지 않게
		t.queue_redraw()  # 크기가 바뀌면 다시 그린다 (아이콘은 평소에 다시 그리지 않는다)
	_node.position = center
