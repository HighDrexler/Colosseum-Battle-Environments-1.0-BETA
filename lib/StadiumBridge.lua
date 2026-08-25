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
  if S.registered then return true end
  local stadium,api=S.compatible()
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
  S.registered=true
  return true
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
  }
end

return S
