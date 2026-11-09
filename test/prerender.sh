#!/usr/bin/env bash
# Checks dist/ (run `npm run build` first) for the pre-rendered hieroglyph lines: no script, no JS, no hieroglyph
# font, two filled spans with the right text, and their bytes identical to src/index.html's.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$HOME/.nvm/versions/node/v24.12.0/bin:$PATH"
DIST="${1:-dist}"
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
[[ -f "$DIST/index.html" ]] || { echo "no $DIST/index.html; run npm run build first" >&2; exit 1; }

TITLE='𓏌𓐰𓎡𓎛𓂓𓐰𓏝𓀭'
AMDUAT='𓐍𓐱𓊪𓐰𓂋𓈖𓌃𓅱𓏛𓐰𓏥𓍿𓐰𓈖𓐰𓏥𓊏𓐰𓊪𓇳𓈖𓎛𓎡𓄿𓅱𓏛𓐰𓏥𓍿𓐰𓈖𓐰𓏥'

check "no <script in index.html" '! grep -qi "<script" "$DIST/index.html"'
check "no *.js in dist/" '[[ -z "$(find "$DIST" -iname "*.js" -o -iname "*.mjs")" ]]'
check "no NewGardiner or Hieroglyphic in any text file" '! grep -rIil -e NewGardiner -e Hieroglyphic "$DIST"'
check "no NewGardiner file" '[[ -z "$(find "$DIST" -iname "*gardiner*")" ]]'

# block extraction: each <span class="hierojax" ...> up to its </svg></span> (the filled span also has inner spans)
blocks() {
  node -e '
    const t = require("fs").readFileSync(process.argv[1], "utf8");
    const re = /<span class="hierojax"[^>]*>[\s\S]*?<\/svg><\/span>/g;
    process.stdout.write(JSON.stringify([...t.matchAll(re)].map((m) => m[0])));
  ' "$1"
}
count() { node -e 'console.log(JSON.parse(process.argv[1]).length)' "$1"; }
B_DIST="$(blocks "$DIST/index.html")"; B_SRC="$(blocks src/index.html)"
check "exactly two hierojax spans in dist" '[[ "$(count "$B_DIST")" == 2 ]]'
check "both opening tags are exactly <span class=\"hierojax\" data-type=\"svg\" data-standalone=\"true\">" '[[ "$(grep -o "<span class=\"hierojax\" data-type=\"svg\" data-standalone=\"true\">" "$DIST/index.html" | wc -l | tr -d " ")" == 2 && "$(grep -o "<span class=\"hierojax\"" "$DIST/index.html" | wc -l | tr -d " ")" == 2 ]]'
check "each span contains exactly one <svg" 'node -e "const b=JSON.parse(process.argv[1]); process.exit(b.length===2 && b.every(x=>(x.match(/<svg\\b/g)||[]).length===1)?0:1)" "$B_DIST"'
dt() { node -e 'const b=JSON.parse(process.argv[1]); const m=/data-text="([^"]*)"/.exec(b[+process.argv[2]]||""); process.stdout.write(m?m[1]:"")' "$B_DIST" "$1"; }
check "title data-text is the title's Unicode" '[[ "$(dt 0)" == "$TITLE" ]]'
check "Amduat data-text is the Amduat line's Unicode" '[[ "$(dt 1)" == "$AMDUAT" ]]'
check "the blocks in dist are byte-identical to src/index.html's" '[[ "$B_DIST" == "$B_SRC" && "$(count "$B_SRC")" == 2 ]]'
exit $fail
