local V=...
local MoveFXVM=V and V.MoveFXVM
local W={
  version=6,
  source="GC6E01 exact-node-offset dependency-timed 60 Hz Waza lifecycle scheduler",
  handlers={},active={},serial=0,trace={},errors={},last=nil,
}

local FRAME_DT=1/60
local MAX_STEPS_PER_UPDATE=30
local MAX_TRACE=256
local MAX_ERRORS=64

local function roleForPhase(phase)
  phase=tostring(phase or "all"):lower()
  if phase=="damage" or phase=="status" then return "damage" end
  return "attack"
end

local function pushTrace(row)
  W.trace[#W.trace+1]=row
  while #W.trace>MAX_TRACE do table.remove(W.trace,1) end
end
local function pushError(row)
  W.errors[#W.errors+1]=row
  while #W.errors>MAX_ERRORS do table.remove(W.errors,1) end
end

local function phaseEntries(spec,role)
  local out={}
  local runtimePhase=0
  for _,phase in ipairs(type(spec)=="table" and (spec.wazaPhases or {}) or {}) do
    if roleForPhase(phase.name)==role then
      runtimePhase=runtimePhase+1
      local namespace=runtimePhase*100000
      for _,entry in ipairs(phase.entries or {}) do
        local copy={}
        for k,v in pairs(entry) do copy[k]=v end
        copy.phase=copy.phase or phase.name
        copy.rawPath=copy.rawPath or phase.rawPath
        -- WZX entry identifiers are local to each source phase. Curated moves
        -- can legitimately layer attack + sp1 (Ember is one), so timing anchors
        -- must be namespaced for the scheduler while the original identifier is
        -- preserved for GPT1/model handler matching and diagnostics.
        local sourceId=tonumber(copy.identifier) or tonumber(copy.index) or (#out+1)
        local sourceAnchor=math.floor(tonumber(copy.anchorEntry) or 0)
        copy.runtimeIdentifier=namespace+sourceId
        copy.runtimeAnchorEntry=sourceAnchor>0 and (namespace+sourceAnchor) or 0
        copy.runtimePhaseOrder=runtimePhase
        out[#out+1]=copy
      end
    end
  end
  table.sort(out,function(a,b)
    local ap=tonumber(a.runtimePhaseOrder) or 0
    local bp=tonumber(b.runtimePhaseOrder) or 0
    if ap~=bp then return ap<bp end
    local ai=tonumber(a.identifier) or tonumber(a.index) or 0
    local bi=tonumber(b.identifier) or tonumber(b.index) or 0
    if ai~=bi then return ai<bi end
    return (tonumber(a.offset) or 0)<(tonumber(b.offset) or 0)
  end)
  return out
end

local function particleEntry(entry)
  return type(entry)=="table" and entry.kind=="particle"
end

local function pointIndex(v)
  v=tonumber(v)
  if not v then return nil end
  v=math.floor(v+.0)
  if v<0 or v>15 then return nil end
  return v
end

local function entryPoint(entry,index)
  index=pointIndex(index)
  if index==nil then return nil end
  local t=type(entry)=="table" and entry.timingPoints
  local v=type(t)=="table" and tonumber(t[index+1]) or nil
  if not v or v < -0x100000 or v > 0x100000 then return nil end
  return math.floor(v+.0)
end

local function globalPoint(points,index)
  index=pointIndex(index)
  if index==nil then return nil end
  local v=type(points)=="table" and tonumber(points[index+1]) or nil
  if not v or v < -0x100000 or v > 0x100000 then return nil end
  return math.floor(v+.0)
end

-- Retail loadTotalSequence/wazaSequence timing model, reconstructed from
-- GC6E01 main.dol. Each source row chooses a local timing point and either a
-- prior SequenceEntry+point or the active Pokemon/Waza global timing point.
-- Colosseum then shifts the entire sequence if any row would begin negative.
local function resolveEntryStarts(entries,globalTimingPoints)
  local byId={}; local rows={}; local unresolved=0; local minStart=math.huge; local maxStart=0
  for _,entry in ipairs(entries or {}) do
    local id=tonumber(entry.runtimeIdentifier) or tonumber(entry.identifier) or tonumber(entry.index) or (#rows+1)
    local anchor=math.floor(tonumber(entry.runtimeAnchorEntry) or tonumber(entry.anchorEntry) or 0)
    local localIdx=pointIndex(entry.localPoint)
    local anchorIdx=pointIndex(entry.anchorPoint)
    local localValue=entryPoint(entry,localIdx) or 0
    local start,source,fallback

    if anchor>0 and byId[anchor] then
      local ref=byId[anchor]
      local refPoint=entryPoint(ref.entry,anchorIdx)
      if refPoint==nil then refPoint=0;fallback="missing-anchor-entry-point" end
      start=(ref.startFrame or 0)+refPoint-localValue
      source="entry"
    else
      local gp=globalPoint(globalTimingPoints,anchorIdx)
      if gp==nil then
        -- Point zero is the Waza origin by definition. Other absent points are
        -- retained as an explicit fail-open timing fallback, never disguised as
        -- exact retail timing. Current PKX metadata supplies points 0..3.
        gp=0
        fallback=(anchor>0 and "missing-anchor-entry" or "missing-global-point")
      end
      start=gp-localValue
      source="global"
    end

    start=math.floor((tonumber(start) or 0)+.0)
    local row={entry=entry,id=id,startFrame=start,timingSource=source,timingFallback=fallback,
      localPoint=localIdx,anchorPoint=anchorIdx,anchorEntry=anchor,localValue=localValue}
    rows[#rows+1]=row;byId[id]=row
    if fallback then unresolved=unresolved+1 end
    if start<minStart then minStart=start end
    if start>maxStart then maxStart=start end
  end

  if minStart==math.huge then minStart=0 end
  local shift=minStart<0 and -minStart or 0
  maxStart=0
  for _,row in ipairs(rows) do
    row.unshiftedStartFrame=row.startFrame
    row.startFrame=row.startFrame+shift
    row.entry.resolvedStartFrame=row.startFrame
    row.entry.timingShift=shift
    row.entry.timingFallback=row.timingFallback
    if row.startFrame>maxStart then maxStart=row.startFrame end
  end
  return rows,{shift=shift,unresolved=unresolved,maxStart=maxStart,minUnshifted=minStart}
end

function W:registerHandler(kind,id,handler)
  kind=tostring(kind or "unknown");id=tostring(id or "handler")
  if type(handler)~="table" then return false,"handler must be table" end
  self.handlers[kind]=self.handlers[kind] or {}
  for i=#self.handlers[kind],1,-1 do
    if self.handlers[kind][i].id==id then table.remove(self.handlers[kind],i) end
  end
  self.handlers[kind][#self.handlers[kind]+1]={id=id,handler=handler}
  return true
end

function W:unregisterHandler(kind,id)
  local list=self.handlers[tostring(kind or "")]
  if not list then return false end
  for i=#list,1,-1 do if list[i].id==id then table.remove(list,i) end end
  return true
end

function W:hasTimeline(spec,role)
  role=tostring(role or "attack")
  return #phaseEntries(spec,role)>0
end

function W:canOwn(spec,role)
  local roles=role and {tostring(role)} or {"attack","damage"}
  for _,r in ipairs(roles) do
    for _,entry in ipairs(phaseEntries(spec,r)) do
      -- Particle ownership remains strict: the referenced GPT1 root must be
      -- executable by the source bytecode VM. Type-2 effect models are now an
      -- equally authoritative Waza presentation path once their HSD cache was
      -- compiled successfully. This lets model-only / model-led source moves
      -- suppress the native Game Boy visual layer without requiring a fake
      -- particle root solely to pass the ownership gate.
      if particleEntry(entry) and MoveFXVM and type(MoveFXVM.hasEntry)=="function"
          and MoveFXVM.hasEntry(spec,entry,r) then return true end
      if type(entry)=="table" and entry.kind=="model"
          and type(entry.modelAsset)=="table" and entry.modelAsset.cache then return true end
    end
  end
  return false
end

local function handlerRecords(entry)
  return W.handlers[type(entry)=="table" and entry.kind or ""] or {}
end

local function callHandlers(ctx,inst,state,eventName)
  local entry=state.entry
  local claimed=false
  for _,record in ipairs(handlerRecords(entry)) do
    local fn=record.handler[eventName]
    if type(fn)=="function" then
      local ok,result=pcall(fn,ctx,inst,entry,eventName,state)
      if not ok then
        pushError({serial=inst.serial,kind=entry.kind,handler=record.id,event=eventName,error=tostring(result)})
      elseif result~=false and result~=nil then claimed=true end
    end
  end
  if eventName~="update" then
    pushTrace({serial=inst.serial,frame=inst.frame,role=inst.role,phase=entry.phase,index=entry.index,
      identifier=entry.identifier,kind=entry.kind,event=eventName,claimed=claimed,
      resolvedStartFrame=state.startFrame,timingFallback=state.timingFallback})
  end
  return claimed
end

local function hasUpdateHandler(state)
  for _,record in ipairs(handlerRecords(state.entry)) do
    if type(record.handler.update)=="function" then return true end
  end
  return false
end

local function closeState(ctx,inst,state,reason,cancelled)
  if not state or not state.started or state.closed then return end
  local event=cancelled and "cancel" or "finish"
  local called=false
  for _,record in ipairs(handlerRecords(state.entry)) do
    local fn=record.handler[event]
    if type(fn)=="function" then
      called=true
      local ok,result=pcall(fn,ctx or inst.ctx,inst,state.entry,reason or event,state)
      if not ok then pushError({serial=inst.serial,kind=state.entry.kind,handler=record.id,event=event,error=tostring(result)}) end
    end
  end
  if cancelled and not called then callHandlers(ctx or inst.ctx,inst,state,"finish") end
  state.closed=true;state.finished=true;state.finishReason=reason or event
  pushTrace({serial=inst.serial,frame=inst.frame,role=inst.role,phase=state.entry.phase,index=state.entry.index,
    identifier=state.entry.identifier,kind=state.entry.kind,event=event,entryClose=true,reason=state.finishReason})
end

local function finishInstance(ctx,inst,reason,cancelled)
  if not inst or inst.done then return end
  inst.cancelled=cancelled==true;inst.finishReason=reason or (cancelled and "cancelled" or "complete")
  for _,state in ipairs(inst.entries or {}) do
    if state.started and not state.closed then closeState(ctx or inst.ctx,inst,state,inst.finishReason,cancelled) end
  end
  pushTrace({serial=inst.serial,frame=inst.frame,role=inst.role,event=cancelled and "sequence-cancel" or "sequence-finish",
    reason=inst.finishReason})
  inst.done=true
end

local function fireDue(ctx,inst,frame)
  local allStarted=true
  for _,state in ipairs(inst.entries) do
    if not state.started and frame>=state.startFrame then
      state.started=true
      state.claimed=callHandlers(ctx,inst,state,"start") or state.claimed
      state.hasUpdate=hasUpdateHandler(state)
      if not state.hasUpdate then
        state.finished=true
        -- Retail has an explicit EntryStart/EntryUpdate/EntryStop lifecycle.
        -- A start-only entry therefore reaches its Stop hook immediately after
        -- launch; long-lived objects (GPT1 particles) retain their own lifetime.
        closeState(ctx,inst,state,"start-only-entry-complete",false)
      end
    end
    if not state.started then allStarted=false
    elseif state.hasUpdate and not state.finished then
      local any=false;local keep=false
      for _,record in ipairs(handlerRecords(state.entry)) do
        local fn=record.handler.update
        if type(fn)=="function" then
          any=true
          local ok,result=pcall(fn,ctx,inst,state.entry,frame,state)
          if not ok then
            pushError({serial=inst.serial,kind=state.entry.kind,handler=record.id,event="update",error=tostring(result)})
          elseif result~=false and result~="done" then keep=true end
        end
      end
      if any and not keep then closeState(ctx,inst,state,"entry-update-complete",false) end
    end
  end
  return allStarted
end

function W:start(ctx,side,spec,opts)
  opts=type(opts)=="table" and opts or {}
  local role=tostring(opts.role or "attack")
  local entries=phaseEntries(spec,role)
  if #entries==0 then return nil,"no WazaSequence entries for role" end

  if role=="attack" then
    for i=#self.active,1,-1 do
      local old=self.active[i]
      if old.side==side and old.role=="attack" then
        finishInstance(ctx,old,"superseded-by-new-attack",true);table.remove(self.active,i)
      end
    end
  else
    for _,old in ipairs(self.active) do
      if old.role=="damage" and old.side==side and old.spec==spec and old.target==opts.target
          and (tonumber(old.age) or 1)<0.065 then return old,"duplicate-damage-boundary" end
    end
  end

  local resolved,timing=resolveEntryStarts(entries,opts.globalTimingPoints)
  self.serial=self.serial+1
  local inst={
    serial=self.serial,ctx=ctx,side=side,target=opts.target or (side=="player" and "enemy" or "player"),
    role=role,spec=spec,moveId=opts.moveId,move=opts.move,age=0,frame=0,accumulator=0,
    entries={},done=false,cancelled=false,startedAt=opts.startedAt,
    presentationSerial=opts.presentationSerial,parentAttackSerial=opts.parentAttackSerial,
    globalTimingPoints=opts.globalTimingPoints,timing=timing,
  }
  for _,row in ipairs(resolved) do
    inst.entries[#inst.entries+1]={entry=row.entry,startFrame=row.startFrame,unshiftedStartFrame=row.unshiftedStartFrame,
      timingFallback=row.timingFallback,started=false,finished=false,closed=false,claimed=false}
  end

  local globalMax=0
  for _,v in ipairs(type(opts.globalTimingPoints)=="table" and opts.globalTimingPoints or {}) do
    v=tonumber(v);if v and v>globalMax then globalMax=v end
  end
  local presentationFrames=math.max(0,math.floor(tonumber(opts.presentationFrames) or 0))
  inst.sourceEndFrame=math.max(1,timing.maxStart+1,globalMax+1,presentationFrames)
  self.active[#self.active+1]=inst;self.last=inst
  pushTrace({serial=inst.serial,frame=0,role=role,event="sequence-start",timingShift=timing.shift,
    unresolvedTiming=timing.unresolved,sourceEndFrame=inst.sourceEndFrame})
  fireDue(ctx,inst,0)
  return inst
end

function W:update(ctx,dt)
  local step=math.max(0,tonumber(dt) or 0)
  for i=#self.active,1,-1 do
    local inst=self.active[i]
    if inst.done then table.remove(self.active,i)
    else
      inst.age=inst.age+step;inst.accumulator=inst.accumulator+step
      local steps=0
      while inst.accumulator>=FRAME_DT and steps<MAX_STEPS_PER_UPDATE do
        inst.accumulator=inst.accumulator-FRAME_DT;steps=steps+1;inst.frame=inst.frame+1
        fireDue(ctx or inst.ctx,inst,inst.frame)
      end
      if steps>=MAX_STEPS_PER_UPDATE and inst.accumulator>FRAME_DT*MAX_STEPS_PER_UPDATE then
        inst.accumulator=FRAME_DT*MAX_STEPS_PER_UPDATE
      end
      local allStarted=true;local anyUpdate=false
      for _,state in ipairs(inst.entries) do
        if not state.started then allStarted=false end
        if state.hasUpdate and not state.finished then anyUpdate=true end
      end
      if allStarted and not anyUpdate and inst.frame>=inst.sourceEndFrame then
        finishInstance(ctx or inst.ctx,inst,"source-timeline-complete",false)
      elseif inst.frame>math.max(inst.sourceEndFrame+240,1200) then
        finishInstance(ctx or inst.ctx,inst,"timing-safety-cap",true)
      end
      if inst.done then table.remove(self.active,i) end
    end
  end
  return #self.active>0
end

function W:finish(ctx,reason)
  for _,inst in ipairs(self.active) do finishInstance(ctx,inst,reason or "battle-finish",true) end
  self.active={}
  return true
end

function W:status()
  local active={}
  for _,inst in ipairs(self.active) do
    active[#active+1]={serial=inst.serial,side=inst.side,target=inst.target,role=inst.role,frame=inst.frame,
      entries=#inst.entries,sourceEndFrame=inst.sourceEndFrame,moveId=inst.moveId,presentationSerial=inst.presentationSerial,parentAttackSerial=inst.parentAttackSerial,
      timingShift=inst.timing and inst.timing.shift or 0,unresolvedTiming=inst.timing and inst.timing.unresolved or 0}
  end
  return {version=self.version,source=self.source,active=active,handlerKinds=(function()
    local out={};for k,v in pairs(self.handlers) do out[k]=#v end;return out end)(),trace=self.trace,errors=self.errors,
    timingModel="retail anchorEntry + timingPoint dependency graph; negative-start normalization"}
end

W._test={phaseEntries=phaseEntries,resolveEntryStarts=resolveEntryStarts,entryPoint=entryPoint,globalPoint=globalPoint}
return W
