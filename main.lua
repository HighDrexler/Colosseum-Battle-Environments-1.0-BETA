local mod=...
local VERSION="1.6.1"
mod.exports.version=VERSION

local function package(path,arg)
  local src=mod:read(path)
  if not src then error("COLOSSEUM_BATTLE_ENVIRONMENTS: missing "..path,0) end
  local chunk,err=load(src,"@"..tostring(mod.path or mod.id).."/"..path)
  if not chunk then error(err,0) end
  return chunk(arg)
end

-- Gen1Recomp owns required-import selection and validation. Native
-- mod.imports/mod.cache provide bounded source access and an installation-scoped
-- generated cache. The compatibility bridge never receives the original host path.
local NativeLauncherCompat=package("lib/NativeLauncherCompat.lua")
local launcherCompat=NativeLauncherCompat.install(mod)
local BuildProgressUI=package("lib/BuildProgressUI.lua")

-- Build the user-owned Colosseum source into an installation-scoped runtime
-- before any battle provider is allowed to acquire generated content.
local extractionStatus={state="NOT RUN",visualReady=false,audioReady=false,message=nil}
local sourceImported=false
local cacheGateOutcome=nil

-- Captured during runBuild so the Colosseum Pokemon actor service can build a
-- species on first send-out. The closure keeps the host path private: the
-- runtime gains the ability to ASK for an opened disc, never the path itself.
local openColosseumDisc=nil
local PokemonExtractorRef=nil
local PKXMetadataRef=nil
local MoveFXExtractorRef=nil
local BuildPipelineRef=nil

-- Pokemon model extraction stays lazy after the arena bootstrap. Keep the
-- launcher-owned source capability alive for CBE's lifetime so any uncached
-- species can be built on first use; there is no valid post-bootstrap release
-- boundary. The mod never receives the original host path.
local function runBuild()
  if not (mod.imports and mod.cache) then
    extractionStatus={state="HOST API MISSING",visualReady=false,audioReady=false,message="Colosseum Battle Environments requires Gen1Recomp required-import support with mod.imports/mod.cache."}
    return
  end
  local info,infoErr=mod.imports:info("pokemon_colosseum_usa")
  sourceImported=info~=nil
  if not info then
    extractionStatus={state="ROM NOT IMPORTED",visualReady=false,audioReady=false,message="In the Gen1Recomp launcher, open MODS > Colosseum Battle Environments > IMPORT FILE.., select your Pokemon Colosseum USA GC6E01 disc image (raw ISO/GCM or GameCube CISO; the selected filename/extension does not matter once the launcher can validate it), then launch the game with CBE enabled. Current Gen1Recomp builds retain this source across CBE updates."}
    return
  end
  local GXTexture=package("extract/GXTexture.lua")
  local GameCubeDisc=package("extract/GameCubeDisc.lua")
  local FSYS=package("extract/FSYS.lua")
  local HSD=package("extract/HSD.lua",{GXTexture=GXTexture})
  local ArenaBuilder=package("extract/ArenaBuilder.lua",{HSD=HSD,FSYS=FSYS})
  local TransitionBuilder=package("extract/TransitionBuilder.lua")
  local AudioProbe=package("extract/AudioProbe.lua",{FSYS=FSYS})
  local TrainerExtractor=package("extract/TrainerExtractor.lua",{HSD=HSD,FSYS=FSYS})
  local ColosseumDex=package("lib/ColosseumDex.lua")
  local PKXMetadata=package("extract/PKXMetadata.lua",{FSYS=FSYS,ColosseumDex=ColosseumDex})
  local PokemonExtractor=package("extract/PokemonExtractor.lua",{HSD=HSD,FSYS=FSYS,ColosseumDex=ColosseumDex,PKXMetadata=PKXMetadata})
  local WazaSequenceExtractor=package("extract/WazaSequenceExtractor.lua")
  local MoveFXExtractor=package("extract/MoveFXExtractor.lua",{FSYS=FSYS,GXTexture=GXTexture,HSD=HSD,WazaSequenceExtractor=WazaSequenceExtractor})
  local FormatProbe=package("extract/FormatProbe.lua",{FSYS=FSYS,HSD=HSD,WazaSequenceExtractor=WazaSequenceExtractor})
  local CameraProbe=package("extract/CameraProbe.lua",{FSYS=FSYS,HSD=HSD})
  PokemonExtractorRef=PokemonExtractor
  PKXMetadataRef=PKXMetadata
  MoveFXExtractorRef=MoveFXExtractor
  openColosseumDisc=function() return GameCubeDisc.open(mod) end
  local BuildPipeline=package("extract/BuildPipeline.lua",{
    GameCubeDisc=GameCubeDisc,FSYS=FSYS,GXTexture=GXTexture,HSD=HSD,
    ArenaBuilder=ArenaBuilder,TrainerExtractor=TrainerExtractor,
    TransitionBuilder=TransitionBuilder,AudioProbe=AudioProbe,
    PokemonExtractor=PokemonExtractor,MoveFXExtractor=MoveFXExtractor,FormatProbe=FormatProbe,CameraProbe=CameraProbe,ColosseumDex=ColosseumDex,
  })
  BuildPipelineRef=BuildPipeline
  extractionStatus={state="RUNNING",visualReady=false,audioReady=false,message="Starting GC6E01 source build."}
  local okPipeline,result=pcall(BuildPipeline.run,mod,function(label,current,total)
    extractionStatus.state="RUNNING";extractionStatus.message=tostring(label);extractionStatus.current=current;extractionStatus.total=total
    BuildProgressUI.update(label,current,total)
    if mod.log and mod.log.info then pcall(mod.log.info,mod.log,"CBE source build: %s (%s/%s)",tostring(label),tostring(current or "?"),tostring(total or "?")) end
  end)
  if not okPipeline then error(result,0) end
  extractionStatus=result or extractionStatus
  BuildProgressUI.finish(extractionStatus.state,extractionStatus.message)
  if extractionStatus.state=="FAILED" and mod.log and mod.log.error then pcall(mod.log.error,mod.log,"CBE source build failed: %s",tostring(extractionStatus.message))
  elseif mod.log and mod.log.info then pcall(mod.log.info,mod.log,"CBE source build: %s",tostring(extractionStatus.state)) end
