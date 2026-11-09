#!/bin/sh
# 完整实验：两轮，每轮两局换色。第一轮少想（effort low），第二轮多想（effort high）。
# 用法：./run_experiment.sh [A] [B]   默认 claude vs openai
set -e
cd "$(dirname "$0")"
A=${1:-claude}; B=${2:-openai}
STAMP=$(date +%Y-%m-%d_%H%M)
python3 run_match.py --a "$A" --b "$B" --games 2 --effort low  --out "results/${STAMP}_round1_low"
python3 run_match.py --a "$A" --b "$B" --games 2 --effort high --out "results/${STAMP}_round2_high"
python3 compare_rounds.py "results/${STAMP}_round1_low" "results/${STAMP}_round2_high"
