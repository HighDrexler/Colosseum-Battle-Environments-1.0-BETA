-- Generic 2D battler provider for StadiumBattleFX Battle Presentation API v1.
--
-- This deliberately does NOT choose Pokemon artwork.  It presents whatever
-- image the engine has already resolved on battle.player/enemy.sprite.  That
-- keeps Colosseum environments independent from Battle Art, Crystal/Gen 5
-- sprite packs, ROM art, and future providers that use the normal sprite seam.
local V=...
local P={
  id=nil, registered=false, preferredPatched=false,
  drawn={player=false,enemy=false}, presented={player=false,enemy=false},
  battleArt=nil, animated=nil,
  stadiumHandle=nil,stadiumApi=nil,stadiumActors={},stadiumError=nil,
  actorApi=nil,actorOwner=nil,
  spriteApi=nil,spriteOwner=nil,spriteError=nil,
  mode="sprites",modeId="builtin:resolved-sprites",externalProvider=nil,
  externalBegun=false,externalError=nil,presentationFallback=nil,
}
local OWNER=(V.mod and V.mod.id) or "COLOSSEUM_BATTLE_ENVIRONMENTS"
local ModLookup=V.ModLookup
local registeredCapabilities={battleActors={},battleSprites={},battlePresentation={}}
local BATTLE_ART_IDS={"BATTLE_ART_VOXEL_FORK","DRAMATIC_SHAPE"}
local STADIUM_ID="STADIUM_BATTLE_FX"
local STADIUM2_ID="STADIUM2_OVERWORLD_MODELS"
if ModLookup and type(ModLookup.remember)=="function" then
  ModLookup.remember(STADIUM2_ID)
end

local function releaseStadiumActors()
  for side,record in pairs(P.stadiumActors) do
    if record and record.actor and type(record.actor.release)=="function" then
      pcall(record.actor.release,record.actor)
    end
    P.stadiumActors[side]=nil
  end
end

-- StadiumBattleFX 2.1.7+ exposes a public actor service independently from
-- its Gen 1 battle host. On Gen 2 CBE owns the live widescreen compositor, so
-- consume that service directly when it is available. This preserves the
-- player's selected Stadium/Stadium 2 appearance pack without depending on
-- Stadium's Gen-1-only BattleState draw hook. Missing/unsupported actors fall
-- through to CBE's built-in current-sprite renderer side by side.
local function stadiumService()
  local handle=ModLookup.find(V.mod,STADIUM_ID)
  local api=handle and handle.exports and handle.exports.models
  if not (type(api)=="table" and tonumber(api.version)==1
      and type(api.acquire)=="function" and type(api.withRenderer)=="function") then
    if P.stadiumHandle~=handle or P.stadiumApi~=nil then releaseStadiumActors() end
    P.stadiumHandle=handle;P.stadiumApi=nil
    return nil
  end
  if P.stadiumHandle~=handle or P.stadiumApi~=api then
    releaseStadiumActors();P.stadiumHandle=handle;P.stadiumApi=api
  end
  return api
end

local function standaloneContext(context)
  return context and context.services and context.services.cbeStandalone==true
end

local function validActorApi(api)
  return type(api)=="table" and tonumber(api.version)==1
    and type(api.acquire)=="function" and type(api.withRenderer)=="function"
end

local function selected(api,context)
  if type(api.selected)~="function" then return true end
  local ok,value=pcall(api.selected,context)
  return ok and value~=false
end

local function bestCapability(context,keys,valid)
  local game=(context and context.game) or (context and context.battle and context.battle.game)
  local best,bestHandle,bestScore
  local function consider(api,handle)
    if valid(api) and selected(api,context) then
      local score=tonumber(api.priority) or 0
      if not best or score>bestScore
          or (score==bestScore and tostring(handle.id)<tostring(bestHandle.id)) then
        best,bestHandle,bestScore=api,handle,score
      end
    end
  end
  local handles=ModLookup.each and ModLookup.each(V.mod,game) or {}
  for _,handle in ipairs(handles) do
    if handle and handle.id~=OWNER then
      local exports=handle.exports
      local api
      for _,key in ipairs(keys) do
        if exports and exports[key]~=nil then api=exports[key];break end
      end
      consider(api,handle)
    end
  end
  -- Registration is optional. It gives providers loaded after CBE a direct,
  -- order-independent handshake while normal loader discovery continues to
  -- work for packages that only publish exports.<capability>.
  for _,key in ipairs(keys) do
    local bucket=registeredCapabilities[key]
    if bucket then
      for owner,api in pairs(bucket) do consider(api,{id=owner,exports={}}) end
    end
  end
  return best,bestHandle
