"""Helper for fetch-fonts.sh. Run as: python -I extract.py font|licence SRC MEMBER OUT
SRC is a downloaded zip (MEMBER = path inside it) or a plain file (MEMBER = -).
font: converts to woff2 (lossless, no subsetting). licence: copies the bytes as is.
Only reads the data; nothing from a download is executed."""
import io, sys, zipfile
from fontTools.ttLib import TTFont

kind, src, member, out = sys.argv[1:5]
if member == "-":
    data = open(src, "rb").read()
else:
    with zipfile.ZipFile(src) as z:
        data = z.read(member)
if kind == "licence":
    open(out, "wb").write(data)
else:
    f = TTFont(io.BytesIO(data))
    f.flavor = "woff2"
    f.save(out)
