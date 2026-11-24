class_name Session
## 이번 판의 참여 정보: 나는 몇 번 플레이어이고, 누가 참여하는가.
## 1인 플레이는 기본값(나=0번, 참여자=[0])이고, 멀티플레이에서는 서버/로비가 채운다.

var local_player_id: int = 0
var events := SimEvents.new()  # 시뮬레이션이 내는 연출 이벤트 통로. 클라이언트가 받아서 그린다
var rng := RandomNumberGenerator.new()  # 이 판의 시뮬레이션 랜덤 하나. 레인과 보스가 같이 쓴다 (서버만 뽑는다)
var participants: Array[int] = [0]  # 레인을 가지는 플레이어 번호들 (보스 레인 제외)

## 게임 모드 (#26). 지금은 협력(PvE)뿐이고, PvP는 나중에 같은 필드로 붙인다. 방(NetServer.game_mode)과 같은 값을 쓴다.
const MODE_COOP := "coop"
var game_mode := MODE_COOP


func is_participant(player_id: int) -> bool:
	return player_id in participants


## 혼자 하는 판인가 (일시정지처럼 싱글에서만 허용하는 행동의 기준)
func is_solo() -> bool:
	return participants.size() <= 1


## 플레이어 번호 -> 닉네임 (로비에서 정해진다). 1인 플레이는 비어 있고 이름을 안 보여 준다.
var names: Dictionary = {}


## 화면에 보일 이름. 정해진 게 없으면 "Player1"처럼 번호로.
func name_of(player_id: int) -> String:
	return str(names.get(player_id, "Player%d" % (player_id + 1)))

