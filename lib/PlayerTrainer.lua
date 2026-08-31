local V = ...
local BattleDirector=V.BattleDirector
local GeneratedAssets=V.GeneratedAssets
local mod, Mat4, TrainerRig = V.mod, V.Mat4, V.TrainerRig
local TrainerPerformance=V.TrainerPerformance
local BattleSides=V.BattleSides
local TrainerRoster=V.TrainerRoster
local P = {}

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
local VERTEX=[[
uniform mat4 vp; uniform mat4 model;
uniform float breathMix; uniform float lookMix; uniform float armMix;
uniform float shiftMix; uniform float settleMix;
uniform float commandMix; uniform float braceMix;
uniform float sourcePoseGain;
attribute vec3 VertexNormal;
attribute vec3 BreathPosition;
attribute vec3 LookPosition;
attribute vec3 ArmPosition;
attribute vec3 ShiftPosition;
attribute vec3 SettlePosition;
attribute vec3 CommandPosition;
attribute vec3 BracePosition;
varying vec3 worldPos; varying vec3 worldNormal;


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
  // Keep Red's source-weighted morphs readable without letting arm targets
  // overpower the hips/shoulders and turn him back into a hinged action figure.
  float wa=max(armMix,0.0)*1.00*sourcePoseGain, ws=max(shiftMix,0.0)*0.96*sourcePoseGain, wt=max(settleMix,0.0)*0.90*sourcePoseGain;
  float wc=max(commandMix,0.0)*1.00*sourcePoseGain, wb=max(braceMix,0.0)*0.96*sourcePoseGain;
  float sum=wa+ws+wt+wc+wb;
  // Native B1 source poses now own decisive gestures. Keep a small ceiling so
  // interpolation/recovery remains smooth, but do not reduce them to pose hints.
  float action=clamp(sum,0.0,0.84);
  if (sum>0.0001) {
    vec3 target=(ArmPosition*wa+ShiftPosition*ws+SettlePosition*wt+
                 CommandPosition*wc+BracePosition*wb)/sum;
    p=mix(base,target,action);
  }
  // Breath and look are tiny secondary motion and fade almost completely
  // during decisive source-style battle gestures.
  float secondary=1.0-action*0.92;
  p+=(BreathPosition-base)*breathMix*secondary;
  p+=(LookPosition-base)*lookMix*secondary;
  vec3 n = VertexNormal;
  vec4 world=model*vec4(p,1.0); worldPos=world.xyz;
  worldNormal=normalize((model*vec4(normalize(n),0.0)).xyz); return vp*world;
}]]
local PIXEL=[[
uniform vec3 cameraEye; uniform vec4 tintColor; uniform vec4 materialColor; uniform float useTexture; uniform float unlit; uniform float opacity;
varying vec3 worldPos; varying vec3 worldNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec4 texel=Texel(texture,uv); float texAlpha=mix(1.0,texel.a,useTexture);
  float a=texAlpha*materialColor.a*tintColor.a*opacity*color.a;
  if (a<0.08) discard; vec3 sourceBase=mix(materialColor.rgb,texel.rgb,useTexture);
  if (unlit>0.5) return vec4(sourceBase*tintColor.rgb,a);
  vec3 n=normalize(worldNormal); vec3 lightDir=normalize(vec3(-0.42,0.82,0.38));
  float ndl=dot(n,lightDir); float key=max(ndl,0.0); float back=max(-ndl,0.0); float hemi=clamp(n.y*0.5+0.5,0.0,1.0);
  vec3 viewDir=normalize(cameraEye-worldPos); float rim=pow(1.0-clamp(abs(dot(n,viewDir)),0.0,1.0),2.4);
  float light=0.73+key*0.25+back*0.055+hemi*0.055; vec3 rgb=sourceBase*light+vec3(0.040,0.047,0.055)*rim;
  rgb=clamp((rgb-vec3(0.5))*1.035+vec3(0.5),vec3(0.0),vec3(1.0));
  return vec4(rgb*tintColor.rgb,a);
}]]

local scene,sceneKey,shader,shadowImage,shadowMesh,errorText
local currentConfig,currentModel,currentReason=nil,"red",nil
local DEFAULT_PLAYER_MODEL=currentModel
local battleKey,age,activeNow=nil,0,false
local actionKind,actionAge,actionStrength=nil,0,0
local performanceState=TrainerPerformance and TrainerPerformance.newState("red") or nil
local currentMotion=nil
local initialThrowQueued=false
local initialOpeningQueued=false
local lastSendingOut=false
local resultSeen=nil
local pendingFrustration=nil
-- CBE-owned wild-capture presentation.  Engine capture logic/dialogue remains
-- authoritative; this state owns only the 3D trainer/ball/Pokemon choreography.
local capture=nil
local captureSuccessTemplate=nil
local captureSuccessActive=nil
local ballMeshRed,ballMeshWhite,ballMeshBlack,ballTexture
local ballError=nil
local ballDrawFrames=0
-- Exact Poké Ball props/animations are compiled locally from the user's
-- Colosseum ISO/CISO. The procedural sphere below is retained only as a
-- fail-open for stale/incomplete source caches.
local captureAssetIndex=nil
local captureAssetError=nil
local captureSourceDrawFrames=0
-- Native prop span is 0.90 source units versus Red's 16.24-unit source height.
-- At CBE's 0.405 human scale that lands at ~0.365 world units: preserve that
-- actual Colosseum proportion instead of enlarging the ball for readability.
local SOURCE_BALL_DIAMETER=0.365
local FINAL_X,FINAL_Z=13.2,25.8
-- Send-out and capture land on opposite battlers. 1.5.60 reused the player
-- send-out anchor for captures, which is why thrown capture balls visibly hit
-- the user's own Pokemon.
local SENDOUT_TARGET_X,SENDOUT_TARGET_Z=0,14.5
local CAPTURE_TARGET_X,CAPTURE_TARGET_Z=0,-14.5

-- Reference-timed Colosseum capture sequence (real presentation seconds).
-- Gameplay/catch odds remain 100% engine-owned; only the visible choreography
-- runs on this wall clock so Gen1Recomp fast-forward cannot delete the shakes.
local CAPTURE_T={charge=.76,throw=1.72,impact=.52,absorb=1.72,fall=1.12,settle=.42,shake=.88,outcome=1.02}
local function captureMilestones(shakes)
  local a=CAPTURE_T.charge
  local b=a+CAPTURE_T.throw
  local c=b+CAPTURE_T.impact
  local d=c+CAPTURE_T.absorb
  local e=d+CAPTURE_T.fall
  local f=e+CAPTURE_T.settle
  local g=f+math.max(0,tonumber(shakes) or 0)*CAPTURE_T.shake
  return a,b,c,d,e,f,g,g+CAPTURE_T.outcome
end
local function presentationNow()
  if love and love.timer and type(love.timer.getTime)=="function" then
    local ok,v=pcall(love.timer.getTime);if ok and tonumber(v) then return tonumber(v) end
  end
  return nil
end
local drawFrames=0
-- Red's ripped model is roughly half Dakim's source-unit height, so it needs
-- an independent scale to land at the same believable human height in-world.
local arenaModelScale=0.405
local MODEL_SCALE=0.405
local FINAL_YAW=math.pi

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function smooth(t) t=clamp(t,0,1);return t*t*(3-2*t) end
local function log(ctx,level,msg,...)
  local l=ctx and ctx.services and ctx.services.log
  if l and type(l[level])=="function" then pcall(l[level],l,"[ColosseumPlayerTrainer] "..msg,...) end
end
local function readLua(path)
  local src,readErr=GeneratedAssets.read(path);if not src then return nil,readErr or ("missing "..path) end
  local chunk,err=load(src,"@"..tostring(mod.path or mod.id).."/"..path);if not chunk then return nil,err end
  local ok,value=pcall(chunk);if not ok then return nil,value end;return value
end

local function loadCaptureAssetIndex()
  if captureAssetIndex~=nil then return captureAssetIndex or nil,captureAssetError end
  local idx,err=readLua("cache/capture/index.lua")
  if type(idx)=="table" and type(idx.balls)=="table" then
    captureAssetIndex=idx;captureAssetError=nil;return idx
  end
  captureAssetIndex=false;captureAssetError=tostring(err or "native Colosseum capture cache unavailable")
  return nil,captureAssetError
