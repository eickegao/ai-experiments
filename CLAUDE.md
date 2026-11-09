# AI Experiments

Public repo (github.com/eickegao/ai-experiments) backing the YouTube channels Build with AI / 独立营业中. One directory per experiment.

- Everything public-facing is in English: README files, CLI help, docstrings, commit messages. Talk to the user in Chinese as usual.
- Commit after every change, don't push unless asked; no Claude attribution or Co-Authored-By lines.
- API keys only in the repo-root `.env` (gitignored, pre-commit hook guards it). Never paste keys in chat or commit them.
- Each experiment keeps its raw data under its own `results/`; per-ply image frames are not committed.
