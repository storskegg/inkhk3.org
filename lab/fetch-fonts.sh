#!/usr/bin/env bash
# Downloads the candidate fonts listed in manifest.tsv (pinned release URLs, sha256 verified),
# converts each style to woff2 (lossless, no subsetting) into lab/fonts/<name>/<style>.woff2, and
# copies the site's assets and recovers Umschrift (today's reference) from git history. Idempotent: cached downloads and finished
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

# Umschrift, the site's title font until the switch to New Athena Unicode, stays in the lab as the "Today"
# reference. Its woff2 files left public/ with that switch, so they are taken from git history, from the
# last commit that had them (UMSCH_COMMIT), and checked against their sha256. (Not kept as lab copies:
# lab/fonts/ is gitignored, and committing the binaries again would put them back in the tree.)
UMSCH_COMMIT=7f519e9
mkdir -p fonts/umschrift
umsch() {  # umsch <file in public/ at UMSCH_COMMIT> <output> <sha256>
  [[ -s "fonts/umschrift/$2.woff2" && "$(sha_of "fonts/umschrift/$2.woff2")" == "$3" ]] && return 0
  if git cat-file -e "$UMSCH_COMMIT:public/$1" 2>/dev/null \
     && git show "$UMSCH_COMMIT:public/$1" > "fonts/umschrift/$2.woff2.part" \
     && [[ "$(sha_of "fonts/umschrift/$2.woff2.part")" == "$3" ]]; then
    mv "fonts/umschrift/$2.woff2.part" "fonts/umschrift/$2.woff2"; echo "ok  fonts/umschrift/$2.woff2 (git $UMSCH_COMMIT)"
  else
    rm -f "fonts/umschrift/$2.woff2.part"
    echo "FAILED: Umschrift $1 from git $UMSCH_COMMIT (history missing, e.g. a shallow clone, or hash mismatch)" >&2; fail=1
  fi
}
umsch UMSCH_S.woff2  regular    1500f41388c6d56b69198dfae30cf920fce3eeb442fe2c87c74e82d5e430bef4
umsch UMSCH_SB.woff2 bold       dfe0a17240463431280d163f59d2d4e64920aea859ca680a7c2cfd09dc11ae2e
umsch UMSCH_I.woff2  italic     7817e9e1af2befb343bad22e7c6cf79fbf70ed933136d9a392338baedc2e6b18
umsch UMSCH_IB.woff2 bolditalic a5a9c6d53ba2d1dca59f3f8bda35f444f0edeea7938771d6bd674ca1c05b394f
# The card's assets, for the side-by-side card.
# hierojax.js asks for /NewGardiner.woff2 at the server root, so these live at lab/ root.
cp "$PUB/paper_fff.jpg" "$PUB/binding_dark2.png" ../vendor/NewGardiner.woff2 ../vendor/hierojax.js .
cp ../vendor/hierojax.css hierojax.css

[[ $fail -eq 0 ]] || { echo "some fonts failed (see above); the rest are ready" >&2; exit 1; }
echo "done"
