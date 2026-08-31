# Colosseum Battle Environments 1.6.1 — presentation stability validation

## Package/version

- `main.lua` version: **1.6.1**
- `manifest.json` version: **1.6.1**
- Release source tree: **53 Lua files**.
- 1.6.0 source/import/audio compatibility code is byte-identical in `NativeLauncherCompat.lua`, `BuildPipeline.lua`, `AudioProbe.lua`, `AudioWorker.lua`, and `Music.lua`; the manifest import declaration is unchanged except for the release version.

## Lua/static validation

- All **53/53 Lua files** compile successfully with the installed LuaTeX embedded Lua parser via `loadfile`.
- Manifest JSON parses successfully.
- Version agreement between `main.lua` and `manifest.json`: **PASS**.
- No merge-conflict markers were introduced in the six runtime modules changed by this presentation pass.

## Pokémon persistence / floor invariants

Static/runtime-module checks confirm:

- dense reaction names `damage/pageN`, `damageHeavy/pageN`, and `faint/pageN` enter the same source root-travel stabilizer as their single-page counterparts;
- damage does not set actor opacity/visibility/removal state;
- pathological hit/faint lower bounds select the resident base body instead of an off-camera reaction page;
- an action-group draw fault immediately retries the resident base groups in the same `Actor:draw` call;
- the final floor equation includes existing presentation lift: `collisionMinY * scale + lift`; therefore negative fallback/faint lift cannot be applied after the clamp and push the mesh beneath the arena ground plane;
- new counters (`reactionClamps`, `reactionFallbacks`, `actionDrawFallbacks`, `floorClamps`) survive `status()` and `resetRuntime()` for live diagnostics.

`PokemonActors.lua` was also loaded under Lua with a minimal provider stub; `status()`/`resetRuntime()` diagnostic invariants passed.

## Trainer stability harness

`TrainerPerformance.lua` was executed directly for Red, Dakim, Miror B., and Nascour over 10 seconds of idle samples.

- source-authoritative whole-body root residual at authority 1: ~**1%**;
- duplicate same-reaction trigger before 0.88 s: rejected;
- brace -> concern retrigger inside 0.76 s: rejected;
- later escalation: accepted;
- idle sway/bob remain small deterministic continuity motion;
- Miror B. retains distinct secondary personality/hair response without the former full-body groove amplitude.

Trainer and PlayerTrainer shader/source-joint morph ceilings use the same **0.84** action limit so Red's hand/capture attachment and visible body pose do not diverge.

## MoveFX ownership harness

`WazaSequenceRuntime.lua` + `BattleDirector.lua` were executed with synthetic retail-style attack and damage entry graphs.

- attack Waza timeline starts even when PKX timing points are unavailable, using the scheduler's explicit timing fallback rather than a separate whole-role renderer;
- damage Waza timeline likewise starts from one damage boundary without requiring PKX timing metadata;
- attack and damage receive distinct Waza serials: **PASS**;
- `CurrentSpriteModels` only direct-stages a whole-role GPT1 fallback when that role has **no Waza timeline**;
- exact repeated Waza SequenceEntry launches are deduped by Waza serial + source entry identity;
- the prior director -> second Waza start -> direct GPT1 cascade is removed.

The 1.6.0 retail WZX mapping/extraction data is unchanged. The source audit remains 251/251 Gen-I/II move families mapped, with Type-4 controller entries preserved as opaque rather than guessed.

## Compatibility regression scope

The 1.6.0 import/audio implementation was intentionally left untouched by this patch. That previously validated path remains:

- raw ISO/GCM and representation-aware CISO/scrubbed GameCube sources;
- content validation against GC6E01/revision/FST/core FSYS data;
- bounded launcher-owned source reads;
- optional/fail-open Colosseum audio cache with stock game audio fallback.

Because the compatibility modules are byte-identical to 1.6.0, this presentation patch does not add a new extraction format or alter source admission behavior.

## Runtime limitation

The environment can compile/execute pure Lua harnesses but cannot launch a full Gen1Recomp + LÖVE GPU battle window. Final confirmation of driver-specific mesh/shader behavior still requires the user's normal gameplay smoke test.
