# Validation — CBE 1.8.2-capture-source-lock.1

Focused capture-bank migration from 1.8.1-capture-presentation.1.

Checks performed:
- `main.lua` remains at package root.
- Manifest version matches runtime version.
- Capture index contract bumped to revision 4.
- Capture readiness now requires 12/12 source-backed balls and zero fallback rows.
- Existing extractor marker remains revision 15 so unrelated arenas/trainers/MoveFX/audio caches remain reusable.
- Existing revision-3 capture cache routes through a focused capture-only rebuild.
- Retail ball candidate selection now requires cross-phase embedded or decoded visual fingerprint recurrence.
- Phase-local candidates must fingerprint-match the canonical ball before use.
- Source ball models compile with `staticOnly=true` so Android avoids HSD morph-page rendering while preserving source HSD geometry/materials/textures.
- Runtime accepts only rows marked sourceReady + staticSource and never labels an unresolved fallback row as native source.
- Modified Lua files passed string/comment-aware delimiter balance checks in this build environment.
