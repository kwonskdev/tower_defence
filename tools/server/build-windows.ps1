# Windows 전용 서버 한 줄 빌드 (#24): build\server-win\lanewars-server.exe
#   powershell -ExecutionPolicy Bypass -File tools\server\build-windows.ps1 -Godot C:\path\Godot_v4.6.3-stable_win64_console.exe
# Godot 4.6.3 + 같은 버전 export 템플릿이 설치돼 있어야 한다.
param([Parameter(Mandatory = $true)][string]$Godot)
$ErrorActionPreference = "Stop"
$root = (Resolve-Path "$PSScriptRoot\..\..").Path
New-Item -ItemType Directory -Force "$root\build\server-win" | Out-Null
& $Godot --headless --path $root --import | Out-Null
& $Godot --headless --path $root --export-release "Windows Server" "$root\build\server-win\lanewars-server.exe"
if (-not (Test-Path "$root\build\server-win\lanewars-server.exe")) { throw "빌드 실패" }
Write-Output "빌드 완료: build\server-win\lanewars-server.exe"
