# AI Experiments

English · [中文说明](README.zh.md)

A public log of the AI experiments we run for our YouTube channels. Every experiment lives in its own directory with the code, prompts, raw data and results, so you can follow along, check every claim made in a video, and reproduce the experiment yourself.

- YouTube: [**Build with AI**](https://www.youtube.com/@buildwithai2027) (English) · [**独立营业中**](https://www.youtube.com/@独立营业中) (Chinese)
- Website: [videodoz.com](https://videodoz.com)
- License: [MIT](LICENSE). Use anything here freely; a link back is appreciated.

| Directory | Experiment | Status |
|---|---|---|
| [`chess-arena/`](chess-arena/) ([中文](chess-arena/README.zh.md)) | Anthropic's strongest model vs OpenAI's strongest model at chess. Legality checked by python-chess, quality scored by Stockfish, two games per round with colors swapped. | Done: GPT-6 Astra 2–0 Claude Fable 5.1 (2026-11-08) |
| [`color-battle-arena/`](color-battle-arena/) ([中文](color-battle-arena/README.zh.md)) | Four LLMs (Claude, GPT, Gemini, DeepSeek) each remote-control a ball in PlayDoz's Color Battle, a 60-second four-player territory game. The game engine referees every command; two rounds (steering only, then with skills), every model starts in every corner once. | Harness ready, running soon (2026-11-09) |
| [`watersort-fog-arena/`](watersort-fog-arena/) ([中文](watersort-fog-arena/README.zh.md)) | Four LLMs each play the same fogged Water Sort level (PlayDoz level 286) in one long conversation, with undo and restart. We record total pours, undos, restarts and the length of the final solution against the proven 50-pour optimum. | Done: GPT-6.2 Astra solved it in 52 pours (optimum 50); Claude Fable 5.2, Gemini 4 Carbon and DeepSeek V4 Pro did not finish (2026-11-17) |
| [`savanna-sandbox/`](savanna-sandbox/) ([中文](savanna-sandbox/README.zh.md)) | How good and how fast is an AI at making a whole game? A god game on a slab of African savanna (herds, a lion pride, two tribes that grow from a campfire to a stone kingdom and go to war, nine god powers), written by Claude Fable 5.2 in one sitting with no art assets. | Demo, under review (2026-11-20) |

## Reproducing an experiment

Each experiment's README lists the exact models, prompts, verification tools and commands. Install the dependencies it names, put your own API keys in `.env` at the repo root (see `.env.example`), and run the command shown. Results you get will differ in detail (the models are not deterministic), which is part of the point: compare your run with ours.

Backlog of scoped-but-not-run ideas: [IDEAS.md](IDEAS.md).

## Conventions

- One directory per experiment, each with its own `README.md` (method, how to run, results), `requirements.txt`, and a `results/` folder.
- API keys live in a single `.env` at the repo root (`cp .env.example .env` and fill it in) and are shared by all experiments. `.gitignore` ignores `.env` at every level, and a local pre-commit hook rejects anything that looks like a key.
- Code, docs and commit messages are in English.
