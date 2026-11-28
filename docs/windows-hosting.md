# 집 Windows PC에서 서버 돌리기 + Cloudflare Tunnel (#24)

소유자 결정: 서버는 집 Windows 데스크탑에서 **네이티브로** 돌리고(WSL 사용 안 함), **Cloudflare Tunnel**로 공개한다. 포트 포워딩 없음, wss(TLS)는 Cloudflare가 처리한다. 앱에는 IP가 아니라 **도메인**을 쓴다. 나중에 VPS로 옮길 수 있게 Linux 빌드/Dockerfile(`docs/server-hosting.md`)도 유지한다.
테스트용 앱으로 집 Wi-Fi/밖에서 먼저 붙어 보는 방법: `docs/test-connection.md`.

```
[폰] --wss://game.example.com--> [Cloudflare] ==터널(나가는 연결)==> [cloudflared (집 PC)] --ws://localhost:47300--> [lanewars-server.exe]
```

> 아래 단계는 **소유자가 직접 해야 하는 일**이다 (Cloudflare 계정, 도메인 구매, 집 PC). 이 저장소의 스크립트는 개발 PC에서 서버 빌드/실행/자동 재시작까지만 확인했다. Cloudflare 터널 연결과 폰 접속은 확인하지 못했다.

## 1. 서버 빌드 (집 PC)

1. Godot 4.6.3과 **같은 버전의 export 템플릿**을 설치한다 (에디터: 에디터 > 내보내기 템플릿 관리).
2. 저장소를 받고:
   ```powershell
   powershell -ExecutionPolicy Bypass -File tools\server\build-windows.ps1 -Godot C:\path\Godot_v4.6.3-stable_win64_console.exe
   ```
   결과: `build\server-win\lanewars-server.exe` (약 100MB, 화면 리소스 제외 전용 서버).

## 2. 설정 (동시 방 수 한도 등)

`deploy\windows\settings.ps1`을 `settings.local.ps1`로 복사해 고친다 (git에 안 올라감). **방 수 한도는 `MaxRooms` 한 곳**이다.

- `MaxRooms`: 동시 방 수. 넘으면 새 방 만들기/빠른 시작이 "서버가 가득 찼습니다"로 거부된다 (이미 있는 방에는 계속 들어올 수 있다). 값을 정하는 방법은 아래 5절.
- `Port`(기본 47300), `MetricsInterval`, `RestartDelaySec`.

## 3. 실행 / 자동 시작 / 재시작

```powershell
powershell -ExecutionPolicy Bypass -File deploy\windows\run-server.ps1      # 직접 실행 (죽으면 RestartDelaySec 뒤 다시 시작)
# 관리자 PowerShell:
powershell -ExecutionPolicy Bypass -File deploy\windows\install-autostart.ps1          # 부팅 시 자동 시작 등록(작업 스케줄러 "LaneWarsServer". 서버는 SYSTEM이 아니라 **일반 계정**(기본: 등록한 현재 사용자, `-User 계정`으로 서버 전용 일반 계정도 가능, S4U/Limited)으로 돈다. 관리자 권한은 등록할 때만 필요하다)
powershell -ExecutionPolicy Bypass -File deploy\windows\install-autostart.ps1 -Remove  # 제거
```

- `run-server.ps1`이 서버 프로세스를 감시한다. 서버가 죽으면(종료 코드가 로그에 남는다) 다시 띄운다. 개발 PC에서 서버 프로세스를 강제 종료해 **자동으로 새 프로세스가 뜨는 것을 확인했다**.
- 작업 스케줄러 등록은 감시 루프 자체가 죽었을 때 1분 간격으로 다시 시작하게 해 둔다 (등록 스크립트는 이 PC에서 실행해 보지 않았다).
- 로그: `logs\server-YYYYMMDD.log`. 지표 줄: `findstr METRICS logs\server-*.log`. 줄 설명은 `docs/server-hosting.md` 3절 (Windows에서는 `cpu`/`rss`는 안 나온다: 작업 관리자에서 본다).