end

local function validPresentationApi(api)
  return type(api)=="table" and tonumber(api.version)==1
    and api.portable~=false and type(api.drawWorld)=="function"
    and type(api.covers)=="function"
end

local function portablePresentationService(context)
  return bestCapability(context,{"battlePresentation","battlePresenter"},validPresentationApi)
end

local function validSpriteApi(api)
  return type(api)=="table" and tonumber(api.version)==1
    and type(api.resolve)=="function"
end

-- Sprite packages normally need no CBE-specific integration: replacing the
-- engine's resolved battler image is enough. A package with animated or
-- context-sensitive art may additionally publish battleSprites v1. Discovery
-- is based on the exported capability, never its package id.
local function portableSpriteService(context)
  return bestCapability(context,{"battleSprites","battleSpriteProvider"},validSpriteApi)
end

-- Portable battle actors are a capability, not a package-name allowlist.
-- Any loaded mod may publish exports.battleActors v1 (or explicitly mark its
-- exports.models service portable). The engine-resolved 2D seam remains the
-- fallback for a service that declines one species or one side.
local function portableActorService(context)
  local api,handle=bestCapability(context,{"battleActors"},validActorApi)
  if api then return api,handle end
  -- Compatibility alias for packages that expose their actor service through
  -- `models`; only an explicit portable marker makes that generic name safe.
  return bestCapability(context,{"models"},function(value)
    return type(value)=="table" and value.portable==true and validActorApi(value)
  end)
end

local function desiredPresentation(context)
  P.presentationFallback=nil
  -- When Stadium's own host selected this provider, the registry has already
  -- dispatched the user's choice. Resolving it again from inside the provider
  -- would recurse. Selection arbitration belongs only to CBE's local host.
  if not standaloneContext(context) then
    return "sprites","builtin:resolved-sprites",nil
  end
  local presenter,presenterHandle=portablePresentationService(context)
  if presenter then
    return "external",tostring(presenterHandle.id)..":battle-presentation",presenter,presenterHandle
  end
  local portable,portableHandle=portableActorService(context)
  if portable then
    return "stadium",tostring(portableHandle.id)..":battle-actors",portable,portableHandle
  end
  local handle=ModLookup.find(V.mod,STADIUM_ID)
  local exports=handle and handle.exports
  local actors=stadiumService()
  local registry=exports and exports.battles
  if not (type(registry)=="table" and tonumber(registry.version)==1
      and type(registry.selectedId)=="function" and type(registry.resolve)=="function") then
    -- Actor-service releases predating the registry had only one meaning:
    -- installed Stadium models. Modern releases always take the branch below.
    if actors then return "stadium","stadium:legacy-selected",actors,handle end
    return "sprites","builtin:resolved-sprites",nil
  end
  local okSelected,selected=pcall(registry.selectedId,registry,"models")
  if not okSelected then return "sprites","builtin:resolved-sprites",nil end
  selected=tostring(selected or "stadium:default")
  if selected=="off" then return "native","off",nil end
  local okResolve,provider,entry=pcall(registry.resolve,registry,"models",context)
  if not okResolve then
    P.externalError=tostring(provider)
    return "sprites","builtin:resolved-sprites",nil
  end
  local resolvedId=(type(entry)=="table" and entry.id) or selected
  P.presentationFallback=registry.FALLBACK
  if provider==P or (P.id and resolvedId==P.id) then
    return "sprites",resolvedId,provider
  end
  local builtin=exports and exports.modelProvider
  if provider==builtin or resolvedId=="stadium:default" then
    if actors then return "stadium",resolvedId,actors,handle end
    return "sprites","builtin:resolved-sprites",nil
  end
  if type(provider)=="table" and provider.hostRender~=true then
    return "external",resolvedId,provider
  end
  -- A selected provider that needs Stadium's private renderer cannot safely
  -- be entered from CBE's renderer. Keep the engine-resolved art visible.
  return "sprites","builtin:resolved-sprites",nil
end

local function invokeExternal(context,method,...)
  local provider=P.externalProvider
  local fn=provider and provider[method]
  if type(fn)~="function" then return true,nil end
  local ok,a,b,c=pcall(fn,provider,context,...)
  if not ok then P.externalError=tostring(a);return false,a end
  return true,a,b,c
end

local function finishExternal(context,reason)
  if P.externalProvider and P.externalBegun then
    invokeExternal(context,"finish",reason or "selection-changed")
  end
  P.externalProvider=nil;P.externalBegun=false
