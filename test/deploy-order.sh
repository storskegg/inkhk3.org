#!/usr/bin/env bash
# Runs ./deploy.sh and ./deploy.sh --live against a fake aws (no AWS calls) and checks the
# order: all uploads, index.html last, invalidate + wait, then deletes; the previous hashed
# pair is kept; the dry run deletes nothing. Needs node 24 (nvm path below) for the build check.
set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
ROOT="$PWD"
HAD_NM=0; [[ -d node_modules ]] && HAD_NM=1
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP" "$ROOT/dist"; [[ $HAD_NM == 1 ]] || rm -rf "$ROOT/node_modules"' EXIT
mkdir -p "$TMP/bin"
cp test/fake-aws.sh "$TMP/bin/aws"
cat > "$TMP/bin/npm" <<'NPM'
#!/usr/bin/env bash
# fake npm: `ci` is a no-op, `run build` writes a small dist/ and runs the real bin/sri.mjs (the postbuild step)
if [[ "$1" == run ]]; then
  rm -rf dist; mkdir -p dist/fonts
  for f in index-NEW1.js index-NEW1.css favicon.png fonts/a.woff2 fonts/b.ttf site.webmanifest license.txt; do echo x > "dist/$f"; done
  cat > dist/index.html <<'HTML'
<!DOCTYPE html>
<html><head>
<link rel="preload" href="/fonts/a.woff2" as="font" type="font/woff2" crossorigin>
<script type="module" crossorigin src="/index-NEW1.js"></script>
<link rel="stylesheet" crossorigin href="/index-NEW1.css">
</head><body>x</body></html>
HTML
  node bin/sri.mjs || exit 1
  # FAKE_TAMPER=js|nohash: change a file after hashing / strip the hash, to test that deploy.sh refuses
  if [[ "${FAKE_TAMPER:-}" == js ]]; then echo tampered >> dist/index-NEW1.js; fi
  if [[ "${FAKE_TAMPER:-}" == nohash ]]; then sed -i.bak 's/ integrity="[^"]*"//' dist/index.html; rm dist/index.html.bak; fi
  # FAKE_LAB=dir|file: smuggle something lab-like into dist/ to test deploy.sh's guard
  if [[ "${FAKE_LAB:-}" == dir ]]; then mkdir -p dist/lab; echo x > dist/lab/fonts.json; fi
  if [[ "${FAKE_LAB:-}" == file ]]; then echo x > dist/fonts/lab; fi
fi
NPM
printf '#!/usr/bin/env bash\necho TFDIST1\n' > "$TMP/bin/terraform"
chmod +x "$TMP/bin/"*
mkdir -p node_modules; [[ $HAD_NM == 1 ]] || touch node_modules/.package-lock.json   # skip npm ci
export PATH="$TMP/bin:$HOME/.nvm/versions/node/v24.12.0/bin:$PATH"
export FAKE_AWS_LOG="$TMP/log"
fail=0
check() { if eval "$2"; then echo "ok   - $1"; else echo "FAIL - $1"; fail=1; fi; }
line() { grep -n -m1 -- "$1" "$FAKE_AWS_LOG" | cut -d: -f1; }
lastline() { grep -n -- "$1" "$FAKE_AWS_LOG" | tail -1 | cut -d: -f1; }

echo "=== dry run ==="; : > "$FAKE_AWS_LOG"
./deploy.sh | tee "$TMP/dry.out"
cat "$FAKE_AWS_LOG"
check "dry run issues no s3 rm / delete-object / invalidation" '! grep -q -E "s3 rm|delete-object|create-invalidation|wait" "$FAKE_AWS_LOG"'
check "dry run uses --dryrun on every sync" '[[ $(grep -c "s3 sync" "$FAKE_AWS_LOG") == $(grep -c "s3 sync.*--dryrun" "$FAKE_AWS_LOG") ]]'
check "dry run lists planned deletions" 'grep -q "would delete: s3://static-site-inkhk3-org/style.css" "$TMP/dry.out" && grep -q "would delete: s3://static-site-inkhk3-org/index-OLDER1.js" "$TMP/dry.out"'