end
local okBuild,buildErr=pcall(runBuild)
if not okBuild then
  extractionStatus={state="FAILED",visualReady=false,audioReady=false,message=tostring(buildErr)}
  BuildProgressUI.finish("FAILED",tostring(buildErr))
  if mod.cache then pcall(mod.cache.write,mod.cache,"build/error.txt",tostring(buildErr).."\n") end
end

-- Visual cache is the hard runtime boundary. Colosseum music is optional: an
-- unsupported converter or failed audio cache must never withhold the arena,
-- actors, trainers, MoveFX, transitions or information-model surfaces.
while sourceImported and extractionStatus.visualReady~=true do
  local action=BuildProgressUI.failureGate(extractionStatus.state,extractionStatus.message,extractionStatus.trainerFirstError,extractionStatus.trainerSourceError)
  if action=="retry" then
    local okRetry,retryErr=pcall(runBuild)
    if not okRetry then
      extractionStatus={state="FAILED",visualReady=false,audioReady=false,message=tostring(retryErr)}
      BuildProgressUI.finish("FAILED",tostring(retryErr))
      if mod.cache then pcall(mod.cache.write,mod.cache,"build/error.txt",tostring(retryErr).."\n") end
    end
  else
    cacheGateOutcome=action
    break
  end
end

local runtimeAllowed=extractionStatus.visualReady==true

local function module(name,arg)
  return package("lib/"..name..".lua",arg)
end
local namespace={mod=mod,FALLBACK=nil,engineRequire=require}
local function loadModule(name,arg)
  local value=module(name,arg==nil and namespace or arg)
  namespace[name]=value
  return value
end

local Mat4=module("Mat4");namespace.Mat4=Mat4
local GeneratedAssets=loadModule("GeneratedAssets")
namespace.MoveFXExtractor=MoveFXExtractorRef
local MoveFXVM=loadModule("MoveFXVM")
local WazaSequenceRuntime=loadModule("WazaSequenceRuntime")
local GenerationCompat=loadModule("GenerationCompat")
local TrainerRig=loadModule("TrainerRig")
local TrainerPerformance=loadModule("TrainerPerformance")
local BattleSides=loadModule("BattleSides")
local BattleDirector=loadModule("BattleDirector")
local ModLookup=loadModule("ModLookup")
local TrainerRoster=loadModule("TrainerRoster")
local Trainer=loadModule("Trainer")
local PlayerTrainer=loadModule("PlayerTrainer")
local NativeTrainerSprites=loadModule("NativeTrainerSprites")
local MoveFXOwnership=loadModule("MoveFXOwnership")
local ArenaCatalog=loadModule("ArenaCatalog")
local BattleArtBridge=loadModule("BattleArtBridge")
local CurrentSpriteModels=loadModule("CurrentSpriteModels")
loadModule("ColosseumDex")
local PokemonActors=loadModule("PokemonActors")
local Arena=loadModule("Arena")
local Camera=loadModule("Camera")
local Music=loadModule("Music")
local WazaAudioRuntime=loadModule("WazaAudioRuntime")
local WazaHandlers=loadModule("WazaHandlers")
local BattleMenuUI=loadModule("BattleMenuUI")
local CacheManager=loadModule("CacheManager")
local BattleSettings=loadModule("BattleSettings")
local Transition=loadModule("Transition")
local StandaloneHost=loadModule("StandaloneHost")
local StadiumBridge=loadModule("StadiumBridge")
local BattleRuntime=loadModule("BattleRuntime")

