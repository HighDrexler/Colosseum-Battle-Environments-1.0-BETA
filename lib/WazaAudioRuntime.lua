local V=...
local Assets=V and V.GeneratedAssets
local A={version=2,source="GC6E01 WazaSequence type-5 GameSound + snd_se_battle SFXGroup",active={},events={},missing={},cache={},presence={},use={},useSerial=0,cacheLimit=32}

local function key(inst,entry)
  return tostring(inst and inst.serial or "?")..":"..tostring(entry and entry.index or "?")
end
local function pathFor(id)
  return ("cache/waza/sfx/%04d.wav"):format(math.max(0,math.floor(tonumber(id) or 0)))
end
local loadSource
local function record(row)
  A.events[#A.events+1]=row
  while #A.events>256 do table.remove(A.events,1) end
end
local function touch(id)
  A.useSerial=(A.useSerial or 0)+1;A.use[id]=A.useSerial
end
local function trimCache()
  local count=0;for _,src in pairs(A.cache) do if src then count=count+1 end end
  local limit=tonumber(A.cacheLimit) or 32
  while count>limit do
    local victim,stamp
    for id,src in pairs(A.cache) do
      if src then
        local busy=false
        for _,row in pairs(A.active) do if row and row.source==src then busy=true;break end end
        local u=tonumber(A.use[id]) or 0
        if not busy and (stamp==nil or u<stamp) then victim=id;stamp=u end
      end
    end
    if victim==nil then break end
    local src=A.cache[victim]
    if src and type(src.stop)=="function" then pcall(src.stop,src) end
    A.cache[victim]=nil;A.use[victim]=nil;count=count-1
  end
end

function A.has(id)
  id=math.floor(tonumber(id) or -1);if id<0 then return false end
  if A.presence[id]~=nil then return A.presence[id] end
  if not (Assets and Assets.info) then A.presence[id]=false;return false end
  local info=Assets.info(pathFor(id));local ok=type(info)=="table" and (tonumber(info.size) or 0)>=44
  if ok and Assets.read then
    local bytes=Assets.read(pathFor(id));ok=type(bytes)=="string" and #bytes>=44 and bytes:sub(1,4)=="RIFF" and bytes:sub(9,12)=="WAVE"
  end
  A.presence[id]=ok and true or false
  return A.presence[id]
end

local function specSoundIds(spec)
  local out,seen={},{}
  for _,row in ipairs(type(spec)=="table" and (spec.sounds or {}) or {}) do
    -- Only retail typed Waza type-5 rows are authoritative GameSound commands.
    -- Do not let any legacy/heuristic sound metadata make CBE suppress native
    -- audio for a move whose source SE coverage is not actually proven.
    local id=(type(row)=="table" and tonumber(row.sourceType)==5) and tonumber(row.soundId) or nil
    if id and id>=0 then id=math.floor(id);if not seen[id] then seen[id]=true;out[#out+1]=id end end
  end
  table.sort(out);return out
end
function A.completeForSpec(spec)
  local ids=specSoundIds(spec);if #ids==0 then return false,ids end
  for _,id in ipairs(ids) do if not A.has(id) then return false,ids end end
  return true,ids
end
function A.prewarmSpec(spec)
  local ready,ids=A.completeForSpec(spec);if not ready then return false,ids end
  local loaded=0
  for _,id in ipairs(ids) do local src=select(1,loadSource(id));if src then loaded=loaded+1 end end
  return loaded==#ids,ids
end
A.readyForSpec=A.prewarmSpec
loadSource=function(id)
  id=math.floor(tonumber(id) or -1)
  if id<0 then return nil,"invalid GameSound id" end
  if A.cache[id]~=nil then if A.cache[id] then touch(id) end;return A.cache[id] or nil,A.missing[id] end
  if not (love and love.audio and love.audio.newSource and Assets and Assets.fileData) then
    A.cache[id]=false;A.missing[id]="source-audio runtime unavailable";return nil,A.missing[id]
  end
  local fd,err=Assets.fileData(pathFor(id),("waza_sfx_%04d.wav"):format(id))
  if not fd then A.cache[id]=false;A.missing[id]=tostring(err or "Waza SFX cache missing");return nil,A.missing[id] end
  local ok,src=pcall(love.audio.newSource,fd,"static")
  if not ok or not src then A.cache[id]=false;A.missing[id]=tostring(src);return nil,A.missing[id] end
  A.cache[id]=src;A.missing[id]=nil;touch(id);trimCache();return src
end

function A:start(ctx,inst,entry)
  local id=tonumber(entry and entry.soundId)
  if id==nil then return false end
  local k=key(inst,entry)
  -- All-or-native audio ownership: never layer one successfully rendered
  -- GameSound over the GB/GBC animation when another source sound required by
  -- the same move is missing/unloadable. Either the complete authored source
  -- set is ready and CBE owns it, or every type-5 row stays silent and the
  -- engine's native move audio remains the audible fail-open path.
  local sourceSetReady=A.readyForSpec(inst and inst.spec)
  local template,why
  if sourceSetReady then template,why=loadSource(id) else why="complete source GameSound set unavailable" end
  local src
  if template and type(template.clone)=="function" then
    local ok,v=pcall(template.clone,template);if ok then src=v end
  end
  src=src or template
  local row={key=k,serial=inst and inst.serial,soundId=id,mode=tonumber(entry.soundMode) or 0,
    param=entry.soundParam,frame=inst and inst.frame or 0,source=src,asset=pathFor(id),fallback=not src and why or nil}
  A.active[k]=row;record({event="start",serial=row.serial,frame=row.frame,soundId=id,mode=row.mode,asset=row.asset,sourceReady=src and true or false})
  if src and type(src.play)=="function" then pcall(src.play,src) end
  -- Claim the Waza entry even when the source macro cache is not built yet: the
  -- scheduler and source id are authoritative, while native battle audio remains
  -- the fail-open audible path until the MusyX macro compiler supplies the WAV.
  return true
end

function A:update(ctx,inst,entry,frame,state)
  local row=A.active[key(inst,entry)]
  if not row then return "done" end
  if not row.source then return "done" end
  if type(row.source.isPlaying)=="function" then
    local ok,playing=pcall(row.source.isPlaying,row.source)
    if ok and playing then return true end
  end
  return "done"
end

function A:finish(ctx,inst,entry)
  local k=key(inst,entry);local row=A.active[k]
  if row then record({event="finish",serial=row.serial,frame=inst and inst.frame,soundId=row.soundId}) end
  A.active[k]=nil;return true
end
function A:cancel(ctx,inst,entry)
  local k=key(inst,entry);local row=A.active[k]
  if row and row.source and type(row.source.stop)=="function" then pcall(row.source.stop,row.source) end
  if row then record({event="cancel",serial=row.serial,frame=inst and inst.frame,soundId=row.soundId}) end
  A.active[k]=nil;return true
end
function A:finishAll()
  for _,row in pairs(A.active) do if row.source and type(row.source.stop)=="function" then pcall(row.source.stop,row.source) end end
  A.active={};return true
end
function A:status()
  local n=0;for _ in pairs(A.active) do n=n+1 end
  local missing=0;for _ in pairs(A.missing) do missing=missing+1 end
  local cached=0;for _,src in pairs(A.cache) do if src then cached=cached+1 end end
  return {version=A.version,source=A.source,active=n,missing=missing,cached=cached,cacheLimit=A.cacheLimit,events=A.events,
    assetPolicy="cache/waza/sfx/<GameSound id>.wav; bounded static-source LRU; native move audio suppressed only when every Waza GameSound id for the active source move is cached"}
end
return A
