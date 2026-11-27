class_name MatchRecord
## 판 기록을 만든다 (#25). 값은 전부 서버가 가진 시뮬레이션 상태(BossController, 방의 자리/세션)에서 읽는다:
## 클라이언트가 보낸 점수나 결과는 어떤 경로로도 여기에 들어오지 않는다 (서버는 그런 메시지를 받지 않는다).
## 모양은 계정 서비스의 POST /v1/matches와 같다.
##   {match_id, started_at, ended_at (unix 초), player_count, result: "win"/"lose", boss_level: 도달한 보스 레벨,
##    duration_s: 판 시작부터 끝까지 게임 속 시간(초), version: 앱 버전,
##    players: [{account_id ("" = 게스트), lane, nickname, boss_damage: 보스에게 준 피해(기여도), lane_damage: 유령 구간 레인 데미지,
##               ghost_boss_damage: 유령 구간 보스 레인 데미지, left: 판 중 이탈한 사람}]}


## room: 끝난 방(NetServer). victory: 전체 승리인가.
static func build(room: NetServer, victory: bool, ended_at: int) -> Dictionary:
	var boss: BossController = room.field.boss
	var lanes: Array = room.session.participants.duplicate()
	lanes.sort()
	var dmg: Dictionary = boss.damage_by_player
	var lane_dmg: Dictionary = boss.ghost_lane_damage_by_player()
	var boss_dmg: Dictionary = boss.ghost_boss_damage_totals()
	var players: Array = []
	for lane in lanes:
		var seat: Dictionary = room.seat_of(lane)
		players.append({
			"account_id": str(seat.get("account", "")),
			"lane": int(lane),
			"nickname": room.session.name_of(lane),
			"boss_damage": _of(dmg, lane),
			"lane_damage": _of(lane_dmg, lane),
			"ghost_boss_damage": _of(boss_dmg, lane),
			"left": bool(seat.get("left", false)),
		})
	var version := NetProtocol.game_version()
	return {
		"match_id": Crypto.new().generate_random_bytes(16).hex_encode(),
		"started_at": room.started_unix,
		"ended_at": ended_at,
		"player_count": players.size(),
		"result": "win" if victory else "lose",
		"boss_level": boss.level,
		"duration_s": snappedf(room.game_seconds, 0.1),
		"version": version if version != "" else "?",
		"players": players,
	}


## 키가 정수든 글자든 (스냅샷은 글자) 같은 값으로
static func _of(by_player: Dictionary, lane: int) -> float:
	return float(by_player.get(lane, by_player.get(str(lane), 0.0)))
