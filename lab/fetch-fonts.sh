#!/usr/bin/env bash
# Downloads the candidate fonts listed in manifest.tsv (pinned release URLs, sha256 verified),
# converts each style to woff2 (lossless, no subsetting) into lab/fonts/<name>/<style>.woff2, and
# copies today's site fonts and assets for comparison. Idempotent: cached downloads and finished
# outputs are reused. Needs FONTTOOLS_PY (a python with fontTools + brotli), e.g.
#   FONTTOOLS_PY=/path/to/venv/bin/python lab/fetch-fonts.sh
# Downloads are untrusted data: they are only hashed, unzipped by Python's zipfile and read with
# fontTools; nothing from them is executed.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")"
: "${FONTTOOLS_PY:?set FONTTOOLS_PY to a python with fontTools and brotli}"
PUB=../public
DL=fonts/.dl
mkdir -p "$DL"
fail=0

sha_of() { shasum -a 256 "$1" | cut -d' ' -f1; }

while IFS=$'\t' read -r name style url sha member; do
  [[ -z "$name" || "$name" == \#* ]] && continue
  ext=woff2; [[ "$style" == licence ]] && ext=lic
  out="fonts/$name/$style.$ext"
  [[ -s "$out" ]] && continue
  cache="$DL/$sha"
  if [[ ! -s "$cache" ]]; then
    echo "download $url"
    if ! curl -fsSL --max-time 300 -o "$cache.part" "$url"; then
      echo "FAILED download: $url" >&2; rm -f "$cache.part"; fail=1; continue
    fi
    mv "$cache.part" "$cache"
  fi
  if [[ "$(sha_of "$cache")" != "$sha" ]]; then
    echo "SHA256 MISMATCH for $url (expected $sha)" >&2; rm -f "$cache"; fail=1; continue
  fi
  mkdir -p "fonts/$name"
  kind=font; [[ "$style" == licence ]] && kind=licence
  tmp="$out.part"
  if "$FONTTOOLS_PY" -I extract.py "$kind" "$cache" "$member" "$tmp"; then
    mv "$tmp" "$out"; echo "ok  $out"
  else
    echo "FAILED convert: $name $style" >&2; rm -f "$tmp"; fail=1
  fi
done < manifest.tsv

# Today's site fonts (Umschrift) and the card's assets, for the side-by-side card.
mkdir -p fonts/umschrift
cp "$PUB/UMSCH_S.woff2"  fonts/umschrift/regular.woff2
cp "$PUB/UMSCH_SB.woff2" fonts/umschrift/bold.woff2
cp "$PUB/UMSCH_I.woff2"  fonts/umschrift/italic.woff2
cp "$PUB/UMSCH_IB.woff2" fonts/umschrift/bolditalic.woff2
# hierojax.js asks for /NewGardiner.woff2 at the server root, so these live at lab/ root.
cp "$PUB/NewGardiner.woff2" "$PUB/paper_fff.jpg" "$PUB/binding_dark2.png" ../src/hierojax.js .
cp ../src/_hierojax.scss hierojax.css   # plain CSS despite the extension

[[ $fail -eq 0 ]] || { echo "some fonts failed (see above); the rest are ready" >&2; exit 1; }
echo "done"
