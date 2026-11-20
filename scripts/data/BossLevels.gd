extends RefCounted
class_name BossLevels
## 보스 10라운드. 라운드가 오를수록 보스 체력, 파견되는 몬스터의 체력/마릿수/속도가 커진다.
## 한 판 약 30분을 목표로 제한시간 합계를 약 1800초로 맞췄다. (수치는 전부 첫 시도)
##
## (몬스터 체력/공격력은 라운드와 무관하게 Monsters.gd에 고정)
## hp: 보스 체력(1인 기준) / time: 제한시간(초) / reward: 처치 보상 골드(모든 참여자)
## income: 보스의 수입 (수입 주기 INCOME_INTERVAL마다 쌓이는 골드). 보스는 웨이브마다 이 돈 안에서 몬스터를 랜덤으로 "사서" 보낸다.
##         라운드가 오를수록 커진다. 몬스터마다 처음 나올 수 있는 라운드는 Monsters.gd의 min_level로 정한다.

const LEVELS := [
	{"name": "화염 군주", "hp": 1500.0, "time": 150.0, "reward": 60, "income": 150, "color": Color(0.85, 0.35, 0.1)},
	{"name": "늑대왕", "hp": 2200.0, "time": 160.0, "reward": 90, "income": 230, "color": Color(0.45, 0.47, 0.55)},
	{"name": "오크 족장", "hp": 3200.0, "time": 170.0, "reward": 130, "income": 330, "color": Color(0.4, 0.5, 0.2)},
	{"name": "해골 마법사", "hp": 4700.0, "time": 175.0, "reward": 180, "income": 450, "color": Color(0.7, 0.68, 0.55)},
	{"name": "슬라임 대장", "hp": 6800.0, "time": 180.0, "reward": 240, "income": 600, "color": Color(0.25, 0.6, 0.25)},
	{"name": "서리 거인", "hp": 9900.0, "time": 185.0, "reward": 310, "income": 780, "color": Color(0.35, 0.6, 0.85)},
	{"name": "어둠 기사", "hp": 14300.0, "time": 190.0, "reward": 400, "income": 1000, "color": Color(0.3, 0.2, 0.45)},
	{"name": "용암 드래곤", "hp": 20800.0, "time": 195.0, "reward": 500, "income": 1300, "color": Color(0.7, 0.2, 0.1)},
	{"name": "심연의 눈", "hp": 30000.0, "time": 200.0, "reward": 620, "income": 1700, "color": Color(0.55, 0.2, 0.6)},
	{"name": "파멸의 왕", "hp": 43500.0, "time": 205.0, "reward": 0, "income": 2200, "color": Color(0.5, 0.05, 0.1)},
]

const COUNT := 10


static func get_level(level: int) -> Dictionary:
	return LEVELS[clampi(level - 1, 0, LEVELS.size() - 1)]
