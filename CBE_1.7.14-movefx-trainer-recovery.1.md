# CBE 1.7.14-movefx-trainer-recovery.1

## Purpose

Recover two regressions visible in the 1.7.11-1.7.13 test line: Windows trainers were visible again but had lost the source animation work, and source-ready battles could present Crystal/GB/GBC native attack art instead of Colosseum Waza/GPT1 effects.

## Windows trainer animation

The 1.7.12 Windows compatibility path reduced each 44-float dense trainer vertex to only position/UV/normal. That made the model render on the affected Windows backend, but it physically removed the breath/look/gesture/reaction morph targets from the mesh.

1.7.14 uses a bounded Windows format with seven attributes: base position, UV, normal, breath position, look position, Action A position, and Action B position. TrainerPerformance's source timeline is built from adjacent B1 samples; the two currently relevant source action targets are refreshed on the dynamic mesh only when that pair changes, while their weights remain lightweight shader uniforms. This preserves source-authored opening/sendout/command/victory/defeat/reaction motion while staying far below the previous dense 15-attribute Windows shader contract.

The enemy trainer path continues to bypass runtime `.f32` trainer sidecars on Windows so canonical dense source rows remain available for those dynamic action targets. Native trainer sprites remain capability-gated and are hidden only after the matching 3D trainer is active and ready.

## Source MoveFX staging

BattleDirector starts WazaSequence at the semantic move boundary after the Pokemon actor selects its source attack slot. That call receives a lean context containing the battle/game but not the later arena compositor object. The type-3 Waza handler previously called `stageMoveFx`, which required `ourArena(context)` and therefore rejected the valid source effect on that exact frame. The later rich path saw the already-owned Waza serial and correctly refused to start a duplicate, leaving no GPT1 particles.

`stageMoveFx` now accepts verified CBE world ownership from any of:

- a rich CBE arena context,
- an active StandaloneHost, or
- StadiumBridge ownership of the battle.

The GPT1 VM can therefore start on the authoritative semantic boundary, and its live Pokemon-relative basis is locked as soon as the rich render/update context supplies actor geometry. This applies to every Waza type-3 move, not to Flame Wheel specifically.

## Source-only visual ownership

The 1.7.12/1.7.13 fail-open visual policy is removed. While CBE owns the battlefield, native move animation scripts still advance underneath so battle queues, timing, and unsuppressed fallback audio remain authoritative, but their Crystal/GB/GBC sprites, palette effects, and screen transforms are not composited. A missing source effect is therefore exposed as a CBE source-runtime failure instead of being disguised by native art.

Native move audio remains more conservative: CBE suppresses it only when every required type-5 GameSound for the active source Waza is cached and loadable.

## Strict 251-move cache validation

The old full-cache marker could be written even when the extractor reported missing banks because `extractAllMoves()` always returned `ready=true`. The v2 MoveFX marker now requires:

- extractor revision 16,
- total = 251,
- ready = 251,
- missing = 0,
- one non-missing source stem row for every move id 1 through 251, and
- a ready Waza GameSound cache.

Upgrading performs a MoveFX-only v2 revalidation. Existing valid revision-16 `cache/movefx/<stem>/effect.lua` banks and Waza SFX WAVs are reused; missing data is rebuilt from the user's validated GC6E01 source. Visual arena/Pokemon/trainer and soundtrack caches are not intentionally invalidated.

## Preserved work

The generalized 1.7.13 GPT1 dependency model remains: one authored Waza root auto-starts, while same-bank, nested, sibling-controller and uniquely resolved cross-bank generator dependencies remain available as dormant templates. Pokemon-relative MoveFX scaling, source GameSound timing, bounded audio/mesh residency, Android transition-safe caching, and camera/capture work are retained.
