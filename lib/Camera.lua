local V = ...
local Trainer = V and V.Trainer
local PlayerTrainer = V and V.PlayerTrainer
local BattleDirector=V and V.BattleDirector
local C = {}

local DEFAULT = {orbit=1.33,elevation=0.34,radius=60,fov=40,focus={0,6,0}}
local MANUAL_RELEASE_DELAY = 1.35
local AUTO_RETURN_BLEND = 0.72
local AUTHORED_ZOOM_OUT = 1.045

-- Battle input can advance several queue checkpoints in a fraction of a
-- second. Those checkpoints may emit move/damage/turn events back-to-back,
-- but they are NOT camera buttons. Commit to readable shots and coalesce
-- lower-priority events rather than cutting once per queue notification.
local EVENT_HOLDS = {
  attack = 0.82,
  damage = 0.68,
  reaction = 0.86,
  capture = 1.35,
  faint = 2.05,
  switch = 1.42,
  exit = 1.22,
  passive = 1.05,
  command = 1.05,
}
local EVENT_PRIORITY = { passive=0, command=1, attack=2, damage=3, reaction=3, capture=4, switch=4, faint=5, exit=6 }
local MIN_INTERRUPT_AGE = 0.44

-- Gen1Recomp fast-forward advances the battle fixed step multiple times per
-- rendered frame. Colosseum choreography belongs to that same game-time clock:
-- 4X should look like the original battle fast-forwarded, NOT replace the
-- authored shot sequence with a wide master or stretch individual holds.
local function battleSpeed(ctx)
  local b=type(ctx)=="table" and (ctx.battle or (ctx.kind and ctx)) or nil
  local game=(b and b.game) or (ctx and ctx.game) or (V and V.mod and V.mod.game)
  local speed
  if game and type(game.logicSpeed)=="function" then
    local ok,value=pcall(game.logicSpeed,game)
    if ok then speed=tonumber(value) end
  end
  if not speed then
    local opts=game and game.save and game.save.options
    speed=tonumber(opts and (opts.speedBattle or opts.speed)) or 1
  end
  if speed~=speed or speed<1 then speed=1 end
  return speed
end

local function holdScale(speed)
  -- Holds are authored in game-time. Fast-forward shortens their wall-clock
  -- duration naturally because the game clock advances faster.
  return 1
end

local function phaseAllowedAtSpeed(phase,speed)
  -- Preserve the complete source-style shot vocabulary at every speed. Dropping
  -- impact/reaction cuts at 4X was the main reason accelerated footage stayed
  -- parked on a distant master while the actors were already performing.
  return true
end

-- Colosseum rarely leaves the battle on one dead master shot. These are
-- deliberate broadcast-style compositions with a little movement inside each
-- hold. Camera travel is kept subtle; the variety comes from shot choice, not
-- a constant orbit around the arena.
local PASSIVE_SHOTS = {
  -- Colosseum-authentic direction: compositions HOLD.  Motion inside the shot
  -- is a small dolly/focus drift, not a continuous tour around the stadium.
  {eye={51,17,4},   focus={0,5.8,0},   fov=35, hold=4.80, blend=1.05, travel={-1.8,.35,-.8}, focusTravel={0,.06,0}},
  {eye={-50,17,-4}, focus={0,5.8,0},   fov=35, hold=4.60, blend=1.05, travel={1.7,.35,.8},   focusTravel={0,.06,0}},
  -- Trainer/Pokemon over-shoulder compositions are used sparingly but held
  -- long enough to read the human performance instead of immediately cutting.
  {eye={-28,14,38}, focus={6.2,6.0,18.2}, fov=35, hold=4.20, blend=.95, travel={1.2,.25,-1.0}, focusTravel={-.25,.04,-.35}},
  {eye={28,14,-38}, focus={-6.2,6.0,-18.2},fov=35, hold=4.20, blend=.95, travel={-1.2,.25,1.0},focusTravel={.25,.04,.35}},
  -- Low battle-level angles provide scale without constantly changing sides.
  {eye={18,10,38},  focus={-1,5.2,-4},fov=33, hold=4.35, blend=1.00, travel={-1.0,.30,-1.4},focusTravel={.25,.06,.45}},
  {eye={-18,10,-38},focus={1,5.2,4}, fov=33, hold=4.35, blend=1.00, travel={1.0,.30,1.4}, focusTravel={-.25,.06,-.45}},
}


local state = {
  time=0, idleClock=0, phaseAge=0, phase="intro", lastPose=nil, startPose=nil,
  eventSide=nil,eventIndex=0,eventResult=nil,resultPending=nil,resultAt=0,shotOffset=0,special=nil,specialUntil=0,
  manual=false, manualLocked=false, manualIdle=0, returning=false, keys={},
  shotLockUntil=0,pendingEvent=nil,lastCutTime=-999,lastEventName=nil,logicSpeed=1,
  orbit=DEFAULT.orbit,elevation=DEFAULT.elevation,radius=DEFAULT.radius,fov=DEFAULT.fov,
  focus={DEFAULT.focus[1],DEFAULT.focus[2],DEFAULT.focus[3]},
  mouseX=nil,mouseY=nil,
}

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function smooth(t) t=clamp(t,0,1); return t*t*(3-2*t) end
local function copy3(v) return {v[1],v[2],v[3]} end
local function copyPose(p)
  if not p then return nil end
  return {eye=copy3(p.eye),focus=copy3(p.focus),fov=p.fov}
end
local function mix(a,b,t)
  if not a then return copyPose(b) end
  t=smooth(t)
  local function v3(x,y) return {x[1]+(y[1]-x[1])*t,x[2]+(y[2]-x[2])*t,x[3]+(y[3]-x[3])*t} end
  return {eye=v3(a.eye,b.eye),focus=v3(a.focus,b.focus),fov=a.fov+(b.fov-a.fov)*t}
end
local function widenAuthored(pose)
  if not pose then return pose end
  local out=copyPose(pose)
  -- Widen field width without turning the camera into a fisheye lens.
  out.fov=2*math.atan(math.tan(out.fov*0.5)*AUTHORED_ZOOM_OUT)
  return out
