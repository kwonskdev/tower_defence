# 계정 서비스와 방 서버가 같이 쓰는 비밀 키(API 키) 도우미 (#25). run-accounts.ps1과 run-server.ps1이 이 파일을 불러서 쓴다.
# 키 파일(기본 data\accounts.key)이 없으면 암호용 난수로 만들고, 현재 사용자만 읽을 수 있게 권한을 줄인다. git에 올라가지 않는다 (.gitignore의 /data/).
# 이 키는 방 서버 -> 계정 서비스 요청에만 쓰이고(127.0.0.1 안에서만), 플레이어의 토큰과는 무관하다.
function Get-AccountsKey {
    param([string]$KeyFile)
    $dir = Split-Path -Parent $KeyFile
    New-Item -ItemType Directory -Force $dir | Out-Null
    if (-not (Test-Path $KeyFile)) {
        $bytes = New-Object byte[] 32
        [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($bytes)
        $key = ($bytes | ForEach-Object { $_.ToString("x2") }) -join ""
        Set-Content -Path $KeyFile -Value $key -Encoding ASCII
        try { & icacls $KeyFile /inheritance:r /grant:r "${env:USERNAME}:(R,W)" | Out-Null } catch { Write-Warning "키 파일 권한을 줄이지 못했다: $KeyFile" }
    }
    return (Get-Content -Path $KeyFile -Raw).Trim()
}
