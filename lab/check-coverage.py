"""Writes lab/fonts.json from lab/fonts/*/<style>.woff2 plus lab/fonts-meta.json.
Run: python -I lab/check-coverage.py   (python with fontTools and brotli)
Coverage comes from the cmap tables, never from rendering."""
import json, os, sys
from fontTools.ttLib import TTFont

HERE = os.path.dirname(os.path.abspath(__file__))
FONTS = os.path.join(HERE, "fonts")
STYLES = ["regular", "italic", "bold", "bolditalic"]

# label -> codepoint sequence (for sequences, every codepoint must be in the cmap)
CORE = [("Ꜣ", [0xA722]), ("ꜣ", [0xA723]), ("Ꜥ", [0xA724]), ("ꜥ", [0xA725]),
        ("Ḥ", [0x1E24]), ("ḥ", [0x1E25]), ("Ḫ", [0x1E2A]), ("ḫ", [0x1E2B]), ("ẖ", [0x1E96]),
        ("Š", [0x160]), ("š", [0x161]), ("Ṯ", [0x1E6E]), ("ṯ", [0x1E6F]), ("Ḏ", [0x1E0E]), ("ḏ", [0x1E0F]),
        ("Ṭ", [0x1E6C]), ("ṭ", [0x1E6D]), ("Ḳ", [0x1E32]), ("ḳ", [0x1E33]),
        ("Ꞽ", [0xA7BC]), ("ꞽ", [0xA7BD]), ("◌̱ U+0331", [0x331])]
EXTRA = [("Q", [0x51]), ("q", [0x71]), ("◌̓ U+0313", [0x313]), ("◌͗ U+0357", [0x357])]
# H + U+0331 is the "H̱" sequence; its cmap check is U+0331 (the H is basic Latin).
BASIC = sorted(set("Ink {.org} May your words occur; may your magic shine." + "Ritner 1993, p. 30; Hornung & Abt 2007, p. 152"))


def covers(cmap, cps):
    return all(c in cmap for c in cps)


def name(f, i):
    r = f["name"].getName(i, 3, 1, 0x409) or f["name"].getName(i, 1, 0, 0)
    return r.toUnicode().strip() if r else None


def main():
    meta = json.load(open(os.path.join(HERE, "fonts-meta.json"), encoding="utf-8"))
    out = {"core": [c for c, _ in CORE], "extra": [c for c, _ in EXTRA],
           "coreDefinition": "22 core chars: 21 letters (U+A722-A725, 1E24/5, 1E2A/B, 1E96, 160/1, 1E6E/F, 1E0E/F, 1E6C/D, 1E32/3, A7BC/D) plus combining U+0331 (for H̱)",
           "fonts": []}
    for key, m in meta.items():
        d = os.path.join(FONTS, key)
        entry = {"name": key, **m, "styles": {}, "downloaded": os.path.isdir(d)}
        if m.get("virtual") or not os.path.isdir(d):
            entry["styles"] = {}
            out["fonts"].append(entry)
            continue
        for st in STYLES:
            p = os.path.join(d, st + ".woff2")
            if not os.path.exists(p):
                continue
            f = TTFont(p)
            cmap = f.getBestCmap()
            info = {
                "woff2Bytes": os.path.getsize(p),
                "version": name(f, 5), "fullName": name(f, 4),
                "nameID0_copyright": name(f, 0), "nameID13_licence": name(f, 13), "nameID14_licenceUrl": name(f, 14),
                "variable": "fvar" in f,
                "core": {c: covers(cmap, cps) for c, cps in CORE},
                "extra": {c: covers(cmap, cps) for c, cps in EXTRA},
                "basicLatin": all(ord(ch) in cmap for ch in BASIC),
                "missingBasic": [ch for ch in BASIC if ord(ch) not in cmap],
                "gposMarkFeature": bool("GPOS" in f and any(fr.FeatureTag in ("mark", "mkmk") for fr in f["GPOS"].table.FeatureList.FeatureRecord)),
            }
            if info["variable"]:
                info["axes"] = {a.axisTag: [a.minValue, a.defaultValue, a.maxValue] for a in f["fvar"].axes}
            info["coreScore"] = sum(info["core"].values())
            entry["styles"][st] = info
            f.close()
        ss = entry["styles"]
        if ss:
            var = [s for s in ss.values() if s["variable"]]
            if var and "wght" in var[0].get("axes", {}):
                lo, _, hi = var[0]["axes"]["wght"]
                entry["weightRange"] = [lo, hi]
            entry["coreMin"] = min(s["coreScore"] for s in ss.values())
            entry["coreRegular"] = ss.get("regular", {}).get("coreScore")
            entry["woff2Regular"] = ss.get("regular", {}).get("woff2Bytes")
            entry["hasBold"] = "bold" in ss or (bool(var) and entry.get("weightRange", [0, 0])[1] >= 700)
            entry["hasItalic"] = "italic" in ss
            entry["hasBoldItalic"] = "bolditalic" in ss or (bool(var) and "italic" in ss and entry["hasBold"])
        out["fonts"].append(entry)
    with open(os.path.join(HERE, "fonts.json"), "w", encoding="utf-8") as fh:
        json.dump(out, fh, ensure_ascii=False, indent=1)
    print("wrote fonts.json:", len(out["fonts"]), "fonts")


main()
