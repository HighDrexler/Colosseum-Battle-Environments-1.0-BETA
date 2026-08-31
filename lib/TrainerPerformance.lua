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
  sourceAuthority=1.00,continuity=1.00,
}
local PROFILES={
  red={label="FOCUSED",sourceAuthority=1,continuity=1.08,tempo=.98,energy=.96,composure=1.04,lead=1,commandTurn=-.064,sendTurn=-.092,openingTurn=.050,lossTurn=.030,victoryTurn=-.050,gesture=.96,reaction=.92,weight=.96,idle=.92,head=.92,bounce=.90},
  leaf={label="POISED",sourceAuthority=1,continuity=1.05,tempo=.94,energy=1.06,composure=.96,lead=-1,commandTurn=.060,sendTurn=.090,openingTurn=-.045,lossTurn=-.038,victoryTurn=.062,gesture=1.04,reaction=.98,weight=1.02,idle=1.04,head=1.12,bounce=1.03},
  wes={label="COOL",sourceAuthority=1,continuity=1.18,tempo=1.05,energy=.92,composure=1.14,lead=1,commandTurn=-.040,sendTurn=-.056,openingTurn=.030,lossTurn=.024,victoryTurn=-.030,gesture=.88,reaction=.84,weight=.95,idle=.82,head=.80,bounce=.78},
  brendan={label="ENERGETIC",sourceAuthority=1,continuity=.96,tempo=.90,energy=1.12,composure=.90,lead=1,commandTurn=-.074,sendTurn=-.106,openingTurn=.058,lossTurn=.042,victoryTurn=-.070,gesture=1.10,reaction=1.03,weight=1.08,idle=1.10,head=1.08,bounce=1.15},
  may={label="UPBEAT",sourceAuthority=1,continuity=.98,tempo=.91,energy=1.10,composure=.92,lead=-1,commandTurn=.072,sendTurn=.102,openingTurn=-.055,lossTurn=-.040,victoryTurn=.070,gesture=1.08,reaction=1.00,weight=1.05,idle=1.10,head=1.14,bounce=1.12},
  cooltrainer_m={label="COMPETITIVE",sourceAuthority=1,continuity=1.02,tempo=.96,energy=1.04,composure=.98,lead=1,commandTurn=-.060,sendTurn=-.086,openingTurn=.046,lossTurn=.036,victoryTurn=-.052,gesture=1.02,reaction=.98,weight=1.04,idle=.98,head=.96,bounce=1.00},
  cooltrainer_f={label="COMPETITIVE",sourceAuthority=1,continuity=1.02,tempo=.95,energy=1.05,composure=.98,lead=-1,commandTurn=.060,sendTurn=.086,openingTurn=-.046,lossTurn=-.036,victoryTurn=.052,gesture=1.03,reaction=.98,weight=1.03,idle=1.00,head=1.04,bounce=1.00},
  dakim={label="POWERFUL",sourceAuthority=1,continuity=1.12,tempo=1.08,energy=1.06,composure=.96,lead=1,commandTurn=-.036,sendTurn=-.054,openingTurn=.052,lossTurn=.044,victoryTurn=-.038,gesture=1.04,reaction=1.04,weight=1.14,idle=.86,head=.78,bounce=.88},
  nascour={label="CONTROLLED",sourceAuthority=1,continuity=1.18,tempo=1.12,energy=.82,composure=1.20,lead=1,commandTurn=-.030,sendTurn=-.050,openingTurn=-.040,lossTurn=-.032,victoryTurn=-.028,gesture=.82,reaction=.78,weight=.90,idle=.68,head=.72,bounce=.62},
  miror_b={label="THEATRICAL",sourceAuthority=1,continuity=.94,tempo=.88,energy=1.22,composure=.82,lead=-1,commandTurn=.078,sendTurn=.106,openingTurn=.074,lossTurn=-.062,victoryTurn=.090,gesture=1.22,reaction=1.12,weight=1.10,idle=1.30,head=1.22,bounce=1.28},
}