end

local function selectPresentation(context,force)
  local mode,id,provider,handle=desiredPresentation(context)
  if not force and mode==P.mode and id==P.modeId
      and (mode~="external" or provider==P.externalProvider)
      and (mode~="stadium" or provider==P.actorApi) then return mode end
  finishExternal(context,"selection-changed")
  releaseStadiumActors()
  P.mode=mode;P.modeId=id;P.externalError=nil
  P.actorApi=(mode=="stadium") and provider or nil
  P.actorOwner=(mode=="stadium" and handle and handle.id) or nil
  if mode=="external" then
    P.externalProvider=provider
    local ok,accepted=invokeExternal(context,"begin",context and context.arena)
    if not ok or accepted==false or accepted==P.presentationFallback then
      finishExternal(context,"begin-declined")
      P.mode="sprites";P.modeId="builtin:resolved-sprites"
    else
      P.externalBegun=true
    end
  end
  return P.mode
end

local function arenasEnabled(context)
  local C=V.ArenaCatalog
  if not (C and type(C.enabled)=="function") then return true end
  local battle=context and context.battle
  local game=(context and context.game) or (battle and battle.game) or (V.mod and V.mod.game)
  local ok,value=pcall(C.enabled,game)
  return not ok or value~=false
end

local function ourArena(context)
  local arena=context and context.arena
  local id=arena and tostring(arena.id or "") or ""
  return id:find("^COLOSSEUM_BATTLE_ENVIRONMENTS:")~=nil
end

local function battleArtHandle()
  for _,id in ipairs(BATTLE_ART_IDS) do
    local h=ModLookup.find(V.mod,id); if h then return h,id end
  end
  return nil
end

local function battleArtRuntime()
  local h,id=battleArtHandle()
  if not h then P.battleArt=nil;P.animated=nil;return nil end
  if P.battleArt and P.battleArt.handle==h then return P.battleArt end
  local lib=h.exports and h.exports.lib
  if not (type(lib)=="table" and type(lib.require)=="function") then return nil end
  local art,animated
  pcall(function() art=lib.require("BattleArt") end)
  pcall(function() animated=lib.require("AnimatedBattleArt") end)
  P.battleArt={handle=h,id=id,art=art}
  P.animated=animated
  return P.battleArt
end

local function battleArtWantsWorldSprites()
  -- CBE owns only the battlefield. Battle Art's 3D-BTL switch controls its
  -- own overworld staging and MUST NOT decide which Pokemon art is used in a
  -- Colosseum arena. If Battle Art is active at all, preserve the art it has
  -- resolved (STATIC / ANIMATED / ROM / MODDED) inside our environment.
  return battleArtRuntime() ~= nil
end

local function liveBattler(context,side)
  local battle=context and context.battle
  -- BattleState replaces battle.player / battle.enemy when a new Pokemon is
  -- sent out. context.sides is a presentation snapshot and can therefore hold
  -- the battler that opened the battle. Always prefer the authoritative live
  -- BattleState slot, then mirror it back into the presentation context.
  local b=battle and battle[side]
  if not b then
    local entry=context and context.sides and context.sides[side]
    b=entry and entry.battler or nil
  end
  if context and context.sides then
    context.sides[side]=context.sides[side] or {}
    context.sides[side].battler=b
  end
  return b
end

local function dexFor(context,battler)
  local mon=battler and battler.mon
  local species=mon and mon.species
  local game=(context and context.game) or (context and context.battle and context.battle.game)
  local def=game and game.data and game.data.pokemon and game.data.pokemon[species]
  -- Gen 1 content commonly calls this field `dex`; the real Gen 2 data model
  -- calls the same National Dex ordinal `index` (Cyndaquil=155, Pidgey=16).
  local dex=(def and (def.dex or def.index or def.number))
    or (mon and (mon.dex or mon.speciesIndex))
  return tonumber(dex),mon and mon.shiny and "shiny" or "normal"
end

