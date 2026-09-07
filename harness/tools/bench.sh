#!/bin/zsh
# OpenMW benchmark runner.
#   bench.sh <label> [-s overlay.cfg]... [-n repeats] [-H hold_seconds] [station ...]
# Each station is a separate openmw launch straight into its start cell; the Lua driver mod
# pins weather/time/camera. Per-frame stats are captured for the trailing HOLD seconds and
# a window screenshot is taken on the first repeat. With -n, each station runs N times and the
# per-metric median is written as <station>-summary.json (per-run files are kept as -r<k>).
# Multiple -s overlays are merged (later wins). Results land in results/<date>-<sha>-<label>/.
set -u
R=${R:-/Users/patricktodd/Desktop/Personal/OpenMW-rework}
SRC=${SRC:-$R/openmw}                                   # source tree the label sha is taken from
B=${B:-$SRC/build/OpenMW.app/Contents/MacOS/openmw}      # engine binary; override to bench another build
H=$R/harness
label=${1:?usage: bench.sh <label> [-s overlay.cfg]... [-n repeats] [-H hold] [station...]}; shift
overlays=(); HOLD=30; LOAD=14; WARM=10; REPEATS=1
while getopts "s:H:n:" opt; do case $opt in s) overlays+=("$OPTARG");; H) HOLD=$OPTARG;; n) REPEATS=$OPTARG;; esac; done
shift $((OPTIND-1))
# A stray engine (e.g. left over from a debugger session) would compete for CPU/GPU and could be the
# window we screenshot, so refuse to measure next to one.
if pgrep -x openmw >/dev/null; then
  echo "bench.sh: an openmw process is already running; kill it first:"; pgrep -xl openmw; exit 1
fi

typeset -A START
START=(seyda "Seyda Neen" balmora "Balmora" vivec "Vivec, Arena" aldruhn "Ald-ruhn" grazelands "Grazelands Region" interior "Vivec, Foreign Quarter Lower Waistworks" route "Bitter Coast Region" sky "Pelagiad" ui "Balmora, Guild of Mages")
stations=("$@"); [[ ${#stations} -eq 0 ]] && stations=(seyda balmora vivec aldruhn grazelands interior route)

sha=$(git -C $SRC rev-parse --short HEAD 2>/dev/null || echo nogit)
run=$H/results/$(date +%Y%m%d-%H%M)-$sha-$label
mkdir -p $run/overlay
# Overlay config: enables the bench mod, plus merged settings overrides for this run.
printf 'data="%s/mod"\ncontent=bench.omwscripts\n' "$H" > $run/overlay/openmw.cfg
[[ ${#overlays} -gt 0 ]] && python3 $H/tools/mergecfg.py "${overlays[@]}" > $run/overlay/settings.cfg
[[ -x $H/tools/winbounds ]] || swiftc -O -o $H/tools/winbounds $H/tools/winbounds.swift 2>/dev/null

cat > $run/meta.json <<EOF
{"label":"$label","sha":"$sha","date":"$(date -Iseconds)","overlays":"${overlays[*]:-none}","repeats":$REPEATS,"hold":$HOLD,"load":$LOAD,"warm":$WARM,"stations":"${stations[*]}","machine":"$(sysctl -n machdep.cpu.brand_string)"}
EOF
echo "run: $run"

for s in $stations; do
  cell=${START[$s]}
  [[ -z $cell ]] && { echo "unknown station $s"; continue; }
  echo "== $s  (--start \"$cell\") x$REPEATS"
  summaries=()
  for k in $(seq 1 $REPEATS); do
    stats=$run/$s-r$k-stats.txt
    OPENMW_OSG_STATS_FILE=$stats OPENMW_OSG_STATS_LIST="times;resource" \
      "$B" --config "$H/config" --config "$run/overlay" --skip-menu --start "$cell" --no-sound > $run/$s-r$k-stdout.txt 2>&1 &
    pid=$!
    sleep $((LOAD + WARM + HOLD - 3))
    if [[ $k -eq 1 ]]; then
      if win=$($H/tools/winbounds $pid 2>/dev/null); then
        screencapture -x -o -l ${win%% *} $run/$s.png
      else
        echo "   (no window bounds; screenshot skipped)"
      fi
    fi
    sleep 3
    kill $pid 2>/dev/null; wait $pid 2>/dev/null; rc=$?
    # 143 = killed by our SIGTERM before it quit on its own; anything else after "Quitting peacefully" is an exit crash.
    [[ $rc -ne 0 && $rc -ne 143 ]] && echo "   exit status $rc"
    echo "$rc" > $run/$s-r$k-exitstatus.txt
    [[ -f $run/overlay/openmw.log ]] && cp $run/overlay/openmw.log $run/$s-r$k-openmw.log
    if [[ $k -eq 1 ]]; then grep -h "BENCH" $run/$s-r1-openmw.log 2>/dev/null | grep -v "route hop" | sed 's/^\[[^]]*\] [^:]*:\t/   /' | head -3; fi
    python3 $H/tools/collect.py $stats --last-seconds $HOLD --json $run/$s-r$k-summary.json --quiet && summaries+=($run/$s-r$k-summary.json)
    python3 - $run/$s-r$k-summary.json $k <<'EOF'
import json,sys; s=json.load(open(sys.argv[1])); f=s["fps"]; h=s.get("hitches",{})
print(f"   r{sys.argv[2]}: fps {f['mean']:.1f} (1%-low {f['p1_low']:.1f})  frame p50 {s['frame ms']['p50']:.2f} p99 {s['frame ms']['p99']:.2f} max {s['frame ms']['max']:.1f} ms  draw {s['draw ms']['p50']:.2f}  cull {s['cull ms']['p50']:.2f}  gpu {s.get('gpu ms',{}).get('p50',0):.2f}  hitches {h.get('count',0)} ({h.get('stall_ms',0):.0f} ms)")
EOF
  done
  [[ ${#summaries} -gt 0 ]] && python3 $H/tools/median.py $run/$s-summary.json "${summaries[@]}"
  [[ $REPEATS -gt 1 ]] && python3 - $run/$s-summary.json <<'EOF'
import json,sys; s=json.load(open(sys.argv[1])); f=s["fps"]; h=s.get("hitches",{})
print(f"   median: fps {f['mean']:.1f} (1%-low {f['p1_low']:.1f})  frame p50 {s['frame ms']['p50']:.2f} p99 {s['frame ms']['p99']:.2f}  draw {s['draw ms']['p50']:.2f}  hitches {h.get('count',0)} ({h.get('stall_ms',0):.0f} ms)")
EOF
done
echo "done: $run"
