#!/usr/bin/env python3
"""NOCLIP mix measurement (docs/design/03_audio_direction.md §6, M3.3).

Reads the rendered WAVs listed in game/assets/audio/manifest.json (run synth.py first)
and prints, per sound and bus, the peak (dBFS), the maximum momentary loudness (400 ms,
LUFS-ish), the maximum 50 ms RMS and the maximum 50 ms K-weighted RMS, every variant
included. Then it checks the 03 §6 numbers the files themselves decide:

  rule 1  every player footstep `foot_*` sits at -14 dB K-weighted RMS peak (+-0.5) at walk,
          except the wading step, which 03 §4 makes louder (and never quieter than -14);
  rule 2  nothing played on the Errors bus peaks above -6 dBFS before the limiter. Files
          rendered for the errors group peak at or under -6 dBFS (synth.py --verify); a sound
          that is louder at 1 m (the contact hit Echo and Flicker play on Errors, Echo's steps
          at -3 dB) is turned down at play time by AudioManager from the manifest's `peak_db`
          and the emitter's distance (AudioMix.errors_headroom_db). This script prints that
          clamp at 1 m and fails when a manifest `peak_db` disagrees with the files;
  rule 3  every room tone is rendered at its manifest `level_db` (+-0.5) and at or above
          -40 dB, so the floor clamp in AudioMix starts from the true level;
  Echo    each echo_foot_* variant's dry part keeps the player's step (the 20 ms extra
          reverb adds, never replaces): its K-weighted RMS peak is within 1 dB of its source.

  python3 tools/audio/measure.py                 # table + checks, exit 1 on a failed check
  python3 tools/audio/measure.py --bus Errors    # only one bus
  python3 tools/audio/measure.py --json out.json # also write the numbers

numpy only (shares synth.py's meters and WAV reader).
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))
import synth  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
TUNING = ROOT / "game" / "src" / "core" / "tuning.gd"

STEP_KRMS_DB = -14.0          # 03 §6 rule 1
STEP_TOL_DB = 0.5
ERRORS_MAX_DB = -6.0          # 03 §6 rule 2
ROOM_FLOOR_DB = -40.0         # 03 §6 rule 3
LEVEL_TOL_DB = 0.5
ECHO_DRY_TOL_DB = 1.0


def tuning_const(name: str, default: float) -> float:
    m = re.search(rf"^const {name}\s*:?=\s*(-?[0-9.]+)", TUNING.read_text(encoding="utf-8"), re.M)
    return float(m.group(1)) if m else default


def played_on_errors() -> dict[str, float]:
    """Sounds a caller plays on the Errors bus that are not in the errors group, with the
    volume_db it passes (game/src/errors: EchoPresent.play_step, ErrorEcho/ErrorFlicker
    contact). AudioManager swaps foot_* for echo_foot_* on Errors, so the step entries are
    the echo variants."""
    echo_db = tuning_const("ECHO_STEP_PLAYBACK_DB", -3.0)
    out = {f"echo_foot_{s}": echo_db for s in ("carpet", "tile", "water", "concrete", "raised_floor", "substrate")}
    out["error_contact_hit"] = 0.0
    return out


def res_to_path(audio_dir: Path, res: str) -> Path:
    rel = res.split("assets/audio/", 1)[1]
    return audio_dir / rel


def measure_file(path: Path, sr: int) -> dict:
    w = synth.read_wav(path)
    pcm = w["pcm"].astype(np.float64) / 32767.0
    if w["loop"] is not None:
        pcm = pcm[:, : pcm.shape[1] - 1]
    return {
        "peak": synth.peak_db(pcm),
        "lufs": synth.loudness_m_max(pcm, sr),
        "rms50": synth.rms_max_db(pcm, sr),
        "krms50": synth.krms_max_db(pcm, sr),
    }


def measure_all(audio_dir: Path) -> dict:
    man = json.loads((audio_dir / "manifest.json").read_text(encoding="utf-8"))
    sr = int(man["rate"])
    out = {}
    for sid, e in man["sounds"].items():
        rows = [measure_file(res_to_path(audio_dir, f), sr) for f in e["files"]]
        out[sid] = {
            "bus": e["bus"], "loop": e["loop"], "runtime": e.get("runtime", {}),
            "variants": rows,
            "runtime_peak": e.get("peak_db"),
            "peak": max(r["peak"] for r in rows),
            "lufs": float(np.mean([r["lufs"] for r in rows])),
            "rms50": float(np.mean([r["rms50"] for r in rows])),
            "krms50": float(np.mean([r["krms50"] for r in rows])),
        }
    return out


def check(m: dict) -> list[str]:
    errs = []
    for sid, s in m.items():
        if sid.startswith("foot_"):
            for i, r in enumerate(s["variants"], 1):
                louder_ok = sid == "foot_water" and r["krms50"] >= STEP_KRMS_DB - STEP_TOL_DB
                if abs(r["krms50"] - STEP_KRMS_DB) > STEP_TOL_DB and not louder_ok:
                    errs.append(f"rule 1: {sid} v{i:02d} K-RMS {r['krms50']:.2f} dB, want {STEP_KRMS_DB}")
        if sid.startswith("room_tone_"):
            want = float(s["runtime"].get("level_db", 0.0))
            if want < ROOM_FLOOR_DB:
                errs.append(f"rule 3: {sid} level_db {want} below {ROOM_FLOOR_DB}")
            if abs(s["lufs"] - want) > LEVEL_TOL_DB:
                errs.append(f"rule 3: {sid} measures {s['lufs']:.2f} LUFS, manifest level_db {want}")
    errors = {sid: 0.0 for sid, s in m.items() if s["bus"] == "Errors"}
    errors.update(played_on_errors())
    for sid, gain in sorted(errors.items()):
        if sid not in m:
            errs.append(f"rule 2: {sid} is played on Errors but is not in the manifest")
            continue
        man_peak = m[sid]["runtime_peak"]
        if man_peak is None or abs(man_peak - m[sid]["peak"]) > 0.05:
            errs.append(f"rule 2: {sid} manifest peak_db {man_peak} != measured {m[sid]['peak']:.2f}")
        pk = m[sid]["peak"] + gain
        clamp = min(0.0, ERRORS_MAX_DB - pk)
        print(f"rule 2: {sid:24s} peak {pk:6.2f} dBFS at 1 m ({gain:+.1f} dB playback)"
              + (f", AudioManager turns it down {-clamp:.2f} dB at 1 m" if clamp < 0 else ", fits"))
    for sid in m:
        if sid.startswith("echo_foot_"):
            src = m.get(sid[len("echo_"):])
            if src is None:
                errs.append(f"Echo: {sid} has no source")
                continue
            for i, (a, b) in enumerate(zip(m[sid]["variants"], src["variants"]), 1):
                if abs(a["krms50"] - b["krms50"]) > ECHO_DRY_TOL_DB:
                    errs.append(f"Echo: {sid} v{i:02d} K-RMS {a['krms50']:.2f} vs its step {b['krms50']:.2f}")
    return errs


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--audio", type=Path, default=ROOT / "game" / "assets" / "audio")
    ap.add_argument("--bus", default="")
    ap.add_argument("--json", type=Path)
    args = ap.parse_args(argv)
    m = measure_all(args.audio)
    print(f"{'id':26s}{'bus':>10s}{'n':>3s}{'peak':>8s}{'LUFS-M':>8s}{'RMS50':>8s}{'K-RMS':>8s}")
    for bus in ("Footsteps", "Player", "Interact", "Errors", "Ambience", "Music", "UI"):
        if args.bus and bus != args.bus:
            continue
        for sid, s in sorted(m.items(), key=lambda kv: -kv[1]["lufs"]):
            if s["bus"] != bus:
                continue
            print(f"{sid:26s}{bus:>10s}{len(s['variants']):3d}{s['peak']:8.1f}{s['lufs']:8.1f}"
                  f"{s['rms50']:8.1f}{s['krms50']:8.1f}{'  loop' if s['loop'] else ''}")
    errs = check(m)
    for e in errs:
        print(f"FAIL {e}")
    print(f"measure: {len(m)} sounds, {sum(len(s['variants']) for s in m.values())} files, {len(errs)} problems")
    if args.json:
        args.json.write_text(json.dumps(m, indent=1) + "\n", encoding="utf-8")
    return 1 if errs else 0


if __name__ == "__main__":
    sys.exit(main())
