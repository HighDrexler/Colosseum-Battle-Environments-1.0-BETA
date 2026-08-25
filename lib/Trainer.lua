local V = ...
local GeneratedAssets=V.GeneratedAssets
local mod, Mat4, TrainerRig = V.mod, V.Mat4, V.TrainerRig
local TrainerPerformance=V.TrainerPerformance
local BattleSides=V.BattleSides
local TrainerRoster=V.TrainerRoster
local T = {}

local FORMAT = {
  {"VertexPosition","float",3},
  {"VertexTexCoord","float",2},
  {"VertexNormal","float",3},
  {"BreathPosition","float",3},
  {"LookPosition","float",3},
  {"ArmPosition","float",3},
  {"ShiftPosition","float",3},
  {"SettlePosition","float",3},
  {"CommandPosition","float",3},
  {"BracePosition","float",3},
  {"ArmWeight","float",1},
}

local VERTEX = [[
uniform mat4 vp;
uniform mat4 model;
uniform float breathMix;
uniform float lookMix;
uniform float armMix;
uniform float shiftMix;
uniform float settleMix;
uniform float commandMix;
uniform float braceMix;
uniform float sourcePoseGain;
attribute vec3 VertexNormal;
attribute vec3 BreathPosition;
attribute vec3 LookPosition;
attribute vec3 ArmPosition;
attribute vec3 ShiftPosition;
attribute vec3 SettlePosition;
attribute vec3 CommandPosition;
attribute vec3 BracePosition;
varying vec3 worldPos;
varying vec3 worldNormal;


vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 base = vertex_position.xyz;
  vec3 p = base;
  // Source-performance compositor: large body poses are mutually normalized.
  // This prevents anticipation/release/recovery targets from stacking into an
  // anatomically impossible action-figure silhouette.
  /* The source morphs are intentionally treated as pose guides rather than
     100% rigid limb targets.  Colosseum's animation reads from whole-body
     silhouette/weight transfer; overdriving these hard-skinned targets is what
     made elbows and shoulders look like an action figure. */
  // Source boss poses are model-specific silhouettes, not rigid
  // action-figure endpoints.  Keep enough morph authority to read the pose,
  // but let the pelvis/torso performance carry more of the gesture.
  float wa=max(armMix,0.0)*0.46*sourcePoseGain, ws=max(shiftMix,0.0)*0.58*sourcePoseGain, wt=max(settleMix,0.0)*0.48*sourcePoseGain;
  float wc=max(commandMix,0.0)*0.57*sourcePoseGain, wb=max(braceMix,0.0)*0.52*sourcePoseGain;
  float sum=wa+ws+wt+wc+wb;
  float action=clamp(sum,0.0,1.0);
  if (sum>0.0001) {
    vec3 target=(ArmPosition*wa+ShiftPosition*ws+SettlePosition*wt+
                 CommandPosition*wc+BracePosition*wb)/sum;
    p=mix(base,target,action);
  }
  // Breath and look are tiny secondary motion and fade almost completely
  // during decisive source-style battle gestures.
  float secondary=1.0-action*0.94;
  p+=(BreathPosition-base)*breathMix*secondary;
  p+=(LookPosition-base)*lookMix*secondary;
  vec3 n = VertexNormal;
  vec4 world = model * vec4(p,1.0);
  worldPos = world.xyz;
  worldNormal = normalize((model * vec4(normalize(n),0.0)).xyz);
  return vp * world;
}
]]

local PIXEL = [[
uniform vec3 cameraEye;
uniform vec4 tintColor;
uniform float unlit;
uniform float opacity;
uniform float flipV;
varying vec3 worldPos;
varying vec3 worldNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec2 sampleUV=vec2(uv.x,mix(uv.y,1.0-uv.y,flipV));
  vec4 texel = Texel(texture,sampleUV);
  float a = texel.a * tintColor.a * opacity * color.a;
  if (a < 0.08) discard;
  if (unlit > 0.5) return vec4(tintColor.rgb,a);
  vec3 n = normalize(worldNormal);
  vec3 lightDir = normalize(vec3(-0.42,0.82,0.38));
  float key = abs(dot(n,lightDir));
  float hemi = clamp(n.y*0.5+0.5,0.0,1.0);
  vec3 viewDir = normalize(cameraEye-worldPos);
  float rim = pow(1.0-clamp(abs(dot(n,viewDir)),0.0,1.0),2.4);
  float light = 0.72 + key*0.24 + hemi*0.07;
  vec3 rgb = texel.rgb * light;
  rgb += vec3(0.055,0.075,0.10)*rim;
  rgb = clamp((rgb-vec3(0.5))*1.035+vec3(0.5),vec3(0.0),vec3(1.0));
  return vec4(rgb*tintColor.rgb,a);
}
]]

