# 서버를 실행하고, 죽으면 다시 시작하는 감시 루프 (#24, Windows 네이티브).
#   powershell -ExecutionPolicy Bypass -File deploy\windows\run-server.ps1
# 설정은 settings.ps1 (또는 settings.local.ps1). 로그: logs\server-YYYYMMDD.log. 중지: 이 창에서 Ctrl+C (또는 작업 스케줄러에서 작업 종료).
param([switch]$Once)   # -Once: 죽어도 다시 시작하지 않는다 (확인용)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
. "$PSScriptRoot\settings.ps1"
if (Test-Path "$PSScriptRoot\settings.local.ps1") { . "$PSScriptRoot\settings.local.ps1" }
$exe = Join-Path $root $Settings.ServerExe
if (-not (Test-Path $exe)) { throw "서버 실행 파일이 없습니다: $exe  (먼저 tools\server\build-windows.ps1)" }
$logDir = Join-Path $root $Settings.LogDir
New-Item -ItemType Directory -Force $logDir | Out-Null
$args = @("--headless", "--server", "--port=$($Settings.Port)",
    "--max-rooms=$($Settings.MaxRooms)", "--max-rooms-per-addr=$($Settings.MaxRooms)",   # 터널/프록시 뒤에서는 접속이 한 주소로 보인다
    "--metrics-interval=$($Settings.MetricsInterval)")
while ($true) {
    $log = Join-Path $logDir ("server-{0:yyyyMMdd}.log" -f (Get-Date))
    Add-Content -Encoding UTF8 $log ("[{0:HH:mm:ss}] ---- 서버 시작 (방 한도 {1}, 포트 {2}) ----" -f (Get-Date), $Settings.MaxRooms, $Settings.Port)
    $p = Start-Process -FilePath $exe -ArgumentList $args -PassThru -NoNewWindow -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err" -WorkingDirectory $root
    $p.WaitForExit()
    # 이번 실행의 출력을 날짜 로그에 붙인다
    foreach ($f in @("$log.out", "$log.err")) { if (Test-Path $f) { Get-Content -Encoding UTF8 $f | Add-Content -Encoding UTF8 $log; Remove-Item $f } }
    Add-Content -Encoding UTF8 $log ("[{0:HH:mm:ss}] ---- 서버 종료 (종료 코드 {1}) ----" -f (Get-Date), $p.ExitCode)
    if ($Once) { exit $p.ExitCode }
    Start-Sleep -Seconds $Settings.RestartDelaySec
}