### 절전 방지 (중요)
PC가 잠들면 서버가 끊긴다.
- 설정 > 시스템 > 전원: **절전 모드 "안 함"** (전원 연결 시), 디스플레이 끄기는 상관없다.
- 관리자 PowerShell: `powercfg /change standby-timeout-ac 0` 와 `powercfg /change hibernate-timeout-ac 0`.
- Windows 업데이트의 자동 재부팅 시간을 사용 시간 밖으로 지정한다. 재부팅돼도 위 작업 스케줄러로 서버와 cloudflared가 다시 뜬다 (판 중인 방은 사라진다).
- 노트북이면 덮개를 닫아도 절전하지 않게 설정.

## 4. Cloudflare Tunnel 설정

전제: Cloudflare 계정(무료), 도메인(예: `example.com`)을 Cloudflare DNS에 연결(네임서버 변경) 해 둠. 서브도메인 예: `game.example.com`.

1. **cloudflared 설치**: `winget install --id Cloudflare.cloudflared` (또는 공식 다운로드).
2. **로그인**: `cloudflared tunnel login` → 브라우저에서 도메인 선택.
3. **터널 만들기**: `cloudflared tunnel create lanewars` → 터널 ID와 자격 파일(`C:\Users\<사용자>\.cloudflared\<ID>.json`) 생성.
4. **설정 파일** `C:\Users\<사용자>\.cloudflared\config.yml`:
   ```yaml
   tunnel: <터널 ID>
   credentials-file: C:\Users\<사용자>\.cloudflared\<터널 ID>.json
   ingress:
     - hostname: game.example.com
       service: http://localhost:47300      # WebSocket(ws)이 http로 올라온다. wss는 Cloudflare 쪽에서 처리
     - service: http_status:404
   ```
5. **도메인 연결**: `cloudflared tunnel route dns lanewars game.example.com`
6. **서비스 등록** (관리자 PowerShell, 부팅 시 자동 시작): 설정 파일을 시스템 위치로 두고 등록한다.
   ```powershell
   # 서비스는 SYSTEM으로 돌아서 사용자 폴더의 설정을 못 읽는다: 복사한다
   New-Item -ItemType Directory -Force C:\Windows\System32\config\systemprofile\.cloudflared
   Copy-Item $env:USERPROFILE\.cloudflared\* C:\Windows\System32\config\systemprofile\.cloudflared\
   # config.yml 안의 credentials-file 경로도 위 위치로 고친다
   cloudflared service install
   ```
   서비스는 죽으면 다시 뜨고(Windows 서비스 복구 설정) 부팅 시 자동 시작된다. 확인: `Get-Service cloudflared`.
7. **확인**: 서버가 떠 있는 상태에서 `curl -i https://game.example.com` 이 응답하면(WebSocket이 아니라서 400류 응답이 정상) 터널과 TLS가 동작하는 것이다. 앱에서는 서버 주소 `wss://game.example.com` (포트 없음).

### 앱에 들어가는 서버 주소
`project.godot`의 `[lanewars] network/default_server="wss://game.example.com"` **한 곳**만 바꾼다 (메인 메뉴 서버 주소 입력칸의 기본값). 비어 있으면 로컬 개발 서버(`127.0.0.1:47300`).

### Cloudflare 유휴 WebSocket 끊김
Cloudflare가 데이터가 안 오가는 WebSocket을 약 100초에 끊는다는 비공식 보고가 있다. 우리 쪽은: 판 중엔 클라이언트가 3초마다 ping, 서버가 스냅샷을 계속 보낸다. 대기방(로비)에서는 클라이언트가 60초마다 ping을 보내고, **서버가 25초 동안 아무것도 안 보낸 연결에는 작은 keepalive(pong)를 보낸다** (`NetProtocol.KEEPALIVE_SEC`). 그래서 양방향 모두 100초보다 훨씬 짧은 간격으로 데이터가 오간다. 이 동작은 자동 테스트로 확인했고(`tests/test_server_hosting.gd`), **실제 Cloudflare 위에서 몇 분 이상 대기해 끊기지 않는지는 확인하지 못했다** (위 7번 이후 소유자 확인 항목).

### 알아둘 점 (프록시 뒤 주소)
터널 뒤에서는 모든 접속이 `localhost` 한 주소로 보인다. 그래서 설정이 주소당 방 한도를 `MaxRooms`와 같게 올려 두고, "잘못된 방 코드 5번"의 1분 입장 제한이 사용자 전체에 걸린다 (`docs/server-hosting.md` 2절).

