# AI Experiments

给 YouTube 频道「独立营业中」/「Build with AI」做的 AI 实验，每个实验一个目录，代码、数据、结果全部公开，视频里的每个结论都能在这里找到依据。

| 目录 | 实验 | 状态 |
|---|---|---|
| [`chess-arena/`](chess-arena/) | Anthropic 最强模型 vs OpenAI 最强模型下国际象棋，python-chess 验合法性、Stockfish 评估，两局换色 | 环境就绪，待对局 |

约定：每个实验目录自带 README（方法、怎么跑、结果）、`requirements.txt`、`.env.example`，结果放在该目录的 `results/` 下；密钥放各自目录的 `.env`，不入库。
