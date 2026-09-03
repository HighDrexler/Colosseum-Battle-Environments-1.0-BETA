# CBE 1.7.6-android-performance.1 validation

## Result

Final Android runtime-stall/cache-efficiency candidate built directly on 1.7.5. The pass changes when/how source-derived assets become resident; it does not remove arenas, models, trainer animation, camera behavior, MoveFX, capture, audio, Random, or Gen 1/Gen 2 functionality.

## Executable/static validation

- **Lua syntax:** 55/55 packaged Lua files parse with `loadfile` under LuaTeX.
- **RuntimeMeshCache harness:** 2 x 44-float rows pack to the expected 352-byte float32 payload, round-trip through generated storage, create a 2-vertex direct-upload mesh, and compact metadata serializes/loads correctly.
- **Trainer runtime-cache harness:** a format-26 trainer cache creates a float32 sidecar + compact manifest on first materialization; after runtime reset the same trainer loads through the runtime sidecar (`runtimeMeshHits=1`) rather than the original vertex table.
- **Trainer prewarm-plan harness:** default configured rival resolves first to `leaf`, followed by the common `default_m` enemy archetype. This closes the previous no-battle-context prewarm gap.
- **Random arena harness:** a primed random definition is stable before battle, is consumed by the next battle, remains immutable across repeated resolves during that battle, and the next random battle avoids the immediately previous arena when alternatives exist.
- **19 targeted source assertions:** runtime mesh module load order, bounded trainer LRU, Pokémon base/action sidecars, fresh-extraction base sidecars, Waza sidecars/LRU, incremental GC, no Pokémon/Waza full-GC seam, Random priming, arena shader/framebuffer reuse, background Random prewarm, Android action-bank pacing, manifest permission, and source-media exclusion all pass.

## Performance changes validated by code path

### Rival / trainers

- `TrainerRoster.prewarmPlan()` is usable without a battle object and identifies the configured rival before `battle.started`.
- `game.ready` queues the plan and materializes the first rival model; non-battle input drains later trainer entries at a paced interval.
- Trainer shader compilation is shared across all roster models.
- Android trainer residency is bounded to three models.
- Trainer runtime sidecars are validated against the canonical source-cache size and exact format-26 contract before use. Missing/invalid sidecars fail closed to the canonical generated trainer cache.

### Pokémon

- Existing base caches progressively write `runtime_mesh_v1/base_XX.f32` plus compact metadata; a later load validates both the extractor revision stamp and binary stride/size before taking the direct path.
- Native action sidecars are written only after runtime reaction stabilization, preserving the exact action geometry that would otherwise be uploaded from the canonical action cache.
- Newly extracted Pokémon can write base float32 sidecars while the decoded HSD rows are already in memory, avoiding an immediate packed-text parse on first materialization.
- Android battle entry prepares the two active base bodies and defers exact action-bank materialization into paced presentation-time jobs.

### Waza / MoveFX

- Type-2 Waza model caches progressively gain compact direct-upload sidecars.
- Sidecars validate against the generated Waza cache size and their own stride before use; canonical generated caches remain fail-open authority.
- Battle end retains only the two most recently used Waza GPU models and explicitly releases older meshes/textures.

### Random arenas / GPU objects

- Random chooses the next arena ahead of battle when possible and consumes that exact choice at battle binding.
- Venue changes release the prior arena geometry/textures but deliberately retain the arena shader and offscreen color/depth target, because those GPU objects are not venue-specific.
- Only one arena scene remains resident, preventing Random prewarming from becoming a multi-arena VRAM cache.
- Non-battle input primes the next Random venue after a prior Random battle or an overworld Random selection.

### Garbage collection

- Pokémon and Waza battle-end cleanup no longer invoke full `collectgarbage("collect")` pauses.
- GPU resources are explicitly released and Lua collection advances incrementally through ordinary Android overworld input frames.

## Cache compatibility

Existing 1.7.5 generated visual caches and the complete portable 24/24 audio cache remain valid. No visual/audio extraction revision is bumped solely for this performance pass. Runtime mesh sidecars are optional accelerators; stale or unavailable sidecars fall back to the existing canonical generated cache.

## Package boundary

- `main.lua`, `manifest.json`, and `mod.card` are at ZIP root.
- Manifest version matches `main.lua`.
- API-2 permissions remain `engine_internals` only.
- No ISO/GCM/CISO/RVZ/WBFS/7z source media or `baseroms/` data is packaged.

## Device boundary

The container cannot execute the Gen1Recomp Android APK/GLES driver. These tests validate the executable Lua/cache scheduling and direct-mesh contracts here; final perceived frame-time, driver upload latency, and device memory behavior still require the Android test device.
