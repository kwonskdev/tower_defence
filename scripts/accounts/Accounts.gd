class_name Accounts
extends Node
## 서버가 계정과 판 기록을 다루는 한 곳 (#25). RoomHub는 이것만 부르고, 저장소(AccountStore)가 무엇인지는 모른다.
##  - login: hello의 토큰으로 계정을 찾거나 만든다 (익명 계정: 회원가입 없음). 닉네임 정리/금칙어/중복은 여기서 서버가 정한다 (클라이언트가 보낸 이름은 "원하는 이름"일 뿐).
##  - 저장소가 죽었을 때: 이미 아는 계정(메모리 캐시)은 그대로 들어오고, 모르는 토큰은 기록이 안 남는 임시(게스트)로 들어온다. 진행 중인 판과 재접속은 영향받지 않는다.
##    한 번 실패하면 DOWN_BACKOFF_SEC 동안은 저장소를 부르지 않고 바로 대체한다 (접속마다 시간 제한만큼 기다리지 않게).
##  - record_match: 판 기록을 큐에 넣고(디스크 대기열에도 적는다) 저장소로 보낸다. 실패하면 점점 늘어나는 간격으로 다시 시도하고, 서버를 다시 켜면 대기열을 읽어 이어서 보낸다.
##  - leaderboard: 조회 결과를 BOARD_CACHE_SEC 동안 캐시한다 (조회가 아무리 많아도 저장소 부하는 일정하다).

const DOWN_BACKOFF_SEC := 10.0
const BOARD_CACHE_SEC := 30.0
const BOARD_LIMIT := 10
const RETRY_MIN_SEC := 5.0
const RETRY_MAX_SEC := 60.0
const MAX_NAME_TRIES := 40
const SPOOL_PATH := "user://match_spool.jsonl"
const MAX_SPOOL := 1000          # 대기열이 이보다 길면 가장 오래된 것부터 버린다 (저장소가 오래 죽어 있을 때 디스크가 차지 않게)

var store: AccountStore
var spool_path := SPOOL_PATH
var clock_ms := Callable()           # () -> 지금(ms). 테스트가 조작한다
var cache := {}                      # 토큰 해시 -> {id, nickname} (저장소가 죽었을 때 아는 계정을 알아보는 용도)
var retry_min_sec := RETRY_MIN_SEC   # 판 기록 저장 재시도 간격 (실패할 때마다 두 배, retry_max_sec까지). 테스트가 줄인다
var retry_max_sec := RETRY_MAX_SEC
var dropped_matches := 0             # 서비스가 거부해서 버린 기록 수 (로그에도 남는다)
var _down_until := 0
var _queue: Array = []
var _flushing := false
var _retry_in := 0.0
var _retry_delay := 0.0
var _boards := {}                    # "기간:개수" -> {at, rows}


func now_ms() -> int:
	return int(clock_ms.call()) if clock_ms.is_valid() else Time.get_ticks_msec()


func set_store(s: AccountStore) -> void:
	store = s
	if s.get_parent() == null:
		add_child(s)


## 저장소가 최근에 실패해서 부르지 않는 중인가
func is_down() -> bool:
	return now_ms() < _down_until


# ---- 로그인 ---------------------------------------------------------------------

## hello를 받은 접속의 계정을 정한다. token: hello의 토큰 (모양이 틀리면 게스트), wanted_name: hello의 name.
## 돌려주는 값: {ok, reject, account_id, nickname, name_result, guest}
##   ok=false면 reject(NetProtocol.REJECT_*)로 접속을 거부한다 (차단된 계정). guest=true면 계정이 없는(기록이 안 남는) 임시 접속이다 (저장소 장애, 신규 계정 한도 초과, 모양이 틀린 토큰).
##   name_result: "" (계정 생성/이름 그대로) / "ok"(이름을 바꿨다) / "taken" / "cooldown" / "banned_word" / "unavailable"
func login(token, wanted_name: String) -> Dictionary:
	var want := Nicknames.sanitize(wanted_name)
	var name_result := ""
	if want != "" and not Nicknames.is_clean(want):
		want = ""
		name_result = "banned_word"
	if store == null or not Identity.valid_token(token):
		return _guest(want, name_result if name_result != "" else "")
	var h := Identity.hash_of(token)
	if is_down():
		return _fallback(h, want, "unavailable")
	var res: Dictionary = await store.login(h, want, Nicknames.key(want) if want != "" else "")
	if res.status == "error" and res.get("reason", "") == "name_required":
		want = Nicknames.generate()   # 새 계정인데 이름이 비었거나 금칙어였다: 자동 이름
		res = await store.login(h, want, Nicknames.key(want))
	var tried: Array = [want]
	var n := 0
	while res.status == "nick_taken" and n < MAX_NAME_TRIES:   # 새 계정인데 이름이 겹침: "이름2", "이름3"... (Nicknames.unique와 같은 규칙)
		var cand := Nicknames.unique(want, tried)
		tried.append(cand)
		res = await store.login(h, cand, Nicknames.key(cand))
		n += 1
	match str(res.status):
		"ok":
			var acct: Dictionary = res.account
			cache[h] = {"id": str(acct.id), "nickname": str(acct.nickname)}
			var nr := str(res.get("name_result", ""))
			if bool(acct.get("created", false)) or nr == "same":
				nr = ""   # 평범한 접속은 알릴 것이 없다
			if nr == "" and name_result != "":
				nr = name_result
			return {"ok": true, "reject": "", "account_id": str(acct.id), "nickname": str(acct.nickname), "name_result": nr, "guest": false}
		"banned":
			return {"ok": false, "reject": NetProtocol.REJECT_BANNED, "account_id": "", "nickname": "", "name_result": "", "guest": false}
		"rate_limited":
			# 신규 계정이 분당 한도를 넘었다 (남발하는 접속이 있을 때 DB가 부풀지 않게). 막지 않고 기록이 안 남는 임시(게스트)로 받는다: 정상 신규 플레이어가 같이 쫓겨나지 않게
			Log.warn(Log.Category.NETWORK, "신규 계정 한도 초과: 계정 없이(게스트) 입장")
			return _guest(want, "unavailable")
		_:
			_down_until = now_ms() + int(DOWN_BACKOFF_SEC * 1000.0)
			Log.warn(Log.Category.NETWORK, "계정 저장소에 닿지 못함 (%s): %.0f초 동안 아는 계정만 받고 나머지는 임시로 입장" % [str(res.get("reason", res.status)), DOWN_BACKOFF_SEC])
			return _fallback(h, want, "unavailable")


