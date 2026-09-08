local V=...
local R={installed=false,activeBattle=nil,pendingEnd=nil,pendingEndReason=nil,pendingEndSince=nil,finishWrapper=nil,
  captureSoundWrapper=nil,captureSoundInner=nil,captureSoundBridge=false,nativeCaughtSuppressed=0,
  movePlayWrapper=nil,movePlayInner=nil,stereoWrapper=nil,stereoInner=nil,moveSoundBridge=false,nativeMoveSoundsSuppressed=0,
  modelPrewarm=nil,entryTiming=nil,exitTiming=nil}

local mod=V.mod
local ArenaCatalog=V.ArenaCatalog
local Arena=V.Arena
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
local WazaHandlers=V.WazaHandlers
local MoveFXExtractor=V.MoveFXExtractor
local ResidentPrewarm=V.ResidentPrewarm
local FrameWork=V.FrameWork

local function platformOS()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok and v then return tostring(v) end
  end
  return "Unknown"
end
local ANDROID_RUNTIME=platformOS()=="Android"
local androidActionWarmNextAt=0
local androidGcNextAt=0
local function wallNow()
  if love and love.timer and type(love.timer.getTime)=="function" then
    local ok,v=pcall(love.timer.getTime);if ok and type(v)=="number" then return v end
  end
  return os.clock()
end
local function stackTop(game)
  local stack=game and game.stack
  if stack and type(stack.top)=="function" then
    local ok,v=pcall(stack.top,stack);if ok then return v end
  end
  return nil
end

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

  local function sourceMoveAudioOwned()
    if not (R.activeBattle and MoveFXOwnership and type(MoveFXOwnership.ownsNativeAudio)=="function") then return false end
    local okOwn,owned=pcall(MoveFXOwnership.ownsNativeAudio,MoveFXOwnership,R.activeBattle)
    return okOwn and owned==true
  end
  -- Gen I's animation sound path is Sound.playMove; Gen II's anim_sound maps
  -- directly to PlayStereoSFX / Sound.playStereo.  Keep both native paths live
  -- unless the active Waza has a complete generated GameSound set. Missing or
  -- unrenderable source ids therefore fail open with the stock GB/GBC sound.
  if type(Sound.playMove)=="function" and Sound.playMove~=R.movePlayWrapper then
    local innerMove=Sound.playMove;R.movePlayInner=innerMove
    R.movePlayWrapper=function(...)
      if sourceMoveAudioOwned() then R.nativeMoveSoundsSuppressed=(R.nativeMoveSoundsSuppressed or 0)+1;return nil end
      return innerMove(...)
    end
    Sound.playMove=R.movePlayWrapper
  end
  if type(Sound.playStereo)=="function" and Sound.playStereo~=R.stereoWrapper then
    local innerStereo=Sound.playStereo;R.stereoInner=innerStereo
    R.stereoWrapper=function(...)
      if sourceMoveAudioOwned() then R.nativeMoveSoundsSuppressed=(R.nativeMoveSoundsSuppressed or 0)+1;return nil end
      return innerStereo(...)
    end
    Sound.playStereo=R.stereoWrapper
  end
  R.moveSoundBridge=(Sound.playMove==R.movePlayWrapper) or (Sound.playStereo==R.stereoWrapper)
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
    if side then
      pcall(PokemonActors.prewarmSwitch,battle,side,replacement,
        ANDROID_RUNTIME and {allowExtract=false,deferCold=true} or nil)
    end
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
  local entryStart=wallNow()
  -- Gen1Recomp can recycle the same battle table between encounters.  Clear
  -- any previous arena binding on the authoritative battle.started boundary,
  -- not only on battle.ended, so a missed/late end event can never carry Mt.
  -- Battle (or any other arena) into the user's next explicit selection.
  if ArenaCatalog and ArenaCatalog.releaseBattle then ArenaCatalog.releaseBattle() end
  R.activeBattle=battle
  R.pendingEnd=nil
  if ANDROID_RUNTIME then androidActionWarmNextAt=wallNow() end
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
  -- the complete BattleState world/compositor on BOTH generations while it can
  -- produce a valid frame. Stadium/Battle Art may contribute Pokemon artwork or
  -- portable battleActors, but not the stage. A CBE render fault is the single
  -- safety exception: that frame fails open to the authoritative engine field
  -- rather than suppressing the battle into black.
  --
  -- Older builds delegated Gen I to Stadium's provider host when present. That
  -- allowed Battle Art staging selected inside Stadium to replace the arena,
  -- which is the regression this branch removes.
  if StadiumBridge then StadiumBridge.setDelegated(false) end

  -- Android battle entry must establish a drawable CBE host BEFORE any Pokemon
  -- cache/model work. The transition reaches its black resolve before this event;
  -- doing source extraction or a large GPU upload first can therefore leave the
  -- device staring at a black frame with no arena compositor alive yet.
  local hostStart=wallNow()
  local began=StandaloneHost.begin(battle)
  local hostEnd=wallNow()

  -- Desktop keeps the established eager active-pair readiness policy. Android
  -- promotes only already-generated models here and queues genuinely cold models
  -- for cooperative work AFTER the arena has successfully presented a frame.
  -- No source extraction is permitted on this battle.started boundary.
  local modelStart=wallNow()
  if began and PokemonActors and type(PokemonActors.prewarmBattle)=="function" then
    local opts=ANDROID_RUNTIME and {allowExtract=false,deferCold=true} or nil
    local okWarm,result=pcall(PokemonActors.prewarmBattle,battle,opts)
    if okWarm then R.modelPrewarm=result else R.modelPrewarm={failed=2,error=tostring(result)} end
  else
    R.modelPrewarm={ready=0,failed=0,deferred=0,hostUnavailable=not began}
  end
  local modelEnd=wallNow()
  R.entryTiming={totalMs=math.max(0,(modelEnd-entryStart)*1000),modelMs=math.max(0,(modelEnd-modelStart)*1000),
    hostMs=math.max(0,(hostEnd-hostStart)*1000),began=began and true or false,androidDeferred=ANDROID_RUNTIME and true or false}
  if NativeTrainerSprites then
    if began then NativeTrainerSprites:begin({battle=battle})
    else
      -- Host acquisition failed, so CBE is not presenting the world this battle.
      -- Do not suppress native trainer pictures on top of the fail-open field.
      NativeTrainerSprites:finish({battle=battle})
    end
  end
