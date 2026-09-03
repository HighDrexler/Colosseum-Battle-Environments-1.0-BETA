# Colosseum Battle Environments 1.7.2-android.1

Android compatibility hardening pass based directly on 1.7.1-fidelity.1.

- Removes the invalid API-2 `compute` permission and unsupported GameCube-specific required-import metadata; keeps only stock launcher import fields.
- Refuses the legacy whole-disc `mod:read` path for large Colosseum media instead of buffering ~1.46 GB into one Lua string. Bounded `mod.imports` is required for the disc source.
- Keeps disc reads at <=8 MiB and aligns the compatibility cache with the current 64 MiB per-write contract.
- Creates nested generated-cache directories before compatibility-overlay writes.
- Adds touch/mouse controls to first-run cache failure recovery so Android users can Retry, Continue without CBE, or Exit without a physical keyboard.
- Caps Android's offscreen 3D arena/depth surface to an aspect-preserving ~720p pixel budget rather than blindly using physical high-DPI resolution.
- Defers heavyweight arena, full-party actor, and global WZX prewarm on Android. Battle entry warms only active battlers; bench Pokémon are prepared when switched in.
- Adds Android GC fences between queued WZX extraction jobs and heavyweight first-run extraction stages.
- Releases battle-resident Pokémon/Waza GPU caches and MoveFX metadata at battle end on Android while preserving generated disk caches and compiled shaders.
- Removes the unused trainer `ArmWeight` vertex attribute, lowering trainer meshes from 16 to 15 vertex attributes.
- Synchronizes CacheManager with extractor 13 / trainer identity 12 so a valid 1.7.1+ cache is not mislabeled stale.
- Audio probing now fails closed on unknown platforms; Android still intentionally falls back to native game audio because the bundled Amuse renderer is Windows-only.
- Package path/case and native-process sweeps found no additional Android visual-runtime path blockers.

For Android, test this build on the current public Gen1Recomp release first. Old Android launcher/picker/mod-manager failures that occur before CBE loads cannot be fixed from inside the mod.
