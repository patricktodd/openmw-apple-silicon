# The core-profile port: design and findings

This document explains what the `opengl profile = core` port changes in OpenMW and its OpenSceneGraph fork, why each change is needed, and what was learned along the way. It is the reasoning behind the patch series mapped in PATCHES.md; the measurements are in harness/RESULTS.md.

## Why a core profile

macOS offers exactly two kinds of OpenGL context: a legacy 2.1 compatibility context, which is what OpenMW has always requested, or a forward-compatible core context at 3.2–4.1 with no fixed-function pipeline. Apple froze OpenGL at 4.1 and layers it on Metal, so the compatibility path can never grow. A core-profile renderer is therefore the ceiling macOS allows and the prerequisite for anything after it — a Metal or Vulkan backend would need the same decoupling from fixed-function state. It is also what RenderDoc requires to attach (OpenMW issue #5251).

What core does not unlock on macOS: compute shaders, SSBOs, clustered lighting (needs GLSL 4.30), reverse-Z via `ARB_clip_control` (4.5) or multiview. Those stay off there regardless.

## Starting point

Requesting a 4.1 core context from an unmodified OpenMW gives a running engine that draws only the clear colour: every `#version 120` shader fails to compile, every draw raises `GL_INVALID_OPERATION` (client-side vertex arrays, no vertex array objects), and luminance/alpha textures raise `GL_INVALID_ENUM`. The frame loop, physics, Lua and statistics all keep working. So the mechanism is sound and the work is an inventory of fixed-function dependencies.

Upstream had already removed the two largest ones before this port began: `osg::Material` and `osg::TexMat` are replaced by `SceneUtil::Material` and `SceneUtil::TexMat`, which upload uniforms instead of touching `glMaterial`/`glLoadMatrix`. That left:

- the shader suite itself: 40 files at `#version 120`, using `varying`, `texture2D`, `gl_FragData`, `gl_Vertex`/`gl_ModelViewMatrix` and friends, `gl_ClipVertex`;
- the MyGUI render backend, which dispatches fixed-function vertex pointers without a vertex array object;
- `GL_QUADS` in the sky, global map and water grid;
- `GL_LUMINANCE`/`GL_ALPHA` texture formats in the GUI, global map, terrain blend maps and greyscale mod textures;
- `osg::ClipPlane` for water reflection/refraction and for transparent objects straddling the water plane;
- display lists and client arrays as OSG's global default;
- and OpenSceneGraph itself, which OpenMW builds with `OPENGL_PROFILE=GL2`: such a build has no runtime notion of a core context.

## Design

### One shader source for both profiles

Rather than fork the shader suite, the shaders are written once in a small profile-neutral vocabulary that `ShaderManager` resolves at load time: `#version @glslVersion @glslProfile`, `@varying` (which becomes `varying` on compatibility and `out`/`in` per stage on core), `@attribute`, `@texture2D`, `@shadow2DProj`, `@textureSize2D`, `@fragColor`, `@fragData0`/`@fragData1`. On core the manager also declares the two fragment outputs the `@fragData` tokens map to. A `@gpuShader4Extension` token stands in for the `GL_EXT_gpu_shader4` pragma (empty on core, where those features are native) so that no `#extension` line is ever left inside a disabled `#if` block. That matters because of how OSG rewrites shaders: `State::convertVertexShaderSourceToOsgBuiltIns` replaces `gl_Vertex`, `gl_ModelViewMatrix` and the other built-ins with `osg_*` equivalents and inserts their declarations *after the last `#extension` line it finds* — even one inside a disabled block, where the declarations are silently lost. The built-in matrices and attributes therefore come from OSG's own aliasing, which is switched on at runtime (below).

The post-processing system (`.omwfx` techniques) already had an equivalent vocabulary (`omw_In`, `omw_Out`, `omw_Texture2D`, `omw_FragColor`) with a modern branch selected when the technique's GLSL version is 330 or above; on core, techniques are floored to 330 so that branch is used. Techniques that bypass the `omw_*` macros and use legacy built-ins directly will not compile on core; this is documented with the setting.

### Clip planes through `gl_ClipDistance`

`glClipPlane` does not exist on core. The water code keeps its eye-space planes in `clipPlane`/`clipPlane1` uniforms and the vertex shaders write `gl_ClipDistance[0]`/`[1]` from them, enabling the corresponding `GL_CLIP_DISTANCEn` modes (numerically identical to `GL_CLIP_PLANEn`, so the existing mode toggles survive). The distances are written by a macro in the calling shader's own compilation unit rather than by a linked helper function. (An early linked variant crashed inside Apple's GLSL linker on this machine; that crash could not be reproduced later, see RESULTS.md, so the macro is a choice, not a workaround for a confirmed driver bug.)

### Formats and primitives