end

local function finishPresentation(battle,reason)
  local exitStart=wallNow()
  battle=Compat and Compat.prepare(battle) or battle
  local standaloneWasActive=false
  if StandaloneHost and type(StandaloneHost.status)=="function" then
    local ok,status=pcall(StandaloneHost.status)
    standaloneWasActive=ok and type(status)=="table" and status.active==true
  end
  local hostFinishStart=wallNow()
  if StandaloneHost then StandaloneHost.finish(reason or "battle.ended") end
  if PokemonActors and type(PokemonActors.cancelBattlePrewarm)=="function" then
    pcall(PokemonActors.cancelBattlePrewarm,"battle-ended")
  end
  local hostFinishEnd=wallNow()
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
  -- Android keeps a small runtime-ready working set instead of throwing away
  -- every parsed/uploaded actor at the end of every battle. 1.7.2's full purge
  -- protected VRAM, but it also guaranteed that the next battle/Pokemon screen
  -- paid the Lua parse + texture decode + GPU upload cost again. 1.7.10 keeps a
  -- bounded multi-battle Pokemon/Waza working set and only evicts after its soft
  -- cap is exceeded; compact parsed MoveFX specs remain cached on disk/in Lua.
  local pokemonTrimMs,wazaTrimMs,randomPrimeMs=0,0,0
  if ANDROID_RUNTIME then
    if PokemonActors and type(PokemonActors.trimRuntimeMemory)=="function" then
      local t0=wallNow()
      -- Protect the entire six-slot player party. The previous four-slot guard
      -- could evict slots 5-6 after every mobile battle and then rebuild them
      -- when a menu/switch touched them. Keep a still-bounded ten-species set:
      -- six party priorities plus four recent encounter species.
      pcall(PokemonActors.trimRuntimeMemory,{game=battle and battle.game,keepParty=6,keepRecent=4,softLimit=10})
      pokemonTrimMs=math.max(0,(wallNow()-t0)*1000)
    end
    -- Do not enqueue model materialization back into ordinary overworld input
    -- frames. An encounter can be accepted inside input.step, so any expensive
    -- work after the engine step can delay the FIRST transition frame by
    -- seconds. Missing party bodies are cheap runtime-sidecar reloads at the
    -- next explicit readiness boundary instead.
    if WazaHandlers and type(WazaHandlers.trimRuntimeMemory)=="function" then
      local t0=wallNow();pcall(WazaHandlers.trimRuntimeMemory);wazaTrimMs=math.max(0,(wallNow()-t0)*1000)
    end
    -- Do NOT clear MoveFXExtractor.memory here. Those entries are compact
    -- parsed cache metadata and prevent repeated disk Lua parsing; WazaHandlers
    -- owns/reclaims the heavyweight GPU-side effect resources above.
    -- Full collections here created a stop-the-world pause immediately before
    -- the next menu/battle. GPU objects are explicitly released above; Lua heap
    -- cleanup is stepped incrementally by the non-battle input hook.
  end

  -- RANDOM still chooses its next venue immediately, but 1.7.10 deliberately
  -- does NOT materialize that arena synchronously on the battle-exit seam.
  -- 1.7.9 moved cold work away from entry but could simply turn it into an
  -- equally visible hitch while returning to the overworld. Runtime mesh
  -- sidecars remain persistent, and already-resident arenas stay hot; a truly
  -- cold random venue is paid behind its next transition instead of freezing
  -- the previous battle's exit.
  local game=battle and battle.game
  if game and ArenaCatalog and type(ArenaCatalog.selected)=="function" and ArenaCatalog.selected(game)=="random"
      and type(ArenaCatalog.primeRandom)=="function" then
    local t0=wallNow();pcall(ArenaCatalog.primeRandom,game);randomPrimeMs=math.max(0,(wallNow()-t0)*1000)
    -- The next RANDOM venue is known now, but never materialize it on the battle
    -- exit seam. Add it to the stable-overworld coordinator instead.
    if ResidentPrewarm and type(ResidentPrewarm.queueArena)=="function" then
      pcall(ResidentPrewarm.queueArena,game,"post-battle-random")
    end
  end
  R.exitTiming={totalMs=math.max(0,(wallNow()-exitStart)*1000),hostFinishMs=math.max(0,(hostFinishEnd-hostFinishStart)*1000),
    pokemonTrimMs=pokemonTrimMs,wazaTrimMs=wazaTrimMs,randomPrimeMs=randomPrimeMs}
  R.activeBattle=nil
  R.pendingEnd=nil
  R.pendingEndReason=nil
  R.pendingEndSince=nil
