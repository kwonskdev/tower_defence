# 부팅 시 자동 시작 + 죽으면 재시작하도록 작업 스케줄러에 등록한다 (#24). 등록 자체에만 관리자 PowerShell이 필요하다 (서버는 관리자 권한 없이 돈다):
#   powershell -ExecutionPolicy Bypass -File deploy\windows\install-autostart.ps1          (등록)
#   powershell -ExecutionPolicy Bypass -File deploy\windows\install-autostart.ps1 -Remove  (제거)
# 서버 감시 루프(run-server.ps1)가 서버 프로세스를 다시 띄우고, 작업 스케줄러는 그 감시 루프가 죽었을 때 다시 시작한다 (1분 간격 최대 999회).
# 서버는 SYSTEM이 아닌 일반(비관리자) 계정으로 돈다: 기본은 등록하는 현재 사용자, -User로 서버 전용 일반 계정을 줄 수 있다.
# S4U + Limited: 로그온 없이 부팅 시 실행되고 비밀번호를 저장하지 않으며 관리자 권한이 없다. 그 계정이 logs\ 와 build\ 에 쓸 수 있어야 한다.
param([switch]$Remove, [string]$User = "$env:USERDOMAIN\$env:USERNAME")
$ErrorActionPreference = "Stop"   # 등록이 실패하면 "등록함"이라고 말하지 않고 멈춘다
$name = "LaneWarsServer"
if ($Remove) { Unregister-ScheduledTask -TaskName $name -Confirm:$false; Write-Output "제거함: $name"; exit 0 }
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
foreach ($d in @("logs", "build")) {
    $dir = Join-Path $root $d
    New-Item -ItemType Directory -Force $dir | Out-Null
    try { $t = Join-Path $dir ".write-test"; Set-Content $t "x" -ErrorAction Stop; Remove-Item $t } catch { Write-Warning "$dir 에 쓸 수 없다: $User 계정에 쓰기 권한을 주세요" }
}
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\run-server.ps1`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId $User -LogonType S4U -RunLevel Limited
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $name
Write-Output "등록하고 시작함: $name (계정 $User, 일반 권한)  (확인: Get-ScheduledTask $name, 로그: logs\)"
