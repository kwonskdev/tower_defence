# 계정과 DB: 익명 계정, 판 기록, 순위 (#25)

범위는 이슈 #25의 **단계 1(익명 계정)과 단계 2(판 기록, 서버가 계산한 값만 인정)** 와 서버 쪽 순위 조회다. 단계 3(Google 로그인)과 순위 **화면**은 하지 않았다.
개인정보처리방침/스토어 문서(#27)는 건드리지 않았다. 수집 항목 초안은 아래 6절에 있다.

> **소유자 확인이 필요한 결정**: 코디네이터에게 묻는 질문(msg_49dfdcf5dc98)에 답이 오지 않아 **작업자가 추천안으로 정했다.** 바꾸고 싶으면 아래 "결정" 표의 해당 줄을 알려 주면 된다 (대부분 상수 한두 개나 한 클래스 교체다).

## 1. 결정 (추천안으로 진행)

| 항목 | 결정 | 이유 / 바꾸려면 |
|---|---|---|
| 계정 방식 | **익명 계정만** (회원가입 없음, 기기에 저장한 토큰) | Google 로그인은 단계 3(선택), 스토어 설문/동의가 늘어난다. 나중에 같은 `players` 테이블에 연동 칸만 더하면 된다 |
| DB | **SQLite 파일 하나 + 별도 작은 HTTP 서비스** (`tools/accounts/accounts_service.py`, Python 표준 라이브러리만, 127.0.0.1 전용) | Godot 4.6.3에는 SQLite가 없다 (GDExtension 애드온이 필요). HTTP 호출은 비동기라 DB가 느리거나 죽어도 방 틱이 안 멈추고, 방 서버를 재시작해도 데이터가 안전하다. 서버가 한 대라 SQLite로 충분하다 |
| 서버가 나뉠 때 | **서비스 뒤의 저장소(`Db` 클래스)만** Postgres로 바꾼다. Godot 쪽은 `AccountStore` 인터페이스 하나만 안다 | 7절 |
| 접근부 | Godot: `scripts/accounts/AccountStore.gd`(인터페이스) + `HttpAccountStore`(운영) + `MemoryAccountStore`(테스트/개발) | DB를 아는 코드는 이 구현들과 서비스 파일뿐이다 |
| 순위 | **서버 조회까지** (전체/주간, `hello mode "board"`). 화면은 없음 | 화면은 실기기 확인이 필요하고 #26/#27 UI와 겹친다 |
| 닉네임 | 길이 `Balance.NICKNAME_MAX_LENGTH`(12) 그대로, **서버 전체 유일**(대소문자·공백 무시), 금칙어(`BannedWords.gd`), **변경은 7일에 한 번**(가입 뒤 첫 변경은 즉시) | 길이/기간은 상수 (`MemoryAccountStore.NICK_COOLDOWN_SEC`, 서비스 `NICK_COOLDOWN_SEC`) |
| 앱 삭제 | **계정이 사라지는 것을 감수** (토큰이 기기에만 있다). 기록은 DB에 남지만 되찾을 수 없다 | 단계 3(Google 연동)에서 해결. 스토어/방침에 그렇게 적는다 |
| 백업 | 서비스가 매일 SQLite 스냅샷(`VACUUM INTO`)을 `data\backups`에 만들고 14개 보관. 폴더를 동기화 폴더(OneDrive 등)로 지정하면 PC 밖 사본도 생긴다 | 8절 |
| 토큰 | **클라이언트가 만든 128비트 난수**를 기기에 저장, 서버는 **SHA-256 해시만** 저장. 계정 ID는 서버가 무작위 16자리로 발급해 준다 | 이슈 문구는 "서버가 토큰 발급"이지만 안전성은 같고(추측 불가한 128비트, 해시 저장) 추가 왕복이 없다. 기존 재접속(#23)의 토큰 검증 코드를 그대로 쓴다 |

## 2. 구조

```
[폰] --wss--> [Cloudflare] --> [lanewars-server (Godot, 한 프로세스, 방 여러 개)]
                                   │  hello(token) ─ Accounts.login ──┐
                                   │  판 끝 ─ MatchRecord.build ─ Accounts.record_match ─┤  HTTP (비동기, 127.0.0.1, X-Api-Key)
                                   │                                   ▼
                                   │                        [accounts_service.py] ── SQLite (data\accounts.db, WAL)
                                   └ 방/판은 서버 메모리 (DB가 죽어도 계속)           └ 매일 백업 data\backups
```

- `RoomHub._on_hello`: hello가 오면 `Accounts.login(token, name)`을 **먼저 기다리고**(그동안 그 연결의 다른 메시지는 무시) 방으로 보낸다.
- `NetServer`: 자리마다 `account`(계정 ID)를 들고 있다. 판 중 재접속은 기존대로 토큰 해시로 자리를 찾는다 (계정 서비스를 부르지 않아도 된다).
- `RoomHub._on_room_finished` -> `MatchRecord.build(room, victory, ended_at)` -> `Accounts.record_match`.
- 계정 옵션이 없으면(`--accounts-url`/`--accounts-memory` 없음) 이전과 똑같이 동작한다 (테스트 전부 그대로 통과).

## 3. 실행

개발(계정 서비스 없이): `--accounts-memory` (서버를 끄면 사라진다).

서비스를 직접 띄우기:
```powershell
$env:LANEWARS_ACCOUNTS_KEY = "<16자 이상 비밀 키>"
python tools\accounts\accounts_service.py --db data\accounts.db serve --port 47310     # --db는 서브명령 앞
lanewars-server.exe --headless --server --port=47300 --accounts-url=http://127.0.0.1:47310   # 같은 키를 환경 변수로
```

집 Windows PC (소유자가 할 일, `docs/windows-hosting.md` 6절):
- `deploy\windows\run-accounts.ps1`: 서비스 감시 루프 (키 파일 `data\accounts.key`를 자동 생성). `run-server.ps1`은 `AccountsEnabled = $true`이면 같은 키와 `--accounts-url`을 서버에 넘긴다.
- 설정은 `deploy\windows\settings.ps1` 한 곳 (`AccountsPort`, `AccountsDb`, `AccountsBackupDir`, `AccountsBackupKeep`, `Python`).
- 서버 옵션: `--accounts-url=`, `--accounts-memory`, `--accounts-spool=경로`.

운영 도구 (서비스를 꺼도 쓸 수 있다, `--db` 뒤 서브명령):
```
python tools\accounts\accounts_service.py --db data\accounts.db stats
python tools\accounts\accounts_service.py --db data\accounts.db ban <계정ID 또는 닉네임>      # unban 도 있다
python tools\accounts\accounts_service.py --db data\accounts.db backup --backup-dir <폴더>
python tools\accounts\accounts_service.py --db data\accounts.db purge --inactive-days 180 --match-days 365   # 보관 기간 정리 (자동 실행 아님)
```

## 4. 프로토콜 (PROTOCOL_VERSION 4 -> 5)

- `hello.token`: 이제 **기기의 계정 토큰**이다 (`Identity.account_token()`: 첫 실행에 만들어 `user://account.cfg`에 저장). 메인 메뉴가 이것으로 접속한다. 테스트/봇처럼 `NetClient.token`을 직접 안 채운 클라이언트는 접속마다 임시 토큰(계정이 매번 새로 생김)이다.
- `hello.name`: "원하는 닉네임"이다. 계정이 있으면 서버가 정한 계정 닉네임이 쓰인다 (`welcome.name`).
- `welcome.name_result`: 원하는 이름이 안 받아들여진 이유 `taken`(남이 씀) / `cooldown`(7일 안) / `banned_word`(금칙어) / `unavailable`(계정 저장소를 못 부름), 바뀌었으면 `ok`, 아니면 빈 글자. `welcome.guest`: true면 계정 없이(기록이 안 남는) 입장.
- 새 계정이 겹치는 이름을 원하면 서버가 `이름2`, `이름3`... 으로 정한다.
- 새 거부 사유 `account_banned` (차단된 계정). 신규 계정 한도(서버 전체 분당 30)를 넘으면 **거부하지 않고 계정 없이(게스트) 입장**시킨다 (`name_result = "unavailable"`): 접속을 남발하는 쪽이 정상 신규 플레이어를 쫓아내지 못하게, 막는 것은 DB 쪽(계정 폭증)뿐이다.
- `hello.mode = "board"`, `hello.period = "all"/"week"`: 방에 들어가지 않고 `{"t":"board","period","status":"ok"/"unavailable","rows":[...]}` 하나를 받고 끊긴다 (`NetClient.board_received`). 계정을 만들지 않는다. 결과는 서버가 30초 캐시한다.
- 구버전 앱은 `protocol_mismatch`로 막힌다 (서버를 먼저 올리고 앱을 나중에: `docs/server-hosting.md` 4절과 같다).

## 5. 판 기록

판이 끝나면(전체 승리/패배) `RoomHub`가 방의 **시뮬레이션 상태에서만** 읽어 만든다. 클라이언트가 보낸 점수/결과는 받는 길이 없다 (모르는 메시지는 무시: `tests/test_accounts.gd`가 `score`/`match`/조작된 `cmd`를 보내 확인).

| 필드 | 값 (출처) |
|---|---|
| `match_id` | 서버가 만든 128비트 난수. 같은 ID는 한 번만 저장 (재시도 안전) |
| `started_at`, `ended_at` | 서버 시계 (unix 초) |
| `player_count` | 판에 참여한 인원 (중간에 나간 사람 포함) |
| `result` | `win`/`lose` (보스 `boss_defeated`/`boss_failed`) |
| `boss_level` | 도달한 보스 레벨 (`BossController.level`) |
| `duration_s` | 판 시작부터 끝까지 서버가 센 게임 시간 (초) |
| `version` | 앱 버전 (`application/config/version`) |
| 플레이어별 `account_id`(게스트는 빈 값), `lane`, `nickname`, `boss_damage`(`damage_by_player`), `lane_damage`(유령 구간 레인 데미지), `ghost_boss_damage`(유령 구간 보스 레인 데미지), `left`(판 중 이탈) | 서버 상태 |

- 시작하지 않은 대기방, 모두 나가서 닫힌 판(끝 신호 없이 방이 사라진 경우)은 기록이 없다.
- 순위 기준: **방(팀) 기록**, 보스 도달 레벨 높은 순 -> 승리 먼저 -> 걸린 시간 짧은 순 -> 먼저 끝난 순. 주간 = 최근 7일(굴러가는 창). 참여자 닉네임이 같이 나온다. 인원수가 달라도 같은 줄에 선다 (인원별 구분은 하지 않았다: 필요하면 `player_count`로 나눈다).

## 6. 수집하는 정보 (#27 개인정보처리방침/스토어 설문용 초안)

| 어디에 | 항목 | 용도 | 보관 기간 (초안) |
|---|---|---|---|
| 기기 (`user://account.cfg`) | 계정 토큰(무작위 128비트) | 같은 사람 식별 | 앱을 지울 때까지 |
| 기기 (`user://profile.cfg`, `resume.cfg`) | 닉네임, 서버 주소, 진행 중인 방 코드와 토큰 | 입력 기억, 판으로 돌아오기 | 앱을 지울 때까지 / 판이 끝나면 삭제 |
| 서버 DB `players` | 계정 ID(무작위), **토큰 해시**(SHA-256), 닉네임, 만든 시각, 마지막 접속 시각, 차단 여부, 닉네임 변경 시각 | 계정, 중복 방지, 차단 | 마지막 접속 후 **180일** 뒤 삭제 (제안. `purge --inactive-days 180`. 자동 실행은 아직 아님) |
| 서버 DB `matches`, `match_players` | 판 시각, 인원, 결과, 도달 레벨, 걸린 시간, 앱 버전, 플레이어별 계정 ID·**그 시점의 닉네임**·레인·피해량·이탈 여부 | 기록, 순위 | **365일** 뒤 삭제 (제안. `purge --match-days 365`). 계정이 지워지면 기록은 남지만 계정 연결만 끊긴다 |
| 서버 메모리 | 방, 접속 중인 연결 | 게임 진행 | 판/접속이 끝나면 |
| 서버 로그 | 닉네임, 연결 번호, 방 코드, 거부 사유 (접속 **IP 주소는 로그에 남기지 않는다**) | 운영 | Windows 로그 폴더 `logs\`, 수동 정리 (보관 기간 미정) |

수집하지 않는 것: 이메일, 전화번호, 실명, 기기 ID(광고 ID 포함), 위치, IP 주소(Cloudflare는 자체적으로 본다: Cloudflare 정책 확인 필요). 닉네임은 다른 플레이어에게 보이고(방, 순위), 사용자가 직접 정한 이름이라 실명을 쓰지 말라는 안내가 필요하다.
사용자가 삭제를 요청하는 경로는 아직 없다 (운영자가 `players`에서 계정 ID로 지우는 방법뿐): #27에서 정할 일.

## 7. 서버를 나눌 때 / DB를 바꿀 때

- 방 서버를 여러 대로 나눠도 **계정 서비스는 한 곳**이면 된다 (각 방 서버가 같은 URL을 쓴다. 지금은 127.0.0.1이라 주소만 바꾸고 키를 공유).
- DB를 Postgres로 옮길 때: `accounts_service.py`의 `Db` 클래스(SQL 한 군데)를 바꾼다. HTTP 규칙(위 4절 엔드포인트)과 Godot 코드는 그대로다. 이전은 `players`/`matches`/`match_players` 세 테이블 복사다.
- 서비스 없이 다른 저장소를 쓰려면 `AccountStore`를 상속해 `login`/`record_match`/`leaderboard` 세 개를 구현하고 `ServerMain._make_accounts`에서 고른다.

## 8. DB가 죽었을 때, 백업과 복원

- **진행 중인 판**: 영향 없음. 아는 계정(메모리 캐시)과 판 중 재접속은 서비스 없이도 된다. 서비스를 한 번 못 부르면 10초 동안은 다시 부르지 않고(접속이 기다리지 않게), 모르는 토큰은 **기록이 안 남는 임시(게스트)** 로 입장한다 (`welcome.guest`, `name_result = "unavailable"`).
- **판 기록**: 서버 메모리 대기열 + 디스크(`user://match_spool.jsonl`, `--accounts-spool=`)에 적어 두고 5초부터 60초까지 늘려 가며 다시 보낸다. 서버를 다시 켜면 파일을 읽어 이어서 보낸다. 같은 `match_id`는 한 번만 저장된다. 대기열은 1000개까지, 넘으면 오래된 것부터 버린다 (로그에 남는다).
- **백업**: 서비스가 `--backup-interval-hours`(기본 24)마다 `--backup-dir`에 `accounts-날짜-시각.db`를 만들고 `--backup-keep`(14)개만 남긴다 (`VACUUM INTO`라서 쓰는 중에도 일관된 사본). 폴더를 OneDrive 같은 동기화 폴더로 두면 PC가 망가져도 남는다. 수동: `... backup --backup-dir <폴더>`.
- **복원**: 서비스를 끄고, 쓸 사본을 `data\accounts.db`로 복사해(`-wal`/`-shm` 파일은 지운다) 서비스를 켠다. 사본으로 서비스를 띄워 계정/기록이 그대로임을 `tests/test_accounts.gd`가 확인한다.

## 9. 확인하지 못한 것 (실기기/실서버 필요)

- 집 Windows PC의 작업 스케줄러 자동 시작(`install-autostart.ps1`의 계정 서비스 작업 등록), `run-server.ps1`이 서버 exe와 함께 도는 것(서버 exe를 빌드하지 않았다: 인자 구성만 확인).
- 실제 폰에서 첫 실행 -> 계정 생성 -> 앱 재실행 시 같은 계정, 앱 삭제 후 새 계정.
- Cloudflare 터널 뒤에서의 동작(접속 IP는 원래 보이지 않는다).
- 부하: 계정 서비스 호출은 접속 때와 판 끝 때뿐이라 가볍지만 `tools/bench`로 재지 않았다.
