#!/usr/bin/env python3
"""Give a recorded replay its sound: the game's background track plus the game's own skill sound effects at the moments
the log says they were cast (the headless recording has no audio track).

    python3 add_audio.py results/2026-11-09_round2 1        # game_1.mp4 → game_1.mp4 with audio (original kept as game_1_silent.mp4 until success)

Sound per skill = the mapping the game uses (clashdoz_game.gui_script SKILL_SND): freeze→timestop, split→clone, accel→boost,
bomb→bomb, giant→giant, fire→laser (aim) + bomb (hit, 0.35 s later), lightning→laser, teleport→warp, shatter→clone (lower),
shock→shock, chain→chain, snowball→shock (quiet). Plus the last-10-seconds tick and the win jingle at 60 s.
Game time 0 = the first frame on which the board is visible (the recording starts on a white/black loading page).
"""
from __future__ import annotations

import json
import subprocess
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
AUDIO = HERE / "game" / "assets" / "audio" / "clashdoz"
SKILL_SND = {"freeze": ("timestop", 0.9), "split": ("clone", 0.8), "accel": ("boost", 0.8), "bomb": ("bomb", 0.9), "giant": ("giant", 1.0),
             "lightning": ("laser", 0.8), "teleport": ("warp", 0.9), "shatter": ("clone", 0.55), "shock": ("shock", 1.0), "chain": ("chain", 0.9),
             "snowball": ("shock", 0.45)}
BGM_GAIN = 0.32
SFX_GAIN = 0.9


def board_offset(mp4: Path) -> float:
    """seconds into the video at which the board first shows (mean grey of the board area jumps from ~0/255 to ~130)"""
    raw = subprocess.run(["ffmpeg", "-loglevel", "error", "-i", str(mp4), "-t", "6", "-vf", "crop=900:900:90:450,scale=8:8", "-f", "rawvideo", "-pix_fmt", "gray", "-"],
                         capture_output=True, check=True).stdout
    for i in range(len(raw) // 64):
        m = sum(raw[i * 64:(i + 1) * 64]) / 64
        if 60 < m < 220:
            return i / 30
    return 0.0


def main():
    run, no = Path(sys.argv[1]), int(sys.argv[2])
    rec = json.loads((run / f"game_{no}.json").read_text())
    mp4 = run / f"game_{no}.mp4"
    silent = run / f"game_{no}_silent.mp4"
    if not silent.exists():
        mp4.rename(silent)
    off = board_offset(silent)
    dur = float(subprocess.run(["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "csv=p=0", str(silent)], capture_output=True, text=True).stdout)
    skills = {L: [s["id"] for s in t["skills"]] for L, t in rec["setup"]["teams"].items()}
    events: list[tuple[float, str, float]] = []   # (seconds in video, wav name, gain)
    for c in rec["commands"]:
        if c["cmd"]["type"] != "cast" or not c["accepted"]:
            continue
        sk = skills[c["team"]][c["cmd"]["slot"] - 1]
        t = off + c["tick"] / 60
        if sk == "fire":
            events.append((t, "laser", 0.35)); events.append((t + 0.35, "bomb", 1.0))
        elif sk in SKILL_SND:
            events.append((t, SKILL_SND[sk][0], SKILL_SND[sk][1]))
    for s in range(50, 60):
        events.append((off + s, "tick", 0.5))
    events.append((off + 60.0, "win", 0.9))
    events.sort()
    cmd = ["ffmpeg", "-y", "-loglevel", "error", "-i", str(silent), "-stream_loop", "-1", "-i", str(AUDIO / "bgm_four_color_2.ogg")]
    for _, name, _ in events:
        cmd += ["-i", str(AUDIO / f"{name}.wav")]
    parts = [f"[1:a]volume={BGM_GAIN},afade=t=out:st={dur - 2.5:.2f}:d=2.5,atrim=0:{dur:.3f}[bgm]"]
    labels = ["[bgm]"]
    for k, (t, _, g) in enumerate(events):
        ms = int(round(t * 1000))
        parts.append(f"[{k + 2}:a]volume={g * SFX_GAIN:.2f},adelay={ms}|{ms}[s{k}]")
        labels.append(f"[s{k}]")
    parts.append("".join(labels) + f"amix=inputs={len(labels)}:duration=first:normalize=0[mix]")
    cmd += ["-filter_complex", ";".join(parts), "-map", "0:v", "-map", "[mix]", "-c:v", "copy", "-c:a", "aac", "-b:a", "160k", "-shortest", str(mp4)]
    subprocess.run(cmd, check=True)
    silent.unlink()
    print(f"game {no}: board at {off:.2f} s, {len(events)} sounds → {mp4}")


if __name__ == "__main__":
    main()
