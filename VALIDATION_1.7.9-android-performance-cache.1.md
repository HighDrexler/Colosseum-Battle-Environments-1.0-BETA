# CBE 1.7.9-android-performance-cache.1 validation

## Static/package checks

- Built from the working 1.7.8 Android audio-stability package.
- Version bumped consistently in `main.lua`, `manifest.json`, README, and card.
- All Lua files parse successfully with `texluac -p`.
- `manifest.json` parses as valid JSON.
- Git whitespace/error check passes.
- ZIP integrity is checked after packaging.
- No ROM/disc data or generated user cache is bundled.

## Targeted performance regression checks

- Synthetic Android `input.step` harness verifies that incremental GC does **not** run when the engine changes the top state during the frame, and that ordinary stable roaming still advances incremental GC.
- Synthetic arena harness verifies Android AUTO can hold two resident arena scenes, creates runtime mesh sidecar metadata/bins on first warm, and hits those runtime sidecars after a simulated runtime reset.
- Static inspection verifies `input.step` no longer calls party prewarm, trainer prewarm, arena prewarm, Random priming, or MoveFX prefetch.

## Physical-device checks requested

1. Relaunch once and allow the game-ready warm to finish. The first launch may be longer while Water/Wildlands runtime arena sidecars are generated.
2. Run at least **5 trainer + 5 wild encounters**, alternating encounter types if possible. Measure the time from encounter trigger to the first visible transition frame and from the end of the transition to the battle scene.
3. Repeat encounters after a full app kill/relaunch. The second session is especially important because arena runtime sidecars should now be reusable.
4. Test one manual heavy arena (Orre, Realgam, or Mt. Battle) twice. The first use may generate its sidecar; the second should avoid the giant source-cache parse.
5. Note whether any remaining long pause happens **before the transition appears**, **during/after the transition**, or only on a **never-before-used Pokémon/trainer/arena**. Those three cases now map cleanly to separate runtime timing diagnostics.
