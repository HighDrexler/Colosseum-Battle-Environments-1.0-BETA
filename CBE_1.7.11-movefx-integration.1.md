# CBE 1.7.11-movefx-integration.1

This test build moves the Waza/MoveFX path from partial visual playback toward a full source-backed move presentation pipeline.

## Full move-bank cache

- Scans move IDs 1-251 with the same alias and attack/damage phase resolution used by runtime MoveFX.
- Writes `cache/movefx/index.lua` and `build/movefx_coverage.txt` so source coverage is measurable per move rather than inferred.
- Retains the canonical WZX payloads and interpreted Waza timelines for later decoder improvements without another disc import.
- Prebuilds compact float32 sidecars for type-2 Waza model meshes where the platform exposes `love.data.pack`; canonical generated mesh caches remain the correctness fallback.

## Source GameSound audio

- Reads typed Waza type-5 `GameSound` IDs from the extracted retail timelines.
- Resolves those IDs through the `snd_se_battle` SFXGroup, PageObject/SoundMacro, SDIR, and `snd_se_battle.samp` source chain.
- Generates 32 kHz PCM16 stereo WAVs under `cache/waza/sfx/<id>.wav` with transactional temporary-file verification.
- Reuses valid generated WAVs on resumed or repeated cache builds.
- Runtime audio ownership is all-or-native per move: CBE suppresses the native move-animation SFX only if every typed GameSound needed by the active Waza is present and can be loaded. Otherwise the normal Gen1/Gen2 sound remains audible and CBE does not partially layer source audio over it.
- The runtime source cache is bounded to 32 templates; exact Waza entries clone/play those sources at their authored timeline frames.

## Effect geometry

Waza model sizing now uses the current 3D actor geometry and source-to-target fight distance. Projectiles originate from attacker scale, target/damage effects track the affected actor, contact/impact effects use a bounded interaction scale between both battlers, and battlefield-wide effects remain world-space.

## Windows trainer recovery

A compact trainer runtime cache intentionally omits textual vertex arrays. If a graphics backend rejects its `.f32` mesh sidecar, 1.7.10 could continue with an empty group while native trainer art was already hidden. 1.7.11 reopens the canonical generated trainer HSD cache, renders it immediately, and may repair the binary sidecar. Native trainer sprites are now hidden only when the corresponding 3D provider reports both active and ready. The same binary-sidecar fallback is applied to Waza effect models.

## Performance policy

The larger one-time persistent MoveFX/GameSound cache is intentional. Battle-time work remains bounded: no all-move GPU preload, recent Waza meshes remain limited, and the GameSound source cache is capped at 32 entries. Existing 1.7.9/1.7.10 arena and actor runtime-sidecar caches remain reusable.
