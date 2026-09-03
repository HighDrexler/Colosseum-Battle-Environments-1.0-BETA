# CBE 1.7.4-android-runtimecache-camera-audio.1

Android performance/cache, camera-direction, and portable-audio follow-up to 1.7.3.

## Android runtime-ready cache
- `Arena.prewarmResident()` loads the selected arena/trainer scene from the existing generated cache at `game.ready`, but intentionally leaves the mobile framebuffer/depth target lazy.
- Cached party Pokémon are queued once, the lead is materialized immediately, and the remainder are warmed one at a time during non-battle input frames.
- Lead-party MoveFX banks are queued at `game.ready` and drained at most one bank every 0.8 seconds outside battle.
- Battle-end trim now retains the first three cached party actor scenes and parsed MoveFX metadata while releasing non-party species and heavyweight Waza GPU resources. Generated disk caches are never discarded.

## Camera
- Camera time is monotonic wall-clock presentation time. Battle speed remains visible only as diagnostic logic state and cannot scale camera velocity.
- Damage/status/faint notifications no longer advance the angle variant independently from the move that caused them.
- Waza source camera targets remain authoritative for composition but are velocity-limited for eye, focus, and FOV motion.

## Android audio
- Adds portable pure-Lua GameCube DSP-ADPCM extraction for `snd_se_battle` sample 92 using only the exact byte range required from `snd_se_battle.samp`.
- Writes `assets/audio/colosseum_battle_transition.wav` and `.cbe-audio-portable-v1.complete` on Android/non-Windows. Once present, the build pipeline now returns directly from that marker with **zero source-disc opens and zero cache rewrites** on subsequent boots.
- This does **not** falsely claim full MusyX song parity: the 23 remaining sequenced theme/capture assets still need a portable MusyX sequencer. Windows continues to use the existing Amuse 24/24 conversion path.

No Pokémon Colosseum ROM data is bundled. Existing 1.7.3 visual caches remain valid; no visual cache revision bump is required.
