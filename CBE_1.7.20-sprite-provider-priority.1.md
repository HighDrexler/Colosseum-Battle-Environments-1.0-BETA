# CBE 1.7.20-sprite-provider-priority.1

Focused compatibility correction over 1.7.19 using the user-supplied Battle Art 2.0.9 package as the integration reference.

## Ownership contract

1. **Colosseum Models ON** — CBE GC6E01 Pokémon actors are absolute. No Battle Art/custom 2D provider may replace them.
2. **Colosseum Models OFF** — the selected external Pokémon-art provider is authoritative.
3. **Vanilla/native sprites** — final fallback only when no external provider supplies the side/species.

This applies independently of the Colosseum arena toggle: CBE still owns its arena/camera/trainer stage while external art owns only the Pokémon presentation when models are OFF.

## Battle Art 2.0.9 integration

The supplied `BATTLE_ART_VOXEL_GEN2-2.0.9.zip` identifies itself as `BATTLE_ART_VOXEL_GEN2`. Earlier CBE compatibility code searched only legacy fork ids, so the current package was invisible to the direct Battle Art bridge.

Battle Art 2.x also does not express all selected battle art as a changed `pokemon.sprite` path:
- STATIC mode installs prepared `Image` objects through `BattleArt.apply()`.
- ANIMATED mode installs/advances prepared frames through `AnimatedBattleArt.update()`.
- `AnimatedBattleArt.reassert()` restores the already-selected frame after another renderer refreshes the battler picture.
- MODDED deliberately relinquishes species ownership to another sprite provider.

CBE now consumes those exported managers directly while Models are OFF. The normal engine `pokemon.sprite` seam and portable `battleSprites` capability remain the generic fallback for every other sprite package.

## Gen 2 facade synchronization

Gold's battle view refreshes CBE's generation-neutral battler facade immediately before the world draw. That refresh can restore the native Gold picture after an earlier Battle Art update.

CBE therefore:
- advances Battle Art animation once during `CurrentSpriteModels:update()`;
- reapplies STATIC / reasserts the current ANIMATED frame at `imageFor()` immediately before drawing;
- never advances animation time at the draw boundary;
- uses the stable CBE facade rather than writing temporary sprite fields into saved Gen 2 party records.

## Stage bridge

`BattleArtBridge` now recognizes `BATTLE_ART_VOXEL_GEN2` too. CBE can suppress Battle Art's competing full arena/camera stage while still consuming its selected Pokémon art.

## Preserved

- 1.7.19 Water/Phenac lighting correction.
- Gen 1 visible faint-boundary synchronization.
- 1.7.18 Gen 1 mobile/full-viewport correction.
- 1.7.17 arena camera-safe framing and source extraction.
- Existing generated arena/audio/MoveFX/capture/trainer caches; no cache schema bump.
