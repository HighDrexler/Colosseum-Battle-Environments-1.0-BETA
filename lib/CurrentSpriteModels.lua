-- Generic 2D battler provider for StadiumBattleFX Battle Presentation API v1.
--
-- This deliberately does NOT choose a Pokemon art package. It follows the
-- engine's live pokemon.sprite resolution seam (then portable battleSprites)
-- and only falls back to battle.player/enemy.sprite when nobody overrides it.
-- That keeps Colosseum environments independent from Battle Art, Crystal/Gen 5
-- sprite packs, ROM art, and future providers that use the normal sprite seam.
-- When COLOSSEUM MODELS is ON, however, CBE's GC6E01 actor service is the
-- authoritative 3D battle actor provider in both generations.
local V=...
local MoveFX=V.MoveFXExtractor
local MoveFXVM=V.MoveFXVM
local WazaSequence=V.WazaSequenceRuntime
local Director=V.BattleDirector
local GeneratedAssets=V.GeneratedAssets
local PlayerTrainer=V.PlayerTrainer
local P={
  id=nil, registered=false, preferredPatched=false,
  drawn={player=false,enemy=false}, presented={player=false,enemy=false},
  battleArt=nil, animated=nil,
  stadiumHandle=nil,stadiumApi=nil,stadiumActors={},retiringActors={},stadiumError=nil,
  actorApi=nil,actorOwner=nil,
  spriteApi=nil,spriteOwner=nil,spriteError=nil,
  mode="sprites",modeId="builtin:resolved-sprites",externalProvider=nil,
  externalBegun=false,externalError=nil,presentationFallback=nil,
  moveFxActive={},moveFxImages={},moveFxShader=nil,moveFxError=nil,
}
local OWNER=(V.mod and V.mod.id) or "COLOSSEUM_BATTLE_ENVIRONMENTS"
local ModLookup=V.ModLookup
local registeredCapabilities={battleActors={},battleSprites={},battlePresentation={}}
local seenEventPayload=setmetatable({},{__mode="k"})
local BATTLE_ART_IDS={"BATTLE_ART_VOXEL_GEN2","BATTLE_ART_VOXEL_FORK","DRAMATIC_SHAPE"}
local STADIUM_ID="STADIUM_BATTLE_FX"
local STADIUM2_ID="STADIUM2_OVERWORLD_MODELS"
if ModLookup and type(ModLookup.remember)=="function" then
  ModLookup.remember(STADIUM2_ID)
end

local function releaseActorRecord(record,reason)
  if not record then return false end
  local actor=record.actor
  if actor and type(actor.remove)=="function" then
    pcall(actor.remove,actor,reason or "removed")
  end
  if actor and type(actor.release)=="function" then pcall(actor.release,actor) end
  return true
end

local function releaseStadiumActor(side,reason)
  local record=P.stadiumActors[side]
  if not record then return false end
  P.stadiumActors[side]=nil
  return releaseActorRecord(record,reason)
end