local function stadiumActor(context,side)
  if P.mode~="stadium" then return nil end
  local api=P.actorApi or stadiumService()
  if not api then return nil end
  local battler=liveBattler(context,side)
  local dex,variant=dexFor(context,battler)
  local record=P.stadiumActors[side]
  if not dex or dex<1 then
    P.stadiumError="no National Dex mapping for "..tostring(battler and battler.mon and battler.mon.species)
    if record and record.actor and record.actor.release then pcall(record.actor.release,record.actor) end
    P.stadiumActors[side]=nil
    return nil
  end
  local key=tostring(dex)..":"..variant
  if record and record.key==key then return record.actor end
  if record and record.actor and record.actor.release then pcall(record.actor.release,record.actor) end
  P.stadiumActors[side]=nil
  local source=api.SELECTED or "selected"
  if type(api.available)=="function" then
    local ok,available=pcall(api.available,source,dex)
    if not (ok and available) then
      P.stadiumError=ok and ("actor provider reports model "..tostring(dex).." unavailable") or tostring(available)
      return nil
    end
  end
  local ok,actor,err=pcall(api.acquire,source,dex,variant,{side=side,context=context,battler=battler})
  if not ok or not actor then
    P.stadiumError=tostring(ok and err or actor)
    return nil
  end
  P.stadiumError=nil
  P.stadiumActors[side]={key=key,actor=actor,dex=dex,variant=variant}
  return actor
end

local growScale
local function visible(context,side)
  local battle=context and context.battle
  local b=liveBattler(context,side)
  if not (battle and b and b.sprite) then return false end
  if side=="enemy" then
    if battle.showEnemyTrainer or battle.enemyHidden then return false end
    if battle.enemySendingOut then
      -- The native grow-in is authoritative. Do not blanket-hide the external
      -- actor for the entire send-out phase; begin presenting it as soon as
      -- BattleState gives it a non-zero spawn scale.
      local scale=growScale(context,b)
      if not (scale and scale>0) then return false end
    end
  else
    if battle.showPlayerBack or battle.safari or battle.demo then return false end
    if battle.sendingOut then
      local scale=growScale(context,b)
      if not (scale and scale>0) then return false end
    end
  end
  -- Faint ownership belongs to BattleState. Keep the resolved external art
  -- visible only while the engine's own faint slide is active; once the
  -- authoritative battler is marked fainted and that slide has finished, the
  -- actor is gone. This prevents a static Battle Arts/ROM sprite from standing
  -- at 0 HP through EXP/result messages.
  local faintActive=false
  if type(battle.fxFaintActive)=="function" then
    local ok,value=pcall(battle.fxFaintActive,battle,b)
    faintActive=ok and value==true
  end
  if b.fainted and not faintActive then return false end
  if type(battle.fxHidden)=="function" then
    local ok,hidden=pcall(battle.fxHidden,battle,b)
    if ok and hidden then return false end
  end
  return true
end

growScale=function(context,b)
  local battle=context and context.battle
  if not (battle and b and type(battle.growInScale)=="function") then return nil end
  local ok,value=pcall(battle.growInScale,battle,b)
  if not (ok and type(value)=="number") then return nil end
  return math.max(0,math.min(1,value))
end

local function faintProgress(context,b)
  local battle=context and context.battle
  if not (battle and b and type(battle.fxFaintActive)=="function") then return nil end
  local ok,active=pcall(battle.fxFaintActive,battle,b)
  if not (ok and active) then return nil end

  -- Gen1Recomp's faint contract is a 56px (7 tile) downward slide. Ask the
  -- engine for its current native-pixel offset, then normalize that motion to
  -- whichever external sprite CBE is presenting. This follows battle timing
  -- without assuming anything about Battle Arts/model animation APIs.
  local off=0
  if type(battle.fxFaintOffset)=="function" then
    local okOff,value=pcall(battle.fxFaintOffset,battle,b,1)
    if okOff and type(value)=="number" then off=value end
  end
  return math.max(0,math.min(1,off/56))
end

local function imageFor(context,side)
  if not visible(context,side) then return nil end
  local battle=context.battle
  local b=liveBattler(context,side)
  local image=b and b.sprite
  if image and type(battle.picImage)=="function" then
    local ok,resolved=pcall(battle.picImage,battle,image)
    if ok and resolved then image=resolved end
  end
  local spriteApi,spriteHandle=portableSpriteService(context)
  P.spriteApi=spriteApi;P.spriteOwner=spriteHandle and spriteHandle.id or nil
  P.spriteError=nil
  if spriteApi then
    local ok,resolved=pcall(spriteApi.resolve,context,side,b,image)
    if ok then
      if type(resolved)=="table" and type(resolved.getDimensions)~="function"
          and resolved.image~=nil then resolved=resolved.image end
      if resolved~=nil and resolved~=false then image=resolved end
    else
      P.spriteError=tostring(resolved)
    end
  end
  if not (image and type(image.getDimensions)=="function") then return nil end
  return image,b
end

local function anchor(context,side)
  local arena=context and context.arena
  local p=arena and arena[side]
  if type(p)~="table" then return nil end
  local x,z=tonumber(p[1]),tonumber(p[2])
  if not (x and z) then return nil end
  return x,z
