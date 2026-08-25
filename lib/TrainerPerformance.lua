local V=...
local A={}

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end

-- Every trainer owns the same semantic performance vocabulary. Profiles only
-- alter personality: tempo, energy, composure, dominant arm, and silhouette.
-- They never remove an action or reduce a trainer to a lower-complexity path.
local BASE={
  label="BALANCED",tempo=1.00,energy=1.00,composure=1.00,lead=1,
  commandTurn=-.052,sendTurn=-.080,openingTurn=.045,lossTurn=.035,victoryTurn=-.045,
  gesture=1.00,reaction=1.00,weight=1.00,idle=1.00,head=1.00,bounce=1.00,
  sourceAuthority=0.00,continuity=1.00,
}
local PROFILES={
  red={label="FOCUSED",sourceAuthority=0,continuity=1.08,tempo=.98,energy=.96,composure=1.04,lead=1,commandTurn=-.064,sendTurn=-.092,openingTurn=.050,lossTurn=.030,victoryTurn=-.050,gesture=.96,reaction=.92,weight=.96,idle=.92,head=.92,bounce=.90},
  leaf={label="POISED",sourceAuthority=0,continuity=1.05,tempo=.94,energy=1.06,composure=.96,lead=-1,commandTurn=.060,sendTurn=.090,openingTurn=-.045,lossTurn=-.038,victoryTurn=.062,gesture=1.04,reaction=.98,weight=1.02,idle=1.04,head=1.12,bounce=1.03},
  wes={label="COOL",sourceAuthority=0,continuity=1.18,tempo=1.05,energy=.92,composure=1.14,lead=1,commandTurn=-.040,sendTurn=-.056,openingTurn=.030,lossTurn=.024,victoryTurn=-.030,gesture=.88,reaction=.84,weight=.95,idle=.82,head=.80,bounce=.78},
  brendan={label="ENERGETIC",sourceAuthority=0,continuity=.96,tempo=.90,energy=1.12,composure=.90,lead=1,commandTurn=-.074,sendTurn=-.106,openingTurn=.058,lossTurn=.042,victoryTurn=-.070,gesture=1.10,reaction=1.03,weight=1.08,idle=1.10,head=1.08,bounce=1.15},
  may={label="UPBEAT",sourceAuthority=0,continuity=.98,tempo=.91,energy=1.10,composure=.92,lead=-1,commandTurn=.072,sendTurn=.102,openingTurn=-.055,lossTurn=-.040,victoryTurn=.070,gesture=1.08,reaction=1.00,weight=1.05,idle=1.10,head=1.14,bounce=1.12},
  cooltrainer_m={label="COMPETITIVE",sourceAuthority=0,continuity=1.02,tempo=.96,energy=1.04,composure=.98,lead=1,commandTurn=-.060,sendTurn=-.086,openingTurn=.046,lossTurn=.036,victoryTurn=-.052,gesture=1.02,reaction=.98,weight=1.04,idle=.98,head=.96,bounce=1.00},
  cooltrainer_f={label="COMPETITIVE",sourceAuthority=0,continuity=1.02,tempo=.95,energy=1.05,composure=.98,lead=-1,commandTurn=.060,sendTurn=.086,openingTurn=-.046,lossTurn=-.036,victoryTurn=.052,gesture=1.03,reaction=.98,weight=1.03,idle=1.00,head=1.04,bounce=1.00},
  dakim={label="POWERFUL",sourceAuthority=0,continuity=1.12,tempo=1.08,energy=1.06,composure=.96,lead=1,commandTurn=-.036,sendTurn=-.054,openingTurn=.052,lossTurn=.044,victoryTurn=-.038,gesture=1.04,reaction=1.04,weight=1.14,idle=.86,head=.78,bounce=.88},
  nascour={label="CONTROLLED",sourceAuthority=0,continuity=1.18,tempo=1.12,energy=.82,composure=1.20,lead=1,commandTurn=-.030,sendTurn=-.050,openingTurn=-.040,lossTurn=-.032,victoryTurn=-.028,gesture=.82,reaction=.78,weight=.90,idle=.68,head=.72,bounce=.62},
  miror_b={label="THEATRICAL",sourceAuthority=0,continuity=.94,tempo=.88,energy=1.22,composure=.82,lead=-1,commandTurn=.078,sendTurn=.106,openingTurn=.074,lossTurn=-.062,victoryTurn=.090,gesture=1.22,reaction=1.12,weight=1.10,idle=1.30,head=1.22,bounce=1.28},
}

