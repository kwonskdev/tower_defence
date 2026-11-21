class_name Command
## 상태를 바꾸는 행동 하나를 나타내는 데이터 (명령).
## 명령은 {type, player_id, ...인자} 형태의 Dictionary이고, 값은 int/String/bool/Vector2i만 쓴다.
## 객체 참조(Tower 등)는 넣지 않는다: 타워는 칸 좌표로 가리킨다. 그래야 네트워크로 보내고 서버가 검증할 수 있다.

const BUILD_TOWER := "build_tower"
const SELL_TOWER := "sell_tower"
const EVOLVE_TOWER := "evolve_tower"
const LEARN_SKILL := "learn_skill"
const UPGRADE_STAT := "upgrade_stat"
const UPGRADE_COLOR := "upgrade_color"
const RECOLOR_TOWER := "recolor_tower"
const HEAL_TOWER := "heal_tower"
const SEND_MONSTER := "send_monster"
const START_GAME := "start_game"
const SET_PAUSE := "set_pause"

## 명령 종류별 인자 {이름: 타입}. type, player_id는 모든 명령이 갖는다.
const SCHEMA := {
	BUILD_TOWER: {"cell": TYPE_VECTOR2I, "kind_id": TYPE_STRING, "confirmed": TYPE_BOOL},
	SELL_TOWER: {"cell": TYPE_VECTOR2I},
	EVOLVE_TOWER: {"cell": TYPE_VECTOR2I, "evo": TYPE_STRING},
	LEARN_SKILL: {"cell": TYPE_VECTOR2I},
	UPGRADE_STAT: {"evo": TYPE_STRING, "skill": TYPE_STRING, "key": TYPE_STRING},
	UPGRADE_COLOR: {"color_name": TYPE_STRING},
	RECOLOR_TOWER: {"cell": TYPE_VECTOR2I},
	HEAL_TOWER: {"cell": TYPE_VECTOR2I},
	SEND_MONSTER: {"kind_id": TYPE_STRING},
	START_GAME: {},
	SET_PAUSE: {"on": TYPE_BOOL},
}


## 명령을 만든다. 인자를 빠뜨리거나 모르는 인자를 넣으면 빈 Dictionary를 돌려준다.
static func make(type: String, player_id: int, args: Dictionary = {}) -> Dictionary:
	var cmd := {"type": type, "player_id": player_id}
	cmd.merge(args)
	return cmd if check(cmd) == "" else {}


## 명령의 모양이 맞는지 검사한다 (종류, 인자 이름, 인자 타입). 맞으면 "", 아니면 사유.
## 값이 게임 규칙에 맞는지(골드, 칸 상태 등)는 CommandBus가 따로 본다.
static func check(cmd: Dictionary) -> String:
	if typeof(cmd.get("type")) != TYPE_STRING or not SCHEMA.has(cmd["type"]):
		return "unknown_type"
	if typeof(cmd.get("player_id")) != TYPE_INT:
		return "bad_player_id"
	var fields: Dictionary = SCHEMA[cmd["type"]]
	for key in cmd:
		if key != "type" and key != "player_id" and not fields.has(key):
			return "unexpected_arg:%s" % key
	for key in fields:
		if not cmd.has(key) or typeof(cmd[key]) != fields[key]:
			return "bad_arg:%s" % key
	return ""


## 네트워크로 보낼 문자열 (JSON). Vector2i는 [x, y]가 된다.
static func to_wire(cmd: Dictionary) -> String:
	var out := {}
	for key in cmd:
		var v = cmd[key]
		out[key] = [v.x, v.y] if v is Vector2i else v
	return JSON.stringify(out)


## to_wire로 만든 문자열을 명령으로 되돌린다. 모양이 맞지 않으면 빈 Dictionary.
## JSON은 정수도 실수로 읽으므로 SCHEMA의 타입을 보고 int / Vector2i로 되돌린다.
static func from_wire(text: String) -> Dictionary:
	var json := JSON.new()  # parse_string은 잘못된 입력에서 엔진 오류를 찍는다: 네트워크에서 온 쓰레기 입력이 로그를 어지럽히지 않게 parse()를 쓴다
	if json.parse(text) != OK:
		return {}
	var parsed = json.data
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var cmd := {}
	var type = parsed.get("type")
	if typeof(type) != TYPE_STRING or not SCHEMA.has(type):
		return {}
	var fields: Dictionary = SCHEMA[type]
	for key in parsed:
		var v = parsed[key]
		if key == "player_id" and typeof(v) == TYPE_FLOAT and v == floorf(v):
			v = int(v)
		elif fields.get(key) == TYPE_VECTOR2I and typeof(v) == TYPE_ARRAY and v.size() == 2 \
				and typeof(v[0]) == TYPE_FLOAT and typeof(v[1]) == TYPE_FLOAT:
			v = Vector2i(int(v[0]), int(v[1]))
		cmd[key] = v
	return cmd if check(cmd) == "" else {}
