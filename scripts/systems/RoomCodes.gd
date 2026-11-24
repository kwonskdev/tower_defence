class_name RoomCodes
## 방 코드 발급/반납과 무차별 대입 제한 (#26). 네트워크와 화면을 모르는 순수 규칙이라 서버(RoomHub)가 쓰고 테스트가 직접 돌린다.
##
## 규칙
##  - 코드는 LENGTH자, ALPHABET의 글자만 쓴다. 혼동되는 글자(0/O, 1/I/L)는 뺐다.
##  - 방이 끝나거나 비면 release()로 코드를 돌려받는다. 시작을 못 한 채 EXPIRE_SEC가 지난 방은 expired()가 알려 준다.
##  - 잘못된 코드를 시도한 횟수를 접속 주소마다(1분 창, MAX_BAD_PER_KEY) 세고, 서버 전체로도 분당(MAX_BAD_PER_MINUTE) 센다.
##    연결마다 세면 끊고 다시 접속해서 우회하므로 주소로 센다. 리버스 프록시 뒤에서는 주소가 모두 같으니 전체 한도가 막아 준다.
##    넘으면 입장 시도를 거부한다 (맞는 코드여도: 맞은 코드로 한계를 시험하지 못하게). 시간은 호출하는 쪽이 now_ms로 준다 (테스트가 시계를 조작한다).

const ALPHABET := "23456789ABCDEFGHJKMNPQRSTUVWXYZ"
const LENGTH := 6
const EXPIRE_SEC := 1800.0            # 만든 뒤 시작을 못 하면 30분 뒤 만료 (#26 결정)
const MAX_BAD_PER_KEY := 5            # 한 접속 주소가 1분 안에 잘못된 코드를 이만큼 시도하면 막는다 (연결을 끊을 뿐이다. 계정 로그아웃이 아니다)
const MAX_BAD_PER_MINUTE := 60        # 서버 전체 잘못된 시도 한도 (분당)
const WINDOW_MS := 60000

var _rooms: Dictionary = {}           # 코드 -> 만든 시각(ms)
var _bad_by_key: Dictionary = {}      # 접속 주소 -> 잘못된 시도 시각들(ms)
var _bad_times: Array = []            # 전체 잘못된 시도 시각(ms)


## 새 코드를 발급한다. rng를 주면 그 랜덤으로 (테스트용). 못 찾으면(사실상 불가능) "".
func issue(now_ms: int, rng: RandomNumberGenerator = null) -> String:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	for _try in range(100):
		var code := ""
		for i in range(LENGTH):
			code += ALPHABET[r.randi_range(0, ALPHABET.length() - 1)]
		if not _rooms.has(code):
			_rooms[code] = now_ms
			return code
	return ""


func release(code: String) -> void:
	_rooms.erase(code)


func has(code: String) -> bool:
	return _rooms.has(code)


func count() -> int:
	return _rooms.size()


## 만료된(시작을 못 한 채 EXPIRE_SEC가 지난) 코드들. 부르는 쪽이 방을 닫고 release한다.
func expired(now_ms: int) -> Array:
	var out: Array = []
	for code in _rooms:
		if now_ms - int(_rooms[code]) >= int(EXPIRE_SEC * 1000.0):
			out.append(code)
	return out


## 사람이 친 글자를 코드 모양으로: 공백/하이픈 제거, 대문자. 헷갈리는 글자는 그대로 둔다 (없는 코드로 거부된다).
static func normalize(text: String) -> String:
	return text.strip_edges().replace(" ", "").replace("-", "").to_upper()


## 길이와 글자 모양이 맞는가 (방이 있는지는 별개)
static func is_valid_format(code: String) -> bool:
	if code.length() != LENGTH:
		return false
	for i in range(code.length()):
		if ALPHABET.find(code[i]) < 0:
			return false
	return true


## 입장 시도를 받아 줄 수 있는가 (한도를 넘었으면 false). key는 시도한 쪽의 구별값(접속 주소). 시도 결과는 record_bad로 알린다.
func allowed(key: String, now_ms: int) -> bool:
	_prune(now_ms)
	return _bad_by_key.get(key, []).size() < MAX_BAD_PER_KEY and _bad_times.size() < MAX_BAD_PER_MINUTE


## 잘못된 코드(없는 코드/모양이 틀림)를 시도했다. 이 key가 한도에 닿았으면 true (그 연결을 끊을 것).
func record_bad(key: String, now_ms: int) -> bool:
	_prune(now_ms)
	var list: Array = _bad_by_key.get(key, [])
	list.append(now_ms)
	_bad_by_key[key] = list
	_bad_times.append(now_ms)
	return list.size() >= MAX_BAD_PER_KEY


func _prune(now_ms: int) -> void:
	while not _bad_times.is_empty() and now_ms - int(_bad_times[0]) >= WINDOW_MS:
		_bad_times.remove_at(0)
	for key in _bad_by_key.keys():
		var list: Array = _bad_by_key[key]
		while not list.is_empty() and now_ms - int(list[0]) >= WINDOW_MS:
			list.remove_at(0)
		if list.is_empty():
			_bad_by_key.erase(key)
