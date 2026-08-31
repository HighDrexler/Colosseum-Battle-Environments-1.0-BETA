local V=...
local R={installed=false,activeBattle=nil,pendingEnd=nil,finishWrapper=nil,
  captureSoundWrapper=nil,captureSoundInner=nil,captureSoundBridge=false,nativeCaughtSuppressed=0,modelPrewarm=nil}

local mod=V.mod
local ArenaCatalog=V.ArenaCatalog
local BattleArtBridge=V.BattleArtBridge
local Camera=V.Camera
local CurrentSpriteModels=V.CurrentSpriteModels
local PokemonActors=V.PokemonActors
local NativeTrainerSprites=V.NativeTrainerSprites
local PlayerTrainer=V.PlayerTrainer
local StandaloneHost=V.StandaloneHost
local StadiumBridge=V.StadiumBridge
local Trainer=V.Trainer
local Compat=V.GenerationCompat
local BattleDirector=V.BattleDirector
local MoveFXOwnership=V.MoveFXOwnership
local BattleSides=V.BattleSides

local SEMANTIC_EVENTS={
  "battle.turn_started",
  "battle.move_used",
  "battle.damage_dealt",
  "battle.status_inflicted",
  "battle.ball_thrown",
  "battle.battler_switched",
  "battle.fainted",
  "battle.exp_gained",
  "battle.turn_ended",
}

local function contextFor(battle)
  battle=Compat and Compat.prepare(battle) or battle
  return {battle=battle,game=(battle and battle.game) or mod.game}
end


