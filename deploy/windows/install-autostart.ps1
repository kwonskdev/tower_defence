# 부팅 시 자동 시작 + 죽으면 재시작하도록 작업 스케줄러에 등록한다 (#24). 관리자 PowerShell에서:
#   powershell -ExecutionPolicy Bypass -File deploy\windows\install-autostart.ps1          (등록)
#   powershell -ExecutionPolicy Bypass -File deploy\windows\install-autostart.ps1 -Remove  (제거)
# 서버 감시 루프(run-server.ps1)가 서버 프로세스를 다시 띄우고, 작업 스케줄러는 그 감시 루프가 죽었을 때 다시 시작한다 (1분 간격 최대 999회).
# 로그온 없이도 부팅하면 SYSTEM 계정으로 돈다 (집 PC가 재부팅/정전 후 자동으로 돌아오게).
param([switch]$Remove)
$name = "LaneWarsServer"
if ($Remove) { Unregister-ScheduledTask -TaskName $name -Confirm:$false; Write-Output "제거함: $name"; exit 0 }
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File `"$PSScriptRoot\run-server.ps1`"" -WorkingDirectory $root
$trigger = New-ScheduledTaskTrigger -AtStartup
$settings = New-ScheduledTaskSettingsSet -RestartCount 999 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit ([TimeSpan]::Zero) -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable
$principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -LogonType ServiceAccount -RunLevel Highest
Register-ScheduledTask -TaskName $name -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
Start-ScheduledTask -TaskName $name
Write-Output "등록하고 시작함: $name  (확인: Get-ScheduledTask $name, 로그: logs\)"