## 5. 동시 방 수 한도 정하기 (집 PC에서 측정)

개발 PC 측정값은 `docs/server-hosting.md` 5절. 한도는 **집 PC 사양에서 다시 재서** 정한다.

```powershell
# 서버/봇이 같은 PC에서 돈다 (실제 서비스에서도 서버만 돈다: 봇이 쓰는 CPU는 서버 몫이 아니다)
powershell -ExecutionPolicy Bypass -File tools\bench\run_bench.ps1 -Godot C:\path\Godot_v4.6.3-stable_win64_console.exe -Rooms 1 -Seconds 90
... -Rooms 2 / -Rooms 4              # 방 수를 늘려 가며
... -Rooms 1 -Stack 1000             # 보스 레인에 몬스터 1000마리 쌓았을 때 (최대 몬스터)
```

출력 한 줄: `cpu`(코어 하나 = 100%), `peak_ws`(메모리), `work_avg/work_max`(한 프레임에서 서버가 일한 시간 ms), `frame_max`(가장 긴 프레임), `monsters_max`. 판단 기준 제안: `work_avg`가 8ms(60fps 예산 16.7ms의 절반)를 넘거나 `frame_max`가 1초 이상 나오기 시작하는 방 수의 **절반 이하**를 `MaxRooms`로 한다. 결과를 알려 주면 값을 정한다.

## 6. 계정/판 기록 서비스 (#25)

방 서버 옆에서 작은 Python 서비스(`tools/accounts/accounts_service.py`, SQLite 파일 하나)가 계정과 판 기록을 저장한다. **자세한 내용은 `docs/accounts-and-db.md`** (결정, 규칙, 수집 항목, 백업/복원).

- 필요한 것: **Python 3** (표준 라이브러리만 쓴다. 따로 설치할 패키지 없음). `deploy\windows\settings.ps1`의 `Python`이 실행 파일 이름이다 (기본 `python`).
- 실행: `powershell -ExecutionPolicy Bypass -File deploy\windows\run-accounts.ps1` (죽으면 다시 시작, 로그 `logs\accounts-*.log`). `install-autostart.ps1`이 `LaneWarsAccounts` 작업도 같이 등록한다. 서비스는 **127.0.0.1에만** 열려서 터널/포트 포워딩과 무관하다.
- 방 서버(`run-server.ps1`)는 `AccountsEnabled = $true`이면 `--accounts-url=http://127.0.0.1:47310`과 같은 키(`data\accounts.key`, 처음 실행에 자동 생성)로 서비스에 붙는다. **서비스가 죽어도 방 서버와 진행 중인 판은 영향이 없다** (모르는 접속은 기록 없이 임시 입장, 판 기록은 대기열에 쌓였다가 복구되면 저장).
- 데이터: `data\accounts.db` (DB), `data\backups\` (매일 스냅샷 14개), `data\accounts.key` (API 키). 모두 git에 안 올라간다. **`AccountsBackupDir`를 OneDrive 같은 동기화 폴더로 바꾸면 PC가 고장나도 백업이 남는다.**
- 방 서버가 못 보낸 판 기록 대기열은 서버 사용자 폴더의 `user://match_spool.jsonl`(Windows: `%APPDATA%\Godot\app_userdata\Lane Wars\`)에 적힌다.
- **보관 기간 자동 정리(#66)**: 계정 서비스가 켜질 때와 24시간마다 마지막 접속 후 365일 지난 계정을 판 기록과 함께, `logs\`의 30일 지난 `*.log`를 지운다 (`settings.ps1`의 `AccountsPurgeHours`/`AccountsInactiveDays`/`LogRetentionDays`). 작업 스케줄러 등록은 필요 없다. 로그에 `보관 기간 정리: {...}` 줄이 매일 남는지 본다. 삭제 요청 처리 명령과 절차는 **`docs/account-deletion.md`**.
- 이 PC에서 실행해 확인하지 않은 것: 작업 스케줄러 등록, 서버 exe와 같이 도는 것 (docs/accounts-and-db.md 9절).
