# CBE 1.7.8-android-audio-stability.1 validation

## Static/package checks

- Built from `ColosseumBattleEnvironments-1.7.7-android-audio-fidelity.1.zip`.
- Version bumped consistently in manifest/main/README/card.
- Portable audio v4 keeps the 32 kHz PCM16 stereo contract.
- v4 migration deletes v3 MusyX-derived theme/one-shot WAVs only on the first migration; once v4 pending/migrating state exists it only resumes missing assets.
- Portable full readiness accepts redundant hidden/non-hidden completion markers and repairs the missing copy.
- The MusyX parser records the source `-2` loop sentinel and uses its start tick as the loop-file end only when all looping tracks agree.
- Arena world rendering clears inherited transform/scissor inside a push/pop-isolated offscreen pass.
- No ROM/disc data is bundled.

## Physical Android checks requested

1. Allow the one-time v4 soundtrack migration to finish. Enter a CBE battle and confirm music/arena functionality.
2. Fully kill Gen1Recomp, relaunch, and verify CBE reaches runtime-ready without returning to `AUDIO PORTABLE 1/24`.
3. Enable Mobile Battle UI and verify the 3D environment still fills the battle viewport.
4. Leave one battle running through at least 4–5 complete music loops and listen for progressive layering, wrong instrumentation, timing drift, or duplicated sections.
