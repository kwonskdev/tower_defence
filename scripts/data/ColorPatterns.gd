extends RefCounted
class_name ColorPatterns
## 색깔 패턴 이스터에그. 타워 색이 특정 모양으로 모이면 완성하는 순간 골드/생명을 한 번 준다.
## 보상은 "패턴 종류마다 한 게임에 한 번"이다 (LaneController가 기록한다). 다시 맞추거나 다른 자리에 또 만들어도 또 주지 않는다.
##
## - 태극기   : 2x2에 빨강/파랑이 대각으로 엇갈린다 (빨파/파빨 또는 파빨/빨파)
## - 무지개   : 일렬 7칸이 빨주노초파남보 순서 (가로는 왼쪽->오른쪽, 세로는 위->아래로 읽는다)
## - 역무지개 : 위와 같은 7칸을 반대 방향으로 읽어 보보남파초노주빨 순서
## - 신호등   : 일렬 3칸이 빨노초 (어느 방향으로 읽어도 된다)

const RAINBOW := ["빨강", "주황", "노랑", "초록", "파랑", "남색", "보라"]
const TRAFFIC_LIGHT := ["빨강", "노랑", "초록"]

# gold / lives: 완성했을 때 한 번 받는 보상
const PATTERNS := {
	"taegeuk": {"name": "태극기", "gold": 31, "lives": 0},
	"rainbow": {"name": "무지개", "gold": 77, "lives": 0},
	"reverse_rainbow": {"name": "역무지개", "gold": 0, "lives": 7},
	"traffic_light": {"name": "신호등", "gold": 0, "lives": 3},
}

const _DIRS := [Vector2i(1, 0), Vector2i(0, 1)]  # 가로(왼->오), 세로(위->아래)


## 보상 문구 (예: "+31골드", "생명 +7")
static func reward_text(id: String) -> String:
	var d: Dictionary = PATTERNS[id]
	var parts: Array[String] = []
	if int(d.gold) > 0:
		parts.append("+%d골드" % int(d.gold))
	if int(d.lives) > 0:
		parts.append("생명 +%d" % int(d.lives))
	return " ".join(parts)


## 타워 색 지도 {칸(Vector2i): 색 이름}에서 지금 완성돼 있는 패턴을 모두 찾는다.
## 반환: [{id: 패턴 ID, cells: Array[Vector2i], key: "ID:x,y;x,y..." (같은 조합이면 항상 같은 문자열)}]
static func find(colors: Dictionary) -> Array:
	var found: Array = []
	for p in colors:
		_find_taegeuk(colors, p, found)
		for dir in _DIRS:
			_find_line(colors, p, dir, RAINBOW.size(), found)
			_find_line(colors, p, dir, TRAFFIC_LIGHT.size(), found)
	return found


static func _find_taegeuk(colors: Dictionary, p: Vector2i, found: Array) -> void:
	var cells: Array[Vector2i] = [p, p + Vector2i(1, 0), p + Vector2i(0, 1), p + Vector2i(1, 1)]
	for c in cells:
		if not colors.has(c):
			return
	var a: String = colors[cells[0]]  # 왼쪽 위 (오른쪽 아래와 같은 색이어야 한다)
	var b: String = colors[cells[1]]  # 오른쪽 위 (왼쪽 아래와 같은 색이어야 한다)
	if a == colors[cells[3]] and b == colors[cells[2]] and ((a == "빨강" and b == "파랑") or (a == "파랑" and b == "빨강")):
		found.append(_entry("taegeuk", cells))


## p에서 dir 방향으로 length칸이 무지개/역무지개/신호등인지 본다 (p가 줄의 시작이다)
static func _find_line(colors: Dictionary, p: Vector2i, dir: Vector2i, length: int, found: Array) -> void:
	var cells: Array[Vector2i] = []
	var names: Array = []
	for i in range(length):
		var c := p + dir * i
		if not colors.has(c):
			return
		cells.append(c)
		names.append(colors[c])
	if length == RAINBOW.size():
		if names == RAINBOW:
			found.append(_entry("rainbow", cells))
		else:
			var reversed := RAINBOW.duplicate()
			reversed.reverse()
			if names == reversed:
				found.append(_entry("reverse_rainbow", cells))
	else:
		var back := TRAFFIC_LIGHT.duplicate()
		back.reverse()
		if names == TRAFFIC_LIGHT or names == back:
			found.append(_entry("traffic_light", cells))


static func _entry(id: String, cells: Array[Vector2i]) -> Dictionary:
	var key := id
	for c in cells:
		key += ":%d,%d" % [c.x, c.y]
	return {"id": id, "cells": cells, "key": key}
