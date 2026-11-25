extends "res://tests/case_base.gd"
## 이슈 #28 요구사항 3: 동시성. 진짜 소켓으로 접속한 클라이언트들이 같은 순간에 명령을 보낸다.
## 먼저 알아 둘 설계: 타워는 "자기 레인"에만 짓는다 (명령에 대상 레인이 없다: CommandBus "남의 레인을 가리키는 명령은 존재하지 않는다").
## 그래서 이슈의 "두 사람이 같은 칸에 동시에 지으려 하면 한 명만 성공"은 이렇게 해석해서 시험한다:
##  [1] 서로 다른 두 사람이 같은 칸 좌표로 동시에 지으면 둘 다 자기 레인에 성공하고 서로의 레인을 건드리지 않는다 (경합이 없다는 것이 올바른 동작)
##  [2] 같은 사람이 같은 칸에 동시에 여러 번(더블탭, 옛 연결+새 연결) 보내면 정확히 한 번만 성공하고 나머지는 cell_not_empty 사유를 받는다. 골드는 한 번만 빠진다
##  [3] 다른 사람 이름으로 보낸 명령(사칭)은 같은 순간에 정상 명령과 섞여도 거절되고(not_your_player) 상대 레인은 그대로다
##  [4] 골드 부족 명령이 겹쳐도 마이너스가 되지 않는다: 한 건만 살 돈으로 여러 건(건설/몬스터/진화)을 동시에 보내면 한 건만 성공하고 나머지는 not_enough_gold, 골드는 0 아래로 안 간다
##  [5] 8명이 몬스터 만들기를 최대한 동시에 퍼붓는다 (보스 레인 스폰은 모두가 공유하는 자원): 성공한 만큼만 골드가 빠지고(실패는 골드를 안 쓴다), 어느 레인도 마이너스가 아니다
## 서버 쪽 골드는 프레임마다 확인한다 (스냅샷 10Hz는 사이를 놓친다).

const PORT := 47660


func run() -> void:
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = PORT
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	var clients := await _join_all(8)
	var room: NetServer = server.hub.room_for(clients[0].room_code)
	check(room != null and room.field != null and room.field.lanes.size() == 8, "8명이 한 방에서 시작했다")
	var results := {}   # client -> {seq: [ok, reason]}
	for c in clients:
		results[c] = {}
		c.command_result.connect(func(seq, ok, reason, _ev): results[c][seq] = [ok, reason])
	var gold := {"min": INF}   # 람다는 지역 변수를 값으로 잡으므로 Dictionary에 담는다
	var guard := func(): _watch_gold(room, gold)
	get_tree().process_frame.connect(guard)  # 프레임마다 서버 레인 골드의 최저값을 본다

	await _same_cell_two_players(room, clients, results)
	await _same_player_same_cell(room, clients, results)
	await _forged_mixed(room, clients, results)
	await _gold_overlap(room, clients, results)
	await _eight_player_storm(room, clients, results)

	get_tree().process_frame.disconnect(guard)
	check(gold.min >= 0.0 and gold.min < INF, "시험 내내 (프레임마다 본) 서버 레인 골드의 최저값이 0 이상이다 (%.2f)" % gold.min)
	for c in clients:
		c.queue_free()
	server.queue_free()
	await frames(4)


func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _watch_gold(room: NetServer, gold: Dictionary) -> void:
	for lane in room.field.lanes.values():
		gold.min = minf(gold.min, lane.gold)


func _join_all(n: int) -> Array:
	var clients: Array = []
	var code := ""
	for i in range(n):
		var cl := NetClient.new()
		cl.player_name = "플레이어%d" % i
		cl.join_mode = NetProtocol.MODE_CREATE if i == 0 else NetProtocol.MODE_JOIN
		cl.join_code = code
		add_child(cl)
		cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", PORT)
		await wait_until(func(): return cl.is_joined(), 8000)
		if i == 0:
			code = cl.room_code
		else:
			cl.set_ready(true)
		clients.append(cl)
	await wait_until(func(): return clients[0].lobby.get("can_start", false), 8000)
	clients[0].request_start()
	await wait_until(func(): return clients.all(func(c): return c.in_game and c.snapshot.get("lanes", {}).has(str(c.player_id))), 10000)
	return clients


## 보낸 seq들의 결과가 다 올 때까지 기다린다
func _await_results(results: Dictionary, c: NetClient, seqs: Array) -> void:
	await wait_until(func(): return seqs.all(func(s): return results[c].has(s)), 8000)


func _reasons(results: Dictionary, c: NetClient, seqs: Array) -> Array:
	return seqs.map(func(s): return "ok" if results[c].get(s, [false, "?"])[0] else results[c].get(s, [false, "?"])[1])


