# Validation — CBE 1.7.22 trainer morph unification

## The load-bearing assumption

The two-slot design is only lossless if no more than two source poses are ever
active simultaneously. Verified directly against the shipped
`TrainerPerformance`:

- 10 trainers × 10 action kinds (`opening`, `throw`, `sendout`, `recall`,
  `command`, `brace`, `concern`, `frustration`, `victory`, `defeat`)
- × both sides × three strengths × 401 timeline steps per action
- = **240,600 motion samples**

Results:

- Maximum simultaneously non-zero source poses: **2** (worst case
  `red/opening` at t=0.381)
- Weight sums never exceed 1.0, so the shader's `clamp(sum,0,1)` never
  saturates differently than before
- `actionPair` never drops an active pose: **0 mismatches** across the sweep
- Slot weights match the source weights to within 1e-12

Conclusion: the seven-attribute shader is **exactly** equivalent to the
fifteen-attribute one for every state the performance system can produce.

## Binding strategy

Exercised under mocked LÖVE builds:

| scenario | expected | result |
|---|---|---|
| LÖVE 11.3+ (`name, mesh, step, attachname`) | attached / `step4` | pass |
| LÖVE 11.2 (`name, mesh, attachname`) | attached / `name3` | pass |
| no `attachAttribute` | dynamic CPU fallback | pass |
| `newMesh` throws during probe | dynamic, no crash | pass |

Behavioural checks:

- correct dense attributes land in the correct slots (`Gesture3Position` →
  `ActionAPosition`, `Gesture2Position` → `ActionBPosition`)
- unchanged pair causes **zero** rebinds (idempotent per frame)
- a pair change causes **exactly one** rebind
- idle binds the bind pose into both slots, with both mixes at zero
- dynamic fallback performs exactly one vertex upload per pair change
- `compactVertex` emits 20 floats with correct offsets (base 1-3, breath 9,
  look 12, action slots pulling gesture3=21 / reaction1=30)

## Static checks

- All 57 Lua files load cleanly
- `manifest.json` parses; version matches `main.lua` `VERSION`
- No leftover references to any removed Windows-only symbol
- Trainer cache `formatVersion=26`, 44-float sidecar stride, and all
  BuildPipeline markers unchanged → **no rebuild**

## What could NOT be verified here

There is no LÖVE runtime, GPU or Colosseum disc in this environment. The
following need on-device confirmation:

1. **`attachAttribute` self-attachment on a real GPU.** The probe validates the
   call signature, not the driver's behaviour. Check `trainer.morph.mode` in
   `exports.status()` — it should read `attached`. If it reads `dynamic` on a
   platform that should support it, the probe found a signature mismatch worth
   reporting.
2. **Windows.** This is the platform that gains the most (2 → 10 poses, plus
   sidecar loading). Worth checking first, and worth comparing a trainer
   send-out against 1.7.21 side by side.
3. **Android attribute count.** Confirm trainers still render on the weakest
   device you have; this is where the 15 → 7 reduction should matter most.
4. **Shadow and Poké Ball meshes**, which share the trainer vertex format and
   now follow the binding mode rather than the OS.
5. `trainer.morph.rebinds` should climb by roughly four per trainer action, not
   per frame. Per-frame growth means the pair key is thrashing.
