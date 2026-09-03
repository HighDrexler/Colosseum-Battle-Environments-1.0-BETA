# CBE 1.8.2-capture-source-lock.1

Focused capture-source fidelity and Android portability pass.

- Replaces loose per-phase geometry ranking with cross-phase retail source fingerprint locking.
- Uses exact embedded-data recurrence first and decoded HSD geometry/material/texture recurrence second.
- Requires a source candidate to recur across at least two authored snatch phases before it can be called a retail Poké Ball.
- Phase-local candidates are accepted only when they fingerprint-match the canonical retail ball.
- Compiles capture props as static source HSD geometry/materials/textures by design; PlayerTrainer continues to own world-space throw, drop and shake choreography.
- Avoids Android/GLES morph-page failures causing a valid source ball to silently fall back to the procedural sphere.
- Capture cache revision 4 is strict: 12/12 source-backed balls, zero fallback rows.
- Adds a capture-only incremental migration so existing arena/trainer/MoveFX/audio caches do not need a full rebuild.
