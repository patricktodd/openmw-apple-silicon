#!/bin/zsh
# Run bench.sh once per overlay config and print comparisons against a baseline run dir.
#   sweep.sh <baseline-results-dir> overlay1.cfg [overlay2.cfg ...]
set -u
H=${H:-$(cd "$(dirname "$0")/.." && pwd)}
base=${1:?usage: sweep.sh <baseline-dir> overlay.cfg...}; shift
for ov in "$@"; do
  label=$(basename "$ov" .cfg)
  echo "######## $label"
  out=$($H/tools/bench.sh "$label" -s "$ov" 2>&1 | grep -v "^   \[")
  echo "$out"
  run=$(echo "$out" | awk '/^done: /{print $2}')
  [[ -n $run ]] && python3 $H/tools/compare.py "$base" "$run"
done
