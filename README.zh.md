# AI 实验

[English](README.md) · 中文说明

这是我们为 YouTube 频道做的 AI 实验的公开记录。每个实验一个目录，代码、提示词、原始数据、结果全部在里面，方便你跟着看、核对视频里的每个结论，并自己复现。

- YouTube：[**独立营业中**](https://www.youtube.com/@独立营业中)（中文）· [**Build with AI**](https://www.youtube.com/@buildwithai2027)（英文）
- 网站：[videodoz.com](https://videodoz.com/zh/)
- 许可证：[MIT](LICENSE)，随便用，注明出处就好。

| 目录 | 实验 | 状态 |
|---|---|---|
| [`chess-arena/`](chess-arena/README.zh.md) | Anthropic 最强模型对 OpenAI 最强模型下国际象棋。python-chess 判合法性，Stockfish 评估每一步，每轮两局换色。 | 已完成：GPT-6 Astra 2 比 0 胜 Claude Fable 5.1（2026-11-08） |

## 怎么复现

每个实验的 README 都写了用的模型、提示词、验证工具和命令。装好它列的依赖，在仓库根目录 `.env` 里填自己的 API key（参考 `.env.example`），照命令跑。你的结果和我们的不会完全一样（模型不是确定性的），这本身就是看点：拿你的结果和我们的对比。

待做的选题：[IDEAS.md](IDEAS.md)（英文）。

## 约定

- 每个实验一个目录，自带 `README.md`（方法、运行、结果）、`requirements.txt` 和 `results/`。
- API key 只放仓库根目录 `.env`，所有实验共用；`.gitignore` 忽略任何层级的 `.env`，本地 pre-commit 钩子拦截疑似密钥。
- 代码、文档、提交信息用英文；中文说明是 `README.zh.md`。
