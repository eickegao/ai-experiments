# AI Experiments

English · [中文说明](README.zh.md)

A public log of the AI experiments we run for our YouTube channels. Every experiment lives in its own directory with the code, prompts, raw data and results, so you can follow along, check every claim made in a video, and reproduce the experiment yourself.

- YouTube: [**Build with AI**](https://www.youtube.com/@buildwithai2027) (English) · [**独立营业中**](https://www.youtube.com/@独立营业中) (Chinese)
- Website: [videodoz.com](https://videodoz.com)
- License: [MIT](LICENSE). Use anything here freely; a link back is appreciated.

| Directory | Experiment | Status |
|---|---|---|
| [`chess-arena/`](chess-arena/) ([中文](chess-arena/README.zh.md)) | Anthropic's strongest model vs OpenAI's strongest model at chess. Legality checked by python-chess, quality scored by Stockfish, two games per round with colors swapped. | Pipeline ready, match pending |

## Reproducing an experiment

Each experiment's README lists the exact models, prompts, verification tools and commands. Install the dependencies it names, put your own API keys in `.env` at the repo root (see `.env.example`), and run the command shown. Results you get will differ in detail (the models are not deterministic), which is part of the point: compare your run with ours.

## Conventions

- One directory per experiment, each with its own `README.md` (method, how to run, results), `requirements.txt`, and a `results/` folder.
- API keys live in a single `.env` at the repo root (`cp .env.example .env` and fill it in) and are shared by all experiments. `.gitignore` ignores `.env` at every level, and a local pre-commit hook rejects anything that looks like a key.
- Code, docs and commit messages are in English.
