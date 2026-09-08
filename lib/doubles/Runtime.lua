-- Optional encounter-boundary integration. Singles do not enter this module's
-- move, input, reward or presentation paths when the option is disabled.
local V=...
local req=V.engineRequire or require
local D={version=1,serial=0,byState=setmetatable({},{__mode='k'}),lastSkip=nil}
local function clone(t,seen)
  if type(t)~='table' then return t end
  seen=seen or {};if seen[t] then return seen[t] end
  local n={};seen[t]=n;for k,v in pairs(t) do n[k]=clone(v,seen) end;return n
end
local function live(m) return V.DoublesCore.healthy(m) end
local function now() return love and love.timer and love.timer.getTime and love.timer.getTime() end
local function log(s)
  if V.mod.log then V.mod.log:info('Colosseum doubles: '..tostring(s)) end
end
function D.session(value)
  if not value then return D.active end
  local direct=D.byState[value];if direct then return direct end
  if type(value)=='table' then
    -- A later SINGLE battle uses the same game object. Never lend it the
    -- previous doubles command/replacement state just because that game matches.
    return D.byState[value._model] or D.byState[value._view] or D.byState[value.battle]
      or D.byState[value.__gen3Source]
  end
end
function D.combat(value)
  local s=D.session(value)
  return s and not s.handoff and not s.progressing and not s.closed and s or nil
end
-- World presentation stays four-actor while native progression owns its UI.
-- The command/UI service deliberately returns nil during that same interval.
function D.presentation(value)
  local s=D.session(value)
  return s and not s.handoff and not s.closed and s or nil
end
local function consumer(game)
  -- CBE is fully standalone. Doubles is the one feature that needs the paired
  -- command/HUD consumer; resolve that optional UI only at encounter admission.
  -- The chosen API is retained on the active session, so this is not a
  -- per-frame dependency and ordinary CBE singles remain independent.
  local api=V.mod and V.mod.exports and V.mod.exports.doublesUI
  if type(api)~='table' and V.ModLookup and type(V.ModLookup.find)=='function' then
    local ui=V.ModLookup.find(V.mod,'colosseum_ui_overhaul')
    api=ui and ui.exports and ui.exports.doublesUI or nil
  end
  if type(api)~='table' or api.version~=1 or type(api.input)~='function' then return nil,'Paired doubles UI is not installed' end
  if type(api.ready)=='function' then
    local ok,ready=pcall(api.ready,game)
    if not ok or not ready then return nil,'Enable Colosseum Battle UI before starting doubles' end
  end
  return api
end

local function eligible(screen,generation)
  local host=generation==2 and screen.battle or screen
  local game=screen.game
  local p=game and game.save and ((V.BattleSettings and V.BattleSettings.prefs(game)) or game.save.colosseumBattle)
  if not (p and p.doubleBattlesEnabled==true) then return false end
  if generation==2 then
    if not host.trainer or host.wild or host.linkBattle or host.inBattleTowerBattle
      or screen.tutorial or screen.contest or host.battleType==3 or host.battleType==6 then return false end
  elseif host.kind~='trainer' or host.demo or host.ghost or host.link or host.spectator then return false end
  if not host.enemyParty or #host.enemyParty<=2 then return false end
  if p.arenasEnabled==false then return false,'Double battles require Colosseum Arenas ON' end
  local api,why=consumer(game);if not api then return false,why end
  return true,api
