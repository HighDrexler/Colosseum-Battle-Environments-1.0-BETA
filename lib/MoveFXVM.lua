local M={version=8,source="GC6E01 GPT1 handler runtime for WazaSequence scheduler"}

-- Runtime interpreter for the subset of Colosseum's GPT1 particle bytecode that
-- directly controls visible particle state. Extraction preserves each generator
-- header + command stream; this module executes those source commands at 60 Hz.
-- It never invents move-type/projectile/wave choreography. Unsupported opcodes
-- are skipped conservatively so a malformed/unknown command fails at the one
-- generator instead of taking the battle renderer down.

local FRAME_DT=1/60
local MAX_PARTICLES_PER_GENERATOR=24
local MAX_TOTAL_PARTICLES=384
local MAX_STEPS_PER_UPDATE=30
local MAX_COMMANDS_PER_FRAME=192
local MAX_EFFECT_SECONDS=8.0

local function hasBit(v,bit) return math.floor((tonumber(v) or 0)/bit)%2>=1 end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function vecLength(v)
  local x,y,z=tonumber(v and v[1]) or 0,tonumber(v and v[2]) or 0,tonumber(v and v[3]) or 0
  return math.sqrt(x*x+y*y+z*z)
end
local function normalizeTo(v,length)
  local n=vecLength(v)
  if n<1e-9 then return {0,0,tonumber(length) or 0} end
  local k=(tonumber(length) or 0)/n
  return {(v[1] or 0)*k,(v[2] or 0)*k,(v[3] or 0)*k}
end