end
local function arenaFrame(pose,arena)
  if not pose then return pose end
  local out=copyPose(pose)
  local cam=arena and arena.camera
  local side=cam and tonumber(cam.side) or 58
  local k=clamp(side/58,0.93,1.10)
  -- Larger environments move the camera itself farther away; this is more
  -- natural than endlessly increasing FOV and keeps Pokemon/trainer scale
  -- readable. Water Colosseum is k~=1 and therefore retains its stable framing.
  local f=out.focus
  out.eye={f[1]+(out.eye[1]-f[1])*k, f[2]+(out.eye[2]-f[2])*(0.96+0.12*k), f[3]+(out.eye[3]-f[3])*k}
  -- Realgam's identity lives above the battle deck: stacked crowd galleries and
  -- tower machinery. Bias the same held-shot compositions slightly upward
  -- rather than inventing extra cuts or a wider/fisheye lens.
  if arena and arena.id=="realgam_colosseum" then
    out.eye[2]=out.eye[2]-.65
    out.focus[2]=out.focus[2]+1.35
  end
  return out
end
local function resetManual()
  state.orbit=DEFAULT.orbit;state.elevation=DEFAULT.elevation;state.radius=DEFAULT.radius;state.fov=DEFAULT.fov
  state.focus={DEFAULT.focus[1],DEFAULT.focus[2],DEFAULT.focus[3]}
  state.mouseX=nil;state.mouseY=nil
end
local function isDown(key) return love and love.keyboard and love.keyboard.isDown and love.keyboard.isDown(key) and true or false end
local function pressed(key)
  local d=isDown(key); local was=state.keys[key]; state.keys[key]=d
  return d and not was
end
local function mouseDown(button)
  return love and love.mouse and love.mouse.isDown and love.mouse.isDown(button) and true or false
end
local function battleOf(ctx)
  if type(ctx)~="table" then return nil end
  return ctx.battle or (ctx.kind and ctx) or nil
end
local function battleHash(ctx)
  local b=battleOf(ctx)
  local id=(b and b.trainer and (b.trainer.id or b.trainer.name)) or (b and b.oppClass) or (b and b.kind) or "battle"
  local h=0
  for i=1,#tostring(id) do h=(h*33+tostring(id):byte(i))%65521 end
  return h
end
local function sideValue(value)
  if value==nil then return nil end
  if type(value)=="string" then
    local key=value:lower()
    if key=="player" or key=="ally" or key=="friendly" or key=="p1" then return "player" end
    if key=="enemy" or key=="opponent" or key=="foe" or key=="p2" then return "enemy" end
    local n=tonumber(value)
    if n==1 then return "player" elseif n==2 then return "enemy" end
    return nil
  end
  if type(value)=="number" then
    if value==1 then return "player" elseif value==2 then return "enemy" end
    return nil
  end
  if type(value)=="table" then
    -- Current Gen1Recomp Battlers explicitly expose isPlayer=false for foes.
    -- The old truthiness test recognized only the player half of that contract.
    if type(value.isPlayer)=="boolean" then return value.isPlayer and "player" or "enemy" end
    for _,k in ipairs({"side","index","id","name","team","ownerSide"}) do
      local resolved=sideValue(value[k])
      if resolved then return resolved end
    end
  end
  return nil
end

local function sideFrom(ctx,payload,fields)
  local b=battleOf(ctx)
  if type(payload)~="table" then return nil end
  for _,key in ipairs(fields or {"user","attacker","source","battler","side","target"}) do
    local value=payload[key]
    local resolved=sideValue(value)
    if resolved then return resolved end
    if b and value then
      if value==b.player then return "player" end
      if value==b.enemy then return "enemy" end
    end
  end
  return nil
end
local function arenaPoint(arena,side,y)
  -- Camera coordinates live in STAGE space. Pokemon providers receive an
  -- actor view-projection with figureScale already multiplied into it, so
  -- arena.player/enemy are intentionally inverse-scaled actor coordinates.
  -- Focusing the camera on those raw actor coordinates double-counts that
  -- inverse and pushes the visible Pokemon toward an edge. The visual anchors
  -- are the real on-stage positions after the actor transform is applied.
  local p=arena and ((side=="player" and arena.visualPlayer) or (side=="enemy" and arena.visualEnemy))
  if not p and arena then p=arena[side] end
  p=p or (side=="player" and {0,14.5} or {0,-14.5})
  return {p[1] or 0,y or 6.5,p[2] or 0}
end
local function trainerPoint(side,y)
  if side=="player" and PlayerTrainer and type(PlayerTrainer.anchor)=="function" then return PlayerTrainer:anchor(y) end
  if side=="enemy" and Trainer and type(Trainer.anchor)=="function" then return Trainer:anchor(y) end
  if side=="player" then return {13.2,y or 7.0,25.8} end
  return {-13.2,y or 7.0,-25.8}
end
local function other(side) return side=="enemy" and "player" or "enemy" end
local function manualPose()
  local r=state.radius; local ce=math.cos(state.elevation); local f=state.focus
  return {
    eye={f[1]+math.sin(state.orbit)*r*ce, f[2]+math.sin(state.elevation)*r, f[3]+math.cos(state.orbit)*r*ce},
    focus={f[1],f[2],f[3]}, fov=math.rad(state.fov),
  }
end

local function shotPose(s,u)
  u=smooth(clamp(u or 0,0,1))
  local tr=s.travel or {0,0,0}; local fr=s.focusTravel or {0,0,0}
  return {
    eye={s.eye[1]+tr[1]*u,s.eye[2]+tr[2]*u,s.eye[3]+tr[3]*u},
    focus={s.focus[1]+fr[1]*u,s.focus[2]+fr[2]*u,s.focus[3]+fr[3]*u},
    fov=math.rad(s.fov),
  }
