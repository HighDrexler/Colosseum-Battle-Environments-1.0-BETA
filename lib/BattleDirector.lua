local V=...
local S=V.BattleSides
local MoveFX=V.MoveFXExtractor
local WazaSequence=V.WazaSequenceRuntime

local D={}

local state={
  battle=nil,time=0,serial=0,moves={player=nil,enemy=nil},faint={},lastEvent=nil,
  prefetch={requested=0,ready=0,queued=0,completed=0,failed=0},
  seen=setmetatable({},{__mode="k"}),
}

local function battleOf(ctx)
  if type(ctx)~="table" then return nil end
  return ctx.battle or (ctx.kind and ctx) or nil
end

local function sideFrom(ctx,payload,fields)
  if S and type(S.payload)=="function" then return S.payload(ctx,payload,fields) end
  return nil
end

local function other(side)
  if S and type(S.other)=="function" then return S.other(side) end
  return side=="player" and "enemy" or (side=="enemy" and "player" or nil)
end

local function reset(battle)
  state.battle=battle
  state.time=0
  state.serial=0
  state.moves={player=nil,enemy=nil}
  state.faint={}
  state.lastEvent=nil
  state.prefetch={requested=0,ready=0,queued=0,completed=0,failed=0}
  state.seen=setmetatable({},{__mode="k"})
end

local function ensure(ctx)
  local b=battleOf(ctx)
  if b~=state.battle then reset(b) end
  return b
end

local function phaseFor(seq)
  if not seq then return nil end
  local age=math.max(0,state.time-(seq.startedAt or state.time))
  local d=math.max(.05,tonumber(seq.attackDuration) or .9)
  if seq.impactAt and state.time>=seq.impactAt then
    local ia=state.time-seq.impactAt
    if ia<math.max(.18,d*.14) then return "impact" end
    if age<d then return "recovery" end
  end
  if age<d*.16 then return "anticipation" end
  if age<d*.72 then return "action" end
  if age<d then return "recovery" end
  return "done"
end

local function fxCueTime(seq)
  if not seq then return nil end
  local d=math.max(.05,tonumber(seq.attackDuration) or .9)
  local style=tostring(seq.fxStyle or "impact")
  if style=="impact" then return seq.impactAt end
  if style=="projectile" then return (seq.startedAt or state.time)+d*.22 end
  if style=="contact" then return (seq.startedAt or state.time)+d*.10 end
  if style=="target" then return (seq.startedAt or state.time)+d*.40 end
  if style=="wave" then return (seq.startedAt or state.time)+d*.20 end
  if style=="aura" or style=="self" then return (seq.startedAt or state.time)+d*.14 end
  return (seq.startedAt or state.time)+d*.26
end

function D:begin(ctx)
  local b=battleOf(ctx)
  reset(b)
  if WazaSequence and type(WazaSequence.finish)=="function" then pcall(WazaSequence.finish,WazaSequence,ctx,"battle-begin-reset") end
  if MoveFX and type(MoveFX.prefetchBattle)=="function" and b then
    local ok,result=pcall(MoveFX.prefetchBattle,b)
    if ok and type(result)=="table" then
      state.prefetch.requested=tonumber(result.requested) or 0
      state.prefetch.ready=tonumber(result.ready) or 0
      state.prefetch.queued=tonumber(result.queued) or 0
      state.prefetch.failed=tonumber(result.failed) or 0
      -- Finish the CURRENT battlers' source banks before CBE opens its world.
      -- This is deliberately at battle.started, before StandaloneHost.begin(),
      -- never on a visible move/impact frame. The former queue-only policy had
      -- no pump caller at all, so an uncached move could remain generic for the
      -- entire battle despite its Colosseum WZX being available.
      if state.prefetch.queued>0 and type(MoveFX.pumpPrefetch)=="function" then
        local okPump,pumped=pcall(MoveFX.pumpPrefetch,math.min(8,state.prefetch.queued))
        if okPump and type(pumped)=="table" then
          state.prefetch.completed=tonumber(pumped.ready) or 0
          state.prefetch.ready=state.prefetch.ready+state.prefetch.completed
          state.prefetch.failed=state.prefetch.failed+(tonumber(pumped.failed) or 0)
        end
      end
    end
  end
  return true
end

function D:update(ctx,dt)
  ensure(ctx)
  local step=math.max(0,tonumber(dt) or 0)
  state.time=state.time+step
  if WazaSequence and type(WazaSequence.update)=="function" then
    pcall(WazaSequence.update,WazaSequence,ctx,step)
  end
  for _,side in ipairs({"player","enemy"}) do
    local seq=state.moves[side]
    if seq then
      seq.phase=phaseFor(seq)
      local d=math.max(.05,tonumber(seq.attackDuration) or .9)
      local tail=seq.impactAt and .42 or .18
      if state.time-(seq.startedAt or state.time)>d+tail and (not seq.fxSpec or seq.fxStarted) then
        state.moves[side]=nil
      end
    end
  end
end

