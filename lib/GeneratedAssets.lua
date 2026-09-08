local V=...
local mod=V.mod
local G={schema=2}

-- Hard-cache registry. mod.cache.info() can be surprisingly expensive on
-- portable/Android backends when hundreds of generated paths are probed during
-- scene/model setup. Hard Cache Save persists the file metadata CBE has already
-- validated so later sessions can answer those existence/size probes without
-- repeatedly crossing the host cache boundary. Every CBE write/delete updates
-- this registry in memory; reset/rebuild explicitly removes the persisted copy.
local INFO_REGISTRY_PATH="build/hard_cache_registry_v1.lua"
local INFO_REGISTRY_REVISION=1
local infoCache={}
local infoRegistry={}
local registryCount=0
local infoStats={host=0,memory=0,registry=0,writes=0,deletes=0}

local function call(obj,name,...)
  if not obj or type(obj[name])~="function" then return nil,"unavailable" end
  local ok,a,b=pcall(obj[name],obj,...)
  if not ok then return nil,tostring(a) end
  return a,b
end

local function loadRegistry()
  local raw=select(1,call(mod and mod.cache,"read",INFO_REGISTRY_PATH))
  if type(raw)~="string" then return end
  local chunk=load(raw,"@generated/"..INFO_REGISTRY_PATH)
  if not chunk then return end
  local ok,value=pcall(chunk)
  if not ok or type(value)~="table" or tonumber(value.revision)~=INFO_REGISTRY_REVISION or type(value.entries)~="table" then return end
  for path,info in pairs(value.entries) do
    if type(path)=="string" and type(info)=="table" then
      local row={type=info.type or "file"}
      if tonumber(info.size) then row.size=tonumber(info.size) end
      if not infoRegistry[path] then registryCount=registryCount+1 end
      infoRegistry[path]=row
    end
  end
end
loadRegistry()

local function remember(path,info)
  if type(path)~="string" or path=="" then return end
  if type(info)=="table" then
    local row={type=info.type or "file"}
    if tonumber(info.size) then row.size=tonumber(info.size) end
    if not infoRegistry[path] then registryCount=registryCount+1 end
    infoCache[path]=row;infoRegistry[path]=row
  else
    -- Never persist a negative lookup. Several extractors intentionally create
    -- lazy assets through the host cache after an earlier probe in the same
    -- process; only positive metadata is safe to memoize across those seams.
    if infoRegistry[path] then registryCount=registryCount-1 end
    infoCache[path]=nil;infoRegistry[path]=nil
  end
end

local function q(v) return string.format("%q",tostring(v)) end

function G.info(path)
  path=tostring(path or "")
  local cached=infoCache[path]
  if cached~=nil then infoStats.memory=infoStats.memory+1;return cached or nil end
  local registered=infoRegistry[path]
  if registered then infoCache[path]=registered;infoStats.registry=infoStats.registry+1;return registered end
  local v=select(1,call(mod.cache,"info",path));infoStats.host=infoStats.host+1
  if type(v)=="table" then remember(path,v);return infoCache[path] end
  -- Do not memoize a miss for the whole process. Extractor modules may create
  -- generated files through the host cache directly after an earlier probe.
  return nil
end

function G.revalidateInfo(path)
  path=tostring(path or "")
  local v=select(1,call(mod.cache,"info",path));infoStats.host=infoStats.host+1
  if type(v)=="table" then remember(path,v);return infoCache[path] end
  remember(path,nil)
  return nil
end

function G.exists(path)
  local v=G.info(path)
  return v and (v.type==nil or v.type=="file") and true or false
end