end
local function passiveShot(arena)
  local count=#PASSIVE_SHOTS
  if count==0 then return manualPose() end
  local total=0
  for _,s in ipairs(PASSIVE_SHOTS) do total=total+s.hold+s.blend end
  local t=state.idleClock%total
  for seq=1,count do
    local idx=((seq-1+state.shotOffset)%count)+1
    local s=PASSIVE_SHOTS[idx]; local span=s.hold+s.blend
    if t<=span then
      if t<=s.hold then return shotPose(s,t/math.max(0.01,s.hold)) end
      local nidx=(idx%count)+1
      local a=shotPose(s,1); local b=shotPose(PASSIVE_SHOTS[nidx],0)
      return mix(a,b,(t-s.hold)/math.max(0.01,s.blend))
    end
    t=t-span
  end
  return shotPose(PASSIVE_SHOTS[1],0)
end

local function trainerVisible(ctx,side)
  local provider=side=="player" and PlayerTrainer or Trainer
  if not (provider and type(provider.shouldRender)=="function") then return false end
  local ok,v=pcall(provider.shouldRender,provider,ctx)
  return ok and v==true
end

local function trainerPassiveMaster(ctx)
  -- During command/menu time keep both back-line trainers and both battler
  -- positions readable. Event cinematography is still free to cut tighter.
  -- This also gives high-speed battles a calm visual home instead of returning
  -- to a side-biased idle shot that can crop a human trainer entirely.
  local hasPlayer=trainerVisible(ctx,"player")
  local hasEnemy=trainerVisible(ctx,"enemy")
  if not (hasPlayer or hasEnemy) then return nil end
  local drift=smooth((math.sin(state.idleClock*.20)+1)*.5)
  local shot={eye={65,26,0},focus={0,5.8,0},fov=48,
    travel={-2.2,.45,1.2},focusTravel={0,.08,0}}
  if hasEnemy and not hasPlayer then
    shot.focus={-2.0,5.9,-3.5}
  elseif hasPlayer and not hasEnemy then
    shot.focus={2.0,5.9,3.5}
  end
  return shotPose(shot,drift)
end


