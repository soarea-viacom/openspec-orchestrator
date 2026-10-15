#!/usr/bin/env bash
# Runs tests/t-*.sh in parallel and sums their failures. Each file is
# self-contained (own temp dir, own stores; see tests/lib.sh), so the wall
# clock is the slowest file, not the sum. Select files by stem:
#   tests/run.sh 30-next 80-applying
# TESTS_SERIAL=1 runs them one after another with live output.
set -uo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

files=()
if [ $# -gt 0 ]; then for a in "$@"; do files+=("tests/t-$a.sh"); done
else files=(tests/t-*.sh); fi

OUT="$(mktemp -d)"; trap 'rm -rf "$OUT"' EXIT
fails=0 aborted=""
if [ -n "${TESTS_SERIAL:-}" ]; then
  for f in "${files[@]}"; do
    echo "== $f"
    bash "$f" | tee "$OUT/$(basename "$f").log"
    [ "${PIPESTATUS[0]}" -eq 0 ] || grep -q '^FAIL' "$OUT/$(basename "$f").log" || aborted="$aborted $f"
  done
else
  for f in "${files[@]}"; do
    { bash "$f" > "$OUT/$(basename "$f").log" 2>&1; echo $? > "$OUT/$(basename "$f").rc"; } &
  done
  wait
  for f in "${files[@]}"; do
    echo "== $f"; cat "$OUT/$(basename "$f").log"
    [ "$(cat "$OUT/$(basename "$f").rc")" -eq 0 ] || grep -q '^FAIL' "$OUT/$(basename "$f").log" || aborted="$aborted $f"
  done
fi
fails="$(cat "$OUT"/*.log | grep -c '^FAIL')"

echo
[ -z "$aborted" ] || { echo "aborted before finishing:$aborted"; fails=$((fails+1)); }
[ "$fails" -eq 0 ] && echo "all tests passed" || { echo "$fails test(s) failed"; exit 1; }
