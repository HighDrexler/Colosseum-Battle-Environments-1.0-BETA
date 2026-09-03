# CBE 1.7.3-android-battlehost.1 validation

## Result
Android battle-host hotfix packaged from 1.7.2-android.1.

## Confirmed code-path correction
- Gen 2 `drawWidescreen` no longer delegates to the vanilla field when CBE owns the battle but `Arena.render()` returns no surface.
- Android selects the GLES-safe arena shader before the desktop dynamic-material shader.
- Android framebuffer setup attempts explicit depth-stencil, then temporary depth, then a color-only ordered fallback rather than aborting the arena.
- Shader uniform updates tolerate uniforms optimized out of the mobile shader.
- Arena begin/render failures persist to `build/android_battle_render_error.txt`.

## Package checks
- `manifest.json` parses as JSON and version matches `main.lua`.
- ZIP contains `main.lua`, `manifest.json`, and `mod.card` at root.
- Only the existing `engine_internals` API-2 permission is declared.
- No ROM/disc image is included.
- Existing 1.7.2 bounded import, touch recovery, mobile prewarm, cache trim, and Android audio-fail-open changes are retained.

## Runtime limitation
This environment cannot execute the Android Gen1Recomp APK or the device OpenGL ES driver. The purpose of this build is to stop masking the renderer error as a vanilla battle and provide Android-compatible shader/framebuffer paths for the real-device test.
