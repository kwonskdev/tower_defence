extends RefCounted
class_name GhostScore
## 유령 구간 점수 계산 (순수 함수 모음).
## 유령 구간 = 보스를 제한시간이 남은 채로 잡으면 그 남은 시간 동안 나오는 보너스 구간 (BossController).
## 점수는 두 가지를 따로 센다.
##   레인 데미지     = 각 플레이어 레인의 타워가 그 레인의 유령에게 준 피해 (LaneController.ghost_damage)
##   보스 레인 데미지 = 보스 레인에서 보스 앞에 선 몬스터가 보스 자리의 유령에게 준 피해 (BossController.ghost_boss_damage_by_player)
## 게임 전체에서 구간마다 쌓인 값을 게임이 끝날 때까지 누적한다.
## 결과 화면은 인원이 달라도 같은 척도로 비교되도록 "누적(팀 전체) ÷ 참여 인원 × 최대 인원(Balance.MAX_PLAYERS)"으로 환산해서 보여 준다.


## 환산 점수: 팀 전체 누적 ÷ 참여 인원 × 최대 인원. 참여 인원이 0이면 0.
static func scaled(total: float, participants: int) -> float:
	if participants <= 0:
		return 0.0
	return total / float(participants) * float(Balance.MAX_PLAYERS)


## {player_id: 피해} -> [{player_id, damage}] 피해가 큰 순서 (같으면 번호가 작은 쪽이 먼저)
static func ranking(by_player: Dictionary) -> Array:
	var list: Array = []
	for pid in by_player:
		list.append({"player_id": int(pid), "damage": float(by_player[pid])})
	list.sort_custom(func(a: Dictionary, b: Dictionary):
		if not is_equal_approx(a.damage, b.damage):
			return a.damage > b.damage
		return a.player_id < b.player_id)
	return list


static func total_of(by_player: Dictionary) -> float:
	var sum := 0.0
	for v in by_player.values():
		sum += float(v)
	return sum


## 점수 요약. lane_by_player / boss_by_player: {player_id: 피해}, participants: 참여 인원
## 반환: {participants, lane_total, boss_total, lane_scaled, boss_scaled, lane_ranking, boss_ranking}
static func summary(lane_by_player: Dictionary, boss_by_player: Dictionary, participants: int) -> Dictionary:
	var lane_total := total_of(lane_by_player)
	var boss_total := total_of(boss_by_player)
	return {
		"participants": participants,
		"lane_total": lane_total,
		"boss_total": boss_total,
		"lane_scaled": scaled(lane_total, participants),
		"boss_scaled": scaled(boss_total, participants),
		"lane_ranking": ranking(lane_by_player),
		"boss_ranking": ranking(boss_by_player),
	}


## 1.2K / 3.4M 처럼 줄여서 쓴다 (좁은 화면용). 1000 미만은 반올림한 정수 (공유 텍스트의 정수와 같은 값)
static func short_number(num: float) -> String:
	if num >= 1000000.0:
		return "%.1fM" % (num / 1000000.0)
	elif num >= 1000.0:
		return "%.1fK" % (num / 1000.0)
	return "%d" % roundi(num)


## 한 줄 순위 글자: "1위 P2 12.3K · 2위 P1 8.1K". 피해가 없으면 "-"
static func ranking_text(ranked: Array) -> String:
	var parts: Array[String] = []
	for i in range(ranked.size()):
		parts.append("%d위 P%d %s" % [i + 1, ranked[i].player_id + 1, short_number(ranked[i].damage)])
	return " · ".join(parts) if not parts.is_empty() else "-"


## 결과를 공유할 수 있는 글자 (클립보드로 복사). stats는 MainGame._collect_game_stats가 만든 것 (ghost 항목은 summary 결과)
static func share_text(is_victory: bool, stats: Dictionary) -> String:
	var lines: Array[String] = ["Lane Wars 결과: %s" % ("승리" if is_victory else "패배")]
	if stats.has("boss_level"):
		lines.append("도달 보스 레벨: %d / %d" % [stats.boss_level, stats.get("total_boss_levels", 10)])
	if stats.has("play_time"):
		var total_sec := int(stats.play_time)
		lines.append("플레이 시간: %d분 %d초" % [floori(total_sec / 60.0), total_sec % 60])
	if stats.has("ghost"):
		var g: Dictionary = stats.ghost
		lines.append("유령 구간 점수 (참여 %d명, 누적 ÷ 참여 인원 × %d로 환산)" % [g.participants, Balance.MAX_PLAYERS])
		lines.append("레인 데미지: %d (누적 %s)" % [roundi(g.lane_scaled), short_number(g.lane_total)])
		lines.append("보스 레인 데미지: %d (누적 %s)" % [roundi(g.boss_scaled), short_number(g.boss_total)])
		if g.participants > 1:
			lines.append("레인 순위: %s" % ranking_text(g.lane_ranking))
			lines.append("보스 레인 순위: %s" % ranking_text(g.boss_ranking))
	return "\n".join(lines)
