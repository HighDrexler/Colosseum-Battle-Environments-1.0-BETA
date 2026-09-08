local V=...
local S={}

local Arena=V.Arena
local ArenaCatalog=V.ArenaCatalog
local PlayerTrainer=V.PlayerTrainer
local Trainer=V.Trainer
local PokemonActors=V.PokemonActors
local CurrentSpriteModels=V.CurrentSpriteModels
local WazaHandlers=V.WazaHandlers
local MoveFXExtractor=V.MoveFXExtractor
local GeneratedAssets=V.GeneratedAssets
local BattleSettings=V.BattleSettings

local function platformOS()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok and v then return tostring(v) end
  end
  return "Unknown"
end
local ANDROID_RUNTIME=platformOS()=="Android"
local INTERVAL=ANDROID_RUNTIME and 0.90 or 0.24
local START_DELAY=ANDROID_RUNTIME and 0.75 or 0.30

local queue={}
local queued={}
local gameRef=nil
local nextAt=0
local epoch=0
local stats={queued=0,completed=0,requeued=0,failed=0,pumps=0,lastLabel=nil,lastMs=0,totalMs=0,maxMs=0}
local hardSerial=0
local hard={running=false,total=0,done=0,failed=0,stage="idle",last=nil,completed=false}

-- Information-viewer coordination. 3D menu surfaces are latency-sensitive: a
-- normal startup/prewarm job that happens to land while the user is browsing a
-- PC/Pokedex/Summary can stop input/audio for the full duration of a model or
-- arena upload. The UI can touch this short lease every visible frame. While
-- the lease is active the scheduler runs only a specifically requested
-- selected information-model job in cooperative slices (including a first
-- source-backed shiny preparation). Unrelated work stays queued for the next
-- quiet overworld window; the UI shows its resolved sprite in the meantime.
local viewerUntil=0
local viewerReason=nil
local informationSerial=0
local informationQueued={}
local informationDesired={}
local informationActiveKey=nil
local informationErrors={}

local function clockNow()
  if love and love.timer and type(love.timer.getTime)=="function" then
    local ok,v=pcall(love.timer.getTime);if ok and type(v)=="number" then return v end
  end
  return os.clock()
end

