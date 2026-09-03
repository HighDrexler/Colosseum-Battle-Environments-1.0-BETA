# CBE 1.7.0-fidelity.1 validation

Validated from the exact packaged 1.6.1 release payload with the fidelity patch applied.

- `main.lua`, `manifest.json`, and `mod.card` are present at ZIP root.
- `main.lua` and `manifest.json` both report `1.7.0-fidelity.1`.
- `manifest.json` parses as valid JSON.
- Every packaged Lua source passes `texluac -p` syntax validation.
- No unresolved Git conflict markers are present in Lua/JSON sources.
- Stable 1.6.1 import, arena, Pokémon actor, capture, floor-collision, and optional-audio code remains in place; this candidate changes trainer source playback and Waza presentation continuity only.

Runtime battle behavior still requires the normal Gen1Recomp + imported GC6E01 test. Static/package validation cannot substitute for that runtime test.
