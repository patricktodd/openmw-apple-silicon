#!/usr/bin/env python3
"""Summarize an OpenMW OPENMW_OSG_STATS_FILE dump into per-metric percentiles.

usage: collect.py stats.txt [--skip N | --last-seconds S] [--json out.json] [--quiet]
  --skip N          ignore the first N frames (cell load / warm-up)
  --last-seconds S  analyse only the trailing S seconds of frames (by summed frame duration)
"""
import sys, json, statistics, argparse

METRICS = [
    ("Frame duration", "frame ms", 1000),
    ("Cull traversal time taken", "cull ms", 1000),
    ("Draw traversal time taken", "draw ms", 1000),
    ("GPU draw time taken", "gpu ms", 1000),
    ("Update traversal time taken", "update ms", 1000),
    ("mechanics_time_taken", "mechanics ms", 1000),
    ("physics_time_taken", "physics ms", 1000),
    ("physicsworker_time_taken", "physics-async ms", 1000),
    ("script_time_taken", "mwscript ms", 1000),
    ("lua_time_taken", "lua-worker ms", 1000),
    ("luasyncupdate_time_taken", "lua-sync ms", 1000),
    ("world_time_taken", "world ms", 1000),
    ("gui_time_taken", "gui ms", 1000),
    ("Lua UsedMemory", "lua mem MB", 1 / 1048576),
]

def parse(path):
    frames, cur = [], None
    with open(path) as f:
        for line in f:
            if line.startswith("Stats Viewer FrameNumber"):
                cur = {}
                frames.append(cur)
            elif line.startswith("Stats Camera"):
                continue
            elif cur is not None and line.startswith("    "):
                key, _, val = line.strip().rpartition("\t")
                try:
                    cur[key] = float(val)
                except ValueError:
                    pass
    return frames

def pct(vals, p):
    s = sorted(vals)
    k = min(len(s) - 1, int(round(p / 100 * (len(s) - 1))))
    return s[k]

def trailing(frames, seconds):
    acc, i = 0.0, len(frames)
    while i > 0 and acc < seconds:
        i -= 1
        acc += frames[i].get("Frame duration", 0.0)
    return frames[i:]

def summarize(frames):
    out = {"frames": len(frames)}
    for key, label, scale in METRICS:
        vals = [fr[key] * scale for fr in frames if key in fr]
        if not vals:
            continue
        out[label] = {
            "mean": statistics.fmean(vals),
            "p50": pct(vals, 50), "p95": pct(vals, 95), "p99": pct(vals, 99),
            "max": max(vals), "n": len(vals),
        }
    fd = [fr["Frame duration"] for fr in frames if "Frame duration" in fr and fr["Frame duration"] > 0]
    if fd:
        out["fps"] = {"mean": len(fd) / sum(fd), "p1_low": 1 / pct(fd, 99), "seconds": sum(fd)}
        # Hitches: frames far above the run's own typical frame (>= 2.5x p50, and at least 25 ms)
        # — where cell loads and GL compiles show up. stall_ms is the total time spent inside them.
        thr = max(0.025, 2.5 * pct(fd, 50))
        hitch = [d * 1000 for d in fd if d > thr]
        out["hitches"] = {"count": len(hitch), "stall_ms": sum(hitch), "threshold_ms": thr * 1000,
                          "per_minute": len(hitch) / (sum(fd) / 60.0)}
    return out

def print_table(s):
    fps = s.get("fps", {})
    h = s.get("hitches", {})
    print(f"frames: {s['frames']} ({fps.get('seconds', 0):.1f}s)   fps mean {fps.get('mean', 0):.1f}   1%-low {fps.get('p1_low', 0):.1f}"
          f"   hitches>20ms {h.get('count', 0)} ({h.get('stall_ms', 0):.0f} ms)")
    print(f"{'metric':18} {'mean':>8} {'p50':>8} {'p95':>8} {'p99':>8} {'max':>8}")
    for _, label, _ in METRICS:
        if label in s:
            m = s[label]
            print(f"{label:18} {m['mean']:8.3f} {m['p50']:8.3f} {m['p95']:8.3f} {m['p99']:8.3f} {m['max']:8.3f}")

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("stats")
    ap.add_argument("--skip", type=int, default=0)
    ap.add_argument("--last-seconds", type=float, default=0)
    ap.add_argument("--json")
    ap.add_argument("--quiet", action="store_true")
    a = ap.parse_args()
    frames = parse(a.stats)[a.skip:]
    if a.last_seconds:
        frames = trailing(frames, a.last_seconds)
    if not frames:
        print("no frames found", file=sys.stderr); sys.exit(1)
    s = summarize(frames)
    if a.json:
        json.dump(s, open(a.json, "w"), indent=1)
    if not a.quiet:
        print_table(s)

if __name__ == "__main__":
    main()
