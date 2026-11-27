class_name AccountStore
extends Node
## 계정/판 기록을 저장하는 곳의 약속 (#25). Godot 서버 코드가 DB를 아는 곳은 이 클래스의 구현 하나뿐이다
## (지금: HttpAccountStore = 별도 계정 서비스(SQLite). 테스트/DB 없는 실행: MemoryAccountStore).
## 서버를 나누거나 Postgres로 옮길 때 바꿀 곳은 이 인터페이스 뒤쪽(서비스, 또는 새 구현)이고, 위(Accounts, RoomHub)는 그대로다.
##
## 모든 메서드는 `await`로 부른다 (HTTP는 비동기라서). 돌려주는 값의 status:
##   "ok" 성공 / "banned" 차단된 계정 / "rate_limited" 신규 계정 한도 / "nick_taken" 새 계정인데 닉네임이 겹침 /
##   "bad_request" 서비스가 값을 거부(다시 보내도 소용없다) / "error" 저장소에 닿지 못함, 서비스 오류(다시 시도하면 될 수 있다)

## 토큰 해시로 계정을 찾고 없으면 만든다. name/name_key는 원하는 닉네임(Nicknames.sanitize/key 한 값. 비면 이름을 바꾸지 않는다).
## 계정이 없는데 name이 비면 {status:"error", reason:"name_required"}.
## ok: {status, account:{id, nickname, created}, name_result: "ok"(바꿈)/"same"/"taken"/"cooldown"}
func login(_token_hash: String, _name: String, _name_key: String) -> Dictionary:
	return {"status": "error"}


## 판 기록 하나를 저장한다. record.match_id가 같으면 한 번만 저장된다 (재시도해도 안전). {status, duplicate?}
func record_match(_record: Dictionary) -> Dictionary:
	return {"status": "error"}


## 방(팀) 기록 순위. period: "all" / "week".
## {status, rows: [{rank, match_id, boss_level, result, duration_s, ended_at, player_count, players:[{nickname, boss_damage, lane_damage, left}]}]}
func leaderboard(_period: String, _limit: int) -> Dictionary:
	return {"status": "error", "rows": []}
