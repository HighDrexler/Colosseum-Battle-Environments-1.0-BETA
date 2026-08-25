local C={}

-- Arena selection stays centralized in this module. The
-- StadiumBattleFX provider is acquired once per battle; the selected id is
-- resolved here before any cache is loaded and is then stamped onto the arena
-- record for that battle.  No later render/update call is allowed to choose a
-- different environment.
local runtimeSelected=nil
-- Explicit menu choices are staged for the NEXT arena acquisition. This is
-- separate from the save object because Gen1Recomp can hand providers a battle
-- context whose game/save reference was captured before the BATTLE overlay wrote
-- the new value. A staged manual choice must win exactly once.
local pendingSelected=nil
local boundBattle=nil
local boundSelected=nil
local boundResolved=nil
local lastRandomArena=nil

local DEFINITIONS={
  water={
    id="water",label="WATER COLOSSEUM",cache="cache/M1_water_cache.lua",ready=true,
    stageScale=0.25,stageYaw=0,sceneRadiusRaw=430,maxGroupSpanRaw=920,vertexRadiusRaw=415,
    pokemon={player={0,14.5},enemy={0,-14.5}},figureScale=0.40,
    trainers={player={13.2,25.8},enemy={-13.2,-25.8}},
    trainerScale={player=0.425,enemy=0.205},
    camera={side=54,back=13,height=22,lookX=0,lookY=5.8,frameH=47},
    backdrop={top={0.025,0.075,0.145},bottom={0.13,0.25,0.34}},
    profile="water",crowd="stadium",
  },
  orre_colosseum={
    id="orre_colosseum",label="ORRE COLOSSEUM",cache="cache/orre_colosseum_cache.lua",ready=true,
    stageScale=0.25,stageYaw=0,sceneRadiusRaw=560,maxGroupSpanRaw=1600,vertexRadiusRaw=550,
    pokemon={player={-4.4,16.8},enemy={4.4,-16.8}},figureScale=0.335,
    trainers={player={10.8,24.8},enemy={-10.8,-24.8}},
    trainerScale={player=0.405,enemy=0.198},
    camera={side=56,back=17,height=18.5,lookX=0,lookY=7.0,frameH=50},
    backdrop={top={0.10,0.31,0.63},bottom={0.72,0.84,0.93}},
    profile="orre",crowd="source-hsd-exact",
  },
  outdoor_wild={
    id="outdoor_wild",label="ORRE WILDLANDS",cache="cache/outdoor_wild_cache.lua",ready=true,
    stageScale=0.25,stageYaw=0,sceneRadiusRaw=620,maxGroupSpanRaw=1350,vertexRadiusRaw=610,
    pokemon={player={-4.5,18.0},enemy={4.5,-18.0}},figureScale=0.365,
    trainers={player={14.0,29.5},enemy={-14.0,-29.5}},
    trainerScale={player=0.425,enemy=0.205},
    camera={side=59,back=18,height=22,lookX=0,lookY=5.3,frameH=51},
    backdrop={top={0.08,0.31,0.65},bottom={0.68,0.84,0.76}},
    profile="outdoor",crowd="none",
  },
  realgam_colosseum={
    id="realgam_colosseum",label="REALGAM COLOSSEUM",cache="cache/realgam_colosseum_cache.lua",ready=true,
    stageScale=0.25,stageYaw=0,sceneRadiusRaw=600,maxGroupSpanRaw=1300,vertexRadiusRaw=590,
    pokemon={player={-4.8,17.5},enemy={4.8,-17.5}},figureScale=0.35,
    trainers={player={12.5,27.0},enemy={-12.5,-27.0}},
    trainerScale={player=0.405,enemy=0.198},
    camera={side=58,back=17,height=20.5,lookX=0,lookY=6.3,frameH=51},
    backdrop={top={0.43,0.64,0.82},bottom={0.72,0.84,0.93}},
    profile="realgam",crowd="source-hsd-exact",
  },
  mt_battle_summit={
    id="mt_battle_summit",label="MT. BATTLE SUMMIT",cache="cache/D2_mt_battle_platform100_cache.lua",ready=true,
    stageScale=0.25,stageYaw=0,sceneRadiusRaw=760,maxGroupSpanRaw=1600,vertexRadiusRaw=750,
    pokemon={player={-6.0,21.0},enemy={6.0,-21.0}},figureScale=0.34,
    trainers={player={17.0,30.0},enemy={-17.0,-30.0}},
    trainerScale={player=0.445,enemy=0.215},
    -- Slightly tighter and lower than the old survey-like framing so the deck,
    -- landmark pylons and first crater wall carry the shot while the skyline
    -- still clears both battlers.
    camera={side=61,back=19,height=23.8,lookX=0,lookY=6.1,frameH=53.5},
    -- Platform 100 source reference carries a pale high-altitude cloud deck
    -- over the active caldera. Arena.lua expands this into layered moving cloud
    -- bands while these colors remain the fallback profile.
    backdrop={top={0.25,0.29,0.35},bottom={0.83,0.84,0.82}},
    profile="summit",crowd="none",
  },
}

