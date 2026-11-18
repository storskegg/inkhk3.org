#!/usr/bin/env bash
# Checks dist/ (run `npm run build` first) for the pre-rendered hieroglyph lines: no script, no JS, no hieroglyph
# font, two filled spans with the right text, and their bytes identical to src/index.html's.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$HOME/.nvm/versions/node/v26.13.0/bin:$PATH"
DIST="${1:-dist}"
fail=0
TMPDIR_AUTH="$(mktemp)"; trap 'rm -f "$TMPDIR_AUTH"' EXIT
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
check "running the JS prints the version and copyright notice first, then exactly src/credits.txt" '[[ -n "$JS" ]] && node -e "
  const {execFileSync} = require(\"child_process\"), fs = require(\"fs\");
  const out = execFileSync(process.execPath, [\"--input-type=module\"], {input: fs.readFileSync(process.argv[1]), stdio: [\"pipe\", \"pipe\", \"ignore\"]}).toString();
  const v = JSON.parse(fs.readFileSync(\"package.json\", \"utf8\")).version;
  const want = \"inkhk3.org \" + v + \"\\nCopyright \\u00a9 2026 Fra. M.H.B.N.M. All rights reserved.\\n\" + fs.readFileSync(\"src/credits.txt\", \"utf8\") + \"\\n\";
  process.exit(out === want ? 0 : 1)" "$JS"'
check "package.json's version is YYYY.WW.PATCH" 'node -e "process.exit(/^20[0-9]{2}\\.[0-9]{2}\\.[0-9]+\$/.test(require(\"./package.json\").version) ? 0 : 1)"'
# Protected names: INKHK3_LEAK_NAMES (newline- or comma-separated) if set and non-empty, else .leak-names at the repo
# root (one per line; blank lines and # lines ignored). Never in the repo. No names at all is a failure, not a skip.
# The pen name (package.json's author) is public and is not protected.
if [[ -n "${INKHK3_LEAK_NAMES:-}" ]]; then LEAK_SRC="$INKHK3_LEAK_NAMES"; LEAK_SPLIT=1
elif [[ -f .leak-names ]]; then LEAK_SRC="$(cat .leak-names)"; LEAK_SPLIT=0
else LEAK_SRC=""; LEAK_SPLIT=0; fi
LEAK_SRC="$LEAK_SRC" LEAK_SPLIT="$LEAK_SPLIT" node -e '
  const split = process.env.LEAK_SPLIT === "1";
  const names = process.env.LEAK_SRC.split(split ? /[\n,]/ : /\n/).map((l) => l.trim()).filter((l) => l && !l.startsWith("#"));
  const words = names.flatMap((n) => [n, ...n.split(/[^\p{L}\p{N}]+/u)]).filter((w) => w.length > 0);
  process.stdout.write(words.join("\n"));' > "$TMPDIR_AUTH"
if [[ ! -s "$TMPDIR_AUTH" ]]; then
  echo "FAIL - no protected names: set INKHK3_LEAK_NAMES (names separated by newlines or commas) or create .leak-names at the repo root (one name per line; it is gitignored)"
fi
check "no protected name (whole, or any word of it) is in any file in dist/" '[[ -s "$TMPDIR_AUTH" ]] && ! grep -raiqF -f "$TMPDIR_AUTH" "$DIST"'
check "the built JS has no \"author\" key and no repository URL" '[[ -n "$JS" ]] && ! grep -qaF "\"author\"" "$JS" && ! grep -qaF "$(node -e "process.stdout.write(require(\"./package.json\").repository.url)")" "$JS"'
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
check "the built css has no ::selection rule" '! grep -q "::selection" "$DIST"/index-*.css'
exit $fail
