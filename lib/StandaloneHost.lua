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
local H={session=nil,installed=false,drawWrapper=nil,wideWrapper=nil,picsWrapper=nil,queueWrapper=nil,lastError=nil,lastUpdateError=nil,frames=0,externalFrames=0,presentationMoveEvents=0}

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

-- A legacy model package may own the entire live battle world rather than
-- lending CBE a portable actor. Discover that ownership by capability instead
-- of package id and yield the frame to avoid two compositors fighting. New
-- integrations should publish portable battleActors/battlePresentation so the
-- selected Pokemon can remain inside CBE's arena.
local function externalFullFramePresenter(context)
  local lookup=V.ModLookup
  local game=(context and context.game) or (context and context.battle and context.battle.game)
  local handles=lookup and type(lookup.each)=="function" and lookup.each(V.mod,game) or {}
  local winner,winnerScore
  for _,handle in ipairs(handles) do
    local exports=handle and handle.exports
    local actors=exports and exports.battleActors
    local function selected(api)
      if type(api)~="table" or type(api.selected)~="function" then return true end
      local ok,value=pcall(api.selected,context)
      return ok and value~=false
    end
    local portableActors=type(actors)=="table" and tonumber(actors.version)==1
      and type(actors.acquire)=="function" and type(actors.withRenderer)=="function" and selected(actors)
    local presentation=exports and (exports.battlePresentation or exports.battlePresenter)
    local portablePresentation=type(presentation)=="table" and tonumber(presentation.version)==1
      and presentation.portable~=false and type(presentation.drawWorld)=="function"
      and type(presentation.covers)=="function" and selected(presentation)
    if not portableActors and not portablePresentation then
      local world=exports and (exports.battleWorld or exports.battleFullFrame)
      local status=type(world)=="table" and world.status or (exports and exports.inWorld3DBattleStatus)
      local fullFrame=type(world)=="table" and tonumber(world.version)==1 and world.fullFrame==true
      if type(status)=="function" and (fullFrame or world==nil) then
        local ok,value=pcall(status,context)
        local active=ok and ((type(value)=="table" and value.active==true) or value==true)
        if active then
          local score=tonumber((type(world)=="table" and world.priority) or 0) or 0
          if not winner or score>winnerScore
              or (score==winnerScore and tostring(handle.id)<tostring(winner.id)) then
            winner,winnerScore=handle,score
          end
        end
      end
    end
  end
  return winner and winner.id or nil
end


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
  local s={battle=battle,context=contextFor(battle),presented=false,started=false}
  H.session=s
  local ok,why=beginProviders(s)
  if not ok then
    H.lastError=tostring(why);H.session=nil
    local level=(why=="arena definition unavailable" or why=="arena declined") and "warn" or "error"
    log(level,"standalone arena begin failed: %s",tostring(why))
    return false
  end
  s.started=true;H.lastError=nil;H.lastUpdateError=nil
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

