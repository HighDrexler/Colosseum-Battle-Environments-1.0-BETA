# CBE 1.7.15-waza-runtime-rewrite.1

This build replaces the broken 1.7.14 Waza particle entry path with the retail Colosseum node layout and selector/resource-link model.

## MoveFX / Waza rewrite

- Fixes the fresh-cache blocker where `MoveFXExtractor` called `scanSequenceGPT1()` even though the helper did not exist. Fresh WZX extraction can now reach GPT1 program compilation instead of aborting before particle assets are cached.
- Advances the MoveFX cache revision to 17 and Waza parser revision to 4. The full MoveFX marker now requires `extractor=17`, `waza=4`, and `runtime=retail-selector-resource-link-v2`, forcing stale revision-16 move banks to rebuild while leaving arenas, Pokemon, trainers, capture assets, and soundtrack caches alone.
- Corrects the serialized WazaSequence common-layout sizes. Mode 1 uses `0x6C`, mode 2 uses `0x68`, and the normal layout uses `0x70`; 1.7.14 incorrectly parsed mode 2 eight bytes late.
- Corrects the retail Waza node fields used by timing and attachment: linked entry `+0x08`, source timing index `+0x0C`, target timing index `+0x10`, loader timing slot `+0x14`, state/resource-link key `+0x18`, flags `+0x1C`, attachment `+0x20`, part `+0x24`, position type `+0x28`, and timing points beginning at `+0x2C`.
- Rewrites type-3 particle parsing around the retail `WazaParticleData` layout: generator selector, animation mode, particle resource size, and particle format.
- Stops treating the type-3 selector as a guessed GPT1 "root REF". The runtime now uses the authored selector as the generator entry point and prefers the exact bank-local REF/selector match, with bank-local ordinal fallback only where the source bank has no REF table.
- Implements the retail type-3 shared-resource rule: a non-zero Waza `state` links to an earlier particle entry and reuses that entry's GPT1 resource bank instead of inventing a second bank from a REF search.
- GPT1 bank correlation now comes from the typed Waza timeline itself. The old byte-before-`GPT1` probe remains diagnostic-only fallback data.
- Type-4 procedural Waza entries now expose their proven effect family and authored frame count from the source descriptor instead of being completely anonymous in diagnostics.
- Waza runtime version is advanced to 6 and GPT1 VM version to 11.

## What this test is for

The highest-priority check is visible source MoveFX. Moves such as Flame Wheel, Ember, Flamethrower, Thunderbolt, Surf, Blizzard, contact moves, and status moves should now reach their actual Waza particle selector/resource path rather than starting an empty timeline.

This build does not claim that all thirteen procedural type-4 effect families are visually 1:1 yet. Their source family/timing is now retained so the remaining family-specific renderer work can be completed without another Waza structure rewrite.
