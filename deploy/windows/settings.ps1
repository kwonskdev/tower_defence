# Lane Wars Windows 서버 설정 (#24). 값을 바꾸는 곳은 여기 한 곳이다 (동시 방 수 한도 포함).
# 이 파일을 deploy\windows\settings.local.ps1 로 복사해 고치면 그 파일이 우선한다 (git에 안 올라간다).
$Settings = @{
    # 서버 실행 파일: tools\server\build-windows.ps1 이 만드는 파일
    ServerExe        = "build\server-win\lanewars-server.exe"
    Port             = 47300        # cloudflared가 이 포트로 넘긴다 (밖에는 열지 않는다)
    MaxRooms         = 3            # 동시 방 수 한도 (권장값 근거: docs/server-hosting.md 5절 "동시 방 수 한도"). 넘으면 새 방 만들기는 "서버가 가득 찼습니다"로 거부된다. 집 PC 사양에 맞춰 tools\bench\run_bench.ps1로 재고 정한다 (docs\server-hosting.md)
    MetricsInterval  = 60           # 초. 지표(METRICS) 로그 간격
    LogDir           = "logs"       # 서버 출력 로그 (프로젝트 폴더 기준, 날짜별)
    RestartDelaySec  = 3            # 서버가 죽으면 이만큼 뒤에 다시 시작
    # ---- 계정/판 기록 서비스 (#25, docs/accounts-and-db.md). 방 서버와 따로 도는 작은 Python 서비스 (127.0.0.1에만 열림) ----
    AccountsEnabled     = $true            # $false면 방 서버가 계정 없이 이전처럼 돈다 (닉네임/기록 저장 없음)
    Python              = "python"         # Python 3 실행 파일 (표준 라이브러리만 쓴다)
    AccountsPort        = 47310
    AccountsDb          = "data\accounts.db"        # SQLite 파일 (프로젝트 폴더 기준. 절대 경로도 된다)
    AccountsKeyFile     = "data\accounts.key"       # 방 서버 -> 계정 서비스 API 키 (없으면 자동 생성, git에 안 올라감)
    AccountsBackupDir   = "data\backups"            # 매일 SQLite 스냅샷. OneDrive 같은 동기화 폴더로 바꾸면 PC 밖에도 사본이 생긴다
    AccountsBackupKeep  = 14                        # 남길 백업 개수
    AccountsBackupHours = 24                        # 백업 간격(시간)
}
