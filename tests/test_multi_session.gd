extends "res://tests/case_base.gd"
## 이슈 #22: 다인원 세션 (로비, 레인 배정, 인원별 보스 체력, 탈락 규칙, 닉네임).
##  [1] Lobby 규칙: 입장 순서대로 빈 레인 / 가득 참 / 시작 뒤 입장 거부 / 첫 입장 기준 30초 자동 시작(2명 이상만)
##  [2] 닉네임: 형용사+명사 자동 생성, 정리(제어문자/길이/공백), 중복 구별
##  [3] 인원별 보스 체력: 1명은 지금 값, 인원당 +BOSS_HP_PER_EXTRA_PLAYER, 시작 인원으로 고정
##  [4] 레인이 무너지면: 그 사람만 탈락(명령 불가, 관전 가능) + 보스 레인의 그 사람 몬스터 철수 + 기여도 보존 / 전원 탈락이면 패배
##  [5] 네트워크 로비: 접속 순서 레인, 닉네임 중복 구별, 시간이 되면 자동 시작, 시작 뒤 입장 거부, 시작 전 명령 거절, 스냅샷의 이름
##  [6] 나가면 자리가 빈다 / 혼자 기다리면 시작하지 않는다
## (폰 실기기/실제 지연은 보지 않는다: #28. 로비 화면 그림은 눈으로 확인해야 한다)

const PORT_BASE := 47240


func run() -> void:
	_lobby_rules()
	_nicknames()
	await _boss_scaling()
	await _lane_fall()
	await _net_lobby()
	await _net_auto_start()
	await _net_solo()
	await _screens()
	await _main_game_screens()
	Engine.time_scale = 1.0


# ---- [1] 로비 규칙 ---------------------------------------------------------

func _lobby_rules() -> void:
	print("[1] 로비 규칙")
	var lobby := Lobby.new()
	check(lobby.join(10, "a").lane == 0 and lobby.join(11, "b").lane == 1 and lobby.join(12, "c").lane == 2, "들어온 순서대로 0,1,2번 레인")
	lobby.leave(11)
	check(lobby.join(13, "d").lane == 1, "나간 자리(가장 작은 빈 레인)를 다음 사람이 쓴다")
	lobby.leave(10)
	check(lobby.lanes() == [1, 2] and lobby.names_by_lane() == {1: "d", 2: "c"}, "레인 목록은 작은 번호부터 %s" % [lobby.lanes()])
	check(lobby.view().members.map(func(m): return m.lane) == [1, 2] and not lobby.view().members[0].has("host") and not lobby.view().members[0].has("ready"), "화면용 상태에는 방장/준비가 없다")

	var full := Lobby.new()
	for i in range(Balance.MAX_PLAYERS):
		full.join(100 + i, "p%d" % i)
	var over := full.join(999, "late")
	check(full.size() == Balance.MAX_PLAYERS and not over.ok and over.reason == NetProtocol.REJECT_FULL, "%d명이 차면 room_full" % Balance.MAX_PLAYERS)
	var cap := Lobby.new()
	cap.max_players = 2
	cap.join(1, "a")
	cap.join(2, "b")
	check(cap.join(3, "c").reason == NetProtocol.REJECT_FULL, "최대 인원을 줄이면 그만큼만 들어온다")

	var t := Lobby.new()
	t.join(1, "first")
	check(absf(t.countdown_left - Balance.LOBBY_AUTO_START_SEC) < 0.001, "첫 입장에서 %.0f초 시계가 시작된다" % Balance.LOBBY_AUTO_START_SEC)
	t.tick(Balance.LOBBY_AUTO_START_SEC - 1.0)
	check(not t.tick(0.5), "혼자면 시간이 다 돼도 시작하지 않고 기다린다 (자동 시작은 2명 이상만)")
	t.tick(10.0)
	check(near_zero(t.countdown_left) and t.phase == Lobby.Phase.OPEN, "혼자일 때 시간은 0에서 멈춘다")
	t.join(2, "guest")
	check(absf(t.countdown_left - Balance.LOBBY_AUTO_START_SEC) < 0.001, "혼자 기다리다 두 번째가 들어오면 그때부터 다시 %.0f초" % Balance.LOBBY_AUTO_START_SEC)
	check(not t.tick(Balance.LOBBY_AUTO_START_SEC - 1.0), "30초 전에는 시작하지 않는다")
	check(t.tick(1.0) and t.phase == Lobby.Phase.STARTING, "시간이 지나면 자동 시작 (2명)")
	var late := t.join(5, "late")
	check(not late.ok and late.reason == NetProtocol.REJECT_STARTED, "시작한 뒤에는 입장 거부 (already_started)")
	check(not t.tick(1.0), "시작은 한 번만 알린다")

	var early := Lobby.new()
	early.join(1, "first")
	early.tick(20.0)
	early.join(2, "second")
	check(early.countdown_left > 9.0 and early.countdown_left < 11.0, "시계는 첫 입장부터 간다: 20초 뒤 입장하면 남은 시간은 약 10초 (%.1f)" % early.countdown_left)
	check(not early.tick(5.0), "남은 시간 전에는 시작하지 않는다 (준비/시작 버튼 같은 조기 시작이 없다)")
	check(early.tick(6.0), "첫 입장 기준 30초가 지나면 시작")

	var gone := Lobby.new()
	gone.join(1, "a")
	gone.leave(1)
	check(gone.countdown_left < 0.0, "모두 나가면 시계가 꺼진다")
	gone.join(2, "b")
	check(absf(gone.countdown_left - Balance.LOBBY_AUTO_START_SEC) < 0.001, "다음 첫 입장이 시계를 다시 시작한다")
	var shrink := Lobby.new()
	shrink.join(1, "a")
	shrink.join(2, "b")
	shrink.tick(10.0)
	shrink.leave(2)
	shrink.join(3, "c")
	check(shrink.countdown_left < Balance.LOBBY_AUTO_START_SEC - 9.0, "중간에 나가고 들어와도 시계는 계속 간다 (%.1f)" % shrink.countdown_left)


