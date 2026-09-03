# CBE 1.7.8-android-audio-stability.1

## Android stability test pass

This candidate is built directly on 1.7.7 and targets three device reports: soundtrack recaching after a full app restart, progressive long-battle music corruption, and the CBE world rendering at quarter size when Mobile Battle UI is enabled.

### Portable audio cache v4

- Completion marker advances to `cbe-audio-portable=4` / `lua-musyx-battle-fidelity-v3-loop-boundary`.
- Adds `build/audio_portable_v4.complete` as a redundant non-hidden completion marker and `build/audio_portable_v4.migrating` as a durable migration journal.
- Missing `.pending` state no longer causes unconditional deletion of already-generated WAVs.
- A v3 cache is invalidated exactly once for the v4 audio migration. Interrupted v4 work resumes from existing assets instead of restarting at 1/24.
- If the last WAV commits before the completion marker, v4 can promote that finished migration on the next launch.
- Transition DSP audio remains on its independent core marker and is not unnecessarily regenerated.

### Long-battle loop correction

- PortableMusyX now recognizes MusyX TrackRegion `regionIndex == -2` as the authored loop sentinel.
- When all looping tracks agree on a loop-end tick, the generated `loopFile` ends at that tick. 1.7.7 instead included the renderer's release/reverb tail after the sequence loop boundary inside the file Gen1Recomp repeats forever.
- The 32 kHz mixer/fidelity work from 1.7.7 is otherwise unchanged.

### Mobile Battle UI isolation

- The CBE arena framebuffer pass resets the current graphics transform and scissor after `push("all")`, then restores the caller state afterward.
- HUD/mobile layout transforms can therefore resize the UI without changing CBE's 3D world canvas.
