extends "res://tests/case_base.gd"
## 이슈 #28 요구사항 2 + 끊김/재접속 자동 재현: 가짜 네트워크 레이어(tests/net_proxy.gd)를 사이에 끼워 지연/지터/손실/갑작스런 끊김에서 판이 이어지는지 본다.
## 봇마다 자기 중계(= 자기 네트워크)를 갖는다: 한 명은 깨끗한 선, 나머지는 나쁜 선. 서버와 클라이언트 코드는 그대로고 진짜 WebSocket 위에서 돈다.
##  [1] 중계 자체: 지연을 넣으면 클라이언트가 재는 왕복(RTT)이 그만큼 늘고, 손실은 재전송 지연으로 나타난다 (TCP라 메시지는 사라지지 않는다)
##  [2] 지연 100/200/300ms + 지터 + 손실 1~5%: 판이 정상으로 이어진다 (연결 유지, 스냅샷 계속 도착, 명령 성공, 골드 마이너스 없음). 스냅샷 간격(화면 튐)을 잰다
##  [3] 갑작스런 끊김: 중계가 연결을 닫으면 클라이언트가 자동으로 같은 레인으로 돌아오고(상태가 서버와 맞다), 다른 사람은 계속 한다. 연속 끊김도 된다
##  [4] 선이 먹통(연결은 열려 있는데 아무것도 안 감): 하트비트가 끊김으로 보고, 풀리면 돌아온다
##  [5] 유예보다 오래 끊기면 이탈 처리되고 돌아오면 거부된다 (다른 사람은 계속 한다)
## 실제 시간으로 돈다(시계를 빠르게 하지 않는다): 약 1~2분. 한 줄 INFO로 구간별 수치를 남긴다.
## 허용 기준(스냅샷 간격 상한 등)은 소유자가 정하는 값이라 여기 값은 제안이다 (GAP_LIMIT_MS). 바꾸려면 이 상수만 고친다.

const Proxy := preload("res://tests/net_proxy.gd")
const PORT := 47620
const GRACE := 6.0
const HEARTBEAT := 2.0
## 제안 기준: 한 구간에서 연속한 스냅샷 사이 최대 간격(ms). 지연+재전송 지연보다 넉넉히 (서버 프레임 끊김이 섞여도 넘지 않게)
const GAP_LIMIT_MS := {"clean": 1500.0, "mobile": 2000.0, "bad": 3000.0, "worst": 4000.0}
## {지연(한쪽, ms), 지터, 손실}: 이슈 "지연 100~300ms, 지터, 손실 5%"
const PROFILES := {
	"clean": {"latency": 0.0, "jitter": 0.0, "loss": 0.0},
	"mobile": {"latency": 100.0, "jitter": 30.0, "loss": 0.01},
	"bad": {"latency": 200.0, "jitter": 60.0, "loss": 0.02},
	"worst": {"latency": 300.0, "jitter": 100.0, "loss": 0.05},
}


func run() -> void:
	await _proxy_itself()
	await _conditions()
	await _disconnects()
	Engine.time_scale = 1.0


func wait_seconds(sec: float) -> void:
	await get_tree().create_timer(sec).timeout


func _server(port: int) -> ServerMain:
	var server := ServerMain.new()
	server.use_rooms = true
	server.net_port = port
	get_tree().root.add_child.call_deferred(server)
	await frames(6)
	server.hub.reconnect_grace = GRACE
	server.hub.heartbeat_timeout = HEARTBEAT
	return server


func _own_lane(cl: NetClient) -> bool:
	return cl.snapshot.get("lanes", {}).has(str(cl.player_id))


func _profile(proxy: Node, name: String) -> void:
	var p: Dictionary = PROFILES[name]
	proxy.latency_ms = p.latency
	proxy.jitter_ms = p.jitter
	proxy.loss = p.loss