end
local function captureBallId(value)
  local idx=loadCaptureAssetIndex()
  local raw=tostring(value or "POKE_BALL"):upper():gsub("[^A-Z0-9]+","_"):gsub("^_+",""):gsub("_+$","")
  if idx and idx.aliases and idx.aliases[raw] then return idx.aliases[raw] end
  if raw:find("MASTER",1,true) then return "master" end
  if raw:find("ULTRA",1,true) or raw:find("HYPER",1,true) then return "ultra" end
  if raw:find("GREAT",1,true) or raw:find("SUPER",1,true) then return "great" end
  if raw:find("SAFARI",1,true) then return "safari" end
  if raw:find("PREMIER",1,true) or raw:find("PREMIRE",1,true) then return "premier" end
  if raw:find("LUXURY",1,true) or raw:find("GORGEOUS",1,true) or raw:find("GORGEUS",1,true) then return "luxury" end
  if raw:find("REPEAT",1,true) then return "repeatball" end
  if raw:find("TIMER",1,true) then return "timer" end
  if raw:find("DIVE",1,true) then return "dive" end
  if raw:find("NEST",1,true) then return "nest" end
  if raw:find("NET",1,true) then return "net" end
  return "poke"
end
local function sourceBallAsset(phase)
  local idx=loadCaptureAssetIndex();if not idx then return nil end
  local id=captureBallId(capture and capture.ball)
  local row=idx.balls and idx.balls[id];local phases=row and row.phases
  if not phases then return nil end
  local key=(phase=="shake" and "shake")
    or ((phase=="fall" or phase=="settle" or phase=="caught") and "land")
    or (phase=="breakout" and "miss") or "throw"
  return phases[key] or phases.shake, id, key
end
local function sourceAssetFrame(asset,phase,u,bp)
  local a=asset and asset.animation or nil
  local finish=math.max(0,tonumber(a and a.endFrame) or 0)
  if finish<=0 then return 0 end
  local q=clamp(tonumber(u) or 0,0,1)
  -- The retail snatch_shake bank contains useful source geometry/materials,
  -- but baking its JOBJ root motion into vertex morph pages makes a grounded
  -- sphere look like it is freely rolling around its centre in CBE. Keep the
  -- source prop at its authored rest frame and apply the retail-style WORLD
  -- rock below around the floor contact point. This preserves the ISO model
  -- and texture without double-driving its orientation.
  if phase=="shake" or phase=="caught" then return 0 end
  return q*finish
end
local function sourceBallModel(asset,bp)
  local b=asset and asset.bounds or {};local mn=b.min or {-1,-1,-1};local mx=b.max or {1,1,1};local c=b.center or {0,0,0}
  local sx=math.abs((tonumber(mx[1]) or 1)-(tonumber(mn[1]) or -1))
  local sy=math.abs((tonumber(mx[2]) or 1)-(tonumber(mn[2]) or -1))
  local sz=math.abs((tonumber(mx[3]) or 1)-(tonumber(mn[3]) or -1))
  local span=math.max(.0001,sx,sy,sz)
  local sc=SOURCE_BALL_DIAMETER/span
  local center=Mat4.translate(-(tonumber(c[1]) or 0),-(tonumber(c[2]) or 0),-(tonumber(c[3]) or 0))
  local scaled=Mat4.mul(Mat4.scale(sc,sc,sc),center)

  -- Airborne motion gets one coherent forward roll. Once the ball is planted,
  -- it never spins around its centre. A shake rotates the entire retail prop
  -- around the BOTTOM contact point, so its centre naturally shifts a few
  -- centimetres sideways/upward exactly as a rigid sphere rocking on turf.
  local airborne=bp and (bp.kind=="throw" or bp.kind=="fall")
  if airborne then
    return Mat4.mul(Mat4.translate(bp[1],bp[2],bp[3]),
      Mat4.mul(Mat4.rotateZ(tonumber(bp.spin) or 0),scaled))
  end
  local rock=(bp and bp.kind=="shake") and (tonumber(bp.rock) or 0) or 0
  if math.abs(rock)>1e-6 then
    local radius=SOURCE_BALL_DIAMETER*.50
    return Mat4.mul(Mat4.translate(bp[1],bp[2]-radius,bp[3]),
      Mat4.mul(Mat4.rotateZ(rock),Mat4.mul(Mat4.translate(0,radius,0),scaled)))
  end
  return Mat4.mul(Mat4.translate(bp[1],bp[2],bp[3]),scaled)
end
local function imageFromRaw(spec)
  local bytes,readErr=GeneratedAssets.read(spec.path);if not bytes then return nil,readErr or ("missing "..tostring(spec.path)) end
  local ok,data=pcall(love.image.newImageData,spec.w,spec.h,"rgba8",bytes);if not ok then return nil,data end
  local ok2,img=pcall(love.graphics.newImage,data);if not ok2 then return nil,img end
  if img.setFilter then local okf=pcall(img.setFilter,img,"linear","linear",16);if not okf then pcall(img.setFilter,img,"linear","linear") end end
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
  local ok,data=pcall(love.image.newImageData,64,64);if not ok then return nil,data end
  for y=0,63 do for x=0,63 do
    local dx=(x-31.5)/31.5;local dy=(y-31.5)/31.5;local d=math.sqrt(dx*dx+dy*dy);local a=clamp(1-d,0,1);a=a*a*0.40
    data:setPixel(x,y,1,1,1,a)
  end end
  shadowImage=love.graphics.newImage(data);shadowImage:setFilter("linear","linear")
  local verts={shadowVertex(-2.2,.035,-1.05,0,0),shadowVertex(2.2,.035,-1.05,1,0),shadowVertex(2.2,.035,1.05,1,1),shadowVertex(-2.2,.035,-1.05,0,0),shadowVertex(2.2,.035,1.05,1,1),shadowVertex(-2.2,.035,1.05,0,1)}
  shadowMesh=love.graphics.newMesh(FORMAT,verts,"triangles","static");shadowMesh:setTexture(shadowImage);return true
end

local function ballVertex(x,y,z,u,v)
  return {x,y,z,u,v,0,1,0,
    x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, x,y,z, 0}
