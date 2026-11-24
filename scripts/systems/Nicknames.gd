class_name Nicknames
## 닉네임 (#22). 클라이언트가 입력하고, 입력이 없으면 형용사+명사로 자동 만든다 ("아름다운사과", "더러운컴퓨터").
## 서버는 받은 이름을 항상 다시 정리한다 (sanitize): 밖에서 온 글자를 그대로 화면에 올리지 않는다.
## 중복은 서버가 뒤에 숫자를 붙여 구별한다 (unique). 계정(#25)이 생기면 계정 이름이 이 값을 대체한다.

const ADJECTIVES := [
	"아름다운", "더러운", "용감한", "졸린", "배고픈", "수상한", "빠른", "느긋한", "엉뚱한", "거대한",
	"작은", "화난", "행복한", "차가운", "뜨거운", "조용한", "시끄러운", "똑똑한", "멍한", "날쌘",
	"듬직한", "깜찍한", "무서운", "심심한", "당당한", "수줍은", "씩씩한", "느린", "반짝이는", "투명한",
]
const NOUNS := [
	"사과", "컴퓨터", "고양이", "감자", "로봇", "우산", "냉장고", "호랑이", "라면", "자전거",
	"펭귄", "선풍기", "토마토", "두더지", "망치", "구름", "거북이", "피자", "오리", "달팽이",
	"의자", "도토리", "문어", "트럭", "수박", "곰", "비행기", "김밥", "참새", "화분",
]
const SAVE_PATH := "user://profile.cfg"


## 형용사+명사 한 쌍을 뽑는다. rng를 주면 그 랜덤으로 (테스트용), 없으면 새로 뽑는다.
static func generate(rng: RandomNumberGenerator = null) -> String:
	var r := rng if rng != null else RandomNumberGenerator.new()
	if rng == null:
		r.randomize()
	return str(ADJECTIVES[r.randi_range(0, ADJECTIVES.size() - 1)]) + str(NOUNS[r.randi_range(0, NOUNS.size() - 1)])


## 밖에서 온 이름을 화면에 올려도 되는 모양으로: 제어문자 제거, 앞뒤/연속 공백 정리, 최대 길이. 비면 "".
static func sanitize(raw: String) -> String:
	var out := ""
	for i in range(raw.length()):
		var code := raw.unicode_at(i)
		if code < 32 or code == 127 or (code >= 0x80 and code < 0xA0) or _is_invisible(code):
			continue  # 제어문자, 보이지 않는 글자, 글자 방향 뒤집기
		out += raw[i]
	return " ".join(out.strip_edges().split(" ", false)).left(Balance.NICKNAME_MAX_LENGTH).strip_edges()


## 화면에 보이지 않거나 글자 방향을 바꿔 다른 사람 이름을 가짜로 보이게 만드는 글자인가
##   U+200B~200F 폭 없는 글자/방향 표시, U+2028~2029 줄/문단 구분, U+202A~202E 방향 덮어쓰기, U+2066~2069 방향 격리, U+061C 아랍어 글자 표시, U+FEFF
static func _is_invisible(code: int) -> bool:
	return (code >= 0x200B and code <= 0x200F) or code == 0x2028 or code == 0x2029 or (code >= 0x202A and code <= 0x202E) \
		or (code >= 0x2066 and code <= 0x2069) or code == 0x061C or code == 0xFEFF


## taken(이미 쓰는 이름들)에 없는 이름으로. 겹치면 "이름2", "이름3"... (길이 제한 안에서 앞을 줄여 붙인다). 이름이 비면 자동 생성.
static func unique(raw: String, taken: Array, rng: RandomNumberGenerator = null) -> String:
	var base := sanitize(raw)
	if base == "":
		base = generate(rng)
	if not taken.has(base):
		return base
	var n := 2
	while true:
		var suffix := str(n)
		var candidate := base.left(Balance.NICKNAME_MAX_LENGTH - suffix.length()) + suffix
		if not taken.has(candidate):
			return candidate
		n += 1
	return base  # 도달하지 않는다


## 저장된 내 닉네임. 없으면 자동 생성해서 저장한다 (다음 실행에도 같은 이름).
static func load_saved() -> String:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		var saved := sanitize(str(cfg.get_value("profile", "nickname", "")))
		if saved != "":
			return saved
	var made := generate()
	save(made)
	return made


## 내 닉네임을 저장한다 (정리한 값. 비면 저장하지 않고 false)
static func save(nickname: String) -> bool:
	var clean := sanitize(nickname)
	if clean == "":
		return false
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)  # 다른 값이 생기면 같이 보존
	cfg.set_value("profile", "nickname", clean)
	return cfg.save(SAVE_PATH) == OK
