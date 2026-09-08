-- Native Gen I/II effect kernels for the experimental four-position scheduler.
-- Native *individual moves* are reused. Neither native takeTurn/resolveTurn nor
-- its two-battler faint/replacement pipeline is called during doubles.
local V=... or {}
local req=V.engineRequire or require
local AbilityEffectsGen1=V.AbilityEffectsGen1
local AbilityEffectsGen2=V.AbilityEffectsGen2
local A={};A.__index=A
local function copy(t) local o={} for k,v in pairs(t or {}) do o[k]=v end return o end
local function set(words) local o={} for w in words:gmatch('%S+') do o[w]=true end return o end
local selfMoves=set([[SWORDS_DANCE GROWTH MEDITATE AGILITY DOUBLE_TEAM HARDEN MINIMIZE WITHDRAW DEFENSE_CURL BARRIER AMNESIA FOCUS_ENERGY RECOVER SOFTBOILED REST SUBSTITUTE SPLASH SHARPEN ACID_ARMOR CONVERSION CONVERSION2 BELLY_DRUM MILK_DRINK SYNTHESIS MOONLIGHT MORNING_SUN PROTECT DETECT ENDURE]])
local sideMoves=set([[REFLECT LIGHT_SCREEN MIST SAFEGUARD HEAL_BELL]])
local fieldMoves=set([[HAZE PERISH_SONG RAIN_DANCE SUNNY_DAY SANDSTORM]])
local foesMoves=set([[SURF SWIFT RAZOR_LEAF BLIZZARD POWDER_SNOW ICY_WIND ROCK_SLIDE ACID TWISTER GROWL LEER TAIL_WHIP STRING_SHOT SWEET_SCENT]])
local allMoves=set([[EARTHQUAKE MAGNITUDE SELFDESTRUCT SELF_DESTRUCT EXPLOSION]])
-- Explicitly unavailable in this test, not silently converted into ordinary hits.
-- These require cross-action identities or native UI/party mutation which the
-- singles effect implementation cannot safely express through a target pair.
local unsupported=set([[BIDE COUNTER MIRROR_COAT MIRROR_MOVE METRONOME MIMIC SLEEP_TALK FUTURE_SIGHT BATON_PASS ROAR WHIRLWIND TELEPORT TRANSFORM ATTRACT PURSUIT BEAT_UP DESTINY_BOND NIGHTMARE SKETCH]])
local gen1Unsupported=set([[BIND WRAP FIRE_SPIN CLAMP]])
local unsafeEffects=set([[EFFECT_BIDE EFFECT_COUNTER EFFECT_MIRROR_COAT EFFECT_MIRROR_MOVE EFFECT_METRONOME EFFECT_MIMIC EFFECT_SLEEP_TALK EFFECT_FUTURE_SIGHT EFFECT_BATON_PASS EFFECT_FORCE_SWITCH EFFECT_TELEPORT EFFECT_TRANSFORM EFFECT_ATTRACT EFFECT_PURSUIT EFFECT_BEAT_UP EFFECT_DESTINY_BOND EFFECT_NIGHTMARE EFFECT_SKETCH]])
A.UNSUPPORTED=unsupported
function A.new(host,generation)
  local self=setmetatable({host=host,generation=generation,data=assert(host.data),
    messages={},screens={player={},enemy={}},spikes={player=false,enemy=false}},A)
  self.native=generation==2 and req('src.battle.gen2.Battle') or req('src.battle.BattleState')
  self.k=setmetatable(copy(host),{__index=self.native})
  local k=self.k
  k.__cbeAbilityActives=function()
    local out={}
    for _,slot in ipairs(self.core and self.core:aliveSlots() or {}) do out[#out+1]=generation==2 and slot.mon or slot.battler end
    return out
  end
  k.__cbeDoublesKernel=true;k.events={};k.queue={};k.result=nil;k.over=false;k.outcome=nil
  k.lastDamage=0;k.copyDepth=0;k.turn=0;k.turnCount=0;k.firstMover=nil
  k.moveDef=function(_,value) return self:moveDef(type(value)=='table' and value.id or value) end
  if generation==2 then
    self.screens={player=copy(host.screens and host.screens.player),enemy=copy(host.screens and host.screens.enemy)}
    self.spikes={player=host.spikes and host.spikes.player or false,enemy=host.spikes and host.spikes.enemy or false}
    k.stages={};k.screens=self.screens
    -- The supplied Gen II kernel names PSYCH_UP but does not implement it.
    -- Add a record to THIS kernel only, preserving an installed handler and
    -- leaving native singles/mod registries untouched. Gen II source semantics:
    -- pret/pokecrystal engine/battle/move_effects/psych_up.asm and the PsychUp
    -- list in data/moves/effects.asm (no checkhit; fail for all-neutral stages).
    local psych=self.native.moveEffectRecordFor(self.data,'EFFECT_PSYCH_UP')
    if not (psych and type(psych.run)=='function') then
      k.data=copy(self.data);k.data.gen2MoveEffects=copy(self.data.gen2MoveEffects)
      k.data.gen2MoveEffects.EFFECT_PSYCH_UP={kind='primary',run=function(kernel,user,target)
        local source=self.core:slotFor(target);local destination=self.core:slotFor(user)
        local keys={'attack','defense','speed','specialAttack','specialDefense','accuracy','evasion'}
        local changed=false
        for _,key in ipairs(keys) do if source and (source.stages[key] or 0)~=0 then changed=true;break end end
        if not changed or not destination then
          kernel:markMissed();self:message('But it failed!');return
        end
        -- Preserve the slot's table identity: native damage/turn-order
        -- calculations read these seven stages on demand, and no partner/target table is aliased.
        for _,key in ipairs(keys) do destination.stages[key]=source.stages[key] or 0 end
        self:message(self:name(user)..' copied '..self:name(target).."'s stat changes!")
      end}
    end
    -- Stage tables are battler-specific; screens/hazards are side-specific.
    k.sideOf=function(_,mon) local s=self.core and self.core:slotFor(mon);return s and s.id or 'enemy' end
    k.sideRecord=function(_,mon)
      local s=self.core and self.core:slotFor(mon)
      return (s and s.side=='player') and self.host.sides[1] or self.host.sides[2]
    end
    k.emit=function(_,event)
      if event.kind=='message' or event.kind=='weather' then self:message(event.text) end
      if event.kind=='move' then self:announce(event) end
      return event
    end
    k.battleStat=function(kernel,mon,key)
      local s=self.core:slotFor(mon);local old=kernel.player
      kernel.player=(s and s.side=='player') and mon or nil
      local n=self.native.battleStat(kernel,mon,key);kernel.player=old;return n
    end
    k.badgeTypeBoost=function(kernel,mon,kind)
      local s=self.core:slotFor(mon);local old=kernel.player
      kernel.player=(s and s.side=='player') and mon or nil
      local n=self.native.badgeTypeBoost(kernel,mon,kind);kernel.player=old;return n
    end
    -- The native flag belongs to a target. Bind ownership to a battler token
    -- so another opponent cannot consume a partner's accuracy guarantee.
    k.consumeLockOn=function(kernel,mon)
      -- Psych Up's source command list has no checkhit, so it cannot spend
      -- the selected target's Lock-On flag through the native common path.
      if self.action and self.action.moveId=='PSYCH_UP' then return false end
      local target=self.core and self.core:slotFor(mon)
      if target and target.lockOnSource and (not self.acting or target.lockOnSource~=self.acting.battlerId) then return false end
      local result=self.native.consumeLockOn(kernel,mon)
      if result and target then target.lockOnSource=nil end
      return result
    end
    k.selfdestructUser=function(_,mon) self.destruct=mon end
    k.dealDamage=function(kernel,attacker,target,damage,opts)
      if self.spread and opts and opts.move then damage=math.max(1,math.floor(damage*.5)) end
      return self.native.dealDamage(kernel,attacker,target,damage,opts)
    end
  else
    self.status=req('src.battle.Status');self.order=req('src.battle.TurnOrder')
    k.ruleset=copy(host.ruleset);k.ruleset.enemyUnlimitedPP=false;k.ruleset.residualAfterMove=false
    k.ruleset.hyperBeamSkipRechargeOnKO=false
    -- These routines enqueue only presentation or invoke a native effect's
    -- gameplay continuation. The four-battler controller owns presentation.
    for _,name in ipairs({'say','sayNext','sayAuto','sayNextAuto','sayNextWaitSfx','sayNextAutoWaitSfx'}) do
      k[name]=function(_,text) self:message(text) end
    end
    for _,name in ipairs({'animBeforeMove','waitBeforeMoveAnim','waitNext','waitSfxNext','drainNext','onFaint'}) do k[name]=function() end end
    -- Native secondary-status effects annotate the returned row (animDelayed,
    -- hit). Preserve animNext's record contract without enqueuing singles HUD
    -- animations; the doubles controller still owns the presentation queue.
    k.animNext=function(_,name,isPlayer,shakes,ball)
      return {anim=name,attackerIsPlayer=isPlayer,shakes=shakes,ball=ball}
    end
    k.act=function(_,fn) if fn then fn() end end;k.actNext=k.act
    k.uiNext=function() error('Doubles test: a move requested an unsupported native UI operation') end
    k.selfDestruct=function(_,battler) self.destruct=battler.mon end
    k.cancelMoveAnim=function(kernel) if kernel.moveAnimRow then kernel.moveAnimRow.cancelled=true end end
    k.computeDamage=function(kernel,user,target,move,opts)
      local n,info=self.native.computeDamage(kernel,user,target,move,opts)
      if self.spread and move.id~='CONFUSED' and n>0 then n=math.max(1,math.floor(n*.5)) end
      return n,info
    end
  end
  return self
end
function A:itemList()return V.DoublesItems and V.DoublesItems.snapshot(self) or {} end
function A:validateItem(request)return V.DoublesItems.validate(self,request)end
function A:performItem(action)return V.DoublesItems.perform(self,action)end
function A:message(text)
  if not text or text=='' then return end
  -- Native kernels announce each spread target. The controller announces the
  -- move once, with all affected positions in its event payload.
  if self.suppressAnnouncement and tostring(text):lower():find('used ',1,true) then return end
  self.core:message(text)
end
function A:announce(event)
  if self.announced then return end
  self.announced=true
  local s=self.acting;local ids={};local tokens={}
  for _,t in ipairs(self.targets or {}) do ids[#ids+1]=t.id;tokens[t.id]=t.battlerId end
  if s then self.presentationEvent={kind='move',slot=s.id,battlerId=s.battlerId,
    move=self.action.moveId,moveDef=self:moveDef(self.action.moveId),targets=ids,
    mon=s.mon,battler=s.battler,targetBattlers=tokens,sourceBattlerId=s.battlerId,
    stage='attack',targetResults={},text=self:name(s.mon)..' used '..(self:moveDef(self.action.moveId).name or self.action.moveId)..'!'}
    self.core:enqueue(self.presentationEvent)
  end
end
function A:newStages() return {attack=0,defense=0,speed=0,special=0,specialAttack=0,specialDefense=0,accuracy=0,evasion=0} end
function A:name(mon)
  local def=self.data.pokemon and self.data.pokemon[mon.species]
  return mon.nickname or mon.name or (def and def.name) or tostring(mon.species or '?')
end
function A:maxHP(mon) return math.max(1,mon.maxHp or mon.maxHP or (mon.stats and mon.stats.hp) or mon.hp or 1) end
function A:makeBattler(s,opening)
  if self.generation==2 then
    self.k:clearVolatile(s.mon)
    if s.side=='player' and self.host.checkAmuletCoin then self.host:checkAmuletCoin(s.mon) end
    return {mon=s.mon,name=self:name(s.mon),isPlayer=s.side=='player',stages=self:newStages()}
  end
  local lead=s.side=='player' and self.host.player or self.host.enemy
  if opening and lead and lead.mon==s.mon then return lead end
  local b=self.native.makeBattler(self.data,s.mon,s.side=='player',self.host.game and self.host.game.save)
  for _,key in ipairs({'reflect','lightScreen','mist'}) do if self.screens[s.side][key] then b[key]=true end end
  return b
end
function A:withdraw(s)
  if self.generation==2 then
    if AbilityEffectsGen2 then AbilityEffectsGen2.onLeave(self.k, s.mon) end
    self.k:clearVolatile(s.mon)
  elseif AbilityEffectsGen1 then
    AbilityEffectsGen1.onLeave(self.k, s)
  end
  -- Identity-bound relations end with a withdrawing source. Leech Seed is a
  -- position-bound drain, so it intentionally survives a source replacement.
  for _,peer in pairs(self.core.slots) do
    if peer.trappedBy==s.battlerId then peer.trappedBy=nil end
    if peer.lockOnSource==s.battlerId then
      peer.lockOnSource=nil
      if peer.mon and peer.mon.volatile then peer.mon.volatile.lockOn=nil end
    end
    if peer.boundBy==s.battlerId then
      peer.boundBy=nil
      local v=peer.mon and peer.mon.volatile
      if self.generation==2 and v then v.wrapCount=nil;v.wrapMove=nil;v.wrapMoveId=nil end
    end
  end
end
function A:moves(s) return (s.battler and s.battler.curMoves) or s.mon.moves or {} end
function A:moveDef(id)
  local d=self.data.moves and self.data.moves[id]
  if d then return d end
  if id=='STRUGGLE' then return {id=id,name=id,power=50,accuracy=100,type='NORMAL',pp=1,
    effect=self.generation==2 and 'EFFECT_RECOIL_HIT' or 'RECOIL_EFFECT'} end
end
function A:supports(def)
  if not def then return false,'Unknown move data' end
  if unsupported[def.id] or unsafeEffects[def.effect] or (self.generation==1 and gen1Unsupported[def.id]) then
    return false,'Requires a doubles-specific effect adapter'
  end
  if self.generation==1 then
    local r=self.k:effectRecord(def.effect)
    if r and (r.callsMove or r.perform) then return false,'Native special flow not yet adapted' end
  end
  return true
end
function A:targetMode(def)
  local id=def and def.id
  if selfMoves[id] then return 'self' end
  if sideMoves[id] then return 'side' end
  if fieldMoves[id] then return 'field' end
  if foesMoves[id] then return 'foes' end
  if allMoves[id] then return 'all-other' end
  if id=='THRASH' or id=='PETAL_DANCE' then return 'random' end
  if id=='SPIKES' then return 'foe' end
  return 'selected'
end
function A:forced(s)
  if self.generation==2 then local id=self.k:forcedMove(s.mon);return id and {id=id} end
  local b=s.battler
  if b.mustRecharge then return {special='recharge'} end
  return b.charging or b.thrashMove or b.rageMove
end
function A:disabled(s,index,move)
  if self.generation==2 then return self.k:moveDisabled(s.mon,move.id) end
  return s.battler.disabledSlot==index
end
function A:abilityTraps(s)
  if not (V.Abilities and (AbilityEffectsGen1 or AbilityEffectsGen2)) then return false end
  local Abilities=V.Abilities
  local abilityOf=self.generation==2 and AbilityEffectsGen2 and AbilityEffectsGen2.abilityOf
    or AbilityEffectsGen1 and AbilityEffectsGen1.abilityOf
  if not abilityOf then return false end
  local selfKey=self.generation==2 and s.mon or s
  local selfDef={types=Abilities.types(self.k,self.generation==2 and s.mon or s.battler)}
  local opponents=self.core:aliveSlots(s.side=='player' and 'enemy' or 'player')
  for _,opp in ipairs(opponents) do
    local oppKey=self.generation==2 and opp.mon or opp
    local trapAbility=abilityOf(self.k, oppKey)
    local meta=trapAbility and Abilities.meta(trapAbility)
    if meta and meta.category=="trap_block" then
      if trapAbility=="MAGNET_PULL" then
        local isSteel=false
        for _,t in ipairs((selfDef and selfDef.types) or {}) do if t=="STEEL" then isSteel=true end end
        if isSteel then return true end
      elseif trapAbility=="ARENA_TRAP" then
        local selfAbility=abilityOf(self.k, selfKey)
        local isFlying=false
        for _,t in ipairs((selfDef and selfDef.types) or {}) do if t=="FLYING" then isFlying=true end end
        if selfAbility~="LEVITATE" and not isFlying then return true end
      else -- SHADOW_TAG: traps everyone
        return true
      end
    end
  end
  return false
end
function A:switchLocked(s)
  if s.trappedBy then
    for _,peer in ipairs(self.core:aliveSlots()) do if peer.battlerId==s.trappedBy then return true end end
    s.trappedBy=nil
  end
  if self:abilityTraps(s) then return true end
  if self.generation==2 then
    local v=s.mon.volatile or {}
    return v.recharge or v.chargeMove or v.rampageMove or v.rolloutLock or v.wrapCount or v.cantRun or false
  end
  local b=s.battler
  return b.mustRecharge or b.charging or b.thrashMove or b.rageMove or b.boundTurns or false
end
function A:bind(s,t)
  local k=self.k
  if self.generation==2 then
    k.player=s.side=='player' and s.mon or t.mon;k.enemy=s.side=='enemy' and s.mon or t.mon
    for _,slot in pairs(self.core.slots) do if slot.mon then
      k.stages[slot.id]=slot.stages;k.screens[slot.id]=self.screens[slot.side]
    end end
    k.stages.player=self.core:slotFor(k.player).stages;k.stages.enemy=self.core:slotFor(k.enemy).stages
    k.spikes=setmetatable({}, {__index=function(_,id) local slot=self.core.slots[id];return self.spikes[slot and slot.side or id] end,
      __newindex=function(_,id,value) local slot=self.core.slots[id];self.spikes[slot and slot.side or id]=value end})
  else
    k.player=s.side=='player' and s.battler or t.battler;k.enemy=s.side=='enemy' and s.battler or t.battler
  end
  k.turn=self.core.turn;k.turnCount=self.core.turn
end
function A:onEnterAbilities(s)
  if not s.mon or (s.mon.hp or 0)<=0 then return end
  local opponents=self.core:aliveSlots(s.side=='player' and 'enemy' or 'player')
  self:bind(s,opponents[1] or s)
  if self.generation==2 then
    if AbilityEffectsGen2 then
      local oppMons={}
      for _,opp in ipairs(opponents) do oppMons[#oppMons+1]=opp.mon end
      AbilityEffectsGen2.onEnter(self.k, s.mon, oppMons)
    end
  elseif AbilityEffectsGen1 then
    local battlers={};for _,opp in ipairs(opponents) do battlers[#battlers+1]=opp.battler end
    AbilityEffectsGen1.onEnter(self.k,s.battler,battlers)
  end
end
function A:onOpeningAbilities()
  if not (V.Abilities and V.Abilities.enabledBattle(self.k)) then return end
  local all=self.core:aliveSlots()
  table.sort(all,function(a,b)local sa,sb=self:speed(a),self:speed(b);if sa~=sb then return sa>sb end;return a.id<b.id end)
  for _,slot in ipairs(all) do self:onEnterAbilities(slot) end
end
function A:abilityInfo(mon)
  if not V.Abilities then return mon.abilityId,mon.abilityName end
  local def=self.data.pokemon and self.data.pokemon[mon.species]
  local id=V.Abilities.current(self.k,mon,V.Abilities.dexOf(mon,def))
  return id,id and V.Abilities.displayName(id)
end
function A:onEnter(s)
  if self.generation==2 then
    self:bind(s,s)
    self.k:spikesDamage(s.mon)
  end
  self:onEnterAbilities(s)
end
function A:speed(s)
  if self.generation==2 then self:bind(s,s);return self.k:effectiveSpeed(s.mon) end
  local multiplier=AbilityEffectsGen1 and AbilityEffectsGen1.speedMultiplier(self.k,s.battler) or 1
  return self.order.effectiveSpeed(s.battler)*multiplier
end
function A:priority(id)
  local d=self:moveDef(id)
  if d and d.priority then return d.priority end
  if self.generation==2 then return self.k:movePriority(id) end
  return id=='QUICK_ATTACK' and 1 or 0
end
function A:quickClaw(s)
  if self.generation~=2 then return false end
  self:bind(s,s)
  local effect,param=self.k:heldEffect(s.mon,'priority')
  return effect=='HELD_QUICK_CLAW' and self.core.rng(0,255)<(tonumber(param) or 0)
end
function A:beginTurn()
  for _,s in ipairs(self.core:aliveSlots()) do
    if self.generation==1 then s.battler.flinched=false;s.battler.residualDone=nil
    else
      local v=self.k:volatile(s.mon)
      v.flinched=nil;v.tookThisTurn=nil;v.tookKind=nil
    end
  end
end
function A:specialField(s,def,move)
  if def.id~='HAZE' and def.id~='PERISH_SONG' and def.id~='HEAL_BELL' then return false end
  if move then move.pp=math.max(0,(move.pp or 1)-1) end
  self:announce()
  if def.id=='HAZE' then
    for _,peer in ipairs(self.core:aliveSlots()) do
      for key in pairs(peer.stages) do peer.stages[key]=0 end
      if self.generation==1 then peer.battler.curStats=peer.mon.stats end
    end
    self:message('All stat changes were eliminated!')
  elseif def.id=='PERISH_SONG' then
    for _,peer in ipairs(self.core:aliveSlots()) do local v=self.k:volatile(peer.mon);if not v.perish then v.perish=4 end end
    self:message('All active Pokemon heard the PERISH SONG!')
  else
    for _,mon in ipairs(self.core:party(s.side)) do mon.status=nil;mon.statusCount=nil;mon.sleepTurns=nil end
    for _,peer in ipairs(self.core:aliveSlots(s.side)) do
      if self.generation==1 then peer.battler.sleepTurns=nil;peer.battler.toxicCounter=nil
      else local v=self.k:volatile(peer.mon);v.toxicCount=nil end
    end
    self:message('A bell chimed! The party recovered from status conditions.')
  end
  return true
end
-- Semantic field absence, not the native picture blink/HIDEPIC layer.
-- Capture this before/after resolution; renderers must never read a future
-- mutable volatile while an older event is still on screen.
function A:structuralHidden(s)
  if self.generation==2 then return (s.mon and s.mon.volatile or {}).vanished==true end
  return s.battler and s.battler.invulnerable==true or false
end
-- Empty opposing positions are not substituted with fresh reserves. Run the
-- generation's pre-action gate, then fail the committed move with its ordinary
-- PP/continuation cost. No target effect, fake recipient or damage is executed.
function A:performNoTarget(s,action)
  local k=self.k;local foe
  for _,id in ipairs(self.core.positions) do local peer=self.core.slots[id]
    if peer.side~=s.side and peer.mon then foe=peer;break end
  end
  foe=foe or s
  self.acting=s;self.targets={};self.action=action;self.announced=false
  self.presentationEvent=nil;self.suppressAnnouncement=false;self.spread=false
  self:bind(s,foe)
  if self.generation==2 then
    if not k:canAct(s.mon,action.moveId) then return end
  else
    if s.battler.mustRecharge then
      s.battler.mustRecharge=nil;self:message(self:name(s.mon)..' must recharge!');return
    end
    if k:statusInterrupt(s.battler,foe.battler,action.moveId) then return end
  end
  local move=self:moves(s)[action.moveIndex]
  if action.moveIndex~=0 and (not move or move.id~=action.moveId) then
    self:message('The selected move is no longer available.');return
  end
  if move and self:disabled(s,action.moveIndex,move) then
    self:message(self:name(s.mon).."'s selected move is disabled!");return
  end
  local continuation=false
  if self.generation==2 then
    local v=k:volatile(s.mon)
    continuation=v.chargeMove==action.moveId or v.rampageMove==action.moveId or v.rolloutLock==action.moveId
    if v.chargeMove==action.moveId then v.chargeMove=nil;v.vanished=nil end
    if v.rampageMove==action.moveId then
      v.rampageTurns=(v.rampageTurns or 1)-1
      if v.rampageTurns<=0 then
        v.rampageMove=nil;v.rampageTurns=nil
        v.confuseCount=v.confuseCount or self.core.rng(2,3)
      end
    end
    -- Like a failed accuracy check, an empty-target Rollout cannot retain its
    -- successive-hit lock. Charging/rollout continuations still cost no PP.
    v.rolloutLock=nil;v.rampCount=nil;v.lastMove=action.moveId
  else
    local b=s.battler
    continuation=(b.charging==move and b.chargeReady) or (b.thrashMove==move and (b.thrashTurns or 0)>0) or (move and b.rageMove==move)
    if b.charging==move then b.charging=nil;b.chargeReady=nil;b.invulnerable=nil end
    if b.thrashMove==move then
      b.thrashTurns=(b.thrashTurns or 1)-1
      if b.thrashTurns<=0 then
        b.thrashMove=nil;b.thrashTurns=nil;b.thrashAnnounced=nil
        b.confusedTurns=b.confusedTurns or self.core.rng(2,5)
      end
    end
    b.lastMove=action.moveId
  end
  if move and not continuation and action.moveId~='STRUGGLE' then
    if (move.pp or 0)<=0 then self:message('There is no PP left!');return end
    move.pp=move.pp-1
  end
  self:message(self:name(s.mon)..' used '..(self:moveDef(action.moveId).name or action.moveId)..'!')
  self:message('But there was no target!')
end
function A:perform(s,targets,action)
  self.acting=s;self.targets=targets;self.action=action;self.announced=false;self.destruct=nil;self.presentationEvent=nil
  self.suppressAnnouncement=true;self.spread=false
  local def=self:moveDef(action.moveId);local k=self.k;local first=targets[1]
  local wasCharging=self.generation==2 and (s.mon.volatile or {}).chargeMove or s.battler.charging
  -- Self/field effects use the real opponent as their native context; their
  -- handlers still act on the user, while direct self-damage is never implied.
  if first==s then local foes=self.core:aliveSlots(s.side=='player' and 'enemy' or 'player');first=foes[1] or s end
  self:bind(s,first)
  if self.generation==2 then
    if not k:canAct(s.mon,action.moveId) then return end
  else
    k.queue={};k.nextInsert=0
    if s.battler.mustRecharge then
      s.battler.mustRecharge=nil;self:message(self:name(s.mon)..' must recharge!');return
    end
    if k:statusInterrupt(s.battler,first.battler,action.moveId) then return end
  end
  local move=self:moves(s)[action.moveIndex]
  -- Recheck at execution: a faster Disable may invalidate a move selected
  -- earlier in the same four-action turn. Do not spend PP or run its effect.
  if move and self:disabled(s,action.moveIndex,move) then
    self:message(self:name(s.mon).."'s "..(def.name or action.moveId)..' is disabled!');return
  end
  if move and not self:forced(s) and (move.pp or 0)<=0 then self:message('There is no PP left!');return end
  if self:specialField(s,def,move) then return self.presentationEvent end
  local beforeAbilityPP=move and move.pp
  self.spread=#targets>1 and (tonumber(def.power) or 0)>0
  local originalMoveDef=k.moveDef
  local magnitude
  if action.moveId=='MAGNITUDE' then
    local roll=self.core.rng(1,100)
    local power=roll<=5 and 10 or roll<=15 and 30 or roll<=35 and 50 or roll<=65 and 70 or roll<=85 and 90 or roll<=95 and 110 or 150
    magnitude=copy(def);magnitude.power=power;magnitude.effect='EFFECT_NORMAL_HIT'
    k.moveDef=function(_,id) if id=='MAGNITUDE' then return magnitude end return originalMoveDef(k,id) end
    self:message('MAGNITUDE!')
  end
  for index,t in ipairs(targets) do
    local nativeTarget=t
    if t==s then nativeTarget=first end
    self:bind(s,nativeTarget)
    if self.generation==2 then
      k.copyDepth=index>1 and 1 or 0
      local wasWrapped=nativeTarget.mon.volatile and nativeTarget.mon.volatile.wrapCount
      local wasTrapping=(s.mon.volatile or {}).trapsTarget
      k.moveEvent=nil
      k:useMove(s.mon,nativeTarget.mon,action.moveId)
      local row=k.moveEvent
      if self.presentationEvent and row then
        self.presentationEvent.targetResults[t.id]={battlerId=t.battlerId,missed=row.missed==true,
          animParam=row.animParam,wasVanished=row.wasVanished==true}
      end
      local v=nativeTarget.mon.volatile
      if not wasWrapped and v and v.wrapCount then nativeTarget.boundBy=s.battlerId end
      if (action.moveId=='LOCK_ON' or action.moveId=='MIND_READER') and v and v.lockOn and not (row and row.missed) then
        nativeTarget.lockOnSource=s.battlerId
      end
      if (action.moveId=='MEAN_LOOK' or action.moveId=='SPIDER_WEB') and not wasTrapping and (s.mon.volatile or {}).trapsTarget then
        nativeTarget.trappedBy=s.battlerId
      end
    else
      self:announce()
      k.queue={};k.nextInsert=0
      k:performMove(s.battler,nativeTarget.battler,move or {id=action.moveId,pp=1,struggle=action.moveId=='STRUGGLE'},index>1)
      if self.presentationEvent then
        self.presentationEvent.targetResults[t.id]={battlerId=t.battlerId,cancelled=k.moveAnimRow and k.moveAnimRow.cancelled==true}
      end
    end
    if action.moveId=='LEECH_SEED' then
      local seeded=self.generation==2 and (nativeTarget.mon.volatile or {}).leechSeed or nativeTarget.battler.leechSeeded
      if seeded then nativeTarget.seedSource=s.id end
    end
  end
  -- Native spread repetitions are called moves and spend no PP. Charge
  -- Pressure ONCE per actual targeted holder, after the action's own debit.
  if V.Abilities and V.Abilities.enabledBattle(k) and move and type(beforeAbilityPP)=="number" and move.pp<beforeAbilityPP then
    local extra=0;local visited={}
    for _,t in ipairs(targets) do
      if t~=s and not visited[t.battlerId] and self:abilityInfo(t.mon)=="PRESSURE" then extra=extra+1;visited[t.battlerId]=true end
    end
    move.pp=math.max(0,move.pp-extra)
  end
  if magnitude then k.moveDef=originalMoveDef end
  k.copyDepth=0;self.spread=false;self.suppressAnnouncement=false
  if self.destruct then self.destruct.hp=0;if self.generation==2 then self.destruct.status=nil end end
  if self.generation==1 and sideMoves[action.moveId] then
    local key=({REFLECT='reflect',LIGHT_SCREEN='lightScreen',MIST='mist'})[action.moveId]
    if key and s.battler[key] then self.screens[s.side][key]=5 end
    for _,peer in ipairs(self.core:aliveSlots(s.side)) do
      if action.moveId=='REFLECT' then peer.battler.reflect=s.battler.reflect
      elseif action.moveId=='LIGHT_SCREEN' then peer.battler.lightScreen=s.battler.lightScreen
      elseif action.moveId=='MIST' then peer.battler.mist=s.battler.mist end
    end
  end
  local event=self.presentationEvent
  if event then
    local charging=self.generation==2 and (s.mon.volatile or {}).chargeMove or s.battler.charging
    event.stage=(charging and not wasCharging) and 'charge' or 'attack'
    event.release=wasCharging and true or false
    event.sourceSlot=s.id;event.moveDef=def
  end
  return event
end
function A:endTurn()
  self.suppressAnnouncement=false;self.spread=false
  local k=self.k;local living=self.core:aliveSlots()
  if self.generation==2 then
    local function sandstormChip(checkCloudNine)
      local E=req('src.battle.gen2.Effects')
      local suppressed=checkCloudNine and AbilityEffectsGen2 and V.AbilityWeather
        and V.AbilityWeather.isSuppressed(k, function(mon) return AbilityEffectsGen2.hasAbility(k,mon,"CLOUD_NINE") end)
      if suppressed then return end
      for _,s in ipairs(living) do
        local d=k:speciesDef(s.mon)
        if not k:volatile(s.mon).vanished and E.sandstormHits((d and d.types) or s.mon.types) then
          s.mon.hp=math.max(0,s.mon.hp-E.sandstormDamage(self:maxHP(s.mon)))
          self:message(self:name(s.mon)..' is buffeted by the sandstorm!')
        end
      end
    end
    -- Ability-set weather (Sand Stream) has no turn limit and Cloud Nine
    -- suppresses its effect without clearing it -- matching
    -- AbilityEffectsGen2's own tickWeather wrap for native singles (doubles
    -- bypasses that wrap since it never calls Battle:tickWeather, hence the
    -- duplicated check here).
    if AbilityEffectsGen2 and AbilityEffectsGen2.enabled(k) then
      local mons={};for _,slot in ipairs(living) do mons[#mons+1]=slot.mon end
      AbilityEffectsGen2.tickWeather(k,mons)
    elseif k.weather=='sandstorm' and k.weatherAbilityLocked then
      sandstormChip(true)
    elseif k.weather and not k.weatherAbilityLocked then
      k.weatherTurns=(k.weatherTurns or 1)-1
      if k.weatherTurns<=0 then self:message('The '..k.weather..' ended.');k.weather=nil
      elseif k.weather=='sandstorm' then
        sandstormChip(false)
      end
    end
    for _,s in ipairs(living) do
      self:bind(s,s)
      if s.mon.hp>0 then k:tickStatus(s.mon) end
      local v=k:volatile(s.mon)
      if v.leechSeed and s.mon.hp>0 then
        local n=math.min(s.mon.hp,math.max(1,math.floor(self:maxHP(s.mon)/8)));s.mon.hp=s.mon.hp-n
        local source=s.seedSource and self.core.slots[s.seedSource]
        if source and source.mon and source.mon.hp>0 then k:heal(source.mon,n) end
        self:message('LEECH SEED saps '..self:name(s.mon)..'!')
      end
      if v.cursed and s.mon.hp>0 then s.mon.hp=math.max(0,s.mon.hp-math.max(1,math.floor(self:maxHP(s.mon)/4)));self:message(self:name(s.mon)..' is hurt by CURSE!') end
      k:tickWrap(s.mon);k:tickHeldItem(s.mon);k:tickPerish(s.mon);k:tickCounters(s.mon)
    end
    -- Exact two SIDE records, not four aliases, for screen duration.
    k:tickScreens()
  else
    for side,fields in pairs(self.screens) do
      for key,turns in pairs(fields) do
        fields[key]=turns-1
        if fields[key]<=0 then fields[key]=nil;for _,p in ipairs(self.core:aliveSlots(side)) do p.battler[key]=nil end end
      end
    end
    for _,s in ipairs(living) do
      local source=s.seedSource and self.core.slots[s.seedSource]
      local foes=self.core:aliveSlots(s.side=='player' and 'enemy' or 'player')
      local t=(source and source.mon and source.mon.hp>0 and source) or foes[1]
      if s.mon.hp>0 then
        self:bind(s,t or s)
        local seeded=s.battler.leechSeeded
        if not (source and source.mon and source.mon.hp>0) then s.battler.leechSeeded=nil end
        local msgs=self.status.residual(s.battler,(t or s).battler,k)
        s.battler.leechSeeded=seeded
        for _,text in ipairs(msgs or {}) do self:message(text) end
      end
      s.battler.skipMove=nil;s.battler.residualDone=nil;s.battler.flinched=false
      if s.battler.disabledTurns then s.battler.disabledTurns=s.battler.disabledTurns-1;if s.battler.disabledTurns<=0 then s.battler.disabledSlot=nil;s.battler.disabledTurns=nil end end
    end
  end
  if self.generation==2 then
    if AbilityEffectsGen2 then
      local mons={}
      for _,s in ipairs(living) do mons[#mons+1]=s.mon end
      AbilityEffectsGen2.onEndOfTurn(k, mons)
    end
  elseif AbilityEffectsGen1 then
    -- Gen I has no native weather system at all (confirmed: self.field is a
    -- stub the engine declares but never sets), and doubles doesn't tick
    -- anything weather-related here either -- unlike Gen II, this module's
    -- own onEndOfTurn is the ONLY place Gen I weather ever gets ticked, so
    -- (unlike Gen II) it's called in full here rather than split apart.
    AbilityEffectsGen1.onEndOfTurn(k, living)
  end
end
-- Encounter bookkeeping is tied to revealed, authoritative party identities;
-- no native singles send-out/replacement routine is called here.
function A:onReveal(s)
  if s.side~='enemy' then return end
  local save=self.host.save or (self.host.game and self.host.game.save)
  if not save then return end
  if self.generation==2 then
    local screen=req('src.ui.gen2.BattleState')
    local view=self.screen or {save=save}
    screen.markSeen(view,s.mon);screen.noteFirstUnown(view,s.mon)
  else
    save.pokedex=save.pokedex or {seen={},owned={}}
    save.pokedex.seen=save.pokedex.seen or {}
    save.pokedex.seen[s.mon.species]=true
  end
end
function A:onFaint(s,source)
  -- The slot guard in Core makes this once per actual faint, not once per
  -- frame or a second notification in the final native victory path.
  local cause=s.faintCause
  local foe=cause and self.core.slots[cause.slot]
  if not (foe and foe.mon and foe.battlerId==cause.battlerId and foe.side~=s.side) then
    foe=nil
    -- Residual/recoil/ally KOs have no opposing attacker; retain the opposing
    -- encounter context, including a simultaneously fainted foe, as singles
    -- does. Never bind a fainted player to itself for level comparisons.
    for _,id in ipairs(self.core.positions) do local peer=self.core.slots[id]
      if peer.side~=s.side and peer.mon then foe=peer;break end
    end
  end
  if s.side=='player' then
    if self.generation==2 and self.k.faintHappiness then
      if foe then self:bind(s,foe);self.k:faintHappiness(s.mon) end
    elseif self.generation==1 then
      local reason=foe and (foe.mon.level or 0)-(s.mon.level or 0)>=30 and 'CARELESSTRAINER' or 'FAINTED'
      req('src.world.PikachuFollower').modifyHappiness(self.host.game.save,reason,s.mon)
    end
  end
  local sideIndex=s.side=='player' and 1 or 2
  local side=self.host.sides and self.host.sides[sideIndex]
  req('src.mods.Runtime').emit('battle.fainted',{battle=self.host,
    battler=self.generation==2 and s.mon or s.battler,side=side,
    mon=s.mon,index=s.partyIndex,partyIndex=s.partyIndex,slot=s.id,
    battlerId=s.battlerId,sideKey=s.side,doubles=true})
end
function A:refreshAfterProgression(levels)
  for _,s in pairs(self.core.slots) do if s.mon then
    if self.generation==1 then
      local b=s.battler
      b.curMoves=s.mon.moves;b.curStats=s.mon.stats
      b.def=self.data.pokemon[s.mon.species] or b.def
      if levels and levels[s.mon]~=s.mon.level then
        -- Pre-existing bug found and fixed during the Colosseum Overhaul
        -- merge, unrelated to the merge itself: `Status.bakeOnInflict` has
        -- never existed anywhere in this engine or in CBE's own codebase
        -- (confirmed by search), so this call always raised "attempt to
        -- call field 'bakeOnInflict' (a nil value)" whenever any Pokemon
        -- leveled up during a doubles battle's post-battle progression,
        -- landing the session in Runtime.lua's D.fail() fault state after
        -- rewards had already committed. Invalidating badgeExtraBoosts
        -- alone is already the correct, complete fix: it matches the exact
        -- native cache-invalidate-then-lazily-recompute pattern used by
        -- src/battle/Damage.lua and src/battle/BattleState.lua/MoveEffects.lua
        -- elsewhere in this same engine; no extra "bake" step exists or is
        -- needed for curStats/badgeExtraBoosts to recompute correctly.
        b.badgeExtraBoosts=nil
      end
      b.shownHP=s.mon.hp;b.drainFloor=nil;b.shownStatus=s.mon.status
    end
    local d=self.core.display[s.battlerId]
    if d then d.hp=s.mon.hp;d.status=s.mon.status end
  end end
  self.core:bump()
end
return A