local function installRuntime(force)
  StadiumBridge.install()
  Music.install(mod)
  Music.attachGame(mod.game)
  BattleSettings.install(mod,Trainer,Music,ArenaCatalog,BattleMenuUI,CacheManager,TrainerRoster,GenerationCompat)
  if ArenaCatalog.sync then ArenaCatalog.sync(mod.game) end
  Transition.install(mod)
  StandaloneHost.install(force)
  BattleArtBridge.install()
  -- CBE consumes its own Colosseum Pokemon models through the SAME documented
  -- battleActors v1 seam third-party providers use (PORTABLE_BATTLE_ACTORS.md),
  -- not a private path. CurrentSpriteModels skips handles whose id matches CBE's
  -- own and registerCapability rejects that id outright, so the service carries
  -- a distinct provider identity. When COLOSSEUM MODELS is ON the CBE arena
  -- consumes this service directly in both generations; when OFF the external
  -- provider/sprite selection remains authoritative.
  PokemonActors.install(PokemonExtractorRef,openColosseumDisc,CurrentSpriteModels,PKXMetadataRef)
  if MoveFXExtractorRef and type(MoveFXExtractorRef.install)=="function" then
    MoveFXExtractorRef.install(mod,openColosseumDisc)
  end
  CurrentSpriteModels.registerCapability(
    "COLOSSEUM_BATTLE_ENVIRONMENTS/pokemon","battleActors",PokemonActors.service)
  -- Give the F9 overlay a hook that runs every frame of a battle whatever the
  -- presentation mode. Idempotent: installRuntime is called again on
  -- mods.loaded, and wrapping an already-wrapped function would nest forever.
  if not CurrentSpriteModels.__cbePokemonDebugWrapped then
    local originalDrawWorld=CurrentSpriteModels.drawWorld
    CurrentSpriteModels.drawWorld=function(self,context)
      local ok,result=pcall(originalDrawWorld,self,context)
      pcall(PokemonActors.debugFrame)
      if not ok then error(result,0) end
      return result
    end
    CurrentSpriteModels.__cbePokemonDebugWrapped=true
  end
  MoveFXOwnership.install()
  if WazaHandlers and type(WazaHandlers.install)=="function" then WazaHandlers.install() end
  BattleRuntime.install()
end

if runtimeAllowed then
  NativeTrainerSprites.install()
  installRuntime(false)
  if mod.events and type(mod.events.on)=="function" then
    mod.events:on("mods.loaded",function(payload)
      if ModLookup and type(ModLookup.setLoader)=="function" then
        ModLookup.setLoader(type(payload)=="table" and payload.loader or nil)
      end
      installRuntime(true)
    end)
    mod.events:on("game.ready",function(payload)
      local game=type(payload)=="table" and payload.game or nil
      if game then
        Music.attachGame(game)
        if ArenaCatalog.sync then ArenaCatalog.sync(game) end
        -- Shift arena/trainer cache parsing and GPU allocation to the normal
        -- game-ready seam rather than the battle transition's final black
        -- frame. This is presentation-only prewarming; battle ownership/state
        -- is not started. Arena/model caches and the lead Pokemon's source WZX
        -- banks may be warmed here so visible battle frames never perform disc decode.
        if Arena and type(Arena.prewarm)=="function" then
          pcall(Arena.prewarm,Arena,{game=game,battle=nil,phase="prewarm",progress=1,services={cbeStandalone=true}})
        end
        if CurrentSpriteModels and type(CurrentSpriteModels.prewarm)=="function" then
          pcall(CurrentSpriteModels.prewarm,CurrentSpriteModels)
        end
        if WazaHandlers and type(WazaHandlers.prewarm)=="function" then
          pcall(WazaHandlers.prewarm)
        end
        if PokemonActors and type(PokemonActors.prewarmParty)=="function" then
          pcall(PokemonActors.prewarmParty,game)
        end
        -- Warm the lead Pokemon's four WZX banks while the normal game-ready
        -- screen is active. This moves the most common source FX decode away
        -- from the first battle transition; BattleDirector completes only the
        -- still-missing current battler banks before its world opens.
        if MoveFXExtractorRef and type(MoveFXExtractorRef.queueParty)=="function" then
          pcall(MoveFXExtractorRef.queueParty,game,1)
          if type(MoveFXExtractorRef.pumpPrefetch)=="function" then pcall(MoveFXExtractorRef.pumpPrefetch,4) end
        end
      end
    end)
  end
