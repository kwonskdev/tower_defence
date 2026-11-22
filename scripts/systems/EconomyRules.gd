class_name EconomyRules
## 레벨/비용/환급 규칙 (순수 함수). 서버(LaneController)와 클라이언트(화면)가 같은 계산을 쓰도록 한 곳에 둔다 (#21).
## 클라이언트는 서버 스냅샷의 레벨/골드 값을 넣어 이 함수로 비용을 계산해 보여 줄 뿐이고, 실제 차감과 판정은 서버(CommandBus)가 한다.


## 진화 항목 레벨 (1~3). levels: 스냅샷/레인의 stat_levels {"계열.스킬.키": 레벨}
static func stat_level(levels: Dictionary, evo: String, skill: String, key: String) -> int:
	return int(levels.get("%s.%s.%s" % [evo, skill, key], 1))


## 설명 문구용: 이 계열의 항목별 레벨 {"A.count": 2, ...}
static func levels_of(levels: Dictionary, evo: String) -> Dictionary:
	var out := {}
	for skill in ["A", "B"]:
		for key in Evolutions.PARAMS[evo][skill]:
			out["%s.%s" % [skill, key]] = stat_level(levels, evo, skill, key)
	return out


## 항목 업그레이드 비용 (다음 레벨로). 최대 레벨이면 -1
static func stat_upgrade_cost(levels: Dictionary, evo: String, skill: String, key: String) -> int:
	var lv := stat_level(levels, evo, skill, key)
	if lv >= Evolutions.MAX_LEVEL:
		return -1
	return int(Balance.STAT_UPGRADE_COSTS[lv - 1])


## 색깔 레벨 (0~5)
static func color_level(color_levels: Dictionary, color_name: String) -> int:
	return int(color_levels.get(color_name, 0))


## 색깔 업그레이드 비용 (현재 레벨에서 다음 레벨로). 최대 레벨이면 -1
static func color_upgrade_cost(color_levels: Dictionary, color_name: String) -> int:
	var cur := color_level(color_levels, color_name)
	if cur >= Balance.COLOR_MAX_LEVEL:
		return -1
	return Balance.COLOR_UPGRADE_COSTS[cur]


## B 스킬 배우는 비용 (진화 전이거나 이미 배웠으면 -1)
static func learn_cost(evolution: String, b_learned: bool) -> int:
	if evolution == "" or b_learned:
		return -1
	return Balance.SKILL_LEARN_COST


## 타워를 팔 때 받는 골드 (반올림하지 않는다). 시작 전에는 전액 환급
static func sell_value(invested: int, started: bool) -> float:
	var ratio := Balance.SELL_REFUND_RATIO if started else Balance.SELL_REFUND_RATIO_BEFORE_START
	return invested * ratio


## 화면에 보이는 정수 골드 (소수점 내림. 부동소수 오차로 3.0이 2.9999999가 되어 2로 보이지 않도록 아주 작은 값을 더한다)
static func whole(amount: float) -> int:
	return floori(amount + 0.000001)


## 팔 때 한 번 더 확인해야 하는가 (진화/B 스킬에 골드를 쓴 타워)
static func sell_needs_confirm(evolution: String) -> bool:
	return evolution != ""


## 선택한 타워 정보창에 보여줄 색깔 보너스 한 줄
static func color_bonus_text(color_levels: Dictionary, color_name: String, evolution: String, cluster_size: int, cluster_mult: float) -> String:
	var lv := color_level(color_levels, color_name)
	var type: String = Balance.COLOR_BONUS_TYPES[color_name]
	if lv == 0:
		return "%s Lv0" % color_name
	var text := "%s Lv%d · %s %s" % [color_name, lv, Balance.COLOR_BONUS_LABELS[type], Balance.color_bonus_value_text(color_name, lv)]
	text += " · 군집 %d개 +%s%%" % [cluster_size, String.num((cluster_mult - 1.0) * 100.0, 2)]
	if type == "damage" and evolution == "skill":
		text += " (스킬형은 효과 없음)"
	return text