end

local function endBattle(payload)
  dispatch("battle.ended",payload)
  local battle=(type(payload)=="table" and payload.battle) or R.activeBattle
  battle=Compat and Compat.prepare(battle) or battle
  -- Never tear the CBE compositor down directly from battle.ended. Both engine
  -- generations can emit/forward the result while the battle screen is still
  -- the frame source for an exit transition. Releasing StandaloneHost here can
  -- expose one native white-field/HUD frame before the overworld fade captures
  -- its source -- the brief vanilla flash visible in the reported end-of-battle
  -- clip. Latch the final CBE frame until the authoritative screen boundary.
  --
  -- Gen 2 owns that boundary through completeBattle() below. Gen 1 is released by
  -- the input.step post-step seam only after the battle state has actually left
  -- the stack, ensuring any transition snapshot taken during the engine step is
  -- still sourced from the CBE composite.
  R.pendingEnd=battle
  R.pendingEndSince=wallNow()
  R.pendingEndReason=(Compat and Compat.isGen2Battle(battle)) and "gen2.screen.finished" or "gen1.stack-exited"
end

local function installGen2FinishBoundary()
  if not (Compat and Compat.current and Compat.current()==2) then return true end
  local req=V.engineRequire or require
  local ok,BattleState=pcall(req,"src.battle.BattleState")
  if not ok or type(BattleState)~="table" or type(BattleState.finishBattle)~="function" then
    return false
  end
  local boundary=type(BattleState.completeBattle)=="function" and "completeBattle" or "finishBattle"
  if BattleState[boundary]==R.finishWrapper then return true end
  local inner=BattleState[boundary]
  R.finishWrapper=function(self,...)
    local results={pcall(inner,self,...)}
    local success=table.remove(results,1)
    if not success then error(results[1],0) end
    local battle=Compat and Compat.prepare(self) or self
    local pending=R.pendingEnd
    if pending and ((Compat and Compat.matches(pending,battle)) or pending==battle) then
      finishPresentation(battle,"gen2.screen.finished")
    end
    return unpack(results)
  end
  BattleState[boundary]=R.finishWrapper
  return true
