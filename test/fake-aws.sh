#!/usr/bin/env bash
# Fake `aws` for test/deploy-order.sh. Logs each call to $FAKE_AWS_LOG and prints plausible output.
echo "aws $*" >> "$FAKE_AWS_LOG"
args=" $* "
ts() { date -u -r $(( $(date +%s) - $1 )) +%Y-%m-%dT%H:%M:%S+00:00 2>/dev/null || date -u -d "@$(( $(date +%s) - $1 ))" +%Y-%m-%dT%H:%M:%S+00:00; }
dry=""; [[ "$args" == *" --dryrun "* ]] && dry="(dryrun) "
case "$1 $2" in
  "sts get-caller-identity") echo '{"Account":"000000000000"}' ;;
  "s3 sync")
    cd dist || exit 1
    while IFS= read -r f; do
      f="${f#./}"
      case "$args" in
        *"--include index-*.js"*) [[ "$f" == index-*.js || "$f" == index-*.css ]] || continue ;;
        *"--include *.woff2"*)    [[ "$f" == *.woff2 ]] || continue ;;
        *"--include *.webmanifest"*) [[ "$f" == *.webmanifest ]] || continue ;;
        *"--include *.ttf"*)      [[ "$f" == *.ttf || "$f" == *.TTF ]] || continue ;;
        *"--include *.txt"*)      [[ "$f" == *.txt ]] || continue ;;
        *) [[ "$f" == index-*.js || "$f" == index-*.css || "$f" == *.woff2 || "$f" == *.webmanifest || "$f" == *.ttf || "$f" == *.TTF || "$f" == *.txt ]] && continue ;;
      esac
      printf '%supload: dist/%s to s3://static-site-inkhk3-org/%s\n' "$dry" "$f" "$f"
    done < <(find . -type f | LC_ALL=C sort)
    ;;
  "s3api list-objects-v2")
    # key <TAB> LastModified (text output); previous deploy's pair is 2h old, older pair 3 days old
    printf 'index.html\t%s\n' "$(ts 7200)"
    printf 'index-OLDER1.js\t%s\n' "$(ts 259200)"
    printf 'index-OLDER1.css\t%s\n' "$(ts 259200)"
    printf 'index-PREV1.js\t%s\n' "$(ts 7200)"
    printf 'index-PREV1.css\t%s\n' "$(ts 7200)"
    printf 'index-NEW1.js\t%s\n' "$(ts 7200)"
    printf 'style.css\t%s\n' "$(ts 900000)"
    printf 'old dir/stray file.png\t%s\n' "$(ts 900000)"
    ;;
  "cloudfront list-distributions") echo EFAKE123 ;;
  "cloudfront create-invalidation") echo I2FAKEINVALIDATION ;;
  "cloudfront wait") exit 0 ;;
  "s3 rm") echo "delete: ${3}" ;;
  "s3api delete-object") ;;
  *) echo "fake-aws: unhandled: $*" >&2 ;;
esac
