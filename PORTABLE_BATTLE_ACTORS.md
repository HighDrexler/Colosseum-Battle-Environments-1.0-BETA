# CBE Battle Presentation Compatibility v1

CBE discovers battle art by capability, not by package name. A mod does not
need to be listed in CBE's manifest, and none of these integrations is a CBE
dependency.

## Ordinary sprite replacements

The default path uses the image already resolved by the live battle state,
including `battle:picImage(...)`. A sprite mod that replaces that normal engine
image seam works without a CBE API.

Animated or context-sensitive sprite packages may publish
`mod.exports.battleSprites`:

```lua
{
  version = 1,
  priority = 0, -- optional; highest selected provider wins
  selected = function(context) return true end, -- optional
  resolve = function(context, side, battler, fallbackImage)
    return image -- or { image = image }
  end,
}
```

Returning `nil` or `false` uses the engine-resolved fallback for that side.
Resolver failure is also fail-open and cannot make CBE depend on the package.
`battleSpriteProvider` is accepted as an alias.

## Portable 3D actors

A mod that supplies real 3D Pokémon may publish `mod.exports.battleActors`:

```lua
{
  version = 1,
  portable = true,
  priority = 0,
  worldUnits = false, -- true receives the unscaled stage VP
  selected = function(context) return true end,
  available = function(source, dex) return true end,
  acquire = function(source, dex, variant, opts) return actor end,
  withRenderer = function(vp, callback, opts) return callback() end,
}
```

`opts` passed to `acquire` contains `side`, `context`, and `battler`. Renderer
options contain `eye`, `width`, `height`, and `context`. An actor may implement
`update`, `matrix`, `build`, `draw`, `spawn`, `idle`, `attack`, `hit`, `faint`,
`remove`, `attachment`, and `release`.
`attack(moveId, moveDef)` receives the visible move boundary. Actor `update`
uses presentation time normalized against logic fast-forward.

Lifecycle callbacks are presentation notifications only. `spawn(progress)` is
driven by the engine's authoritative send-out scale, and `remove(reason)` is
called only when the live battle slot is replaced or authoritatively hidden.
Providers must not mutate battle state or decide damage, fainting, switching,
or replacement.

`attachment(name)` may return `{ matrix, boneIndex, source }` for a source-authored
body-map point such as `origin`, `mouth`, `chest`, `tail`, `center`, hands, feet,
or eyes. Return `nil` when that joint matrix is unavailable; hosts must not
invent a bounding-box attachment as a substitute.

The service draws only into the caller's active color/depth target and must not
clear or replace the canvas, UI, arena, camera, or battle state. Declining one
species falls back only that side to the resolved 2D sprite.

## Portable custom presentation

A renderer that needs more control than individual actors may publish
`mod.exports.battlePresentation` (alias `battlePresenter`):

```lua
{
  version = 1,
  portable = true,
  priority = 0,
  selected = function(context) return true end,
  begin = function(self, context, arena) return true end,
  update = function(self, context, dt) end,
  drawWorld = function(self, context) return true end,
  covers = function(self, context, side) return true end,
  event = function(self, context, name, payload) end,
  finish = function(self, context, reason) end,
}
```

`drawWorld` runs inside CBE's arena pass. `covers` is evaluated per side, so a
provider can decline one Pokémon without exposing or suppressing the other.
All calls are protected; a declined or failing provider falls back to resolved
sprites.

## Legacy full-frame renderers

A renderer that cannot lend portable actors can prevent compositor conflicts by
publishing `mod.exports.battleWorld` (alias `battleFullFrame`):

```lua
{
  version = 1,
  fullFrame = true,
  priority = 0,
  status = function(context) return { active = true } end,
}
```

CBE yields the full frame while it is active. This avoids double-rendering, but
portable actors or presentations are preferred because they preserve the CBE
environment.

## Optional direct registration

Normal discovery reads loaded mod exports every update and is load-order safe.
A provider may also find CBE and call:

```lua
local host = cbe.exports.battleCompatibility
host.register("MY_MOD_ID", "battleActors", actors)
host.unregister("MY_MOD_ID", "battleActors")
```

Valid kinds are `battleSprites`, `battleActors`, and `battlePresentation`.
Registration is optional and never required for exported-capability discovery.
