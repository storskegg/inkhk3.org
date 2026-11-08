"""Measures every candidate font's Egyptological aleph (U+A723) against Umschrift's, writes
lab/aleph.json and lab/aleph-report.md.

Run: python -I lab/measure-aleph.py   (python with fontTools, brotli, Pillow, numpy, scipy)
Inputs: lab/fonts/<name>/<style>.woff2 (lab/fetch-fonts.sh), lab/fonts.json (lab/check-coverage.py).
Everything is read from the font files: outlines via fontTools pens, shapes by rasterising with
Pillow/FreeType. All numbers are approximate (rasterised at ~400 px ink height, no hinting control).

Umschrift is keyboard-mapped: its aleph is the glyph at "#", but its 'x' and 'H' are NOT plain Latin
(x = h-breve-below, H = H with dot below). So for Umschrift the x-height is the top of the flat-topped
plain 'z' and the cap height the top of plain 'E'. All other fonts use 'x' and 'H'.
"""
import io, json, math, os, sys
import numpy as np
from fontTools.ttLib import TTFont
from fontTools.pens.boundsPen import BoundsPen
from fontTools.varLib import instancer
from PIL import Image, ImageDraw, ImageFont
from scipy import ndimage as ndi

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "fonts")
ALEPH = 0xA723
TARGET_H = 400          # rasterised ink height of the aleph, px
STEM_EM_PX = 1000       # px per em when measuring the stem of 'I'

# ---------------------------------------------------------------- font access
_cache = {}


def load(name, style, wght=None):
    """TTFont for lab/fonts/<name>/<style>.woff2 as a static font (variable fonts instanced: wght 400/700,
    other axes at default). Returns (TTFont, ttf bytes) or None."""
    key = (name, style, wght)
    if key in _cache:
        return _cache[key]
    p = os.path.join(FONTS, name, style + ".woff2")
    if not os.path.exists(p):
        _cache[key] = None
        return None
    f = TTFont(p)
    f.flavor = None
    if "fvar" in f:
        loc = {a.axisTag: a.defaultValue for a in f["fvar"].axes}
        if "wght" in loc:
            loc["wght"] = wght or (700 if style.startswith("bold") else 400)
        f = instancer.instantiateVariableFont(f, loc, inplace=False)
    buf = io.BytesIO()
    f.save(buf)
    f = TTFont(io.BytesIO(buf.getvalue()))
    _cache[key] = (f, buf.getvalue())
    return _cache[key]


def bounds(f, ch):
    gs = f.getGlyphSet()
    g = f.getBestCmap().get(ord(ch))
    if g is None:
        return None
    bp = BoundsPen(gs)
    gs[g].draw(bp)
    return bp.bounds


def advance(f, ch):
    return f["hmtx"][f.getBestCmap()[ord(ch)]][0]


# ---------------------------------------------------------------- raster helpers
def render(ttf, ch, px_per_em):
    """Boolean ink image of ch, cropped to its ink box, plus its offsets from the origin/baseline in px."""
    ft = ImageFont.truetype(io.BytesIO(ttf), px_per_em)
    W = int(px_per_em * 3)
    im = Image.new("L", (W, W), 0)
    ox, oy = W // 3, W * 2 // 3
    ImageDraw.Draw(im).text((ox, oy), ch, font=ft, fill=255, anchor="ls")
    a = np.asarray(im) > 127
    ys, xs = np.where(a)
    y0, y1, x0, x1 = ys.min(), ys.max() + 1, xs.min(), xs.max() + 1
    return a[y0:y1, x0:x1], (x0 - ox, oy - y1)   # left bearing, bottom above baseline (px)


