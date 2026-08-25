local V = ...
local Trainer = V and V.Trainer
local PlayerTrainer = V and V.PlayerTrainer
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

-- Gen1Recomp fast-forward runs the fixed logic step multiple times per real
-- frame. Camera movement must NOT inherit that multiplier: otherwise 4X/10X
-- battle speed also means 4X/10X cuts, blends and manual camera movement.
-- We keep battle semantics accelerated, but run the director on a real-time
-- clock and progressively reduce low-value cuts at the highest speed levels.
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
  speed=tonumber(speed) or 1
  if speed>=10 then return 1.45 end
  if speed>=4 then return 1.28 end
  if speed>=3 then return 1.18 end
  if speed>=2 then return 1.08 end
  return 1
end

local function phaseAllowedAtSpeed(phase,speed)
  speed=tonumber(speed) or 1
  if speed>=10 then
    return phase=="capture" or phase=="switch" or phase=="faint" or phase=="exit"
  end
  if speed>=2 then
    return phase=="attack" or phase=="capture" or phase=="switch"
      or phase=="faint" or phase=="exit"
  end
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

-- Fast-forward should accelerate the battle, not turn the viewer around the
-- arena once per queued event. Above 1X keep one screen direction and express
-- semantics with restrained focus/lens changes. The battle still reacts to
-- attacks, switches and KOs, but never whip-pans between opposite hemispheres.
local function speedMasterShot(ctx,arena,phase,side,speed)
  local center={0,5.9,0}
  local subject=arenaPoint(arena,side or "enemy",6.1)
  local bias=speed>=6 and .12 or (speed>=4 and .18 or .28)
  if phase=="passive" or phase=="command" then bias=0 end
  local focus={center[1]+(subject[1]-center[1])*bias,
    center[2]+(subject[2]-center[2])*bias,
    center[3]+(subject[3]-center[3])*bias}
  local eye={58,22.5,7.5}
  local fov=43
  if speed>=6 then eye={63,25,5};fov=46
  elseif speed>=4 then eye={61,24,6};fov=45 end
  if phase=="faint" then
    focus[1]=center[1]+(subject[1]-center[1])*(speed>=4 and .22 or .36)
    focus[3]=center[3]+(subject[3]-center[3])*(speed>=4 and .22 or .36)
    fov=fov-1
  elseif phase=="switch" or phase=="capture" then
    fov=fov-0.6
  end
  -- One small dolly breath keeps the camera alive without producing yaw.
  local breath=math.sin(state.time*.55)*.45
  eye[1]=eye[1]+breath
  eye[2]=eye[2]+breath*.12
  return {eye=eye,focus=focus,fov=math.rad(fov)}
end

