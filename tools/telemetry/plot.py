#!/usr/bin/env python3
"""Plot a Director telemetry CSV (10 §9) so the sawtooth can be seen.

usage: tools/telemetry/plot.py <level.csv> [more.csv ...] [--out <dir>]

Writes <name>.svg next to each CSV (or into --out): intensity (white line) and threat
(accent) over time, phases as background bands (Calm, Build, Peak, Relief, Pursuit),
the nearest hunter's distance (dim, 0 to 40 m), and a tick per scare. Standard library
only; no matplotlib needed.
"""
import csv
import os
import sys

PHASE_FILL = {"calm": "#1b2a1b", "build": "#2a2a1b", "peak": "#3a1b1b", "relief": "#1b2433", "pursuit": "#331b33"}
W, H, PAD = 1200, 320, 40


def load(path):
    with open(path, newline="") as f:
        return list(csv.DictReader(f))


def plot(rows, title):
    if not rows:
        return "<svg xmlns='http://www.w3.org/2000/svg'/>"
    t_end = max(float(r["time"]) for r in rows) or 1.0
    x = lambda t: PAD + (W - 2 * PAD) * float(t) / t_end
    y = lambda v: H - PAD - (H - 2 * PAD) * max(0.0, min(1.0, float(v)))
    out = [f"<svg xmlns='http://www.w3.org/2000/svg' width='{W}' height='{H}' font-family='monospace' font-size='11'>",
           f"<rect width='{W}' height='{H}' fill='#000'/>"]
    start = 0
    for i in range(1, len(rows) + 1):
        if i == len(rows) or rows[i]["phase"] != rows[start]["phase"]:
            ph = rows[start]["phase"]
            x0 = x(rows[start]["time"])
            x1 = x(rows[i]["time"]) if i < len(rows) else W - PAD
            out.append(f"<rect x='{x0:.1f}' y='{PAD}' width='{max(x1 - x0, 0.5):.1f}' height='{H - 2 * PAD}' fill='{PHASE_FILL.get(ph, '#111')}'/>")
            out.append(f"<text x='{x0 + 2:.1f}' y='{PAD + 12}' fill='#888'>{ph}</text>")
            start = i

    def line(key, color, scale=1.0, width=1.5):
        pts = []
        for r in rows:
            v = r.get(key, "")
            if v == "":
                continue
            pts.append(f"{x(r['time']):.1f},{y(float(v) / scale):.1f}")
        if pts:
            out.append(f"<polyline fill='none' stroke='{color}' stroke-width='{width}' points='{' '.join(pts)}'/>")

    line("nearest_hunter_d", "#555", 40.0, 1.0)
    line("threat", "#ff4a2e")
    line("intensity", "#f2f2f2", 1.0, 2.0)
    for r in rows:
        if r.get("scare"):
            xs = x(r["time"])
            out.append(f"<line x1='{xs:.1f}' x2='{xs:.1f}' y1='{H - PAD}' y2='{H - PAD + 8}' stroke='#7cff4a'/>")
            out.append(f"<text x='{xs + 2:.1f}' y='{H - PAD + 18}' fill='#7cff4a' font-size='9'>{r['scare']}</text>")
    out.append(f"<text x='{PAD}' y='{PAD - 12}' fill='#f2f2f2'>{title}  intensity (white), threat (red), nearest hunter 0-40 m (grey), scares (green)</text>")
    out.append(f"<text x='{W - PAD}' y='{H - 8}' fill='#888' text-anchor='end'>{t_end:.0f} s</text>")
    out.append("</svg>")
    return "\n".join(out)


def main(argv):
    out_dir = None
    paths = []
    i = 0
    while i < len(argv):
        if argv[i] == "--out" and i + 1 < len(argv):
            out_dir = argv[i + 1]
            i += 2
            continue
        paths.append(argv[i])
        i += 1
    if not paths:
        print(__doc__)
        return 2
    for p in paths:
        svg = plot(load(p), os.path.basename(p))
        target = os.path.join(out_dir or os.path.dirname(p) or ".", os.path.splitext(os.path.basename(p))[0] + ".svg")
        if out_dir:
            os.makedirs(out_dir, exist_ok=True)
        with open(target, "w") as f:
            f.write(svg)
        print(target)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
