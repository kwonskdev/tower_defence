class_name Lobby
## 시작 전 대기방 (#22). 네트워크와 화면을 모르는 순수 규칙이라 서버가 쓰고 테스트가 직접 돌린다.
##
## 흐름 (오너 결정): 방장이 방을 만든다 -> 사람들이 모인다 -> 각자 [준비] -> 모두 준비하면 방장이 [시작] -> 게임(레인) 화면으로 넘어간다.
##   게임 화면에 들어간 뒤의 30초 카운트다운은 로비가 아니라 서버(NetServer)가 센다. 1인 플레이는 로비를 거치지 않는다 (로컬).
## 규칙
##  - 먼저 들어온 순서대로 가장 작은 빈 레인(0~max-1)을 받는다. 나가면 그 레인이 빈다.
##  - 방장 = 지금 들어 있는 사람 중 가장 먼저 들어온 사람 (방을 만든 사람). 로비에서 방장이 나가면 다음 사람이 된다 (게임 중 승계는 #23).
##  - 방장은 늘 준비된 것으로 본다. 시작은 방장만, 나머지가 모두 준비했을 때만 (방장 재량으로 못 앞당긴다). 방장 혼자여도 된다 (최소 1명).
##  - 준비 후에 새로 사람이 들어오면 그 사람이 준비하기 전에는 시작할 수 없다.

enum Phase { OPEN, STARTING, STARTED }

signal changed()

var max_players := Balance.MAX_PLAYERS
var phase := Phase.OPEN

var _members: Array = []         # 들어온 순서대로 [{peer, name, ready, lane}]


## 들어온다. 성공하면 {"ok": true, "lane": 레인}, 아니면 {"ok": false, "reason": REJECT 사유}.
## name은 이미 정리/중복 제거한 것을 준다 (NetServer가 Nicknames.unique로).
func join(peer: int, player_name: String) -> Dictionary:
	if phase != Phase.OPEN:
		return {"ok": false, "reason": NetProtocol.REJECT_STARTED}
	if find(peer) >= 0:
		return {"ok": true, "lane": lane_of(peer)}
	var lane := _free_lane()
	if lane < 0:
		return {"ok": false, "reason": NetProtocol.REJECT_FULL}
	_members.append({"peer": peer, "name": player_name, "ready": false, "lane": lane})
	_changed()
	return {"ok": true, "lane": lane}


func leave(peer: int) -> void:
	var i := find(peer)
	if i < 0 or phase != Phase.OPEN:
		return
	_members.remove_at(i)
	_changed()


## 준비/준비 취소. 방장은 늘 준비된 것으로 보므로 바꿀 수 없다 (false).
func set_ready(peer: int, on: bool) -> bool:
	var i := find(peer)
	if i <= 0 or phase != Phase.OPEN:
		return false
	_members[i].ready = on
	_changed()
	return true


## 방장을 뺀 모두가 준비했는가
func all_ready() -> bool:
	for i in range(1, _members.size()):
		if not _members[i].ready:
			return false
	return true


## 지금 시작할 수 있는가 (한 명 이상, 모두 준비)
func can_start() -> bool:
	return phase == Phase.OPEN and not _members.is_empty() and all_ready()


## 방장이 [시작]을 눌렀다. 방장이 아니거나 아직 모두 준비하지 않았으면 false.
func host_start(peer: int) -> bool:
	if peer != host_peer() or not can_start():
		return false
	phase = Phase.STARTING
	return true


func mark_started() -> void:
	phase = Phase.STARTED
	_changed()


func size() -> int:
	return _members.size()


func find(peer: int) -> int:
	for i in range(_members.size()):
		if _members[i].peer == peer:
			return i
	return -1


func lane_of(peer: int) -> int:
	var i := find(peer)
	return -1 if i < 0 else int(_members[i].lane)


func host_peer() -> int:
	return -1 if _members.is_empty() else int(_members[0].peer)


## 시작 때 확정되는 참여 레인 (작은 번호부터)
func lanes() -> Array[int]:
	var out: Array[int] = []
	for m in _members:
		out.append(int(m.lane))
	out.sort()
	return out


## 레인 번호 -> 닉네임
func names_by_lane() -> Dictionary:
	var out := {}
	for m in _members:
		out[int(m.lane)] = m.name
	return out


## 화면/네트워크로 보낼 모양: {members: [{lane, name, ready, host}], host: 방장 레인, max, can_start} (레인 번호 순)
func view() -> Dictionary:
	var list: Array = []
	for i in range(_members.size()):
		var m: Dictionary = _members[i]
		list.append({"lane": m.lane, "name": m.name, "ready": i == 0 or m.ready, "host": i == 0})
	list.sort_custom(func(a, b): return a.lane < b.lane)
	return {"members": list, "host": -1 if _members.is_empty() else int(_members[0].lane), "max": max_players, "can_start": can_start()}


func _free_lane() -> int:
	for lane in range(max_players):
		var used := false
		for m in _members:
			if m.lane == lane:
				used = true
				break
		if not used:
			return lane
	return -1


func _changed() -> void:
	changed.emit()
