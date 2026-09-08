# Results

All numbers are from OpenMW master `def9412` (2026-09-05) and the core-profile branch on top of it, measured with the harness described in HARNESS.md on an Apple M5 Pro running macOS 26 ("OpenGL 4.1 Metal" for core, "OpenGL 2.1 Metal" for compatibility). Unless stated otherwise: median of three repeats, 30-second hold per station, default settings, GL error checking off. Run-to-run noise is about ±3–5 % on mean frame rate and ±10–20 % on the tails, so single-digit differences in the mean are not significant.

Two facts established on an older master while designing the port still hold and shaped the settings used here: extra worker threads did not help on this machine (and hurt continuous-motion traversal), so thread settings are left at their defaults; and a resolution ladder showed a CPU-side draw-submission floor of roughly 6–7 ms per frame that no GPU-side change moves.

## Upstream master `def9412` against the older base

211 upstream commits landed between the master used while designing the port (`f0c2823`) and this base, among them light-list state-set sharing, once-per-program sampler binding, parallel Lua garbage collection, cell-transition preload lead, and the removal of `osg::Material`/`osg::TexMat` from the renderer. Old base → new base:

| Station | Vanilla FPS | Vanilla cull p50 | Heavy FPS | Heavy draw p50 |
|---|---|---|---|---|
| Seyda Neen | 112 → 122 (+9 %) | 0.84 → 0.51 ms (−40 %) | 57 → 60 (+4 %) | 16.8 → 16.2 |
| Balmora | 118 → 118 | 0.77 → 0.77 | 53 → 52 | 18.4 → 18.6 |
| Vivec | 120 → 116 (−3 %) | 0.85 → 0.69 (−20 %) | 40 → **48 (+20 %)** | 24.8 → **20.6 (−17 %)** |
| Ald-ruhn | 129 → 144 (+12 %) | 0.48 → 0.39 (−18 %) | 39 → 41 (+6 %) | 25.2 → 23.9 |
| Grazelands | 241 → 223 (−8 %) | 0.19 → 0.20 | 102 → 92 (−9 %) | 8.9 → 9.0 |
| Interior | 118 → 115 | 0.72 → 0.72 | 91 → 89 | 10.0 → 10.1 |
| Route (glide) | 246 → 226 (−8 %) | — | 71 → 75 (+5 %), hitches 4 → 1 | 11.1 → 11.1 |

Light-list state-set sharing shows up as 20–40 % less cull time in towns and +20 % in the Vivec heavy scene; the preload lead removes most route hitches. Open terrain got about 8 % slower, plausibly from the LOD-range fix for active-grid object paging drawing more distant objects.

## Core profile versus compatibility, before the fixed-function attribute change

Same binary, `[Video] opengl profile = core` against the default. With `OSG_GL_ERROR_CHECKING=ONCE_PER_ATTRIBUTE` both profiles report zero errors on every station. Screenshot RMSE compares the first repeat of each.

| station | fps mean compat | fps mean core | 1%-low compat | 1%-low core | frame p99 compat | frame p99 core | draw p50 compat | draw p50 core | gpu p50 compat | gpu p50 core | RMSE |
|---|---|---|---|---|---|---|---|---|---|---|---|
| seyda | 121.1 | 119.9 | 99.9 | 99.5 | 10.01 | 10.05 | 7.30 | 7.55 | 6.67 | 6.95 | 1.94 % |
| balmora | 124.7 | 120.1 | 93.4 | 99.2 | 10.71 | 10.09 | 7.35 | 7.36 | 6.03 | 6.18 | 0.77 % |
| vivec | 110.8 | 113.1 | 79.8 | 82.4 | 12.53 | 12.13 | 8.65 | 8.45 | 8.30 | 8.05 | 0.04 % |
| aldruhn | 139.9 | 142.2 | 93.7 | 100.6 | 10.68 | 9.94 | 6.45 | 6.20 | 5.30 | 5.23 | 0.64 % |
| grazelands | 237.7 | 240.8 | 110.1 | 137.4 | 9.08 | 7.28 | 3.37 | 3.14 | 2.48 | 2.59 | 0.08 % |
| interior | 118.1 | 120.0 | 89.6 | 103.3 | 11.16 | 9.68 | 7.61 | 7.97 | 6.70 | 7.17 | 0.82 % |
| route | 233.4 | 218.4 | 74.4 | 76.1 | 13.45 | 13.15 | 3.14 | 3.52 | 3.02 | 3.32 | 17.61 % |
| sky | 711.0 | 783.6 | 202.7 | 226.0 | 4.93 | 4.42 | 0.94 | 0.73 | 0.65 | 0.46 | 0.01 % |

At this stage core matched compatibility on mean frame rate within noise and was already better on the tails (1 %-low +6 % to +25 %, p99 −6 % to −20 % on five of eight stations). The sky-only station, which is almost pure state-change and draw-call overhead, was +10 % with 22 % less draw time. The route station's screenshot difference is camera timing along the glide path, not rendering.

