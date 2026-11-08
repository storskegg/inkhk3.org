#!/usr/bin/env python3
"""Make public/InkHk3Serif-Bold.woff2 and InkHk3Serif-Italic.woff2 from the New Athena Unicode 5.008 release.

Usage (fontTools and brotli needed; the source zip is data only, nothing in it is executed):

    python3 -I fonts/make-inkhk3-serif.py NAU5_008.zip public/

The zip is https://apagreekkeys.org/fonts/NAU5_008.zip; its sha256 is checked first. The font is opened with
recalcBBoxes=False, only the `name` table is changed (the family is renamed, because the SIL OFL 1.1 reserves the
original name for the original; a modification note is added to name ID 10), and the result is saved as woff2
with the default transforms: no subsetting, no other table edit. Converting drops DSIG, rebuilds glyf and loca
and sets head's flag and modified date; that is all that differs from the source besides `name`.

The script then decodes each output and fails if any table's raw bytes contain the reserved name's roots
("athena", "newathu"; case-insensitive; ASCII and UTF-16BE). Name IDs 0, 13 and 14 (copyright, licence
description, licence URL) are kept as they are; the script stops if one of them contains the reserved name.
"""
import hashlib
import io
import re
import sys
import zipfile

from fontTools.ttLib import TTFont

SHA256 = "cdfe5c38aac9c9c82568e7260cf79fe4c3f4d51461713b1485214104a6e7bbf1"
FAMILY = "InkHk3 Serif"
PS_BASE = "InkHk3Serif"
NOTE = ("Modified for inkhk3.org, 2026: renamed under the SIL Open Font License 1.1 (reserved name not used); "
        "converted to WOFF2 (DSIG dropped, glyf and loca rebuilt, head flags and modified date changed). "
        "Outlines, hinting and metrics unchanged. Licence text and original font's name: "
        "https://inkhk3.org/InkHk3Serif-OFL.txt")
TRADEMARK = ("The name of the font this one is derived from is a trademark of Society for Classical Studies "
             "(formerly American Philological Association).")
FONTS = [("Bold", "NAU5_008/newathuBold5_8.ttf"), ("Italic", "NAU5_008/newathuItalic5_8.ttf")]
KEEP = (0, 13, 14)
OLD = re.compile(r"new\s*athena(\s*unicode)?|newathu\w*|athena", re.I)
NEEDLES = [s.encode(enc) for s in ("athena", "newathu") for enc in ("ascii", "utf-16-be")]


def fail(msg):
    sys.exit("error: " + msg)


def text(rec):
    return rec.toUnicode()


def put(rec, s):
    rec.string = s.encode(rec.getEncoding())


def rename(font, style):
    ps = f"{PS_BASE}-{style}"
    names = font["name"].names
    for rec in names:
        if rec.nameID in KEEP:
            if OLD.search(text(rec)):
                fail(f"name ID {rec.nameID} contains the reserved name: {text(rec)!r}")
            continue
        s = text(rec)
        if rec.nameID in (1, 16, 21):
            put(rec, FAMILY)
        elif rec.nameID == 3:
            put(rec, OLD.sub(PS_BASE, s))  # "Version 5.008;SWAP;<ps name>;2021;FL720"
        elif rec.nameID == 4:
            put(rec, f"{FAMILY} {style}")
        elif rec.nameID == 6:
            put(rec, ps)
        elif rec.nameID == 7:
            put(rec, TRADEMARK)
        elif rec.nameID == 10:
            put(rec, (s + " " + NOTE) if s else NOTE)
        elif rec.nameID in (2, 17, 22):
            pass  # subfamily stays
        elif OLD.search(s):
            fail(f"name ID {rec.nameID} still carries the old name: {s!r}")
    # Name ID 10 may not exist: add it for every (platform, encoding, language) that has an ID 1.
    have10 = {(r.platformID, r.platEncID, r.langID) for r in names if r.nameID == 10}
    for r in list(names):
        k = (r.platformID, r.platEncID, r.langID)
        if r.nameID == 1 and k not in have10:
            font["name"].setName(NOTE, 10, *k)


def check(path):
    font = TTFont(path, recalcBBoxes=False)
    bad = []
    for tag in font.reader.keys():
        raw = font.reader[tag].lower()
        for n in NEEDLES:
            if n in raw:
                bad.append((tag, n))
    if bad:
        fail(f"{path}: reserved name found in {bad}")
    print(f"ok  {path}: no 'athena'/'newathu' (ASCII, UTF-16BE) in any of {len(font.reader.keys())} tables")


def main():
    if len(sys.argv) != 3:
        fail("usage: make-inkhk3-serif.py NAU5_008.zip OUTDIR")
    zpath, outdir = sys.argv[1:]
    data = open(zpath, "rb").read()
    if hashlib.sha256(data).hexdigest() != SHA256:
        fail("sha256 of the zip does not match")
    z = zipfile.ZipFile(io.BytesIO(data))
    for style, member in FONTS:
        font = TTFont(io.BytesIO(z.read(member)), recalcBBoxes=False)
        rename(font, style)
        font.flavor = "woff2"
        out = f"{outdir.rstrip('/')}/{PS_BASE}-{style}.woff2"
        font.save(out)
        print(f"wrote {out}")
        check(out)


main()
