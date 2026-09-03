# CBE 1.7.7-android-audio-fidelity.1

## Android audio-fidelity rebuild

This candidate replaces the first-generation portable MusyX mix path used by 1.7.5/1.7.6. The old Android soundtrack cache was functional but baked at 16 kHz and omitted or approximated several mixer behaviors that materially affect tonal balance.

### Changes

- Portable MusyX output rate: **16,000 Hz -> 32,000 Hz** (native MusyX synthesis bandwidth).
- Amuse-derived normal and DLS volume lookup curves replace linear gain and the old fixed `0.28` master attenuation.
- Voice gain now follows the same major staging order as Amuse: layer/current user volume, SoundMacro volume, envelope/ADSR, velocity, nonlinear volume law.
- Channel volume changes use a 5 ms slew instead of hard steps.
- Stereo placement uses Amuse's -3 dB square-root pan law.
- GameCube DSP playback starts with predictor history `(0,0)`; SDIR history is no longer incorrectly applied to the first transient.
- Sample-rate conversion uses interpolation rather than nearest-neighbor reads.
- Controller-driven ADSR (CC20/22/23/24 in the Colosseum bank), CC7 volume, CC10 pan, CC91 reverb, mod-wheel vibrato, and keygroups are retained in the portable render.
- Portable Aux-A implements the same ReverbStd parameter family initialized by Amuse's default Studio (coloration 0.5, mix 0.8, time 3.0 s, damping 0.5, pre-delay 0.1 s).
- Cache marker advances to `cbe-audio-portable=3` / 32 kHz / `lua-musyx-battle-fidelity-v2`.
- A v3 pending marker permits interrupted regeneration to resume. On the first migration, only the 23 MusyX-derived WAVs are invalidated; the transition cue has its own revised DSP decoder marker and regenerates only when needed.

### Preserved

All 1.7.6 performance/cache behavior, 1.7.5 full audio runtime wiring and Random arena selection, 1.7.4 wall-clock camera behavior, 1.7.3 Android battle-host fallbacks, trainer/source animation work, MoveFX, capture, and Gen 1/Gen 2 behavior remain present.
