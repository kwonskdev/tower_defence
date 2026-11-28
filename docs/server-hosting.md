# 서버 빌드와 호스팅 (#24)

헤드리스 서버를 빌드하고 올리는 방법과 측정 결과. **소유자 결정(#24)**: 1차 호스팅은 **집 Windows PC + Cloudflare Tunnel** (`docs/windows-hosting.md`), **한 프로세스가 여러 방**(RoomHub), 도메인은 소유자가 구매. 나중에 VPS로 옮길 수 있게 Linux 빌드/Docker(아래)도 유지한다. **실제 원격 배포, Cloudflare 터널 연결, 폰 2대 실기기 확인은 아직 하지 않았다** (맨 아래 "소유자가 할 일").

**계정과 판 기록(#25)**: 서버는 `--accounts-url=`로 별도 계정 서비스(SQLite)에 붙을 수 있다 (옵션이 없으면 계정 없이 이전처럼 동작). `docs/accounts-and-db.md`, Windows 실행은 `docs/windows-hosting.md` 6절. Docker/VPS 구성에는 아직 계정 서비스를 넣지 않았다 (서비스는 어디서든 `python tools/accounts/accounts_service.py`로 돈다).

## 1. 빌드와 실행

```bash
# 필요: Godot 4.6.3 + 같은 버전 export 템플릿(Linux). GODOT에 실행 파일 경로
GODOT=/path/to/godot tools/server/build.sh        # -> build/server/lanewars-server.x86_64 (약 70MB, pck 내장)
tools/server/run.sh 47300 --max-rooms=16           # 빌드 결과가 있으면 그것을, 없으면 Godot로 프로젝트를 바로 실행
```

- export 프리셋 `Linux Server` (`export_presets.cfg`): 전용 서버(dedicated_server) 모드라 화면용 리소스가 빠진다.
- 직접 실행: `lanewars-server.x86_64 --headless --server --port=47300 [옵션]`

서버 옵션 (전체 설명은 `scripts/server/ServerMain.gd` 머리 주석):

| 옵션 | 기본 | 뜻 |
|---|---|---|
| `--port=N` | (필수) | 방 코드 서버로 연다 |
| `--max-rooms=N` | 64 | 동시에 열 수 있는 방 수 |
| `--max-rooms-per-addr=N` | 3 | 주소당 방장 방 수. **프록시 뒤에서는 `--max-rooms`와 같게** |
| `--max-fps=N` | 60 | 서버 프레임 상한 (0 = 제한 없음, 측정용) |
| `--metrics-interval=N` | 60 | 지표 로그 간격(초, 0 = 끔) |
| `--tls-cert= --tls-key=` | - | 서버가 직접 wss. 보통은 아래 리버스 프록시를 쓴다 |

## 2. 배포 (작은 VPS + Docker)

파일: `deploy/Dockerfile`, `deploy/docker-compose.yml`, `deploy/Caddyfile`, `deploy/.env.example`, `deploy/lanewars.service`(Docker 없이 systemd), `deploy/nginx.conf.example`.

```bash
tools/server/build.sh                      # 서버 바이너리 (VPS에서 하거나 빌드한 파일을 복사)
cp deploy/.env.example deploy/.env         # DOMAIN, MAX_ROOMS 수정
docker compose -f deploy/docker-compose.yml --env-file deploy/.env up -d --build
```

- 서버는 컨테이너 안에서 평문 ws(47300)로 열고, **Caddy가 443에서 TLS(Let's Encrypt 자동)를 맡아 wss로 넘긴다.** 서버 포트는 밖에 열지 않는다. 클라이언트 서버 주소는 `wss://<도메인>`.
- 죽으면 다시 뜬다: compose `restart: unless-stopped` (또는 systemd `Restart=always`).
- 방화벽: 80, 443만 연다 (80은 인증서 발급 확인용).

### 프록시 뒤 주소 (이슈 #24 메모)
Godot 4.6.3 WebSocket 서버는 `X-Forwarded-For`를 읽지 못해 모든 접속이 프록시 주소로 보인다. 그래서 (1) 주소당 방 한도를 `--max-rooms`와 같게 올려 두었고(compose/systemd 예시), (2) 잘못된 방 코드 제한(주소당 분당 5회)이 **사용자 전체에 한 번에 걸린다**: 누가 5번 틀리면 1분간 모두의 방 입장이 막힌다. 작은 규모에서는 감수하고, 커지면 앞단에서 속도 제한을 하거나 서버를 직접 wss로 열어(`--tls-cert`) 실제 주소를 쓰게 한다.

## 3. 관측

- 로그는 표준 출력으로 나온다: `docker compose logs -f lanewars`, systemd는 `journalctl -u lanewars -f`.
- `--metrics-interval`(기본 60초)마다 한 줄:
  `METRICS rooms=3 (대기 1, 진행 2, 끝남 0) players=9 conns=9 monsters=412 frame_avg=16.7ms frame_max=21.9ms work_avg=2.1ms work_max=6.4ms mem=212MB peak_rooms=3 peak_conns=9 [cpu=35% rss=240MB]`
  - `frame_*` 프레임 사이 시간(60fps면 16.7 근처가 정상), `work_*` 한 프레임에서 서버가 일한 시간, `cpu`/`rss`는 Linux에서만(코어 1개 = 100%).
  - 확인: `docker compose logs lanewars | grep METRICS | tail`.
- 접속 거부(버전 불일치 등)는 `NETWORK` 경고로 남는다.

## 4. 버전 불일치

서버와 클라이언트의 `PROTOCOL_VERSION`/스냅샷 버전이 다르면 hello 단계에서 `protocol_mismatch`로 거부되고, 거부 메시지에 서버 버전이 실린다. 앱은 "앱을 최신 버전으로 업데이트하세요"를 보여주고, 서버가 앱보다 낮으면(서버를 아직 못 올렸다) "서버가 아직 … 잠시 뒤에 다시 시도하세요"를 보여준다. 배포 순서: **서버를 먼저 올리고 앱을 나중에** (구버전 앱은 막힘).

## 5. 측정 결과

도구: `tools/bench/run_bench.ps1`(Windows) / `run_bench.sh`(Linux). 운영과 같은 방 코드 서버에 봇(방당 8명, 실제 클라이언트로 접속, 사람과 같은 건설/몬스터 보내기 명령, 골드 치트 없음)을 붙여 판 시작 뒤 CPU/메모리/프레임을 잰다. `-Stack N`은 방마다 보스 레인에 몬스터를 N마리 쌓는 시험이다(쌓는 것만 측정 도구가 하고 서버 코드는 그대로).

**측정 환경: 개발 PC (Windows 10, 24스레드, Godot 4.6.3 에디터 빌드, 서버·봇 같은 PC).** Linux VPS의 CPU 코어 하나는 이보다 느릴 수 있어서 **절대값이 아니라 상대 비교용**이다. 실제 VPS에서 `run_bench.sh`로 다시 재야 한다 (아래 확인 목록).

| 경우 (판 시작 뒤 60~90초, 서버 60fps 상한) | CPU (코어 1개 = 100%) | 메모리 (프로세스 최대) | 프레임 일한 시간 평균 구간 최대 / 한 프레임 최대 | 몬스터 최대 |
|---|---|---|---|---|
| 방 1 (8명) | 19% | 121MB | 5.7ms / 374ms | 128 |
| 방 2 (16명) | 33% | 122MB | 32ms / 491ms | 248 |
| 방 4 (32명) | 57% | 134MB | 148ms / 1379ms | 500 |
| 방 1 + 보스 레인 몬스터 300 | 29% | 123MB | 4.6ms / 488ms | 436 |
| 방 1 + 몬스터 1000 | 48% | 141MB | 15ms / 1565ms | 1135 |
| 방 1 + 몬스터 3000 | 84% | 195MB | 94ms / 1793ms | 3099 |

해석 (측정된 것만):
- **메모리**: 방 하나 약 20~30MB 증가, 프로세스 기본 약 85~120MB. 방 수보다 CPU가 한도다.
- **평소 CPU는 낮다**: 방 하나가 코어의 약 20%. 하지만 **프레임 하나가 0.4~1.8초 걸리는 끊김(hitch)이 방 1개에서도 나온다** (파도가 시작되어 몬스터가 나오거나 봇이 한꺼번에 지을 때). 같은 프로세스 안의 **모든 방이 그동안 같이 멈춘다** (단일 스레드). 방 4개에서는 평균 프레임이 148ms까지 올라 60fps 예산(16.7ms)을 크게 넘었다.
- 몬스터 3000마리(보스 레인에 쌓임)는 코어 하나의 84%, 구간 평균 94ms/프레임: 방 하나만으로 한 코어가 찬다.
- 끊김의 원인은 이 PR에서 조사하지 않았다 (의심: 경로 재계산(A*), 헤드리스에서도 도는 몬스터/타워 `queue_redraw`와 `_draw`). **성능 개선은 별도 이슈로 하는 게 맞다.** 이 측정 도구로 전후를 비교할 수 있다.
- 서버 CPU 사용은 스냅샷 전송(클라이언트 8명 분)을 포함한다.

### 동시 방 수 한도 (권장값: 3)

측정 PC는 소유자 집 PC와 같은 CPU다 (Intel Core i7-13700KF 16코어/24스레드, RAM 32GB, Windows 10 Home). 판단 근거:

- 서버는 한 프로세스이고 Godot 시뮬레이션은 사실상 **코어 하나**만 쓴다 (24스레드가 있어도 방이 늘어도 다른 코어로 퍼지지 않는다). 그래서 한도는 "코어 하나의 몇 %"로 본다.
- 코어 하나 사용률: 방 1개 19%, 2개 33%, 4개 57% -> 방 하나당 약 14~19%, **방 약 6~7개에서 코어 하나가 찬다** (직선 추정. 4개까지만 잼).
- 소유자 기준(감당 가능한 수의 40~50%만 사용, 여유율 50~60%)을 적용: 6~7개 x 약 45% = **3개**. 집 PC는 게임/다른 작업과 CPU를 나눠 쓰므로 이 여유가 필요하다.
- **하지만 부드러움은 방 수와 별개로 문제다**: 방 1개에서도 한 프레임이 0.4~0.6초 걸리는 끊김이 나왔고(파도 시작/봇이 한꺼번에 지을 때), 방 4개에서는 평균 프레임이 예산을 크게 넘었다(위 표). 방을 3개로 제한해도 한 방의 끊김이 나머지 방에 퍼진다. 3은 "CPU로는 안전한 값"이고, 끊김은 시뮬레이션 성능 개선(별도 이슈)이 필요하다.
- 메모리는 문제가 아니다 (방 4개에서 134MB).

값은 `deploy/windows/settings.ps1`의 `MaxRooms` 한 곳(서버 옵션 `--max-rooms`로 전달)에서 바꾼다. 넘으면 새 방 만들기/빠른 시작은 "서버가 가득 찼습니다"로 거부되고 이미 있는 방에는 계속 들어올 수 있다 (`tests/test_server_hosting.gd`). 성능이 개선되면 `tools/bench/run_bench.ps1`로 다시 재서 올린다.

### 프로세스 구조 (결정됨: 한 프로세스 여러 방)
아래는 결정 근거로 남긴 메모. 한 프로세스 안의 방들은 단일 스레드를 나눠 쓰므로 **끊김이 다른 방으로 퍼진다**는 점이 위험이고, 그래서 동시 방 수 한도(`--max-rooms`, Windows는 `settings.ps1`의 `MaxRooms`)를 보수적으로 둔다. 끊김 원인 조사/개선은 별도 이슈.

### (참고) 구조에 대한 근거
한 프로세스에 여러 방은 코드가 이미 그렇게 되어 있고(RoomHub), 구현은 쉽지만 **한 방의 끊김이 모든 방에 퍼진다.** 방마다 프로세스로 하면 끊김이 격리되고 코어를 나눠 쓸 수 있지만, 프로세스당 기본 메모리가 약 85~120MB 들고 포트/방 코드 라우팅(프록시가 방 코드로 프로세스를 찾는 중계)이 새로 필요하다 (현재 코드에는 없다). 소규모에서 가장 단순한 절충: **프로세스 하나 = 방 몇 개(2~4)**로 두고, VPS 코어 수만큼 프로세스를 띄워 포트를 나눠 쓰는 것이다 (이 경우 클라이언트에게 서버 주소를 나누어 주는 방법이 필요 → 이것도 결정 사항).

## 6. 호스팅 비교 (참고: 가격은 이 PR에서 공식 가격표로 확인하지 못했다)

| 후보 | 월 비용 | 비고 |
|---|---|---|
| **집 Windows PC + Cloudflare Tunnel (선택됨)** | 전기료 + 도메인(연 단위) | 포트 포워딩 없음, TLS는 Cloudflare. PC가 꺼지거나 절전이면 서버도 멈춘다 -> `docs/windows-hosting.md` 절전 방지. 집 인터넷 상향 대역폭/지연이 한도 |
| 작은 VPS + Docker (이전 단계에서 옮길 곳) | 몇 달러~십수 달러 (미확인) | Dockerfile/compose/Caddy 준비됨 (2절). 서울 리전 존재만 확인 |
| 컨테이너 서비스 | 위보다 높음 | 지금 규모에 과함 |

## 7. 소유자가 할 일 (단계별, 아직 하지 않음)

집 Windows PC 기준 (자세한 명령은 `docs/windows-hosting.md`):

1. 도메인 구매 후 Cloudflare에 연결.
2. 집 PC에 Godot 4.6.3 + export 템플릿 설치, `tools/server/build-windows.ps1`로 서버 빌드.
3. `settings.local.ps1`에서 `MaxRooms` 등 설정, `run-server.ps1` 실행해 로그/METRICS 확인, 관리자 PowerShell에서 `install-autostart.ps1`.
4. 절전/최대 절전 끄기. 서버 프로세스를 강제 종료해 자동으로 다시 뜨는지, PC 재부팅 뒤 서버가 자동으로 뜨는지 확인.
5. `cloudflared` 터널 생성, 도메인 연결, 서비스 등록. `https://<도메인>` 응답 확인.
6. `tools/bench/run_bench.ps1`을 집 PC에서 방 1/2/4와 `-Stack 1000`으로 돌려 결과를 알려 준다 -> `MaxRooms` 확정.
7. `project.godot`의 `[lanewars] network/default_server`에 `wss://<도메인>`을 넣고 앱 빌드.
8. **폰 2대**로 접속해 판을 끝까지 한다 (이슈 체크리스트 2번). 방 대기 상태로 3분 이상 두어 Cloudflare가 끊지 않는지도 본다.
9. 구버전 앱으로 접속해 업데이트 안내가 뜨는지 확인(서버만 올린 상태).
10. (선택) Linux 서버 빌드(`tools/server/build.sh`)를 Linux나 WSL에서 한 번 실행해 본다: 이 PR에서는 WSL이 없어 **Linux 바이너리를 실행해 보지 못했다** (빌드/내보내기만 확인).
