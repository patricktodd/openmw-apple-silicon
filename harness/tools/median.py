#!/usr/bin/env python3
"""Merge several collect.py summaries (repeat runs of one station) into a per-metric median summary.
usage: median.py out.json run1-summary.json run2-summary.json ...
"""
import sys, json, statistics

out_path, inputs = sys.argv[1], sys.argv[2:]
runs = [json.load(open(p)) for p in inputs]
merged = {"runs": len(runs)}
for key in runs[0]:
    vals = [r[key] for r in runs if key in r]
    if isinstance(vals[0], dict):
        merged[key] = {}
        for sub in vals[0]:
            nums = [v[sub] for v in vals if isinstance(v.get(sub), (int, float))]
            if nums:
                merged[key][sub] = statistics.median(nums)
    elif isinstance(vals[0], (int, float)):
        merged[key] = statistics.median(vals)
json.dump(merged, open(out_path, "w"), indent=1)
