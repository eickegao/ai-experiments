# AI Experiments

Experiments behind the YouTube channels **Build with AI** (English) and **独立营业中** (Chinese). Every experiment lives in its own directory with the code, raw data and results, so every claim made in a video can be checked here.

| Directory | Experiment | Status |
|---|---|---|
| [`chess-arena/`](chess-arena/) | Anthropic's strongest model vs OpenAI's strongest model at chess. Legality checked by python-chess, quality scored by Stockfish, two games per round with colors swapped. | Pipeline ready, match pending |

## Conventions

- One directory per experiment, each with its own `README.md` (method, how to run, results), `requirements.txt`, and a `results/` folder.
- API keys live in a single `.env` at the repo root (`cp .env.example .env` and fill it in) and are shared by all experiments. `.gitignore` ignores `.env` at every level, and a local pre-commit hook rejects anything that looks like a key.
- Code, docs and commit messages are in English.
