#!/usr/bin/env python3
"""NOCLIP sound synthesis (docs/design/03_audio_direction.md §2).

Renders every recipe in tools/audio/recipes.json to 48 kHz 16-bit WAV files,
deterministically from seeds, and writes game/assets/audio/manifest.json for the
game (AudioManager) and its tests. numpy only.

  python3 tools/audio/synth.py --out game/assets/audio            # render all
  python3 tools/audio/synth.py --out game/assets/audio --only foot_tile
  python3 tools/audio/synth.py --out game/assets/audio --verify   # check, write nothing
  python3 tools/audio/synth.py --out game/assets/audio --report   # timbre numbers

Recipe schema: tools/audio/README.md. Loops are rendered circularly: every source
is periodic in the loop length (noise is shaped in the frequency domain over the
loop, oscillator and LFO frequencies are quantised to whole cycles per loop, and
stateful effects are pre-rolled over earlier periods), so the tail crossfades into
the head exactly and the seam is as smooth as any other point of the file.
"""
from __future__ import annotations

import argparse
import json
import math
import os
import re
import struct
import sys
import zlib
from pathlib import Path

import numpy as np

SCHEMA = 1
ID_RE = re.compile(r"^[a-z][a-z0-9_]*$")
FADE_IN_S = 0.002          # 03 §6 rule 4: every sample has a 2 ms fade-in
FADE_OUT_S = 0.005         # one-shots end on a short fade so the last sample is 0
NOISE_RMS = 0.25           # every noise source is scaled to this RMS before gains
LOOP_PREROLL_S = 1.0       # IIR state settles over this much of the previous period
REVERB_TAIL_S = 3.0        # extra pre-roll for reverbs inside loops

# Seed-path purposes (kept stable: changing one changes every file).
P_VARIANT, P_LAYER, P_NOISE, P_LFO, P_PHASE = 1, 2, 3, 4, 5


class RecipeError(Exception):
    pass


def undb(d: float) -> float:
    return 10.0 ** (d / 20.0)


def to_db(x: float) -> float:
    return 20.0 * math.log10(max(x, 1e-12))


def crc(s: str) -> int:
    return zlib.crc32(s.encode("utf-8")) & 0xFFFFFFFF


def rng_for(key: list[int], purpose: int, *extra: int) -> np.random.Generator:
    return np.random.default_rng([*key, purpose, *extra])


# --------------------------------------------------------------------------- context


class Ctx:
    """Per-render state: sample rate, seed path, pitch factor, loop length, channel."""

    def __init__(self, sr: int, key: list[int], pitch: float, loop_n: int | None,
                 ch: int, nch: int, decorrelate: bool, recipes: dict, depth: int = 0):
        self.sr = sr
        self.key = key
        self.pitch = pitch
        self.loop_n = loop_n
        self.ch = ch
        self.nch = nch
        self.decorrelate = decorrelate
        self.recipes = recipes
        self.depth = depth
        self.jit: dict = {}

    def child(self, key: list[int], loop_n: int | None = -1, depth: int | None = None) -> "Ctx":
        c = Ctx(self.sr, key, self.pitch, self.loop_n if loop_n == -1 else loop_n, self.ch, self.nch,
                self.decorrelate, self.recipes, self.depth if depth is None else depth)
        c.jit = self.jit
        return c

    @property
    def loop(self) -> bool:
        return self.loop_n is not None

    @property
    def loop_t(self) -> float:
        return self.loop_n / self.sr

    def noise_ch(self) -> int:
        return self.ch if self.decorrelate else 0

    def qfreq(self, f: float) -> float:
        """In a loop, quantise a frequency to a whole number of cycles per loop."""
        if not self.loop:
            return f
        cycles = max(1, round(f * self.loop_t))
        return cycles / self.loop_t


# --------------------------------------------------------------------------- parameters


def param(v, n: int, ctx: Ctx, freq: bool = False, track: bool = True):
    """A number, a [start, end] sweep over n samples, or {"points": [[t, v], ...]}.

    Frequencies follow the variant pitch factor when track is true. Returns a float
    or an ndarray of length n.
    """
    scale = ctx.pitch if (freq and track) else 1.0
    if isinstance(v, (int, float)):
        out = float(v) * scale
        return ctx.qfreq(out) if freq else out
    if ctx.loop:
        raise RecipeError("swept parameters are not allowed in loops")
    if isinstance(v, list) and len(v) == 2:
        a, b = float(v[0]) * scale, float(v[1]) * scale
        x = np.linspace(0.0, 1.0, n, endpoint=False) if n > 0 else np.zeros(0)
        if freq and a > 0 and b > 0:
            return a * (b / a) ** x
        return a + (b - a) * x
    if isinstance(v, dict) and "points" in v:
        pts = np.asarray(v["points"], dtype=float)
        t = np.arange(n) / ctx.sr
        return np.interp(t, pts[:, 0], pts[:, 1]) * scale
    raise RecipeError(f"bad parameter {v!r}")


def as_array(v, n: int) -> np.ndarray:
    return v if isinstance(v, np.ndarray) else np.full(n, float(v))


# --------------------------------------------------------------------------- sources


def _blep(t: np.ndarray, dt: np.ndarray) -> np.ndarray:
    """PolyBLEP residual, vectorised. t is phase in [0, 1), dt the phase increment."""
    out = np.zeros_like(t)
    a = t < dt
    x = t[a] / dt[a]
    out[a] = x + x - x * x - 1.0
    b = t > 1.0 - dt
    x = (t[b] - 1.0) / dt[b]
    out[b] = x * x + x + x + 1.0
    return out


def osc(wave: str, freq, n: int, sr: int, phase0: float, duty: float = 0.5) -> np.ndarray:
    f = as_array(freq, n)
    dt = np.clip(np.abs(f) / sr, 1e-9, 0.5)
    ph = (phase0 + np.concatenate(([0.0], np.cumsum(f[:-1] / sr)))) % 1.0 if n else np.zeros(0)
    if wave == "sine":
        return np.sin(2 * np.pi * ph)
    if wave == "saw":
        return 2.0 * ph - 1.0 - _blep(ph, dt)
    if wave in ("square", "pulse"):
        d = duty if wave == "pulse" else 0.5
        y = np.where(ph < d, 1.0, -1.0)
        return y + _blep(ph, dt) - _blep((ph - d) % 1.0, dt)
    if wave == "triangle":
        return 1.0 - 4.0 * np.abs(ph - 0.5)
    raise RecipeError(f"unknown oscillator {wave!r}")


NOISE_SLOPES = {"white": 0.0, "pink": -0.5, "brown": -1.0, "blue": 0.5, "violet": 1.0}


