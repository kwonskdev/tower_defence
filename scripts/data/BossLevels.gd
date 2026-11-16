extends RefCounted
class_name BossLevels
## 보스 10라운드. 라운드가 오를수록 보스 체력, 파견되는 몬스터의 체력/마릿수/속도가 커진다.
## 한 판 약 30분을 목표로 제한시간 합계를 약 1800초로 맞췄다. (수치는 전부 첫 시도)
##
## hp: 보스 체력(1인 기준) / time: 제한시간(초) / reward: 처치 보상 골드(모든 참여자)
## wave_hp: 파견 몬스터 체력 배율 / count_mult: 한 번에 보내는 마릿수 배율 / interval: 파견 압박 기준(작을수록 웨이브가 커진다. 웨이브 시점은 수입 주기로 고정)

const LEVELS := [
	{"name": "화염 군주", "hp": 1500.0, "time": 150.0, "reward": 60, "wave_hp": 1.0, "count_mult": 1.0, "interval": 2.5, "color": Color(0.85, 0.35, 0.1)},
	{"name": "늑대왕", "hp": 2200.0, "time": 160.0, "reward": 90, "wave_hp": 1.2, "count_mult": 1.0, "interval": 2.5, "color": Color(0.45, 0.47, 0.55)},
	{"name": "오크 족장", "hp": 3200.0, "time": 170.0, "reward": 130, "wave_hp": 1.45, "count_mult": 1.1, "interval": 2.4, "color": Color(0.4, 0.5, 0.2)},
	{"name": "해골 마법사", "hp": 4700.0, "time": 175.0, "reward": 180, "wave_hp": 1.75, "count_mult": 1.2, "interval": 2.3, "color": Color(0.7, 0.68, 0.55)},
	{"name": "슬라임 대장", "hp": 6800.0, "time": 180.0, "reward": 240, "wave_hp": 2.1, "count_mult": 1.3, "interval": 2.2, "color": Color(0.25, 0.6, 0.25)},
	{"name": "서리 거인", "hp": 9900.0, "time": 185.0, "reward": 310, "wave_hp": 2.5, "count_mult": 1.4, "interval": 2.1, "color": Color(0.35, 0.6, 0.85)},
	{"name": "어둠 기사", "hp": 14300.0, "time": 190.0, "reward": 400, "wave_hp": 3.0, "count_mult": 1.5, "interval": 2.0, "color": Color(0.3, 0.2, 0.45)},
	{"name": "용암 드래곤", "hp": 20800.0, "time": 195.0, "reward": 500, "wave_hp": 3.6, "count_mult": 1.6, "interval": 1.9, "color": Color(0.7, 0.2, 0.1)},
	{"name": "심연의 눈", "hp": 30000.0, "time": 200.0, "reward": 620, "wave_hp": 4.3, "count_mult": 1.8, "interval": 1.8, "color": Color(0.55, 0.2, 0.6)},
	{"name": "파멸의 왕", "hp": 43500.0, "time": 205.0, "reward": 0, "wave_hp": 5.2, "count_mult": 2.0, "interval": 1.7, "color": Color(0.5, 0.05, 0.1)},
]

const COUNT := 10


static func get_level(level: int) -> Dictionary:
	return LEVELS[clampi(level - 1, 0, LEVELS.size() - 1)]
