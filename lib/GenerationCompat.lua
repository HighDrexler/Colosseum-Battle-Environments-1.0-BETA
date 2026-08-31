-- Generation-neutral presentation facade.
--
-- Gen 1's BattleState is both the battle model and its screen. Gen 2 splits
-- those responsibilities between src/battle/gen2/Battle.lua and
-- src/ui/gen2/BattleState.lua. CBE's providers intentionally consume one
-- stable, Gen-1-shaped presentation object; this adapter supplies that object
-- locally instead of relying on another mod to normalize the two engines.
local V=...
local C={}
local byModel=setmetatable({},{__mode="k"})
local byView=setmetatable({},{__mode="k"})
local detectedGeneration=nil

local function engineRequire(name)
  return (V.engineRequire or require)(name)
end

function C.current()
  if detectedGeneration then return detectedGeneration end
  local ok,GameVersion=pcall(engineRequire,"src.core.GameVersion")
  if ok and GameVersion and type(GameVersion.generation)=="function" then
    local okGen,value=pcall(GameVersion.generation)
    if okGen and tonumber(value) then detectedGeneration=tonumber(value) end
  end
  return detectedGeneration or 1
end

local function isGen2View(value)
  return type(value)=="table" and type(value.battle)=="table"
    and type(value.pic)=="function" and type(value.activeMon)=="function"
    and type(value.game)=="table"
end

local function isGen2Model(value)
  return type(value)=="table" and value.wild~=nil
    and type(value.takeEvents)=="function" and type(value.data)=="table"
    and value.game==nil
end

local function sideOf(facade,value)
  if value==facade.player or value==(facade.player and facade.player.mon) then return "player" end
  if value==facade.enemy or value==(facade.enemy and facade.enemy.mon) then return "enemy" end
  return nil
end

local function activeMon(facade,side)
  local view=facade._view
  if view and type(view.activeMon)=="function" then
    local ok,mon=pcall(view.activeMon,view,side)
    if ok and mon then return mon end
  end
  return facade._model and facade._model[side] or nil
end

local function resolvedImage(facade,mon,side)
  local view=facade._view
  if not (view and mon and type(view.pic)=="function") then return nil end
  local ok,image=pcall(view.pic,view,mon,side=="player")
  return ok and image or nil
end

local function animState(facade,side)
  local view=facade and facade._view
  if not (view and type(view.animPicState)=="function") then return nil end
  local ok,state=pcall(view.animPicState,view,side)
  return ok and state or nil
end

local RESIZE_SCALE={
  player={[0]=1,[1]=4/6,[2]=2/6},
  enemy={[3]=1,[4]=5/7,[5]=3/7},
}

local function syncBattler(facade,side)
  local mon=activeMon(facade,side)
  local battler=facade[side]
  if type(battler)~="table" then battler={};facade[side]=battler end
  battler.mon=mon
  battler.sprite=resolvedImage(facade,mon,side)
  battler.isPlayer=side=="player"
  battler.fainted=mon and (tonumber(mon.hp) or 0)<=0 or false
  battler.side=side
  return battler
end

local function sync(facade)
  if not (facade and facade.__cbePresentation) then return facade end
  local model,view=facade._model,facade._view
  facade.game=(view and view.game) or (V.mod and V.mod.game)
  facade.kind=(model and model.wild) and "wild" or "trainer"
  facade.trainer=model and model.trainer or nil
  facade.oppClass=facade.trainer and (facade.trainer.classId or facade.trainer.class) or nil
  facade.oppName=facade.trainer and facade.trainer.name or nil
  facade.trainerClass=facade.oppClass
  facade.trainerName=facade.oppName
  facade.showPlayerBack=view and view.showPlayerTrainer==true or false
  facade.showEnemyTrainer=view and view.showEnemyTrainer==true or false
  facade.safari=false
  facade.demo=view and view.tutorial==true or false
  facade.result=model and model.outcome or nil
  facade.enemyHidden=view and view.picHidden and view.picHidden.enemy==true or false
  facade.playerHidden=view and view.picHidden and view.picHidden.player==true or false
  local playerAnim=animState(facade,"player")
  local enemyAnim=animState(facade,"enemy")
  facade.sendingOut=playerAnim and playerAnim.size~=nil or false
  facade.enemySendingOut=enemyAnim and enemyAnim.size~=nil or false
  local player=syncBattler(facade,"player")
  local enemy=syncBattler(facade,"enemy")
  facade.sides.player=facade.sides.player or {}
  facade.sides.enemy=facade.sides.enemy or {}
  facade.sides.player.battler=player
  facade.sides.enemy.battler=enemy
  return facade