local function eventShot(ctx,arena,side,kind,variant)
  side=side or "player"; variant=((variant or 1)-1)%3+1
  local a=arenaPoint(arena,side,6.2); local sgn=side=="player" and 1 or -1
  local z=a[3]
  if kind=="attack" then
    -- Two of the three attack variants deliberately preserve trainer + Pokemon
    -- in one composition so a command gesture is visible during normal play.
    -- This adds performance value without increasing cut frequency.
    local hasTrainer=trainerVisible(ctx,side)
    local tp=hasTrainer and trainerPoint(side,7.0) or a
    local midx=hasTrainer and (tp[1]+a[1])*.5 or a[1]
    local midz=hasTrainer and (tp[3]+a[3])*.5 or a[3]
    if variant==1 then return {eye={-sgn*36,16,sgn*8},focus={midx,6.1,midz},fov=math.rad(hasTrainer and 40 or 42)} end
    if variant==2 then return {eye={-36,16,z+sgn*9},focus={midx,6.2,midz},fov=math.rad(hasTrainer and 39 or 41)} end
    return {eye={sgn*33,17,sgn*10},focus={midx,6.2,midz},fov=math.rad(hasTrainer and 40 or 42)}
  elseif kind=="damage" then
    if variant==1 then return {eye={34,14,z+sgn*10},focus={a[1],6.1,z},fov=math.rad(32)} end
    if variant==2 then return {eye={-30,13,z+sgn*13},focus={a[1],5.9,z},fov=math.rad(33)} end
    return {eye={46,18,z*0.35},focus={a[1],6.0,z},fov=math.rad(35)}
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
    local midx=hasTrainer and (target[1]*.72+tp[1]*.28) or target[1]
    local midz=hasTrainer and (target[3]*.72+tp[3]*.28) or target[3]
    if variant==1 then return {eye={39,18,22},focus={midx,6.1,midz},fov=math.rad(39)} end
    if variant==2 then return {eye={-35,15,18},focus={target[1],6.0,target[3]},fov=math.rad(37)} end
    return {eye={44,21,-5},focus={midx,6.0,midz},fov=math.rad(40)}
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
  if speed>=2 and phase~="intro" and phase~="exit" then
    pose=speedMasterShot(ctx,arena,phase,side,speed)
  elseif phase=="attack" then pose=eventShot(ctx,arena,side or "player","attack",state.eventIndex)
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
  if name=="battle.damage_dealt" then return "damage" end
  if name=="battle.status_inflicted" then return "reaction" end
  if name=="battle.ball_thrown" then return "capture" end
  if name=="battle.exp_gained" then return nil end
  if name=="battle.fainted" then return "faint" end
  if name=="battle.battler_switched" then return "switch" end
  if name=="battle.turn_started" or name=="battle.turn_ended" then return "passive" end
  if name=="battle.ended" then return "exit" end
  local p=ctx and ctx.phase
  if p=="intro" or p=="command" or p=="passive" or p=="exit" then return p end
  return state.phase
end

