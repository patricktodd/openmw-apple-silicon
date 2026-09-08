# The patch series

Two repositories carry the code. In both, compatibility stays the default and every change is gated on the running profile, so a compatibility build behaves as before.

## OpenMW — branch `core-profile`, three commits over master `8c09e3851` (2026-09-07)

| commit | what |
|---|---|
| `42f4e1b1f` | The `[Video] opengl profile` setting; `SceneUtil::CoreProfileOperation` (attribute aliasing, matrix uniforms, mode validity, version-implied feature flags); the SDL 3.3 core context request; the viewer created with `NO_LIGHT`; settings documentation and changelog entry. |
| `3b89fbc93` | `ShaderManager`'s profile-neutral vocabulary (including the `@gpuShader4Extension` token) and the core-profile fragment output declaration; the MyGUI render manager on a VAO/VBO path with R/RG textures. |
| `33e17f6dd` | The scene: every shader in the vocabulary, `gl_ClipDistance` clip planes, quads to triangles, alpha/luminance/intensity images expanded on load and in-memory alpha images as R8 with a swizzle, own-VAO drawables, the NIF particle system dispatching its overall-bound normal as a constant attribute instead of a one-element client array (invalid inside a VAO), `.omwfx` techniques floored to GLSL 330 on core, the stats overlays. Three small pieces are not gated on the profile and apply to both: `water.frag` derives the camera and sun positions from `osg_ViewMatrixInverse` and a `nodePosition` uniform instead of `gl_ModelViewMatrixInverse` (which OSG's attribute aliasing has no replacement for); the viewer is created with `NO_LIGHT` so the loading-screen frames skip the fixed-function headlight the renderer disables later anyway; and the profiler overlay drops the fixed-function light and material of osgViewer's HUD camera. |

72 files, about 980 lines added. Each commit builds on its own and references Feature #5251. The C++ follows the project's naming, include-grouping and Doxygen conventions and passes its clang-format configuration; the branch was also given a second, line-by-line review pass against those conventions before submission (LLM-assisted, like the rest). This branch is the reference tree; it is offered upstream in pieces. Once merged, the only user-visible change is one setting, off by default everywhere (on macOS it selects the 4.1 core context); the three ungated changes listed above produce the same output on the compatibility profile (RESULTS.md, last section). OpenMW-CS reads the same settings file but never enters core mode: the flag the components consult is set only by the engine.

## OpenSceneGraph — branch `core-profile-fork-v2`, five commits over OpenMW/osg `3.6`

The two bug fixes (bold below) are also on their own branches as [OpenMW/osg#50](https://github.com/OpenMW/osg/pull/50) and [OpenMW/osg#51](https://github.com/OpenMW/osg/pull/51).

OpenMW builds its OpenSceneGraph fork with `OPENGL_PROFILE=GL2`, and a GL2 build has no runtime notion of a core context. These commits give it one: `GLExtensions::isCoreProfile` is read once from `GL_CONTEXT_PROFILE_MASK` and cached on the `osg::State`, and every behavioural change is gated on it (or, for osgText, on the `SHADER_GL3` display-settings hint), so a stock GL2 build on a compatibility context is unchanged.

| commit | what |
|---|---|
| `168788c89a` | **`GLExtensions` static-destruction crash: upstream OSG's fix, backported.** `~GLExtensions` wrote into file-scope statics that can already be destroyed during `exit()`; any application whose `GLExtensions` outlives static destruction (every VAO user on a GL2 build) can hit it. Mainline OSG fixed this in 2019 (commit `97f955b2`, an `observer_ptr` to the registries) and OpenMW's `3.6` branch predates it; this is that commit cherry-picked, replacing an equivalent fix of our own after review on the pull request. Independent of the core-profile work. |
| `3ae795bf3e` | **`VertexArrayState::dirty()` forces every active array to be dispatched again.** A bug in stock OSG's VAO path that any application can hit: when one of a drawable's arrays is replaced, the others sharing its buffer object move when the buffer is recompiled, but `setArray()` skipped them as unchanged and the VAO kept their old offsets. `Drawable::dirtyGLObjects()` already reaches `dirty()`; it now invalidates the recorded modified count of every active array (nine lines). Replaces a first version that tracked offsets, after review on the pull request. |
| `c4a6a17d22` | Detect the context profile; skip the compiled-in `glMatrixMode`/`glLoadMatrix` calls and the `GL_MAX_TEXTURE_COORDS` query on core; accept VBO, PBO, VAO, texture swizzle and packed depth-stencil by GL version as well as extension string. Without this nothing renders. |
| `1c05a3ddb2` | The fixed-function attributes (`AlphaFunc`, `Material`, `LightModel`, `Light`, `Fog`, `TexEnv`, `TexEnvCombine`, `TexGen`, `ShadeModel`, `LineStipple`, `PolygonStipple`, `ColorMatrix`) become no-ops on core; `GL_CLAMP` mapped to `CLAMP_TO_EDGE` and no `GL_DEPTH_TEXTURE_MODE` there; osgParticle without quads or attribute push/pop. |
| `f5c1361c4a` | osgText glyph pages as R/RG under the GL3 shader hint; no compile-time warm-up draw on core (it draws with no program bound). |

The `VertexArrayState` fix applies to mainline OpenSceneGraph as well (mainline `master` still has the offset-only check at the time of writing); the `GLExtensions` one is mainline's own commit.

## Diagnostics

No diagnostic code ships with the series. The tracing used while finding the bugs above (draw-time VAO traces, native backtraces at GL error checkpoints, shader source dumps) was removed before submission; what remains usable on a stock build is OSG's own `OSG_GL_ERROR_CHECKING=ONCE_PER_ATTRIBUTE`, which is how the "zero GL errors" figures in RESULTS.md were taken.