local function eventShot(ctx,arena,side,kind,variant)
  side=side or "player"; variant=((variant or 1)-1)%3+1
  local a=arenaPoint(arena,side,6.2); local sgn=side=="player" and 1 or -1
  local z=a[3]
  if kind=="attack" then
    -- Move cinematography must keep the attacking Pokemon readable. The old
    -- trainer/Pokemon midpoint could put the human in the exact centre while
    -- both battlers were outside the crop (visible in the 1.5.40 Flame Wheel
    -- test). Frame the combat line itself; trainer reaction gets its own beat.
    local target=arenaPoint(arena,other(side),6.1)
    local focus={a[1]*.72+target[1]*.28,6.15,a[3]*.72+target[3]*.28}
    if variant==1 then return {eye={56,20,sgn*15},focus=focus,fov=math.rad(45)} end
    if variant==2 then return {eye={-52,19,-sgn*13},focus=focus,fov=math.rad(45)} end
    return {eye={sgn*48,20,-sgn*18},focus=focus,fov=math.rad(46)}
  elseif kind=="damage" then
    -- Center the damaged Pokemon but retain enough of the combat line to show
    -- incoming source particles and the authored hurt animation together.
    local attacker=arenaPoint(arena,other(side),6.1)
    local focus={a[1]*.78+attacker[1]*.22,6.05,a[3]*.78+attacker[3]*.22}
    if variant==1 then return {eye={50,18,z+sgn*7},focus=focus,fov=math.rad(42)} end
    if variant==2 then return {eye={-47,18,z+sgn*8},focus=focus,fov=math.rad(43)} end
    return {eye={54,20,z*.25},focus=focus,fov=math.rad(44)}
  elseif kind=="reaction" then
    -- Reactions belong to the affected side, not to a specific model mod. If a
    -- trainer is actually present, keep the Pokemon as the foreground subject
    -- but include the human response so concern/brace/frustration can read.
    local hasTrainer=trainerVisible(ctx,side)
    local tp=hasTrainer and trainerPoint(side,7.0) or a
    local midx=hasTrainer and (a[1]*.68+tp[1]*.32) or a[1]
    local midz=hasTrainer and (a[3]*.68+tp[3]*.32) or a[3]
    if variant==1 then return {eye={30,13,z+sgn*11},focus={midx,6.05,midz},fov=math.rad(hasTrainer and 37 or 34)} end
    if variant==2 then return {eye={-27,14,z+sgn*12},focus={midx,6.1,midz},fov=math.rad(hasTrainer and 37 or 34)} end
    return {eye={sgn*38,16,z*0.42},focus={midx,6.1,midz},fov=math.rad(hasTrainer and 38 or 35)}
  elseif kind=="capture" then
    local target=arenaPoint(arena,"enemy",6.0); local hasTrainer=trainerVisible(ctx,"player")
    local tp=hasTrainer and trainerPoint("player",7.0) or target
    local status
    if PlayerTrainer and type(PlayerTrainer.captureStatus)=="function" then
      local ok,v=pcall(PlayerTrainer.captureStatus,PlayerTrainer,ctx)
      if ok and type(v)=="table" and v.active then status=v end
    end
    local phase=status and status.phase or "charge"
    local u=math.max(0,math.min(1,tonumber(status and status.progress) or 0))
    local liveBall=nil
    if PlayerTrainer and type(PlayerTrainer.captureBallPosition)=="function" then
      local ok,v=pcall(PlayerTrainer.captureBallPosition,PlayerTrainer,ctx)
      if ok and type(v)=="table" and tonumber(v[1]) and tonumber(v[2]) and tonumber(v[3]) then liveBall=v end
    end

    -- Build every capture shot from the live trainer->enemy battle axis so the
    -- sequence keeps the same Colosseum screen direction in every arena.
    local dx,dz=target[1]-tp[1],target[3]-tp[3]
    local len=math.max(.001,math.sqrt(dx*dx+dz*dz));local fx,fz=dx/len,dz/len
    local rx,rz=-fz,fx
    local function eyeAt(point,back,side,y)
      return {point[1]-fx*back+rx*side,y,point[3]-fz*back+rz*side}
    end
    local function focusAt(point,y)
      return {point[1],y,point[3]}
    end

    -- Reference order: source hand/ball hold -> tracked side throw -> target
    -- impact/absorb -> tracked fall -> low resting/shake shot -> result. The
    -- live source prop is the focus whenever available, so camera and ball can
    -- no longer disagree about where the throw actually is.
    local ball=liveBall or target
    if phase=="charge" then
      -- Medium over-shoulder rather than an extreme body-centred close-up. This
      -- keeps the authentic small ball readable in the throwing hand.
      return {eye=eyeAt(tp,5.9,7.8,8.4),focus={ball[1],ball[2]+.05,ball[3]},fov=math.rad(31)}
    elseif phase=="throw" then
      local lead={ball[1]+fx*2.0,ball[2]-.12,ball[3]+fz*2.0}
      return {eye=eyeAt(ball,5.8,10.8-u*2.4,8.8-u*.8),focus=lead,fov=math.rad(33)}
    elseif phase=="impact" then
      return {eye=eyeAt(target,13.2,-8.0,8.7),focus={ball[1],ball[2],ball[3]},fov=math.rad(29)}
    elseif phase=="absorb" then
      return {eye=eyeAt(target,11.8,-6.8,7.8),focus={ball[1],ball[2]-.10,ball[3]},fov=math.rad(28)}
    elseif phase=="fall" then
      return {eye=eyeAt(ball,8.6,7.0,5.0),focus={ball[1],ball[2]-.18,ball[3]},fov=math.rad(27)}
    elseif phase=="settle" then
      return {eye=eyeAt(ball,7.4,6.3,3.25),focus={ball[1],ball[2]+.06,ball[3]},fov=math.rad(25)}
    elseif phase=="shake" then
      -- Lock the lens to the LANDING POINT, not to the moving ball. 1.5.61
      -- tracked the ball's lateral wobble with the camera, visually cancelling
      -- the shake. The real source prop now rocks inside a stationary low shot,
      -- so every engine-authored shake count is unmistakable.
      local ground={target[1],.31,target[3]}
      return {eye=eyeAt(ground,5.35,4.55,2.42),focus={ground[1],ground[2]+.08,ground[3]},fov=math.rad(22)}
    elseif phase=="caught" then
      return {eye=eyeAt(ball,7.4,5.8,3.7),focus={ball[1],ball[2]+.04,ball[3]},fov=math.rad(26)}
    elseif phase=="breakout" then
      -- Give the native miss/open prop its own ground beat, then let the frame
      -- travel back up to the re-forming target instead of snapping immediately
      -- from ball to Pokemon.
      local ground={target[1],.31,target[3]}
      if u<.42 then
        return {eye=eyeAt(ground,7.2,5.8,3.15),focus={ground[1],ground[2]+.18,ground[3]},fov=math.rad(26)}
      end
      local q=smooth((u-.42)/.58)
      local focus={ground[1]+(target[1]-ground[1])*q,.55+(5.15-.55)*q,ground[3]+(target[3]-ground[3])*q}
      return {eye=eyeAt(target,10.6,-7.1,6.9),focus=focus,fov=math.rad(29)}
    end
    return {eye=eyeAt(target,12,8,8),focus=focusAt(target,4),fov=math.rad(30)}
  elseif kind=="faint" then
    -- Human reaction is part of the KO, not background dressing. Bias the
    -- composition toward the trainer while retaining the fallen Pokemon in the
    -- foreground, and stay close enough for the arms-up silhouette to read.
    local hasTrainer=trainerVisible(ctx,side)
    local tp=hasTrainer and trainerPoint(side,6.9) or a
    local focusBias=hasTrainer and .62 or 0
    local midx=tp[1]*focusBias+a[1]*(1-focusBias)
    local midz=tp[3]*focusBias+a[3]*(1-focusBias)
    if variant==1 then return {eye={-sgn*(hasTrainer and 28 or 36),15,sgn*8},focus={midx,6.15,midz},fov=math.rad(hasTrainer and 37 or 41)} end
    if variant==2 then return {eye={sgn*(hasTrainer and 25 or 34),15,sgn*10},focus={midx,6.0,midz},fov=math.rad(hasTrainer and 38 or 41)} end
    return {eye={-sgn*(hasTrainer and 21 or 38),18,sgn*5},focus={midx,6.0,midz},fov=math.rad(hasTrainer and 39 or 42)}
  elseif kind=="switch" then
    local hasTrainer=trainerVisible(ctx,side)
    local tp=hasTrainer and trainerPoint(side,7.0) or a
    local midx=hasTrainer and (tp[1]+a[1])*.5 or a[1]
    local midz=hasTrainer and (tp[3]+a[3])*.5 or a[3]
    if variant==1 then return {eye={-sgn*(hasTrainer and 33 or 39),16,sgn*8},focus={midx,6.2,midz},fov=math.rad(hasTrainer and 40 or 44)} end
    if variant==2 then return {eye={sgn*(hasTrainer and 30 or 38),16,sgn*11},focus={midx,6.3,midz},fov=math.rad(hasTrainer and 40 or 44)} end
    return {eye={-sgn*(hasTrainer and 25 or 40),14,sgn*4},focus={midx,5.9,midz},fov=math.rad(hasTrainer and 41 or 45)}
  end
  return {eye={46,20,z+sgn*8},focus={a[1],6,z},fov=math.rad(37)}
end