def zhang_suen(img):
    img = img.copy().astype(np.uint8)
    img = np.pad(img, 1)
    changed = True
    while changed:
        changed = False
        for step in (0, 1):
            P = [np.roll(img, s, (0, 1)) for s in ((1, 0), (1, -1), (0, -1), (-1, -1), (-1, 0), (-1, 1), (0, 1), (1, 1))]
            P2, P3, P4, P5, P6, P7, P8, P9 = P
            B = sum(P)
            A = sum(((P[i] == 0) & (P[(i + 1) % 8] == 1)).astype(np.uint8) for i in range(8))
            if step == 0:
                c = (P2 * P4 * P6 == 0) & (P4 * P6 * P8 == 0)
            else:
                c = (P2 * P4 * P8 == 0) & (P2 * P6 * P8 == 0)
            m = (img == 1) & (B >= 2) & (B <= 6) & (A == 1) & c
            if m.any():
                img[m] = 0
                changed = True
    return img[1:-1, 1:-1].astype(bool)


def skeleton_length(sk):
    n = 0.0
    ys, xs = np.where(sk)
    s = set(zip(ys.tolist(), xs.tolist()))
    for y, x in s:
        for dy, dx, d in ((0, 1, 1.0), (1, 0, 1.0), (1, 1, math.sqrt(2)), (1, -1, math.sqrt(2))):
            if (y + dy, x + dx) in s:
                n += d
    return max(n, 1.0)


def stem_em(ttf):
    """Stem width of 'I' in em: median run length of ink in the middle band."""
    a, _ = render(ttf, "I", STEM_EM_PX)
    h = a.shape[0]
    runs = []
    for y in range(int(h * 0.45), int(h * 0.55)):
        lab, n = ndi.label(a[y][None, :])
        for i in range(1, n + 1):
            runs.append(int((lab == i).sum()))
    return float(np.median(runs)) / STEM_EM_PX


def blur(a, sigma):
    return ndi.gaussian_filter(a.astype(float), sigma)


def place(a, W, H, cx, cy):
    """Put boolean image a on a W x H canvas so its centroid lands on (cx, cy)."""
    out = np.zeros((H, W), bool)
    ys, xs = np.where(a)
    my, mx = ys.mean(), xs.mean()
    dy, dx = int(round(cy - my)), int(round(cx - mx))
    y0, x0 = max(0, dy), max(0, dx)
    y1, x1 = min(H, dy + a.shape[0]), min(W, dx + a.shape[1])
    out[y0:y1, x0:x1] = a[y0 - dy:y1 - dy, x0 - dx:x1 - dx]
    return out


def shape_stats(ttf, ch, stem):
    """Rasterise ch so its ink is TARGET_H px tall; return stats and the image."""
    probe, _ = render(ttf, ch, 500)
    ppe = 500.0 * TARGET_H / probe.shape[0]
    a, _ = render(ttf, ch, ppe)
    H, W = a.shape
    lab, n = ndi.label(a, structure=np.ones((3, 3)))
    sizes = ndi.sum(a, lab, range(1, n + 1))
    keep = [i + 1 for i, s in enumerate(sizes) if s >= 0.005 * a.sum()]
    comps = [(lab == k) for k in keep]
    rows = a.any(axis=1)
    # largest run of ink-free rows between ink rows = vertical gap between the pieces
    gap = run = 0
    started = False
    for r in rows:
        if r:
            started = True
            gap = max(gap, run)
            run = 0
        elif started:
            run += 1
    sep = None
    if len(comps) >= 2:
        comps.sort(key=lambda c: -c.sum())
        dt = ndi.distance_transform_edt(~comps[0])
        sep = float(dt[comps[1]].min()) / H
    sk = zhang_suen(a)
    thick_px = a.sum() / skeleton_length(sk)
    return {
        "components": len(comps),
        "gapFrac": gap / H,
        "componentDistFrac": sep,
        "strokeEm": float(thick_px / ppe),
        "strokeOverStem": float(thick_px / ppe / stem),
        "aspectWH": W / H,
    }, a


def iou(a, b):
    return float((a & b).sum() / max(1, (a | b).sum()))


