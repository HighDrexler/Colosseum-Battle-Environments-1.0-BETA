local V=...
local Assets=V and V.GeneratedAssets
local A={version=1,source="GC6E01 WazaSequence type-5 GameSound",active={},events={},missing={},cache={}}

local function key(inst,entry)
  return tostring(inst and inst.serial or "?")..":"..tostring(entry and entry.index or "?")
end
local function pathFor(id)
  return ("cache/waza/sfx/%04d.wav"):format(math.max(0,math.floor(tonumber(id) or 0)))
end
local function record(row)
  A.events[#A.events+1]=row
  while #A.events>256 do table.remove(A.events,1) end
end
local function loadSource(id)
  id=math.floor(tonumber(id) or -1)
  if id<0 then return nil,"invalid GameSound id" end
  if A.cache[id]~=nil then return A.cache[id] or nil,A.missing[id] end
  if not (love and love.audio and love.audio.newSource and Assets and Assets.fileData) then
    A.cache[id]=false;A.missing[id]="source-audio runtime unavailable";return nil,A.missing[id]
  end
  local fd,err=Assets.fileData(pathFor(id),("waza_sfx_%04d.wav"):format(id))
  if not fd then A.cache[id]=false;A.missing[id]=tostring(err or "Waza SFX cache missing");return nil,A.missing[id] end
  local ok,src=pcall(love.audio.newSource,fd,"static")
  if not ok or not src then A.cache[id]=false;A.missing[id]=tostring(src);return nil,A.missing[id] end
  A.cache[id]=src;A.missing[id]=nil;return src
end

function A:start(ctx,inst,entry)
  local id=tonumber(entry and entry.soundId)
  if id==nil then return false end
  local k=key(inst,entry)
  local template,why=loadSource(id)
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
  return {version=A.version,source=A.source,active=n,missing=missing,events=A.events,
    assetPolicy="cache/waza/sfx/<GameSound id>.wav; native audio fails open until source macro cache exists"}
end
return A
