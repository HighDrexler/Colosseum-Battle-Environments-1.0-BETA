-- Installation-scoped cache quality. No save edits, live DSP, or audio deletion.
-- AUTO affects NEW renders only: Android/iOS use FAST; other hosts use HIGH.
-- Existing v9 WAVs remain playable until the user explicitly requests an update.
local F={version=1,root="build/audio_fidelity_v1/"}
F.configPath=F.root.."quality.txt"
F.requestPath=F.root.."request.txt"
F.reportPath=F.root.."status.txt"
local function read(mod,path)
  if not (mod and mod.cache and type(mod.cache.read)=="function") then return nil end
  local ok,b=pcall(mod.cache.read,mod.cache,path)
  return ok and type(b)=="string" and b or nil
end
local function write(mod,path,bytes)
  assert(mod and mod.cache and type(mod.cache.write)=="function","audio cache unavailable")
  local ok,a,b=pcall(mod.cache.write,mod.cache,path,bytes)
  assert(ok and a~=nil and a~=false,"audio fidelity write failed: "..path.." / "..tostring(b or a))
  assert(read(mod,path)==bytes,"audio fidelity readback failed: "..path)
end
local function remove(mod,path)
  assert(mod and mod.cache and type(mod.cache.delete)=="function","audio cache delete unavailable")
  if read(mod,path)==nil then return true end
  local ok,a=pcall(mod.cache.delete,mod.cache,path)
  assert(ok and a~=false and read(mod,path)==nil,"audio fidelity delete failed: "..path)
  return true
end
local function osName()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,n=pcall(love.system.getOS);if ok then return tostring(n or "") end
  end
  return "Unknown"
end
function F.preference(mod)
  local raw=read(mod,F.configPath)
  local q=raw and raw:match("^cbe%-audio%-quality=1\nquality=(%a+)\n$")
  return (q=="fast" or q=="high") and q or "auto"
end
function F.resolve(mod,platform)
  local q=F.preference(mod)
  if q~="auto" then return q end
  local name=platform or osName()
  return (name=="Android" or name=="iOS") and "fast" or "high"
end
function F.setPreference(mod,quality)
  if quality~="auto" and quality~="fast" and quality~="high" then return false,"invalid audio quality" end
  local ok,why=pcall(write,mod,F.configPath,"cbe-audio-quality=1\nquality="..quality.."\n")
  return ok,not ok and tostring(why) or nil
end
function F.pending(mod)
  local raw=read(mod,F.requestPath)
  local q=raw and raw:match("^cbe%-audio%-update=1\nquality=(%a+)\n$")
  return (q=="fast" or q=="high") and q or nil
end
function F.request(mod)
  local q=F.resolve(mod)
  if F.pending(mod)==q then return true,q end
  local ok,why=pcall(write,mod,F.requestPath,"cbe-audio-update=1\nquality="..q.."\n")
  return ok,ok and q or tostring(why)
end
function F.cancelRequest(mod)
  local ok,why=pcall(remove,mod,F.requestPath)
  return ok,not ok and tostring(why) or nil
end
function F.identity(quality)return quality=="fast" and "linear-v9-notes-v2-headroom-v1" or "lanczos4-256-v1-notes-v2-headroom-v1" end
function F.checksum(bytes)
  -- Adler-32, reducing modulo per block. Accumulators remain exact Lua doubles.
  local a,b=1,0
  for start=1,#bytes,4096 do
    for i=start,math.min(#bytes,start+4095) do a=a+bytes:byte(i);b=b+a end
    a=a%65521;b=b%65521
  end
  return string.format("%08x",b*65536+a)
end
function F.stampPath(path)
  assert(type(path)=="string" and path:match("^assets/audio/[%w_./%-]+$") and not path:find("..",1,true),"invalid audio path")
  return F.root.."assets/"..path:sub(14)..".stamp"
end
function F.stamp(path,bytes,quality)
  return "cbe-audio-fidelity=1\nrenderer="..F.identity(quality).."\npath="..path.."\nbytes="..#bytes.."\nadler32="..F.checksum(bytes).."\n"
end
function F.assetReady(mod,path,bytes,quality)
  local stamp=read(mod,F.stampPath(path))
  if not stamp or not stamp:find("renderer="..F.identity(quality).."\n",1,true) then return false end
  bytes=bytes or read(mod,path)
  return type(bytes)=="string" and #bytes>=44 and stamp==F.stamp(path,bytes,quality)
end
function F.record(mod,path,bytes,quality,generated)
  local stamp=F.stampPath(path);write(mod,stamp,F.stamp(path,bytes,quality))
  if generated then generated[#generated+1]=stamp end
end
function F.status(mod)
  local raw=read(mod,F.reportPath) or ""
  return {preference=F.preference(mod),effective=F.resolve(mod),pending=F.pending(mod),
    state=raw:match("state=([^\n]+)"),complete=tonumber(raw:match("complete=(%d+)")),
    total=tonumber(raw:match("total=(%d+)")),lastQuality=raw:match("quality=(%a+)"),
    error=raw:match("error=([^\n]+)")}
end
F.read,F.write,F.remove=read,write,remove
return F