def soft_iou(a, b, sigma):
    x, y = blur(a, sigma), blur(b, sigma)
    return float(np.minimum(x, y).sum() / max(1e-9, np.maximum(x, y).sum()))


def compare(a, u):
    """Silhouette similarity of a to Umschrift's u (both ~TARGET_H px tall, aspect kept):
    centroid-aligned IoU, a blurred ('soft') IoU, and IoU with a stretched to u's ink box."""
    H = TARGET_H + 120
    W = max(a.shape[1], u.shape[1]) + 120
    cx, cy = W / 2, H / 2
    ap, up = place(a, W, H, cx, cy), place(u, W, H, cx, cy)
    sig = 0.02 * TARGET_H
    r = {"iou": iou(ap, up), "iouSoft": soft_iou(ap, up, sig)}
    st = np.asarray(Image.fromarray((a * 255).astype(np.uint8)).resize((u.shape[1], u.shape[0]), Image.LANCZOS)) > 127
    r["iouStretched"] = iou(st, u)
    return r


# ---------------------------------------------------------------- per font and face
def measure_face(name, style, is_umschrift=False, wght=None):
    got = load(name, style, wght)
    if not got:
        return None
    f, ttf = got
    upm = f["head"].unitsPerEm
    ach = "#" if is_umschrift else "ꜣ"
    xch, cch = ("z", "E") if is_umschrift else ("x", "H")
    ab = bounds(f, ach)
    if ab is None:
        return None
    xb, cb, kb = bounds(f, xch), bounds(f, cch), bounds(f, "k")
    x_h, cap_h = xb[3], cb[3]
    ah, aw = ab[3] - ab[1], ab[2] - ab[0]
    title = "Ink Ok#" if is_umschrift else "Ink Ḥkꜣ"
    title_adv = sum(advance(f, c) for c in title) / upm
    m = {
        "upm": upm, "xHeightEm": x_h / upm, "capHeightEm": cap_h / upm,
        "alephHeightEm": ah / upm, "alephWidthEm": aw / upm,
        "alephTopEm": ab[3] / upm, "alephBottomEm": ab[1] / upm,
        "alephAdvanceEm": advance(f, ach) / upm,
        "kWidthEm": (kb[2] - kb[0]) / upm,
        "hOverX": ah / x_h, "hOverCap": ah / cap_h, "wOverX": aw / x_h,
        "topOverCap": ab[3] / cap_h, "bottomOverX": ab[1] / x_h, "wOverK": aw / (kb[2] - kb[0]),
        "titleAdvanceEm": title_adv,
        "xGlyph": xch, "capGlyph": cch,
    }
    stem = stem_em(ttf)
    s, img = shape_stats(ttf, ach, stem)
    m.update(s)
    m["stemEm"] = stem
    return m, img


def ratio_score(r, ru, tol=1.5):
    """1 when equal, 0 when r differs from ru by a factor of tol (50 % by default) or more; log-linear."""
    if r <= 0 or ru <= 0:
        return 0.0
    return max(0.0, 1 - abs(math.log(r / ru)) / math.log(tol))


def score(m, u):
    comp = 1.0 if m["components"] == u["components"] else (0.25 if abs(m["components"] - u["components"]) == 1 else 0.0)
    # gap: 0 when the vertical gap differs from Umschrift's by 0.15 of the glyph height or more
    gapS = max(0.0, 1 - abs(m["gapFrac"] - u["gapFrac"]) / 0.15)
    iouS = m["iouMean"]
    strokeS = ratio_score(m["strokeOverStem"], u["strokeOverStem"], 2.0)
    shape = (comp + gapS + iouS + strokeS) / 4
    pr = [ratio_score(m["hOverX"], u["hOverX"]), ratio_score(m["wOverX"], u["wOverX"]), ratio_score(m["topOverCap"], u["topOverCap"])]
    prop = sum(pr) / 3
    return {"compMatch": comp, "gapScore": gapS, "iouScore": iouS, "strokeScore": strokeS, "shape": shape,
            "hOverXScore": pr[0], "wOverXScore": pr[1], "topOverCapScore": pr[2], "proportion": prop,
            "total": (shape + prop) / 2}