function H.event(name,payload)
  local s=H.session
  if not s then return end
  -- Switches replace BattleState.player/enemy. Refresh the presentation
  -- references before providers process the event so Battle Arts/current-sprite
  -- rendering cannot retain the Pokemon that opened the battle.
  syncBattlers(s)
  if name=="battle.turn_started" or name=="battle.turn_ended" then s.context.phase="passive"
  elseif name=="battle.move_used" or name=="battle.presentation_move" then s.context.phase="attack"
  elseif name=="battle.damage_dealt" then s.context.phase="damage"
  elseif name=="battle.status_inflicted" then s.context.phase="reaction"
  elseif name=="battle.ball_thrown" then s.context.phase="capture"
  elseif name=="battle.fainted" then s.context.phase="faint"
  elseif name=="battle.battler_switched" then s.context.phase="switch"
  elseif name=="battle.ended" then s.context.phase="exit" end
  if name=="battle.battler_switched" and CurrentSprites then
    pcall(CurrentSprites.invalidate,CurrentSprites,s.context)
    syncBattlers(s)
  end
  if CurrentSprites and type(CurrentSprites.event)=="function" then
    pcall(CurrentSprites.event,CurrentSprites,s.context,name,payload)
  end
  if syncCameraOwnership(s) then pcall(Camera.event,Camera,s.context,name,payload) end
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
      if H.coversSide(battle,side) or trainerHidden then return end
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
    H.picsWrapper=function(self,slide,sx,sy,onlySide,skipMenuClip)
      if onlySide=="player" or onlySide=="enemy" then
        if H.coversSide(self,onlySide) then return end
        return inner(self,slide,sx,sy,onlySide,skipMenuClip)
      end
      local pc=H.coversSide(self,"player")
      local ec=H.coversSide(self,"enemy")
      if pc and ec then return end
      if pc then onlySide="enemy" elseif ec then onlySide="player" end
      return inner(self,slide,sx,sy,onlySide,skipMenuClip)
    end
    BattleState.drawPicsLayer=H.picsWrapper
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
    H.queueWrapper=function(self,...)
      local event=self.queue and self.queue[1]
      local s=H.session
      if s and type(event)=="table" and event.kind=="move"
          and not event.missed and not event.__cbePortableActorMove then
        local battle=Compat and Compat.prepare(self) or self
        local owns=(Compat and Compat.matches(s.battle,battle)) or s.battle==battle
        if owns then
          event.__cbePortableActorMove=true
          H.presentationMoveEvents=H.presentationMoveEvents+1
          H.event("battle.presentation_move",{
            battle=self.battle or self,side=event.side,moveId=event.move,
          })
        end
      end
      return inner(self,...)
    end
    BattleState.advanceQueue=H.queueWrapper
  end

  if BattleState.draw~=H.drawWrapper then
    local inner=BattleState.draw
    H.drawWrapper=function(self,...)
      local args={...}
      local s=H.session
      local battle=Compat and Compat.prepare(self) or self
      local owns=s and ((Compat and Compat.matches(s.battle,battle)) or s.battle==battle)
        and enabled((battle and battle.game) or self.game)
      if owns and Compat then
        s.battle=Compat.sync(battle);s.context.battle=s.battle;s.context.game=s.battle.game or s.context.game
      end
      local external=owns and externalFullFramePresenter(s.context) or nil
      if owns then s.externalPresentation=external;if external then s.presented=false;H.externalFrames=H.externalFrames+1 end end
      local surface=owns and not external and render(s) or nil
      if surface then
        if Compat and Compat.isGen2Battle(battle) then
          drawGen2Surface(surface)
          return withoutGen2Field(self,battle,function() return inner(self,unpack(args)) end)
        end
        self.letterboxWhite=false
        love.graphics.clear(0,0,0,0)
        return withoutBattleField(self,function() return inner(self,unpack(args)) end)
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
    H.wideWrapper=function(self,w,h,...)
      local args={...}
      local s=H.session
      local battle=Compat and Compat.prepare(self) or self
      local owns=s and ((Compat and Compat.matches(s.battle,battle)) or s.battle==battle)
        and enabled((battle and battle.game) or self.game)
      if owns and Compat then
        s.battle=Compat.sync(battle);s.context.battle=s.battle;s.context.game=s.battle.game or s.context.game
      end
      local external=owns and externalFullFramePresenter(s.context) or nil
      if owns then s.externalPresentation=external;if external then s.presented=false;H.externalFrames=H.externalFrames+1 end end
      local surface=owns and not external and render(s) or nil
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
  if Compat then Compat.release(s.battle) end
  H.session=nil
end

function H.status()
  local s=H.session
  local ps=s and s.context and s.context.sides and s.context.sides.player and s.context.sides.player.battler
  local es=s and s.context and s.context.sides and s.context.sides.enemy and s.context.sides.enemy.battler
  return {installed=H.installed,active=s~=nil,generation=(s and s.battle and s.battle.__cbeGeneration) or 1,arena=s and s.context.arena and s.context.arena.id or nil,
    actor="current-sprites",playerSpecies=ps and ps.mon and ps.mon.species or nil,enemySpecies=es and es.mon and es.mon.species or nil,
    cameraActive=s and s.cameraActive==true,cameraMode=not s and "inactive" or (s.cameraActive and "cinematic" or "neutral-static"),frames=H.frames,
    externalPresentation=s and s.externalPresentation or nil,externalFrames=H.externalFrames,presentationMoveEvents=H.presentationMoveEvents,
    error=H.lastError,updateError=H.lastUpdateError,contract="standalone-stage-host"}
end
return H
