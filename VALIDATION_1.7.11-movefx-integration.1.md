# Validation — CBE 1.7.11-movefx-integration.1

## Static/package checks

- 56/56 Lua source files compiled successfully with `texlua` `loadfile` syntax validation.
- `manifest.json` parsed successfully and reports `1.7.11-movefx-integration.1` with `main.lua` as the package entry point.
- The retail source-stem alias roster contains a row for every Gen I/II move ID 1-251.
- No unresolved merge/conflict markers were found in Lua/JSON/Markdown sources.

## Portable MusyX SFX test

A synthetic GameCube-style SFXGroup/POOL/SDIR/SAMP fixture was passed through the new `PortableMusyX.prepareSfx` + `renderSfx` path. The renderer:

- resolved the requested GameSound ID through its SFXGroup entry and PageObject/SoundMacro,
- produced one playable voice,
- produced non-zero PCM,
- emitted a valid RIFF/WAVE 32 kHz stereo file.

Synthetic result: `portable-sfx-ok bytes=12332 frames=3072 peak=0.022205 voices=1`.

## Transactional Waza SFX cache test

The new `WazaSfxBuilder` was exercised with two source-complete IDs and one deliberately missing SFXGroup ID. It:

- generated only valid source IDs,
- left the missing ID recorded as missing rather than manufacturing an approximation,
- removed temporary transactional files,
- accepted the completed marker/index on validation,
- reused the two existing final WAVs on a second run with zero rerenders.

Synthetic result: `waza-builder-ok ready=2/3 missing=1 rerenders=0`.

## Runtime audio ownership test

`WazaAudioRuntime` was tested against a mock audio backend. It verified that:

- a move with every typed type-5 GameSound cached is source-audio complete,
- legacy/untyped sound metadata cannot authorize native-audio suppression,
- a partial source set does not play one Colosseum sound over the native fallback,
- source GameSound playback occurs on the exact scheduled Waza entry,
- static audio residency remains bounded by the configured 32-source cache.

Synthetic result: `waza-audio-ok complete-gate + prewarm + timed source`.

## Windows trainer fail-open test

The native-trainer suppression wrapper was tested with mock trainer providers. Native trainer art remained visible while the 3D provider was not ready, hid only after the matching provider became active+ready, and became visible again immediately when readiness was lost.

Synthetic result: `trainer-failopen-ok`.

## Device/runtime scope

This environment cannot execute the actual Windows OpenGL/LÖVE battle runtime or Android GLES/audio backend. The Windows `.f32` sidecar recovery and full retail GC6E01 Waza/GameSound coverage therefore still require device testing. The build intentionally fails open: unsupported or missing source GameSound renders keep native Gen1/Gen2 move audio, and failed trainer/Waza binary meshes reopen canonical generated meshes rather than presenting invisible actors/effects.