func _same_cell_two_players(room: NetServer, clients: Array, results: Dictionary) -> void:
	print("[1] 서로 다른 두 사람이 같은 칸에 동시에 짓는다 (레인이 따로라서 둘 다 성공)")
	var cell := Vector2i(5, 12)
	var a: NetClient = clients[0]
	var b: NetClient = clients[1]
	room.field.lanes[a.player_id].gold = 100.0
	room.field.lanes[b.player_id].gold = 100.0
	var sa := a.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": "long", "confirmed": false})
	var sb := b.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": "long", "confirmed": false})
	await _await_results(results, a, [sa])
	await _await_results(results, b, [sb])
	check(results[a][sa][0] and results[b][sb][0], "둘 다 성공했다 (각자 자기 레인): %s / %s" % [results[a][sa], results[b][sb]])
	var cost: float = Balance.tower_kind("long").cost
	var la: LaneController = room.field.lanes[a.player_id]
	var lb: LaneController = room.field.lanes[b.player_id]
	check(la.towers.size() == 1 and lb.towers.size() == 1 and la.tower_at(cell) != null and lb.tower_at(cell) != null, "각자의 레인에 타워가 정확히 하나씩 있다")
	near(la.gold, 100.0 - cost, "A의 골드는 한 번만 빠졌다")
	near(lb.gold, 100.0 - cost, "B의 골드는 한 번만 빠졌다")
	check(room.field.lanes[clients[2].player_id].towers.is_empty(), "상관없는 C의 레인에는 타워가 생기지 않았다")