end
local function sphereBand(y0,y1,r,segments)
  local out={}
  segments=segments or 12
  local function ringY(t) return math.sin(t)*r end
  local function ringR(t) return math.cos(t)*r end
  for i=0,segments-1 do
    local a0=(i/segments)*math.pi*2; local a1=((i+1)/segments)*math.pi*2
    local r0,r1=ringR(y0),ringR(y1); local yy0,yy1=ringY(y0),ringY(y1)
    local p00={math.cos(a0)*r0,yy0,math.sin(a0)*r0}; local p01={math.cos(a1)*r0,yy0,math.sin(a1)*r0}
    local p10={math.cos(a0)*r1,yy1,math.sin(a0)*r1}; local p11={math.cos(a1)*r1,yy1,math.sin(a1)*r1}
    local function add(p,u,v) out[#out+1]=ballVertex(p[1],p[2],p[3],u,v) end
    add(p00,0,0);add(p10,0,1);add(p11,1,1); add(p00,0,0);add(p11,1,1);add(p01,1,0)
  end
  return out
end
local function ensureBall()
  if ballMeshRed and ballMeshWhite and ballMeshBlack then return true end
  if not (love and love.graphics and love.image) then
    ballError="LÖVE image/graphics unavailable"
    return false
  end
  local ok,err=pcall(function()
    local id=love.image.newImageData(1,1)
    id:setPixel(0,0,1,1,1,1)
    ballTexture=love.graphics.newImage(id)
    local red,white,black={},{},{}
    -- Upper/lower hemispheres plus a slightly proud black equator.  Keep this
    -- geometry self-contained so capture never depends on a Game Boy sprite or
    -- on another mod's Poké Ball asset.
    for j=0,4 do
      local a=.08+(j/5)*(math.pi/2-.08)
      local b=.08+((j+1)/5)*(math.pi/2-.08)
      local top=sphereBand(a,b,1,18);for _,v in ipairs(top) do red[#red+1]=v end
      local bot=sphereBand(-b,-a,1,18);for _,v in ipairs(bot) do white[#white+1]=v end
    end
    local eq=sphereBand(-.105,.105,1.025,18);for _,v in ipairs(eq) do black[#black+1]=v end
    local function make(vs)
      local m=love.graphics.newMesh(FORMAT,vs,"triangles","static")
      m:setTexture(ballTexture)
      return m
    end
    ballMeshRed,ballMeshWhite,ballMeshBlack=make(red),make(white),make(black)
  end)
  if not ok then
    ballMeshRed,ballMeshWhite,ballMeshBlack,ballTexture=nil,nil,nil,nil
    ballError=tostring(err)
    return false
  end
  ballError=nil
  return true
end

-- Source-strap relief: Red's original Colosseum mesh already contains
-- the backpack shoulder straps, but the front strap polygons sit nearly coplanar
-- with the jacket. In close cameras that reads like yellow tape painted onto his
-- chest. Preserve the authored geometry/UVs and lift only those measured strap
-- vertices slightly off the torso, across every source morph stream equally.
local function redStrapRelief(v)
  local row={}; for j=1,#v do row[j]=v[j] end
  local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
  local u,vv=tonumber(v[4]) or 0,tonumber(v[5]) or 0
  -- Source measurements: the two visible front harness strips occupy |X|
  -- roughly .8..1.25, Y 10..12.1, Z .45..+.9 and wrap UV U~.99..1.09.
  local strap=math.abs(x)>.72 and math.abs(x)<1.34 and y>9.72 and y<12.30
      and z>.32 and z<1.08 and u>.94 and u<1.12 and vv>.12 and vv<.30
  if not strap then return row end
  local side=x>=0 and 1 or -1
  -- Lift forward off the jacket and open a tiny side gap.  Keep this subtle:
  -- .14 source units is only ~.057 world units at Red's shipping scale.
  local t=clamp((y-9.72)/(12.30-9.72),0,1)
  local crown=math.sin(t*math.pi)
  local shoulder=smooth(clamp((t-.58)/.42,0,1))
  -- A worn strap is shallow at the lower chest, lifts through the curved chest,
  -- then stays proud of the jacket as it wraps over the shoulder toward the pack.
  -- The old symmetric crown fell back flush at the shoulder and still looked
  -- painted-on from three-quarter views.
  local dx=side*(.012+.025*crown+.010*shoulder)
  local dz=.060+.120*crown+.025*shoulder
  -- Apply the same offset to base + every morph position so the strap keeps its
  -- original authored animation relationship instead of swimming on the body.
  for _,base in ipairs({1,9,12,15,18,21,24,27}) do
    if row[base]~=nil then row[base]=row[base]+dx end
    if row[base+2]~=nil then row[base+2]=row[base+2]+dz end
  end
  -- Give the lifted source polygons a subtly different light response.  Their
  -- original normals were almost identical to the jacket, which visually erased
  -- the geometric relief even when the vertices were physically separated.
  local nx,ny,nz=tonumber(row[6]) or 0,tonumber(row[7]) or 0,tonumber(row[8]) or 1
  nx=nx+side*.09; nz=nz+.14
  local nl=math.sqrt(nx*nx+ny*ny+nz*nz)
  if nl>.0001 then row[6],row[7],row[8]=nx/nl,ny/nl,nz/nl end
  return row
end

local function preparePlayerVertices(vertices,isRed)
  if not isRed then return vertices or {} end
  local out={}
  for i,v in ipairs(vertices or {}) do
    local row=redStrapRelief(v)
    row[30]=tonumber(row[30]) or 0
    out[i]=row
  end
  return out
end

local function playerModelFor(ctx)
  if TrainerRoster and type(TrainerRoster.playerModelFor)=="function" then
    return TrainerRoster.playerModelFor(ctx)
  end
  return {id="red",label="RED",cache="cache/trainers/red/model_cache.lua",playerScaleMul=1,pivotY=7.4,playerPivotY=7.4,rig="red"},"legacy-red"
end
local function applyModelScale()
  local mul=currentConfig and tonumber(currentConfig.playerScaleMul) or 1
  MODEL_SCALE=arenaModelScale*(mul or 1)
end


local function loadScene(ctx)
  local cfg,reason=playerModelFor(ctx)
  if not cfg then return nil,reason or "player-model-unavailable" end
  local wanted=tostring(cfg.id or cfg.label or cfg.cache or "player")
  if scene and shader and sceneKey==wanted then currentReason=reason;return scene end
  if sceneKey~=wanted then scene=nil;shader=nil;errorText=nil;sceneKey=nil end
  currentConfig=cfg;currentModel=wanted;currentReason=reason;applyModelScale()
  if errorText then return nil,errorText end
  if not (love and love.graphics and love.image and love.graphics.newMesh and love.graphics.newShader) then errorText="LÖVE mesh/shader API unavailable";return nil,errorText end
  local cache,err=readLua(cfg.cache);if not cache then errorText=tostring(err);return nil,errorText end
  local textures,groups={},{}
  for i,g in ipairs(cache.groups or {}) do
    local path=g.texture and g.texture.path;local img=path and textures[path] or nil
    if path and not img then img,err=imageFromRaw(g.texture);if not img then errorText=tostring(err);return nil,errorText end;textures[path]=img end
    -- Direct source geometry stays untouched; source material/pass state is
    -- retained per HSD DOBJ group instead of flattening the trainer to one
    -- opaque texture-only material.
    local weighted=preparePlayerVertices(g.vertices or {},currentModel==DEFAULT_PLAYER_MODEL and not cfg.directSource)
    local ok,mesh=pcall(love.graphics.newMesh,FORMAT,weighted,"triangles","static")
    if not ok then errorText=(cfg.label or wanted).." mesh "..i..": "..tostring(mesh);return nil,errorText end
    if img then mesh:setTexture(img) end
    local d=g.diffuse or {1,1,1}
    groups[#groups+1]={mesh=mesh,material=g.material,image=img,textured=img~=nil,
      diffuse={tonumber(d[1]) or 1,tonumber(d[2]) or 1,tonumber(d[3]) or 1},
      alpha=tonumber(g.alpha) or 1,xlu=g.xlu==true,noz=g.noz==true,
      renderFlags=tonumber(g.renderFlags) or 0,shadow=g.shadow==true,effect=g.effect==true}
  end
  local ok,sh=pcall(love.graphics.newShader,VERTEX,PIXEL);if not ok or not sh then errorText=(cfg.label or wanted).." shader: "..tostring(sh or "unavailable");return nil,errorText end
  shader=sh;local sok,serr=ensureShadow();if not sok then errorText=(cfg.label or wanted).." shadow: "..tostring(serr);return nil,errorText end
  scene={groups=groups,bounds=cache.bounds,source=cache.source,textures=textures,
    jointPositions=cache.jointPositions,jointParents=cache.jointParents,poseJointPositions=cache.poseJointPositions,
    releaseJoint=tonumber(cache.releaseJoint),releaseSide=tonumber(cache.releaseSide),
    releaseJointScore=tonumber(cache.releaseJointScore)};sceneKey=wanted
  log(ctx,"info","loaded player trainer %s: %d material groups",cfg.label or wanted,#groups);return scene
end
local function battleOf(ctx) if type(ctx)~="table" then return nil end;return ctx.battle or (ctx.kind and ctx) or nil end
local function enabled(ctx)
  local cfg=playerModelFor(ctx)
  if not cfg then return false end
  local b=battleOf(ctx)
  if battleKey==b and errorText and not scene then return false end
  return true
end
function P:prewarm(ctx)
  local s,err=loadScene(ctx)
  if s then
    local source=loadCaptureAssetIndex()
    if not source then pcall(ensureBall) end
  end
  return s~=nil,err
end
function P:shouldRender(ctx) return enabled(ctx) end
local trigger,performanceId
function P:begin(ctx)
  battleKey=battleOf(ctx);age=0;actionKind=nil;actionAge=0;actionStrength=0;initialThrowQueued=false;initialOpeningQueued=false;lastSendingOut=false;resultSeen=nil;capture=nil;drawFrames=0;currentMotion=nil
  performanceState=TrainerPerformance and TrainerPerformance.resetState(performanceState,"red") or nil
  activeNow=self:shouldRender(ctx)
  if activeNow then
    local loaded,err=loadScene(ctx)
    if not loaded then
      activeNow=false
      log(ctx,"error","Player Colosseum actor failed to load: %s",tostring(err or errorText))
      return false,err or errorText
    end
  end
  return true
end
local function stopCaptureSuccessAudio()
  if captureSuccessActive and type(captureSuccessActive.stop)=="function" then pcall(captureSuccessActive.stop,captureSuccessActive) end
  captureSuccessActive=nil
end
local function ensureCaptureSuccessAudio(ctx)
  if not (love and love.audio and love.audio.newSource and GeneratedAssets and GeneratedAssets.fileData) then return false end
  if captureSuccessTemplate==nil then
    local fd,err=GeneratedAssets.fileData("assets/audio/capture/me_snatch.wav","me_snatch.wav")
    if not fd then captureSuccessTemplate=false;log(ctx,"warn","Colosseum capture-success jingle unavailable: %s",tostring(err));return false end
    local ok,src=pcall(love.audio.newSource,fd,"static")
    captureSuccessTemplate=(ok and src) or false
    if captureSuccessTemplate and type(captureSuccessTemplate.setLooping)=="function" then pcall(captureSuccessTemplate.setLooping,captureSuccessTemplate,false) end
    if not captureSuccessTemplate then log(ctx,"warn","Colosseum capture-success jingle failed to load") end
  end
  return captureSuccessTemplate and true or false
end
local function playCaptureSuccessAudio(ctx)
  if not ensureCaptureSuccessAudio(ctx) then return false end
  local src=captureSuccessTemplate
  if type(src.clone)=="function" then local ok,v=pcall(src.clone,src);if ok and v then src=v end end
  stopCaptureSuccessAudio();captureSuccessActive=src
  if type(src.play)=="function" then local ok=pcall(src.play,src);return ok end
  return false
end

function P:update(ctx,dt)
  local b=battleOf(ctx);if b~=battleKey then stopCaptureSuccessAudio();battleKey=b;age=0;actionKind=nil;actionAge=0;actionStrength=0;initialThrowQueued=false;initialOpeningQueued=false;lastSendingOut=false;resultSeen=nil;pendingFrustration=nil;capture=nil;currentMotion=nil;performanceState=TrainerPerformance and TrainerPerformance.resetState(performanceState,"red") or nil end
  activeNow=self:shouldRender(ctx);dt=TrainerPerformance and TrainerPerformance.realDt(ctx,dt) or (tonumber(dt) or 0)
  if activeNow then
    local cfg=playerModelFor(ctx)
    if cfg and sceneKey~=tostring(cfg.id or cfg.label or cfg.cache or "player") then loadScene(ctx) end
    age=age+dt
    -- Establish personality on the intro clock, but NEVER guess the actual
    -- Poké Ball release from elapsed presentation time. The engine's live
    -- sendingOut edge is authoritative for initial leads and later switches,
    -- so trainer choreography cannot visually promise a Pokémon before the
    -- battle/model runtime is ready to release it.
    if not initialOpeningQueued and age>=.72 then initialOpeningQueued=true;trigger("opening",.88) end
    local sending=(b and b.sendingOut==true) or false
    -- POOF_ANIM is battle-global and is also used by captures. Gate it with
    -- the player-side sendingOut state so an enemy replacement cannot make
    -- the player trainer perform a phantom throw.
    local poof=(sending and b and b.animPlaying and b.animName=="POOF_ANIM") and true or false
    local growing=(b and b.growIn and b.growIn.battler==b.player) and true or false
    -- Release on the actual ball-open / grow seam. `sendingOut` begins much
    -- earlier while the Go! text is still printing, so using its rising edge
    -- makes the trainer finish throwing long before the Pokemon can exist.
    if (poof or growing) and not initialThrowQueued then
      initialThrowQueued=true
      trigger("throw",1.0)
    end
    if not sending and not poof and not growing then initialThrowQueued=false end
    lastSendingOut=sending
    local result=b and b.result
    if result and result~=resultSeen then
      resultSeen=result
      if result=="win" or result=="victory" then trigger("victory",1.0)
      elseif result=="lose" or result=="loss" or result=="defeat" then trigger("defeat",1.0) end
    end
  end
  if actionKind then actionAge=actionAge+dt end
  if capture then
    -- Capture presentation deliberately uses monotonic real time. The battle
    -- may run at 2x/4x, but Colosseum's throw/absorb/drop/shake camera sequence
    -- must remain readable instead of collapsing into a few rendered frames.
    local wall=presentationNow();local step=dt
    if wall and capture.lastClock then step=math.max(0,math.min(.12,wall-capture.lastClock)) end
    if wall then capture.lastClock=wall end
    capture.age=(capture.age or 0)+math.max(0,tonumber(step) or 0)
    if capture.caught and not capture.successSfxPlayed and capture.age>=(capture.outcomeAt or 0) then
      capture.successSfxPlayed=true
      capture.successSfxOwned=playCaptureSuccessAudio(ctx)==true
    end
    if capture.age>(capture.duration or 12.0) then capture.done=true end
  end
  if activeNow and pendingFrustration then
    pendingFrustration=pendingFrustration-dt
    if pendingFrustration<=0 then pendingFrustration=nil;trigger("frustration",1.0,true) end
  end
  if activeNow and TrainerPerformance then
    local id=performanceId();local duration=actionKind and TrainerPerformance.duration(id,actionKind) or nil
    if actionKind and actionAge>(duration or 1.2) then actionKind=nil;actionStrength=0 end
    currentMotion,performanceState=TrainerPerformance.step(performanceState,id,age,actionKind,actionAge,actionStrength,"player",dt)
  end
end
function P:finish() stopCaptureSuccessAudio();battleKey=nil;age=0;activeNow=false;actionKind=nil;actionAge=0;actionStrength=0;initialThrowQueued=false;initialOpeningQueued=false;lastSendingOut=false;resultSeen=nil;pendingFrustration=nil;capture=nil;currentMotion=nil;performanceState=TrainerPerformance and TrainerPerformance.resetState(performanceState,"red") or nil end
local function entryPose()
  local p=smooth((age-0.06)/1.05)
  -- Start just outside whichever arena back-line is active and settle inward.
  -- Water keeps the stable authored destination; alternate arenas only
  -- change the profile values before the battle begins.
  local sx=FINAL_X+2.8
  local sz=FINAL_Z+5.0
  return {x=sx+(FINAL_X-sx)*p,y=-.12+.12*p,z=sz+(FINAL_Z-sz)*p,yaw=FINAL_YAW-.10*(1-p),progress=p}
end
local function payloadSide(ctx,payload,fields)
  return BattleSides.payload(ctx,payload,fields)
end
local other=BattleSides.other

performanceId=function()
  return tostring((currentConfig and currentConfig.id) or currentModel or "red"):lower()
end
trigger=function(kind,strength,force)
  if not force and TrainerPerformance and not TrainerPerformance.shouldTrigger({battle=battleKey},actionKind,actionAge,kind) then return end
  actionKind=kind;actionAge=0;actionStrength=strength or 1
end

function P:event(ctx,name,payload)
  payload=type(payload)=="table" and payload or {}
  local b0=battleOf(ctx)
  local gen2=b0 and b0.__cbeGeneration==2
  local queueSync=gen2 and b0.__cbePresentationQueueSync==true
  if queueSync and (name=="battle.move_used" or name=="battle.damage_dealt" or name=="battle.fainted") then return end
  local semantic=name
  if name=="battle.presentation_damage" then semantic="battle.damage_dealt"
  elseif name=="battle.presentation_faint" then semantic="battle.fainted" end
  if semantic=="battle.move_used" or name=="battle.presentation_move" then
    local actorSide=payloadSide(ctx,payload,{"user","attacker","source","battler","side"})
    if actorSide=="player" then
      local b=battleOf(ctx)
      local stillReleasing=b and (b.sendingOut==true or (b.growIn and b.growIn.battler==b.player))
      -- A fast first-turn input can land while the trainer is in the last
      -- few frames of throw recovery even though the Pokémon is already live.
      -- Once the engine's release seam is over, the real battle command owns
      -- the performance and may cleanly carry the throw momentum into command.
      trigger("command",1.0,actionKind=="throw" and not stillReleasing)
    end
  elseif semantic=="battle.damage_dealt" then
    local targetSide=payloadSide(ctx,payload,{"target","defender","targetSide","defenderSide"})
    if not targetSide then local actorSide=payloadSide(ctx,payload,{"user","attacker","source","side"});targetSide=other(actorSide) end
    if targetSide=="player" then
      local b=battleOf(ctx);local dmg=tonumber(payload.damage) or 0
      local maxhp=b and b.player and b.player.mon and b.player.mon.stats and tonumber(b.player.mon.stats.hp) or 1
      local ratio=dmg/math.max(1,maxhp)
      if ratio>=.30 then trigger("concern",1.0)
      elseif ratio>=.085 then trigger("brace",.68) end
    end
  elseif name=="battle.status_inflicted" then
    local targetSide=payloadSide(ctx,payload,{"target","battler","side","targetSide"})
    if targetSide=="player" then trigger("concern",.72) end
  elseif name=="battle.battler_switched" then
    -- The battler-switched event can precede the engine's actual send-out
    -- phase. Do not release the prop here; update() will consume the live
    -- sendingOut edge so the throw and Pokémon arrival stay synchronized.
    local switched=payloadSide(ctx,payload,{"side","battler","target","switchedSide"})
    if switched=="player" then
      initialThrowQueued=false
      local previous=payload.previous or payload.oldBattler
      local mon=type(previous)=="table" and (previous.mon or previous) or nil
      local hp=mon and tonumber(mon.hp)
      if hp==nil or hp>0 then trigger("recall",.96,true) end
    end
  elseif semantic=="battle.fainted" then
    local fainted=payloadSide(ctx,payload,{"battler","target","side","faintedSide","targetSide"})
    -- Give the Pokemon's first collapse frames ownership of the KO, then let
    -- the trainer reaction enter the same composition. This is game-time, so
    -- 4x fast-forward preserves Colosseum's ordering instead of adding a real-
    -- time pause between model and trainer.
    if fainted=="player" then
      local fd=BattleDirector and type(BattleDirector.faintDuration)=="function"
        and BattleDirector:faintDuration(ctx,"player") or nil
      pendingFrustration=math.max(.52,math.min(1.35,(tonumber(fd) or 1.0)*.80))
    end
  elseif name=="battle.ball_thrown" then
    -- The engine has already resolved the authoritative catch result and shake
    -- count before emitting this event.  Mirror only that presentation data;
    -- never recalculate catch odds or consume inventory here.
    local rawShakes=payload.shakes or payload.shakeCount or payload.shake_count or payload.wobbles or payload.rocks
    local rawCaught=payload.caught
    local caught=rawCaught==true or rawCaught==1 or (type(rawCaught)=="string" and rawCaught:lower()=="true")
    -- One choreography on both generations. Successful captures ALWAYS travel
    -- through the same three source shake beats before the outcome branch,
    -- regardless of whether a generation reports 0/nil/3 as its internal
    -- success shake count. Failed captures preserve the engine's exact 0..3
    -- count. Only the post-shake outcome differs.
    local shakes=caught and 3
      or math.max(0,math.min(3,math.floor(tonumber(rawShakes) or 0)))
    local ball=tostring(payload.ball or payload.item or "POKE_BALL")
    local _,_,_,_,_,_,outcomeAt,duration=captureMilestones(shakes)
    capture={age=0,caught=caught,shakes=shakes,ball=ball,duration=duration,done=false,
      lastClock=presentationNow(),outcomeAt=outcomeAt,successSfxPlayed=false,successSfxOwned=false,
      successSfxAvailable=caught and ensureCaptureSuccessAudio(ctx)==true or false,rawShakes=rawShakes,
      sourceBallId=captureBallId(ball)}
    -- Use the trainer's real B1 throw sequence for the release.  `force` is
    -- intentional: capture is a player-authored command and must interrupt an
    -- idle/brace pose cleanly instead of waiting for the generic trigger gate.
    trigger("throw",1.0,true)
  elseif name=="battle.ended" then
    pendingFrustration=nil
    local b=battleOf(ctx);local result=payload.result or payload.outcome or (b and b.result)
    if result=="win" or result=="victory" then trigger("victory",1.0)
    elseif result=="lose" or result=="loss" or result=="defeat" then trigger("defeat",1.0)
    else actionKind=nil;actionAge=0;actionStrength=0 end
  end
end

local function idleMotion()
  local id=performanceId()
  if TrainerPerformance then
    -- Capture trainer motion shares the SAME real-time choreography clock as
    -- the ball/camera. The old path advanced trainer actionAge on battle-speed
    -- time, so at 2x/4x the hand could finish/recover before the real-time ball
    -- release seam and the prop appeared detached from the body.
    if capture and not capture.done then
      local t=math.max(0,tonumber(capture.age) or 0)
      local a,b,c1=captureMilestones(capture.shakes)
      local d=math.max(.001,TrainerPerformance.duration(id,"throw") or 1.48)
      local phase
      if t<a then
        phase=.05+.26*clamp(t/math.max(.001,a),0,1)        -- anticipation -> release
      elseif t<b then
        phase=.31+.48*clamp((t-a)/math.max(.001,b-a),0,1) -- hand release -> follow-through
      elseif t<c1 then
        phase=.79+.21*clamp((t-b)/math.max(.001,c1-b),0,1)
      end
      if phase then
        return TrainerPerformance.idle(id,age,"throw",phase*d,1,"player")
      end
    end
    return currentMotion or TrainerPerformance.idle(id,age,actionKind,actionAge,actionStrength,"player")
  end
  return {breath=.12,look=0,arm=0,shift=0,settle=0,lean=0,turn=0,bob=0,sway=0,command=0,brace=0,forward=0}
end
local function animatedModel(p,motion)
  -- Humanize the source morphs with restrained whole-body weight transfer.
  -- Crucially this rotates around the hips instead of around the model origin
  -- at the feet; the old foot-pivot made every gesture read like a rigid robot
  -- tipping on a stand.
  local root=TrainerPerformance and TrainerPerformance.root(performanceId(),motion) or {pitch=0,roll=0,yaw=(motion.turn or 0)*.8,compression=(motion.brace or 0)*.032}
  local pivotY=(currentConfig and (tonumber(currentConfig.playerPivotY) or tonumber(currentConfig.pivotY))) or 7.4
  local localAnim=Mat4.mul(Mat4.translate(0,pivotY,0),
    Mat4.mul(Mat4.rotateZ(root.roll or 0),
      Mat4.mul(Mat4.rotateX(root.pitch or 0),
        Mat4.mul(Mat4.rotateY(root.yaw or 0),Mat4.translate(0,-pivotY,0)))))
  local compression=root.compression or 0
  return Mat4.mul(Mat4.translate(p.x+motion.sway,p.y+motion.bob-compression,p.z+motion.forward),
    Mat4.mul(Mat4.rotateY(p.yaw),Mat4.mul(Mat4.scale(MODEL_SCALE,MODEL_SCALE,MODEL_SCALE),localAnim)))
end
local function setShader(vp,model,pose,unlit,tint,opacity,motion)
  motion=motion or {}
  if not shader then local loaded=loadScene(nil); if not (loaded and shader) then return false end end
  love.graphics.setShader(shader);shader:send("vp","row",vp);shader:send("model","row",model);shader:send("cameraEye",pose and pose.eye or {54,24,13});shader:send("unlit",unlit or 0);shader:send("tintColor",tint or {1,1,1,1});shader:send("opacity",opacity or 1)
  shader:send("breathMix",motion.breath or 0);shader:send("lookMix",motion.look or 0);shader:send("armMix",motion.arm or 0)
  shader:send("shiftMix",motion.shift or 0);shader:send("settleMix",motion.settle or 0)
  shader:send("commandMix",motion.command or 0);shader:send("braceMix",motion.brace or 0);shader:send("sourcePoseGain",1)
end
function P:drawShadow(ctx,vp,pose)
  if not activeNow then return end;local s=loadScene(ctx);if not s then return end;local p=entryPose();if p.progress<.05 then return end
  local motion=idleMotion();local model=Mat4.translate(p.x+motion.sway,0,p.z);love.graphics.setDepthMode("lequal",false);love.graphics.setBlendMode("alpha","alphamultiply");if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end;love.graphics.setColor(1,1,1,1)
  setShader(vp,model,pose,1,{0,0,0,.58},smooth(p.progress/.50));love.graphics.draw(shadowMesh);love.graphics.setShader()
end
function P:draw(ctx,vp,pose)
  if not activeNow then return end;drawFrames=drawFrames+1;local s=loadScene(ctx);if not s then return end;local p=entryPose();if p.progress<.03 then return end
  local motion=idleMotion();local model=animatedModel(p,motion)
  love.graphics.setDepthMode("lequal",true);love.graphics.setBlendMode("alpha","alphamultiply");if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end;love.graphics.setColor(1,1,1,1)
  setShader(vp,model,pose,0,{1,1,1,1},smooth(p.progress/.38),motion)
  for _,grp in ipairs(s.groups) do
    local d=grp.diffuse or {1,1,1}
    shader:send("materialColor",{d[1] or 1,d[2] or 1,d[3] or 1,grp.alpha or 1})
    shader:send("useTexture",grp.textured and 1 or 0)
    if love.graphics.setDepthMode then love.graphics.setDepthMode("lequal",not (grp.noz or grp.xlu)) end
    love.graphics.draw(grp.mesh)
  end
  if love.graphics.setDepthMode then love.graphics.setDepthMode("lequal",true) end
  love.graphics.setShader()
end


local function transformPoint(m,p)
  local x,y,z=tonumber(p and p[1]) or 0,tonumber(p and p[2]) or 0,tonumber(p and p[3]) or 0
  return {m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12]}
end
local function mixJointPoint(base,poses,index,motion)
  local p=base and base[index];if type(p)~="table" then return nil end
  motion=motion or {}
  local wa=math.max(tonumber(motion.arm) or 0,0)*1.00
  local ws=math.max(tonumber(motion.shift) or 0,0)*.96
  local wt=math.max(tonumber(motion.settle) or 0,0)*.90
  local wc=math.max(tonumber(motion.command) or 0,0)*1.00
  local wb=math.max(tonumber(motion.brace) or 0,0)*.96
  local sum=wa+ws+wt+wc+wb;local action=clamp(sum,0,.84)
  local x,y,z=tonumber(p[1]) or 0,tonumber(p[2]) or 0,tonumber(p[3]) or 0
  if sum>.0001 then
    local tx,ty,tz,tw=0,0,0,0
    local function add(name,w)
      local q=poses and poses[name] and poses[name][index]
      if q and w>0 then tx=tx+(tonumber(q[1]) or x)*w;ty=ty+(tonumber(q[2]) or y)*w;tz=tz+(tonumber(q[3]) or z)*w;tw=tw+w end
    end
    add("arm",wa);add("shift",ws);add("settle",wt);add("command",wc);add("brace",wb)
    if tw>.0001 then x=x+(tx/tw-x)*action;y=y+(ty/tw-y)*action;z=z+(tz/tw-z)*action end
  end
  local secondary=1-action*.92
  local function secondaryPose(name,w)
    local q=poses and poses[name] and poses[name][index]
    if q and w~=0 then x=x+((tonumber(q[1]) or x)-(tonumber(p[1]) or x))*w*secondary;y=y+((tonumber(q[2]) or y)-(tonumber(p[2]) or y))*w*secondary;z=z+((tonumber(q[3]) or z)-(tonumber(p[3]) or z))*w*secondary end
  end
  secondaryPose("breath",tonumber(motion.breath) or 0);secondaryPose("look",tonumber(motion.look) or 0)
  return {x,y,z}
end
local function runtimeReleaseJoint()
  if not (scene and type(scene.jointPositions)=="table" and #scene.jointPositions>0) then return nil end
  if scene.runtimeReleaseJoint~=nil then return scene.runtimeReleaseJoint or nil end

  local base=scene.jointPositions
  local poses=scene.poseJointPositions or {}
  local action=poses.arm or poses.command or poses.settle or base
  local parents=scene.jointParents or {}
  local b=scene.bounds or {};local mn=b.min or {0,0,0};local mx=b.max or {0,16,0};local center=b.center or {0,8,0}
  local h=math.max(.001,(tonumber(mx[2]) or 16)-(tonumber(mn[2]) or 0))
  local cx=tonumber(center[1]) or 0
  local side=tonumber(scene.releaseSide) or -1
  local childCount={}
  for i,parent in ipairs(parents) do
    parent=tonumber(parent) or 0
    if parent>0 then childCount[parent]=(childCount[parent] or 0)+1 end
  end
  local best,bestScore=nil,-1e30

  local function scoreCandidate(i)
    local rest=base[i];local p=action[i] or rest
    if type(rest)~="table" or type(p)~="table" then return nil end
    local bx,by=tonumber(rest[1]) or 0,tonumber(rest[2]) or 0
    local sideX=side*(bx-cx)/h
    local baseY=(by-(tonumber(mn[2]) or 0))/h
    local topologyKnown=#parents==#base
    local leaf=topologyKnown and ((childCount[i] or 0)==0) or nil
    if sideX<=.10 or baseY<=.56 or baseY>=.90 or leaf==false then return nil end
    local dx=(tonumber(p[1]) or bx)-bx
    local dy=(tonumber(p[2]) or by)-by
    local dz=(tonumber(p[3]) or (tonumber(rest[3]) or 0))-(tonumber(rest[3]) or 0)
    local move=math.sqrt(dx*dx+dy*dy+dz*dz)/h
    local handBand=1-math.min(1,math.abs(baseY-.74)/.18)
    return sideX*7.0+move*1.25+handBand*.9+(leaf==true and 2.4 or 0)
  end

  -- Prefer the extractor's source-topology wrist/end-effector when valid.
  local hinted=tonumber(scene.releaseJoint)
  if hinted and hinted>0 and hinted<=#base then
    local score=scoreCandidate(hinted)
    if score then best,bestScore=hinted,score+.35 end
  end
  for i=1,#base do
    local score=scoreCandidate(i)
    if score and score>bestScore then best,bestScore=i,score end
  end

  scene.runtimeReleaseJoint=best or false
  scene.runtimeReleaseJointScore=bestScore>-1e20 and bestScore or nil
  return best
end

local function releaseAnchor()
  -- 1.5.62: the ISO-derived trainer cache records the exact JOBJ chosen as the
  -- lead throwing hand plus that joint's retained source-pose positions. Apply
  -- the same morph weights and root transform as the visible trainer, so the
  -- ball physically sits in the hand until the release seam.
  local idx=runtimeReleaseJoint()
  if idx and idx>0 and scene.jointPositions and scene.jointPositions[idx] then
    local motion=idleMotion()
    local localPoint=mixJointPoint(scene.jointPositions,scene.poseJointPositions,idx,motion)
    if localPoint then
      local b=scene.bounds or {};local mn=b.min or {0,0,0};local mx=b.max or {0,16,0}
      local h=math.max(.001,(tonumber(mx[2]) or 16)-(tonumber(mn[2]) or 0))
      local yn=((tonumber(localPoint[2]) or 0)-(tonumber(mn[2]) or 0))/h
      -- The retail wrist can legitimately dip below half-height during the
      -- throw wind-up. Validate it from the source rest skeleton/topology above,
      -- then transform the live animated point exactly with the visible trainer.
      if yn>=.30 and yn<=.98 then
        local ep=entryPose();local world=animatedModel(ep,motion)
        local out=transformPoint(world,localPoint)
        -- The extractor already selected the source skeleton's throwing-hand
        -- end-effector. Do NOT extend beyond it with a guessed palm vector: that
        -- was the remaining reason the capture prop floated visibly outside the
        -- trainer's fingers. The exact animated source joint is now the release
        -- anchor and therefore moves with the visible hand one-for-one.
        -- Final world-space guard: a stale/malformed cache still cannot release
        -- from the trainer's lower body.
        if out[2]>=2.20 then return out,"source-hand-end-effector" end
      end
    end
  end
  -- Fail-open for old caches: retain the old shoulder heuristic, but make it a
  -- fallback rather than the primary capture origin.
  local id=performanceId()
  local pf=TrainerPerformance and TrainerPerformance.profile(id) or {lead=1}
  local lead=tonumber(pf.lead) or 1
  local rigName=(currentConfig and currentConfig.rig) or id
  local rp=TrainerRig and scene and TrainerRig.profile(rigName,scene.bounds) or nil
  local shoulderLocal=rp and ((rp.minY or 0)+(rp.shoulder or .72)*(rp.height or 1)) or (4.35/MODEL_SCALE)
  local lateralLocal=rp and ((rp.halfWidth or 1)*math.max(.52,tonumber(rp.shoulderRadius) or .22)) or (0.70/MODEL_SCALE)
  local releaseY=clamp(shoulderLocal*MODEL_SCALE-.08,3.55,5.25)
  local releaseX=clamp(lateralLocal*MODEL_SCALE*.92,.48,1.02)
  return {FINAL_X-releaseX*lead,releaseY,FINAL_Z-0.46},"heuristic"
end

local function normalThrowBallPose()
  if actionKind~="throw" then return nil end
  local id=performanceId();local d=TrainerPerformance and TrainerPerformance.duration(id,"throw") or 1.48
  local phase=clamp(actionAge/math.max(.001,d),0,1)
  if phase<.31 or phase>.79 then return nil end
  local u=clamp((phase-.31)/.48,0,1)
  local start=releaseAnchor()
  local target={SENDOUT_TARGET_X,3.85,SENDOUT_TARGET_Z}
  local x=start[1]+(target[1]-start[1])*u
  local z=start[3]+(target[3]-start[3])*u
  local y=start[2]+(target[2]-start[2])*u+math.sin(u*math.pi)*4.65
  return {x,y,z,u,kind="sendout"}
end

local function capturePhase(c)
  if not c then return nil,0 end
  local t=math.max(0,tonumber(c.age) or 0)
  local a,b,c1,d,e,f,g=captureMilestones(c.shakes)
  if t<a then return "charge",t/math.max(.001,CAPTURE_T.charge) end
  if t<b then return "throw",(t-a)/CAPTURE_T.throw end
  if t<c1 then return "impact",(t-b)/CAPTURE_T.impact end
  if t<d then return "absorb",(t-c1)/CAPTURE_T.absorb end
  if t<e then return "fall",(t-d)/CAPTURE_T.fall end
  if t<f then return "settle",(t-e)/CAPTURE_T.settle end
  if t<g then
    local elapsed=math.max(0,t-f)
    return "shake",(elapsed/CAPTURE_T.shake)%1
  end
  return c.caught and "caught" or "breakout",math.max(0,(t-g)/CAPTURE_T.outcome)
end

local function captureBallPose()
  local c=capture
  if not c or c.done then return nil end
  local phase,u=capturePhase(c)
  local liveStart,anchorKind=releaseAnchor()
  -- Stay physically attached to the animated throwing hand through the first
  -- portion of the retail release motion. Older builds froze the projectile on
  -- the first throw frame, while the hand was still moving, which reintroduced
  -- a visible gap even with the correct wrist/end-effector selected.
  local releaseU=.11
  local handAttached=(phase=="charge") or (phase=="throw" and (tonumber(u) or 0)<releaseU)
  if handAttached then c.releasePoint=nil;c.releaseAnchorKind=anchorKind
  elseif not c.releasePoint then c.releasePoint={liveStart[1],liveStart[2],liveStart[3]};c.releaseAnchorKind=anchorKind end
  local start=handAttached and liveStart or (c.releasePoint or liveStart)
  local target={CAPTURE_TARGET_X,3.75,CAPTURE_TARGET_Z}
  local ground={CAPTURE_TARGET_X,0.31,CAPTURE_TARGET_Z}
  if phase=="charge" then
    -- No giant body-centred aura: the authentic prop simply reads in the hand.
    local pulse=.018*math.sin(clamp(u,0,1)*math.pi*4)
    -- The retail prop is a solid physical object in the trainer's hand. Do not
    -- fade it in: partial alpha was another source of the see-through read.
    return {start[1],start[2]+pulse,start[3],0,kind=phase,phaseU=u,spin=0,opacity=1}
  elseif phase=="throw" then
    if handAttached then
      return {start[1],start[2],start[3],0,kind=phase,phaseU=u,spin=0,trail=0,opacity=1,handAttached=true}
    end
    local q=smooth(clamp((u-releaseU)/math.max(.001,1-releaseU),0,1))
    return {start[1]+(target[1]-start[1])*q,
      start[2]+(target[2]-start[2])*q+math.sin(q*math.pi)*5.15,
      start[3]+(target[3]-start[3])*q,0,kind=phase,phaseU=u,
      spin=q*math.pi*2.35,trail=math.sin(q*math.pi),opacity=1}
  elseif phase=="impact" then
    local q=clamp(u,0,1)
    return {target[1],target[2]+.12*math.sin(q*math.pi),target[3],0,kind=phase,phaseU=u,spin=0,flare=1-q*.50,opacity=1}
  elseif phase=="absorb" then
    local q=clamp(u,0,1)
    return {target[1],target[2]+math.sin(q*math.pi)*.46,target[3],0,kind=phase,phaseU=u,spin=0,flare=(1-q)*.42+.08,opacity=1}
  elseif phase=="fall" then
    local q=smooth(u)
    return {target[1],target[2]+(ground[2]-target[2])*q+math.sin(q*math.pi)*.18,target[3],0,kind=phase,phaseU=u,
      spin=(1-q)*math.pi*.48,trail=(1-q)*.24,opacity=1}
  elseif phase=="settle" then
    local q=clamp(u,0,1)
    local bounce=math.abs(math.sin(q*math.pi*2))*math.max(0,1-q)*.17
    return {ground[1],ground[2]+bounce,ground[3],2.58,kind=phase,phaseU=u,rock=math.sin(q*math.pi*2)*.055,flare=math.max(0,1-q*2)*.20,opacity=1}
  elseif phase=="shake" then
    local _,_,_,_,_,f=captureMilestones(c.shakes)
    local elapsed=math.max(0,(c.age or 0)-f)
    local idx=math.floor(elapsed/CAPTURE_T.shake)
    local q=(elapsed/CAPTURE_T.shake)-idx
    local dir=(idx%2==0) and -1 or 1
    local maxRock=math.rad(27)
    local rock=0
    -- One authored-looking struggle beat, not a sine-wave spinner:
    --   0-.10  planted/rest
    --  .10-.28  sharp primary tilt
    --  .28-.48  return to centre
    --  .48-.62  small physical counter-recoil
    --  .62-.75  settle to centre
    --  .75-1.0  readable pause before the next shake
    -- Alternate the primary side on consecutive shakes, matching the visual
    -- cadence of Colosseum while keeping every shake discrete and countable.
    if q<.10 then
      rock=0
    elseif q<.28 then
      rock=dir*maxRock*smooth((q-.10)/.18)
    elseif q<.48 then
      rock=dir*maxRock*(1-smooth((q-.28)/.20))
    elseif q<.62 then
      rock=-dir*maxRock*.34*smooth((q-.48)/.14)
    elseif q<.75 then
      rock=-dir*maxRock*.34*(1-smooth((q-.62)/.13))
    end
    return {ground[1],ground[2],ground[3],0,kind=phase,phaseU=u,shakeQ=q,rock=rock,shakeIndex=idx+1,opacity=1}
  elseif phase=="caught" then
    return {ground[1],ground[2],ground[3],3.02,kind=phase,phaseU=u,flare=math.max(0,1-clamp(u,0,1))*.12,opacity=1}
  elseif phase=="breakout" then
    local q=clamp(u,0,1)
    -- Hold the failed ball for a beat before the native miss/open animation so
    -- the last completed shake is readable; do not instantly pop the Pokémon.
    local open=smooth(clamp((q-.10)/.68,0,1))
    local hop=math.sin(open*math.pi)*.25
    return {ground[1],ground[2]+hop,ground[3],3.08+open*.18,kind=phase,phaseU=u,rock=math.sin(open*math.pi)*.08,flare=math.max(0,1-open)*.34,opacity=1}
  end
end

local function ballPose()
  return captureBallPose() or normalThrowBallPose()
end

function P:captureStatus(ctx)
  if not capture then return {active=false} end
  local phase,u=capturePhase(capture)
  return {active=not capture.done,phase=phase,progress=u,caught=capture.caught,shakes=capture.shakes,ball=capture.ball,age=capture.age,duration=capture.duration,
    successSfxPlayed=capture.successSfxPlayed==true,successSfxOwned=capture.successSfxOwned==true,successSfxAvailable=capture.successSfxAvailable==true,
    releaseAnchorKind=capture.releaseAnchorKind}
end

-- BattleRuntime uses this narrow query to intercept ONLY Gen1Recomp's stock
-- Caught_Mon fanfare once the ISO-derived me_snatch source has been verified
-- available for this successful capture. If source audio is missing, this
-- deliberately returns false so the native sound fails open instead of leaving
-- a silent catch.
function P:suppressesNativeCaughtAudio(ctx)
  return capture~=nil and capture.caught==true and (capture.successSfxAvailable==true or capture.successSfxOwned==true)
end
function P:captureBallPosition(ctx)
  local bp=captureBallPose();if not bp then return nil end
  return {bp[1],bp[2],bp[3],phase=bp.kind,progress=bp.phaseU or 0,shakeIndex=bp.shakeIndex}
end

function P:captureEnemyScale(ctx)
  if not capture or capture.done then return 1 end
  local phase,u=capturePhase(capture)
  if phase=="charge" or phase=="throw" or phase=="impact" then return 1 end
  if phase=="absorb" then return math.max(0,1-smooth(clamp((u-.10)/.72,0,1))) end
  if phase=="breakout" then return smooth(clamp((u-.27)/.54,0,1)) end
  return 0
end

function P:captureHidesEnemy(ctx)
  return self:captureEnemyScale(ctx)<=.015
end

local function drawBallPart(mesh,vp,pose,model,tint)
  setShader(vp,model,pose,1,tint,1,{})
  love.graphics.draw(mesh)
end
local function captureBallTints()
  -- Procedural fallback only. Native ISO props keep their exact source texture.
  local id=capture and tostring(capture.ball or "POKE_BALL"):upper() or "POKE_BALL"
  if id:find("GREAT",1,true) then return {.96,.96,.94,1},{.08,.22,.68,1},{.78,.08,.06,1} end
  if id:find("ULTRA",1,true) then return {.96,.96,.94,1},{.045,.045,.055,1},{.90,.72,.08,1} end
  if id:find("MASTER",1,true) then return {.96,.96,.94,1},{.38,.12,.58,1},{.90,.25,.50,1} end
  if id:find("SAFARI",1,true) then return {.94,.94,.86,1},{.30,.48,.18,1},{.16,.22,.10,1} end
  return {.96,.96,.94,1},{.84,.08,.07,1},{.035,.035,.04,1}
end
function P:drawBall(ctx,vp,pose)
  local bp=ballPose()
  if not bp then return false end
  local captureActive=capture and not capture.done
  local sourcePropActive=captureActive or bp.kind=="sendout"

  -- Primary path: exact ball-type-specific prop and HSD animation compiled from
  -- Colosseum's snatch_attack / snatch_ball_land / snatch_shake / snatch_miss.
  -- The same retail Poké Ball prop also replaces the procedural sphere for the
  -- player's normal send-out throw.
  if sourcePropActive then
    local asset,sourceId,sourcePhase=sourceBallAsset(bp.kind)
    local handlers=V.WazaHandlers
    if asset and handlers and type(handlers.drawAsset)=="function" then
      local model=sourceBallModel(asset,bp)
      local frame=sourceAssetFrame(asset,bp.kind,bp.phaseU,bp)
      -- The ball is a closed opaque HSD prop. Never use the old capture
      -- "depth always / no writes" path here: rear triangles then overwrite the
      -- front shell and make the ball look clipped/see-through.
      local ok,drew=pcall(handlers.drawAsset,ctx,asset,vp,model,frame,{
        opacity=bp.opacity or 1,depthAlways=false,forceOpaque=true,cullMode="none"})
      if ok and drew==true then
        captureSourceDrawFrames=captureSourceDrawFrames+1;ballDrawFrames=ballDrawFrames+1
        return true
      end
      if not ok then captureAssetError=tostring(drew) end
    end
  end

  -- Fail-open only: a deliberately small/simple sphere if the source cache was
  -- not rebuilt yet. It must never masquerade as the fidelity path.
  if not ensureBall() then
    log(ctx,"warn","3D capture ball unavailable: %s",tostring(ballError or "unknown"))
    return false
  end
  local grounded=(bp.kind=="caught" or bp.kind=="shake" or bp.kind=="settle" or bp.kind=="breakout")
  local scale=grounded and .180 or .188
  local roll=bp.rock or (grounded and 0 or (tonumber(bp.spin) or 0))
  local model=Mat4.mul(Mat4.translate(bp[1],bp[2],bp[3]),
    Mat4.mul(Mat4.rotateZ(roll),Mat4.scale(scale,scale,scale)))
  -- Fallback obeys the same solid-object depth contract as the source prop.
  -- Rear triangles may render, but depth testing/writes prevent them from ever
  -- punching through the front shell on stale or partially rebuilt caches.
  love.graphics.setDepthMode("lequal",true)
  love.graphics.setBlendMode("alpha","alphamultiply")
  if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end
  love.graphics.setColor(1,1,1,1)
  local white,top,band=captureBallTints()
  drawBallPart(ballMeshWhite,vp,pose,model,white)
  drawBallPart(ballMeshRed,vp,pose,model,top)
  drawBallPart(ballMeshBlack,vp,pose,model,band)

  -- Keep fallback flashes tightly local to the prop. The giant synthetic halo
  -- that intersected the trainer torso is intentionally removed; source WZX
  -- owns the visual language whenever the capture cache is available.
  local flare=math.max(0,tonumber(bp.flare) or 0)
  if captureActive and flare>.04 and bp.kind~="charge" and bp.kind~="throw" then
    love.graphics.setShader();pcall(love.graphics.setBlendMode,"add","alphamultiply")
    local tint=(bp.kind=="impact" or bp.kind=="settle") and {1.0,.62,.22,.36*flare}
      or (bp.kind=="absorb" and {.98,.20,.56,.30*flare})
      or (bp.kind=="breakout" and {.58,.22,1.0,.38*flare}) or {.76,.46,1.0,.24*flare}
    local ss=scale*1.42
    local shell=Mat4.mul(Mat4.translate(bp[1],bp[2],bp[3]),Mat4.scale(ss,ss,ss))
    drawBallPart(ballMeshWhite,vp,pose,shell,tint)
    love.graphics.setShader();love.graphics.setBlendMode("alpha","alphamultiply")
  end
  love.graphics.setShader();love.graphics.setDepthMode("lequal",true)
  ballDrawFrames=ballDrawFrames+1
  return true
end

function P:setArenaProfile(def)
  local t=def and def.trainers and def.trainers.player
  local playerMon=def and def.pokemon and def.pokemon.player
  local enemyMon=def and def.pokemon and def.pokemon.enemy
  if t then FINAL_X=tonumber(t[1]) or FINAL_X;FINAL_Z=tonumber(t[2]) or FINAL_Z end
  if playerMon then SENDOUT_TARGET_X=tonumber(playerMon[1]) or SENDOUT_TARGET_X;SENDOUT_TARGET_Z=tonumber(playerMon[2]) or SENDOUT_TARGET_Z end
  if enemyMon then CAPTURE_TARGET_X=tonumber(enemyMon[1]) or CAPTURE_TARGET_X;CAPTURE_TARGET_Z=tonumber(enemyMon[2]) or CAPTURE_TARGET_Z end
  local sc=def and def.trainerScale and tonumber(def.trainerScale.player)
  if sc then arenaModelScale=sc;applyModelScale() end
end

function P:anchor(y) return {FINAL_X,y or 7.0,FINAL_Z} end
function P:resetRuntime()
  stopCaptureSuccessAudio()
  scene=nil;sceneKey=nil;shader=nil;shadowImage=nil;shadowMesh=nil;errorText=nil
  currentConfig=nil;currentModel="red";currentReason=nil;MODEL_SCALE=arenaModelScale
  activeNow=false;age=0;drawFrames=0;actionKind=nil;actionAge=0;actionStrength=0;lastSendingOut=false
  ballMeshWhite=nil;ballMeshRed=nil;ballMeshBlack=nil;ballTexture=nil;ballError=nil;ballDrawFrames=0
  captureAssetIndex=nil;captureAssetError=nil;captureSourceDrawFrames=0
  return true
end
function P:status() return {active=activeNow,ready=scene~=nil,error=errorText,model=(currentConfig and currentConfig.label) or tostring(currentModel):upper(),modelSource=currentConfig and currentConfig.source or nil,modelReason=currentReason,pose="NativeHSD-source-hand-anchored-throw-player",action=actionKind,modelScale=MODEL_SCALE,final={FINAL_X,0,FINAL_Z},ballTarget={SENDOUT_TARGET_X,0,SENDOUT_TARGET_Z},captureTarget={CAPTURE_TARGET_X,0,CAPTURE_TARGET_Z},drawFrames=drawFrames,ballReady=(captureAssetIndex and true) or ballMeshRed~=nil,ballError=ballError,captureAssetError=captureAssetError,captureSourceDrawFrames=captureSourceDrawFrames,ballDrawFrames=ballDrawFrames,releaseJoint=scene and scene.releaseJoint or nil,releaseJointScore=scene and scene.releaseJointScore or nil,capture=P:captureStatus()} end
return P
