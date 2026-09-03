# CBE 1.7.10-android-performance-polish.1

## Performance polish

This candidate follows the large 1.7.9 encounter-entry improvement and targets the smaller, intermittent stalls that remain between consecutive battles on Android.

### Pokémon residency

- Android now uses an eight-species soft resident cap.
- While eight or fewer Pokémon scenes are materialized, battle-end cleanup releases none of them.
- Above the cap, four party priorities plus four most-recently-used species are retained and older scenes are evicted.
- This prevents routes with several encounter species from repeatedly releasing and re-uploading the same generated model/texture data after every battle.

### MoveFX residency

- Four recently used Waza effect models remain GPU-resident instead of two.
- Generated runtime sidecars remain authoritative; this only changes the bounded live working set.

### First-frame framebuffer

- Android's capped CBE color/depth framebuffer is allocated at `game.ready`.
- The surface still uses the existing ~720p mobile cap and rebuilds lazily after a genuine resolution/orientation change.
- This removes canvas/depth-driver setup from the first visible CBE battle frame.

### Battle-exit work

- RANDOM mode still primes the identity of the following venue after battle, but no longer materializes that arena synchronously while the previous battle is closing.
- This avoids converting a battle-entry hitch into a battle-exit hitch. Persistent arena float32 sidecars still make genuinely cold RANDOM loads cheaper when they are eventually needed.

### GC pacing

- Stable-overworld incremental Lua GC changes from step 48 / 0.12 s to step 24 / 0.18 s on Android.
- GC remains completely skipped on state-change frames, including encounter-transition pushes.

### Diagnostics

- `BattleRuntime.status().exitTiming` now exposes total exit time plus host-finish, Pokémon-trim, Waza-trim, and RANDOM-prime timing.
- Existing battle-entry model/host timing remains intact.

### Compatibility

- No battle mechanics changed.
- Existing caches remain valid.
- Arena ownership remains independent from Battle Art, StadiumFX, Mobile Battle UI, and other presentation providers.
