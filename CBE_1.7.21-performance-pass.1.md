# CBE 1.7.21 — performance pass

This release changes **no behaviour, no visuals, no audio and no cache
formats**. Every cache contract marker (`cbe-runtime=2`, `extractor=13`,
`cbe-arena=7`, `cbe-trainer-identity=12`, `cbe-movefx-full=2`,
`cbe-audio=3`, `cbe-audio-portable=4`, arena `runtimeMeshVersion=2`, arena
source `version=32`, PKX `formatVersion=4`) is byte-for-byte identical to
1.7.20, so **an existing 1.7.20 install does not rebuild anything.** It is a
drop-in swap.

The target was the two complaints from weaker desktops and phones:

1. first-run cache builds approaching half an hour;
2. long waits between battles, and Colosseum models feeling heavy next to
   the battle UI.

Twelve files changed. Nothing else was touched.

---

## 1. Cache build

### `extract/FSYS.lua` — SysDolphin LZSS ring decompressor

This is the hottest function in the entire build: every arena, trainer,
Pokémon, Waza bank and audio member on the disc is decompressed through it.

The old inner loop ran, **per decompressed byte**: an `emit()` closure call, a
`heartbeat()` closure call, a `string.char()` allocation, and two `% 4096`
ring wraps — plus a `2^bit` exponentiation per flag bit. All of that is now
inlined; bytes come from a pre-interned 256-entry table, the flag word is
consumed by halving instead of exponentiating, ring wrap is a compare, and the
progress heartbeat fires once per flag group rather than once per byte.

**~3.3x faster, byte-identical output.** Verified against the original decoder
over 120 randomized streams covering runs, zero-fill, incompressible noise and
repeating patterns, plus the `expected=nil` header-derived path. The
`maxOutput` safety guard and the short-output assertion both still fire.

### `extract/GXTexture.lua` — GX texture decoder

Every texel used to allocate roughly eight temporary strings (`c8()` per
channel plus three concatenations), and paletted formats re-derived the colour
from the TLUT for **every single texel**.

Now: pre-interned byte strings, precomputed 4/5/6-bit expansion ramps, a
precomputed opaque-grey table for I4/I8, and the TLUT decoded **once** into
ready-made 4-byte pixels. CMPR builds its four block colours as scalars
instead of five throwaway tables per 4×4 sub-block. C14X2 memoizes on demand
rather than eagerly building 16384 entries for a small texture.

| format | speedup | | format | speedup |
|---|---|---|---|---|
| I4 | 10.2x | | RGBA8 | 3.5x |
| I8 | 9.2x | | C4 | 16.4x |
| IA4 | 5.0x | | C8 | 12.0x |
| IA8 | 3.6x | | C14X2 | 2.2x |
| RGB565 | 3.1x | | CMPR | 6.5x |
| RGB5A3 | 2.9x | | **overall** | **5.4x** |

Verified byte-identical over 900 randomized decodes across all eleven formats
at random non-block-aligned sizes and all three palette formats, plus
truncated-source behaviour and both error paths (unsupported format, paletted
without TLUT).

### Serializers and binary packers

- `lib/RuntimeMeshCache.packRows` made one `pcall` + one `love.data.pack` +
  one scratch table **per vertex**. Now batched 64 rows per call — **2.2x**,
  identical bytes.
- `extract/PokemonExtractor.runtimeVerticesBytes` had the same per-vertex
  pattern; batched the same way.
- `extract/PokemonExtractor.packedVerticesLua` built a parts table and ran
  `table.concat` per vertex; now writes straight into one buffer.
- `extract/ArenaBuilder` did the same via `vec()` for every arena vertex —
  hundreds of thousands per venue. Replaced with an append-in-place writer.

Both serializers were checked byte-identical including empty vectors, NaN and
infinity inputs.

### `lib/BuildProgressUI.lua`

The 45 ms redraw throttle was **bypassed whenever the progress label changed**
— and the extractors change their label per move, per species and per member.
A 251-move pass therefore paid hundreds of full-screen clear + `present()`
cycles, each costing a whole display frame on a phone, purely to redraw a
progress bar.

The throttle is now on elapsed time alone (still ~22 updates/second) and
`force` still bypasses it for stage transitions and the final frame.
Crucially, **event pumping was decoupled from redrawing**: the OS message
queue is still drained on every progress call, so Android will not flag the
app as unresponsive during a long synchronous build. Pumping without
redrawing is nearly free.

---

## 2. Runtime / frame time

### `lib/Arena.lua` — the sky was being repainted every frame

