#!/usr/bin/env python3
"""Checks the screenshot tour (docs/design/02 section 13, 14 section 9) against T1, T3 and T4,
and prints the by-eye record of T5 and T6 (docs/qa/visual_targets_by_eye.md) beside them.

Usage: tools/ci/tour_check.py [tour_dir]          (default build/tour; reads manifest.json)
       tools/ci/tour_check.py --selftest          (PNG decoder against files it writes itself)
Exit code 0 when no check fails, 1 otherwise. numpy is required; Pillow is used when it is
installed, otherwise a small zlib PNG decoder reads the frames (set TOUR_CHECK_NO_PIL=1 to
force it).

T1  Readability of the floor. At Coherence 100, flashlight off, every floor reading the
    tour took (2..12 m ahead, 2..6 m in Server and Substrate) is above 8% luminance. In the
    dark strata (manifest `flashlight`: Server, Substrate) the frames are taken with the
    flashlight on and T3's dark threshold does not apply (02 section 2 ruling, 2026-10-08).
Extra entries (manifest `extra`: the Cycle 2 sample) take T1 and T3 only. Cycle 2 frames
    are taken with the flashlight on (manifest `flashlight`; CHANGELOG 2026-10-08 Cycle 2 T1
    ruling: a quarter of its fixtures are dead on purpose) and their T1 binds; an extra entry
    shot without the flashlight reports T1 as INFO.
Monochrome strata (manifest `monochrome`: the Substrate, lines on black) order T4 by two
    measures built for lines on black (M3.2; saturation, whole-frame grain and the mean
    vignette do not order them: CA paints colour onto white lines, the lines' own edges
    swamp the grain residual, and black corners hold no vignette): the film grain in the
    flat black away from every line (rises at every step) and the share of line pixels in
    the border against the centre that stay bright (falls as the vignette and CA eat the
    border lines: it never moves back by more than its tolerance and falls by
    MONO_LINES_TOTAL from Coherence 100 to 10; at 60 the vignette has barely begun).
T3  No flat black, no flat white. At Coherence 100 the darkest 1% of a frame is above 2%
    luminance (fog in the shadow) and bright clipped pixels stay under 2% of the frame
    (the brightest fixture blooms but is not a white slab).
T4  Coherence is visible without the HUD. For each pose the four frames (100, 60, 30, 10)
    must be orderable by measurement: between consecutive frames at least two of saturation
    (falls), grain (rises) and vignette (corner-to-centre brightness falls) move the right
    way, and none moves the wrong way by more than its tolerance. In a dark frame (the
    Coherence 100 border under T4_DARK_BORDER luma: the Garage, the Server) the post's
    luminance grain, clamped at black, lifts the corners as its amount rises (its mean
    under the clamp grows wherever the image is darker than the grain amplitude), against
    the vignette: there a vignette that moves back is not held against the frame (it still
    counts when it moves the right way), so two of the three must still move (M3.2).
Soft wall (02 section 5). The band on the soft wall changes the wall between soft_wall_c100
    and soft_wall_c100_t1 (1 s of world time apart, grain held) by SOFT_MIN_DELTA..SOFT_MAX_DELTA
    luma, at least SOFT_CONTROL_RATIO times the change elsewhere in the frame.
Thresholds are constants below; they restate 02, they are not tuned to the frames.
"""
import json
import os
import struct
import sys
import zlib

import numpy as np