func near_zero(x: float) -> bool:
	return absf(x) < 0.0001


# ---- [2] 닉네임 ------------------------------------------------------------

func _nicknames() -> void:
	print("[2] 닉네임")
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var seen := {}
	var shape_ok := true
	for i in range(40):
		var n := Nicknames.generate(rng)
		seen[n] = true
		var found := false
		for adj in Nicknames.ADJECTIVES:
			if n.begins_with(adj) and Nicknames.NOUNS.has(n.substr(adj.length())):
				found = true
		shape_ok = shape_ok and found and n.length() <= Balance.NICKNAME_MAX_LENGTH
	check(shape_ok, "자동 이름은 형용사+명사이고 최대 길이 안이다")
	check(seen.size() > 10, "여러 가지가 나온다 (%d종/40번)" % seen.size())
	check(Nicknames.sanitize("  아름다운   사과  ") == "아름다운 사과", "앞뒤/연속 공백 정리")
	check(Nicknames.sanitize("a" + String.chr(10) + "b" + String.chr(9) + "c" + String.chr(1) + "d") == "abcd", "제어문자 제거")
	check(Nicknames.sanitize("x" + String.chr(0x202E) + "y") == "xy", "글자 방향 뒤집기 문자 제거")
	check(Nicknames.sanitize("가".repeat(50)).length() == Balance.NICKNAME_MAX_LENGTH, "너무 길면 %d글자로" % Balance.NICKNAME_MAX_LENGTH)
	check(Nicknames.sanitize("   ") == "", "공백뿐이면 빈 이름")
	check(Nicknames.unique("민수", ["철수"]) == "민수", "안 겹치면 그대로")
	check(Nicknames.unique("민수", ["민수"]) == "민수2" and Nicknames.unique("민수", ["민수", "민수2"]) == "민수3", "겹치면 뒤에 숫자")
	var long_name := "가".repeat(Balance.NICKNAME_MAX_LENGTH)
	var u := Nicknames.unique(long_name, [long_name])
	check(u != long_name and u.length() <= Balance.NICKNAME_MAX_LENGTH, "긴 이름이 겹쳐도 길이 제한 안 (%s)" % u)
	var auto := Nicknames.unique("", [], rng)
	check(auto != "" and auto.length() <= Balance.NICKNAME_MAX_LENGTH, "비면 자동 생성 (%s)" % auto)


# ---- 공통: 필드 만들기 -----------------------------------------------------

