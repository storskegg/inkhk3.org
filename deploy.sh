#!/usr/bin/env bash
# Build the site and publish dist/ to S3, then invalidate CloudFront.
#   ./deploy.sh          build + dry run only (nothing is changed in AWS)
#   ./deploy.sh --live   build + real sync + CloudFront invalidation
set -euo pipefail

BUCKET="static-site-inkhk3-org"
ALIAS="inkhk3.org"
SHORT_CACHE="public, max-age=300"
IMMUTABLE_CACHE="public, max-age=31536000, immutable"
MAX_INVALIDATION_PATHS=20

LIVE=0
case "${1:-}" in
  "") ;;
  --live) LIVE=1 ;;
  *) echo "usage: $0 [--live]" >&2; exit 2 ;;
esac

cd "$(dirname "${BASH_SOURCE[0]}")"

die() { echo "error: $*" >&2; exit 1; }

# --- node 24.x -------------------------------------------------------------
node_ok() { command -v node >/dev/null 2>&1 && [[ "$(node -v)" == v24.* ]]; }

if ! node_ok; then
  echo "node 24.x not active (found: $(node -v 2>/dev/null || echo none)); trying nvm..."
  if [[ -s "$HOME/.nvm/nvm.sh" ]]; then
    set +u
    # shellcheck source=/dev/null
    source "$HOME/.nvm/nvm.sh"
    nvm use || true
    set -u
  fi
  node_ok || die "node 24.x is required (see .nvmrc). Run 'nvm install && nvm use' and retry."
fi
echo "using node $(node -v)"

# --- aws -------------------------------------------------------------------
command -v aws >/dev/null 2>&1 || die "aws CLI not found; install it first."
if ! aws sts get-caller-identity >/dev/null 2>&1; then
  die "not authenticated to AWS. Run 'aws login' and retry."
fi

# --- build -----------------------------------------------------------------
[[ -d node_modules ]] || npm ci
npm run build
[[ -f dist/index.html ]] || die "dist/index.html missing after build"

# --- sync ------------------------------------------------------------------
# aws s3 sync guesses content types from file extensions and has no per-file
# header rules, so dist/ is synced in disjoint passes. Each pass filters with
# --exclude/--include, and --delete only applies within a pass's own filter, so
# nothing is deleted twice or missed. All output is collected in $LOG.
LOG="$(mktemp)"
trap 'rm -f "$LOG"' EXIT
MODE_ARGS=(--dryrun)
if [[ $LIVE -eq 1 ]]; then MODE_ARGS=(); fi

sync_pass() {
  aws s3 sync dist/ "s3://$BUCKET" --delete ${MODE_ARGS[@]+"${MODE_ARGS[@]}"} "$@" | tee -a "$LOG"
}

echo
if [[ $LIVE -eq 1 ]]; then
  echo "== LIVE sync to s3://$BUCKET =="
else
  echo "== DRY RUN sync to s3://$BUCKET =="
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
# 5. everything else (index.html, style.css, images, ...), short cache
sync_pass \
  --exclude 'index-*.js' --exclude 'index-*.css' --exclude '*.woff2' \
  --exclude '*.webmanifest' --exclude '*.ttf' --exclude '*.TTF' \
  --cache-control "$SHORT_CACHE"

if [[ $LIVE -eq 0 ]]; then
  echo
  echo "Dry run only; nothing was changed. Re-run with --live to upload and invalidate."
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
  die "sync done, but could not find the CloudFront distribution for $ALIAS; invalidate manually."
fi

# Changed keys come from the sync output:
#   "upload: dist/KEY to s3://BUCKET/KEY" and "delete: s3://BUCKET/KEY".
PATHS=()
while IFS= read -r p; do
  if [[ -n "$p" ]]; then PATHS+=("$p"); fi
done < <(
  {
    sed -n -E "s#^upload: dist/(.*) to s3://$BUCKET/.*#/\\1#p; s#^delete: s3://$BUCKET/(.*)#/\\1#p" "$LOG"
    # index.html is also served at the root
    if grep -q -E "^(upload|delete): .*index\\.html" "$LOG"; then echo "/"; fi
  } | sort -u
)

if [[ ${#PATHS[@]} -eq 0 ]]; then
  echo "nothing changed; no invalidation needed."
  exit 0
fi
if [[ ${#PATHS[@]} -gt $MAX_INVALIDATION_PATHS ]]; then
  echo "${#PATHS[@]} changed paths (more than $MAX_INVALIDATION_PATHS); invalidating /*"
  PATHS=("/*")
fi
echo "invalidating: ${PATHS[*]}"
aws cloudfront create-invalidation --distribution-id "$DIST_ID" --paths "${PATHS[@]}" \
  --query 'Invalidation.{Id:Id,Status:Status}' --output table
echo "Deployed."
