#!/usr/bin/env python3
"""Merge OpenMW settings overlay files (INI-style) — later files override earlier keys.
usage: mergecfg.py a.cfg [b.cfg ...] > merged.cfg
"""
import sys
from collections import OrderedDict

sections = OrderedDict()
for path in sys.argv[1:]:
    sec = None
    for raw in open(path):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            sec = line
            sections.setdefault(sec, OrderedDict())
        elif "=" in line and sec is not None:
            k, v = [p.strip() for p in line.split("=", 1)]
            sections[sec][k] = v
for sec, kv in sections.items():
    print(sec)
    for k, v in kv.items():
        print(f"{k} = {v}")
    print()