T1_MIN_LUMA = 0.08
T3_MIN_P01 = 0.02
T3_MAX_CLIPPED_FRACTION = 0.02
# T4 per-step minimum movement, and the largest tolerated move in the wrong direction.
T4_SAT_STEP = 0.01
T4_NOISE_STEP = 0.0005
T4_VIG_STEP = 0.01
T4_WRONG_WAY = 0.5   # fraction of the step above which a reversed feature counts as wrong
T4_DARK_BORDER = 0.18  # 02 section 4: the grain amplitude at full drain; below it the clamp biases the corners
# 02 section 5 soft walls: the band's temporal contrast between two frames 1 s apart (half a
# 0.5 Hz period), as mean |delta luma| of 8 px block means on the wall. Below the minimum the
# shimmer is not there to read; above the maximum it is garish (it must stay "faint").
SOFT_BLOCK_PX = 8
SOFT_MIN_DELTA = 0.008
SOFT_MAX_DELTA = 0.05
SOFT_CONTROL_RATIO = 3
# Monochrome T4 (the Substrate): a line pixel is brighter than MONO_LINE_LUMA; flat black is
# farther than MONO_LINE_CLEAR px from any line pixel; per-step minimum movements.
MONO_LINE_LUMA = 0.25
MONO_LINE_CLEAR = 3
MONO_GRAIN_STEP = 0.002
MONO_LINES_STEP = 0.01
MONO_LINES_TOTAL = 0.03


# ---------------------------------------------------------------- PNG reading

def _paeth(a, b, c):
    p = a + b - c
    pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
    if pa <= pb and pa <= pc:
        return a
    return b if pb <= pc else c


def decode_png(path):
    """Returns an (h, w, 3) float32 array in 0..1 (alpha dropped). Uses Pillow when present."""
    if not os.environ.get("TOUR_CHECK_NO_PIL"):
        try:
            from PIL import Image
            return np.asarray(Image.open(path).convert("RGB"), dtype=np.float32) / 255.0
        except ImportError:
            pass
    return _decode_png_zlib(open(path, "rb").read())


def _decode_png_zlib(data):
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos = 8
    idat = b""
    width = height = depth = ctype = interlace = 0
    palette = None
    while pos < len(data):
        (length,) = struct.unpack(">I", data[pos:pos + 4])
        kind = data[pos + 4:pos + 8]
        body = data[pos + 8:pos + 8 + length]
        pos += 12 + length
        if kind == b"IHDR":
            width, height, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
        elif kind == b"PLTE":
            palette = np.frombuffer(body, dtype=np.uint8).reshape(-1, 3)
        elif kind == b"IDAT":
            idat += body
        elif kind == b"IEND":
            break
    if depth != 8 or interlace != 0 or ctype not in (0, 2, 3, 4, 6):
        raise ValueError("unsupported PNG (depth %d, type %d, interlace %d)" % (depth, ctype, interlace))
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[ctype]
    stride = width * channels
    raw = zlib.decompress(idat)
    out = np.zeros((height, stride), dtype=np.uint8)
    prev = bytearray(stride)
    p = 0
    for y in range(height):
        f = raw[p]
        line = bytearray(raw[p + 1:p + 1 + stride])
        p += 1 + stride
        if f == 1:
            for i in range(channels, stride):
                line[i] = (line[i] + line[i - channels]) & 255
        elif f == 2:
            prev_arr = np.frombuffer(bytes(prev), dtype=np.uint8)
            line = bytearray(((np.frombuffer(bytes(line), dtype=np.uint8).astype(np.uint16) + prev_arr) & 255).astype(np.uint8).tobytes())
        elif f == 3:
            for i in range(stride):
                left = line[i - channels] if i >= channels else 0
                line[i] = (line[i] + ((left + prev[i]) >> 1)) & 255
        elif f == 4:
            for i in range(stride):
                a = line[i - channels] if i >= channels else 0
                c = prev[i - channels] if i >= channels else 0
                line[i] = (line[i] + _paeth(a, prev[i], c)) & 255
        elif f != 0:
            raise ValueError("bad PNG filter %d" % f)
        out[y] = np.frombuffer(bytes(line), dtype=np.uint8)
        prev = line
    img = out.reshape(height, width, channels)
    if ctype == 0:
        rgb = np.repeat(img, 3, axis=2)
    elif ctype == 4:
        rgb = np.repeat(img[:, :, :1], 3, axis=2)
    elif ctype == 3:
        rgb = palette[img[:, :, 0]]
    else:
        rgb = img[:, :, :3]
    return rgb.astype(np.float32) / 255.0


# ---------------------------------------------------------------- measures

def luma(img):
    return 0.2126 * img[:, :, 0] + 0.7152 * img[:, :, 1] + 0.0722 * img[:, :, 2]


