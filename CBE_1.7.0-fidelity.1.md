# Colosseum Battle Environments 1.7.0-fidelity.1

## Source-motion / MoveFX fidelity candidate

This build is intentionally aggressive on presentation while keeping the stable 1.6.1 battle/import base intact.

### Trainer motion
- Decisive trainer actions now replay the retained chronological Colosseum B1 source poses at full authority instead of stopping at an 84% morph ceiling.
- The source timeline follows the actual retained sample positions (gesture 20% -> 52% -> 84%; reaction 36% -> 68%) and returns to the source rest body.
- The second spring/low-pass layer is removed while an authored action owns the trainer. This eliminates the visible shoulder/hand lag that made source poses read like a procedural puppet.
- Procedural root movement during authored actions is reduced to ~0.5% continuity only. Idle continuity remains restrained and filtered.
- Player capture/send-out hand anchoring uses the exact same live source weights as the visible trainer, so the prop stays synchronized with the source motion.

### MoveFX / camera composition
- Attack and damage WazaSequence instances now carry the same BattleDirector presentation serial. They are treated as two chapters of one move presentation rather than unrelated effect sessions.
- The source-led camera preserves the final attack pose across the attack -> damage Waza boundary and blends only the first eight source frames of the new instance. This removes the hard impact-camera snap without reintroducing slow generic easing.
- Existing 60 Hz WazaSequence, GPT1 particle, HSD type-2 model, source audio, source attachments, and actor-scaled fight geometry remain the effect authority.
- Opaque retail controller types remain preserved but are not falsely claimed as decoded.

### Base retained
All 1.6.1 visibility, floor-collision, capture, import, compatibility, and fail-open audio hardening remains intact.