local scene, sceneKey, shader, shadowImage, shadowMesh
local ballMeshRed,ballMeshWhite,ballMeshBlack,ballTexture
local errorText
local currentModel="dakim"
local currentConfig=nil
local currentReason=nil
local arenaModelScale=0.19
local MODEL_CONFIG={
  dakim={label="DAKIM",cache="cache/trainers/dakim/model_cache.lua",scaleMul=1.0,pivotY=12.8},
  nascour={label="NASCOUR",cache="cache/trainers/nascour/model_cache.lua",scaleMul=1.48,pivotY=12.2},
  miror_b={label="MIROR B.",cache="cache/trainers/miror_b/model_cache.lua",scaleMul=1.28,pivotY=11.3},
}
local battleKey=nil
local age=0
local actionKind,actionAge,actionStrength=nil,0,0
local performanceState=TrainerPerformance and TrainerPerformance.newState("dakim") or nil
local currentMotion=nil
local initialSendoutQueued=false
local initialOpeningQueued=false
local lastSendingOut=false
local pendingFrustration=nil
local resultSeen=nil
local activeNow=false
local activationReason=nil

local FINAL_X, FINAL_Z = -13.2, -25.8
local BALL_TARGET_X,BALL_TARGET_Z=0,-14.5
local MODEL_SCALE = 0.19
local REFERENCE_ENEMY_SCALE = 0.205
local drawFrames=0

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function smooth(t) t=clamp(t,0,1); return t*t*(3-2*t) end
local function log(ctx,level,msg,...)
  local l=ctx and ctx.services and ctx.services.log
  if l and type(l[level])=="function" then pcall(l[level],l,"[ColosseumTrainer] "..msg,...) end
end
local function readLua(path)
  local src,readErr=GeneratedAssets.read(path); if not src then return nil,readErr or ("missing "..path) end
  local chunk,err=load(src,"@"..tostring(mod.path or mod.id).."/"..path)
  if not chunk then return nil,err end
  local ok,value=pcall(chunk); if not ok then return nil,value end
  return value
end
local function imageFromRaw(spec)
  local bytes,readErr=GeneratedAssets.read(spec.path); if not bytes then return nil,readErr or ("missing "..tostring(spec.path)) end
  local ok,data=pcall(love.image.newImageData,spec.w,spec.h,"rgba8",bytes)
  if not ok then return nil,data end
  local ok2,img=pcall(love.graphics.newImage,data)
  if not ok2 then return nil,img end
  if img.setFilter then
    local okf=pcall(img.setFilter,img,"linear","linear",16)
    if not okf then pcall(img.setFilter,img,"linear","linear") end
  end
  if img.setWrap then pcall(img.setWrap,img,"clamp","clamp") end
  return img
end
local function shadowVertex(x,y,z,u,v)
  -- Same base position is supplied for every morph stream. Shadows never
  -- morph, but the mesh must still satisfy the GPU-safe 10-attribute format.
  return {x,y,z,u,v,0,1,0,
    x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, 0}
end
local function ensureShadow()
  if shadowImage and shadowMesh then return true end
  local ok,data=pcall(love.image.newImageData,64,64)
  if not ok then return nil,data end
  for y=0,63 do
    for x=0,63 do
      local dx=(x-31.5)/31.5;local dy=(y-31.5)/31.5
      local d=math.sqrt(dx*dx+dy*dy)
      local a=clamp(1-d,0,1); a=a*a*0.46
      data:setPixel(x,y,1,1,1,a)
    end
  end
  shadowImage=love.graphics.newImage(data)
  shadowImage:setFilter("linear","linear")
  local verts={
    shadowVertex(-2.6,0.035,-1.25,0,0), shadowVertex(2.6,0.035,-1.25,1,0), shadowVertex(2.6,0.035,1.25,1,1),
    shadowVertex(-2.6,0.035,-1.25,0,0), shadowVertex(2.6,0.035,1.25,1,1), shadowVertex(-2.6,0.035,1.25,0,1),
  }
  shadowMesh=love.graphics.newMesh(FORMAT,verts,"triangles","static")
  shadowMesh:setTexture(shadowImage)
  return true
