local M={version=15,source="GC6E01 FieldParticleFile + PSGeneratorState/PSParticle retail runtime"}

-- Colosseum has two distinct particle-runtime layers:
--   Waza Type-3 -> PSGeneratorState -> emitted PSParticle -> particle bytecode.
-- 1.9.x collapsed both layers into a synthetic emitter and then interpreted the
-- generator record as though it were already a particle. This VM keeps the two
-- source objects distinct and uses bank-local script ids/table lookups exactly.

local FRAME_DT=1/60
local MAX_TOTAL_PARTICLES=768
local MAX_TOTAL_GENERATORS=192
local MAX_STEPS_PER_UPDATE=30
local MAX_COMMANDS_PER_FRAME=256
local MAX_EMIT_PER_FRAME=96
local MAX_EFFECT_SECONDS=30 -- watchdog only; source objects normally retire themselves

local function hasBit(v,bit) return math.floor((tonumber(v) or 0)/bit)%2>=1 end
local function setBit(v,bit,on)
  v=tonumber(v) or 0
  local present=hasBit(v,bit)
  if on then return present and v or (v+bit) end
  return present and (v-bit) or v
end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function phaseRole(phase)
  phase=tostring(phase or "all"):lower()
  return (phase:match("^damage") or phase=="status") and "damage" or "attack"
end
local function vecLength(v)
  local x,y,z=tonumber(v and v[1]) or 0,tonumber(v and v[2]) or 0,tonumber(v and v[3]) or 0
  return math.sqrt(x*x+y*y+z*z)
end
local function normalizeTo(v,length)
  local n=vecLength(v);if n<1e-9 then return {0,0,tonumber(length) or 0} end
  local k=(tonumber(length) or 0)/n
  return {(v[1] or 0)*k,(v[2] or 0)*k,(v[3] or 0)*k}
end
local function add3(a,b) return {(a and a[1] or 0)+(b and b[1] or 0),(a and a[2] or 0)+(b and b[2] or 0),(a and a[3] or 0)+(b and b[3] or 0)} end

local function hexToBytes(hex)
  if type(hex)~="string" or hex=="" then return "" end
  local out={};for i=1,#hex-1,2 do local n=tonumber(hex:sub(i,i+1),16);if not n then break end;out[#out+1]=string.char(n) end
  return table.concat(out)
end
local function u8(data,pos) if pos>#data then return 0,#data+1 end;return data:byte(pos) or 0,pos+1 end
local function s8(data,pos) local v;v,pos=u8(data,pos);if v>=128 then v=v-256 end;return v,pos end
local function u16(data,pos) local a,b=data:byte(pos,pos+1);if not b then return 0,#data+1 end;return a*256+b,pos+2 end
local function u32(data,pos) local a,b,c,d=data:byte(pos,pos+3);if not d then return 0,#data+1 end;return ((a*256+b)*256+c)*256+d,pos+4 end
local function f32(data,pos)
  local bits,nextPos=u32(data,pos);local sign=bits>=2147483648 and -1 or 1;if bits>=2147483648 then bits=bits-2147483648 end
  local exp=math.floor(bits/8388608);local mant=bits-exp*8388608
  if exp==255 then return mant==0 and sign*1e30 or 0,nextPos end
  if exp==0 then return mant==0 and 0 or sign*(mant/8388608)*(2^-126),nextPos end
  return sign*(1+mant/8388608)*(2^(exp-127)),nextPos
end
local function readTime(data,pos)
  local b;b,pos=u8(data,pos);if b>=128 then local b2;b2,pos=u8(data,pos);return (b-128)*256+b2,pos end;return b,pos
end
local function rng(seed)
  seed=math.floor(math.abs(tonumber(seed) or 1))%2147483647;if seed==0 then seed=1 end
  return function() seed=(seed*16807)%2147483647;return seed/2147483647 end
end

local function countBits(mask,n)
  local c=0;for i=0,n-1 do if hasBit(mask,2^i) then c=c+1 end end;return c
end