local DURATIONS={opening=1.92,throw=1.48,sendout=1.48,recall=1.18,command=1.20,brace=1.04,concern=1.22,frustration=2.62,victory=1.78,defeat=2.48}
local PRIORITY={brace=1,concern=2,command=2,opening=3,throw=4,sendout=4,recall=4,victory=5,defeat=6,frustration=6}

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
-- Presentation follows battle GAME-TIME. At 4x the source performance should
-- fast-forward exactly like Colosseum itself, not remain at 1x while Pokemon,
-- FX and the battle state advance four times faster.
function A.realDt(ctx,dt) return math.max(0,tonumber(dt) or 0) end
function A.speed(ctx) return battleSpeed(ctx) end

function A.shouldTrigger(ctx,current,currentAge,newKind)
  local age=tonumber(currentAge) or 0
  -- Do not let duplicate/rapid semantic events hammer the same source pose back
  -- to frame zero.  Damage, multi-hit and host wrappers can publish closely
  -- spaced presentation events; Colosseum trainers read as one reaction, not a
  -- strobing stack of braces.
  if current==newKind and age<.88 then return false end
  local reactionFamily={brace=true,concern=true}
  if reactionFamily[current] and reactionFamily[newKind] and age<.76 then return false end
  local cp=A.priority(current);local np=A.priority(newKind)
  if current and cp>np and age<.92 then return false end
  if (current=="frustration" or current=="defeat") and age<1.55 and np<6 then return false end
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

