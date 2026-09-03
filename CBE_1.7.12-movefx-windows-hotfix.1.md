# Colosseum Battle Environments 1.7.12-movefx-windows-hotfix.1

Targeted hotfix built from 1.7.11 after Windows footage showed two hard presentation failures: Flame Wheel could run with no visible fire at all, and both 3D trainers could remain absent on Windows while Android continued to render them.

## MoveFX

- Fixed a concrete Waza/GPT1 bank-selection bug. A Waza type-3 SequenceEntry selects the generator ROOT to start; it does not mean the remaining generators in that GPT1 bank are irrelevant. Controller roots can spawn sibling/child generators by REF id. 1.7.11 filtered those children out of the VM template pool, so a correctly timed controller could execute while producing no visible particles. The runtime now retains the complete selected phase/source bank and uses `rootRef` only to choose the auto-start generator.
- Fixed a second Lua selector bug in that same path: the `a and b or c` pseudo-ternary caused an unselected authored root to auto-start whenever an exact selected root comparison returned false. Entry root selection is now explicit and unmatched retail metadata records a bounded phase-bank-root fallback instead.
- Source Waza startup gets a second authored-source seam if BattleDirector/provider timing did not arm the attack serial.
- Native move visuals no longer disappear merely because CBE owns the arena. Native visuals fail open for unprepared/unmapped source moves; source-ready move/capture ownership suppresses them narrowly.
- Waza Type-2 runtime sidecar failure now reopens the canonical generated model cache instead of treating the effect as empty.

## Windows trainers

- Windows now uses a compact trainer compatibility vertex path: position + UV + normal, with a minimal 3D shader and the existing whole-body source performance transform. Android/mobile keeps the dense source-morph trainer path.
- Windows bypasses compact enemy-trainer `.f32` sidecars and builds from the canonical generated HSD trainer cache, avoiding the backend-specific sidecar/attribute failure seen while Android accepted the same cache.
- Gen 2's shared `drawPic` path is now trainer-aware. The generic Pokemon-side suppressor previously also caught trainer intro pictures; if the Windows 3D actor failed, it could suppress the native fallback too. Trainer picture ownership is now controlled only by the 3D trainer capability gate.
- Native trainer art also fails open after an Arena trainer draw fault, not only after a trainer load failure.

## Cache / compatibility

No full cache rebuild is required. Existing 1.7.11 extracted Waza, GameSound, arena, Pokemon and trainer source caches remain compatible. Runtime sidecars remain disposable accelerators rather than authoritative source data.