function G.read(path)
  local data,err=call(mod.cache,"read",path)
  if type(data)=="string" then
    -- A successful read is authoritative, including after an extractor writes
    -- through mod.cache directly. Do not preserve an obsolete registered size.
    remember(tostring(path),{type="file",size=#data})
    return data
  end
  remember(tostring(path),nil)
  return nil,err or ("generated asset missing: "..tostring(path))
end

function G.write(path,data)
  local a,b=call(mod.cache,"write",path,data)
  if a~=nil and a~=false then
    remember(tostring(path),{type="file",size=type(data)=="string" and #data or nil});infoStats.writes=infoStats.writes+1
  else
    remember(tostring(path),nil)
  end
  return a,b
end

function G.delete(path)
  local a,b=call(mod.cache,"delete",path)
  remember(tostring(path),nil);infoStats.deletes=infoStats.deletes+1
  return a,b
end

function G.readLua(path)
  local src,err=G.read(path)
  if not src then return nil,err end
  local chunk,loadErr=load(src,"@generated/"..tostring(path))
  if not chunk then return nil,loadErr end
  local ok,value=pcall(chunk)
  if not ok then return nil,value end
  return value
end

-- Runtime audio definitions may accept a FileData object anywhere LÖVE accepts
-- a file argument.  This lets generated WAV data remain in the engine-owned
-- installation cache instead of exposing a host filesystem path to the mod.
function G.fileData(path,name)
  local bytes,err=G.read(path)
  if not bytes then return nil,err end
  if not (love and love.filesystem and love.filesystem.newFileData) then
    return nil,"love.filesystem.newFileData unavailable"
  end
  local ok,fd=pcall(love.filesystem.newFileData,bytes,name or tostring(path):match("[^/]+$") or "generated.bin")
  if not ok then return nil,tostring(fd) end
  return fd
end

function G.packageRead(path)
  if not (mod and type(mod.read)=="function") then return nil,"mod.read unavailable" end
  local ok,data=pcall(mod.read,mod,path)
  if not ok then return nil,tostring(data) end
  return data
end

function G.packageLua(path,arg)
  local src,err=G.packageRead(path)
  if not src then return nil,err end
  local chunk,loadErr=load(src,"@"..tostring(mod.path or mod.id).."/"..tostring(path))
  if not chunk then return nil,loadErr end
  local ok,value=pcall(chunk,arg)
  if not ok then return nil,value end
  return value
end

function G.invalidateInfo(path)
  if path==nil then infoCache={} else infoCache[tostring(path)]=nil end
  return true
end

function G.saveInfoRegistry(extra)
  local keys={}
  for path,info in pairs(infoRegistry) do
    if path~=INFO_REGISTRY_PATH and type(info)=="table" then keys[#keys+1]=path end
  end
  table.sort(keys)
  local out={"return {revision=",tostring(INFO_REGISTRY_REVISION),",entries={"}
  for _,path in ipairs(keys) do
    local info=infoRegistry[path]
    out[#out+1]="["..q(path).."]={type="..q(info.type or "file")
    if tonumber(info.size) then out[#out+1]=",size="..tostring(math.floor(tonumber(info.size))) end
    out[#out+1]="},"
  end
  out[#out+1]="},meta={"
  if type(extra)=="table" then
    for k,v in pairs(extra) do
      if type(k)=="string" and (type(v)=="string" or type(v)=="number" or type(v)=="boolean") then
        out[#out+1]="["..q(k).."]="..(type(v)=="string" and q(v) or tostring(v))..","
      end
    end
  end
  out[#out+1]="}}\n"
  local body=table.concat(out)
  local a,b=call(mod.cache,"write",INFO_REGISTRY_PATH,body)
  if a~=nil and a~=false then remember(INFO_REGISTRY_PATH,{type="file",size=#body});return true,b,#keys end
  return false,b or "registry write failed",#keys
end

function G.clearInfoRegistry(deletePersisted)
  infoCache={};infoRegistry={};registryCount=0
  if deletePersisted~=false then call(mod.cache,"delete",INFO_REGISTRY_PATH) end
  return true
end

function G.registryStatus()
  return {path=INFO_REGISTRY_PATH,revision=INFO_REGISTRY_REVISION,entries=registryCount,hostProbes=infoStats.host,memoryHits=infoStats.memory,registryHits=infoStats.registry,writes=infoStats.writes,deletes=infoStats.deletes}
end

return G