Images loaded in alpha, luminance, luminance-alpha or intensity formats are expanded to RGBA with exactly the channel semantics a compatibility context gives them (`(0,0,0,a)`, `(l,l,l,1)`, `(l,l,l,a)`, `(i,i,i,i)`), so no shader needs to change how it samples; the few alpha images created in memory (global map, terrain blend maps), the GUI's L8/L8A8 textures and OSG's own glyph pages are stored as R8/RG8 with a texture swizzle instead. `GL_QUADS` sites are rewritten as triangle fans or indexed triangles.

### Runtime switches instead of an OSG rebuild

A GL3-profile OSG build would remove the fixed-function code paths, but it switches OSG's headers to `gl3.h` and breaks every OpenMW reference to `GL_LIGHTING`, `GL_ALPHA_TEST`, `GL_LUMINANCE8` and the compatibility path on other platforms. Instead the GL2 build is kept and a realize operation switches the `osg::State` into core mode:

- `setUseVertexAttributeAliasing(true)`: all vertex arrays dispatch as generic attributes at fixed locations, and `osg::Program` binds `osg_Vertex`, `osg_Normal`, `osg_Color`, `osg_MultiTexCoordN` to them at link;
- `setUseModelViewAndProjectionUniforms(true)`: OSG maintains `osg_ModelViewMatrix`, `osg_ProjectionMatrix`, `osg_ModelViewProjectionMatrix` and `osg_NormalMatrix` per program;
- `setModeValidity(mode, false)` for every removed mode (`GL_LIGHTING`, `GL_ALPHA_TEST`, `GL_TEXTURE_2D`, `GL_LIGHTn`, …), so OSG stops issuing `glEnable`/`glDisable` for them;
- `DisplaySettings::setVertexBufferHint(VERTEX_ARRAY_OBJECT)` and `setShaderHint(SHADER_GL3)` before the viewer is realized, which force VBO+VAO for every drawable and make OSG's own generated shaders (osgText) target GLSL 330;
- and, because a GL2 build probes most features by extension string and a core context does not advertise extensions that were promoted to core, the operation grants the feature flags the context version implies (VBOs, VAOs, FBOs, texture swizzle, …).

Everything the GL2 build hard-codes and cannot be switched off from the outside lives in the OSG fork patches, gated on a new `GLExtensions::isCoreProfile` flag read once from the context's profile mask: the compiled-in `glMatrixMode`/`glLoadMatrix` calls, the fixed-function attribute `apply()` methods (`AlphaFunc`, `Material`, `Light`, `TexEnv`, …, made no-ops there), the removed enums (`GL_CLAMP`, `GL_DEPTH_TEXTURE_MODE`, `GL_MAX_TEXTURE_COORDS`, `GL_GENERATE_MIPMAP_SGIS`), `glPushAttrib`/`glPopAttrib` and quads in osgParticle, and version-based feature detection. Each patch is gated on that flag (or, for osgText, on the `SHADER_GL3` hint), so a stock GL2 build on a compatibility context is unchanged.

### The GUI

The MyGUI render manager dispatches its vertex data through `osg::State`'s vertex-array API, which produces fixed-function pointers on compatibility and generic attributes on core; on core it also generates a vertex array object for OSG's global vertex array state, which OSG otherwise never gives one. Its L8/L8A8 textures use the R/RG layout above.

## Findings

Everything below was found with the harness (screenshot comparison against the compatibility renderer and `OSG_GL_ERROR_CHECKING=ONCE_PER_ATTRIBUTE`), temporary tracing added to OSG for the hunt and removed afterwards, and a debugger, rather than guessed; each is recorded because it is the kind of thing a reviewer or a later port would otherwise rediscover.

**OSG on a core context**

