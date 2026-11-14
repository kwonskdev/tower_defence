extends RefCounted
class_name Balance
## 밸런스 수치 모음. 전부 임시값이며, 밸런스 패치는 이 파일만 고치면 된다.

# --- 경제 ---
const START_GOLD := 150
const BASE_INCOME := 30            # 수입 틱마다 기본으로 들어오는 골드
const INCOME_INTERVAL := 30.0      # 수입 지급 주기(초)
const START_LIVES := 10

# --- 타워 (속성 없는 기본 타워 1종) ---
const TOWER_COST := 25
const TOWER_RANGE := 3.5           # 칸
const TOWER_DAMAGE := 1.0
const TOWER_COOLDOWN := 0.5        # 초

# --- 보스가 내 레인으로 보내는 몬스터 (일반형) ---
const MONSTER_SPEED := 3.0         # 초당 이동 칸
const WAVE_MONSTER_HP := 4.0
const WAVE_HP_BONUS_AT_LOW_BOSS := 3.0   # 보스 체력이 0에 가까울수록 몬스터 체력이 (1 + 이 값)배
const KILL_REWARD := 2
const DISPATCH_INTERVAL := 3.0     # 보스의 자동 파견 주기(초)

# --- 보스 ---
const BOSS_BASE_HP := 1500.0
const BOSS_HP_PER_EXTRA_PLAYER := 1000.0
const BOSS_TIME_LIMIT := 600.0     # 초

# --- 플레이어가 보스 레인으로 보내는 몬스터 (공격형) ---
# cost: 생산 비용 / income: 수입 틱 골드 영구 증가량 / dps: 보스에게 주는 초당 피해(지속)
const SENT_MONSTERS := {
	"income": {"name": "수입형", "short": "수입", "cost": 30, "income": 4, "dps": 0.5, "color": Color(0.3, 0.8, 0.3)},
	"balanced": {"name": "균형형", "short": "균형", "cost": 40, "income": 2, "dps": 2.0, "color": Color(0.9, 0.7, 0.2)},
	"power": {"name": "화력형", "short": "화력", "cost": 60, "income": 1, "dps": 6.0, "color": Color(0.7, 0.3, 0.9)},
}
