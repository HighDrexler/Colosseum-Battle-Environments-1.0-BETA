-- CBE experimental doubles controller. No renderer, global RNG or native turn loop.
-- One encounter, four positions, one ordered action queue; the adapter executes
-- individual move effects, never a second singles battle.
local Core={VERSION=1}; Core.__index=Core
local positions={"player-left","player-right","enemy-left","enemy-right"}
local function copy(t) local n={} for k,v in pairs(t or {}) do n[k]=v end return n end
local function healthy(m) return m and not m.isEgg and not m.egg and (tonumber(m.hp) or 0)>0 end
local function count(t) local n=0 for _ in pairs(t or {}) do n=n+1 end return n end
local function other(side) return side=="player" and "enemy" or "player" end
-- Textbox flow markers must never reach the independent doubles dialogue HUD.
-- Preserve ordinary prose (including the word "prompt") and localized glyphs.
local function clean(s)
  return (tostring(s or ""):gsub("{[Pp][Rr][Oo][Mm][Pp][Tt]}",""):gsub("{[Dd][Oo][Nn][Ee]}","")
    :gsub("[\1-\31]"," "):gsub(" +"," "))
end
Core.positions=positions
Core.healthy=healthy
function Core.new(opts)
  assert(type(opts)=="table" and opts.adapter,"doubles adapter required")
  local self=setmetatable({adapter=opts.adapter,id=assert(opts.id),revision=0,ticket=0,turn=1,
    phase="intro",slots={},byMon={},byBattler={},commands={},queue={},qhead=1,
    log={},defeated={},seenFaints={},spawn=0,rng=opts.rng or math.random,
    playerParty=opts.playerParty or {},enemyParty=opts.enemyParty or {},
    display={},clock=0,actionQueue={},actionIndex=1,finishPending=false,
    pendingReplacements={},participants={},nativeRules=opts.generation==2 and "gen2" or "gen1",
    generation=opts.generation or 1},Core)
  self.adapter.core=self
  for i,id in ipairs(positions) do
    self.slots[id]={id=id,side=i<=2 and "player" or "enemy",position=(i-1)%2+1}
  end
  if opts.openingText then self:message(opts.openingText) end
  for _,side in ipairs(opts.groupedOpening and {"enemy","player"} or {"player","enemy"}) do
    local party=side=="player" and self.playerParty or self.enemyParty
    local lead=side=="player" and opts.playerIndex or opts.enemyIndex
    local choices={}
    if lead and healthy(party[lead]) then choices[1]=lead end
    for i,mon in ipairs(party) do
      if healthy(mon) and i~=lead then choices[#choices+1]=i end
    end
    for index=1,2 do
      if choices[index] then self:occupy(side..(index==1 and "-left" or "-right"),choices[index],true) end
    end
  end
  if self.adapter.onOpeningAbilities then
    local before=self:captureVitals();self.adapter:onOpeningAbilities();self:recordVitals(before);self:noteFaints()
  end
  self:markParticipants()
  self:message("Double battle! Choose an action for each active Pokemon.")
  self.afterEvents=self.afterEvents or "command"
  return self
end
function Core:bump() self.revision=self.revision+1 end
-- Detached presentation records prevent a queued recall/faint from describing
-- the incoming occupant after the logic-side slot has already changed.
local function portraitMon(m,adapter)
  if not m then return nil end
  local out={species=m.species,dex=m.dex,level=m.level,nickname=m.nickname,
    name=m.name,gender=m.gender,shiny=m.shiny,isShiny=m.isShiny,
    abilityId=m.abilityId,abilityName=m.abilityName,otId=m.otId}
  if adapter and adapter.abilityInfo then out.abilityId,out.abilityName=adapter:abilityInfo(m) end
  if type(m.dvs)=="table" then
    out.dvs={};for k,v in pairs(m.dvs) do if type(v)=="number" then out.dvs[k]=v end end
  end
  return out
end
function Core:describe(id,token,m)
  local s=self.slots[id]
  if not (s and m) then return nil end
  local d=token and self.display[token]
  local portrait=portraitMon(m,self.adapter)
  return {id=id,side=s.side,position=s.position,battlerId=token,
    name=self.adapter:name(m),species=m.species,level=m.level,
    hp=d and d.hp or m.hp or 0,maxHP=self.adapter:maxHP(m),
    status=d and d.status or m.status,gender=m.gender,portrait=portrait,
    abilityId=portrait and portrait.abilityId,abilityName=portrait and portrait.abilityName}
end
function Core:enqueue(e)
  e.battleId=self.id; e.turn=self.turn
  self.eventSerial=(self.eventSerial or 0)+1;e.eventId=self.eventSerial
  local slot=e.slot and self.slots[e.slot]
  local m=e.mon or (slot and slot.battlerId==e.battlerId and slot.mon)
  e.subject=self:describe(e.slot,e.battlerId,m)
  self.queue[#self.queue+1]=e
  self:bump()
end
function Core:message(text) if text and text~="" then self:enqueue({kind="message",text=clean(text)}) end end
function Core:party(side) return side=="player" and self.playerParty or self.enemyParty end
function Core:slotFor(value) return self.byMon[value] or self.byBattler[value] end
function Core:aliveSlots(side)
  local out={} for _,id in ipairs(positions) do local s=self.slots[id]
    if (not side or s.side==side) and healthy(s.mon) then out[#out+1]=s end
  end return out
end
function Core:bench(side)
  local active={}
  for _,s in pairs(self.slots) do if s.side==side and s.mon then active[s.partyIndex]=true end end
  local reserved={}
  for _,a in pairs(self.commands) do if a.kind=="switch" then reserved[a.partyIndex]=true end end
  local out={}
  for i,m in ipairs(self:party(side)) do
    if healthy(m) and not active[i] and (side~="player" or not reserved[i]) then out[#out+1]=i end
  end
  return out
end
function Core:occupy(id,index,opening)
  local s=assert(self.slots[id]); local mon=self:party(s.side)[index]
  assert(healthy(mon),"cannot send a fainted Pokemon or egg")
  for _,peer in pairs(self.slots) do
    assert(peer==s or peer.mon~=mon,"Pokemon is already active")
  end
  local old=s.mon
  if old then
    self.byMon[old]=nil; self.byBattler[s.battler]=nil
    self.adapter:withdraw(s)
    self:enqueue({kind="recall",slot=id,battlerId=s.battlerId,mon=old,battler=s.battler})
  end
  self.spawn=self.spawn+1
  s.mon=mon; s.partyIndex=index; s.battlerId=s.side..":"..index..":"..self.spawn
  s.battler=self.adapter:makeBattler(s,opening)
  s.stages=s.battler.stages or self.adapter:newStages()
  s.faintNoted=false;s.seedSource=nil;s.boundBy=nil;s.trappedBy=nil;s.lockOnSource=nil
  self.byMon[mon]=s; self.byBattler[s.battler]=s
  self.display[s.battlerId]={hp=mon.hp,status=mon.status}
  if s.side=="enemy" then self.participants[mon]={} end
  self:markParticipants()
  self:enqueue({kind="send",slot=id,battlerId=s.battlerId,mon=mon,battler=s.battler,
    opening=opening==true,
    text=(s.side=="player" and "Go! " or "Opponent sent out ")..self.adapter:name(mon).."!"})
  if self.adapter.onReveal then self.adapter:onReveal(s,old,opening) end
  if not opening and self.adapter.onEnter then
    local before=self:captureVitals();self.adapter:onEnter(s);self:recordVitals(before);self:noteFaints()

  end
  self:bump()
end
function Core:markParticipants()
  for _,e in ipairs(self:aliveSlots("enemy")) do
    local p=self.participants[e.mon] or {}; self.participants[e.mon]=p
    for _,s in ipairs(self:aliveSlots("player")) do p[s.partyIndex]=true end
  end
end
function Core:checkOutcome()
  local function any(p) for _,m in ipairs(p) do if healthy(m) then return true end end return false end
  -- A simultaneous full wipe follows the host's blackout contract, not a win
  -- that would leave the save with no usable party.
  if not any(self.playerParty) then return "lose" end
  if not any(self.enemyParty) then return "win" end
end
function Core:noteFaints(source)
  local found=false
  for _,id in ipairs(positions) do local s=self.slots[id]
    if s.mon and not healthy(s.mon) and not s.faintNoted then
      s.faintNoted=true; found=true
      self.pendingReplacements[s.id]=s.battlerId
      self:enqueue({kind="faint",slot=id,battlerId=s.battlerId,mon=s.mon,battler=s.battler,
        text=self.adapter:name(s.mon).." fainted!"})
      if s.side=="enemy" and not self.seenFaints[s.mon] then
        self.seenFaints[s.mon]=true
        local p=copy(self.participants[s.mon])
        for i in pairs(p) do if not healthy(self.playerParty[i]) then p[i]=nil end end
        local eligible={}
        for i,m in ipairs(self.playerParty) do
          eligible[i]={mon=m,alive=healthy(m)==true,item=m.item,hp=m.hp}
        end
        self.defeated[#self.defeated+1]={mon=s.mon,battler=s.battler,participants=p,
          partyIndex=s.partyIndex,battlerId=s.battlerId,eligibleParty=eligible,
          turn=self.turn,rewardState="pending"}

      end
      if self.adapter.onFaint then self.adapter:onFaint(s,source) end
    end
  end
  self.outcome=self:checkOutcome()
  -- A faint retires its visual actor, NOT the turn's vacant position. Forced
  -- replacements occur only after committed actions AND residuals finish.
  if self.outcome then self.afterEvents="finished" end
  return found
end
function Core:targets(slot,move)
  local mode=self.adapter:targetMode(move)
  if mode=="self" or mode=="field" or mode=="side" then return {slot.id},mode end
  local out={}
  for _,id in ipairs(positions) do local s=self.slots[id]
    if healthy(s.mon) and s~=slot then
      local legal=mode=="all-other" or mode=="selected"
        or ((mode=="foes" or mode=="foe" or mode=="random") and s.side~=slot.side)
        or (mode=="ally" and s.side==slot.side)
      if legal then out[#out+1]=id end
    end
  end
  return out,mode
end
function Core:legalMoves(slot)
  local out={}; local forced=self.adapter:forced(slot)
  for i,m in ipairs(self.adapter:moves(slot)) do
    local def=self.adapter:moveDef(m.id or m.move)
    local supported,reason=self.adapter:supports(def)
    local can=def and supported and ((tonumber(m.pp) or 0)>0 or forced~=nil)
    if forced and forced.id and forced.id~=(m.id or m.move) then can=false end
    if self.adapter.disabled and self.adapter:disabled(slot,i,m) then can=false end
    out[#out+1]={index=i,id=m.id or m.move,name=def and def.name or m.id or "?",
      pp=m.pp or 0,maxPP=m.maxPP or (def and def.pp) or 0,enabled=can==true,
      reason=reason or (not can and "Unavailable" or nil),type=def and def.type}
  end
  local any=false for _,m in ipairs(out) do if m.enabled then any=true end end
  if not any then out[#out+1]={index=0,id="STRUGGLE",name="STRUGGLE",pp=0,maxPP=0,enabled=true} end
  return out
end
function Core:nextCommand()
  self.phase="command"; self.commandSlot=nil
  for _,s in ipairs(self:aliveSlots("player")) do
    if not self.commands[s.id] then self.commandSlot=s.id;break end
  end
  self.ticket=self.ticket+1; self:bump()
  if not self.commandSlot then self:commitTurn() end
end
function Core:validateRequest(req)
  if type(req)~="table" or req.battleId~=self.id then return false,"Wrong battle" end
  if req.ticket~=self.ticket then return false,"Selection has changed" end
  if req.turn~=self.turn then return false,"Turn has changed" end
  return true
end
function Core:submit(req)
  local ok,why=self:validateRequest(req); if not ok then return false,why end
  if req.kind=="cancel" and self.phase=="command" then
    local last
    for _,id in ipairs({"player-left","player-right"}) do if self.commands[id] then last=id end end
    if not last then return false,"Nothing to revise" end
    self.commands[last]=nil;self:nextCommand();return true
  end
  if self.phase=="replace" then
    if req.kind~="switch" then return false,"Choose a replacement" end
    local id=self.commandSlot
    local slot=id and self.slots[id]
    if not slot or req.slot~=id or req.battlerId~=slot.battlerId then return false,"Replacement position changed" end
    local valid=false for _,i in ipairs(self:bench("player")) do if i==req.partyIndex then valid=true end end
    if not valid then return false,"Pokemon is fainted, active, or reserved" end
    self:occupy(id,req.partyIndex,false)
    self.afterEvents=self.outcome and "finished" or "replace";self.phase="present";self.commandSlot=nil
    self.ticket=self.ticket+1;return true
  end
  if self.phase~="command" then return false,"Battle is not accepting commands" end
  local s=self.slots[self.commandSlot]
  if req.slot~=s.id or req.battlerId~=s.battlerId then return false,"Active Pokemon changed" end
  local a={kind=req.kind,slot=s.id,battlerId=s.battlerId}
  if req.kind=="switch" then
    if self.adapter:switchLocked(s) then return false,"This Pokemon cannot switch" end
    local valid=false for _,i in ipairs(self:bench(s.side)) do if i==req.partyIndex then valid=true end end
    if not valid then return false,"Pokemon is fainted, active, or reserved" end
    a.partyIndex=req.partyIndex
  elseif req.kind=="item" then
    if not self.adapter.validateItem then return false,"Items are unavailable" end
    local ok,why,mon=self.adapter:validateItem(req)
    if not ok then return false,why end
    a.item=req.item;a.partyIndex=req.partyIndex;a.moveIndex=req.moveIndex;a.targetMon=mon
  elseif req.kind=="move" then
    local selected
    for _,m in ipairs(self:legalMoves(s)) do
      if m.index==req.moveIndex and m.enabled then selected=m;break end
    end
    if not selected then return false,"Move is unavailable" end
    a.moveIndex=selected.index;a.moveId=selected.id
    local def=self.adapter:moveDef(a.moveId)
    local targets,mode=self:targets(s,def)
    a.targetMode=mode
    if mode=="selected" or mode=="foe" or mode=="ally" then
      local valid=false for _,id in ipairs(targets) do if id==req.target then valid=true end end
      if not valid then return false,"Choose a legal target" end
      a.target=req.target
    elseif mode=="random" then
      local foes={} for _,id in ipairs(targets) do if self.slots[id].side~=s.side then foes[#foes+1]=id end end
      a.target=foes[#foes>0 and self.rng(1,#foes) or 1]
    else a.target=targets[1] end
  else return false,"Choose Fight, Pokemon or an item" end
  self.commands[s.id]=a
  self:nextCommand()
  return true
end
function Core:aiCommand(s)
  local options={}
  for _,m in ipairs(self:legalMoves(s)) do if m.enabled then options[#options+1]=m end end
  local choice=options[self.rng(1,#options)]
  local def=self.adapter:moveDef(choice.id);local targets,mode=self:targets(s,def)
  local foes={}
  for _,id in ipairs(targets) do if self.slots[id].side~=s.side then foes[#foes+1]=id end end
  local target=(#foes>0 and foes[self.rng(1,#foes)]) or targets[1]
  return {kind="move",slot=s.id,battlerId=s.battlerId,moveIndex=choice.index,
    moveId=choice.id,target=target,targetMode=mode}
end
function Core:commitTurn()
  local actions={}
  for _,id in ipairs(positions) do local s=self.slots[id]
    if healthy(s.mon) then
      local a=s.side=="player" and self.commands[id] or self:aiCommand(s)
      if a then
        a.priority=a.kind=="item" and 7 or a.kind=="switch" and 6 or self.adapter:priority(a.moveId)
        a.speed=self.adapter:speed(s)
        a.quickClaw=a.kind=="move" and self.adapter.quickClaw and self.adapter:quickClaw(s) or false
        actions[#actions+1]=a
      end
    end
  end
  -- Shuffle ONCE. Never roll RNG inside table.sort's comparator.
  for i=#actions,2,-1 do local j=self.rng(1,i);actions[i],actions[j]=actions[j],actions[i] end
  for i,a in ipairs(actions) do a.tie=i end
  table.sort(actions,function(a,b)
    if a.priority~=b.priority then return a.priority>b.priority end
    if a.quickClaw~=b.quickClaw then return a.quickClaw end
    if a.speed~=b.speed then return a.speed>b.speed end
    return a.tie<b.tie
  end)
  self.commands={}; self.actionQueue=actions;self.actionIndex=1;self.turnEnded=false
  self.phase="resolving";self.commandSlot=nil;self.ticket=self.ticket+1
  self.adapter:beginTurn();self:bump()
end
function Core:resolvedTargets(s,a,def)
  local choices,mode=self:targets(s,def)
  if mode=="foes" or mode=="all-other" then
    local t={} for _,id in ipairs(choices) do t[#t+1]=self.slots[id] end return t
  end
  if mode=="self" or mode=="field" or mode=="side" then return {s} end
  local selected=self.slots[a.target]
  if selected and healthy(selected.mon) and selected~=s then return {selected} end
  -- A disappeared opposing position retargets a remaining foe. An ally target
  -- never silently turns into an attack on an enemy (or on the user).
  if selected and selected.side==s.side then return {} end
  local foes=self:aliveSlots(other(s.side));return foes[1] and {foes[1]} or {}
end
function Core:performNext()
  local a=self.actionQueue[self.actionIndex]
  if not a then
    self.phase="present"
    if not self.turnEnded then
      self.turnEnded=true -- progression/entry-KO continuations cannot tick twice
      local before=self:captureVitals()
      self.adapter:endTurn()
      self:recordVitals(before)
      self:noteFaints()
    end
    self.afterEvents=self.outcome and "finished" or (next(self.pendingReplacements) and "replace" or "next-turn")
    self.resumeAfterReplace="next-turn"
    return
  end
  self.actionIndex=self.actionIndex+1
  local s=self.slots[a.slot]
  if not s or not healthy(s.mon) or s.battlerId~=a.battlerId then return end
  self.phase="present";self.afterEvents="resolving"
  if a.kind=="switch" then
    if healthy(self:party(s.side)[a.partyIndex]) then
      local valid=true for _,peer in pairs(self.slots) do if peer.mon==self:party(s.side)[a.partyIndex] then valid=false end end
      if valid and not self.adapter:switchLocked(s) then self:occupy(s.id,a.partyIndex,false)
      else self:message("The switch could not be completed.") end
    end
    return
  end
  if a.kind=="item" then
    local before=self:captureVitals()
    self.adapter:performItem(a)
    self:recordVitals(before)
    self:noteFaints()
    return
  end
  -- Encore can be applied after command collection. Re-resolve only the
  -- locked move, retaining the submitted target unless its mode now differs.
  local forced=self.adapter:forced(s)
  if forced and forced.id and forced.id~=a.moveId then
    for i,move in ipairs(self.adapter:moves(s))do if move.id==forced.id then
      local revised={} for k,v in pairs(a)do revised[k]=v end
      revised.moveId=forced.id;revised.moveIndex=i;a=revised;break
    end end
  end
  local def=self.adapter:moveDef(a.moveId)
  local targets=self:resolvedTargets(s,a,def)
  -- A level-up/forget dialog may have changed this move SLOT. Never turn a
  -- frozen command into the newly learned move or charge its PP by accident.
  local selected=self.adapter:moves(s)[a.moveIndex]
  if a.moveIndex~=0 and (not selected or selected.id~=a.moveId) then
    self:message(self.adapter:name(s.mon).." can no longer use the selected move.");return
  end
  local before=self:captureVitals()
  local ids={} for _,t in ipairs(targets) do ids[#ids+1]=t.id end
  local source
  if #targets==0 then
    if self.adapter.performNoTarget then source=self.adapter:performNoTarget(s,a)
    else self:message("There is no target for "..self.adapter:name(s.mon)..".") end
  else source=self.adapter:perform(s,targets,a) end
  self:recordVitals(before,source)
  self:noteFaints(source)
end
function Core:captureVitals()
  local out={} for _,id in ipairs(positions) do local s=self.slots[id]
    if s.mon then out[id]={id=s.battlerId,hp=s.mon.hp,status=s.mon.status,stages=copy(s.stages),
      structuralHidden=self.adapter.structuralHidden and self.adapter:structuralHidden(s) or false} end
  end return out
end
function Core:recordVitals(before,source)
  for _,id in ipairs(positions) do local s=self.slots[id];local old=before[id]
    if s.mon and old and old.id==s.battlerId then
      local hidden=self.adapter.structuralHidden and self.adapter:structuralHidden(s) or false
      if source and source.battlerId==s.battlerId then
        source.structuralHiddenBefore=old.structuralHidden==true
        source.structuralHiddenAfter=hidden==true
      end
      if hidden~=(old.structuralHidden==true) then
        -- Runs after the move's complete departure/release, or after an
        -- interruption with no move event. Exact tokens isolate replacements.
        self:enqueue({kind="visibility",slot=id,battlerId=s.battlerId,
          hidden=hidden==true,duration=0,automatic=true})
      end
      if old.hp~=s.mon.hp then
        -- Recoil, confusion, costs and self-destruction are NOT the move's
        -- receiving Waza chapter. Only a proven opposing/ally target gets it.
        local impact=source and source.slot~=id and source.targetBattlers
          and source.targetBattlers[id]==s.battlerId and source.stage~='charge' and source or nil
        if s.mon.hp<=0 and s.mon.hp<old.hp then
          s.faintCause=impact and {slot=impact.slot,battlerId=impact.battlerId} or nil
        end
        local receiving={kind=s.mon.hp<old.hp and "damage" or "heal",slot=id,battlerId=s.battlerId,
          mon=s.mon,battler=s.battler,from=old.hp,hp=s.mon.hp,amount=math.abs(old.hp-s.mon.hp),sourceSlot=impact and impact.slot,sourceBattlerId=impact and impact.battlerId,
          move=impact and impact.move,moveDef=impact and impact.moveDef,stage=impact and impact.stage}
        self:enqueue(receiving)
        if impact and receiving.kind=="damage" then
          receiving.impactOf=impact.eventId
          impact.impacts=impact.impacts or {};impact.impacts[#impact.impacts+1]=receiving
        end
      end
      local statusChanged=old.status~=s.mon.status
      if statusChanged then self:enqueue({kind="status",slot=id,battlerId=s.battlerId,status=s.mon.status or false}) end
      local stagesChanged=false
      for key,value in pairs(s.stages or {}) do
        if (tonumber(value) or 0)~=(tonumber((old.stages or {})[key]) or 0) then stagesChanged=true;break end
      end
      local impact=source and source.slot~=id and source.stage~='charge' and source.targetBattlers
        and source.targetBattlers[id]==s.battlerId and source
      if impact and old.hp==s.mon.hp and (statusChanged or stagesChanged) then
        -- Status/stat moves have a target-side Waza chapter even when HP is
        -- unchanged. A dedicated event prevents healing, misses or recoil
        -- from being mislabeled as damage or replaying the attack chapter.
        local receiving={kind="reaction",slot=id,battlerId=s.battlerId,mon=s.mon,battler=s.battler,
          hp=s.mon.hp,amount=0,sourceSlot=impact.slot,sourceBattlerId=impact.battlerId,
          move=impact.move,moveDef=impact.moveDef,stage=impact.stage,statusReaction=true,impactOf=impact.eventId}
        self:enqueue(receiving)
        impact.impacts=impact.impacts or {};impact.impacts[#impact.impacts+1]=receiving
      end
    end
  end
end
function Core:replaceFainted()
  self.resumeAfterReplace=self.resumeAfterReplace or "resolving"
  for _,id in ipairs(positions) do local s=self.slots[id]
    if s.mon and not healthy(s.mon) then
      -- Empty the position only after its faint presentation has completed.
      self.byMon[s.mon]=nil;self.byBattler[s.battler]=nil
      self.adapter:withdraw(s)
      self.pendingReplacements[id]=nil
      s.mon=nil;s.battler=nil;s.battlerId=nil;s.partyIndex=nil;s.faintCause=nil
    end
  end
  for _,id in ipairs({"enemy-left","enemy-right"}) do local s=self.slots[id]
    local bench=self:bench("enemy")
    if not s.mon and bench[1] then
      self:occupy(id,bench[1],false);self.phase="present"
      self.afterEvents=self.outcome and "finished" or "replace";return
    end
  end
  for _,id in ipairs({"player-left","player-right"}) do local s=self.slots[id]
    if not s.mon and self:bench("player")[1] then
      self.phase="replace";self.commandSlot=id;self.ticket=self.ticket+1;self:bump();return
    end
  end
  local nextPhase=self.resumeAfterReplace;self.resumeAfterReplace=nil
  if nextPhase=="next-turn" then self:newTurn() else self.phase="resolving" end
end
function Core:newTurn()
  self.turn=self.turn+1;self.commands={};self.actionQueue={};self.actionIndex=1;self.turnEnded=false
  self:markParticipants();self:nextCommand()
end
-- This advances only the detached HUD view. Native HP was resolved atomically
-- by the action already. Exact event identity prevents recoil, a later hit or
-- a new occupant from being mistaken for an already-presented receiving cue.
function Core:presentImpact(e,duration)
  if not e or e.presentationConsumed or not e.impactOf then return false end
  local current=self.currentEvent
  if not current or current.eventId~=e.impactOf then return false end
  local slot=self.slots[e.slot]
  if not slot or slot.battlerId~=e.battlerId then return false end
  local d=self.display[e.battlerId] or {};self.display[e.battlerId]=d
  e.previousHP=d.hp or e.from or e.hp
  if e.kind=="damage" then d.hp=e.hp end
  e.presentationConsumed=true;e.impactElapsed=0;e.impactDuration=duration or .38
  e.automatic=true;e.duration=0
  self:bump();return true
end
function Core:presentNext()
  local e=self.queue[self.qhead]
  if e then
    self.queue[self.qhead]=false;self.qhead=self.qhead+1
    self.currentEvent=e;self.eventTime=0;self.messageText=e.text or ""
    if e.subject then
      local d=self.display[e.battlerId]
      e.previousHP=d and d.hp or e.subject.hp
      e.subject.hp=e.hp or (d and d.hp) or e.subject.hp
      if e.kind=="status" then e.subject.status=e.status end
    end
    if e.kind=="damage" or e.kind=="heal" then
      local d=self.display[e.battlerId] or {};self.display[e.battlerId]=d;d.hp=e.hp
    elseif e.kind=="status" then
      local d=self.display[e.battlerId] or {};self.display[e.battlerId]=d;d.status=e.status
    end
    self.log[#self.log+1]={turn=e.turn,kind=e.kind,slot=e.slot,move=e.move,text=e.text,hp=e.hp}
    if #self.log>80 then table.remove(self.log,1) end
    if self.onEvent then self.onEvent(e) end
    self:bump();return true
  end
  self.queue={};self.qhead=1;self.currentEvent=nil;self.messageText=""
  local phase=self.afterEvents;self.afterEvents=nil
  -- Progression owns the native UI until its callback returns. No action,
  -- residual or forced send-out may advance across this boundary.
  if self.onProgression and self.onProgression(phase) then return false end
  self:continueAfterEvents(phase)
  return false
end
function Core:continueAfterEvents(phase)
  if phase=="command" then self:nextCommand()
  elseif phase=="replace" then self:replaceFainted()
  elseif phase=="next-turn" then self:newTurn()
  elseif phase=="finished" then
    self.phase="finished";self.messageText=self.outcome=="win" and "Double battle won!" or "Your party was defeated."
    self.ticket=self.ticket+1;self:bump()
  else self.phase=phase or "resolving" end
  return false
end
local durations={move=.95,send=.75,recall=.45,faint=.9,damage=.38,heal=.38,status=.25,message=.75}
function Core:update(dt,advance)
  self.clock=self.clock+math.max(0,math.min(tonumber(dt) or 0,.1))
  if self.phase=="intro" then self.phase="present" end
  if self.phase=="present" then
    if self.currentEvent then
      self.eventTime=(self.eventTime or 0)+math.max(0,math.min(tonumber(dt) or 0,.1))
      local event=self.currentEvent
      if event.presentationPending or self.eventTime<(event.minimumDuration or 0) then return end
      local readTime=self.autoProgress~=false and event.text and math.min(3,math.max(.8,#event.text/45)) or 0
      if self.eventTime<math.max(event.duration or durations[event.kind] or .6,readTime)
          and not (advance and self.eventTime>.12) then return end
      if self.autoProgress==false and not advance and not event.automatic then return end
      self.currentEvent=nil
    end
    self:presentNext()
  elseif self.phase=="resolving" then self:performNext() end
end
function Core:snapshot(options)
  -- Default version-1 snapshots remain complete and detached. The paired UI
  -- can explicitly request only the collections it will render; native item
  -- previews/legal-target construction must not run on every animation frame.
  local render=type(options)=="table" and options.view=="render"
  local page=render and options.page or nil
  local selecting=self.phase=="command" or self.phase=="replace"
  local partyNeeded=not render or self.phase=="replace" or (selecting and (page=="party" or page=="item-party" or page=="item-moves"))
  local itemsNeeded=not render or (selecting and (page=="bag" or page=="item-party" or page=="item-moves"))
  local movesNeeded=not render or (selecting and (page=="moves" or page=="targets"))
  local snap={version=1,battleId=self.id,revision=self.revision,ticket=self.ticket,
    format="double",turn=self.turn,phase=self.phase,commandSlot=self.commandSlot,
    message=self.messageText or "",outcome=self.outcome,slots={},party={},nativeRules=self.nativeRules,
    items=itemsNeeded and self.adapter.itemList and self.adapter:itemList() or {},itemApiVersion=1,abilityApiVersion=1,
    limitations={bag=self.adapter.itemList~=nil,sourceMoveFX=self.sourceMoveFX==true,inBattleCheckpoint=false},commandsCommitted=count(self.commands)}
  for _,id in ipairs(positions) do local s=self.slots[id];local m=s.mon
    local d=s.battlerId and self.display[s.battlerId]
    snap.slots[#snap.slots+1]={id=id,side=s.side,position=s.position,battlerId=s.battlerId,
      partyIndex=s.partyIndex,name=m and self.adapter:name(m) or "EMPTY",species=m and m.species,
      level=m and m.level,hp=m and ((d and d.hp) or m.hp) or 0,
      maxHP=m and self.adapter:maxHP(m) or 1,status=m and ((d and d.status) or m.status),
      portrait=portraitMon(m,self.adapter),gender=m and m.gender,empty=m==nil,active=m and healthy(m) or false,
      committed=self.commands[id]~=nil}
  end
  local event=self.currentEvent
  if event then
    local subject=event.subject and copy(event.subject)
    if subject and subject.portrait then
      subject.portrait=copy(subject.portrait)
      if subject.portrait.dvs then subject.portrait.dvs=copy(subject.portrait.dvs) end
    end
    snap.presentation={kind=event.kind,slot=event.slot,battlerId=event.battlerId,
      subject=subject,text=event.text or "",move=event.move,
      elapsed=self.eventTime or 0,duration=event.duration or durations[event.kind] or .6,
      previousHP=event.previousHP,targets=event.targets and copy(event.targets) or nil,
      presentationConsumed=event.presentationConsumed or nil,impacts={}}
    for _,e in ipairs(event.impacts or {}) do
      if e.presentationConsumed then
        snap.presentation.impacts[#snap.presentation.impacts+1]={kind=e.kind,slot=e.slot,battlerId=e.battlerId,
          previousHP=e.previousHP,hp=e.hp,elapsed=e.impactElapsed or 0,duration=e.impactDuration or .38}
      end
    end
  end
  for i,m in ipairs(partyNeeded and self.playerParty or {}) do
    local active=self.byMon[m];local reserved=false
    for _,a in pairs(self.commands) do if a.kind=="switch" and a.partyIndex==i then reserved=true end end
    snap.party[#snap.party+1]={index=i,name=self.adapter:name(m),hp=m.hp or 0,maxHP=self.adapter:maxHP(m),
      level=m.level,active=active and active.id or nil,enabled=healthy(m) and not active and not reserved,
      reserved=reserved,egg=m.isEgg or m.egg,moves=(function()
          local rows={};for i,mv in ipairs(m.moves or {})do local def=self.adapter:moveDef(mv.id)
           rows[#rows+1]={index=i,id=mv.id,name=def and def.name or mv.id,pp=mv.pp,maxPP=mv.maxPp or mv.maxPP or (def and def.pp)}
          end;return rows
        end)()}
  end
  local s=self.commandSlot and self.slots[self.commandSlot]
  if s and s.mon then
    snap.battlerId=s.battlerId;snap.moves=movesNeeded and self:legalMoves(s) or {};snap.targets={}
    for _,m in ipairs(snap.moves) do if m.enabled then
      local ids,mode=self:targets(s,self.adapter:moveDef(m.id));snap.targets[m.index]={ids=ids,mode=mode}
    end end
    snap.switchLocked=not not self.adapter:switchLocked(s)
  end
  return snap
end
return Core