end

local function project(context,x,y,z)
  local fn=context and context.services and context.services.project
  if type(fn)~="function" then return nil end
  local ok,sx,sy=pcall(fn,x,y,z)
  if not ok or type(sx)~="number" or type(sy)~="number" then return nil end
  return sx,sy
end

local function targetGeometry(context,side)
  local x,z=anchor(context,side); if not x then return nil end
  local arena=context.arena or {}
  local k=math.max(.08,tonumber(arena.figureScale) or .38)
  local px,py=project(context,x,0,z); if not px then return nil end
  -- Sprite collections are authored to a common battle slot, so normalize
  -- their displayed size rather than treating source PNG pixel dimensions as
  -- physical Pokemon height.  The arena's actor VP includes figureScale;
  -- dividing here keeps the intended visible world height stable.
  local physicalH=side=="player" and 24.5 or 25.5
  local tx,ty=project(context,x,physicalH/k,z)
  local targetH=ty and math.abs(py-ty) or nil
  if not targetH or targetH<8 then
    local rs=context.services and context.services.renderSize
    targetH=((rs and rs.height) or 768)*.115
  end
  targetH=math.max(34,math.min(targetH,190))
  return px,py,targetH
end

local function playerFlip()
  local runtime=battleArtRuntime()
  local art=runtime and runtime.art
  if not art then return false end
  local side=type(art.playerSide)=="function" and art.playerSide() or "back"
  if side~="front" then return false end
  if type(art.flipsPlayerFront)=="function" then
    local ok,value=pcall(art.flipsPlayerFront)
    return ok and value==true
  end
  return false
end

