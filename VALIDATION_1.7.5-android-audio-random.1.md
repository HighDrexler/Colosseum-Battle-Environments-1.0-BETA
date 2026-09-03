# CBE 1.7.5-android-audio-random.1 validation

## Result

Test candidate packaged from the 1.7.4 Android runtime-cache/camera branch with full portable battle-audio integration and Random arena selection.

## Source-backed portable-audio validation

- The production portable renderer was executed against real GC6E01-derived MusyX project/pool/sample-directory/song data.
- All 11 battle sequences plus `me_snatch` produced non-silent PCM in the all-sequence renderer harness.
- Representative 16 kHz production renders passed for the normal battle and the long `battle9plus` sequence; resulting per-file WAV sizes remain far below the 64 MiB cache-write ceiling.
- The complete AudioProbe integration was executed through the real GameCubeDisc/FSYS readers against the GC6E01 source view: **24/24 generated assets**, valid RIFF/WAVE headers, portable full-ready marker, and bounded source reads.
- Full-integration test result: `FULL_AUDIO_OK assets=24 bytes=3267104 discReads=312 generated=26 renderer=portable Lua MusyX battle subset` at the accelerated 1 kHz test-output rate.
- Interrupted-cache resume test deleted one loop asset plus the v2 marker and regenerated only the missing loop plus completion marker.
- BuildPipeline test confirmed the first portable upgrade reaches `READY`, while a second run is a cache no-op with no additional disc open.
- CacheManager test reports `RUNTIME READY` and `audio=24/24` for a valid portable-v2 cache.

## Runtime music validation

- All 11 generated theme pairs are visible to the music selector when cached.
- Explicit theme selection maps to the corresponding `COLOSSEUM_ENV_*` song record.
- Random music selects one cached theme and registers that theme only.
- Lazy residency test: default startup reads only the selected theme's two WAVs rather than all 22 theme WAVs; Random requires at most two additional WAV reads when its battle theme is selected.

## Random arena validation

- `RANDOM` is present in the arena options/validation set.
- A random arena is resolved once per battle and remains stable for the battle lifetime.
- A new battle performs a new selection and avoids immediate repetition when alternatives exist.
- Status/menu calls without a battle do not advance RNG or alter the next battle selection.

## Code/package validation

- 54 packaged Lua source files parse successfully.
- `manifest.json` and `main.lua` both identify version `1.7.5-android-audio-random.1`.
- API-2 permissions remain `engine_internals` only.
- No ISO/GCM/CISO/RVZ/WBFS/7z or `baseroms/` source media is included.
- `main.lua`, `manifest.json`, and `mod.card` are located at ZIP root.

## Device validation

The portable renderer and cache/runtime paths are executable-tested here against the source data, but final wall-clock synthesis time, device thermal behavior, and audible playback through the Android Gen1Recomp APK still require the physical-device test. The first full portable soundtrack build is intentionally a one-time cache operation and may take several minutes on mobile; subsequent launches should use the completed cache.
