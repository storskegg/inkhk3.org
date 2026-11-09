#!/usr/bin/env bash
# Tests bin/sri.mjs on small fake builds in a temp dir (no vite, no network, no AWS). Needs node 24 (nvm path below).
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
export PATH="$HOME/.nvm/versions/node/v24.12.0/bin:$PATH"
SRI="$PWD/bin/sri.mjs"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
b64() { openssl dgst -sha384 -binary "$1" | openssl base64 -A; }
b64url8() { openssl dgst -sha384 -binary "$1" | openssl base64 -A | tr '+/' '-_' | cut -c1-8; }

fresh() {  # fresh DIR: a Vite-shaped build
  rm -rf "$1"; mkdir -p "$1"
  echo 'console.log(1)' > "$1/index-AAAA1111.js"
  echo 'body{color:red}' > "$1/index-BBBB2222.css"
  echo font > "$1/a.woff2"
  cat > "$1/index.html" <<'HTML'
<!DOCTYPE html>
<html><head>
	<link rel="preload" href="/a.woff2" as="font" type="font/woff2" crossorigin>
  <script type="module" crossorigin src="/index-AAAA1111.js"></script>
  <link rel="stylesheet" crossorigin href="/index-BBBB2222.css">
<!-- <script src="https://example.com/commented-out.js"></script> -->
</head><body><script>var s = '<script src="https://example.com/x.js"><\/script>';</script></body></html>
HTML
}

D="$TMP/a"; fresh "$D"
cp "$D/index.html" "$TMP/orig.html"
node "$SRI" "$D" > "$TMP/run1.out" 2>&1; rc=$?
check "build mode succeeds" '[[ $rc -eq 0 ]]'
# the old CSS name is gone; the new one is the first 8 base64url chars of the sha384 of the bytes
CSSF="$(cd "$D" && ls index-*.css)"
check "exactly one css, renamed (old name gone)" '[[ "$CSSF" != index-BBBB2222.css && $(ls "$D"/*.css | wc -l) -eq 1 ]]'
check "css name = index-<8 base64url chars of sha384 of its bytes>" '[[ "$CSSF" == "index-$(b64url8 "$D/$CSSF").css" ]]'
check "js integrity is the sha384 of the file" 'grep -q "src=\"/index-AAAA1111.js\" integrity=\"sha384-$(b64 "$D/index-AAAA1111.js")\"" "$D/index.html"'
check "css integrity is the sha384 of the renamed file; html points at the new name" 'grep -q "href=\"/$CSSF\" integrity=\"sha384-$(b64 "$D/$CSSF")\"" "$D/index.html"'
check "crossorigin kept on both" '[[ $(grep -c "crossorigin src=\"/index-AAAA\|crossorigin href=\"/index-" "$D/index.html") -eq 2 ]]'
check "font preload untouched (no integrity)" 'grep -q "^	<link rel=\"preload\" href=\"/a.woff2\" as=\"font\" type=\"font/woff2\" crossorigin>$" "$D/index.html"'
check "rest of the html byte-identical (diff after removing the additions)" '[[ "$(sed -e "s/ integrity=\"[^\"]*\"//" -e "s#/index-[A-Za-z0-9_-]*\.css#/index-BBBB2222.css#" "$D/index.html")" == "$(cat "$TMP/orig.html")" ]]'
node "$SRI" --check "$D" > /dev/null 2>&1; rc=$?
check "--check passes on the result" '[[ $rc -eq 0 ]]'
cp -R "$D" "$TMP/snap"
node "$SRI" "$D" > /dev/null 2>&1; rc=$?
check "rerun succeeds" '[[ $rc -eq 0 ]]'
check "rerun is idempotent (tree identical)" 'diff -r "$D" "$TMP/snap" > /dev/null'
node "$SRI" --check "$D" > /dev/null 2>&1; check "--check changes nothing" 'diff -r "$D" "$TMP/snap" > /dev/null'

# postcss-style change after a first run: new bytes under the old name -> new name, new hash
echo 'body{color:blue}' > "$D/$CSSF"
node "$SRI" --check "$D" > "$TMP/c.out" 2>&1; rc=$?
check "--check fails when the css bytes changed (hash and name)" '[[ $rc -ne 0 ]] && grep -q "integrity does not match" "$TMP/c.out" && grep -q "name does not follow its bytes" "$TMP/c.out"'
node "$SRI" "$D" > /dev/null 2>&1; node "$SRI" --check "$D" > /dev/null 2>&1; rc=$?
check "build mode re-hashes and renames after a change; --check passes again" '[[ $rc -eq 0 && $(ls "$D"/*.css | wc -l) -eq 1 && "$(cd "$D" && ls index-*.css)" != "$CSSF" ]]'

