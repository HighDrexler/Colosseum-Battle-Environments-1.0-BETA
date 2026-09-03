# CBE 1.7.1-fidelity.1 validation

## Scope

Focused follow-up to 1.7.0-fidelity.1 for two recording-visible regressions: source trainer actions reading as broad interpolated/swimming motion, and audited multi-bank Waza moves resolving gameplay without all visible source effect layers (Ember was the concrete reproduced case).

## Static/package validation

- `manifest.json` parses as JSON and reports `1.7.1-fidelity.1`.
- `main.lua` exports `1.7.1-fidelity.1`.
- Full source-tree Lua parse check: **53 / 53 files pass** under `texlua`.
- Final ZIP is required to expose `main.lua`, `manifest.json`, and `mod.card` at archive root with no enclosing directory.
- Development `.bak170` files are excluded from the final archive.

## Trainer animation validation

- Extractor revision: **13**.
- Trainer cache format: **26**.
- Gesture source bank: five chronological samples from one selected native B1 clip (`20/36/52/68/84%`).
- Reaction source bank: five chronological samples from one selected native B1 clip (`20/36/52/68/84%`).
- Runtime unit test verifies no more than two neighboring authored frames are blended at once and total dense source weight never exceeds 1.0.
- Lead-hand classifier now rewards motion on the actor's release side and penalizes broad opposite-arm travel to reduce selection of two-arm/swimming-looking clips.
- Release-hand/Poke Ball anchoring follows the same dense source-frame blend as the visible actor.
- Cache marker bump forces 1.7.0 trainer data to rebuild instead of silently reusing the sparse pose bank.

## MoveFX / Waza validation

- MoveFX extractor revision: **15**.
- Curated phase-selection unit test verifies authored `attack + damage + sp1` banks are retained in authored order; discovery-only aliases remain conservative.
- Ember's audited phase set therefore retains `wzx_hinoko_attack.fsys`, `wzx_hinoko_damage.fsys`, and `wzx_hinoko_sp1.fsys` when present in the user's source.
- Waza runtime unit test verifies same-numbered SequenceEntry IDs from separate source phases receive distinct runtime namespaces (`100001`, `200001`, ...), preventing attack/sp1 lifecycle collisions.
- GPT1 entry matching is phase-strict to prevent an auxiliary bank from binding to a same-shaped generator from another bank.

## Runtime limitation

The source parser/scheduler/cache/package paths above are locally validated. A real Gen1Recomp + user-imported GC6E01 battle runtime is not available in this environment, so visual confirmation of the rebuilt trainer clips and the restored Ember projectile must still come from an in-engine test. This build intentionally does not claim that every trainer semantic action or every remaining Waza entry subtype is fully decoded.
