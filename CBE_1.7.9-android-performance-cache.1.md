# CBE 1.7.9-android-performance-cache.1

## Battle-entry performance pass

This candidate targets the remaining 5–10 second stalls reported between accepting an encounter, seeing the battle transition, and reaching the CBE battle scene. The core goal is to make the generated cache behave like a true runtime cache instead of repeatedly converting expensive text/source assets into GPU-ready objects during normal gameplay.

### Transition-frame protection

- CBE now snapshots the Gen1Recomp state-stack top before and after the wrapped `input.step` call.
- If the engine pushes any new state on that frame — including a battle transition — CBE performs **zero** background cache/model work afterward.
- Party model prewarm, trainer prewarm, Random/AUTO arena prewarm, and MoveFX prefetch were removed from ordinary Android overworld input frames.
- Incremental Lua GC remains allowed only on stable roaming frames and is reduced from a 64-step / 0.10 s cadence to 48-step / 0.12 s.
- Native Pokémon action-bank warming remains paced inside an already-active battle, but is also skipped on state-change frames.

### Runtime-ready arena cache

- Arena scenes now have a small resident LRU: **2 scenes on Android, 3 on desktop**.
- Android `AUTO` prewarms exactly its two possible battle environments: Water Colosseum for trainer battles and Orre Wildlands for wild/safari battles.
- Switching from a trainer encounter to a wild encounter therefore no longer requires destroying one arena before parsing/uploading the other.
- Arena shader and battle framebuffer remain shared/lazy; this is not a return to keeping every arena and framebuffer in VRAM.

### Persistent binary arena sidecars

- On first materialization, each final CBE arena material group is written as a tightly packed 12-float-per-vertex `.f32` stream plus compact Lua metadata under `cache/runtime_mesh_v1/arenas/<arena>/`.
- Runtime sidecars contain only the already-filtered, normal-complete geometry needed by the renderer. They do not duplicate the original ROM/disc source and do not replace the canonical extracted arena cache.
- On later sessions, CBE validates the sidecar against the source arena cache path + byte size, then creates GPU meshes directly from `ByteData` instead of reparsing the giant vertex Lua table and rebuilding normals.
- Any missing/stale/corrupt sidecar fails open to the original extracted cache and is regenerated.

### Game-ready working set

- Already-extracted party Pokémon now use a new base-only game-ready warm path. It never starts ISO extraction and deliberately leaves attack/damage/faint action banks lazy.
- The trainer prewarm plan is drained at game-ready instead of being paced through player movement.
- A bounded two-bank MoveFX seed is also prepared at game-ready on Android.
- Android post-battle Pokémon residency increases from three party actors to four, while retaining only two recent non-party actors.

### Diagnostics

- Battle runtime status now reports `entryTiming.totalMs`, `entryTiming.modelMs`, and `entryTiming.hostMs` so a remaining device-specific pause can be separated into Pokémon readiness versus arena/trainer host startup.
- Arena status reports resident scene count/limit and runtime sidecar hit/write counters.

### Compatibility / unchanged behavior

- CBE arena ownership remains independent from Battle Art, StadiumFX, sprite-source choices, and other presentation mods.
- No battle logic is changed.
- Existing 1.7.8 visual, model, audio-v4, camera, capture, and MoveFX caches remain valid; there is no forced global visual re-extraction.
- The first 1.7.9 launch can be slower at the game-ready seam because Water/Wildlands arena sidecars may be generated once. The intended trade is a larger persistent cache and slightly higher bounded residency for dramatically cheaper encounter-time work.
