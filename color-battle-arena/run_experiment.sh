#!/bin/sh
# Full experiment inside the real game: four games (every model starts in every quadrant once, each drafts its own skills),
# then a bot-only baseline (free). Each game: live match headless → results/<run>/game_N.json/.md → replay recorded to game_N.mp4.
# Usage: ./run_experiment.sh [players]   default claude,openai,gemini,deepseek   (needs game/build_web built, see README)
set -e
cd "$(dirname "$0")"
P=${1:-claude,openai,gemini,deepseek}
STAMP=$(date +%Y-%m-%d_%H%M)
PORT=8787

run_set() {   # $1 players  $2 out dir
  python3 arena_server.py --players "$1" --out "$2" --port $PORT > "/tmp/arena_server_$STAMP.log" 2>&1 &
  SRV=$!
  sleep 2
  for g in 1 2 3 4; do python3 record_match.py --game $g --out "$2" --server "http://127.0.0.1:$PORT"; done
  kill $SRV
  wait $SRV 2>/dev/null || true
}

run_set "$P" "results/${STAMP}_arena"
run_set "bot,bot,bot,bot" "results/${STAMP}_baseline_bots"
echo "done: results/${STAMP}_arena/summary.md"
