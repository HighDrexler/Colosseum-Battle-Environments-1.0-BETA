# CBE 1.7.16-presentation-fidelity.1

## MoveFX
- Keeps the 1.7.15 retail WazaSequence/type-3 particle runtime.
- Adds dual retail selector ordinal resolution (direct one-based and zero-based table conventions) for Waza roots and child generator references.
- No move-specific Flame Wheel/Ember hacks are used.

## Camera
- Attack, impact and reaction beats now remain on one camera variant/action axis instead of cycling variants at every event.
- Damage can no longer interrupt an attack camera until 0.72 wall-clock seconds.
- Source Waza camera translation/focus/FOV rates were reduced to 30 / 22 world units/s and 24 degrees/s.
- Android/iOS attack, damage, reaction and faint shots use a HUD-safe optical shift plus modest lens widening so the action is not hidden by the lower battle controls.
- Source camera easing minimum increased to 0.42 s. Battle speed and repeated A input still do not multiply camera velocity.

## Android audio
- Portable soundtrack cache revision v5.
- Generated PCM is now 48 kHz.
- Resolved MusyX layer/keymap pan is preserved instead of being discarded in favor of channel pan only.
- v4 -> v5 is an audio-only transactional migration; valid non-audio caches are left alone.

## Water Colosseum
- Reduced cyan/white water exposure and highlight energy.
- Opaque venue materials get a Water-profile-only cool-gray/desaturation grade.
- Backdrop exposure and blue saturation reduced to restore source-like gray undertones.
