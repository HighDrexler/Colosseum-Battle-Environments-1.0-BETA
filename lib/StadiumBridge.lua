local V=...
local S={
  registered=false,
  delegated=false,
  arenaProviderId=nil,
  cameraProviderId=nil,
}

local mod=V.mod
local Arena=V.Arena
local Camera=V.Camera
local ArenaCatalog=V.ArenaCatalog
local BattleSettings=V.BattleSettings
local CurrentSpriteModels=V.CurrentSpriteModels
local ModLookup=V.ModLookup

local function cbeOwnsPokemonModels(ctx)
  local arena=ctx and ctx.arena
  local id=arena and tostring(arena.id or "") or ""
  if not id:find("^COLOSSEUM_BATTLE_ENVIRONMENTS:") then return false end
  local game=(ctx and ctx.game) or (ctx and ctx.battle and ctx.battle.game) or mod.game
  local arenasEnabled=not (ArenaCatalog and ArenaCatalog.enabled) or ArenaCatalog.enabled(game)
  local modelsEnabled=not (BattleSettings and BattleSettings.pokemonModelsEnabled)
    or BattleSettings.pokemonModelsEnabled(game)
  return arenasEnabled and modelsEnabled
end

-- StadiumBattleFX's Gen 1 host resolves its private `models` slot AFTER the
-- selected CBE arena begins.  That model registry is intentionally player-
-- selected, so CBE cannot reliably change it through the public resolve API.
-- Instead, make non-CBE model providers decline only while a CBE arena with
-- COLOSSEUM MODELS enabled owns the battle.  Arena.lua then renders CBE's
-- CurrentSpriteModels directly inside the same depth buffer.  The provider's
-- original begin contract is untouched everywhere else, including when the
-- CBE model toggle is OFF.
local function gateModelProvider(provider)
  if type(provider)~="table" or provider==CurrentSpriteModels then return false end
  if rawget(provider,"__cbeDelegatedModelBegin")~=nil then return true end
  local original=provider.begin
  provider.__cbeDelegatedModelBegin=original or false
  provider.begin=function(self,ctx,...)
    if cbeOwnsPokemonModels(ctx) then return false end
    if type(original)=="function" then return original(self,ctx,...) end
    return true
  end
  return true
end

local function patchDelegatedModels(stadium,api)
  local count=0
  local builtin=stadium and stadium.exports and stadium.exports.modelProvider
  if gateModelProvider(builtin) then count=count+1 end
  if api and type(api.componentList)=="function" then
    local ok,list=pcall(api.componentList,api,"models")
    if ok and type(list)=="table" then
      for _,entry in ipairs(list) do
        if type(entry)=="table" and gateModelProvider(entry.provider) then count=count+1 end
      end
    end
  end
  S.modelGates=count
  return count
end

function S.compatible()
  local stadium=ModLookup.find(mod,"STADIUM_BATTLE_FX")
  local api=stadium and stadium.exports and stadium.exports.battles
  if api and api.version==1 and type(api.registerComponent)=="function" then
    return stadium,api
  end
  return nil,nil
end

local function patchDefaults(stadium,api,arenaId,cameraId)
  local arenaBuiltin=stadium and stadium.exports and stadium.exports.arenaProvider
  if type(arenaBuiltin)=="table" and not arenaBuiltin.__cbeArenaPreference then
    local original=arenaBuiltin.preferredExternal
    arenaBuiltin.__cbeArenaPreference=original or false
    arenaBuiltin.preferredExternal=function(self,ctx)
      local game=(ctx and ctx.game) or (ctx and ctx.battle and ctx.battle.game) or mod.game
      local enabled=not (ArenaCatalog and ArenaCatalog.enabled) or ArenaCatalog.enabled(game)
      if enabled and arenaId then return arenaId end
      if type(original)=="function" then return original(self,ctx) end
      return nil
    end
  end

  local selected=type(api.selectedId)=="function" and api:selectedId("camera") or nil
  if selected=="stadium:default" and type(api.resolve)=="function" then
    local cameraBuiltin=api:resolve("camera",{game=mod.game})
    if type(cameraBuiltin)=="table" and not cameraBuiltin.__cbeCameraPreference then
      local original=cameraBuiltin.preferredExternal
      cameraBuiltin.__cbeCameraPreference=original or false
      cameraBuiltin.preferredExternal=function(self,ctx)
        local game=(ctx and ctx.game) or (ctx and ctx.battle and ctx.battle.game) or mod.game
        local arenasEnabled=not (ArenaCatalog and ArenaCatalog.enabled) or ArenaCatalog.enabled(game)
        local cameraEnabled=not (BattleSettings and BattleSettings.cameraEnabled) or BattleSettings.cameraEnabled(game)
        if arenasEnabled and cameraEnabled and cameraId then return cameraId end
        if type(original)=="function" then return original(self,ctx) end
        return nil
      end
    end
  end
