#!/usr/bin/env python3
"""Checks the screenshot tour (docs/design/02 section 13, 14 section 9) against T1, T3 and T4.

Usage: tools/ci/tour_check.py [tour_dir]          (default build/tour; reads manifest.json)
       tools/ci/tour_check.py --selftest          (PNG decoder against files it writes itself)
Exit code 0 when no check fails, 1 otherwise. numpy is required; Pillow is used when it is
installed, otherwise a small zlib PNG decoder reads the frames (set TOUR_CHECK_NO_PIL=1 to
force it).

T1  Readability of the floor. At Coherence 100, flashlight off, every floor reading the
    tour took (2..12 m ahead, 2..6 m in Server and Substrate) is above 8% luminance.
T3  No flat black, no flat white. At Coherence 100 the darkest 1% of a frame is above 2%
    luminance (fog in the shadow) and bright clipped pixels stay under 2% of the frame
    (the brightest fixture blooms but is not a white slab).
T4  Coherence is visible without the HUD. For each pose the four frames (100, 60, 30, 10)
    must be orderable by measurement: between consecutive frames at least two of saturation
    (falls), grain (rises) and vignette (corner-to-centre brightness falls) move the right
    way, and none moves the wrong way by more than its tolerance.
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
# 02 section 5 soft walls: the band's temporal contrast between two frames 1 s apart (half a
# 0.5 Hz period), as mean |delta luma| of 8 px block means on the wall. Below the minimum the
# shimmer is not there to read; above the maximum it is garish (it must stay "faint").
SOFT_BLOCK_PX = 8
SOFT_MIN_DELTA = 0.008
SOFT_MAX_DELTA = 0.05
SOFT_CONTROL_RATIO = 3


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


def features(img):
    return {"sat": saturation(img), "grain": grain(img), "vig": vignette(img)}


def check_t4(feats):
    """feats: list of feature dicts at Coherence 100, 60, 30, 10. Returns (status, detail)."""
    worst = "PASS"
    notes = []
    for i in range(len(feats) - 1):
        a, b = feats[i], feats[i + 1]
        moves = {
            "sat": (a["sat"] - b["sat"], T4_SAT_STEP),
            "grain": (b["grain"] - a["grain"], T4_NOISE_STEP),
            "vig": (a["vig"] - b["vig"], T4_VIG_STEP),
        }
        good = [k for k, (d, step) in moves.items() if d >= step]
        wrong = [k for k, (d, step) in moves.items() if d <= -step * T4_WRONG_WAY]
        if len(good) < 2 or wrong:
            worst = "FAIL"
            notes.append("step %d: good=%s wrong=%s" % (i + 1, ",".join(good) or "-", ",".join(wrong) or "-"))
    return worst, "; ".join(notes) if notes else "sat/grain/vig ordered"


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
        rows.append((stratum, "T1 floor", status, detail))
        failed |= status == "FAIL"
        imgs = {}
        for name, e in entries.items():
            if e.get("kind") == "pose" and e["coherence"] == 100:
                imgs[name] = decode_png(os.path.join(tour_dir, e["file"]))
        for name, e in sorted(entries.items()):
            if name not in imgs:
                continue
            dark, p01, white, frac = check_t3(e, imgs[name])
            rows.append((stratum, "T3 dark  " + name, dark, "p01 %.3f (>= %.2f)" % (p01, T3_MIN_P01)))
            rows.append((stratum, "T3 white " + name, white, "clipped %.2f%% (<= %.0f%%)" % (frac * 100, T3_MAX_CLIPPED_FRACTION * 100)))
            failed |= dark == "FAIL" or white == "FAIL"
        poses = sorted({e["pose"] for e in entries.values() if e.get("kind") == "pose" and e["coherence"] != 100})
        for pose in poses:
            feats = []
            for c in steps:
                key = "%s_c%03d" % (pose, int(c))
                if key not in entries:
                    break
                feats.append(features(decode_png(os.path.join(tour_dir, entries[key]["file"]))))
            if len(feats) == len(steps):
                status, detail = check_t4(feats)
                shown = " ".join("%.2f/%.4f/%.2f" % (f["sat"], f["grain"], f["vig"]) for f in feats)
                rows.append((stratum, "T4 order " + pose, status, "%s  [sat/grain/vig %s]" % (detail, shown)))
                failed |= status == "FAIL"
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
    print("tour_check selftest: %s" % ("ok" if ok else "FAILED"))
    return 0 if ok else 1


if __name__ == "__main__":
    if "--selftest" in sys.argv:
        sys.exit(selftest())
    sys.exit(run(sys.argv[1] if len(sys.argv) > 1 else "build/tour"))
