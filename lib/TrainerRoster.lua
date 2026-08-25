local V=...
local mod=V.mod
local GeneratedAssets=V.GeneratedAssets
local R={index=nil,indexTried=false,indexError=nil}

-- Selectable Colosseum/GBA trainer actors. ROM-built entries can override these
-- through cache/trainers/generic/index.lua -> models/rivals/archetypes.
local MODELS={
  red={id="red",label="RED",cache="cache/trainers/red/model_cache.lua",scaleMul=1.62,playerScaleMul=1.00,enemyWorldHeight=6.90,pivotY=7.4,playerPivotY=7.4,rig="red",directSource=true,source="gc6e01-generated"},
  leaf={id="leaf",label="GREEN / LEAF",cache="cache/trainers/leaf/model_cache.lua",scaleMul=1.66,playerScaleMul=1.02,enemyWorldHeight=6.90,pivotY=7.3,playerPivotY=7.3,rig="leaf",directSource=true,source="gc6e01-generated"},
  wes={id="wes",label="WES / SETH",cache="cache/trainers/wes/model_cache.lua",scaleMul=1.50,playerScaleMul=.93,enemyWorldHeight=6.90,pivotY=8.0,playerPivotY=8.0,rig="wes",source="gc6e01-generated"},
  -- GC6E01 carries distinct Kanto and Hoenn GBA battle actors.
  brendan={id="brendan",label="BRENDAN",cache="cache/trainers/brendan/model_cache.lua",scaleMul=1.55,playerScaleMul=.96,enemyWorldHeight=6.90,pivotY=7.7,playerPivotY=7.7,rig="brendan",source="gc6e01-generated"},
  may={id="may",label="MAY",cache="cache/trainers/may/model_cache.lua",scaleMul=1.60,playerScaleMul=.99,enemyWorldHeight=6.90,pivotY=7.5,playerPivotY=7.5,rig="may",source="gc6e01-generated"},
  dakim={id="dakim",label="DAKIM",cache="cache/trainers/dakim/model_cache.lua",scaleMul=1.0,playerScaleMul=.62,pivotY=12.8,playerPivotY=12.8,rig="dakim",source="gc6e01-generated"},
  nascour={id="nascour",label="NASCOUR",cache="cache/trainers/nascour/model_cache.lua",scaleMul=1.48,playerScaleMul=.92,pivotY=12.2,playerPivotY=12.2,rig="nascour",source="gc6e01-generated"},
  miror_b={id="miror_b",label="MIROR B.",cache="cache/trainers/miror_b/model_cache.lua",scaleMul=1.28,playerScaleMul=.80,pivotY=11.3,playerPivotY=11.3,rig="miror_b",source="gc6e01-generated"},
  cooltrainer_m={id="cooltrainer_m",label="COOLTRAINER M",cache="cache/trainers/cooltrainer_m/model_cache.lua",scaleMul=1.47,enemyWorldHeight=6.90,pivotY=8.1,rig="cooltrainer_m",source="gc6e01-generated"},
  cooltrainer_f={id="cooltrainer_f",label="COOLTRAINER F",cache="cache/trainers/cooltrainer_f/model_cache.lua",scaleMul=1.58,enemyWorldHeight=6.90,pivotY=7.6,rig="cooltrainer_f",source="gc6e01-generated"},
}
local PLAYER_ORDER={"red","wes","brendan","may","leaf","dakim","nascour","miror_b"}
local RIVAL_ORDER={"leaf","red","wes","brendan","may","dakim","nascour","miror_b"}
local ENEMY_ORDER={"cooltrainer_m","cooltrainer_f","red","leaf","wes","brendan","may","dakim","nascour","miror_b"}

local BOSS_NAMES={
  "BROCK","MISTY","SURGE","ERIKA","KOGA","SABRINA","BLAINE","GIOVANNI",
  "LORELEI","BRUNO","AGATHA","LANCE","CHAMPION",
  "FALKNER","BUGSY","WHITNEY","MORTY","CHUCK","JASMINE","PRYCE","CLAIR",
  "WILL","KAREN","RED",
}

local function battleOf(ctx)
  if type(ctx)~="table" then return nil end
  return ctx.battle or (ctx.kind and ctx) or nil
end
local function values(ctx)
  local b=battleOf(ctx)
  if not b then return {} end
  return {
    b.oppClass,b.oppName,b.trainerClass,b.trainerName,b.enemyTrainerName,
    b.enemyTrainer and b.enemyTrainer.id,b.enemyTrainer and b.enemyTrainer.name,b.enemyTrainer and b.enemyTrainer.class,
    b.opponent and b.opponent.id,b.opponent and b.opponent.name,b.opponent and b.opponent.class,
    b.trainer and b.trainer.id,b.trainer and b.trainer.name,b.trainer and b.trainer.class,
  }
