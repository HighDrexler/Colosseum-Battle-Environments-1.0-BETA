local V = ...
local Trainer=V.Trainer
local PlayerTrainer=V.PlayerTrainer
-- Native trainer-picture suppression for the Colosseum world presentation.
--
-- Pokemon picture ownership is already handled by the active model/current-
-- sprite host.  This module exists specifically for the Gen1 trainer pictures
-- shown during battle entry.  Suppression is per-side and capability-driven:
-- CBE hides a native trainer only when its matching 3D trainer can actually
-- render. Missing ROM cache data therefore fails open to the engine art instead
-- of producing an empty trainer back-line.
local N = {
  installed=false, activeBattle=nil, error=nil,
  picsWrapper=nil,
  installs=0,
}

local function presentation(battle)
  local compat=V.GenerationCompat
  return compat and compat.prepare(battle) or battle
end

local function sameBattle(a,b)
  local compat=V.GenerationCompat
  return (compat and compat.matches(a,b)) or a==b
end

local function suppress(battle)
  battle=presentation(battle)
  if type(battle)~="table" or not sameBattle(battle,N.activeBattle) then return false end
  if battle.safari or battle.demo then return false end
  return battle.kind=="trainer" or battle.kind=="wild"
end

local function providerVisible(provider,battle)
  if not (provider and type(provider.shouldRender)=="function") then return false end
  local ok,value=pcall(provider.shouldRender,provider,{battle=battle,game=battle and battle.game})
  return ok and value==true
end

local function trainerMask(battle)
  battle=presentation(battle)
  if not suppress(battle) then return false,false end
  local hidePlayer=battle.showPlayerBack and providerVisible(PlayerTrainer,battle) or false
  local hideEnemy=battle.showEnemyTrainer and providerVisible(Trainer,battle) or false
  return hidePlayer,hideEnemy
end

local function wrapMethod(BattleState,name,slot,make)
  local current=BattleState[name]
  if type(current)~="function" then return true end
  if current==N[slot] then return true end
  local wrapper=make(current)
  N[slot]=wrapper
  BattleState[name]=wrapper
  return true
end

function N.install(force)
  local req=V.engineRequire or require
  local ok,BattleState=pcall(req,"src.battle.BattleState")
  if not ok or type(BattleState)~="table" then
    N.error=tostring(BattleState); return false,N.error
  end

  -- Re-chain against whatever the final UI / Stadium host installed.  The
  -- wrapper is intentionally scoped by activeBattle, so outside this arena it
  -- is a transparent pass-through.
  wrapMethod(BattleState,"drawPicsLayer","picsWrapper",function(inner)
    return function(self,slide,sx,sy,onlySide,skipMenuClip)
      local hidePlayer,hideEnemy=trainerMask(self)
      if not hidePlayer and not hideEnemy then
        return inner(self,slide,sx,sy,onlySide,skipMenuClip)
      end

      -- Respect explicit one-side draws used by widescreen/model hosts.
      if onlySide=="player" then
        if hidePlayer then return end
        return inner(self,slide,sx,sy,onlySide,skipMenuClip)
      elseif onlySide=="enemy" then
        if hideEnemy then return end
        return inner(self,slide,sx,sy,onlySide,skipMenuClip)
      end

      if hidePlayer and hideEnemy then return end
      -- BattleState's onlySide values name the side to KEEP.
      if hidePlayer then
        return inner(self,slide,sx,sy,"enemy",skipMenuClip)
      end
      return inner(self,slide,sx,sy,"player",skipMenuClip)
    end
  end)

  -- Never hide the stock status HUD here. The replacement Colosseum UI is an
  -- optional integration, so making arena ownership suppress HP/name panels
  -- would turn it into an undeclared functional dependency. A UI mod that is
  -- actually present owns its own HUD replacement hook; CBE-alone deliberately
  -- keeps the complete engine interface.

  N.installed=true; N.error=nil; N.installs=N.installs+1
  return true
end

function N:begin(ctx)
  local battle=type(ctx)=="table" and (ctx.battle or (ctx.kind and ctx)) or nil
  battle=presentation(battle)
  if battle and not battle.safari and not battle.demo then
    self.activeBattle=battle
    -- The hook is installed once at mod load. StadiumBattleFX may wrap it on
    -- the outside at battle start; keeping our suppressor inside that stable
    -- chain avoids wrapper growth across repeated battles.
    if not self.installed then self.install() end
  end
end

function N:finish(ctx)
  local battle=type(ctx)=="table" and (ctx.battle or (ctx.kind and ctx)) or nil
  battle=presentation(battle)
  if not battle or sameBattle(self.activeBattle,battle) then self.activeBattle=nil end
end

function N:hides(battle,side)
  local hidePlayer,hideEnemy=trainerMask(presentation(battle))
  return side=="player" and hidePlayer or side=="enemy" and hideEnemy or false
end

function N.status()
  return {
    installed=N.installed,
    active=N.activeBattle~=nil,
    error=N.error,
    installs=N.installs,
    scope="capability-driven-native-trainer-picture-only; stock-hud-fails-open",
  }
end
return N