## 봇 하나: 자기 중계를 거쳐 접속한다. {bot, proxy, client, links_lost, reconnects, failed}
func _member(server_port: int, proxy_port: int, i: int, code: String) -> Dictionary:
	var proxy := Proxy.new()
	add_child(proxy)
	proxy.open(server_port, proxy_port)
	var cl := NetClient.new()
	cl.player_name = "봇%d" % i
	cl.join_mode = NetProtocol.MODE_CREATE if i == 0 else NetProtocol.MODE_JOIN
	cl.join_code = code
	cl.ping_interval = 0.5          # RTT를 자주 잰다 / 서버 하트비트(2초)보다 자주
	cl.heartbeat_timeout = 1.5
	cl.reconnect_grace = GRACE + 6.0
	add_child(cl)
	var m := {"proxy": proxy, "client": cl, "links_lost": 0, "reconnects": 0, "failed": ""}
	cl.link_lost.connect(func(): m.links_lost += 1)
	cl.reconnected.connect(func(): m.reconnects += 1)
	cl.reconnect_failed.connect(func(why): m.failed = why)
	cl.connect_to(NetTransport.DEFAULT, "127.0.0.1", proxy_port)
	var bot := NetBot.new()
	bot.is_host = i == 0
	bot.setup(cl)
	add_child(bot)
	m["bot"] = bot
	return m


## 서버 + 봇 n명(각자 중계). 모두 판에 들어간 뒤 {server, room, members}
func _game(server_port: int, n: int) -> Dictionary:
	var server := await _server(server_port)
	var members: Array = []
	var code := ""
	for i in range(n):
		var m := _member(server_port, server_port + 1 + i, i, code)
		members.append(m)
		await wait_until(func(): return m.client.is_joined(), 8000)
		if i == 0:
			code = m.client.room_code
	await wait_until(func():
		for m in members:
			m.bot.lobby_step(n)
		return members.all(func(m): return m.client.in_game and _own_lane(m.client)), 20000)
	return {"server": server, "room": server.hub.room_for(code), "members": members}


func _cleanup(g: Dictionary) -> void:
	for m in g.members:
		m.bot.queue_free()
		m.client.queue_free()
		m.proxy.queue_free()
	g.server.queue_free()
	await frames(4)


func _proxy_itself() -> void:
	print("[1] 가짜 네트워크 자체: 지연이 왕복 시간에 보이고, 손실은 재전송 지연이다")
	var g := await _game(PORT, 2)
	var m: Dictionary = g.members[1]
	var proxy: Node = m.proxy
	check(g.members.all(func(x): return x.client.in_game), "중계를 거쳐도 접속/시작이 된다 (연결 %d, 중계한 바이트 위 %d / 아래 %d)" % [proxy.accepted, proxy.bytes_up, proxy.bytes_down])
	await wait_seconds(2.0)
	var base_rtt: float = m.client.rtt_ms
	_profile(proxy, "mobile")  # 한쪽 100ms = 왕복 200ms
	await wait_seconds(4.0)
	var rtt: float = m.client.rtt_ms
	check(base_rtt >= 0.0 and rtt >= 190.0, "한쪽 100ms를 넣으면 왕복이 200ms 이상으로 잰다 (전 %.0f -> 후 %.0f ms)" % [base_rtt, rtt])
	_profile(proxy, "worst")
	var delayed0: int = proxy.delayed_chunks
	await wait_seconds(8.0)
	check(proxy.delayed_chunks > delayed0, "손실 5%%는 조각을 재전송 시간만큼 늦춘다 (지연 붙은 조각 %d개)" % (proxy.delayed_chunks - delayed0))
	check(m.client.is_joined() and m.links_lost == 0, "그래도 연결은 유지된다")
	await _cleanup(g)


