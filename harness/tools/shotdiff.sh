#!/bin/zsh
# Compare station screenshots between two result dirs with ImageMagick RMSE (0 = identical, 1 = fully different).
# usage: shotdiff.sh results/<baseline> results/<candidate> [threshold=0.02]
set -u
base=$1; cand=$2; thr=${3:-0.02}
mkdir -p "$cand/diff"
printf "%-12s %8s  %s\n" station rmse verdict
for b in "$base"/*.png; do
  s=$(basename "$b" .png)
  c="$cand/$s.png"
  [[ -f "$c" ]] || { printf "%-12s %8s  missing in candidate\n" "$s" "-"; continue; }
  # magick compare prints "<abs> (<normalized>)" on stderr
  r=$(magick compare -metric RMSE "$b" "$c" "$cand/diff/$s.png" 2>&1 | sed -E 's/.*\(([0-9.e-]+)\).*/\1/')
  verdict=ok
  awk -v r="$r" -v t="$thr" 'BEGIN{exit !(r>t)}' && verdict="DIFF (see $cand/diff/$s.png)"
  printf "%-12s %8s  %s\n" "$s" "$r" "$verdict"
done
