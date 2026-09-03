# CBE 1.7.4-android-runtimecache-camera-audio.1 validation

Validation target: combined Android runtime-cache, speed-invariant camera, and portable-audio candidate.

## Executable checks

- **Lua parse:** 53 / 53 Lua files load through a Lua 5.4 syntax harness.
- **Manifest:** `manifest.json` parses, version matches `main.lua`, API=2, and the only requested permission is `engine_internals` (`compute` is absent).
- **Camera 4x invariance:** the real `lib/Camera.lua` was run twice against a controlled wall clock. The 1x run executed 60 simulation updates; the 4x run executed 240 updates over the same one second of wall time. At 0.20 / 0.50 / 0.80 / 1.00 s, phase, shot-lock remaining, event index, and last camera event were identical. The attack hold returned to passive at the same wall-clock instant in both runs.
- **Android completed-cache no-op:** the real `extract/BuildPipeline.lua` was run with a complete visual cache + portable-audio marker under an Android platform stub. Result: `READY / PORTABLE AUDIO CORE`, **0 source-disc opens and 0 cache writes**. This prevents a complete Android cache from doing source indexing/state rewrites every boot simply because the Windows-only 24/24 MusyX cache is absent.

## Real GC6E01 portable-audio validation

The portable DSP path was exercised with the actual user-provided tested CISO, not a synthetic fixture.

- CISO size: 664,830,528 bytes
- CISO MD5: `a2d58d82c6b76b42653dcd25c8966de7` (matches the tested digest declared by CBE)
- Disc identity after CISO reconstruction: `GC6E01`
- `common.fsys/snd_se_battle_sdir` located and decoded through CBE's actual FSYS reader.
- `snd_se_battle.samp` source located through the actual GameCube FST.
- DSP sample id: 92 / SFX 0x00CC
- Bounded SAMP payload read: 51,352 bytes
- Generated WAV: 179,756 bytes, mono PCM16, 22,050 Hz, 89,856 frames, 4.075102 s
- Generated WAV SHA-256: `e803c83427ce9918431bf9b8cfb58da8130dc21388045db06ad1a003e220b1b5`
- The same `AudioProbe.runPortableCore()` then recognizes its completion marker and reuses the WAV without decoding again.

## Runtime-cache policy checks

- Android `game.ready` materializes the selected generated arena/trainer scene without retaining the battle framebuffer/depth target.
- The lead cached party Pokemon is warmed immediately; remaining cached party actors are paced through non-battle frames rather than stacked onto the battle-entry frame.
- Android MoveFX prefetch is queued and paced outside battle.
- Battle end keeps a bounded party/recent Pokemon working set while releasing heavyweight Waza GPU resources; generated disk assets and compact parsed MoveFX metadata remain cached.
- Existing 1.7.3 arena/trainer visual cache markers remain valid; this patch does not force a full visual re-extraction.

## Package boundary

- No `.iso`, `.gcm`, `.ciso`, `.7z`, `baseroms/`, or user Colosseum source is included in the mod tree.
- Full Windows MusyX rendering remains isolated to the optional `AudioWorker`/Amuse branch. Android/non-Windows never enters that worker path.

## Known audio boundary

The portable path in this build proves and caches source-derived GameCube DSP audio on Android. It does **not** claim that the 11 sequenced battle themes or `me_snatch` are fully rendered on Android yet. Those assets are MusyX sequences whose correct rendering requires the project/pool/sample macro/sequencer pipeline; Windows continues to use Amuse for those 24 generated assets. Visual CBE functionality never depends on that full audio cache.

## Device validation still required

This environment cannot execute the Gen1Recomp Android APK on a physical GLES/mobile device. The package therefore passes executable Lua/source/cache tests here, while final performance, GPU-driver behavior, touch flow, and perceived battle-entry latency still require the Android device test.