func _conditions() -> void:
	print("[2] 지연/지터/손실 구간별: 판이 이어지고 화면이 크게 튀지 않는가 (실제 시간 약 1분)")
	var g := await _game(PORT + 10, 4)
	var members: Array = g.members
	var room: NetServer = g.room
	var gold := {"min": INF}   # 람다는 지역 변수를 값으로 잡으므로 Dictionary에 담는다
	var watch := func():
		for lane in room.field.lanes.values():
			gold.min = minf(gold.min, lane.gold)
	# 봇 0은 늘 깨끗한 선 (비교 기준), 1~3이 구간마다 나빠진다
	var last_ticks := {}
	for name in ["clean", "mobile", "bad", "worst"]:
		for i in range(1, members.size()):
			_profile(members[i].proxy, name)
		await wait_seconds(1.5)  # 바뀐 조건이 자리 잡을 시간
		for m in members:
			m.bot.reset_stats()
		var ticks0 := members.map(func(m): return m.client.last_tick)
		var dur := 12.0
		var t0 := Time.get_ticks_msec()
		while Time.get_ticks_msec() - t0 < dur * 1000.0:
			watch.call()
			await get_tree().process_frame
		var lines := []
		var ok := true
		for i in range(members.size()):
			var b: NetBot = members[i].bot
			lines.append("봇%d 스냅샷 %d 간격 평균 %.0f/최대 %.0f ms RTT %.0f" % [i, b.snapshots, b.average_gap_ms(), b.max_gap_ms, members[i].client.rtt_ms])
			if i >= 1 and b.max_gap_ms > GAP_LIMIT_MS[name]:
				ok = false
		print("  INFO  [%s] %s" % [name, " | ".join(lines)])
		# 서버는 바뀐 것이 없는 틱에는 변경분을 안 보낸다(조용한 구간): 받은 스냅샷 수가 아니라 클라이언트가 아는 틱이 계속 전진하는지로 본다
		var expect_ticks := int(dur * NetServer.SNAP_HZ * 0.25)
		check(members.all(func(m): return m.client.is_joined() and m.links_lost == 0), "[%s] 연결이 한 번도 끊기지 않았다" % name)
		var advanced := []
		for i in range(members.size()):
			advanced.append(members[i].client.last_tick - ticks0[i])
		check(advanced.all(func(a): return a >= expect_ticks) and members.all(func(m): return m.bot.snapshots >= 10), "[%s] 스냅샷이 계속 도착해 틱이 전진한다 (%.0f초에 틱 %s, 스냅샷 %s)" % [name, dur, advanced, members.map(func(m): return m.bot.snapshots)])
		check(ok, "[%s] 스냅샷 간격이 기준(%.0f ms) 안이다 (최대 %s)" % [name, GAP_LIMIT_MS[name], members.map(func(m): return int(m.bot.max_gap_ms))])
		# 골드가 떨어지면 서버가 not_enough_gold로 거절하는 것이 정상이다: "결과가 돌아온다"로 본다 (거절도 서버가 살아 있고 응답한다는 뜻)
		check(members.all(func(m): return m.bot.results > 0 and m.bot.results >= m.bot.sent - 4), "[%s] 보낸 명령의 결과가 서버에서 돌아온다 (보냄 %s / 결과 %s)" % [name, members.map(func(m): return m.bot.sent), members.map(func(m): return m.bot.results)])
		check(members.all(func(m): return m.bot.tick_jump_max <= 3), "[%s] 틱 번호가 크게 건너뛰지 않는다 (최대 점프 %s)" % [name, members.map(func(m): return m.bot.tick_jump_max)])
	check(gold.min >= 0.0 and gold.min < INF, "구간 내내 서버 레인 골드가 마이너스인 적이 없다 (최저 %.2f)" % gold.min)
	check(not members.any(func(m): return m.bot.negative_gold_seen), "봇이 받은 스냅샷에도 마이너스 골드가 없다")
	# 화면(클라이언트 상태)과 서버 상태가 맞는다: 선이 나빠도 결국 같은 타워/골드를 본다
	await wait_seconds(1.5)
	for i in range(members.size()):
		var lane_srv: LaneController = room.field.lanes[members[i].client.player_id]
		var lane_cl: Dictionary = members[i].client.snapshot.lanes[str(members[i].client.player_id)]
		check(lane_cl.towers.size() == lane_srv.towers.size() or absi(lane_cl.towers.size() - lane_srv.towers.size()) <= 2, "봇%d가 보는 타워 수가 서버와 맞다 (화면 %d / 서버 %d)" % [i, lane_cl.towers.size(), lane_srv.towers.size()])
	await _cleanup(g)


