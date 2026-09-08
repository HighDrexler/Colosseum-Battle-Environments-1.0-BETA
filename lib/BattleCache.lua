-- Main-menu preparation owns an opaque state; runtime readiness never does.
-- Cold runtime work retains the last game frame and completes before native
-- battle updates. No turns, HP, rewards, save data or sprite options are changed.
-- Errors never authorize another Pokemon artwork provider.
local V=...
local A,W=V.PokemonActors,V.WorkBudget
local C={version=7}
local Planner=V.QuickCachePlanner
local lastInventory=nil
local CacheScreen=V.CacheScreen
local view=nil
local active=nil
local completedIdentity=nil
local quickValidated={}
local lastCompleted=nil
local pendingTitle=nil
local renderErrors=setmetatable({}, {__mode="k"})
local runtime=setmetatable({}, {__mode="k"})
local attempted=setmetatable({}, {__mode='k'})
local function clock()return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()end
local function req(n)return (V.engineRequire or require)(n)end
function C.enabled(game,save)
  save=save or (game and game.save)
  local p=save and save.colosseumBattle
  return not (p and p.pokemonModelsEnabled==false)
end
function C.plan()
  local rows={}
  for dex=1,251 do
    rows[#rows+1]={dex=dex,variant='normal'}
    rows[#rows+1]={dex=dex,variant='shiny'}
  end
  return rows
end
-- Required startup warms only the current team. Manual Quick Start separately
-- selects 30 NEW source-model units based on save progress and disk completeness.
local function generation()
  return V.GenerationCompat and V.GenerationCompat.current() or 1
end
local function readSave(game)
  local ok,Save=pcall(req,generation()==2 and 'src.core.gen2.Save' or 'src.core.SaveData')
  if ok and Save and Save.load then
    local read,save=pcall(Save.load)
    if read and type(save)=='table' then return save end
  end
  return game and game.save or nil
end
local function rowKey(row)
  return tostring(row.dex)..':'..tostring(row.variant or 'normal')
end
local function isEgg(mon)
  mon=type(mon)=='table' and (type(mon.mon)=='table' and mon.mon or mon) or nil
  return mon and (mon.isEgg==true or mon.egg==true or mon.species=='EGG')
end
function C.startupPlan(game,save,newGame)
  local rows,seen={},{}
  local function add(dex,variant,why)
    local row={dex=dex,variant=variant or 'normal',error=why}
    local key=why and ('error:'..tostring(why)) or rowKey(row)
    if not seen[key] then rows[#rows+1]=row;seen[key]=true end
  end
  local party=not newGame and save and (save.party or save.pokemon or save.team)
  if type(party)=='table' then
    -- Native parties contain at most six entries. Never walk PC boxes, the
    -- Pokédex, or an unrelated save just to enter a session.
    for i=1,math.min(6,#party) do
      local mon=party[i]
      if not isEgg(mon) then
        local dex,variant=V.ModelIdentity.resolve(game,mon)
        if dex then add(dex,variant) else add(nil,'normal',variant) end
      end
    end
  end
  if newGame or not save then
    local starters=generation()==2 and {152,155,158} or {1,4,7}
    local ok,Version=pcall(req,'src.core.GameVersion')
    if generation()==1 and ok and Version and Version.get and Version.get()=='yellow' then starters={25} end
    for _,dex in ipairs(starters) do add(dex,'normal') end
  end
  return rows
end
-- Compatibility for existing consumers of the old team-only plan API.
C.quickPlan=C.startupPlan
function C.fullPlan(game,save)
  local rows,seen={},{}
  local function add(row)
    if not row.error and row.dex and not seen[rowKey(row)] then
      rows[#rows+1]=row;seen[rowKey(row)]=true
    end
  end
  for _,row in ipairs(C.startupPlan(game,save)) do add(row) end
  for _,row in ipairs(C.plan()) do add(row) end
  return rows
end
function C.quickReady(rows)
  local identity=A.sessionCacheIdentity()
  for _,row in ipairs(rows or {}) do
    if row.error or quickValidated[rowKey(row)]~=identity
        or not A.peek('startup',row.dex,row.variant).resident then return false end
  end
  return true
end
function C.busy()return active~=nil end
-- Backward-compatible full-catalog readiness, NOT quick-start completion.
function C.ready()return completedIdentity~=nil and completedIdentity==A.sessionCacheIdentity()end
function C.status()
  local current=active or lastCompleted
  local live=V.mod and V.mod.game and runtime[V.mod.game]
  return {ready=C.ready(),fullCatalogReady=C.ready(),active=active~=nil,
    mode=current and current.mode or 'idle',done=current and (current.index-1) or 0,
    total=current and #(current.rows or {}) or 0,error=active and active.error,
    planning=active and active.planning==true or false,
    batchLimit=Planner and Planner.batchSize or 30,
    cachedModels=lastInventory and lastInventory.cachedModels,
    cachedAppearances=lastInventory and lastInventory.cachedAppearances,
    totalModels=270,totalAppearances=502,
    catalogDiskReady=lastInventory and lastInventory.cachedModels==270 or false,
    profile=lastInventory and lastInventory.profile,
    label=current and current.label,resident=A.sessionResidentCount and A.sessionResidentCount() or 0,
    elapsed=current and math.max(0,(current.finishedAt or clock())-(current.startedAt or clock())) or 0,
    runtime=live and {error=live.error,prepared=live.prepared,lastMs=live.lastMs,maxMs=live.maxMs,
      failures=live.failures,retryAt=live.retryAt} or nil,
    runtimeLoadingScreen=false}
end
function C.frameBudgetMs()
  local ok,osName=pcall(function()return love.system.getOS()end)
  return ok and (osName=='Android' or osName=='iOS') and 8 or 12
end
-- Any title/cache chooser may advertise REUSE CACHE only after proving that
-- at least one full Quick Start quota (30 model units) already
-- exists on disk. This is a read-only metadata/sidecar check and is deliberately
-- separate from the 30-new Quick Start planner. It never prepares a new model.
local function stepReuseProbe(self)
  if not (self and self.selector) or self.reuseChecked then return end
  if not (Planner and Planner.reuseInfo and A and A.persistentModelState and W) then
    self.reuseChecked=true;self.reuseEligible=false;self.reuseProbeError='cache inventory unavailable';return
  end
  local started=clock()
  if started<(self.reuseNextAt or 0) then return end
  self.reuseNextAt=started+1/60
  if not self.reuseTask then
    self.reuseTask=W.new(function()
      return Planner.reuseInfo(A.persistentModelState,function(label)
        self.reuseLabel=label;W.checkpoint(label)
      end,Planner.batchSize or 30)
    end,'Checking existing cache for reuse')
  end
  local ok,state,info=W.resume(self.reuseTask,C.frameBudgetMs())
  if ok and state=='working' then return end
  self.reuseTask=nil;self.reuseChecked=true
  if ok and type(info)=='table' then
    self.reuseInfo=info;self.reuseEligible=info.eligible==true
  else
    self.reuseEligible=false;self.reuseProbeError=tostring(info or state or 'cache inventory failed')
  end
end
local State={isOpaque=true,isFixedSpeed=true,__cbeBattleCache=true,holdsUIAnchors=true}
State.__index=State
function State:wantsFillScale()return true end
function State:drawsWidescreen()return true end
local function report(self,why)
  self.error=tostring(why or 'model preparation failed')
  local row=self.rows[self.index]
  self.label=self.planning and 'Cache inventory' or ('Dex '..tostring(row and row.dex or '?')..' / '..tostring(row and row.variant or '?'))
  if V.mod and V.mod.cache then
    pcall(V.mod.cache.write,V.mod.cache,'build/model-cache-error.txt',self.label..'\n'..self.error..'\n')
  end
end
-- StateStack may also remove this screen during a launcher/state reset. Keep
-- the worker cleanup on the native exit boundary as well as on our own buttons.
-- Idempotent: close() calls this before pop(), whose exit callback calls it again.
-- No completion callback, extraction, cache deletion or prewarm runs from exit.
function State:exit()
  if self.task then W.cancel(self.task);self.task=nil end
  if self.reuseTask then W.cancel(self.reuseTask);self.reuseTask=nil end
  if active==self then active=nil end
  self.pointerAction=nil
  self.startupRequest=nil;self.onDone=nil;self.selectionArmed=false
end
function State:close()
  self:exit()
  if self.game.stack:top()==self then self.game.stack:pop() end
  if not self.battle and not self.selector and self.game.save and V.ResidentPrewarm and V.ResidentPrewarm.queueStartup then
    V.ResidentPrewarm.queueStartup(self.game)
  end
end
function State:update()
  local input=self.game.input
  local action=self.pointerAction;self.pointerAction=nil
  local function pressed(k)return action==k or (input and input.wasPressed and input:wasPressed(k))end
  if self.complete then
    if pressed('a') or pressed('b') then self:close() end
    return
  end
  if self.selector then
    stepReuseProbe(self)
    if pressed('b') then self:close();return end
    -- Do not let QUICK START be confirmed while the read-only reuse check is
    -- still in flight. Otherwise a slow Android metadata scan could leave Quick
    -- highlighted long enough for the user to accidentally start another batch
    -- before REUSE CACHE has had a chance to become the top option.
    if not self.reuseChecked then return end
    -- The title button can still be held (or its edge queued) when this state
    -- receives its first update. Require one neutral input step and a NEW
    -- confirmation. Never let opening the options also select the first mode.
    if not self.selectionArmed then
      local held=input and input.isDown and input:isDown('a')
      if not held and not pressed('a') and not action then self.selectionArmed=true end
      return
    end
    local firstStartupKey=self.reuseEligible and 'reuse' or 'startup'
    local keys
    if self.startupRequest then keys={firstStartupKey,'quick','full','b'}
    elseif self.reuseEligible then keys={'reuse','quick','full','b'}
    else keys={'quick','full','b'} end
    if pressed('up') then self.choice=(self.choice-2)%#keys+1 end
    if pressed('down') then self.choice=self.choice%#keys+1 end
    for i,key in ipairs(keys) do
      if action==key then self.choice=i;action='a';break end
    end
    if pressed('a') then
      local choice,game,save,request=keys[self.choice],self.game,self.selectedSave,self.startupRequest
      self:close()
      if choice=='reuse' and request then
        lastInventory=self.reuseInfo or lastInventory
        C.openReuse(game,request.save,request.onDone,request.newGame)
      elseif choice=='reuse' then
        -- The automatic/manual chooser has no pending Continue/New Game callback,
        -- but selecting REUSE should still make the choice meaningful: warm only
        -- the current team's required models from the existing disk cache now.
        -- This never invokes the 30-new planner, and it prevents an immediate
        -- second cache prompt when the user selects Continue afterward.
        lastInventory=self.reuseInfo or lastInventory
        C.openReuse(game,save,nil,false)
      elseif choice=='startup' and request then
        C.openStartup(game,request.save,request.onDone,request.newGame)
      elseif choice=='quick' then C.openQuick(game,save)
      elseif choice=='full' then C.openFull(game,save) end
    end
    return
  end
  if self.error then
    if pressed('a') then
      if self.retryRenderer then self:close();return end
      self.error=nil;self.nextAt=0
    elseif pressed('b') and not self.battle then self:close()
    elseif pressed('start') and love and love.event and love.event.quit then love.event.quit() end
    return
  end
  if not self.battle and pressed('b') then self:close();return end
  local started=clock()
  if started<(self.nextAt or 0) then return end
  -- A dedicated loading screen gets a foreground budget. This is still a
  -- wall-clock cap, not multiplied by the user's accelerated game logic rate.
  self.nextAt=started+1/60
  local deadline=started+C.frameBudgetMs()/1000
  if self.planning then
    if not self.task then
      self.task=W.new(function()
        if not (Planner and A.persistentModelState) then return nil,'Batch cache service unavailable' end
        return Planner.select(self.game,self.selectedSave,A.persistentModelState,function(label)
          self.label=label;W.checkpoint(label)
        end)
      end,'Selecting the next 30 uncached models')
    end
    local ok,state,rows,info=W.resume(self.task,math.max(.25,(deadline-clock())*1000))
    if ok and state=='working' then return end
    self.task=nil
    if not ok or not rows then report(self,ok and info or state);return end
    self.rows=rows;self.batchInfo=info;lastInventory=info;self.planning=false
    self.label=#rows>0 and ('Next '..#rows..' uncached models selected') or 'Full model cache already complete'
    -- Never grant a second foreground budget after the inventory scan.
    return
  end
  local passes=0
  repeat
    local row=self.rows[self.index]
    if not row then
      if self.full then
        completedIdentity=A.sessionCacheIdentity()
        lastInventory={cachedModels=270,cachedAppearances=502,totalModels=270,totalAppearances=502}
      end
      self.finishedAt=clock();self.label=self.full and 'Full catalog prepared' or (self.battle and 'Battle models prepared' or (self.batchInfo and 'Batch complete; cached models are kept' or 'Startup models prepared'))
      lastCompleted={mode=self.mode,index=self.index,rows=self.rows,label=self.label,
        startedAt=self.startedAt,finishedAt=self.finishedAt}
      if self.mode=='quick' and self.batchInfo then
        self.complete=true;return
      end
      local done=self.onDone;self:close()
      if done then done() end
      return
    end
    if not self.task then
      self.task=W.new(function()
        if row.error then return false,row.error end
        local result,why
        for _,variant in ipairs(row.variants or {row.variant or 'normal'})do
          result,why=A.prepareSessionModel(row.dex,variant,function(label)
            self.label=tostring(label or self.label or '')
            W.checkpoint(self.label)
          end)
          if not result then return false,why end
          quickValidated[rowKey({dex=row.dex,variant=variant})]=A.sessionCacheIdentity()
        end
        return result,why
      end,'Preparing Dex '..tostring(row.dex))
    end
    local remaining=(deadline-clock())*1000
    if remaining<.25 then return end
    local ok,state,result,why=W.resume(self.task,remaining)
    if ok and state=='working' then return end
    self.task=nil
    if not ok or not result then report(self,ok and why or state);return end
    quickValidated[rowKey(row)]=A.sessionCacheIdentity()
    self.index=self.index+1;passes=passes+1
    if self.batchInfo then
      self.batchInfo.cachedModels=self.batchInfo.cachedModels+1
      self.batchInfo.cachedAppearances=self.batchInfo.cachedAppearances+#(row.variants or {row.variant})
      lastInventory=self.batchInfo
    end
    -- Reuse-only rows allocate little. Do not force a large GC step for each
    -- normal/shiny alias; keep decoder cleanup on the actual preparation rows.
    if why~='resident' and collectgarbage then collectgarbage('step',128) end
  until passes>=32 or clock()>=deadline
end
-- Render once, after each generation's palette/composition pipeline. The native
-- 160x144 path is deliberately empty: painting RGB there made Gen I's SGB
-- palette remap this screen to garbled blue/red text.
function State:draw() end
function State:drawWidescreen() end
function State:drawPanel(w,h,localSpace)
  self.localSpace=localSpace==true
  assert(CacheScreen,'cache screen module unavailable')
  return CacheScreen.draw(self,w,h,lastInventory,clock())
end
function State:pointer(event)
  if not event or event.phase~='pressed' then return true end
  if event.source=='mouse' and event.button and event.button~=1 then return true end
  if event.insideGame==false then return true end
  if self.selector and not self.selectionArmed then return true end
  local x,y=event.x,event.y
  -- Engine gameX/gameY are viewport-local LOVE units, not Game Boy pixels.
  if self.localSpace and event.gameX and event.gameY then x,y=event.gameX,event.gameY end
  if not x or not y then return true end
  for _,button in ipairs(self.buttons or {}) do
    if x>=button.x and x<=button.x+button.w and y>=button.y and y<=button.y+button.h then
      self.pointerAction=button.key;break
    end
  end
  return true
end
function C.drawHud(next,game,viewport)
  local result=next(game,viewport)
  local live=runtime[game]
  local showError=live and live.error and C.enabled(game) and game.stack:top()==live.owner
    and CacheScreen and CacheScreen.drawRuntimeError
  local showCache=active and active.game==game and game.stack:top()==active
  if not ((showCache or showError) and love and love.graphics) then return result end
  local G=love.graphics
  local w,h=G.getDimensions()
  if not view then
    local ok,value=pcall(req,'src.render.GameViewport')
    if ok then view=value end
  end
  G.push('all')
  if view and view.dimensions then w,h=view.dimensions() end
  if view and view.setTarget then view.setTarget() end
  G.origin();G.setShader();if G.setScissor then G.setScissor() end
  if G.setBlendMode then G.setBlendMode('alpha') end
  if showCache then active:drawPanel(w,h,true) else CacheScreen.drawRuntimeError(w,h) end
  G.pop()
  return result
end
function C.open(game,rows,onDone,battle,mode)
  -- Runtime readiness must never acquire a full-screen state, including errors.
  if battle then return false,'runtime preparation uses holdBattle' end
  if active then return false,'cache preparation already active' end
  if not (game and game.stack and game.stack.push and W and A.prepareSessionModel) then return false,'cache state unavailable' end
  if V.ResidentPrewarm and V.ResidentPrewarm.cancel then V.ResidentPrewarm.cancel() end
  local full=mode=='full' or (mode==nil and rows==nil)
  local s=setmetatable({game=game,rows=rows or C.plan(),full=full,mode=mode or (battle and 'battle' or (full and 'full' or 'quick')),
    index=1,onDone=onDone,battle=battle==true,nextAt=0,startedAt=clock()},State)
  active=s;game.stack:push(s);return true
end
function C.openStartup(game,save,onDone,newGame)
  if active then return false,'cache preparation already active' end
  if not newGame and save==nil then save=readSave(game) end
  local rows=C.startupPlan(game,save,newGame)
  if C.quickReady(rows) then if onDone then onDone() end;return true,'startup-ready' end
  return C.open(game,rows,onDone,false,'startup')
end
-- Explicit reuse is intentionally the same narrow required-model warm as the
-- old team/starter-only path. The important contract is what it does NOT do:
-- it never invokes QuickCachePlanner.select and therefore never adds 30 models.
-- Required team/starter bodies may still be loaded from their existing disk cache
-- (or prepared individually if genuinely absent) so strict Colosseum rendering
-- remains intact.
function C.openReuse(game,save,onDone,newGame)
  return C.openStartup(game,save,onDone,newGame)
end
-- Explicit Quick Start ALWAYS makes a fresh 30-new-unit selection. Continue
-- uses openStartup instead, so finishing a batch cannot trigger another batch
-- just by loading the save. Disk completeness is checked on a cancellable worker.
function C.openQuick(game,save)
  if active then return false,'cache preparation already active' end
  local ok,why=C.open(game,{},nil,false,'quick')
  if ok then
    active.planning=true;active.selectedSave=save or readSave(game)
    active.label='Checking completed models; no source extraction during selection'
  end
  return ok,why
end
function C.openFull(game,save)
  if not active then lastInventory=nil end
  return C.open(game,C.fullPlan(game,save or readSave(game)),nil,false,'full')
end
function C.openMenu(game,save,startupRequest)
  if active then return false,'cache preparation already active' end
  if not (game and game.stack and game.stack.push) then return false,'cache state unavailable' end
  if V.ResidentPrewarm and V.ResidentPrewarm.cancel then V.ResidentPrewarm.cancel() end
  if pendingTitle and pendingTitle.game==game then pendingTitle=nil end
  local selectedSave=save or readSave(game)
  if startupRequest and startupRequest.newGame then
    -- New Game has no selected party yet. Prioritize native starters, never
    -- the old save's party, without writing either save or its options.
    selectedSave={party=C.startupPlan(game,nil,true)}
  end
  local knownReusable=lastInventory and tonumber(lastInventory.cachedModels)
    and tonumber(lastInventory.cachedModels)>=((Planner and Planner.batchSize) or 30) or false
  local s=setmetatable({game=game,selector=true,mode='choice',choice=1,rows={},index=1,
    selectionArmed=false,startupRequest=startupRequest,
    selectedSave=selectedSave,startedAt=clock(),reuseNextAt=0,
    reuseChecked=knownReusable==true,reuseEligible=knownReusable==true,
    reuseInfo=knownReusable and lastInventory or nil},State)
  active=s;game.stack:push(s);return true
end
-- User-facing title entry: only a fully ready current-session team may go
-- straight through. Cold/evicted startup models must offer an explicit choice
-- instead of starting a preparation worker from Continue or New Game.
-- openStartup remains the executor for an explicitly selected team/starter mode.
function C.requestStartup(game,save,onDone,newGame)
  if active then return false,'cache preparation already active' end
  if pendingTitle and pendingTitle.game==game then pendingTitle=nil end
  if not newGame and save==nil then save=readSave(game) end
  if C.quickReady(C.startupPlan(game,save,newGame)) then
    if onDone then onDone() end
    return true,'startup-ready'
  end
  return C.openMenu(game,save,{save=save,onDone=onDone,newGame=newGame==true})
end
function C.noteRenderError(game,reason)
  if game then completedIdentity=nil;renderErrors[game]=tostring(reason or 'Colosseum renderer failed') end
end
function C.runtimeStatus(game)return runtime[game] end
local function runtimeFailure(game,r,why,kind)
  r.error=tostring(why or 'model preparation failed');r.kind=kind
  r.failures=(r.failures or 0)+1
  r.retryAt=clock()+math.min(8,2^math.min(3,r.failures-1))
  -- A persistent fault is reported once per distinct reason, not every draw.
  if r.logged~=r.error then
    r.logged=r.error
    if V.mod and V.mod.cache then
      pcall(V.mod.cache.write,V.mod.cache,'build/model-cache-error.txt','Runtime '..tostring(kind)..'\n'..r.error..'\n')
    end
  end
  return true
end
function C.holdBattle(game,mons,owner)
  if not C.enabled(game) or active then return active~=nil end
  if not game then return false end
  owner=owner or (game.stack and game.stack:top())
  local r=runtime[game]
  if not r or r.owner~=owner then
    r={owner=owner,prepared=0,failures=0,lastMs=0,maxMs=0};runtime[game]=r
  end
  local renderError=renderErrors[game];renderErrors[game]=nil
  if renderError and not r.error then return runtimeFailure(game,r,renderError,'renderer') end
  if r.error then
    local input=game.input
    local function pressed(k)return input and input.wasPressed and input:wasPressed(k) end
    if pressed('start') and love and love.event and love.event.quit then love.event.quit();return true end
    if not pressed('a') and clock()<(r.retryAt or 0) then return true end
    r.error=nil
  end
  local rows,seen={},{}
  local cacheIdentity=A.sessionCacheIdentity()
  for _,mon in ipairs(mons or {}) do
    local dex,variant=V.ModelIdentity.resolve(game,mon)
    local identity=tostring(dex)..':'..tostring(variant)
    if not seen[identity] then
      seen[identity]=true
      if not dex then rows[#rows+1]={error=variant}
      elseif not ((A.sessionModelReady and A.sessionModelReady(dex,variant))
          or (not A.sessionModelReady and quickValidated[identity]==cacheIdentity and A.peek('selected',dex,variant).resident)) then
        -- An information viewer may have loaded the body without baking the
        -- battle action sidecars. Finish those here, not inside a turn.
        rows[#rows+1]={dex=dex,variant=variant}
      end
    end
  end
  if #rows==0 then return false end
  -- Finish required assets on the native update boundary. The last presented
  -- game frame remains visible during a cold read/build; no stack push, progress
  -- draw, GPU placeholder or battle update occurs in between. A cold model can
  -- still buffer, but cannot open the startup cache UI. Keep source validation,
  -- exact shiny metadata and all authored action sidecars intact.
  if V.ResidentPrewarm and V.ResidentPrewarm.cancel then V.ResidentPrewarm.cancel() end
  local started=clock();local pumpAt=started
  local function checkpoint()
    -- Keep the OS message queue responsive without dispatching game input or
    -- presenting another screen. Host I/O/GPU calls remain indivisible.
    local now=clock()
    if now-pumpAt>=.05 then
      pumpAt=now
      if love and love.event and love.event.pump then love.event.pump() end
    end
  end
  for _,row in ipairs(rows) do
    local ok,result,why
    if row.error then ok,result,why=true,false,row.error
    elseif W then
      -- Keep the worker's transactional cleanup even though runtime buffering
      -- drains it synchronously. Decoder/GPU failures must release resources
      -- registered with WorkBudget.onCancel, just like title preparation does.
      local task=W.new(function()return A.prepareSessionModel(row.dex,row.variant,checkpoint)end,'Battle model')
      local state
      repeat
        ok,state,result,why=W.resume(task,C.frameBudgetMs())
        checkpoint()
      until not ok or state~='working'
      if not ok then result=state end
    else ok,result,why=pcall(A.prepareSessionModel,row.dex,row.variant,checkpoint) end
    r.lastMs=math.max(0,(clock()-started)*1000);r.maxMs=math.max(r.maxMs,r.lastMs)
    if not ok or not result then return runtimeFailure(game,r,ok and why or result,'model') end
    quickValidated[rowKey(row)]=A.sessionCacheIdentity();r.prepared=r.prepared+1
  end
  r.failures=0;r.logged=nil
  return false
end
-- Other title-menu mods may prepend/reorder actions, and Strings translates
-- native labels. Never classify a row by its index or its keepOpen flag: that
-- could intercept OPTIONS/EXIT and leave the real CONTINUE without its guard.
local function titleAction(row)
  if row.value=='continue' then return 'continue' end
  if row.value=='new' then return 'new' end
  local label=row.label
  if label=='CONTINUE' then return 'continue' end
  if label=='NEW GAME' then return 'new' end
  local ok,Strings=pcall(req,'src.core.Strings')
  if ok then
    local hasContinue,continueLabel=pcall(Strings,'CONTINUE')
    local hasNew,newLabel=pcall(Strings,'NEW GAME')
    if hasContinue and label==continueLabel then return 'continue' end
    if hasNew and label==newLabel then return 'new' end
  end
  return nil
end
function C.install()
  if C.installed then return end
  C.installed=true
  V.mod.hooks:wrap('render.hud',C.drawHud,20000)
  V.mod.hooks:wrap('ui.title_menu.items',function(next,game,items)
    items=next(game,items) or items
    local rows={};local hasCacheItem=false
    for _,item in ipairs(items or {}) do
      local row={};for k,v in pairs(item)do row[k]=v end
      if row.value=='cbe_battle_cache' then hasCacheItem=true end
      -- Gen I title actions. Gen II dispatches values in MainMenu:choose below.
      local kind=row.onSelect and titleAction(row)
      if kind and not row.__cbeStartupGuard then
        local action=row.onSelect;local keepOpen=row.keepOpen==true
        local newGame=kind=='new'
        local run=function()
          if not keepOpen then game.stack:pop() end
          action()
        end
        row.keepOpen=true;row.__cbeStartupGuard=true
        row.onSelect=function()
          local save=not newGame and readSave(game) or nil
          if newGame or C.enabled(game,save) then C.requestStartup(game,save,run,newGame) else run() end
        end
      end
      rows[#rows+1]=row
    end
    if not hasCacheItem then
      rows[#rows+1]={label='BATTLE CACHE',value='cbe_battle_cache',keepOpen=true,onSelect=function()C.openMenu(game)end}
    end
    if not attempted[game] then
      attempted[game]=true
      local save=readSave(game)
      if C.enabled(game,save) and not C.quickReady(C.startupPlan(game,save)) then pendingTitle={game=game,save=save} end
    end
    return rows
  end)
  V.mod.hooks:wrap('input.step',function(next,game,dt)
    local result=next(game,dt)
    if pendingTitle and pendingTitle.game==game then
      local pending=pendingTitle;pendingTitle=nil
      if not active then C.openMenu(game,pending.save) end
    end
    return result
  end)
  V.mod.hooks:wrap('input.pointer',function(next,game,event)
    if active and active.game==game and game.stack:top()==active then
      return active:pointer(event)
    end
    return next(game,event)
  end)
  local generation=V.GenerationCompat and V.GenerationCompat.current() or 1
  if generation==2 then
    local ok,M=pcall(req,'src.ui.gen2.MainMenu')
    if ok and M and M.choose and not M.__cbeModelCache then
      local old=M.choose
      M.choose=function(self,value)
        if value=='cbe_battle_cache' then return C.openMenu(self.game,self.save) end
        if (value=='new' or value=='continue') and (value=='new' or C.enabled(self.game,self.save)) then
          return C.requestStartup(self.game,self.save,function()old(self,value)end,value=='new')
        end
        return old(self,value)
      end
      M.__cbeModelCache=true
    end
  end
  -- Actual native screen boundary: before singles/doubles can advance input or
  -- event clocks, not a draw-time placeholder. Recheck after switch/Transform.
  local ok,B=pcall(req,generation==2 and 'src.ui.gen2.BattleState' or 'src.battle.BattleState')
  if ok and B and B.update and not B.__cbeModelCache then
    local old=B.update
    B.update=function(screen,dt,...)
      local game=screen.game
      if C.enabled(game) then
        local mons={}
        local doubles=V.DoublesRuntime and V.DoublesRuntime.combat(screen)
        if doubles and doubles.core then
          for _,id in ipairs({'player-left','player-right','enemy-left','enemy-right'}) do
            local slot=doubles.core.slots[id];if slot and slot.mon then mons[#mons+1]=slot.mon end
          end
        else
          local host=V.GenerationCompat and V.GenerationCompat.prepare(screen) or screen
          for _,side in ipairs({'player','enemy'}) do if host and host[side] then mons[#mons+1]=host[side] end end
        end
        if C.holdBattle(game,mons,screen) then return end
      end
      return old(screen,dt,...)
    end
    B.__cbeModelCache=true
  end
end
C._test={State=State,reset=function()active=nil;completedIdentity=nil;quickValidated={};lastCompleted=nil;lastInventory=nil;pendingTitle=nil;renderErrors=setmetatable({}, {__mode='k'});runtime=setmetatable({}, {__mode='k'});attempted=setmetatable({}, {__mode='k'})end}
return C
