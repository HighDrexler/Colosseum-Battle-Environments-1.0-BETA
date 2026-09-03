# CBE 1.7.2-android.1 validation

## Result

**PASS — Android compatibility candidate packaged from the 1.7.1-fidelity.1 branch.**

## Static / package validation

- `manifest.json` parses and reports `1.7.2-android.1`.
- `main.lua` exports `1.7.2-android.1`.
- API-2 permissions contain only recognized `engine_internals`; invalid `compute` is gone.
- `required_imports` uses only stock API-2 fields and remains below the documented 2 GiB source ceiling.
- No Colosseum ROM/disc bytes are shipped in the package.
- All **53 Lua files** parse successfully with Lua 5.4 syntax validation.
- Package path/case audit reports **0 case-sensitive mismatches**.
- Windows native process/thread calls are confined to the optional audio renderer (`AudioProbe.lua` / `AudioWorker.lua`).

## Android compatibility assertions

- Legacy whole-disc fallback refuses >128 MiB imports instead of allocating the Colosseum disc as one Lua string.
- Native GameCube disc reads remain chunked to <=8 MiB.
- Compatibility cache creates parent directories and enforces a 64 MiB per-key write ceiling.
- Startup cache failure gate exposes touch-capable Retry / Continue / Exit controls.
- Android arena color/depth target uses an aspect-preserving <=1280x720-class pixel budget.
- Representative 2400x1080, 1080x2400, 3200x1440, and 1440x3200 displays resolve to 1280x576 / 576x1280 render targets.
- Heavy arena/full-party/global-WZX `game.ready` prewarm is disabled on Android.
- Android battle prewarm is limited to active battlers; bench actors defer until switch.
- Android WZX prefetch applies a full GC fence between extraction jobs.
- Pokémon scene/action GPU caches, Waza GPU caches, and MoveFX metadata are trimmed at battle end on Android while generated disk cache remains reusable.
- Trainer and player-trainer vertex formats use **15 attributes**, below the previous 16-attribute edge case.
- Cache marker readers agree on extractor 13 / trainer identity 12.
- Audio probing accepts Windows only; Android never attempts `amuserender.exe`.

## Scope limitation

This environment cannot execute the Android Gen1Recomp APK, Android Storage Access Framework, or device-specific OpenGL ES drivers. Real-device testing is still required for OEM memory behavior, driver-specific shader/mesh limits, and launcher picker behavior. The code/package audit is intended to remove the Android-specific faults CBE can control before that device test.
