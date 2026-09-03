# CBE 1.7.20-sprite-provider-priority.1 validation

Baseline: exact packaged `1.7.19-water-faint-sprite-parity.1` payload.

Reference compatibility package: user-supplied `BATTLE_ART_VOXEL_GEN2-2.0.9.zip`.

## Battle Art reference audit

- PASS: Battle Art manifest id is `BATTLE_ART_VOXEL_GEN2`.
- PASS: Battle Art manifest version is `2.0.9`.
- PASS: Battle Art exports `lib`, allowing companion mods to load its documented `BattleArt` and `AnimatedBattleArt` modules.
- PASS: `BattleArt.apply(battle)` exists and owns STATIC species-image installation.
- PASS: `AnimatedBattleArt.update(battle, dt, trainerBattle)` exists and owns animated species playback.
- PASS: `AnimatedBattleArt.reassert(battler)` exists for consumer-boundary frame ownership.
- PASS: Battle Art MODDED mode is explicitly represented by `ownsSpeciesArt()==false`.

## CBE compatibility changes

- PASS: CBE discovery includes current id `BATTLE_ART_VOXEL_GEN2` plus legacy ids.
- PASS: manifest optional dependencies include `BATTLE_ART_VOXEL_GEN2`, preserving deterministic load ordering where supported.
- PASS: `BattleArtBridge` recognizes current Battle Art 2.x for full-stage suppression while CBE arenas are ON.
- PASS: `syncBattleArtSpecies()` is gated off whenever Colosseum Models are enabled.
- PASS: with models OFF, animated playback advances only from update.
- PASS: STATIC installation and ANIMATED frame reassertion occur again at the final sprite consumer boundary after the Gen 2 facade refresh.
- PASS: generic engine `pokemon.sprite` and portable `battleSprites` paths remain available after Battle Art processing.
- PASS: MODDED can yield to another provider rather than falsely claiming Battle Art ownership.
- PASS: native battler image remains the final fallback.

## Package/static checks

- PASS: `main.lua` and `manifest.json` report `1.7.20-sprite-provider-priority.1`.
- PASS: manifest parses as JSON and remains Gen 1 + Gen 2.
- PASS: all 56 packaged Lua files parse with `texluac -p`.
- PASS: compared with 1.7.19, runtime changes are limited to `CurrentSpriteModels.lua`, `BattleArtBridge.lua`, version/manifest metadata and release documentation.
- PASS: no `assets/`, `recipes/`, `extract/`, audio, MoveFX, capture, trainer, or arena-cache payload changes.

## Highest-value runtime matrix

1. Gen 2: CBE Arenas ON + Colosseum Models ON + Battle Art ON -> Colosseum models must appear, never Battle Art sprites.
2. Gen 2: CBE Arenas ON + Colosseum Models OFF + Battle Art STATIC -> selected static Battle Art front/back images must appear.
3. Gen 2: same but Battle Art ANIMATED -> animation frames must play inside the CBE arena.
4. Gen 2: Battle Art DUPLICATE FIX = MODDED + another sprite package -> that other package must win.
5. Gen 2: no external sprite provider -> native Gold sprites must still be the final fallback.
6. Re-check Water, Gen 1 4x faint timing and Gen 1 mobile viewport to ensure 1.7.19/1.7.18 behavior is unchanged.