elseif mod.log and mod.log.warn then
  pcall(mod.log.warn,mod.log,"CBE runtime withheld because generated visual cache is not ready (%s)",tostring(cacheGateOutcome or extractionStatus.state))
end

-- Regenerate build/format_probe.txt on demand. The probe is otherwise written
-- once, on the first build that has it; this re-runs it without touching any
-- generated cache, so the WZX/CAM report can be refreshed at will.
mod.exports.probeFormats=function()
  if not BuildPipelineRef then return false,"build pipeline unavailable (source not imported?)" end
  local ok,result,note=pcall(BuildPipelineRef.ensureFormatProbe,mod,nil,true)
  if not ok then return false,tostring(result) end
  return result==true,tostring(note or ""),"build/format_probe.txt"
end

-- Clear every cached Pokemon model so the next send-out re-extracts from the
-- imported disc. Cheaper than exports.rebuild(): arenas, trainers, transitions
-- and audio are untouched.
mod.exports.rebuildPokemon=function()
  local ok,result,count=pcall(PokemonActors.rebuildSpecies)
  if not ok then return false,tostring(result) end
  return result==true,("cleared %d generated Pokemon cache files"):format(tonumber(count) or 0)
end

mod.exports.rebuild=function()
  local ok,msg=CacheManager.resetGenerated();if not ok then return false,msg end
  local ok2,err2=pcall(runBuild);if not ok2 then return false,tostring(err2) end
  CacheManager.resetRuntime();return extractionStatus.visualReady,extractionStatus
end
-- Lightweight presentation-ownership query for UI/compatibility consumers.
--
-- Keep this deliberately separate from exports.status(): status() is a full
-- diagnostic report and may inspect generated-cache state. It is appropriate
-- for menus/logging, never for a battle update or draw loop. Ownership only
-- depends on already-live runtime tables, so this path performs no filesystem
-- work and is safe to sample at a battle boundary.
mod.exports.presentationOwnership=function(battle)
  local host=StandaloneHost.status()
  local runtime=BattleRuntime.status()
  local trainer=Trainer:status()
  local wild=type(battle)=="table" and battle.wild==true
  local world=host.active==true or runtime.active==true
  return {
    version=1,
    world=world,
    trainer=(not wild) and (host.active==true or trainer.active==true) or false,
    standalone=host.active==true,
    runtime=runtime.active==true,
  }
end

-- Full diagnostics. This may perform cache/status inspection and must not be
-- polled from frame-critical update/draw paths. Use presentationOwnership()
-- when a consumer only needs to know who owns the live battle presentation.
mod.exports.status=function()
  local stadium=StadiumBridge.status()
  return {version=VERSION,registered=stadium.registered,stadiumDelegated=stadium.delegated,arenaProviderId=stadium.arenaProviderId,cameraProviderId=stadium.cameraProviderId,stadium=stadium,
    runtime=BattleRuntime.status(),battleDirector=BattleDirector:status(),trainerRig=TrainerRig:status(),trainerPerformance=TrainerPerformance.status(),trainerRoster=TrainerRoster:status(),arena=Arena:status(),arenaCatalog=ArenaCatalog.status(mod.game,nil),trainer=Trainer:status(),playerTrainer=PlayerTrainer:status(),camera=Camera:status(),music=Music.status(),settings=BattleSettings.status(mod.game),cache=CacheManager.status(),extraction=extractionStatus,launcherImport=launcherCompat,battleMenuUI=BattleMenuUI.status(),transition=Transition.status(),nativeTrainerSprites=NativeTrainerSprites.status(),moveFxOwnership=MoveFXOwnership.status(),moveFxExtractor=MoveFXExtractorRef and MoveFXExtractorRef.status and MoveFXExtractorRef.status() or nil,moveFxVM={version=MoveFXVM.version,source=MoveFXVM.source},wazaSequenceRuntime=WazaSequenceRuntime and WazaSequenceRuntime.status and WazaSequenceRuntime:status() or nil,wazaHandlers=WazaHandlers and WazaHandlers.status and WazaHandlers.status() or nil,wazaAudio=WazaAudioRuntime and WazaAudioRuntime.status and WazaAudioRuntime:status() or nil,standaloneHost=StandaloneHost.status(),battleArtBridge=BattleArtBridge.status(),currentSpriteModels=CurrentSpriteModels.status(),pokemonActors=PokemonActors.status(),cacheGate={runtimeAllowed=runtimeAllowed,outcome=cacheGateOutcome}}