local function introShot(ctx)
  local hasEnemy=Trainer and Trainer.shouldRender and Trainer:shouldRender(ctx)
  local hasPlayer=PlayerTrainer and PlayerTrainer.shouldRender and PlayerTrainer:shouldRender(ctx)
  local establish={eye={56,30,24},focus={0,5.4,-1},fov=math.rad(43)}
  local et=trainerPoint("enemy",6.6); local pt=trainerPoint("player",6.6)
  local enemy=hasEnemy and {eye={31,17.5,et[3]-12.5},focus={et[1]*0.66,6.2,et[3]+5.4},fov=math.rad(39)}
                         or {eye={-43,20,-24},focus={0,6,-8},fov=math.rad(39)}
  local player=hasPlayer and {eye={-31,17.5,pt[3]+12.5},focus={pt[1]*0.66,6.2,pt[3]-5.4},fov=math.rad(39)}
                           or {eye={45,20,24},focus={0,6,8},fov=math.rad(39)}
  local battle={eye={58,21,2},focus={0,6,0},fov=math.rad(38)}
  local t=state.phaseAge
  if t<0.78 then
    local drift={eye={54,29,22},focus={0,5.7,-1},fov=math.rad(42)}
    return mix(establish,drift,t/0.78)
  elseif t<1.48 then
    return mix({eye={54,29,22},focus={0,5.7,-1},fov=math.rad(42)},enemy,(t-0.78)/0.70)
  elseif t<1.98 then
    return enemy
  elseif t<2.72 then
    return mix(enemy,player,(t-1.98)/0.74)
  elseif t<3.18 then
    return player
  elseif t<3.92 then
    return mix(player,battle,(t-3.18)/0.74)
  end
  return battle
end

local function exitShot(ctx,arena,result)
  result=tostring(result or ""):lower()
  local player=arenaPoint(arena,"player",6.2); local enemy=arenaPoint(arena,"enemy",6.2)
  if result=="lose" or result=="loss" or result=="defeat" then
    local hasTrainer=trainerVisible(ctx,"enemy")
    if not hasTrainer then
      -- Wild/externally-presented opponents have no human victory anchor. Use
      -- a broad result master that keeps winner + fallen player readable
      -- instead of manufacturing a phantom trainer close-up.
      return {eye={46,19,-28},focus={(player[1]+enemy[1])*.5,5.9,(player[3]+enemy[3])*.5},fov=math.rad(45)}
    end
    local tp=trainerPoint("enemy",7.0)
    return {eye={38,19,-32},focus={(tp[1]+enemy[1])*.5,6.2,(tp[3]+enemy[3])*.5},fov=math.rad(40)}
  elseif result=="run" or result=="escape" then
    return {eye={55,25,18},focus={player[1],5.8,player[3]-5},fov=math.rad(42)}
  elseif result=="caught" or result=="capture" or result=="captured" then
    return {eye={42,20,18},focus={enemy[1],5.9,enemy[3]},fov=math.rad(40)}
  end
  local hasTrainer=trainerVisible(ctx,"player")
  if not hasTrainer then
    return {eye={-46,19,28},focus={(player[1]+enemy[1])*.5,5.9,(player[3]+enemy[3])*.5},fov=math.rad(45)}
  end
  local tp=trainerPoint("player",7.0)
  return {eye={-38,19,32},focus={(tp[1]+player[1])*.5,6.2,(tp[3]+player[3])*.5},fov=math.rad(40)}
end

local function targetFor(ctx,phase,base,arena)
  if state.manual then return manualPose() end
  local side=state.eventSide
  local pose
  local speed=battleSpeed(ctx)
  if phase=="attack" then pose=eventShot(ctx,arena,side or "player","attack",state.eventIndex)
  elseif phase=="damage" then pose=eventShot(ctx,arena,side or "enemy","damage",state.eventIndex)
  elseif phase=="reaction" then pose=eventShot(ctx,arena,side or "enemy","reaction",state.eventIndex)
  elseif phase=="capture" then pose=eventShot(ctx,arena,"enemy","capture",state.eventIndex)
  elseif phase=="faint" then pose=eventShot(ctx,arena,side or "enemy","faint",state.eventIndex)
  elseif phase=="intro" then pose=introShot(ctx)
  elseif phase=="exit" then pose=exitShot(ctx,arena,state.eventResult)
  elseif phase=="switch" or (state.special=="switch" and state.time<state.specialUntil) then
    pose=eventShot(ctx,arena,side or "player","switch",state.eventIndex)
  else
    pose=trainerPassiveMaster(ctx) or passiveShot(arena)
  end
  return widenAuthored(arenaFrame(pose,arena))
end

local function touchManual()
  if not state.manual then
    state.manual=true;state.startPose=copyPose(state.lastPose);state.phaseAge=0
  end
  state.manualIdle=0;state.returning=false
end
local function releaseManual()
  if not state.manual then return end
  state.manual=false;state.manualIdle=0;state.startPose=copyPose(state.lastPose);state.phaseAge=0;state.returning=true
  state.mouseX=nil;state.mouseY=nil
end
local function updateMouse()
  if not (love and love.mouse and love.mouse.getPosition) then state.mouseX=nil;state.mouseY=nil;return false end
  local x,y=love.mouse.getPosition()
  if state.mouseX==nil then state.mouseX=x;state.mouseY=y;return false end
  local dx,dy=x-state.mouseX,y-state.mouseY;state.mouseX,state.mouseY=x,y
  if dx==0 and dy==0 then return false end
  local dragging=mouseDown(1) or mouseDown(2) or mouseDown(3)
  if not dragging then return false end
  touchManual()
  if mouseDown(1) then
    state.orbit=state.orbit-dx*0.0075;state.elevation=state.elevation-dy*0.0058
  elseif mouseDown(2) then
    if isDown("lshift") or isDown("rshift") then state.fov=state.fov+dy*0.12 else state.radius=state.radius+dy*0.28 end
  elseif mouseDown(3) then
    local pan=state.radius*0.0025;local rx,rz=math.cos(state.orbit),-math.sin(state.orbit);local fx,fz=math.sin(state.orbit),math.cos(state.orbit)
    state.focus[1]=state.focus[1]-dx*pan*rx+dy*pan*0.18*fx;state.focus[3]=state.focus[3]-dx*pan*rz+dy*pan*0.18*fz;state.focus[2]=state.focus[2]+dy*0.025
  end
  return true
end
local function keyboardCameraActive()
  return isDown("j") or isDown("l") or isDown("i") or isDown("k") or isDown("u") or isDown("o") or isDown("n") or isDown("m")
end
local function clampManual()
  state.elevation=clamp(state.elevation,0.08,1.16);state.radius=clamp(state.radius,26,135);state.fov=clamp(state.fov,22,74)
  state.focus[1]=clamp(state.focus[1],-42,42);state.focus[2]=clamp(state.focus[2],1.5,22);state.focus[3]=clamp(state.focus[3],-42,42)
