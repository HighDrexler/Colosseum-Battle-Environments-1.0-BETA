# Validation — CBE 1.7.21 performance pass

All optimized code was executed against the 1.7.20 implementation under a real
Lua 5.4 interpreter and compared for exact equality. Nothing below is an
estimate.

## Equivalence

| Component | Test | Result |
|---|---|---|
| `FSYS.decompressLZSS` | 120 randomized LZSS streams (runs, zero-fill, incompressible noise, repeating patterns) round-tripped through a reference encoder; both the `expected`-supplied and header-derived `expected=nil` paths | byte-identical to 1.7.20 |
| `FSYS.decompressLZSS` | `maxOutput` safety guard; short-output assertion | both still fire |
| `GXTexture.decode` | 900 randomized decodes, all 11 formats, random 1–72px non-block-aligned sizes, all 3 palette formats | byte-identical |
| `GXTexture.decode` | truncated / short source data for every format | identical behaviour |
| `GXTexture.decode` | unsupported format; paletted without TLUT | both errors preserved |
| `GXTexture.dataSize` | all formats | unchanged |
| `Mat4.mul` / `Mat4.lookAt` | 40,000 randomized cases + degenerate cases (zero-length forward, forward parallel to up) | bit-for-bit identical |
| `Mat4` others | identity/translate/scale/rotateX/Y/Z/perspective | identical |
| `RuntimeMeshCache.packRows` | 60,000 × 12-component rows | identical bytes |
| `PokemonExtractor.packedVerticesLua` | 0/1/2/7/1000 vertices incl. NaN and infinity components | byte-identical |
| `ArenaBuilder` vector writer | 5,000 randomized vectors incl. empty and sub-epsilon values | byte-identical |

## Measured speedups (Lua 5.4, no JIT — a phone's floor, not its ceiling)

- LZSS decompression: **3.3x**
- GX texture decode: **5.4x** overall (I4 10.2x · I8 9.2x · IA4 5.0x · IA8 3.6x · RGB565 3.1x · RGB5A3 2.9x · RGBA8 3.5x · C4 16.4x · C8 12.0x · C14X2 2.2x · CMPR 6.5x)
- `Mat4.mul` + `Mat4.lookAt`: **3.0x**
- Binary vertex packing: **2.2x**
- Arena vertex serialization: 1.28x wall clock, and a much larger reduction in
  transient garbage — which matters more on a phone than in this timing.

## Cache compatibility

Confirmed identical to 1.7.20 by direct diff:

- `cacheVersion=2`, `extractorRevision=13`
- `cbe-runtime=2` / `extractor=13`, `cbe-arena=7`, `cbe-trainer-identity=12`,
  `cbe-movefx-full=2`, `cbe-audio=3`, `cbe-audio-portable=4`
- arena source `version=32`, arena `runtimeMeshVersion=2`, PKX `formatVersion=4`

An existing healthy 1.7.20 install therefore performs **no rebuild** of any
kind. Arena, trainer, Pokémon, MoveFX, capture and audio caches are all reused
as-is, and any caches written by 1.7.21 are byte-identical to what 1.7.20
would have written.

## Static checks

- All 56 Lua files load cleanly.
- `manifest.json` parses; version and `main.lua` `VERSION` string agree.
- 12 files changed in total; no other file differs from 1.7.20.

## Scope note

`extract/PortableMusyX.lua` was intentionally not modified. See the "What was
deliberately NOT changed" section of CBE_1.7.21-performance-pass.1.md.

## Suggested on-device checks

1. Launch with an existing 1.7.20 cache — confirm no rebuild is triggered.
2. Enter each arena (Water, Orre, Realgam, Wildlands, Mt. Battle) and compare
   the sky against 1.7.20; Outdoor Wild's clouds must still drift and its sun
   must still track the camera.
3. Confirm water/glass transparency still sorts correctly as the camera orbits.
4. Confirm crowd sector culling still behaves in Orre and Realgam.
5. Trigger a faint in both Gen 1 and Gen 2 sprite mode (the reused Quad path).
6. Rotate the device / resize the window to exercise backdrop and framebuffer
   invalidation.
7. `exports.status()` now reports `arena.backdropBaked` and
   `arena.backdropBakes`; the bake count should stay low and stable, not climb
   per frame.