- The GL2 build's extension-string feature probing concludes that Apple's core context, which lists no promoted extensions, has no buffer objects at all. Fixed by version-based detection in the fork and by the realize operation granting version-implied flags.
- `State::initializeExtensionProcs()` runs at `makeCurrent`, before realize operations, so anything it caches from the context (e.g. the removed `GL_MAX_TEXTURE_COORDS` query) has to be handled inside OSG.
- OSG's global `VertexArrayState` never gets a VAO — the call is commented out in `State.cpp` — so any custom `drawImplementation` on core must generate one.
- OSG prefers the removed `GL_GENERATE_MIPMAP_SGIS` parameter for power-of-two textures; on core that leaves them without mip levels, and they sample opaque black. `glGenerateMipmap` is used instead.
- `Program::linkProgram` sets `GL_GEOMETRY_*_EXT` program parameters whenever it believes geometry shaders are available; on core those enums are gone (3.2 uses layout qualifiers), so that flag must not be granted.
- osgViewer's default headlight is applied through `glLight` to the frames drawn before `RenderingManager` disables it; the viewer is now created with `NO_LIGHT`. The profiler's HUD camera carried the same SceneView light, light model and material.
- `osgText` glyph pages are `GL_ALPHA`/`GL_LUMINANCE_ALPHA` in a GL2 build, and `TextBase::compileGLObjects` draws each text once at compile time with no program bound.
- **A genuine VAO bug in stock OSG.** `VertexArrayState::setArray` re-dispatches an attribute pointer only when the array object or its modified count changes. When another array sharing the same `VertexBufferObject` is replaced or resized, the buffer is re-laid out and unchanged arrays move inside it, but their VAO pointers keep the old offset. OpenMW's sky exposes it: `SkyManager` replaces the cloud mesh's colour array after first compile, and the clouds then rendered with their texture coordinates read from the colour data. Compatibility never notices because client arrays are re-pointed on every draw. `Drawable::dirtyGLObjects()` already reaches the per-context `VertexArrayState::dirty()` when an array is replaced; the fix makes that call invalidate every active array's recorded modified count so they are all dispatched again (a first version tracked offsets per array; the review on the pull request asked for the existing signal instead).
- **A client array inside a VAO, in OpenMW.** `NifOsg::ParticleSystem::drawImplementation` sent its one-element, overall-bound normal array through the vertex-array path whenever a VAO was in use, a client pointer that a core context rejects on every particle draw. It now goes through the attribute dispatcher as a constant, as it already did without a VAO. Found only after the OSG fix above was narrowed: the first version had silently given such arrays a buffer object.
- **A genuine static-destruction bug in stock OSG.** `GLExtensions::~GLExtensions` writes into three file-scope statics. On a core context every `VertexArrayState` holds a reference to the context's `GLExtensions`, and released states stay in the `ContextData` until process exit, so the destructor runs during `exit()` after those statics are already destroyed, corrupting the heap; the crash surfaced later in an unrelated static destructor about two thirds of the time. Found with guard malloc after stack logging, heap checks and unmap tracing had all come back clean. Mainline OSG had fixed the same bug in 2019 (commit `97f955b2`, an `observer_ptr` to the registries), which OpenMW's `3.6` branch predates; that commit is backported, replacing an equivalent fix written here first.

**Shaders and drivers**

- An early variant that wrote `gl_ClipDistance` from a separately linked unit crashed inside Apple's GLSL linker on this machine; the same crash appeared twice while testing !5502's linked design and then could not be reproduced in seventeen further launches (RESULTS.md). Cause unknown; the macro stays because it is simple, not because linking is known to be broken.
- `textureProj` on a `sampler2DShadow` returns a float in core GLSL where `shadow2DProj` returned a `vec4`; the token maps to a `vec4`-returning macro so the `.r` swizzles keep working.
- The `GL_EXT_gpu_shader4` pragma is rejected by core contexts (its features are native in 330); it is replaced by the `@gpuShader4Extension` token, which is empty on core, so no `#extension` line is left inside a disabled `#if` block (see the design section for why that matters).
- A local variable named `textureSize` in `alpha.glsl` shadowed the GLSL 330 built-in function.
- Declaring `osg_ViewMatrixInverse` explicitly in a shader breaks compilation on *both* profiles, because OSG declares it itself whenever it sees the name. This was introduced during the port and caught by running the heavy profile on compatibility — which is why the heavy profile is part of every regression run.
- Each fixed-function attribute applied on a core context costs a `GL_INVALID_OPERATION` round-trip inside Apple's driver. Making them no-ops is where most of core's measured frame-rate advantage over compatibility comes from.

## Results

See harness/RESULTS.md. In short, on an Apple Silicon Mac the core profile renders the same picture as compatibility on every station (screenshot RMSE 0.04–2.15 %), reports zero GL errors under per-attribute checking, exits cleanly, and is ahead on mean frame rate on six of nine stations (level on two, behind on one) and on the heavy profile at the two stations tried, with better frame-time tails at every station. It does not move the CPU-side draw-submission floor (roughly 6–7 ms per frame); that is a draw-call-count problem a different backend would have to solve.

## Limitations and open items

- Not tested on Windows or Linux core contexts; nothing in the port is macOS-specific, but the SDL request and driver behaviour deserve a run there.
- Not tested with stereo/multiview rendering on core; the water clip uniform is keyed per eye but that path has not been exercised.
- OpenCS is untouched. It reads the same settings.cfg, but the core-profile flag is set only by the engine, so it keeps its Qt compatibility context; this was checked by reading the code, not by running OpenCS with the setting on.
- `.omwfx` techniques that use raw legacy built-ins do not compile on core (documented with the setting).
- The vcpkg OSG package used for this build aliases png/tga to an `imageio` plugin it does not ship, so the ripple normal map and tga splash screens never load in that build on either profile. Not a port issue.

## Sources

OpenMW issue [#5251](https://gitlab.com/OpenMW/openmw/-/work_items/5251) (core profile / RenderDoc); [#6057](https://gitlab.com/OpenMW/openmw/-/work_items/6057) (shadows FBO on macOS); [Apple developer forum on missing alpha textures in core GL](https://developer.apple.com/forums/thread/772982). File references are to the OpenMW and OpenMW/osg source trees.