echo; echo "=== live run ==="; : > "$FAKE_AWS_LOG"
./deploy.sh --live | tee "$TMP/live.out"
echo "--- call log ---"; cat "$FAKE_AWS_LOG"
check "no sync uses --delete" '! grep -q -- "--delete" "$FAKE_AWS_LOG"'
check "six sync passes" '[[ $(grep -c "s3 sync" "$FAKE_AWS_LOG") == 6 ]]'
check "index.html uploaded in the last pass, after other passes" '[[ $(grep -n "s3 sync" "$FAKE_AWS_LOG" | tail -1 | cut -d: -f1) == $(lastline "s3 sync") ]] && grep "s3 sync" "$FAKE_AWS_LOG" | tail -1 | grep -q -- "--cache-control public, max-age=300" && ! grep "s3 sync" "$FAKE_AWS_LOG" | tail -1 | grep -q -- "--include"'
check "a .txt goes through its own pass with a utf-8 charset, before the last pass" '[[ $(grep -c -- "--include \*.txt.*--content-type text/plain; charset=utf-8" "$FAKE_AWS_LOG") == 1 ]] && grep -q "upload: dist/license.txt" "$TMP/live.out" && [[ $(grep -n "upload: dist/license.txt" "$TMP/live.out" | cut -d: -f1) -lt $(grep -n "upload: dist/index.html" "$TMP/live.out" | cut -d: -f1) ]]'
check "index.html upload printed after index-NEW1.js and fonts" '[[ $(grep -n "upload: dist/index.html" "$TMP/live.out" | cut -d: -f1) -gt $(grep -n "upload: dist/fonts/b.ttf" "$TMP/live.out" | cut -d: -f1) && $(grep -n "upload: dist/index.html" "$TMP/live.out" | cut -d: -f1) -gt $(grep -n "upload: dist/index-NEW1.js" "$TMP/live.out" | cut -d: -f1) ]]'
check "invalidation then wait, both after last sync" '[[ $(line create-invalidation) -gt $(lastline "s3 sync") && $(line "cloudfront wait") -gt $(line create-invalidation) ]]'
check "all deletes after the wait" '[[ $(line "s3 rm") -gt $(line "cloudfront wait") ]]'
check "previous hashed pair kept" '! grep -q "PREV1" <(grep "s3 rm" "$FAKE_AWS_LOG")'
check "older hashed files deleted" 'grep -q "s3 rm s3://static-site-inkhk3-org/index-OLDER1.js" "$FAKE_AWS_LOG" && grep -q "s3 rm s3://static-site-inkhk3-org/index-OLDER1.css" "$FAKE_AWS_LOG"'
check "strays deleted" 'grep -q "s3 rm s3://static-site-inkhk3-org/style.css" "$FAKE_AWS_LOG" && grep -q "s3 rm s3://static-site-inkhk3-org/old dir/stray file.png" "$FAKE_AWS_LOG"'
check "files in dist/ not deleted" '! grep "s3 rm" "$FAKE_AWS_LOG" | grep -q -E "index.html|index-NEW1"'

echo; echo "=== SRI guard ==="
check "live run: dist/index.html carries integrity on the js and css (fake build ran bin/sri.mjs)" 'grep -c "integrity=\"sha384-" dist/index.html | grep -q "^2$"'
for kind in js nohash; do
  : > "$FAKE_AWS_LOG"
  rc=0; FAKE_TAMPER=$kind ./deploy.sh --live > "$TMP/sri-$kind.out" 2>&1 || rc=$?
  check "SRI ($kind): deploy.sh --live exits non-zero" '[[ $rc -ne 0 ]]'
  check "SRI ($kind): error says the SRI check failed" 'grep -q "SRI check failed" "$TMP/sri-$kind.out"'
  check "SRI ($kind): nothing uploaded, invalidated or deleted" '! grep -q -E "s3 sync|s3 rm|create-invalidation" "$FAKE_AWS_LOG"'
done

echo; echo "=== lab guard ==="
for kind in dir file; do
  : > "$FAKE_AWS_LOG"
  rc=0; FAKE_LAB=$kind ./deploy.sh --live > "$TMP/guard-$kind.out" 2>&1 || rc=$?
  check "guard ($kind named lab in dist/): deploy.sh --live exits non-zero" '[[ $rc -ne 0 ]]'
  check "guard ($kind): error message names the lab file" 'grep -q "dist/ contains lab files" "$TMP/guard-$kind.out" && grep -q "lab" "$TMP/guard-$kind.out"'
  check "guard ($kind): nothing uploaded, invalidated or deleted" '! grep -q -E "s3 sync|s3 rm|create-invalidation" "$FAKE_AWS_LOG"'
done
: > "$FAKE_AWS_LOG"
rc=0; ./deploy.sh > "$TMP/guard-dry.out" 2>&1 || rc=$?
check "guard: a dist/ without lab still deploys (dry run ok)" '[[ $rc -eq 0 ]]'
exit $fail
