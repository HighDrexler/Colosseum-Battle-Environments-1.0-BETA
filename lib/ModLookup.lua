local M={}
local loader
local remembered={}

function M.find(mod,id)
  local finder=mod and mod.find
  if type(finder)~="function" then return nil end
  local ok,found=pcall(finder,id)
  if ok and found then return found end
  ok,found=pcall(finder,mod,id)
  return ok and found or nil
end

function M.setLoader(value)
  loader=value
  return value~=nil
end

function M.remember(id)
  if type(id)=="string" and id~="" then remembered[id]=true;return true end
  return false
end

local function addLoadedIds(target,value)
  local loaded=value and value.loaded
  if type(loaded)~="table" then return end
  for _,entry in ipairs(loaded) do
    local id=type(entry)=="table" and entry.id or entry
    if type(id)=="string" then target[id]=true end
  end
end

-- Enumerate loaded handles without reaching into another mod's private state.
-- Loader/game status supply public ids; mod.find turns each one into the
-- documented {id,version,exports} handle.
function M.each(mod,game)
  game=game or (mod and mod.game)
  local loaded=game and game.modStatus and game.modStatus.loaded
  local ids={}
  addLoadedIds(ids,{loaded=loaded})
  addLoadedIds(ids,mod and mod.game and mod.game.modStatus)
  if loader and type(loader.status)=="function" then
    local ok,status=pcall(loader.status,loader)
    if ok then addLoadedIds(ids,status) end
  end
  for id in pairs(remembered) do ids[id]=true end
  local ordered={}
  for id in pairs(ids) do ordered[#ordered+1]=id end
  table.sort(ordered)
  local out={}
  for _,id in ipairs(ordered) do
    local handle=M.find(mod,id)
    if handle then out[#out+1]=handle end
  end
  return out
end

return M