end

function S.install()
  local stadium,api=S.compatible()
  if S.registered then
    if stadium and api then patchDelegatedModels(stadium,api) end
    return stadium~=nil and api~=nil
  end
  if not (stadium and api) then return false end

  V.FALLBACK=api.FALLBACK
  local owner=mod.id or "COLOSSEUM_BATTLE_ENVIRONMENTS"
  S.arenaProviderId=api:registerComponent(owner,"arena","water-colosseum",{
    label="COLOSSEUM ENVIRONMENTS",
    description="Selectable Colosseum environments with battle-synchronized trainers and cinematography.",
    provider=Arena,
    available=function(ctx) return Arena:available(ctx) end,
  })

  if CurrentSpriteModels and type(CurrentSpriteModels.register)=="function" then
    CurrentSpriteModels.register(stadium,api)
  end

  S.cameraProviderId=api:registerComponent(owner,"camera","colosseum-camera",{
    label="COLOSSEUM CAMERA",
    description="Event-driven Colosseum cinematography with optional manual camera override.",
    provider=Camera,
    available=function(ctx)
      local game=(ctx and ctx.game) or (ctx and ctx.battle and ctx.battle.game) or mod.game
      local arenasEnabled=not (ArenaCatalog and ArenaCatalog.enabled) or ArenaCatalog.enabled(game)
      local cameraEnabled=not (BattleSettings and BattleSettings.cameraEnabled) or BattleSettings.cameraEnabled(game)
      return arenasEnabled and cameraEnabled
    end,
  })

  patchDefaults(stadium,api,S.arenaProviderId,S.cameraProviderId)
  patchDelegatedModels(stadium,api)
  S.registered=true
  return true
end

function S.refreshModelGates()
  local stadium,api=S.compatible()
  if not (stadium and api) then return 0 end
  return patchDelegatedModels(stadium,api)
end

function S.hasProviderHost()
  local stadium,api=S.compatible()
  local generation=V.GenerationCompat and V.GenerationCompat.current
    and V.GenerationCompat.current() or 1
  -- StadiumBattleFX 2.1.7's host patches the combined Gen 1 BattleState draw
  -- path and cannot own Gold's split drawWidescreen screen. Keep CBE's local
  -- Gen 2 host authoritative and consume Stadium's public actor service there.
  -- A future Stadium host can explicitly advertise the generation-neutral
  -- contract without another CBE change.
  if generation==2 and not (api and api.gen2Host==true) then return false end
  return S.registered and stadium~=nil and api~=nil
end

function S.ownsArena(battle)
  local game=(battle and battle.game) or mod.game
  if ArenaCatalog and ArenaCatalog.enabled and not ArenaCatalog.enabled(game) then return false end
  local _,api=S.compatible()
  if not (api and S.registered and type(api.resolve)=="function") then return true end
  local ok,provider,entry=pcall(api.resolve,api,"arena",{battle=battle,game=game})
  if not ok then return false end
  return provider==Arena or (type(entry)=="table" and entry.id==S.arenaProviderId)
end

function S.usesCamera(battle)
  if not (S.delegated and S.cameraProviderId) then return false end
  local _,api=S.compatible()
  if not (api and type(api.resolve)=="function") then return false end
  local game=(battle and battle.game) or mod.game
  local ok,provider,entry=pcall(api.resolve,api,"camera",{battle=battle,game=game})
  if not ok then return false end
  return provider==Camera or (type(entry)=="table" and entry.id==S.cameraProviderId)
end

function S.setDelegated(value)
  S.delegated=value and true or false
end

function S.status()
  return {
    registered=S.registered,
    delegated=S.delegated,
    arenaProviderId=S.arenaProviderId,
    cameraProviderId=S.cameraProviderId,
    modelGates=S.modelGates or 0,
  }
end

return S
