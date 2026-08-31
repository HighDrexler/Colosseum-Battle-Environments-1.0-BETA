-- Colosseum Battle Environments standalone battle-stage host.
--
-- This is intentionally independent from StadiumBattleFX, Battle Art, and any
-- UI mod.  When COLOSSEUM ARENAS is enabled it owns only the world/camera
-- presentation.  Pokemon artwork is read from the battle's already-resolved
-- sprite seam and projected into the 3D arena; optional model integrations may
-- replace that actor pass without becoming a dependency of the stage itself.
local V=...
local Arena=V.Arena
local Camera=V.Camera
local CurrentSprites=V.CurrentSpriteModels
local Catalog=V.ArenaCatalog
local Compat=V.GenerationCompat
local BattleDirector=V.BattleDirector
local MoveFXOwnership=V.MoveFXOwnership
local BattleSides=V.BattleSides
local PlayerTrainer=V.PlayerTrainer
local Trainer=V.Trainer
local H={session=nil,installed=false,drawWrapper=nil,wideWrapper=nil,picsWrapper=nil,queueWrapper=nil,updateQueueWrapper=nil,textWrapper=nil,bottomWrapper=nil,statusWrapper=nil,panelWrapper=nil,
  drawEpoch=0,wideEpoch=0,picsEpoch=0,queueEpoch=0,updateQueueEpoch=0,textEpoch=0,bottomEpoch=0,statusEpoch=0,panelEpoch=0,
  lastError=nil,lastUpdateError=nil,frames=0,externalFrames=0,presentationMoveEvents=0,presentationDamageEvents=0,presentationFaintEvents=0,
  captureQueueHolds=0,captureRowsStripped=0,captureUiSuppressed=0}

local function log(level,fmt,...)
  local m=V.mod
  local l=m and m.log
  if l and type(l[level])=="function" then pcall(l[level],l,fmt,...) end
end

local function enabled(game)
  if Catalog and type(Catalog.enabled)=="function" then
    local ok,v=pcall(Catalog.enabled,game)
    if ok then return v~=false end
  end
  return true
end

-- CBE arena ownership is absolute while the standalone host has a live
-- session. Legacy full-frame 3D providers are never allowed to replace this
-- world/camera/trainer compositor. Compatible external Pokemon presentation
-- must come through CurrentSpriteModels' portable actor/presentation seams.


local function cameraWanted(s)
  local settings=V.BattleSettings
  local game=s and s.context and s.context.game or (s and s.battle and s.battle.game)
  if settings and type(settings.cameraEnabled)=="function" then
    local ok,v=pcall(settings.cameraEnabled,game)
    if ok then return v~=false end
  end
  return true
end

local function syncCameraOwnership(s)
  if not (s and Camera) then return false end
  local want=cameraWanted(s)
  if want and not s.cameraActive then
    pcall(Camera.begin,Camera,s.context)
    s.cameraActive=true
  elseif not want and s.cameraActive then
    pcall(Camera.finish,Camera,s.context,"camera.disabled")
    s.cameraActive=false
  end
  return s.cameraActive==true
end

local function contextFor(battle)
  battle=Compat and Compat.prepare(battle) or battle
  return {
    apiVersion=1,
    battle=battle,
    game=battle and battle.game,
    encounter={
      kind=battle and battle.kind,
      trainerId=battle and (battle.oppClass or (battle.trainer and battle.trainer.id)),
      mapId=battle and battle.currentMapId and battle:currentMapId() or nil,
      partyIndex=battle and battle.partyIndex,
    },
    sides={
      player={battler=battle and battle.player},
      enemy={battler=battle and battle.enemy},
    },
    phase="intro",progress=0,groundY=0,services={cbeStandalone=true},
  }
end

local function baseCamera(arena)
  local R=(arena and arena.camera) or {side=58,back=17,height=20,lookX=0,lookY=6,frameH=50}
  local mid=(arena and arena.mid) or {0,0}
  local focus={mid[1]+(R.lookX or 0),R.lookY or 0,mid[2]}
  local eye={mid[1]+(R.side or 58),R.height or 20,mid[2]+(R.back or 17)}
  local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
  local dist=math.max(2,math.sqrt(dx*dx+dy*dy+dz*dz))
  local fov=2*math.atan(((R.frameH or 50)/2)/dist)
  return {eye=eye,focus=focus,fov=fov,curve=0}
end

local function cameraPose(s)
  local base=baseCamera(s.context.arena)
  if not Camera or not syncCameraOwnership(s) then return base end
  local okClaim,claim=pcall(Camera.claim,Camera,s.context,s.context.phase)
  if not okClaim or claim==false then return base end
  local ok,pose=pcall(Camera.shot,Camera,s.context,s.context.phase,s.context.progress,base,s.context.arena)
  if ok and pose and pose.eye and pose.focus and pose.fov then return pose end
  return base
end

local function project(vp,w,h,x,y,z)
  local cx=vp[1]*x+vp[2]*y+vp[3]*z+vp[4]
  local cy=vp[5]*x+vp[6]*y+vp[7]*z+vp[8]
  local cw=vp[13]*x+vp[14]*y+vp[15]*z+vp[16]
  if not cw or cw<=1e-6 then return nil end
  return (cx/cw*.5+.5)*w,(cy/cw*.5+.5)*h