end
local function tokens(ctx)
  local out={}
  for _,v in ipairs(values(ctx)) do
    if v~=nil then out[#out+1]=tostring(v):upper():gsub("[%s%-]+","_") end
  end
  return out
end
local function containsAny(list,needles)
  for _,key in ipairs(list) do for _,needle in ipairs(needles) do if key:find(needle,1,true) then return true end end end
  return false
end
local function gameFor(ctx)
  local b=battleOf(ctx)
  return (b and b.game) or (ctx and ctx.game) or (mod and mod.game)
end
local function prefs(ctx)
  local game=gameFor(ctx)
  local p=game and game.save and game.save.colosseumBattle
  return type(p)=="table" and p or {}
end
local function info(path) return GeneratedAssets.info(path) end
local function exists(path) return GeneratedAssets.exists(path) end
local function readLua(path)
  local value,err=GeneratedAssets.readLua(path)
  return type(value)=="table" and value or nil,err or "invalid roster index"
end
local function loadIndex()
  if R.indexTried then return R.index end
  R.indexTried=true
  local idx,err=readLua("cache/trainers/generic/index.lua")
  local version=idx and tonumber(idx.version or 1)
  if idx and version and version>=1 and version<=2 then R.index=idx;R.indexError=nil else R.index=nil;R.indexError=err or "unsupported roster index version" end
  return R.index
end
local function normalizeEntry(id,entry,source)
  if type(entry)~="table" then return nil end
  local cache=entry.cache or entry.model or entry.modelCache
  if type(cache)~="string" or cache=="" or not exists(cache) then return nil end
  return {
    id=tostring(entry.id or id),label=tostring(entry.label or id):upper(),cache=cache,
    scaleMul=tonumber(entry.scaleMul) or tonumber(entry.scale) or 1,
    playerScaleMul=tonumber(entry.playerScaleMul) or tonumber(entry.playerScale),
    enemyWorldHeight=tonumber(entry.enemyWorldHeight) or tonumber(entry.enemyTargetHeight),
    pivotY=tonumber(entry.pivotY) or 12.0,
    playerPivotY=tonumber(entry.playerPivotY) or tonumber(entry.pivotY) or 12.0,
    rig=tostring(entry.rig or entry.id or id):lower(),directSource=entry.directSource==true,source=source or "rom-generic",
  }
end
local function indexEntry(group,id)
  local idx=loadIndex(); local tableGroup=idx and idx[group]
  return normalizeEntry(id,tableGroup and tableGroup[id],"rom-"..tostring(group))
end

local function catalogEntry(id)
  id=tostring(id or ""):lower()
  if id=="green" or id=="female" then id="leaf" end
  if id=="seth" or id=="colosseum" or id=="protagonist" then id="wes" end
  local fromIndex=indexEntry("models",id)
  if fromIndex then return fromIndex end
  local base=MODELS[id]
  if not base or not exists(base.cache) then return nil end
  local out={};for k,v in pairs(base) do out[k]=v end;return out
end
function R.normalizeChoice(id,role)
  id=tostring(id or ""):lower()
  if id=="green" then id="leaf" elseif id=="seth" then id="wes" end
  if role=="enemy" and id=="all" then id="auto" end
  local valid={off=true,auto=role=="enemy"}
  for k,_ in pairs(MODELS) do valid[k]=true end
  return valid[id] and id or ((role=="player" and "red") or (role=="rival" and "leaf") or "auto")
end
function R.label(id)
  id=R.normalizeChoice(id,"player")
  if id=="off" then return "OFF" end
  if id=="auto" then return "AUTO" end
  return (MODELS[id] and MODELS[id].label) or tostring(id):upper()
end
function R.options(role)
  local out={}
  if role=="enemy" then out[#out+1]={id="auto",label="AUTO / TRAINER CLASS",available=true} end
  out[#out+1]={id="off",label="OFF",available=true}
  local order=(role=="rival" and RIVAL_ORDER) or (role=="enemy" and ENEMY_ORDER) or PLAYER_ORDER
  for _,id in ipairs(order) do
    local cfg=catalogEntry(id)
    out[#out+1]={id=id,label=(MODELS[id] and MODELS[id].label) or id:upper(),available=cfg~=nil}
  end
  return out
end
function R.modelById(id)
  id=R.normalizeChoice(id,"player")
  if id=="off" or id=="auto" then return nil end
  return catalogEntry(id)
end

function R.isRival(ctx)
  local b=battleOf(ctx)
  if not b or b.kind~="trainer" then return false end
  local oc=tostring(b.oppClass or ""):upper()
  -- Gen1Recomp exposes every Kanto rival encounter directly as OPP_RIVAL1/2/3.
  -- Use that authoritative identity first; names are user-editable and must not
  -- be required for rival presentation.
  if oc=="OPP_RIVAL1" or oc=="OPP_RIVAL2" or oc=="OPP_RIVAL3" or oc:find("OPP_RIVAL",1,true)==1 then return true end
  return containsAny(tokens(ctx),{"RIVAL","BLUE","GARY"})
end
function R.isBoss(ctx)
  local b=battleOf(ctx); if not b or b.kind~="trainer" then return false end
  if b.isGymLeader then return true end
  if R.isRival(ctx) then return true end
  return containsAny(tokens(ctx),BOSS_NAMES)
end
local function genericKey(ctx)
  local t=tokens(ctx)
  if containsAny(t,{"ROCKET"}) then return containsAny(t,{"FEMALE","_F","GIRL"}) and "rocket_f" or "rocket_m" end
  if containsAny(t,{"SCIENTIST","ENGINEER","BURGLAR"}) then return "scientist_m" end
  if containsAny(t,{"PSYCHIC","CHANNELER","MEDIUM","SAGE"}) then return containsAny(t,{"CHANNELER","MEDIUM","FEMALE","_F"}) and "psychic_f" or "psychic_m" end
  if containsAny(t,{"BLACKBELT","HIKER","BIKER","CUE_BALL","FIREBREATHER"}) then return "athletic_m" end
  if containsAny(t,{"SWIMMER_F","BEAUTY","LASS","JR_TRAINER_F","COOLTRAINER_F","PICNICKER","KIMONO_GIRL","SKIER"}) then return "young_f" end
  if containsAny(t,{"YOUNGSTER","BUG_CATCHER","JR_TRAINER_M","COOLTRAINER_M","SWIMMER_M","CAMPER","SCHOOLBOY","BIRD_KEEPER"}) then return "young_m" end
  if containsAny(t,{"GENTLEMAN","GAMBLER","FISHER","SAILOR","POKEMANIAC"}) then return "adult_m" end
  if containsAny(t,{"POKE_MANIAC","TAMER","JUGGLER","SCIENTIST","BOARDER"}) then return "specialist_m" end
  return "default_m"
end
local function specialFor(ctx)
  local t=tokens(ctx)
  if containsAny(t,{"LANCE"}) then return catalogEntry("miror_b") end
  if containsAny(t,{"AGATHA"}) then return catalogEntry("nascour") end
  if R.isBoss(ctx) and not R.isRival(ctx) then return catalogEntry("dakim") end
  return nil
end

function R.playerModelFor(ctx)
  local p=prefs(ctx)
  local choice=R.normalizeChoice(p.playerModel or (p.playerTrainerModel==false and "off" or "red"),"player")
  if choice=="off" then return nil,"player-off" end
  local cfg=indexEntry("players",choice) or catalogEntry(choice)
  return cfg,cfg and ("player:"..choice) or ("player-cache-missing:"..choice)
end
function R.modelFor(ctx)
  local b=battleOf(ctx); if not b or b.kind~="trainer" then return nil,"not-trainer" end
  local p=prefs(ctx)
  if R.isRival(ctx) then
    local choice=R.normalizeChoice(p.rivalModel or "leaf","rival")
    if choice=="off" then return nil,"rival-off" end
    local cfg=indexEntry("rivals",choice) or catalogEntry(choice)
    return cfg,cfg and ("rival:"..choice) or ("rival-cache-missing:"..choice)
  end
  local enemyChoice=R.normalizeChoice(p.enemyTrainerModel or (p.enemyTrainerModels==false and "off" or "auto"),"enemy")
  if enemyChoice=="off" then return nil,"enemy-models-off" end
  if enemyChoice~="auto" then
    local cfg=catalogEntry(enemyChoice)
    return cfg,cfg and ("enemy-forced:"..enemyChoice) or ("enemy-cache-missing:"..enemyChoice)
  end
  local special=specialFor(ctx); if special then return special,"special" end
  local key=genericKey(ctx)
  local generic=indexEntry("archetypes",key) or indexEntry("archetypes","default_m")
  if generic then return generic,"generic:"..key end
  return nil,"generic-cache-missing:"..key
end
function R.available(id) return catalogEntry(id)~=nil end
function R.coverage()
  local idx=loadIndex(); local archetypes,rivals,players,models=0,0,0,0
  if idx and type(idx.archetypes)=="table" then for id,_ in pairs(idx.archetypes) do if indexEntry("archetypes",id) then archetypes=archetypes+1 end end end
  if idx and type(idx.rivals)=="table" then for id,_ in pairs(idx.rivals) do if indexEntry("rivals",id) then rivals=rivals+1 end end end
  if idx and type(idx.players)=="table" then for id,_ in pairs(idx.players) do if indexEntry("players",id) then players=players+1 end end end
  for id,_ in pairs(MODELS) do if catalogEntry(id) then models=models+1 end end
  return {index=idx~=nil,error=R.indexError,archetypes=archetypes,rivals=rivals,players=players,models=models,
    red=R.available("red"),leaf=R.available("leaf"),wes=R.available("wes"),brendan=R.available("brendan"),may=R.available("may")}
end
function R.resetRuntime() R.index=nil;R.indexTried=false;R.indexError=nil;return true end
function R.status() return R.coverage() end
return R
