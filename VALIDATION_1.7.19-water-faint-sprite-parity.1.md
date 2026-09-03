# CBE 1.7.19-water-faint-sprite-parity.1 validation

Baseline: exact packaged 1.7.18-gen1-viewport-hotfix.1 payload.

## Static/package contract
- PASS: `main.lua` and `manifest.json` report 1.7.19-water-faint-sprite-parity.1.
- PASS: manifest remains Gen 1 + Gen 2 and parses as valid JSON.
- PASS: all 56 packaged Lua files parse with `texluac -p`.
- PASS: no `assets/`, `recipes/`, or `extract/` payload changed from 1.7.18; this is a renderer/presentation-timing/provider patch and does not invalidate generated source caches.
- PASS: the 1.7.18 Gen 1 `worldOverride` full-playfield rescale is still present.

## Water / Phenac fidelity
- PASS: Android's GLES-safe arena shader now consumes `sceneProfile` and gives Water a bounded source-lighting path instead of adding full ambient + diffuse into a 1.65 highlight ceiling.
- PASS: Water's mobile highlight ceiling is 0.88 and its full shader applies a dedicated limestone exposure/highlight rolloff.
- PASS: Water's backdrop no longer references `d2_crater` / Mt. Battle sky or cloud textures.
- PASS: the Water branch explicitly leaves the extracted M1 HSD scene authoritative for walls, balconies, banners, fountains and water.

## Gen 1 faint ordering
- PASS: raw Gen 1 `battle.fainted` is buffered while CBE owns the presentation queue.
- PASS: the buffered event is released only at `BattleState:fxFaintActive()` / queued `battler.fainted` visible-faint boundary.
- PASS: CurrentSpriteModels, BattleDirector, Camera, PlayerTrainer and Trainer all ignore the early raw Gen 1 faint and consume `battle.presentation_faint` instead.
- PASS: the compatibility fallback cannot use the early logical HP=0 alone as a faint trigger.

## Gen 2 external sprite ownership
- PASS: CBE's 2D battler path calls Gen1Recomp's live `src.pokemon.Sprites.path()` seam before native fallback.
- PASS: player is resolved as battle `back`; enemy as battle `front`.
- PASS: a changed custom path is used without replacing unchanged native Gold art with an unprocessed raw bitmap.
- PASS: an explicitly selected portable `battleSprites` provider can still override the path result.
- PASS: `battler.sprite` remains the final native fallback.

## Live-runtime boundary
Static validation proves package structure and event/provider contracts, not the final on-device frame. Highest-value live checks for this candidate:
1. Android Water/Phenac Colosseum at the same camera shown in the 1.7.18 screenshot: stone should read light grey/beige with visible grout/wall depth, not clipped white.
2. Gen 1 at 4x: land a lethal hit and verify the HP bar reaches zero before the CBE faint clip begins; actor remains present through the visible faint reaction.
3. Gen 2 with CBE Arenas ON, Colosseum Models OFF, Battle Arts/custom sprite package ON: both player and enemy must use the selected custom front/back presentation rather than stock Gold sprites.
4. Repeat item 3 with no custom sprite provider and confirm native Gold art still renders normally.
