# CBE 1.7.17-arena-camera-fidelity.1 validation

## Static/package checks
- Built directly from `ColosseumBattleEnvironments-1.7.16-presentation-fidelity.1.zip`.
- Version bumped consistently in manifest/main/README/card.
- Gen 1 final-frame isolation is gated to an active CBE StandaloneHost session and explicitly excludes Gen 2.
- Gen 2 direct/widescreen compositor code is unchanged.
- Camera safe volumes exist for all five selectable arenas.
- Attack/damage/reaction camera pitch, radius, height and FOV are bounded before presentation interpolation.
- Combat-subject screen projection can reject a source/semantic shot and fall back to a readable master.
- Arena v7 migration re-extracts Water/Orre/Realgam/Mt. Battle and rematerializes the current Wildlands recipe; trainer, MoveFX and audio caches are preserved.
- No ROM/disc data is bundled.

## Runtime checks requested
1. Gen 1 + Mobile Battle UI ON: CBE world fills the normal battle viewport instead of top-left quarter-size.
2. Gen 2 + Mobile Battle UI/config equivalent: verify no presentation regression.
3. Test attacks in every arena: neither combatant should disappear behind architecture or become a tiny edge element; reject overhead/floor-dominant shots.
4. Test 1x and 4x battle speed: camera velocity/overshoot should remain wall-clock stable.
5. Allow the one-time arena v7 migration to complete; confirm source-backed venues plus Wildlands refresh while trainer/MoveFX/audio caches are not rebuilt.
6. Compare distant architecture/materials/skyline coverage against Colosseum source references, especially Mt. Battle and Realgam.