func _make_field(players: int) -> GameField:
	var field := (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	field.session.participants.clear()
	for i in range(players):
		field.session.participants.append(i)
	field.session.rng.seed = 3
	field.play_effects = false
	get_tree().root.add_child.call_deferred(field)
	await wait_until(func(): return field.boss != null, 5000)
	return field


# ---- [3] 인원별 보스 체력 --------------------------------------------------

func _boss_scaling() -> void:
	print("[3] 인원별 보스 체력")
	check(is_equal_approx(Balance.BOSS_HP_PER_EXTRA_PLAYER, 1.1), "한 명 늘 때마다 +110% (Balance)")
	var base_hp := float(BossLevels.get_level(1).hp)
	for n in [1, 2, 8]:
		var field := await _make_field(n)
		var expect: float = base_hp * (1.0 + Balance.BOSS_HP_PER_EXTRA_PLAYER * (n - 1))
		near(field.boss.max_hp, expect, "%d명 판 Lv.1 보스 체력" % n)
		if n == 1:
			near(field.boss.max_hp, base_hp, "1명 판은 레벨 데이터 그대로 (배율 1.0)")
		field.queue_free()
		await frames(3)
	var two := await _make_field(2)
	two.bus.execute(Command.make(Command.START_GAME, 0, {}))
	var hp_before := two.boss.max_hp
	two.lanes[1].lives = 0.0
	two.lanes[1].shutdown()
	two.lanes[1].lane_failed.emit(1)
	check(not two.lanes[1].active and two.boss.state == BossController.State.RUNNING, "한 명이 무너져도 판은 이어진다")
	check(two.boss.max_hp == hp_before, "탈락해도 이미 정해진 보스 체력은 그대로")
	two.boss._start_level(2)  # 다음 보스도 시작 인원(2명) 기준이다
	near(two.boss.max_hp, float(BossLevels.get_level(2).hp) * (1.0 + Balance.BOSS_HP_PER_EXTRA_PLAYER), "탈락 뒤 다음 보스도 시작 인원 기준 체력")
	two.queue_free()
	await frames(3)


# ---- [4] 레인이 무너졌을 때 ------------------------------------------------

func _lane_fall() -> void:
	print("[4] 레인 붕괴: 탈락 + 몬스터 철수 + 관전")
	var field := await _make_field(3)
	var boss := field.boss
	field.bus.execute(Command.make(Command.START_GAME, 0, {}))
	# 보스 레인에 P0 2마리, P1 1마리를 보내 둔다
	boss.spawn_player_monster(0, "warrior")
	boss.spawn_player_monster(0, "warrior")
	boss.spawn_player_monster(1, "warrior")
	boss.damage_by_player[0] = 123.0
	var sent_before := boss.get_sent_monsters().size()
	check(sent_before == 3, "(준비) 보스 레인에 3마리 %d" % sent_before)
	var max_before := boss.max_hp

	field.lanes[0].lives = 0.0
	field.lanes[0].shutdown()
	field.lanes[0].lane_failed.emit(0)
	var owners := boss.get_sent_monsters().map(func(m): return m.owner_id)
	check(owners == [1], "P0이 무너지면 P0의 몬스터가 보스 레인에서 바로 철수한다 (남은 주인: %s)" % [owners])
	check(boss.get_attackers().all(func(m): return m.owner_id != 0), "공격 중인 몬스터에도 P0 것이 없다")
	check(boss.state == BossController.State.RUNNING and field.lanes[1].active and field.lanes[2].active, "나머지는 계속 한다")
	near(boss.damage_by_player.get(0, 0.0), 123.0, "탈락자의 이미 낸 기여도는 남는다")
	check(boss.max_hp == max_before, "난이도(보스 체력)는 시작 인원 그대로")
	check(field.snapshot(true).lanes.has("0") and not field.snapshot(true).lanes["0"].active, "탈락 레인도 스냅샷에 남아 있어 관전할 수 있다 (active=false)")
	var build := field.bus.execute(Command.make(Command.BUILD_TOWER, 0, {"cell": Vector2i(5, 10), "kind_id": "long", "confirmed": false}))
	check(not build.ok, "탈락자는 건설 명령이 거절된다 (%s)" % build.reason)
	var send := field.bus.execute(Command.make(Command.SEND_MONSTER, 0, {"kind_id": "warrior"}))
	check(not send.ok, "탈락자는 몬스터를 더 보낼 수 없다 (%s)" % send.reason)
	var other := field.bus.execute(Command.make(Command.BUILD_TOWER, 1, {"cell": Vector2i(5, 10), "kind_id": "long", "confirmed": false}))
	check(other.ok, "살아 있는 사람은 그대로 건설한다")
	check(field.lanes[1].tower_at(Vector2i(5, 10)) != null and field.lanes[0].tower_at(Vector2i(5, 10)) == null, "타워는 자기 레인에만 생긴다")
	# 다음 보스 라운드의 웨이브 파견은 살아 있는 레인에만 간다
	check(boss.state == BossController.State.RUNNING, "(계속) 보스 진행 중")

	field.lanes[1].shutdown()
	field.lanes[1].lane_failed.emit(1)
	check(boss.state == BossController.State.RUNNING, "두 명이 무너져도 한 명이 남으면 계속")
	field.lanes[2].shutdown()
	field.lanes[2].lane_failed.emit(2)
	check(boss.state == BossController.State.DEFEAT, "모든 참여 레인이 무너지면 전체 패배")
	field.queue_free()
	await frames(3)


# ---- [5] 네트워크 로비 -----------------------------------------------------

func _server(port: int, auto_sec: float, max_players: int = 8) -> ServerMain:
	var server := ServerMain.new()
	server.use_lobby = true
	server.net_port = port
	server.lobby_auto_start_sec = auto_sec
	server.lobby_max_players = max_players
	server.session.rng.seed = 9
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	return server


func _client(player_name: String, port: int) -> NetClient:
	var cl := NetClient.new()
	cl.player_name = player_name
	add_child(cl)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", port)
	return cl


func _net_lobby() -> void:
	print("[5] 네트워크 로비")
	var port := PORT_BASE
	var server := await _server(port, 3.0)
	var net: NetServer = server.net
	check(net != null and net.peer != null and server.field == null, "로비 서버가 열렸고 판(필드)은 아직 없다")
	var a := _client("철수", port)
	await wait_until(func(): return a.is_joined(), 8000)
	var b := _client("철수", port)  # 같은 이름
	await wait_until(func(): return b.is_joined(), 8000)
	var c := _client("", port)       # 이름 없음
	await wait_until(func(): return c.is_joined(), 8000)
	check(a.player_id == 0 and b.player_id == 1 and c.player_id == 2, "접속 순서대로 레인 0,1,2 (%d,%d,%d)" % [a.player_id, b.player_id, c.player_id])
	check(a.my_name == "철수" and b.my_name != "철수" and b.my_name.begins_with("철수"), "같은 이름은 서버가 구별해 준다 (%s / %s)" % [a.my_name, b.my_name])
	check(c.my_name != "" and c.my_name.length() <= Balance.NICKNAME_MAX_LENGTH, "이름이 없으면 자동 생성 (%s)" % c.my_name)
	await wait_until(func(): return a.lobby.get("members", []).size() == 3 and c.lobby.get("members", []).size() == 3, 5000)
	var members: Array = a.lobby.get("members", [])
	check(members.size() == 3 and a.lobby.get("max", 0) == 8, "로비 상태에 참여자 3명과 최대 인원")
	check(a.lobby.get("countdown", -1.0) > 0.0 and a.lobby.get("countdown", 99.0) <= 3.0, "로비 상태에 자동 시작까지 남은 시간 (%.1f)" % a.lobby.get("countdown", -1.0))
	check(not members[0].has("host") and not members[0].has("ready"), "방장/준비 개념이 없다")
	var names_ok: bool = members.map(func(m): return m.name) == [a.my_name, b.my_name, c.my_name]
	check(names_ok, "로비 목록의 이름이 각자 받은 이름과 같다")

	# 시작 전 명령은 거절
	var seq_hold := {}
	a.command_result.connect(func(seq, ok, reason, _ev): seq_hold[seq] = [ok, reason])
	var s0 := a.send(Command.BUILD_TOWER, {"cell": Vector2i(5, 10), "kind_id": "long", "confirmed": false})
	await wait_until(func(): return seq_hold.has(s0), 5000)
	check(seq_hold.get(s0, [true, ""]) == [false, "not_started"], "로비에서 온 건설 명령은 거절 (%s)" % [seq_hold.get(s0)])
	check(not a.in_game and server.field == null, "시간이 되기 전에는 로비다")

	# 시간이 되면 모두 동시에 시작
	var started := {}
	for cl in [a, b, c]:
		cl.game_started.connect(func(players, names): started[cl.player_id] = [players, names])
	var begun := await wait_until(func(): return started.size() == 3, 12000)
	check(begun, "첫 입장 뒤 시간이 지나면 모두가 started를 받는다")
	check(started.get(0, [[]])[0] == [0, 1, 2], "참여자(레인)가 접속자로 확정됐다 %s" % [started.get(0, [[]])[0]])
	check(server.session.participants == [0, 1, 2] and server.field != null and server.field.lanes.size() == 3, "서버 시뮬레이션에 레인이 3개만 만들어졌다")
	check(server.field.bus.started and server.field.boss.state == BossController.State.RUNNING, "모든 레인과 보스가 동시에 시작했다")
	near(server.field.boss.max_hp, float(BossLevels.get_level(1).hp) * (1.0 + Balance.BOSS_HP_PER_EXTRA_PLAYER * 2), "3명 판 보스 체력")
	var names: Dictionary = started.get(1, [[], {}])[1]
	check(names.get("0") == a.my_name and names.get("1") == b.my_name and names.get("2") == c.my_name, "started에 레인별 닉네임이 있다")
	var got_snap := await wait_until(func(): return c.snapshot.has("names") and c.snapshot.lanes.has("2"), 8000)
	check(got_snap and c.snapshot.names.get("0") == a.my_name and c.snapshot.names.get("2") == c.my_name, "스냅샷에 닉네임이 실려 온다")
	check(c.snapshot.lanes.has("2") and not c.snapshot.lanes.has("5"), "참여하지 않은 레인은 스냅샷에 없다")

	# 시작 뒤 입장 거부
	var late := _client("늦은사람", port)
	var reject := {}
	late.rejected.connect(func(reason, _info): reject["reason"] = reason)
	await wait_until(func(): return not reject.is_empty(), 8000)
	check(reject.get("reason", "") == NetProtocol.REJECT_STARTED, "시작한 뒤의 입장은 already_started로 거부 (%s)" % [reject.get("reason")])
	check(net.joined_count() == 3, "거부된 연결이 자리를 쓰지 않았다")

	# 시작 뒤에는 명령이 된다 (자기 레인에만)
	var res := {}
	b.command_result.connect(func(seq, ok, reason, _ev): res[seq] = [ok, reason])
	var s1 := b.send(Command.BUILD_TOWER, {"cell": Vector2i(7, 12), "kind_id": "long", "confirmed": false})
	await wait_until(func(): return res.has(s1), 5000)
	check(res.get(s1, [false])[0] and server.field.lanes[1].tower_at(Vector2i(7, 12)) != null and server.field.lanes[0].tower_at(Vector2i(7, 12)) == null, "시작 뒤 B의 건설은 B 레인에만 생긴다")
	for cl in [a, b, c, late]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [6] 로비에서 나가기 -----------------------------------------------------

func _net_auto_start() -> void:
	print("[6] 로비에서 나가면 자리가 빈다")
	var port := PORT_BASE + 3
	var server := await _server(port, 60.0, 2)
	var a := _client("a", port)
	await wait_until(func(): return a.is_joined(), 8000)
	var b := _client("b", port)
	await wait_until(func(): return b.is_joined(), 8000)
	var c := _client("c", port)
	var full := {}
	c.rejected.connect(func(reason, _info): full["reason"] = reason)
	await wait_until(func(): return not full.is_empty(), 8000)
	check(full.get("reason", "") == NetProtocol.REJECT_FULL, "최대 인원(2)이면 room_full")
	b.close()
	await wait_until(func(): return a.lobby.get("members", []).size() == 1, 8000)
	check(a.lobby.get("members", []).size() == 1, "나간 사람이 로비 목록에서 사라진다")
	var d := _client("d", port)
	await wait_until(func(): return d.is_joined(), 8000)
	check(d.player_id == 1, "빈 레인을 다음 사람이 쓴다 (레인 %d)" % d.player_id)
	for cl in [a, b, c, d]:
		cl.queue_free()
	server.queue_free()
	await frames(4)


# ---- [7] 혼자 기다리기 -------------------------------------------------------

func _net_solo() -> void:
	print("[7] 혼자 로비에 있으면 시간이 지나도 시작하지 않는다 (둘째가 들어오면 그때부터 다시 센다)")
	var port := PORT_BASE + 4
	var server := await _server(port, 1.5)
	var a := _client("", port)
	await wait_until(func(): return a.is_joined(), 8000)
	await wait_seconds(2.5)
	check(not a.in_game and server.field == null and not server.net.game_started, "혼자일 때는 시간이 다 돼도 로비다")
	var b := _client("", port)
	await wait_until(func(): return b.is_joined(), 8000)
	await wait_seconds(0.5)
	check(not a.in_game, "둘째가 들어온 직후에는 아직 시작하지 않는다 (시계가 다시 시작)")
	var ok := await wait_until(func(): return a.in_game and b.in_game, 8000)
	check(ok and a.players == [0, 1], "둘째가 들어온 뒤 시간이 지나면 둘이 시작한다 %s" % [a.players])
	a.queue_free()
	b.queue_free()
	server.queue_free()
	await frames(4)


func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


# ---- [8] 화면 ---------------------------------------------------------------

func _screens() -> void:
	print("[8] 로비 화면")
	var view := {"members": [
		{"lane": 0, "name": "아름다운사과"},
		{"lane": 1, "name": "더러운컴퓨터"},
		{"lane": 2, "name": "졸린감자"}], "max": 8, "countdown": 12.3}
	check(LobbyScreen.row_text(view.members[0], true) == "1  아름다운사과  ◀ 나", "로비 줄: 레인 번호, 닉네임, 나")
	check(LobbyScreen.row_text(view.members[1], false) == "2  더러운컴퓨터", "로비 줄: 다른 사람")
	check(LobbyScreen.countdown_text(12.3, 3) == "13초 뒤 자동 시작" and LobbyScreen.countdown_text(-1.0, 1) == "", "카운트다운 문구")
	check(LobbyScreen.countdown_text(0.0, 1).begins_with("다른 사람을 기다리는 중"), "혼자 시간이 다 되면 기다리는 중 문구")
	var screen := LobbyScreen.new()
	add_child(screen)
	var fake := NetClient.new()
	fake.player_id = 1
	screen.client = fake
	screen.show_lobby(view)
	check(screen._title.text == "대기실 3/8", "제목에 인원")
	check(screen._countdown.text == "13초 뒤 자동 시작", "화면에 남은 시간")
	await frames(2)
	check(screen._list.get_child_count() == 3, "참여자 3줄")
	var buttons := screen.find_children("*", "Button", true, false)
	check(buttons.size() == 1 and buttons[0].text == "나가기", "버튼은 [나가기]뿐이다 (준비/시작 없음)")
	fake.free()
	screen.queue_free()
	await frames(2)


## MainGame(화면)을 3명 판으로 띄워서 결과 화면과 미니맵이 닉네임/탈락을 쓰는지 본다
func _main_game_screens() -> void:
	print("[9] 화면: 결과 화면의 모든 참여자 + 미니맵 닉네임")
	var game := (load("res://scenes/main/MainGame.tscn") as PackedScene).instantiate()
	var found := game.find_children("*", "GameField", true, false)
	check(found.size() == 1, "(준비) MainGame 안의 GameField")
	var gf: GameField = found[0]
	gf.session.participants.clear()
	for i in range(3):
		gf.session.participants.append(i)
	gf.session.names = {0: "아름다운사과", 1: "더러운컴퓨터", 2: "졸린감자"}
	gf.session.local_player_id = 1
	get_tree().root.add_child.call_deferred(game)
	await wait_until(func(): return gf.boss != null and game.is_inside_tree(), 5000)
	await frames(10)
	gf.bus.execute(Command.make(Command.START_GAME, 1, {}))
	gf.boss.damage_by_player[0] = 300.0
	gf.boss.damage_by_player[1] = 100.0
	gf.lanes[2].lives = 0.0
	gf.lanes[2].shutdown()
	gf.lanes[2].lane_failed.emit(2)
	await frames(10)  # 미니맵이 몇 번 그려진다 (스크립트 오류가 나면 여기서 터진다)
	var stats: Dictionary = game._collect_game_stats(false)
	var list: Array = stats.get("contributions", [])
	check(list.size() == 3, "결과의 기여도에 참여자 3명이 모두 있다 (한 번도 못 친 사람 포함) %d" % list.size())
	check(list.size() == 3 and list[0].name == "아름다운사과" and list[0].damage == 300.0 and absf(list[0].percent - 75.0) < 0.01, "닉네임과 기여도 비율 (%s)" % [list[0] if list.size() > 0 else {}])
	check(list.size() == 3 and list[2].name == "졸린감자" and list[2].eliminated and list[1].me, "탈락 표시와 '나' 표시")
	game.game_over_screen.show_result(false, stats)
	var text: String = game.game_over_screen.contribution_label.text
	check(text.contains("아름다운사과") and text.contains("더러운컴퓨터") and text.contains("졸린감자") and text.contains("탈락"), "결과 화면 글에 닉네임과 탈락이 나온다")
	check(game.minimap_views.has(2) and game.minimap_views[2].size.x > 0.0, "미니맵이 만들어져 있다")
	game.queue_free()
	await frames(3)
