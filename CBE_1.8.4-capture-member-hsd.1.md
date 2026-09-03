# CBE 1.8.4 — Capture Member HSD Resolution

- Treats each retail `wzx_snatch_*.fsys` payload as the complete `.fdat` asset container used by the game instead of assuming the visible Poké Ball must be an embedded Waza Type-2 model row.
- Adds full-member HSD root enumeration and a deep archive scan for capture extraction only.
- Selects the most ball-like textured HSD root from the authored capture phase (shake first), then falls back to decoded Type-2 rows only when appropriate.
- Compiles source geometry/materials/textures as a static runtime prop; CBE owns world motion for throw/drop/shake.
- Capture index revision 6 records `sourceComplete`, `sourceReady`, and `fallbackBalls` separately. Structural capture readiness no longer requires 12/12 source props, preventing capture-source uncertainty from blocking the entire generated runtime.
- Existing arenas, trainers, MoveFX and audio caches remain reusable; only the capture bank migrates.