function D:event(ctx,name,payload)
  ensure(ctx)
  payload=type(payload)=="table" and payload or {}
  if type(payload)=="table" then
    local prev=state.seen[payload]
    if prev==name then return end
    state.seen[payload]=name
  end
  local b=battleOf(ctx)
  local gen2=b and b.__cbeGeneration==2
  local queueSync=gen2 and b.__cbePresentationQueueSync==true
  -- 1.5.32: presentation is battle-flow authoritative, never text/input
  -- authoritative. Gold's presentation_* rows are emitted later when the UI
  -- queue is consumed, and A/B can advance that queue. Treat those rows as
  -- visual-suppression bookkeeping only and drive the director from the
  -- resolved battle semantics immediately. This makes camera/actors/trainers
  -- deterministic regardless of how quickly the player pages text.
  if queueSync and (name=="battle.move_used" or name=="battle.damage_dealt" or name=="battle.fainted") then return end
  local semantic=name
  if name=="battle.presentation_damage" then semantic="battle.damage_dealt"
  elseif name=="battle.presentation_faint" then semantic="battle.fainted" end
  state.lastEvent=name

  if semantic=="battle.move_used" or name=="battle.presentation_move" then
    local side=sideFrom(ctx,payload,{"user","attacker","source","battler","side"})
    if not side and S and type(S.value)=="function" then side=S.value(payload.side) end
    if side then
      state.serial=state.serial+1
      state.moves[side]={serial=state.serial,side=side,target=other(side),startedAt=state.time,
        attackDuration=.9,phase="anticipation",moveId=payload.moveId,
        sourceEvent=name,fxStarted=false,impactAt=nil,damage=nil}
    end
  elseif semantic=="battle.damage_dealt" then
    local target=sideFrom(ctx,payload,{"target","defender","targetSide","defenderSide","battler"})
    if not target then
      local attacker=sideFrom(ctx,payload,{"user","attacker","source","side"})
      target=other(attacker)
    end
    local attacker=other(target)
    local seq=attacker and state.moves[attacker]
    if seq then
      seq.target=target or seq.target
      seq.impactAt=state.time
      seq.damage=tonumber(payload.damage or payload.amount or payload.hpDamage)
      seq.phase="impact"
      if seq.fxStyle=="impact" then seq.fxAt=state.time end
    end
  elseif semantic=="battle.fainted" then
    local target=sideFrom(ctx,payload,{"battler","target","side","faintedSide","targetSide"})
    local attacker=other(target)
    local seq=attacker and state.moves[attacker]
    if seq then seq.faintedSide=target;seq.faintAt=state.time end
  elseif name=="battle.battler_switched" then
    local side=sideFrom(ctx,payload,{"side","battler","target","switchedSide","replacement"})
    if side then state.moves[side]=nil end
    if MoveFX and type(MoveFX.prefetchBattler)=="function" and b and side then
      local battler=b[side]
      if battler then
        local ok,r=pcall(MoveFX.prefetchBattler,b,battler)
        if ok and type(r)=="table" then
          local queued=tonumber(r.queued) or 0
          state.prefetch.requested=state.prefetch.requested+(tonumber(r.requested) or 0)
          state.prefetch.ready=state.prefetch.ready+(tonumber(r.ready) or 0)
          state.prefetch.queued=state.prefetch.queued+queued
          state.prefetch.failed=state.prefetch.failed+(tonumber(r.failed) or 0)
          -- A newly switched battler may not have been visible at battle.start.
          -- Complete at most its four move banks now, at the switch boundary,
          -- so the next attack cannot silently fall back for the whole fight.
          -- Performance/caching can be tightened after this fidelity candidate.
          if queued>0 and type(MoveFX.pumpPrefetch)=="function" then
            local okPump,pumped=pcall(MoveFX.pumpPrefetch,math.min(4,queued))
            if okPump and type(pumped)=="table" then
              local ready=tonumber(pumped.ready) or 0
              state.prefetch.completed=state.prefetch.completed+ready
              state.prefetch.ready=state.prefetch.ready+ready
              state.prefetch.failed=state.prefetch.failed+(tonumber(pumped.failed) or 0)
            end
          end
        end
      end
    end
  elseif name=="battle.ended" then
    state.moves={player=nil,enemy=nil}
  end
end

