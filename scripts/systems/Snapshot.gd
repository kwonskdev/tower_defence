class_name Snapshot
## 서버가 클라이언트에게 보내는 "지금 상태" 한 장 (#21). 순수 데이터(Dictionary/Array/숫자/문자열)만 담아서 JSON으로 그대로 바뀐다.
## 클라이언트는 시뮬레이션 객체(LaneController, Tower, Monster, BossController)를 읽지 않고 이 값만 보고 그린다.
## 연출(파괴 폭발, 스킬 배너, 데미지 숫자)은 상태가 아니라 이벤트라서 여기 없다 (CommandBus 결과의 events와 BossController 신호).
##
## 모양:
##   {"v", "boss_lane": int, "players": [id...],
##    "lanes": {"<id>": 레인}, "boss": 보스}
##   레인: gold, lives, income, income_left, active, started, ghost_damage, stat_levels, color_levels, towers[], monsters[]
##   타워: lane, cell[x,y], kind, color, evo, b, invested, durability, kills, damage, ghost_damage + Tower.view_state()(aim, recoil, sealed, warn, charge, charge_max, haste, range)
##   몬스터: Monster.view_state() (id, kind, owner, pos[x,y], hp, max_hp, flying, ghost, shape, color, size, facing, 상태이상 ...)
##   보스: state, level, hp, max_hp, time_left, in_ghost, ghost_length, total_dps, damage_mult, wave_text,
##         next_wave_in, sent_count, attackers, damage_by_player, ghost_boss_damage_by_player, monsters[],
##         has_level, level_flash, color, name, phase_text, effective_dps, has_guard, ghost_running, ghost_summary, wave_preview[], affix
##   색은 "RRGGBB" 글자(Color.to_html), 되돌릴 때는 Color.html()
## 위치는 셀 단위 [x, y] (셀 중심 = +0.5). 키는 JSON을 거쳐도 같도록 문자열로 쓴다.

const VERSION := 1


static func build(session: Session, lanes: Dictionary, boss: BossController) -> Dictionary:
	var out_lanes := {}
	for pid in lanes:
		out_lanes[str(pid)] = _lane(lanes[pid])
	return {
		"v": VERSION,
		"boss_lane": GameField.BOSS_LANE_ID,
		"players": session.participants.duplicate(),
		"lanes": out_lanes,
		"boss": _boss(boss) if boss != null else {},
	}


static func _vec(v: Vector2) -> Array:
	return [snappedf(v.x, 0.001), snappedf(v.y, 0.001)]


static func _lane(lane: LaneController) -> Dictionary:
	var towers: Array = []
	for t in lane.towers:
		var entry := {
			"lane": lane.player_id, "cell": [t.cell.x, t.cell.y], "kind": t.kind.id, "color": t.color_info.name, "evo": t.evolution, "b": t.b_learned,
			"invested": t.invested, "durability": t.durability, "kills": t.kills,
			"damage": t.total_damage, "ghost_damage": t.ghost_damage,
		}
		entry.merge(t.view_state())  # 그리는 데 필요한 값 (조준각, 반동, 충전, 사거리 ...)
		towers.append(entry)
	var monsters: Array = []
	for m in lane.monsters:
		if is_instance_valid(m):
			monsters.append(_monster(m))
	return {
		"gold": lane.gold, "lives": lane.lives, "income": lane.income, "income_left": lane.income_time_left(),
		"active": lane.active, "started": lane.started, "ghost_damage": lane.ghost_damage,
		"stat_levels": lane.stat_levels.duplicate(), "color_levels": lane.color_levels.duplicate(),
		"towers": towers, "monsters": monsters,
	}


static func _monster(m: Monster) -> Dictionary:
	return m.view_state()  # 위치/체력/외형/상태이상 (클라이언트 껍데기가 이것만으로 그린다)


static func _boss(boss: BossController) -> Dictionary:
	var sent: Array = []
	for m in boss.get_sent_monsters():
		if is_instance_valid(m):
			sent.append(_monster(m))
	var damage := {}
	for pid in boss.damage_by_player:
		damage[str(pid)] = boss.damage_by_player[pid]
	var ghost_damage := {}
	for pid in boss.ghost_boss_damage_by_player:
		ghost_damage[str(pid)] = boss.ghost_boss_damage_by_player[pid]
	return {
		"state": int(boss.state), "level": boss.level, "hp": boss.hp, "max_hp": boss.max_hp, "time_left": boss.time_left,
		"in_ghost": boss.in_ghost_phase, "ghost_length": boss.ghost_length, "total_dps": boss.total_dps,
		"damage_mult": boss.damage_mult, "wave_text": boss.current_wave_text, "next_wave_in": boss.time_to_next_wave(),
		"sent_count": boss.sent_count, "attackers": boss.get_attacker_count(),
		"damage_by_player": damage, "ghost_boss_damage_by_player": ghost_damage, "monsters": sent,
		"has_level": not boss.level_data.is_empty(), "level_flash": boss.level_flash,
		"color": Color(boss.level_data.get("color", Color.WHITE)).to_html(false),
		"name": boss.level_data.get("name", ""), "phase_text": boss.phase_text(), "effective_dps": boss.effective_dps(),
		"has_guard": boss.has_guard(), "ghost_running": boss.ghost_running(), "ghost_summary": boss.ghost_summary(),
		"wave_preview": _wave_preview(boss), "affix": _affix(boss),
	}


static func _wave_preview(boss: BossController) -> Array:
	var out: Array = []
	for e in boss.get_next_wave_preview():
		out.append({"type": e.type, "name": e.name, "count": e.count, "flying": e.flying, "color": e.color.to_html(false)})
	return out


static func _affix(boss: BossController) -> Dictionary:
	var a := boss.get_next_wave_affix()
	return {} if a.is_empty() else {"id": a.id, "name": a.name, "color": a.color.to_html(false)}
