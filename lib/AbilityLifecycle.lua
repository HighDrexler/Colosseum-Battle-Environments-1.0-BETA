-- Optional ability lifecycle for NATIVE singles. Doubles owns its own entry,
-- residual and progression boundaries; none of these listeners run its turns.
local V=... or {};local req=V.engineRequire or require
local unpack=unpack or table.unpack
local function pack(...)return {n=select('#',...),...}end
local A=assert(V.Abilities);local G1=assert(V.AbilityEffectsGen1);local G2=assert(V.AbilityEffectsGen2)
local L={};local installed={};local listenersInstalled=false
local states=setmetatable({},{__mode='k'})
local function normalize(value)
  if type(value)~='table' then return nil end
  if value.battle and value.battle.data then return value.battle,2 end
  if value.player and value.player.mon then return value,1 end
  if value.party and value.data then return value,2 end
end
local function controlled(b)
  if b.__cbeDoublesKernel then return true end
  local d=V.DoublesRuntime;local s=d and d.session and d.session(b)
  return s and not s.closed and (s.host==b or s.screen==b)
end
local function valid(b)
  return b and A.enabledBattle(b) and not controlled(b) and not b.result and not b.over
end
local function candidate(b,g)
  local p=(b.save or (b.game and b.game.save) or {}).colosseumBattle
  return p and p.doubleBattlesEnabled==true and p.arenasEnabled~=false and b.enemyParty and #b.enemyParty>2
    and ((g==1 and b.kind=='trainer') or (g==2 and b.trainer and not b.wild))
end
local function state(b)
  if not states[b] then states[b]={entered=setmetatable({},{__mode='k'})} end
  return states[b]
end
function L.enter(b,g,value)
  if not valid(b) or not value then return end
  local mon=g==1 and value.mon or value
  if not mon or (mon.hp or 0)<=0 or state(b).entered[value] then return end
  state(b).entered[value]=true
  local opponent=value==b.player and b.enemy or b.player
  if g==1 then G1.onEnter(b,value,opponent)else G2.onEnter(b,value,opponent)end
end
function L.ensure(b,g,atAction)
  if not valid(b) then return end
  -- Conversion occurs only at the arena boundary. Do not activate an incomplete
  -- native pair before the four-slot controller has had the chance to take over.
  -- A declined conversion still gets both entries before its first native action.
  if not atAction and candidate(b,g) then return end
  local p,e=b.player,b.enemy
  if not (p and e) then return end
  local ps=g==1 and (p.curStats and p.curStats.speed or 0) or b:effectiveSpeed(p)
  local es=g==1 and (e.curStats and e.curStats.speed or 0) or b:effectiveSpeed(e)
  if es>ps then L.enter(b,g,e);L.enter(b,g,p) else L.enter(b,g,p);L.enter(b,g,e) end
end
function L.onStarted(event)
  local b,g=normalize(event and event.battle);if b then L.ensure(b,g,false) end
end
function L.onSwitched(event)
  local b,g=normalize(event and event.battle)
  if not valid(b) then return end
  local old=event.previous;local value=event.battler
  if old then
    if g==1 then G1.onLeave(b,old)else G2.onLeave(b,old)end
    state(b).entered[old]=nil
  end
  if g==1 then L.enter(b,g,value)
  else state(b).pending=value end -- native spikesDamage is immediately next
end
function L.install(mod,generation)
  -- Production always supplies the active game. nil is an explicit test seam
  -- for a ROM-free dual-kernel fixture, never the launcher installation path.
  if generation~=2 and not installed[1] then
    local B1=req('src.battle.BattleState')
    local resolve=B1.resolveTurn
    B1.resolveTurn=function(self,...)
      if not valid(self) then return resolve(self,...) end
      L.ensure(self,1,true)
      -- resolveTurn only fixes order and queues closures. Temporary battle-stat
      -- copies therefore affect order without changing a saved stat or battler
      -- identity, or leaving scaled attack stats in a deferred action callback.
      local saved={}
      for _,b in ipairs({self.player,self.enemy})do
        local m=G1.speedMultiplier(self,b)
        if m~=1 and b.curStats then
          saved[b]=b.curStats;local copy={};for k,v in pairs(b.curStats)do copy[k]=v end
          copy.speed=copy.speed*m;b.curStats=copy
        end
      end
      local results=pack(pcall(resolve,self,...))
      for b,stats in pairs(saved)do b.curStats=stats end
      if not results[1]then error(results[2],0)end
      return unpack(results,2,results.n)
    end
    local end1=B1.endOfTurn
    B1.endOfTurn=function(self,...)
      if valid(self) and state(self).turn~=(self.turnCount or 0) then
        state(self).turn=self.turnCount or 0
        local active=A.actives(self);local hp={};for _,b in ipairs(active)do hp[b]=b.mon.hp end
        G1.onEndOfTurn(self,active)
        for _,b in ipairs(active)do if hp[b]>0 and b.mon.hp<=0 then self:onFaint(b) end end
      end
      return end1(self,...)
    end
    installed[1]=true
  end
  if generation~=1 and not installed[2] then
    local B2=req('src.battle.gen2.Battle')
    local take=B2.takeTurn
    B2.takeTurn=function(self,...)
      if valid(self) then L.ensure(self,2,true) end
      return take(self,...)
    end
    local close=B2.closeTurn
    B2.closeTurn=function(self,events)
      if valid(self) and self.turnOpen and state(self).turn~=self.turn then
        state(self).turn=self.turn
        G2.onEndOfTurn(self,A.actives(self))
        events=events or {}
        for _,e in ipairs(self:takeEvents())do events[#events+1]=e end
      end
      return close(self,events)
    end
    local spikes=B2.spikesDamage
    B2.spikesDamage=function(self,mon,...)
      local results=pack(pcall(spikes,self,mon,...))
      if not results[1]then error(results[2],0)end
      if valid(self) and state(self).pending==mon then
        state(self).pending=nil;L.enter(self,2,mon)
      end
      return unpack(results,2,results.n)
    end
    installed[2]=true
  end
  if not listenersInstalled and mod and mod.events and type(mod.events.on)=='function' then
    mod.events:on('battle.started',L.onStarted)
    mod.events:on('battle.battler_switched',L.onSwitched)
    mod.events:on('battle.ended',function(e)
      local b=normalize(e and e.battle);if b then states[b]=nil;A.reset(b) end
    end)
    listenersInstalled=true
  end
  return true
end
return L