end

function R.runWorkFrame(game,topBefore,topAfter)
  local stateChanged=topBefore~=topAfter
  local perfNow=wallNow()
  if not R.activeBattle and not stateChanged then
    -- Ordinary resident/prewarm work belongs ONLY on the true overworld
    -- state. The previous `not battle + unchanged stack` test also matched
    -- PC/Pokedex/Summary/dialogue screens, so an unrelated arena/trainer/
    -- MoveFX upload could land directly on a menu input frame and freeze
    -- the game + audio for seconds. Two explicit exceptions remain:
    --   1) an active information-viewer lease, whose scheduler is restricted
    --  to that viewer's already-cached, viewer-safe model promotion;
    --   2) Hard Cache Save, an explicit build operation that must progress
    --  while its settings screen is open.
    local onOverworld=FrameWork and FrameWork.isOverworld(game,topAfter) or (topAfter and topAfter.isOverworld==true)
    local viewerWork=false
    local hardCacheWork=false
    if ResidentPrewarm then
      if type(ResidentPrewarm.viewerActive)=="function" then
    local ok,v=pcall(ResidentPrewarm.viewerActive);viewerWork=ok and v==true
      end
      if type(ResidentPrewarm.hardCacheRunning)=="function" then
    local ok,v=pcall(ResidentPrewarm.hardCacheRunning);hardCacheWork=ok and v==true
      end
    end
    if ResidentPrewarm and type(ResidentPrewarm.pump)=="function" then
      if onOverworld or viewerWork or hardCacheWork then pcall(ResidentPrewarm.pump,game) end
    elseif onOverworld and PokemonActors and type(PokemonActors.pumpPartyPrewarm)=="function" then
      -- Compatibility fallback for stripped integrations that omit the
      -- coordinator: keep the old one-species queue rather than bulk warm.
      pcall(PokemonActors.pumpPartyPrewarm,game)
    end
    -- Only a tiny incremental GC step remains in interactive Android TRUE
    -- overworld frames. Even incremental GC is kept out of 3D menu browsing
    -- so driver/Lua cleanup cannot coincide with rapid species changes.
    if onOverworld and ANDROID_RUNTIME and perfNow>=androidGcNextAt and PokemonActors and type(PokemonActors.gcStep)=="function" then
      pcall(PokemonActors.gcStep,24);androidGcNextAt=perfNow+0.18
    end
  elseif R.activeBattle and not stateChanged and ResidentPrewarm
      and ResidentPrewarm.viewerActive and ResidentPrewarm.viewerActive() then
    -- An optional Party/Summary overlay still belongs to the current battle.
    -- Permit ONLY the selected viewer's resumable jobs, not startup/arena work.
    pcall(ResidentPrewarm.pump,game,true)
  elseif R.activeBattle and not stateChanged and ANDROID_RUNTIME and PokemonActors
      and type(PokemonActors.pumpBattlePrewarm)=="function" then
    local presented=false
    if StandaloneHost and type(StandaloneHost.status)=="function" then
      local okStatus,status=pcall(StandaloneHost.status)
      presented=okStatus and type(status)=="table" and status.presented==true and status.failOpen~=true
    end
    if presented then
      local okPump,worked,pending=pcall(PokemonActors.pumpBattlePrewarm,3)
      if okPump and (worked==true or (tonumber(pending) or 0)>0) then return end
    end
    if perfNow>=androidActionWarmNextAt and type(PokemonActors.pumpActionPrewarm)=="function" then
      pcall(PokemonActors.pumpActionPrewarm,1);androidActionWarmNextAt=perfNow+0.18
    end
  elseif R.activeBattle and not stateChanged and perfNow>=androidActionWarmNextAt and PokemonActors and type(PokemonActors.pumpActionPrewarm)=="function" then
    -- Exact source action banks are staged rather than bulk-uploaded on
    -- battle.started. One bank per stable frame window keeps transition latency
    -- bounded without changing battle timing.
    pcall(PokemonActors.pumpActionPrewarm,1);androidActionWarmNextAt=perfNow+0.07
  end
