class_name Lobby
## 시작 전 대기실 (#22). 네트워크와 화면을 모르는 순수 규칙이라 서버가 쓰고 테스트가 직접 돌린다.
##
## 규칙 (오너 결정)
##  - 먼저 들어온 순서대로 가장 작은 빈 레인(0~max-1)을 받는다. 나가면 그 레인이 빈다.
##  - 방장, 준비, 시작 버튼은 없다. 로비가 열린 뒤(첫 입장 기준) AUTO_START_SEC가 지나면 그때 들어 있는 사람들로 자동 시작한다.
##  - 자동 시작은 2명 이상일 때만이다. 혼자 하는 1인 플레이는 로비를 거치지 않고 지금처럼 시작 버튼으로 시작한다 (로컬).
## 내가 정한 것 (PR 설명에 적었다):
##  - 시간이 다 됐는데 한 명뿐이면 시작하지 않고 기다린다. 두 번째 사람이 들어오면 그 순간부터 다시 AUTO_START_SEC를 센다.
##  - 중간에 나가도 시계는 계속 간다 (2명 아래로 줄어도). 모두 나가 빈 방이 되면 시계가 꺼지고 다음 첫 입장이 다시 시작한다.
##  - 8명이 다 차도 시간을 기다린다 (오너가 시간 경과만 정했다).

enum Phase { OPEN, STARTING, STARTED }

signal changed()

var max_players := Balance.MAX_PLAYERS
var auto_start_sec := Balance.LOBBY_AUTO_START_SEC
var phase := Phase.OPEN
var countdown_left := -1.0      # 자동 시작까지 남은 시간(초). -1 = 세지 않는 중 (아무도 없음)

var _members: Array = []         # 들어온 순서대로 [{peer, name, lane}]


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
	_members.append({"peer": peer, "name": player_name, "lane": lane})
	if _members.size() == 1 or (_members.size() == 2 and countdown_left <= 0.0):
		countdown_left = auto_start_sec  # 첫 입장 = 로비가 열린 순간 / 혼자 기다리다 시간이 다 된 뒤 두 번째가 들어온 순간
	_changed()
	return {"ok": true, "lane": lane}


func leave(peer: int) -> void:
	var i := find(peer)
	if i < 0 or phase != Phase.OPEN:
		return
	_members.remove_at(i)
	if _members.is_empty():
		countdown_left = -1.0  # 아무도 없으면 시계를 끈다. 다음 첫 입장이 다시 시작한다
	_changed()


## 시간이 흐른다. 시작해야 하면 true (한 번만. 그 뒤 phase는 STARTING).
func tick(delta: float) -> bool:
	if phase != Phase.OPEN or _members.is_empty():
		return false
	if countdown_left > 0.0:
		countdown_left = maxf(0.0, countdown_left - delta)
	if should_start():
		phase = Phase.STARTING
		return true
	return false


func should_start() -> bool:
	return phase == Phase.OPEN and _members.size() >= 2 and countdown_left <= 0.0


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


## 화면/네트워크로 보낼 모양: {members: [{lane, name}], max, countdown} (레인 번호 순)
func view() -> Dictionary:
	var list: Array = []
	for m in _members:
		list.append({"lane": m.lane, "name": m.name})
	list.sort_custom(func(a, b): return a.lane < b.lane)
	return {"members": list, "max": max_players, "countdown": countdown_left}


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