## Heavy profile, post-processing and render-to-texture

Single runs with a 6-second hold and GL error checking on (which costs both profiles about 5 % of frame rate).

| test | compat fps | core fps | GL errors (core) | RMSE |
|---|---|---|---|---|
| heavy profile, Seyda Neen (3 shadow maps with object/terrain/actor shadows, water shader + refraction + ripples, bloom + adjustments) | 59.5 | 58.6 | 0 | 1.0 % |
| HDR, the `debug` technique (normals/depth) and rain ripples, Seyda Neen | 71.8 | 81.2 | 0 | 6.7 % (wandering NPCs; the debug output itself is identical) |
| `ui` station: inventory with character preview, local and global map, over the Balmora Mages Guild | 234.9 | 233.6 | 0 | 0.05 % |

## Core profile versus compatibility, final

Same protocol as above, with the OpenSceneGraph fork now making fixed-function attributes no-ops on core. Each of those attributes had cost a `GL_INVALID_OPERATION` round-trip inside Apple's driver on every apply, which is where the difference from the earlier table comes from.

### Default settings

| station | fps compat | fps core | Δ | 1%-low compat | 1%-low core | p99 compat | p99 core | draw p50 compat | draw p50 core | RMSE |
|---|---|---|---|---|---|---|---|---|---|---|
| seyda | 132.5 | 120.3 | −9 % | 92.8 | 97.6 | 10.78 | 10.24 | 6.75 | 6.98 | 2.15 % |
| balmora | 120.3 | 120.3 | 0 % | 93.5 | 97.0 | 10.70 | 10.31 | 7.61 | 7.42 | 0.61 % |
| vivec | 116.6 | 119.6 | +3 % | 78.8 | 111.9 | 12.69 | 8.94 | 8.13 | 7.63 | 0.04 % |
| aldruhn | 135.4 | 163.5 | +21 % | 92.7 | 141.2 | 10.79 | 7.08 | 6.62 | 5.88 | 0.44 % |
| grazelands | 238.0 | 320.8 | +35 % | 109.3 | 267.5 | 9.14 | 3.74 | 3.33 | 2.81 | 0.08 % |
| interior | 113.3 | 132.9 | +17 % | 81.1 | 121.3 | 12.33 | 8.24 | 8.42 | 7.26 | 0.63 % |
| route | 229.4 | 250.8 | +9 % | 72.9 | 77.4 | 13.71 | 12.92 | 3.28 | 3.42 | 17.85 % |
| sky | 721.2 | 995.8 | +38 % | 207.1 | 607.2 | 4.83 | 1.65 | 0.93 | 0.76 | 0.06 % |
| ui | 744.1 | 971.4 | +31 % | 240.4 | 666.7 | 4.16 | 1.50 | 0.93 | 0.86 | 0.18 % |

### Heavy profile (24k view distance, 3 shadow maps, water shader + refraction, post-processing)

| station | fps compat | fps core | Δ | 1%-low compat | 1%-low core | p99 compat | p99 core | draw p50 compat | draw p50 core | RMSE |
|---|---|---|---|---|---|---|---|---|---|---|
| seyda | 62.6 | 69.3 | +11 % | 52.6 | 55.5 | 19.02 | 18.03 | 15.65 | 13.97 | 1.04 % |
| vivec | 47.5 | 51.2 | +8 % | 41.9 | 46.0 | 23.87 | 21.72 | 20.78 | 19.20 | 0.98 % |

