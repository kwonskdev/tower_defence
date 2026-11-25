#!/usr/bin/env bash
# 서버 부하 측정 (#24, Linux/macOS). 운영과 같은 방 코드 서버를 띄우고 봇 R개 방 x 8명을 붙여서 CPU/메모리/프레임 작업 시간을 잰다.
#   GODOT=/path/to/godot tools/bench/run_bench.sh <방 수> [초=60] [몬스터 적체 수=0] [최대 fps=60]
# VPS에서 실제 기계로 재려면 같은 기계에서 돌린다. 서버 CPU는 서버 프로세스가 직접 찍는 METRICS 줄의 cpu=/rss= (/proc 기준)를 쓴다.
set -euo pipefail
cd "$(dirname "$0")/../.."
GODOT="${GODOT:-godot}"
ROOMS="${1:-1}"; SECONDS_RUN="${2:-60}"; STACK="${3:-0}"; MAXFPS="${4:-60}"; PORT="${PORT:-47410}"
OUT="${OUT:-/tmp/lanewars-bench}"; mkdir -p "$OUT"
SRV_LOG="$OUT/server-r$ROOMS-s$STACK.log"; GEN_LOG="$OUT/loadgen-r$ROOMS-s$STACK.log"
SRV_ARGS=(--server "--port=$PORT" "--max-rooms=$((ROOMS + 4))" --max-rooms-per-addr=999 "--max-fps=$MAXFPS" --metrics-interval=5)
[ "$STACK" -gt 0 ] && SRV_ARGS+=("--stack=$STACK")
"$GODOT" --headless --path . -s res://tools/bench/bench_server.gd -- "${SRV_ARGS[@]}" >"$SRV_LOG" 2>&1 &
SRV_PID=$!
trap 'kill $SRV_PID 2>/dev/null || true' EXIT
sleep 4
"$GODOT" --headless --path . -s res://tools/bench/loadgen.gd -- "--port=$PORT" "--rooms=$ROOMS" "--seconds=$SECONDS_RUN" >"$GEN_LOG" 2>&1
grep -a "LOADGEN" "$GEN_LOG" || true
echo "--- 서버 METRICS (마지막 5줄, cpu는 코어 1개 = 100%) ---"
grep -a "METRICS" "$SRV_LOG" | tail -5
echo "--- 서버 프로세스 (ps) ---"
ps -o pid,%cpu,rss,etime,cmd -p "$SRV_PID" || true
