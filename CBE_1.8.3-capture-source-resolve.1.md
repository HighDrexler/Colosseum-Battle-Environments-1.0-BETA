# CBE 1.8.3 — Capture Source Resolve

- Fixes the 1.8.2 `0/12 retail balls source-locked` regression.
- Removes mandatory cross-phase fingerprint recurrence; retail WZX phases do not guarantee duplicated model blobs.
- Selects each ball only from its own Colosseum `snatch_*` WZX family.
- Prioritizes `snatch_shake` because the physical ball must be present there, then land/throw/miss.
- Requires successful Type-2 parse, HSD decode and drawable static source compilation before a row is source-ready.
- Uses texture/geometry/phase semantics plus recurrence as confidence evidence; no byte-size window is restored.
- Shares the one proven retail ball prop across all capture choreography phases, which are world-motion driven by CBE.
- Keeps Android on the static exact-source geometry/material/texture path; no HSD morph-page dependency.
- Capture index revision is 5; existing arenas/trainers/MoveFX/audio remain reusable and only capture is rebuilt.