local unpackArgs=table.unpack or unpack
local function installCaptureSoundBridge()
  local req=V.engineRequire or require
  local ok,Sound=pcall(req,"src.core.Sound")
  if not ok or type(Sound)~="table" or type(Sound.play)~="function" then
    R.captureSoundBridge=false
    return false
  end
  if Sound.play==R.captureSoundWrapper then R.captureSoundBridge=true;return true end
  local inner=Sound.play
  R.captureSoundInner=inner
  R.captureSoundWrapper=function(...)
    local args={...}
    local requested
    -- Current Gen1Recomp calls Sound.play(data,"Caught_Mon"), but keep the
    -- bridge tolerant of a future method-style call without intercepting any
    -- unrelated sound identifier.
    for i=1,math.min(3,#args) do
      if type(args[i])=="string" and args[i]=="Caught_Mon" then requested=args[i];break end
    end
    if requested=="Caught_Mon" and R.activeBattle and PlayerTrainer
        and type(PlayerTrainer.suppressesNativeCaughtAudio)=="function" then
      local okOwn,owned=pcall(PlayerTrainer.suppressesNativeCaughtAudio,PlayerTrainer,contextFor(R.activeBattle))
      if okOwn and owned==true then
        R.nativeCaughtSuppressed=(tonumber(R.nativeCaughtSuppressed) or 0)+1
        -- The engine has already resolved the catch and CBE's ISO-derived
        -- me_snatch source is playing. Return no native source so sayNextWaitSfx
        -- proceeds without layering the Game Boy/GBC caught fanfare on top.
        return nil
      end
    end
    return inner(unpackArgs(args,1,#args))
  end
  Sound.play=R.captureSoundWrapper
  R.captureSoundBridge=true
  return true
end

local function dispatch(name,payload)
  local battle=(type(payload)=="table" and payload.battle) or R.activeBattle
  battle=Compat and Compat.prepare(battle) or battle
  local ctx=contextFor(battle)
  -- A replacement must be resident BEFORE the presentation providers observe
  -- the switch. Otherwise a large HSD body can spend the first visible switch
  -- frames parsing packed vertices/uploading meshes and pop in late. This gate
  -- is presentation-only and never changes the battle model or switch result.
  if name=="battle.battler_switched" and PokemonActors and type(PokemonActors.prewarmSwitch)=="function" then
    local side
    if BattleSides and type(BattleSides.payload)=="function" then
      local okSide,value=pcall(BattleSides.payload,ctx,payload,{"side","battler","replacement","newBattler","target"})
      if okSide then side=value end
    end
    if not side and type(payload)=="table" then side=payload.side or payload.targetSide end
    if BattleSides and type(BattleSides.value)=="function" then side=BattleSides.value(side) or side end
    local replacement=type(payload)=="table" and (payload.replacement or payload.newBattler or payload.battler or payload.target) or nil
    if side then pcall(PokemonActors.prewarmSwitch,battle,side,replacement) end
  end
  if BattleDirector and type(BattleDirector.event)=="function" then
    pcall(BattleDirector.event,BattleDirector,ctx,name,payload)
  end
  if MoveFXOwnership and type(MoveFXOwnership.event)=="function" then
    pcall(MoveFXOwnership.event,MoveFXOwnership,ctx,name,payload)
  end
  if StandaloneHost then StandaloneHost.event(name,payload) end

  -- StandaloneHost forwards events into the actor host using its rich arena
  -- context. When Stadium owns the compositor there is no standalone session,
  -- so route the same authoritative event directly. This keeps CBE's portable
  -- actor lifecycle aligned in both hosts without touching battle logic.
  local standaloneActive=false
  if StandaloneHost and type(StandaloneHost.status)=="function" then
    local ok,status=pcall(StandaloneHost.status)
    standaloneActive=ok and type(status)=="table" and status.active==true
  end
  if not standaloneActive and CurrentSpriteModels and type(CurrentSpriteModels.event)=="function" then
    pcall(CurrentSpriteModels.event,CurrentSpriteModels,ctx,name,payload)
  end

  -- StadiumBattleFX API v1 does not forward battle.ball_thrown to external
  -- camera providers. Bridge only that missing engine event, and only when CBE
  -- is the camera provider selected for this battle.
  if name=="battle.ball_thrown" and Camera and StadiumBridge and StadiumBridge.usesCamera(battle) then
    pcall(Camera.event,Camera,ctx,name,payload)
  end

  if PlayerTrainer and type(PlayerTrainer.event)=="function" then PlayerTrainer:event(ctx,name,payload) end
  if Trainer and type(Trainer.event)=="function" then Trainer:event(ctx,name,payload) end
end

local function beginBattle(payload)
  local battle=type(payload)=="table" and payload.battle or nil
  battle=Compat and Compat.prepare(battle) or battle
  if not battle then return end
  -- Gen1Recomp can recycle the same battle table between encounters.  Clear
  -- any previous arena binding on the authoritative battle.started boundary,
  -- not only on battle.ended, so a missed/late end event can never carry Mt.
  -- Battle (or any other arena) into the user's next explicit selection.
  if ArenaCatalog and ArenaCatalog.releaseBattle then ArenaCatalog.releaseBattle() end
  R.activeBattle=battle
  R.pendingEnd=nil
  -- Reclaim this narrow audio seam at the authoritative battle boundary in
  -- case another mod rewrapped Sound.play after mods.loaded.
  installCaptureSoundBridge()
  if BattleDirector and type(BattleDirector.begin)=="function" then
    pcall(BattleDirector.begin,BattleDirector,contextFor(battle))
  end
  if MoveFXOwnership and type(MoveFXOwnership.begin)=="function" then
    pcall(MoveFXOwnership.begin,MoveFXOwnership,contextFor(battle))
  end

  if not StandaloneHost then return end
  if StadiumBridge and type(StadiumBridge.refreshModelGates)=="function" then
    pcall(StadiumBridge.refreshModelGates)
  end
  if BattleArtBridge and type(BattleArtBridge.install)=="function" then
    pcall(BattleArtBridge.install)
  end

  -- StadiumBattleFX 2.1.x intentionally calls BattleHost.install(true) again
  -- on battle.started. Since Stadium loads before CBE, that can move its host
  -- back OUTSIDE the wrapper CBE installed during mods.loaded. Reinstall CBE
  -- here, at the same authoritative boundary but after earlier-priority event
  -- handlers, so CBE is outermost for the actual battle. StandaloneHost uses
  -- epoch guards, therefore an older nested CBE wrapper becomes a no-op rather
  -- than drawing the arena twice.
  pcall(StandaloneHost.install,true)

  -- HARD OWNERSHIP CONTRACT:
  -- If CBE is equipped and COLOSSEUM ARENAS is enabled, CBE's local host owns
  -- the complete BattleState world/compositor on BOTH generations. Stadium,
  -- Battle Art, Dramatic Shape and any other full-stage provider are never
  -- allowed to become the battle host. They may contribute Pokemon artwork or
  -- portable battleActors through CurrentSpriteModels, but arena/camera/trainers
  -- and BattleState presentation flow remain CBE-authored without exception.
  --
  -- Older builds delegated Gen I to Stadium's provider host when present. That
  -- allowed Battle Art staging selected inside Stadium to replace the arena,
  -- which is the regression this branch removes.
  if StadiumBridge then StadiumBridge.setDelegated(false) end

  -- Model readiness is part of CBE's battle-entry contract. The old path
  -- deliberately deferred HSD scene creation until draw() to avoid a black
  -- transition stall; that traded one pause for a much worse visible late
  -- spawn on high-detail Pokemon. Prepare both active battlers and only the
  -- native action banks their current moves require before the arena opens.
  if PokemonActors and type(PokemonActors.prewarmBattle)=="function" then
    local okWarm,result=pcall(PokemonActors.prewarmBattle,battle)
    if okWarm then R.modelPrewarm=result else R.modelPrewarm={failed=2,error=tostring(result)} end
  end

  local began=StandaloneHost.begin(battle)
  if NativeTrainerSprites then
    if began then NativeTrainerSprites:begin({battle=battle})
    else
      -- Even a source/cache failure must not hand ownership to another battle
      -- compositor. Keep CBE's staging bridge authoritative and fail only this
      -- native trainer-picture suppression seam.
      NativeTrainerSprites:finish({battle=battle})
    end
  end
end

local function finishPresentation(battle,reason)
  battle=Compat and Compat.prepare(battle) or battle
  local standaloneWasActive=false
  if StandaloneHost and type(StandaloneHost.status)=="function" then
    local ok,status=pcall(StandaloneHost.status)
    standaloneWasActive=ok and type(status)=="table" and status.active==true
  end
  if StandaloneHost then StandaloneHost.finish(reason or "battle.ended") end
  -- A delegated Stadium compositor has no StandaloneHost session to own actor
  -- cleanup. Close CBE's portable actors explicitly at the same authoritative
  -- screen boundary; StandaloneHost already does this when it was active.
  if not standaloneWasActive and CurrentSpriteModels and type(CurrentSpriteModels.finish)=="function" then
    pcall(CurrentSpriteModels.finish,CurrentSpriteModels,contextFor(battle),reason or "battle.ended")
  end
  if NativeTrainerSprites then NativeTrainerSprites:finish({battle=battle}) end
  if ArenaCatalog and ArenaCatalog.releaseBattle then ArenaCatalog.releaseBattle(battle) end
  if BattleDirector and type(BattleDirector.finish)=="function" then
    pcall(BattleDirector.finish,BattleDirector,contextFor(battle),reason or "battle.ended")
  end
  if MoveFXOwnership and type(MoveFXOwnership.finish)=="function" then
    pcall(MoveFXOwnership.finish,MoveFXOwnership,contextFor(battle),reason or "battle.ended")
  end
  R.activeBattle=nil
  R.pendingEnd=nil
end

local function endBattle(payload)
  dispatch("battle.ended",payload)
  local battle=(type(payload)=="table" and payload.battle) or R.activeBattle
  battle=Compat and Compat.prepare(battle) or battle
  -- Gen 2's pure battle model announces the outcome before its screen has
  -- replayed the queued killing hit, faint, EXP, money, and victory messages.
  -- Keep the presentation alive until BattleState:finishBattle reaches the
  -- actual screen boundary. Gen 1 emits this event at its visual boundary and
  -- retains the original immediate cleanup.
  if Compat and Compat.isGen2Battle(battle) then
    R.pendingEnd=battle
    return
  end
  finishPresentation(battle,"battle.ended")
end

local function installGen2FinishBoundary()
  if not (Compat and Compat.current and Compat.current()==2) then return true end
  local req=V.engineRequire or require
  local ok,BattleState=pcall(req,"src.battle.BattleState")
  if not ok or type(BattleState)~="table" or type(BattleState.finishBattle)~="function" then
    return false
  end
  if BattleState.finishBattle==R.finishWrapper then return true end
  local inner=BattleState.finishBattle
  R.finishWrapper=function(self,...)
    local results={pcall(inner,self,...)}
    local success=table.remove(results,1)
    local battle=Compat and Compat.prepare(self) or self
    local pending=R.pendingEnd
    if pending and ((Compat and Compat.matches(pending,battle)) or pending==battle) then
      finishPresentation(battle,"gen2.screen.finished")
    end
    if not success then error(results[1],0) end
    return unpack(results)
  end
  BattleState.finishBattle=R.finishWrapper
  return true
end

function R.install()
  if R.installed then installGen2FinishBoundary();installCaptureSoundBridge();return true end

  installGen2FinishBoundary()
  installCaptureSoundBridge()

  if mod.hooks and type(mod.hooks.wrap)=="function" then
    mod.hooks:wrap("input.step",function(next,game,dt)
      local result=next(game,dt)
      if BattleDirector and R.activeBattle and type(BattleDirector.update)=="function" then
        pcall(BattleDirector.update,BattleDirector,contextFor(R.activeBattle),dt)
      end
      if StandaloneHost then
        -- Last-resort arbitration seam: if a later-priority mod rewrapped
        -- BattleState after battle.started, reclaim the outer slot before the
        -- next frame. install() is effectively free while our wrapper is still
        -- current and only creates a new epoch when it was actually displaced.
        if R.activeBattle then pcall(StandaloneHost.install,true) end
        StandaloneHost.update(dt)
      end
      return result
    end)
  end

  if mod.events and type(mod.events.on)=="function" then
    mod.events:on("battle.started",beginBattle)
    for _,name in ipairs(SEMANTIC_EVENTS) do
      mod.events:on(name,function(payload) dispatch(name,payload) end)
    end
    mod.events:on("battle.ended",endBattle)
  end

  R.installed=true
  return true
end

function R.status()
  return {installed=R.installed,active=R.activeBattle~=nil,pendingEnd=R.pendingEnd~=nil,
    endBoundary=(Compat and Compat.current and Compat.current()==2) and "gen2.screen.finished" or "battle.ended",
    captureSoundBridge=R.captureSoundBridge==true,nativeCaughtSuppressed=R.nativeCaughtSuppressed or 0,
    modelPrewarm=R.modelPrewarm,
    captureSuccessAudio="ISO me_snatch owns success; native Caught_Mon suppressed only when source cue is available"}
end

return R
