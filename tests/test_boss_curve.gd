extends "res://tests/case_base.gd"
## 이슈 #51 보스 난이도 곡선 회귀 테스트.
## Lv.1 보스는 조금만 쉽게(체력 10% 안쪽으로 감소), Lv.2~10은 체력이 단계마다 커지고 증가 비율도 뒤로 갈수록 작아지지 않는다.
## 그리고 마지막 보스의 필요 DPS(체력/제한시간)가 앞 보스보다 충분히 커서, 앞 단계 화력만으로는 뒤 보스를 못 잡는다.

const ORIGINAL_LV1_HP := 1500.0   # #51 이전 값 (Lv.1을 얼마나 쉽게 했는지 재는 기준)


func run() -> void:
	var hp1: float = float(BossLevels.get_level(1).hp)
	check(hp1 < ORIGINAL_LV1_HP and hp1 >= ORIGINAL_LV1_HP * 0.9, "Lv.1 체력이 이전(%.0f)보다 낮고 감소폭이 10%% 안쪽이다 (%.0f, -%.1f%%)" % [
		ORIGINAL_LV1_HP, hp1, (1.0 - hp1 / ORIGINAL_LV1_HP) * 100.0])
	var grows := true
	var ratios_ok := true
	var prev_ratio := 0.0
	for level in range(2, BossLevels.COUNT + 1):
		var h: float = float(BossLevels.get_level(level).hp)
		var p: float = float(BossLevels.get_level(level - 1).hp)
		if h <= p:
			grows = false
		var ratio := h / p
		if ratio < prev_ratio - 0.000001:
			ratios_ok = false
			print("  (증가 비율이 줄어듦: Lv.%d %.3f < %.3f)" % [level, ratio, prev_ratio])
		prev_ratio = ratio
	check(grows, "Lv.2~%d 체력이 단계마다 이전보다 크다" % BossLevels.COUNT)
	check(ratios_ok, "체력 증가 비율이 뒤로 갈수록 작아지지 않는다")
	var need_last: float = float(BossLevels.get_level(BossLevels.COUNT).hp) / float(BossLevels.get_level(BossLevels.COUNT).time)
	var need_first: float = hp1 / float(BossLevels.get_level(1).time)
	check(need_last > need_first * 20.0, "마지막 보스 필요 DPS(%.0f)가 Lv.1(%.1f)의 20배를 넘는다" % [need_last, need_first])
