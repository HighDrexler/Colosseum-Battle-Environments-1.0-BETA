-- Compatibility bridge for Battle Art / Dramatic Shape battle staging.
--
-- Colosseum Battle Environments owns only the WORLD presentation when its
-- master arena switch is on.  Battle Art remains free to own Pokemon artwork:
-- its existing sprite hooks still resolve STATIC / ANIMATED / ROM / MODDED
-- choices exactly as the user configured them.  The only thing suppressed is
-- Battle Art's *own* overworld-arena staging, which otherwise claims the whole
-- battle surface and prevents StadiumBattleFX from composing our selected
-- external arena underneath those sprites.
--
-- The wrapper is deliberately conditional rather than changing another mod's
-- setting.  COLOSSEUM ARENAS OFF immediately restores Battle Art's normal
-- begin() behavior without rewriting the user's 3D-BTL option.
local V=...
local B={installed=false,owner=nil,reason=nil}
local ModLookup=V.ModLookup
local IDS={"BATTLE_ART_VOXEL_FORK","DRAMATIC_SHAPE"}

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
  if B.installed then return true end
  for _,id in ipairs(IDS) do
    local handle=ModLookup.find(V.mod,id)
    if handle then
      local ow,why=requireOverworld(handle)
      if ow and type(ow.begin)=="function" then
        -- If another hot reload of this mod already installed the seam, reuse
        -- it instead of stacking wrappers.
        if type(ow.__cbeArenaOriginalBegin)=="function" then
          B.installed=true; B.owner=id; B.reason="existing bridge"
          return true
        end
        local original=ow.begin
        ow.__cbeArenaOriginalBegin=original
        ow.begin=function(state,battle)
          if arenaOwnsStage(state,battle) then
            -- Defensive cleanup for a session that may have been staged before
            -- the user turned our arenas on. finish() is a no-op without one.
            if type(ow.finish)=="function" then pcall(ow.finish) end
            return false
          end
          return original(state,battle)
        end
        B.installed=true; B.owner=id; B.reason="arena-only staging bridge"
        return true
      end
      B.reason=why
    end
  end
  B.reason=B.reason or "Battle Art not installed"
  return false
end

function B.status()
  return {installed=B.installed,owner=B.owner,reason=B.reason,
    contract="arena-only; Pokemon art remains externally resolved"}
end

return B