end
function R.attachFrame(game)
  return FrameWork and FrameWork.attach(game,R.runWorkFrame) or false
end

function R.install()
  if R.installed then installGen2FinishBoundary();installCaptureSoundBridge();return true end

  installGen2FinishBoundary()
  installCaptureSoundBridge()

  if mod.hooks and type(mod.hooks.wrap)=="function" then
    mod.hooks:wrap("input.step",function(next,game,dt)
      -- An encounter transition is pushed DURING the engine step. Snapshot the
      -- stack so CBE can guarantee that no background cache/model job runs
      -- after that push but before the transition gets its first draw. This was
      -- the hidden source of the 5-10 second "encounter happened, wipe has not
      -- appeared yet" pause on slower Android storage/GPUs.
      local topBefore=stackTop(game)
      local result=next(game,dt)
      local topAfter=stackTop(game)
      local stateChanged=topBefore~=topAfter

      -- Gen 1 exit-presentation latch. battle.ended is delivered during the
      -- engine step, but the same step may still need the current battle frame
      -- as the source for BattleReturn/MapEntryAfterBattle. Keep CBE resident
      -- through that work and release only after the battle state is no longer
      -- top-of-stack. This removes the single-frame native battle leak without
      -- delaying battle logic, map music restoration, or the actual fade.
      if R.pendingEnd and not (Compat and Compat.isGen2Battle(R.pendingEnd)) then
        local stillBattle=false
        if topAfter then
          stillBattle=(topAfter==R.pendingEnd)
          if not stillBattle and Compat and type(Compat.matches)=="function" then
            local okMatch,matched=pcall(Compat.matches,R.pendingEnd,topAfter)
            stillBattle=okMatch and matched==true
          end
        end
        if not stillBattle then
          finishPresentation(R.pendingEnd,R.pendingEndReason or "gen1.stack-exited")
        end
      end

      if BattleDirector and R.activeBattle and type(BattleDirector.update)=="function" then
        pcall(BattleDirector.update,BattleDirector,contextFor(R.activeBattle),dt)
      end
      -- Legacy hosts/tests without Game.update retain the old paced fallback.
      -- On native Gen I/II, preparation drains once AFTER the real update.
      if not (FrameWork and FrameWork.active(game)) then
        R.attachFrame(game)
        if not (FrameWork and FrameWork.attached(game)) then R.runWorkFrame(game,topBefore,topAfter) end
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

  R.attachFrame(mod.game)
  R.installed=true
  return true
end

function R.status()
  return {installed=R.installed,active=R.activeBattle~=nil,pendingEnd=R.pendingEnd~=nil,
    endBoundary=(Compat and Compat.current and Compat.current()==2) and "gen2.screen.finished" or "gen1.stack-exited",
    exitPresentationLatch=R.pendingEnd~=nil and (R.pendingEndReason or "pending") or "idle",
    captureSoundBridge=R.captureSoundBridge==true,nativeCaughtSuppressed=R.nativeCaughtSuppressed or 0,
    moveSoundBridge=R.moveSoundBridge==true,nativeMoveSoundsSuppressed=R.nativeMoveSoundsSuppressed or 0,
    modelPrewarm=R.modelPrewarm,entryTiming=R.entryTiming,exitTiming=R.exitTiming,
    captureSuccessAudio="ISO me_snatch owns success; native Caught_Mon suppressed only when source cue is available",
    moveAudio="Waza type-5 GameSound owns native battle-animation SFX only when the complete generated snd_se_battle WAV set is present"}
end

return R