def main():
    data = json.load(open(os.path.join(HERE, "fonts.json"), encoding="utf-8"))
    out = {"umschrift": {}, "fonts": [], "formula": None}
    uimg = {}
    for st in ("bold", "regular"):
        r = measure_face("umschrift", st, True)
        out["umschrift"][st] = r[0]
        uimg[st] = r[1]
    for fe in data["fonts"]:
        name = fe["name"]
        if name == "umschrift" or fe.get("virtual") or "regular" not in fe["styles"]:
            continue
        if not fe["styles"]["regular"]["core"].get("ꜣ"):
            continue
        entry = {"name": name, "family": fe["family"], "licence": fe["licence"], "woff2": {}, "faces": {}}
        has_bold = "bold" in fe["styles"] or bool(fe.get("weightRange") and fe["weightRange"][1] >= 700)
        reg = fe["styles"]["regular"]
        for want in ("bold", "regular"):
            real = want == "regular"
            if want == "bold":
                if "bold" in fe["styles"] and fe["styles"]["bold"]["core"].get("ꜣ"):
                    got, real = measure_face(name, "bold"), True        # static bold file
                elif reg["variable"] and has_bold:
                    got, real = measure_face(name, "regular", wght=700), True   # variable: wght axis at 700
                else:
                    got = measure_face(name, "regular")                 # no bold: regular stands in
            else:
                got = measure_face(name, "regular")
            if not got:
                continue
            m, img = got
            m.update(compare(img, uimg[want]))
            m["iouMean"] = (m["iou"] + m["iouSoft"]) / 2
            m["realFace"] = real
            m.update({"score_" + k: v for k, v in score(m, out["umschrift"][want]).items()})
            m["score"] = m["score_total"]
            entry["faces"][want] = m
        for st, info in fe["styles"].items():
            if st in ("regular", "bold"):
                entry["woff2"][st] = info["woff2Bytes"]
        entry["hasBold"] = has_bold and bool(entry["faces"].get("bold", {}).get("realFace"))
        out["fonts"].append(entry)
    for want in ("bold", "regular"):
        order = sorted(out["fonts"], key=lambda e: -e["faces"][want]["score"])
        for i, e in enumerate(order):
            e["faces"][want]["rank"] = i + 1
        out["rank_" + want] = [e["name"] for e in order]
    out["formula"] = FORMULA
    with open(os.path.join(HERE, "aleph.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
    write_report(out)
    print("wrote aleph.json and aleph-report.md:", len(out["fonts"]), "fonts")


FORMULA = """total = (shape + proportion) / 2
shape      = mean of four scores, each 0..1:
  components  1 if the number of separate ink pieces equals Umschrift's, 0.25 if it differs by one, else 0
  gap         1 - |gap - gap_Umschrift| / 0.15, clipped at 0   (gap = tallest ink-free band between the pieces, as a fraction of the glyph height)
  iou         mean of the hard IoU and a blurred (sigma 2 % of the height) IoU against Umschrift's glyph, both at 400 px ink height, centroids aligned, aspect kept
  stroke      1 - |log2(r / r_Umschrift)|, clipped at 0, r = mean stroke thickness / the font's own 'I' stem
proportion = mean of three scores, each 1 - |ln(r / r_Umschrift)| / ln(1.5), clipped at 0 (zero when 50 % off):
  height / x-height,  width / x-height,  top / cap height
Rank on the bold face (the title face; the regular face if the font has no bold) and, separately, on regular."""


def write_report(out):
    U = out["umschrift"]
    L = []
    L.append("# Aleph (ꜣ) against Umschrift\n")
    L.append("Generated by `lab/measure-aleph.py` from the font files. All numbers are approximate: outlines are exact, but shape numbers come from rasterising at about 400 px ink height with FreeType/Pillow (stroke thickness = ink area / Zhang-Suen skeleton length).\n")
    L.append("Umschrift is keyboard-mapped. Its aleph is the glyph at `#`. Its `x` and `H` are not plain Latin letters (`x` is h-breve-below, `H` is H with a dot below), so its x-height is taken from the flat top of plain `z` and its cap height from plain `E`; every other font uses `x` and `H`. Title width = sum of advance widths (no kerning or GPOS) of \"Ink Ok#\" for Umschrift and \"Ink Ḥkꜣ\" for the others.\n")
    for st in ("bold", "regular"):
        u = U[st]
        L.append(f"**Umschrift {'SB (the title face)' if st == 'bold' else 'S (regular)'}:** ꜣ is {u['components']} separate ink piece(s); gap {u['gapFrac']*100:.1f} % of its height (distance between the pieces {((u['componentDistFrac'] or 0)*100):.1f} %); ink {u['alephHeightEm']:.3f} em high, {u['alephWidthEm']:.3f} em wide, top {u['alephTopEm']:.3f} em, bottom {u['alephBottomEm']:.3f} em; x-height {u['xHeightEm']:.3f} em, cap {u['capHeightEm']:.3f} em; h/x {u['hOverX']:.2f}, h/cap {u['hOverCap']:.2f}, w/x {u['wOverX']:.2f}, top/cap {u['topOverCap']:.2f}, w/k {u['wOverK']:.2f}; stroke/stem {u['strokeOverStem']:.2f}; title {u['titleAdvanceEm']:.3f} em.\n")
    L.append("## Formula\n\n```\n" + out["formula"] + "\n```\n")
    for st, title in (("bold", "Ranking, bold face (the title face)"), ("regular", "Ranking, regular face")):
        L.append(f"## {title}\n")
        L.append("| # | Font | Score | shape | prop | ꜣ pieces | gap % | IoU (hard/soft/stretched) | stroke/stem | h/x | h/cap | w/x | top/cap | w/k | title em | licence | woff2 KB (R/B) |")
        L.append("|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|")
        u = U[st]
        L.append(f"| - | **Umschrift ({'SB' if st=='bold' else 'S'})** | - | - | - | {u['components']} | {u['gapFrac']*100:.1f} | - | {u['strokeOverStem']:.2f} | {u['hOverX']:.2f} | {u['hOverCap']:.2f} | {u['wOverX']:.2f} | {u['topOverCap']:.2f} | {u['wOverK']:.2f} | {u['titleAdvanceEm']:.2f} | unknown | - |")
        for name in out["rank_" + st]:
            e = next(x for x in out["fonts"] if x["name"] == name)
            m = e["faces"][st]
            kb = lambda k: f"{e['woff2'][k]/1024:.0f}" if k in e["woff2"] else "-"
            note = "" if m["realFace"] else " (no bold: regular)"
            L.append(f"| {m['rank']} | {e['family']}{note} | {m['score']:.3f} | {m['score_shape']:.2f} | {m['score_proportion']:.2f} | {m['components']} | {m['gapFrac']*100:.1f} | {m['iou']:.2f} / {m['iouSoft']:.2f} / {m['iouStretched']:.2f} | {m['strokeOverStem']:.2f} | {m['hOverX']:.2f} | {m['hOverCap']:.2f} | {m['wOverX']:.2f} | {m['topOverCap']:.2f} | {m['wOverK']:.2f} | {m['titleAdvanceEm']:.2f} | {e['licence'].split(' (')[0]} | {kb('regular')} / {kb('bold')} |")
        L.append("")
    open(os.path.join(HERE, "aleph-report.md"), "w", encoding="utf-8").write("\n".join(L))


main()