end

local function makeFacade(model)
  local facade={
    __cbePresentation=true,__cbeGeneration=2,_model=model,_view=nil,
    sides={player={},enemy={}},
  }
  function facade:currentMapId()
    local world=self.game and self.game.world
    local map=world and world.map
    return map and (map.id or (map.def and map.def.id)) or nil
  end
  function facade:picImage(image) return image end
  function facade:fxHidden(battler)
    local side=sideOf(self,battler)
    if not side then return false end
    if side=="enemy" and self.enemyHidden then return true end
    if side=="player" and self.playerHidden then return true end
    local anim=animState(self,side)
    if anim and anim.hidden then return true end
    local view,mon=self._view,battler and battler.mon
    if view and type(view.isVanished)=="function" then
      local ok,hidden=pcall(view.isVanished,mon)
      if ok and hidden then return true end
    end
    return false
  end
  -- Persistent 3D actors need a stronger distinction than the 2D picture
  -- renderer: anim.hidden can be a transient blink/hide frame, while a move
  -- such as Fly/Dig is a genuine field-visibility state. Expose only the latter
  -- as an actor-level hide so CBE can ignore damage blinking without making a
  -- vanished Pokemon visible.
  function facade:actorHidden(battler)
    local side=sideOf(self,battler)
    if not side then return false end
    -- picHidden/playerHidden/enemyHidden belong to the 2D picture layer and are
    -- also used for damage blinking. They are deliberately NOT structural actor
    -- visibility. Only the battle view's real vanished state may hide a 3D actor.
    local view,mon=self._view,battler and battler.mon
    if view and type(view.isVanished)=="function" then
      -- Match the existing facade call convention: Gen-2 exposes this as a
      -- plain function of the mon rather than a colon-method.
      local ok,hidden=pcall(view.isVanished,mon)
      if ok and hidden then return true end
    end
    return false
  end
  function facade:fxFaintActive(battler)
    local side=sideOf(self,battler)
    local slide=self._view and self._view.faintSlide
    return side~=nil and slide~=nil and slide.side==side
  end
  function facade:fxFaintOffset(battler)
    local side=sideOf(self,battler)
    local view=self._view
    if not (side and view and type(view.faintSink)=="function") then return 0 end
    local ok,value=pcall(view.faintSink,view,side)
    return ok and (tonumber(value) or 0) or 0
  end
  function facade:growInScale(battler)
    local side=sideOf(self,battler)
    local anim=side and animState(self,side) or nil
    if not (side and anim and anim.size~=nil) then return nil end
    return RESIZE_SCALE[side][anim.size]
  end
  return sync(facade)
end

function C.prepare(value)
  if type(value)~="table" then return value end
  if value.__cbePresentation then return sync(value) end
  local known=byView[value] or byModel[value]
  if known then return sync(known) end
  if isGen2View(value) then
    local model=value.battle
    local facade=byModel[model] or makeFacade(model)
    facade._view=value
    byModel[model]=facade
    byView[value]=facade
    return sync(facade)
  end
  if isGen2Model(value) then
    local facade=makeFacade(value)
    byModel[value]=facade
    return facade
  end
  return value
end

function C.sync(value) return sync(C.prepare(value)) end
function C.model(value)
  local facade=C.prepare(value)
  return type(facade)=="table" and facade.__cbePresentation and facade._model or value
end
function C.view(value)
  local facade=C.prepare(value)
  return type(facade)=="table" and facade.__cbePresentation and facade._view or nil
end
function C.isGen2Battle(value)
  local facade=C.prepare(value)
  return type(facade)=="table" and facade.__cbeGeneration==2
end
function C.matches(a,b)
  if a==b then return true end
  local aa,bb=C.prepare(a),C.prepare(b)
  if aa==bb then return true end
  return type(aa)=="table" and type(bb)=="table"
    and aa.__cbePresentation and bb.__cbePresentation and aa._model==bb._model
end
function C.release(value)
  local facade=C.prepare(value)
  if not (type(facade)=="table" and facade.__cbePresentation) then return end
  if facade._model then byModel[facade._model]=nil end
  if facade._view then byView[facade._view]=nil end
  facade._view=nil
end
function C.status()
  return {generation=C.current(),mode="built-in-gen1/gen2-battle-presentation-facade"}
end

return C
