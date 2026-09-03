# CBE 1.7.17-arena-camera-fidelity.1

## Gen 1 Mobile Battle UI
- Fix is now isolated at Gen 1's final `Renderer:endFrame` / `worldOverride` boundary.
- CBE forces identity screen-space before the Gen 1 world override is composited, preventing a leaked 0.5x Mobile Battle UI transform from shrinking the world to one-quarter area in the top-left.
- Gen 2's working `drawWidescreen` / direct-surface compositor is intentionally unchanged.

## Camera
- Adds explicit per-arena safe camera volumes for Water, Orre, Realgam, Wildlands and Mt. Battle.
- Attack/damage/reaction elevation is capped so source Waza cameras cannot become unreadable bird's-eye/floor-dominant shots.
- Camera positions are clamped to finite radius/height/FOV bounds before interpolation.
- Both combatants are projected into screen space for attack/damage/reaction/faint/switch shots. The camera first pulls back/widens while preserving the requested axis; if the battle is still unreadable it falls back to a stable combat master.
- Existing wall-clock speed invariance remains intact.

## Arena source parity
- Arena cache marker advances to v7.
- Existing installs now refresh **all four source-backed arenas** from GC6E01 using the current HSD/material serializer: Water, Orre, Realgam and Mt. Battle.
- Source diffuse, ambient, specular, shininess, GX wrap state, retained source scene geometry and current runtime material handling are therefore applied consistently even when an older Water/Mt. Battle cache had previously been preserved.
- Wildlands remains authored because there is no equivalent retail arena source currently used by CBE; the current recipe is rematerialized during the same arena-only migration, with reduced outer relief for cleaner silhouettes and camera clearance.
- Trainer, MoveFX and soundtrack caches are reused by this arena-only migration. Compact arena runtime meshes move to v2 and rebuild from the refreshed arena caches.

## Scope
- Trainer model overhaul intentionally deferred until this arena/camera candidate is visually stable.