-- Framing is part of ownership. A source program is executable only if every
-- instruction boundary is known. Notably AC consumes two floats after time and
-- F1 consumes a u16 table index. Consuming the following opcode as an extra
-- argument turns the source CF color ramp into a bogus 0x82 position command
-- in Seismic Toss/Vital Throw (and consumes loop delays in other banks).
local function programSupported(commandHex,visit)
  local data=hexToBytes(commandHex);if data=="" then return false end
  local pos=1;local guard=0
  local function need(n) if pos+n-1>#data then return false end;pos=pos+n;return true end
  local function timeArg() if pos>#data then return false end;local b=data:byte(pos) or 0;pos=pos+1;if b>=128 then return need(1) end;return true end
  while pos<=#data and guard<8192 do
    guard=guard+1;local op=data:byte(pos);if visit then visit(op,pos) end;pos=pos+1
    if op<0x80 then
      if hasBit(op,0x20) and not need(1) then return false end
      if hasBit(op,0x40) and not need(1) then return false end
    elseif op>=0x80 and op<=0x9F then if not need(countBits(op%8,3)*4) then return false end
    elseif op==0xA0 or op==0xB6 then if not timeArg() or not need(4) then return false end
    elseif op==0xAC then if not timeArg() or not need(8) then return false end
    elseif op==0xFE or op==0xFF then return true
    elseif op==0xA1 or op==0xAD or (op>=0xAE and op<=0xB2) or op==0xB4 or op==0xB5
        or op==0xE2 or op==0xE6 or op==0xE7 or op==0xF5 or op==0xF6 or op==0xF7
        or op==0xFB or op==0xFC or op==0xFD then
    elseif op==0xA2 or op==0xA3 or op==0xA9 or op==0xAB or op==0xE8 then if not need(4) then return false end
    elseif op==0xA4 or op==0xA5 or op==0xB9 or op==0xF2 then if not need(2) then return false end
    elseif op==0xF1 then if not need(2) then return false end
    elseif op==0xA6 or op==0xAA then if not need(4) then return false end
    elseif op==0xA7 or op==0xB7 or op==0xBF or op==0xE1 or op==0xE3 or op==0xE4 or op==0xE5 or op==0xFA then if not need(1) then return false end
    elseif op==0xA8 or op==0xBE then if not need(12) then return false end
    elseif op==0xB3 then if not timeArg() or not need(3) then return false end
    elseif op==0xB8 then if not need(9) then return false end
    elseif op==0xBA or op==0xBB or op==0xE0 then if not need(4) then return false end
    elseif op==0xBC then if not need(2) then return false end
    elseif op==0xBD then if not need(8) then return false end
    elseif op>=0xC0 and op<=0xCF then if not timeArg() or not need(countBits(op-0xC0,4)) then return false end
    elseif op>=0xD0 and op<=0xDF then if not timeArg() or not need(countBits(op-0xD0,4)) then return false end
    elseif op==0xE9 then
      if not need(2) then return false end;local mask=data:byte(pos-2) or 0;if not need(countBits(mask,4)) then return false end
    elseif op==0xEA or op==0xEB then
      if not timeArg() or not need(1) then return false end;local flags=data:byte(pos-1) or 0
      local n=(hasBit(flags,1) and 1 or 0)+(hasBit(flags,8) and 1 or 0);if not need(n) then return false end
    elseif op==0xEC then if not need(5) then return false end
    elseif op==0xED then if not need(9) then return false end
    elseif op==0xEF or op==0xF0 then if not need(3) then return false end
    elseif op==0xF3 then if not need(9) or not timeArg() then return false end
    elseif op==0xF4 then if not need(16) then return false end
    else return false end
  end
  return guard<8192 and pos==#data+1
end
M.programSupported=programSupported

local function exactPhaseMatches(g,entry)
  if type(entry)~="table" then return true end
  return not (entry.phase~=nil and g.phase~=nil and tostring(entry.phase):lower()~=tostring(g.phase):lower())
end
local function bankMatchesEntry(g,entry)
  if type(entry)~="table" then return true end
  if entry.sourceBank~=nil and g.sourceBank~=nil and tonumber(entry.sourceBank)~=tonumber(g.sourceBank) then return false end
  if entry.bank~=nil and g.bank~=nil and tonumber(entry.bank)~=tonumber(g.bank) then return false end
  return true
end
local function executable(g,role,entry)
  return phaseRole(g.phase)==role and exactPhaseMatches(g,entry) and type(g.commandHex)=="string" and #g.commandHex>=2 and programSupported(g.commandHex)
end
local function selectRoot(spec,entry,role)
  local wanted=type(entry)=="table" and tonumber(entry.selector~=nil and entry.selector or entry.rootRef) or nil
  local same,any,marked=nil,nil,nil
  for _,g in ipairs(type(spec)=="table" and (spec.generatorPrograms or {}) or {}) do
    if executable(g,role,entry) then
      any=any or g;if g.root==true then marked=marked or g end
      local id=tonumber(g.scriptId~=nil and g.scriptId or g.bankIndex)
      if wanted~=nil and id==wanted then if bankMatchesEntry(g,entry) then return g else same=same or g end end
    end
  end
  -- An explicit Type-3 selector is a bank-local identity. Using an unrelated
  -- root disguises an incomplete cache as a different move effect.
  if wanted~=nil then return nil end
  if type(entry)=="table" and (entry.bank~=nil or entry.sourceBank~=nil) then
    for _,g in ipairs(spec.generatorPrograms or {}) do
      if executable(g,role,entry) and bankMatchesEntry(g,entry) and g.root==true then return g end
    end
    return nil
  end
  return marked or any
end
function M.hasRole(spec,role)
  role=tostring(role or "attack")
  for _,g in ipairs(type(spec)=="table" and (spec.generatorPrograms or {}) or {}) do if executable(g,role,nil) and g.root==true then return true end end
  return false
end
function M.hasEntry(spec,entry,role)
  if type(spec)~="table" or type(entry)~="table" or #(spec.textures or {})<1 then return false end
  local root=selectRoot(spec,entry,tostring(role or phaseRole(entry.phase)))
  if not root then return false end
  for _,tex in ipairs(spec.textures) do
    if tex.bank==nil or root.bank==nil or tonumber(tex.bank)==tonumber(root.bank) then return true end
  end
  return false
end
function M.programSpawnsChildren(commandHex)
  local found=false
  local valid=programSupported(commandHex,function(op)
    if op==0xA4 or op==0xA5 or op==0xAA or op==0xB9 or op==0xF1 or op==0xF2 then found=true end
  end)
  return valid and found
end

local function templateKey(bank,id) return tostring(tonumber(bank) or 1)..":"..tostring(tonumber(id) or 0) end
local function addFault(fx,kind,detail)
  fx.opcodeFaults=fx.opcodeFaults or {};if #fx.opcodeFaults<64 then fx.opcodeFaults[#fx.opcodeFaults+1]={frame=fx.frame,kind=kind,detail=detail} end
