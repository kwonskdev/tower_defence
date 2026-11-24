extends "res://tests/case_base.gd"
## 이슈 #20: 스냅샷을 변경분(SnapshotDelta)으로 보내면 대역폭이 얼마가 되는가, 그리고 변경분을 적용하면 원래 스냅샷이 그대로 복원되는가.
## 최악에 가까운 판: 8명이 각자 타워 30기, 보스 레인에 몬스터 300마리가 몰려 서 있는 상황 (보스는 안 죽게 한다).
## 숫자를 출력하고, 넉넉한 상한만 검사한다 (예산 값은 #20에서 정한 것: 아래 BUDGET_*). 1000마리일 때의 수치는 이슈 #20 코멘트에 적혀 있다.

const DEFAULT_MONSTERS := 300           # 인자 --monsters=N으로 바꿔 돌릴 수 있다 (더 큰 수치를 잴 때)
const BUDGET_SETTLED_BASE := 3000        # 몬스터가 서 있는 보스 레인을 보는 클라이언트: 틱당 변경분 바이트 상한 = 이 값 + 몬스터 수 (서 있는 몬스터는 거의 0바이트라 몬스터 수에는 거의 안 늘어난다)
const BUDGET_OWN_FULL := 24000           # 자기 레인 + 보스 상태 전체(키프레임)


