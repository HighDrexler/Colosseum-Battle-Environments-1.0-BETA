-- Compatibility bridge for Battle Art / Dramatic Shape battle staging.
--
-- Colosseum Battle Environments owns the WORLD presentation whenever its
-- arena switch is on: arena, camera, trainers and stage choreography all stay
-- inside CBE on both generations. When COLOSSEUM MODELS is also ON, CBE's own
-- GC6E01 Pokemon actor service owns the battlers too. When models are OFF,
-- compatible external actor/sprite providers may still supply Pokemon through
-- CBE's portable seams, but a private Battle Art full-frame 3D world may never
-- replace the CBE arena.
--
-- This wrapper changes no Battle Art setting. COLOSSEUM ARENAS OFF restores
-- Battle Art's normal begin() behavior immediately.
local V=...
local B={installed=false,owner=nil,owners={},reason=nil}
local ModLookup=V.ModLookup
local IDS={"BATTLE_ART_VOXEL_GEN2","BATTLE_ART_VOXEL_FORK","DRAMATIC_SHAPE","DRAMALESS_SHAPE","scott_kanto_dramatic"}

local function arenaOwnsStage(state,battle)
  local C=V and V.ArenaCatalog
  local game=(battle and battle.game) or (state and state.game)
      or (V.mod and V.mod.game)
  if C and type(C.enabled)=="function" then
    local ok,value=pcall(C.enabled,game)
    if ok then return value~=false end
  end
  return true
end

local function requireOverworld(handle)
  local lib=handle and handle.exports and handle.exports.lib
  if not (type(lib)=="table" and type(lib.require)=="function") then
    return nil,"no exports.lib.require"
  end
  local ok,ow=pcall(function() return lib.require("OverworldBattle") end)
  if not ok or type(ow)~="table" then return nil,"OverworldBattle unavailable" end
  return ow
end

function B.install()
  local installedAny=false
  local reasons={}
  B.owners=B.owners or {}

  -- Scan every loaded mod in addition to the known Battle Art ids. CBE's
  -- ownership contract is about CAPABILITY, not branding: any mod exporting
  -- the conventional OverworldBattle full-stage compositor is suppressed while
  -- Colosseum Arenas is ON. This prevents forks/renames from silently bypassing
  -- the bridge and reverting Gen I to a Battle Art battle.
  local handles,seen={},{}
  local function add(handle,id)
    id=tostring(id or (handle and handle.id) or "")
    if handle and id~="" and id~=tostring(V.mod and V.mod.id or "") and not seen[id] then
      seen[id]=true;handles[#handles+1]={handle=handle,id=id}
    end
  end
  for _,id in ipairs(IDS) do add(ModLookup.find(V.mod,id),id) end
  if ModLookup and type(ModLookup.each)=="function" then
    local ok,list=pcall(ModLookup.each,V.mod,V.mod and V.mod.game)
    if ok and type(list)=="table" then
      for _,handle in ipairs(list) do add(handle,handle and handle.id) end
    end
  end

  for _,entry in ipairs(handles) do
    local handle,id=entry.handle,entry.id
    local ow,why=requireOverworld(handle)
    if ow and type(ow.begin)=="function" then
      if type(ow.__cbeArenaOriginalBegin)~="function" then
        local original=ow.begin
        ow.__cbeArenaOriginalBegin=original
        ow.begin=function(state,battle)
          if arenaOwnsStage(state,battle) then
            -- Absolute stage ownership: external mods may provide resolved
            -- Pokemon art/portable battleActors, never a second arena/camera.
            if type(ow.finish)=="function" then pcall(ow.finish) end
            return false
          end
          return original(state,battle)
        end
      end
      B.owners[id]=true
      B.owner=B.owner or id
      installedAny=true
    elseif seen[id] and (id=="BATTLE_ART_VOXEL_GEN2" or id=="BATTLE_ART_VOXEL_FORK" or id=="DRAMATIC_SHAPE"
        or id=="DRAMALESS_SHAPE" or id=="scott_kanto_dramatic") then
      reasons[#reasons+1]=id..":"..tostring(why)
    end
  end
  B.installed=installedAny
  if installedAny then
    B.reason="CBE stage ownership bridge"
  elseif #reasons>0 then
    B.reason=table.concat(reasons,"; ")
  else
    B.reason="Battle Art not installed"
  end
  return installedAny
end

function B.status()
  local owners={}
  for id in pairs(B.owners or {}) do owners[#owners+1]=id end
  table.sort(owners)
  return {installed=B.installed,owner=B.owner,owners=owners,reason=B.reason,
    contract="CBE arena/camera/trainer world is authoritative; portable external actors only when CBE Models are OFF"}
end

return B
