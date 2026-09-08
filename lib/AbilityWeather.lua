-- Weather adapter shared by optional abilities. Gen II keeps its native field;
-- Gen I uses the existing field extension with the same 1/8 sandstorm rule.
-- Do not require a foreign-generation module on a Gen I launcher boot.
local V=... or {}
local req=V.engineRequire or require
local W={}

local gen1Rules={WEATHER_TURNS=5,
  sandstormDamage=function(hp)return math.max(1,math.floor((hp or 8)/8))end,
  sandstormHits=function(types)
    for _,kind in ipairs(types or {})do
      if kind=="ROCK" or kind=="GROUND" or kind=="STEEL" then return false end
    end
    return true
  end,
}
local function weatherRules(generation)
  if generation==1 then return gen1Rules end
  return V.Gen2Effects or req('src.battle.gen2.Effects')
end

local function stateFor(battle, generation)
  if generation==2 then return battle end
  battle.field=battle.field or {}
  return battle.field
end

function W.get(battle, generation)
  local s=stateFor(battle, generation)
  if not s.weather then return nil end
  return {kind=s.weather, turns=s.weatherTurns, abilityLocked=s.weatherAbilityLocked==true}
end

-- opts.abilityLocked=true (Sand Stream): no turn limit, lasts until replaced
-- or the battle ends, matching this reference's Gen III ruleset text.
function W.set(battle, generation, kind, opts)
  local s=stateFor(battle, generation)
  s.weather=kind
  if opts and opts.abilityLocked then
    s.weatherTurns=nil
    s.weatherAbilityLocked=true
  else
    s.weatherTurns=(opts and opts.turns) or weatherRules(generation).WEATHER_TURNS
    s.weatherAbilityLocked=false
  end
end

function W.clear(battle, generation)
  local s=stateFor(battle, generation)
  s.weather=nil
  s.weatherTurns=nil
  s.weatherAbilityLocked=false
end

-- Cloud Nine suppresses weather's EFFECTS everywhere they're checked, without
-- clearing the underlying weather. hasCloudNine(mon) is supplied by the
-- caller (the effects installer, which knows how to resolve a mon's ability)
-- so this module never needs to know about ability resolution itself.
function W.isSuppressed(battle, hasCloudNine)
  if type(hasCloudNine)~="function" then return false end
  local values=V.Abilities and V.Abilities.actives(battle) or {battle.player,battle.enemy}
  for _,value in ipairs(values) do
    local mon=value and (value.mon or value)
    if mon and (mon.hp or 0)>0 and hasCloudNine(value) then return true end
  end
  return false
end

-- Speed multiplier for Chlorophyll (sun) / Swift Swim (rain). Returns 1 when
-- the ability's matching weather isn't active or is suppressed.
function W.speedMultiplierFor(battle, generation, mon, hasCloudNine, weatherKind, multiplier)
  local w=W.get(battle, generation)
  if not w or w.kind~=weatherKind then return 1 end
  if W.isSuppressed(battle, hasCloudNine) then return 1 end
  return multiplier or 2
end

-- Sand Veil's incoming-accuracy multiplier: only while sandstorm is active
-- and unsuppressed.
function W.sandAccuracyMultiplier(battle, generation, hasCloudNine, multiplier)
  local w=W.get(battle, generation)
  if not w or w.kind~="sandstorm" then return 1 end
  if W.isSuppressed(battle, hasCloudNine) then return 1 end
  return multiplier or 0.8
end

-- Generic residual sandstorm tick, generation-neutral. ctx provides:
--   ctx.actives()          -> list of {mon=, dealDamage=fn(dmg), types=fn()->{}, isImmune=fn()->bool}
--   ctx.hasCloudNine(mon)  -> bool
--   ctx.message(text)      -> emit a message (generation-specific transport)
-- Ability-set sandstorm (Sand Stream) never expires; move-set weather (Gen II
-- only, in this engine) counts down and clears at zero.
function W.tick(battle, generation, ctx)
  local s=stateFor(battle, generation)
  if not s.weather then return end
  -- A move that overwrites ability weather supplies a positive native duration.
  if s.weatherAbilityLocked and s.weatherTurns~=nil then s.weatherAbilityLocked=false end
  if not s.weatherAbilityLocked then
    s.weatherTurns=(s.weatherTurns or 1)-1
    if s.weatherTurns<=0 then
      local old=s.weather;W.clear(battle,generation)
      if ctx.message then ctx.message("The "..old.." ended.") end
      return
    end
  end
  if s.weather=="sandstorm" and not W.isSuppressed(battle,ctx.hasCloudNine) then
    local Effects=weatherRules(generation)
    for _,entry in ipairs(ctx.actives()) do
      if (not entry.mon or (entry.mon.hp or 0)>0) and (not entry.isImmune or not entry.isImmune())
          and Effects.sandstormHits(entry.types and entry.types() or {}) then
        local dmg=Effects.sandstormDamage(entry.maxHp and entry.maxHp())
        entry.dealDamage(dmg)
      end
    end
  end
end

return W