local RANDOM_ARENAS={"water","orre_colosseum","realgam_colosseum","outdoor_wild","mt_battle_summit"}
local ORDER={"auto","random","water","orre_colosseum","realgam_colosseum","outdoor_wild","mt_battle_summit"}
local VALID={auto=true,random=true,water=true,orre_colosseum=true,realgam_colosseum=true,outdoor_wild=true,mt_battle_summit=true}

local function chooseRandomArena()
  local available={}
  for _,id in ipairs(RANDOM_ARENAS) do
    local def=DEFINITIONS[id]
    if def and def.ready then available[#available+1]=id end
  end
  if #available==0 then return "water" end
  local index=math.random(1,#available)
  if #available>1 and available[index]==lastRandomArena then
    index=(index%#available)+1
  end
  lastRandomArena=available[index]
  return lastRandomArena
end

local function saved(game)
  local save=game and game.save
  local p=save and save.colosseumBattle
  local id=p and p.arena or "auto"
  if not VALID[id] then id="auto" end
  return id
end

local function ensurePrefs(game)
  if not (game and game.save) then return nil end
  local p=game.save.colosseumBattle
  if type(p)~="table" then p={};game.save.colosseumBattle=p end
  return p
end


function C.enabled(game)
  local save=game and game.save
  local p=save and save.colosseumBattle
  if not p then return true end
  if p.arenasEnabled==nil then p.arenasEnabled=true end
  return p.arenasEnabled and true or false
end

function C.setEnabled(game,value)
  local p=ensurePrefs(game)
  if p then p.arenasEnabled=value and true or false end
  return value and true or false
end

function C.definition(id) return DEFINITIONS[id] end
function C.order() return ORDER end
function C.options()
  return {
    {id="auto",label="AUTO"},
    {id="random",label="RANDOM"},
    {id="water",label="WATER COLOSSEUM"},
    {id="orre_colosseum",label="ORRE COLOSSEUM"},
    {id="realgam_colosseum",label="REALGAM COLOSSEUM"},
    {id="outdoor_wild",label="ORRE WILDLANDS"},
    {id="mt_battle_summit",label="MT. BATTLE SUMMIT"},
  }
end

function C.setSelected(game,id)
  if not VALID[id] then id="auto" end
  runtimeSelected=id
  pendingSelected=id
  local p=ensurePrefs(game)
  if p then p.arena=id end
  -- Arena providers are acquired once at battle start. Never mutate a battle
  -- already in progress; stage the explicit choice so the NEXT acquire cannot
  -- be overwritten by an older battle.game.save snapshot.
  return id
end

function C.sync(game)
  -- Do not cache the first value forever. If mod load happens
  -- before the active save was fully attached, that stale AUTO/WATER value
  -- overrode later selection. Do not let background save synchronization erase
  -- a menu choice that is waiting to be acquired by the next battle.
  if game and game.save and pendingSelected==nil then runtimeSelected=saved(game) end
  return pendingSelected or runtimeSelected or "auto"
end

function C.selected(game)
  if pendingSelected~=nil then return pendingSelected end
  if game and game.save then
    runtimeSelected=saved(game)
    return runtimeSelected
  end
  return runtimeSelected or "auto"
end

function C.resolve(game,battle)
  local selected
  if battle then
    -- Bind one immutable manual selection to this exact battle.  StadiumBattleFX
    -- acquires the arena once at battle.started; Agatha/Nascour, Lance, camera
    -- events, or later save reads cannot change the selected arena underneath it.
    if boundBattle~=battle then
      boundBattle=battle
      -- A selection made in the BATTLE overlay is authoritative for this
      -- acquisition even if ctx.game still exposes an older save snapshot.
      boundSelected=pendingSelected or C.selected(game)
      boundResolved=nil
      runtimeSelected=boundSelected
      pendingSelected=nil
    end
    selected=boundSelected or "auto"
  else
    selected=C.selected(game)
  end
  local wanted=selected
  if selected=="auto" then
    wanted=(battle and (battle.kind=="wild" or battle.kind=="safari")) and "outdoor_wild" or "water"
  elseif selected=="random" then
    -- Random is a battle-start choice, not a per-frame choice. Status/menu
    -- reads outside a battle never consume RNG; the concrete arena is bound
    -- exactly once when the provider acquires this battle.
    if battle then
      boundResolved=boundResolved or chooseRandomArena()
      wanted=boundResolved
    else
      wanted=lastRandomArena or "water"
    end
  end
  local def=DEFINITIONS[wanted] or DEFINITIONS.water
  if not def.ready then def=DEFINITIONS.water end
  return def,selected
end

function C.releaseBattle(battle)
  if not battle or boundBattle==battle then
    boundBattle=nil
    boundSelected=nil
    boundResolved=nil
  end
end

function C.status(game,battle)
  local def,selected=C.resolve(game,battle)
  return {enabled=C.enabled(game),selected=selected,resolved=def.id,cache=def.cache,runtimeSelected=runtimeSelected,pendingSelected=pendingSelected,boundSelected=boundSelected,boundResolved=boundResolved,lastRandomArena=lastRandomArena,boundBattle=boundBattle~=nil,definitions=DEFINITIONS}
end

return C
