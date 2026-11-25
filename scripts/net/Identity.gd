class_name Identity
## 재접속 때 "같은 사람인가"를 정하는 한 곳 (#23). 지금은 기기 임시 토큰이고, 계정(#25)이 생기면 이 파일만 바꾼다
## (서버의 authorize가 계정 ID를 보도록, 클라이언트의 new_token/hello 필드가 계정 세션을 싣도록).
##  - 클라이언트는 방에 들어갈 때 무작위 토큰을 만들어 hello에 싣는다. 닉네임만으로는 자리를 못 가져간다 (닉네임은 겹쳐도 되고 남이 쓸 수 있다).
##  - 서버는 토큰 원문을 보관하지 않고 해시(SHA-256)만 둔다. 재접속하는 쪽이 같은 토큰을 내면 그 해시가 같다.
##  - 앱이 죽었다 켜져도 돌아올 수 있게 (방 코드, 서버 주소, 토큰)을 기기에 저장한다 (resume 파일).

const TOKEN_BYTES := 16            # 128비트
const TOKEN_HEX_LENGTH := 32
const RESUME_PATH := "user://resume.cfg"

static var resume_path := RESUME_PATH   # 테스트는 다른 경로를 쓴다


## 새 임시 토큰 (소문자 16진수 32글자). 암호용 난수를 쓴다.
static func new_token() -> String:
	return Crypto.new().generate_random_bytes(TOKEN_BYTES).hex_encode()


## 밖에서 온 토큰이 모양은 맞는가 (길이와 16진수만). 모양이 틀리면 없는 것으로 본다.
static func valid_token(token) -> bool:
	if typeof(token) != TYPE_STRING or token.length() != TOKEN_HEX_LENGTH:
		return false
	return token.is_valid_hex_number(false) and token == token.to_lower()


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
