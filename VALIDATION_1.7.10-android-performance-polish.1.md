# CBE 1.7.10-android-performance-polish.1 validation

## Static/package validation

- Lua syntax: 55 / 55 `.lua` files accepted by LuaTeX `loadfile`.
- `manifest.json` parses successfully and reports `1.7.10-android-performance-polish.1`.
- `main.lua` exports the same version.
- Existing source/cache schema versions were intentionally left unchanged; 1.7.9/1.7.8 caches are reusable.

## Performance-policy checks

- Encounter transition state-change guard remains installed around `input.step`.
- Android GC work remains skipped on state-change frames and is reduced to step 24 every 0.18 s on stable overworld frames.
- Pokémon battle-end trim now uses `keepParty=4`, `keepRecent=4`, `softLimit=8`.
- Waza GPU residency retains four recent effect models.
- Android game-ready now preallocates the capped CBE framebuffer through `Arena:prewarmFramebuffer()`.
- RANDOM mode primes only the next arena identity at battle exit; it no longer calls `Arena:prewarmDefinition()` synchronously there.
- `BattleRuntime.status()` exposes both `entryTiming` and `exitTiming`.

## Runtime scope

This environment can validate Lua/package structure and the policy wiring, but it cannot reproduce the user's physical Android GPU/storage/runtime. Device testing remains authoritative for frame pacing and memory pressure.