Core leads on mean frame rate at six of the nine default stations (+9 % to +38 %), is within noise at Balmora and Vivec (0 % and +3 %) and behind at Seyda Neen (−9 %, within that station's spread — its compatibility figure ranged 121–133 across suites), and leads at both heavy stations. The tails are better at every station: 1 %-low +4 % to +190 % and p99 −4 % to −66 % (the small figures are Seyda Neen, Balmora and the route; the large ones the sky and `ui` stations). Draw-thread time is 6–18 % lower at six stations and within noise at Seyda Neen, Balmora and the route. Screenshots match on every station except the route, for the timing reason above. All nine stations exit with status 0 on both profiles (verified on the final tree with a separate single-repeat run, since the suites above predate the exit fix in the OpenSceneGraph fork).

## Compatibility profile against upstream master

The other half of "no behaviour change unless set": the branch on its default profile against an unmodified `def9412` build, same stations, first-repeat screenshots.

| station | RMSE |
|---|---|
| seyda | 1.0 % (wandering NPCs) |
| balmora | 1.9 % |
| vivec | 0.3 % |
| aldruhn | 1.8 % |
| grazelands | 0.7 % |
| interior | 0.8 % |
| route | 24 % (camera timing along the glide) |

The Vivec station has two discrete camera states about 5 % RMSE apart that the harness lands in at random, on upstream's own binary as much as on the branch (see HARNESS.md, "Noise"); the figure above compares two runs in the same state. Mean frame rate on the compatibility profile stays within the run-to-run spread: upstream → the two branch suites, Seyda Neen 122 → 121/132, Balmora 118 → 125/120, Vivec 116 → 111/117, Ald-ruhn 144 → 140/135, Grazelands 223 → 238/238, interior 115 → 118/113.

## The open upstream branches, run here

OpenMW's own fixed-function removal (#9239) has two open merge requests that overlap this work. Both were fetched from GitLab's merge-request refs and built with the same configuration as everything else here, on the compatibility context unless stated. Runs: `20260907-*-mr5541-*`, `-base5541-compat`, `-ours-compat-sameday`, `-mr5502-*`.

### !5541 "Remove all possible remaining FFP state" (8f482b21a on master aba2ba0ce)

Unconditional vertex attribute aliasing and matrix uniforms, shaders rewritten to `osg_Vertex`/`osg_ModelViewMatrix`. Under `OSG_GL_ERROR_CHECKING=ONCE_PER_ATTRIBUTE`: zero GL errors, no shader compile or link errors, all runs exit 0. Screenshots against this branch's compatibility runs: 0.02–0.6 % on the static stations (Seyda 2.5 %, NPC wander; route, camera timing).

Frame rate, four towns, median of three 30-second holds, all three columns run within the same hour:

| station | base `aba2ba0ce` | `core-profile` on compatibility | !5541 | !5541 vs base | draw p50 ms: base / ours / !5541 |
|---|---|---|---|---|---|
| Seyda Neen | 120 | 118 | 117 | −3 % | 7.66 / 7.86 / 7.94 |
| Balmora | 134 | 115 | 111 | −17 % (base run high; −4 % vs ours) | 6.85 / 7.99 / 8.41 |
| Vivec | 120 | 115 | 111 | −7 % | 8.04 / 8.20 / 8.35 |
| Ald-ruhn | 146 | 140 | 131 | −10 % | 6.28 / 6.31 / 6.64 |

Open terrain, interior, sky and the GUI station were flat in the full nine-station run (`-mr5541-compat`). On the town stations !5541 is 3–10 % below its own base and 1–7 % below the same-hour compatibility run of this branch, with draw-thread time up 0.1–0.4 ms. A plausible mechanism: with matrix uniforms OSG uploads four matrices per program per drawable through `glUniformMatrix4fv` instead of one `glLoadMatrix`, and towns have the highest draw counts. Absolute numbers drift by up to 10 % between days on this machine, which is why only same-hour columns are compared.

### !5502 "Draft: Add core profile alternative to osg::ClipPlane" (3da359f04 on master 566b4fc90)

`gl_ClipDistance` from `clipPlaneN` uniforms in a separately linked `lib/core/clip.glsl`, a discard fallback for GLES, and a legacy `gl_ClipVertex` unit for GLSL 120. Tested as !5502 merged onto the `core-profile` reference tree with !5502's clip-plane code taken in full and this branch's clip code dropped.

- Compatibility context (`clip_legacy.glsl` path): zero GL errors, exit 0, screenshots match (Vivec 0.3 %, Seyda 2.4 %).
- Core context (linked `clip.glsl`): segmentation fault at address 0 inside Apple's GLSL linker while loading the first cell, on the draw thread, during `osgUtil::GLObjectsVisitor` compilation of an osgParticle drawable's state set. Reproducible on every launch:

  ```
  GLEngine`glLinkProgramARB_Exec
  libGLProgrammability.dylib`ShLink
  libGLProgrammability.dylib`glpLinkProgram
  libGLProgrammability.dylib`glpASTMergePhase2
  libGLProgrammability.dylib`phase2AddDef / phase2ProcessRawCall / phase2Process (recursive)
  libGLProgrammability.dylib`phase2ProcessLValue
  libGLProgrammability.dylib`BitSetSetRangeEquals → BitSetSetSizeEquals   ← SIGSEGV, address 0x0
  ```

  This is the same failure the `core-profile` branch hit when its clip code was first written as a linked helper; the trigger is `gl_ClipDistance` written inside a function in a different compilation unit from the shader that calls it.
- Same tree with `applyClipPlanes` as a macro in `lib/core/vertex.h.glsl` (the `clipPlaneN` uniforms declared there through the same `@foreach`): zero GL errors, exit 0, screenshots match this branch's core runs (Vivec 0.3 %, Seyda 2.5 %). A plain function definition in that header does not link ("duplicate definition of function 'applyClipPlanes'"), since the header is included by several linked units (`-mr5502-core-inline`). The experiment hard-codes two planes and omits the GLES conditional branch. It also only works because on the core profile every shader is compiled as GLSL 330: `gl_ClipDistance` does not exist in `#version 120`, so a compatibility context that qualifies for native clip distances (GL 3.0+ on Windows or Linux, where the main shaders are still 120) needs the separately linked 330 unit, which is why !5502 links it. The two are not in conflict; the crash is only reachable on a core context.