def noise(color: str, n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """Coloured noise shaped in the frequency domain (circular, so periodic in n)."""
    if n <= 1:
        return np.zeros(n)
    if color not in NOISE_SLOPES:
        raise RecipeError(f"unknown noise colour {color!r}")
    w = rng.standard_normal(n)
    slope = NOISE_SLOPES[color]
    if slope != 0.0:
        spec = np.fft.rfft(w)
        f = np.fft.rfftfreq(n, 1.0 / sr)
        f = np.maximum(f, 20.0)  # flat below 20 Hz so brown noise does not run away
        spec *= (f / 1000.0) ** slope
        spec[0] = 0.0
        w = np.fft.irfft(spec, n)
    w -= w.mean()
    rms = math.sqrt(float(np.mean(w * w))) or 1.0
    return w * (NOISE_RMS / rms)


def smooth_random(rate: float, n: int, sr: int, rng: np.random.Generator) -> np.ndarray:
    """A random control signal in [0, 1] with energy below `rate` Hz (periodic in n)."""
    if n <= 1:
        return np.full(n, 0.5)
    w = rng.standard_normal(n)
    spec = np.fft.rfft(w)
    f = np.fft.rfftfreq(n, 1.0 / sr)
    spec *= np.exp(-0.5 * (f / max(rate, 0.01)) ** 2)
    spec[0] = 0.0
    y = np.fft.irfft(spec, n)
    s = float(np.std(y)) or 1.0
    return 0.5 + 0.5 * np.tanh(y / (1.2 * s))


def lfo(spec: dict, n: int, ctx: Ctx, rng: np.random.Generator, track: bool = False) -> np.ndarray:
    """Control signal in [0, 1]. wave: sine, square, saw, triangle, random, shape."""
    wave = spec.get("wave", "sine")
    f = param(spec["freq"], n, ctx, freq=True, track=spec.get("track", track))
    ph0 = float(spec.get("phase", 0.0))
    if wave == "random":
        return smooth_random(float(np.mean(f)), n, ctx.sr, rng)
    fa = as_array(f, n)
    ph = (ph0 + np.concatenate(([0.0], np.cumsum(fa[:-1] / ctx.sr)))) % 1.0 if n else np.zeros(0)
    if wave == "sine":
        return 0.5 + 0.5 * np.sin(2 * np.pi * ph)
    if wave == "square":
        return (ph < float(spec.get("duty", 0.5))).astype(float)
    if wave == "saw":
        return ph
    if wave == "triangle":
        return 1.0 - 2.0 * np.abs(ph - 0.5)
    if wave == "shape":
        pts = np.asarray(spec["points"], dtype=float)
        return np.interp(ph, pts[:, 0], pts[:, 1])
    raise RecipeError(f"unknown lfo wave {wave!r}")


# --------------------------------------------------------------------------- envelopes


def _curve(x: np.ndarray, k: float) -> np.ndarray:
    return x if k == 0 else (1.0 - np.exp(-k * x)) / (1.0 - math.exp(-k))


def envelope(env: dict | None, n: int, sr: int) -> np.ndarray:
    if not env or n == 0:
        return np.ones(n)
    t = np.arange(n) / sr
    kind = env.get("type", "adsr")
    if kind == "adsr":
        a, d, s, r = (float(env.get(k, dflt)) for k, dflt in (("a", 0.002), ("d", 0.0), ("s", 1.0), ("r", 0.0)))
        k = float(env.get("curve", 4.0))
        T = n / sr
        rel0 = max(T - r, 0.0)
        y = np.empty(n)
        att = t < a
        y[att] = 0.5 - 0.5 * np.cos(np.pi * t[att] / max(a, 1e-9))
        dec = (~att) & (t < a + d)
        y[dec] = 1.0 + (s - 1.0) * _curve((t[dec] - a) / max(d, 1e-9), k)
        sus = (~att) & (~dec)
        y[sus] = s
        if r > 0:
            rel = t >= rel0
            start = np.interp(rel0, t, y) if rel0 > 0 else y[0]
            y[rel] = start * (1.0 - _curve((t[rel] - rel0) / r, k))
        return y
    if kind == "exp":
        a = float(env.get("a", 0.001))
        t60 = float(env["t60"])
        y = np.exp(-6.907755 * np.maximum(t - a, 0.0) / t60)
        att = t < a
        y[att] = 0.5 - 0.5 * np.cos(np.pi * t[att] / max(a, 1e-9))
        return y
    if kind == "points":
        pts = np.asarray(env["points"], dtype=float)
        v = np.interp(t, pts[:, 0], pts[:, 1])
        return np.power(10.0, v / 20.0) * (v > -119.0) if env.get("db") else v
    raise RecipeError(f"unknown envelope {kind!r}")


# --------------------------------------------------------------------------- filters


def biquad_coeffs(kind: str, f, q, gain_db: float, sr: int):
    """RBJ cookbook coefficients; f and q may be arrays (time-varying)."""
    f = np.clip(f, 5.0, 0.45 * sr)
    w0 = 2 * np.pi * f / sr
    c, s = np.cos(w0), np.sin(w0)
    alpha = s / (2 * q)
    if kind == "lp":
        b0 = b2 = (1 - c) / 2; b1 = 1 - c; a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha
    elif kind == "hp":
        b0 = b2 = (1 + c) / 2; b1 = -(1 + c); a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha
    elif kind == "bp":
        b0 = alpha; b1 = 0 * c; b2 = -alpha; a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha
    elif kind == "notch":
        b0 = 1 + 0 * c; b1 = -2 * c; b2 = 1 + 0 * c; a0 = 1 + alpha; a1 = -2 * c; a2 = 1 - alpha
    elif kind == "peak":
        A = 10 ** (gain_db / 40)
        b0 = 1 + alpha * A; b1 = -2 * c; b2 = 1 - alpha * A
        a0 = 1 + alpha / A; a1 = -2 * c; a2 = 1 - alpha / A
    elif kind in ("lowshelf", "highshelf"):
        A = 10 ** (gain_db / 40)
        sq = 2 * np.sqrt(A) * alpha
        if kind == "lowshelf":
            b0 = A * ((A + 1) - (A - 1) * c + sq); b1 = 2 * A * ((A - 1) - (A + 1) * c)
            b2 = A * ((A + 1) - (A - 1) * c - sq); a0 = (A + 1) + (A - 1) * c + sq
            a1 = -2 * ((A - 1) + (A + 1) * c); a2 = (A + 1) + (A - 1) * c - sq
        else:
            b0 = A * ((A + 1) + (A - 1) * c + sq); b1 = -2 * A * ((A - 1) + (A + 1) * c)
            b2 = A * ((A + 1) + (A - 1) * c - sq); a0 = (A + 1) - (A - 1) * c + sq
            a1 = 2 * ((A - 1) - (A + 1) * c); a2 = (A + 1) - (A - 1) * c - sq
    else:
        raise RecipeError(f"unknown filter {kind!r}")
    return b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0


def run_biquad(x: np.ndarray, co) -> np.ndarray:
    """Direct form I. Coefficients are floats or arrays of len(x)."""
    n = len(x)
    xs = x.tolist()
    y = [0.0] * n
    x1 = x2 = y1 = y2 = 0.0
    if all(np.ndim(c) == 0 for c in co):
        b0, b1, b2, a1, a2 = (float(c) for c in co)
        for i in range(n):
            xi = xs[i]
            yi = b0 * xi + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = yi
            y[i] = yi
    else:
        B0, B1, B2, A1, A2 = (as_array(c, n).tolist() for c in co)
        for i in range(n):
            xi = xs[i]
            yi = B0[i] * xi + B1[i] * x1 + B2[i] * x2 - A1[i] * y1 - A2[i] * y2
            x2 = x1; x1 = xi; y2 = y1; y1 = yi
            y[i] = yi
    return np.asarray(y)


def run_onepole(x: np.ndarray, f, sr: int, high: bool) -> np.ndarray:
    n = len(x)
    a = 1.0 - np.exp(-2 * np.pi * np.clip(as_array(f, n), 1.0, 0.45 * sr) / sr)
    xs, al = x.tolist(), a.tolist()
    y = [0.0] * n
    s = 0.0
    for i in range(n):
        s += al[i] * (xs[i] - s)
        y[i] = s
    lp = np.asarray(y)
    return x - lp if high else lp


# --------------------------------------------------------------------------- effects

STATEFUL = {"lp", "hp", "bp", "notch", "peak", "lowshelf", "highshelf", "lp1", "hp1", "delay", "reverb"}
BIQUADS = {"lp", "hp", "bp", "notch", "peak", "lowshelf", "highshelf"}

# Freeverb tunings at 44.1 kHz, scaled to the render rate.
FV_COMBS = (1116, 1188, 1277, 1356, 1422, 1491, 1557, 1617)
FV_ALLPASS = (556, 441, 341, 225)
FV_SPREAD = 23


def freeverb(x: np.ndarray, room: float, damp: float, sr: int, ch: int) -> np.ndarray:
    scale = sr / 44100.0
    spread = FV_SPREAD * ch
    fb = 0.7 + 0.28 * room
    d = 0.4 * damp
    n = len(x)
    xs = (x * 0.015).tolist()
    out = np.zeros(n)
    for L in FV_COMBS:
        D = int((L + spread) * scale)
        buf = [0.0] * D
        idx = 0
        st = 0.0
        y = [0.0] * n
        for i in range(n):
            o = buf[idx]
            st = o * (1 - d) + st * d
            buf[idx] = xs[i] + st * fb
            idx += 1
            if idx == D:
                idx = 0
            y[i] = o
        out += np.asarray(y)
    ys = out.tolist()
    for L in FV_ALLPASS:
        D = int((L + spread) * scale)
        buf = [0.0] * D
        idx = 0
        for i in range(n):
            b = buf[idx]
            o = -ys[i] + b
            buf[idx] = ys[i] + b * 0.5
            idx += 1
            if idx == D:
                idx = 0
            ys[i] = o
    return np.asarray(ys) * 3.0


def apply_fx(x: np.ndarray, fx: dict, ctx: Ctx, t0_s: float, rng_key: list[int]) -> np.ndarray:
    kind = fx["fx"]
    n = len(x)
    sr = ctx.sr
    track = fx.get("track", True)
    if kind in BIQUADS:
        f = param(fx["f"], n, ctx, freq=True, track=track)
        if "bw" in fx:
            q = f / (float(fx["bw"]) * (ctx.pitch if track else 1.0))
        else:
            q = param(fx.get("q", 0.7071), n, ctx)
        co = biquad_coeffs(kind, f, q, float(fx.get("gain_db", 0.0)), sr)
        y = x
        for _ in range(max(1, int(fx.get("order", 2)) // 2)):
            y = run_biquad(y, co)
        return y
    if kind in ("lp1", "hp1"):
        return run_onepole(x, param(fx["f"], n, ctx, freq=True, track=track), sr, kind == "hp1")
    if kind == "gain":
        return x * undb(float(fx["db"]))
    if kind == "drive":
        # Soft clip with unity small-signal gain, the knee `db` below the signal's own
        # peak (level-independent). Adds odd harmonics to tones and shaves the Gaussian
        # peaks of noise (crest control).
        g = undb(float(fx["db"]))
        pk = max(float(np.max(np.abs(x))), 1e-12)
        wet = np.tanh(g * x / pk) * (pk / g)
        m = float(fx.get("mix", 1.0))
        return x * (1 - m) + wet * m
    if kind == "crush":
        y = x
        hold = int(fx.get("hold", 1))
        if hold > 1:
            idx = (np.arange(n) // hold) * hold
            y = y[np.minimum(idx, n - 1)]
        if "bits" in fx:
            steps = 2.0 ** (float(fx["bits"]) - 1)
            y = np.round(y * steps) / steps
        return y
    if kind == "am":
        rng = rng_for(rng_key, P_LFO)
        m = lfo(fx, n, ctx, rng)
        depth = param(fx.get("depth", 1.0), n, ctx)
        return x * (1.0 - depth + depth * m)
    if kind == "ring":
        f = param(fx["freq"], n, ctx, freq=True, track=track)
        car = osc(fx.get("wave", "sine"), f, n, sr, float(fx.get("phase", 0.0)))
        m = float(fx.get("mix", 1.0))
        return x * (1 - m) + x * car * m
    if kind == "gap":
        at = float(fx["at"]) - t0_s
        g = np.ones(n)
        i0, i1 = int(round(at * sr)), int(round((at + float(fx["dur"])) * sr))
        r = max(1, int(0.001 * sr))
        for i in range(max(i0 - r, 0), min(i0, n)):
            g[i] = 0.5 + 0.5 * math.cos(math.pi * (i - (i0 - r)) / r)
        g[max(i0, 0):max(min(i1, n), 0)] = 0.0
        for i in range(max(i1, 0), min(i1 + r, n)):
            g[i] = 0.5 - 0.5 * math.cos(math.pi * (i - i1) / r)
        return x * g
    if kind == "fade":
        g = np.ones(n)
        fi, fo = int(float(fx.get("in", 0)) * sr), int(float(fx.get("out", 0)) * sr)
        if fi:
            g[:fi] *= 0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi)
        if fo:
            g[n - fo:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(fo) / fo)
        return x * g
    if kind == "delay":
        D = max(1, int(float(fx["time"]) * sr))
        fb = float(fx.get("fb", 0.3))
        damp = fx.get("damp")
        a = 1.0 - math.exp(-2 * math.pi * float(damp) / sr) if damp else 1.0
        xs = x.tolist()
        buf = [0.0] * D
        wet = [0.0] * n
        idx = 0
        st = 0.0
        for i in range(n):
            o = buf[idx]
            st += a * (o - st)
            buf[idx] = xs[i] + st * fb
            idx += 1
            if idx == D:
                idx = 0
            wet[i] = o
        m = float(fx.get("mix", 0.3))
        return x * (1 - m) + np.asarray(wet) * m
    if kind == "reverb":
        pre = int(float(fx.get("predelay", 0.0)) * sr)
        src = np.concatenate((np.zeros(pre), x))[:n] if pre else x
        wet = freeverb(src, float(fx.get("room", 0.5)), float(fx.get("damp", 0.5)), sr, ctx.ch)
        w = float(fx.get("wet", 0.3))
        return x * (1 - w) + wet * w
    raise RecipeError(f"unknown effect {kind!r}")


def apply_chain(x: np.ndarray, chain: list, ctx: Ctx, t0_s: float, key: list[int]) -> np.ndarray:
    n = len(x)
    for i, fx in enumerate(chain or []):
        k = key + [i]
        if ctx.loop and fx["fx"] in STATEFUL:
            pre = LOOP_PREROLL_S + (REVERB_TAIL_S if fx["fx"] in ("reverb", "delay") else 0.0)
            reps = 1 + int(math.ceil(pre * ctx.sr / n))
            x = apply_fx(np.tile(x, reps + 1), fx, ctx, t0_s, k)[-n:]
        else:
            x = apply_fx(x, fx, ctx, t0_s, k)
    return x


# --------------------------------------------------------------------------- layers


def source(layer: dict, n: int, ctx: Ctx, key: list[int]) -> np.ndarray:
    src = layer.get("src", "sine")
    if src == "silence":
        return np.zeros(n)
    if src == "noise":
        return noise(layer.get("color", "white"), n, ctx.sr, rng_for(key, P_NOISE, ctx.noise_ch()))
    track = not layer.get("fixed_pitch", False)
    base = param(layer["freq"], n, ctx, freq=True, track=track)
    detune = layer.get("detune", [0.0])
    prng = rng_for(key, P_PHASE)  # phases: identical in both channels
    out = np.zeros(n)
    for cents in detune:
        f = base * 2.0 ** (float(cents) / 1200.0)
        if not isinstance(f, np.ndarray):
            f = ctx.qfreq(f)
        if "fm" in layer:
            fm = layer["fm"]
            if "ratio" in fm:
                mf = as_array(f, n) * float(fm["ratio"])
            else:
                mf = param(fm["freq"], n, ctx, freq=True, track=fm.get("track", False))
            mod = osc(fm.get("wave", "sine"), mf, n, ctx.sr, float(fm.get("phase", 0.0)))
            dev = float(fm["dev"]) if "dev" in fm else float(fm["index"]) * as_array(mf, n)
            f = as_array(f, n) + dev * mod
        phase = float(layer["phase"]) if "phase" in layer else float(prng.random())
        out += osc(src, f, n, ctx.sr, phase, float(layer.get("duty", 0.5)))
    return out / len(detune)


def pan_gain(pan, n: int, ctx: Ctx):
    if ctx.nch == 1:
        return 1.0
    p = np.clip(as_array(param(pan, n, ctx), n), -1.0, 1.0)
    ang = (p + 1.0) * np.pi / 4.0
    return np.cos(ang) if ctx.ch == 0 else np.sin(ang)


def place(out: np.ndarray, sig: np.ndarray, start: int, loop: bool) -> None:
    n = len(out)
    if loop:
        idx = (start + np.arange(len(sig))) % n
        np.add.at(out, idx, sig)
        return
    if start >= n:
        return
    end = min(n, start + len(sig))
    if end > max(start, 0):
        out[max(start, 0):end] += sig[max(0, -start):end - start]


def render_layer(layer: dict, li: int, ctx: Ctx, total_n: int, tscale: float, out: np.ndarray) -> None:
    sr = ctx.sr
    lkey = ctx.key + [P_LAYER, li]
    prng = rng_for(lkey, P_VARIANT)  # timing and gain jitter, channel independent
    jit = ctx.jit
    rep = layer.get("repeat", {})
    count = int(rep.get("count", 1))
    every = float(rep.get("every", 0.0)) * tscale
    if ctx.loop and rep and "count" not in rep:
        count = max(1, round(ctx.loop_t / every))
    if ctx.loop and rep:
        every = ctx.loop_t / max(1, round(ctx.loop_t / every))
    at = float(layer.get("at", 0.0)) * tscale
    if at > 0 and jit.get("time"):
        at = max(0.0, at + prng.uniform(-1, 1) * float(jit["time"]))
    gain = undb(float(layer.get("gain_db", 0.0)))
    if jit.get("gain_db"):
        gain *= undb(prng.uniform(-1, 1) * float(jit["gain_db"]))
    for r in range(count):
        rkey = lkey + [r]
        rrng = rng_for(rkey, P_VARIANT)
        t = at + r * every
        if r > 0 and rep.get("jitter"):
            t += rrng.uniform(-1, 1) * float(rep["jitter"])
        g = gain * undb(float(rep.get("decay_db", 0.0)) * r)
        if rep.get("gain_jitter_db"):
            g *= undb(rrng.uniform(-1, 1) * float(rep["gain_jitter_db"]))
        sub = ctx.child(rkey)
        if rep.get("pitch_jitter"):
            sub.pitch *= 1.0 + rrng.uniform(-1, 1) * float(rep["pitch_jitter"])
        if layer.get("src") == "ref":
            sig = render_ref(layer["ref"], sub)
            if "dur" in layer:
                sig = np.pad(sig, (0, max(0, int(float(layer["dur"]) * tscale * sr) - len(sig))))[
                    : int(float(layer["dur"]) * tscale * sr)]
            n = len(sig)
        else:
            if ctx.loop and not rep:
                n = total_n
            elif "dur" in layer:
                n = max(1, int(round(float(layer["dur"]) * tscale * sr)))
            else:
                n = max(1, total_n - int(round(t * sr)))
            sig = source(layer, n, sub, rkey)
        sig = sig * envelope(layer.get("env"), n, sr)
        sig = apply_chain(sig, layer.get("chain", []), sub, t, rkey + [P_LFO])
        if "peak_db" in layer:  # explicit balance: this layer's own peak, before jitter
            sig = sig * (undb(float(layer["peak_db"])) / max(float(np.max(np.abs(sig))), 1e-12))
        sig = sig * g * pan_gain(layer.get("pan", 0.0), n, sub)
        place(out, sig, int(round(t * sr)), ctx.loop)


def render_ref(ref_id: str, ctx: Ctx) -> np.ndarray:
    recipes = ctx.recipes
    if ref_id not in recipes["recipes"]:
        raise RecipeError(f"ref to unknown recipe {ref_id!r}")
    if ctx.depth > 4:
        raise RecipeError("ref nesting too deep")
    if recipes["recipes"][ref_id].get("loop"):
        raise RecipeError("a loop cannot be referenced as a layer")
    sub = ctx.child(ctx.key + [crc(ref_id)], loop_n=None, depth=ctx.depth + 1)
    return render_mix(ref_id, sub, apply_variant_jitter=False)


def render_mix(rid: str, ctx: Ctx, apply_variant_jitter: bool = True) -> np.ndarray:
    """The summed layers plus the recipe's master chain, before finishing."""
    rec = ctx.recipes["recipes"][rid]
    jit = rec.get("jitter", {}) if not rec.get("loop") else {}
    vr = rng_for(ctx.key, P_VARIANT)
    tscale = 1.0
    if apply_variant_jitter:
        if jit.get("pitch"):
            ctx.pitch *= 1.0 + vr.uniform(-1, 1) * float(jit["pitch"])
        if jit.get("dur"):
            tscale = 1.0 + vr.uniform(-1, 1) * float(jit["dur"])
    ctx.jit = jit
    if rec.get("loop"):
        total_n = ctx.loop_n
    else:
        total_n = int(round(float(rec["dur"]) * tscale * ctx.sr))
    out = np.zeros(total_n)
    for li, layer in enumerate(rec["layers"]):
        render_layer(layer, li, ctx, total_n, tscale, out)
    return apply_chain(out, rec.get("fx", []), ctx, 0.0, ctx.key + [P_LFO, 999])


# --------------------------------------------------------------------------- measurement

# ITU-R BS.1770 K-weighting at 48 kHz (pre-filter shelf, then RLB high-pass).
K1 = (1.53512485958697, -2.69169618940638, 1.19839281085285, -1.69065929318241, 0.73248077421585)
K2 = (1.0, -2.0, 1.0, -1.99004745483398, 0.99007225036621)


def _sliding_mean(x2: np.ndarray, w: int, hop: int) -> np.ndarray:
    if len(x2) < w:
        x2 = np.pad(x2, (0, w - len(x2)))
    c = np.concatenate(([0.0], np.cumsum(x2)))
    starts = np.arange(0, len(x2) - w + 1, hop)
    return (c[starts + w] - c[starts]) / w


def loudness_m_max(chans: np.ndarray, sr: int) -> float:
    """Maximum momentary loudness (400 ms window, 10 ms hop), LUFS-ish."""
    z = None
    for ch in chans:
        k = run_biquad(run_biquad(ch, K1), K2)
        m = _sliding_mean(k * k, int(0.4 * sr), int(0.01 * sr))
        z = m if z is None else z + m
    return -0.691 + 10 * math.log10(max(float(z.max()), 1e-20))


def rms_max_db(chans: np.ndarray, sr: int, win_s: float = 0.05) -> float:
    m = _sliding_mean(np.mean(chans * chans, axis=0), int(win_s * sr), int(0.005 * sr))
    return 10 * math.log10(max(float(m.max()), 1e-20))


def krms_max_db(chans: np.ndarray, sr: int, win_s: float = 0.05) -> float:
    """Short-term loudness: K-weighted RMS over 50 ms windows (LUFS-ish, for short one-shots)."""
    k = np.stack([run_biquad(run_biquad(ch, K1), K2) for ch in chans])
    m = _sliding_mean(np.sum(k * k, axis=0), int(win_s * sr), int(0.005 * sr))
    return -0.691 + 10 * math.log10(max(float(m.max()), 1e-20))


def peak_db(chans: np.ndarray) -> float:
    return to_db(float(np.max(np.abs(chans))))


def measure(chans: np.ndarray, sr: int, mode: str) -> float:
    if mode == "peak_db":
        return peak_db(chans)
    if mode == "rms_db":
        return rms_max_db(chans, sr)
    if mode == "krms_db":
        return krms_max_db(chans, sr)
    if mode == "lufs":
        return loudness_m_max(chans, sr)
    raise RecipeError(f"unknown norm {mode!r}")


def spectrum(chans: np.ndarray, sr: int):
    mono = np.mean(chans, axis=0)
    # No analysis window: one-shots start and end at zero and loops are periodic, and a
    # whole-file window would erase every attack at t = 0.
    nfft = 1 << max(16, int(math.ceil(math.log2(max(len(mono), 2)))))
    p = np.abs(np.fft.rfft(mono, nfft)) ** 2
    f = np.fft.rfftfreq(nfft, 1.0 / sr)
    band = (f >= 20) & (f <= 20000)
    return f[band], p[band]


def timbre(chans: np.ndarray, sr: int) -> dict:
    f, p = spectrum(chans, sr)
    tot = float(p.sum()) or 1e-20
    env = np.sqrt(_sliding_mean(np.mean(chans * chans, axis=0), max(1, int(0.005 * sr)), max(1, int(0.001 * sr))))
    ipk = int(np.argmax(env))
    pk = float(env[ipk]) or 1e-12
    below = np.nonzero(env[ipk:] < pk * 0.1)[0]
    return {
        "dur_ms": 1000.0 * chans.shape[1] / sr,
        "peak_db": peak_db(chans),
        "lufs": loudness_m_max(chans, sr),
        "rms50_db": rms_max_db(chans, sr),
        "krms50": krms_max_db(chans, sr),
        "centroid": float((f * p).sum() / tot),
        "peak_hz": float(f[int(np.argmax(p))]),
        "attack_ms": ipk * 1.0,
        "t20_ms": float(below[0]) if len(below) else float("nan"),
        "crest_db": peak_db(chans) - rms_max_db(chans, sr, win_s=chans.shape[1] / sr),
    }


# --------------------------------------------------------------------------- finishing


LIMIT_LOOKAHEAD_S = 0.001
LIMIT_RELEASE_S = 0.04
LIMIT_MAX_GR_DB = 6.0      # more than this means the recipe's crest factor fights its target


def _sliding_min(x: np.ndarray, half: int, circular: bool) -> np.ndarray:
    out = x.copy()
    for k in range(1, half + 1):
        if circular:
            out = np.minimum(out, np.minimum(np.roll(x, k), np.roll(x, -k)))
        else:
            out[k:] = np.minimum(out[k:], x[:-k])
            out[:-k] = np.minimum(out[:-k], x[k:])
    return out


def limit(chans: np.ndarray, ceiling_db: float, sr: int, circular: bool) -> tuple[np.ndarray, float]:
    """Look-ahead peak limiter (linked channels). Returns the signal and the max gain reduction in dB.

    The required gain is min-filtered over +/-L, averaged over L (so it never exceeds the
    requirement at any sample and has a smooth attack), then released with a one-pole.
    """
    c = undb(ceiling_db)
    need = np.minimum(1.0, c / np.maximum(np.max(np.abs(chans), axis=0), 1e-12))
    if need.min() >= 1.0:
        return chans, 0.0
    L = max(1, int(LIMIT_LOOKAHEAD_S * sr))
    m = _sliding_min(need, L, circular)
    k = np.ones(L + 1) / (L + 1)
    if circular:
        kern = np.roll(np.pad(k, (0, len(m) - len(k))), -(L // 2))
        a = np.real(np.fft.ifft(np.fft.fft(m) * np.fft.fft(kern)))
    else:
        a = np.convolve(np.pad(m, (L // 2, L - L // 2), constant_values=1.0), k, mode="valid")[: len(m)]
    a = np.minimum(a, need)
    rel = 1.0 - math.exp(-1.0 / (LIMIT_RELEASE_S * sr))
    al = a.tolist()
    g = [1.0] * len(al)
    prev = 1.0
    for _ in range(2 if circular else 1):
        for i in range(len(al)):
            prev = min(al[i], prev + (1.0 - prev) * rel)
            g[i] = prev
    gain = np.asarray(g)
    return chans * gain, -to_db(float(gain.min()))


def finish(chans: np.ndarray, rec: dict, group: dict, sr: int, info: dict | None = None) -> np.ndarray:
    """Normalise to the target through the limiter, then edge fades (one-shots), then DC removal.

    Order matters: the limiter only lowers gain, the fades come after it so the 2 ms fade-in
    is exact, and the DC removal is shaped by the fades (zero at both ends) so it neither
    moves the first and last samples nor undoes the fade.
    """
    n = chans.shape[1]
    loop = bool(rec.get("loop"))
    g = np.ones(n)
    if not loop:
        fi = int(FADE_IN_S * sr)
        fo = int(float(rec.get("fade_out", FADE_OUT_S)) * sr)
        g[:fi] = 0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi)
        g[n - fo:] *= 0.5 + 0.5 * np.cos(np.pi * np.arange(1, fo + 1) / fo)
    dcw = np.ones(n) if loop else g * np.sin(np.pi * (np.arange(n) + 0.5) / n) ** 2

    def shape(x: np.ndarray) -> np.ndarray:
        x = x * g
        return x - (x.sum(axis=1, keepdims=True) / dcw.sum()) * dcw

    chans = chans - chans.mean(axis=1, keepdims=True) if loop else chans
    norm = rec.get("norm") or group.get("norm") or {"peak_db": -1.0}
    (mode, target), = norm.items()
    ceiling = float(rec.get("ceiling_db", group.get("ceiling_db", -1.0)))
    out, gr = chans, 0.0
    if mode == "gain_db":  # a fixed gain (derived recipes keep their source's level)
        out, gr = limit(chans * g * undb(float(target)), ceiling - 0.03, sr, loop)
        out = shape(out)
        pk = peak_db(out)
        if pk > ceiling - 0.01:
            out = out * undb(ceiling - 0.01 - pk)
        if info is not None:
            info["gr_db"] = gr
        return out
    gain_db = float(target) - measure(shape(chans), sr, mode)
    for _ in range(10):
        lim, gr = limit(chans * g * undb(gain_db), ceiling - 0.03, sr, loop)
        out = shape(lim)
        err = float(target) - measure(out, sr, mode)
        if abs(err) < 0.05:
            break
        gain_db += err
    pk = peak_db(out)
    if pk > ceiling - 0.01:  # DC removal can nudge a peak; scaling keeps fades and zero mean
        out = out * undb(ceiling - 0.01 - pk)
    if info is not None:
        info["gr_db"] = gr
    return out


# --------------------------------------------------------------------------- recipes I/O


def load_recipes(path: Path) -> dict:
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    if data.get("schema") != SCHEMA:
        raise RecipeError(f"{path}: schema must be {SCHEMA}")
    if data["format"] != {"rate": 48000, "bits": 16}:
        # 03 §2 fixes 48 kHz 16-bit, and the K-weighting coefficients below are the 48 kHz set.
        raise RecipeError(f"{path}: format must be 48000 Hz, 16-bit")
    groups = data["groups"]
    for rid, rec in data["recipes"].items():
        if not ID_RE.match(rid):
            raise RecipeError(f"bad recipe id {rid!r}")
        if rec.get("group") not in groups:
            raise RecipeError(f"{rid}: unknown group {rec.get('group')!r}")
        if "from" in rec:  # a derived recipe: another one-shot's variants through an extra chain
            src = data["recipes"].get(rec["from"])
            if src is None or src.get("loop") or "from" in src:
                raise RecipeError(f"{rid}: 'from' must name a one-shot recipe that is not derived")
            if rec.get("layers") or rec.get("loop") or "variants" in rec or "dur" in rec:
                raise RecipeError(f"{rid}: a derived recipe has no layers, loop, variants or dur")
            continue
        if not rec.get("layers"):
            raise RecipeError(f"{rid}: no layers")
        if "dur" not in rec:
            raise RecipeError(f"{rid}: no dur")
        for i, layer in enumerate(rec["layers"]):
            if "peak_db" in layer and "gain_db" in layer:
                raise RecipeError(f"{rid} layer {i}: use peak_db or gain_db, not both")
    return data


def variants_of(rec: dict, data: dict | None = None) -> int:
    if "from" in rec and data is not None:
        return variants_of(data["recipes"][rec["from"]])
    return int(rec.get("variants", 1 if rec.get("loop") else 3))


def file_name(rid: str, v: int) -> str:
    return f"{rid}_v{v:02d}.wav"


def render_variant(data: dict, rid: str, v: int, info: dict | None = None) -> np.ndarray:
    rec = data["recipes"][rid]
    group = data["groups"][rec["group"]]
    sr = int(data["format"]["rate"])
    nch = int(rec.get("channels", group.get("channels", 1)))
    if "from" in rec:
        # The source's own finished variant v (same file the game plays), with a tail of
        # silence for the extra chain to ring into, then this recipe's fx and finish.
        src = render_variant(data, rec["from"], v)
        tail = int(round(float(rec.get("tail", 0.0)) * sr))
        src = np.concatenate((src, np.zeros((src.shape[0], tail))), axis=1)
        key = [int(data.get("seed", 0)), crc(rid), v]
        out = []
        for ch in range(src.shape[0]):
            ctx = Ctx(sr, list(key), 1.0, None, ch, src.shape[0], False, data)
            out.append(apply_chain(src[ch], rec.get("fx", []), ctx, 0.0, key + [P_LFO, 999]))
        return finish(np.stack(out), rec, group, sr, info)
    loop_n = int(round(float(rec["dur"]) * sr)) if rec.get("loop") else None
    key = [int(data.get("seed", 0)), crc(rid), v]
    chans = []
    for ch in range(nch):
        ctx = Ctx(sr, list(key), 1.0, loop_n, ch, nch, bool(rec.get("decorrelate", False)), data)
        chans.append(render_mix(rid, ctx))
    n = min(len(c) for c in chans)
    mix = np.stack([c[:n] for c in chans])
    lead = int(round(float(rec.get("lead", 0.0)) * sr))  # silence so a transient clears the fade-in
    if lead and not rec.get("loop"):
        mix = np.concatenate((np.zeros((nch, lead)), mix), axis=1)
    return finish(mix, rec, group, sr, info)


def to_pcm16(chans: np.ndarray) -> np.ndarray:
    return np.clip(np.round(chans * 32767.0), -32767, 32767).astype("<i2")


def write_wav(path: Path, pcm: np.ndarray, sr: int, loop: bool) -> None:
    """16-bit PCM. Loops get a guard frame (a copy of frame 0) and a smpl chunk whose
    end is the guard's index: inclusive per the RIFF spec, and exactly the loop length
    in Godot, which reads the end as exclusive (checked on 4.7.2)."""
    nch, n = pcm.shape
    if loop:
        pcm = np.concatenate((pcm, pcm[:, :1]), axis=1)
    data = pcm.T.reshape(-1).astype("<i2").tobytes()
    fmt = struct.pack("<HHIIHH", 1, nch, sr, sr * nch * 2, nch * 2, 16)
    body = b"fmt " + struct.pack("<I", len(fmt)) + fmt
    body += b"data" + struct.pack("<I", len(data)) + data
    if loop:
        smpl = struct.pack("<9I", 0, 0, int(round(1e9 / sr)), 60, 0, 0, 0, 1, 0)
        smpl += struct.pack("<6I", 0, 0, 0, n, 0, 0)
        body += b"smpl" + struct.pack("<I", len(smpl)) + smpl
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_suffix(".wav.tmp")
    with open(tmp, "wb") as fh:
        fh.write(b"RIFF" + struct.pack("<I", 4 + len(body)) + b"WAVE" + body)
    os.replace(tmp, path)


def read_wav(path: Path) -> dict:
    raw = path.read_bytes()
    if raw[:4] != b"RIFF" or raw[8:12] != b"WAVE":
        raise RecipeError(f"{path}: not a RIFF/WAVE file")
    pos, info = 12, {"loop": None}
    while pos + 8 <= len(raw):
        cid, size = raw[pos:pos + 4], struct.unpack("<I", raw[pos + 4:pos + 8])[0]
        body = raw[pos + 8:pos + 8 + size]
        if cid == b"fmt ":
            info["format"], info["channels"], info["rate"], _, _, info["bits"] = struct.unpack("<HHIIHH", body[:16])
        elif cid == b"data":
            info["pcm"] = np.frombuffer(body, dtype="<i2")
        elif cid == b"smpl" and len(body) >= 60:
            info["loop"] = struct.unpack("<II", body[44:52])
        pos += 8 + size + (size & 1)
    nch = info["channels"]
    info["pcm"] = info["pcm"].reshape(-1, nch).T
    return info


def project_root(out: Path) -> Path | None:
    for d in [out.resolve(), *out.resolve().parents]:
        if (d / "project.godot").exists():
            return d
    return None


def res_path(out: Path, rel: str) -> str:
    root = project_root(out)
    if root is None:
        return rel
    return "res://" + (out.resolve() / rel).relative_to(root).as_posix()


def build_manifest(data: dict, out: Path) -> dict:
    sounds = {}
    sr = int(data["format"]["rate"])
    for rid, rec in data["recipes"].items():
        group = data["groups"][rec["group"]]
        files, lengths, loop_frames = [], [], []
        for v in range(1, variants_of(rec, data) + 1):
            rel = f"{group['dir']}/{file_name(rid, v)}"
            p = out / rel
            if not p.exists():
                raise RecipeError(f"manifest: missing {p} (render it first)")
            w = read_wav(p)
            frames = w["pcm"].shape[1]
            if w["loop"] is not None:
                loop_frames.append(int(w["loop"][1]))
            files.append(res_path(out, rel))
            lengths.append(round(frames / sr, 6))
        entry = {
            "group": rec["group"],
            "bus": rec.get("bus", group["bus"]),
            "loop": bool(rec.get("loop")),
            "channels": int(rec.get("channels", group.get("channels", 1))),
            "files": files,
            "length_s": lengths,
        }
        if rec.get("loop"):
            entry["loop_frames"] = loop_frames
        if rec.get("runtime"):
            entry["runtime"] = rec["runtime"]
        sounds[rid] = entry
    return {"schema": SCHEMA, "generator": "tools/audio/synth.py", "rate": sr,
            "bits": int(data["format"]["bits"]), "sounds": sounds}


# --------------------------------------------------------------------------- verify

SEAM_STEP_RATIO = 1.5   # wrap step <= 1.5 x the 99.9th percentile step inside the loop
SEAM_RMS_DB = 1.0       # seam level jump <= the largest 10 ms jump inside the loop + 1 dB
NORM_TOL_DB = 0.5
DC_MAX = 1e-3           # -60 dBFS
LSB_TOL = 2


def check_audio(rid: str, v: int, chans: np.ndarray, rec: dict, group: dict, sr: int) -> list[str]:
    errs = []
    tag = f"{rid} v{v:02d}"
    n = chans.shape[1]
    dur = n / sr
    loop = bool(rec.get("loop"))
    # duration
    if "dur" in rec:  # derived recipes take their source's length plus `tail`
        want = float(rec["dur"])
        lead = 0.0 if loop else float(rec.get("lead", 0.0))
        j = 0.0 if loop else float(rec.get("jitter", {}).get("dur", 0.0))
        if not (want * (1 - j) + lead - 0.001 <= dur <= want * (1 + j) + lead + 0.001):
            errs.append(f"{tag}: duration {dur:.4f}s outside {want}s +/- {j:.0%}")
    lo, hi = group.get("dur_range", [0.0, 60.0])
    if not (lo <= dur <= hi):
        errs.append(f"{tag}: duration {dur:.3f}s outside group range {lo}..{hi}s")
    # level
    ceiling = float(rec.get("ceiling_db", group.get("ceiling_db", -1.0)))
    pk = peak_db(chans)
    if pk > ceiling + 0.05:
        errs.append(f"{tag}: peak {pk:.2f} dBFS above ceiling {ceiling}")
    pcm = to_pcm16(chans)
    if np.any(np.abs(pcm.astype(np.int32)) >= 32767):
        errs.append(f"{tag}: clipped samples")
    norm = rec.get("norm") or group.get("norm") or {"peak_db": -1.0}
    (mode, target), = norm.items()
    got = float(target) if mode == "gain_db" else measure(chans, sr, mode)
    if abs(got - float(target)) > NORM_TOL_DB:
        errs.append(f"{tag}: {mode} {got:.2f} misses target {target} (ceiling-limited? lower the target)")
    dc = float(np.max(np.abs(chans.mean(axis=1))))
    if dc > DC_MAX:
        errs.append(f"{tag}: DC offset {dc:.5f}")
    if not loop:
        fi = int(FADE_IN_S * sr)
        if np.max(np.abs(chans[:, 0])) > 1e-4:
            errs.append(f"{tag}: does not start at zero")
        ramp = 0.5 - 0.5 * np.cos(np.pi * np.arange(fi) / fi)
        if np.any(np.abs(chans[:, :fi]) > ramp + 1e-4):
            errs.append(f"{tag}: no 2 ms fade-in")
        if np.max(np.abs(chans[:, -1])) > 1e-3:
            errs.append(f"{tag}: does not end at zero")
    else:
        for c, x in enumerate(chans):
            steps = np.abs(np.diff(x))
            ref = float(np.percentile(steps, 99.9)) + 1e-4
            seam = abs(float(x[0] - x[-1]))
            if seam > SEAM_STEP_RATIO * ref:
                errs.append(f"{tag} ch{c}: loop seam step {seam:.4f} > {SEAM_STEP_RATIO} x {ref:.4f}")
            # 10 ms RMS windows aligned to the seam; the jump across the seam (last window to
            # first) must be no larger than the largest jump between any other two windows.
            k = int(0.01 * sr)
            m = n // k
            lv = np.array([to_db(math.sqrt(float(np.mean(x[i * k:(i + 1) * k] ** 2)) + 1e-20))
                           for i in range(m)])
            inner = float(np.max(np.abs(np.diff(lv)))) if m > 2 else 0.0
            seam_jump = abs(float(lv[0] - lv[-1]))
            if seam_jump > inner + SEAM_RMS_DB:
                errs.append(f"{tag} ch{c}: loop seam level jump {seam_jump:.1f} dB > "
                            f"{inner:.1f} dB inside the loop + {SEAM_RMS_DB}")
    # timbre expectations declared by the recipe
    exp = rec.get("expect", {})
    if exp:
        t = timbre(chans, sr)
        for k2, (a, b) in exp.items():
            if not (a <= t[k2] <= b):
                errs.append(f"{tag}: {k2} {t[k2]:.1f} outside expected {a}..{b}")
    return errs


def verify(data: dict, out: Path, ids: list[str]) -> list[str]:
    errs = []
    sr = int(data["format"]["rate"])
    expected_files = set()
    for rid, rec in data["recipes"].items():
        group = data["groups"][rec["group"]]
        for v in range(1, variants_of(rec, data) + 1):
            expected_files.add((out / group["dir"] / file_name(rid, v)).resolve())
    for rid in ids:
        rec = data["recipes"][rid]
        group = data["groups"][rec["group"]]
        nv = variants_of(rec, data)
        lo, hi = group.get("variants_loop" if rec.get("loop") else "variants", [1, 99])
        if not (lo <= nv <= hi):
            errs.append(f"{rid}: {nv} variants outside {lo}..{hi} (03 §2)")
        nch = int(rec.get("channels", group.get("channels", 1)))
        rendered = []
        for v in range(1, nv + 1):
            info: dict = {}
            try:
                chans = render_variant(data, rid, v, info)
            except Exception as e:  # noqa: BLE001 - report and keep checking others
                errs.append(f"{rid} v{v:02d}: render failed: {e}")
                continue
            rendered.append(chans)
            errs += check_audio(rid, v, chans, rec, group, sr)
            if info.get("gr_db", 0.0) > LIMIT_MAX_GR_DB:
                errs.append(f"{rid} v{v:02d}: limiter took {info['gr_db']:.1f} dB to reach the target "
                            f"(max {LIMIT_MAX_GR_DB}); lower the target or the crest factor")
            p = out / group["dir"] / file_name(rid, v)
            if not p.exists():
                errs.append(f"{rid} v{v:02d}: missing {p}")
                continue
            w = read_wav(p)
            if (w["format"], w["rate"], w["bits"], w["channels"]) != (1, sr, 16, nch):
                errs.append(f"{p}: format {w['format']}/{w['rate']}/{w['bits']}/{w['channels']}ch, "
                            f"want PCM/{sr}/16/{nch}ch")
                continue
            pcm = w["pcm"]
            if rec.get("loop"):
                n = pcm.shape[1] - 1
                if w["loop"] != (0, n) or not np.array_equal(pcm[:, -1], pcm[:, 0]):
                    errs.append(f"{p}: loop chunk/guard frame wrong ({w['loop']})")
                pcm = pcm[:, :n]
            elif w["loop"] is not None:
                errs.append(f"{p}: one-shot has a loop chunk")
            want = to_pcm16(chans)
            if pcm.shape != want.shape or int(np.max(np.abs(pcm.astype(np.int32) - want))) > LSB_TOL:
                errs.append(f"{p}: stale (differs from the recipe; re-render)")
        for a in range(len(rendered)):
            for b in range(a + 1, len(rendered)):
                x, y = rendered[a], rendered[b]
                m = min(x.shape[1], y.shape[1])
                d = float(np.sqrt(np.mean((x[:, :m] - y[:, :m]) ** 2)) / (np.sqrt(np.mean(x ** 2)) + 1e-12))
                if d < 0.05:
                    errs.append(f"{rid}: variants {a + 1} and {b + 1} are nearly identical ({d:.3f})")
    # stray files and manifest
    for gname, group in data["groups"].items():
        d = out / group["dir"]
        if d.exists():
            for f in sorted(d.glob("*.wav")):
                if f.resolve() not in expected_files:
                    errs.append(f"{f}: not produced by any recipe (stale)")
    mp = out / "manifest.json"
    if not mp.exists():
        errs.append(f"{mp}: missing")
    else:
        try:
            have = json.loads(mp.read_text(encoding="utf-8"))
            want = build_manifest(data, out)
            if have != want:
                errs.append(f"{mp}: out of date (re-render)")
        except Exception as e:  # noqa: BLE001
            errs.append(f"{mp}: {e}")
    return errs


# --------------------------------------------------------------------------- main


def remove_stale(data: dict, out: Path) -> None:
    keep = set()
    for rid, rec in data["recipes"].items():
        group = data["groups"][rec["group"]]
        for v in range(1, variants_of(rec, data) + 1):
            keep.add((out / group["dir"] / file_name(rid, v)).resolve())
    for group in data["groups"].values():
        d = out / group["dir"]
        if not d.exists():
            continue
        for f in d.glob("*.wav"):
            if f.resolve() not in keep:
                f.unlink()
                imp = f.with_name(f.name + ".import")
                if imp.exists():
                    imp.unlink()


def main(argv: list[str] | None = None) -> int:
    here = Path(__file__).resolve().parent
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--out", required=True, type=Path, help="output folder (game/assets/audio)")
    ap.add_argument("--recipes", type=Path, default=here / "recipes.json")
    ap.add_argument("--only", action="append", default=[], help="recipe id (repeatable, or comma list)")
    ap.add_argument("--verify", action="store_true", help="render in memory and check files; write nothing")
    ap.add_argument("--report", action="store_true", help="print timbre numbers per recipe (variant 1)")
    args = ap.parse_args(argv)

    try:
        data = load_recipes(args.recipes)
    except (RecipeError, OSError, json.JSONDecodeError) as e:
        print(f"synth: {e}", file=sys.stderr)
        return 2
    ids = [i for s in args.only for i in s.split(",") if i] or list(data["recipes"])
    unknown = [i for i in ids if i not in data["recipes"]]
    if unknown:
        print(f"synth: unknown recipe ids: {', '.join(unknown)}", file=sys.stderr)
        return 2
    sr = int(data["format"]["rate"])
    out: Path = args.out

    if args.report:
        cols = ("dur_ms", "peak_db", "lufs", "rms50_db", "krms50", "centroid", "peak_hz", "attack_ms", "t20_ms", "crest_db",
                "gr_db")
        print(f"{'id':26s}" + "".join(f"{c:>10s}" for c in cols))
        for rid in ids:
            info: dict = {}
            t = timbre(render_variant(data, rid, 1, info), sr)
            t["gr_db"] = info.get("gr_db", 0.0)
            print(f"{rid:26s}" + "".join(f"{t[c]:10.1f}" for c in cols))
        return 0

    if args.verify:
        errs = verify(data, out, ids)
        for e in errs:
            print(f"FAIL {e}")
        nfiles = sum(variants_of(data["recipes"][i], data) for i in ids)
        print(f"synth --verify: {len(ids)} recipes, {nfiles} files, {len(errs)} problems")
        return 1 if errs else 0

    for rid in ids:
        rec = data["recipes"][rid]
        group = data["groups"][rec["group"]]
        for v in range(1, variants_of(rec, data) + 1):
            chans = render_variant(data, rid, v)
            write_wav(out / group["dir"] / file_name(rid, v), to_pcm16(chans), sr, bool(rec.get("loop")))
        print(f"rendered {rid} x{variants_of(rec, data)}")
    if not args.only:
        remove_stale(data, out)
    manifest = build_manifest(data, out)
    (out / "manifest.json").write_text(json.dumps(manifest, indent=1) + "\n", encoding="utf-8")
    print(f"wrote {out / 'manifest.json'} ({len(manifest['sounds'])} sounds)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
