# CBE 1.7.5-android-audio-random.1

Android full-audio-cache and Random-arena follow-up to 1.7.4.

## Android / non-Windows audio

- Replaces the 1.7.4 diagnostic-only portable audio artifact with a runtime-consumable **24/24 generated audio cache**.
- Adds a pure-Lua source-backed MusyX battle renderer for the 11 Pokémon Colosseum battle sequences plus the Snag cue, using the user's validated GC6E01 import.
- Parses the Colosseum song/project/pool/sample-directory data needed by those sequences and decodes the referenced GameCube DSP-ADPCM samples without `amuserender.exe`, `cmd.exe`, FFI, or an external extraction host.
- Production mobile output is 16 kHz stereo PCM WAV. Theme intro/loop assets are split using the source loop metadata expected by CBE's music runtime.
- Keeps the existing Windows Amuse path intact.
- The portable full-cache marker is `.cbe-audio-portable-v2.complete`; it is written only after all 24 required generated audio assets are verified.
- Valid portable-v2 audio now satisfies CBE's actual `audioReady`/runtime-ready contract instead of remaining an orphaned diagnostic cache.
- Interrupted portable audio builds resume from missing theme pairs/assets instead of discarding already completed WAVs.
- Once the full portable cache is valid, subsequent cache checks return without reopening the Colosseum disc.
- Decoded source samples are retained internally as compact packed PCM and reused between theme renders to reduce first-build Android RAM/CPU overhead.
- Runtime music residency is lazy: the cache may contain all themes, but only the selected battle theme is materialized into LÖVE audio memory. Random mode materializes only the theme chosen for that battle.

## Arena selector

- Adds **RANDOM** to the CBE arena selector.
- Random resolves exactly once when a new battle acquires its CBE environment and remains immutable for that battle.
- Menu/status/prewarm calls do not consume the random selector.
- When more than one arena is available, Random avoids immediately repeating the previously selected random arena when possible.

## Cache/status cleanup

- Portable full-audio readiness is reported as 24/24 and can make the existing valid visual cache fully runtime-ready.
- Existing 1.7.4 visual caches remain reusable; this update can upgrade audio in place without requiring a complete visual re-extraction.
- Trainer cache marker expectations are aligned with the current extractor marker so a valid trainer cache is not incorrectly reported stale.

No Pokémon Colosseum disc/ROM material is bundled with this package.
