#!/usr/bin/env bash
# Linux 서버 한 줄 빌드 (#24): build/server/lanewars-server.x86_64 를 만든다 (헤드리스 export, 전용 서버 모드 = 화면용 리소스 제외).
# 사용: tools/server/build.sh            (GODOT 환경 변수에 Godot 4.6.3 실행 파일 경로. 없으면 PATH의 godot)
# 필요: Godot 4.6.3 + 같은 버전의 export 템플릿(Linux). 템플릿은 에디터의 [프로젝트 > 내보내기 > 템플릿 관리]나
#       https://godotengine.org/download/archive/4.6.3-stable/ 의 Export templates(.tpz)를 한 번 설치한다.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
OUT="build/server/lanewars-server.x86_64"
mkdir -p "$(dirname "$OUT")"
"$GODOT" --headless --path . --import   # 새 체크아웃은 import를 한 번 해야 클래스 캐시가 생긴다
"$GODOT" --headless --path . --export-release "Linux Server" "$OUT"
test -s "$OUT" || { echo "빌드 실패: $OUT 이 없음" >&2; exit 1; }
chmod +x "$OUT"
echo "빌드 완료: $OUT ($(du -h "$OUT" | cut -f1))"
