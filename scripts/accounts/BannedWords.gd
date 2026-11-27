class_name BannedWords
## 닉네임 금칙어 (#25). 서버가 계정을 만들거나 닉네임을 바꿀 때 검사한다 (Nicknames.is_clean).
## 목록은 최소한의 시작점이다: 운영하면서 이 파일 한 곳에 단어를 더한다 (소유자가 보강).
## 비교는 정규화한 글자(Nicknames.screen_text: 소문자, 공백/기호 제거)로 한다.

## 이 글자가 이름 어디에 들어 있어도 막는다 (욕설, 운영자 사칭)
const CONTAINS := [
	"시발", "씨발", "씨팔", "시팔", "병신", "지랄", "개새끼", "좆", "썅", "니미", "섹스", "느금",
	"fuck", "shit", "bitch", "nigger", "nigga", "faggot", "cunt",
	"운영자", "관리자", "운영진", "lanewars", "레인워즈",
]
## 이름 전체가 이것과 같을 때만 막는다 (짧아서 다른 낱말에 들어 있을 수 있는 것)
const EXACT := ["gm", "admin", "system", "server", "시스템", "서버", "공지", "null", "undefined", "운영"]


static func contains_banned(screened: String) -> bool:
	if screened == "":
		return false
	if EXACT.has(screened):
		return true
	for word in CONTAINS:
		if screened.contains(word):
			return true
	return false
