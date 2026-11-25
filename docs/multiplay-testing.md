# 멀티플레이 테스트 (#28)

Godot 4.6.3 기준. `G`는 `Godot_v4.6.3-stable_win64_console.exe` 경로. 새 워크트리는 먼저 `"$G" --headless --path . --import` 한 번.

## 자동 테스트 (tests/)

전체: `"$G" --headless --path . -s res://tests/run_tests.gd` (끝에 `ALL: N checks, M failed`, 실패가 있으면 종료 코드 1). 이름으로 고르기: `... -- <이름>`.

| 파일 | 이슈 요구사항 | 내용 | 걸리는 시간 |
|---|---|---|---|
| `test_mp_bots.gd` | 1, 5 | 평소 실행: 봇 1명 짧은 판. 전체 판은 `-- mp_bots` (`n=1`/`n=2`/`n=8`, `rich`/`normal`로 고름): 서버 1 + 봇 N(1/2/8)이 진짜 WebSocket으로 판 끝까지. "보통"(골드 치트 없음, 봇이 약해 대개 패배로 끝남)과 "부자"(서버 쪽에서 골드를 채워 보스 Lv.10 승리까지) | 평소 수 초 / 전체 n=8 약 8분 |
| `test_mp_network.gd` | 2 | 가짜 네트워크(`tests/net_proxy.gd`)를 끼운 지연/지터/손실/끊김/먹통/유예 초과 | 약 1.5분 (실제 시간) |
| `test_mp_concurrency.gd` | 3 | 같은 칸 동시 건설, 사칭 혼합, 골드 부족 겹침, 8명 동시 몬스터 만들기 | 수 초 |
| `test_server_full_run.gd` 등 기존 | 5 | 1인/기존 회귀 (`-- full_run`은 오래 걸려 따로) | |

1인 플레이는 기존 `tests/` 전체(`test_main_menu`, `test_online_game`, `test_server_headless` 등)가 그대로 통과해야 한다.

### 가짜 네트워크 레이어 (`tests/net_proxy.gd`)
외부 도구(clumsy, tc netem) 없이, 클라이언트와 서버 사이에 TCP 중계를 끼운다. 서버/클라이언트 코드는 그대로고 진짜 WebSocket 위에서 돈다.
- `latency_ms`(한쪽 지연), `jitter_ms`, `loss`: TCP라 메시지는 사라지지 않고 손실은 재전송 지연(max(200ms, 3x지연))으로 나타난다. 앞 조각을 추월하지 않는다.
- `freeze(true)`: 연결은 열린 채 아무것도 안 감. `cut()`: 모든 연결을 갑자기 닫음. `refusing`: 새 연결 거부.
- 실제 시간 기준이라 `Engine.time_scale`을 올린 시험에는 쓰지 않는다.

### 해석한 것 (이슈 3번)
타워는 자기 레인에만 짓는다(명령에 대상 레인이 없다). 그래서 서로 다른 두 사람이 같은 좌표를 지으면 둘 다 자기 레인에 성공하는 것이 올바른 동작이고, "한 명만 성공"은 같은 사람의 중복 명령(더블탭, 옛 연결+새 연결)에서 나온다. 둘 다 시험한다.

## 부하/끊김 측정 도구 (tools/bench/)
- `run_bench.ps1 -Godot <exe> -Rooms 1 -Seconds 60 [-Stack N] [-ViewBoss]` / `run_bench.sh` (`VIEW_BOSS=1`). `-ViewBoss`: 봇 전원이 보스 레인을 본다(몬스터 전체가 스냅샷으로 가는 최대 대역폭). 서버 `METRICS` 줄에 방송 시간(`bcast_*`: snapshot/quantize/diff/send), 가장 큰 메시지(`msg_max`), 클라이언트 1명당 스냅샷 KB/s(`snap_per_client`)가 추가됐다.
- `hitch_probe.gd`: 방 1개 + 봇을 한 프로세스에서 돌리며 프레임 시간/상위 끊김/명령·방송 구간 시간을 출력 (`-- --seconds=60 --log=info|debug|error --no-build --no-send --players=N --stack=N`). 서버 로그를 파이프(`| grep`)로 보내면 줄당 약 15ms가 걸리니 측정할 때는 파일로 리다이렉트한다.

## 폰 실기기 체크리스트 (요구사항 6, 소유자가 직접)
준비: `docs/test-connection.md`(테스트용 debug APK, PC 서버, 방화벽/터널). 폰 2대 이상, 한 대는 Wi-Fi, 한 대는 모바일 데이터.
- [ ] 폰 A가 방 만들기, 폰 B가 방 코드로 입장, 모두 준비 후 시작
- [ ] 보스 Lv.10까지 한 판 완주 (또는 패배로 결과 화면까지) 하고 [메뉴로]
- [ ] 판 중 폰 B를 비행기 모드 10초 켰다 끄기: "재접속 중" 후 같은 레인으로 복귀, 타워/골드 유지
- [ ] 판 중 폰 B의 Wi-Fi <-> 모바일 데이터 전환: 복귀
- [ ] 앱을 홈으로 보냈다 30초 뒤 복귀: 복귀 (판은 멈추지 않는다)
- [ ] 폰 B를 2분(유예 90초 초과) 끊어 두었다 복귀: 이탈 안내, 다른 폰은 계속 진행
- [ ] 같은 칸을 두 폰이 동시에 누르는 상황(각자 자기 레인): 서로 영향 없음
- [ ] 화면이 크게 튀거나 멈추는 구간이 있었는가 (몇 초, 언제)
- [ ] 결과를 이슈 #28에 남기기 (기기, 망 종류, 인원, 결과, 이상한 점)