end

local function requestedPhase(name,ctx)
  if name=="battle.move_used" or name=="battle.presentation_move" then return "attack" end
  if name=="battle.damage_dealt" or name=="battle.presentation_damage" then return "damage" end
  if name=="battle.status_inflicted" then return "reaction" end
  if name=="battle.ball_thrown" then return "capture" end
  if name=="battle.exp_gained" then return nil end
  if name=="battle.fainted" or name=="battle.presentation_faint" then return "faint" end
  if name=="battle.battler_switched" then return "switch" end
  if name=="battle.turn_started" or name=="battle.turn_ended" then return "passive" end
  if name=="battle.ended" then return "exit" end
  local p=ctx and ctx.phase
  if p=="intro" or p=="command" or p=="passive" or p=="exit" then return p end
  return state.phase
end

local function eventSideFor(ctx,name,payload)
  -- Shot ownership is explicit in v8:
  --   move_used -> actor, damage/faint -> affected battler, switch -> switched side.
  -- Damage payloads are not guaranteed to expose `user`; resolving the target
  -- first avoids the old fallback that occasionally cut to the attacker's side.
  if name=="battle.move_used" or name=="battle.presentation_move" then
    return sideFrom(ctx,payload,{"user","attacker","source","battler","side"})
  elseif name=="battle.damage_dealt" or name=="battle.presentation_damage" then
    local target=sideFrom(ctx,payload,{"target","defender","targetSide","defenderSide","battler"})
    if target then return target end
    local actor=sideFrom(ctx,payload,{"user","attacker","source","side"})
    return actor and other(actor) or nil
  elseif name=="battle.status_inflicted" then
    return sideFrom(ctx,payload,{"target","battler","side","targetSide","source"})
  elseif name=="battle.ball_thrown" then
    return "enemy"
  elseif name=="battle.fainted" or name=="battle.presentation_faint" then
    return sideFrom(ctx,payload,{"battler","target","side","faintedSide","targetSide"})
  elseif name=="battle.battler_switched" then
    return sideFrom(ctx,payload,{"side","battler","target","switchedSide"})
  end
  return sideFrom(ctx,payload)
end

local function acceptEvent(ev)
  if not ev then return end
  state.startPose=copyPose(state.lastPose)
  state.phase=ev.phase or state.phase
  state.phaseAge=0
  if ev.side then state.eventSide=ev.side end
  if ev.indexed then state.eventIndex=state.eventIndex+1 end
  state.lastCutTime=state.time
  state.lastEventName=ev.name
  local speed=battleSpeed(ev.ctx)
  state.logicSpeed=speed
  state.shotLockUntil=state.time+(EVENT_HOLDS[state.phase] or 0.55)*holdScale(speed)
  if state.phase=="switch" then
    state.special="switch";state.specialUntil=state.shotLockUntil
  end
end

local function queueEvent(ev)
  local nextPriority=EVENT_PRIORITY[ev.phase] or 0
  local age=state.time-state.lastCutTime

  -- Treat one move as an authored three-beat sequence instead of a generic
  -- priority queue: command/attack -> impact -> KO. Damage is the best timing
  -- signal we receive for impact, so it is allowed to take ownership as soon
  -- as the attack shot has actually registered on screen. A faint can then
  -- take ownership after the impact has had a short readable beat.
  local impactBeat = ev.phase=="damage" and state.phase=="attack" and age>=0.42
  local hardEnd = ev.phase=="exit" and age>=MIN_INTERRUPT_AGE
  if impactBeat or hardEnd then
    acceptEvent(ev)
    state.pendingEvent=nil
    return
  end

  local pending=state.pendingEvent
  if not pending or nextPriority>(EVENT_PRIORITY[pending.phase] or 0)
      or (nextPriority==(EVENT_PRIORITY[pending.phase] or 0) and ev.phase~="passive") then
    state.pendingEvent=ev
  end
end

function C:begin(ctx)
  state.time=0;state.idleClock=0;state.phaseAge=0;state.phase="intro";state.eventSide=nil;state.eventIndex=0;state.eventResult=nil;state.resultPending=nil;state.resultAt=0
  state.lastPose=nil;state.startPose=nil;state.special=nil;state.specialUntil=0
  state.shotLockUntil=0;state.pendingEvent=nil;state.lastCutTime=-999;state.lastEventName=nil;state.logicSpeed=battleSpeed(ctx)
  state.shotOffset=battleHash(ctx)%#PASSIVE_SHOTS
  state.manual=false;state.manualLocked=false;state.manualIdle=0;state.returning=false;resetManual()