local function eventSideFor(ctx,name,payload)
  -- Shot ownership is explicit in v7:
  --   move_used -> actor, damage/faint -> affected battler, switch -> switched side.
  -- Damage payloads are not guaranteed to expose `user`; resolving the target
  -- first avoids the old fallback that occasionally cut to the attacker's side.
  if name=="battle.move_used" or name=="battle.presentation_move" then
    return sideFrom(ctx,payload,{"user","attacker","source","battler","side"})
  elseif name=="battle.damage_dealt" then
    local target=sideFrom(ctx,payload,{"target","defender","targetSide","defenderSide","battler"})
    if target then return target end
    local actor=sideFrom(ctx,payload,{"user","attacker","source","side"})
    return actor and other(actor) or nil
  elseif name=="battle.status_inflicted" then
    return sideFrom(ctx,payload,{"target","battler","side","targetSide","source"})
  elseif name=="battle.ball_thrown" then
    return "enemy"
  elseif name=="battle.fainted" then
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
  -- input.step supplies the fixed 1/60 logic step. At NX battle speed the
  -- engine invokes this update N times per real frame, so dividing each step
  -- by N reconstructs the presentation clock without changing battle timing.
  local cameraDt=dt/math.max(1,speed)
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
    -- At accelerated battle speeds the engine may finish several queue rows in
    -- one rendered frame. Keep a brief readable result beat, but do not hold
    -- the camera to a slow-motion schedule after the native battle has moved on.
    if speed>=10 then resultDelay=math.min(resultDelay,0.08)
    elseif speed>=4 then resultDelay=math.min(resultDelay,0.26)
    elseif speed>=3 then resultDelay=math.min(resultDelay,0.42) end
    state.resultAt=state.time+resultDelay
  end
  -- The authored opening is a real-time camera sequence, not a battle-state
  -- phase. Gen1Recomp can remain in intro/messages until the user dismisses
  -- text, so waiting for turn_started leaves the camera parked forever on the
  -- final intro angle. Hand control to the passive/menu master once the opening
  -- has actually played, independent of text speed or fast-forward.
  if state.phase=="intro" and state.phaseAge>=4.20 then
    state.startPose=copyPose(state.lastPose)
    state.phase="passive";state.phaseAge=0;state.idleClock=0
    state.lastCutTime=state.time;state.lastEventName="intro.complete";state.shotLockUntil=0
  end
  if state.phase=="passive" or state.phase=="command" then state.idleClock=state.idleClock+cameraDt end
  if state.special and state.time>=state.specialUntil then state.special=nil end
  if state.pendingEvent and state.time>=state.shotLockUntil and state.time>=(state.pendingEvent.notBefore or 0) then
    local ev=state.pendingEvent;state.pendingEvent=nil;acceptEvent(ev)
  elseif not state.pendingEvent and state.time>=state.shotLockUntil and state.shotLockUntil>0
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
  if name=="battle.move_used" and gen2 then return end
  local phase=requestedPhase(name,ctx)
  if not phase then return end
  local speed=battleSpeed(ctx)
  state.logicSpeed=speed
  if name=="battle.ended" and type(payload)=="table" then state.eventResult=payload.result or payload.outcome end
  -- Fast-forward may deliver an entire move/impact/turn chain between two
  -- renders. Preserve meaningful battle state but deliberately drop low-value
  -- camera cuts as speed rises: 4X becomes one authored cut per move at most;
  -- 10X+ keeps only switches, captures, KOs and the result.
  if not phaseAllowedAtSpeed(phase,speed) then return end
  local indexed=name=="battle.move_used" or name=="battle.presentation_move" or name=="battle.damage_dealt"
    or name=="battle.status_inflicted" or name=="battle.ball_thrown"
    or name=="battle.fainted" or name=="battle.battler_switched"
  local ev={name=name,phase=phase,side=eventSideFor(ctx,name,payload),indexed=indexed,ctx=ctx}
  -- Gen1Recomp emits the faint semantic state before the complete visual fall
  -- has necessarily finished. Hold the impact composition briefly, then move
  -- to the trainer reaction instead of cutting on move selection / early KO.
  if phase=="faint" then ev.notBefore=state.time+0.62 end

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
  if name=="battle.damage_dealt" and ev.side and trainerVisible(ctx,ev.side) and type(payload)=="table" then
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
  if state.manual then
    if state.phaseAge<0.24 and state.startPose then pose=mix(state.startPose,target,state.phaseAge/0.24) else pose=target end
  elseif state.returning then
    pose=mix(state.startPose or base,target,state.phaseAge/AUTO_RETURN_BLEND);if state.phaseAge>=AUTO_RETURN_BLEND then state.returning=false end
  elseif activePhase=="intro" then
    pose=mix(state.startPose or base,target,state.phaseAge/0.34)
  elseif activePhase=="passive" or activePhase=="command" then
    if state.startPose and state.phaseAge<0.72 then pose=mix(state.startPose,target,state.phaseAge/0.72) else pose=target end
  else
    local blend=state.logicSpeed>=4 and 0.62 or (state.logicSpeed>=2 and 0.52 or 0.38)
    pose=mix(state.startPose or base,target,state.phaseAge/blend)
  end
  state.lastPose=copyPose(pose);return pose,nil
end
function C:finish(ctx,reason)
  state.lastPose=nil;state.startPose=nil;state.mouseX=nil;state.mouseY=nil;state.special=nil
  state.pendingEvent=nil;state.resultPending=nil;state.resultAt=0;state.shotLockUntil=0;state.lastCutTime=-999;state.lastEventName=nil
  state.manual=false;state.manualLocked=false;state.manualIdle=0;state.returning=false
end
function C:status()
  return {manual=state.manual,manualLocked=state.manualLocked,manualIdle=state.manualIdle,radius=state.radius,elevation=state.elevation,fov=state.fov,focus=copy3(state.focus),idleShots=#PASSIVE_SHOTS,director="colosseum-semantic-director-v6-visible-boundary-stable-speed-master",shotOffset=state.shotOffset,eventIndex=state.eventIndex,authoredZoomOut=AUTHORED_ZOOM_OUT,phase=state.phase,eventSide=state.eventSide,shotLockRemaining=math.max(0,state.shotLockUntil-state.time),pendingEvent=state.pendingEvent and state.pendingEvent.phase or nil,lastEvent=state.lastEventName,eventResult=state.eventResult,resultPending=state.resultPending,logicSpeed=state.logicSpeed,clock="real-time-from-fixed-step",highSpeedMaster=state.logicSpeed>=2}
end
return C
