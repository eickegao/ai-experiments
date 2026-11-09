#!/bin/sh
# Full experiment: two rounds of two games with colors swapped. Round 1 thinks little (effort low), round 2 thinks hard (effort high).
# Usage: ./run_experiment.sh [A] [B]   default claude vs openai
set -e
cd "$(dirname "$0")"
A=${1:-claude}; B=${2:-openai}
STAMP=$(date +%Y-%m-%d_%H%M)
python3 run_match.py --a "$A" --b "$B" --games 2 --effort low  --out "results/${STAMP}_round1_low"
python3 run_match.py --a "$A" --b "$B" --games 2 --effort high --out "results/${STAMP}_round2_high"
python3 compare_rounds.py "results/${STAMP}_round1_low" "results/${STAMP}_round2_high"
