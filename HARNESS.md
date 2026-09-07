# Benchmark and regression harness

A small harness that makes renderer changes to OpenMW measurable and regression-safe: it launches the engine straight into fixed *stations* (a cell, a spot, a camera, pinned weather and time of day), records per-frame statistics for a hold period, takes a screenshot, and compares runs against each other by frame-time percentiles and screenshot difference. Everything in this repository's results tables was produced with it.

## Prerequisites

- An OpenMW build (the `core-profile` branch, or plain master for baselines) and, for the core profile, the patched OpenSceneGraph libraries described in PATCHES.md.
- A legal copy of Morrowind with the Tribunal and Bloodmoon expansions: `Morrowind.esm`, `Tribunal.esm`, `Bloodmoon.esm`, the `.bsa` archives and the `Data Files` tree. Any retail source works (GOG, Steam, disc); on macOS the GOG installer can be unpacked with `innoextract`. Point `harness/config/openmw.cfg`'s `data=` line at the `Data Files` directory. No game data is, or may be, included in this repository.
- macOS tools used by the runner: `screencapture` (system), `swiftc` (Xcode command line tools, to build `tools/winbounds`), ImageMagick's `magick` for `shotdiff.sh`, Python 3.

## Layout

| Path | Role |
|---|---|
| `config/` | Isolated OpenMW configuration: `openmw.cfg` (fallback values imported from `Morrowind.ini`, data path, content list), `settings.cfg` (1600×900 borderless window, vsync off, uncapped frame rate). All engine state written during a run (log, Lua storage, key bindings) stays under the run's overlay directory. |
| `mod/bench.omwscripts`, `mod/scripts/bench/*.lua` | The benchmark driver, a small Lua mod. The station is selected by the cell the engine is started in (`--start`); the driver pins weather and hour, freezes game time, teleports the player to a fixed spot and parks a static camera with the HUD hidden. The route station glides the player along a fixed path at constant speed to exercise cell streaming; the `ui` station opens the inventory and map windows. |
| `overlays/*.cfg` | Settings overrides layered on `config/` for a run: `core.cfg` (`opengl profile = core`), `heavy.cfg` (a settings-only stand-in for a heavily modded install: 24576 view distance, distant terrain, object paging, three shadow maps with object/terrain/actor shadows, water shader with refraction, post-processing, maximum actor processing range — roughly halves the frame rate in towns), thread-count and resolution variants. |
| `tools/bench.sh <label> [-s overlay.cfg]… [-n repeats] [-H hold] [station…]` | The runner: one engine launch per station (repeated `-n` times, with a per-metric median summary), overlays merged by `mergecfg.py`, per-frame statistics captured through `OPENMW_OSG_STATS_FILE`, a screenshot of the engine's own window on the first repeat, and the exit status of every run. Output goes to `results/<date>-<sha>-<label>/`. Refuses to start while another `openmw` process is running, since a stray engine competes for the GPU and can be the window that gets screenshotted. |
| `tools/sweep.sh <baseline-dir> overlay.cfg…` | Runs `bench.sh` once per overlay and prints `compare.py` deltas against a baseline. |
| `tools/collect.py stats.txt --last-seconds N` | Per-lane mean/p50/p95/p99 (frame, cull, draw, GPU, mechanics, physics, scripts, Lua) and frame-rate statistics for the trailing N seconds of a run. |
| `tools/median.py`, `tools/compare.py a b` | Median of repeats; station-by-station delta table between two runs, flagging changes over 5 %. |
| `tools/shotdiff.sh a b` | ImageMagick RMSE per station screenshot, with difference images written to `b/diff/`. |
| `tools/winbounds` | Swift helper returning the window id and bounds of the engine window for a given PID, for `screencapture -l`. Built on first use. |

## Stations

`seyda` (Seyda Neen, village), `balmora` (Odai bridges), `vivec` (Arena canton walkway), `aldruhn` (town from the south), `grazelands` (open terrain at maximum view distance), `interior` (Vivec Foreign Quarter Lower Waistworks corridor, with NPCs), `route` (continuous glide from Seyda Neen towards Balmora, cell streaming), `sky` (Pelagiad, camera pitched up: clouds and atmosphere), `ui` (Balmora Mages Guild with the inventory and map windows open: character preview and map render-to-texture).

## Running

```
harness/tools/bench.sh mylabel -s harness/overlays/core.cfg -n 3 seyda balmora interior
harness/tools/compare.py results/<baseline> results/<candidate>
harness/tools/shotdiff.sh results/<baseline> results/<candidate>
```

The runner's launch line, for reproducing a single station by hand:

```
OPENMW_OSG_STATS_FILE=<out> OPENMW_OSG_STATS_LIST="times;resource" \
  openmw --config harness/config --config <overlay-dir> --skip-menu --start "<cell>" --no-sound
```

`--new-game` must not be added: it overrides `--start` with the intro sequence.

Each run directory contains, per station and repeat: `-summary.json` (the digest the tables use), `-openmw.log`, `-exitstatus.txt` (0 = clean quit; 143 = still running when the runner sent SIGTERM; anything else after "Quitting peacefully" is a crash during shutdown), the first repeat's screenshot, and — locally, not in this repository — the raw per-frame `-stats.txt`.

## Diagnostics the runner passes through

Set these in front of `bench.sh`.

- `OSG_GL_ERROR_CHECKING=ONCE_PER_ATTRIBUTE` — OSG checks for GL errors after every state attribute and draw and names the attribute in the log. Costs roughly 5 % frame rate; every core-profile figure in RESULTS.md was first taken with this on and confirmed at zero errors.
- `OPENMW_DISABLE_CRASH_CATCHER=1` — let signals reach the process instead of OpenMW's crash catcher; needed under a debugger, and to see a real exit status from the runner.

Debugger notes that cost time to learn: under `lldb`, pass SIGTERM through with `process handle SIGTERM -s false -p true -n false` and use `-k` for on-crash commands; never put `continue` inside breakpoint commands (use `-G true`); `lldb` does not propagate `DYLD_INSERT_LIBRARIES`, so guard malloc (`/usr/lib/libgmalloc.dylib`) has to run without it — leave the crash catcher enabled in that case and read the backtrace it writes. Key presses (for the F3/F4 overlays) can be sent with `osascript -e 'tell application "System Events" to key code 99'` once the engine window is frontmost. Replace OSG dylibs by copying to a temporary name and renaming over the old file: overwriting a mapped, signed library in place makes macOS kill every later launch.

## Noise and how it is handled

Exteriors carry NPC schedule, AI wander and weather variance even with time frozen; interiors are the tightest comparison. The Vivec station settles into one of two camera positions a fraction of a pixel apart (the player's landing after the teleport), which shows up as a fixed 5 % screenshot RMSE between runs that landed differently — on any binary — while runs in the same state agree to 0.3 %; compare Vivec screenshots with that in mind. The sky station's clouds scroll with wall-clock time, so its screenshot depends on how long loading took: two runs with identical rendering can differ by about 5 % RMSE (same mean colour, cloud-shaped difference image), while runs that happen to line up agree to 0.05 %. Run-to-run noise on this setup is about ±3–5 % on mean frame rate and ±10–20 % on the tails, so decisions on small deltas use the median of three repeats and holds of at least 20 seconds to wash out cell-load spikes. The driver's "ready" mark is not frame-correlated with the statistics file, so `collect.py` analyses the trailing hold seconds of a run rather than a window after the mark.
