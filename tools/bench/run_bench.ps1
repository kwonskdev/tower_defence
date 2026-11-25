# 서버 부하 측정 (#24, Windows). 운영과 같은 방 코드 서버를 띄우고 봇 R개 방 x 8명을 붙여서 CPU/메모리/프레임 작업 시간을 잰다.
#   powershell -File tools/bench/run_bench.ps1 -Godot C:\path\Godot_console.exe -Rooms 4 -Seconds 90 [-Stack 1000] [-MaxFps 60]
# 결과는 한 줄 요약으로 출력하고 서버 로그는 -Out 폴더에 남는다. Linux/VPS에서는 run_bench.sh를 쓴다.
param(
    [Parameter(Mandatory = $true)][string]$Godot,
    [int]$Rooms = 1,
    [int]$Seconds = 60,
    [int]$Stack = 0,          # 0이 아니면 방마다 보스 레인에 몬스터를 이만큼 쌓는다 (최대 몬스터 시험)
    [int]$MaxFps = 60,
    [int]$Port = 47410,
    [string]$Out = "$env:TEMP\lanewars-bench"
)
$ErrorActionPreference = "Stop"
New-Item -ItemType Directory -Force $Out | Out-Null
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
$tag = "r$Rooms-s$Stack"
$srvLog = "$Out\server-$tag.log"
$genLog = "$Out\loadgen-$tag.log"
$srvArgs = @("--headless", "--path", $root, "-s", "res://tools/bench/bench_server.gd", "--", "--server", "--port=$Port",
    "--max-rooms=$($Rooms + 4)", "--max-rooms-per-addr=999", "--max-fps=$MaxFps", "--metrics-interval=5")
if ($Stack -gt 0) { $srvArgs += "--stack=$Stack" }
$srv = Start-Process -FilePath $Godot -ArgumentList $srvArgs -PassThru -NoNewWindow -RedirectStandardOutput $srvLog -RedirectStandardError "$srvLog.err"
Start-Sleep -Seconds 4
# Godot의 *_console.exe는 실제 Godot를 자식 프로세스로 띄우는 래퍼라서, CPU/메모리는 자식에서 잰다
$child = Get-CimInstance Win32_Process -Filter "ParentProcessId=$($srv.Id)" | Select-Object -First 1
$meter = if ($null -ne $child) { Get-Process -Id $child.ProcessId } else { $srv }
$genArgs = @("--headless", "--path", $root, "-s", "res://tools/bench/loadgen.gd", "--", "--port=$Port", "--rooms=$Rooms", "--seconds=$Seconds")
$gen = Start-Process -FilePath $Godot -ArgumentList $genArgs -PassThru -NoNewWindow -RedirectStandardOutput $genLog -RedirectStandardError "$genLog.err"
# 판이 시작될 때(전원 입장)부터 끝날 때까지의 서버 CPU 시간을 잰다
$t0 = $null; $cpu0 = $null
while (-not $gen.HasExited) {
    Start-Sleep -Milliseconds 500
    if ($null -eq $t0 -and (Select-String -Path $genLog -Pattern "all joined" -Quiet)) {
        $meter.Refresh(); $t0 = Get-Date; $cpu0 = $meter.TotalProcessorTime
    }
}
$meter.Refresh()
$t1 = Get-Date; $cpu1 = $meter.TotalProcessorTime
$peakMb = [math]::Round($meter.PeakWorkingSet64 / 1MB, 1)
Stop-Process -Id $meter.Id -Force -ErrorAction SilentlyContinue
Stop-Process -Id $srv.Id -Force -ErrorAction SilentlyContinue
if ($null -eq $t0) { Write-Output "FAILED: game did not start ($genLog)"; exit 1 }
$cpuPct = [math]::Round(($cpu1 - $cpu0).TotalSeconds / ($t1 - $t0).TotalSeconds * 100, 1)
# 서버 METRICS 줄 중 전원이 판 중인 구간(첫 구간은 시작 준비가 섞여 뺀다)
$lines = @(Select-String -Path $srvLog -Pattern "METRICS" | ForEach-Object { $_.Line } | Where-Object { $_ -match ("players=" + ($Rooms * 8) + " ") } | Select-Object -Skip 1)
function Field($line, $name) { if ($line -match "$name=([0-9.]+)") { [double]$Matches[1] } else { 0 } }
if ($lines.Count -gt 0) {
    $workAvg = [math]::Round((($lines | ForEach-Object { Field $_ "work_avg" }) | Measure-Object -Average).Average, 2)
    $workMax = [math]::Round((($lines | ForEach-Object { Field $_ "work_max" }) | Measure-Object -Maximum).Maximum, 2)
    $frameMax = [math]::Round((($lines | ForEach-Object { Field $_ "frame_max" }) | Measure-Object -Maximum).Maximum, 2)
    $monMax = (($lines | ForEach-Object { Field $_ "monsters" }) | Measure-Object -Maximum).Maximum
    $memLast = Field $lines[-1] "mem"
} else { $workAvg = $workMax = $frameMax = $monMax = $memLast = "n/a" }
Write-Output ("RESULT rooms={0} players={1} stack={2} max_fps={3} seconds={4} | cpu={5}% of 1 core, peak_ws={6}MB, mem(engine)={7}MB | work_avg={8}ms work_max={9}ms frame_max={10}ms monsters_max={11} (구간 {12}개)" -f `
        $Rooms, ($Rooms * 8), $Stack, $MaxFps, $Seconds, $cpuPct, $peakMb, $memLast, $workAvg, $workMax, $frameMax, $monMax, $lines.Count)
