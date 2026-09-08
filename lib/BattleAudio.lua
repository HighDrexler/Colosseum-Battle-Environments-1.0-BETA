-- Presentation-only battle reward audio. All static Sources are prepared at
-- startup/game.ready; Sound.play and queue/event hooks perform no disk I/O.
local V=...
local A={version=1}
local S=assert(V.BattleAudioSpec)
local G=assert(V.GeneratedAssets)
local req=V.engineRequire or require
local gameRef,modRef=V.mod and V.mod.game,V.mod
local sources,owned,queue={},{},{}
local installed,loaded=false,false
local currentBattle,currentJingle,expDeadline,expRow,expScreen
local previousEnabled
local victorySeen=setmetatable({},{__mode="k"})
local taggedRows=setmetatable({},{__mode="k"})
local scope=nil
local Sound,Music
local volume=0.8
local function cueVolume(id)
 return volume*((id=="exp" or id=="expEnd") and .75 or 1)
end
local totals={level=0,exp=0,victory=0,fallback=0,preloads=0}
local errors={}
local function now()
 if love and love.timer and love.timer.getTime then return love.timer.getTime()end
 return os.clock()
end
local function call(obj,name,...)
 if not obj or type(obj[name])~="function" then return nil end
 local ok,r=pcall(obj[name],obj,...);if ok then return r end
 return nil
end
local function playing(src)return call(src,"isPlaying")==true end
local function stop(src)call(src,"stop")end
local function duration(src)return tonumber(call(src,"getDuration")) or 0 end
local function enabled()
 local p=gameRef and gameRef.save and gameRef.save.colosseumBattle
 return not (p and p.battleSoundsEnabled==false)
end
local function liveBattle()
 local states=gameRef and gameRef.stack and gameRef.stack.states
 if type(states)~="table" then return nil end
 for i=#states,1,-1 do
  local b=states[i]
  if type(b)=="table" and (b.isBattleState==true or
   (type(b.battle)=="table" and type(b.activeMon)=="function" and type(b.pic)=="function")) then return b end
 end
end
local Ticket={};Ticket.__index=Ticket
function Ticket:isPlaying()
 if self.done then return false end
 if not self.started then return true end
 if not playing(self.source) then self.done=true;return false end
 return true
end
function Ticket:stop()
 if self.started and not self.done then stop(self.source)end
 self.done=true
end
function Ticket:getDuration()return self.waitDuration end
function Ticket:getPitch()return 1 end
function Ticket:tell()return math.min(self.waitDuration,math.max(0,now()-self.created))end
local function remaining(ticket)
 if not ticket or not ticket:isPlaying()then return 0 end
 if not ticket.started then return duration(ticket.source)end
 return math.max(0,duration(ticket.source)-(tonumber(call(ticket.source,"tell")) or 0))
end
local function stopExp()
 stop(sources.exp);expDeadline=nil;expRow=nil;expScreen=nil
end
function A.stopAll()
 stopExp();stop(sources.expEnd)
 if currentJingle then currentJingle:stop()end
 for _,t in ipairs(queue)do t:stop()end
 currentJingle=nil;queue={};owned={}
 -- Native Music owns the paused song. Its next update observes stopped Tickets
 -- and releases its own duck; we never write music volume or restore a map.
end
local function sync()
 local b=liveBattle();local on=enabled()
 if b~=currentBattle or on~=previousEnabled then
  A.stopAll();currentBattle=b;previousEnabled=on
 end
 return on and b or nil
end
local function applyVolume(level)
 volume=.8*math.max(0,math.min(7,tonumber(level) or 7))/7
 for id,src in pairs(sources)do call(src,"setVolume",cueVolume(id))end
end
local function startTicket(t)
 stopExp()
 stop(t.source)
 call(t.source,"setLooping",false)
 call(t.source,"setVolume",cueVolume(t.kind))
 local ok,r=pcall(t.source.play,t.source)
 if not ok or r==false then t.done=true;return false end
 t.started=true;currentJingle=t
 if Music and Music.duckForFanfare then Music.duckForFanfare(t)end
 return true
