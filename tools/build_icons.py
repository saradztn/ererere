#!/usr/bin/env python3
"""
Dev tooling for the Referral System resource.

Takes the AI generated 5x3 icon sprite sheet (transparent checker background
baked into RGB) and produces 15 individual, normalised, transparent PNG icons
plus matching SVG sources, all sharing one visual language:

  * same optical size (content bbox normalised into the same box)
  * same padding / centering
  * same stroke colour
  * same corner rounding / caps (inherited from the single generation)

Run:  python3 tools/build_icons.py
"""
import os
import numpy as np
from PIL import Image

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SHEET = "/tmp/icon_sheet.png"
OUT_DIR = os.path.join(ROOT, "referral_system", "assets", "icons")

ICON_NAMES = [
    "referral", "referral-link", "invite", "share", "reward",
    "gift", "user-add", "team", "growth", "coins",
    "wallet", "milestone", "achievement", "activity", "analytics",
]

CANVAS = 128            # final PNG canvas (NovaUI icons are drawn small)
CONTENT_BOX = 0.80      # content occupies 80% of the canvas
STROKE_COLOR = (242, 245, 250, 255)


# ---------------------------------------------------------------- extraction
def checker_period(line):
    """Detect the checkerboard square size from a scanline of grey values."""
    runs, cur = [], 1
    for i in range(1, len(line)):
        same = abs(int(line[i]) - int(line[i - 1])) < 6
        if same:
            cur += 1
        else:
            runs.append(cur)
            cur = 1
    runs.append(cur)
    runs = [r for r in runs if r >= 2]
    if not runs:
        return 8
    return int(round(float(np.median(runs))))


def extract_alpha(rgb):
    """Separate the light icon strokes from the grey checkerboard."""
    luma = rgb[..., 0] * 0.299 + rgb[..., 1] * 0.587 + rgb[..., 2] * 0.114
    h, w = luma.shape
    period = checker_period(luma[h // 2])
    yy, xx = np.mgrid[0:h, 0:w]
    parity = ((xx // period) + (yy // period)) % 2

    # sample the two checker tones from a clean border area
    border = np.zeros((h, w), dtype=bool)
    border[:4, :] = border[-4:, :] = True
    border[:, :4] = border[:, -4:] = True
    dark_tone = float(np.median(luma[border & (parity == 0)]))
    light_tone = float(np.median(luma[border & (parity == 1)]))
    if light_tone < dark_tone:
        dark_tone, light_tone = light_tone, dark_tone

    bg = np.where(parity == 0, dark_tone, light_tone)
    stroke_luma = 236.0
    denom = max(stroke_luma - light_tone, 1.0)
    intensity = (luma - bg) / denom
    alpha = np.clip(intensity, 0.0, 1.0)
    return alpha


def content_runs(col, min_gap=8):
    """Maximal runs of content, merging runs separated by tiny gaps."""
    runs, start = [], None
    for i, v in enumerate(col):
        if v and start is None:
            start = i
        elif not v and start is not None:
            runs.append([start, i])
            start = None
    if start is not None:
        runs.append([start, len(col)])
    merged = []
    for r in runs:
        if r[1] - r[0] < 24:          # drop speckle / stray anti-aliased pixels
            continue
        if merged and r[0] - merged[-1][1] < min_gap:
            merged[-1][1] = r[1]
        else:
            merged.append(r)
    return merged


def bands(mask, expected, axis=0):
    """Split a mask into `expected` cell bands around the detected content runs."""
    col = mask.any(axis=axis) if mask.ndim == 2 else mask
    runs = content_runs(col)
    if len(runs) != expected:
        raise SystemExit("expected %d bands, found %d -> %s" % (expected, len(runs), runs))
    n = len(runs)
    cuts = []
    for i, r in enumerate(runs):
        start = 0 if i == 0 else (runs[i - 1][1] + r[0]) // 2
        end = len(col) if i == n - 1 else (r[1] + runs[i + 1][0]) // 2
        cuts.append((start, end))
    return cuts


def normalise(cell_rgba):
    """Crop to content, scale into a fixed box, centre on a square canvas."""
    alpha = cell_rgba[..., 3]
    ys, xs = np.where(alpha > 24)
    if len(xs) == 0:
        raise SystemExit("empty cell")
    x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
    crop = cell_rgba[y0:y1, x0:x1]
    ch, cw = crop.shape[:2]
    box = int(CANVAS * CONTENT_BOX)
    scale = min(box / cw, box / ch)
    nw, nh = max(1, int(round(cw * scale))), max(1, int(round(ch * scale)))
    img = Image.fromarray(crop, "RGBA").resize((nw, nh), Image.LANCZOS)
    canvas = Image.new("RGBA", (CANVAS, CANVAS), (0, 0, 0, 0))
    canvas.paste(img, ((CANVAS - nw) // 2, (CANVAS - nh) // 2), img)
    return canvas


def recolour(img, color=STROKE_COLOR):
    arr = np.array(img).astype(np.float32)
    a = arr[..., 3:4] / 255.0
    out = np.zeros_like(arr)
    out[..., 0] = color[0]
    out[..., 1] = color[1]
    out[..., 2] = color[2]
    out[..., 3] = arr[..., 3]
    return Image.fromarray(out.astype(np.uint8), "RGBA")


def to_svg(img, name):
    """Emit a transparent SVG wrapper around the raster (kept for editing)."""
    import base64
    import io
    buf = io.BytesIO()
    img.save(buf, format="PNG")
    b64 = base64.b64encode(buf.getvalue()).decode("ascii")
    return (
        '<svg xmlns="http://www.w3.org/2000/svg" width="128" height="128" '
        'viewBox="0 0 128 128">\n'
        '  <title>%s</title>\n'
        '  <image width="128" height="128" href="data:image/png;base64,%s"/>\n'
        '</svg>\n' % (name, b64)
    )


def main():
    os.makedirs(OUT_DIR, exist_ok=True)
    rgb = np.array(Image.open(SHEET).convert("RGB"))
    alpha = extract_alpha(rgb)
    mask = alpha > 0.18
    h, w = mask.shape

    xcuts = bands(mask, 5)
    ycuts = bands(mask, 3, axis=1)
    print("x bands:", xcuts)
    print("y bands:", ycuts)

    rgba = np.dstack([rgb, (alpha * 255).astype(np.uint8)])
    idx = 0
    for (ry0, ry1) in ycuts:
        for (cx0, cx1) in xcuts:
            cell = rgba[ry0:ry1, cx0:cx1]
            img = recolour(normalise(cell))
            name = ICON_NAMES[idx]
            img.save(os.path.join(OUT_DIR, name + ".png"))
            with open(os.path.join(OUT_DIR, name + ".svg"), "w") as fh:
                fh.write(to_svg(img, name))
            print("%02d %-14s %dx%d" % (idx + 1, name, img.size[0], img.size[1]))
            idx += 1
    assert idx == 15, idx
    print("done ->", OUT_DIR)


if __name__ == "__main__":
    main()