end
function C:update(ctx,dt)
  dt=tonumber(dt) or 0
  local speed=battleSpeed(ctx)
  state.logicSpeed=speed
  -- Follow game-time exactly. 4X/10X fast-forward therefore accelerates the
  -- same choreography instead of changing which shots exist.
  local cameraDt=dt
  state.time=state.time+cameraDt
  state.phaseAge=state.phaseAge+cameraDt

  -- Win/loss/run/capture is committed on BattleState.result BEFORE the battle
  -- screen tears down and before battle.ended is emitted. Observe that native
  -- result directly so the final composition is visible while victory/blackout
  -- text is still on screen. This is intentionally engine-state driven: no
  -- model, animation or companion mod has to tell CBE that the battle ended.
  local b=battleOf(ctx)
  local result=b and b.result
  if result~=nil then result=tostring(result):lower() end
  if result and result~="" and result~=state.eventResult and result~=state.resultPending then
    state.resultPending=result
    local faintInFlight=state.phase=="faint"
      or (state.pendingEvent and state.pendingEvent.phase=="faint")
    -- Let the actual KO read before moving to the victory/defeat master. Runs
    -- and captures have no faint beat and can transition much sooner.
    local resultDelay=faintInFlight and 1.35 or 0.22
    if faintInFlight and BattleDirector and type(BattleDirector.faintDuration)=="function" then
      local side=(state.pendingEvent and state.pendingEvent.phase=="faint" and state.pendingEvent.side) or state.eventSide
      local ok,fd=pcall(BattleDirector.faintDuration,BattleDirector,ctx,side)
      if ok and tonumber(fd) then
        -- Never abandon an authored faint clip for the victory/defeat master.
        -- The short removal tail is part of Actor:terminalDuration(), so this
        -- cut lands only after the complete source collapse has actually read.
        resultDelay=math.max(resultDelay,tonumber(fd)+.10)
      end
    end
    -- Result delay is authored in game-time, so fast-forward naturally
    -- compresses it in wall-clock time without changing the battle direction.
    state.resultAt=state.time+resultDelay
  end
  -- The authored opening is a presentation-time sequence, not a battle-state
  -- phase. Gen1Recomp can remain in intro/messages until the user dismisses
  -- text, so waiting for turn_started leaves the camera parked forever on the
  -- final intro angle. Hand control to the passive/menu master once the opening
  -- has actually played; fast-forward advances this same sequence in game-time.
  if state.phase=="intro" and state.phaseAge>=4.20 then
    state.startPose=copyPose(state.lastPose)
    state.phase="passive";state.phaseAge=0;state.idleClock=0
    state.lastCutTime=state.time;state.lastEventName="intro.complete";state.shotLockUntil=0
  end
  if state.phase=="passive" or state.phase=="command" then state.idleClock=state.idleClock+cameraDt end
  if state.special and state.time>=state.specialUntil then state.special=nil end
  local captureStillActive=false
  if state.phase=="capture" and PlayerTrainer and type(PlayerTrainer.captureStatus)=="function" then
    local okCapture,captureStatus=pcall(PlayerTrainer.captureStatus,PlayerTrainer,ctx)
    captureStillActive=okCapture and type(captureStatus)=="table" and captureStatus.active==true
  end
  local pendingBlockedByCapture=captureStillActive and state.pendingEvent
    and (EVENT_PRIORITY[state.pendingEvent.phase] or 0)<EVENT_PRIORITY.capture
  if state.pendingEvent and not pendingBlockedByCapture and state.time>=state.shotLockUntil and state.time>=(state.pendingEvent.notBefore or 0) then
    local ev=state.pendingEvent;state.pendingEvent=nil;acceptEvent(ev)
  elseif not captureStillActive and not state.pendingEvent and state.time>=state.shotLockUntil and state.shotLockUntil>0
      and (state.phase=="attack" or state.phase=="damage" or state.phase=="reaction" or state.phase=="capture" or state.phase=="faint" or state.phase=="switch") then
    -- One-shot cinematic beats must relinquish the camera. Older builds left
    -- the director permanently parked on the last damaged/fainted Pokemon
    -- until another semantic event happened. Return to the authored passive
    -- orbit immediately after the readable hold.
    state.startPose=copyPose(state.lastPose)
    state.phase="passive";state.phaseAge=0;state.idleClock=0
    state.lastCutTime=state.time;state.lastEventName="auto.return";state.shotLockUntil=0
  end
  if state.resultPending and state.time>=state.resultAt then
    local committed=state.resultPending
    state.resultPending=nil;state.eventResult=committed
    state.pendingEvent=nil
    acceptEvent({name="battle.result",phase="exit",side=nil,indexed=false,ctx=ctx})
  end
  if pressed("f8") then
    state.manualLocked=not state.manualLocked
    if state.manualLocked then touchManual() else releaseManual() end
    state.mouseX=nil;state.mouseY=nil
  end
  if pressed("home") then resetManual() end
  local mouseMoved=updateMouse();local keyboardActive=keyboardCameraActive();if keyboardActive then touchManual() end
  if state.manual then
    local turn=1.35*cameraDt;local lift=0.90*cameraDt;local zoom=44*cameraDt;local lens=32*cameraDt
    if isDown("j") then state.orbit=state.orbit-turn end;if isDown("l") then state.orbit=state.orbit+turn end
    if isDown("i") then state.elevation=state.elevation+lift end;if isDown("k") then state.elevation=state.elevation-lift end
    if isDown("u") then state.radius=state.radius-zoom end;if isDown("o") then state.radius=state.radius+zoom end
    if isDown("n") then state.fov=state.fov-lens end;if isDown("m") then state.fov=state.fov+lens end
    clampManual()
    if state.manualLocked or mouseMoved or keyboardActive or mouseDown(1) or mouseDown(2) or mouseDown(3) then
      state.manualIdle=0
    else
      state.manualIdle=state.manualIdle+cameraDt;if state.manualIdle>=MANUAL_RELEASE_DELAY then releaseManual() end
    end
  end
