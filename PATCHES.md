# The patch series

Two repositories carry the code. In both, compatibility stays the default and every change is gated on the running profile, so a compatibility build behaves as before.

## OpenMW — branch `core-profile`, three commits over master `aaf769f51` (2026-09-08)

| commit | what |
|---|---|
| `a7387c542` | The `[Video] opengl profile` setting; `SceneUtil::CoreProfileOperation` (attribute aliasing, matrix uniforms, mode validity, version-implied feature flags); the SDL 3.3 core context request; the viewer created with `NO_LIGHT`; settings documentation and changelog entry. |
| `06718f312` | `ShaderManager`'s profile-neutral vocabulary (including the `@gpuShader4Extension` token) and the core-profile fragment output declaration; the MyGUI render manager on a VAO/VBO path with R/RG textures. |
| `94c915a44` | The scene: every shader in the vocabulary, `gl_ClipDistance` clip planes, quads to triangles, alpha/luminance/intensity images expanded on load and in-memory alpha images as R8 with a swizzle, own-VAO drawables, the NIF particle system dispatching its overall-bound normal as a constant attribute instead of a one-element client array (invalid inside a VAO), `.omwfx` techniques floored to GLSL 330 on core, the stats overlays. Three small pieces are not gated on the profile and apply to both: `water.frag` derives the camera and sun positions from `osg_ViewMatrixInverse` and a `nodePosition` uniform instead of `gl_ModelViewMatrixInverse` (which OSG's attribute aliasing has no replacement for); the viewer is created with `NO_LIGHT` so the loading-screen frames skip the fixed-function headlight the renderer disables later anyway; and the profiler overlay drops the fixed-function light and material of osgViewer's HUD camera. |

72 files, about 980 lines added. Each commit builds on its own and references Feature #5251. The C++ follows the project's naming, include-grouping and Doxygen conventions and passes its clang-format configuration; the branch was also given a second, line-by-line review pass against those conventions before submission (LLM-assisted, like the rest). This branch is the reference tree; it is offered upstream in pieces. Once merged, the only user-visible change is one setting, off by default everywhere (on macOS it selects the 4.1 core context); the three ungated changes listed above produce the same output on the compatibility profile (RESULTS.md, last section). OpenMW-CS reads the same settings file but never enters core mode: the flag the components consult is set only by the engine.

## OpenSceneGraph — branch `core-profile-fork-v2`, three commits over OpenMW/osg `3.6` (`b8d836d001`, 2026-09-10)

Two further fixes found during the port were merged into OpenMW/osg `3.6` on 2026-09-10 and are no longer on the branch: the `GLExtensions` static-destruction crash, as a backport of mainline's 2019 fix ([OpenMW/osg#50](https://github.com/OpenMW/osg/pull/50)), and the stale vertex-array-object pointers after a sibling array is replaced, fixed by having `VertexArrayState::dirty()` re-dispatch every active array ([OpenMW/osg#51](https://github.com/OpenMW/osg/pull/51)). Both apply to any VAO user on any profile.

OpenMW builds its OpenSceneGraph fork with `OPENGL_PROFILE=GL2`, and a GL2 build has no runtime notion of a core context. These commits give it one: `GLExtensions::isCoreProfile` is read once from `GL_CONTEXT_PROFILE_MASK` and cached on the `osg::State`, and every behavioural change is gated on it (or, for osgText, on the `SHADER_GL3` display-settings hint), so a stock GL2 build on a compatibility context is unchanged.

| commit | what |
|---|---|
| `5337edbee4` | Detect the context profile; skip the compiled-in `glMatrixMode`/`glLoadMatrix` calls and the `GL_MAX_TEXTURE_COORDS` query on core; accept VBO, PBO, VAO, texture swizzle and packed depth-stencil by GL version as well as extension string. Without this nothing renders. |
| `a773f30a47` | The fixed-function attributes (`AlphaFunc`, `Material`, `LightModel`, `Light`, `Fog`, `TexEnv`, `TexEnvCombine`, `TexGen`, `ShadeModel`, `LineStipple`, `PolygonStipple`, `ColorMatrix`) become no-ops on core; `GL_CLAMP` mapped to `CLAMP_TO_EDGE` and no `GL_DEPTH_TEXTURE_MODE` there; osgParticle without quads or attribute push/pop. |
| `dd9ccb2b3e` | osgText glyph pages as R/RG under the GL3 shader hint; no compile-time warm-up draw on core (it draws with no program bound). |

The `VertexArrayState` fix applies to mainline OpenSceneGraph as well (mainline `master` still has the offset-only check at the time of writing).

## Diagnostics

No diagnostic code ships with the series. The tracing used while finding the bugs above (draw-time VAO traces, native backtraces at GL error checkpoints, shader source dumps) was removed before submission; what remains usable on a stock build is OSG's own `OSG_GL_ERROR_CHECKING=ONCE_PER_ATTRIBUTE`, which is how the "zero GL errors" figures in RESULTS.md were taken.