func _disconnects() -> void:
	print("[3~5] 갑작스런 끊김 / 먹통 / 유예 초과 (봇 3명, 각자 자기 선)")
	var g := await _game(PORT + 30, 3)
	var members: Array = g.members
	var room: NetServer = g.room
	var away := []
	var back := []
	var left := []
	room.seat_away.connect(func(l): away.append(l))
	room.seat_back.connect(func(l): back.append(l))
	room.seat_left.connect(func(l): left.append(l))
	var stable: Dictionary = members[0]
	var victim: Dictionary = members[1]
	var vlane: int = victim.client.player_id
	await wait_seconds(4.0)
	stable.bot.reset_stats()

	print("[3] 갑작스런 끊김 (한 명, 연속 3번)")
	for round in range(3):
		var towers_before: int = room.field.lanes[vlane].towers.size()
		var gold_before: float = room.field.lanes[vlane].gold
		victim.proxy.cut()
		check(await wait_until(func(): return victim.links_lost == round + 1, 8000), "끊김 %d: 클라이언트가 끊긴 것을 안다 (link_lost)" % (round + 1))
		check(await wait_until(func(): return victim.reconnects == round + 1 and _own_lane(victim.client), 15000), "끊김 %d: 자동으로 같은 레인에 돌아왔다 (재접속 %d번)" % [round + 1, victim.reconnects])
		check(victim.client.player_id == vlane and room.field.lanes[vlane].active, "끊김 %d: 같은 레인(P%d)이고 레인은 살아 있다" % [round + 1, vlane + 1])
		check(room.field.lanes[vlane].towers.size() >= towers_before, "끊김 %d: 끊긴 동안에도 서버 레인은 유지됐다 (타워 %d -> %d)" % [round + 1, towers_before, room.field.lanes[vlane].towers.size()])
		check(room.field.lanes[vlane].gold >= 0.0 and gold_before >= 0.0, "끊김 %d: 골드는 마이너스가 아니다" % (round + 1))
		await wait_seconds(1.5)
		var snap_lane: Dictionary = victim.client.snapshot.lanes[str(vlane)]
		check(absi(snap_lane.towers.size() - room.field.lanes[vlane].towers.size()) <= 2, "끊김 %d: 돌아온 화면의 타워 수가 서버와 맞다 (화면 %d / 서버 %d)" % [round + 1, snap_lane.towers.size(), room.field.lanes[vlane].towers.size()])
		var results_before: int = victim.bot.results
		await wait_seconds(3.0)
		check(victim.bot.results > results_before, "끊김 %d: 돌아온 뒤 명령의 결과가 다시 돌아온다" % (round + 1))
	check(away == [vlane, vlane, vlane] and back == [vlane, vlane, vlane] and left.is_empty(), "서버: 끊김 3번 = 유예 3번, 복귀 3번, 이탈 없음 (%s / %s / %s)" % [away, back, left])
	check(stable.links_lost == 0 and stable.bot.snapshots > 0 and room.field.lanes[stable.client.player_id].active, "그동안 다른 사람(봇0)은 끊김 없이 계속 했다")

	print("[4] 선이 먹통: 연결은 열려 있는데 아무것도 안 간다")
	away.clear()
	back.clear()
	var lost0: int = victim.links_lost
	var re0: int = victim.reconnects
	victim.proxy.freeze(true)
	check(await wait_until(func(): return victim.links_lost == lost0 + 1, 10000), "먹통이면 클라이언트 하트비트가 끊김으로 본다 (조용한 시간 %.1f초 기준)" % victim.client.heartbeat_timeout)
	check(await wait_until(func(): return away.has(vlane), 10000), "서버 하트비트도 그 사람을 끊김(유예)으로 본다")
	victim.proxy.freeze(false)
	check(await wait_until(func(): return victim.reconnects == re0 + 1 and _own_lane(victim.client), 20000), "선이 풀리면 같은 레인으로 돌아온다")
	check(back.has(vlane) and left.is_empty(), "서버: 복귀로 처리됐고 이탈은 없다")

	print("[5] 유예보다 오래 끊기면 이탈")
	var lost1: int = victim.links_lost
	victim.proxy.refusing = true
	victim.proxy.cut()
	check(await wait_until(func(): return left.has(vlane), int((GRACE + 8.0) * 1000)), "유예(%.0f초)가 지나면 서버가 이탈로 처리한다" % GRACE)
	check(not room.field.lanes[vlane].active, "이탈한 사람의 레인은 무너졌다")
	victim.proxy.refusing = false
	check(await wait_until(func(): return victim.failed != "", 20000), "돌아와도 자리가 없다: 클라이언트가 포기한다 (사유 %s)" % victim.failed)
	check(victim.failed in ["seat_released", "grace_expired"], "사유는 이탈된 자리(seat_released)나 클라이언트 유예 끝(grace_expired)이다")
	check(stable.links_lost == 0 and room.field.lanes[stable.client.player_id].active and not room.finished, "그래도 남은 사람의 판은 계속 돈다")
	await _cleanup(g)
