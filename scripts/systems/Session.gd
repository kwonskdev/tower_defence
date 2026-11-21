class_name Session
## 이번 판의 참여 정보: 나는 몇 번 플레이어이고, 누가 참여하는가.
## 1인 플레이는 기본값(나=0번, 참여자=[0])이고, 멀티플레이에서는 서버/로비가 채운다.

var local_player_id: int = 0
var events := SimEvents.new()  # 시뮬레이션이 내는 연출 이벤트 통로. 클라이언트가 받아서 그린다
var rng := RandomNumberGenerator.new()  # 이 판의 시뮬레이션 랜덤 하나. 레인과 보스가 같이 쓴다 (서버만 뽑는다)
var participants: Array[int] = [0]  # 레인을 가지는 플레이어 번호들 (보스 레인 제외)


func is_participant(player_id: int) -> bool:
	return player_id in participants


## 혼자 하는 판인가 (일시정지처럼 싱글에서만 허용하는 행동의 기준)
func is_solo() -> bool:
	return participants.size() <= 1