func _fallback(token_hash: String, want: String, name_result: String) -> Dictionary:
	if cache.has(token_hash):
		var c: Dictionary = cache[token_hash]
		return {"ok": true, "reject": "", "account_id": c.id, "nickname": c.nickname, "name_result": name_result, "guest": false}
	return _guest(want, name_result)


func _guest(want: String, name_result: String) -> Dictionary:
	return {"ok": true, "reject": "", "account_id": "", "nickname": want, "name_result": name_result, "guest": true}


# ---- 판 기록 --------------------------------------------------------------------

## 판 기록(MatchRecord.build)을 저장 대기열에 넣는다. 저장소가 죽어 있으면 나중에 다시 보낸다.
func record_match(rec: Dictionary) -> void:
	_queue.append(rec)
	while _queue.size() > MAX_SPOOL:
		_queue.pop_front()
		dropped_matches += 1
		Log.error(Log.Category.NETWORK, "판 기록 대기열이 가득 차 가장 오래된 기록을 버림")
	_save_spool()
	_kick()


func queue_size() -> int:
	return _queue.size()


## 지난 실행에서 못 보낸 기록을 읽어 대기열에 올린다 (서버 시작 때)
func load_spool() -> int:
	if not FileAccess.file_exists(spool_path):
		return 0
	var f := FileAccess.open(spool_path, FileAccess.READ)
	if f == null:
		return 0
	var n := 0
	while not f.eof_reached():
		var line := f.get_line().strip_edges()
		if line == "":
			continue
		var json := JSON.new()
		if json.parse(line) == OK and typeof(json.data) == TYPE_DICTIONARY and json.data.has("match_id"):
			_queue.append(json.data)
			n += 1
	f.close()
	if n > 0:
		Log.info(Log.Category.NETWORK, "지난 실행에서 못 보낸 판 기록 %d개를 대기열에 올림" % n)
		_kick()
	return n


func _save_spool() -> void:
	if _queue.is_empty():
		if FileAccess.file_exists(spool_path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(spool_path))
		return
	var f := FileAccess.open(spool_path, FileAccess.WRITE)
	if f == null:
		Log.warn(Log.Category.NETWORK, "판 기록 대기열 파일을 쓰지 못함: %s" % spool_path)
		return
	for rec in _queue:
		f.store_line(JSON.stringify(rec))
	f.close()


func _kick() -> void:
	if _flushing or store == null or _queue.is_empty():
		return
	_flush()


func _flush() -> void:
	_flushing = true
	while not _queue.is_empty():
		var rec: Dictionary = _queue[0]
		var res: Dictionary = await store.record_match(rec)
		if _queue.is_empty() or _queue[0] != rec:
			continue   # 기다리는 동안 대기열이 바뀌었다 (넘침으로 버려짐): 다시 맨 앞부터
		if res.status == "ok":
			_queue.pop_front()
			_save_spool()
			_retry_delay = 0.0
		elif res.status == "bad_request":   # 다시 보내도 소용없다: 버린다
			_queue.pop_front()
			_save_spool()
			dropped_matches += 1
			Log.error(Log.Category.NETWORK, "계정 서비스가 판 기록을 거부해 버림: %s" % str(res.get("reason", "")))
		else:
			_retry_delay = retry_min_sec if _retry_delay <= 0.0 else minf(_retry_delay * 2.0, retry_max_sec)
			_retry_in = _retry_delay
			Log.warn(Log.Category.NETWORK, "판 기록 저장 실패: 대기열 %d개, %.0f초 뒤 다시 시도" % [_queue.size(), _retry_in])
			break
	_flushing = false


func _process(delta: float) -> void:
	if _retry_in > 0.0:
		_retry_in -= delta
		if _retry_in <= 0.0:
			_retry_in = 0.0
			_kick()


# ---- 리더보드 -------------------------------------------------------------------

## 순위 조회. {status: "ok"/"unavailable", period, rows}. 같은 조회는 BOARD_CACHE_SEC 동안 캐시에서 준다.
func leaderboard(period: String) -> Dictionary:
	if period not in ["all", "week"]:
		period = "all"
	var key := "%s:%d" % [period, BOARD_LIMIT]
	var hit: Dictionary = _boards.get(key, {})
	if not hit.is_empty() and now_ms() - int(hit.at) < int(BOARD_CACHE_SEC * 1000.0):
		return {"status": "ok", "period": period, "rows": hit.rows}
	if store == null or is_down():
		return {"status": "unavailable", "period": period, "rows": []}
	var res: Dictionary = await store.leaderboard(period, BOARD_LIMIT)
	if res.status != "ok":
		_down_until = now_ms() + int(DOWN_BACKOFF_SEC * 1000.0)
		return {"status": "unavailable", "period": period, "rows": []}
	_boards[key] = {"at": now_ms(), "rows": res.rows}
	return {"status": "ok", "period": period, "rows": res.rows}
