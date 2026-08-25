local mod=...
local VERSION="1.2"
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
local function runBuild()
  if not (mod.imports and mod.cache) then
    extractionStatus={state="HOST API MISSING",visualReady=false,audioReady=false,message="Colosseum Battle Environments requires the current Gen1Recomp required-import host (mod.imports/mod.cache). Update the launcher/app before importing large ISO/CISO sources."}
    return
  end
  local info,infoErr=mod.imports:info("pokemon_colosseum_usa")
  sourceImported=info~=nil
  if not info then
    extractionStatus={state="ROM NOT IMPORTED",visualReady=false,audioReady=false,message="In the Gen1Recomp launcher, open MODS > Colosseum Battle Environments > IMPORT FILE.., select Pokemon Colosseum USA GC6E01 as ISO/GCM or GameCube CISO, then launch the game with CBE enabled. Current Gen1Recomp builds retain this source across CBE updates."}
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
  local BuildPipeline=package("extract/BuildPipeline.lua",{
    GameCubeDisc=GameCubeDisc,FSYS=FSYS,GXTexture=GXTexture,HSD=HSD,
    ArenaBuilder=ArenaBuilder,TrainerExtractor=TrainerExtractor,
    TransitionBuilder=TransitionBuilder,AudioProbe=AudioProbe,
  })
  extractionStatus={state="RUNNING",visualReady=false,audioReady=false,message="Starting GC6E01 source build."}
  local okPipeline,result=pcall(BuildPipeline.run,mod,function(label,current,total)
    extractionStatus.state="RUNNING";extractionStatus.message=tostring(label);extractionStatus.current=current;extractionStatus.total=total
    BuildProgressUI.update(label,current,total)
    if mod.log and mod.log.info then pcall(mod.log.info,mod.log,"CBE source build: %s (%s/%s)",tostring(label),tostring(current or "?"),tostring(total or "?")) end
  end)
  if mod.imports and type(mod.imports.release)=="function" then pcall(mod.imports.release,mod.imports) end
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

-- Visuals and audio share one generated runtime. A complete visual cache is
-- preserved while an audio-only stage is retried.
while sourceImported and (extractionStatus.visualReady~=true or extractionStatus.audioReady~=true) do
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

local runtimeAllowed=extractionStatus.visualReady==true and extractionStatus.audioReady==true

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
local GenerationCompat=loadModule("GenerationCompat")
local TrainerRig=loadModule("TrainerRig")
local TrainerPerformance=loadModule("TrainerPerformance")
local BattleSides=loadModule("BattleSides")
local ModLookup=loadModule("ModLookup")
local TrainerRoster=loadModule("TrainerRoster")
local Trainer=loadModule("Trainer")
local PlayerTrainer=loadModule("PlayerTrainer")
local NativeTrainerSprites=loadModule("NativeTrainerSprites")
local ArenaCatalog=loadModule("ArenaCatalog")
local BattleArtBridge=loadModule("BattleArtBridge")
local CurrentSpriteModels=loadModule("CurrentSpriteModels")
local Arena=loadModule("Arena")
local Camera=loadModule("Camera")
local Music=loadModule("Music")
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
      if game then Music.attachGame(game);if ArenaCatalog.sync then ArenaCatalog.sync(game) end end
    end)
  end
elseif mod.log and mod.log.warn then
  pcall(mod.log.warn,mod.log,"CBE runtime withheld because generated visual cache is not ready (%s)",tostring(cacheGateOutcome or extractionStatus.state))
end

mod.exports.rebuild=function()
  local ok,msg=CacheManager.resetGenerated();if not ok then return false,msg end
  local ok2,err2=pcall(runBuild);if not ok2 then return false,tostring(err2) end
  CacheManager.resetRuntime();return extractionStatus.visualReady,extractionStatus
end
mod.exports.status=function()
  local stadium=StadiumBridge.status()
  return {version=VERSION,registered=stadium.registered,stadiumDelegated=stadium.delegated,arenaProviderId=stadium.arenaProviderId,cameraProviderId=stadium.cameraProviderId,stadium=stadium,
    runtime=BattleRuntime.status(),trainerRig=TrainerRig:status(),trainerPerformance=TrainerPerformance.status(),trainerRoster=TrainerRoster:status(),arena=Arena:status(),arenaCatalog=ArenaCatalog.status(mod.game,nil),trainer=Trainer:status(),playerTrainer=PlayerTrainer:status(),camera=Camera:status(),music=Music.status(),settings=BattleSettings.status(mod.game),cache=CacheManager.status(),extraction=extractionStatus,launcherImport=launcherCompat,battleMenuUI=BattleMenuUI.status(),transition=Transition.status(),nativeTrainerSprites=NativeTrainerSprites.status(),standaloneHost=StandaloneHost.status(),battleArtBridge=BattleArtBridge.status(),currentSpriteModels=CurrentSpriteModels.status(),cacheGate={runtimeAllowed=runtimeAllowed,outcome=cacheGateOutcome}}
end
mod.exports.battleCompatibility={
  version=1,
  capabilities={sprites="battleSprites",actors="battleActors",presentation="battlePresentation",world="battleWorld"},
  register=function(owner,kind,provider) return CurrentSpriteModels.registerCapability(owner,kind,provider) end,
  unregister=function(owner,kind) return CurrentSpriteModels.unregisterCapability(owner,kind) end,
}
mod.exports.controls={mouseOrbit="LMB DRAG",mouseDolly="RMB DRAG",mouseLens="SHIFT+RMB DRAG",mousePan="MMB DRAG",toggle="F8",orbitLeft="J",orbitRight="L",raise="I",lower="K",zoomIn="U",zoomOut="O",lensNarrow="N",lensWide="M",reset="HOME"}