end
local function ballVertex(x,y,z,u,v)
  return {x,y,z,u,v,0,1,0,
    x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, 0}
end
local function sphereBand(y0,y1,r,segments)
  local out={};segments=segments or 12
  local function ringY(t) return math.sin(t)*r end
  local function ringR(t) return math.cos(t)*r end
  for i=0,segments-1 do
    local a0=(i/segments)*math.pi*2;local a1=((i+1)/segments)*math.pi*2
    local r0,r1=ringR(y0),ringR(y1);local yy0,yy1=ringY(y0),ringY(y1)
    local p00={math.cos(a0)*r0,yy0,math.sin(a0)*r0};local p01={math.cos(a1)*r0,yy0,math.sin(a1)*r0}
    local p10={math.cos(a0)*r1,yy1,math.sin(a0)*r1};local p11={math.cos(a1)*r1,yy1,math.sin(a1)*r1}
    local function add(p,u,v) out[#out+1]=ballVertex(p[1],p[2],p[3],u,v) end
    add(p00,0,0);add(p10,0,1);add(p11,1,1);add(p00,0,0);add(p11,1,1);add(p01,1,0)
  end
  return out
end
local function ensureBall()
  if ballMeshRed then return true end
  if not (love and love.graphics and love.image) then return false end
  local ok,id=pcall(love.image.newImageData,1,1);if not ok then return false end
  id:setPixel(0,0,1,1,1,1);ballTexture=love.graphics.newImage(id)
  local red,white,black={},{},{}
  for j=0,3 do
    local a=.10+(j/4)*(math.pi/2-.10);local b=.10+((j+1)/4)*(math.pi/2-.10)
    for _,v in ipairs(sphereBand(a,b,1,14)) do red[#red+1]=v end
    for _,v in ipairs(sphereBand(-b,-a,1,14)) do white[#white+1]=v end
  end
  for _,v in ipairs(sphereBand(-.10,.10,1.015,14)) do black[#black+1]=v end
  local function make(vs)local m=love.graphics.newMesh(FORMAT,vs,"triangles","static");m:setTexture(ballTexture);return m end
  ballMeshRed,ballMeshWhite,ballMeshBlack=make(red),make(white),make(black)
  return true
end

local function trainerModelFor(ctx)
  if TrainerRoster and type(TrainerRoster.modelFor)=="function" then
    local cfg,reason=TrainerRoster.modelFor(ctx)
    return cfg,reason
  end
  return MODEL_CONFIG.dakim,"legacy-dakim"
end
local function applyModelScale()
  local cfg=currentConfig or MODEL_CONFIG[currentModel] or MODEL_CONFIG.dakim
  local target=tonumber(cfg.enemyWorldHeight)
  local b=scene and sceneKey==currentModel and scene.bounds
  local h=b and b.max and b.min and ((tonumber(b.max[2]) or 0)-(tonumber(b.min[2]) or 0)) or nil
  if target and h and h>0.01 then
    -- The source trainers use very different authoring scales. Normalize human
    -- actors to the same readable battle-world height as the proven Colosseum
    -- bosses, while retaining each arena profile's subtle scale adjustment.
    MODEL_SCALE=(target/h)*(arenaModelScale/REFERENCE_ENEMY_SCALE)
  else
    MODEL_SCALE=arenaModelScale*(cfg.scaleMul or 1)
  end
end

-- Dakim's cache carries a second, fully authored clip-1 idle frame in slots
-- 9..11. Promote that coherent source frame to every position stream instead
-- of trying to reconstruct his characteristic stance with limb masks. This is
-- deliberately all-or-nothing per vertex: triangles retain their source shape.
local function dakimAuthoredIdle(vertices)
  if currentModel~="dakim" then return vertices or {} end
  local out={}
  for i,v in ipairs(vertices or {}) do
    local row={};for j=1,#v do row[j]=v[j] end
    local x,y,z=tonumber(v[9]) or tonumber(v[1]) or 0,tonumber(v[10]) or tonumber(v[2]) or 0,tonumber(v[11]) or tonumber(v[3]) or 0
    -- battleyama_b1's malformed rear shoulder shell occupies this exact band.
    -- Compact it around the measured attachment instead of deleting triangles;
    -- the result is a broad cap with intact UVs and no upward white tower.
    if math.abs(x)>3 and y>25 and z< -2.4 then
      local side=x>=0 and 1 or -1
      local px,py,pz=side*4.786,21.87,-2.699
      x=px+(x-px)*.35+side*.8
      y=py+(y-py)*.35
      z=pz+(z-pz)*.45
    end
    for _,base in ipairs({1,9,12,15,18,21,24,27}) do row[base],row[base+1],row[base+2]=x,y,z end
    row[30]=0
    out[i]=row
  end
  -- The shoulder shell changed shape, so rebuild flat face normals to keep the
  -- compacted cap's lighting coherent with Dakim's faceted source art.
  for i=1,#out,3 do if out[i+2] then
    local a,b,c=out[i],out[i+1],out[i+2]
    local ux,uy,uz=b[1]-a[1],b[2]-a[2],b[3]-a[3]
    local vx,vy,vz=c[1]-a[1],c[2]-a[2],c[3]-a[3]
    local nx,ny,nz=uy*vz-uz*vy,uz*vx-ux*vz,ux*vy-uy*vx
    local n=math.sqrt(nx*nx+ny*ny+nz*nz)
    if n>.000001 then nx,ny,nz=nx/n,ny/n,nz/n;for j=i,i+2 do out[j][6],out[j][7],out[j][8]=nx,ny,nz end end
  end end
  return out
end

local function loadScene(ctx)
  local cfg,reason=trainerModelFor(ctx)
  if not cfg then return nil,reason or "trainer-model-unavailable" end
  local wanted=tostring(cfg.id or cfg.label or cfg.cache or "trainer")
  if scene and sceneKey==wanted then currentReason=reason;return scene end
  if sceneKey~=wanted then scene=nil;errorText=nil;sceneKey=nil end
  currentModel=wanted
  currentConfig=cfg
  currentReason=reason
  applyModelScale()
  if errorText then return nil,errorText end
  if not (love and love.graphics and love.image and love.graphics.newMesh and love.graphics.newShader) then
    errorText="LÖVE mesh/shader API unavailable"; return nil,errorText
  end
  local cache,err=readLua(cfg.cache)
  if not cache then errorText=tostring(err);return nil,errorText end
  local textures={}; local groups={}
  for i,g in ipairs(cache.groups or {}) do
    local path=g.texture and g.texture.path
    local img=textures[path]
    if not img then
      img,err=imageFromRaw(g.texture)
      if not img then errorText=tostring(err);return nil,errorText end
      textures[path]=img
    end
    -- Every non-Dakim trainer passes through untouched. Dakim alone promotes
    -- his complete authored idle sample; no positional membership mask exists.
    local ok,mesh=pcall(love.graphics.newMesh,FORMAT,dakimAuthoredIdle(g.vertices),"triangles","static")
    if not ok then errorText=(cfg.label or currentModel).." mesh "..i..": "..tostring(mesh);return nil,errorText end
    mesh:setTexture(img)
    groups[#groups+1]={mesh=mesh,material=g.material}
  end
  local ok,sh=pcall(love.graphics.newShader,VERTEX,PIXEL)
  if not ok or not sh then errorText=(cfg.label or currentModel).." shader: "..tostring(sh or "unavailable");return nil,errorText end
  shader=sh
  local sok,serr=ensureShadow()
  if not sok then errorText=(cfg.label or currentModel).." shadow: "..tostring(serr);return nil,errorText end
  scene={groups=groups,bounds=cache.bounds,source=cache.source,textures=textures}
  sceneKey=currentModel
  applyModelScale()
  log(ctx,"info","loaded %s source actor: %d material groups",cfg.label or currentModel,#groups)
  return scene
end

local function battleOf(ctx)
  if type(ctx)~="table" then return nil end
  return ctx.battle or (ctx.kind and ctx) or nil
end

function T:isBossBattle(ctx)
  if TrainerRoster and type(TrainerRoster.isBoss)=="function" then
    return TrainerRoster.isBoss(ctx)
  end
  return false
end

function T:getMode(game)
  local p=game and game.save and game.save.colosseumBattle
  if type(p)=="table" then
    if p.enemyTrainerModel then return tostring(p.enemyTrainerModel) end
    if p.enemyTrainerModels==false then return "off" end
  end
  return "auto"
end
function T:setMode(game,mode)
  if not (game and game.save) then return end
  local p=game.save.colosseumBattle
  if type(p)~="table" then p={};game.save.colosseumBattle=p end
  local off=mode=="off" or mode=="player"
  p.enemyTrainerModels=not off
  if off then p.enemyTrainerModel="off" elseif not p.enemyTrainerModel or p.enemyTrainerModel=="off" then p.enemyTrainerModel="auto" end
end

function T:shouldRender(ctx)
  local b=battleOf(ctx)
  if not b or b.kind~="trainer" then return false end
  local cfg=trainerModelFor(ctx)
  if not cfg then return false end
  -- A trainer cache can exist yet still fail to decode/load. Once that has
  -- happened for this battle, immediately relinquish native-picture suppression
  -- so a damaged user cache cannot leave an empty enemy back-line.
  if battleKey==b and activationReason=="load-error" then return false end
  return true
end

local trigger,performanceId

function T:begin(ctx)
  battleKey=battleOf(ctx)
  age=0;actionKind=nil;actionAge=0;actionStrength=0;initialSendoutQueued=false;initialOpeningQueued=false;lastSendingOut=false;pendingFrustration=nil;resultSeen=nil;drawFrames=0;currentMotion=nil
  performanceState=TrainerPerformance and TrainerPerformance.resetState(performanceState,performanceId and performanceId() or "dakim") or nil
  local cfg,reason=trainerModelFor(ctx)
  activeNow=cfg~=nil
  activationReason=reason or (activeNow and "trainer" or "disabled")
  if activeNow then
    local loaded,err=loadScene(ctx)
    if not loaded then
      activeNow=false
      activationReason="load-error"
      log(ctx,"error","Enemy Colosseum actor failed to load: %s",tostring(err or errorText))
      return false,err or errorText
    end
  end
  return true
end

function T:update(ctx,dt)
  local b=battleOf(ctx)
  if b~=battleKey then
    battleKey=b;age=0;actionKind=nil;actionAge=0;actionStrength=0;initialSendoutQueued=false;initialOpeningQueued=false;lastSendingOut=false;pendingFrustration=nil;resultSeen=nil;activeNow=false;activationReason=nil;currentMotion=nil
    performanceState=TrainerPerformance and TrainerPerformance.resetState(performanceState,"dakim") or nil
  end
  local cfg,reason=trainerModelFor(ctx)
  local should=cfg~=nil
  if should and not activeNow then
    activeNow=true;age=0
    activationReason=reason or "trainer"
    local loaded,err=loadScene(ctx)
    if not loaded then
      activeNow=false
      activationReason="load-error"
      log(ctx,"error","Enemy Colosseum actor failed to load during update: %s",tostring(err or errorText))
    end
  elseif not should and activeNow then
    activeNow=false;age=0;actionKind=nil;actionAge=0;actionStrength=0;initialOpeningQueued=false;pendingFrustration=nil;resultSeen=nil;activationReason=nil;currentMotion=nil
  end
  local step=TrainerPerformance and TrainerPerformance.realDt(ctx,dt) or (tonumber(dt) or 0)
  if activeNow then
    age=age+step
    -- Personality can establish on presentation time, but the actual send-out
    -- must follow BattleState. A timer-authored enemy throw was able to finish
    -- before Stadium/current-sprite actors had entered their real grow-in,
    -- making every Pokémon look late even though its lifecycle was correct.
    if not initialOpeningQueued and age>=.70 then initialOpeningQueued=true;trigger("opening",.90) end
    local sending=(b and b.enemySendingOut==true) or false
    local growing=(b and b.growIn and b.growIn.battler==b.enemy) and true or false
    -- Gen1Recomp's EnemySendOutFirstMon has no POOF animation: the enemy
    -- trainer's authoritative release seam is AnimateSendingOutMon/startGrowIn.
    -- Never listen to the battle-global POOF here; that animation belongs to
    -- the player send-out/capture path and previously made both trainers throw.
    if growing and not initialSendoutQueued then
      initialSendoutQueued=true
      trigger("sendout",1.0)
    end
    if not sending and not growing then initialSendoutQueued=false end
    lastSendingOut=sending
    local result=b and b.result
    if result and result~=resultSeen then
      resultSeen=result
      if result=="lose" or result=="loss" or result=="defeat" then trigger("victory",1.0)
      elseif result=="win" or result=="victory" then trigger("defeat",1.0) end
    end
  end
  if actionKind then actionAge=actionAge+step end
  if activeNow and pendingFrustration then
    pendingFrustration=pendingFrustration-step
    if pendingFrustration<=0 then pendingFrustration=nil;trigger("frustration",1.0) end
  end
  if activeNow and TrainerPerformance then
    local id=performanceId();local duration=actionKind and TrainerPerformance.duration(id,actionKind) or nil
    if actionKind and actionAge>(duration or 1.2) then actionKind=nil;actionStrength=0 end
    currentMotion,performanceState=TrainerPerformance.step(performanceState,id,age,actionKind,actionAge,actionStrength,"enemy",step)
  end
end

function T:entryPose()
  local p=smooth((age-0.08)/1.18)
  -- Settle from just outside the active arena's enemy back-line.
  local sx=FINAL_X-2.8
  local sz=FINAL_Z-5.0
  local x=sx+(FINAL_X-sx)*p
  local z=sz+(FINAL_Z-sz)*p
  local y=-0.18+0.18*p
  local yaw=-0.12*(1-p)
  return {x=x,y=y,z=z,yaw=yaw,progress=p}
end

local function payloadSide(ctx,payload,fields)
  return BattleSides.payload(ctx,payload,fields)
end
local other=BattleSides.other

performanceId=function()
  return tostring((currentConfig and currentConfig.id) or currentModel or "dakim"):lower()
end
trigger=function(kind,strength)
  if TrainerPerformance and not TrainerPerformance.shouldTrigger({battle=battleKey},actionKind,actionAge,kind) then return end
  actionKind=kind;actionAge=0;actionStrength=strength or 1
end

function T:event(ctx,name,payload)
  payload=type(payload)=="table" and payload or {}
  if not activeNow then return end
  if name=="battle.move_used" then
    local actor=payloadSide(ctx,payload,{"user","attacker","source","battler","side"})
    if actor=="enemy" and not pendingFrustration then trigger("command",1.0) end
  elseif name=="battle.damage_dealt" then
    local target=payloadSide(ctx,payload,{"target","defender","targetSide","defenderSide"})
    if not target then local actor=payloadSide(ctx,payload,{"user","attacker","source","side"});target=other(actor) end
    if target=="enemy" then
      local b=battleOf(ctx);local dmg=tonumber(payload.damage) or 0
      local maxhp=b and b.enemy and b.enemy.mon and b.enemy.mon.stats and tonumber(b.enemy.mon.stats.hp) or 1
      local ratio=dmg/math.max(1,maxhp)
      trigger(ratio>=0.28 and "concern" or "brace",ratio>=0.28 and 1.0 or .78)
    end
  elseif name=="battle.status_inflicted" then
    local target=payloadSide(ctx,payload,{"target","battler","side","targetSide"})
    if target=="enemy" then trigger("concern",.72) end
  elseif name=="battle.battler_switched" then
    -- AI switch events can lead the actual enemySendingOut phase. Arm the
    -- performance, but let update() start it on the authoritative phase edge.
    local switched=payloadSide(ctx,payload,{"side","battler","target","switchedSide"})
    if switched=="enemy" then initialSendoutQueued=false end
  elseif name=="battle.fainted" then
    local fainted=payloadSide(ctx,payload,{"battler","target","side","faintedSide","targetSide"})
    if fainted=="enemy" then pendingFrustration=0.24 end
  elseif name=="battle.ended" then
    local b=battleOf(ctx);local result=payload.result or payload.outcome or (b and b.result)
    if result=="lose" or result=="loss" or result=="defeat" then trigger("victory",1.0)
    elseif result=="win" or result=="victory" then trigger("defeat",1.0)
    else actionKind=nil;actionAge=0;actionStrength=0 end
    pendingFrustration=nil
  end
end

local function idleMotion()
  local id=performanceId()
  if TrainerPerformance then
    return currentMotion or TrainerPerformance.idle(id,age,actionKind,actionAge,actionStrength,"enemy")
  end
  return {breath=.12,look=0,arm=0,shift=0,settle=0,lean=0,turn=0,bob=0,sway=0,command=0,brace=0,forward=0}
end
local function animatedModel(p,motion)
  -- Humanize the source morphs with restrained whole-body weight transfer.
  -- Crucially this rotates around the hips instead of around the model origin
  -- at the feet; the old foot-pivot made every gesture read like a rigid robot
  -- tipping on a stand.
  local root=TrainerPerformance and TrainerPerformance.root(performanceId(),motion) or {pitch=0,roll=0,yaw=(motion.turn or 0)*.8,compression=(motion.brace or 0)*.032}
  local pivotY=(currentConfig and tonumber(currentConfig.pivotY)) or ((MODEL_CONFIG[currentModel] or MODEL_CONFIG.dakim).pivotY or 12.8)
  local localAnim=Mat4.mul(Mat4.translate(0,pivotY,0),
    Mat4.mul(Mat4.rotateZ(root.roll or 0),
      Mat4.mul(Mat4.rotateX(root.pitch or 0),
        Mat4.mul(Mat4.rotateY(root.yaw or 0),Mat4.translate(0,-pivotY,0)))))
  return Mat4.mul(Mat4.translate(p.x+motion.sway,p.y+motion.bob-(root.compression or 0),p.z+motion.forward),
    Mat4.mul(Mat4.rotateY(p.yaw),Mat4.mul(Mat4.scale(MODEL_SCALE,MODEL_SCALE,MODEL_SCALE),localAnim)))
end

local function setShader(vp,model,pose,unlit,tint,opacity,motion)
  motion=motion or {}
  if not shader then local loaded=loadScene(nil); if not (loaded and shader) then return false end end
  love.graphics.setShader(shader)
  shader:send("vp","row",vp)
  shader:send("model","row",model)
  shader:send("cameraEye",pose and pose.eye or {54,24,13})
  shader:send("unlit",unlit or 0)
  shader:send("tintColor",tint or {1,1,1,1})
  shader:send("opacity",opacity or 1)
  shader:send("flipV",currentModel=="miror_b" and 1 or 0)
  local breathMix=currentModel=="dakim" and 0 or (motion.breath or 0)
  shader:send("breathMix",breathMix)
  shader:send("lookMix",motion.look or 0)
  shader:send("armMix",motion.arm or 0)
  shader:send("shiftMix",motion.shift or 0)
  shader:send("settleMix",motion.settle or 0)
  shader:send("commandMix",motion.command or 0)
  shader:send("braceMix",motion.brace or 0)
  shader:send("sourcePoseGain",1+(tonumber(motion.sourceAuthority) or 0)*.28)
end

function T:drawShadow(ctx,vp,pose)
  if not activeNow then return end
  local s=loadScene(ctx); if not s then return end
  local p=self:entryPose()
  if p.progress<0.05 then return end
  local motion=idleMotion()
  local model=Mat4.translate(p.x+motion.sway,0,p.z)
  love.graphics.setDepthMode("lequal",false)
  love.graphics.setBlendMode("alpha","alphamultiply")
  love.graphics.setMeshCullMode("none")
  love.graphics.setColor(1,1,1,1)
  setShader(vp,model,pose,1,{0,0,0,0.62},smooth(p.progress/0.55),{})
  love.graphics.draw(shadowMesh)
  love.graphics.setShader()
end

function T:draw(ctx,vp,pose)
  if not activeNow then return end
  drawFrames=drawFrames+1
  local s=loadScene(ctx); if not s then return end
  local p=self:entryPose()
  if p.progress<0.03 then return end
  local motion=idleMotion()
  local model=animatedModel(p,motion)
  love.graphics.setDepthMode("lequal",true)
  love.graphics.setBlendMode("alpha","alphamultiply")
  if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end
  love.graphics.setColor(1,1,1,1)
  setShader(vp,model,pose,0,{1,1,1,1},smooth(p.progress/0.40),motion)
  for _,g in ipairs(s.groups) do love.graphics.draw(g.mesh) end
  love.graphics.setShader()
end

local function ballPose()
  if actionKind~="sendout" then return nil end
  local id=performanceId();local d=TrainerPerformance and TrainerPerformance.duration(id,"sendout") or 1.48
  local phase=clamp(actionAge/math.max(.001,d),0,1)
  if phase<.31 or phase>.79 then return nil end
  local u=clamp((phase-.31)/.48,0,1)
  local pf=TrainerPerformance and TrainerPerformance.profile(id) or {lead=1}
  local lead=tonumber(pf.lead) or 1
  -- Source-scaled release anchor. A fixed 3.25 world-unit hand height was much
  -- too low for Dakim/Nascour and visibly detached the Poké Ball from the arm.
  local rigName=(currentConfig and currentConfig.rig) or id
  local rp=TrainerRig and scene and TrainerRig.profile(rigName,scene.bounds) or nil
  local shoulderLocal=rp and ((rp.minY or 0)+(rp.shoulder or .68)*(rp.height or 1)) or (4.20/MODEL_SCALE)
  local lateralLocal=rp and ((rp.halfWidth or 1)*math.max(.52,tonumber(rp.shoulderRadius) or .24)) or (0.70/MODEL_SCALE)
  local releaseY=clamp(shoulderLocal*MODEL_SCALE-.08,3.55,5.35)
  local releaseX=clamp(lateralLocal*MODEL_SCALE*.92,.48,1.08)
  local start={FINAL_X+releaseX*lead,releaseY,FINAL_Z+0.46}
  local target={BALL_TARGET_X,3.85,BALL_TARGET_Z}
  return {start[1]+(target[1]-start[1])*u,
          start[2]+(target[2]-start[2])*u+math.sin(u*math.pi)*4.65,
          start[3]+(target[3]-start[3])*u,u}
end
function T:drawBall(ctx,vp,pose)
  local bp=ballPose();if not bp or not ensureBall() then return end
  local spin=bp[4]*math.pi*7
  local model=Mat4.mul(Mat4.translate(bp[1],bp[2],bp[3]),Mat4.mul(Mat4.rotateY(spin),Mat4.mul(Mat4.rotateZ(spin*.55),Mat4.scale(.38,.38,.38))))
  love.graphics.setDepthMode("lequal",true);love.graphics.setBlendMode("alpha","alphamultiply")
  if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end
  local function part(mesh,tint)
    setShader(vp,model,pose,1,tint,1,{})
    love.graphics.draw(mesh)
  end
  part(ballMeshWhite,{.96,.96,.94,1});part(ballMeshRed,{.84,.08,.07,1});part(ballMeshBlack,{.035,.035,.04,1})
  love.graphics.setShader()
end

function T:finish(ctx,reason)
  battleKey=nil;age=0;actionKind=nil;actionAge=0;actionStrength=0;initialSendoutQueued=false;initialOpeningQueued=false;lastSendingOut=false;pendingFrustration=nil;resultSeen=nil;activeNow=false;activationReason=nil
end


function T:setArenaProfile(def)
  local t=def and def.trainers and def.trainers.enemy
  local mon=def and def.pokemon and def.pokemon.enemy
  if t then FINAL_X=tonumber(t[1]) or FINAL_X;FINAL_Z=tonumber(t[2]) or FINAL_Z end
  if mon then BALL_TARGET_X=tonumber(mon[1]) or BALL_TARGET_X;BALL_TARGET_Z=tonumber(mon[2]) or BALL_TARGET_Z end
  local sc=def and def.trainerScale and tonumber(def.trainerScale.enemy)
  if sc then arenaModelScale=sc;applyModelScale() end
end

function T:anchor(y) return {FINAL_X,y or 7.0,FINAL_Z} end
function T:resetRuntime()
  scene=nil;sceneKey=nil;shader=nil;shadowImage=nil;shadowMesh=nil;errorText=nil
  currentConfig=nil;currentReason=nil
  ballMeshRed=nil;ballMeshWhite=nil;ballMeshBlack=nil;ballTexture=nil
  activeNow=false;age=0;drawFrames=0;actionKind=nil;actionAge=0;actionStrength=0;lastSendingOut=false
  return true
end
function T:status()
  return {
    ready=scene~=nil,error=errorText,active=activeNow,age=age,
    reason=activationReason,
    model=(currentConfig and currentConfig.label) or (MODEL_CONFIG[currentModel] and MODEL_CONFIG[currentModel].label) or tostring(currentModel),
    modelSource=currentConfig and currentConfig.source or nil,modelReason=currentReason,
    pose="NativeHSD-clip1-nonbind-shoulder-anchored-throw-enemy",action=actionKind,pendingFrustration=pendingFrustration,modelScale=MODEL_SCALE,final={FINAL_X,0,FINAL_Z},drawFrames=drawFrames,
    mode=T:getMode(mod and mod.game),bossOnly=false,
  }
end

return T