-- Called immediately after the Pokemon actor chooses its real PKX action bank.
-- This is the authoritative bridge between source animation length and every
-- other presentation system; camera/FX/trainer choreography can now share one
-- game-time move clock instead of inventing unrelated timers.
function D:bindAttack(ctx,side,moveId,move,duration,fxSpec,wazaTimingPoints,presentationFrames,animationSlot,animationName)
  ensure(ctx)
  if not side then return nil end
  local seq=state.moves[side]
  if not seq then
    state.serial=state.serial+1
    seq={serial=state.serial,side=side,target=other(side),startedAt=state.time,phase="anticipation",fxStarted=false}
    state.moves[side]=seq
  end
  seq.moveId=moveId or seq.moveId
  seq.move=move or seq.move
  seq.attackDuration=math.max(.05,tonumber(duration) or tonumber(seq.attackDuration) or .9)
  seq.wazaTimingPoints=type(wazaTimingPoints)=="table" and wazaTimingPoints or seq.wazaTimingPoints
  seq.presentationFrames=tonumber(presentationFrames) or math.floor(seq.attackDuration*60+.5)
  seq.animationSlot=animationSlot or seq.animationSlot
  seq.animationName=animationName or seq.animationName
  if type(fxSpec)=="table" then
    seq.fxSpec=fxSpec
    seq.fxStyle=fxSpec.style or "impact"
    seq.fxDuration=tonumber(fxSpec.duration)
    if WazaSequence and type(WazaSequence.hasTimeline)=="function" and type(WazaSequence.start)=="function" then
      local okHas,has=pcall(WazaSequence.hasTimeline,WazaSequence,fxSpec,"attack")
      if okHas and has and not seq.wazaAttackSerial then
        -- Waza must never start before the actor has selected the actual PKX
        -- attack slot. The caller supplies that slot's retail timing points;
        -- starting without them recreates the old generic-percentage timing bug.
        -- A semantic move can be rebound by more than one presentation wrapper,
        -- so once this move-sequence owns a Waza serial it is never restarted.
        local okStart,inst=pcall(WazaSequence.start,WazaSequence,ctx,side,fxSpec,{
          role="attack",target=seq.target,moveId=seq.moveId,move=seq.move,startedAt=seq.startedAt,
          globalTimingPoints=seq.wazaTimingPoints,presentationFrames=seq.presentationFrames,
          animationSlot=seq.animationSlot,animationName=seq.animationName})
        if okStart and type(inst)=="table" then seq.wazaAttackSerial=inst.serial end
      end
    end
  end
  seq.fxAt=fxCueTime(seq)
  seq.phase=phaseFor(seq)
  return seq
end

function D:bindDamage(ctx,attacker,target,fxSpec,moveId,move,wazaTimingPoints,presentationFrames)
  ensure(ctx)
  if not (attacker and target and type(fxSpec)=="table") then return nil,"damage binding incomplete" end
  if not (WazaSequence and type(WazaSequence.hasTimeline)=="function" and type(WazaSequence.start)=="function") then
    return nil,"WazaSequence unavailable"
  end
  local okHas,has=pcall(WazaSequence.hasTimeline,WazaSequence,fxSpec,"damage")
  if not okHas or not has then return nil,"no damage Waza timeline" end
  -- Missing PKX timing points are an explicit Waza timing fallback, not a
  -- reason to split the presentation into an unrelated direct GPT1 path.
  local okStart,inst,why=pcall(WazaSequence.start,WazaSequence,ctx,attacker,fxSpec,{
    role="damage",target=target,moveId=moveId,move=move,globalTimingPoints=wazaTimingPoints,
    presentationFrames=tonumber(presentationFrames) or 0})
  if not okStart or type(inst)~="table" then return nil,tostring(okStart and why or inst) end
  return inst
end

function D:bindFaint(ctx,side,duration)
  ensure(ctx)
  state.faint=state.faint or {}
  state.faint[side]={startedAt=state.time,duration=math.max(.05,tonumber(duration) or 1.0)}
end

function D:consumeFxCue(ctx,side)
  ensure(ctx)
  local seq=side and state.moves[side]
  if not (seq and seq.fxSpec) or seq.fxStarted then return nil end
  local at=seq.fxAt or fxCueTime(seq)
  if not at or state.time<at then return nil end
  seq.fxStarted=true
  return {serial=seq.serial,side=side,target=seq.target,moveId=seq.moveId,move=seq.move,spec=seq.fxSpec,
    phase=seq.phase,attackDuration=seq.attackDuration,impactAt=seq.impactAt}
end

function D:move(ctx,side)
  ensure(ctx)
  local seq=state.moves[side]
  if not seq then return nil end
  seq.phase=phaseFor(seq)
  return seq
end

function D:attackDuration(ctx,side)
  local seq=self:move(ctx,side)
  return seq and seq.attackDuration or nil
end

function D:faintDuration(ctx,side)
  ensure(ctx)
  local f=state.faint and state.faint[side]
  return f and f.duration or nil
end

function D:finish(ctx,reason)
  if WazaSequence and type(WazaSequence.finish)=="function" then pcall(WazaSequence.finish,WazaSequence,ctx,reason or "battle-finish") end
  reset(nil)
end

function D:status()
  local function brief(seq)
    if not seq then return nil end
    return {serial=seq.serial,moveId=seq.moveId,phase=phaseFor(seq),duration=seq.attackDuration,
      fxStyle=seq.fxStyle,fxStarted=seq.fxStarted,wazaAttackSerial=seq.wazaAttackSerial,impactAt=seq.impactAt and (seq.impactAt-state.time) or nil}
  end
  return {version=2,clock="game-time",time=state.time,lastEvent=state.lastEvent,
    player=brief(state.moves.player),enemy=brief(state.moves.enemy),prefetch=state.prefetch}
end

return D
