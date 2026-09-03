# Colosseum Battle Environments 1.7.22-trainer-morph-unification.1


## 1.7.22 trainer morph unification

Step B of the trainer animation work. No cache format change and no rebuild.

Trainer animation ran on two divergent paths: non-Windows declared FIFTEEN
vertex attributes to reach ten source poses, while Windows declared seven and
could only ever reach TWO -- so Windows ran visibly poorer trainer animation,
could not use the compact runtime mesh sidecar, and kept every dense vertex row
resident to rewrite meshes on the fly. Fifteen enabled attributes is also above
the eight GLES2 guarantees and at the sixteen most mobile drivers cap at.

TrainerPerformance never produces more than TWO non-zero source-pose weights at
once (verified over 240,600 motion samples), so two attribute slots are
sufficient. All platforms now share one seven-attribute shader and reach all ten
source poses; the dense 44-float mesh is unchanged and the active pair is
rebound with Mesh:attachAttribute, with a probed CPU fallback for LOVE builds
that order or omit that call differently.

Windows gains full ten-pose animation and sidecar loading. Android drops from
fifteen enabled vertex attributes to seven.

This does not yet add new source clips -- it removes the attribute ceiling that
made adding them impossible. See CBE_1.7.22-trainer-morph-unification.1.md.



## 1.7.21 performance pass

Pure optimization release. No behaviour, visual, audio or cache-format change,
and every cache contract marker is identical to 1.7.20 -- an existing install
does NOT rebuild. See CBE_1.7.21-performance-pass.1.md for detail.

Cache build:
- SysDolphin LZSS decompressor inner loop inlined (~3.3x); every arena,
  trainer, Pokemon, Waza and audio member decompresses through it.
- GX texture decoder rewritten around interned bytes, precomputed expansion
  ramps and a decode-once TLUT (~5.4x overall; 16x on 4-bit paletted art).
- Vertex serializers and binary packers batched instead of one pack call,
  scratch table and intermediate string per vertex.
- Build progress UI no longer bypasses its own redraw throttle on every label
  change, so a 251-move pass stops paying hundreds of full-screen presents.
  Event pumping is kept per-call so Android never sees the app as unresponsive.

Runtime:
- The static sky is baked once into a cached canvas instead of being repainted
  as 40-72 filled rectangles every frame. Outdoor Wild's drifting clouds and
  projected sun remain live.
- Shader uniform presence is resolved once per compiled shader rather than via
  two pcalls per uniform per material group per frame.
- Transparent-pass sorting no longer runs trigonometry inside the comparator.
- Per-frame table/closure allocation removed from the arena draw path, Mat4
  (lookAt allocated four closures per call), Pokemon actor draw (13 string
  concatenations per actor per frame for uniform names), and the sprite
  compositor (a new Quad object every frame during a faint).
- Android no longer issues a driver getSystemLimits query every frame.

All rewritten decoders and serializers were verified byte-identical against the
1.7.20 implementations, including error paths and safety guards.



## 1.7.20 sprite-provider priority

- Colosseum Models remain an absolute presentation override. When ON, GC6E01 Pokémon actors are used and external 2D art is not allowed to replace them.
- When Colosseum Models are OFF, CBE now recognizes the current Battle Art 2.x package id (`BATTLE_ART_VOXEL_GEN2`) in addition to legacy fork ids.
- CBE consumes Battle Art's exported `BattleArt` / `AnimatedBattleArt` managers directly, because Battle Art STATIC/ANIMATED battle art is installed as live Image objects and is not guaranteed to appear as a changed `pokemon.sprite` path.
- Battle Art ANIMATED playback advances once per update; the selected frame is reasserted after the Gen 2 presentation facade refreshes immediately before draw.
- Battle Art STATIC is installed at the same consumer boundary. Battle Art MODDED deliberately yields to the next selected sprite provider; native sprites remain the final fallback only.
- No arena, audio, MoveFX, capture, trainer, or generated cache revision changes.

## 1.7.19 Water / faint / sprite parity

- Water (Phenac) Colosseum now uses a restrained source-material grade on desktop and Android instead of additive ambient+diffuse clipping. Pale limestone stays pale while grout, walls, water recesses and balcony cavities remain readable.
- Water no longer borrows Mt. Battle sky/cloud artwork for background gaps; the authentic M1 source shell is the venue, with only a neutral interior clear behind it.
- Gen 1 KO presentation is synchronized to the engine's actual queued faint slide. CBE no longer starts a model's faint animation at the early logical HP=0 event while the visible HP bar is still draining.
- Gen 2 CBE sprite-mode battles now resolve the live engine `pokemon.sprite` hook before native fallback, so selected Battle Arts/custom front/back art is preserved rather than replaced by stock Gold sprites.
- The 1.7.18 Gen 1 high-DPI/mobile full-viewport fix is unchanged.



## 1.7.18 Gen 1 viewport hotfix

- Fixes the remaining Gen 1-only CBE mini-screen regression on high-DPI/mobile layouts.
- Keeps the Android arena framebuffer at its performance-friendly logical/capped resolution, then scales the completed `worldOverride` to Gen 1's live physical playfield at final composition.
- Does not touch Gen 2's already-correct explicit surface scaling path.
- Retains the 1.7.17 arena-source refresh and camera readability/safe-volume changes unchanged.

Presentation-focused Colosseum battle environments for Gen1Recomp.

This candidate builds directly on 1.7.16 and focuses on arena/source fidelity plus battle readability:

- per-arena safe camera volumes for Water, Orre, Realgam, Wildlands and Mt. Battle;
- attacker/target screen-space validation for attack, impact, reaction, faint and switch shots;
- source/Waza camera preservation when readable, with pullback/widen correction before a safe-master fallback;
- a Gen 1-only final-compositor reset for the Mobile Battle UI quarter-screen regression, leaving Gen 2 untouched;
- fresh GC6E01 HSD extraction for Water, Orre, Realgam and Mt. Battle under the current material/GX-wrap serializer;
- current authored Wildlands recipe materialization with softer outer terrain relief and cleaner camera silhouettes;
- compact arena runtime mesh cache v2 so Android cannot reuse stale pre-refresh geometry.

Existing healthy 1.7.16 installs use an arena-only migration path: trainer, MoveFX, capture and audio caches remain reusable. Trainer-model fidelity work is intentionally deferred until this arena/camera candidate is stable.

