#!/usr/bin/env bash
# 서버 한 줄 실행 (#24). 사용: tools/server/run.sh [포트] [서버 옵션...]
#   예) tools/server/run.sh 47300
#       tools/server/run.sh 47300 --max-rooms=32 --metrics-interval=30
#       tools/server/run.sh 47300 --tls-cert=/etc/ssl/lw.crt --tls-key=/etc/ssl/lw.key    (서버가 직접 wss. 보통은 리버스 프록시가 TLS를 맡는다: deploy/Caddyfile)
# build/server/lanewars-server.x86_64 (빌드 결과)가 있으면 그것을, 없으면 Godot로 프로젝트를 바로 띄운다 (개발용).
set -euo pipefail
cd "$(dirname "$0")/../.."
PORT="${1:-47300}"
shift || true
BIN="build/server/lanewars-server.x86_64"
if [ -x "$BIN" ]; then
  exec "$BIN" --headless --server --port="$PORT" "$@"
else
  exec "${GODOT:-godot}" --headless --path . -- --server --port="$PORT" "$@"
fi