local function hexToBytes(hex)
  if type(hex)~="string" or hex=="" then return "" end
  local out={}
  for i=1,#hex-1,2 do
    local n=tonumber(hex:sub(i,i+1),16)
    if not n then break end
    out[#out+1]=string.char(n)
  end
  return table.concat(out)
end

local function u8(data,pos)
  if pos>#data then return 0,#data+1 end
  return data:byte(pos) or 0,pos+1
end
local function u16(data,pos)
  local a,b=data:byte(pos,pos+1)
  if not b then return 0,#data+1 end
  return a*256+b,pos+2
end
local function u32(data,pos)
  local a,b,c,d=data:byte(pos,pos+3)
  if not d then return 0,#data+1 end
  return ((a*256+b)*256+c)*256+d,pos+4
end
local function f32(data,pos)
  local bits,nextPos=u32(data,pos)
  local sign=bits>=2147483648 and -1 or 1
  if bits>=2147483648 then bits=bits-2147483648 end
  local exp=math.floor(bits/8388608)
  local mant=bits-exp*8388608
  if exp==255 then
    if mant==0 then return sign*1e30,nextPos end
    return 0,nextPos
  elseif exp==0 then
    if mant==0 then return 0,nextPos end
    return sign*(mant/8388608)*(2^-126),nextPos
  end
  return sign*(1+mant/8388608)*(2^(exp-127)),nextPos
end
local function readTime(data,pos)
  local b;b,pos=u8(data,pos)
  if b>=128 then
    local b2;b2,pos=u8(data,pos)
    return (b-128)*256+b2,pos
  end
  return b,pos
end

local function rng(seed)
  seed=math.floor(math.abs(tonumber(seed) or 1))%2147483647
  if seed==0 then seed=1 end
  return function()
    seed=(seed*16807)%2147483647
    return seed/2147483647
  end
end

local function phaseRole(phase)
  phase=tostring(phase or "all"):lower()
  if phase=="damage" or phase=="status" then return "damage" end
  return "attack"
end


-- Validate command framing before CBE claims native move-visual ownership. The
-- VM can intentionally no-op several known rendering-only commands, but it must
-- know each command's argument length; otherwise one unsupported opcode would
-- desynchronize the byte stream and could turn arbitrary argument bytes into
-- fake particle commands while the native animation is already suppressed.
local function programSupported(commandHex)
  local data=hexToBytes(commandHex)
  if data=="" then return false end
  local pos=1
  local function need(n)
    if pos+n-1>#data then return false end
    pos=pos+n;return true
  end
  local function timeArg()
    if pos>#data then return false end
    local b=data:byte(pos) or 0;pos=pos+1
    if b>=128 then return need(1) end
    return true
  end
  local function bitCount3(mask)
    local n=0;if hasBit(mask,1) then n=n+1 end;if hasBit(mask,2) then n=n+1 end;if hasBit(mask,4) then n=n+1 end;return n
  end
  local function bitCount4(mask)
    local n=bitCount3(mask);if hasBit(mask,8) then n=n+1 end;return n
  end
  local guard=0
  while pos<=#data and guard<4096 do
    guard=guard+1
    local op=data:byte(pos);pos=pos+1
    if op<0x80 then
      if hasBit(op,32) and not need(1) then return false end
      if hasBit(op,64) and not need(1) then return false end
    elseif op>=0x80 and op<=0x9F then
      if not need(bitCount3(op%8)*4) then return false end
    elseif op==0xA0 or op==0xAC or op==0xB6 then
      if not timeArg() or not need(4) then return false end
    elseif op==0xA1 or op==0xAD or (op>=0xAE and op<=0xB2)
        or op==0xB4 or op==0xB5 or op==0xE2 or op==0xE6 or op==0xE7
        or op==0xF5 or op==0xF6 or op==0xF7
        or op==0xFB or op==0xFC or op==0xFD or op==0xFE or op==0xFF then
      -- known no-argument commands. E2/E6/E7 alter particle render/orientation
      -- flags only, so CBE can preserve command framing even before those GX
      -- presentation details are mirrored one-for-one.
    elseif op==0xA2 or op==0xA3 or op==0xA9 or op==0xAB or op==0xE0 or op==0xE8 then
      if not need(4) then return false end
    elseif op==0xA4 or op==0xA5 or op==0xB9 or op==0xF1 or op==0xF2 then
      if not need(2) then return false end
    elseif op==0xA6 or op==0xAA then
      if not need(4) then return false end
    elseif op==0xA7 or op==0xB7 or op==0xBF or op==0xE1 or op==0xE3 or op==0xE4 or op==0xE5 or op==0xFA then
      if not need(1) then return false end
    elseif op==0xA8 or op==0xBE then
      if not need(12) then return false end
    elseif op==0xB3 then
      if not timeArg() or not need(3) then return false end
    elseif op==0xB8 then
      if not need(9) then return false end
    elseif op==0xBA or op==0xBB then
      if not need(4) then return false end
    elseif op==0xBC then
      if not need(2) then return false end
    elseif op==0xBD then
      if not need(8) then return false end
    elseif op>=0xC0 and op<=0xCF then
      if not timeArg() or not need(bitCount4(op-0xC0)) then return false end
    elseif op>=0xD0 and op<=0xDF then
      if not timeArg() or not need(bitCount4(op-0xD0)) then return false end
    elseif op==0xE9 then
      if not need(2) then return false end
      local flags=data:byte(pos-2) or 0
      if not need(bitCount4(flags)) then return false end
    elseif op==0xEA or op==0xEB then
      if not timeArg() or not need(1) then return false end
      local flags=data:byte(pos-1) or 0
      local n=(hasBit(flags,1) and 1 or 0)+(hasBit(flags,8) and 1 or 0)
      if not need(n) then return false end
    elseif op==0xEC then
      if not need(5) then return false end
    elseif op==0xED then
      if not need(9) then return false end
    elseif op==0xEF or op==0xF0 then
      if not need(3) then return false end
    elseif op==0xF3 then
      if not need(9) or not timeArg() then return false end
    elseif op==0xF4 then
      if not need(16) then return false end
    else
      return false
    end
  end
  return guard<4096 and pos==#data+1
end

function M.programSupported(commandHex) return programSupported(commandHex) end

-- A WZX root can either be a normal particle-emitting generator or a tiny
-- controller program whose job is to spawn child generators.  Treating the
-- latter's maxParticles field as an automatic emission count multiplies the
-- whole source program (Flame Wheel's root is the clearest case) and floods
-- the renderer.  Walk only an already frame-safe command stream and identify
-- source spawn opcodes at instruction boundaries -- never by searching raw
-- bytes, since an opcode-looking byte may legitimately occur inside a float.
local function programSpawnsChildren(commandHex)
  if not programSupported(commandHex) then return false end
  local data=hexToBytes(commandHex)
  local pos=1
  local function take(n) pos=math.min(#data+1,pos+n) end
  local function timeArg()
    local b;b,pos=u8(data,pos)
    if b>=128 then take(1) end
  end
  local function count3(mask)
    local n=0;if hasBit(mask,1) then n=n+1 end;if hasBit(mask,2) then n=n+1 end;if hasBit(mask,4) then n=n+1 end;return n
  end
  local function count4(mask) local n=count3(mask);if hasBit(mask,8) then n=n+1 end;return n end
  local guard=0
  while pos<=#data and guard<4096 do
    guard=guard+1
    local op;op,pos=u8(data,pos)
    if op==0xA4 or op==0xA5 or op==0xAA or op==0xB9
        or op==0xEF or op==0xF0 or op==0xF1 or op==0xF2 then
      return true
    end
    if op<0x80 then
      if hasBit(op,32) then take(1) end
      if hasBit(op,64) then take(1) end
    elseif op>=0x80 and op<=0x9F then take(count3(op%8)*4)
    elseif op==0xA0 or op==0xAC or op==0xB6 then timeArg();take(4)
    elseif op==0xA1 or op==0xAD or (op>=0xAE and op<=0xB2)
        or op==0xB4 or op==0xB5 or op==0xE2 or op==0xE6 or op==0xE7
        or op==0xF5 or op==0xF6 or op==0xF7
        or op==0xFB or op==0xFC or op==0xFD or op==0xFE or op==0xFF then
    elseif op==0xA2 or op==0xA3 or op==0xA9 or op==0xAB or op==0xE0 or op==0xE8 then take(4)
    elseif op==0xA4 or op==0xA5 or op==0xB9 or op==0xF1 or op==0xF2 then take(2)
    elseif op==0xA6 or op==0xAA then take(4)
    elseif op==0xA7 or op==0xB7 or op==0xBF or op==0xE1 or op==0xE3 or op==0xE4 or op==0xE5 or op==0xFA then take(1)
    elseif op==0xA8 or op==0xBE then take(12)
    elseif op==0xB3 then timeArg();take(3)
    elseif op==0xB8 then take(9)
    elseif op==0xBA or op==0xBB then take(4)
    elseif op==0xBC then take(2)
    elseif op==0xBD then take(8)
    elseif op>=0xC0 and op<=0xCF then timeArg();take(count4(op-0xC0))
    elseif op>=0xD0 and op<=0xDF then timeArg();take(count4(op-0xD0))
    elseif op==0xE9 then
      local flags;flags,pos=u8(data,pos);take(1);take(count4(flags))
    elseif op==0xEA or op==0xEB then
      timeArg();local flags;flags,pos=u8(data,pos);take((hasBit(flags,1) and 1 or 0)+(hasBit(flags,8) and 1 or 0))
    elseif op==0xEC then take(5)
    elseif op==0xED then take(9)
    elseif op==0xEF or op==0xF0 then take(3)
    elseif op==0xF3 then take(9);timeArg()
    elseif op==0xF4 then take(16)
    else return false end
  end
  return false
end

function M.programSpawnsChildren(commandHex) return programSpawnsChildren(commandHex) end

function M.hasRole(spec,role)
  if type(spec)~="table" then return false end
  local textureBanks={}
  for _,t in ipairs(spec.textures or {}) do textureBanks[tonumber(t.bank) or 1]=true end
  for _,g in ipairs(spec.generatorPrograms or {}) do
    local bank=tonumber(g.bank) or 1
    if phaseRole(g.phase)==role and g.root==true and type(g.commandHex)=="string" and #g.commandHex>=2
        and textureBanks[bank] and programSupported(g.commandHex) then return true end
  end
  return false
end

local function matchesEntry(gen,entry)
  if type(entry)~="table" then return true end
  if entry.gptOffset~=nil and gen.gptOffset~=nil
      and tonumber(entry.gptOffset)~=tonumber(gen.gptOffset) then return false end
  if entry.sourceBank~=nil and gen.sourceBank~=nil
      and tonumber(entry.sourceBank)~=tonumber(gen.sourceBank) then return false end
  -- For a scheduler-selected type-3 row, rootRef names the generator that this
  -- SequenceEntry starts.  gen.rootRef describes the owner GPT1's *original*
  -- root and is therefore wrong for later rows that reuse the same bank.
  if entry.rootRef~=nil and gen.refId~=nil
      and tonumber(entry.rootRef)~=tonumber(gen.refId) then return false end
  return true
end

local function entrySelectsGenerator(gen,entry)
  if type(entry)~="table" then return gen.root==true end
  if not matchesEntry(gen,entry) then return false end
  if entry.rootRef~=nil and gen.refId~=nil then
    return tonumber(entry.rootRef)==tonumber(gen.refId)
  end
  return gen.root==true
end

function M.hasEntry(spec,entry,role)
  if type(spec)~="table" or type(entry)~="table" then return false end
  role=tostring(role or phaseRole(entry.phase))
  local textureBanks={}
  for _,t in ipairs(spec.textures or {}) do textureBanks[tonumber(t.bank) or 1]=true end
  for _,g in ipairs(spec.generatorPrograms or {}) do
    local bank=tonumber(g.bank) or 1
    if phaseRole(g.phase)==role and entrySelectsGenerator(g,entry)
        and type(g.commandHex)=="string" and #g.commandHex>=2
        and textureBanks[bank] and programSupported(g.commandHex) then return true end
  end
  return false
end

local function safeSequenceFrame(value)
  value=tonumber(value)
  -- WZX sequence start/hit/finish fields are signed frame-domain values in the
  -- files CBE targets. Negative values are sentinels; absurd values are treated
  -- as unavailable rather than delaying a move for minutes.
  if not value or value<0 or value>3600 then return 0 end
  return math.floor(value+.5)
end

-- Generator parameter interpretation follows the known Colosseum emitter
-- heuristic used by the reference importer. Runtime bytecode then becomes
-- authoritative for all subsequent motion/state.
local function initialState(gen,random)
  local params=gen.params or {}
  local gravity=tonumber(params[1]) or 0
  if math.abs(gravity)>1e-6 then
    local speed=math.abs(tonumber(params[12]) or 0)>1e-6 and (tonumber(params[12]) or .5) or .5
    local sx=math.abs(tonumber(params[8]) or 0)>1e-6 and (tonumber(params[8]) or 1) or 1
    local sy=math.abs(tonumber(params[10]) or 0)>1e-6 and (tonumber(params[10]) or 1) or 1
    local sz=math.abs(tonumber(params[9]) or 0)>1e-6 and (tonumber(params[9]) or 1) or 1
    local angle=random()*math.pi*2
    local spread=random()*.3
    return {0,0,0},{
      math.sin(angle)*spread*sx*speed,
      speed*sy*(.5+.5*random()),
      math.cos(angle)*spread*sz*speed,
    },gravity
  end
  local rx=math.abs(tonumber(params[10]) or 0)>1e-6 and (tonumber(params[10]) or 1) or 1
  local ry=math.abs(tonumber(params[11]) or 0)>1e-6 and (tonumber(params[11]) or 1) or 1
  local rz=math.abs(tonumber(params[12]) or 0)>1e-6 and (tonumber(params[12]) or 1) or 1
  return {(random()*2-1)*rx,(random()*2-1)*ry,(random()*2-1)*rz},
    {(random()*2-1)*.01,(random()*2-1)*.01,(random()*2-1)*.01},gravity
end

local function add3(a,b)
  return {(a and a[1] or 0)+(b and b[1] or 0),
    (a and a[2] or 0)+(b and b[2] or 0),
    (a and a[3] or 0)+(b and b[3] or 0)}
end

local function newParticle(fx,emitter,position,velocity)
  -- Source programs can recursively spawn referenced particles/generators.
  -- Keep the VM bounded, but preserve the distinction: a generator instance
  -- schedules its own particles while a particle-spawn opcode creates exactly
  -- one particle immediately.
  if #fx.particles>=MAX_TOTAL_PARTICLES then return nil end
  local gen=emitter.gen
  local random=emitter.random
  local pos,vel,gravity
  if position then
    pos={position[1] or 0,position[2] or 0,position[3] or 0}
    vel={velocity and velocity[1] or 0,velocity and velocity[2] or 0,velocity and velocity[3] or 0}
    gravity=tonumber(gen.params and gen.params[1]) or 0
  else
    pos,vel,gravity=initialState(gen,random)
    if emitter.origin then pos=add3(pos,emitter.origin) end
    if emitter.baseVelocity then vel=add3(vel,emitter.baseVelocity) end
  end
  local flags=tonumber(gen.flags) or 0
  local p={
    alive=true,frame=0,bank=gen.bank or 1,generator=gen.index or emitter.index,
    position=pos,velocity=vel,gravity=gravity,friction=1,
    applyGravity=hasBit(flags,0x00000001),applyFriction=hasBit(flags,0x00000002),
    size=1,sizeTarget=1,sizeTime=0,
    rotation=0,rotRate=0,rotAccel=0,rotTime=0,
    prim={255,255,255,255},primTarget={255,255,255,255},primTime=0,
    env={0,0,0,0},envTarget={0,0,0,0},envTime=0,
    flags=flags,texEdge=hasBit(flags,0x8),mirrorS=hasBit(flags,0x20),mirrorT=hasBit(flags,0x40),
    primEnv=hasBit(flags,0x80),nearest=hasBit(flags,0x200),
    textureIndex=-1,textureOff=not hasBit(flags,0x400),
    jointId=math.floor(flags/0x1000)%8,updateJoint=hasBit(flags,0x8000),jointExplicit=(math.floor(flags/0x1000)%8)~=0 or hasBit(flags,0x8000),
    flipS=hasBit(flags,0x40000),flipT=hasBit(flags,0x80000),
    trail=hasBit(flags,0x100000),trailLength=hasBit(flags,0x100000) and 1 or 0,history={},
    dirVec=hasBit(flags,0x200000),blendMode=math.floor(flags/0x400000)%4,
    noZComp=hasBit(flags,0x10000000),lighting=hasBit(flags,0x80000000),
    cmdPos=1,wait=0,loopCount=0,loopPos=1,jumpPos=1,random=random,data=emitter.data or "",
  }
  if emitter.inherit then
    p.jointId=emitter.inherit.jointId or p.jointId
    p.updateJoint=emitter.inherit.updateJoint or p.updateJoint
    p.jointExplicit=emitter.inherit.jointExplicit or p.jointExplicit
    p.generatorDirection=emitter.inherit.generatorDirection
  end
  fx.particles[#fx.particles+1]=p
  return p
end

local function findTemplateForRef(fx,bank,ref)
  ref=tonumber(ref)
  if not ref then return nil end
  for _,e in ipairs(fx.templates or {}) do
    if e.gen.bank==bank and tonumber(e.gen.refId)==ref then return e end
  end
  -- Some files use a generator ordinal rather than the REF id.
  local ordinal=ref+1
  for _,e in ipairs(fx.templates or {}) do
    if e.gen.bank==bank and tonumber(e.gen.bankIndex)==ordinal then return e end
  end
  return nil
end

local function emitterInstance(fx,template,startFrame,origin,velocity,parent)
  if not template or #(fx.emitters or {})>=MAX_TOTAL_PARTICLES then return nil end
  fx.spawnSerial=(fx.spawnSerial or 0)+1
  local gen=template.gen
  local life=math.max(1,tonumber(gen.lifetime) or 1)
  local maxp=math.max(1,tonumber(gen.maxParticles) or 1)
  local controller=programSpawnsChildren(gen.commandHex)
  local count=controller and 1 or math.min(MAX_PARTICLES_PER_GENERATOR,maxp)
  local seed=(tonumber(gen.bank) or 1)*7919+(tonumber(gen.bankIndex) or template.index or 1)*104729+fx.spawnSerial*97
  local e={gen=gen,index=template.index,data=template.data,random=rng(seed),
    autoRoot=template.autoRoot==true,controllerRoot=controller,
    startFrame=math.max(0,tonumber(startFrame) or fx.frame or 0),
    emitted=0,emitCount=count,emitInterval=count>0 and math.max(1,math.floor(life/count)) or 1,
    nextEmitFrame=0,origin=origin and {origin[1] or 0,origin[2] or 0,origin[3] or 0} or nil,
    baseVelocity=velocity and {velocity[1] or 0,velocity[2] or 0,velocity[3] or 0} or nil,
    inherit=parent and {jointId=parent.jointId,updateJoint=parent.updateJoint,
      jointExplicit=parent.jointExplicit,generatorDirection=parent.generatorDirection} or nil,
  }
  fx.emitters[#fx.emitters+1]=e
  return e
end

local function spawnParticleRef(fx,parent,ref,inheritVelocity)
  local template=findTemplateForRef(fx,parent.bank,ref)
  if not template then return nil end
  fx.spawnSerial=(fx.spawnSerial or 0)+1
  local seed=(tonumber(template.gen.bank) or 1)*7919+(tonumber(template.gen.bankIndex) or template.index or 1)*104729+fx.spawnSerial*97
  local source={gen=template.gen,index=template.index,data=template.data,random=rng(seed),
    inherit={jointId=parent.jointId,updateJoint=parent.updateJoint,
      jointExplicit=parent.jointExplicit,generatorDirection=parent.generatorDirection}}
  local vel=inheritVelocity and parent.velocity or {0,0,0}
  return newParticle(fx,source,parent.position,vel)
end

local function spawnGeneratorRef(fx,parent,ref,inheritVelocity)
  local template=findTemplateForRef(fx,parent.bank,ref)
  if not template then return nil end
  local vel=inheritVelocity and parent.velocity or {0,0,0}
  return emitterInstance(fx,template,fx.frame,parent.position,vel,parent)
end

local function jointTarget(fx,id)
  id=tonumber(id)
  local joints=fx and fx.joints
  if not (id and type(joints)=="table") then return nil end
  return joints[id] or joints[id+1]
end

local function applyFlipMode(current,mode,random)
  mode=tonumber(mode) or 0
  if mode==0 then return false end
  if mode==1 then return true end
  if mode==2 then return not current end
  return random()>=0.5
end

local function randomizeColor(p,color,args)
  for i=1,4 do
    local span=tonumber(args[i]) or 0
    if span>0 then color[i]=clamp(math.floor(color[i]-(p.random()*span)+.5),0,255) end
  end
end

local function finishColor(color,target,time)
  if time and time>0 then for i=1,4 do color[i]=target[i] end end
end

local function skipUnknown(p,data,op,fx)
  local pos=p.cmdPos
  if op==0xA4 or op==0xB9 or op==0xF1 or op==0xF2 then
    local ref;ref,pos=u16(data,pos);p.cmdPos=pos;spawnParticleRef(fx,p,ref,op==0xB9 or op==0xF2)
  elseif op==0xA5 then
    local ref;ref,pos=u16(data,pos);p.cmdPos=pos;spawnGeneratorRef(fx,p,ref,false)
  elseif op==0xA6 then
    local base,range;base,pos=u16(data,pos);range,pos=u16(data,pos)
    p.killTimer=base+math.floor(range*p.random())
  elseif op==0xA7 then
    local chance;chance,pos=u8(data,pos);if p.random()*100<chance then p.alive=false end
  elseif op==0xAA then
    local base,count;base,pos=u16(data,pos);count,pos=u16(data,pos)
    if count>0 then
      local ref=base+math.floor(p.random()*count)
      p.cmdPos=pos;spawnParticleRef(fx,p,ref,false);return
    end
  elseif op==0xB2 then
    p.applyAppSRT=true
  elseif op==0xB3 then
    local time;time,pos=readTime(data,pos);local mode,p1,p2;mode,pos=u8(data,pos);p1,pos=u8(data,pos);p2,pos=u8(data,pos)
    p.alphaCompare={time=time,mode=mode,p1=p1,p2=p2}
  elseif op==0xB7 then
    local joint;joint,pos=u8(data,pos);p.jointId=joint;p.jointExplicit=true
    local target=jointTarget(fx,joint)
    if target then
      local delta={target[1]-p.position[1],target[2]-p.position[2],target[3]-p.position[3]}
      local speed=math.max(vecLength(p.velocity),.001);p.velocity=normalizeTo(delta,speed)
    end
  elseif op==0xB8 then
    local gravity,friction,joint;gravity,pos=f32(data,pos);friction,pos=f32(data,pos);joint,pos=u8(data,pos)
    p.jointForce={gravity=gravity,friction=friction,joint=joint};p.jointId=joint;p.jointExplicit=true
  elseif op==0xBA or op==0xBB then
    local args={};for i=1,4 do args[i],pos=u8(data,pos) end
    randomizeColor(p,op==0xBA and p.prim or p.env,args)
  elseif op==0xBC then
    local base,range;base,pos=u8(data,pos);range,pos=u8(data,pos)
    p.textureIndex=base+math.floor(p.random()*math.max(0,range));p.textureOff=false
  elseif op==0xBD then
    local base,range;base,pos=f32(data,pos);range,pos=f32(data,pos)
    local speed=base+range*p.random();p.velocity=normalizeTo(p.velocity,speed)
  elseif op==0xBE then
    local x,y,z;x,pos=f32(data,pos);y,pos=f32(data,pos);z,pos=f32(data,pos)
    p.velocity[1]=p.velocity[1]*x;p.velocity[2]=p.velocity[2]*y;p.velocity[3]=p.velocity[3]*z
  elseif op==0xBF then
    p.jointId,pos=u8(data,pos);p.jointExplicit=true
  elseif op==0xE0 then
    local args={};for i=1,4 do args[i],pos=u8(data,pos) end
    randomizeColor(p,p.prim,args);randomizeColor(p,p.env,args)
  elseif op==0xE1 then p.callbackId,pos=u8(data,pos)
  elseif op==0xE3 then p.palette,pos=u8(data,pos)
  elseif op==0xE4 then local mode;mode,pos=u8(data,pos);p.flipS=applyFlipMode(p.flipS,mode,p.random)
  elseif op==0xE5 then local mode;mode,pos=u8(data,pos);p.flipT=applyFlipMode(p.flipT,mode,p.random)
  elseif op==0xE8 then
    p.trailLength,pos=f32(data,pos);p.trail=(p.trailLength or -1)>=0
  elseif op==0xE9 then
    local flags,count;flags,pos=u8(data,pos);count,pos=u8(data,pos)
    local args={0,0,0,0}
    if hasBit(flags,1) then args[1],pos=u8(data,pos) end;if hasBit(flags,2) then args[2],pos=u8(data,pos) end
    if hasBit(flags,4) then args[3],pos=u8(data,pos) end;if hasBit(flags,8) then args[4],pos=u8(data,pos) end
    randomizeColor(p,p.prim,args);randomizeColor(p,p.env,args);p.randomColorCount=count
  elseif op==0xEA or op==0xEB then
    local time,flags;time,pos=readTime(data,pos);flags,pos=u8(data,pos)
    local rgb,alpha
    if hasBit(flags,1) then rgb,pos=u8(data,pos) end;if hasBit(flags,8) then alpha,pos=u8(data,pos) end
    p.materialColor={kind=op==0xEA and "material" or "ambient",time=time,flags=flags,rgb=rgb,alpha=alpha}
  elseif op==0xEC then local idx;idx,pos=u8(data,pos);local v;v,pos=f32(data,pos);p.custom=p.custom or {};p.custom[idx]=v
  elseif op==0xEF or op==0xF0 then
    local ref;ref,pos=u16(data,pos);local flags;flags,pos=u8(data,pos);p.cmdPos=pos
    -- EF/F0 are generator-reference spawns in Colosseum. The previous VM
    -- incorrectly instantiated the referenced generator's command stream as a
    -- single particle, which skipped its lifetime/max-particle scheduler.
    spawnGeneratorRef(fx,p,ref,hasBit(flags,1));p.spawnFlags=flags;return
  elseif op==0xF4 then
    p.generatorDirection={};for i=1,4 do p.generatorDirection[i],pos=f32(data,pos) end
  elseif op==0xF5 then p.generatorTrack2000=true
  elseif op==0xF6 then p.generatorTrack1000=true
  elseif op==0xF7 then p.noZComp=true
  end
  p.cmdPos=math.min(pos,#data+1)
end

local function complex(p,data,op,fx)
  local pos=p.cmdPos
  local bits=op%8
  if op>=0x80 and op<=0x87 then
    if hasBit(bits,1) then p.position[1],pos=f32(data,pos) end
    if hasBit(bits,2) then p.position[2],pos=f32(data,pos) end
    if hasBit(bits,4) then p.position[3],pos=f32(data,pos) end
  elseif op>=0x88 and op<=0x8F then
    if hasBit(bits,1) then local v;v,pos=f32(data,pos);p.position[1]=p.position[1]+v end
    if hasBit(bits,2) then local v;v,pos=f32(data,pos);p.position[2]=p.position[2]+v end
    if hasBit(bits,4) then local v;v,pos=f32(data,pos);p.position[3]=p.position[3]+v end
  elseif op>=0x90 and op<=0x97 then
    if hasBit(bits,1) then p.velocity[1],pos=f32(data,pos) end
    if hasBit(bits,2) then p.velocity[2],pos=f32(data,pos) end
    if hasBit(bits,4) then p.velocity[3],pos=f32(data,pos) end
  elseif op>=0x98 and op<=0x9F then
    if hasBit(bits,1) then local v;v,pos=f32(data,pos);p.velocity[1]=p.velocity[1]+v end
    if hasBit(bits,2) then local v;v,pos=f32(data,pos);p.velocity[2]=p.velocity[2]+v end
    if hasBit(bits,4) then local v;v,pos=f32(data,pos);p.velocity[3]=p.velocity[3]+v end
  elseif op==0xA0 then
    p.sizeTime,pos=readTime(data,pos);p.sizeTarget,pos=f32(data,pos)
    if p.sizeTime==0 then p.size=p.sizeTarget end
  elseif op==0xA1 then p.textureOff=true
  elseif op==0xA2 then p.gravity,pos=f32(data,pos);p.applyGravity=math.abs(p.gravity)>1e-9
  elseif op==0xA3 then p.friction,pos=f32(data,pos);p.applyFriction=math.abs(p.friction-1)>1e-9
  elseif op==0xA8 then
    local x,y,z;x,pos=f32(data,pos);y,pos=f32(data,pos);z,pos=f32(data,pos)
    p.position[1]=p.position[1]+(p.random()*2-1)*x
    p.position[2]=p.position[2]+(p.random()*2-1)*y
    p.position[3]=p.position[3]+(p.random()*2-1)*z
  elseif op==0xA9 then
    local a;a,pos=f32(data,pos);local vx,vz=p.velocity[1],p.velocity[3]
    local c,s=math.cos(a),math.sin(a);p.velocity[1]=vx*c-vz*s;p.velocity[3]=vx*s+vz*c
  elseif op==0xAB then
    local f;f,pos=f32(data,pos);for i=1,3 do p.velocity[i]=p.velocity[i]*f end
  elseif op==0xAC then
    p.sizeTime,pos=readTime(data,pos);local r;r,pos=f32(data,pos)
    p.sizeTarget=p.size+r*p.random();if p.sizeTime==0 then p.size=p.sizeTarget end
  elseif op==0xAD then p.primEnv=true
  elseif op==0xAE then p.mirrorS=false;p.mirrorT=false
  elseif op==0xAF then p.mirrorS=true;p.mirrorT=false
  elseif op==0xB0 then p.mirrorS=false;p.mirrorT=true
  elseif op==0xB1 then p.mirrorS=true;p.mirrorT=true
  elseif op==0xB4 then p.nearest=true
  elseif op==0xB5 then p.nearest=false
  elseif op==0xE2 then p.texEdge=true
  elseif op==0xE6 then p.dirVec=true
  elseif op==0xE7 then p.dirVec=false
  elseif op==0xB6 then
    p.rotTime,pos=readTime(data,pos);p.rotRate,pos=f32(data,pos)
    if p.rotTime==0 then p.rotation=p.rotRate end
  elseif op>=0xC0 and op<=0xCF then
    finishColor(p.prim,p.primTarget,p.primTime)
    p.primTime,pos=readTime(data,pos);p.primTarget={p.prim[1],p.prim[2],p.prim[3],p.prim[4]}
    local mask=op-0xC0
    if hasBit(mask,1) then p.primTarget[1],pos=u8(data,pos) end
    if hasBit(mask,2) then p.primTarget[2],pos=u8(data,pos) end
    if hasBit(mask,4) then p.primTarget[3],pos=u8(data,pos) end
    if hasBit(mask,8) then p.primTarget[4],pos=u8(data,pos) end
    if p.primTime==0 then p.prim={p.primTarget[1],p.primTarget[2],p.primTarget[3],p.primTarget[4]} end
  elseif op>=0xD0 and op<=0xDF then
    finishColor(p.env,p.envTarget,p.envTime)
    p.envTime,pos=readTime(data,pos);p.envTarget={p.env[1],p.env[2],p.env[3],p.env[4]}
    local mask=op-0xD0
    if hasBit(mask,1) then p.envTarget[1],pos=u8(data,pos) end
    if hasBit(mask,2) then p.envTarget[2],pos=u8(data,pos) end
    if hasBit(mask,4) then p.envTarget[3],pos=u8(data,pos) end
    if hasBit(mask,8) then p.envTarget[4],pos=u8(data,pos) end
    if p.envTime==0 then p.env={p.envTarget[1],p.envTarget[2],p.envTarget[3],p.envTarget[4]} end
  elseif op==0xED then
    local base,range,_;base,pos=f32(data,pos);range,pos=f32(data,pos);_,pos=u8(data,pos)
    p.rotation=base+range*p.random()
  elseif op==0xF3 then
    local dir,rate,accel,time;dir,pos=u8(data,pos);rate,pos=f32(data,pos);accel,pos=f32(data,pos);time,pos=readTime(data,pos)
    p.rotRate=(dir~=0) and rate or -rate;p.rotAccel=accel;p.rotTime=time
  elseif op==0xFA then
    p.loopCount,pos=u8(data,pos);p.loopPos=pos
  elseif op==0xFB then
    p.loopCount=(p.loopCount or 0)-1
    if p.loopCount>0 then pos=p.loopPos or pos end
  elseif op==0xFC then p.jumpPos=pos
  elseif op==0xFD then pos=p.jumpPos or pos
  else
    p.cmdPos=pos;skipUnknown(p,data,op,fx);return
  end
  p.cmdPos=math.min(pos,#data+1)
end

local function execute(p,fx)
  local data=p.data
  local guard=0
  while p.alive and p.cmdPos<=#data and guard<MAX_COMMANDS_PER_FRAME do
    guard=guard+1
    local op;op,p.cmdPos=u8(data,p.cmdPos)
    if op<0x80 then
      local frames=op%32
      if hasBit(op,32) then local ext;ext,p.cmdPos=u8(data,p.cmdPos);frames=frames*256+ext end
      if hasBit(op,64) then p.textureIndex,p.cmdPos=u8(data,p.cmdPos);p.textureOff=false end
      if frames>0 then p.wait=frames;return end
    elseif op==0xFE or op==0xFF then
      p.alive=false;return
    else
      complex(p,data,op,fx)
    end
  end
  if p.cmdPos>#data or guard>=MAX_COMMANDS_PER_FRAME then p.alive=false end
end

local function interpColor(color,target,time)
  if time<=0 then return time end
  time=time-1
  if time==0 then for i=1,4 do color[i]=target[i] end
  else
    local t=1/(time+1)
    for i=1,4 do color[i]=math.floor(color[i]+(target[i]-color[i])*t+.5) end
  end
  return time
end

local function stepParticle(p,fx)
  if not p.alive then return end
  p.frame=p.frame+1
  if p.wait>0 then p.wait=p.wait-1 end
  if p.wait==0 then execute(p,fx) end
  if not p.alive then return end
  if p.killTimer then p.killTimer=p.killTimer-1;if p.killTimer<=0 then p.alive=false;return end end
  if p.trail then
    p.history=p.history or {}
    table.insert(p.history,1,{p.position[1],p.position[2],p.position[3]})
    local keep=math.max(2,math.min(18,math.floor(math.abs(tonumber(p.trailLength) or 1)*4+.5)))
    while #p.history>keep do table.remove(p.history) end
  end
  if p.jointForce then
    local target=jointTarget(fx,p.jointForce.joint)
    if target then
      local dx,dy,dz=target[1]-p.position[1],target[2]-p.position[2],target[3]-p.position[3]
      local dist=math.sqrt(dx*dx+dy*dy+dz*dz)
      if dist<.08 then p.alive=false;return end
      local k=(tonumber(p.jointForce.gravity) or 0)/math.max(dist,1e-6)
      p.velocity[1]=p.velocity[1]+dx*k;p.velocity[2]=p.velocity[2]+dy*k;p.velocity[3]=p.velocity[3]+dz*k
      local jf=tonumber(p.jointForce.friction) or 1
      for i=1,3 do p.velocity[i]=p.velocity[i]*jf end
    end
  end
  if p.applyGravity then p.velocity[2]=p.velocity[2]+p.gravity end
  if p.applyFriction and p.friction~=1 then for i=1,3 do p.velocity[i]=p.velocity[i]*p.friction end end
  for i=1,3 do p.position[i]=p.position[i]+p.velocity[i] end
  if p.sizeTime>0 then
    local t=1/p.sizeTime;p.size=p.size+(p.sizeTarget-p.size)*t;p.sizeTime=p.sizeTime-1
    if p.sizeTime==0 then p.size=p.sizeTarget end
  end
  p.primTime=interpColor(p.prim,p.primTarget,p.primTime)
  p.envTime=interpColor(p.env,p.envTarget,p.envTime)
  if p.rotTime>0 then
    p.rotation=p.rotation+p.rotRate
    if p.rotAccel~=0 then p.rotRate=p.rotRate+(p.rotRate>=0 and p.rotAccel or -p.rotAccel) end
    p.rotTime=p.rotTime-1
  end
end

local function stepFrame(fx)
  fx.frame=fx.frame+1
  local withinSource=not fx.sourceEndFrame or fx.frame<=fx.sourceEndFrame
  for _,e in ipairs(fx.emitters) do
    local localFrame=fx.frame-e.startFrame
    if withinSource and localFrame>=0 and e.emitted<e.emitCount then
      while e.emitted<e.emitCount and localFrame>=e.nextEmitFrame do
        newParticle(fx,e)
        e.emitted=e.emitted+1
        e.nextEmitFrame=e.nextEmitFrame+e.emitInterval
      end
    elseif not withinSource then
      -- Waza phase ownership has ended. Do not let a heuristic emitter schedule
      -- manufacture new particles after the source phase has finished.
      e.emitted=e.emitCount
    end
  end
  for i=#fx.particles,1,-1 do
    local p=fx.particles[i]
    stepParticle(p,fx)
    if fx.hardEndFrame and fx.frame>=fx.hardEndFrame then p.alive=false end
    if not p.alive then table.remove(fx.particles,i) end
  end
end

function M.start(spec,opts)
  opts=type(opts)=="table" and opts or {}
  local role=tostring(opts.role or "attack")
  local fx={spec=spec,role=role,age=0,frame=0,accumulator=0,particles={},templates={},emitters={},done=false,joints=opts.joints or {},spawnSerial=0}
  local selectedEntry=type(opts.entry)=="table" and opts.entry or nil
  for i,gen in ipairs(type(spec)=="table" and (spec.generatorPrograms or {}) or {}) do
    if phaseRole(gen.phase)==role and matchesEntry(gen,selectedEntry)
        and type(gen.commandHex)=="string" and #gen.commandHex>=2
        and programSupported(gen.commandHex) then
      local t={gen=gen,index=i,data=hexToBytes(gen.commandHex or ""),
        autoRoot=selectedEntry and entrySelectsGenerator(gen,selectedEntry) or gen.root==true}
      fx.templates[#fx.templates+1]=t
    end
  end
  -- Bound particle ownership to the source WZX phase instead of the old global
  -- eight-second safety timer. MoveFXExtractor records each phase duration from
  -- the real GPT1 generator lifetime; use that plus the largest source root
  -- delay, then permit only a short particle tail. This prevents Peck/contact
  -- debris from surviving into the next command while preserving legitimate
  -- impact decay.
  local phaseSeconds=0
  local authoredFrames=tonumber(opts.sourceDurationFrames)
  if authoredFrames and authoredFrames>0 then
    phaseSeconds=authoredFrames/60
  else
    for _,phase in ipairs(type(spec)=="table" and (spec.phases or {}) or {}) do
      if phaseRole(phase.name)==role then phaseSeconds=math.max(phaseSeconds,tonumber(phase.duration) or 0) end
    end
  end
  if phaseSeconds<=0 then phaseSeconds=math.min(2.6,tonumber(spec and spec.duration) or .8) end
  phaseSeconds=clamp(phaseSeconds,.12,2.6)
  local rootDelay=0
  if not opts.sequenceStartHandled then
    for _,t in ipairs(fx.templates) do
      if t.autoRoot then rootDelay=math.max(rootDelay,safeSequenceFrame(t.gen.sequence and t.gen.sequence.start)) end
    end
  end
  fx.sourceEndFrame=rootDelay+math.max(1,math.ceil(phaseSeconds*60))
  fx.hardEndFrame=fx.sourceEndFrame+12

  -- Only source roots are live at the top level. Every non-root template stays
  -- dormant until a GPT1 spawn opcode references it.
  for _,t in ipairs(fx.templates) do
    if t.autoRoot then
      local startFrame=opts.sequenceStartHandled and 0 or safeSequenceFrame(t.gen.sequence and t.gen.sequence.start)
      emitterInstance(fx,t,startFrame)
    end
  end
  return fx
end

function M.update(fx,dt)
  if type(fx)~="table" or fx.done then return false end
  local step=math.max(0,tonumber(dt) or 0)
  fx.age=fx.age+step;fx.accumulator=(fx.accumulator or 0)+step
  local steps=0
  while fx.accumulator>=FRAME_DT and steps<MAX_STEPS_PER_UPDATE do
    fx.accumulator=fx.accumulator-FRAME_DT;steps=steps+1;stepFrame(fx)
  end
  if steps>=MAX_STEPS_PER_UPDATE and fx.accumulator>FRAME_DT*MAX_STEPS_PER_UPDATE then
    fx.accumulator=FRAME_DT*MAX_STEPS_PER_UPDATE
  end
  local emitDone=true
  for _,e in ipairs(fx.emitters) do if e.emitted<e.emitCount then emitDone=false;break end end
  if (emitDone and #fx.particles==0 and fx.frame>0)
      or (fx.hardEndFrame and fx.frame>=fx.hardEndFrame)
      or fx.age>=MAX_EFFECT_SECONDS then fx.done=true end
  return not fx.done
end

function M.visibleParticles(fx) return type(fx)=="table" and fx.particles or {} end
function M.status(fx)
  if type(fx)~="table" then return nil end
  local roots,controllers=0,0
  for _,e in ipairs(fx.emitters) do if e.autoRoot then roots=roots+1;if e.controllerRoot then controllers=controllers+1 end end end
  return {role=fx.role,age=fx.age,frame=fx.frame,templates=#(fx.templates or {}),emitters=#fx.emitters,roots=roots,controllers=controllers,particles=#fx.particles,done=fx.done,sourceEndFrame=fx.sourceEndFrame,hardEndFrame=fx.hardEndFrame}
end

return M
