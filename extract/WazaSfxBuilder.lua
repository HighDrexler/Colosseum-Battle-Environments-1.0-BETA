local V=...
local FSYS=V.FSYS
local Portable=V.PortableMusyX
local S={version=1,rate=32000}

local MARKER="cbe-waza-sfx=1\nsource=GC6E01/common.fsys:snd_se_battle + snd_se_battle.samp\nrate=32000\nrenderer=lua-musyx-sfx-v1\n"
local MARKER_PATH=".cbe-waza-sfx-v1.complete"
local FALLBACK_MARKER_PATH="build/waza_sfx_v1.complete"
local INDEX_PATH="cache/waza/sfx/index.lua"

local function cacheRead(mod,path)
  if not (mod and mod.cache and type(mod.cache.read)=="function") then return nil end
  local ok,v=pcall(mod.cache.read,mod.cache,path);return ok and type(v)=="string" and v or nil
end
local function cacheInfo(mod,path)
  if not (mod and mod.cache and type(mod.cache.info)=="function") then return nil end
  local ok,v=pcall(mod.cache.info,mod.cache,path);return ok and type(v)=="table" and v or nil
end
local function cacheWrite(mod,path,data,generated)
  local ok,a,b=pcall(mod.cache.write,mod.cache,path,data)
  assert(ok and a~=false and a~=nil,"Waza SFX cache write failed: "..path.." / "..tostring(b or a))
  if generated then generated[#generated+1]=path end
  return true
end
local function cacheDelete(mod,path)
  if mod and mod.cache and type(mod.cache.delete)=="function" then pcall(mod.cache.delete,mod.cache,path) end
end
local function wavValid(bytes)
  return type(bytes)=="string" and #bytes>=44 and bytes:sub(1,4)=="RIFF" and bytes:sub(9,12)=="WAVE"
end
local function cachedWavValid(mod,path)
  local info=cacheInfo(mod,path);if not info or (tonumber(info.size) or 0)<44 then return false end
  local bytes=cacheRead(mod,path);return wavValid(bytes)
end
local function memberMap(archive)
  local out={};for _,entry in ipairs(archive:list()) do out[tostring(entry.name):lower()]=entry end;return out
end
local function requiredMember(archive,map,name,archiveName)
  local entry=map[tostring(name):lower()]
  assert(entry,("move audio source %s/%s: member missing"):format(archiveName,name))
  local ok,data=pcall(archive.extract,archive,entry,{maxOutput=64*1024*1024})
  assert(ok,("move audio source %s/%s: %s"):format(archiveName,name,tostring(data)))
  assert(type(data)=="string" and #data>0,("move audio source %s/%s: empty member"):format(archiveName,name))
  return data
end
local function directFile(disc,name)
  local file=disc:file(name);assert(file,"move audio source disc/"..name..": file missing")
  local ok,data=pcall(disc.readFile,disc,file)
  assert(ok,"move audio source disc/"..name..": "..tostring(data))
  assert(type(data)=="string" and #data>0,"move audio source disc/"..name..": empty file")
  return data
end
local function serialize(v)
  local t=type(v)
  if t=="nil" then return "nil" elseif t=="number" then return ("%.17g"):format(v)
  elseif t=="boolean" then return v and "true" or "false" elseif t=="string" then return string.format("%q",v)
  elseif t=="table" then
    local a={"{"};local n=#v
    for i=1,n do a[#a+1]=serialize(v[i]);a[#a+1]="," end
    local keys={};for k in pairs(v) do if not (type(k)=="number" and k>=1 and k<=n and math.floor(k)==k) then keys[#keys+1]=k end end
    table.sort(keys,function(x,y)return tostring(x)<tostring(y) end)
    for _,k in ipairs(keys) do a[#a+1]="["..serialize(k).."]="..serialize(v[k]).."," end
    a[#a+1]="}";return table.concat(a)
  end
  return "nil"
end
local function outputPath(id)return ("cache/waza/sfx/%04d.wav"):format(math.floor(tonumber(id) or 0)) end

function S.ready(mod)
  local marker=cacheRead(mod,MARKER_PATH) or cacheRead(mod,FALLBACK_MARKER_PATH)
  if marker~=MARKER then return false end
  local raw=cacheRead(mod,INDEX_PATH);if type(raw)~="string" then return false end
  local chunk=load(raw,"@generated/"..INDEX_PATH);if not chunk then return false end
  local ok,idx=pcall(chunk);if not ok or type(idx)~="table" or tonumber(idx.version)~=S.version then return false end
  for _,id in ipairs(idx.readyIds or {}) do if not cachedWavValid(mod,outputPath(id)) then return false end end
  return true,idx
end

function S.run(mod,disc,soundIds,progress,generated)
  assert(Portable and type(Portable.prepareSfx)=="function" and type(Portable.renderSfx)=="function","portable MusyX SFX renderer unavailable")
  soundIds=type(soundIds)=="table" and soundIds or {}
  local ids,seen={},{}
  for _,id in ipairs(soundIds) do id=math.floor(tonumber(id) or -1);if id>=0 and id<65536 and not seen[id] then seen[id]=true;ids[#ids+1]=id end end
  table.sort(ids)
  progress=progress or function()end

  local commonFile=assert(disc:file("common.fsys"),"move audio source common.fsys: archive missing")
  local common=FSYS.open(disc,commonFile);local members=memberMap(common)
  local payload={sfx={
    proj=requiredMember(common,members,"snd_se_battle_proj","common.fsys"),
    pool=requiredMember(common,members,"snd_se_battle_pool","common.fsys"),
    sdir=requiredMember(common,members,"snd_se_battle_sdir","common.fsys"),
    samp=directFile(disc,"snd_se_battle.samp"),
  }}
  local ctx=Portable.prepareSfx(payload);payload=nil;common=nil;commonFile=nil
  local index={version=S.version,source="GC6E01 snd_se_battle SFXGroup",rate=S.rate,renderer="lua-musyx-sfx-v1",
    requestedIds=ids,readyIds={},missingIds={},stats={}}
  local total=#ids
  for n,id in ipairs(ids) do
    local path=outputPath(id)
    progress(("MOVE AUDIO %d/%d / GameSound %04d"):format(n,total,id),n-1,math.max(1,total))
    if cachedWavValid(mod,path) then
      index.readyIds[#index.readyIds+1]=id;index.stats[id]={cached=true}
    elseif not Portable.hasSfx(ctx,id) then
      index.missingIds[#index.missingIds+1]=id;index.stats[id]={missing=true,reason="SFX id absent from snd_se_battle SFXGroup"}
    else
      local ok,wav,stats=pcall(Portable.renderSfx,ctx,id,S.rate,function(frame,frames)
        if frame and frames and frames>0 and frame%(S.rate)==0 then progress(("MOVE AUDIO %d/%d / GameSound %04d"):format(n,total,id),n-1+math.min(.95,frame/frames),math.max(1,total)) end
      end)
      if ok and wavValid(wav) and type(stats)=="table" and (tonumber(stats.peak) or 0)>0.000001 then
        local tmp=("cache/waza/sfx/.tmp_%04d.wav"):format(id)
        cacheWrite(mod,tmp,wav,nil)
        local verify=cacheRead(mod,tmp);assert(wavValid(verify),"transaction verify failed for GameSound "..id)
        cacheWrite(mod,path,verify,generated);cacheDelete(mod,tmp)
        index.readyIds[#index.readyIds+1]=id
        index.stats[id]={frames=stats.frames,peak=stats.peak,voices=stats.voices,clipped=stats.clipped}
      else
        index.missingIds[#index.missingIds+1]=id
        index.stats[id]={missing=true,reason=tostring(ok and "renderer produced silence/invalid WAV" or wav)}
        cacheDelete(mod,("cache/waza/sfx/.tmp_%04d.wav"):format(id))
      end
    end
    if n%6==0 and type(collectgarbage)=="function" then pcall(collectgarbage,"step",180) end
  end
  index.ready=#index.readyIds;index.missing=#index.missingIds;index.requested=#ids
  cacheWrite(mod,INDEX_PATH,"return "..serialize(index).."\n",generated)
  cacheWrite(mod,MARKER_PATH,MARKER,generated);cacheWrite(mod,FALLBACK_MARKER_PATH,MARKER,generated)
  progress(("MOVE AUDIO READY %d/%d source IDs"):format(index.ready,index.requested),math.max(1,total),math.max(1,total))
  return {ready=true,complete=index.ready,total=index.requested,missing=index.missing,index=index}
end

S.marker=MARKER
S.markerPath=MARKER_PATH
S.indexPath=INDEX_PATH
return S
