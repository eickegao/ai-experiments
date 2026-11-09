# AI Chess Arena · Anthropic 最强模型 vs OpenAI 最强模型

两家最强的公开模型下两盘国际象棋，各执一次白、一次黑。每一步都经过独立验证：

- **合法性**：python-chess 按规则判定（非法走法不会上棋盘）。每步最多 3 次机会；第 2 次起附上合法走法列表；3 次都不合法判负（可用 `--on-illegal random` 改成随机合法走法继续）。
- **质量**：Stockfish 19（深度 18）对每一步前后局面评估，记录丢分、是否最佳着法、失误（≥2 兵）。
- 150 回合未分胜负由 Stockfish 评估裁定（±8 兵以上判胜负，否则和）。

两位棋手拿到**完全相同的提示词**：完整走法记录（PGN）、FEN、文字棋盘、对手上一步。第一次尝试不给合法走法列表，考的是模型自己的棋力。模型是无状态的：每步单独一次请求，不靠多轮对话。

## 实验设计

两轮，每轮两局换色，共四局（`./run_experiment.sh`）：

| 轮 | 推理强度（两家同设） | 问的是 |
|---|---|---|
| round1 | `effort=low`，少想 | 少想时能不能走出合法、合理的棋 |
| round2 | `effort=high`，多想 | 多想之后非法走法和失误会不会减少 |

不给模型时间限制（API 也没法限），但每一步、每次尝试的**耗时都记录**，和 token、成本一起进统计。

每方统计：比分、非法尝试次数、Top-1 / Top-3 吻合率（走法在 Stockfish 前 1 / 前 3 佳着法里的比例）、平均丢分、失误数（丢 ≥2 兵）、每步秒数、token 数、成本。`compare_rounds.py` 把两轮并成一张表和一张图。

事先说明：这是通用大语言模型，不是象棋引擎，棋力肯定不如 Stockfish；看的是通用模型在精确规则任务上的表现。每一步都把完整棋局（PGN + FEN + 棋盘）发给模型，不靠聊天记忆；模型给出的每一步由 python-chess 验合法性，非法就记录并重试。

## 模型

| 方 | 模型 ID | 备注 |
|---|---|---|
| Anthropic | `claude-fable-5-1` | 思考常开，`effort=high` |
| OpenAI | `gpt-6-astra` | Responses API，`reasoning.effort=high` |

（模型 ID 可用 `--a claude:<id> --b openai:<id>` 换。）

## 运行

在 `chess-arena/` 目录下：

```bash
brew install stockfish librsvg ffmpeg
pip3 install -r requirements.txt
cp ../.env.example ../.env   # 密钥放仓库根目录，所有实验共用
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
