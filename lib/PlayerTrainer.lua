local V = ...
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
  float wa=max(armMix,0.0)*0.42*sourcePoseGain, ws=max(shiftMix,0.0)*0.60*sourcePoseGain, wt=max(settleMix,0.0)*0.48*sourcePoseGain;
  float wc=max(commandMix,0.0)*0.38*sourcePoseGain, wb=max(braceMix,0.0)*0.42*sourcePoseGain;
  float sum=wa+ws+wt+wc+wb;
  /* Keep a restrained amount of the real Colosseum source performance.
     This preserves authored elbow/wrist/hand relationships without overdriving
     the native non-bind silhouette. */
  float action=clamp(sum*0.20,0.0,0.135);
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
  vec4 world=model*vec4(p,1.0); worldPos=world.xyz;
  worldNormal=normalize((model*vec4(normalize(n),0.0)).xyz); return vp*world;
}]]
local PIXEL=[[
uniform vec3 cameraEye; uniform vec4 tintColor; uniform float unlit; uniform float opacity;
varying vec3 worldPos; varying vec3 worldNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec4 texel=Texel(texture,uv); float a=texel.a*tintColor.a*opacity*color.a;
  if (a<0.08) discard; if (unlit>0.5) return vec4(tintColor.rgb,a);
  vec3 n=normalize(worldNormal); vec3 lightDir=normalize(vec3(-0.42,0.82,0.38));
  float ndl=dot(n,lightDir); float key=max(ndl,0.0); float back=max(-ndl,0.0); float hemi=clamp(n.y*0.5+0.5,0.0,1.0);
  vec3 viewDir=normalize(cameraEye-worldPos); float rim=pow(1.0-clamp(abs(dot(n,viewDir)),0.0,1.0),2.4);
  float light=0.73+key*0.25+back*0.055+hemi*0.055; vec3 rgb=texel.rgb*light+vec3(0.040,0.047,0.055)*rim;
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
local ballMeshRed,ballMeshWhite,ballMeshBlack,ballTexture
local FINAL_X,FINAL_Z=13.2,25.8
local BALL_TARGET_X,BALL_TARGET_Z=0,14.5
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
  if ballMeshRed then return true end
  if not (love and love.graphics and love.image) then return false end
  local ok,id=pcall(love.image.newImageData,1,1); if not ok then return false end
  id:setPixel(0,0,1,1,1,1); ballTexture=love.graphics.newImage(id)
  local red, white, black = {}, {}, {}
  -- upper and lower hemispheres with a narrow black equator band
  for j=0,3 do
    local a=.10+(j/4)*(math.pi/2-.10); local b=.10+((j+1)/4)*(math.pi/2-.10)
    local top=sphereBand(a,b,1,14); for _,v in ipairs(top) do red[#red+1]=v end
    local bot=sphereBand(-b,-a,1,14); for _,v in ipairs(bot) do white[#white+1]=v end
  end
  local eq=sphereBand(-.10,.10,1.015,14); for _,v in ipairs(eq) do black[#black+1]=v end
  local function make(vs)
    local m=love.graphics.newMesh(FORMAT,vs,'triangles','static');m:setTexture(ballTexture);return m
  end
  ballMeshRed,ballMeshWhite,ballMeshBlack=make(red),make(white),make(black)
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

-- The generated Dakim cache stores a complete authored clip-1 idle sample in
-- BreathPosition. Make that coherent frame his base pose in player-model mode
-- too; duplicating it across streams prevents generic actions from snapping him
-- back to the narrow frame-0 silhouette.
local function dakimAuthoredIdle(vertices)
  if currentModel~="dakim" then return vertices or {} end
  local out={}
  for i,v in ipairs(vertices or {}) do
    local row={};for j=1,#v do row[j]=v[j] end
    local x,y,z=tonumber(v[9]) or tonumber(v[1]) or 0,tonumber(v[10]) or tonumber(v[2]) or 0,tonumber(v[11]) or tonumber(v[3]) or 0
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
    local path=g.texture and g.texture.path;local img=textures[path]
    if not img then img,err=imageFromRaw(g.texture);if not img then errorText=tostring(err);return nil,errorText end;textures[path]=img end
    -- The old strap relief was measured on the unrelated heuristic model.
    -- Direct Red keeps his authored disc geometry; the legacy procedural limb rig
    -- is no longer part of the shipping renderer.
    local weighted=currentModel=="dakim"
      and dakimAuthoredIdle(g.vertices)
      or preparePlayerVertices(g.vertices or {},currentModel==DEFAULT_PLAYER_MODEL and not cfg.directSource)
    local ok,mesh=pcall(love.graphics.newMesh,FORMAT,weighted,"triangles","static")
    if not ok then errorText=(cfg.label or wanted).." mesh "..i..": "..tostring(mesh);return nil,errorText end
    mesh:setTexture(img);groups[#groups+1]={mesh=mesh,material=g.material}
  end
  local ok,sh=pcall(love.graphics.newShader,VERTEX,PIXEL);if not ok or not sh then errorText=(cfg.label or wanted).." shader: "..tostring(sh or "unavailable");return nil,errorText end
  shader=sh;local sok,serr=ensureShadow();if not sok then errorText=(cfg.label or wanted).." shadow: "..tostring(serr);return nil,errorText end
  scene={groups=groups,bounds=cache.bounds,source=cache.source,textures=textures};sceneKey=wanted
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
function P:shouldRender(ctx) return enabled(ctx) end
local trigger,performanceId
function P:begin(ctx)
  battleKey=battleOf(ctx);age=0;actionKind=nil;actionAge=0;actionStrength=0;initialThrowQueued=false;initialOpeningQueued=false;lastSendingOut=false;resultSeen=nil;drawFrames=0;currentMotion=nil
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
function P:update(ctx,dt)
  local b=battleOf(ctx);if b~=battleKey then battleKey=b;age=0;actionKind=nil;actionAge=0;actionStrength=0;initialThrowQueued=false;initialOpeningQueued=false;lastSendingOut=false;resultSeen=nil;currentMotion=nil;performanceState=TrainerPerformance and TrainerPerformance.resetState(performanceState,"red") or nil end
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
  if activeNow and TrainerPerformance then
    local id=performanceId();local duration=actionKind and TrainerPerformance.duration(id,actionKind) or nil
    if actionKind and actionAge>(duration or 1.2) then actionKind=nil;actionStrength=0 end
    currentMotion,performanceState=TrainerPerformance.step(performanceState,id,age,actionKind,actionAge,actionStrength,"player",dt)
  end
end
function P:finish() battleKey=nil;age=0;activeNow=false;actionKind=nil;actionAge=0;actionStrength=0;initialThrowQueued=false;initialOpeningQueued=false;lastSendingOut=false;resultSeen=nil;currentMotion=nil;performanceState=TrainerPerformance and TrainerPerformance.resetState(performanceState,"red") or nil end
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
  if name=="battle.move_used" then
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
  elseif name=="battle.damage_dealt" then
    local targetSide=payloadSide(ctx,payload,{"target","defender","targetSide","defenderSide"})
    if not targetSide then local actorSide=payloadSide(ctx,payload,{"user","attacker","source","side"});targetSide=other(actorSide) end
    if targetSide=="player" then
      local b=battleOf(ctx);local dmg=tonumber(payload.damage) or 0
      local maxhp=b and b.player and b.player.mon and b.player.mon.stats and tonumber(b.player.mon.stats.hp) or 1
      local ratio=dmg/math.max(1,maxhp)
      trigger(ratio>=0.28 and "concern" or "brace",ratio>=0.28 and 1.0 or 0.76)
    end
  elseif name=="battle.status_inflicted" then
    local targetSide=payloadSide(ctx,payload,{"target","battler","side","targetSide"})
    if targetSide=="player" then trigger("concern",.72) end
  elseif name=="battle.battler_switched" then
    -- The battler-switched event can precede the engine's actual send-out
    -- phase. Do not release the prop here; update() will consume the live
    -- sendingOut edge so the throw and Pokémon arrival stay synchronized.
    local switched=payloadSide(ctx,payload,{"side","battler","target","switchedSide"})
    if switched=="player" then initialThrowQueued=false end
  elseif name=="battle.fainted" then
    local fainted=payloadSide(ctx,payload,{"battler","target","side","faintedSide","targetSide"})
    if fainted=="player" then trigger("frustration",1.0) end
  elseif name=="battle.ended" then
    local b=battleOf(ctx);local result=payload.result or payload.outcome or (b and b.result)
    if result=="win" or result=="victory" then trigger("victory",1.0)
    elseif result=="lose" or result=="loss" or result=="defeat" then trigger("defeat",1.0)
    else actionKind=nil;actionAge=0;actionStrength=0 end
  end
end

local function idleMotion()
  local id=performanceId()
  if TrainerPerformance then return currentMotion or TrainerPerformance.idle(id,age,actionKind,actionAge,actionStrength,"player") end
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
  shader:send("breathMix",currentModel=="dakim" and 0 or (motion.breath or 0));shader:send("lookMix",motion.look or 0);shader:send("armMix",motion.arm or 0)
  shader:send("shiftMix",motion.shift or 0);shader:send("settleMix",motion.settle or 0)
  shader:send("commandMix",motion.command or 0);shader:send("braceMix",motion.brace or 0);shader:send("sourcePoseGain",1+(tonumber(motion.sourceAuthority) or 0)*.28)
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
  setShader(vp,model,pose,0,{1,1,1,1},smooth(p.progress/.38),motion);for _,g in ipairs(s.groups) do love.graphics.draw(g.mesh) end;love.graphics.setShader()
end


local function ballPose()
  if actionKind~="throw" then return nil end
  local id=performanceId();local d=TrainerPerformance and TrainerPerformance.duration(id,"throw") or 1.48
  local phase=clamp(actionAge/math.max(.001,d),0,1)
  if phase<.31 or phase>.79 then return nil end
  local u=clamp((phase-.31)/.48,0,1)
  local pf=TrainerPerformance and TrainerPerformance.profile(id) or {lead=1}
  local lead=tonumber(pf.lead) or 1
  -- Release from the selected model's actual shoulder/hand band instead of a
  -- global Y=3.25. Wes/Dakim/Red have very different authored heights, so the
  -- old constant could put the ball inside the chest or below the throwing arm.
  -- World-space X reverses because player trainers face into the arena at pi.
  local rigName=(currentConfig and currentConfig.rig) or id
  local rp=TrainerRig and scene and TrainerRig.profile(rigName,scene.bounds) or nil
  local shoulderLocal=rp and ((rp.minY or 0)+(rp.shoulder or .72)*(rp.height or 1)) or (4.35/MODEL_SCALE)
  local lateralLocal=rp and ((rp.halfWidth or 1)*math.max(.52,tonumber(rp.shoulderRadius) or .22)) or (0.70/MODEL_SCALE)
  local releaseY=clamp(shoulderLocal*MODEL_SCALE-.08,3.55,5.25)
  local releaseX=clamp(lateralLocal*MODEL_SCALE*.92,.48,1.02)
  local start={FINAL_X-releaseX*lead,releaseY,FINAL_Z-0.46}
  local target={BALL_TARGET_X,3.85,BALL_TARGET_Z}
  -- Arc rises enough to read clearly in the wider Colosseum cameras.
  local x=start[1]+(target[1]-start[1])*u
  local z=start[3]+(target[3]-start[3])*u
  local y=start[2]+(target[2]-start[2])*u+math.sin(u*math.pi)*4.65
  return {x,y,z,u}
end
local function drawBallPart(mesh,vp,pose,model,tint)
  setShader(vp,model,pose,1,tint,1,{})
  love.graphics.draw(mesh)
end
function P:drawBall(ctx,vp,pose)
  local bp=ballPose();if not bp or not ensureBall() then return end
  local spin=bp[4]*math.pi*7
  local model=Mat4.mul(Mat4.translate(bp[1],bp[2],bp[3]),Mat4.mul(Mat4.rotateY(spin),Mat4.mul(Mat4.rotateZ(spin*.55),Mat4.scale(.38,.38,.38))))
  love.graphics.setDepthMode("lequal",true);love.graphics.setBlendMode("alpha","alphamultiply");if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end
  love.graphics.setColor(1,1,1,1)
  drawBallPart(ballMeshWhite,vp,pose,model,{.96,.96,.94,1});drawBallPart(ballMeshRed,vp,pose,model,{.84,.08,.07,1});drawBallPart(ballMeshBlack,vp,pose,model,{.035,.035,.04,1})
  love.graphics.setShader()
end

function P:setArenaProfile(def)
  local t=def and def.trainers and def.trainers.player
  local mon=def and def.pokemon and def.pokemon.player
  if t then FINAL_X=tonumber(t[1]) or FINAL_X;FINAL_Z=tonumber(t[2]) or FINAL_Z end
  if mon then BALL_TARGET_X=tonumber(mon[1]) or BALL_TARGET_X;BALL_TARGET_Z=tonumber(mon[2]) or BALL_TARGET_Z end
  local sc=def and def.trainerScale and tonumber(def.trainerScale.player)
  if sc then arenaModelScale=sc;applyModelScale() end
end

function P:anchor(y) return {FINAL_X,y or 7.0,FINAL_Z} end
function P:resetRuntime()
  scene=nil;sceneKey=nil;shader=nil;shadowImage=nil;shadowMesh=nil;errorText=nil
  currentConfig=nil;currentModel="red";currentReason=nil;MODEL_SCALE=arenaModelScale
  activeNow=false;age=0;drawFrames=0;actionKind=nil;actionAge=0;actionStrength=0;lastSendingOut=false
  ballMeshWhite=nil;ballMeshRed=nil;ballMeshBlack=nil
  return true
end
function P:status() return {active=activeNow,ready=scene~=nil,error=errorText,model=(currentConfig and currentConfig.label) or tostring(currentModel):upper(),modelSource=currentConfig and currentConfig.source or nil,modelReason=currentReason,pose="NativeHSD-clip1-nonbind-shoulder-anchored-throw-player",action=actionKind,modelScale=MODEL_SCALE,final={FINAL_X,0,FINAL_Z},ballTarget={BALL_TARGET_X,0,BALL_TARGET_Z},drawFrames=drawFrames} end
return P
