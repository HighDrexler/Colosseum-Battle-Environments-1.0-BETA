-- Optional presentation-only boss prelude. The native battle queue is held at
-- its opening boundary, then resumed unchanged. No trainer scripts or rewards
-- are replaced, and this feature never depends on doubles being enabled.
local V=...
local req=V.engineRequire or require
local B={version=2,byScreen=setmetatable({},{__mode='k'}),lastSkip=nil,starts=0}
local CUE='assets/audio/intro/fanfare00.wav' -- GC6E01 colosseum entrance fanfare, setup 12
local CLASSES={
  BROCK='gym',MISTY='gym',LT_SURGE='gym',LTSURGE='gym',ERIKA='gym',KOGA='gym',SABRINA='gym',BLAINE='gym',GIOVANNI='organization-leader',
  FALKNER='gym',BUGSY='gym',WHITNEY='gym',MORTY='gym',CHUCK='gym',JASMINE='gym',PRYCE='gym',CLAIR='gym',JANINE='gym',BLUE='gym',
  LORELEI='elite-four',BRUNO='elite-four',AGATHA='elite-four',LANCE='champion',WILL='elite-four',KAREN='elite-four',CHAMPION='champion',
  RIVAL1='rival',RIVAL2='rival',RIVAL3='rival',RIVAL='rival',RED='story-boss',
  MAXIE='organization-leader',ARCHIE='organization-leader',CYRUS='organization-leader',GHETSIS='organization-leader',LYSANDRE='organization-leader',
}
local CATEGORIES={gym=true,['gym-leader']=true,['elite-four']=true,champion=true,rival=true,['organization-leader']=true,['story-boss']=true}
local function normalized(value)
  if type(value)~='string' then return nil end
  return value:upper():gsub('^OPP_',''):gsub('^TRAINER_',''):gsub('[%s%-]','_')
end
function B.classify(screen)
  if type(screen)~='table' then return nil,'not a battle' end
  local model=screen._model or screen.battle or screen
  if model.wild or (model.kind and model.kind~='trainer') or model.link or model.linkBattle or model.spectator
    or screen.link or screen.tutorial or screen.contest or model.demo or model.ghost or model.inBattleTowerBattle
    or model.battleType==3 or model.battleType==6 then return nil,'excluded encounter' end
  local trainer=model.trainer
  if type(trainer)~='table' then return nil,'no trainer identity' end
  if model.cbeBossIntro==false or trainer.cbeBossIntro==false then return nil,'explicitly excluded' end
  local category=model.cbeBossCategory or trainer.cbeBossCategory
  if category and CATEGORIES[category] then return category end
  if model.cbeBossIntro==true or trainer.cbeBossIntro==true then return 'story-boss' end
  -- Exact constants only: never inspect names, levels, party sizes, music,
  -- arena IDs, or substring-match a grunt into a boss classification.
  local keys={model.oppClass or false,trainer.classId or false,trainer.class or false,trainer.id or false,screen.enemyTrainerClass or false}
  for _,value in ipairs(keys) do local key=normalized(value);if key and CLASSES[key] then return CLASSES[key] end end
  return nil,'ordinary trainer'
end
local function now() return love and love.timer and love.timer.getTime and love.timer.getTime() end
local function sourceCall(source,key,...)
  if source and type(source[key])=='function' then return pcall(source[key],source,...) end
end
local function prefs(screen) return screen.game and screen.game.save and screen.game.save.colosseumBattle or {} end
local function matches(a,b)
  if a==b then return true end
  if V.GenerationCompat and V.GenerationCompat.matches then return V.GenerationCompat.matches(a,b) end
  return type(a)=='table' and type(b)=='table' and (a.battle==b or b._view==a or b._model==a.battle)
end
function B.active(value)
  local s=B.current
  return s and not s.closed and (value==nil or matches(s.screen,value)) and s or nil
