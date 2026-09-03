# CBE 1.7.7-android-audio-fidelity.1 validation

## Result

Android audio-fidelity test candidate built directly on the complete 1.7.6 performance package. The visual/model/runtime performance changes are unchanged; this pass advances only the portable audio synthesis/cache contract plus version/docs.

## Real GC6E01 source audit

The previously supplied Pokemon Colosseum USA CISO was inspected through its real sparse CISO block map and GameCube FST:

- Logical source: GC6E01 revision 0.
- CISO block size: 2 MiB.
- GameCube FST: 1,872 files.
- `common.fsys`: 32 members; `bgm_archive.fsys`: 78 members.
- Real `snd_music_proj`, `snd_music_pool`, `snd_music_sdir`, all 11 battle sequences, and `me_snatch_song` were located/extracted successfully for format auditing.
- `snd_music.samp` is present at 3,659,136 bytes.
- The source battle-song pool contains 215 SoundMacros. Its actually present macro command set was audited before this pass; the meaningful mixer/sample commands used by the battle bank are covered by the portable path, while Amuse's age-count opcodes present in the pool are themselves unimplemented/no-op in upstream Amuse.
- Source song controller audit confirms heavy CC7/CC10/CC91 use plus CC20/22/23/24 ADSR-controller values in the relevant battle sequences. The v2 portable mixer now preserves those paths instead of flattening them.

## Portable mixer changes checked

- Portable output contract is 32,000 Hz PCM16 stereo for MusyX-derived assets.
- Old 16 kHz full marker is no longer accepted.
- New completion marker is `cbe-audio-portable=3` / `rate=32000` / `renderer=lua-musyx-battle-fidelity-v2`.
- New pending marker makes v3 regeneration resumable.
- First v3 migration removes only the 23 stale MusyX-derived WAVs and old v2 full marker; visual/model caches are untouched.
- Transition DSP marker also changes so the transition WAV is regenerated with fresh `(0,0)` predictor history rather than reusing the old decode.
- Portable full-ready requires both the revised transition core and the v3 full marker.
- No `rate=16000` portable-runtime references remain in packaged Lua.
- The old arbitrary `MASTER_GAIN` path is absent.
- Amuse-derived nonlinear volume tables, interpolated PCM reads, controller ADSR, 5 ms user-volume slew, -3 dB pan law, keygroup handling, CC91 Aux-A routing, and ReverbStd processing are present in the renderer.

## Package/static validation

- 55 Lua source files are present, the same source-file inventory as 1.7.6.
- The 1.7.6 package had previously passed 55/55 Lua parsing; 1.7.7 changes are limited to `PortableMusyX.lua`, `AudioProbe.lua`, `BuildPipeline.lua`, `CacheManager.lua`, version strings, and documentation. A Lua interpreter/compiler is not installed in the current container, so this candidate is not falsely labeled as a fresh 55/55 `luac` run.
- `manifest.json` parses successfully.
- `manifest.json` and `main.lua` both identify `1.7.7-android-audio-fidelity.1`.
- API-2 permissions remain `engine_internals` only.
- Launcher-required import metadata/digests are unchanged.
- No ISO/GCM/CISO/RVZ/WBFS/7z or `baseroms/` content is included.
- `main.lua`, `manifest.json`, and `mod.card` are at ZIP root.

## Device validation requested

This is intentionally a test build. The most important physical-Android comparison is the regenerated 1.7.7 soundtrack versus the same theme from the Colosseum ISO/Windows Amuse cache: tonal balance, high-frequency detail, percussion/bass balance, stereo image, reverb level, clipping, and first-generation time/thermals. The v3 audio rebuild is one-time; the existing 1.7.6 visual/runtime cache remains reusable.
