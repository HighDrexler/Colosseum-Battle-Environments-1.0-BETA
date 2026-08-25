local V=...
local mod=V.mod
local G={}

local function call(obj,name,...)
  if not obj or type(obj[name])~="function" then return nil,"unavailable" end
  local ok,a,b=pcall(obj[name],obj,...)
  if not ok then return nil,tostring(a) end
  return a,b
end

function G.info(path)
  local v=select(1,call(mod.cache,"info",path))
  if type(v)=="table" then return v end
  return nil
end

function G.exists(path)
  local v=G.info(path)
  return v and (v.type==nil or v.type=="file") and true or false
end

function G.read(path)
  local data,err=call(mod.cache,"read",path)
  if type(data)=="string" then return data end
  return nil,err or ("generated asset missing: "..tostring(path))
end

function G.write(path,data)
  return call(mod.cache,"write",path,data)
end

function G.delete(path)
  return call(mod.cache,"delete",path)
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

return G
