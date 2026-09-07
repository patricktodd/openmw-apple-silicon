#!/usr/bin/env python3
"""Compare two harness result directories station by station.

usage: compare.py results/<baseline> results/<candidate> [--threshold 5]
Prints a delta table of the key metrics; negative frame-time deltas are improvements.
"""
import sys, json, os, re, argparse

KEYS = [("fps", "mean", "fps mean", False), ("fps", "p1_low", "fps 1%low", False),
        ("frame ms", "p50", "frame p50", True), ("frame ms", "p99", "frame p99", True),
        ("draw ms", "p50", "draw p50", True), ("cull ms", "p50", "cull p50", True),
        ("gpu ms", "p50", "gpu p50", True),
        ("frame ms", "max", "frame max", True),
        ("hitches", "count", "hitches", True), ("hitches", "stall_ms", "stall ms", True)]

def load(d):
    out = {}
    for f in sorted(os.listdir(d)):
        if f.endswith("-summary.json") and not re.search(r"-r\d+-summary\.json$", f):
            out[f[:-len("-summary.json")]] = json.load(open(os.path.join(d, f)))
    return out

def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("baseline"); ap.add_argument("candidate")
    ap.add_argument("--threshold", type=float, default=5.0, help="flag deltas above this percent")
    a = ap.parse_args()
    b, c = load(a.baseline), load(a.candidate)
    print(f"baseline: {a.baseline}\ncandidate: {a.candidate}\n")
    for station in sorted(set(b) | set(c)):
        if station not in b or station not in c:
            print(f"{station}: only in {'baseline' if station in b else 'candidate'}"); continue
        print(f"== {station}")
        print(f"   {'metric':12} {'base':>9} {'cand':>9} {'delta':>8}")
        for grp, sub, label, lower_better in KEYS:
            try:
                bv, cv = b[station][grp][sub], c[station][grp][sub]
            except KeyError:
                continue
            pct = (cv - bv) / bv * 100 if bv else 0
            improved = (pct < 0) == lower_better
            flag = "" if abs(pct) < a.threshold else ("  better" if improved else "  WORSE")
            print(f"   {label:12} {bv:9.2f} {cv:9.2f} {pct:+7.1f}%{flag}")

if __name__ == "__main__":
    main()
