# Validation — 1.8.1-capture-presentation.1

## Scope
Runtime/presentation-only capture pass based directly on `1.8.0-capture-source-fix.1`.
Generated source cache contract remains `cacheVersion=2`, `extractorRevision=15`.

## Static validation
- All 57 Lua files parse successfully with LuaTeX's Lua `loadfile` parser.
- `manifest.json` parses successfully and reports `1.8.1-capture-presentation.1`.
- `main.lua` reports the same version.
- `main.lua` remains at archive root.

## Capture invariants
- Engine-provided `caught` and `shakes` remain authoritative. CBE does not change catch odds, inventory, Pokédex state, or nickname logic.
- `battle.result` and `battle.ended` exit shots are deferred while `PlayerTrainer.captureStatus().active` is true.
- Successful and failed captures therefore share the same charge/throw/impact/absorb/fall/settle/shake camera path until the outcome phase.
- Successful capture sets enemy presentation scale to zero after the cinematic reaches `done`; the latch remains until battle presentation teardown.
- Native enemy suppression now follows `captureHidesEnemy()` so 2D/native fallback presentation obeys the same terminal caught latch.

## Motion changes
- Ball stays attached to the source throwing-hand anchor through release seam.
- Post-release horizontal travel is linear rather than smoothstep eased.
- Vertical flight uses a ballistic parabola.
- Impact recoil is compact; absorb no longer uses a large hovering bob.
- Drop accelerates under a gravity-shaped `q^2` curve.
- Landing uses one damped bounce/rock before the shake cycle.
- Throw camera uses a stable sideline tracking dolly rather than projectile-mounted tracking.
