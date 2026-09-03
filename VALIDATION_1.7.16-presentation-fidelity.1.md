# Validation - 1.7.16-presentation-fidelity.1

Static validation is performed in the build environment. This is not a physical Windows/Android runtime certification.

Checks:
- all Lua files parse through LuaTeX `loadfile`;
- manifest/main version parity;
- portable audio v5 marker/rate/migration policy assertions;
- camera HUD-safe, wall-clock axis-lock and hold-policy assertions;
- Water-profile grading assertions;
- MoveFX dual selector ordinal assertions;
- ZIP integrity.

Live acceptance targets:
1. Ember / Flame Wheel / unrelated projectile moves: source particles should remain visible between attacker and target and no native Crystal visual fallback should mask failures.
2. Android attack sequences: lower HUD must not cover the principal combat line.
3. 1x/2x/4x battle speed and A-spam: camera velocity and cut cadence remain stable.
4. Android soundtrack: regenerated v5 WAVs play through the file-backed host music path; compare timbre to source.
5. Water Colosseum: darker steel/mineral gray undertone without crushing source textures.