end

local function syncBattlers(s)
  local battle=s and s.battle
  if Compat then battle=Compat.sync(battle);if s then s.battle=battle;s.context.battle=battle;s.context.game=battle and battle.game or s.context.game end end
  local sides=s and s.context and s.context.sides
  if not (battle and sides) then return end
  sides.player=sides.player or {}
  sides.enemy=sides.enemy or {}
  sides.player.battler=battle.player
  sides.enemy.battler=battle.enemy
end

local function beginProviders(s)
  local arena=Arena and Arena:arena(s.context)
  if not arena then return false,"arena definition unavailable" end
  s.context.arena=arena
  local ok,accepted=pcall(Arena.begin,Arena,s.context,arena)
  if not ok then return false,accepted end
  if accepted==false or accepted==V.FALLBACK then return false,"arena declined" end
  s.cameraActive=false
  syncCameraOwnership(s)
  if CurrentSprites then pcall(CurrentSprites.begin,CurrentSprites,s.context) end
  return true
end

function H.begin(battle)
  H.finish("replaced")
  battle=Compat and Compat.prepare(battle) or battle
  if not battle or not enabled(battle.game) then return false end
  local s={battle=battle,context=contextFor(battle),presented=false,started=false,
    pendingSemantics={move={player={},enemy={}},damage={player={},enemy={}},faint={player={},enemy={}}}}
  H.session=s
  local ok,why=beginProviders(s)
  if not ok then
    if s.battle then s.battle.__cbePresentationQueueSync=nil end
    -- Keep an ownership-only session alive. A missing/broken CBE arena is
    -- allowed to fail visibly, but it is NEVER a signal that Battle Art,
    -- Stadium or another full-stage compositor may take the BattleState back.
    -- drawWrapper will preserve engine HUD/input while suppressing every
    -- competing battle field until this battle ends.
    s.started=false
    s.ownershipOnly=true
    s.beginError=tostring(why)
    H.lastError=tostring(why)
    local level=(why=="arena definition unavailable" or why=="arena declined") and "warn" or "error"
    log(level,"standalone arena begin failed under retained CBE ownership: %s",tostring(why))
    return false
  end
  s.started=true
  if s.battle then s.battle.__cbePresentationQueueSync=true end
  H.lastError=nil;H.lastUpdateError=nil
  log("info","standalone arena host began: arena=%s actor=current-sprites",tostring(s.context.arena and s.context.arena.id))
  return true
end

function H.update(dt)
  local s=H.session
  if not (s and s.started) then return end
  dt=tonumber(dt) or 0
  s.context.progress=(s.context.progress or 0)+dt
  syncBattlers(s)
  if syncCameraOwnership(s) then pcall(Camera.update,Camera,s.context,dt) end
  if Arena then
    local ok,err=pcall(Arena.update,Arena,s.context,dt,s.context.arena)
    if ok then
      H.lastUpdateError=nil
    else
      local msg=tostring(err)
      if H.lastUpdateError~=msg then
        H.lastUpdateError=msg
        H.lastError=msg
        log("error","standalone arena update failed: %s",msg)
      end
    end
  end
  if CurrentSprites then pcall(CurrentSprites.update,CurrentSprites,s.context,dt) end
end

local function semanticSide(s,name,payload)
  if not (s and BattleSides and type(BattleSides.payload)=="function") then return nil end
  if name=="battle.move_used" then
    return BattleSides.payload(s.context,payload,{"user","attacker","source","battler","side"})
  elseif name=="battle.damage_dealt" then
    local target=BattleSides.payload(s.context,payload,{"target","defender","targetSide","defenderSide","battler"})
    if target then return target end
    local actor=BattleSides.payload(s.context,payload,{"user","attacker","source","side"})
    return actor and BattleSides.other(actor) or nil
  elseif name=="battle.fainted" then
    return BattleSides.payload(s.context,payload,{"battler","target","side","faintedSide","targetSide"})
  end
end