end
local function musicVolume(s)
  local opts=s.screen.game and s.screen.game.save and s.screen.game.save.options or {}
  local scale=math.max(0,math.min(7,tonumber(opts.musicVol) or 7))/7
  local volume=.7*scale
  local ok,Runtime=pcall(req,'src.mods.Runtime')
  if ok and Runtime.wantsHook and Runtime.wantsHook('music.volume') then
    local worked,v=pcall(Runtime.call,'music.volume',function(x)return x end,volume,
      {song='CBE_BOSS_INTRO',reason='boss_intro',battle=s.screen,optionScale=scale})
    if worked and type(v)=='number' then volume=math.max(0,v) end
  end
  if s.fade then volume=volume*s.fade end
  sourceCall(s.source,'setVolume',volume)
end
local function openCue()
  if not (love and love.audio and love.audio.newSource and love.filesystem and love.filesystem.newFileData) then return nil,'audio unavailable' end
  local bytes=V.GeneratedAssets and V.GeneratedAssets.read(CUE)
  if type(bytes)~='string' or #bytes<44 or bytes:sub(1,4)~='RIFF' or bytes:sub(9,12)~='WAVE' then return nil,'canonical boss fanfare cache missing' end
  local ok,source=pcall(function()
    local fd=love.filesystem.newFileData(bytes,'cbe-boss-intro.wav')
    return love.audio.newSource(fd,'stream')
  end)
  if ok and source then return source end
  return nil,tostring(source)