end
local function lookupScriptId(fx,bank,tableIndex)
  local t=fx.spec and fx.spec.lookupTables and fx.spec.lookupTables[tonumber(bank) or bank]
  local v=t and (t[tableIndex]~=nil and t[tableIndex] or t[tostring(tableIndex)])
  if v==nil then addFault(fx,"lookup-miss",tostring(bank)..":"..tostring(tableIndex));return nil end
  return tonumber(v)
end
local function findTemplate(fx,bank,scriptId)
  return fx.templateById[templateKey(bank,scriptId)]
end

local function generatorBasisVelocity(g)
  return {tonumber(g.velocityX) or tonumber(g.params and g.params[3]) or 0,tonumber(g.velocityY) or tonumber(g.params and g.params[4]) or 0,tonumber(g.velocityZ) or tonumber(g.params and g.params[5]) or 0}
end
local function rotateToward(v,forward)
  -- Lightweight source-space orientation: preserve magnitude and align local Z
  -- with the generator's authored velocity. The retail matrix path additionally
  -- applies generator Euler/AppSRT; those remain explicit runtime state rather
  -- than a move-type heuristic.
  local m=vecLength(v);if m<1e-9 then return {0,0,0} end
  local f=normalizeTo(forward,1);local up={0,1,0}
  if math.abs(f[2])>.98 then up={1,0,0} end
  local rx=up[2]*f[3]-up[3]*f[2];local ry=up[3]*f[1]-up[1]*f[3];local rz=up[1]*f[2]-up[2]*f[1]
  local r=normalizeTo({rx,ry,rz},1);local u={f[2]*r[3]-f[3]*r[2],f[3]*r[1]-f[1]*r[3],f[1]*r[2]-f[2]*r[1]}
  return {r[1]*v[1]+u[1]*v[2]+f[1]*v[3],r[2]*v[1]+u[2]*v[2]+f[2]*v[3],r[3]*v[1]+u[3]*v[2]+f[3]*v[3]}
end

