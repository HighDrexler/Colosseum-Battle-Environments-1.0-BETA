local V=...
local R={installed=false,activeBattle=nil,pendingEnd=nil,finishWrapper=nil}

local mod=V.mod
local ArenaCatalog=V.ArenaCatalog
local Camera=V.Camera
local NativeTrainerSprites=V.NativeTrainerSprites
local PlayerTrainer=V.PlayerTrainer
local StandaloneHost=V.StandaloneHost
local StadiumBridge=V.StadiumBridge
local Trainer=V.Trainer
local Compat=V.GenerationCompat

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

local function dispatch(name,payload)
  if StandaloneHost then StandaloneHost.event(name,payload) end
  local battle=(type(payload)=="table" and payload.battle) or R.activeBattle
  battle=Compat and Compat.prepare(battle) or battle
  local ctx=contextFor(battle)

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

  if not StandaloneHost then return end
  if StadiumBridge and StadiumBridge.hasProviderHost() then
    StandaloneHost.finish("stadium-provider-host")
    StadiumBridge.setDelegated(true)
    -- With a provider host, resolve actual arena ownership before suppressing
    -- the native battle picture layer. An enabled preference is not ownership.
    if NativeTrainerSprites then
      if StadiumBridge.ownsArena(battle) then NativeTrainerSprites:begin({battle=battle})
      else NativeTrainerSprites:finish({battle=battle}) end
    end
  else
    -- Standalone ownership is established only after the arena successfully
    -- begins. If its trainer cache is missing, leave native battle rendering
    -- completely untouched and fail open rather than producing a black battle.
    local began=StandaloneHost.begin(battle)
    if NativeTrainerSprites then
      if began then NativeTrainerSprites:begin({battle=battle})
      else NativeTrainerSprites:finish({battle=battle}) end
    end
    if StadiumBridge then StadiumBridge.setDelegated(false) end
  end
end

local function finishPresentation(battle,reason)
  battle=Compat and Compat.prepare(battle) or battle
  if StandaloneHost then StandaloneHost.finish(reason or "battle.ended") end
  if NativeTrainerSprites then NativeTrainerSprites:finish({battle=battle}) end
  if ArenaCatalog and ArenaCatalog.releaseBattle then ArenaCatalog.releaseBattle(battle) end
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
  if R.installed then installGen2FinishBoundary();return true end

  installGen2FinishBoundary()

  if mod.hooks and type(mod.hooks.wrap)=="function" then
    mod.hooks:wrap("input.step",function(next,game,dt)
      local result=next(game,dt)
      if StandaloneHost then StandaloneHost.update(dt) end
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
    endBoundary=(Compat and Compat.current and Compat.current()==2) and "gen2.screen.finished" or "battle.ended"}
end

return R