end
function B.finish(reason)
  local s=B.current;if not s or s.closed then return end
  s.closed=true;s.reason=reason or 'complete';B.current=nil
  sourceCall(s.source,'stop')
  -- Release the stock fanfare duck immediately; do not restart the battle
  -- soundtrack or overwrite the remembered overworld music.
  if s.music and s.music.update then pcall(s.music.update,s.screen.game and s.screen.game.data) end
  -- The entrance fanfare is independent of every battle theme. Native Music
  -- resumes its paused source (including that theme's own intro) exactly once.
  sourceCall(s.source,'release');s.source=nil
  if s.screen then
    s.screen.__cbeBossIntroActive=nil
    if s.skipAt then s.screen.__cbeBossIntroRelease=true end
  end
end
function B.begin(screen)
  if screen.__cbeBossIntroChecked then return nil end
  screen.__cbeBossIntroChecked=true -- encounter-boundary latch, including OFF
  if prefs(screen).bossIntroEnabled~=true or prefs(screen).arenasEnabled==false then return nil end
  local category,why=B.classify(screen);if not category then B.lastSkip=why;return nil end
  -- A resumed command checkpoint is not a new introduction.
  if screen.phase=='menu' or screen.phase=='moves' or screen.phase=='cbe_doubles' then B.lastSkip='opening already completed';return nil end
  local host=V.StandaloneHost and V.StandaloneHost.session
  if not (host and host.started and matches(screen,host.battle)) then B.lastSkip='arena is not ready';return nil end
  local ok,Music=pcall(req,'src.core.Music')
  if not ok or not Music.duckForFanfare then B.lastSkip='native audio handoff unavailable';return nil end
  local source,err=openCue()
  if not source then B.lastSkip=err;return nil end
  B.finish('replaced')
  local durationOK,duration=sourceCall(source,'getDuration','seconds')
  duration=durationOK and tonumber(duration) or 0
  if not duration or duration<1 then sourceCall(source,'release');B.lastSkip='invalid fanfare duration';return nil end
  local s={screen=screen,category=category,source=source,music=Music,elapsed=0,
    duration=math.min(24,duration),lastTime=now(),cue=CUE}
  B.byScreen[screen]=s;B.current=s;B.starts=B.starts+1;B.lastSkip=nil
  screen.__cbeBossIntroActive=true
  sourceCall(source,'setLooping',false);sourceCall(source,'setPitch',1);musicVolume(s)
  sourceCall(source,'play');Music.duckForFanfare(source)
  return s
end
function B.update(s,dt)
  if not s or s.closed then return false end
  local t=now()
  if t then dt=t-(s.lastTime or t);s.lastTime=t end
  dt=math.max(0,math.min(.1,tonumber(dt) or 0));s.elapsed=s.elapsed+dt
  local input=s.screen.game and s.screen.game.input
  local press=input and input.wasPressed and (input:wasPressed('a') or input:wasPressed('b') or input:wasPressed('start'))
  if press and s.elapsed>.35 and not s.skipAt then s.skipAt=s.elapsed end
  if s.skipAt then s.fade=math.max(0,1-(s.elapsed-s.skipAt)/.18) end
  musicVolume(s)
  if s.elapsed>=s.duration or (s.skipAt and s.elapsed-s.skipAt>=.18) then
    B.finish(s.skipAt and 'skipped' or 'complete');return false
  end
  return true
end
local function lerp(a,b,t) return a+(b-a)*t end
local function smooth(t) t=math.max(0,math.min(1,t));return t*t*(3-2*t) end
local function trainerAnchor(context,side)
  local actor=side=='player' and V.PlayerTrainer or V.Trainer
  if actor and actor.anchor then
    local ok,v=pcall(actor.anchor,actor,4.5);if ok and type(v)=='table' and v[1] and v[3] then return v end
  end
  local arena=context.arena or {};local p=arena[side] or {0,0};local q=arena[side=='player' and 'enemy' or 'player'] or {0,1}
  local dx,dz=p[1]-q[1],p[2]-q[2];local d=math.max(1,math.sqrt(dx*dx+dz*dz))
  return {p[1]+dx/d*10,(context.groundY or 0)+4.5,p[2]+dz/d*10}
end
function B.camera(base,context)
  local s=B.active(context.battle);if not s then return nil end
  local t=s.elapsed/math.max(.1,s.duration)
  if t<.34 then
    local p=smooth(t/.34);local f=base.focus
    local dx,dz=base.eye[1]-f[1],base.eye[3]-f[3];local angle=lerp(-.13,.13,p)
    return {eye={f[1]+dx*math.cos(angle)-dz*math.sin(angle),base.eye[2]+lerp(10,5,p),f[3]+dx*math.sin(angle)+dz*math.cos(angle)},
      focus={f[1],f[2],f[3]},fov=math.min(1.4,base.fov*1.12),curve=0}
  elseif t<.90 then
    local side=t<.63 and 'enemy' or 'player'
    local p=smooth((t-(side=='enemy' and .34 or .63))/(side=='enemy' and .29 or .27))
    local a=trainerAnchor(context,side);local mid=(context.arena or {}).mid or {0,0}
    local dx,dz=mid[1]-a[1],mid[2]-a[3];local d=math.max(1,math.sqrt(dx*dx+dz*dz));dx=dx/d;dz=dz/d
    local pan=lerp(-4,4,p)
    return {eye={a[1]+dx*19-dz*pan,a[2]+2.8,a[3]+dz*19+dx*pan},focus={a[1],a[2],a[3]},fov=.72,curve=0}
  end
  return base
end
function B.install()
  if B.installed then return end
  B.installed=true
  V.mod.exports=V.mod.exports or {}
  V.mod.exports.bossIntro={version=B.version,active=function(b)return B.active(b)~=nil end,
    status=function()local s=B.current;return {active=s~=nil,category=s and s.category,elapsed=s and s.elapsed,
      duration=s and s.duration,starts=B.starts,lastSkip=B.lastSkip,cue=CUE} end}
  local generation=V.GenerationCompat.current()
  local class=req(generation==2 and 'src.ui.gen2.BattleState' or 'src.battle.BattleState')
  local old=assert(class.update)
  class.update=function(screen,dt,...)
    if screen.__cbeBossIntroRelease then
      local input=screen.game and screen.game.input
      local held=false
      for _,key in ipairs({'a','b','start'}) do
        held=held or (input and input.isDown and input:isDown(key)) or (input and input.wasPressed and input:wasPressed(key))
      end
      if held then return end
      screen.__cbeBossIntroRelease=nil
    end
    local s=B.active(screen) or B.begin(screen)
    if s then B.update(s,dt);return end -- never leak a skip press into the native queue
    return old(screen,dt,...)
  end
  for _,key in ipairs({'bottomUIVisible','statusHUDVisible','drawTextArea','drawHUDs'}) do
    local inner=class[key]
    if type(inner)=='function' then class[key]=function(screen,...)
      if B.active(screen) then return false end
      return inner(screen,...)
    end end
  end
  if V.mod.events then V.mod.events:on('battle.ended',function(e)
    if e and B.active(e.battle) then B.finish('battle ended') end
  end) end
end
B._test={classes=CLASSES,categories=CATEGORIES,normalized=normalized}
return B
