# OpenMW on Apple Silicon: the OpenGL core-profile port and its benchmark harness

This repository holds the working notes, tools and results of an effort to get [OpenMW](https://openmw.org) off Apple's legacy OpenGL 2.1 context on Apple Silicon: an OpenGL core-profile port of its renderer, and the harness used to measure it. The code changes themselves live on branches of the two upstream projects (see below); this repo is the harness, the measurements and the write-ups that justify them.

The work was done with heavy LLM assistance. Every change was verified by the harness in this repo — screenshot diffs against the unmodified renderer and frame-time statistics on fixed stations — and the survey documents record what broke, why, and how it was found, so the reasoning can be checked rather than trusted.

## What is here

| path | what |
|---|---|
| [CORE-PROFILE-SURVEY.md](CORE-PROFILE-SURVEY.md) | Design and findings of the port: why a core profile, what had to change and how, and the non-obvious bugs found on the way (two of them in OpenSceneGraph itself). |
| [HARNESS.md](HARNESS.md), `harness/` | The benchmark and regression harness: a Lua driver mod that pins weather/time/camera at fixed stations, a runner that captures per-frame statistics and screenshots, comparison tools, and `results/` with every run referenced in the write-ups. |
| [harness/RESULTS.md](harness/RESULTS.md) | The numbers: baselines, the heavy ("modded") profile, and core versus compatibility on every station. |
| [PATCHES.md](PATCHES.md) | Map of the upstream patch series for OpenMW and for OpenMW's OpenSceneGraph fork, with what each commit does and how it is meant to be reviewed. |

## The code

- **OpenMW**: branch `core-profile` (three commits over upstream master) adds `[Video] opengl profile = core`. Compatibility stays the default; core is opt-in. On macOS it is the only way past OpenGL 2.1. This branch is the reference tree; upstream is removing fixed-function state along its own path (#9239) and the work is being offered in pieces that fit it.
- **OpenSceneGraph** (OpenMW's fork, branch `3.6`): `fixes-3.6` carries two bug fixes that apply to any VAO user — a stale vertex-attribute offset in `VertexArrayState` ([OpenMW/osg#51](https://github.com/OpenMW/osg/pull/51)), and a use-after-free in `GLExtensions` during static destruction, for which mainline OSG's 2019 fix is backported ([OpenMW/osg#50](https://github.com/OpenMW/osg/pull/50)) — and `core-profile-fork-v2` adds, on top of them, what lets a GL2-profile OSG build run on a core context at runtime.

Result on one Apple Silicon Mac (RESULTS.md, "Core profile versus compatibility, final"): screenshots within 2 % RMSE of the compatibility renderer on every static station, zero GL errors under per-attribute checking, mean frame rate ahead of the compatibility profile on six of nine stations (+9…+38 %, level on two, behind on one) and on the heavy profile at both stations tried (+8…+11 %), with better frame-time tails at every station (1 %-low +4…+190 %).

## Reproducing

1. Build OpenMW from the `core-profile` branch against the patched OSG (build notes in HARNESS.md; the important one: replace OSG dylibs by rename, never in place — macOS kills processes whose mapped libraries change underneath them).
2. Point `harness/config/openmw.cfg` at a Morrowind installation (GOG/Steam; `innoextract` unpacks the GOG installer on macOS).
3. `harness/tools/bench.sh <label> [-s overlays/core.cfg] [-n 3] [stations…]` — one launch per station, per-frame stats and a screenshot each; `tools/compare.py` and `tools/shotdiff.sh` compare two runs.

## Status and what is next

The port runs end to end on macOS and is measured there; it has not been tried on Windows or Linux core contexts, on OpenCS, or with stereo rendering. It is being submitted upstream in pieces that fit OpenMW's own fixed-function removal (#9239); the patch map is PATCHES.md. What it does not change is the CPU-side draw-submission floor (roughly 6–7 ms per frame on this hardware); that would take a different rendering backend, for which the harness now provides a measured target.