def saturation(img):
    mx = img.max(axis=2)
    mn = img.min(axis=2)
    keep = mx > 0.05
    if not keep.any():
        return 0.0
    return float(((mx - mn)[keep] / mx[keep]).mean())


def grain(img):
    """Std of the residual after a 3x3 box blur of the luma: film grain and aliasing noise."""
    y = luma(img)
    pad = np.pad(y, 1, mode="edge")
    blur = sum(pad[dy:dy + y.shape[0], dx:dx + y.shape[1]] for dy in range(3) for dx in range(3)) / 9.0
    return float((y - blur).std())


def vignette(img):
    """Mean luma of the outer 10% border over the mean luma of the middle half (falls with Coherence)."""
    y = luma(img)
    h, w = y.shape
    bh, bw = max(h // 10, 1), max(w // 10, 1)
    border = np.concatenate([y[:bh].ravel(), y[-bh:].ravel(), y[:, :bw].ravel(), y[:, -bw:].ravel()])
    centre = y[h // 4:3 * h // 4, w // 4:3 * w // 4]
    return float(border.mean() / max(centre.mean(), 1e-6))


def clipped_fraction(img):
    return float((img.min(axis=2) >= 0.995).mean())


# ---------------------------------------------------------------- checks

def check_t1(entries, limit):
    """(status, detail) for T1 over the Coherence 100 pose frames of one stratum."""
    reach = 0.0
    worst = None
    for name, e in entries.items():
        if e.get("kind") != "pose" or e.get("coherence") != 100:
            continue
        for key, v in e.get("floor_luma", {}).items():
            d = float(key.rstrip("m"))
            if d > limit:
                continue
            reach = max(reach, d)
            if worst is None or v < worst[0]:
                worst = (v, d, name)
    if worst is None:
        return "NOCOV", "no floor reading"
    if worst[0] <= T1_MIN_LUMA:
        return "FAIL", "%.3f at %d m in %s" % worst
    detail = "min %.3f (%d m, %s), read out to %d m" % (worst[0], worst[1], worst[2], reach)
    if reach < limit:
        return "PASS", detail + " (limit %d m not reached by any pose)" % limit
    return "PASS", detail


def check_t3(entry, img):
    p01 = entry["luma_p01"]
    frac = clipped_fraction(img)
    dark = "PASS" if p01 >= T3_MIN_P01 else "FAIL"
    white = "PASS" if frac <= T3_MAX_CLIPPED_FRACTION else "FAIL"
    return dark, p01, white, frac


def border_luma(img):
    y = luma(img)
    h, w = y.shape
    bh, bw = max(h // 10, 1), max(w // 10, 1)
    return float(np.concatenate([y[:bh].ravel(), y[-bh:].ravel(), y[:, :bw].ravel(), y[:, -bw:].ravel()]).mean())


def features(img):
    return {"sat": saturation(img), "grain": grain(img), "vig": vignette(img), "border": border_luma(img)}


def check_t4(feats):
    """feats: list of feature dicts at Coherence 100, 60, 30, 10. Returns (status, detail)."""
    worst = "PASS"
    notes = []
    dark = feats[0].get("border", 1.0) < T4_DARK_BORDER
    for i in range(len(feats) - 1):
        a, b = feats[i], feats[i + 1]
        moves = {
            "sat": (a["sat"] - b["sat"], T4_SAT_STEP),
            "grain": (b["grain"] - a["grain"], T4_NOISE_STEP),
            "vig": (a["vig"] - b["vig"], T4_VIG_STEP),
        }
        good = [k for k, (d, step) in moves.items() if d >= step]
        wrong = [k for k, (d, step) in moves.items() if d <= -step * T4_WRONG_WAY and not (dark and k == "vig")]
        if len(good) < 2 or wrong:
            worst = "FAIL"
            notes.append("step %d: good=%s wrong=%s" % (i + 1, ",".join(good) or "-", ",".join(wrong) or "-"))
    if notes:
        return worst, "; ".join(notes)
    return worst, "ordered (dark frame: a vignette moving back is not held against it)" if dark else "sat/grain/vig ordered"


def _dilate(mask, r):
    out = mask.copy()
    h, w = mask.shape
    for dy in range(-r, r + 1):
        for dx in range(-r, r + 1):
            shifted = np.zeros_like(mask)
            shifted[max(-dy, 0):h + min(-dy, 0), max(-dx, 0):w + min(-dx, 0)] = \
                mask[max(dy, 0):h + min(dy, 0), max(dx, 0):w + min(dx, 0)]
            out |= shifted
    return out


def mono_features(img):
    """Lines on black: grain = std of the 3x3 residual over flat black (away from lines);
    lines = border line pixels over centre line pixels (the border is the outer 10%, the centre
    the middle half, as for `vignette`): the vignette and CA dim the border lines first."""
    y = luma(img)
    bright = y > MONO_LINE_LUMA
    flat = ~_dilate(bright, MONO_LINE_CLEAR)
    pad = np.pad(y, 1, mode="edge")
    blur = sum(pad[dy:dy + y.shape[0], dx:dx + y.shape[1]] for dy in range(3) for dx in range(3)) / 9.0
    res = (y - blur)[flat]
    h, w = y.shape
    bh, bw = max(h // 10, 1), max(w // 10, 1)
    border = np.zeros_like(bright)
    border[:bh] = True
    border[-bh:] = True
    border[:, :bw] = True
    border[:, -bw:] = True
    centre = np.zeros_like(bright)
    centre[h // 4:3 * h // 4, w // 4:3 * w // 4] = True
    n_centre = int((bright & centre).sum())
    return {"grain": float(res.std()) if res.size else 0.0,
            "lines": float((bright & border).sum()) / max(n_centre, 1)}


def check_t4_mono(feats):
    """feats: mono_features at Coherence 100, 60, 30, 10: grain rises at every step; the border
    lines never move back by more than half a step and fall by MONO_LINES_TOTAL overall."""
    notes = []
    for i in range(len(feats) - 1):
        a, b = feats[i], feats[i + 1]
        bad = []
        if b["grain"] - a["grain"] < MONO_GRAIN_STEP:
            bad.append("grain")
        if b["lines"] - a["lines"] > MONO_LINES_STEP * T4_WRONG_WAY:
            bad.append("lines back")
        if bad:
            notes.append("step %d: %s" % (i + 1, ",".join(bad)))
    if feats[0]["lines"] - feats[-1]["lines"] < MONO_LINES_TOTAL:
        notes.append("border lines fall %.3f (< %.2f)" % (feats[0]["lines"] - feats[-1]["lines"], MONO_LINES_TOTAL))
    return ("FAIL" if notes else "PASS"), ("; ".join(notes) if notes else "flat grain/border lines ordered")


def block_luma(img, block=SOFT_BLOCK_PX):
    """Luma averaged over block x block tiles (kills grain and TAA speckle)."""
    y = luma(img)
    h, w = (y.shape[0] // block) * block, (y.shape[1] // block) * block
    return y[:h, :w].reshape(h // block, block, w // block, block).mean(axis=(1, 3))


def soft_contrast(img_a, img_b, rect, block=SOFT_BLOCK_PX):
    """(soft, control): mean |delta luma| of the block means inside the soft wall's screen rect and
    outside it, between two frames SOFT_INTERVAL apart."""
    d = np.abs(block_luma(img_a, block) - block_luma(img_b, block))
    x0, y0, x1, y1 = [int(v) // block for v in rect]
    mask = np.zeros(d.shape, dtype=bool)
    mask[y0:max(y1, y0 + 1), x0:max(x1, x0 + 1)] = True
    soft = float(d[mask].mean()) if mask.any() else 0.0
    control = float(d[~mask].mean()) if (~mask).any() else 0.0
    return soft, control


def check_soft(img_a, img_b, rect):
    """02 section 5: the soft wall's band must read as a shimmer (a temporal change of at least
    SOFT_MIN_DELTA luma on the wall, SOFT_CONTROL_RATIO times the rest of the frame) without
    being garish (at most SOFT_MAX_DELTA)."""
    if len(rect) != 4 or rect[2] <= rect[0] or rect[3] <= rect[1]:
        return "NOCOV", "soft wall not on screen"
    soft, control = soft_contrast(img_a, img_b, rect)
    ok = soft >= SOFT_MIN_DELTA and soft <= SOFT_MAX_DELTA and soft >= SOFT_CONTROL_RATIO * control
    detail = "wall %.4f vs rest %.4f luma over 1 s (want %.3f..%.3f, >= %dx rest)" % (
        soft, control, SOFT_MIN_DELTA, SOFT_MAX_DELTA, SOFT_CONTROL_RATIO)
    return ("PASS" if ok else "FAIL"), detail


# T5 and T6 have no measurement: they are judged by eye from the tour's corridor frames (T5)
# and the error arena's 15 m frames (T6), and recorded in BY_EYE (M3 review S4, R20). The
# record is printed beside the measured targets: MANUAL for a recorded pass, FAIL for a
# recorded failure, OPEN where the row says open or nothing is recorded (OPEN does not fail).
BY_EYE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "qa", "visual_targets_by_eye.md")
T6_ERRORS = ("static", "still", "flicker", "echo", "null")


def read_by_eye(path=BY_EYE):
    """Rows of the record's table: {(target, subject): (result, frame, note)}."""
    out = {}
    if not os.path.exists(path):
        return out
    for line in open(path, encoding="utf-8"):
        cells = [c.strip() for c in line.strip().strip("|").split("|")]
        if len(cells) < 5 or cells[0] not in ("T5", "T6"):
            continue
        out[(cells[0], cells[1])] = (cells[2], cells[3], cells[4])
    return out


def by_eye_rows(strata, path=BY_EYE):
    record = read_by_eye(path)
    rows = []
    subjects = [("T5", s) for s in strata if s in ("halls", "pools", "garage", "offices", "server", "substrate")]
    subjects += [("T6", e) for e in T6_ERRORS]
    for target, subject in subjects:
        if (target, subject) not in record:
            rows.append((subject, target + " by eye", "OPEN", "not recorded in docs/qa/visual_targets_by_eye.md"))
            continue
        result, frame, note = record[(target, subject)]
        key = result.lower()
        status = "FAIL" if key.startswith("fail") else ("OPEN" if key.startswith("open") else "MANUAL")
        rows.append((subject, target + " by eye", status, "%s: %s (%s)" % (result, note, frame)))
    return rows


def run(tour_dir):
    path = os.path.join(tour_dir, "manifest.json")
    if not os.path.exists(path):
        print("tour_check: no manifest at %s (run tools/ci/render.sh --path game -- --tour %s)" % (path, tour_dir))
        return 1
    manifest = json.load(open(path))
    rows = []
    failed = False
    steps = manifest.get("coherence_steps", [100, 60, 30, 10])
    for stratum, sdata in manifest["strata"].items():
        entries = sdata["shots"]
        status, detail = check_t1(entries, sdata["t1_limit_m"])
        if sdata.get("extra") and not sdata.get("flashlight") and status == "FAIL":
            status = "INFO"
        rows.append((stratum, "T1 floor", status, detail))
        failed |= status == "FAIL"
        imgs = {}
        for name, e in entries.items():
            if e.get("kind") == "pose" and e["coherence"] == 100:
                imgs[name] = decode_png(os.path.join(tour_dir, e["file"]))
        # The dark strata waive T3's dark threshold (the player brings the light); Cycle 2 keeps
        # it (its live fixtures and fog still light the shadows).
        lit_by_player = bool(sdata.get("flashlight", False)) and not sdata.get("extra")
        for name, e in sorted(entries.items()):
            if name not in imgs:
                continue
            dark, p01, white, frac = check_t3(e, imgs[name])
            if lit_by_player:
                dark = "INFO"
            rows.append((stratum, "T3 dark  " + name, dark, "p01 %.3f (>= %.2f)" % (p01, T3_MIN_P01)))
            rows.append((stratum, "T3 white " + name, white, "clipped %.2f%% (<= %.0f%%)" % (frac * 100, T3_MAX_CLIPPED_FRACTION * 100)))
            failed |= dark == "FAIL" or white == "FAIL"
        poses = sorted({e["pose"] for e in entries.values() if e.get("kind") == "pose" and e["coherence"] != 100})
        for pose in poses:
            mono = bool(sdata.get("monochrome"))
            feats = []
            for c in steps:
                key = "%s_c%03d" % (pose, int(c))
                if key not in entries:
                    break
                img = decode_png(os.path.join(tour_dir, entries[key]["file"]))
                feats.append(mono_features(img) if mono else features(img))
            if len(feats) == len(steps):
                if mono:
                    status, detail = check_t4_mono(feats)
                    shown = "[grain/lines " + " ".join("%.4f/%.3f" % (f["grain"], f["lines"]) for f in feats) + "]"
                else:
                    status, detail = check_t4(feats)
                    shown = "[sat/grain/vig " + " ".join("%.2f/%.4f/%.2f" % (f["sat"], f["grain"], f["vig"]) for f in feats) + "]"
                rows.append((stratum, "T4 order " + pose, status, "%s  %s" % (detail, shown)))
                failed |= status == "FAIL"
        if sdata.get("extra"):
            continue
        if "soft_wall_c100" in entries and "soft_wall_c100_t1" in entries:
            a, b = entries["soft_wall_c100"], entries["soft_wall_c100_t1"]
            status, detail = check_soft(decode_png(os.path.join(tour_dir, a["file"])),
                                        decode_png(os.path.join(tour_dir, b["file"])), a.get("soft_rect", []))
            rows.append((stratum, "soft wall shimmer", status, detail))
            failed |= status == "FAIL"
        else:
            rows.append((stratum, "soft wall shimmer", "NOCOV", "no soft wall frames (level has none?)"))
        for name in ("noclip_commit", "null_8m"):
            rows.append((stratum, "frame " + name, "PASS" if name in entries else "MISSING",
                         entries[name]["file"] if name in entries else "not captured"))
            failed |= name not in entries
    for row in by_eye_rows(list(manifest["strata"].keys())):
        rows.append(row)
        failed |= row[2] == "FAIL"
    width = max(len(r[1]) for r in rows)
    print("%-10s %-*s %-6s %s" % ("stratum", width, "check", "result", "detail"))
    for stratum, check, status, detail in rows:
        print("%-10s %-*s %-6s %s" % (stratum, width, check, status, detail))
    print("tour_check: %s (%d checks)" % ("FAIL" if failed else "ok", len(rows)))
    return 1 if failed else 0


# ---------------------------------------------------------------- self test

def _encode_png(img, filters):
    """Encodes an (h, w, 4) uint8 array with the given PNG filter per row (0..4), for the self test."""
    h, w, c = img.shape
    stride = w * c
    rows = [bytes(img[y].reshape(-1)) for y in range(h)]
    out = bytearray()
    prev = bytes(stride)
    for y in range(h):
        f = filters[y % len(filters)]
        cur = rows[y]
        line = bytearray(stride)
        for i in range(stride):
            a = cur[i - c] if i >= c else 0
            b = prev[i]
            cc = prev[i - c] if i >= c else 0
            if f == 0:
                pred = 0
            elif f == 1:
                pred = a
            elif f == 2:
                pred = b
            elif f == 3:
                pred = (a + b) >> 1
            else:
                pred = _paeth(a, b, cc)
            line[i] = (cur[i] - pred) & 255
        out.append(f)
        out += line
        prev = cur
    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
            + chunk(b"IDAT", zlib.compress(bytes(out))) + chunk(b"IEND", b""))


def selftest():
    rng = np.random.default_rng(3)
    img = rng.integers(0, 256, size=(12, 17, 4), dtype=np.uint8)
    data = _encode_png(img, [0, 1, 2, 3, 4])
    got = _decode_png_zlib(data)
    want = img[:, :, :3].astype(np.float32) / 255.0
    ok = np.allclose(got, want)
    # T4 ordering: a synthetic ladder passes, a flat one fails.
    ladder = [{"sat": 1.0, "grain": 0.002, "vig": 0.9}, {"sat": 0.9, "grain": 0.004, "vig": 0.8},
              {"sat": 0.5, "grain": 0.008, "vig": 0.6}, {"sat": 0.1, "grain": 0.012, "vig": 0.4}]
    flat = [dict(ladder[0]) for _ in range(4)]
    ok &= check_t4(ladder)[0] == "PASS" and check_t4(flat)[0] == "FAIL"
    # A dark frame: a reversed vig is not held against it when sat and grain move,
    # a frame that only desaturates fails, and a lit frame with a reversed vignette still fails.
    dark = [dict(f, vig=0.4 + 0.02 * i, border=0.03) for i, f in enumerate(ladder)]
    ok &= check_t4(dark)[0] == "PASS"
    ok &= check_t4([dict(f, grain=0.002, vig=0.5, border=0.03) for f in ladder])[0] == "FAIL"
    ok &= check_t4([dict(f, vig=0.4 + 0.02 * i) for i, f in enumerate(ladder)])[0] == "FAIL"
    # Monochrome T4: lines on black with grain rising and border lines dimming passes; the
    # same frame four times fails.
    def lines_frame(grain_amp, k):
        img = np.zeros((90, 160, 3), dtype=np.float32)
        img[::5, :, :] = 0.9
        img[:, ::8, :] = 0.9
        if k:
            kx = k * 16 // 9
            img[:k] = 0.0
            img[-k:] = 0.0
            img[:, :kx] = 0.0
            img[:, -kx:] = 0.0
        noise = rng.random((90, 160)).astype(np.float32) * grain_amp
        return np.clip(img + noise[:, :, None], 0.0, 1.0)
    mono_ladder = [mono_features(lines_frame(g, k)) for g, k in ((0.01, 0), (0.05, 3), (0.1, 5), (0.15, 7))]
    mono_flat = [mono_features(lines_frame(0.05, 0)) for _ in range(4)]
    ok &= check_t4_mono(mono_ladder)[0] == "PASS" and check_t4_mono(mono_flat)[0] == "FAIL"
    # Soft wall shimmer: a 2% swing inside the rect passes, none fails, a 20% swing is garish.
    base = np.full((64, 96, 3), 0.4, dtype=np.float32)
    rect = [32, 16, 64, 48]
    def swung(v):
        img = base.copy()
        img[16:48, 32:64] += v
        return img
    ok &= check_soft(base, swung(0.02), rect)[0] == "PASS"
    ok &= check_soft(base, base, rect)[0] == "FAIL"
    ok &= check_soft(base, swung(0.2), rect)[0] == "FAIL"
    # The by-eye record (T5, T6): a pass is MANUAL, a fail FAIL, a missing row OPEN; the real
    # record parses and names every stratum and every error.
    import tempfile
    with tempfile.NamedTemporaryFile("w", suffix=".md", delete=False, encoding="utf-8") as f:
        f.write("| target | subject | result | frame | note |\n|---|---|---|---|---|\n")
        f.write("| T5 | halls | pass | corridor_c100 | yellow |\n| T6 | still | fail | still_15m | lost in fog |\n")
        tmp = f.name
    eye = {(r[0], r[1]): r[2] for r in by_eye_rows(["halls", "pools"], tmp)}
    os.unlink(tmp)
    ok &= eye.get(("halls", "T5 by eye")) == "MANUAL" and eye.get(("still", "T6 by eye")) == "FAIL"
    ok &= eye.get(("pools", "T5 by eye")) == "OPEN" and eye.get(("echo", "T6 by eye")) == "OPEN"
    real = by_eye_rows(["halls", "pools", "garage", "offices", "server", "substrate"])
    ok &= len(real) == 11 and all(r[2] != "FAIL" for r in real)
    print("tour_check selftest: %s" % ("ok" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(run(sys.argv[1] if len(sys.argv) > 1 else "build/tour"))
