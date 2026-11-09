# AI Experiments

Public repo (github.com/eickegao/ai-experiments, MIT) backing the YouTube channels Build with AI / 独立营业中. One directory per experiment. Talk to the user in Chinese; everything in the repo is English with a Chinese mirror.

## Format every experiment must follow (user decided 2026-11-08)

- **Directory**: `<experiment-slug>/` at the repo root, kebab-case English name. Add a row to the index table in both root READMEs (`README.md` English, `README.zh.md` Chinese) with status.
- **Docs in both languages**: `README.md` (English) and `README.zh.md` (Chinese), each with a language switch line at the top (`English · [中文说明](README.zh.md)` / `[English](README.md) · 中文说明`). Sections: what and why, verification method, experiment design, models (exact IDs), how to run, output files, results.
- **Links**: channel names are the links ([**Build with AI**](https://www.youtube.com/@buildwithai2027), [**独立营业中**](https://www.youtube.com/@独立营业中)); no bare URLs; website is [videodoz.com](https://videodoz.com). No App Store / Google Play links.
- **Reproducible**: `requirements.txt`, exact model IDs and prompts in the code, a free dry-run mode that needs no API keys, all raw data under `results/` (JSON with every raw model reply, plus human-readable summary.md). Large per-frame images are gitignored and regenerable.
- **Video assets** are produced by the experiment itself (frames, replay mp4, charts, key-moment list), landscape 1920x1080 by default, portrait option for Shorts.
- **Cost and time**: record tokens, wall-clock seconds and USD cost per model call; price table lives in the experiment.
- **Language**: code, docstrings, comments, CLI help, commit messages all English. Commit after every change, don't push unless asked; no Claude attribution lines.
- **Keys**: only in the repo-root `.env` (gitignored; pre-commit hook rejects .env files and key-like strings). Never paste keys in chat or commit them.
- The video for an experiment is built in `~/Projects/VideoDoz` (Remotion), Chinese version first, long-form landscape; the experiment repo holds only code and data.
