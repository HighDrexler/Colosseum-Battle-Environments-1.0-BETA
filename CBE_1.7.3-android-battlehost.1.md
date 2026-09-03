# CBE 1.7.3-android-battlehost.1

Android battle-host hotfix based on 1.7.2-android.1.

## Confirmed bug from Android Gen 2 screenshot
The Gen 2 `drawWidescreen` wrapper returned directly to the native battle draw whenever `Arena.render()` returned nil. On Android, any arena shader/framebuffer incompatibility therefore looked exactly like CBE had never started: a short transition stall followed by the stock white battlefield.

## Fixes
- Gen 2 no longer silently restores the vanilla paper battlefield while CBE owns the world.
- Android now uses a simplified GLES-safe source-textured arena shader as its primary path; desktop retains the full dynamic material shader.
- Android color/depth targets use a compatibility ladder: explicit depth-stencil canvas -> temporary depth attachment -> color-only ordered fallback.
- Shader uniform sends are capability-safe so optimized-out uniforms in the mobile shader cannot abort the render.
- Render failures are written to `build/android_battle_render_error.txt` for exact device-side diagnosis.

No source ROM material is bundled.
