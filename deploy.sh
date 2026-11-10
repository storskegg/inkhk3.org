#!/usr/bin/env bash
# Build the site and publish dist/ to S3, then invalidate CloudFront.
#   ./deploy.sh          build + dry run only (nothing is changed in AWS)
#   ./deploy.sh --live   build + upload + CloudFront invalidation + cleanup
# Order matters: upload everything (no deletes, index.html last), invalidate and
# wait, and only then delete stale objects, so a page that is still cached never
# points at assets that are gone.
set -euo pipefail

BUCKET="static-site-inkhk3-org"
ALIAS="inkhk3.org"
SHORT_CACHE="public, max-age=300"
IMMUTABLE_CACHE="public, max-age=31536000, immutable"
MAX_INVALIDATION_PATHS=20
# Hashed index-*.js/css objects uploaded within this many seconds are kept, so
# the previous deploy's pair survives for pages that still reference it.
KEEP_HASHED_SECONDS=86400

LIVE=0
case "${1:-}" in
  "") ;;
  --live) LIVE=1 ;;
  *) echo "usage: $0 [--live]" >&2; exit 2 ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"

die() { echo "error: $*" >&2; exit 1; }

# --- node 26.x -------------------------------------------------------------
# On macOS the node must also be a native arm64 build (not x64 under Rosetta).
node_ok() {
  command -v node >/dev/null 2>&1 && [[ "$(node -v)" == v26.* ]] || return 1
  [[ "$(uname -s)" != Darwin || "$(node -p process.arch)" == arm64 ]]
}

if ! node_ok; then
  echo "node 26.x not active (found: $(node -v 2>/dev/null || echo none)); trying nvm..."
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    set +u
    # shellcheck source=/dev/null
    source "$HOME/.nvm/nvm.sh"
    nvm use || true
    set -u
  fi
  node_ok || die "an arm64 node 26.x is required (see .nvmrc); found $(node -v 2>/dev/null || echo none), arch $(node -p process.arch 2>/dev/null || echo unknown). On macOS node must be a native arm64 build: open an arm64 shell ('uname -m' prints arm64) and run 'nvm install 26'; nvm installs an arm64 Node there."
fi
echo "using node $(node -v)"

# --- aws -------------------------------------------------------------------
command -v aws >/dev/null 2>&1 || die "aws CLI not found; install it first."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  die "not authenticated to AWS. Run 'aws login' and retry."
fi

# --- build -----------------------------------------------------------------
if [[ ! -d node_modules || ! -f node_modules/.package-lock.json \
      || package-lock.json -nt node_modules/.package-lock.json ]]; then
  npm ci
fi
npm run build
[[ -f dist/index.html ]] || die "dist/index.html missing after build"

# Subresource Integrity: every script/stylesheet in dist/ must carry a hash that matches the bytes about to be
# uploaded (the build writes them in `postbuild`; this re-checks, changes nothing). Before any upload.
node bin/sri.mjs --check || die "SRI check failed; nothing was uploaded."

# The local font lab (lab/, `npm run lab`) must never reach the bucket: it holds downloaded font
# files whose web licences are not all cleared. Abort if anything lab-like is in dist/.
lab_hits="$(find dist \( -iname lab -o -path '*/lab/*' \) -print | head -n 5)"
[[ -z "$lab_hits" ]] || die "dist/ contains lab files, refusing to upload:
$lab_hits"

# --- upload (no deletes) -----------------------------------------------------
# aws s3 sync guesses content types from file extensions and has no per-file
# header rules, so dist/ is synced in disjoint passes. Each pass filters with
# --exclude/--include. No pass uses --delete: stale objects are removed only in
# the delete phase below, after the new files are live and CloudFront is
# invalidated. Passes run assets first and index.html (in the last pass) last,
# so the new HTML only goes up once everything it references is in the bucket.
# All output is collected in $LOG.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
MODE_ARGS=(--dryrun)
if [[ $LIVE -eq 1 ]]; then MODE_ARGS=(); fi

sync_pass() {
  aws s3 sync dist/ "s3://$BUCKET" --no-progress ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} "$@" | tee -a "$LOG"
}

echo
if [[ $LIVE -eq 1 ]]; then
  echo "== LIVE upload to s3://$BUCKET =="
else
  echo "== DRY RUN upload to s3://$BUCKET =="
fi

# 1. hashed, immutable assets
sync_pass --exclude '*' --include 'index-*.js' --include 'index-*.css' \
  --cache-control "$IMMUTABLE_CACHE"
# 2. woff2 fonts
sync_pass --exclude '*' --include '*.woff2' \
  --content-type font/woff2 --cache-control "$SHORT_CACHE"
# 3. web manifest
sync_pass --exclude '*' --include '*.webmanifest' \
  --content-type application/manifest+json --cache-control "$SHORT_CACHE"
# 4. TrueType fonts (lowercase .ttf and uppercase .TTF)
sync_pass --exclude '*' --include '*.ttf' --include '*.TTF' \
  --content-type font/ttf --cache-control "$SHORT_CACHE"
# 5. text files (the font licence text is UTF-8 and has a non-ASCII character), with an explicit charset
sync_pass --exclude '*' --include '*.txt' \
  --content-type 'text/plain; charset=utf-8' --cache-control "$SHORT_CACHE"
# 6. everything else (index.html, images, ...), short cache. Last on purpose.
sync_pass \
  --exclude 'index-*.js' --exclude 'index-*.css' --exclude '*.woff2' \
  --exclude '*.webmanifest' --exclude '*.ttf' --exclude '*.TTF' --exclude '*.txt' \
  --cache-control "$SHORT_CACHE"