func _same_player_same_cell(room: NetServer, clients: Array, results: Dictionary) -> void:
	print("[2] 같은 사람이 같은 칸에 한꺼번에 여러 번 (더블탭/옛 연결+새 연결)")
	var c: NetClient = clients[2]
	var lane: LaneController = room.field.lanes[c.player_id]
	lane.gold = 100.0
	var cell := Vector2i(7, 14)
	var seqs: Array = []
	for i in range(5):
		seqs.append(c.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": "long", "confirmed": false}))
	await _await_results(results, c, seqs)
	var reasons := _reasons(results, c, seqs)
	check(reasons.count("ok") == 1, "정확히 한 번만 성공했다: %s" % [reasons])
	check(reasons.count("cell_not_empty") == 4, "나머지 4번은 cell_not_empty 사유를 받았다")
	check(lane.towers.size() == 1, "타워는 하나뿐이다 (%d)" % lane.towers.size())
	near(lane.gold, 100.0 - float(Balance.tower_kind("long").cost), "골드는 한 번만 빠졌다")
	# 서로 다른 연결: 같은 토큰으로 다시 접속하면 옛 연결의 명령은 무시된다 (test_reconnect [3]이 자세히 본다). 여기서는 새 연결만 살아 있는지 본다
	var d: NetClient = clients[3]
	var dl: LaneController = room.field.lanes[d.player_id]
	dl.gold = 100.0
	var seqs_d: Array = []
	for i in range(3):
		seqs_d.append(d.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": "splash", "confirmed": false}))
	await _await_results(results, d, seqs_d)
	var reasons_d := _reasons(results, d, seqs_d)
	check(reasons_d.count("ok") == 1 and dl.towers.size() == 1, "다른 종류의 타워로 겹쳐 보내도 한 번만 성공한다: %s" % [reasons_d])


func _forged_mixed(room: NetServer, clients: Array, results: Dictionary) -> void:
	print("[3] 사칭 명령이 정상 명령과 섞여도 거절된다")
	var a: NetClient = clients[4]
	var victim: NetClient = clients[5]
	var cell := Vector2i(9, 16)
	var vl: LaneController = room.field.lanes[victim.player_id]
	var al: LaneController = room.field.lanes[a.player_id]
	vl.gold = 100.0
	al.gold = 100.0
	var forged := a.send_command(Command.make(Command.BUILD_TOWER, victim.player_id, {"cell": cell, "kind_id": "long", "confirmed": false}))
	var own := a.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": "long", "confirmed": false})
	var own_v := victim.send(Command.BUILD_TOWER, {"cell": cell, "kind_id": "long", "confirmed": false})
	await _await_results(results, a, [forged, own])
	await _await_results(results, victim, [own_v])
	check(results[a][forged] == [false, "not_your_player"], "A가 B 이름으로 보낸 명령은 거절된다 (%s)" % [results[a][forged]])
	check(results[a][own][0] and results[victim][own_v][0], "정상 명령은 둘 다 성공한다")
	check(vl.towers.size() == 1 and al.towers.size() == 1, "B의 레인에는 B가 지은 타워 하나만, A의 레인에는 A의 것 하나만 있다")
	near(vl.gold, 100.0 - float(Balance.tower_kind("long").cost), "B의 골드는 B의 건설 한 번만큼만 줄었다 (사칭에 쓰이지 않았다)")


func _gold_overlap(room: NetServer, clients: Array, results: Dictionary) -> void:
	print("[4] 한 건만 살 수 있는 골드로 여러 건을 동시에 보낸다")
	var c: NetClient = clients[6]
	var lane: LaneController = room.field.lanes[c.player_id]
	var tower_cost: float = Balance.tower_kind("long").cost
	var rusher_cost: float = Monsters.DATA["rusher"].cost
	var enough := maxf(tower_cost, rusher_cost)
	lane.gold = enough + 0.5      # 둘 중 비싼 것 하나 + 0.5. 둘 다 사려면 부족하다
	var gold_before := lane.gold
	var seqs: Array = []
	for i in range(4):
		seqs.append(c.send(Command.BUILD_TOWER, {"cell": Vector2i(1 + 2 * i, 18), "kind_id": "long", "confirmed": false}))
	for i in range(4):
		seqs.append(c.send(Command.SEND_MONSTER, {"kind_id": "rusher"}))
	await _await_results(results, c, seqs)
	var reasons := _reasons(results, c, seqs)
	var oks := reasons.count("ok")
	var spent := gold_before - lane.gold
	check(lane.gold >= 0.0, "골드가 마이너스가 아니다 (%.2f)" % lane.gold)
	check(oks >= 1 and reasons.count("not_enough_gold") >= 1, "일부는 성공하고 부족한 것은 not_enough_gold로 거절됐다: %s" % [reasons])
	var expected := tower_cost * lane.towers.size() + rusher_cost * (reasons.slice(4, 8).count("ok"))
	check(absf(spent - expected) < 0.001, "성공한 건만큼만 골드가 빠졌다 (빠진 %.2f, 성공 건 합 %.2f)" % [spent, expected])
	# 앞선 건이 성공하고 남은 돈으로 더 살 수 있으면 사는 것도 정상이다. 핵심은 마이너스가 없고 성공한 만큼만 차감되는 것
	room.field.lanes[c.player_id].gold = 0.0
	var seqs2: Array = [c.send(Command.BUILD_TOWER, {"cell": Vector2i(1, 20), "kind_id": "long", "confirmed": false}), c.send(Command.SEND_MONSTER, {"kind_id": "rusher"})]
	await _await_results(results, c, seqs2)
	check(_reasons(results, c, seqs2) == ["not_enough_gold", "not_enough_gold"] and lane.gold == 0.0, "골드 0에서는 전부 거절되고 골드는 0 그대로다 (%s, %.2f)" % [_reasons(results, c, seqs2), lane.gold])


func _eight_player_storm(room: NetServer, clients: Array, results: Dictionary) -> void:
	print("[5] 8명이 몬스터 만들기를 동시에 퍼붓는다 (보스 레인 스폰은 공유 자원)")
	await wait_seconds(2.0)  # 앞 시험에서 쓴 속도 제한 통(burst 30, 초당 20)이 다시 차게
	var cost: float = Monsters.DATA["rusher"].cost
	var before := {}
	for c in clients:
		var lane: LaneController = room.field.lanes[c.player_id]
		if not lane.active:
			continue
		lane.gold = 100000.0
		before[c] = lane.gold
	var boss_before: int = room.field.boss.get_sent_monsters().size()
	var seqs := {}
	for c in clients:
		seqs[c] = []
		for i in range(25):   # 속도 제한 통(30) 안
			seqs[c].append(c.send(Command.SEND_MONSTER, {"kind_id": "rusher"}))
	for c in clients:
		await _await_results(results, c, seqs[c])
	var total_ok := 0
	var fail_counts := {}
	var all_accounted := true
	var neg := false
	for c in clients:
		var reasons := _reasons(results, c, seqs[c])
		var oks := reasons.count("ok")
		total_ok += oks
		for r in reasons:
			if r != "ok":
				fail_counts[r] = fail_counts.get(r, 0) + 1
		var lane: LaneController = room.field.lanes[c.player_id]
		var spent: float = before[c] - lane.gold
		if absf(spent - cost * oks) > 0.001:
			all_accounted = false
			print("  INFO  P%d: 성공 %d건인데 빠진 골드 %.2f (기대 %.2f), 사유 %s" % [c.player_id + 1, oks, spent, cost * oks, reasons])
		if lane.gold < 0.0:
			neg = true
	check(all_accounted, "모든 레인에서 빠진 골드 = 성공한 건수 x 가격 (실패는 골드를 쓰지 않았다)")
	check(not neg, "어느 레인도 마이너스가 아니다")
	print("  INFO  8명 x 25건 중 성공 %d, 실패 사유 %s" % [total_ok, fail_counts])
	check(total_ok == 200, "골드가 넉넉하면 8명 x 25건이 전부 성공한다 (성공 %d, 실패 사유 %s)" % [total_ok, fail_counts])
	check(room.field.boss.get_sent_monsters().size() - boss_before >= 0, "보스 레인 몬스터 수가 줄지 않았다 (%d -> %d)" % [boss_before, room.field.boss.get_sent_monsters().size()])