end
mod.exports.battleCompatibility={
  version=1,
  capabilities={sprites="battleSprites",actors="battleActors",presentation="battlePresentation",world="battleWorld"},
  register=function(owner,kind,provider) return CurrentSpriteModels.registerCapability(owner,kind,provider) end,
  unregister=function(owner,kind) return CurrentSpriteModels.unregisterCapability(owner,kind) end,
}
-- Read-only information/showroom model bridge for Party/Summary UI surfaces.
-- This never starts battle presentation ownership. The standard resolver asks
-- CurrentSpriteModels which portable actor provider would win; resolveColosseum
-- explicitly requests CBE's source Pokemon actors for a Colosseum-branded pod.
local function cbeInformationContext(request)
  request=type(request)=="table" and request or {}
  local game=request.game or mod.game
  local mon=request.mon or request.pokemon
  local battler=request.battler
  if type(battler)~="table" and type(mon)=="table" then battler={mon=mon} end
  local enabled=true
  if BattleSettings and type(BattleSettings.pokemonModelsEnabled)=="function" then
    local ok,value=pcall(BattleSettings.pokemonModelsEnabled,game)
    enabled=(not ok) or value~=false
  end
  local context={
    apiVersion=1,game=game,battle=nil,
    sides={player={battler=battler},enemy={battler=nil}},
    phase="information",progress=1,groundY=0,
    services={cbeStandalone=true,informationSurface=true},
  }
  if not enabled then return nil,"cbe-pokemon-models-disabled",context end
  return context,nil
end

mod.exports.informationModels={
  version=3,
  resolve=function(_,request)
    if not runtimeAllowed then return nil,"cbe-runtime-unavailable" end
    return CurrentSpriteModels.informationActorProvider(request)
  end,
  resolveColosseum=function(_,request)
    if not runtimeAllowed then return nil,"cbe-runtime-unavailable" end
    local context,reason=cbeInformationContext(request)
    if not context then return nil,reason end
    return PokemonActors.service,"cbe:colosseum-pokemon",context,mod.id
  end,
  -- Dedicated read-only Stats/Data showroom seam.  This intentionally does
  -- NOT inherit the live-battle COLOSSEUM MODELS toggle, which is save-local
  -- and may legitimately differ between Gen I and Gen II.  A UI information
  -- viewer does not claim battle actor ownership, mutate battle state, or
  -- change the player's selected battle sprite/model source.
  resolveShowroom=function(_,request)
    if not runtimeAllowed then return nil,"cbe-runtime-unavailable" end
    request=type(request)=="table" and request or {}
    local game=request.game or mod.game
    local mon=request.mon or request.pokemon
    local battler=request.battler
    if type(battler)~="table" and type(mon)=="table" then battler={mon=mon} end
    local context={
      apiVersion=1,game=game,battle=nil,
      sides={player={battler=battler},enemy={battler=nil}},
      phase="information",progress=1,groundY=0,
      services={cbeStandalone=true,informationSurface=true,showroom=true},
    }
    return PokemonActors.service,"cbe:colosseum-pokemon",context,mod.id
  end,
}

mod.exports.controls={mouseOrbit="LMB DRAG",mouseDolly="RMB DRAG",mouseLens="SHIFT+RMB DRAG",mousePan="MMB DRAG",toggle="F8",orbitLeft="J",orbitRight="L",raise="I",lower="K",zoomIn="U",zoomOut="O",lensNarrow="N",lensWide="M",reset="HOME"}