local function newGenerator(fx,template,position,parentParticle)
  if not template or #fx.generators>=MAX_TOTAL_GENERATORS then return nil end
  fx.spawnSerial=fx.spawnSerial+1;local g=template.gen;local rate=tonumber(g.emissionRate) or tonumber(g.params and g.params[8]) or 0
  local random=rng((tonumber(g.bank) or 1)*7919+(tonumber(g.scriptId) or 0)*104729+fx.spawnSerial*97)
  local acc=rate<0 and 0 or random()
  local inst={template=template,gen=g,bank=tonumber(g.bank) or 1,scriptId=tonumber(g.scriptId~=nil and g.scriptId or g.bankIndex) or 0,
    position={position and position[1] or 0,position and position[2] or 0,position and position[3] or 0},
    random=random,accumulator=acc,rate=rate,maxLife=tonumber(g.maxLife) or 0,age=0,alive=true,childCount=0,parentParticle=parentParticle,
    autoRoot=template.autoRoot==true}
  fx.generators[#fx.generators+1]=inst;fx.emitters=fx.generators;return inst
end

local function sourceParticleState(template)
  local g=template.gen;return {
    flags=tonumber(g.flags) or 0,animIndex=tonumber(g.animIndex) or tonumber(g.texGroup) or 0,
    repeatCount=tonumber(g.repeatCount) or tonumber(g.particleLife) or 0,
    size=tonumber(g.particleSize) or tonumber(g.params and g.params[9]) or 1,
    gravity=tonumber(g.gravity) or tonumber(g.params and g.params[1]) or 0,
    friction=tonumber(g.friction) or tonumber(g.params and g.params[2]) or 1,
    velocity={tonumber(g.velocityX) or tonumber(g.params and g.params[3]) or 0,tonumber(g.velocityY) or tonumber(g.params and g.params[4]) or 0,tonumber(g.velocityZ) or tonumber(g.params and g.params[5]) or 0},
  }
end
local function newParticleFromTemplate(fx,template,position,velocity,parent,generator,inheritVelocity)
  if not template or #fx.particles>=MAX_TOTAL_PARTICLES then return nil end
  fx.spawnSerial=fx.spawnSerial+1;local g=template.gen;local st=sourceParticleState(template);local flags=st.flags
  local vel={st.velocity[1],st.velocity[2],st.velocity[3]};if velocity then vel={velocity[1] or 0,velocity[2] or 0,velocity[3] or 0} end
  if inheritVelocity and parent then vel={parent.velocity[1],parent.velocity[2],parent.velocity[3]} end
  local p={alive=true,frame=0,bank=tonumber(g.bank) or 1,sourceBank=g.sourceBank,gptOffset=g.gptOffset,scriptId=tonumber(g.scriptId~=nil and g.scriptId or g.bankIndex) or 0,
    animIndex=st.animIndex,position={position and position[1] or 0,position and position[2] or 0,position and position[3] or 0},velocity=vel,
    scaleFactor=st.gravity,gravity=st.gravity,frictionFactor=st.friction,friction=st.friction,
    repeatCount=math.max(1,math.floor(st.repeatCount)+1),size=st.size,sizeTarget=st.size,sizeTime=0,
    rotation=0,heading=0,headingSpeed=0,headingAccel=0,headingTime=0,
    prim={255,255,255,255},primTarget={255,255,255,255},primTime=0,env={0,0,0,0},envTarget={0,0,0,0},envTime=0,
    flags=flags,textureIndex=0,textureOff=not hasBit(flags,0x400),objRefIndex=0,
    mirrorS=hasBit(flags,0x20),mirrorT=hasBit(flags,0x40),flipS=hasBit(flags,0x40000),flipT=hasBit(flags,0x80000),
    blendMode=math.floor(flags/0x400000)%4,alphaScale=1,alphaMode=0x33,alphaStart=((math.floor(flags/0x400000)%4)>=2) and 0 or 1,alphaEnd=255,
    alphaTargetStart=0,alphaTargetEnd=255,alphaTime=0,trail=hasBit(flags,0x100000),history={},
    jointId=math.floor(flags/0x1000)%8,updateJoint=hasBit(flags,0x8000),jointExplicit=hasBit(flags,0x8000),
    cmdPos=1,wait=1,savedPC=1,loopCount=0,loopPos=1,data=template.data,random=rng((tonumber(g.bank) or 1)*7919+(tonumber(g.scriptId) or 0)*104729+fx.spawnSerial*131),
    generator=generator,parent=parent}
  -- Keep the birth part transform outside script-local positions. Source
  -- position opcodes (80..8F) must not erase the emitter's world attachment.
  -- Children inherit that birth frame, so old foam does not slide with a wave.
  local owner=parent or (generator and generator.parentParticle)
  local matrix=owner and owner.attachmentMatrix or (generator and generator.autoRoot and fx.emissionTransform)
  if matrix then p.attachmentMatrix={};for k=1,12 do p.attachmentMatrix[k]=matrix[k] end end
  fx.particles[#fx.particles+1]=p;if generator then generator.childCount=generator.childCount+1 end;return p
end

local function emitGeneratorParticle(fx,gen)
  local g=gen.gen;local random=gen.random;local mode=(tonumber(g.angleFlags) or 0)%16
  local radius=tonumber(g.radius) or tonumber(g.params and g.params[6]) or 0
  local angle=tonumber(g.angle) or tonumber(g.params and g.params[7]) or 0
  local sx=tonumber(g.shapeX) or tonumber(g.params and g.params[10]) or 0
  local sy=tonumber(g.shapeY) or tonumber(g.params and g.params[11]) or 0
  local sz=tonumber(g.shapeZ) or tonumber(g.params and g.params[12]) or 0
  local baseVel=generatorBasisVelocity(g);local speed=vecLength(baseVel);local pos={0,0,0};local vel={baseVel[1],baseVel[2],baseVel[3]}
  if mode==1 then
    local r=random();pos={r*sx,r*sy,r*sz}
  elseif mode==5 then
    pos={(random()*2-1)*math.abs(sx),(random()*2-1)*math.abs(sy),(random()*2-1)*math.abs(sz)}
  elseif mode==2 then
    local theta=random()*math.pi*2;local rr=radius<0 and math.abs(radius) or math.abs(radius)*random();pos={rr*math.cos(theta),rr*math.sin(theta),0}
  else
    local theta=random()*math.pi*2;local rr=radius<0 and math.abs(radius) or math.abs(radius)*((mode==3 or mode==4) and math.sqrt(random()) or random())
    local cone=math.abs(angle)*random();pos={rr*math.cos(theta),rr*math.sin(theta),(mode==6 or mode==7) and random()*sz or 0}
    if speed>1e-9 then vel={speed*math.sin(cone)*math.cos(theta),speed*math.sin(cone)*math.sin(theta),speed*math.cos(cone)};vel=rotateToward(vel,baseVel) end
  end
  pos=add3(gen.position,pos)
  -- Root emitters follow their live Waza attachment at emission time. Existing
  -- particles and child generators retain their source-space positions.
  -- Explicit joint-follow particles are positioned by their own joint opcode.
  if gen.autoRoot and not gen.parentParticle and fx.emissionOrigin and not hasBit(tonumber(g.flags) or 0,0x8000) then
    pos=add3(pos,fx.emissionOrigin)
  end
  return newParticleFromTemplate(fx,gen.template,pos,vel,nil,gen,false)
end

local function spawnParticle(fx,parent,scriptId,inheritVelocity,tableLookup)
  if tableLookup then scriptId=lookupScriptId(fx,parent.bank,scriptId) end;if scriptId==nil then return nil end
  local t=findTemplate(fx,parent.bank,scriptId);if not t then addFault(fx,"script-miss",tostring(parent.bank)..":"..tostring(scriptId));return nil end
  local p=newParticleFromTemplate(fx,t,parent.position,nil,parent,nil,inheritVelocity)
  if p and parent then p.jointId=parent.jointId;p.updateJoint=parent.updateJoint;p.jointExplicit=parent.jointExplicit end
  return p
end
local function spawnGenerator(fx,parent,scriptId,tableLookup)
  if tableLookup then scriptId=lookupScriptId(fx,parent.bank,scriptId) end;if scriptId==nil then return nil end
  local t=findTemplate(fx,parent.bank,scriptId);if not t then addFault(fx,"generator-miss",tostring(parent.bank)..":"..tostring(scriptId));return nil end
  return newGenerator(fx,t,parent.position,parent)
end
local function jointTarget(fx,id) local j=fx and fx.joints;id=tonumber(id);return id and type(j)=="table" and (j[id] or j[id+1]) or nil end

local function finishColor(c,t,time) if time and time>0 then for i=1,4 do c[i]=t[i] end end end
local function interpColor(c,t,time)
  if not time or time<=0 then return 0 end;time=time-1;if time==0 then for i=1,4 do c[i]=t[i] end else local q=1/(time+1);for i=1,4 do c[i]=math.floor(c[i]+(t[i]-c[i])*q+.5) end end;return time
end
local function signedRandomDelta(p,span) span=tonumber(span) or 0;return math.floor((p.random()*2-1)*span*2+.5) end

local function executeComplex(p,fx,op)
  local d=p.data;local pos=p.cmdPos;local bits=op%8
  if op>=0x80 and op<=0x87 then
    if hasBit(bits,1) then p.position[1],pos=f32(d,pos) end;if hasBit(bits,2) then p.position[2],pos=f32(d,pos) end;if hasBit(bits,4) then p.position[3],pos=f32(d,pos) end
  elseif op>=0x88 and op<=0x8F then
    if hasBit(bits,1) then local v;v,pos=f32(d,pos);p.position[1]=p.position[1]+v end;if hasBit(bits,2) then local v;v,pos=f32(d,pos);p.position[2]=p.position[2]+v end;if hasBit(bits,4) then local v;v,pos=f32(d,pos);p.position[3]=p.position[3]+v end
  elseif op>=0x90 and op<=0x97 then
    if hasBit(bits,1) then p.velocity[1],pos=f32(d,pos) end;if hasBit(bits,2) then p.velocity[2],pos=f32(d,pos) end;if hasBit(bits,4) then p.velocity[3],pos=f32(d,pos) end
  elseif op>=0x98 and op<=0x9F then
    if hasBit(bits,1) then local v;v,pos=f32(d,pos);p.velocity[1]=p.velocity[1]+v end;if hasBit(bits,2) then local v;v,pos=f32(d,pos);p.velocity[2]=p.velocity[2]+v end;if hasBit(bits,4) then local v;v,pos=f32(d,pos);p.velocity[3]=p.velocity[3]+v end
  elseif op==0xA0 then p.sizeTime,pos=readTime(d,pos);p.sizeTarget,pos=f32(d,pos);if p.sizeTime==0 then p.size=p.sizeTarget end
  elseif op==0xA1 then p.flags=p.flags-(hasBit(p.flags,0x400) and 0x400 or 0);p.textureOff=true
  elseif op==0xA2 then p.scaleFactor,pos=f32(d,pos);p.gravity=p.scaleFactor;p.flags=setBit(p.flags,1,p.scaleFactor~=0)
  elseif op==0xA3 then p.frictionFactor,pos=f32(d,pos);p.friction=p.frictionFactor;p.flags=setBit(p.flags,2,p.frictionFactor~=1)
  elseif op==0xA4 then local id;id,pos=u16(d,pos);p.cmdPos=pos;spawnParticle(fx,p,id,false,false);return
  elseif op==0xA5 then local id;id,pos=u16(d,pos);p.cmdPos=pos;spawnGenerator(fx,p,id,false);return
  elseif op==0xA6 then local base,range;base,pos=u16(d,pos);range,pos=u16(d,pos);p.repeatCount=base+math.floor(range*p.random())
  elseif op==0xA7 then local threshold;threshold,pos=u8(d,pos);if math.floor(p.random()*256)>threshold then p.wait=1;p.cmdPos=pos;return "yield" end
  elseif op==0xA8 then local x,y,z;x,pos=f32(d,pos);y,pos=f32(d,pos);z,pos=f32(d,pos);p.position[1]=p.position[1]+(p.random()*2-1)*x;p.position[2]=p.position[2]+(p.random()*2-1)*y;p.position[3]=p.position[3]+(p.random()*2-1)*z
  elseif op==0xA9 then local a;a,pos=f32(d,pos);local vx,vz=p.velocity[1],p.velocity[3];local c,s=math.cos(a),math.sin(a);p.velocity[1]=vx*c-vz*s;p.velocity[3]=vx*s+vz*c
  elseif op==0xAA then local base,range;base,pos=u16(d,pos);range,pos=u16(d,pos);local idx=base+(range>0 and math.floor(range*p.random()) or 0);p.cmdPos=pos;spawnParticle(fx,p,idx,false,true);return
  elseif op==0xAB then local f;f,pos=f32(d,pos);for i=1,3 do p.velocity[i]=p.velocity[i]*f end
  elseif op==0xAC then local tm,base,range;tm,pos=readTime(d,pos);base,pos=f32(d,pos);range,pos=f32(d,pos);p.sizeTime=tm;p.sizeTarget=base+range*p.random();if tm==0 then p.size=p.sizeTarget end
  elseif op==0xAD then p.flags=p.flags+((not hasBit(p.flags,0x80)) and 0x80 or 0)
  elseif op==0xAE then p.flags=setBit(setBit(p.flags,0x20,false),0x40,false);p.mirrorS=false;p.mirrorT=false
  elseif op==0xAF then p.flags=setBit(setBit(p.flags,0x20,true),0x40,false);p.mirrorS=true;p.mirrorT=false
  elseif op==0xB0 then p.flags=setBit(setBit(p.flags,0x20,false),0x40,true);p.mirrorS=false;p.mirrorT=true
  elseif op==0xB1 then p.flags=setBit(setBit(p.flags,0x20,true),0x40,true);p.mirrorS=true;p.mirrorT=true
  elseif op==0xB2 then p.appSRTBaked=true
  elseif op==0xB3 then p.alphaTime,pos=readTime(d,pos);p.alphaMode,pos=u8(d,pos);p.alphaTargetStart,pos=u8(d,pos);p.alphaTargetEnd,pos=u8(d,pos)
  elseif op==0xB4 then p.flags=setBit(p.flags,0x200,true);p.flag200=true
  elseif op==0xB5 then p.flags=setBit(p.flags,0x200,false);p.flag200=false
  elseif op==0xB6 then p.headingTime,pos=readTime(d,pos);local target;target,pos=f32(d,pos);p.headingSpeed=p.headingSpeed+target
  elseif op==0xB7 then local slot;slot,pos=u8(d,pos);local t=jointTarget(fx,slot);p.jointId=slot;p.jointExplicit=true;if t then p.velocity=normalizeTo({t[1]-p.position[1],t[2]-p.position[2],t[3]-p.position[3]},math.max(vecLength(p.velocity),.001)) end
  elseif op==0xB8 then local slot,force,radius;slot,pos=u8(d,pos);force,pos=f32(d,pos);radius,pos=f32(d,pos);p.jointForce={joint=slot,force=force,radius=radius};p.jointId=slot;p.jointExplicit=true
  elseif op==0xB9 then local id;id,pos=u16(d,pos);p.cmdPos=pos;spawnParticle(fx,p,id,true,false);return
  elseif op==0xBA or op==0xBB then
    local target=op==0xBA and p.prim or p.env;for i=1,4 do local v;v,pos=s8(d,pos);target[i]=clamp(target[i]+signedRandomDelta(p,math.abs(v)),0,255) end
  elseif op==0xBC then local base,range;base,pos=u8(d,pos);range,pos=u8(d,pos);p.objRefIndex=base+(range>0 and math.floor(range*p.random()) or 0);p.textureIndex=p.objRefIndex;p.textureOff=false;p.flags=p.flags+((not hasBit(p.flags,0x400)) and 0x400 or 0)
  elseif op==0xBD then local base,range;base,pos=f32(d,pos);range,pos=f32(d,pos);p.velocity=normalizeTo(p.velocity,base+range*p.random())
  elseif op==0xBE then local x,y,z;x,pos=f32(d,pos);y,pos=f32(d,pos);z,pos=f32(d,pos);p.velocity[1]=p.velocity[1]*x;p.velocity[2]=p.velocity[2]*y;p.velocity[3]=p.velocity[3]*z
  elseif op==0xBF then p.cameraSlot,pos=u8(d,pos)
  elseif op>=0xC0 and op<=0xCF then
    finishColor(p.prim,p.primTarget,p.primTime);p.primTime,pos=readTime(d,pos);p.primTarget={p.prim[1],p.prim[2],p.prim[3],p.prim[4]};local m=op-0xC0
    for i=1,4 do if hasBit(m,2^(i-1)) then p.primTarget[i],pos=u8(d,pos) end end;if p.primTime==0 then p.prim={p.primTarget[1],p.primTarget[2],p.primTarget[3],p.primTarget[4]} end
  elseif op>=0xD0 and op<=0xDF then
    finishColor(p.env,p.envTarget,p.envTime);p.envTime,pos=readTime(d,pos);p.envTarget={p.env[1],p.env[2],p.env[3],p.env[4]};local m=op-0xD0
    for i=1,4 do if hasBit(m,2^(i-1)) then p.envTarget[i],pos=u8(d,pos) end end;if p.envTime==0 then p.env={p.envTarget[1],p.envTarget[2],p.envTarget[3],p.envTarget[4]} end
  elseif op==0xE0 then for i=1,4 do local v;v,pos=s8(d,pos);local delta=signedRandomDelta(p,math.abs(v));p.prim[i]=clamp(p.prim[i]+delta,0,255);p.env[i]=clamp(p.env[i]+delta,0,255) end
  elseif op==0xE1 then p.callbackId,pos=u8(d,pos)
  elseif op==0xE2 then p.flag8=true
  elseif op==0xE3 then p.pad0B,pos=u8(d,pos)
  elseif op==0xE4 then local mode;mode,pos=u8(d,pos);p.flipS=(mode==1) or (mode>1 and p.random()>.5)
  elseif op==0xE5 then local mode;mode,pos=u8(d,pos);p.flipT=(mode==1) or (mode>1 and p.random()>.5)
  elseif op==0xE6 then p.flags=setBit(p.flags,0x200000,true);p.dirVec=true
  elseif op==0xE7 then p.flags=setBit(p.flags,0x200000,false);p.dirVec=false
  elseif op==0xE8 then
    local alpha;alpha,pos=f32(d,pos)
    if alpha<0 then p.flags=setBit(p.flags,0x100000,false);p.trail=false;p.alphaScale=1
    else p.flags=setBit(p.flags,0x100000,true);p.trail=true;p.alphaScale=alpha end
  elseif op==0xE9 then
    local mask,count;mask,pos=u8(d,pos);count,pos=u8(d,pos);local delta={0,0,0,0};for i=1,4 do if hasBit(mask,2^(i-1)) then delta[i],pos=s8(d,pos) end end
    local function apply(c) for i=1,4 do c[i]=clamp(c[i]+signedRandomDelta(p,math.abs(delta[i])),0,255) end end
    if hasBit(mask,0x10) then apply(p.prim) end;if hasBit(mask,0x20) then apply(p.env) end;p.randomColorCount=count
  elseif op==0xEA or op==0xEB then
    local tm,flags;tm,pos=readTime(d,pos);flags,pos=u8(d,pos);local rgb,alpha;if hasBit(flags,1) then rgb,pos=u8(d,pos) end;if hasBit(flags,8) then alpha,pos=u8(d,pos) end
    p.channelSize=p.channelSize or {};p.channelSize[op==0xEA and "x" or "y"]={time=tm,flags=flags,rgb=rgb,alpha=alpha}
  elseif op==0xEC then local idx,v;idx,pos=u8(d,pos);v,pos=f32(d,pos);p.custom=p.custom or {};p.custom[idx]=v
  elseif op==0xED then local base,range,count;base,pos=f32(d,pos);range,pos=f32(d,pos);count,pos=u8(d,pos);local delta=base+range*p.random();p.headingSpeed=p.headingSpeed+delta;p.heading=p.heading+delta;p.headingRandomCount=count
  elseif op==0xEF or op==0xF0 then local id,flags;id,pos=u16(d,pos);flags,pos=u8(d,pos);p.cmdPos=pos;spawnGenerator(fx,p,id,false);p.spawnFlags=flags;return
  elseif op==0xF1 then local idx;idx,pos=u16(d,pos);p.cmdPos=pos;spawnGenerator(fx,p,idx,true);return
  elseif op==0xF2 then local idx;idx,pos=u16(d,pos);p.cmdPos=pos;spawnParticle(fx,p,idx,true,true);return
  elseif op==0xF3 then local reverse,rate,accel,tm;reverse,pos=u8(d,pos);rate,pos=f32(d,pos);accel,pos=f32(d,pos);tm,pos=readTime(d,pos);p.headingSpeed=p.headingSpeed+((reverse~=0) and -rate or rate);p.headingAccel=accel;p.headingTime=tm
  elseif op==0xF4 then p.generatorDirection={};for i=1,4 do p.generatorDirection[i],pos=f32(d,pos) end
  elseif op==0xF5 then p.generatorTrack2000=true
  elseif op==0xF6 then p.generatorTrack1000=true
  elseif op==0xF7 then p.noZComp=true
  elseif op==0xFA then p.loopCount,pos=u8(d,pos);p.loopPos=pos
  elseif op==0xFB then p.loopCount=(p.loopCount or 0)-1;if p.loopCount>0 then pos=p.loopPos or pos end
  elseif op==0xFC then p.savedPC=pos
  elseif op==0xFD then pos=p.savedPC or pos
  else addFault(fx,"opcode",string.format("0x%02X",op));p.alive=false
  end
  p.cmdPos=math.min(pos,#d+1)
end

local function executeParticle(p,fx)
  local d=p.data;local guard=0
  while p.alive and p.cmdPos<=#d and guard<MAX_COMMANDS_PER_FRAME do
    guard=guard+1;local op;op,p.cmdPos=u8(d,p.cmdPos)
    if op<0x80 then
      local delay=op%32;if hasBit(op,0x20) then local x;x,p.cmdPos=u8(d,p.cmdPos);delay=delay*256+x end
      if hasBit(op,0x40) then p.objRefIndex,p.cmdPos=u8(d,p.cmdPos);p.textureIndex=p.objRefIndex;p.textureOff=false end
      if delay>0 then p.wait=delay;return end
    elseif op==0xFE or op==0xFF then p.repeatCount=1;return
    else local r=executeComplex(p,fx,op);if r=="yield" then return end end
  end
  if guard>=MAX_COMMANDS_PER_FRAME then addFault(fx,"command-guard",p.scriptId);p.alive=false end
end

local function stepParticle(p,fx)
  if not p.alive then return end;p.frame=p.frame+1
  if p.wait>0 then p.wait=p.wait-1 end;if p.wait==0 then executeParticle(p,fx) end;if not p.alive then return end
  if p.jointForce then
    local t=jointTarget(fx,p.jointForce.joint);if t then local d={t[1]-p.position[1],t[2]-p.position[2],t[3]-p.position[3]};local dist=vecLength(d);local radius=math.abs(tonumber(p.jointForce.radius) or 0)
      if radius<=0 or dist<=radius then local k=(tonumber(p.jointForce.force) or 0)/math.max(dist,1e-6);for i=1,3 do p.velocity[i]=p.velocity[i]+d[i]*k end end end
  end
  -- GX particle physics is opt-in: an unused zero friction field is NOT a
  -- request to erase velocity. A2/A3 above update the same low flag bits.
  if hasBit(p.flags,1) then p.velocity[2]=p.velocity[2]-(p.scaleFactor or 0) end
  if hasBit(p.flags,2) then for i=1,3 do p.velocity[i]=p.velocity[i]*(p.frictionFactor or 1) end end
  for i=1,3 do p.position[i]=p.position[i]+p.velocity[i] end
  if p.sizeTime>0 then local q=1/p.sizeTime;p.size=p.size+(p.sizeTarget-p.size)*q;p.sizeTime=p.sizeTime-1;if p.sizeTime==0 then p.size=p.sizeTarget end end
  p.primTime=interpColor(p.prim,p.primTarget,p.primTime);p.envTime=interpColor(p.env,p.envTarget,p.envTime)
  if p.alphaTime>0 then p.alphaTime=p.alphaTime-1;if p.alphaTime==0 then p.alphaStart=p.alphaTargetStart;p.alphaEnd=p.alphaTargetEnd end end
  if p.headingTime>0 then p.heading=p.heading+p.headingSpeed;p.headingSpeed=p.headingSpeed+p.headingAccel;p.headingTime=p.headingTime-1 end
  p.rotation=p.heading
  if p.trail then p.history=p.history or {};table.insert(p.history,1,{p.position[1],p.position[2],p.position[3]});while #p.history>12 do table.remove(p.history) end end
  p.repeatCount=(p.repeatCount or 1)-1;if p.repeatCount<=0 then p.alive=false end
end

local function stepGenerator(g,fx)
  if not g.alive then return end;g.age=g.age+1
  -- A finite generator stops emitting at its own authored lifetime; its
  -- particles (and late children) retain their own lifetimes after that.
  if not g.emissionStopped and g.maxLife<=0 and fx.frame>fx.sourceEndFrame then
    g.emissionStopped=true;g.rate=0;g.accumulator=0
  end
  if not g.emissionStopped then
    local rate=g.rate or 0
    if rate<0 then g.accumulator=g.accumulator-rate else g.accumulator=g.accumulator+rate*g.random() end
    local emitted=0
    while g.accumulator>=1 and emitted<MAX_EMIT_PER_FRAME and #fx.particles<MAX_TOTAL_PARTICLES do
      emitGeneratorParticle(fx,g);g.accumulator=g.accumulator-1;emitted=emitted+1
    end
    if g.maxLife>0 then
      g.maxLife=g.maxLife-1
      if g.maxLife<=0 then g.emissionStopped=true;g.rate=0;g.accumulator=0 end
    end
  end
  if g.emissionStopped and g.childCount<=0 then g.alive=false end
end

local function safeFrame(v) v=tonumber(v);if not v or v<0 or v>7200 then return 0 end;return math.floor(v+.5) end
function M.start(spec,opts)
  opts=type(opts)=="table" and opts or {};local role=tostring(opts.role or "attack")
  local fx={spec=spec,role=role,age=0,frame=0,accumulator=0,particles={},generators={},emitters={},templates={},templateById={},joints=opts.joints or {},spawnSerial=0,done=false,opcodeFaults={}}
  local entry=type(opts.entry)=="table" and opts.entry or nil;local root=selectRoot(spec,entry,role)
  for i,g in ipairs(type(spec)=="table" and (spec.generatorPrograms or {}) or {}) do
    if executable(g,role,entry) then local t={gen=g,index=i,data=hexToBytes(g.commandHex or ""),autoRoot=(g==root)};fx.templates[#fx.templates+1]=t;fx.templateById[templateKey(g.bank,g.scriptId~=nil and g.scriptId or g.bankIndex)]=t end
  end
  if root then
    local t=fx.templateById[templateKey(root.bank,root.scriptId~=nil and root.scriptId or root.bankIndex)]
    local start=(entry and opts.sequenceStartHandled) and 0 or safeFrame(root.sequence and root.sequence.start);fx.rootStartFrame=start
    if start<=0 then newGenerator(fx,t,{0,0,0},nil) else fx.pendingRoot=t end
  end
  local duration=tonumber(opts.sourceDurationFrames)
  if not duration or duration<=0 then
    duration=0;for _,g in ipairs(type(spec)=="table" and (spec.generatorPrograms or {}) or {}) do if phaseRole(g.phase)==role then duration=math.max(duration,tonumber(g.maxLife) or 0) end end
    if duration<=0 then duration=math.ceil((tonumber(spec and spec.duration) or 2)*60) end
  end
  fx.sourceEndFrame=math.max(1,math.min(MAX_EFFECT_SECONDS*60,duration))
  fx.hardEndFrame=MAX_EFFECT_SECONDS*60
  return fx
end
function M.update(fx,dt)
  if type(fx)~="table" or fx.done then return false end;local step=math.max(0,tonumber(dt) or 0);fx.age=fx.age+step;fx.accumulator=fx.accumulator+step;local steps=0
  while fx.accumulator+1e-10>=FRAME_DT and steps<MAX_STEPS_PER_UPDATE do
    fx.accumulator=fx.accumulator-FRAME_DT;steps=steps+1;fx.frame=fx.frame+1
    if fx.pendingRoot and fx.frame>=fx.rootStartFrame then newGenerator(fx,fx.pendingRoot,{0,0,0},nil);fx.pendingRoot=nil end
    for _,g in ipairs(fx.generators) do stepGenerator(g,fx) end
    for i=#fx.particles,1,-1 do
      local p=fx.particles[i];stepParticle(p,fx)
      if not p.alive then
        if p.generator then p.generator.childCount=math.max(0,(p.generator.childCount or 1)-1) end
        table.remove(fx.particles,i)
      end
    end
    for i=#fx.generators,1,-1 do if not fx.generators[i].alive then table.remove(fx.generators,i) end end;fx.emitters=fx.generators
  end
  if #fx.generators==0 and #fx.particles==0 and not fx.pendingRoot and fx.frame>0 then
    fx.done=true;fx.finishReason="source-objects-drained"
  elseif fx.frame>=fx.hardEndFrame then
    fx.done=true;fx.finishReason="particle-watchdog";fx.truncated=true
    addFault(fx,"particle-watchdog",fx.frame)
  end
  return not fx.done
end
function M.visibleParticles(fx) return type(fx)=="table" and fx.particles or {} end
function M.status(fx) if type(fx)~="table" then return nil end;return {role=fx.role,age=fx.age,frame=fx.frame,templates=#fx.templates,generators=#fx.generators,emitters=#fx.generators,particles=#fx.particles,done=fx.done,finishReason=fx.finishReason,truncated=fx.truncated==true,sourceEndFrame=fx.sourceEndFrame,hardEndFrame=fx.hardEndFrame,opcodeFaults=fx.opcodeFaults} end
M._test={hexToBytes=hexToBytes,selectRoot=selectRoot,lookupScriptId=lookupScriptId}
return M
