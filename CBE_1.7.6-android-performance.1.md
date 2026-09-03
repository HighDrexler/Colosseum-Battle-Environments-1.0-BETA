# CBE 1.7.6-android-performance.1

Final Android runtime-stall and cache-efficiency sweep built directly on 1.7.5. No presentation feature, arena, animation, MoveFX behavior, audio behavior, model source, or camera behavior is removed.

## Battle-entry / rival stalls

- Fixes the previous enemy-trainer prewarm gap: game-ready prewarming had no trainer battle context, so the configured rival was still parsed, textured, meshed, and shader-bound on `battle.started`.
- `TrainerRoster.prewarmPlan()` now identifies the configured rival first (Leaf by default), followed by the forced/common enemy archetype. `Trainer` drains that plan outside battle and keeps a bounded Android trainer LRU.
- The trainer shader is shared across roster models instead of relinking for every trainer switch.
- Trainer caches progressively gain compact float32 runtime-mesh sidecars; later sessions can skip the large Lua vertex-table parse and upload the cached bytes directly to `Mesh:setVertices(Data)`.

## Pokémon / arbitrary model loading

- Adds `RuntimeMeshCache`, an installation-local runtime cache for compact float32 vertex data plus small metadata manifests.
- Existing Pokémon caches self-upgrade when first materialized. Subsequent loads can skip packed CSV parsing and thousands of `tonumber` conversions.
- Newly extracted Pokémon emit base runtime sidecars while decoded HSD vertices are already in memory, avoiding an immediate text-serialize/text-parse round-trip before first use.
- Runtime sidecars are revision-stamped and fail closed to the canonical generated cache when stale/missing/corrupt. The canonical source-derived cache remains authoritative.
- Android battle entry uploads only the active base bodies. Exact damage/faint/move action banks are queued and paced through the opening presentation instead of all landing on the same transition frame.

## MoveFX / Waza residency

- Type-2 Waza effect models gain compact runtime-mesh sidecars keyed to their generated source cache. Reused effects can bypass packed-vertex parsing in later sessions.
- Android retains only the two most recently used Waza GPU model caches after battle, explicitly releasing the rest. This avoids both unbounded VRAM growth and the old behavior that guaranteed every common effect had to be rebuilt next battle.

## Random arena / GPU driver work

- Random now primes the exact **next** per-battle arena before the battle begins, then consumes that immutable choice at battle acquisition. It remains stable for the entire battle and retains no-immediate-repeat behavior.
- Android background runtime work primes the next Random venue during ordinary non-battle frames.
- Arena venue switches now reuse the already compiled GLES shader and existing offscreen color/depth framebuffer. Those GPU objects are not arena-specific and no longer get recreated merely because Random chose a different venue.
- Only one arena geometry/texture scene remains resident at a time; the old venue is explicitly released before the next one is loaded. This keeps the optimization light on mobile VRAM.

## Garbage collection / working sets

- Removes battle-end stop-the-world collections from Pokémon/Waza cleanup. GPU objects are explicitly released and Lua GC advances incrementally while roaming.
- Party Pokémon, recent Pokémon, trainers, Waza effects, arena, and music each retain only small bounded working sets appropriate to their subsystem.

## Compatibility

- Existing 1.7.5 visual and 24/24 portable audio caches remain valid. No forced extraction revision bump is required.
- Full portable Android/non-Windows Colosseum battle audio, Random arena selection, wall-clock 1×/4× camera behavior, GLES battle hosting, source trainer animation, WazaSequence/MoveFX, capture, and Gen 1/Gen 2 behavior are retained.
