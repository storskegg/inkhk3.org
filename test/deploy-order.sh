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
# fake npm: `ci` is a no-op, `run build` writes a small dist/
if [[ "$1" == run ]]; then
  rm -rf dist; mkdir -p dist/fonts
  for f in index.html index-NEW1.js index-NEW1.css favicon.png fonts/a.woff2 fonts/b.ttf site.webmanifest; do echo x > "dist/$f"; done
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
check "five sync passes" '[[ $(grep -c "s3 sync" "$FAKE_AWS_LOG") == 5 ]]'
check "index.html uploaded in the last pass, after other passes" '[[ $(grep -n "s3 sync" "$FAKE_AWS_LOG" | tail -1 | cut -d: -f1) == $(lastline "s3 sync") ]] && grep "s3 sync" "$FAKE_AWS_LOG" | tail -1 | grep -q -- "--cache-control public, max-age=300" && ! grep "s3 sync" "$FAKE_AWS_LOG" | tail -1 | grep -q -- "--include"'
check "index.html upload printed after index-NEW1.js and fonts" '[[ $(grep -n "upload: dist/index.html" "$TMP/live.out" | cut -d: -f1) -gt $(grep -n "upload: dist/fonts/b.ttf" "$TMP/live.out" | cut -d: -f1) && $(grep -n "upload: dist/index.html" "$TMP/live.out" | cut -d: -f1) -gt $(grep -n "upload: dist/index-NEW1.js" "$TMP/live.out" | cut -d: -f1) ]]'
check "invalidation then wait, both after last sync" '[[ $(line create-invalidation) -gt $(lastline "s3 sync") && $(line "cloudfront wait") -gt $(line create-invalidation) ]]'
check "all deletes after the wait" '[[ $(line "s3 rm") -gt $(line "cloudfront wait") ]]'
check "previous hashed pair kept" '! grep -q "PREV1" <(grep "s3 rm" "$FAKE_AWS_LOG")'
check "older hashed files deleted" 'grep -q "s3 rm s3://static-site-inkhk3-org/index-OLDER1.js" "$FAKE_AWS_LOG" && grep -q "s3 rm s3://static-site-inkhk3-org/index-OLDER1.css" "$FAKE_AWS_LOG"'
check "strays deleted" 'grep -q "s3 rm s3://static-site-inkhk3-org/style.css" "$FAKE_AWS_LOG" && grep -q "s3 rm s3://static-site-inkhk3-org/old dir/stray file.png" "$FAKE_AWS_LOG"'
check "files in dist/ not deleted" '! grep "s3 rm" "$FAKE_AWS_LOG" | grep -q -E "index.html|index-NEW1"'
exit $fail
