# CBE 1.7.22 — trainer morph unification

Step B of the trainer animation work. **No cache format change and no rebuild:**
trainer cache `formatVersion=26`, the 44-float runtime sidecars, and every
BuildPipeline marker are untouched. Drop-in over 1.7.21.

This release does not yet add new source clips. It removes the ceiling that
made adding them impossible, and along the way fixes a real platform disparity.

## What was wrong

There were two divergent trainer animation paths:

| | attributes | source poses reachable | runtime .f32 sidecar |
|---|---|---|---|
| non-Windows (before) | **15** | 10 | yes |
| Windows (before) | 7 | **2** | **no** |
| all platforms (now) | **7** | **10** | **yes** |

Two consequences:

1. **Windows ran materially worse trainer animation than everything else** — two
   morph slots instead of ten. It also couldn't use the compact runtime mesh
   sidecar, so it loaded trainers more slowly, and it had to keep every dense
   Lua vertex row resident in order to rewrite meshes on the fly.
2. Fifteen enabled vertex attributes is above the eight GLES2 guarantees and at
   the sixteen most mobile drivers cap at. That is a genuine robustness risk on
   weaker Android hardware and a plausible contributor to trainer-side lag.

## The key observation

`TrainerPerformance`'s `adjacentWeights` timeline **never produces more than two
non-zero source-pose weights at once**. The ten attribute slots existed only so
the pose data could sit statically in the vertex buffer — the shader never
blended more than two of them.

So the Windows shader was always the correct general design. It simply had no
way to reach the other eight poses.

This was verified, not assumed: **240,600 motion samples** across all 10
trainers × 10 action kinds × both sides × three strengths × 400 timeline steps.
Maximum simultaneously active source poses: **2**. Weight sums never exceed the
shader's clamp. See VALIDATION.

## What changed

New shared module `lib/TrainerMorph.lua`, used by both `Trainer.lua` and
`PlayerTrainer.lua` so the enemy and player actors can no longer drift apart.

- **One seven-attribute vertex program for every platform** — the previously
  Windows-only shader, whose blend math is unchanged.
- The dense 44-float mesh is kept **exactly as the cache and sidecar already
  store it**. Whichever two source poses are currently active are rebound into
  the two shader slots with `Mesh:attachAttribute` against the mesh's own
  attributes. No extra buffers, no uploads, no cache change.
- The active pair only changes about four times across a ~1.5s clip, and
  `bindPair` is a no-op when it hasn't changed.
- LÖVE moved `attachAttribute`'s argument order between 11.2 (`name, mesh,
  attachname`) and 11.3 (`name, mesh, step, attachname`), and some forks omit it
  entirely. The exact call is **probed once at runtime**, with the proven CPU
  rewrite path retained as a fallback — now available on any platform rather
  than being Windows-only.

`exports.status()` reports the chosen strategy under `trainer.morph` /
`playerTrainer.morph`: `mode` (`attached` or `dynamic`), `attachStyle`,
`rebinds`, `rewrites`.

## Why this unblocks step A

With ten poses costing two attributes instead of ten, the number of distinct
source clip families is no longer limited by the attribute budget. The extractor
can retain `send` / `recall` / `command` / `react` / `win` / `lose` as separate
clips instead of collapsing everything into one gesture clip and one reaction
clip — which is the actual reason a Poké Ball throw, a recall, a command and a
victory currently look identical.

That work still needs the disc in hand. Step C (the clip-inventory diagnostic)
comes next.

## Deliberately unchanged

Animation timing, phase curves, root motion, event wiring, ball anchoring,
`TrainerRig` landmarks, `TrainerPerformance` profiles and durations, and every
cache format. This release changes **how** the existing poses reach the GPU,
not which poses play or when.