# --- stale objects -----------------------------------------------------------
# Prints the keys to delete: bucket keys that are not in dist/, except hashed
# index-*.js/css modified within KEEP_HASHED_SECONDS (the previous deploy's
# pair). Why a time window and not "what the old index.html referenced": it
# needs no extra fetch or HTML parsing before the upload, and it also covers
# pages cached from an even older deploy if two deploys land in one day. The
# cost is that a deploy may leave up to a day's worth of hashed files, which the
# next deploy after that cleans up. S3 LastModified is always UTC, so
# the cutoff is built in UTC and compared as an ISO-8601 string. BSD date
# (macOS) and GNU date format epoch seconds differently, hence the fallback.
stale_keys() {
  local cutoff now
  now="$(date +%s)"
  cutoff="$(date -u -r $((now - KEEP_HASHED_SECONDS)) +%Y-%m-%dT%H:%M:%S 2>/dev/null \
    || date -u -d "@$((now - KEEP_HASHED_SECONDS))" +%Y-%m-%dT%H:%M:%S)"
  local dist_keys bucket_lines
  dist_keys="$(cd dist && find . -type f | sed 's#^\./##' | LC_ALL=C sort)"
  bucket_lines="$(aws s3api list-objects-v2 --bucket "$BUCKET" \
    --query 'Contents[].[Key,LastModified]' --output text | tr -d '\r')"
  local key modified
  while IFS=$'\t' read -r key modified; do
    [[ -n "$key" && "$key" != "None" ]] || continue
    if printf '%s\n' "$dist_keys" | grep -q -x -F -- "$key"; then continue; fi
    if [[ "$key" =~ ^index-[^/]*\.(js|css)$ && "${modified:0:19}" > "$cutoff" ]]; then
      echo "keep (recent hashed file): $key" >&2
      continue
    fi
    printf '%s\n' "$key"
  done <<< "$bucket_lines"
}

delete_stale() {
  local keys=() k
  while IFS= read -r k; do
    if [[ -n "$k" ]]; then keys+=("$k"); fi
  done < <(stale_keys)
  echo
  if [[ ${#keys[@]} -eq 0 ]]; then
    echo "no stale objects to delete."
    return 0
  fi
  if [[ $LIVE -eq 0 ]]; then
    echo "== would delete ${#keys[@]} stale object(s) (dry run) =="
    for k in "${keys[@]}"; do echo "would delete: s3://$BUCKET/$k"; done
    return 0
  fi
  echo "== deleting ${#keys[@]} stale object(s) =="
  for k in "${keys[@]}"; do aws s3 rm "s3://$BUCKET/$k"; done
}

if [[ $LIVE -eq 0 ]]; then
  delete_stale
  echo
  echo "Dry run only; nothing was changed. Re-run with --live to upload, invalidate and clean up."
  exit 0
fi

# --- CloudFront invalidation -------------------------------------------------
echo
echo "== CloudFront invalidation =="
DIST_ID=""
if command -v terraform >/dev/null 2>&1; then
  DIST_ID="$(terraform output -raw cloudfront_distribution_id 2>/dev/null || true)"
fi
if [[ ! "$DIST_ID" =~ ^[A-Z0-9]+$ ]]; then
  DIST_ID="$(aws cloudfront list-distributions \
    --query "DistributionList.Items[?Aliases.Items && contains(Aliases.Items, '$ALIAS')].Id | [0]" \
    --output text 2>/dev/null || true)"
fi
if [[ -z "$DIST_ID" || "$DIST_ID" == "None" ]]; then
  die "upload done, but could not find the CloudFront distribution for $ALIAS; invalidate manually. Stale objects were NOT deleted."
fi

# Changed keys come from the upload output: "upload: dist/KEY to s3://BUCKET/KEY".
# Progress lines end in \r, not \n, and can prefix an upload: line; turn every
# \r into a newline and drop everything before "upload:" so none hide.
changed_lines() {
  tr '\r' '\n' < "$1" | sed -n -E 's#^.*(upload|delete): #\1: #p'
}
extract_paths() {
  local lines
  lines="$(changed_lines "$1")"
  {
    printf '%s\n' "$lines" | sed -n -E "s#^upload: dist/(.*) to s3://$BUCKET/.*#/\1#p; s#^delete: s3://$BUCKET/(.*)#/\1#p"
    # index.html is also served at the root
    if printf '%s\n' "$lines" | grep -q -E "index\.html"; then echo "/"; fi
  } | sort -u
}

PATHS=()
while IFS= read -r p; do
  if [[ -n "$p" ]]; then PATHS+=("$p"); fi
done < <(extract_paths "$LOG")

if [[ ${#PATHS[@]} -eq 0 ]]; then
  echo "nothing uploaded; no invalidation needed."
else
  if [[ ${#PATHS[@]} -gt $MAX_INVALIDATION_PATHS ]]; then
    echo "${#PATHS[@]} changed paths (more than $MAX_INVALIDATION_PATHS); invalidating /*"
    PATHS=("/*")
  fi
  echo "invalidating: ${PATHS[*]}"
  INVALIDATION_ID="$(aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "${PATHS[@]}" \
    --query 'Invalidation.Id' --output text)"
  echo "invalidation $INVALIDATION_ID created; waiting for it to complete..."
  aws cloudfront wait invalidation-completed --distribution-id "$DIST_ID" --id "$INVALIDATION_ID"
  echo "invalidation $INVALIDATION_ID completed."
fi

# --- delete phase ------------------------------------------------------------
# Only now is it safe: the new index.html is live everywhere, so nothing but
# very old cached copies still point at the stale objects. Deleted keys are not
# invalidated: nothing references them.
delete_stale
echo "Deployed."