-- 1.5.57 source-clip playback.  TrainerExtractor v9 deliberately stores
-- COMMAND -> ARM -> SETTLE as chronological samples from one native B1 gesture
-- clip, and BRACE -> SHIFT as chronological samples from one native reaction
-- clip.  Drive those samples as a continuous barycentric timeline instead of
-- choosing one dominant semantic pose at a time.  At most two neighboring
-- source poses are blended at once, so every intermediate silhouette lies on
-- the path between adjacent frames from the SAME Colosseum clip.
local GESTURE_KIND={opening=true,throw=true,sendout=true,recall=true,command=true,victory=true}
local REACTION_KIND={brace=true,concern=true,frustration=true,defeat=true}
local function sourceTimeline(id,kind,t,strength)
  local p=cloneProfile(id)
  local out={command=0,arm=0,settle=0,brace=0,shift=0}
  if not kind then return out end
  local d=A.duration(id,kind)
  local u=clamp((tonumber(t) or 0)/math.max(.001,d),0,1)
  local raw=clamp(tonumber(strength) or 1,0,1.20)
  if GESTURE_KIND[kind] then
    local amp=clamp(raw*(tonumber(p.gesture) or 1),0,1)
    if u<.18 then
      out.command=smooth(u/.18)*amp
    elseif u<.48 then
      local q=smooth((u-.18)/.30);out.command=(1-q)*amp;out.arm=q*amp
    elseif u<.78 then
      local q=smooth((u-.48)/.30);out.arm=(1-q)*amp;out.settle=q*amp
    else
      out.settle=(1-smooth((u-.78)/.22))*amp
    end
  elseif REACTION_KIND[kind] then
    local amp=clamp(raw*(tonumber(p.reaction) or 1),0,1)
    if u<.16 then
      out.brace=smooth(u/.16)*amp
    elseif u<.60 then
      local q=smooth((u-.16)/.44);out.brace=(1-q)*amp;out.shift=q*amp
    else
      out.shift=(1-smooth((u-.60)/.40))*amp
    end
  end
  return out
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
  elseif kind=="recall" then
    -- Ball-hand recall: brace backward, present the dominant hand toward the
    -- outgoing Pokemon, then draw the arm back as the actor contracts into the
    -- return effect. This is a semantic performance placeholder until each
    -- trainer's exact Colosseum recall clip is decoded from its source archive.
    if u<.14 then local q=smooth(u/.14);m.shift=-.22*w*q;m.arm=.18*g*q;m.turn=-sendTurn*.55*q;m.forward=.030*w*q;m.lean=-.020*w*q;m.look=.08*q
    elseif u<.36 then local q=smooth((u-.14)/.22);m.shift=-.22*w;m.arm=(.18+.46*q)*g;m.command=.28*g*q;m.turn=-sendTurn*(.55+.45*q);m.forward=.030*w-.052*w*q;m.lean=-.020*w+.042*w*q;m.look=.10
    elseif u<.62 then m.shift=-.20*w;m.arm=.64*g;m.command=.28*g;m.turn=-sendTurn;m.forward=-.022*w;m.lean=.022*w;m.look=.10
    elseif u<.84 then local q=smooth((u-.62)/.22);m.shift=-.20*w*(1-q);m.arm=.64*g*(1-q);m.command=.28*g*(1-q);m.settle=.50*q;m.turn=-sendTurn*(1-q);m.forward=-.022*w*(1-q);m.lean=.022*w*(1-q);m.look=.10*(1-q)
    else local q=1-smooth((u-.84)/.16);m.settle=.50*q;m.arm=.08*g*q end
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
  local breath=clamp((.105+.032*math.sin(age*1.36+phase)+.012*math.sin(age*.51+1.2+phase))*live*idle,.015,.18)
  local glance=ambientWindow(age,6.8+comp*.4,.7+phase,.32,.48,.64)-ambientWindow(age,9.0+comp*.7,3.8+phase,.35,.42,.72)*.62
  local look=clamp((math.sin(age*.21+.35+phase)*.042+glance*.105)*live*(p.head or 1),-.15,.16)
  local gust=ambientWindow(age,5.0,.9+phase,.32,.42,.92)
  local settle=(.020+.0065*math.sin(age*.89+.2+phase)+.009*gust)*live*idle
  local weight=math.sin(age*.26+1.0+phase)
  local turn=(math.sin(age*.15+.20+phase)*.007+glance*-.006)*live*idle/comp
  local bob=(math.sin(age*1.36+phase)*.0026+math.sin(age*.39+.7+phase)*.0010)*live*idle*(p.bounce or 1)
  local sway=(weight*.0070+math.sin(age*.70+.4+phase)*.0026)*live*idle
  local lean=(weight*.0044+math.sin(age*.62+.2+phase)*.0019-gust*.0018)*live*idle
  local windForward=(math.sin(age*1.80+.2+phase)*.0038-gust*.0052)*live*idle
  local idleArm=(math.sin(age*.54+.8+phase)*.010+breath*.018)*live*idle
  local perf=A.motion(id,kind,actionAge,strength,side)
  local damp=kind and .18 or 1.0
  local out={breath=breath,look=look*damp+(perf.look or 0),arm=perf.arm or 0,shift=perf.shift or 0,settle=settle*damp+(perf.settle or 0),
    lean=lean*damp+(perf.lean or 0),turn=turn*damp+(perf.turn or 0),bob=bob*damp+(perf.bob or 0),sway=sway*damp+(perf.sway or 0),
    command=perf.command or 0,brace=perf.brace or 0,forward=windForward*damp+(perf.forward or 0),idleArm=idleArm*damp,
    armLead=perf.armLead or p.lead or 1,headEnergy=p.head or 1,weightEnergy=p.weight or 1}
  if id=="miror_b" then
    local groove=math.sin(age*.82+.40)*live
    local groove2=math.sin(age*.41+1.25)*live
    if not kind then out.sway=out.sway+groove*.012;out.turn=out.turn+groove2*.009;out.bob=out.bob+math.sin(age*1.64+.35)*.0028*live;out.lean=out.lean-groove*.005;out.look=out.look+groove2*.020 end
    local bodyTurn=out.turn or 0;local bodyShift=(out.shift or 0)*.045+(out.sway or 0);local bodyBob=out.bob or 0
    out.hairSway=clamp(-bodyTurn*1.10-bodyShift*1.20,-.115,.115);out.hairBounce=clamp(-bodyBob*1.45,-.070,.070);out.hairTwist=clamp(-bodyTurn*.52,-.060,.060)
  end
  out.sourceAuthority=clamp(tonumber(p.sourceAuthority) or 0,0,1)
  -- Source-authoritative actions follow the actual chronological B1 clip family
  -- instead of winner-take-all pose switching.  This removes the visible snap
  -- when COMMAND suddenly lost ownership to ARM/SETTLE while keeping all large
  -- deformation source-authored.
  if kind and out.sourceAuthority>=.75 then
    local src=sourceTimeline(id,kind,actionAge,strength)
    out.command=src.command;out.arm=src.arm;out.settle=src.settle
    out.brace=src.brace;out.shift=src.shift
  end
  -- 1.5.54: source B1 poses own the visible trainer performance. Whole-body
  -- sway/bob/lean remains only as a small continuity layer so authored feet,
  -- shoulders and torso silhouettes are not puppeteered by procedural motion.
  local residual=1-out.sourceAuthority*.97
  out.lean=(out.lean or 0)*residual;out.turn=(out.turn or 0)*residual
  out.bob=(out.bob or 0)*residual;out.sway=(out.sway or 0)*residual
  out.forward=(out.forward or 0)*residual
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
function A.newState(id)
  return {id=tostring(id or "balanced"),current={},velocity={}}
