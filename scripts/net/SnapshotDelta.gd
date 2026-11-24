class_name SnapshotDelta
## 스냅샷 두 장의 차이만 담은 "변경분"을 만들고(diff), 받은 쪽이 기준 스냅샷에 적용한다(apply) (#20).
## 모양은 Snapshot.build가 만든 Dictionary 그대로라서 JSON으로 보낼 수 있고, 적용한 결과는 스냅샷과 같은 모양이다.
##
## 규칙
##   - Dictionary: 바뀐 키만 담는다. 값이 Dictionary면 안쪽도 같은 규칙으로 (재귀). 사라진 키는 REMOVED 목록에 적는다.
##   - 키가 있는 목록(KEYED: 타워는 cell, 몬스터는 id): {"s": [새로 생겼거나 바뀐 항목], "d": [사라진 항목의 키]}.
##       바뀐 항목은 키 필드와 바뀐 필드만 담는다. 목록의 순서는 보존하지 않는다 (그리는 데 순서가 필요 없다).
##   - 그 밖의 목록과 숫자/글자: 달라졌으면 통째로 바꾼다.
##   - 기준에 없던 키는 값 그대로 담는다 (키 목록도 통째로). 기준이 {}이면 변경분 = 스냅샷 전체 (키프레임).
## 서버가 보내기 전에 quantize()로 값을 거칠게 만들어 둔다: 변하지 않는 값은 아예 안 보내진다 (서 있는 몬스터는 0바이트).

const REMOVED := "-"
## 목록 이름 -> 항목을 구분하는 필드
const KEYED := {"towers": "cell", "monsters": "id"}


## 네트워크로 보낼 정밀도로 거칠게 한다. 그리는 데 필요한 만큼만 남긴다 (새 Dictionary를 돌려주고 원본은 건드리지 않는다).
##   위치 0.01칸, 몬스터 체력 정수, 서 있은 시간 5초 단위 (자라는 모습에만 쓰인다. 60초까지. 1초 단위면 서 있는 몬스터가 매 틱 10%씩 계속 변경분에 실린다)
static func quantize(snap: Dictionary) -> Dictionary:
	var out := snap.duplicate()
	var lanes := {}
	for key in snap.lanes:
		var lane: Dictionary = snap.lanes[key].duplicate()
		lane["monsters"] = _q_monsters(lane.monsters)
		lanes[key] = lane
	out["lanes"] = lanes
	if not snap.boss.is_empty():
		var boss: Dictionary = snap.boss.duplicate()
		boss["monsters"] = _q_monsters(boss.monsters)
		out["boss"] = boss
	return out


static func _q_monsters(list: Array) -> Array:
	var out: Array = []
	out.resize(list.size())
	for i in list.size():
		var m: Dictionary = list[i].duplicate()
		var p: Array = m.pos
		m["pos"] = [snappedf(p[0], 0.01), snappedf(p[1], 0.01)]
		m["hp"] = roundf(m.hp)
		m["time_at_boss"] = minf(floorf(m.time_at_boss / 5.0) * 5.0, 60.0)
		out[i] = m
	return out


## base에서 cur로 가는 변경분. 같으면 빈 Dictionary.
static func diff(base: Dictionary, cur: Dictionary) -> Dictionary:
	var out := {}
	for key in cur:
		if not base.has(key):
			out[key] = cur[key]
			continue
		var a = base[key]
		var b = cur[key]
		if typeof(a) == TYPE_DICTIONARY and typeof(b) == TYPE_DICTIONARY:
			var sub := diff(a, b)
			if not sub.is_empty():
				out[key] = sub
		elif KEYED.has(key) and typeof(a) == TYPE_ARRAY and typeof(b) == TYPE_ARRAY:
			var sub := _diff_keyed(a, b, KEYED[key])
			if not sub.is_empty():
				out[key] = sub
		elif a != b:
			out[key] = b
	var gone: Array = []
	for key in base:
		if not cur.has(key):
			gone.append(key)
	if not gone.is_empty():
		out[REMOVED] = gone
	return out


static func _key_of(entry: Dictionary, field: String) -> String:
	var v = entry[field]
	return "%d,%d" % [v[0], v[1]] if typeof(v) == TYPE_ARRAY else str(int(v))


static func _diff_keyed(a: Array, b: Array, field: String) -> Dictionary:
	var old := {}
	for e in a:
		old[_key_of(e, field)] = e
	var changed: Array = []
	var seen := {}
	for e in b:
		var k := _key_of(e, field)
		seen[k] = true
		if not old.has(k):
			changed.append(e)
			continue
		var part := {}
		for f in e:
			if not old[k].has(f) or old[k][f] != e[f]:
				part[f] = e[f]
		if not part.is_empty():
			part[field] = e[field]
			changed.append(part)
	var removed: Array = []
	for k in old:
		if not seen.has(k):
			removed.append(old[k][field])
	if changed.is_empty() and removed.is_empty():
		return {}
	return {"s": changed, "d": removed}


## base에 변경분을 적용한 새 스냅샷 (base는 건드리지 않는다). 받은 데이터가 이상해도 오류 없이 가능한 만큼만 적용한다.
static func apply(base: Dictionary, delta: Dictionary) -> Dictionary:
	var out := base.duplicate()
	for key in delta:
		if key == REMOVED:
			continue
		var d = delta[key]
		if typeof(d) == TYPE_DICTIONARY and typeof(out.get(key)) == TYPE_DICTIONARY and not _is_keyed_patch(key, d):
			out[key] = apply(out[key], d)
		elif KEYED.has(key) and typeof(d) == TYPE_DICTIONARY and typeof(out.get(key)) == TYPE_ARRAY:
			out[key] = _apply_keyed(out[key], d, KEYED[key])
		else:
			out[key] = d
	var gone = delta.get(REMOVED, [])
	if typeof(gone) == TYPE_ARRAY:
		for key in gone:
			out.erase(key)
	return out


static func _is_keyed_patch(key: String, d: Dictionary) -> bool:
	return KEYED.has(key) and d.has("s")


static func _apply_keyed(base: Array, patch: Dictionary, field: String) -> Array:
	var index := {}  # 키 -> 항목 (들어온 순서를 유지한다)
	for e in base:
		index[_key_of(e, field)] = e.duplicate()
	for k in patch.get("d", []):
		index.erase(_key_of({field: k}, field))
	for e in patch.get("s", []):
		var k := _key_of(e, field)
		if index.has(k):
			index[k].merge(e, true)
		else:
			index[k] = e.duplicate()
	return index.values()