func run() -> void:
	var MONSTERS := int(ServerMain.arg_value("monsters", str(DEFAULT_MONSTERS)))
	var seconds := float(ServerMain.arg_value("secs", "9"))
	var field := (load("res://scenes/ui/GameField.tscn") as PackedScene).instantiate() as GameField
	field.session.participants = [0, 1, 2, 3, 4, 5, 6, 7]
	field.play_effects = false
	get_tree().root.add_child.call_deferred(field)
	await frames(8)
	field.boss.max_hp = 1e15
	field.boss.hp = 1e15
	for pid in field.session.participants:
		field.lanes[pid].gold = 1e9
	field.bus.execute(Command.make(Command.START_GAME, 0, {}))
	for pid in field.session.participants:
		for i in range(30):
			field.bus.execute(Command.make(Command.BUILD_TOWER, pid, {"cell": Vector2i(1 + (i % 6) * 2, 8 + (i / 6) * 2), "kind_id": "long", "confirmed": false}))
	var sent := 0
	for i in range(MONSTERS):
		if field.bus.execute(Command.make(Command.SEND_MONSTER, i % 8, {"kind_id": "rusher"}))["ok"]:
			sent += 1
	check(sent == MONSTERS, "(준비) 보스 레인으로 몬스터 %d마리 파견" % sent)

	# 보는 곳이 다른 두 클라이언트: 보스 레인을 보는 쪽(boss)과 자기 레인을 보는 쪽(own)
	var views := {"boss": GameField.BOSS_LANE_ID, "own": 0}
	var prev := {}
	var prev_q := {}
	var t_last := 0.0
	var started_ms := Time.get_ticks_msec()
	var samples := {"boss": [], "own": []}  # [경과 초, 변경분 바이트, 서 있는 몬스터 수]
	var roundtrip_ok := true
	var cost_build_us := 0
	var cost_quant_us := 0
	var cost_diff_us := 0
	var cost_n := 0
	var first_full := {}
	while float(Time.get_ticks_msec() - started_ms) < seconds * 1000.0:
		await get_tree().process_frame
		for pid in field.session.participants:
			field.lanes[pid].gold = 1e9
		var now := float(Time.get_ticks_msec() - started_ms) / 1000.0
		if now - t_last < 0.1:
			continue
		t_last = now
		var t0 := Time.get_ticks_usec()
		var raw := field.snapshot(true)
		var t1 := Time.get_ticks_usec()
		var q := SnapshotDelta.quantize(raw)
		cost_build_us += t1 - t0
		cost_quant_us += Time.get_ticks_usec() - t1
		cost_n += 1
		var stopped := 0
		for m in q.boss.monsters:
			if m.stopped:
				stopped += 1
		# 서버와 같은 경로: 틱당 전체 변경분을 한 번 계산하고, 클라이언트별로 자른다
		var t2 := Time.get_ticks_usec()
		var world_delta := SnapshotDelta.diff(prev_q, q) if not prev_q.is_empty() else {}
		cost_diff_us += Time.get_ticks_usec() - t2
		prev_q = q
		for who in views:
			var cur := NetServer.slice_for(q, 0, views[who])
			var cur_json: Dictionary = JSON.parse_string(JSON.stringify(cur))
			if prev.has(who):
				var d := NetServer.slice_delta(world_delta, 0, views[who])
				var d_text := JSON.stringify(d)
				var rebuilt := SnapshotDelta.apply(JSON.parse_string(JSON.stringify(prev[who])), JSON.parse_string(d_text))
				if _norm(rebuilt) != _norm(cur_json):
					roundtrip_ok = false
				samples[who].append([now, d_text.length(), stopped, d_text.to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE).size()])
			else:
				first_full[who] = JSON.stringify(cur).length()
				first_full[who + "_deflate"] = JSON.stringify(cur).to_utf8_buffer().compress(FileAccess.COMPRESSION_DEFLATE).size()
			prev[who] = cur
	print("  서버 비용(틱당 평균): 스냅샷 만들기 %.2fms + 거칠게 하기 %.2fms + 전체 변경분 계산 %.2fms (틱당 한 번, 클라이언트 수와 무관) (몬스터 %d마리)" % [cost_build_us / 1000.0 / cost_n, cost_quant_us / 1000.0 / cost_n, cost_diff_us / 1000.0 / maxi(1, cost_n - 1), MONSTERS])
	check(roundtrip_ok, "변경분을 적용하면 원래 스냅샷이 그대로 복원된다 (%d번 비교)" % (samples.boss.size() + samples.own.size()))

	var settled: Array = samples.boss.filter(func(s): return s[2] == MONSTERS and s[0] > 5.0)
	var moving: Array = samples.boss.filter(func(s): return s[2] < MONSTERS)
	check(not settled.is_empty(), "몬스터가 모두 보스 앞에 서는 데까지 걸린 시간 안에 측정했다 (서 있는 틱 %d개, 이동 중 틱 %d개)" % [settled.size(), moving.size()])
	var settled_max := 0
	var settled_sum := 0
	for s in settled:
		settled_max = maxi(settled_max, s[1])
		settled_sum += s[1]
	var moving_max := 0
	for s in moving:
		moving_max = maxi(moving_max, s[1])
	var moving_deflate_max := 0
	for s in moving:
		moving_deflate_max = maxi(moving_deflate_max, s[3])
	var settled_deflate_sum := 0
	for s in settled:
		settled_deflate_sum += s[3]
	var own_max := 0
	var own_sum := 0
	for s in samples.own:
		own_max = maxi(own_max, s[1])
		own_sum += s[1]
	var own_avg := own_sum / maxi(1, samples.own.size())
	print("  보스 레인 몬스터 %d마리, 타워 8x30기 / 보스 레인을 보는 클라이언트: 키프레임 %d바이트, 이동 중 틱당 최대 %d바이트, 다 서 있을 때 틱당 평균 %d / 최대 %d바이트" % [MONSTERS, first_full.boss, moving_max, settled_sum / maxi(1, settled.size()), settled_max])
	print("  (deflate 압축 시) 보스 레인 키프레임 %d바이트, 이동 중 틱당 최대 %d바이트, 다 서 있을 때 틱당 평균 %d바이트" % [first_full.boss_deflate, moving_deflate_max, settled_deflate_sum / maxi(1, settled.size())])
	print("  자기 레인을 보는 클라이언트: 키프레임 %d바이트, 틱당 변경분 평균 %d / 최대 %d바이트 (10Hz면 초당 약 %d바이트)" % [first_full.own, own_avg, own_max, own_avg * 10])
	var budget := BUDGET_SETTLED_BASE + MONSTERS
	check(settled_max < budget, "서 있는 몬스터 %d마리는 변경분에 거의 안 실린다 (틱당 최대 %d < %d바이트)" % [MONSTERS, settled_max, budget])
	check(first_full.own < BUDGET_OWN_FULL, "자기 레인 키프레임 %d < %d바이트 (보스 레인 몬스터 목록은 안 들어간다)" % [first_full.own, BUDGET_OWN_FULL])
	check(own_avg * 10 < first_full.own * 10 / 4, "자기 레인 변경분(초당 %d바이트)은 매번 전체를 보낼 때(%d바이트)의 1/4 아래" % [own_avg * 10, first_full.own * 10])
	field.queue_free()
	await frames(3)


## 키 목록의 순서가 달라도 같게 비교하려고 순서를 맞춘다
func _norm(snap: Dictionary) -> Dictionary:
	var out := snap.duplicate(true)
	for lane in out.lanes.values():
		lane["towers"] = _sorted(lane.towers, "cell")
		lane["monsters"] = _sorted(lane.monsters, "id")
	if not out.boss.is_empty():
		out.boss["monsters"] = _sorted(out.boss.monsters, "id")
	return out


func _sorted(list: Array, field: String) -> Array:
	var copy := list.duplicate()
	copy.sort_custom(func(a, b): return str(a[field]) < str(b[field]))
	return copy
