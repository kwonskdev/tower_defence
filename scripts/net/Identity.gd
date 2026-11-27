class_name Identity
## "같은 사람인가"를 정하는 한 곳 (#23, #25).
##  - 계정 토큰 (#25): 처음 실행할 때 기기에서 암호용 난수 128비트를 만들어 기기에 저장하고(account_token), 이후 모든 접속의 hello에 싣는다.
##    서버는 그 해시로 익명 계정을 찾거나 만든다 (Accounts). 앱을 지우면 토큰도 사라져 계정을 되찾을 수 없다 (계정 연동은 단계 3).
##  - 재접속도 같은 토큰으로 한다: 서버는 판이 시작될 때 자리마다 토큰 해시를 두고, 같은 토큰을 내면 같은 레인으로 돌려보낸다. 닉네임만으로는 자리를 못 가져간다.
##  - (테스트/봇처럼 계정이 필요 없는 클라이언트는 new_token으로 접속마다 임시 토큰을 쓴다.)
##  - 서버는 토큰 원문을 보관하지 않고 해시(SHA-256)만 둔다. 재접속하는 쪽이 같은 토큰을 내면 그 해시가 같다.
##  - 앱이 죽었다 켜져도 돌아올 수 있게 (방 코드, 서버 주소, 토큰)을 기기에 저장한다 (resume 파일).

const TOKEN_BYTES := 16            # 128비트
const TOKEN_HEX_LENGTH := 32
const RESUME_PATH := "user://resume.cfg"
const ACCOUNT_PATH := "user://account.cfg"

static var resume_path := RESUME_PATH   # 테스트는 다른 경로를 쓴다
static var account_path := ACCOUNT_PATH


## 새 임시 토큰 (소문자 16진수 32글자). 암호용 난수를 쓴다.
static func new_token() -> String:
	return Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()


## 밖에서 온 토큰이 모양은 맞는가 (길이와 16진수만). 모양이 틀리면 없는 것으로 본다.
static func valid_token(token) -> bool:
	if typeof(token) != TYPE_STRING or token.length() != TOKEN_HEX_LENGTH:
		return false
	return token.is_valid_hex_number(false) and token == token.to_lower()


## 이 기기의 계정 토큰 (#25). 저장된 것이 있으면 그것을, 없으면(첫 실행) 새로 만들어 저장해서 돌려준다.
## 저장에 실패해도 이번 실행에는 쓸 토큰을 돌려준다 (다음 실행에는 새 계정이 된다).
static func account_token() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(account_path) == OK:
		var saved = cfg.get_value("account", "token", "")
		if valid_token(saved):
			return saved
	var fresh := new_token()
	cfg.set_value("account", "token", fresh)
	if cfg.save(account_path) != OK:
		Log.warn(Log.Category.NETWORK, "계정 토큰을 기기에 저장하지 못함: %s" % account_path)
	return fresh


## 서버가 보관하는 값 (토큰 원문 대신)
static func hash_of(token: String) -> String:
	return token.sha256_text()


## 서버: 이 자리의 주인(저장해 둔 해시)이 지금 내민 토큰의 주인인가
static func authorize(stored_hash: String, presented_token) -> bool:
	if stored_hash == "" or not valid_token(presented_token):
		return false
	return hash_of(presented_token) == stored_hash


# ---- 앱이 죽었다 켜졌을 때 돌아오기 위한 저장 (클라이언트) ---------------------------

## {server, room, token, name}을 저장한다
static func save_resume(info: Dictionary) -> void:
	var cfg := ConfigFile.new()
	for key in ["server", "room", "token", "name"]:
		cfg.set_value("resume", key, str(info.get(key, "")))
	cfg.save(resume_path)


## 저장된 것 {server, room, token, name}. 없거나 모양이 틀리면 빈 Dictionary.
static func load_resume() -> Dictionary:
	var cfg := ConfigFile.new()
	if cfg.load(resume_path) != OK:
		return {}
	var info := {}
	for key in ["server", "room", "token", "name"]:
		info[key] = str(cfg.get_value("resume", key, ""))
	if info.server == "" or not RoomCodes.is_valid_format(info.room) or not valid_token(info.token):
		return {}
	return info


static func clear_resume() -> void:
	if FileAccess.file_exists(resume_path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(resume_path))