end
function A.resetState(state,id)
  state=state or {}
  state.id=tostring(id or state.id or "balanced");state.current={};state.velocity={}
  return state
end
function A.step(state,id,age,kind,actionAge,strength,side,dt)
  state=state or A.newState(id);id=tostring(id or state.id or "balanced"):lower();state.id=id
  dt=clamp(tonumber(dt) or 0,0,.060)
  local target=A.idle(id,age,kind,actionAge,strength,side)
  -- Do not randomly perturb source-pose weights. Once CBE has classified an
  -- authored B1 silhouette, replay that silhouette consistently; only the
  -- deterministic continuity filter below remains on top of the source pose.
  local p=cloneProfile(id);local continuity=tonumber(p.continuity) or 1
  local sourceKeys={breath=true,look=true,arm=true,shift=true,settle=true,command=true,brace=true}
  for _,k in ipairs(DYNAMIC_KEYS) do
    local x=tonumber(state.current[k]);local goal=tonumber(target[k]) or 0;if x==nil then x=goal end
    if sourceKeys[k] then
      -- The target itself is now a continuous source-clip timeline. Apply only
      -- a gentle low-pass for event-boundary continuity; do not independently
      -- spring each source pose or it re-introduces robotic phase lag/snapping.
      local attack=kind and 9.2 or 6.8;local release=kind and 7.4 or 5.8
      local rate=(math.abs(goal)>math.abs(x) and attack or release)/continuity
      local q=1-math.exp(-rate*dt);x=x+(goal-x)*q;state.velocity[k]=0
    else
      local vel=tonumber(state.velocity[k]) or 0
      local tune=RESPONSE[k] or {10,7};local stiffness=tune[1]/continuity;local damping=tune[2]/math.sqrt(continuity)
      vel=vel+(goal-x)*stiffness*stiffness*dt;vel=vel*math.exp(-damping*dt);x=x+vel*dt;state.velocity[k]=vel
    end
    state.current[k]=x;target[k]=x
  end
  target.armLead=target.armLead or p.lead or 1
  target.headEnergy=target.headEnergy or p.head or 1
  target.weightEnergy=target.weightEnergy or p.weight or 1
  target.sourceAuthority=clamp(tonumber(p.sourceAuthority) or 0,0,1)
  return target,state
end

function A.root(id,motion)
  local p=cloneProfile(id);motion=motion or {};local w=p.weight or 1
  local authority=clamp(tonumber(motion.sourceAuthority) or tonumber(p.sourceAuthority) or 0,0,1)
  local residual=1-authority*.99
  return {
    -- The anatomical rig already carries the full lean/turn through pelvis and
    -- spine.  Root motion is only the residual whole-body commitment; keeping
    -- it restrained prevents planted feet from orbiting around the hip pivot.
    pitch=((motion.command or 0)*.025-(motion.brace or 0)*.016-(motion.arm or 0)*.004-(motion.shift or 0)*.010+(motion.lean or 0)*.28)*w*residual,
    roll=((motion.shift or 0)*.016-(motion.command or 0)*.008+(motion.arm or 0)*.003+clamp((motion.sway or 0)*.10,-.006,.006))*w*residual,
    yaw=(motion.turn or 0)*.46*residual,
    compression=(motion.brace or 0)*.020*residual,
  }
end
function A.status() return {version=10,vocabulary={"opening","sendout","recall","command","brace","concern","frustration","victory","defeat"},profiles=PROFILES,clock="game-time-from-fixed-step",sharedPlayerEnemy=true,statefulContinuity=true,sourceAuthority=true,sourcePoseBank="native-b1-coherent-clipfamilies",sourcePlayback="continuous-adjacent-b1-timeline",proceduralRoot="one-percent-continuity-only",randomVariation=false} end
return A
