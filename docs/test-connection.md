# 폰으로 PC 서버에 접속해 보기 (테스트 빌드) (#24)

도메인/Cloudflare Tunnel 없이 **테스트용(debug) 앱**으로 PC에서 돌리는 서버에 붙어 보는 방법. 도메인 구매와 정식 서버 가동(Cloudflare Tunnel)은 소유자가 나중에 별도 이슈로 한다: `docs/windows-hosting.md` (가이드만, 이 PR에서 가동 확인 안 함).

## 빌드 구분 (중요)

| | 테스트용 (debug) | 정식 (release) |
|---|---|---|
| 앱 안 서버 주소 입력 | 가능 | 잠김 (project.godot의 기본 서버만) |
| 평문 `ws://` / `호스트:포트` | 가능 | **막힘** (wss만) |
| 안드로이드 네트워크 보안 설정 | `android/build/src/debug/res/xml/network_security_config.xml` (평문 허용) | `android/build/src/release/res/xml/network_security_config.xml` (평문 불허) |
| 안드로이드 프리셋 | **Android Debug APK** (`--export-debug`) | **Android** (AAB), **Android APK** (`--export-release`) |
| INTERNET 권한 | 켬 | 켬 |

코드 쪽 판정은 `OS.has_feature("debug")` (`MainMenu.test_build()`). 정식 빌드에서는 안드로이드 설정과 코드 둘 다 평문을 막는다.

테스트용 APK 빌드: `Godot --headless --path . --export-debug "Android Debug APK" build/lanewars-debug.apk`

## 1. 집 Wi-Fi에서 PC 내부 IP로 접속

1. PC와 폰을 **같은 공유기 Wi-Fi**에 연결 (게스트 Wi-Fi/기기 격리 설정이면 안 된다).
2. PC 내부 IP 확인: `ipconfig` -> "IPv4 주소" (예: `192.168.0.10`).
3. 서버 실행 (PC):
   ```powershell
   powershell -ExecutionPolicy Bypass -File deploy\windows\run-server.ps1
   ```
   (서버 빌드 방법: `docs/windows-hosting.md` 1절. 바로 확인만 하려면 `Godot --headless --path . -- --server --port=47300` 도 된다.)
4. **Windows 방화벽에서 포트 허용** (관리자 PowerShell, 개인(Private) 네트워크 한정):
   ```powershell
   New-NetFirewallRule -DisplayName "LaneWars test 47300" -Direction Inbound -Protocol TCP -LocalPort 47300 -Action Allow -Profile Private
   ```
   다 쓰면 제거: `Remove-NetFirewallRule -DisplayName "LaneWars test 47300"`. Wi-Fi 연결이 "공용(Public)"으로 잡혀 있으면 `-Profile Private`로는 안 열리니 설정 > 네트워크에서 "개인"으로 바꾸거나 `-Profile Any`(권장하지 않음).
5. 폰의 테스트용 앱 메인 메뉴 **서버 주소**에 `192.168.0.10:47300` (위 IP) 입력 -> [방 만들기]. 두 번째 폰은 같은 주소와 방 코드로 입장.
6. 안 될 때: PC에서 `Test-NetConnection 192.168.0.10 -Port 47300` (또는 폰 브라우저로 `http://192.168.0.10:47300` 이 연결은 되는지: WebSocket이 아니라 400류 응답이 오면 포트는 열린 것), 서버 로그(`logs\`) 확인.

## 2. 밖에서 접속 (집 밖 LTE/다른 Wi-Fi)

둘 다 **서버를 인터넷에 직접 열지 않는다** (포트 포워딩 없음).

### A. cloudflared 빠른 터널 (계정/도메인 불필요, 임시 주소)
1. `winget install --id Cloudflare.cloudflared`
2. 서버를 켜 둔 상태에서: `cloudflared tunnel --url http://localhost:47300`
3. 출력에 `https://무작위이름.trycloudflare.com` 이 나온다. 앱의 서버 주소에 **`wss://무작위이름.trycloudflare.com`** (포트 없음)을 쓴다. 빠른 터널은 Cloudflare가 TLS를 처리하므로 wss다 (정식 앱도 이 주소로는 접속할 수 있다).
4. 주소는 터널을 켤 때마다 바뀌고, 명령 창을 닫으면 끝난다. (테스트 전용: 가용성 보장 없음)

### B. Tailscale (같은 계정의 기기끼리 사설망)
1. PC와 폰 모두 Tailscale 설치, 같은 계정으로 로그인.
2. PC의 Tailscale IP(`tailscale ip -4`, 예 `100.64.0.5`) 또는 MagicDNS 이름 확인.
3. 서버 주소: `100.64.0.5:47300` (평문 ws. Tailscale 구간이 WireGuard로 암호화된다). **테스트용(debug) 앱에서만** 된다.
4. Windows 방화벽은 Tailscale 인터페이스 쪽 TCP 47300을 허용해야 할 수 있다 (1의 4번 규칙에서 `-Profile Any` 대신 `-InterfaceAlias Tailscale`).

## 3. 확인 목록 (소유자가 직접)

- [ ] 폰 2대가 같은 방에 들어가 판을 끝까지 한다 (위 1 또는 2)
- [ ] 방 대기 상태로 3분 이상 두어도 끊기지 않는다 (특히 2-A 빠른 터널에서: Cloudflare의 유휴 WebSocket 끊김 확인)
- [ ] 정식(release) 빌드 앱에서는 서버 주소 칸이 잠기고 평문 주소로 접속되지 않는다