local function stashSemantic(s,name,payload)
  local kind=name=="battle.move_used" and "move"
    or (name=="battle.damage_dealt" and "damage")
    or (name=="battle.fainted" and "faint") or nil
  if not kind then return false end
  local side=semanticSide(s,name,payload)
  local buckets=s.pendingSemantics and s.pendingSemantics[kind]
  local bucket=buckets and side and buckets[side]
  if bucket then bucket[#bucket+1]=payload end
  return true
end

local function takeSemantic(s,kind,side)
  local buckets=s and s.pendingSemantics and s.pendingSemantics[kind]
  local bucket=buckets and side and buckets[side]
  if type(bucket)=="table" and #bucket>0 then return table.remove(bucket,1) end
end

local function visiblePayload(s,battle,kind,side,event)
  local source=takeSemantic(s,kind,side)
  local out={}
  if type(source)=="table" then for k,v in pairs(source) do out[k]=v end end
  if type(event)=="table" then
    for k,v in pairs(event) do
      -- Gen2 queue rows store `move` as an id, while the earlier semantic event
      -- can carry the complete move definition. Preserve that richer source
      -- object and expose the queue id separately as moveId.
      if not (kind=="move" and k=="move" and type(out.move)=="table") then out[k]=v end
    end
  end
  out.battle=battle
  out.side=side or out.side
  if kind=="move" then out.moveId=(event and event.move) or out.moveId end
  out.presentationBoundary=true
  return out
end

local CAPTURE_ANIMS={
  TOSS_ANIM=true,GREATTOSS_ANIM=true,ULTRATOSS_ANIM=true,BLOCKBALL_ANIM=true,
  POOF_ANIM=true,HIDEPIC_ANIM=true,SHAKE_ANIM=true,SHOWPIC_ANIM=true,
}

local function ownsSessionBattle(s,battle)
  if not (s and battle) then return false end
  local prepared=Compat and Compat.prepare(battle) or battle
  return (Compat and Compat.matches and Compat.matches(s.battle,prepared)) or s.battle==prepared or s.battle==battle
end

local function captureStatus(s)
  if not (s and PlayerTrainer and type(PlayerTrainer.captureStatus)=="function") then return nil end
  local ok,st=pcall(PlayerTrainer.captureStatus,PlayerTrainer,s.context)
  return ok and type(st)=="table" and st or nil
end

local function captureAnimationActive(s)
  local st=captureStatus(s)
  return st and st.active==true
end

-- Remove only the native visual rows that the engine inserts AFTER
-- battle.ball_thrown. Outcome text/functions remain in place and are released
-- when CBE's real-time capture presentation finishes. This is the key ordering
-- guarantee: action first, result dialogue second, at every battle speed.
local function stripNativeCapturePrefix(battle,s)
  if not (type(battle)=="table" and type(battle.queue)=="table" and s and s.captureHold and not s.captureHold.stripped) then return 0 end
  local q=battle.queue;local removed=0;local sawCapture=false;local i=1;local guard=0
  while i<=#q and guard<40 do
    guard=guard+1
    local row=q[i]
    if type(row)~="table" then break end
    if row.text or row.ui or row.mimicSelect or row.drain or row.waitSound then break end
    if row.anim and CAPTURE_ANIMS[tostring(row.anim)] then
      sawCapture=true;table.remove(q,i);removed=removed+1
    elseif row.wait and tonumber(row.wait) and tonumber(row.wait)<=30 and (i==1 or sawCapture) then
      -- Gen 1 inserts a 20-frame stock delay directly in front of ballChain.
      table.remove(q,i);removed=removed+1
    elseif row.hitRow or row.hit then
      break
    elseif row.fn then
      -- Outcome/state functions (storeCaughtMon, enemy turn, etc.) are battle
      -- logic, not presentation. Never delete or execute them early.
      break
    else
      i=i+1
    end
  end
  s.captureHold.stripped=true
  s.captureHold.strippedRows=removed
  H.captureRowsStripped=(H.captureRowsStripped or 0)+removed
  return removed
end

local function captureUiOwned(s,battle)
  if not (s and s.captureHold and ownsSessionBattle(s,battle)) then return false end
  if captureAnimationActive(s) then return true end
  return s.captureHold.hideUI==true
end

function H.event(name,payload)
  local s=H.session
  if not s then return end
  if name=="battle.ball_thrown" then
    s.captureHold={active=true,stripped=false,hideUI=true,released=false,caught=type(payload)=="table" and payload.caught or nil}
    H.captureQueueHolds=(H.captureQueueHolds or 0)+1
  end
  -- Gen 2 resolves its pure model before BattleState replays the visible queue.
  -- Buffer those semantics here and release them at advanceQueue below. That
  -- keeps Pokemon, trainers, FX and camera on the SAME visible frame instead of
  -- allowing one subsystem to react several text/animation rows early.
  local gen2=Compat and Compat.isGen2Battle and Compat.isGen2Battle(s.battle)
  if gen2 and (name=="battle.move_used" or name=="battle.damage_dealt" or name=="battle.fainted") then
    stashSemantic(s,name,payload)
    return
  end
  -- Switches replace BattleState.player/enemy. Refresh the presentation
  -- references before providers process the event so Battle Arts/current-sprite
  -- rendering cannot retain the Pokemon that opened the battle.
  syncBattlers(s)
  if BattleDirector and type(BattleDirector.event)=="function" then
    pcall(BattleDirector.event,BattleDirector,s.context,name,payload)
  end
  if MoveFXOwnership and type(MoveFXOwnership.event)=="function" then
    pcall(MoveFXOwnership.event,MoveFXOwnership,s.context,name,payload)
  end
  if name=="battle.turn_started" or name=="battle.turn_ended" then s.context.phase="passive"
  elseif name=="battle.move_used" or name=="battle.presentation_move" then s.context.phase="attack"
  elseif name=="battle.damage_dealt" or name=="battle.presentation_damage" then s.context.phase="damage"
  elseif name=="battle.status_inflicted" then s.context.phase="reaction"
  elseif name=="battle.ball_thrown" then s.context.phase="capture"
  elseif name=="battle.fainted" or name=="battle.presentation_faint" then s.context.phase="faint"
  elseif name=="battle.battler_switched" then s.context.phase="switch"
  elseif name=="battle.ended" then s.context.phase="exit" end
  -- CurrentSpriteModels owns per-side actor identity. Do not invalidate and
  -- restart the whole presentation provider on a switch: that used to remove
  -- both actors, reset external providers, and make replacements follow a
  -- different path from the opening send-out.
  if CurrentSprites and type(CurrentSprites.event)=="function" then
    pcall(CurrentSprites.event,CurrentSprites,s.context,name,payload)
  end
  if syncCameraOwnership(s) then pcall(Camera.event,Camera,s.context,name,payload) end
  -- presentation_* events are synthesized inside this host rather than emitted
  -- by Gen1Recomp's global event bus, so trainers receive them explicitly too.
  if name=="battle.presentation_move" or name=="battle.presentation_damage" or name=="battle.presentation_faint" then
    if PlayerTrainer and type(PlayerTrainer.event)=="function" then pcall(PlayerTrainer.event,PlayerTrainer,s.context,name,payload) end
    if Trainer and type(Trainer.event)=="function" then pcall(Trainer.event,Trainer,s.context,name,payload) end
  end
end

local function render(s)
  local battle=Compat and Compat.sync(s.battle) or s.battle
  s.battle=battle;s.context.battle=battle;s.context.game=(battle and battle.game) or s.context.game
  syncBattlers(s)
  if not (battle and Arena) then return false end
  s.context.services.camera={pose=cameraPose(s)}
  local ok,surface=pcall(Arena.render,Arena,s.context,s.context.arena,function(world)
    world=world or {}
    local vp=world.vp
    local w,h=tonumber(world.width),tonumber(world.height)
    if tonumber(world.groundY) then s.context.groundY=world.groundY end
    s.context.services.renderSize={width=w,height=h}
    s.context.services.vp=vp
    s.context.services.stageVP=world.stageVP or vp
    s.context.services.figureScale=world.figureScale
    if type(world.project)=="function" then
      s.context.services.project=world.project
    elseif vp and w and h then
      s.context.services.project=function(x,y,z) return project(vp,w,h,x,y,z) end
    end
    if CurrentSprites then CurrentSprites:drawWorld(s.context) end
  end)
  if not ok then
    H.lastError=tostring(surface);log("error","standalone arena render failed: %s",tostring(surface));return nil
  end
  if not surface or surface==true or surface==V.FALLBACK then return nil end
  local gen2=Compat and Compat.isGen2Battle(battle)
  local renderer=battle.game and battle.game.renderer
  if not gen2 then
    if not (renderer and type(renderer.setWorldOverride)=="function") then return nil end
    renderer:setWorldOverride(surface)
  end
  s.presented=true;H.frames=H.frames+1
  return surface
end

function H.coversSide(battle,side)
  local s=H.session
  local same=s and ((Compat and Compat.matches(s.battle,battle)) or s.battle==battle)
  if not (same and s.presented and CurrentSprites) then return false end
  local ok,v=pcall(CurrentSprites.covers,CurrentSprites,s.context,side)
  return ok and v==true
end

local function cbeWorldOwns(battle)
  local s=H.session
  local same=s and ((Compat and Compat.matches(s.battle,battle)) or s.battle==battle)
  if same and s.started then return true end
  local bridge=V.StadiumBridge
  if bridge and type(bridge.ownsArena)=="function" then
    local ok,value=pcall(bridge.ownsArena,battle)
    if ok and value==true then return true end
  end
  return false
end

local function cbeModelsEnabled(battle)
  local settings=V.BattleSettings
  if not (settings and type(settings.pokemonModelsEnabled)=="function") then return true end
  local game=(battle and battle.game) or (V.mod and V.mod.game)
  local ok,value=pcall(settings.pokemonModelsEnabled,game)
  return (not ok) or value~=false
end

local function captureHidesNativeEnemy(battle)
  if not (PlayerTrainer and type(PlayerTrainer.captureStatus)=="function") then return false end
  local ok,status=pcall(PlayerTrainer.captureStatus,PlayerTrainer,{battle=battle,game=battle and battle.game})
  return ok and type(status)=="table" and status.active==true
end

-- Native battler pictures are a fallback for non-CBE model configurations,
-- not a layer that may blink through a CBE-owned 3D battle.  The delegated
-- Gen 1 Stadium host has no StandaloneHost session, so this ownership check is
-- intentionally based on arena/settings state as well as the local session.
function H.suppressesNativeSide(battle,side)
  if not cbeWorldOwns(battle) then return H.coversSide(battle,side) end
  if side=="enemy" and captureHidesNativeEnemy(battle) then return true end
  if cbeModelsEnabled(battle) then return true end
  return H.coversSide(battle,side)
end

function H.presentationFor(battle)
  return Compat and Compat.prepare(battle) or battle
end

local function drawGen2Surface(surface,targetW,targetH)
  if not (surface and love and love.graphics) then return false end
  local ok,w,h=pcall(surface.getDimensions,surface)
  if not ok or not (tonumber(w) and tonumber(h)) or w<=0 or h<=0 then return false end
  targetW=tonumber(targetW) or 160
  targetH=tonumber(targetH) or 144
  love.graphics.setColor(1,1,1,1)
  love.graphics.draw(surface,0,0,0,targetW/w,targetH/h)
  return true
end

-- Gen 2 draws its battle world and UI into one 160x144 scene. There are two
-- paper backgrounds on the widescreen path: BattleState:drawWidescreen's
-- window-sized surround and Chrome.clear's centred 160x144 panel. Animation
-- scanline composition can add the same logical background through
-- BattleAnimView:fillBackground. Suppress those background routines narrowly
-- while leaving battle flashes, text, command boxes, animations, and every
-- actor that failed open to the engine. This is the split Gen 1 gets from
-- Renderer.worldOverride.
local function withoutGen2Field(view,battle,fn,fieldW,fieldH)
  local g=love.graphics
  local rectangle=g.rectangle
  local skippedPaper=false
  fieldW=tonumber(fieldW) or 160
  fieldH=tonumber(fieldH) or 144

  local req=V.engineRequire or require
  local okChrome,Chrome=pcall(req,"src.ui.gen2.Chrome")
  local chromeClear=okChrome and type(Chrome)=="table" and Chrome.clear or nil
  if type(chromeClear)=="function" then
    Chrome.clear=function()
      -- Chrome.clear normally leaves black selected for borders/text.
      g.setColor(0,0,0,1)
    end
  end
  local okAnim,AnimView=pcall(req,"src.ui.gen2.BattleAnimView")
  local animFill=okAnim and type(AnimView)=="table" and AnimView.fillBackground or nil
  if type(animFill)=="function" then AnimView.fillBackground=function() end end

  g.rectangle=function(mode,x,y,w,h,...)
    if not skippedPaper and mode=="fill" and x==0 and y==0 and w==fieldW and h==fieldH then
      skippedPaper=true
      return
    end
    -- Compatibility fallback for an engine build that has the Gen 2 screen
    -- but does not expose Chrome as a require-able module.
    if not chromeClear and mode=="fill" and x==0 and y==0 and w==160 and h==144 then return end
    return rectangle(mode,x,y,w,h,...)
  end

  local ownDrawPic=rawget(view,"drawPic")
  local inheritedDrawPic=view.drawPic
  if type(inheritedDrawPic)=="function" then
    view.drawPic=function(self,mon,back,...)
      local side=back and "player" or "enemy"
      local trainerHidden=V.NativeTrainerSprites and type(V.NativeTrainerSprites.hides)=="function"
        and V.NativeTrainerSprites:hides(battle,side)
      if H.suppressesNativeSide(battle,side) or trainerHidden then return end
      return inheritedDrawPic(self,mon,back,...)
    end
  end
  local ok,res=pcall(fn)
  g.rectangle=rectangle
  if type(chromeClear)=="function" then Chrome.clear=chromeClear end
  if type(animFill)=="function" then AnimView.fillBackground=animFill end
  if ownDrawPic~=nil then view.drawPic=ownDrawPic else view.drawPic=nil end
  if not ok then error(res,0) end
  return res
end

-- Suppress the battle's opaque paper field while preserving every HUD/text /
-- animation draw above it.  This mirrors the engine's own worldOverride seam:
-- the arena lives in Renderer, while BattleState remains authoritative for UI.
local function withoutBattleField(battle,fn)
  local g=love.graphics
  local rectangle=g.rectangle
  local fieldSuppressed=false
  local shakeZoneFills={
    ["0:0:160:144"]=true,["8:0:80:32"]=true,["80:56:80:32"]=true,
    ["0:32:72:64"]=true,["88:0:72:56"]=true,["0:96:160:48"]=true,
  }
  local fx=battle and battle.fx
  local shaking=fx and (((tonumber(fx.shakeX) or 0)~=0) or ((tonumber(fx.shakeY) or 0)~=0) or ((tonumber(fx.shake) or 0)>0))
  g.rectangle=function(mode,x,y,w,h,...)
    local r,gg,b,a=g.getColor()
    local full=mode=="fill" and x==0 and y==0 and h==144 and (w==160 or w==304)
    if not fieldSuppressed and full and (a or 1)>.99 then
      fieldSuppressed=true
      local target=g.getCanvas()
      if target~=nil and (target==battle.bgCanvas or target==battle.waveCanvas) then g.clear(0,0,0,0) end
      return
    end
    local zone=mode=="fill" and shaking and shakeZoneFills[table.concat({x,y,w,h},":")]
    if fieldSuppressed and zone and (r or 1)>.99 and (gg or 1)>.99 and (b or 1)>.99 and (a or 1)>.99 then return end
    return rectangle(mode,x,y,w,h,...)
  end
  local ok,res=pcall(fn)
  g.rectangle=rectangle
  if not ok then error(res,0) end
  return res
end

function H.install(force)
  local req=V.engineRequire or require
  local ok,BattleState=pcall(req,"src.battle.BattleState")
  if not ok or type(BattleState)~="table" then H.lastError=tostring(BattleState);return false end

  if type(BattleState.drawPicsLayer)=="function" and BattleState.drawPicsLayer~=H.picsWrapper then
    local inner=BattleState.drawPicsLayer
    H.picsEpoch=(H.picsEpoch or 0)+1
    local epoch=H.picsEpoch
    H.picsWrapper=function(self,slide,sx,sy,onlySide,skipMenuClip)
      -- Other presentation mods may re-wrap BattleState at battle.started.
      -- When CBE reasserts ownership, older CBE wrappers remain nested inside
      -- those foreign wrappers. Make every stale generation inert so only the
      -- newest, outermost CBE wrapper can suppress/draw the battle.
      if epoch~=H.picsEpoch then
        return inner(self,slide,sx,sy,onlySide,skipMenuClip)
      end
      if onlySide=="player" or onlySide=="enemy" then
        if H.suppressesNativeSide(self,onlySide) then return end
        return inner(self,slide,sx,sy,onlySide,skipMenuClip)
      end
      local pc=H.suppressesNativeSide(self,"player")
      local ec=H.suppressesNativeSide(self,"enemy")
      if pc and ec then return end
      if pc then onlySide="enemy" elseif ec then onlySide="player" end
      return inner(self,slide,sx,sy,onlySide,skipMenuClip)
    end
    BattleState.drawPicsLayer=H.picsWrapper
  end

  -- Gen 1's authoritative catch event is emitted from the item action BEFORE
  -- the stock wait/ballChain/outcome rows are consumed. Freeze the engine queue
  -- for the duration of CBE's wall-clock capture, strip only those native visual
  -- rows, then release the untouched battle result. Game-speed multipliers can
  -- no longer make "caught!" dialogue outrun the ball animation.
  if type(BattleState.updateQueue)=="function" and BattleState.updateQueue~=H.updateQueueWrapper then
    local inner=BattleState.updateQueue
    H.updateQueueEpoch=(H.updateQueueEpoch or 0)+1
    local epoch=H.updateQueueEpoch
    H.updateQueueWrapper=function(self,...)
      if epoch~=H.updateQueueEpoch then return inner(self,...) end
      local s=H.session
      if s and ownsSessionBattle(s,self) and s.captureHold then
        stripNativeCapturePrefix(self,s)
        if captureAnimationActive(s) then
          return true
        end
        if not s.captureHold.released then
          s.captureHold.released=true
          -- The old "used BALL" glyph buffer intentionally persists through
          -- native animations. CBE owns those animations, so erase that stale
          -- buffer before allowing the outcome row to start.
          if type(self.shown)=="table" then self.shown={} end
          self.msgHold=nil;self.msgPrompt=nil
        end
        local result=inner(self,...)
        -- As soon as the queued result starts, normal dialogue owns the lower
        -- panel again. The catch object's audio latch remains independent.
        if self.current or self.waitingUI or self.waitingSound or not result then
          s.captureHold.hideUI=false
          s.captureHold=nil
        end
        return result
      end
      return inner(self,...)
    end
    BattleState.updateQueue=H.updateQueueWrapper
  end

  -- Hide the stock Gen-1 message panel while CBE owns capture choreography.
  -- This removes the lingering "used GREAT BALL" box seen in the reference
  -- recording without suppressing the later catch/miss/nickname dialogue.
  if type(BattleState.drawTextArea)=="function" and BattleState.drawTextArea~=H.textWrapper then
    local inner=BattleState.drawTextArea
    H.textEpoch=(H.textEpoch or 0)+1;local epoch=H.textEpoch
    H.textWrapper=function(self,...)
      if epoch~=H.textEpoch then return inner(self,...) end
      local s=H.session
      if captureUiOwned(s,self) then H.captureUiSuppressed=(H.captureUiSuppressed or 0)+1;return end
      return inner(self,...)
    end
    BattleState.drawTextArea=H.textWrapper
  end

  -- Both generations expose bottomUIVisible. Make capture ownership explicit at
  -- this shared seam as well; Gen 2 draws its message/menu panel through it,
  -- while Gen 1's direct drawTextArea wrapper above handles older builds that
  -- do not consult the hook for message pages.
  if type(BattleState.bottomUIVisible)=="function" and BattleState.bottomUIVisible~=H.bottomWrapper then
    local inner=BattleState.bottomUIVisible
    H.bottomEpoch=(H.bottomEpoch or 0)+1;local epoch=H.bottomEpoch
    H.bottomWrapper=function(self,...)
      if epoch~=H.bottomEpoch then return inner(self,...) end
      local s=H.session
      if captureUiOwned(s,self) then return false end
      return inner(self,...)
    end
    BattleState.bottomUIVisible=H.bottomWrapper
  end

  -- A Colosseum capture is a clean cinematic beat: native HP/name HUD rows do
  -- not remain glued over the ball sequence. Keep the hook visual-only; the
  -- battle state's HP/status data continues updating underneath and reappears
  -- unchanged when the result dialogue is released.
  if type(BattleState.statusHUDVisible)=="function" and BattleState.statusHUDVisible~=H.statusWrapper then
    local inner=BattleState.statusHUDVisible
    H.statusEpoch=(H.statusEpoch or 0)+1;local epoch=H.statusEpoch
    H.statusWrapper=function(self,...)
      if epoch~=H.statusEpoch then return inner(self,...) end
      local s=H.session
      if captureUiOwned(s,self) then return false end
      return inner(self,...)
    end
    BattleState.statusHUDVisible=H.statusWrapper
  end

  -- Gen 2's Chrome battle panel composites text, HUD and sprites in one panel
  -- and older engine revisions do not necessarily consult bottomUIVisible for
  -- every one of those layers. Suppress the complete native panel only during
  -- CBE's capture choreography. The arena and CBE 3D actors are drawn outside
  -- this panel, and advanceQueue remains frozen, so no stock sprite/text can
  -- leak while the ball is still moving.
  if type(BattleState.drawPanel)=="function" and BattleState.drawPanel~=H.panelWrapper then
    local inner=BattleState.drawPanel
    H.panelEpoch=(H.panelEpoch or 0)+1;local epoch=H.panelEpoch
    H.panelWrapper=function(self,...)
      if epoch~=H.panelEpoch then return inner(self,...) end
      local s=H.session
      if captureUiOwned(s,self) then H.captureUiSuppressed=(H.captureUiSuppressed or 0)+1;return end
      return inner(self,...)
    end
    BattleState.drawPanel=H.panelWrapper
  end

  -- Gold resolves the whole turn in its pure battle model, then its screen
  -- replays the queued `move` event later. The semantic battle.move_used event
  -- is therefore too early for a visible Stadium performance: the actor can
  -- finish before the "used MOVE" page reaches the screen. Start portable
  -- actor motion at the screen's authoritative queue-consumption boundary.
  if Compat and Compat.current and Compat.current()==2
      and type(BattleState.advanceQueue)=="function"
      and BattleState.advanceQueue~=H.queueWrapper then
    local inner=BattleState.advanceQueue
    H.queueEpoch=(H.queueEpoch or 0)+1
    local epoch=H.queueEpoch
    H.queueWrapper=function(self,...)
      if epoch~=H.queueEpoch then return inner(self,...) end
      local s=H.session
      if s and ownsSessionBattle(s,self) and s.captureHold then
        if captureAnimationActive(s) then return true end
        if not s.captureHold.released then s.captureHold.released=true end
        -- Gen 2's event queue is semantic rather than Gen 1's BALL_ANIMS chain;
        -- release it only after CBE animation completion and keep the result row.
        s.captureHold.hideUI=false;s.captureHold=nil
      end
      local event=self.queue and self.queue[1]
      if s and type(event)=="table" then
        local battle=Compat and Compat.prepare(self) or self
        local owns=(Compat and Compat.matches(s.battle,battle)) or s.battle==battle
        if owns then
          local liveBattle=self.battle or self
          local side=BattleSides and BattleSides.value and BattleSides.value(event.side) or event.side
          if event.kind=="move" and not event.missed and not event.__cbePortableActorMove then
            event.__cbePortableActorMove=true
            H.presentationMoveEvents=H.presentationMoveEvents+1
            H.event("battle.presentation_move",visiblePayload(s,liveBattle,"move",side,event))
          elseif event.kind=="damage" and side and not event.__cbePortableActorDamage then
            event.__cbePortableActorDamage=true
            H.presentationDamageEvents=H.presentationDamageEvents+1
            H.event("battle.presentation_damage",visiblePayload(s,liveBattle,"damage",side,event))
          elseif event.kind=="faint" and side and not event.__cbePortableActorFaint then
            -- Fire at the FIRST faint queue encounter: BattleState starts its
            -- sink animation here, reinserts the same row, and only prints the
            -- faint text after the slide. The 3D native faint must begin at
            -- that first visual boundary, not when the later text appears.
            event.__cbePortableActorFaint=true
            H.presentationFaintEvents=H.presentationFaintEvents+1
            H.event("battle.presentation_faint",visiblePayload(s,liveBattle,"faint",side,event))
          end
        end
      end
      return inner(self,...)
    end
    BattleState.advanceQueue=H.queueWrapper
  end

  if BattleState.draw~=H.drawWrapper then
    local inner=BattleState.draw
    H.drawEpoch=(H.drawEpoch or 0)+1
    local epoch=H.drawEpoch
    H.drawWrapper=function(self,...)
      local args={...}
      if epoch~=H.drawEpoch then return inner(self,unpack(args)) end
      local s=H.session
      local battle=Compat and Compat.prepare(self) or self
      local owns=s and ((Compat and Compat.matches(s.battle,battle)) or s.battle==battle)
        and enabled((battle and battle.game) or self.game)
      if owns and Compat then
        s.battle=Compat.sync(battle);s.context.battle=s.battle;s.context.game=s.battle.game or s.context.game
      end
      if owns then s.externalPresentation=nil end
      local surface=owns and render(s) or nil
      if surface then
        if Compat and Compat.isGen2Battle(battle) then
          drawGen2Surface(surface)
          return withoutGen2Field(self,battle,function() return inner(self,unpack(args)) end)
        end
        self.letterboxWhite=false
        love.graphics.clear(0,0,0,0)
        local results={withoutBattleField(self,function() return inner(self,unpack(args)) end)}
        -- CBE must be the LAST writer to Renderer.worldOverride. StadiumFX
        -- deliberately reattaches its own BattleHost at battle.started and an
        -- inner host may call setWorldOverride while our UI pass is running.
        -- Reassert the already-rendered CBE surface after every inner draw so
        -- no nested provider can replace the Colosseum world for this frame.
        local renderer=(battle and battle.game and battle.game.renderer) or (self.game and self.game.renderer)
        if renderer and type(renderer.setWorldOverride)=="function" then
          renderer:setWorldOverride(surface)
        end
        return unpack(results)
      end
      if owns then
        -- A CBE render failure is a CBE failure, never permission for Battle
        -- Art/Stadium/another compositor to take over the battle. Preserve the
        -- engine HUD/input flow but suppress the native/external battle field.
        if Compat and Compat.isGen2Battle(battle) then
          return withoutGen2Field(self,battle,function() return inner(self,unpack(args)) end)
        end
        self.letterboxWhite=false
        love.graphics.clear(0,0,0,0)
        local results={withoutBattleField(self,function() return inner(self,unpack(args)) end)}
        local renderer=(battle and battle.game and battle.game.renderer) or (self.game and self.game.renderer)
        if renderer and type(renderer.setWorldOverride)=="function" then renderer:setWorldOverride(nil) end
        return unpack(results)
      end
      self.letterboxWhite=nil
      return inner(self,unpack(args))
    end
    BattleState.draw=H.drawWrapper
  end

  -- Gold normally asks its battle screen for the edge-to-edge widescreen pass
  -- instead of calling :draw(). Patch that live path as well; otherwise the
  -- arena would exist only in nested/contained draws and normal Gen 2 battles
  -- would still paint the stock white field.
  if type(BattleState.drawWidescreen)=="function" and BattleState.drawWidescreen~=H.wideWrapper then
    local inner=BattleState.drawWidescreen
    H.wideEpoch=(H.wideEpoch or 0)+1
    local epoch=H.wideEpoch
    H.wideWrapper=function(self,w,h,...)
      local args={...}
      if epoch~=H.wideEpoch then return inner(self,w,h,unpack(args)) end
      local s=H.session
      local battle=Compat and Compat.prepare(self) or self
      local owns=s and ((Compat and Compat.matches(s.battle,battle)) or s.battle==battle)
        and enabled((battle and battle.game) or self.game)
      if owns and Compat then
        s.battle=Compat.sync(battle);s.context.battle=s.battle;s.context.game=s.battle.game or s.context.game
      end
      if owns then s.externalPresentation=nil end
      local surface=owns and render(s) or nil
      if surface and Compat and Compat.isGen2Battle(battle) then
        drawGen2Surface(surface,w,h)
        return withoutGen2Field(self,battle,function() return inner(self,w,h,unpack(args)) end,w,h)
      end
      return inner(self,w,h,unpack(args))
    end
    BattleState.drawWidescreen=H.wideWrapper
  end
  BattleState.cbeStandaloneHostHook=true
  H.installed=true
  return true
end

function H.finish(reason)
  local s=H.session
  if not s then return end
  if CurrentSprites then pcall(CurrentSprites.finish,CurrentSprites,s.context,reason) end
  if Camera and s.cameraActive then pcall(Camera.finish,Camera,s.context,reason) end
  if Arena then pcall(Arena.finish,Arena,s.context,reason) end
  if s.battle then s.battle.__cbePresentationQueueSync=nil end
  if Compat then Compat.release(s.battle) end
  H.session=nil
end

function H.status()
  local s=H.session
  local ps=s and s.context and s.context.sides and s.context.sides.player and s.context.sides.player.battler
  local es=s and s.context and s.context.sides and s.context.sides.enemy and s.context.sides.enemy.battler
  return {installed=H.installed,active=s~=nil,started=s and s.started==true,ownershipOnly=s and s.ownershipOnly==true,generation=(s and s.battle and s.battle.__cbeGeneration) or 1,arena=s and s.context.arena and s.context.arena.id or nil,
    actor="current-sprites",playerSpecies=ps and ps.mon and ps.mon.species or nil,enemySpecies=es and es.mon and es.mon.species or nil,
    cameraActive=s and s.cameraActive==true,cameraMode=not s and "inactive" or (s.cameraActive and "cinematic" or "neutral-static"),frames=H.frames,
    externalPresentation=s and s.externalPresentation or nil,externalFrames=H.externalFrames,presentationMoveEvents=H.presentationMoveEvents,presentationDamageEvents=H.presentationDamageEvents,presentationFaintEvents=H.presentationFaintEvents,
    captureQueueHolds=H.captureQueueHolds or 0,captureRowsStripped=H.captureRowsStripped or 0,captureUiSuppressed=H.captureUiSuppressed or 0,
    captureFlow=s and s.captureHold and "cbe-wall-clock-hold" or nil,
    error=H.lastError,updateError=H.lastUpdateError,contract="CBE BattleState/world/camera/trainer stage is absolute on Gen 1 + Gen 2 while Arenas ON; render failure never delegates"}
end
return H
