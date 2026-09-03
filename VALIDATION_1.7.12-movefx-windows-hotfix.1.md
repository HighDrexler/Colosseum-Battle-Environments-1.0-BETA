# Validation - 1.7.12-movefx-windows-hotfix.1

Static/runtime-harness validation performed in the build environment; no claim of a physical Windows/Android Gen1Recomp runtime test is made.

- Lua parse gate: all package Lua files parse with `texluac`.
- Manifest JSON parse/version gate.
- Package-root gate: `main.lua`, `manifest.json`, `mod.card`.
- Waza controller-child regression: selected root + sibling child in the same source bank retains both templates; only the exact root auto-starts; the root's REF spawn resolves the child.
- Waza unmatched-root regression: an invalid `rootRef` no longer silently auto-starts an unrelated root through Lua pseudo-ternary fallback; the explicit `phase-bank-root` diagnostic is set.
- Windows trainer policy static gate: compact three-attribute format and compact shader are present for player/enemy trainers; enemy runtime sidecars are bypassed on Windows; native trainer suppression consults Arena draw errors.
- Gen 2 trainer fallback static gate: shared `drawPic` distinguishes trainer calls from Pokemon battler calls so Pokemon-side ownership cannot erase a failed-open trainer.
- Forbidden-media scan: no ISO/CISO/GCM/RVZ/WBFS/GCZ source media packaged.
- Conflict-marker scan.
- ZIP integrity gate with `unzip -t`.

Device acceptance targets:
1. Flame Wheel visibly produces its authored source effect instead of a zero-FX attack.
2. Player/enemy 3D trainers render on Windows; if either 3D path faults, the stock trainer picture is not simultaneously suppressed.
3. Android trainer behavior remains on the existing dense path.
4. Unready MoveFX fails open rather than producing a completely blank move.
