local V = ...
local BattleDirector=V.BattleDirector
local GeneratedAssets=V.GeneratedAssets
local mod, Mat4, TrainerRig = V.mod, V.Mat4, V.TrainerRig
local TrainerPerformance=V.TrainerPerformance
local BattleSides=V.BattleSides
local TrainerRoster=V.TrainerRoster
local RuntimeMeshCache=V.RuntimeMeshCache
local TrainerMorph=V.TrainerMorph
local T = {}

local function platformOS()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok and v then return tostring(v) end
  end
  return "Unknown"
end
local ANDROID_RUNTIME=platformOS()=="Android"
local WINDOWS_RUNTIME=platformOS()=="Windows"

-- Mesh layouts now come from TrainerMorph so Trainer and PlayerTrainer cannot
-- drift apart. DENSE is the unchanged 44-float cache/sidecar layout; COMPACT
-- is only used by the CPU fallback binding path.
local FORMAT=TrainerMorph.DENSE_FORMAT
local FORMAT_COMPACT=TrainerMorph.COMPACT_FORMAT
local DENSE_MESH=TrainerMorph.dense()
local VERTEX=TrainerMorph.VERTEX
local PIXEL = [[
uniform vec3 cameraEye;
uniform vec4 tintColor;
uniform vec4 materialColor;
uniform float useTexture;
uniform float unlit;
uniform float opacity;
uniform float flipV;
varying vec3 worldPos;
varying vec3 worldNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec2 sampleUV=vec2(uv.x,mix(uv.y,1.0-uv.y,flipV));
  vec4 texel = Texel(texture,sampleUV);
  float texAlpha=mix(1.0,texel.a,useTexture);
  float a = texAlpha * materialColor.a * tintColor.a * opacity * color.a;
  if (a < 0.08) discard;
  vec3 sourceBase=mix(materialColor.rgb,texel.rgb,useTexture);
  if (unlit > 0.5) return vec4(sourceBase*tintColor.rgb,a);
  vec3 n = normalize(worldNormal);
  vec3 lightDir = normalize(vec3(-0.42,0.82,0.38));
  float key = abs(dot(n,lightDir));
  float hemi = clamp(n.y*0.5+0.5,0.0,1.0);
  vec3 viewDir = normalize(cameraEye-worldPos);
  float rim = pow(1.0-clamp(abs(dot(n,viewDir)),0.0,1.0),2.4);
  float light = 0.72 + key*0.24 + hemi*0.07;
  vec3 rgb = sourceBase * light;
  rgb += vec3(0.055,0.075,0.10)*rim;
  rgb = clamp((rgb-vec3(0.5))*1.035+vec3(0.5),vec3(0.0),vec3(1.0));
  return vec4(rgb*tintColor.rgb,a);
}
]]

local scene, sceneKey, shader, shadowImage, shadowMesh
local sceneCache,sceneErrors,sceneUseSerial={}, {}, 0
local prewarmQueue,prewarmSeen,prewarmNextAt={}, {}, 0
local MAX_RESIDENT_TRAINERS=ANDROID_RUNTIME and 3 or 6
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
local TRAINER_RUNTIME_MESH_VERSION=1
local trainerRuntimeHits,trainerRuntimeWrites,trainerRuntimeFallbacks=0,0,0
local function trainerRuntimeTag(wanted) return tostring(wanted or "trainer"):gsub("[^%w_%-]","_") end
local function trainerRuntimeRoot(wanted) return "cache/runtime_mesh_v1/trainers/"..trainerRuntimeTag(wanted) end
local function trainerRuntimeMetaPath(wanted) return trainerRuntimeRoot(wanted).."/base.lua" end
local function trainerRuntimeBinPath(wanted,i) return trainerRuntimeRoot(wanted)..("/base_%02d.f32"):format(tonumber(i) or 0) end
local function trainerSourceSize(cfg)
  local info=GeneratedAssets and GeneratedAssets.info and GeneratedAssets.info(cfg and cfg.cache) or nil
  return info and tonumber(info.size) or nil
