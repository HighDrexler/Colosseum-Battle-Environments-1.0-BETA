# Colosseum Battle Environments 1.6.1

## Presentation-stability pass

1.6.1 is a targeted stability/fidelity update over 1.6.0. It does not change battle mechanics, disc-import rules, or the release cache format.

### Pokémon damage / visibility

- A live 3D battler is never intentionally hidden by damage. Capture, explicit recall/withdraw, and the completed faint-removal tail remain the only normal removal paths.
- Dense native PKX reaction pages (`damage/pageN`, `damageHeavy/pageN`, `faint/pageN`) now pass through the same root-travel stabilizer as the original single-page banks. Earlier builds accidentally skipped these pages because the guard matched only exact action names.
- If a decoded reaction pose would move the complete model an implausible distance below its base body, CBE holds the already-resident base body for that frame instead of allowing a blank/off-camera reaction.
- If an optional native action mesh faults while drawing, the resident base model is drawn in the same frame rather than turning a source-action failure into invisibility.

### Solid arena floor

- Floor collision is evaluated from the lower bound of the currently blended native pose and conservatively includes fallback pitch/roll.
- The collision equation now includes all presentation lift already applied to the actor. This closes the case where a negative faint/reaction lift could be applied after the old floor calculation and still sink geometry through the deck.
- The invariant is the final transformed lower bound: the complete Pokémon mesh must remain at or above the arena ground plane until its legitimate removal presentation begins.

### Trainer presentation

- Native B1 poses remain the main pose source, but the hard morph ceiling is reduced to avoid extreme hinge/action-figure silhouettes.
- Procedural whole-body root motion is reduced to a ~1% continuity layer; ambient sway, bob, lean, arm drift and Miror B.'s body groove are substantially reduced.
- Repeated/duplicate damage events cannot rapidly restart the same brace/concern pose.
- Tiny chip damage no longer causes a full trainer reaction. Large hits escalate to concern; medium readable hits use a restrained brace.
- Faint reactions enter near the end of the Pokémon's authored faint beat instead of almost immediately, keeping the Pokémon KO as the primary visual event.

### MoveFX ownership

- A WazaSequence timeline is now exclusive timing/lifecycle authority for its attack or damage phase. CBE will not start a separate whole-role GPT1 VM beside a valid retail Waza timeline.
- Damage presentation performs one Waza start at the authoritative damage boundary instead of attempting the director path and then a second sequence path.
- Exact duplicate Waza SequenceEntry launches are suppressed by sequence serial + source entry identity while distinct retail entries and genuine multi-hit impacts remain valid.
- Missing PKX timing points stay inside WazaSequence's explicit source-timing fallback rather than causing the renderer to switch to a second unrelated effect path.
- Direct decoded-GPT1 staging remains only as compatibility behavior for older generated caches that contain a role program but no Waza timeline.

### Compatibility

All 1.6.0 import/extraction hardening remains unchanged: raw ISO/GCM, structurally valid CISO/scrubbed media on compatible launchers, bounded source reads, and fully fail-open optional audio behavior.
