# Android audit — CBE 1.7.2-android.1

This is an Android-specific sweep of the 1.7.1-fidelity.1 runtime and extraction path. It targets failures that desktop systems can hide through larger RAM/VRAM budgets, physical keyboards/mice, legacy file access, or Windows-only helpers.

## Fixed in this build

1. **Manifest load blocker:** 1.7.1 declared `compute`, which is not a valid current API-2 permission. Removed.
2. **Legacy import OOM:** the no-range-import compatibility path could buffer the full Colosseum disc into one Lua string. Sources over 128 MiB now fail safely with an explicit launcher-upgrade message instead of attempting the allocation.
3. **Bounded import compliance:** native Colosseum reads remain chunked to at most 8 MiB, matching the current required-import read contract.
4. **Nested cache writes:** the compatibility filesystem cache now creates parent directories before writing generated artifacts.
5. **Cache write parity:** the legacy cache bridge enforces the native API-2 64 MiB per-key write ceiling instead of behaving differently from the current launcher.
6. **Touch-only recovery deadlock:** the first-run failure gate now exposes tappable Retry / Continue / Exit controls; a physical keyboard is no longer required to recover from extraction/import failure.
7. **High-DPI GPU pressure:** Android's arena color/depth render target is capped to an aspect-preserving ~1280x720 pixel budget rather than blindly allocating at physical phone/tablet resolution.
8. **Startup memory spike:** Android skips heavyweight arena, full-party Pokémon actor, and global WZX prewarm at `game.ready`.
9. **Battle-entry actor pressure:** Android prewarms only the two active battlers. Bench species are deferred until the actual switch boundary.
10. **MoveFX extraction pressure:** Android forces a full Lua GC fence between queued WZX extraction jobs.
11. **Long-session VRAM/RAM creep:** at the authoritative battle-end boundary Android now releases Pokémon scene/action meshes, Waza meshes/textures, and MoveFX metadata caches while keeping generated disk caches and compiled shaders. This prevents an ever-growing species/move GPU cache across many battles.
12. **Trainer GPU attribute pressure:** the unused `ArmWeight` vertex attribute was removed, lowering trainer meshes from 16 attributes to 15 while keeping the source deformation data used by the shader.
13. **Extraction transient memory:** full GC fences now run between the largest first-run extraction stages, including FSYS, arenas, trainers, capture, and transition generation.
14. **Cache revision mismatch:** `CacheManager` now agrees with extractor 13 / trainer identity 12 so a valid 1.7.1+ generated cache is not incorrectly reported stale and rebuilt.
15. **Unknown-platform audio hazard:** the Windows Amuse renderer is attempted only on Windows; unknown/Android platforms fail closed to visual-only operation.
16. **Package path/case audit:** all packaged module/resource references were checked for case-sensitive path mismatches; none were found.
17. **Native-process audit:** all direct Windows process/thread assumptions are confined to the optional audio conversion path; the visual runtime does not depend on them.

## Android launcher / storage findings

- The Colosseum source is ~1.46 GB logical size. Current Gen1Recomp required-import support handles large sources through bounded reads; CBE must not emulate that by reading the whole source into Lua.
- Android file selection is launcher-owned through the system document picker / Storage Access Framework. CBE never receives or depends on a desktop-style host filesystem path.
- Required-import validation happens before `main.lua`. If the selected ISO/CISO bytes do not match a digest admitted by the manifest, CBE cannot inspect or repair that source after the fact.
- Older Android Gen1Recomp builds have had picker/import and mod-manager failures before mod code runs. For Android testing, use the current public Gen1Recomp release rather than an older 0.1.x build.
- CBE keeps its declared floor at `>=0.2.11`, but this Android pass is intended to be tested first on Gen1Recomp **v0.2.44** (current on 2026-08-31).

## Remaining Android parity / risk items

### Colosseum audio
CBE's ISO-derived Colosseum audio conversion still depends on bundled Windows `amuserender.exe` + `cmd.exe`. Android intentionally skips that path and retains the visual runtime. Full audio parity requires a portable MusyX/Amuse decoder or an engine-owned conversion service; launching the Windows helper on Android is not a valid solution.

### Manual camera input
The automated cinematic camera works on Android, but the optional free/manual camera controls are still mouse/keyboard-oriented. This does not block battles or arena rendering. A future mobile-control pass should use an explicit multi-touch gesture scheme so camera input cannot steal normal battle-menu taps.

### Very large lazily generated Pokémon action banks
Pokémon action caches are already split by semantic action and loaded lazily, which avoids the old monolithic cache. Extremely large dense source banks can still create significant transient strings/meshes when first materialized. This build mitigates the Android peak by deferring bench actors and trimming battle-resident GPU caches; a future cache-format revision could page these banks even more aggressively if real-device logs identify a specific species/action crossing the current cache/write budget.

## What was not changed

- No battle logic, damage, move selection, AI, encounter, or generation mechanics were changed.
- Arena independence from Battle Art / StadiumFX / other Pokémon art providers is unchanged.
- 1.7.1 trainer-source animation and layered MoveFX fixes remain intact.
- Generated source assets are still derived only from the user's launcher-imported Colosseum disc.

## Validation scope

The package was statically audited, Lua-parsed, archive-verified, and checked against the current documented Gen1Recomp import/cache/sandbox contracts. This environment cannot execute the Android Gen1Recomp APK/GLES runtime itself, so physical-device validation is still required for GPU-driver, OEM-memory-killer, and Storage Access Framework behavior.