end
local function jingle(id)
 local src=sources[id];if not src then return nil end
 local ahead=remaining(currentJingle)
 for _,t in ipairs(queue)do ahead=ahead+remaining(t)end
 local t=setmetatable({source=src,kind=id,created=now(),waitDuration=ahead+duration(src)},Ticket)
 if currentJingle and currentJingle:isPlaying()then queue[#queue+1]=t
 else currentJingle=nil;if not startTicket(t)then return nil end end
 totals[id]=totals[id]+1
 return t
end
local function startExp(seconds,screen,row)
 local src=sources.exp;if not src then return nil end
 if not playing(src) then
  stop(src);call(src,"setLooping",true);call(src,"setVolume",cueVolume("exp"))
  local ok,r=pcall(src.play,src);if not ok or r==false then return nil end
  totals.exp=totals.exp+1
 end
 expDeadline=seconds and now()+seconds or nil;expScreen=screen;expRow=row
 return src
end
local function update()
 if not sync()then return end
 if expDeadline and now()>=expDeadline then stopExp()end
 if expRow and expScreen and expScreen.current~=expRow then stopExp()end
 if currentJingle and not currentJingle:isPlaying()then currentJingle=nil end
 if not currentJingle then
  while #queue>0 do
   local t=table.remove(queue,1)
   if not t.done and startTicket(t)then break end
  end
 end
end
local function ownLevel(t)
 for name in pairs(S.levelNames)do owned[name]=t end
end
local function emit(name)
 -- Loader permits only mod-prefixed broadcasts. Do not forge sound.played via
 -- the public mod event API (that throws and would break the native queue).
 if modRef and modRef.id and modRef.events and type(modRef.events.emit)=="function" then
  pcall(modRef.events.emit,modRef.events,"mod."..modRef.id..".battle_sound",
   {kind="sfx",name=name,provider="colosseum-battle-audio"})
 end
end
function A.preload()
 if loaded then return true end
 if not (love and love.audio and love.audio.newSource and love.filesystem and love.filesystem.newFileData)then return false end
 local all=true
 for _,cue in ipairs(S.cues)do
  if not sources[cue.id] then
   local ok,err=pcall(function()
    local bytes=G.read(cue.path)
    assert(S.ready(cue,bytes,G.read(S.markerPath(cue))),"cue missing or incomplete")
    local fd=love.filesystem.newFileData(bytes,cue.id..".wav")
    local src=love.audio.newSource(fd,"static")
    assert(src,"audio Source unavailable");src:setLooping(cue.id=="exp");src:setVolume(cueVolume(cue.id))
    sources[cue.id]=src;totals.preloads=totals.preloads+1
    if cue.id=="exp" then
     local ending=love.audio.newSource(fd,"static");assert(ending,"EXP end Source unavailable")
     ending:setLooping(false);ending:setVolume(cueVolume("expEnd"));sources.expEnd=ending;totals.preloads=totals.preloads+1
    end
   end)
   if not ok then
    errors[cue.id]=tostring(err);all=false
    stop(sources[cue.id]);sources[cue.id]=nil
   else errors[cue.id]=nil end
  end
 end
 loaded=all
 return all
end
function A.attachGame(game)
 if game and game~=gameRef then A.stopAll();currentBattle=nil;gameRef=game end
 local opts=gameRef and ((gameRef.save and gameRef.save.options) or gameRef.options)
 applyVolume(opts and opts.sfxVol or 7)
 return A.preload()
end
local function hookClass(path,install)
 local ok,class=pcall(req,path)
 if ok and type(class)=="table" then install(class)end
end
local function installQueueHooks()
 hookClass("src.battle.BattleState",function(C)
  if type(C.sayNext)=="function" then
   local original=C.sayNext
   C.sayNext=function(self,...)
    local ret=original(self,...)
    if scope and scope.battle==self and scope.announce and scope.gained and scope.gained>0 then
     local row=self.queue and self.queue[self.nextInsert]
     if row and (tonumber(scope.level) or 100)<100 then taggedRows[row]=true end
     scope.gained=nil
    end
    return ret
   end
  end
  if type(C.updateQueue)=="function" then
   local original=C.updateQueue
   C.updateQueue=function(self,...)
    local ret=original(self,...)
    if sync()==self then
     local row=self.current
     if row and taggedRows[row]then
      taggedRows[row]=nil;startExp(.65,self,row)
     elseif expScreen==self and expRow and expRow~=row then stopExp()end
    end
    return ret
   end
  end
 end)
 hookClass("src.ui.gen2.BattleState",function(C)
  if type(C.advanceQueue)~="function"then return end
  local original=C.advanceQueue
  C.advanceQueue=function(self,...)
   local event=self.queue and self.queue[1]
   if expScreen==self then stopExp()end
   local ret=original(self,...)
   if sync()==self and event and event.kind=="experience" and (tonumber(event.amount) or 0)>0 and not self.expAnim then
    local b=self.battle;local mon=b and b.party and b.party[event.index]
    -- Active Gold EXP has its native per-pixel clock. Bench/EXP-share rewards
    -- have no bar; give their displayed award one bounded pulse train instead.
    local crossedToCap=false
    if mon and tonumber(mon.level)==100 then
     for _,ahead in ipairs(self.queue or {})do
      if ahead.kind=="level" and ahead.index==event.index then crossedToCap=true;break end
     end
    end
    if mon and mon~=b.player and ((tonumber(mon.level) or 100)<100 or crossedToCap)then startExp(.65,self)end
   end
   return ret
  end
 end)
end
local function pack(...)return {n=select('#',...),...}end
local unpackValues=table.unpack or unpack
local function awardWrapper(next,ctx,...)
 if type(ctx)~="table" or type(ctx.applyShare)~="function"then return next(ctx,...)end
 local original=ctx.applyShare
 ctx.applyShare=function(mon,split,announce,...)
  local prior=scope
  scope={battle=ctx.battle,mon=mon,level=mon and mon.level,announce=announce}
  local r=pack(pcall(original,mon,split,announce,...))
  scope=prior
  if not r[1]then error(r[2],0)end
  return unpackValues(r,2,r.n)
 end
 local r=pack(pcall(next,ctx,...));ctx.applyShare=original
 if not r[1]then error(r[2],0)end
 return unpackValues(r,2,r.n)
end
local function victoryWrapper(next,song,ctx)
 local selected=next(song,ctx)
 local b=sync();local reason=type(ctx)=="table" and ctx.reason
 if reason=="map" or reason=="restore" then A.stopAll();return selected end
 if reason~="victory" or not b or not sources.victory then return selected end
 local state=b.battle or b
 local outcome=state.outcome or state.result
 if outcome and outcome~="win" then return selected end
 if state.kind=="safari" or b.tutorial or b.link then return selected end
 if victorySeen[b] then return nil end
 local t=jingle("victory")
 if not t then return selected end
 victorySeen[b]=true
 -- Returning nil keeps the battle track selected but paused by native ducking.
 -- Once the one-shot ends, native Music.update resumes that very same track.
 return nil
end
function A.install(mod)
 modRef=mod or modRef
 if installed then return true end
 local okS,s=pcall(req,"src.core.Sound");local okM,m=pcall(req,"src.core.Music")
 if not(okS and okM and s and m and type(s.play)=="function")then return false end
 Sound,Music=s,m
 local originalPlay=Sound.play
 Sound.play=function(data,name,...)
  local b=sync()
  if b then
   local src
   if S.levelNames[name] then
    src=jingle("level");if src then ownLevel(src)end
   elseif name=="Sfx_ExpBar" then src=startExp();if src then owned[name]=src end
   elseif name=="Sfx_HitEndOfExpBar" and sources.expEnd then
    stopExp();stop(sources.expEnd)
    local ok,r=pcall(sources.expEnd.play,sources.expEnd)
    if ok and r~=false then src=sources.expEnd;owned[name]=src end
   end
   if src then emit(name);return src end
   if S.levelNames[name] or name=="Sfx_ExpBar" or name=="Sfx_HitEndOfExpBar" then
    owned[name]=nil;totals.fallback=totals.fallback+1
   end
  end
  return originalPlay(data,name,...)
 end
 local originalIsPlaying=Sound.isPlaying
 if originalIsPlaying then Sound.isPlaying=function(name,...)
  sync();local src=owned[name];if src then return playing(src)end
  return originalIsPlaying(name,...)
 end end
 local originalStop=Sound.stop
 if originalStop then Sound.stop=function(name,...)
  sync();if owned[name] then stop(owned[name]);if name=="Sfx_ExpBar"then stopExp()end end
  return originalStop(name,...)
 end end
 local originalFrames=Sound.waitFramesFor
 if originalFrames then Sound.waitFramesFor=function(name,fallback,...)
  sync();local src=owned[name]
  if src then return Sound.waitFrames(src,fallback)end
  return originalFrames(name,fallback,...)
 end end
 local function busyRemaining()
  local left=0
  if currentJingle and currentJingle.kind=="level" then left=remaining(currentJingle)end
  for _,t in ipairs(queue)do if t.kind=="level" and t:isPlaying()then left=math.max(left,t:getDuration()-t:tell())end end
  if playing(sources.exp)then left=math.max(left,expDeadline and math.max(0,expDeadline-now()) or .048)end
  if playing(sources.expEnd)then left=math.max(left,duration(sources.expEnd)-(tonumber(call(sources.expEnd,"tell")) or 0))end
  return left
 end
 local originalBusy=Sound.sfxBusy
 if originalBusy then Sound.sfxBusy=function(...)
  sync();return busyRemaining()>0 or originalBusy(...)
 end end
 local originalRemaining=Sound.sfxRemaining
 if originalRemaining then Sound.sfxRemaining=function(...)
  sync();local left=busyRemaining();local native=originalRemaining(...)
  if native==nil then return left>0 and left or nil end
  return math.max(left,native)
 end end
 for _,name in ipairs({"waitSfxDone","sfxChannelsOff"})do
  local original=Sound[name]
  if original then Sound[name]=function(...)
   sync();stopExp();stop(sources.expEnd)
   if currentJingle and currentJingle.kind=="level"then currentJingle:stop()end
   for _,t in ipairs(queue)do if t.kind=="level"then t:stop()end end
   return original(...)
  end end
 end
 local originalVolume=Sound.setVolumeLevel
 if originalVolume then Sound.setVolumeLevel=function(level,...)
  applyVolume(level);return originalVolume(level,...)
 end end
 local originalUpdate=Music.update
 if originalUpdate then Music.update=function(...)
  update();return originalUpdate(...)
 end end
 local originalReset=Sound.onDeviceReset
 if originalReset then Sound.onDeviceReset=function(...)
  A.stopAll();sources={};loaded=false
  local r=pack(originalReset(...));A.preload();return unpackValues(r,1,r.n)
 end end
 local hooks=modRef and modRef.hooks
 if hooks and type(hooks.wrap)=="function"then
  hooks:wrap("music.select",victoryWrapper,1300)
  hooks:wrap("battle.exp_award",awardWrapper,1300)
 end
 if modRef and modRef.events and type(modRef.events.on)=="function"then
  modRef.events:on("battle.exp_gained",function(e)
   if scope and e and e.battle==scope.battle and e.mon==scope.mon then scope.gained=tonumber(e.gained)end
  end)
 end
 installQueueHooks();installed=true
 A.attachGame(modRef and modRef.game)
 return true
end
function A.status()
 local ready={};for _,c in ipairs(S.cues)do ready[c.id]=sources[c.id]~=nil end
 return {installed=installed,ready=ready,enabled=enabled(),errors=errors,totals=totals,
  pendingFanfares=#queue,expPlaying=playing(sources.exp),version=S.version}
end
A._test={update=update,sync=sync,awardWrapper=awardWrapper,victoryWrapper=victoryWrapper,taggedRows=taggedRows}
return A
