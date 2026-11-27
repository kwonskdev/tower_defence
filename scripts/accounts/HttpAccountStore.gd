class_name HttpAccountStore
extends AccountStore
## 계정 서비스(tools/accounts/accounts_service.py)에 HTTP로 붙는 저장소 (#25). 요청은 비동기라서 서비스가 느리거나 죽어도
## 방 틱(시뮬레이션)은 멈추지 않는다. 시간 제한 안에 답이 없으면 {status:"error"}이다 (위의 Accounts가 재시도/대체를 정한다).

const DEFAULT_TIMEOUT_SEC := 2.0   # 접속(hello) 처리 시간(NetProtocol.HELLO_TIMEOUT 5초) 안에 끝나야 한다

var base_url := "http://127.0.0.1:47310"
var api_key := ""
var timeout_sec := DEFAULT_TIMEOUT_SEC


func login(token_hash: String, player_name: String, name_key: String) -> Dictionary:
	var body := {"token_hash": token_hash}
	if player_name != "":
		body["name"] = player_name
		body["name_key"] = name_key
	return await _call(HTTPClient.METHOD_POST, "/v1/login", body)


func record_match(record: Dictionary) -> Dictionary:
	return await _call(HTTPClient.METHOD_POST, "/v1/matches", record)


func leaderboard(period: String, limit: int) -> Dictionary:
	var res := await _call(HTTPClient.METHOD_GET, "/v1/leaderboard?period=%s&limit=%d" % [period.uri_encode(), limit], {})
	if not res.has("rows"):
		res["rows"] = []
	return res


func _call(method: HTTPClient.Method, path: String, body: Dictionary) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout_sec
	add_child(req)
	var headers := PackedStringArray(["X-Api-Key: " + api_key, "Content-Type: application/json"])
	var err := req.request(base_url + path, headers, method, "" if method == HTTPClient.METHOD_GET else JSON.stringify(body))
	if err != OK:
		req.queue_free()
		return {"status": "error", "reason": "request_failed"}
	var done: Array = await req.request_completed   # [result, 응답 코드, 헤더, 본문]
	req.queue_free()
	var json := JSON.new()
	var parsed: Dictionary = {}
	if json.parse(PackedByteArray(done[3]).get_string_from_utf8()) == OK and typeof(json.data) == TYPE_DICTIONARY:
		parsed = json.data
	if done[0] != HTTPRequest.RESULT_SUCCESS:
		return {"status": "error", "reason": "network"}
	if done[1] == 400:
		return {"status": "bad_request", "reason": str(parsed.get("reason", ""))}
	if done[1] != 200 or not parsed.has("status"):
		return {"status": "error", "reason": "http_%d" % done[1]}
	return parsed