-- Preserve an outgoing 3D actor long enough to play its presentation tail.
-- BattleState swaps the authoritative battler reference before CBE necessarily
-- gets a final render of the old slot, so immediately releasing here makes a
-- switch/return look like a hard pop. Retired actors are presentation-only:
-- they are detached from BattleState and can never write battle state.
local function retireStadiumActor(side,reason)
  local record=P.stadiumActors[side]
  if not record then return false end
  P.stadiumActors[side]=nil
  record.side=side
  record.retireReason=reason or "replacement"
  local actor=record.actor
  local alreadyTerminal=actor and (actor.state=="faint" or actor.state=="recall")
  if actor and not alreadyTerminal and type(actor.recall)=="function" then
    pcall(actor.recall,actor,record.retireReason)
  elseif actor and not alreadyTerminal and type(actor.remove)=="function" then
    pcall(actor.remove,actor,record.retireReason)
  end
  P.retiringActors[#P.retiringActors+1]=record
  return true
end

local function releaseRetiringActors(reason)
  for i=#P.retiringActors,1,-1 do
    local record=P.retiringActors[i]
    table.remove(P.retiringActors,i)
    releaseActorRecord(record,reason or record.retireReason or "removed")
  end
end

local function releaseStadiumActors(reason)
  local sides={}
  for side in pairs(P.stadiumActors) do sides[#sides+1]=side end
  for _,side in ipairs(sides) do releaseStadiumActor(side,reason) end
  releaseRetiringActors(reason)
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
    if P.stadiumHandle~=handle or P.stadiumApi~=nil then releaseStadiumActors("provider-unavailable") end
    P.stadiumHandle=handle;P.stadiumApi=nil
    return nil
  end
  if P.stadiumHandle~=handle or P.stadiumApi~=api then
    releaseStadiumActors("provider-changed");P.stadiumHandle=handle;P.stadiumApi=api
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

local function cbePokemonModelsEnabled(context)
  local settings=V.BattleSettings
  if not (settings and type(settings.pokemonModelsEnabled)=="function") then return true end
  local game=(context and context.game) or (context and context.battle and context.battle.game) or (V.mod and V.mod.game)
  local ok,value=pcall(settings.pokemonModelsEnabled,game)
  return (not ok) or value~=false
end

local function cbePokemonActorService(context)
  if not cbePokemonModelsEnabled(context) then return nil end
  local actors=V.PokemonActors
  local api=actors and actors.service
  if validActorApi(api) and selected(api,context) then return api end
  return nil
end

local function desiredPresentation(context)
  P.presentationFallback=nil

  -- Explicit CBE Pokemon toggle is an ownership override, not a preference.
  -- When ON, GC6E01 Pokemon actors win before every portable presentation,
  -- Stadium registry choice or sprite provider. Missing species still fail open
  -- per-side at acquire(), but another provider cannot steal ownership mid-hit.
  local cbeApi=cbePokemonActorService(context)
  if cbeApi then
    return "stadium","cbe:colosseum-pokemon",cbeApi,{id=OWNER.."/pokemon",exports={}}
  end

  -- Portable POKEMON ACTORS remain compatible, but portable full-frame
  -- battlePresentation providers do not. CBE owns BattleState/world/camera flow
  -- whenever its arena switch is enabled; accepting a battlePresentation here
  -- is equivalent to handing Battle Art/Stadium the whole stage again.
  --
  -- This is deliberately asymmetric: battleActors may supply only Pokemon
  -- meshes/poses inside CBE, while battlePresentation is ignored until CBE
  -- arenas are turned OFF.
  local stageOwned=true
  local C=V.ArenaCatalog
  if C and type(C.enabled)=="function" then
    local game=(context and context.game) or (context and context.battle and context.battle.game) or (V.mod and V.mod.game)
    local ok,value=pcall(C.enabled,game)
    if ok then stageOwned=value~=false end
  end
  if not stageOwned then
    local presenter,presenterHandle=portablePresentationService(context)
    if presenter then
      return "external",tostring(presenterHandle.id)..":battle-presentation",presenter,presenterHandle
    end
  end
  local portable,portableHandle=portableActorService(context)
  if portable then
    return "stadium",tostring(portableHandle.id)..":battle-actors",portable,portableHandle
  end

  -- Below here the Stadium registry may resolve back to this provider, so the
  -- original standalone-host restriction still applies exactly as before.
  if not standaloneContext(context) then
    return "sprites","builtin:resolved-sprites",nil
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
  -- Registry-selected full presentation/compositor providers are never
  -- entered while CBE owns the arena. A provider is accepted here only if it
  -- satisfies the portable battleActors contract; otherwise preserve the
  -- engine-resolved Pokemon art and keep CBE's stage untouched.
  if validActorApi(provider) then
    return "stadium",resolvedId,provider,handle
  end
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
  releaseStadiumActors("presentation-changed")
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

-- WazaSequence is started from BattleDirector on the semantic move boundary,
-- which intentionally receives a lean {battle,game} context before the rich
-- arena compositor context is forwarded. Requiring context.arena here made the
-- type-3 particle handler reject every otherwise-valid source move at start;
-- the native Crystal/GB animation then became the only visible FX. Accept a
-- verified live CBE compositor as equivalent ownership and let the next rich
-- render/update frame lock the actual actor-space basis.
local function cbeFxWorldActive(context)
  if ourArena(context) then return true end
  local host=V and V.StandaloneHost
  if host and type(host.status)=="function" then
    local ok,st=pcall(host.status)
    if ok and type(st)=="table" and st.active==true then return true end
  end
  local bridge=V and V.StadiumBridge
  local battle=context and context.battle
  if bridge and type(bridge.ownsArena)=="function" then
    local ok,owned=pcall(bridge.ownsArena,battle)
    if ok and owned==true then return true end
  end
  return false
end

-- Resolve the exact portable 3D actor provider CBE would use for a Pokemon
-- information surface (Party/Summary) without starting or mutating a battle
-- presentation session. This is intentionally read-only: UI mods may ask for
-- the provider while a menu is open, while CBE keeps authority over whether
-- its environments are enabled and which battleActors capability wins.
--
-- Returning nil means the caller MUST use the engine-resolved sprite path.
-- That preserves Battle Arts, Crystal/custom sprite packs and vanilla art when
-- CBE is disabled or when CBE itself would not use a portable actor provider.
function P.informationActorProvider(request)
  request=type(request)=="table" and request or {}
  local game=request.game or (V.mod and V.mod.game)
  local mon=request.mon or request.pokemon
  local battler=request.battler
  if type(battler)~="table" and type(mon)=="table" then battler={mon=mon} end
  local context={
    apiVersion=1,
    game=game,
    battle=nil,
    sides={player={battler=battler},enemy={battler=nil}},
    phase="information",progress=1,groundY=0,
    services={cbeStandalone=true,informationSurface=true},
  }
  local mode,id,provider,handle=desiredPresentation(context)
  if mode~="stadium" or not validActorApi(provider) then
    return nil,tostring(mode or "sprites"),context
  end
  return provider,tostring(id or "portable-actors"),context,
    handle and handle.id or nil
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

-- Battle Art 2.x does not publish its selected battle Pokemon exclusively
-- through pokemon.sprite. STATIC/ANIMATED modes intentionally install prepared
-- Image objects directly on the live battler, while MODDED yields ownership to
-- whichever lower sprite provider won the engine seam. CBE therefore consumes
-- Battle Art through its exported compatibility library when COLOSSEUM MODELS
-- is OFF.
--
-- `advance` is true from update() and false from the draw consumer boundary.
-- GenerationCompat gives Gold a stable Gen-1-shaped facade, so the same art
-- managers work in both generations without writing transient sprite fields
-- onto the user's saved Gen 2 party records.
local function syncBattleArtSpecies(context,dt,advance)
  if not (context and context.battle) then return false end
  if cbePokemonModelsEnabled(context) then P.spriteOwner=nil;return false end
  local runtime=battleArtRuntime()
  local art=runtime and runtime.art
  if not art then return false end
  local battle=context.battle
  local animated=P.animated

  -- Advance atlas playback exactly once per update. The final draw path calls
  -- this with advance=false after GenerationCompat has refreshed Gold's native
  -- picture fields; reassert below restores the selected frame without ticking
  -- its clock twice.
  if advance and animated and type(animated.update)=="function" then
    pcall(animated.update,battle,math.max(0,tonumber(dt) or 0))
  end

  -- STATIC mode is installed here. In ANIMATED mode BattleArt.apply() releases
  -- stale static ownership but does not overwrite AnimatedBattleArt's manager.
  -- In MODDED mode it is intentionally a species no-op, leaving the generic
  -- pokemon.sprite / other-provider fallback below authoritative.
  if type(art.apply)=="function" then pcall(art.apply,battle) end

  if animated and type(animated.reassert)=="function" then
    if battle.enemy then pcall(animated.reassert,battle.enemy) end
    if battle.player then pcall(animated.reassert,battle.player) end
  end
  local owns=true
  if type(art.ownsSpeciesArt)=="function" then
    local ok,value=pcall(art.ownsSpeciesArt)
    owns=ok and value~=false
  end
  P.spriteOwner=owns and runtime.id or nil
  return owns
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

-- Native battle scripts are free to rebuild lightweight battler wrappers while
-- their visual queue is running. A resident model in one of these presentation
-- states is the same visual actor until an explicit replacement event says
-- otherwise. Fly/Dig remain the only supported attacks whose hidden state is
-- semantically part of the move instead of stock picture choreography.
local STRUCTURAL_HIDE_MOVE={[19]=true,[91]=true,fly=true,dig=true}
local function actorStructuralHide(actor)
  if not actor then return false end
  local move=actor.lastMove
  local key=tonumber(move) or tostring(move or ""):lower():gsub("[^a-z0-9]","")
  return STRUCTURAL_HIDE_MOVE[key]==true
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
    releaseStadiumActor(side,"missing-dex")
    return nil
  end
  local key=tostring(dex)..":"..variant
  if record and record.key==key then
    -- Gen I rebuilds lightweight battler/mon wrappers much more aggressively
    -- than Gold. Species + variant are the stable visual identity; the explicit
    -- battle.battler_switched event owns real replacement/recall. Requiring Lua
    -- table identity here caused idle Gen-I actors to be retired/reacquired
    -- between update/draw calls, producing visible gaps and repeated cache work.
    record.battler=battler
    return record.actor
  end
  if record then retireStadiumActor(side,"replacement") end
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
  P.stadiumActors[side]={key=key,actor=actor,dex=dex,variant=variant,
    battler=battler,state="spawn"}
  return actor
end

local growScale
local function visible(context,side)
  local battle=context and context.battle
  local b=liveBattler(context,side)
  if not (battle and b and b.sprite) then return false end
  if side=="enemy" then
    if PlayerTrainer and type(PlayerTrainer.captureHidesEnemy)=="function" then
      local okHide,hide=pcall(PlayerTrainer.captureHidesEnemy,PlayerTrainer,context)
      if okHide and hide then return false end
    end
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

-- 3D actors deliberately do NOT mirror BattleState:fxHidden(). In Gen 1 that
-- method is the stock damage-blink bit: five frames hidden, five visible, six
-- times. Applying it to a persistent 3D actor makes the entire model vanish on
-- every hit and, worse, the old lifecycle path interpreted the blink as an
-- authoritative removal. The actor owns its own hit flash/recoil instead.
--
-- Structural visibility (trainers occupying the slot, send-out scale 0, or a
-- real Gen-2 vanished/Fly-Dig state) is still respected, and faint completion is
-- handled separately so this does not resurrect a genuinely removed battler.
local function actorVisible(context,side,actor)
  local battle=context and context.battle
  local b=liveBattler(context,side)
  -- Persistent 3D actors are keyed to the authoritative battler/mon, NOT to the
  -- native 2D picture object. Gen1Recomp is allowed to clear b.sprite and toggle
  -- picHidden/playerHidden/enemyHidden during its stock damage blink. Treating
  -- any of those picture-layer states as actor lifecycle made the entire model
  -- vanish on impact even though Actor:hit() itself never removes the actor.
  if not (battle and b) then return false end
  if side=="enemy" then
    if PlayerTrainer and type(PlayerTrainer.captureHidesEnemy)=="function" then
      local okHide,hide=pcall(PlayerTrainer.captureHidesEnemy,PlayerTrainer,context)
      if okHide and hide then return false end
    end
    if battle.showEnemyTrainer then return false end
    if battle.enemySendingOut then
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

  -- Only a dedicated structural actor-hide signal may suppress a live 3D model.
  -- Gen 2 exposes Fly/Dig-style vanished state here; ordinary picture hiding is
  -- intentionally excluded. Gen 1 currently has no stronger structural signal,
  -- so persistence wins over transient native-picture visibility.
  -- Picture-layer HIDEPIC/vanish flags are never model lifecycle for CBE.
  -- Consult the structural hide hook only for Fly/Dig themselves; for every
  -- other move, a live resident Pokemon remains draw-eligible continuously
  -- through attack, impact, damage blink, hit recovery and the lethal handoff.
  -- This is the hard persistence invariant: animation state may change, model
  -- existence/visibility may not.
  if actorStructuralHide(actor) and type(battle.actorHidden)=="function" then
    local ok,hidden=pcall(battle.actorHidden,battle,b)
    if ok and hidden then return false end
  end

  if b.fainted then
    -- HP reaching zero is not itself an actor-removal event. On lethal hits the
    -- battle model can set `fainted` before the later visible faint queue item.
    -- Keep the resident model present through the complete Damage reaction and
    -- through that hand-off; battle.fainted will move the SAME actor into its
    -- authored faint clip. This removes the blank gap seen immediately on hit.
    if actor and (actor.state=="hit" or actor.pendingFaint) then return true end
    local faintActive=false
    if type(battle.fxFaintActive)=="function" then
      local ok,value=pcall(battle.fxFaintActive,battle,b)
      faintActive=ok and value==true
    end
    if faintActive then return actor~=nil end
    -- Let a provider finish its authored/fallback faint tail even after the
    -- Game Boy slide has ended. It remains presentation-only and covers() keeps
    -- the native sprite suppressed during this tail.
    if actor and actor.state=="faint" then
      if type(actor.terminalComplete)=="function" then
        local ok,done=pcall(actor.terminalComplete,actor)
        if ok then return not done end
      end
      return true
    end
    -- One or more frames can exist between lethal damage and battle.fainted.
    -- Keeping the resident actor alive here is deliberate; releasing it would
    -- make the subsequent faint event target an actor that no longer exists.
    return actor~=nil
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

local function actorGoneByBattle(context,b,actor)
  local battle=context and context.battle
  if not (battle and b) then return true end

  -- Do not consult fxHidden here: in Gen 1 it is only the stock damage blink,
  -- not a lifecycle/removal signal. Releasing a 3D actor because one blink
  -- frame is hidden is the exact cause of the 1.5.27 hit-disappearance bug.
  if b.fainted==true then
    -- A lethal damage result precedes the visible faint event on both supported
    -- battle queues. Never destroy the resident actor merely because HP is zero;
    -- it must finish hit, receive battle.fainted, then finish its faint tail.
    if actor and (actor.state=="hit" or actor.pendingFaint) then return false end
    if actor and actor.state=="faint" then
      if faintProgress(context,b)~=nil then return false end
      if type(actor.terminalComplete)=="function" then
        local ok,done=pcall(actor.terminalComplete,actor)
        if ok then return done end
      end
      return false
    end
    -- Between damage and the faint event the actor may still be in idle/attack.
    -- Keep it resident so the faint event can transition the same object rather
    -- than trying to animate a model that was already released.
    return actor==nil
  end
  return false
end

-- Keep actor identity tied to the authoritative BattleState slot. This is the
-- lifecycle seam: a switch replaces only the changed side, even when the new
-- Pokemon has the same species/variant key as the old one.
local function syncStadiumActor(context,side)
  local record=P.stadiumActors[side]
  if not record then return nil end
  local battler=liveBattler(context,side)
  if battler~=record.battler then
    -- Wrapper identity is not stable in Gen I. Keep the resident actor whenever
    -- the authoritative visual identity (National Dex + shiny variant) is the
    -- same, regardless of whether the engine rebuilt the battler or mon table.
    -- A real switch to a different visual identity still retires immediately;
    -- same-species switches are handled by the explicit battler_switched event.
    local newDex,newVariant=dexFor(context,battler)
    if tonumber(newDex)==tonumber(record.dex) and tostring(newVariant)==tostring(record.variant) then
      record.battler=battler
    else
      retireStadiumActor(side,"replacement")
      return nil
    end
  end
  if actorGoneByBattle(context,battler,record.actor) then
    releaseStadiumActor(side,battler and battler.fainted and "faint-complete" or "hidden")
    return nil
  end
  return record.actor
end

local function driveSpawn(context,side,actor)
  if not actor then return end
  local battler=liveBattler(context,side)
  local scale=growScale(context,battler)
  if scale==nil then scale=1 end
  if side=="enemy" and PlayerTrainer and type(PlayerTrainer.captureEnemyScale)=="function" then
    local okCapture,captureScale=pcall(PlayerTrainer.captureEnemyScale,PlayerTrainer,context)
    if okCapture and tonumber(captureScale) then scale=scale*math.max(0,math.min(1,tonumber(captureScale))) end
  end
  if type(actor.spawn)=="function" then
    pcall(actor.spawn,actor,scale,{side=side,context=context,battler=battler})
  elseif scale>=1 and type(actor.idle)=="function" then
    pcall(actor.idle,actor)
  end
  local record=P.stadiumActors[side]
  if record then record.state=scale<1 and "spawn" or "idle" end
end

local function driveRetiringActor(context,record)
  local actor=record and record.actor
  if not actor then return end
  local battle=context and context.battle
  if actor.state=="recall" and battle and type(battle.shrinkOutScale)=="function"
      and record.battler and type(actor.setRecallScale)=="function" then
    local ok,scale=pcall(battle.shrinkOutScale,battle,record.battler)
    if ok and type(scale)=="number" then
      pcall(actor.setRecallScale,actor,scale)
    end
  end
end

local EnginePokemonSprites,EngineAssets
local function engineResolvedSprite(context,side,b,current)
  -- CBE's standalone Gen 2 arena does not ask BattleState to draw its native
  -- picture layer, so simply reusing battler.sprite can strand us on the ROM
  -- image even when another mod owns the sanctioned pokemon.sprite seam.
  -- Resolve that seam again here and use it ONLY when it actually selects a
  -- different path. This preserves Battle Arts/custom packs without replacing
  -- Gold's already-palette-processed native image with a raw source bitmap.
  local mon=b and b.mon
  local game=(context and context.game) or (context and context.battle and context.battle.game)
  local data=game and game.data
  local species=mon and mon.species
  if not (data and species) then return current,false end
  local req=V.engineRequire or require
  if EnginePokemonSprites==nil then
    local ok,value=pcall(req,"src.pokemon.Sprites")
    EnginePokemonSprites=ok and value or false
  end
  if EngineAssets==nil then
    local ok,value=pcall(req,"src.render.Assets")
    EngineAssets=ok and value or false
  end
  if not (type(EnginePokemonSprites)=="table" and type(EnginePokemonSprites.path)=="function"
      and type(EngineAssets)=="table" and type(EngineAssets.image)=="function") then
    return current,false
  end
  local def=data.pokemon and data.pokemon[species]
  local facing=side=="player" and "back" or "front"
  local vanilla=def and (facing=="back" and def.spriteBack or def.spriteFront) or nil
  local ok,path,trueColor=pcall(EnginePokemonSprites.path,data,species,facing,{mon=mon,kind="battle"})
  if not ok or type(path)~="string" or path=="" then return current,false end
  -- A changed path is an explicit external-art decision. trueColor is advisory
  -- metadata and by itself must not make us reload the unchanged ROM image.
  if vanilla and path==vanilla then return current,false end
  local okImage,resolved=pcall(EngineAssets.image,path)
  if not (okImage and resolved and type(resolved.getDimensions)=="function") then
    return current,false
  end
  if resolved.setFilter then pcall(resolved.setFilter,resolved,"nearest","nearest") end
  return resolved,true
end

local function imageFor(context,side)
  if not visible(context,side) then return nil end
  -- StandaloneHost re-syncs Gold's presentation facade immediately before the
  -- world pass, which refreshes b.sprite from the native BattleState. Reapply
  -- Battle Art at the consumer boundary so STATIC/ANIMATED selections survive
  -- that sync; no playback time advances here.
  local battleArtOwns=syncBattleArtSpecies(context,0,false)
  local battle=context.battle
  local b=liveBattler(context,side)
  local image=b and b.sprite
  if image and type(battle.picImage)=="function" then
    local ok,resolved=pcall(battle.picImage,battle,image)
    if ok and resolved then image=resolved end
  end

  -- First recover the engine's live sprite-selection seam. This is what lets
  -- Battle Arts, Crystal/custom sprite packs and future pokemon.sprite owners
  -- stay authoritative when COLOSSEUM MODELS is OFF.
  local seamOwned=false
  local spriteApi,spriteHandle
  P.spriteError=nil

  if not battleArtOwns then
    local seamImage
    seamImage,seamOwned=engineResolvedSprite(context,side,b,image)
    if seamOwned then image=seamImage end

    -- A portable battleSprites provider is more explicit than a generic path
    -- hook. It is consulted only when Battle Art has itself yielded species
    -- ownership (MODDED) or is absent; BATTLE ART ownership must not be undone
    -- by a second provider after BattleArt.apply selected the user's package.
    spriteApi,spriteHandle=portableSpriteService(context)
    P.spriteApi=spriteApi
    if spriteHandle then
      P.spriteOwner=spriteHandle.id
    elseif seamOwned then
      P.spriteOwner="engine:pokemon.sprite"
    elseif not battleArtWantsWorldSprites() then
      P.spriteOwner=nil
    end
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
  else
    P.spriteApi=nil
  end
  if not (image and type(image.getDimensions)=="function") then return nil end
  return image,b
end

-- Constant side-iteration orders. These table literals used to be rebuilt on
-- every frame at each of the five loops below.
local SIDES_EP={"enemy","player"}
local SIDES_PE={"player","enemy"}
-- Reused faint-clip quad; g.newQuad allocated a new LOVE object every frame a
-- Pokemon was fainting, which is exactly the moment the frame budget is
-- tightest.
local faintQuad=nil

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


-- 1.5.38 source move-FX runtime. The extractor now preserves GPT1 generator
-- headers + particle bytecode, and MoveFXVM executes those source commands at
-- runtime. The old style compositor (projectile/wave/contact rings) is gone:
-- CBE no longer decides how a move's particles should travel based on move type.
local MOVE_FX_PIXEL=[[
extern vec4 cbePrim;
extern vec4 cbeEnv;
extern float cbePrimEnv;
extern float cbeAlphaCutoff;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec4 t=Texel(texture,uv);
  if (t.a < cbeAlphaCutoff) discard;
  if (cbePrimEnv > 0.5) {
    // GX particle Prim/Env textures use intensity as the interpolation weight.
    // Preserve that source gradient instead of flattening I4/I8 into a white
    // alpha mask and applying one CBE-authored tint.
    float k=clamp(t.r,0.0,1.0);
    vec3 rgb=mix(cbeEnv.rgb,cbePrim.rgb,k);
    float a=t.a*mix(cbeEnv.a,cbePrim.a,k);
    return vec4(rgb,a)*color;
  }
  return vec4(t.rgb*cbePrim.rgb,t.a*cbePrim.a)*color;
}
]]
local function moveFxShader()
  if P.moveFxShader~=nil then return P.moveFxShader or nil end
  if not (love and love.graphics and love.graphics.newShader) then P.moveFxShader=false;return nil end
  local ok,sh=pcall(love.graphics.newShader,MOVE_FX_PIXEL)
  P.moveFxShader=ok and sh or false
  if not ok then P.moveFxError=tostring(sh) end
  return ok and sh or nil
end

local function moveFxImage(spec)
  if not (GeneratedAssets and spec and spec.path and love and love.image and love.graphics) then return nil end
  local cached=P.moveFxImages[spec.path]
  if cached~=nil then return cached or nil end
  local bytes=GeneratedAssets.read(spec.path)
  if type(bytes)~="string" then P.moveFxImages[spec.path]=false;return nil end
  local okData,data=pcall(love.image.newImageData,spec.w,spec.h,"rgba8",bytes)
  if not okData or not data then P.moveFxImages[spec.path]=false;return nil end
  local okImg,img=pcall(love.graphics.newImage,data)
  if not okImg or not img then P.moveFxImages[spec.path]=false;return nil end
  if not pcall(img.setFilter,img,"linear","linear",8) then pcall(img.setFilter,img,"linear","linear",1) end
  P.moveFxImages[spec.path]=img
  return img
end

local refreshMoveFxBasis
local sourceRootAttachment

local function roleHasSource(spec,role)
  return MoveFXVM and type(MoveFXVM.hasRole)=="function" and MoveFXVM.hasRole(spec,role)
end
local function roleHasTimeline(spec,role)
  if not (WazaSequence and type(WazaSequence.hasTimeline)=="function") then return false end
  local ok,has=pcall(WazaSequence.hasTimeline,WazaSequence,spec,role)
  return ok and has==true
end
local function wazaEntryKey(entry)
  if type(entry)~="table" then return nil end
  return table.concat({tostring(entry.phase or ""),tostring(entry.identifier or ""),
    tostring(entry.index or ""),tostring(entry.offset or "")},"|")
end

local function stageMoveFx(context,side,spec,target,role,wazaEntry,wazaSerial)
  role=role or "attack"
  local executable=MoveFXVM and type(MoveFXVM.start)=="function"
    and ((type(wazaEntry)=="table" and type(MoveFXVM.hasEntry)=="function" and MoveFXVM.hasEntry(spec,wazaEntry,role))
      or (wazaEntry==nil and roleHasSource(spec,role)))
  if not (side and cbeFxWorldActive(context) and type(spec)=="table"
      and type(spec.textures)=="table" and #spec.textures>0
      and type(spec.generatorPrograms)=="table" and #spec.generatorPrograms>0
      and executable) then
    return false
  end
  local imagesByBank={};local imageCount=0
  for _,tex in ipairs(spec.textures) do
    local img=moveFxImage(tex)
    if img then
      local bank=tonumber(tex.bank) or 1
      imagesByBank[bank]=imagesByBank[bank] or {}
      imagesByBank[bank][#imagesByBank[bank]+1]={image=img,spec=tex}
      imageCount=imageCount+1
    end
  end
  for _,list in pairs(imagesByBank) do
    table.sort(list,function(a,b)
      local ac,bc=tonumber(a.spec.container) or 0,tonumber(b.spec.container) or 0
      if ac~=bc then return ac<bc end
      return (tonumber(a.spec.texture) or 0)<(tonumber(b.spec.texture) or 0)
    end)
  end
  if imageCount==0 then P.moveFxError="source GPT1 textures failed to create LÖVE images";return false end
  -- One Waza SequenceEntry owns one VM launch. Some hosts can surface the same
  -- semantic boundary through more than one wrapper; never duplicate the exact
  -- source entry while allowing distinct entries in the same Waza serial.
  local entryKey=wazaEntryKey(wazaEntry)
  if wazaSerial and entryKey then
    for _,old in ipairs(P.moveFxActive) do
      if old.wazaSerial==wazaSerial and old.wazaEntryKey==entryKey then return true end
    end
  end

  -- A new attack phase supersedes any source FX still owned by the same
  -- attacker. The previous VM could legally survive for seconds after its move,
  -- which is why contact debris appeared during the following command. Damage
  -- wrappers can be duplicated by presentation hosts; suppress only an
  -- immediate duplicate of the same source bank while preserving real multi-hit
  -- impacts that arrive later.
  for i=#P.moveFxActive,1,-1 do
    local old=P.moveFxActive[i]
    if role=="attack" and old.side==side and (not wazaSerial or old.wazaSerial~=wazaSerial) then
      table.remove(P.moveFxActive,i)
    elseif not wazaSerial and role=="damage" and old.side==side and old.spec==spec and old.role=="damage"
        and old.vm and (tonumber(old.vm.age) or 1)<0.065 then
      return true
    end
  end

  local okVm,vm=pcall(MoveFXVM.start,spec,{role=role,entry=wazaEntry,
    sequenceStartHandled=wazaEntry~=nil})
  if not okVm or type(vm)~="table" or #(vm.emitters or {})==0 then
    P.moveFxError=tostring(okVm and "source GPT1 phase has no executable generators" or vm);return false
  end
  P.moveFxError=nil
  local active={
    side=side,target=target or (side=="player" and "enemy" or "player"),spec=spec,role=role,
    vm=vm,imagesByBank=imagesByBank,wazaEntry=wazaEntry,wazaSerial=wazaSerial,wazaEntryKey=entryKey,
    rootAttachment=(type(wazaEntry)=="table" and tonumber(wazaEntry.attachment)) or sourceRootAttachment(spec,role),
  }
  P.moveFxActive[#P.moveFxActive+1]=active
  refreshMoveFxBasis(context,active)
  return true
end

local wazaHandlersInstalled=false
local function installWazaHandlers()
  if wazaHandlersInstalled or not (WazaSequence and type(WazaSequence.registerHandler)=="function") then return end
  local handler={
    start=function(context,instance,entry)
      return stageMoveFx(context,instance.side,instance.spec,instance.target,instance.role,entry,instance.serial)
    end,
    -- Normal sequence completion does not truncate a GPT1 program; generator
    -- and particle lifetimes remain source-authoritative after the entry start.
    finish=function() return true end,
    -- Cancellation is different: a superseded Waza must not strand old source
    -- effects in the following move/camera beat. Remove only FX owned by this
    -- exact Waza serial, preserving legitimate concurrent damage sequences.
    cancel=function(context,instance)
      for i=#P.moveFxActive,1,-1 do
        if P.moveFxActive[i].wazaSerial==instance.serial then table.remove(P.moveFxActive,i) end
      end
      return true
    end,
  }
  WazaSequence:registerHandler("particle","cbe-gpt1",handler)
  wazaHandlersInstalled=true
end

local function actorWazaTiming(actor)
  if actor and type(actor.wazaTimingPoints)=="function" then
    local ok,points=pcall(actor.wazaTimingPoints,actor)
    if ok and type(points)=="table" then return points end
  end
  return nil
end

local function startWazaSequence(context,side,spec,target,role,moveId,move)
  if not (WazaSequence and type(WazaSequence.hasTimeline)=="function" and type(WazaSequence.start)=="function") then return false end
  installWazaHandlers()
  local okHas,has=pcall(WazaSequence.hasTimeline,WazaSequence,spec,role)
  if not okHas or not has then return false end
  local timingSide=(role=="damage" and target) or side
  local timingActor=timingSide and P.stadiumActors[timingSide] and P.stadiumActors[timingSide].actor or nil
  if not timingActor and timingSide then timingActor=stadiumActor(context,timingSide) end
  local points=actorWazaTiming(timingActor)
  local presentationFrames
  if timingActor and type(timingActor.stateDuration)=="function" then
    local stateKind=role=="damage" and "hit" or "attack"
    local okDur,dur=pcall(timingActor.stateDuration,timingActor,stateKind)
    if okDur and tonumber(dur) then presentationFrames=math.floor(math.max(0,tonumber(dur))*60+.5) end
  end
  local ok,inst,err=pcall(WazaSequence.start,WazaSequence,context,side,spec,{role=role,target=target,moveId=moveId,move=move,
    globalTimingPoints=points,presentationFrames=presentationFrames})
  if not ok or type(inst)~="table" then
    P.moveFxError=tostring(ok and (err or "WazaSequence did not start") or inst)
    return false
  end
  -- Starting the retail timeline is the ownership decision. It may contain
  -- controller/audio/model entries that are not yet drawable by one handler;
  -- never launch a second whole-role GPT1 fallback in parallel with it.
  return true
end

local function startMoveFx(context,side,moveId,move,role,target)
  if not (MoveFX and side and ourArena(context)) then return false end
  local spec,err
  if type(MoveFX.peek)=="function" then
    local ok,value,why=pcall(MoveFX.peek,moveId,move)
    if ok and type(value)=="table" then spec=value else err=why or value end
  end
  if not spec then
    if type(MoveFX.queuePrefetch)=="function" then pcall(MoveFX.queuePrefetch,moveId,move,context and context.battle) end
    P.moveFxError=tostring(err or "source WZX cache not prepared; queued without blocking battle")
    return false
  end
  if not (type(spec.generatorPrograms)=="table" and #spec.generatorPrograms>0) then
    P.moveFxError=tostring(err or (spec and spec.note) or "source WZX has no decoded GPT1 program bank")
    return false
  end
  return stageMoveFx(context,side,spec,target,role or "attack")
end

-- BattleDirector still owns shared move/camera/trainer timing. Consume its FX cue
-- so the director can retire the move sequence, but do not use its old
-- style-derived cue time to launch particles: GPT1 has its own sequence timing.
local function directedMoveFx(context)
  if not (Director and type(Director.consumeFxCue)=="function") then return false end
  for _,side in ipairs(SIDES_PE) do pcall(Director.consumeFxCue,Director,context,side) end
  return false
end

local function updateMoveFx(context,dt)
  local step=math.max(0,tonumber(dt) or 0)
  for i=#P.moveFxActive,1,-1 do
    local fx=P.moveFxActive[i]
    refreshMoveFxBasis(context,fx)
    local ok,alive=pcall(MoveFXVM.update,fx.vm,step)
    if not ok then
      P.moveFxError=tostring(alive);table.remove(P.moveFxActive,i)
    elseif alive==false or (fx.vm and fx.vm.done) then
      table.remove(P.moveFxActive,i)
    end
  end
end

local BODY_SLOT_NAMES={
  "origin","mouth","chest","tail","eye_left","eye_right","hand_left","hand_right",
  "additional_1","additional_2","additional_3","additional_4","foot_left","foot_right","center","additional_5",
}

local function actorAttachmentWorld(side,name)
  local rec=P.stadiumActors and P.stadiumActors[side]
  local actor=rec and rec.actor
  if actor and type(actor.attachment)=="function" then
    local ok,a=pcall(actor.attachment,actor,name)
    local p=ok and type(a)=="table" and a.position
    if type(p)=="table" and tonumber(p[1]) and tonumber(p[2]) and tonumber(p[3]) then
      return {tonumber(p[1]),tonumber(p[2]),tonumber(p[3])},actor
    end
  end
  return nil,actor
end

-- Actor geometry is rendered with arena.actorVP = stageVP * figureScale. Keep
-- particle anchors in that exact pre-figure-scale actor world, then project by
-- the same figureScale so Pokemon and attached MoveFX cannot drift apart when a
-- venue changes its figure scale.
local function moveFxWorldPoint(context,side,name)
  local p,actor=actorAttachmentWorld(side,name or "center")
  if not p and name~="chest" then p,actor=actorAttachmentWorld(side,"chest") end
  if p then return p,actor,true end
  local x,z=anchor(context,side);if not x then return nil end
  local arena=context.arena or {};local k=math.max(.08,tonumber(arena.figureScale) or .38)
  local rel=tonumber(actor and actor.physicalScale) or .72
  rel=math.max(.30,math.min(2.20,rel))
  local y=13*(rel/.72)
  y=math.max(6.6,math.min(31,y))
  return {x,y/k,z},actor,false
end

local function projectMoveFxWorld(context,p)
  if not (p and p[1]) then return nil end
  local k=tonumber(context and context.services and context.services.figureScale)
    or tonumber(context and context.arena and context.arena.figureScale) or .38
  return project(context,(p[1] or 0)*k,(p[2] or 0)*k,(p[3] or 0)*k)
end

local function vsub(a,b)return {(a[1] or 0)-(b[1] or 0),(a[2] or 0)-(b[2] or 0),(a[3] or 0)-(b[3] or 0)} end
local function vdot(a,b)return (a[1] or 0)*(b[1] or 0)+(a[2] or 0)*(b[2] or 0)+(a[3] or 0)*(b[3] or 0) end
local function vlen(v)return math.sqrt(vdot(v,v)) end
local function vnorm(v)
  local l=vlen(v);if l<1e-8 then return {0,0,1} end
  return {v[1]/l,v[2]/l,v[3]/l}
end
local function vcross(a,b)return {(a[2] or 0)*(b[3] or 0)-(a[3] or 0)*(b[2] or 0),(a[3] or 0)*(b[1] or 0)-(a[1] or 0)*(b[3] or 0),(a[1] or 0)*(b[2] or 0)-(a[2] or 0)*(b[1] or 0)} end
local function effectBasis(source,target)
  -- Keep Waza "up" tied to the arena instead of tilting the entire source
  -- coordinate frame when two differently sized Pokemon have attachment points
  -- at different heights. Forward is the horizontal fight line; authored Y is
  -- therefore always vertical and ground-plane effects stay on the floor.
  local delta=vsub(target,source)
  local flat={delta[1] or 0,0,delta[3] or 0}
  local forward=vnorm(vlen(flat)>1e-6 and flat or delta)
  local up={0,1,0}
  local right=vnorm(vcross(up,forward))
  if vlen(right)<1e-6 then right={1,0,0} end
  forward=vnorm(vcross(right,up))
  return right,up,forward
end

local GROUND_FIELD_MOVES={
  [89]=true,  -- Earthquake
  [222]=true, -- Magnitude
}
local function actorVisualHeight(actor)
  local h=tonumber(actor and actor.height) or 16
  local scale=tonumber(actor and actor.worldScale) or 1
  return math.max(.25,h*scale)
end
local function combatGeometry(context,side,target,attachment,opts)
  opts=type(opts)=="table" and opts or {}
  local slot=tonumber(attachment)
  local name=(slot and slot>=0 and slot<#BODY_SLOT_NAMES) and BODY_SLOT_NAMES[math.floor(slot)+1] or "center"
  local other=target or (side=="player" and "enemy" or "player")
  local origin,actor=moveFxWorldPoint(context,side,name)
  local goal,targetActor=moveFxWorldPoint(context,other,"center")
  if not (origin and goal) then return nil end

  local sourceHeight=actorVisualHeight(actor)
  local targetHeight=actorVisualHeight(targetActor)
  local fullFightDistance=vlen(vsub(goal,origin))
  local moveId=tonumber(opts.moveId)
  local style=tostring(opts.style or ""):lower()
  local role=tostring(opts.role or "attack"):lower()
  local groundField=role=="attack" and GROUND_FIELD_MOVES[moveId]==true

  -- Earthquake/Magnitude are authored as field-space effects, not a giant
  -- object hanging from the attacker's chest. Anchor them to the arena floor
  -- at the midpoint of the two live combat slots while retaining the source
  -- attacker->target direction. Damage-phase rows still bind to the target.
  if groundField then
    local sx,sz=anchor(context,side);local tx,tz=anchor(context,other)
    if sx and tx then
      local gy=tonumber(context and context.groundY) or 0
      origin={(sx+tx)*.5,gy,(sz+tz)*.5}
      goal={tx,gy,tz}
      fullFightDistance=math.sqrt((tx-sx)^2+(tz-sz)^2)
    else
      local gy=tonumber(context and context.groundY) or 0
      origin={(origin[1]+goal[1])*.5,gy,(origin[3]+goal[3])*.5}
    end
  end

  local right,up,forward=effectBasis(origin,goal)
  local sourceUnit=sourceHeight/100
  local units={x=sourceUnit,y=sourceUnit,z=sourceUnit}

  -- Source GPT1 coordinates describe local effect motion, but projectiles also
  -- need to traverse the live combat span. Scale lateral/vertical motion from
  -- the actor and forward motion from the fight line, bounded relative to the
  -- actor so tiny/giant Pokemon cannot explode the authored trajectory.
  if style=="projectile" then
    local fightUnit=math.max(.01,fullFightDistance/100)
    units.z=math.max(sourceUnit*.65,math.min(sourceUnit*6.0,fightUnit))
  elseif style=="wave" then
    local fightUnit=math.max(.01,fullFightDistance/100)
    units.x=math.max(sourceUnit*.80,math.min(sourceUnit*3.0,fullFightDistance/180))
    units.z=math.max(sourceUnit*.80,math.min(sourceUnit*5.0,fightUnit))
  elseif groundField then
    local fieldUnit=math.max(.01,fullFightDistance/100)
    units.x=fieldUnit;units.z=fieldUnit
    units.y=((sourceHeight+targetHeight)*.5)/100
  end

  -- Scale from the live actors rather than species ids or a fixed Colosseum
  -- unit.  Self/aura effects remain attacker-sized, damage rows remain the
  -- damaged actor's size, and contact/impact effects use a bounded geometric
  -- mean of both battlers.  The latter is important for extreme matchups (for
  -- example a tiny attacker striking Onix): fitting only to the user made the
  -- hit almost invisible, while fitting only to the target made it comically
  -- oversized around a small attacker.
  local interactionHeight=math.sqrt(math.max(.01,sourceHeight*targetHeight))
  interactionHeight=math.max(math.min(sourceHeight,targetHeight)*.72,
    math.min(math.max(sourceHeight,targetHeight)*1.12,interactionHeight))
  local referenceHeight
  if groundField then referenceHeight=(sourceHeight+targetHeight)*.5
  elseif role=="damage" then referenceHeight=sourceHeight
  elseif style=="target" then referenceHeight=targetHeight
  elseif style=="impact" or style=="contact" then referenceHeight=interactionHeight
  else referenceHeight=sourceHeight end

  local modelTargetSpan
  if groundField then modelTargetSpan=math.max(referenceHeight,fullFightDistance*1.08)
  elseif style=="wave" then modelTargetSpan=math.max(referenceHeight,fullFightDistance*.82)
  elseif style=="projectile" then
    -- Projectile bodies originate at the user, but their maximum apparent
    -- size may grow modestly toward the opponent. Keep this tightly bounded so
    -- small/large species combinations cannot balloon the source HSD object.
    local projectileHeight=math.max(sourceHeight*.80,math.min(interactionHeight*1.12,sourceHeight*1.85))
    modelTargetSpan=math.max(projectileHeight*.80,math.min(fullFightDistance*.72,projectileHeight*2.55))
  elseif role=="damage" then modelTargetSpan=sourceHeight*.92
  elseif style=="target" then modelTargetSpan=targetHeight*.92
  elseif style=="impact" or style=="contact" then modelTargetSpan=interactionHeight*.86
  else modelTargetSpan=referenceHeight end

  return {origin=origin,target=goal,right=right,up=up,forward=forward,actor=actor,targetActor=targetActor,
    actorScale=tonumber(actor and actor.worldScale) or 1,attachment=name,style=style,moveId=moveId,role=role,
    groundField=groundField,sourceVisualHeight=sourceHeight,targetVisualHeight=targetHeight,interactionVisualHeight=interactionHeight,
    fightDistance=fullFightDistance,sourceUnits=units,referenceVisualHeight=referenceHeight,modelTargetSpan=modelTargetSpan}
end

-- Public source-space bridge for first-class Waza handlers. Effect models,
-- cameras and later controller types use the exact same animated PKX anchors,
-- actor normalization and live fight geometry as GPT1.
function P:wazaBasis(context,side,target,attachment,opts)
  return combatGeometry(context,side,target,attachment,opts)
end

local function unitAxis(unit,key,index)
  if type(unit)=="table" then return tonumber(unit[key]) or tonumber(unit[index]) or 1 end
  return tonumber(unit) or 1
end
local function localToWorld(origin,right,up,forward,pos,unit)
  local ux,uy,uz=unitAxis(unit,"x",1),unitAxis(unit,"y",2),unitAxis(unit,"z",3)
  local x=(tonumber(pos and pos[1]) or 0)*ux
  local y=(tonumber(pos and pos[2]) or 0)*uy
  local z=(tonumber(pos and pos[3]) or 0)*uz
  return {
    origin[1]+right[1]*x+up[1]*y+forward[1]*z,
    origin[2]+right[2]*x+up[2]*y+forward[2]*z,
    origin[3]+right[3]*x+up[3]*y+forward[3]*z,
  }
end
local function worldToLocal(origin,right,up,forward,p)
  local d=vsub(p,origin);return {vdot(d,right),vdot(d,up),vdot(d,forward)}
end

local function moveFxPhaseRole(phase)
  phase=tostring(phase or "all"):lower()
  return (phase=="damage" or phase=="status") and "damage" or "attack"
end

sourceRootAttachment=function(spec,role)
  for _,g in ipairs(type(spec)=="table" and (spec.generatorPrograms or {}) or {}) do
    if g.root==true and moveFxPhaseRole(g.phase)==role then
      local seq=g.sequence
      local a=seq and tonumber(seq.attachment)
      if a and a>=0 and a<#BODY_SLOT_NAMES then return math.floor(a) end
    end
  end
  return nil
end

refreshMoveFxBasis=function(context,fx)
  if not fx then return false end
  local originSide=fx.role=="damage" and fx.target or fx.side
  local otherSide=originSide==fx.side and fx.target or fx.side
  local rootSlot=fx.rootAttachment
  if rootSlot==nil then rootSlot=sourceRootAttachment(fx.spec,fx.role);fx.rootAttachment=rootSlot end
  local geometry=combatGeometry(context,originSide,otherSide,rootSlot,{
    moveId=fx.spec and fx.spec.moveId,style=fx.spec and fx.spec.style,role=fx.role})
  if not geometry then return false end
  local liveSource,actor=geometry.origin,geometry.actor
  local liveTarget,targetActor=geometry.target,geometry.targetActor

  -- Free particles live in the effect's world frame after emission. 1.5.45
  -- rebuilt the attacker->target basis every render frame, so normal particles
  -- swam or snapped whenever either Pokemon moved during its attack/damage
  -- animation. Lock the source WZX basis on the first valid frame. Explicit
  -- joint-follow commands still use the live animated body points below.
  if not fx.basisLocked then
    local right,up,forward=effectBasis(liveSource,liveTarget)
    fx.sourceWorld={liveSource[1],liveSource[2],liveSource[3]}
    fx.targetWorld={liveTarget[1],liveTarget[2],liveTarget[3]}
    fx.right=right;fx.up=up;fx.forward=forward;fx.basisLocked=true
  end
  local source,target=fx.sourceWorld,fx.targetWorld
  local right,up,forward=fx.right,fx.up,fx.forward
  fx.originSide=originSide;fx.otherSide=otherSide;fx.originActor=actor;fx.targetActor=targetActor
  fx.spatialStyle=geometry.style;fx.groundField=geometry.groundField
  fx.sourceVisualHeight=geometry.sourceVisualHeight;fx.targetVisualHeight=geometry.targetVisualHeight
  fx.referenceVisualHeight=geometry.referenceVisualHeight;fx.fightDistance=geometry.fightDistance
  -- 1.5.53: particle coordinates now use the SAME presentation scale that the
  -- live Pokemon actor uses. The old actor.height/100 path ignored worldScale,
  -- so billboards could look actor-sized while their 3D travel/offset remained
  -- locked to a 16-unit cache body. Keep VM physics in untouched source units
  -- and apply the actor/fight transform only at the render boundary.
  fx.sourceUnits=geometry.sourceUnits
  fx.sourceUnit=(geometry.sourceUnits.x+geometry.sourceUnits.y+geometry.sourceUnits.z)/3
  -- Joint opcodes execute inside the VM's source coordinate domain. Convert
  -- live HSD/PKX body points back per axis, matching the non-uniform combat
  -- transform used by projectile/wave/field effects.
  if fx.vm then
    local joints={}
    local ux=math.max(1e-6,geometry.sourceUnits.x)
    local uy=math.max(1e-6,geometry.sourceUnits.y)
    local uz=math.max(1e-6,geometry.sourceUnits.z)
    for slot,name in ipairs(BODY_SLOT_NAMES) do
      local wp=actorAttachmentWorld(originSide,name)
      if wp then
        local lp=worldToLocal(source,right,up,forward,wp)
        joints[slot-1]={lp[1]/ux,lp[2]/uy,lp[3]/uz}
      end
    end
    fx.vm.joints=joints
  end
  return true
end

local function entryScale(entry)
  -- GPT1 size defines the physical particle quad. Transparent padding inside a
  -- source texture is part of that authored quad and must not be "corrected" by
  -- enlarging the entire billboard to its non-transparent bounding box. The old
  -- contentScale compensation could make a sparse 128px sheet four times larger
  -- than Colosseum intended and was a major source of giant card-like FX.
  return 1
end

local function particleImage(fx,p)
  if not (fx and p) or p.textureOff then return nil end
  local list=fx.imagesByBank and fx.imagesByBank[tonumber(p.bank) or 1]
  if not (list and #list>0) then return nil end
  local idx=(tonumber(p.textureIndex) or -1)+1
  if idx<1 then idx=1 end
  return list[idx] or list[((idx-1)%#list)+1] or list[1]
end

local function particleColors(p)
  local c=p and p.prim or {255,255,255,255}
  local e=p and p.env or {0,0,0,0}
  local function f(v,d)return math.max(0,math.min(1,(tonumber(v) or d)/255)) end
  return {f(c[1],255),f(c[2],255),f(c[3],255),f(c[4],255)},
    {f(e[1],0),f(e[2],0),f(e[3],0),f(e[4],0)}
end

local function blendForParticle(g,p)
  local mode=tonumber(p and p.blendMode) or 0
  local ok
  if mode==1 then ok=pcall(g.setBlendMode,"add","alphamultiply")
  elseif mode==2 then ok=pcall(g.setBlendMode,"subtract","alphamultiply")
  elseif mode==3 then ok=pcall(g.setBlendMode,"multiply","premultiplied")
  else ok=pcall(g.setBlendMode,"alpha","alphamultiply") end
  -- Some older/mobile LÖVE backends expose a smaller blend-mode set. Never
  -- inherit the previous particle's mode when the source mode is unsupported.
  if not ok then pcall(g.setBlendMode,"alpha","alphamultiply") end
  return ok
end

local function particleWorld(fx,p,pos)
  if not (fx and fx.sourceWorld and fx.right and fx.up and fx.forward) then return nil end
  local origin=fx.sourceWorld
  -- Only the source update-joint flag makes an emitted quad follow a body
  -- point every frame. B7/B8/BF also set a joint id, but those commands use the
  -- joint as a direction/force target inside the VM; treating them as a render
  -- origin double-applied the joint transform and made effects swim across the
  -- Pokemon during Damage/attack motion.
  if p and p.updateJoint and p.jointId~=nil and fx.originSide then
    local name=BODY_SLOT_NAMES[(tonumber(p.jointId) or 0)+1]
    local joint=name and actorAttachmentWorld(fx.originSide,name)
    if joint then origin=joint end
  end
  return localToWorld(origin,fx.right,fx.up,fx.forward,pos or (p and p.position),fx.sourceUnits or fx.sourceUnit)
end

local function particlePixelUnit(context,fx,actor,world)
  local rs=context.services and context.services.renderSize
  local fallback=18*((rs and rs.height) or 768)/768
  if not world then return fallback end
  local localHeight=tonumber(fx and fx.referenceVisualHeight) or actorVisualHeight(actor)
  if localHeight<=0 then return fallback end
  local x1,y1=projectMoveFxWorld(context,world)
  local x2,y2=projectMoveFxWorld(context,{world[1],world[2]+localHeight,world[3]})
  if not (x1 and x2) then return fallback end
  local apparent=math.sqrt((x2-x1)^2+(y2-y1)^2)
  -- One GPT1 size unit is about an eighth of the on-screen Pokemon height.
  -- Once a live actor reference exists, do not impose the old resolution-based
  -- minimum: that floor made a tiny-but-readable Pokemon use nearly the same FX
  -- billboard unit as a full-size one. Actor scale already contains CBE's tiny
  -- floor / giant ceiling, so following apparent height here is the consistent
  -- rule. The resolution fallback is reserved for missing/unprojectable actors.
  return math.max(3,math.min(72,apparent*.16))
end

local function drawParticleAt(g,shader,context,fx,p,entry,pos,trailAlpha)
  local world=particleWorld(fx,p,pos);if not world then return false end
  local x,y=projectMoveFxWorld(context,world);if not x then return false end
  local img=entry.image;local iw,ih=img:getDimensions()
  local sourceSize=math.abs(tonumber(p.size) or 1)
  -- GPT1 `size` is the physical quad scale; texture resolution is only detail.
  -- Multiplying it by a 128px source sheet turned ordinary 2.4-size contact
  -- particles into 300-420px opaque cards (the white "foliage" seen on Peck).
  -- Render one source size unit as a stable screen-space particle unit instead.
  local particlePixels=particlePixelUnit(context,fx,fx.originActor,world)
  local visible=math.max(1,math.min(320,sourceSize*particlePixels*entryScale(entry)))
  local sc=visible/math.max(iw,ih)
  if sc<=0 then return false end
  local prim,env=particleColors(p)
  local alpha=prim[4]*(trailAlpha or 1)
  if alpha<=0.002 then return false end
  if shader then
    shader:send("cbePrim",{prim[1],prim[2],prim[3],alpha})
    shader:send("cbeEnv",{env[1],env[2],env[3],env[4]*(trailAlpha or 1)})
    shader:send("cbePrimEnv",p.primEnv and 1 or 0)
    local cutoff=p.texEdge and .055 or .004
    if type(p.alphaCompare)=="table" then
      cutoff=math.max(cutoff,math.min(.72,(tonumber(p.alphaCompare.p1) or 0)/255))
    end
    shader:send("cbeAlphaCutoff",cutoff)
    g.setColor(1,1,1,1)
  else g.setColor(prim[1],prim[2],prim[3],alpha) end
  if type(img.setFilter)=="function" then
    local filt=p.nearest and "nearest" or "linear"
    local aniso=p.nearest and 1 or 8
    if not pcall(img.setFilter,img,filt,filt,aniso) then pcall(img.setFilter,img,filt,filt,1) end
  end
  local angle=tonumber(p.rotation) or 0
  if p.dirVec then
    local vel=p.velocity or {0,0,0}
    local wp2=localToWorld(world,fx.right,fx.up,fx.forward,vel,fx.sourceUnits or fx.sourceUnit)
    local x2,y2=projectMoveFxWorld(context,wp2)
    if x2 then angle=math.atan2 and math.atan2(y2-y,x2-x) or angle end
  end
  local sx=((p.flipS~=p.mirrorS) and -sc or sc);local sy=((p.flipT~=p.mirrorT) and -sc or sc)
  blendForParticle(g,p)
  g.draw(img,x,y,angle,sx,sy,iw*.5,ih*.5)
  return true
end

local function drawTrailRibbon(g,shader,context,fx,p,entry,history)
  if not (history and #history>=2 and entry and entry.image) then return false end
  local pts={}
  -- History is newest-first. Build oldest -> live point so UV progression and
  -- taper match the source particle's actual motion instead of a generic line.
  for i=#history,1,-1 do
    local world=particleWorld(fx,p,history[i])
    local x,y=world and projectMoveFxWorld(context,world)
    if x then pts[#pts+1]={x,y,world} end
  end
  local liveWorld=particleWorld(fx,p,p.position)
  local x,y=liveWorld and projectMoveFxWorld(context,liveWorld)
  if x then pts[#pts+1]={x,y,liveWorld} end
  if #pts<3 then return false end

  local sourceSize=math.max(.20,math.abs(tonumber(p.size) or 1))
  local baseWidth=math.max(1,math.min(36,
    particlePixelUnit(context,fx,fx.originActor,liveWorld)*sourceSize*.42))
  local verts={}
  local total=0
  for i=2,#pts do
    local dx,dy=pts[i][1]-pts[i-1][1],pts[i][2]-pts[i-1][2]
    total=total+math.sqrt(dx*dx+dy*dy)
  end
  if total<1 then return false end
  local walked=0
  for i,pt in ipairs(pts) do
    local prev=pts[math.max(1,i-1)];local nxt=pts[math.min(#pts,i+1)]
    local dx,dy=nxt[1]-prev[1],nxt[2]-prev[2]
    local len=math.sqrt(dx*dx+dy*dy)
    if len<1e-5 then dx,dy,len=1,0,1 end
    local nx,ny=-dy/len,dx/len
    if i>1 then
      local q=pts[i-1];local qx,qy=pt[1]-q[1],pt[2]-q[2]
      walked=walked+math.sqrt(qx*qx+qy*qy)
    end
    local u=math.max(0,math.min(1,walked/total))
    -- Fade/taper the oldest tail while leaving the live end at source size.
    local taper=.22+.78*u
    local hw=baseWidth*.5*taper
    verts[#verts+1]={pt[1]+nx*hw,pt[2]+ny*hw,u,0,1,1,1,taper}
    verts[#verts+1]={pt[1]-nx*hw,pt[2]-ny*hw,u,1,1,1,1,taper}
  end
  if #verts<6 then return false end

  local mesh=p._cbeTrailMesh
  if not mesh then
    local ok,m=pcall(love.graphics.newMesh,verts,"strip","stream")
    if not ok or not m then return false end
    mesh=m;p._cbeTrailMesh=mesh
  else
    local ok=pcall(mesh.setVertices,mesh,verts)
    if not ok then
      local ok2,m=pcall(love.graphics.newMesh,verts,"strip","stream")
      if not ok2 or not m then return false end
      mesh=m;p._cbeTrailMesh=mesh
    end
  end
  pcall(mesh.setTexture,mesh,entry.image)
  local prim,env=particleColors(p)
  if shader then
    g.setShader(shader)
    shader:send("cbePrim",prim);shader:send("cbeEnv",env)
    shader:send("cbePrimEnv",p.primEnv and 1 or 0)
    local cutoff=p.texEdge and .055 or .004
    if type(p.alphaCompare)=="table" then cutoff=math.max(cutoff,math.min(.72,(tonumber(p.alphaCompare.p1) or 0)/255)) end
    shader:send("cbeAlphaCutoff",cutoff)
  end
  blendForParticle(g,p)
  g.setColor(1,1,1,1)
  g.draw(mesh)
  return true
end

-- Every graphics-state scope in the MoveFX path is exception-safe.  The arena
-- host intentionally catches presentation errors so gameplay can continue; an
-- unmatched push inside that caught error used to leak one LÖVE graphics-stack
-- frame per bad particle until Gen2 eventually crashed with
-- "Maximum stack depth reached (more pushes than pops?)".
local function graphicsScope(g,fn)
  local pushed=false
  local okPush,pushErr=pcall(g.push,"all")
  if not okPush then return false,nil,pushErr end
  pushed=true
  local ok,value=pcall(fn)
  -- Restore the dangerous states explicitly before popping as a second safety
  -- net for older/mobile backends, then ALWAYS unwind the stack.
  pcall(g.setShader)
  pcall(g.setDepthMode)
  if pushed then pcall(g.pop) end
  if not ok then return false,nil,value end
  return true,value,nil
end

local function recordMoveFxRenderFault(fx,p,err)
  local moveId=fx and (fx.moveId or (fx.spec and fx.spec.moveId)) or "?"
  local msg=("MoveFX render fault move=%s: %s"):format(tostring(moveId),tostring(err))
  P.moveFxError=msg
  P.moveFxRenderFaults=(tonumber(P.moveFxRenderFaults) or 0)+1
  if type(p)=="table" then
    p._cbeRenderFaults=(tonumber(p._cbeRenderFaults) or 0)+1
    -- A malformed source particle must never be able to blank the arena every
    -- frame.  Quarantine only that particle after repeated identical failures;
    -- the rest of the Waza keeps rendering and gameplay remains authoritative.
    if p._cbeRenderFaults>=3 then p._cbeRenderDisabled=true end
  end
  return msg
end

local function drawMoveFx(context)
  local g=love and love.graphics
  if not (g and MoveFXVM and #P.moveFxActive>0) then return false end
  local drew=false
  local ok,value,err=graphicsScope(g,function()
    g.setDepthMode()
    local shader=moveFxShader();g.setShader(shader)
    for _,fx in ipairs(P.moveFxActive) do
      if refreshMoveFxBasis(context,fx) then
        for _,p in ipairs(MoveFXVM.visibleParticles(fx.vm) or {}) do
          if not p._cbeRenderDisabled then
            local entry=particleImage(fx,p)
            if entry and p.alive~=false then
              -- Source trail history is rendered as one tapered, source-textured
              -- ribbon strip rather than repeated billboards/lines.
              local history=p.trail and p.history or nil
              if history and #history>1 then
                local okTrail,didTrail=pcall(drawTrailRibbon,g,shader,context,fx,p,entry,history)
                if okTrail then drew=didTrail or drew
                else recordMoveFxRenderFault(fx,p,didTrail);pcall(g.setShader,shader) end
              end
              local okParticle,didParticle=pcall(drawParticleAt,g,shader,context,fx,p,entry,p.position,1)
              if okParticle then drew=didParticle or drew
              else recordMoveFxRenderFault(fx,p,didParticle);pcall(g.setShader,shader) end
            end
          end
        end
      end
    end
    return drew
  end)
  if not ok then
    recordMoveFxRenderFault(nil,nil,err)
    return false
  end
  return value==true
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

  -- Outgoing actors are drawn from the same field anchor while their recall or
  -- faint tail finishes. They are no longer tied to the live BattleState slot,
  -- so a replacement can be acquired without hard-popping the old model.
  for _,record in ipairs(P.retiringActors) do
    local side=record.side
    local actor=record.actor
    local cell=side and arena[side]
    local other=side and arena[side=="player" and "enemy" or "player"]
    if actor and type(cell)=="table" and type(other)=="table"
        and type(actor.matrix)=="function" and type(actor.draw)=="function" then
      driveRetiringActor(context,record)
      local ok,matrix=pcall(actor.matrix,actor,cell[1],context.groundY or 0,cell[2],
        (other[1] or 0)-(cell[1] or 0),(other[2] or 0)-(cell[2] or 0))
      if ok and matrix then jobs[#jobs+1]={side=side,actor=actor,matrix=matrix,retiring=true} end
    end
  end

  for _,side in ipairs(SIDES_EP) do
    local existing=P.stadiumActors[side] and P.stadiumActors[side].actor
    local actor=actorVisible(context,side,existing) and stadiumActor(context,side) or nil
    local cell=arena[side]
    local other=arena[side=="player" and "enemy" or "player"]
    if actor and type(cell)=="table" and type(other)=="table"
        and type(actor.matrix)=="function" and type(actor.draw)=="function" then
      driveSpawn(context,side,actor)
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
  self.moveFxActive={};self.moveFxError=nil;self.moveFxRenderFaults=0
  installWazaHandlers()
  if WazaSequence and type(WazaSequence.finish)=="function" then pcall(WazaSequence.finish,WazaSequence,context,"battle-begin-reset") end
  battleArtRuntime()
  stadiumService()
  selectPresentation(context,true)
  local available=self:available(context)
  -- Do not synchronously acquire/extract opening actors on battle.started.
  -- That callback runs after the transition has reached its black resolve, so
  -- cache parsing/GPU uploads here directly become a long black screen.  The
  -- normal actor path acquires already-resident/cached scenes when the battle
  -- begins drawing; uncached source extraction remains a fail-open case rather
  -- than a transition blocker.
  return available
end

local function actorDelta(context,dt)
  -- input.step is game-time. At 4x Gen1Recomp executes four fixed steps before
  -- the next rendered frame, exactly like fast-forwarding Colosseum itself.
  -- Do NOT divide cosmetic animation by the speed multiplier: that made the
  -- battle resolve four times faster while the Pokemon performed at 1x.
  return math.max(0,tonumber(dt) or 0)
end

function P:update(context,dt)
  -- Keep both side references synchronized even if the switch event is emitted
  -- before/after another mod's listener. The next update/draw always observes
  -- the current BattleState battler rather than the opener cached at begin().
  liveBattler(context,"player")
  liveBattler(context,"enemy")
  selectPresentation(context,false)
  directedMoveFx(context)
  updateMoveFx(context,dt)
  -- CBE suppresses Battle Art's competing world/camera stage, not its Pokemon
  -- art. With models OFF, advance/install the exact Battle Art 2.x selection
  -- (ANIMATED / STATIC / ROM / MODDED) onto our generation-neutral battlers.
  -- With models ON this path is skipped entirely: GC6E01 actors are absolute.
  battleArtRuntime()
  syncBattleArtSpecies(context,dt,true)
  if P.mode=="external" then
    local ok=invokeExternal(context,"update",dt or 0)
    if not ok then
      finishExternal(context,"update-failed")
      P.mode="sprites";P.modeId="builtin:resolved-sprites"
    end
  elseif P.mode=="stadium" then
    local actorDt=actorDelta(context,dt)

    -- Detached return/faint tails continue in real presentation time.
    for i=#P.retiringActors,1,-1 do
      local record=P.retiringActors[i]
      local actor=record and record.actor
      driveRetiringActor(context,record)
      if actor and type(actor.update)=="function" then pcall(actor.update,actor,actorDt) end
      local done=false
      if actor and type(actor.terminalComplete)=="function" then
        local ok,value=pcall(actor.terminalComplete,actor)
        done=ok and value==true
      elseif actor and actor.state=="removal" then
        done=true
      end
      if done then
        table.remove(P.retiringActors,i)
        releaseActorRecord(record,record.retireReason or "tail-complete")
      end
    end

    for _,side in ipairs(SIDES_PE) do
      syncStadiumActor(context,side)
      local existing=P.stadiumActors[side] and P.stadiumActors[side].actor
      local actor=actorVisible(context,side,existing) and stadiumActor(context,side) or nil
      driveSpawn(context,side,actor)
      if actor and type(actor.update)=="function" then pcall(actor.update,actor,actorDt) end
    end
  end
end

local function hasRetiringActor(side)
  for _,record in ipairs(P.retiringActors) do
    if record and record.side==side and record.actor then return true end
  end
  return false
end

function P:covers(context,side)
  if self.mode=="native" or not self:available(context) then return false end
  -- A live CBE 3D actor owns its side continuously, not only after drawWorld
  -- happened to set a per-frame `drawn` flag. Gen1 damage presentation can
  -- query the picture layer before the world pass; tying ownership to draw
  -- order let the stock picture blink/leak through and made the model appear
  -- to disappear. Retiring actors likewise remain authoritative through their
  -- authored recall/faint tail.
  if self.mode=="stadium" then
    if hasRetiringActor(side) then return true end
    local actor=P.stadiumActors[side] and P.stadiumActors[side].actor
    if actor and actorVisible(context,side,actor) then return true end
  elseif self.drawn[side]==true and visible(context,side) then
    return true
  end
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
      for _,side in ipairs(SIDES_EP) do
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
  local spriteOk,_,spriteErr=graphicsScope(g,function()
    g.setShader();g.setDepthMode();g.setColor(1,1,1,1)
    for _,side in ipairs(SIDES_EP) do
      -- COLOSSEUM MODELS means exactly that: once CBE's GC6E01 actor service
      -- owns the battle, never fall back to a Game Boy/Battle Art sprite merely
      -- because the actor is intentionally hidden for recall/faint/capture or
      -- because a delegated Gen 1 host queried the frame in a different order.
      -- This was the capture leak that showed the enemy sprite inside the ball.
      local cbeAbsolute=self.mode=="stadium"
        and self.modeId=="cbe:colosseum-pokemon"
        and cbePokemonModelsEnabled(context)
      local captureHidden=false
      local captureScale=1
      if side=="enemy" and PlayerTrainer then
        if type(PlayerTrainer.captureEnemyScale)=="function" then
          local okScale,value=pcall(PlayerTrainer.captureEnemyScale,PlayerTrainer,context)
          if okScale and tonumber(value) then captureScale=math.max(0,math.min(1,tonumber(value))) end
        end
        if type(PlayerTrainer.captureHidesEnemy)=="function" then
          local okHidden,value=pcall(PlayerTrainer.captureHidesEnemy,PlayerTrainer,context)
          captureHidden=okHidden and value==true
        end
      end
      local image=(not self.drawn[side] and not cbeAbsolute and not captureHidden)
        and imageFor(context,side) or nil
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
            local visibleH=math.max(0,math.floor(h*(1-faint)+.5))
            if visibleH>0 then
              if faintQuad and faintQuad.setViewport then
                pcall(faintQuad.setViewport,faintQuad,0,0,w,visibleH,w,h)
              else
                faintQuad=g.newQuad(0,0,w,visibleH,w,h)
              end
              g.draw(image,faintQuad,px,py,0,sx,s,w*.5,visibleH)
              self.drawn[side]=true;self.presented[side]=true; any=true
            end
          else
            -- Resolved 2D sources participate in the same capture absorption as
            -- the Colosseum actor. Shrink about the feet/center anchor instead
            -- of leaving the sprite fully visible until a binary hide cutoff.
            local presentScale=(grow~=nil and grow or 1)*captureScale
            if presentScale>0 then
              if presentScale<.999 then
                local eff=s*presentScale
                local ex=eff
                if side=="player" and playerFlip() then ex=-eff end
                g.draw(image,px,py,0,ex,eff,w*.5,h)
              else
                g.draw(image,px,py,0,sx,s,w*.5,h)
              end
              self.drawn[side]=true;self.presented[side]=true; any=true
            end
          end
        end
      end
    end
    return true
  end)
  if not spriteOk then self.spriteError="render: "..tostring(spriteErr) end
  local wh=V and V.WazaHandlers
  if wh and type(wh.drawWorld)=="function" then
    local okW,drewW=pcall(wh.drawWorld,context)
    if okW and drewW then any=true end
  end
  any=drawMoveFx(context) or any
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
  -- BattleRuntime guarantees delivery when CBE actors are hosted outside the
  -- standalone compositor. A host that also forwards the same payload must not
  -- restart a one-shot animation, so table payloads are deduplicated by identity.
  if type(payload)=="table" then
    if seenEventPayload[payload]==name then return end
    seenEventPayload[payload]=name
  end
  if P.mode=="external" then
    local ok=invokeExternal(context,"event",name,payload)
    if ok then return end
    finishExternal(context,"event-failed")
    P.mode="sprites";P.modeId="builtin:resolved-sprites"
  end
  local S=V.BattleSides
  local side
  local gen2=context and context.battle and context.battle.__cbeGeneration==2
  local queueSync=context and context.battle and context.battle.__cbePresentationQueueSync==true
  -- Gen 2 resolves move/damage/faint semantics in its pure battle model before
  -- the screen replays them. StandaloneHost raises presentation_* events at
  -- the actual queue-consumption boundary; all 3D actor reactions follow those.
  if queueSync and ((gen2 and (name=="battle.move_used" or name=="battle.damage_dealt" or name=="battle.fainted"))
      or ((not gen2) and name=="battle.fainted")) then return end
  local semantic=name
  if name=="battle.presentation_damage" then semantic="battle.damage_dealt"
  elseif name=="battle.presentation_faint" then semantic="battle.fainted" end
  if semantic=="battle.move_used" or name=="battle.presentation_move" then
    side=(S and S.payload and S.payload(context,payload,{"user","side"})) or (payload and payload.side)
    local actor=side and actorVisible(context,side,P.stadiumActors[side] and P.stadiumActors[side].actor) and stadiumActor(context,side)
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
    local resolvedId=moveId~=nil and (tonumber(moveId) or moveId) or nil
    local spec
    if resolvedId~=nil and MoveFX then
      if type(MoveFX.peek)=="function" then
        local okPeek,value=pcall(MoveFX.peek,resolvedId,move)
        if okPeek and type(value)=="table" then spec=value end
      end
      -- A visible move boundary is NOT a legal extraction seam.  WZX source
      -- decode/cache writes can be expensive enough to stall the compositor for
      -- seconds on mobile/slow storage. Consume prepared caches only and queue
      -- misses for out-of-battle preparation.
      if not spec and type(MoveFX.queuePrefetch)=="function" then
        pcall(MoveFX.queuePrefetch,resolvedId,move,context and context.battle)
        P.moveFxError="source MoveFX cache queued; first uncached use failed open without blocking"
      end
    end
    local attackDuration,wazaTimingPoints,presentationFrames,animationSlot,animationName
    if actor and type(actor.attack)=="function" and resolvedId~=nil then
      pcall(actor.attack,actor,resolvedId,move)
      if type(actor.stateDuration)=="function" then
        local okDur,value=pcall(actor.stateDuration,actor,"attack")
        if okDur then attackDuration=tonumber(value) end
      end
      wazaTimingPoints=actorWazaTiming(actor)
      presentationFrames=attackDuration and math.floor(math.max(0,attackDuration)*60+.5) or nil
      animationSlot=actor.nativeSlot and actor.nativeSlot.index or actor.nativeClip
      animationName=actor.nativeActionName or actor.requestedNativeSlot
    end
    local directorSeq
    if Director and type(Director.bindAttack)=="function" and resolvedId~=nil then
      local okBind,bound=pcall(Director.bindAttack,Director,context,side,resolvedId,move,attackDuration,spec,
        wazaTimingPoints,presentationFrames,animationSlot,animationName)
      if okBind and type(bound)=="table" then directorSeq=bound end
      if not spec and MoveFX and type(MoveFX.mapped)=="function" then
        local okMap,mapped=pcall(MoveFX.mapped,resolvedId,move)
        if okMap and mapped then P.moveFxError="mapped source FX was not prefetched before move playback" end
      end
    end
    -- Source attack/special generators begin on the authoritative move boundary.
    -- Their own WZX SequenceEntry + GPT1 waits decide when particles actually
    -- appear; BattleDirector's former style-derived launch percentage is no
    -- longer part of the visible effect path.
    if spec then
      local hasAttackTimeline=roleHasTimeline(spec,"attack")
      -- BattleDirector normally starts the retail Waza timeline after the actor
      -- has chosen its source attack slot. If a host/provider path prevented
      -- that bind from returning a Waza serial, start the SAME source timeline
      -- here rather than leaving a source-ready move visually empty. Waza's
      -- per-side supersession/dedup keeps this from creating parallel attacks.
      if hasAttackTimeline and not (directorSeq and directorSeq.wazaAttackSerial) then
        local started=startWazaSequence(context,side,spec,nil,"attack",resolvedId,move)
        if not started then P.moveFxError=P.moveFxError or "source attack Waza timeline could not start" end
      end
      if not hasAttackTimeline and roleHasSource(spec,"attack") then
        -- Compatibility path for an older cache that has a decoded GPT1 role but
        -- no WazaSequence table. Never run this beside a retail Waza timeline.
        if not stageMoveFx(context,side,spec,nil,"attack") and not P.moveFxError then
          P.moveFxError="verified source attack MoveFX could not be staged"
        end
      elseif not hasAttackTimeline and roleHasSource(spec,"damage") then
        -- Genuine damage-only sequences intentionally wait for impact.
        P.moveFxError=nil
      end
    elseif resolvedId~=nil then
      -- Last fail-open attempt for hosts whose move table could not be resolved
      -- during the first acquisition arm.
      startMoveFx(context,side,resolvedId,move,"attack")
    end
  elseif semantic=="battle.damage_dealt" then
    side=(S and S.payload and S.payload(context,payload,{"target","side"})) or (payload and payload.side)
    -- Damage must reach the resident 3D actor even if the native picture layer
    -- toggles visibility on this same frame. The hit handler never removes the
    -- actor; it starts the authored Damage bank or its stable recoil fallback.
    local actor=side and P.stadiumActors[side] and P.stadiumActors[side].actor or nil
    if not actor and side then actor=stadiumActor(context,side) end
    if actor and type(actor.hit)=="function" then pcall(actor.hit,actor,payload) end
    -- Damage/status WZX banks are a separate source phase. Arm them exactly when
    -- battle.damage_dealt fires instead of guessing an impact percentage from
    -- the attack animation. Multi-hit moves intentionally replay this bank on
    -- each resolved hit.
    local attacker=side=="player" and "enemy" or (side=="enemy" and "player" or nil)
    if attacker and Director and type(Director.move)=="function" then
      local okSeq,seq=pcall(Director.move,Director,context,attacker)
      if okSeq and type(seq)=="table" and type(seq.fxSpec)=="table" then
        local points=actorWazaTiming(actor)
        local damageFrames
        if actor and type(actor.stateDuration)=="function" then
          local okDur,dur=pcall(actor.stateDuration,actor,"hit")
          if okDur and tonumber(dur) then damageFrames=math.floor(math.max(0,tonumber(dur))*60+.5) end
        end
        local hasDamageTimeline=roleHasTimeline(seq.fxSpec,"damage")
        local bound=false
        if hasDamageTimeline and Director and type(Director.bindDamage)=="function" then
          local okBind,inst=pcall(Director.bindDamage,Director,context,attacker,side,seq.fxSpec,seq.moveId,seq.move,points,damageFrames)
          bound=okBind and type(inst)=="table"
        elseif hasDamageTimeline then
          bound=startWazaSequence(context,attacker,seq.fxSpec,side,"damage",seq.moveId,seq.move)
        end
        if not hasDamageTimeline and roleHasSource(seq.fxSpec,"damage") then
          -- Legacy decoded-role fallback only when the retail timeline itself is
          -- absent. A Waza timeline and a whole-role VM must never overlap.
          stageMoveFx(context,attacker,seq.fxSpec,side,"damage")
        elseif hasDamageTimeline and not bound then
          P.moveFxError=P.moveFxError or "source damage Waza timeline could not start"
        end
      end
    end
  elseif semantic=="battle.fainted" then
    side=(S and S.payload and S.payload(context,payload,{"battler","side"})) or (payload and payload.side)
    local actor=side and (P.stadiumActors[side] and P.stadiumActors[side].actor)
    if actor and type(actor.faint)=="function" then
      -- Faint and recall are separate lifecycle beats. A KO should play the
      -- faint reaction for every side; recall belongs to a voluntary/forced
      -- battler switch and is handled below.
      pcall(actor.faint,actor,"collapse")
      if Director and type(Director.bindFaint)=="function" then
        local duration
        if type(actor.terminalDuration)=="function" then
          local okDur,value=pcall(actor.terminalDuration,actor,"faint");if okDur then duration=tonumber(value) end
        elseif type(actor.stateDuration)=="function" then
          local okDur,value=pcall(actor.stateDuration,actor,"faint");if okDur then duration=tonumber(value) end
        end
        pcall(Director.bindFaint,Director,context,side,duration)
      end
    end
  elseif name=="battle.battler_switched" then
    side=(S and S.payload and S.payload(context,payload,
      {"battler","replacement","target","side","oldBattler","newBattler"}))
      or (payload and S and S.value and S.value(payload.side))
    if side then
      local record=P.stadiumActors[side]
      local live=liveBattler(context,side)
      local previous=payload and (payload.previous or payload.oldBattler)
      -- The event can arrive before or after another listener has already
      -- observed the new slot. Retire only the actor that actually belongs to
      -- the outgoing battler; never accidentally recall a freshly acquired
      -- replacement.
      if record and ((previous and record.battler==previous) or record.battler~=live) then
        retireStadiumActor(side,"switch-return")
      end
    else
      -- Some engine builds omit the side from the event. Identity comparison is
      -- still authoritative and retires only records whose live slot changed.
      syncStadiumActor(context,"player");syncStadiumActor(context,"enemy")
    end
  end
end
function P:finish(context,reason)
  self.drawn.player=false;self.drawn.enemy=false
  self.moveFxActive={}
  if P.animated and type(P.animated.finish)=="function"
      and context and context.battle and not cbePokemonModelsEnabled(context) then
    pcall(P.animated.finish,context.battle)
  end
  if WazaSequence and type(WazaSequence.finish)=="function" then pcall(WazaSequence.finish,WazaSequence,context,reason or "battle-ended") end
  self.presented.player=false;self.presented.enemy=false
  finishExternal(context,reason or "battle-ended")
  releaseStadiumActors(reason or "battle-ended")
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

function P.prewarm()
  -- Compile the portable GPT1 particle shader outside battle presentation.
  -- Source textures/programs stay lazy and cache-backed; no disc extraction or
  -- move-cache parsing is performed here.
  local sh=moveFxShader()
  return sh~=nil or P.moveFxShader==false
end

function P.status()
  local _,id=battleArtHandle()
  local stadium=stadiumService()
  local actorStatus
  if P.actorApi and type(P.actorApi.status)=="function" then
    local ok,value=pcall(P.actorApi.status)
    if ok then actorStatus=value end
  end
  local activeFx=P.moveFxActive[1]
  local scaleStatus=activeFx and {moveId=activeFx.spec and activeFx.spec.moveId,style=activeFx.spatialStyle,role=activeFx.role,
    groundField=activeFx.groundField==true,sourceVisualHeight=activeFx.sourceVisualHeight,targetVisualHeight=activeFx.targetVisualHeight,
    fightDistance=activeFx.fightDistance,sourceUnits=activeFx.sourceUnits} or nil
  return {registered=P.registered,id=P.id,preferredPatched=P.preferredPatched,
    standaloneOnlyGateApplies=false,
    registeredActorOwners=(function()
      local out={}
      for owner in pairs(registeredCapabilities.battleActors or {}) do out[#out+1]=owner end
      table.sort(out);return out
    end)(),
    battleArt=id,battleArtWorld=battleArtWantsWorldSprites(),
    stadiumActors=stadium and true or false,stadiumError=P.stadiumError,
    retiringActorCount=#P.retiringActors,
    moveFxActive=#P.moveFxActive,moveFxError=P.moveFxError,moveFxRenderFaults=P.moveFxRenderFaults or 0,moveFxScale=scaleStatus,
    actorLifecycle="persistent-hit / detached-recall / faint-tail",
    presentationMode=P.mode,presentationId=P.modeId,actorOwner=P.actorOwner,actorStatus=actorStatus,
    spriteOwner=P.spriteOwner,spriteError=P.spriteError,externalError=P.externalError,
    contract="CBE Arenas ON = CBE stage always; Models ON = GC6E01 actors; Models OFF = portable battleActors or resolved sprites (full battlePresentation only when Arenas OFF)"}
end

installWazaHandlers()
return P