end
local function trainerRuntimeUsable(meta,wanted,sourceSize)
  if not (RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function") then return false end
  if type(meta)~="table" or tonumber(meta.runtimeMeshVersion)~=TRAINER_RUNTIME_MESH_VERSION or tonumber(meta.formatVersion)~=26 then return false end
  if not sourceSize or tonumber(meta.sourceSize)~=sourceSize or type(meta.groups)~="table" or #meta.groups==0 then return false end
  for i,g in ipairs(meta.groups) do
    local path=type(g)=="table" and (g.runtimeBin or trainerRuntimeBinPath(wanted,i)) or nil
    local info=path and GeneratedAssets.info and GeneratedAssets.info(path) or nil
    local size=info and tonumber(info.size)
    if not size or size<176 or size%176~=0 then return false end
  end
  return true
end
local function trainerGroupCompact(g,wanted,i)
  local out={}
  for k,v in pairs(g or {}) do if k~="vertices" and k~="verticesPacked" then out[k]=v end end
  out.runtimeBin=trainerRuntimeBinPath(wanted,i)
  return out
end
local function writeTrainerRuntimeMeta(wanted,cache,sourceSize)
  if not (RuntimeMeshCache and RuntimeMeshCache.writeLua and sourceSize) then return false end
  local out={runtimeMeshVersion=TRAINER_RUNTIME_MESH_VERSION,sourceSize=sourceSize,formatVersion=cache.formatVersion}
  for k,v in pairs(cache or {}) do if k~="groups" then out[k]=v end end
  out.groups={}
  for i,g in ipairs(cache.groups or {}) do out.groups[i]=trainerGroupCompact(g,wanted,i) end
  local ok=RuntimeMeshCache.writeLua(trainerRuntimeMetaPath(wanted),out)
  if ok then trainerRuntimeWrites=trainerRuntimeWrites+1 end
  return ok
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
  if not DENSE_MESH then return TrainerMorph.staticCompactVertex(x,y,z,u,v,0,1,0) end
  -- Same base position is supplied for every morph stream. Shadows never
  -- morph, but the mesh must still satisfy the dense source format.
  return {x,y,z,u,v,0,1,0,
    x,y,z, x,y,z,
    x,y,z, x,y,z, x,y,z, x,y,z, x,y,z,
    x,y,z, x,y,z, x,y,z, x,y,z, x,y,z}
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
  shadowMesh=love.graphics.newMesh(DENSE_MESH and FORMAT or FORMAT_COMPACT,verts,"triangles","static")
  shadowMesh:setTexture(shadowImage)
  return true
end
local function ballVertex(x,y,z,u,v)
  if not DENSE_MESH then return TrainerMorph.staticCompactVertex(x,y,z,u,v,0,1,0) end
  return {x,y,z,u,v,0,1,0,
    x,y,z, x,y,z,
    x,y,z, x,y,z, x,y,z, x,y,z, x,y,z,
    x,y,z, x,y,z, x,y,z, x,y,z, x,y,z}
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
  local function make(vs)local m=love.graphics.newMesh(DENSE_MESH and FORMAT or FORMAT_COMPACT,vs,"triangles","static");m:setTexture(ballTexture);return m end
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


local function releaseLoveObject(obj,seen)
  if obj==nil then return end
  seen=seen or {}
  if seen[obj] then return end
  seen[obj]=true
  pcall(function()
    if type(obj.release)=="function" then obj:release() end
  end)
end
local function releaseScene(entry)
  if type(entry)~="table" then return end
  local seen={}
  for _,g in ipairs(entry.groups or {}) do
    if type(g)=="table" then releaseLoveObject(g.mesh,seen) end
  end
  for _,img in pairs(entry.textures or {}) do releaseLoveObject(img,seen) end
end
local function trimSceneCache()
  local count=0;for _ in pairs(sceneCache) do count=count+1 end
  while count>MAX_RESIDENT_TRAINERS do
    local victim,vuse
    for key,entry in pairs(sceneCache) do
      if key~=sceneKey then
        local use=tonumber(entry.__cbeUse) or 0
        if victim==nil or use<vuse then victim,vuse=key,use end
      end
    end
    if not victim then break end
    releaseScene(sceneCache[victim]);sceneCache[victim]=nil;sceneErrors[victim]=nil
    count=count-1
  end
end
local function activateScene(cfg,reason,wanted,entry)
  sceneUseSerial=sceneUseSerial+1;entry.__cbeUse=sceneUseSerial
  scene=entry;sceneKey=wanted;currentModel=wanted;currentConfig=cfg;currentReason=reason
  errorText=nil;applyModelScale()
  return entry
end
local function loadConfig(ctx,cfg,reason)
  if not cfg then return nil,reason or "trainer-model-unavailable" end
  local wanted=tostring(cfg.id or cfg.label or cfg.cache or "trainer")
  local hit=sceneCache[wanted]
  if hit then return activateScene(cfg,reason,wanted,hit) end
  local priorErr=sceneErrors[wanted]
  if priorErr then errorText=priorErr;return nil,priorErr end
  currentModel=wanted;currentConfig=cfg;currentReason=reason;errorText=nil
  if not (love and love.graphics and love.image and love.graphics.newMesh and love.graphics.newShader) then
    errorText="LÖVE mesh/shader API unavailable";sceneErrors[wanted]=errorText;return nil,errorText
  end
  -- Trainer shader is identical for every roster model. Compile it once and
  -- keep it resident instead of relinking GLSL every time a rival/class model
  -- changes.
  if not shader then
    local ok,sh=pcall(love.graphics.newShader,VERTEX,PIXEL)
    if not ok or not sh then errorText=(cfg.label or wanted).." shader: "..tostring(sh or "unavailable");sceneErrors[wanted]=errorText;return nil,errorText end
    shader=sh
  end
  local sourceSize=trainerSourceSize(cfg)
  local cache,err,fromRuntime
  if DENSE_MESH and RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    local rt=select(1,RuntimeMeshCache.readLua(trainerRuntimeMetaPath(wanted)))
    if trainerRuntimeUsable(rt,wanted,sourceSize) then cache=rt;fromRuntime=true;trainerRuntimeHits=trainerRuntimeHits+1 end
  end
  if not cache then cache,err=readLua(cfg.cache) end
  if not cache then errorText=tostring(err);sceneErrors[wanted]=errorText;return nil,errorText end
  if tonumber(cache.formatVersion)~=26 then
    errorText=(cfg.label or wanted).." trainer cache format "..tostring(cache.formatVersion or "?").." is stale; rebuild required for dense source animation"
    sceneErrors[wanted]=errorText;return nil,errorText
  end
  local textures={}; local groups={}
  local canonicalFallback=nil
  for i,g in ipairs(cache.groups or {}) do
    local path=g.texture and g.texture.path
    local img=path and textures[path] or nil
    if path and not img then
      img,err=imageFromRaw(g.texture)
      if not img then errorText=tostring(err);sceneErrors[wanted]=errorText;return nil,errorText end
      textures[path]=img
    end
    local mesh,meshErr
    local denseVertices
    local binPath=g.runtimeBin or trainerRuntimeBinPath(wanted,i)
    if fromRuntime and RuntimeMeshCache and type(RuntimeMeshCache.meshFromPath)=="function" then
      mesh,meshErr=RuntimeMeshCache.meshFromPath(FORMAT,binPath,44,"static")
    end
    if not mesh then
      -- A compact runtime meta intentionally contains no Lua vertex rows. If a
      -- platform/backend cannot turn its .f32 sidecar into a Mesh (observed on
      -- Windows while Android accepted the same cache), never continue with an
      -- empty vertex table. Reopen the canonical extracted HSD cache for this
      -- group, draw it immediately, and opportunistically repair the sidecar.
      local sourceGroup=g
      if fromRuntime and type(g.vertices)~="table" then
        if canonicalFallback==nil then
          local canonical,cerr=readLua(cfg.cache)
          if type(canonical)=="table" and tonumber(canonical.formatVersion)==26 then canonicalFallback=canonical else canonicalFallback=false;meshErr=tostring(cerr or meshErr or "canonical trainer fallback unavailable") end
        end
        if canonicalFallback and canonicalFallback.groups and canonicalFallback.groups[i] then
          sourceGroup=canonicalFallback.groups[i];trainerRuntimeFallbacks=trainerRuntimeFallbacks+1
        end
      end
      local vertices=sourceGroup and sourceGroup.vertices or {}
      if type(vertices)~="table" or #vertices==0 then
        errorText=(cfg.label or wanted).." mesh "..i.." runtime sidecar failed and canonical vertices are unavailable: "..tostring(meshErr or "empty mesh")
        sceneErrors[wanted]=errorText;return nil,errorText
      end
      for _,row in ipairs(vertices) do if type(row)=="table" then row[45]=nil end end
      denseVertices=vertices
      if not DENSE_MESH then
        local compact={}
        for ri,row in ipairs(denseVertices) do compact[ri]=TrainerMorph.compactVertex(row,nil,nil) end
        vertices=compact
      end
      local ok,built=pcall(love.graphics.newMesh,DENSE_MESH and FORMAT or FORMAT_COMPACT,vertices,"triangles",DENSE_MESH and "static" or "dynamic")
      if not ok then errorText=(cfg.label or wanted).." mesh "..i..": "..tostring(built);sceneErrors[wanted]=errorText;return nil,errorText end
      mesh=built
      if DENSE_MESH and RuntimeMeshCache and RuntimeMeshCache.supported and RuntimeMeshCache.supported() then
        local wok=RuntimeMeshCache.writeRows(binPath,vertices,44)
        if not wok then meshErr="runtime sidecar write failed" end
      end
    end
    if img then mesh:setTexture(img) end
    local d=g.diffuse or {1,1,1}
    groups[#groups+1]={mesh=mesh,material=g.material,image=img,textured=img~=nil,
      diffuse={tonumber(d[1]) or 1,tonumber(d[2]) or 1,tonumber(d[3]) or 1},
      alpha=tonumber(g.alpha) or 1,xlu=g.xlu==true,noz=g.noz==true,
      renderFlags=tonumber(g.renderFlags) or 0,shadow=g.shadow==true,effect=g.effect==true,
      poseSourceRows=(not DENSE_MESH) and denseVertices or nil,posePair=nil}
  end
  local sok,serr=ensureShadow()
  if not sok then errorText=(cfg.label or wanted).." shadow: "..tostring(serr);sceneErrors[wanted]=errorText;return nil,errorText end
  if not fromRuntime and RuntimeMeshCache and RuntimeMeshCache.supported and RuntimeMeshCache.supported() and sourceSize then
    local all=true
    for i=1,#(cache.groups or {}) do
      local info=GeneratedAssets.info and GeneratedAssets.info(trainerRuntimeBinPath(wanted,i)) or nil
      local size=info and tonumber(info.size)
      if not size or size<176 or size%176~=0 then all=false;break end
    end
    if all then writeTrainerRuntimeMeta(wanted,cache,sourceSize) end
  end
  local entry={groups=groups,bounds=cache.bounds,source=cache.source,textures=textures}
  sceneCache[wanted]=entry
  activateScene(cfg,reason,wanted,entry);trimSceneCache()
  log(ctx,"info","loaded %s source actor: %d material groups",cfg.label or wanted,#groups)
  return entry
end

local function loadScene(ctx)
  local cfg,reason=trainerModelFor(ctx)
  return loadConfig(ctx,cfg,reason)
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

function T:prewarm(ctx)
  local s,err=loadScene(ctx)
  if s then pcall(ensureBall) end
  return s~=nil,err
end
function T:prewarmModel(cfg,ctx,reason)
  local s,err=loadConfig(ctx or {},cfg,reason or "explicit-prewarm")
  if s then pcall(ensureBall) end
  return s~=nil,err
end
function T:queuePrewarm(game)
  prewarmQueue={};prewarmSeen={};prewarmNextAt=0
  if not (TrainerRoster and type(TrainerRoster.prewarmPlan)=="function") then return 0 end
  local ok,plan=pcall(TrainerRoster.prewarmPlan,game)
  if not ok or type(plan)~="table" then return 0 end
  for _,row in ipairs(plan) do
    local cfg=row and row.config
    local key=cfg and tostring(cfg.id or cfg.cache or cfg.label or "trainer")
    if cfg and key and not sceneCache[key] and not prewarmSeen[key] then
      prewarmSeen[key]=true;prewarmQueue[#prewarmQueue+1]=row
    end
  end
  return #prewarmQueue
end
function T:drainPrewarm(game,limit)
  limit=math.max(1,math.floor(tonumber(limit) or #prewarmQueue))
  local warmed=0
  while #prewarmQueue>0 and warmed<limit do
    local row=table.remove(prewarmQueue,1)
    if not row then break end
    local ok=self:prewarmModel(row.config,{game=game,phase="trainer-game-ready",services={androidResidentWarm=ANDROID_RUNTIME}},row.reason)
    if ok then warmed=warmed+1 end
  end
  prewarmNextAt=0
  return warmed,#prewarmQueue
end

function T:pumpPrewarm(game)
  if #prewarmQueue==0 then return false,0 end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local now=clock and clock() or 0
  if now>0 and now<prewarmNextAt then return false,#prewarmQueue end
  local row=table.remove(prewarmQueue,1);if not row then return false,0 end
  local ok=self:prewarmModel(row.config,{game=game,phase="trainer-prewarm",services={androidResidentWarm=ANDROID_RUNTIME}},row.reason)
  local after=clock and clock() or now
  prewarmNextAt=(after>0 and after or now)+(ANDROID_RUNTIME and .80 or .20)
  return ok,#prewarmQueue
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
  local b0=battleOf(ctx)
  local gen2=b0 and b0.__cbeGeneration==2
  local queueSync=b0 and b0.__cbePresentationQueueSync==true
  if queueSync and ((gen2 and (name=="battle.move_used" or name=="battle.damage_dealt" or name=="battle.fainted"))
      or ((not gen2) and name=="battle.fainted")) then return end
  local semantic=name
  if name=="battle.presentation_damage" then semantic="battle.damage_dealt"
  elseif name=="battle.presentation_faint" then semantic="battle.fainted" end
  if not activeNow then return end
  if semantic=="battle.move_used" or name=="battle.presentation_move" then
    local actor=payloadSide(ctx,payload,{"user","attacker","source","battler","side"})
    if actor=="enemy" and not pendingFrustration then trigger("command",1.0) end
  elseif semantic=="battle.damage_dealt" then
    local target=payloadSide(ctx,payload,{"target","defender","targetSide","defenderSide"})
    if not target then local actor=payloadSide(ctx,payload,{"user","attacker","source","side"});target=other(actor) end
    if target=="enemy" then
      local b=battleOf(ctx);local dmg=tonumber(payload.damage) or 0
      local maxhp=b and b.enemy and b.enemy.mon and b.enemy.mon.stats and tonumber(b.enemy.mon.stats.hp) or 1
      local ratio=dmg/math.max(1,maxhp)
      -- Tiny chip hits do not make the trainer flinch on every contact. Source
      -- reactions are reserved for readable battle beats; large hits escalate.
      if ratio>=.30 then trigger("concern",1.0)
      elseif ratio>=.085 then trigger("brace",.70) end
    end
  elseif name=="battle.status_inflicted" then
    local target=payloadSide(ctx,payload,{"target","battler","side","targetSide"})
    if target=="enemy" then trigger("concern",.72) end
  elseif name=="battle.battler_switched" then
    -- AI switch events can lead the actual enemySendingOut phase. Arm the
    -- performance, but let update() start it on the authoritative phase edge.
    local switched=payloadSide(ctx,payload,{"side","battler","target","switchedSide"})
    if switched=="enemy" then
      initialSendoutQueued=false
      local previous=payload.previous or payload.oldBattler
      local mon=type(previous)=="table" and (previous.mon or previous) or nil
      local hp=mon and tonumber(mon.hp)
      if hp==nil or hp>0 then trigger("recall",.96) end
    end
  elseif semantic=="battle.fainted" then
    local fainted=payloadSide(ctx,payload,{"battler","target","side","faintedSide","targetSide"})
    if fainted=="enemy" then
      local fd=BattleDirector and type(BattleDirector.faintDuration)=="function"
        and BattleDirector:faintDuration(ctx,"enemy") or nil
      pendingFrustration=math.max(.52,math.min(1.35,(tonumber(fd) or 1.0)*.80))
    end
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
  shader:send("materialColor",{1,1,1,1})
  shader:send("useTexture",1)
  shader:send("flipV",currentModel=="miror_b" and 1 or 0)
  TrainerMorph.sendMixes(shader,motion)
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
  TrainerMorph.bindPair(s.groups,motion)
  love.graphics.setDepthMode("lequal",true)
  love.graphics.setBlendMode("alpha","alphamultiply")
  if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end
  love.graphics.setColor(1,1,1,1)
  setShader(vp,model,pose,0,{1,1,1,1},smooth(p.progress/0.40),motion)
  -- Retain source HSD material/pass semantics. Opaque groups write depth; XLU
  -- and NO_ZUPDATE helper/effect surfaces blend without corrupting the world Z.
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
  local all=sceneCache;sceneCache={};sceneErrors={};sceneUseSerial=0
  for _,entry in pairs(all or {}) do releaseScene(entry) end
  prewarmQueue={};prewarmSeen={};prewarmNextAt=0
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
    mode=T:getMode(mod and mod.game),bossOnly=false,residentModels=(function() local n=0;for _ in pairs(sceneCache) do n=n+1 end;return n end)(),prewarmPending=#prewarmQueue,runtimeMeshHits=trainerRuntimeHits,runtimeMeshWrites=trainerRuntimeWrites,runtimeMeshFallbacks=trainerRuntimeFallbacks,morph=TrainerMorph.status(),windowsCompat=WINDOWS_RUNTIME,
  }
end

return T