end
function D.tryBegin(screen,generation)
  if screen.__cbeDoublesDecision~=nil then return nil end
  local arena=V.StandaloneHost and V.StandaloneHost.session
  local opening=arena and arena.started and (arena.battle==screen
    or (V.GenerationCompat and V.GenerationCompat.matches and V.GenerationCompat.matches(arena.battle,screen)))
    and ((generation==1 and screen.phase=='messages' and screen.showPlayerBack==true and screen.showEnemyTrainer==true)
      or (generation==2 and screen.phase=='intro' and screen.showPlayerTrainer==true))
  if screen.phase~='menu' and not opening then return nil end
  local ok,api=eligible(screen,generation)
  screen.__cbeDoublesDecision=ok==true
  if not ok then if type(api)=='string' then D.lastSkip=api;log(api) end;return nil end
  local host=generation==2 and screen.battle or screen
  local party=generation==2 and host.party or host:playerPartyView()
  local ready=false;for _,m in ipairs(party) do if live(m) then ready=true end end
  if not ready then return nil end
  D.serial=D.serial+1
  local backup={player={},enemy={}}
  for i,m in ipairs(party) do backup.player[i]=clone(m) end
  for i,m in ipairs(host.enemyParty) do backup.enemy[i]=clone(m) end
  backup.inventory=clone(screen.game.save.inventory);backup.bagOrder=clone(screen.game.save.bagOrder)
  backup.itemSaveFields={}
  for _,key in ipairs({'pikachuHappiness','pikachuMood','pikachuEmotionModifier'})do
    backup.itemSaveFields[key]={value=screen.game.save[key]}
  end
  local oldAmuletCoin=host.amuletCoin
  local adapter=V.DoublesNativeAdapter.new(host,generation)
  adapter.screen=screen
  local pi=generation==2 and host.playerIndex or nil
  if not pi then for i,m in ipairs(party) do if host.player and host.player.mon==m then pi=i end end end
  local core=V.DoublesCore.new{adapter=adapter,id='cbe-double-'..D.serial,generation=generation,
    playerParty=party,enemyParty=host.enemyParty,playerIndex=pi,enemyIndex=host.enemyIndex,
    groupedOpening=opening==true,openingText=opening and (screen.introText or ((host.trainer and host.trainer.name or 'Opponent')..' wants to battle!')) or nil,
    rng=host.rng or math.random}
  local s={screen=screen,host=host,generation=generation,core=core,adapter=adapter,consumer=api,
    backup=backup,oldPlayer=host.player,oldEnemy=host.enemy,oldPlayerIndex=host.playerIndex,
    oldEnemyIndex=host.enemyIndex,oldAmuletCoin=oldAmuletCoin,lastTime=now(),inputHeld={},awardIndex=1,groupedOpening=opening==true}
  core.sourceMoveFX=V.DoublesMovePresentation~=nil
  if opening then
    -- Take over before either native singles sendout. Retain the opening queue
    -- for the explicit test-abort path; ordinary native turns never consume it.
    s.openingState={}
    for _,key in ipairs({'phase','queue','message','shown','msgHold','nextInsert','waitFrames','afterQueue','showEnemyTrainer','showPlayerBack','showPlayerTrainer','introBalls','startHuds','ballRows','showEnemyHud','showPlayerHud'})do
      s.openingState[key]={value=screen[key]}
    end
    screen.queue={};screen.message=nil;screen.shown=nil;screen.msgHold=nil
    screen.showEnemyTrainer=false;screen.showPlayerBack=false;screen.showPlayerTrainer=false;screen.introBalls=nil
    screen.startHuds=nil;screen.ballRows={player=false,enemy=false};screen.showEnemyHud=false;screen.showPlayerHud=false
  end
  screen.__cbeDoublesActive=true;host.__cbeDoublesActive=true
  D.byState[screen]=s;D.byState[host]=s;D.active=s
  screen.phase='cbe_doubles'
  if V.DoublesPresenter then V.DoublesPresenter.begin(s) end
  core.onEvent=function(e) if V.DoublesPresenter then V.DoublesPresenter.event(s,e) end end
  core.onProgression=function(phase)
    if s.awardIndex>#core.defeated then return false end
    D.startProgression(s,phase);return true
  end
  log(core.id..' started: generation '..generation..', trainer party '..#host.enemyParty)
  return s
end
function D.close(s)
  if not s or s.closed then return end
  s.closed=true
  if s.progressGuards then
    s.screen.advanceQueue=s.progressGuards.advanceQueue
    s.screen.submit=s.progressGuards.submit
    s.progressGuards=nil
  end
  s.screen.__cbeDoublesProgressing=nil;s.host.__cbeDoublesProgressing=nil
  if V.DoublesPresenter then V.DoublesPresenter.finish(s) end
  s.screen.__cbeDoublesActive=nil;s.host.__cbeDoublesActive=nil
  D.byState[s.screen]=nil;D.byState[s.host]=nil
  if D.active==s then D.active=nil end
end
local function restoreRecord(dst,src)
  for k in pairs(dst) do dst[k]=nil end
  for k,v in pairs(clone(src)) do dst[k]=v end
end
function D.abort(s)
  if not s or s.handoff or s.rewardsStarted then return false,'Progression has committed; reload the pre-battle save rather than rolling it back.' end
  for i,m in ipairs(s.core.playerParty) do restoreRecord(m,s.backup.player[i]) end
  for i,m in ipairs(s.core.enemyParty) do restoreRecord(m,s.backup.enemy[i]) end
  local host=s.host
  if s.backup.inventory then s.screen.game.save.inventory=clone(s.backup.inventory) end
  s.screen.game.save.bagOrder=clone(s.backup.bagOrder)
  for key,row in pairs(s.backup.itemSaveFields or {})do s.screen.game.save[key]=row.value end
  host.amuletCoin=s.oldAmuletCoin
  host.player=s.oldPlayer;host.enemy=s.oldEnemy;host.playerIndex=s.oldPlayerIndex;host.enemyIndex=s.oldEnemyIndex
  if s.generation==1 then
    host.player=s.adapter.native.makeBattler(host.data,s.oldPlayer.mon,true,host.game.save)
    host.enemy=s.adapter.native.makeBattler(host.data,s.oldEnemy.mon,false)
  end
  s.screen.phase='menu';s.screen.__cbeDoublesDecision=false
  if s.openingState then for key,row in pairs(s.openingState)do s.screen[key]=row.value end end
  D.close(s);log('Encounter restored to its initial single-battle command state after test abort')
  return true
end
local function resetNativeQueue(s)
  local screen=s.screen
  screen.queue={};screen.current=nil;screen.message=nil;screen.shown=nil;screen.msgHold=nil
  screen.messagePages=nil;screen.messageCarry=nil
  screen.nextInsert=0;screen.waitFrames=nil;screen.afterQueue='menu'
  screen.waitingUI=nil;screen.waitingSound=nil;screen.waitSoundLeft=nil
  screen.animPlaying=false;screen.anim=nil;screen.pendingHit=nil
  screen.pendingSendOut=nil;screen.afterSendOut=nil;screen.shiftSwitchIndex=nil
end
local function bindNativeView(s)
  local core,host=s.core,s.host
  local player=core:aliveSlots('player')[1]
  if not player then
    for _,id in ipairs({'player-left','player-right'}) do
      if core.slots[id].mon then player=core.slots[id];break end
    end
  end
  if player then host.player=s.generation==2 and player.mon or player.battler;host.playerIndex=player.partyIndex end
  host.turn=s.generation==2 and core.turn or host.turn;host.turnCount=core.turn
  if type(host.syncSides)=='function' then host:syncSides() end
end
local function installProgressGuards(s)
  if s.progressGuards or s.generation~=2 then return end
  local screen=s.screen
  s.progressGuards={advanceQueue=rawget(screen,'advanceQueue'),submit=rawget(screen,'submit')}
  local advance=screen.advanceQueue;local submit=screen.submit
  screen.advanceQueue=function(view,...)
    if not s.closed and (s.progressing or s.handoff) and not s.finalizing and #(view.queue or {})==0
        and not (s.host.over) then
      -- Queue completion is a continuation, NEVER Gen II's CheckPlayerLockedIn
      -- -> automatic submit path. Do not clear the real charge/rampage state.
      if type(view.syncShownStatus)=='function' then view:syncShownStatus() end
      view.phase='cbe_progression_idle';view.message=nil
      return
    end
    return advance(view,...)
  end
  screen.submit=function(view,...)
    if not s.closed and (s.progressing or s.handoff) then
      error('Native singles combat submission blocked during doubles progression',0)
    end
    return submit(view,...)
  end
end
function D.startProgression(s,resume)
  assert(not s.progressing,'Doubles progression is already active')
  s.progressing=true;s.rewardResume=resume;s.core.phase='progression';s.core:bump()
  s.progressSaved={player=s.host.player,enemy=s.host.enemy,playerIndex=s.host.playerIndex,
    enemyIndex=s.host.enemyIndex,participants=s.host.participants,events=s.host.events}
  s.screen.__cbeDoublesProgressing=true;s.host.__cbeDoublesProgressing=true
  installProgressGuards(s);bindNativeView(s);resetNativeQueue(s)
  s.screen.phase='cbe_progression_idle'
  -- Start immediately: no transient singles command screen is rendered.
  D.rewardStep(s)
end
local function restoreProgressView(s)
  local saved=s.progressSaved
  if saved then
    for _,key in ipairs({'player','enemy','playerIndex','enemyIndex','participants','events'}) do s.host[key]=saved[key] end
    if type(s.host.syncSides)=='function' then s.host:syncSides() end
  end
  s.progressSaved=nil;s.progressing=nil
  s.screen.__cbeDoublesProgressing=nil;s.host.__cbeDoublesProgressing=nil
  s.screen.phase='cbe_doubles';s.lastTime=now()
  -- Do not replay the A/B edge which dismissed the final native dialog as a
  -- doubles command. The normal edge detector rearms after the button lifts.
  local input=s.screen.game.input
  for _,key in ipairs({'a','b','start','select'}) do
    s.inputHeld[key]=(input and input.isDown and input:isDown(key))
      or (input and input.wasPressed and input:wasPressed(key)) or false
  end
end
function D.startHandoff(s)
  if s.handoff then return end
  s.handoff=true
  if V.DoublesPresenter then V.DoublesPresenter.finish(s) end
  bindNativeView(s)
  local last=s.core.defeated[#s.core.defeated]
  if last then
    s.host.enemy=s.generation==2 and last.mon or last.battler
    s.host.enemyIndex=last.partyIndex or s.host.enemyIndex
  end
  s.host.payDay=s.adapter.k.payDay or s.host.payDay
  s.host.payDayMoney=s.adapter.k.payDayMoney or s.host.payDayMoney
  installProgressGuards(s);resetNativeQueue(s);s.screen.phase='cbe_progression_idle'
end
local function awardOne(s,defeated)
  local core,host,screen=s.core,s.host,s.screen
  assert(defeated.rewardState~='started','An interrupted EXP award cannot be replayed safely')
  defeated.rewardState='started';s.rewardCurrent=defeated;s.rewardsStarted=true
  s.rewardLevels={};for _,m in ipairs(core.playerParty) do s.rewardLevels[m]=m.level end
  host.participants={}
  for index in pairs(defeated.participants or {}) do
    local mon=core.playerParty[index]
    -- The controller captured eligibility at this KO. No later-turn HP filter
    -- is permitted here; live combat is suspended until this queue completes.
    if mon then host.participants[s.generation==2 and index or mon]=true end
  end
  host.enemy=s.generation==2 and defeated.mon or defeated.battler
  host.enemyIndex=defeated.partyIndex or host.enemyIndex
  resetNativeQueue(s)
  if s.generation==2 then
    host.events={};host:awardExperience(defeated.mon)
    screen.phase='resolving';screen:pushAll(host:takeEvents());screen:advanceQueue()
  else
    -- With zero participants the native singles helper pays its current user.
    -- That fallback is not legal for doubles. A call-local read-only view
    -- suppresses ONLY that fallback, without writing any real Pokemon's HP,
    -- bypassing EXP.ALL, replacing applyShare, or changing deferred commits.
    local player=host.player
    if next(host.participants)==nil and player and player.mon and (player.mon.hp or 0)>0 then
      local facade={};for k,v in pairs(player) do facade[k]=v end
      facade.mon=setmetatable({hp=0},{__index=player.mon});host.player=facade
    end
    local ok,err=pcall(host.awardExp,host);host.player=player
    if not ok then error(err,0) end
    screen.phase='messages';screen.afterQueue='menu'
  end
end
local function finishNative(s)
  if s.finalizing then return false end
  local core,host,screen=s.core,s.host,s.screen
  s.finalizing=true;resetNativeQueue(s)
  if s.generation==2 then
    host.events={}
    if core.outcome=='win' then
      -- Reuse native prize/Pay Day/result semantics while excluding the final
      -- already-presented faint and its already-settled EXP. Both temporary
      -- interceptors are restored even if the native handler raises an error.
      local rt=req('src.mods.Runtime')
      local oldAward,oldEmit,oldPublic=host.awardExperience,host.emit,rt.emit
      host.awardExperience=function() end
      host.emit=function(h,e,...) if e.kind=='faint' then return e end;return oldEmit(h,e,...) end
      rt.emit=function(name,e,...) if name=='battle.fainted' and e and e.battle==host then return end;return oldPublic(name,e,...) end
      local ok,err=pcall(host.resolveFaints,host)
      host.awardExperience=oldAward;host.emit=oldEmit;rt.emit=oldPublic
      if not ok then D.close(s);error(err,0) end
    else
      host:emit{kind='message',text='You have no more POKéMON!'}
      if host.battleType==1 then host:printWinLossText('lose') end
      host:endBattle('lose')
    end
    screen.phase='resolving';screen:pushAll(host:takeEvents());screen:advanceQueue()
  else
    screen.phase='messages'
    if core.outcome=='win' then
      local previous=host.awardExp;host.awardExp=function() end
      local ok,err=pcall(host.enemyMonFainted,host);host.awardExp=previous
      if not ok then D.close(s);error(err,0) end
    else
      local previous=host.playerPartyView
      host.playerPartyView=function()
        local party={};for _,mon in ipairs(core.playerParty) do
          if not mon.isEgg and not mon.egg then party[#party+1]=mon end
        end;return party
      end
      local ok,err=pcall(host.playerMonFainted,host);host.playerPartyView=previous
      if not ok then D.close(s);error(err,0) end
    end
    screen.afterQueue='finish'
  end
  D.close(s);return true
end
function D.rewardStep(s)
  local core,host,screen=s.core,s.host,s.screen
  local idle=screen.phase=='cbe_progression_idle' or screen.phase=='menu'
  -- Old producers/tests may arrive at this native state. Intercept it BEFORE
  -- its update submits a move; the live guard above never creates it.
  idle=idle or (screen.phase=='locked-in' and #(screen.queue or {})==0)
  if not idle then return false end
  if s.rewardCurrent then
    s.rewardCurrent.rewardState='complete';s.rewardCurrent=nil
    s.awardIndex=s.awardIndex+1;s.rewardsCompleted=(s.rewardsCompleted or 0)+1
    if s.adapter.refreshAfterProgression then s.adapter:refreshAfterProgression(s.rewardLevels) end
    s.rewardLevels=nil
  end
  local defeated=core.defeated[s.awardIndex]
  while defeated and defeated.rewardState=='complete' do
    s.awardIndex=s.awardIndex+1;defeated=core.defeated[s.awardIndex]
  end
  if defeated then awardOne(s,defeated);return true end
  if s.progressing then
    local resume=s.rewardResume;s.rewardResume=nil
    restoreProgressView(s);core:continueAfterEvents(resume)
    if core.phase=='finished' then D.startHandoff(s) end
    return true
  end
  return finishNative(s)
end
function D.fail(s,err)
  s.core.phase='fault';s.progressing=nil;s.handoff=nil
  s.screen.phase='cbe_doubles'
  s.screen.__cbeDoublesProgressing=nil;s.host.__cbeDoublesProgressing=nil
  s.core.messageText='Doubles test error: '..tostring(err)..(s.rewardsStarted
    and ' | Progression has committed; reload the pre-battle save.' or ' | B: restore encounter as singles.')
  s.core:bump();log(s.core.messageText)
  if V.mod.cache then pcall(V.mod.cache.write,V.mod.cache,'build/doubles-test-error.txt',s.core.messageText) end
end
function D.update(s,dt)
  if s.handoff or s.progressing then return D.rewardStep(s) end
  local t=now()
  if t then dt=math.max(0,math.min(.1,t-(s.lastTime or t)));s.lastTime=t end
  local input=s.screen.game.input;local pressed={}
  for _,key in ipairs({'up','down','left','right','a','b','start','select'}) do
    local down=input and type(input.isDown)=='function' and input:isDown(key) or false
    local raw=input and type(input.wasPressed)=='function' and input:wasPressed(key) or false
    pressed[key]=(raw or down) and not s.inputHeld[key]
    s.inputHeld[key]=down or raw
  end
  if s.core.phase=='fault' then
    if pressed.b then D.abort(s) end
    return true
  end
  local success,err=pcall(function()
    local inputChanged=s.inputTicket~=s.core.ticket or s.inputPhase~=s.core.phase
    for _,down in pairs(pressed) do if down then inputChanged=true;break end end
    if inputChanged then
      s.consumer.input(D.service,s.core:snapshot(),pressed,s.screen.game)
      s.inputTicket=s.core.ticket;s.inputPhase=s.core.phase
      D.inputSnapshots=(D.inputSnapshots or 0)+1
    end
    if s.closed then return end
    s.core.autoProgress=not V.BattleAutoProgress or V.BattleAutoProgress.enabled(s.screen.game)
    s.core:update(dt,pressed.a or pressed.b)
    if V.DoublesPresenter then V.DoublesPresenter.update(s,dt) end
    if s.core.phase=='finished' then D.startHandoff(s) end
  end)
  if not success then
    D.fail(s,err)
  end
  return true
end
D.service={version=1,format='double',experimental=false,snapshotOptionsVersion=1,
  snapshot=function(value,options)
    local s=D.combat(value);if not s then return nil end
    D.snapshotRequests=(D.snapshotRequests or 0)+1
    return s.core:snapshot(options)
  end,
  submit=function(request)
    local s=D.combat();if not s then return false,'No active doubles encounter' end
    return s.core:submit(request)
  end,
  status=function() local s=D.session();local fx=V.DoublesMovePresentation;return {active=s~=nil,battleId=s and s.core.id,phase=s and s.core.phase,lastSkip=D.lastSkip,
    inputSnapshots=D.inputSnapshots or 0,snapshotRequests=D.snapshotRequests or 0,
    moveFX=fx and {starts=fx.starts,sourceStarts=fx.sourceStarts,nativeAudioFallbacks=fx.nativeAudioFallbacks,lastError=fx.lastError}} end,
  abort=function(request)
    local s=D.combat();if not s then return false,'No doubles battle' end
    local ok,why=s.core:validateRequest(request);if not ok then return false,why end
    return D.abort(s)
  end,
}
function D.install()
  if D.installed then return end
  D.installed=true;V.mod.exports.doubles=D.service
  local Runtime=req('src.mods.Runtime')
  if not Runtime.__cbeDoublesEmitGuard then
    local old=Runtime.emit
    Runtime.emit=function(name,payload,...)
      if type(payload)=='table' and type(payload.battle)=='table' and payload.battle.__cbeDoublesKernel then return end
      return old(name,payload,...)
    end
    Runtime.__cbeDoublesEmitGuard=true
  end
  local generation=V.GenerationCompat.current()
  local class=req(generation==2 and 'src.ui.gen2.BattleState' or 'src.battle.BattleState')
  local old=assert(class.update,'Native battle update is unavailable')
  class.update=function(screen,dt,...)
    local s=D.byState[screen] or D.tryBegin(screen,generation)
    if s and not s.closed then
      if s.handoff or s.progressing then
        -- Native dialogs/stat boxes/learning run, but native combat submission
        -- cannot. The arena presenter keeps its four independent actor handles.
        if s.progressing and V.DoublesPresenter then V.DoublesPresenter.update(s,dt) end
        s.lastTime=now()
        local ok,handled=pcall(D.rewardStep,s)
        if not ok then D.fail(s,handled);return end
        if handled then return end
        local success,result=pcall(old,screen,dt,...)
        if not success then D.fail(s,result);return end
        if not s.closed and (s.progressing or s.handoff) then
          local settled,why=pcall(D.rewardStep,s)
          if not settled then D.fail(s,why) end
        end
        return result
      else D.update(s,dt);return end
    end
    return old(screen,dt,...)
  end
  -- Freeze native checkpoints at the unsupported custom phase (not 'menu').
  -- Engine BattleSafety already rejects this phase; no save serializer changes.
  if V.mod.events then V.mod.events:on('battle.ended',function(e)
    local s=e and D.session(e.battle)
    if s and not s.handoff then D.close(s) end
  end) end
end
return D