# tamper
fresh "$D"; node "$SRI" "$D" > /dev/null 2>&1
echo '//evil' >> "$D/index-AAAA1111.js"
node "$SRI" --check "$D" > "$TMP/c.out" 2>&1; rc=$?
check "--check fails on a tampered js" '[[ $rc -ne 0 ]] && grep -q "index-AAAA1111.js" "$TMP/c.out"'
fresh "$D"; node "$SRI" "$D" > /dev/null 2>&1
sed -i.bak 's/ integrity="sha384-[^"]*"//' "$D/index.html"; rm "$D/index.html.bak"
node "$SRI" --check "$D" > "$TMP/c.out" 2>&1; rc=$?
check "--check fails when a tag lacks its integrity" '[[ $rc -ne 0 ]] && grep -q "no integrity attribute" "$TMP/c.out"'

# unreferenced chunk
fresh "$D"; echo 'export default 1' > "$D/chunk-9999.js"
cp -R "$D" "$TMP/snap2"
node "$SRI" "$D" > "$TMP/c.out" 2>&1; rc=$?
check "an unreferenced js chunk fails the build" '[[ $rc -ne 0 ]] && grep -q "chunk-9999.js" "$TMP/c.out"'
check "a failed build writes nothing" 'diff -r "$D" "$TMP/snap2" > /dev/null'
fresh "$D"; echo 'a{}' > "$D/extra.css"
node "$SRI" "$D" > /dev/null 2>&1; rc=$?; check "an unreferenced css fails the build" '[[ $rc -ne 0 ]]'

# remote tags
fresh "$D"; sed -i.bak 's#src="/index-AAAA1111.js"#src="https://cdn.example.com/x.js"#' "$D/index.html"; rm "$D/index.html.bak"
node "$SRI" "$D" > "$TMP/c.out" 2>&1; rc=$?
check "a remote <script> fails the build" '[[ $rc -ne 0 ]] && grep -q "another origin" "$TMP/c.out"'
fresh "$D"; sed -i.bak 's#href="/index-BBBB2222.css"#href="//cdn.example.com/x.css"#' "$D/index.html"; rm "$D/index.html.bak"
node "$SRI" "$D" > "$TMP/c.out" 2>&1; rc=$?
check "a protocol-relative stylesheet fails the build" '[[ $rc -ne 0 ]] && grep -q "another origin" "$TMP/c.out"'

# missing file
fresh "$D"; rm "$D/index-AAAA1111.js"
node "$SRI" "$D" > "$TMP/c.out" 2>&1; rc=$?
check "a missing referenced file fails the build" '[[ $rc -ne 0 ]] && grep -q "missing" "$TMP/c.out"'

# several html files
fresh "$D"; mkdir "$D/sub"; sed 's#/index-#../index-#g' "$D/index.html" > "$D/sub/other.html"
node "$SRI" "$D" > /dev/null 2>&1; rc=$?
check "every html in dist/ is handled (also in a subfolder, relative URLs)" '[[ $rc -eq 0 && $(grep -c "integrity=" "$D/sub/other.html") -eq 2 ]] && node "$SRI" --check "$D" > /dev/null 2>&1'
check "both html files point at the one renamed css" '[[ $(grep -l "$(cd "$D" && ls index-*.css)" "$D/index.html" "$D/sub/other.html" | wc -l) -eq 2 ]]'

# the script tag at the end of <body> (as the built site has it)
fresh "$D"
python3 - "$D/index.html" <<'PY'
import sys; p=sys.argv[1]; s=open(p).read()
t='  <script type="module" crossorigin src="/index-AAAA1111.js"></script>\n'
open(p,'w').write(s.replace(t,'',1).replace('</body>','\n\t'+t.strip()+'\n</body>'))
PY
node "$SRI" "$D" > /dev/null 2>&1; rc=$?
check "a script at the end of <body> gets its integrity, in place" '[[ $rc -eq 0 ]] && grep -q "^	<script type=\"module\" crossorigin src=\"/index-AAAA1111.js\" integrity=\"sha384-$(b64 "$D/index-AAAA1111.js")\"></script>$" "$D/index.html" && node "$SRI" --check "$D" > /dev/null 2>&1'
echo '//evil' >> "$D/index-AAAA1111.js"
node "$SRI" --check "$D" > "$TMP/c.out" 2>&1; rc=$?
check "--check fails when the script in <body> was tampered with" '[[ $rc -ne 0 ]] && grep -q "integrity does not match" "$TMP/c.out"'

# a build with a stylesheet and no script (the site since the hieroglyphs are pre-drawn SVG)
rm -rf "$D"; mkdir -p "$D"
echo 'body{color:red}' > "$D/index-BBBB2222.css"
cat > "$D/index.html" <<'HTML'
<!DOCTYPE html>
<html><head>
	<link rel="stylesheet" crossorigin href="/index-BBBB2222.css">
</head><body><p>no script here</p></body></html>
HTML
node "$SRI" "$D" > /dev/null 2>&1; rc=$?
check "no script: build mode passes, the stylesheet is hashed" '[[ $rc -eq 0 ]] && grep -q "integrity=\"sha384-$(b64 "$D"/index-*.css)\"" "$D/index.html" && [[ $(ls "$D"/*.js 2>/dev/null | wc -l) -eq 0 ]]'
node "$SRI" --check "$D" > /dev/null 2>&1; rc=$?
check "no script: --check passes" '[[ $rc -eq 0 ]]'
exit $fail