local DURATIONS={opening=1.92,throw=1.48,sendout=1.48,command=1.20,brace=1.04,concern=1.22,frustration=2.62,victory=1.78,defeat=2.48}
local PRIORITY={brace=1,concern=2,command=2,opening=3,throw=4,sendout=4,victory=5,defeat=6,frustration=6}

local function cloneProfile(id)
  id=tostring(id or ""):lower()
  if id=="green" then id="leaf" elseif id=="seth" then id="wes" end
  local src=PROFILES[id] or BASE
  local out={}
  for k,v in pairs(BASE) do out[k]=v end
  for k,v in pairs(src) do out[k]=v end
  out.id=id~="" and id or "balanced"
  return out
end
function A.profile(id) return cloneProfile(id) end
function A.sourceAuthority(id) return clamp(tonumber(cloneProfile(id).sourceAuthority) or 0,0,1) end
function A.priority(kind) return PRIORITY[kind] or 0 end
function A.duration(id,kind)
  local p=cloneProfile(id);return (DURATIONS[kind] or 1.2)*(p.tempo or 1)
end

local function battleSpeed(ctx)
  local b=type(ctx)=="table" and (ctx.battle or (ctx.kind and ctx)) or nil
  local game=(b and b.game) or (ctx and ctx.game) or (V and V.mod and V.mod.game)
  local speed
  if game and type(game.logicSpeed)=="function" then local ok,v=pcall(game.logicSpeed,game);if ok then speed=tonumber(v) end end
  if not speed then local o=game and game.save and game.save.options;speed=tonumber(o and (o.speedBattle or o.speed)) or 1 end
  if not speed or speed~=speed or speed<1 then speed=1 end
  return speed
end
function A.realDt(ctx,dt) return (tonumber(dt) or 0)/math.max(1,battleSpeed(ctx)) end
function A.speed(ctx) return battleSpeed(ctx) end

function A.shouldTrigger(ctx,current,currentAge,newKind)
  local speed=battleSpeed(ctx)
  if speed>=10 and (newKind=="command" or newKind=="brace" or newKind=="concern") then return false end
  if speed>=4 and newKind=="brace" then return false end
  if current==newKind and (tonumber(currentAge) or 0)<.44 then return false end
  local cp=A.priority(current);local np=A.priority(newKind)
  if current and cp>np and (tonumber(currentAge) or 0)<.82 then return false end
  if (current=="frustration" or current=="defeat") and (tonumber(currentAge) or 0)<1.55 and np<6 then return false end
  return true
end

local function zero(p)
  return {command=0,brace=0,shift=0,settle=0,look=0,arm=0,lean=0,turn=0,forward=0,bob=0,sway=0,
    idleArm=0,armLead=p.lead or 1,headEnergy=p.head or 1,weightEnergy=p.weight or 1}
end
local function scaleMotion(m,s)
  for k,v in pairs(m) do
    if type(v)=="number" and k~="armLead" and k~="headEnergy" and k~="weightEnergy" then m[k]=v*s end
  end
  return m
end