end
function C:event(ctx,name,payload)
  -- move_used and damage_dealt are separate cinematic beats. Earlier builds
  -- discarded rapid damage events entirely, which is why some impacts never
  -- received a camera cut. The scheduler now preserves the impact and simply
  -- delays it until the attack shot has been readable.
  -- Gen 2 resolves its model before replaying the screen queue. Ignore that
  -- early semantic move event and cut only when StandaloneHost reports the
  -- corresponding visible queue row. Gen 1 keeps its native move boundary.
  local gen2=ctx and ctx.battle and ctx.battle.__cbeGeneration==2
  local queueSync=gen2 and ctx.battle.__cbePresentationQueueSync==true
  if queueSync and (name=="battle.move_used" or name=="battle.damage_dealt" or name=="battle.fainted") then return end
  local phase=requestedPhase(name,ctx)
  if not phase then return end
  local speed=battleSpeed(ctx)
  state.logicSpeed=speed
  if name=="battle.ended" and type(payload)=="table" then state.eventResult=payload.result or payload.outcome end
  -- Fast-forward can deliver several semantic beats between rendered frames,
  -- but they still belong to the same authored sequence. The scheduler below
  -- coalesces genuinely superseded events; speed itself never deletes a shot.
  if not phaseAllowedAtSpeed(phase,speed) then return end
  local indexed=name=="battle.move_used" or name=="battle.presentation_move" or name=="battle.damage_dealt" or name=="battle.presentation_damage"
    or name=="battle.status_inflicted" or name=="battle.ball_thrown"
    or name=="battle.fainted" or name=="battle.presentation_faint" or name=="battle.battler_switched"
  local ev={name=name,phase=phase,side=eventSideFor(ctx,name,payload),indexed=indexed,ctx=ctx}
  -- Gen1Recomp emits the faint semantic state before the complete visual fall
  -- has necessarily finished. Hold the impact composition briefly, then move
  -- to the trainer reaction instead of cutting on move selection / early KO.
  if phase=="faint" then
    local delay=.32
    if BattleDirector and type(BattleDirector.faintDuration)=="function" and ev.side then
      local ok,fd=pcall(BattleDirector.faintDuration,BattleDirector,ctx,ev.side)
      if ok and tonumber(fd) then delay=math.max(.14,math.min(.48,tonumber(fd)*.14)) end
    end
    ev.notBefore=state.time+delay
  end

  -- Intro owns its authored sequence until actual battle events begin.
  -- After that, inputs merely advancing text/menus cannot reset the camera:
  -- only semantic battle events enter this scheduler.
  if state.time<state.shotLockUntil or (ev.notBefore and state.time<ev.notBefore) then
    queueEvent(ev)
  else
    acceptEvent(ev)
  end

  -- A major hit gets one human reaction beat after the impact. This is derived
  -- only from authoritative battle damage/max-HP data; external animation mods
  -- never need to expose their own notions of recoil or expression.
  if (name=="battle.damage_dealt" or name=="battle.presentation_damage") and ev.side and trainerVisible(ctx,ev.side) and type(payload)=="table" then
    local damage=tonumber(payload.damage or payload.amount or payload.hpDamage) or 0
    local target=payload.target or payload.defender or payload.battler
    local mon=type(target)=="table" and (target.mon or target) or nil
    local maxHp=mon and (tonumber(mon.maxHp) or tonumber(mon.maxHP) or (mon.stats and tonumber(mon.stats.hp))) or nil
    if damage>0 and maxHp and maxHp>0 and damage/maxHp>=0.24 then
      local reaction={name="battle.major_damage_reaction",phase="reaction",side=ev.side,indexed=false,notBefore=state.time+0.56,ctx=ctx}
      local pending=state.pendingEvent
      if not pending or (EVENT_PRIORITY[pending.phase] or 0)<=(EVENT_PRIORITY.reaction or 0) then state.pendingEvent=reaction end
    end
  end
end
function C:claim(ctx,phase)
  return phase=="passive" or phase=="intro" or phase=="command" or phase=="attack" or phase=="damage" or phase=="reaction" or phase=="capture" or phase=="faint" or phase=="switch" or phase=="exit"
end
function C:shot(ctx,phase,progress,base,arena)
  -- `phase` is the host's latest queue phase, not an instruction to cut.
  -- The event scheduler above is the sole owner of automatic shot changes.
  local activePhase=state.phase
  local target=targetFor(ctx,activePhase,base,arena);local pose
  -- WazaSequence camera entries outrank the semantic CBE camera once their
  -- source parameter curves are decoded. The handler currently preserves the
  -- exact entry and returns nil rather than guessing a pose; this seam means the
  -- future decoder does not require another camera architecture rewrite.
  local wh=V and V.WazaHandlers
  local sourceBlend=nil
  if wh and type(wh.cameraPose)=="function" and not state.manual and (activePhase=="attack" or activePhase=="damage") then
    local ok,sourcePose=pcall(wh.cameraPose,ctx)
    if ok and type(sourcePose)=="table" and sourcePose.eye and sourcePose.focus and sourcePose.fov then
      target=sourcePose
      sourceBlend=tonumber(sourcePose.blend)
    end
  end
  if state.manual then
    if state.phaseAge<0.24 and state.startPose then pose=mix(state.startPose,target,state.phaseAge/0.24) else pose=target end
  elseif state.returning then
    pose=mix(state.startPose or base,target,state.phaseAge/AUTO_RETURN_BLEND);if state.phaseAge>=AUTO_RETURN_BLEND then state.returning=false end
  elseif activePhase=="intro" then
    pose=mix(state.startPose or base,target,state.phaseAge/0.34)
  elseif activePhase=="passive" or activePhase=="command" then
    if state.startPose and state.phaseAge<0.72 then pose=mix(state.startPose,target,state.phaseAge/0.72) else pose=target end
  else
    -- Source Waza cameras are already moving on the decoded 60 Hz effect clock;
    -- use their shorter blend request so the semantic camera cannot spend most
    -- of a fast move easing toward an angle the effect has already left.
    local blend=sourceBlend or 0.38
    pose=mix(state.startPose or base,target,state.phaseAge/math.max(.04,blend))
  end
  state.lastPose=copyPose(pose);return pose,nil
end
function C:finish(ctx,reason)
  state.lastPose=nil;state.startPose=nil;state.mouseX=nil;state.mouseY=nil;state.special=nil
  state.pendingEvent=nil;state.resultPending=nil;state.resultAt=0;state.shotLockUntil=0;state.lastCutTime=-999;state.lastEventName=nil
  state.manual=false;state.manualLocked=false;state.manualIdle=0;state.returning=false
end
function C:status()
  return {manual=state.manual,manualLocked=state.manualLocked,manualIdle=state.manualIdle,radius=state.radius,elevation=state.elevation,fov=state.fov,focus=copy3(state.focus),idleShots=#PASSIVE_SHOTS,director="colosseum-semantic-director-v9-waza-source-geometry",shotOffset=state.shotOffset,eventIndex=state.eventIndex,authoredZoomOut=AUTHORED_ZOOM_OUT,phase=state.phase,eventSide=state.eventSide,shotLockRemaining=math.max(0,state.shotLockUntil-state.time),pendingEvent=state.pendingEvent and state.pendingEvent.phase or nil,lastEvent=state.lastEventName,eventResult=state.eventResult,resultPending=state.resultPending,logicSpeed=state.logicSpeed,clock="game-time-from-fixed-step",highSpeedMaster=false}
end
return C
