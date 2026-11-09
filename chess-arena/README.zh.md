# Chess Arena：Anthropic 最强模型 vs OpenAI 最强模型

[English](README.md) · 中文说明

两家最强的公开模型下国际象棋，每一步都经过独立验证：

- **合法性**：python-chess 按规则判定，非法走法不会上棋盘。每步最多 3 次机会，第 2 次起附上合法走法列表，3 次都不合法判负（`--on-illegal random` 可改成随机合法走法继续）。
- **质量**：Stockfish 19（深度 18，3 条主变）评估每一步前后局面，记录丢分、走法是否在 Stockfish 前 1 / 前 3 佳着法里、失误（丢 ≥2 兵）。
- 150 回合未分胜负由 Stockfish 裁定（±8 兵判胜负，否则和）。

两位棋手拿到**完全相同的提示词**，交流格式就是 PGN：把目前为止的棋谱发过去，模型回一步 SAN。第一次尝试不给合法走法列表，考的是模型自己的棋力。棋手无状态：每步单独一次请求，不靠多轮记忆。

## 实验设计

两轮，每轮两局换色，共四局（`./run_experiment.sh`）：

| 轮 | 推理强度（两家同设） | 问的是 |
|---|---|---|
| round1 | `effort=low`，少想 | 少想时能不能走出合法、合理的棋 |
| round2 | `effort=high`，多想 | 多想之后非法走法和失误会不会减少 |

不限时（API 也没法限），但每一步、每次尝试的**耗时都记录**，连同 token 和成本一起统计。

每方统计：比分、非法尝试次数、Top-1 / Top-3 吻合率、平均丢分、失误数、每步秒数、token 数、成本。`compare_rounds.py` 把两轮并成一张表和一张图。

事先说明：这是通用大语言模型，不是象棋引擎，棋力远不如 Stockfish；看的是通用模型在精确规则任务上的表现。每一步都把完整棋局发给模型，不靠聊天记忆；每个回复先过 python-chess 再上棋盘。

## 模型

| 方 | 模型 ID | 备注 |
|---|---|---|
| Anthropic | `claude-fable-5-1` | 思考常开，按轮设 `effort=high` / `low` |
| OpenAI | `gpt-6-astra` | Responses API，按轮设 `reasoning.effort=high` / `low` |

可用 `--a claude:<id> --b openai:<id>` 换模型。

## 运行

在 `chess-arena/` 目录下：

```bash
brew install stockfish librsvg ffmpeg
pip3 install -r requirements.txt
cp ../.env.example ../.env     # key 放仓库根目录，所有实验共用
./run_experiment.sh            # 两轮共四局
python3 run_match.py --a stockfish:50 --b random:0.1 --out results/dryrun   # 不花钱的流水线测试
python3 run_match.py --render-only results/<dir> --layout portrait          # 重新出素材
```

## 产出（`results/<时间戳>_<A>_vs_<B>/`）

| 文件 | 内容 |
|---|---|
| `gameN.pgn` | 标准棋谱，每步带 `[%eval]` 注释 |
| `gameN.json` | 每一步：模型原始回复、每次尝试、耗时、token、Stockfish 评估前后、丢分、最佳着法、前 3 佳 |
| `gameN_transcript.md` | 完整交流记录：每次发给模型的 PGN、模型的原话、验证结果，一字不改 |
| `gameN_dialogue.mp4` + `frames_dialogue/gameN/*.png` | 同一份交流做成画面：左边提示词、右边模型原话、底部验证结果，每次尝试一帧 |
| `gameN.log` | 实时日志 |
| `gameN_replay.mp4` | 回放视频（1920×1080：棋盘、评估条、走法、评估、最佳着法、标记） |
| `gameN_eval.png` | 评估曲线，红点是失误 |
| `gameN_key_moments.json` | 非法尝试、失误、将死、判负 |
| `frames/gameN/*.png` | 每一步一帧（不入库，`--render-only` 可重生成） |
| `summary.md` / `summary.json` | 本轮比分和双方统计 |
| `../comparison.md` / `comparison.png` | 两轮对比 |

成本用的单价（美元/百万 token，输入 / 输出）在 `arena/prices.py`：两家旗舰定价相同，都是 10 / 50 美元（Anthropic 官方价格页；OpenAI developers.openai.com 价格页标准档，2026-11-08 查）。

## 结果（2026-11-08，双方 effort=high）

原始数据：[`results/2026-11-08_2051_claude-fable-5-1_vs_gpt-6-astra/`](results/2026-11-08_2051_claude-fable-5-1_vs_gpt-6-astra/)（PGN、含每次提示和回复的 JSON、交流记录、回放和对话视频、评估曲线）。

**GPT-6 Astra 2 比 0 获胜，两局都是将死。**

| 局 | 白 | 黑 | 结果 | 半步数 |
|---|---|---|---|---|
| game1 | Claude Fable 5.1 | GPT-6 Astra | 0–1，将死（34... Re1#） | 68 |
| game2 | GPT-6 Astra | Claude Fable 5.1 | 1–0，将死（31. Qe8#） | 61 |

| 两局合计 | Claude Fable 5.1 | GPT-6 Astra |
|---|---|---|
| 走了几步 | 64 | 65 |
| 失败尝试（非法 / 没给走法） | 1（非法 `Rxf3`：自己的后在 f2 挡住了车） | 1（空回复：4,000 token 的输出额度全花在推理上，没给出走法） |
| 与 Stockfish 第一选择吻合 | 45.3% | 53.8% |
| 在 Stockfish 前三选择内 | 71.9% | 83.1% |
| 平均每步丢分（兵） | 0.68 | 0.38 |
| 大失误（丢 ≥2 兵） | 7 | 5 |
| 思考时间合计 | 7 分 06 秒（6.7 秒/步） | 43 分钟（39.7 秒/步） |
| token 输入 / 输出 | 28,134 / 23,847 | 19,497 / 65,895 |
| 成本（两家都是 10 / 50 美元每百万） | 1.47 美元 | 3.49 美元 |

两局经过：

- **第一局**：西西里防御，前 13 回合双方走法大多在 Stockfish 前三之内。Claude（白）连续几回合漏吃 `Qxb4` 这个白送的兵；GPT 走 `23...Qf8` 失误（白方 +2.7），Claude 下一步 `24.Qf2` 立刻还了回去，随后 `26.Qe4` 一步丢 10.8 兵，棋局就此崩盘，GPT 在第 34 回合将死。
- **第二局**：前 17 回合平稳均势。GPT（白）先走 `18.b3` 失误（−6.2），Claude 回敬同等级的失误 `18...Bd7`，接着 `20...g6`、`21...Qb7`（−6.6）、`22...d5` 连续走错，GPT 干净利落地在第 31 回合将死。
- GPT 每步思考时间是 Claude 的六倍左右，输出 token 多 2.8 倍，走法更贴近 Stockfish、丢分更少；Claude 几秒就回，但大失误更多。
- 合法性方面：129 步里只有两次尝试失败（各一次），都在附上合法走法列表的重试中纠正。

说明：两局只是样本，不是定论。OpenAI 的 `max_output_tokens=4000` 包含推理 token，导致了那一次空回复，额度调高可避免。两家都远不及 Stockfish（第一选择吻合率只有五成左右，每局都有好几次丢好几兵的失误）。