-- Five-stage performances: anticipation -> action -> readable hold -> follow-through -> recovery.
-- The same phase structure is used by every trainer; profiles only reshape it.
function A.motion(id,kind,t,strength,side)
  local p=cloneProfile(id);local m=zero(p);if not kind then return m end
  local d=A.duration(id,kind);local u=clamp((tonumber(t) or 0)/math.max(.001,d),0,1)
  local e=p.energy or 1;local g=p.gesture or 1;local r=p.reaction or 1;local w=p.weight or 1
  local turnSign=(side=="enemy") and -1 or 1
  local cmdTurn=(p.commandTurn or -.05)*turnSign
  local sendTurn=(p.sendTurn or -.08)*turnSign
  local openTurn=(p.openingTurn or .04)*turnSign
  local lossTurn=(p.lossTurn or .03)*turnSign
  local winTurn=(p.victoryTurn or -.04)*turnSign

  if kind=="opening" then
    if u<.16 then local q=smooth(u/.16);m.shift=.58*w*q;m.turn=openTurn*q;m.lean=-.018*w*q;m.bob=-.010*q
    elseif u<.36 then local q=smooth((u-.16)/.20);m.shift=.58*w*(1-.30*q);m.command=.44*g*q;m.arm=.16*g*q;m.turn=openTurn;m.lean=.022*w*q;m.look=.10*q
    elseif u<.66 then m.shift=.40*w;m.command=.44*g;m.arm=.16*g;m.turn=openTurn;m.lean=.022*w;m.look=.10
    elseif u<.88 then local q=smooth((u-.66)/.22);m.shift=.40*w*(1-q);m.command=.44*g*(1-q);m.arm=.16*g*(1-q);m.settle=.48*q;m.turn=openTurn*(1-q);m.lean=.022*w*(1-q);m.look=.10*(1-q)
    else local q=1-smooth((u-.88)/.12);m.settle=.48*q;m.bob=-.006*q end
  elseif kind=="throw" or kind=="sendout" then
    if u<.16 then local q=smooth(u/.16);m.shift=.72*w*q;m.turn=-sendTurn*.65*q;m.forward=.024*w*q;m.bob=-.018*q;m.lean=-.024*w*q
    elseif u<.31 then local q=smooth((u-.16)/.15);m.shift=.72*w*(1-q);m.command=.44*g*q;m.arm=.56*g*q;m.turn=(-sendTurn*.65)+(sendTurn*1.55)*q;m.forward=.024-.092*w*q;m.bob=-.018+.030*q;m.lean=-.024+.056*w*q
    elseif u<.52 then local q=smooth((u-.31)/.21);m.command=.50*g;m.arm=(.66-.08*q)*g;m.turn=sendTurn*(1+.16*q);m.forward=-.068*w-.024*w*q;m.bob=.012*p.bounce;m.lean=.034*w+.016*w*q;m.look=.07
    elseif u<.76 then local q=smooth((u-.52)/.24);m.arm=(.58*(1-q)+.14*q)*g;m.command=.50*g*(1-q);m.settle=.58*q;m.turn=sendTurn*(1-q);m.forward=-.092*w*(1-q);m.bob=.012*p.bounce*(1-q);m.lean=.050*w*(1-q)-.010*q
    else local q=1-smooth((u-.76)/.24);m.arm=.14*g*q;m.settle=.62*q;m.turn=sendTurn*.28*q;m.forward=-.028*w*q;m.lean=-.010*q end
  elseif kind=="command" then
    if u<.14 then local q=smooth(u/.14);m.shift=.10*w*q;m.command=.70*g*q;m.turn=cmdTurn*q;m.forward=-.046*w*q;m.lean=.034*w*q;m.look=.10*q
    elseif u<.34 then local q=smooth((u-.14)/.20);m.command=(.70+.08*q)*g;m.arm=.12*g*q;m.turn=cmdTurn*(1+.12*q);m.forward=-.046*w;m.lean=.034*w;m.look=.10
    elseif u<.58 then m.command=.78*g;m.arm=.12*g;m.turn=cmdTurn*1.12;m.forward=-.046*w;m.lean=.034*w;m.look=.10
    elseif u<.84 then local q=smooth((u-.58)/.26);m.command=.78*g*(1-q);m.arm=.12*g*(1-q);m.settle=.46*q;m.turn=cmdTurn*1.12*(1-q);m.forward=-.046*w*(1-q);m.lean=.034*w*(1-q)-.010*q;m.look=.10*(1-q)
    else local q=1-smooth((u-.84)/.16);m.settle=.48*q;m.look=.025*q end
  elseif kind=="brace" then
    if u<.10 then local q=smooth(u/.10);m.brace=.72*r*q;m.forward=.016*w*q;m.bob=-.010*r*q;m.lean=-.020*r*q
    elseif u<.30 then local q=smooth((u-.10)/.20);m.brace=(.72+.08*q)*r;m.shift=-.10*w*q;m.forward=.016*w;m.bob=-.010*r;m.lean=-.020*r-.010*r*q;m.look=-.05*q
    elseif u<.52 then m.brace=.80*r;m.shift=-.10*w;m.forward=.016*w;m.bob=-.010*r;m.lean=-.030*r;m.look=-.05
    elseif u<.82 then local q=smooth((u-.52)/.30);m.brace=.80*r*(1-q);m.shift=-.10*w*(1-q);m.settle=.36*q;m.forward=.016*w*(1-q);m.bob=-.010*r*(1-q);m.lean=-.030*r*(1-q);m.look=-.05*(1-q)
    else local q=1-smooth((u-.82)/.18);m.settle=.36*q end
  elseif kind=="concern" then
    if u<.12 then local q=smooth(u/.12);m.brace=.62*r*q;m.forward=-.016*w*q;m.bob=-.012*r*q;m.look=-.08*q
    elseif u<.34 then local q=smooth((u-.12)/.22);m.brace=.62*r*(1-.22*q);m.arm=.24*g*q;m.shift=.18*w*q;m.turn=-lossTurn*.55*q;m.look=-.18*q;m.lean=.022*r*q
    elseif u<.62 then m.brace=.48*r;m.arm=.24*g;m.shift=.18*w;m.turn=-lossTurn*.55;m.look=-.18;m.lean=.022*r
    elseif u<.86 then local q=smooth((u-.62)/.24);m.brace=.48*r*(1-q);m.arm=.24*g*(1-q);m.shift=.18*w*(1-q);m.settle=.38*q;m.turn=-lossTurn*.55*(1-q);m.look=-.18*(1-q);m.lean=.022*r*(1-q)
    else local q=1-smooth((u-.86)/.14);m.settle=.38*q end
  elseif kind=="frustration" or kind=="defeat" then
    local defeat=(kind=="defeat") and 1.10 or 1.0
    if u<.12 then local q=smooth(u/.12);m.brace=.66*r*q;m.forward=.020*w*q;m.bob=-.018*r*q;m.lean=-.026*r*q;m.look=-.06*q
    elseif u<.30 then local q=smooth((u-.12)/.18);m.brace=.66*r*(1-q);m.arm=.48*g*defeat*q;m.shift=.28*w*q;m.turn=lossTurn*q;m.forward=.020*w*(1-q);m.bob=-.018*r*(1-q);m.lean=-.026*r+.064*r*q;m.look=-.17*q
    elseif u<.58 then m.arm=.48*g*defeat;m.shift=.28*w;m.turn=lossTurn;m.lean=.038*r*defeat;m.look=-.18*defeat
    elseif u<.84 then local q=smooth((u-.58)/.26);m.arm=.48*g*defeat*(1-q);m.shift=.28*w*(1-q);m.settle=.52*q;m.turn=lossTurn*(1-q);m.bob=-.012*q;m.lean=.038*r*defeat*(1-q)-.014*defeat*q;m.look=-.18*defeat*(1-q)
    else local q=1-smooth((u-.84)/.16);m.settle=.52*q;m.bob=-.009*q;m.lean=-.012*defeat*q end
  elseif kind=="victory" then
    if u<.16 then local q=smooth(u/.16);m.shift=-.16*w*q;m.command=.30*g*q;m.turn=winTurn*q;m.bob=-.006*q
    elseif u<.36 then local q=smooth((u-.16)/.20);m.command=(.30+.36*q)*g;m.arm=.30*g*q;m.shift=-.16*w*(1-q);m.turn=winTurn*(1+.18*q);m.forward=-.022*w*q;m.lean=.026*w*q;m.look=.12*q;m.bob=.012*p.bounce*q
    elseif u<.64 then m.command=.66*g;m.arm=.30*g;m.turn=winTurn*1.18;m.forward=-.022*w;m.lean=.026*w;m.look=.12;m.bob=.012*p.bounce*math.sin(u*math.pi*3.0)
    elseif u<.86 then local q=smooth((u-.64)/.22);m.command=.66*g*(1-q);m.arm=.30*g*(1-q);m.settle=.44*q;m.turn=winTurn*1.18*(1-q);m.forward=-.022*w*(1-q);m.lean=.026*w*(1-q);m.look=.12*(1-q);m.bob=.010*p.bounce*(1-q)
    else local q=1-smooth((u-.86)/.14);m.settle=.44*q;m.look=.025*q end
  end
  return scaleMotion(m,(tonumber(strength) or 1)*e)