`drawBackdrop` painted its gradient as **40–72 individually filled
screen-width rectangles every single frame**, for artwork that is completely
static. On a phone that is 40–72 extra draw calls and state changes before a
single piece of arena geometry is submitted.

The original painter is unchanged in what it draws; it is now rendered **once**
into a cached canvas keyed by profile / framebuffer size / loaded scene, and
blitted thereafter. The bake happens before the arena framebuffer is bound, so
it never disturbs the live depth attachment, and it falls back to the original
immediate-mode painter if canvas creation is rejected by the backend.

Outdoor Wild's genuinely per-frame elements — the `sceneTime`-driven cloud
cards and the vp-projected sun — are split into `paintBackdropDynamic` and
still drawn live, in exactly the same position in the layer order. The
resulting image is unchanged for every profile.

### `lib/Arena.lua` — uniform traffic and per-frame garbage

- `sendShader` ran **two `pcall`s** (`hasUniform` then `send`) for every
  uniform. `drawGroups` sends nine per material group, per frame. Uniform
  presence is a property of the compiled shader, not of the frame, so it is
  now resolved once per shader object and cached (invalidated on shader
  rebuild and on `resetRuntime`).
- `drawCrowd` allocated a throwaway table per visible crowd sector per frame
  (`drawGroups({g})`) and re-derived the crowd policy and arena profile inside
  the loop. Both hoisted; single-group draw goes through a direct path.
- `drawTransparent`'s sort comparator called `worldCenter()` twice per
  comparison, and `worldCenter` runs `math.cos`/`math.sin` whenever the stage
  is yawed — O(n log n) trig every frame. Each group's squared eye distance is
  now computed once per frame and the sort compares plain numbers. Ordering is
  identical.
- Material fallbacks (`{1,1,1}`, `{0,0,0}`, `{1,1}`) were allocated fresh for
  every group that omitted the field. Now shared constants.
- `pixelSize` called `love.graphics.getSystemLimits()` — a driver query,
  through a `pcall` — **every frame on Android**. Both the texture limit and
  the derived canvas size are now cached per window size.
- `installActorServices` built a `renderSize` table and a fresh `project`
  closure every frame. Both are now allocated once; the projector reads its
  matrix and viewport from upvalues refreshed each frame, so consumers see the
  same `services.project(x,y,z)` contract and the same live values.
- `viewProjection` built a scale matrix and ran a full 4×4 multiply just to
  flip Y. That only negates one row of the perspective matrix, so it is done
  directly.

### `lib/Mat4.lua`

`lookAt` allocated **four closures** (`sub`/`norm`/`cross`/`dot`) plus five
intermediate vector tables on every call — that is every frame, per camera.
Rewritten on scalars. `mul` was unrolled; it is on the per-frame path for the
arena, both trainers and every visible Pokémon actor.

**3.0x on `mul`+`lookAt` combined, verified bit-for-bit identical across
40,000 randomized cases plus the degenerate ones the old closures
special-cased** (zero-length forward vector, forward parallel to up).

### `lib/PokemonActors.lua` — `Actor:draw`

- Morph-weight uniform names were built with `("w"..i)`: **thirteen string
  concatenations per actor per frame** for names that never change.
  Precomputed.
- `setBaseWeights` was a closure defined inside `draw`, allocated every frame.
  Hoisted.
- `materialColor` allocated a fresh 4-element table **per material group per
  actor per frame**, and `tintColor` allocated `{1,1,1,1}` every frame.
  `love`'s `send` copies immediately, so both now reuse a single scratch
  table.

### `lib/CurrentSpriteModels.lua`

- Five loops used `ipairs({"enemy","player"})` / `ipairs({"player","enemy"})`
  literals, rebuilt on every frame. Now module constants.
- `g.newQuad(...)` allocated a new LÖVE Quad object **every frame a Pokémon
  was fainting** — exactly when the frame budget is tightest. Reused via
  `setViewport`, with `newQuad` retained as the fallback.

---

## What was deliberately NOT changed

**`extract/PortableMusyX.lua` was left alone.** It is the other long pole —
the README already warns that first-run soundtrack synthesis takes several
minutes on mobile — but it is an 850-line synthesis engine where any change
risks altering rendered audio, and it already has an FFI fast path. The
risk/reward is bad next to everything above, and the audio cache is optional
and never blocks the visual runtime. If build time is still the priority after
this pass, that is the next thing to look at, and it should be done on its own
with A/B waveform comparison.

No changes were made to arena geometry, camera framing, sprite-provider
priority, MoveFX, trainer animation, the Gen 1 viewport fix, faint
synchronisation, or any cache format.
