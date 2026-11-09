# AI Chess Arena · Anthropic 最强模型 vs OpenAI 最强模型

两家最强的公开模型下两盘国际象棋，各执一次白、一次黑。每一步都经过独立验证：

- **合法性**：python-chess 按规则判定（非法走法不会上棋盘）。每步最多 3 次机会；第 2 次起附上合法走法列表；3 次都不合法判负（可用 `--on-illegal random` 改成随机合法走法继续）。
- **质量**：Stockfish 19（深度 18）对每一步前后局面评估，记录丢分、是否最佳着法、失误（≥2 兵）。
- 150 回合未分胜负由 Stockfish 评估裁定（±8 兵以上判胜负，否则和）。

两位棋手拿到**完全相同的提示词**：完整走法记录（PGN）、FEN、文字棋盘、对手上一步。第一次尝试不给合法走法列表，考的是模型自己的棋力。模型是无状态的：每步单独一次请求，不靠多轮对话。

## 模型

| 方 | 模型 ID | 备注 |
|---|---|---|
| Anthropic | `claude-fable-5-1` | 思考常开，`effort=high` |
| OpenAI | `gpt-6-astra` | Responses API，`reasoning.effort=high` |

（模型 ID 可用 `--a claude:<id> --b openai:<id>` 换。）

## 运行

```bash
brew install stockfish librsvg ffmpeg
pip3 install -r requirements.txt
cp .env.example .env   # 填 ANTHROPIC_API_KEY / OPENAI_API_KEY
python3 run_match.py                                   # 两局
python3 run_match.py --a stockfish:50 --b random:0.1 --out results/dryrun   # 不花钱的流水线测试
```

## 产出（`results/<时间戳>_<A>_vs_<B>/`）

| 文件 | 内容 |
|---|---|
| `gameN.pgn` | 标准棋谱，每步带 `[%eval]` 注释 |
| `gameN.json` | 每一步：模型原始回复、每次尝试、耗时、token、Stockfish 评估前后、丢分、最佳着法 |
| `gameN.log` | 实时日志 |
| `gameN_replay.mp4` | 回放视频（1080×1350，棋盘 + 评估条 + 字幕） |
| `gameN_eval.png` | 评估曲线，红点是失误 |
| `gameN_key_moments.json` | 关键时刻：非法尝试、失误、将死、判负 |
| `frames/gameN/*.png` | 每一步一帧（不入库） |
| `summary.md` / `summary.json` | 比分和双方统计 |

## 结果

（对局完成后填写）