end

local function ambientWindow(age,period,offset,attack,hold,release)
  local t=(age+offset)%period;local total=attack+hold+release
  if t>=total then return 0 end
  if t<attack then return smooth(t/math.max(.001,attack)) end
  if t<attack+hold then return 1 end
  return 1-smooth((t-attack-hold)/math.max(.001,release))
end
function A.idle(id,age,kind,actionAge,strength,side)
  local p=cloneProfile(id);age=tonumber(age) or 0
  local live=smooth((age-.48)/.70);local idle=p.idle or 1;local comp=p.composure or 1
  local phase=(#tostring(id or "")*0.37)%2.7
  local breath=clamp((.145+.052*math.sin(age*1.36+phase)+.020*math.sin(age*.51+1.2+phase))*live*idle,.020,.26)
  local glance=ambientWindow(age,6.8+comp*.4,.7+phase,.32,.48,.64)-ambientWindow(age,9.0+comp*.7,3.8+phase,.35,.42,.72)*.62
  local look=clamp((math.sin(age*.21+.35+phase)*.072+glance*.18)*live*(p.head or 1),-.24,.26)
  local gust=ambientWindow(age,5.0,.9+phase,.32,.42,.92)
  local settle=(.028+.011*math.sin(age*.89+.2+phase)+.018*gust)*live*idle
  local weight=math.sin(age*.26+1.0+phase)
  local turn=(math.sin(age*.15+.20+phase)*.012+glance*-.010)*live*idle/comp
  local bob=(math.sin(age*1.36+phase)*.0044+math.sin(age*.39+.7+phase)*.0018)*live*idle*(p.bounce or 1)
  local sway=(weight*.012+math.sin(age*.70+.4+phase)*.0045)*live*idle
  local lean=(weight*.0075+math.sin(age*.62+.2+phase)*.0033-gust*.003)*live*idle
  local windForward=(math.sin(age*1.80+.2+phase)*.0065-gust*.009)*live*idle
  local idleArm=(math.sin(age*.54+.8+phase)*.018+breath*.030)*live*idle
  local perf=A.motion(id,kind,actionAge,strength,side)
  local damp=kind and .18 or 1.0
  local out={breath=breath,look=look*damp+(perf.look or 0),arm=perf.arm or 0,shift=perf.shift or 0,settle=settle*damp+(perf.settle or 0),
    lean=lean*damp+(perf.lean or 0),turn=turn*damp+(perf.turn or 0),bob=bob*damp+(perf.bob or 0),sway=sway*damp+(perf.sway or 0),
    command=perf.command or 0,brace=perf.brace or 0,forward=windForward*damp+(perf.forward or 0),idleArm=idleArm*damp,
    armLead=perf.armLead or p.lead or 1,headEnergy=p.head or 1,weightEnergy=p.weight or 1}
  if id=="miror_b" then
    local groove=math.sin(age*.82+.40)*live
    local groove2=math.sin(age*.41+1.25)*live
    if not kind then out.sway=out.sway+groove*.024;out.turn=out.turn+groove2*.019;out.bob=out.bob+math.sin(age*1.64+.35)*.0055*live;out.lean=out.lean-groove*.010;out.look=out.look+groove2*.040 end
    local bodyTurn=out.turn or 0;local bodyShift=(out.shift or 0)*.045+(out.sway or 0);local bodyBob=out.bob or 0
    out.hairSway=clamp(-bodyTurn*1.10-bodyShift*1.20,-.115,.115);out.hairBounce=clamp(-bodyBob*1.45,-.070,.070);out.hairTwist=clamp(-bodyTurn*.52,-.060,.060)
  end
  out.sourceAuthority=clamp(tonumber(p.sourceAuthority) or 0,0,1)
  return out
end

-- Persistent performance state.  The old renderer sampled the mathematical
-- pose directly every draw, so a semantic event could snap the whole body from
-- one clean pose to another.  This spring layer preserves momentum across
-- anticipation, action, follow-through and recovery.  Different body regions
-- settle at different rates; recovery is intentionally slower than attack.
local DYNAMIC_KEYS={
  "breath","look","arm","shift","settle","lean","turn","bob","sway",
  "command","brace","forward","idleArm","hairSway","hairBounce","hairTwist",
}
local RESPONSE={
  breath={9.0,8.0},look={8.0,7.0},arm={16.0,8.8},shift={11.5,7.8},settle={8.0,6.3},
  lean={10.0,7.0},turn={10.5,7.2},bob={13.0,8.5},sway={8.0,6.2},command={17.0,9.0},
  brace={18.0,9.6},forward={12.0,7.8},idleArm={7.0,5.6},hairSway={5.5,4.5},
  hairBounce={6.5,5.0},hairTwist={5.0,4.2},
}
local function hash01(text)
  local h=2166136261
  for i=1,#text do h=(h*16777619 + text:byte(i)*97 + i*13) % 4294967296 end
  return (h%10000)/9999
end
local function signedVariant(id,kind,serial,salt)
  return hash01(table.concat({tostring(id),tostring(kind),tostring(serial or 0),tostring(salt)},":"))*2-1
end
function A.newState(id)
  return {id=tostring(id or "balanced"),current={},velocity={},lastKind=nil,serial=0,variant={0,0,0}}
end
function A.resetState(state,id)
  state=state or {}
  state.id=tostring(id or state.id or "balanced");state.current={};state.velocity={};state.lastKind=nil;state.serial=0;state.variant={0,0,0}
  return state
end
local function variedTarget(state,id,kind,target)
  if kind~=state.lastKind then
    state.lastKind=kind;state.serial=(state.serial or 0)+1
    state.variant={signedVariant(id,kind,state.serial,1),signedVariant(id,kind,state.serial,2),signedVariant(id,kind,state.serial,3)}
  end
  local v=state.variant or {0,0,0}
  local activity=clamp(math.max(math.abs(target.command or 0),math.abs(target.brace or 0),math.abs(target.arm or 0),math.abs(target.shift or 0)),0,1)
  -- Variation is deliberately small: it prevents carbon-copy repeats without
  -- changing the recognisable action silhouette or source-authored intent.
  target.turn=(target.turn or 0)*(1+v[1]*.045)
  target.arm=(target.arm or 0)*(1+v[2]*.055)
  target.command=(target.command or 0)*(1-v[2]*.035)
  target.shift=(target.shift or 0)*(1+v[3]*.040)
  target.sway=(target.sway or 0)+v[1]*.0045*activity
  target.lean=(target.lean or 0)+v[3]*.0035*activity
  return target
end
function A.step(state,id,age,kind,actionAge,strength,side,dt)
  state=state or A.newState(id);id=tostring(id or state.id or "balanced"):lower();state.id=id
  dt=clamp(tonumber(dt) or 0,0,.060)
  local target=A.idle(id,age,kind,actionAge,strength,side)
  target=variedTarget(state,id,kind,target)
  local p=cloneProfile(id);local continuity=tonumber(p.continuity) or 1
  for _,k in ipairs(DYNAMIC_KEYS) do
    local x=tonumber(state.current[k])
    local goal=tonumber(target[k]) or 0
    if x==nil then x=goal end
    local vel=tonumber(state.velocity[k]) or 0
    local tune=RESPONSE[k] or {10,7};local stiffness=tune[1]/continuity;local damping=tune[2]/math.sqrt(continuity)
    -- Let limbs and torso carry more inertia while returning toward neutral.
    if math.abs(goal)<math.abs(x) and (k=="arm" or k=="command" or k=="shift" or k=="lean" or k=="turn") then stiffness=stiffness*.68;damping=damping*.84 end
    vel=vel+(goal-x)*stiffness*stiffness*dt
    vel=vel*math.exp(-damping*dt)
    x=x+vel*dt
    state.current[k]=x;state.velocity[k]=vel;target[k]=x
  end
  target.armLead=target.armLead or p.lead or 1
  target.headEnergy=target.headEnergy or p.head or 1
  target.weightEnergy=target.weightEnergy or p.weight or 1
  target.sourceAuthority=clamp(tonumber(p.sourceAuthority) or 0,0,1)
  return target,state
end

function A.root(id,motion)
  local p=cloneProfile(id);motion=motion or {};local w=p.weight or 1
  return {
    -- The anatomical rig already carries the full lean/turn through pelvis and
    -- spine.  Root motion is only the residual whole-body commitment; keeping
    -- it restrained prevents planted feet from orbiting around the hip pivot.
    pitch=((motion.command or 0)*.025-(motion.brace or 0)*.016-(motion.arm or 0)*.004-(motion.shift or 0)*.010+(motion.lean or 0)*.28)*w,
    roll=((motion.shift or 0)*.016-(motion.command or 0)*.008+(motion.arm or 0)*.003+clamp((motion.sway or 0)*.10,-.006,.006))*w,
    yaw=(motion.turn or 0)*.46,
    compression=(motion.brace or 0)*.020,
  }
end
function A.status() return {version=3,vocabulary={"opening","sendout","command","brace","concern","frustration","victory","defeat"},profiles=PROFILES,clock="real-time-from-fixed-step",sharedPlayerEnemy=true,statefulContinuity=true,sourceAuthority=false,deterministicVariation=true} end
return A