local function drawStadiumActors(context)
  if P.mode~="stadium" then return false end
  local api=P.actorApi or stadiumService()
  local services=context and context.services
  local vp=services and ((api and api.worldUnits==true and services.stageVP) or services.vp)
  local arena=context and context.arena
  if not (api and type(vp)=="table" and arena) then return false end
  local jobs={}
  for _,side in ipairs({"enemy","player"}) do
    local actor=visible(context,side) and stadiumActor(context,side) or nil
    local cell=arena[side]
    local other=arena[side=="player" and "enemy" or "player"]
    if actor and type(cell)=="table" and type(other)=="table"
        and type(actor.matrix)=="function" and type(actor.draw)=="function" then
      local ok,matrix=pcall(actor.matrix,actor,cell[1],context.groundY or 0,cell[2],
        (other[1] or 0)-(cell[1] or 0),(other[2] or 0)-(cell[2] or 0))
      if ok and matrix then jobs[#jobs+1]={side=side,actor=actor,matrix=matrix} end
    end
  end
  if #jobs==0 then return false end
  local any=false
  local ok,accepted,err=pcall(api.withRenderer,vp,function()
    for _,job in ipairs(jobs) do
      local built=true
      if type(job.actor.build)=="function" then
        local okBuild,value=pcall(job.actor.build,job.actor)
        built=okBuild and value~=false
      end
      if built then
        local okDraw,value=pcall(job.actor.draw,job.actor,job.matrix,0)
        if okDraw and value~=false then
          P.drawn[job.side]=true;P.presented[job.side]=true;any=true
        end
      end
    end
    return true
  end,{
    eye=services and services.camera and services.camera.pose and services.camera.pose.eye,
    width=services and services.renderSize and services.renderSize.width,
    height=services and services.renderSize and services.renderSize.height,
    context=context,
  })
  if not ok or accepted==false then
    P.stadiumError=tostring(ok and err or accepted)
    return false
  end
  P.stadiumError=nil
  return any
end

function P:available(context)
  return arenasEnabled(context) and ourArena(context)
end

function P:begin(context)
  self.drawn.player=false;self.drawn.enemy=false
  self.presented.player=false;self.presented.enemy=false
  battleArtRuntime()
  stadiumService()
  selectPresentation(context,true)
  return self:available(context)
end

local function actorDelta(context,dt)
  local step=math.max(0,tonumber(dt) or 0)
  local game=(context and context.game) or (context and context.battle and context.battle.game)
  local speed
  if game and type(game.logicSpeed)=="function" then
    local ok,value=pcall(game.logicSpeed,game)
    if ok then speed=tonumber(value) end
  end
  speed=speed or tonumber(game and game.speedOverride)
    or tonumber(game and game.options and game.options.speed) or 1
  -- CBE is updated from input.step, once per fixed LOGIC tick. At Nx speed
  -- that hook runs N times per rendered frame; divide each cosmetic step by N
  -- so idle/attack/faint performances remain real-time presentation.
  return step/math.max(1,speed)
end

function P:update(context,dt)
  -- Keep both side references synchronized even if the switch event is emitted
  -- before/after another mod's listener. The next update/draw always observes
  -- the current BattleState battler rather than the opener cached at begin().
  liveBattler(context,"player")
  liveBattler(context,"enemy")
  selectPresentation(context,false)
  -- Battle Art normally advances animated atlases from its staged-world
  -- session.  Our arena bridge intentionally suppresses that session, so
  -- advance only its art manager here while leaving every setting untouched.
  battleArtRuntime()
  if P.animated and type(P.animated.update)=="function" and context and context.battle then
    pcall(P.animated.update,context.battle,dt)
  end
  if P.mode=="external" then
    local ok=invokeExternal(context,"update",dt or 0)
    if not ok then
      finishExternal(context,"update-failed")
      P.mode="sprites";P.modeId="builtin:resolved-sprites"
    end
  elseif P.mode=="stadium" then
    local actorDt=actorDelta(context,dt)
    for _,side in ipairs({"player","enemy"}) do
      local actor=stadiumActor(context,side)
      if actor and type(actor.update)=="function" then pcall(actor.update,actor,actorDt) end
    end
  end
end

function P:covers(context,side)
  if self.mode=="native" or not self:available(context) then return false end
  if self.drawn[side]==true and visible(context,side) then return true end
  -- Once CBE has successfully presented a battler, retain ownership through
  -- the remainder of its faint/KO tail even after its replacement actor has
  -- disappeared. Otherwise the native picture layer gets one final frame and
  -- leaks the original ROM sprite at its stock screen-space coordinates.
  -- This latch is deliberately conditional on an observed presentation and
  -- an authoritatively fainted battler, so missing providers and OFF/native
  -- mode continue to fail open to the engine renderer.
  local b=liveBattler(context,side)
  return self.presented[side]==true and b~=nil and b.fainted==true
end

function P:cameraLocked() return false end

function P:drawWorld(context)
  local g=love and love.graphics
  if not (g and context) then return false end
  self.drawn.player=false;self.drawn.enemy=false
  if self.mode=="native" then return false end
  local any=false
  local externalValue=false
  if self.mode=="external" then
    local ok,value=invokeExternal(context,"drawWorld",0)
    if ok then
      for _,side in ipairs({"enemy","player"}) do
        local coveredOk,covered=invokeExternal(context,"covers",side)
        self.drawn[side]=coveredOk and covered==true and visible(context,side)
        if self.drawn[side] then self.presented[side]=true end
        any=any or self.drawn[side]
      end
      -- A portable presenter owns only the sides it reports. Continue through
      -- the normal resolved-sprite pass for every declined side instead of
      -- turning one missing species into a whole-battle failure.
      externalValue=value==true
    else
      finishExternal(context,"draw-failed")
      self.mode="sprites";self.modeId="builtin:resolved-sprites"
    end
  end
  any=drawStadiumActors(context) or any
  local oldFilterMin,oldFilterMag,oldAniso=g.getDefaultFilter()
  g.setDefaultFilter("nearest","nearest",oldAniso or 1)
  g.push("all")
  g.setShader();g.setDepthMode();g.setColor(1,1,1,1)
  for _,side in ipairs({"enemy","player"}) do
    local image=not self.drawn[side] and imageFor(context,side) or nil
    local px,py,targetH=targetGeometry(context,side)
    if image and px and py and targetH then
      local w,h=image:getDimensions()
      if w>0 and h>0 then
        local s=targetH/h
        local sx=s
        if side=="player" and playerFlip() then sx=-s end
        local b=liveBattler(context,side)
        local faint=faintProgress(context,b)
        local grow=growScale(context,b)
        if faint~=nil then
          -- Match BattleState:drawBattlerPic(): preserve the top of the image,
          -- progressively crop rows from the bottom, and slide that visible
          -- portion down into the fixed battlefield baseline. Because the
          -- progress is normalized, a Gen 5 Battle Arts PNG and a ROM sprite
          -- complete the exact same battle-defined faint beat.
          local visibleH=math.max(0,math.floor(h*(1-faint)+.5))
          if visibleH>0 then
            local quad=g.newQuad(0,0,w,visibleH,w,h)
            g.draw(image,quad,px,py,0,sx,s,w*.5,visibleH)
            self.drawn[side]=true;self.presented[side]=true; any=true
          end
        elseif grow~=nil then
          -- AnimateSendingOutMon is authoritative for spawn scale. Preserve
          -- its 0 -> 3/7 -> 5/7 -> full stages in CBE's projected actor slot
          -- instead of popping an external sprite/model to full size. The
          -- source art remains whatever the user's sprite pipeline resolved.
          if grow>0 then
            local eff=s*grow
            local ex=eff
            if side=="player" and playerFlip() then ex=-eff end
            g.draw(image,px,py,0,ex,eff,w*.5,h)
            self.drawn[side]=true;self.presented[side]=true; any=true
          end
        else
          -- Feet are pinned to the projected arena anchor. This mirrors the
          -- engine's battle-slot contract while allowing the Colosseum camera
          -- to move freely around the arena.
          g.draw(image,px,py,0,sx,s,w*.5,h)
          self.drawn[side]=true;self.presented[side]=true; any=true
        end
      end
    end
  end
  g.pop()
  g.setDefaultFilter(oldFilterMin,oldFilterMag,oldAniso or 1)
  return any or externalValue
end

function P:center(context,side)
  local x,z=anchor(context,side); if not x then return nil end
  local arena=context.arena or {}; local k=math.max(.08,tonumber(arena.figureScale) or .38)
  return project(context,x,14/k,z)
end
function P:screenCenter(context,side) return self:center(context,side) end
function P:showing(context,side) return self.drawn[side]==true end
function P:footprint() return 18 end
function P:event(context,name,payload)
  if P.mode=="external" then
    local ok=invokeExternal(context,"event",name,payload)
    if ok then return end
    finishExternal(context,"event-failed")
    P.mode="sprites";P.modeId="builtin:resolved-sprites"
  end
  local S=V.BattleSides
  local side
  local gen2=context and context.battle and context.battle.__cbeGeneration==2
  -- Gen 2's semantic move event is emitted while its pure model batches the
  -- turn, before the screen replays it. StandaloneHost raises the presentation
  -- event when that queued move actually reaches the visible battle screen.
  if name=="battle.move_used" and gen2 then return end
  if name=="battle.move_used" or name=="battle.presentation_move" then
    side=(S and S.payload and S.payload(context,payload,{"user","side"})) or (payload and payload.side)
    local actor=side and stadiumActor(context,side)
    local move=payload and payload.move
    local moveId=(move and (move.index or move.id)) or (payload and payload.moveId)
    local game=context and context.game
    if type(move)~="table" and game and game.data and game.data.moves then
      move=game.data.moves[moveId]
    end
    if type(moveId)~="number" then
      local order=game and game.data and game.data.gen2Constants
        and game.data.gen2Constants.moveOrder
      if type(order)=="table" then
        for i,id in ipairs(order) do if id==moveId then moveId=i;break end end
      end
    end
    if actor and type(actor.attack)=="function" and moveId~=nil then
      pcall(actor.attack,actor,tonumber(moveId) or moveId,move)
    end
  elseif name=="battle.damage_dealt" then
    side=(S and S.payload and S.payload(context,payload,{"target","side"})) or (payload and payload.side)
    local actor=side and stadiumActor(context,side)
    if actor and type(actor.hit)=="function" then pcall(actor.hit,actor) end
  elseif name=="battle.fainted" then
    side=(S and S.payload and S.payload(context,payload,{"battler","side"})) or (payload and payload.side)
    local actor=side and stadiumActor(context,side)
    if actor and type(actor.faint)=="function" then
      local battle=context and context.battle
      local disposition=(side=="player" or (battle and battle.kind~="wild")) and "recall" or "collapse"
      pcall(actor.faint,actor,disposition)
    end
  elseif name=="battle.battler_switched" then
    releaseStadiumActors()
  end
end
function P:finish(context,reason)
  self.drawn.player=false;self.drawn.enemy=false
  self.presented.player=false;self.presented.enemy=false
  finishExternal(context,reason or "battle-ended")
  releaseStadiumActors()
  self.actorApi=nil;self.actorOwner=nil
  self.spriteApi=nil;self.spriteOwner=nil;self.spriteError=nil
  self.mode="sprites";self.modeId="builtin:resolved-sprites"
end
function P:invalidate(context)
  if P.externalProvider then invokeExternal(context,"invalidate") end
  self:finish(context,"invalidated")
end

local function restoreCbeWrapper(built,method,marker)
  local original=rawget(built,marker)
  if original==nil then return false end
  built[method]=(original~=false) and original or nil
  built[marker]=nil
  return true
end

local function patchPreferred(stadium)
  local built=stadium and stadium.exports and stadium.exports.modelProvider
  if type(built)~="table" then return false end

  -- CBE owns the arena and camera, not Stadium's Pokemon lifecycle.
  --
  -- 0.0.67+ temporarily wrapped several Stadium model-provider methods while
  -- trying to arbitrate actor visibility.  That crossed the provider boundary:
  -- StadiumModels already owns opening send-outs, later replacements, switches,
  -- faints, hidden states and its own covers/showing contract.  Intercepting
  -- those methods made the first actor and replacement actors follow different
  -- paths, which is exactly the regression this build removes.
  --
  -- Fresh launches have nothing to restore.  The restoration below exists only
  -- so a development hot reload over an affected CBE build also returns the
  -- SAME Stadium provider table to its pre-CBE methods instead of retaining a
  -- stale wrapper until the process restarts.
  restoreCbeWrapper(built,"update","__cbeOriginalUpdate")
  restoreCbeWrapper(built,"begin","__cbeOriginalBegin")
  restoreCbeWrapper(built,"finish","__cbeOriginalFinish")
  restoreCbeWrapper(built,"covers","__cbeOriginalCovers")
  restoreCbeWrapper(built,"preferredExternal","__cbeOriginalPreferredExternal")

  built.__cbeStartupRecoveryVersion=nil
  built.__cbeStartupRecoveryOwnerInstance=nil
  built.__cbeStartupGrowRecoveryState=nil
  built.__cbeActorPreferenceVersion=nil
  built.__cbePreferenceOwnerInstance=nil

  -- Deliberately DO NOT install a new preferredExternal wrapper.
  -- StadiumBattleFX's registry already gives the saved BTL MODELS selection
  -- authority:
  --   STADIUM DEFAULT -> Stadium's built-in model provider
  --   CURRENT SPRITES -> this CBE provider
  --   any other registered model provider -> that selected provider
  -- That is the user preference contract we want. Merely having Battle Art
  -- installed must not silently override STADIUM DEFAULT, and CBE must not
  -- restart or second-guess Stadium's model session after the choice is made.
  P.preferredPatched=true
  return true
end

function P.register(stadium,api)
  if P.registered then patchPreferred(stadium);return true end
  api=api or (stadium and stadium.exports and stadium.exports.battles)
  if not (api and api.version==1 and type(api.registerComponent)=="function") then return false end
  local id=api:registerComponent(OWNER,"models","current-sprites",{
    label="CURRENT SPRITES",
    description="Use the Pokemon artwork already resolved by the user's active sprite/Battle Art pipeline inside Colosseum environments.",
    provider=P,
    available=function(context) return P:available(context) end,
  })
  P.id=id;P.registered=true
  patchPreferred(stadium)
  return true
end

function P.registerCapability(owner,kind,api)
  owner=tostring(owner or "")
  if owner=="" or owner==OWNER then return false,"invalid capability owner" end
  if kind=="battleSpriteProvider" then kind="battleSprites" end
  if kind=="battlePresenter" then kind="battlePresentation" end
  local valid=(kind=="battleActors" and validActorApi(api))
    or (kind=="battleSprites" and validSpriteApi(api))
    or (kind=="battlePresentation" and validPresentationApi(api))
  if not valid or not registeredCapabilities[kind] then return false,"unsupported capability" end
  registeredCapabilities[kind][owner]=api
  return true
end

function P.unregisterCapability(owner,kind)
  owner=tostring(owner or "")
  if kind=="battleSpriteProvider" then kind="battleSprites" end
  if kind=="battlePresenter" then kind="battlePresentation" end
  local bucket=registeredCapabilities[kind]
  if not bucket then return false end
  bucket[owner]=nil
  return true
end

function P.status()
  local _,id=battleArtHandle()
  local stadium=stadiumService()
  local actorStatus
  if P.actorApi and type(P.actorApi.status)=="function" then
    local ok,value=pcall(P.actorApi.status)
    if ok then actorStatus=value end
  end
  return {registered=P.registered,id=P.id,preferredPatched=P.preferredPatched,
    battleArt=id,battleArtWorld=battleArtWantsWorldSprites(),
    stadiumActors=stadium and true or false,stadiumError=P.stadiumError,
    presentationMode=P.mode,presentationId=P.modeId,actorOwner=P.actorOwner,actorStatus=actorStatus,
    spriteOwner=P.spriteOwner,spriteError=P.spriteError,externalError=P.externalError,
    contract="package-neutral engine sprite, battleSprites v1, battleActors v1 and battlePresentation v1 arbitration"}
end

return P
