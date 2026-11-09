#!/bin/sh
# Full experiment: round 1 steering only, round 2 with the same three level-1 skills for everyone. Four games per round,
# every model starts in every quadrant once. Then a bot-only baseline (free) and the replays / charts.
# Usage: ./run_experiment.sh [players]   default claude,openai,gemini,deepseek
set -e
cd "$(dirname "$0")"
P=${1:-claude,openai,gemini,deepseek}
STAMP=$(date +%Y-%m-%d_%H%M)
python3 run_match.py --players "$P" --games 4 --skills off --out "results/${STAMP}_round1_steering"
python3 run_match.py --players "$P" --games 4 --skills on  --out "results/${STAMP}_round2_skills"
python3 run_match.py --players bot,bot,bot,bot --games 4 --skills off --out "results/${STAMP}_baseline_bots"
for d in "results/${STAMP}_round1_steering" "results/${STAMP}_round2_skills"; do python3 replay.py "$d" --check; done