local function add(key,label,run,kind,viewerSafe,infoTag,infoDex)
  if type(run)~="function" then return false end
  key=tostring(key or label or (#queue+1))
  if queued[key] then return false end
  queued[key]=true
  queue[#queue+1]={key=key,label=tostring(label or key),run=run,kind=kind,viewerSafe=viewerSafe==true,
    infoTag=infoTag,infoDex=infoDex}
  stats.queued=stats.queued+1
  return true
end

local function addFront(key,label,run,kind,viewerSafe,infoTag,infoDex)
  if type(run)~="function" then return false end
  key=tostring(key or label or (#queue+1))
  if queued[key] then return false end
  queued[key]=true
  table.insert(queue,1,{key=key,label=tostring(label or key),run=run,kind=kind,viewerSafe=viewerSafe==true,
    infoTag=infoTag,infoDex=infoDex})
  stats.queued=stats.queued+1
  return true
end

local function arenaWarmContext(game)
  return {game=game,battle=nil,phase="resident-prewarm",progress=1,
    services={cbeStandalone=true,androidResidentWarm=ANDROID_RUNTIME,coordinatedPrewarm=true}}
end

local function queueArenaDefinition(game,id,tag)
  if not (Arena and type(Arena.prewarmDefinition)=="function") then return false end
  id=tostring(id or "")
  if id=="" then return false end
  local key=(tag or "arena")..":"..id..":"..tostring(epoch)
  return add(key,"arena:"..id,function()
    pcall(Arena.prewarmDefinition,Arena,arenaWarmContext(game),id)
    return false
  end)
end

function S.queueArena(game,tag)
  if not (ArenaCatalog and Arena and game) then return 0 end
  if type(ArenaCatalog.enabled)=="function" then
    local ok,on=pcall(ArenaCatalog.enabled,game);if ok and on==false then return 0 end
  end
  local selected=type(ArenaCatalog.selected)=="function" and ArenaCatalog.selected(game) or "auto"
  local before=#queue
  if selected=="auto" then
    -- AUTO can resolve to either of these at encounter time. Pace both onto the
    -- resident set instead of paying either scene at the first battle boundary.
    queueArenaDefinition(game,"water",tag or "auto")
    queueArenaDefinition(game,"outdoor_wild",tag or "auto")
  elseif selected=="random" and type(ArenaCatalog.primeRandom)=="function" then
    local ok,def=pcall(ArenaCatalog.primeRandom,game)
    if ok and type(def)=="table" and def.id then queueArenaDefinition(game,def.id,tag or "random") end
  else
    queueArenaDefinition(game,selected,tag or "selected")
  end
  return #queue-before
end

local function queueTrainerPump(game)
  if not (Trainer and type(Trainer.queuePrewarm)=="function" and type(Trainer.pumpPrewarm)=="function") then return 0 end
  local ok,count=pcall(Trainer.queuePrewarm,Trainer,game)
  count=ok and tonumber(count) or 0
  if not count or count<=0 then return 0 end
  add("trainer-pump:"..tostring(epoch),"enemy-trainer",function()
    local okPump,_,pending=pcall(Trainer.pumpPrewarm,Trainer,game)
    if not okPump then return false end
    return (tonumber(pending) or 0)>0
  end)
  return count
end

local function queuePartyPump(game)
  if not (PokemonActors and type(PokemonActors.queuePartyPrewarm)=="function" and type(PokemonActors.pumpPartyPrewarm)=="function") then return 0 end
  local ok,count=pcall(PokemonActors.queuePartyPrewarm,game)
  count=ok and tonumber(count) or 0
  if not count or count<=0 then return 0 end
  add("pokemon-pump:"..tostring(epoch),"party-model",function()
    local okPump,_,pending=pcall(PokemonActors.pumpPartyPrewarm,game)
    if not okPump then return false end
    return (tonumber(pending) or 0)>0
  end)
  return count
end

local function queueMoveFXPump(game)
  if not (MoveFXExtractor and type(MoveFXExtractor.queueParty)=="function" and type(MoveFXExtractor.pumpPrefetch)=="function") then return 0 end
  local ok,result=pcall(MoveFXExtractor.queueParty,game,6)
  local pending=ok and type(result)=="table" and tonumber(result.queued) or 0
  if not pending or pending<=0 then return 0 end
  add("movefx-pump:"..tostring(epoch),"movefx-cache",function()
    local okPump,out=pcall(MoveFXExtractor.pumpPrefetch,1)
    if not okPump then return false end
    return type(out)=="table" and (tonumber(out.pending) or 0)>0
  end)
  return pending
end

local function hardModuleStatus()
  local p=hard.pokemonQueued and PokemonActors and PokemonActors.hardCacheStatus and PokemonActors.hardCacheStatus() or {}
  local w=hard.wazaQueued and WazaHandlers and WazaHandlers.hardCacheStatus and WazaHandlers.hardCacheStatus() or {}
  local mp=MoveFXExtractor and MoveFXExtractor.status and MoveFXExtractor.status() or {}
  return p,w,tonumber(mp.pending) or 0
end

local function pruneHardJobs()
  local kept={}
  for _,row in ipairs(queue) do
    if not tostring(row.key or ""):match("^hard%-") then kept[#kept+1]=row else queued[row.key]=nil end
  end
  queue=kept
end

function S.cancelHardCache()
  pruneHardJobs()
  if PokemonActors and type(PokemonActors.cancelHardCache)=="function" then pcall(PokemonActors.cancelHardCache) end
  if WazaHandlers and type(WazaHandlers.cancelHardCache)=="function" then pcall(WazaHandlers.cancelHardCache) end
  hard.running=false;hard.stage="cancelled"
  return true
end

function S.touchViewer(seconds,reason)
  local now=clockNow()
  local span=math.max(0.10,math.min(1.00,tonumber(seconds) or 0.35))
  viewerUntil=math.max(viewerUntil or 0,(now or 0)+span)
  viewerReason=tostring(reason or "information-model")
  return viewerUntil
end

local function pruneInformationTag(tag,keepDex)
  tag=tostring(tag or "information")
  local kept={}
  for _,row in ipairs(queue) do
    local stale=(row.infoTag==tag and tostring(row.infoDex)~=tostring(keepDex) and row.key~=informationActiveKey
      and (row.kind=="information" or row.kind=="information-idle"))
    if stale then
      queued[row.key]=nil
      if row.infoDex then informationQueued[row.infoDex]=nil end
    else
      kept[#kept+1]=row
    end
  end
  queue=kept
end

function S.queueInformation(game,battler,tag)
  if not (PokemonActors and type(PokemonActors.informationWarmStatus)=="function"
      and type(PokemonActors.prewarmInformation)=="function") then return false,"information warm unavailable" end
  local okStatus,status=pcall(PokemonActors.informationWarmStatus,game,battler)
  if not okStatus or type(status)~="table" then return false,"information status unavailable" end
  local dex=tonumber(status.dex)
  if not dex or status.supported==false then return false,"unsupported pokemon",status end
  -- Distinguish palette variants even when they share a GPU body: a normal
  -- body is not a completed shiny warm until its native colour recipe exists.
  local identity=tostring(status.key or dex)..":"..tostring(status.variant or "normal")
  tag=tostring(tag or "information")
  informationDesired[tag]=identity
  pruneInformationTag(tag,identity)
  local key="information-model:"..tag..":"..identity
  local failure=informationErrors[key]
  if failure and clockNow()<failure.retryAt then status.error=failure.reason;return false,"retry-cooldown",status end
  local cooperative=type(PokemonActors.pumpInformation)=="function"
  local function queueIdleBake()
    if status.idlePrepared==true or not PokemonActors.bakeInformationIdle then return false end
    local idleKey="information-idle:"..tag..":"..identity
    if queued[idleKey] then return true end
    return add(idleKey,idleKey,function()
      if informationDesired[tag]~=identity and informationActiveKey~=idleKey then return false end
      if cooperative then
        informationActiveKey=idleKey
        local ok,warmed,why,pending=pcall(PokemonActors.pumpInformation,game,battler,"idle")
        if ok and pending then return true end
        informationActiveKey=nil
        if not ok or not warmed then stats.failed=stats.failed+1 end
      else pcall(PokemonActors.bakeInformationIdle,game,battler) end
      return false
    end,"information-idle",cooperative,tag,identity)
  end
  if status.resident==true then
    local idle=queueIdleBake();return true,idle and "resident-idle-deferred" or "resident",status
  end
  if queued[key] then return true,"queued",status end
  informationSerial=informationSerial+1
  informationQueued[identity]=true
  local task,deadline
  local function checkpoint()
    if clockNow()>=deadline then coroutine.yield("information-slice") end
  end
  local added=addFront(key,key..(status.cached and ":cached" or ":source"),function()
    if not task and informationActiveKey~=key and informationDesired[tag]~=identity then informationQueued[identity]=nil;return false end
    deadline=clockNow()+(ANDROID_RUNTIME and .003 or .006)
    informationActiveKey=key
    local resumed,warmed,why,pending
    if cooperative then
      resumed,warmed,why,pending=pcall(PokemonActors.pumpInformation,game,battler,"body")
      if resumed and pending then return true end
    else
      -- Older providers retain the existing coroutine/progress contract.
      if not task then task=coroutine.create(function()
        return PokemonActors.prewarmInformation(game,battler,status.cached~=true,checkpoint)
      end) end
      resumed,warmed,why=coroutine.resume(task)
      if resumed and coroutine.status(task)~="dead" then return true end
    end
    task=nil;informationActiveKey=nil;informationQueued[identity]=nil
    if resumed and warmed then
      informationErrors[key]=nil
      if informationDesired[tag]==identity then queueIdleBake() end
    else
      informationErrors[key]={retryAt=clockNow()+2,reason=tostring(resumed and why or warmed)}
      stats.failed=stats.failed+1
    end
    return false
  end,"information",true,tag,identity)
  if not added then informationQueued[identity]=nil end
  nextAt=math.min(nextAt or math.huge,clockNow()+.05)
  return added,added and (status.cached and "queued-cached" or "queued-source") or "already-queued",status
end


function S.viewerActive()
  return clockNow()<(viewerUntil or 0)
end

function S.pauseHardCache(value)
  if not hard.running then return false end
  hard.paused=value~=false
  if not hard.paused then nextAt=clockNow() end
  return true
end

function S.hardCacheRunning()
  return hard.running==true
end

function S.queueHardCache(game,scope)
  scope=scope=="team" and "team" or "full"
  local marker=scope=="team" and "build/hard_cache_team_v1.complete" or "build/hard_cache_v5.complete"
  if type(game)~="table" then return 0,"game unavailable" end
  -- Repeated clicks do not throw away a running cache job.
  if hard.running and gameRef==game then return hard.total,"already-running" end
  S.cancelHardCache();hardSerial=hardSerial+1;gameRef=game
  hard={running=true,paused=false,scope=scope,total=0,done=0,failed=0,stage="party",last=nil,completed=false,
    startedAt=clockNow(),jobs=0,moveDone=0,moveTotal=0,moveUnavailable=0}
  local tag=tostring(hardSerial)
  if GeneratedAssets and GeneratedAssets.delete then
    -- A previous completion marker must not survive a failed refresh. No
    -- generated model, action, arena, or source-import data is cleared here.
    GeneratedAssets.delete(marker)
  end
  local function finalize()
    local ps,ws=hardModuleStatus()
    local errors=hard.failed+(tonumber(ps.failed) or 0)+(tonumber(ws.failed) or 0)
    if (tonumber(ps.pending) or 0)+(tonumber(ws.pending) or 0)>0 then errors=errors+1 end
    hard.stage="register"
    local saved=false
    if GeneratedAssets and type(GeneratedAssets.saveInfoRegistry)=="function" then
      saved=select(1,GeneratedAssets.saveInfoRegistry({hardCache=errors==0 and "complete" or "partial",revision=1}))
    end
    if not saved then hard.failed=hard.failed+1;errors=errors+1 end
    local written=false
    if errors==0 and GeneratedAssets and type(GeneratedAssets.write)=="function" then
      written=GeneratedAssets.write(marker,
        "cbe-hard-cache=5\nsource=GC6E01\npokemon-extractor=37\nshiny-source-contract=1\nscope="..scope.."\nmode=party-storage-native-shiny-source-actions-movefx-registry\n")
      if not written then hard.failed=hard.failed+1;errors=errors+1 end
    end
    hard.done=(tonumber(ps.done) or 0)+(tonumber(ws.done) or 0)+(hard.registryIndex or 0)+hard.moveDone
    hard.running=false;hard.completed=errors==0 and not not written
    hard.stage=hard.completed and "ready" or "failed"
    hard.finishedAt=clockNow()
    return false
  end
  local function hardJob(key,label,run)
    hard.jobs=hard.jobs+1
    add(key..":"..tag,label,function()
      local ok,again=pcall(run)
      if not ok then hard.failed=hard.failed+1;hard.last=tostring(again) end
      if ok and again==true then return true end
      hard.jobs=hard.jobs-1
      if hard.jobs==0 then
        -- Schedule finalization exactly once, not once every queue rotation.
        add("hard-finalize:"..tag,"hard-cache:register",finalize,"hard-cache")
      end
      return false
    end,"hard-cache")
  end
  local pokemonCount=0
  local modelsEnabled=true
  if BattleSettings and type(BattleSettings.pokemonModelsEnabled)=="function" then
    local ok,on=pcall(BattleSettings.pokemonModelsEnabled,game);if ok and on==false then modelsEnabled=false end
  end
  if modelsEnabled and PokemonActors and type(PokemonActors.queueHardCache)=="function" then
    local ok,n=pcall(PokemonActors.queueHardCache,game,scope)
    hard.pokemonQueued=true
    if ok then pokemonCount=tonumber(n) or 0 else hard.failed=hard.failed+1 end
  end
  if MoveFXExtractor and type(MoveFXExtractor.queueParty)=="function" then
    local ok,r=pcall(MoveFXExtractor.queueParty,game,6)
    if ok and type(r)=="table" then
      local st=MoveFXExtractor.status and MoveFXExtractor.status() or {}
      hard.moveTotal=tonumber(st.pending) or tonumber(r.queued) or 0
      -- Unsupported source moves are allowed to retain their existing visual
      -- fallback. They are reported separately, never forged as cached banks.
      hard.moveUnavailable=tonumber(r.failed) or 0
    else hard.failed=hard.failed+1 end
  end
  hard.total=pokemonCount+hard.moveTotal

  hard.registryPaths={};hard.registryIndex=0
  if scope=="full" and GeneratedAssets and type(GeneratedAssets.read)=="function" then
    local raw=GeneratedAssets.read("build/generated_paths.lua")
    if type(raw)=="string" then
      local chunk=load(raw,"@generated/build/generated_paths.lua")
      local ok,paths=false,nil
      if chunk then ok,paths=pcall(chunk) end
      if ok and type(paths)=="table" then
        local seen={}
        for _,path in ipairs(paths) do
          if type(path)=="string" and path~="" and not seen[path] then
            seen[path]=true;hard.registryPaths[#hard.registryPaths+1]=path
          end
        end
      else hard.failed=hard.failed+1 end
    end
  end
  hard.total=hard.total+#hard.registryPaths
  if #hard.registryPaths>0 then
    hardJob("hard-register-paths","hard-cache:asset-registry",function()
      hard.stage="registry"
      local deadline=clockNow()+(ANDROID_RUNTIME and 0.002 or 0.004)
      local stop=math.min(#hard.registryPaths,hard.registryIndex+(ANDROID_RUNTIME and 64 or 128))
      for i=hard.registryIndex+1,stop do
        -- Keep authoritative validation, but no 240/900ms sleep per tiny batch.
        if GeneratedAssets.revalidateInfo then GeneratedAssets.revalidateInfo(hard.registryPaths[i])
        elseif GeneratedAssets.info then GeneratedAssets.info(hard.registryPaths[i]) end
        hard.registryIndex=i
        if i%8==0 and clockNow()>=deadline then break end
      end
      return hard.registryIndex<#hard.registryPaths
    end)
  end
  if pokemonCount>0 then
    hardJob("hard-pokemon","hard-cache:party-storage-actions",function()
      hard.stage="party"
      local out=PokemonActors.pumpHardCache(game,1)
      if type(out)~="table" then error("Pokemon hard-cache worker returned no status") end
      hard.last=(PokemonActors.hardCacheStatus and PokemonActors.hardCacheStatus().last) or hard.last
      return (tonumber(out.pending) or 0)>0
    end)
  end
  hardJob("hard-movefx","hard-cache:movefx",function()
    hard.stage="movefx"
    if not hard.movesFinished and MoveFXExtractor and type(MoveFXExtractor.pumpPrefetch)=="function" then
      local out=MoveFXExtractor.pumpPrefetch(1)
      if type(out)~="table" then error("MoveFX hard-cache worker returned no status") end
      hard.moveDone=math.min(hard.moveTotal,hard.moveDone+(tonumber(out.processed) or 0))
      hard.moveUnavailable=hard.moveUnavailable+(tonumber(out.failed) or 0)
      if (tonumber(out.pending) or 0)>0 then return true end
    end
    hard.movesFinished=true
    if not hard.wazaQueued then
      hard.wazaQueued=true
      if WazaHandlers and type(WazaHandlers.queueHardCacheSpecs)=="function" then
        local specs=MoveFXExtractor and type(MoveFXExtractor.partySpecs)=="function" and MoveFXExtractor.partySpecs(game,6) or {}
        hard.total=hard.total+(tonumber(WazaHandlers.queueHardCacheSpecs(specs)) or 0)
      end
    end
    hard.stage="waza"
    if WazaHandlers and type(WazaHandlers.pumpHardCache)=="function" then
      local out=WazaHandlers.pumpHardCache(1)
      if type(out)~="table" then error("Waza hard-cache worker returned no status") end
      return (tonumber(out.pending) or 0)>0
    end
    return false
  end)
  nextAt=clockNow()
  return hard.total
end

function S.queueStartup(game)
  if PokemonActors and PokemonActors.cancelInformation then PokemonActors.cancelInformation() end
  S.cancelHardCache()
  epoch=epoch+1
  gameRef=game
  queue={};queued={};informationQueued={};informationDesired={};viewerUntil=0;viewerReason=nil
  local now=clockNow();nextAt=(now or 0)+START_DELAY

  -- Put the most likely next-battle dependencies at the front of the queue.
  -- AUTO's secondary Wildlands scene is useful, but must not delay the player
  -- trainer/common enemy/party body needed by a trainer encounter.
  local selected=ArenaCatalog and type(ArenaCatalog.selected)=="function" and ArenaCatalog.selected(game) or "auto"
  local arenasEnabled=true
  if ArenaCatalog and type(ArenaCatalog.enabled)=="function" then
    local ok,on=pcall(ArenaCatalog.enabled,game);if ok and on==false then arenasEnabled=false end
  end
  if arenasEnabled then
    if selected=="auto" then
      queueArenaDefinition(game,"water","startup-primary")
    elseif selected=="random" and ArenaCatalog and type(ArenaCatalog.primeRandom)=="function" then
      local ok,def=pcall(ArenaCatalog.primeRandom,game)
      if ok and type(def)=="table" and def.id then queueArenaDefinition(game,def.id,"startup-primary") end
    else
      queueArenaDefinition(game,selected,"startup-primary")
    end
  end

  if PlayerTrainer and type(PlayerTrainer.prewarm)=="function" then
    add("player-trainer:"..tostring(epoch),"player-trainer",function()
      pcall(PlayerTrainer.prewarm,PlayerTrainer,arenaWarmContext(game))
      return false
    end)
  end

  if ANDROID_RUNTIME and Arena and type(Arena.prewarmFramebuffer)=="function" then
    add("framebuffer:"..tostring(epoch),"battle-framebuffer",function()
      pcall(Arena.prewarmFramebuffer,Arena)
      return false
    end)
  end

  queueTrainerPump(game)
  queuePartyPump(game)

  if arenasEnabled and selected=="auto" then
    queueArenaDefinition(game,"outdoor_wild","startup-secondary")
  end

  -- Shader compilation is small compared with a scene upload, but still belongs
  -- behind the same single-job gate so game.ready stays a bookkeeping seam.
  if CurrentSpriteModels and type(CurrentSpriteModels.prewarm)=="function" then
    add("sprite-shader:"..tostring(epoch),"sprite-shader",function()
      pcall(CurrentSpriteModels.prewarm,CurrentSpriteModels);return false
    end)
  end
  if WazaHandlers and type(WazaHandlers.prewarm)=="function" then
    add("waza-shaders:"..tostring(epoch),"waza-shaders",function()
      pcall(WazaHandlers.prewarm);return false
    end)
  end
  queueMoveFXPump(game)

  return #queue
end

function S.pump(game,viewerOnly)
  if game then gameRef=game end
  if #queue==0 then return false,0 end
  if hard.running and hard.paused and not informationActiveKey then return false,#queue,"hard-cache-paused",0 end
  local now=clockNow()
  if now and now<nextAt then return false,#queue end
  local viewerActive=viewerOnly==true or (now or 0)<(viewerUntil or 0)
  local deadline=now+(ANDROID_RUNTIME and 0.003 or 0.006)
  local passes,lastOk,lastLabel,totalMs=0,false,nil,0
  repeat
    local row,index
    if informationActiveKey then
      for i,candidate in ipairs(queue) do if candidate.key==informationActiveKey then row,index=candidate,i;break end end
    elseif hard.running and PokemonActors and PokemonActors.sourceBusy and PokemonActors.sourceBusy() then
      for i,candidate in ipairs(queue) do if candidate.kind=="hard-cache" then row,index=candidate,i;break end end
    elseif viewerActive then
      for i,candidate in ipairs(queue) do
        if (candidate.kind=="information" or candidate.kind=="information-idle") and candidate.viewerSafe==true then row,index=candidate,i;break end
      end
      if not row then return false,#queue,"viewer-defer",0 end
    elseif hard.running then
      -- Do not interleave duplicate background GPU prewarms with an explicit
      -- disk bake. The normal queue remains intact and resumes afterwards.
      for i,candidate in ipairs(queue) do
        if candidate.kind=="hard-cache" then row,index=candidate,i;break end
      end
    else row,index=queue[1],1 end
    if not row then break end
    table.remove(queue,index);queued[row.key]=nil
    local t0=clockNow()
    local ok,again=pcall(row.run)
    local t1=clockNow();local ms=math.max(0,(t1-t0)*1000)
    stats.pumps=stats.pumps+1;stats.lastLabel=row.label;stats.lastMs=ms;stats.totalMs=stats.totalMs+ms
    if ms>stats.maxMs then stats.maxMs=ms end
    if not ok then
      stats.failed=stats.failed+1
      if row.kind=="hard-cache" then
        hard.failed=hard.failed+1;hard.running=false;hard.completed=false;hard.stage="failed";hard.last=tostring(again)
        pruneHardJobs()
      end
    elseif again==true then
      queued[row.key]=true;queue[#queue+1]=row;stats.requeued=stats.requeued+1
    else stats.completed=stats.completed+1 end
    passes=passes+1;lastOk=ok;lastLabel=row.label;totalMs=totalMs+ms
    local cooldown=INTERVAL
    if row.kind=="information" or row.kind=="information-idle" then cooldown=(ok and again==true) and 0 or (ANDROID_RUNTIME and .10 or .03) end
    if row.kind=="hard-cache" then
      -- Cheap validation and cooperative CPU slices resume next game update.
      -- One unusually slow, indivisible extractor/I/O call gets a brief rest.
      cooldown=ms>20 and (ANDROID_RUNTIME and 0.033 or 0.016) or 0
    end
    nextAt=t1+cooldown
    if row.kind~="hard-cache" or not hard.running or not ok or cooldown>0 then break end
  until passes>=8 or clockNow()>=deadline or #queue==0
  return lastOk,#queue,lastLabel,totalMs
end

function S.cancel()
  if PokemonActors and PokemonActors.cancelInformation then PokemonActors.cancelInformation() end
  if PokemonActors and type(PokemonActors.cancelHardCache)=="function" then pcall(PokemonActors.cancelHardCache) end
  if WazaHandlers and type(WazaHandlers.cancelHardCache)=="function" then pcall(WazaHandlers.cancelHardCache) end
  hard.running=false
  informationActiveKey=nil;informationErrors={}
  if PokemonActors and PokemonActors.cancelSourceWork then PokemonActors.cancelSourceWork() end
  queue={};queued={};informationQueued={};informationDesired={};gameRef=nil;nextAt=0;viewerUntil=0;viewerReason=nil
  if PokemonActors and type(PokemonActors.cancelPartyPrewarm)=="function" then pcall(PokemonActors.cancelPartyPrewarm) end
  return true
end

S.resetRuntime=S.cancel

function S.status()
  local labels={}
  for i,row in ipairs(queue) do if i<=12 then labels[#labels+1]=row.label end end
  local ps,ws,movePending=hardModuleStatus()
  local registryPending=math.max(0,#(hard.registryPaths or {})-(tonumber(hard.registryIndex) or 0))
  local hardPending=(tonumber(ps.pending) or 0)+(tonumber(ws.pending) or 0)+movePending+registryPending
  local hardDone=(tonumber(ps.done) or 0)+(tonumber(ws.done) or 0)+(tonumber(hard.registryIndex) or 0)+(tonumber(hard.moveDone) or 0)
  local now=clockNow()
  return {pending=#queue,nextAt=nextAt,android=ANDROID_RUNTIME,interval=INTERVAL,startDelay=START_DELAY,
    lastLabel=stats.lastLabel,lastMs=stats.lastMs,totalMs=stats.totalMs,maxMs=stats.maxMs,
    queued=stats.queued,completed=stats.completed,requeued=stats.requeued,failed=stats.failed,pumps=stats.pumps,labels=labels,
    informationViewer={active=(now or 0)<(viewerUntil or 0),untilTime=viewerUntil,reason=viewerReason,serial=informationSerial},
    hardCache={running=hard.running,paused=hard.paused==true,scope=hard.scope,pending=hardPending,total=hard.total,done=hardDone,failed=(tonumber(ps.failed) or 0)+(tonumber(ws.failed) or 0)+hard.failed,stage=hard.stage,last=hard.last,completed=hard.completed,
      elapsed=hard.startedAt and math.max(0,(hard.finishedAt or now)-hard.startedAt) or 0,
      moveUnavailable=hard.moveUnavailable or 0,cpuSliceMs=ANDROID_RUNTIME and 3 or 6}}
end

return S
