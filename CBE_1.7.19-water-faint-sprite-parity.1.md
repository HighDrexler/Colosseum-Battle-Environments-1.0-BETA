# CBE 1.7.19-water-faint-sprite-parity.1

Focused presentation correction over 1.7.18.

## Water / Phenac Colosseum
- The Android GLES arena shader now has the same venue-profile awareness as the full shader. Water's source ambient/diffuse values are weighted rather than summed to a clipped-white output.
- The full shader rolls Phenac highlights into a controlled limestone midrange instead of leaving broad floor/wall surfaces near pure white.
- Water's screen-space fallback no longer imports Mt. Battle sky/cloud textures. A neutral interior tone is visible only through actual holes in the source HSD shell.
- No Water geometry or texture is replaced: M1_water_colo source groups/textures remain authoritative.

## Gen 1 faint ordering
- Raw Gen 1 `battle.fainted` is now treated as an early semantic commit while CBE owns the presentation queue.
- CBE buffers that event and releases `battle.presentation_faint` only when `BattleState:fxFaintActive()` reports the visible faint slide (or the queued `battler.fainted` compatibility fallback begins).
- Current Pokémon actor, camera, battle director and trainer reactions ignore the early raw KO and consume the visible presentation event instead.
- This prevents the enemy actor from collapsing/disappearing before its HP meter has visibly reached zero. Battle speed still controls the engine timeline; CBE no longer gets a head start at 4x.

## Gen 2 external sprite ownership
- When CBE models are not selected, the 2D arena actor path now calls Gen1Recomp's sanctioned live `src.pokemon.Sprites.path()` resolver for the correct front/back side.
- A changed path from Battle Arts or another `pokemon.sprite` owner is loaded and shown inside the CBE arena.
- Selected portable `battleSprites` providers remain higher-priority and native `battler.sprite` remains the final fallback.
- CBE does not change another mod's settings or select an art package on the user's behalf.

## Preserved
- 1.7.18 Gen 1 full-viewport/high-DPI compositor fix.
- 1.7.17 arena-safe camera envelopes and source-arena migration.
- Existing arena/model/MoveFX/capture/audio generated caches; this pass requires no cache revision bump.
