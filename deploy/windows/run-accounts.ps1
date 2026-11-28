# 계정/판 기록 서비스를 실행하고, 죽으면 다시 시작하는 감시 루프 (#25, Windows 네이티브). 방 서버(run-server.ps1)와 따로 돈다:
# 이 서비스가 죽거나 재시작해도 방 서버와 진행 중인 판은 영향받지 않는다 (판 기록은 방 서버가 대기열에 쌓았다가 다시 보낸다).
#   powershell -ExecutionPolicy Bypass -File deploy\windows\run-accounts.ps1
# 설정은 settings.ps1 (또는 settings.local.ps1). 로그: logs\accounts-YYYYMMDD.log. 필요한 것: Python 3 (표준 라이브러리만 쓴다. 따로 설치할 패키지 없음).
# 서비스는 127.0.0.1에만 열린다 (밖에서 접근 불가). DB 파일: data\accounts.db, 백업: data\backups (settings.ps1에서 동기화 폴더 등으로 바꿀 수 있다).
param([switch]$Once)   # -Once: 죽어도 다시 시작하지 않는다 (확인용)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
. "$PSScriptRoot\settings.ps1"
if (Test-Path "$PSScriptRoot\settings.local.ps1") { . "$PSScriptRoot\settings.local.ps1" }
. "$PSScriptRoot\accounts-key.ps1"
$python = (Get-Command $Settings.Python -ErrorAction Stop).Source
function Resolve-RootPath([string]$p) { if ([System.IO.Path]::IsPathRooted($p)) { return $p } else { return (Join-Path $root $p) } }
$logDir = Join-Path $root $Settings.LogDir
New-Item -ItemType Directory -Force $logDir | Out-Null
$env:LANEWARS_ACCOUNTS_KEY = Get-AccountsKey (Resolve-RootPath $Settings.AccountsKeyFile)
$db = Resolve-RootPath $Settings.AccountsDb
$backups = Resolve-RootPath $Settings.AccountsBackupDir
$script = Join-Path $root "tools\accounts\accounts_service.py"
# settings.local.ps1 이 옛 설정 목록을 통째로 덮어써도 보관 기간 정리(#66)가 꺼지지 않게 기본값을 채운다 (방침: 계정 365일, 로그 30일)
foreach ($d in @{ AccountsPurgeHours = 24; AccountsInactiveDays = 365; LogRetentionDays = 30 }.GetEnumerator()) { if ($null -eq $Settings[$d.Key]) { $Settings[$d.Key] = $d.Value } }
$svcArgs = @($script, "--db", $db, "serve", "--port", $Settings.AccountsPort, "--backup-dir", $backups, "--backup-keep", $Settings.AccountsBackupKeep, "--backup-interval-hours", $Settings.AccountsBackupHours,
    "--purge-interval-hours", $Settings.AccountsPurgeHours, "--inactive-days", $Settings.AccountsInactiveDays, "--log-dir", $logDir, "--log-days", $Settings.LogRetentionDays)
while ($true) {
    $log = Join-Path $logDir ("accounts-{0:yyyyMMdd}.log" -f (Get-Date))
    Add-Content -Encoding UTF8 $log ("[{0:HH:mm:ss}] ---- 계정 서비스 시작 (포트 {1}, DB {2}) ----" -f (Get-Date), $Settings.AccountsPort, $db)
    $p = Start-Process -FilePath $python -ArgumentList $svcArgs -PassThru -NoNewWindow -RedirectStandardOutput "$log.out" -RedirectStandardError "$log.err" -WorkingDirectory $root
    $p.WaitForExit()
    foreach ($f in @("$log.out", "$log.err")) { if (Test-Path $f) { Get-Content -Encoding UTF8 $f | Add-Content -Encoding UTF8 $log; Remove-Item $f } }
    Add-Content -Encoding UTF8 $log ("[{0:HH:mm:ss}] ---- 계정 서비스 종료 (종료 코드 {1}) ----" -f (Get-Date), $p.ExitCode)
    if ($Once) { exit $p.ExitCode }
    Start-Sleep -Seconds $Settings.RestartDelaySec
}
