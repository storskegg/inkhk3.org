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

check "exactly one <script in index.html" '[[ "$(grep -oi "<script" "$DIST/index.html" | wc -l | tr -d " ")" == 1 ]]'
check "the script is the last element in <body>, with integrity and crossorigin" 'node -e "
  const t = require(\"fs\").readFileSync(process.argv[1], \"utf8\");
  const m = /<script\\b[^>]*><\\/script>\\s*<\\/body>/i.exec(t);
  process.exit(m && /\\sintegrity=\"sha384-/.test(m[0]) && /\\scrossorigin\\b/.test(m[0]) ? 0 : 1)" "$DIST/index.html"'
JS="$(find "$DIST" -iname "*.js" -o -iname "*.mjs")"
check "exactly one JS file in dist/, under 8 KB" '[[ -n "$JS" && "$(echo "$JS" | wc -l | tr -d " ")" == 1 && "$(wc -c < "$JS" | tr -d " ")" -lt 8192 ]]'
check "running the JS prints exactly src/credits.txt" '[[ -n "$JS" ]] && node -e "
  const {execFileSync} = require(\"child_process\"), fs = require(\"fs\");
  const out = execFileSync(process.execPath, [\"--input-type=module\"], {input: fs.readFileSync(process.argv[1]), stdio: [\"pipe\", \"pipe\", \"ignore\"]}).toString();
  process.exit(out === fs.readFileSync(\"src/credits.txt\", \"utf8\") + \"\\n\" ? 0 : 1)" "$JS"'
check "credits.txt's OFL body is byte-identical to public/InkHk3Serif-OFL.txt lines 39 on" 'sed -n "39,\$p" public/InkHk3Serif-OFL.txt | cmp -s - <(tail -n "$(sed -n "39,\$p" public/InkHk3Serif-OFL.txt | wc -l)" src/credits.txt)'
check "no NewGardiner or Hieroglyphic in index.html or the css" '! grep -il -e NewGardiner -e Hieroglyphic "$DIST/index.html" "$DIST"/*.css'
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
check "the built css has a .hierojax ::selection rule with a transparent colour" 'grep -Eqh "\.hierojax ::selection\{[^}]*color:transparent" "$DIST"/index-*.css'
exit $fail
