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
}
