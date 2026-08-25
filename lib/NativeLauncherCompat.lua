-- Compatibility bridge for Gen1Recomp launcher importers.
--
-- PR #1616 and newer test builds expose native mod.imports/mod.cache; when
-- those are present this module leaves them untouched. Older launchers may only
-- expose the validated baserom through mod:read plus the legacy per-mod overlay.
-- This fallback keeps CBE testable without ever receiving a host path:
--   * mod.imports reads only the launcher-validated baserom via mod:read.
--   * mod.cache is backed by Gen1Recomp's per-mod legacy filesystem overlay.
--
-- The current mod:read API returns a complete Lua string, so legacy builds
-- buffer the validated ISO/CISO once, lazily, for the extraction transaction.
-- Current launchers use native mod.imports and never take this path.
local M={}

local IMPORT_ID="pokemon_colosseum_usa"
local IMPORT_PATH="baseroms/pokemon_colosseum_usa.iso"
local ACCEPTED_SIZES={[1459978240]=true,[664830528]=true}
local CACHE_ROOT="cbe_generated_v2"

local function safeCachePath(path)
  assert(type(path)=="string" and path~="","cache path is required")
  path=path:gsub("\\","/")
  assert(path:sub(1,1)~="/" and not path:match("^%a:"),"absolute cache path rejected")
  assert(not path:find("../",1,true) and path~=".." and not path:find("/..",1,true),"cache path traversal rejected")
  return CACHE_ROOT.."/"..path
end

function M.install(mod)
  assert(type(mod)=="table","CBE launcher bridge requires mod API")
  local status={
    source="launcher required_imports",
    sourcePath=IMPORT_PATH,
    cache="Gen1Recomp installation-scoped generated cache",
    sourceBuffered=false,
    acceptedSizes={1459978240,664830528},
  }

  if not mod.imports then
    local sourceBlob=nil
    local imports={}

    function imports:info(id)
      if id~=IMPORT_ID then return nil,"unknown import: "..tostring(id) end
      if type(mod.info)~="function" then return nil,"mod:info is unavailable" end
      local info=mod:info(IMPORT_PATH)
      if not info or (info.type and info.type~="file") then
        return nil,"launcher import is not installed"
      end
      if not ACCEPTED_SIZES[tonumber(info.size)] then
        return nil,("launcher import has unexpected size (%s)"):format(tostring(info.size))
      end
      return {id=IMPORT_ID,file=IMPORT_PATH,size=info.size,type="file",validated=true}
    end

    function imports:read(id,offset,length)
      local info,err=self:info(id)
      if not info then return nil,err end
      offset=tonumber(offset);length=tonumber(length)
      if not offset or not length or offset<0 or length<0 or offset%1~=0 or length%1~=0 then
        return nil,"invalid import read range"
      end
      if offset+length>info.size then return nil,"import read exceeds source" end
      if length==0 then return "" end
      if sourceBlob==nil then
        local bytes,readErr=mod:read(IMPORT_PATH)
        if type(bytes)~="string" then return nil,readErr or "launcher import could not be read" end
        if #bytes~=tonumber(info.size) then
          sourceBlob=nil
          return nil,("launcher import read returned %d bytes; expected %d"):format(#bytes,tonumber(info.size))
        end
        sourceBlob=bytes
        status.sourceBuffered=true
      end
      return sourceBlob:sub(offset+1,offset+length)
    end

    function imports:release()
      sourceBlob=nil
      status.sourceBuffered=false
      collectgarbage("collect")
      return true
    end

    rawset(mod,"imports",imports)
    status.importBridge="mod:read(baseroms/...) adapter"
  else
    status.importBridge="native mod.imports"
  end

  if not mod.cache then
    local fs=love and love.filesystem
    assert(fs and type(fs.read)=="function" and type(fs.write)=="function" and type(fs.getInfo)=="function",
      "Gen1Recomp per-mod filesystem compatibility overlay is unavailable")
    local cache={}
    function cache:info(path)
      return fs.getInfo(safeCachePath(path))
    end
    function cache:read(path)
      return fs.read(safeCachePath(path))
    end
    function cache:write(path,data)
      assert(type(data)=="string","cache writes require string bytes")
      return fs.write(safeCachePath(path),data)
    end
    function cache:delete(path)
      local full=safeCachePath(path)
      if not fs.getInfo(full) then return true end
      local ok,err=fs.remove(full)
      if ok==false then return false,err end
      return true
    end
    rawset(mod,"cache",cache)
    status.cacheBridge="legacy filesystem overlay adapter"
  else
    status.cacheBridge="native mod.cache"
  end

  return status
end

return M
