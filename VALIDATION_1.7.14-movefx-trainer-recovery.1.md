# Validation — 1.7.14-movefx-trainer-recovery.1

This file records non-device validation for the regression-recovery build. Physical Windows/Android runtime execution was not available in the build environment.

## Completed checks

- 56/56 Lua files parsed successfully with `texlua` / `loadfile`.
- Lean-context Waza harness: a type-3 particle handler started from `{battle, game}` while StandaloneHost reported active, launched exactly one GPT1 VM, and left one source FX instance resident.
- Source-only ownership harness: with a live CBE world, native visual and native move-animation composition are suppressed while native audio remains unsuppressed without complete source GameSound ownership.
- MoveFX v2 marker harness: a 251/251 revision-16 index is accepted; a 250/251 index, a missing move row, and a legacy marker are rejected.
- Windows trainer source check: both trainer renderers retain dense source rows, use a seven-attribute compact animated Windows format, send breath/look/action weights, and refresh dynamic Action A/B source targets rather than collapsing vertices to position/UV/normal.
- Source-stem alias table contains every numeric move id 1-251 exactly; the MoveFX/Waza runtime contains no Flame Wheel/`kaenguruma` special-case branch.
- Existing 1.7.13 generalized GPT1 dependency code is retained; the fix is lifecycle/ownership-wide rather than move-specific.

## Device verification still required

- Windows: both trainers render and visibly perform opening/sendout/command/reaction/victory/defeat motion.
- MoveFX: Flame Wheel and unrelated projectile/contact/field/status moves show Colosseum source effects with no Crystal/GB/GBC visual layer.
- MoveFX cache migration: first 1.7.14 launch revalidates to 251/251 and subsequent launches reuse the v2 marker without disc work.
- Android/mobile: no regression to battle-entry performance, trainer animation, or bounded MoveFX residency.
