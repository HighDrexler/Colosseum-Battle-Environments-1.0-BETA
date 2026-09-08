local V=...
local Waza=V and V.WazaSequenceRuntime
local Assets=V and V.GeneratedAssets
local CSM=V and V.CurrentSpriteModels
local Audio=V and V.WazaAudioRuntime
local RuntimeMeshCache=V and V.RuntimeMeshCache
local H={installed=false,models={},effects={},controllers={player={},enemy={}},opaque={},lastModel=nil,modelCache={},partsCache={},modelErrors={},textureCache={},drawError=nil,
  postCanvas=nil,postHistory=nil,postW=0,postH=0,distortShader=nil,postErrors=0}

local FORMAT_STATIC={
  {"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexNormal","float",3},
}
-- Base position/UV/normal plus twelve exact HSD-evaluated source positions.
-- Packing mirrors PokemonActors so Type-2 Waza models stay under generic GPU
-- attribute limits while preserving the retail 60 Hz pose stream.
local FORMAT_MORPH={
  {"VertexPosition","float",3},{"VertexTexCoord","float",2},{"VertexNormal","float",3},
  {"FramePack1","float",4},{"FramePack2","float",4},{"FramePack3","float",4},
  {"FramePack4","float",4},{"FramePack5","float",4},{"FramePack6","float",4},
  {"FramePack7","float",4},{"FramePack8","float",4},{"FramePack9","float",4},
}
local VERTEX_STATIC=[[
uniform mat4 vp;
uniform mat4 model;
attribute vec3 VertexNormal;
varying vec3 wNormal;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec4 world=model*vec4(vertex_position.xyz,1.0);
  wNormal=normalize((model*vec4(VertexNormal,0.0)).xyz);
  return vp*world;
}
]]
local VERTEX_MORPH=[[
uniform mat4 vp;
uniform mat4 model;
uniform float w0; uniform float w1; uniform float w2; uniform float w3;
uniform float w4; uniform float w5; uniform float w6; uniform float w7;
uniform float w8; uniform float w9; uniform float w10; uniform float w11; uniform float w12;
attribute vec3 VertexNormal;
attribute vec4 FramePack1; attribute vec4 FramePack2; attribute vec4 FramePack3;
attribute vec4 FramePack4; attribute vec4 FramePack5; attribute vec4 FramePack6;
attribute vec4 FramePack7; attribute vec4 FramePack8; attribute vec4 FramePack9;
varying vec3 wNormal;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 f1=FramePack1.xyz;
  vec3 f2=vec3(FramePack1.w,FramePack2.x,FramePack2.y);
  vec3 f3=vec3(FramePack2.z,FramePack2.w,FramePack3.x);
  vec3 f4=FramePack3.yzw;
  vec3 f5=FramePack4.xyz;
  vec3 f6=vec3(FramePack4.w,FramePack5.x,FramePack5.y);
  vec3 f7=vec3(FramePack5.z,FramePack5.w,FramePack6.x);
  vec3 f8=FramePack6.yzw;
  vec3 f9=FramePack7.xyz;
  vec3 f10=vec3(FramePack7.w,FramePack8.x,FramePack8.y);
  vec3 f11=vec3(FramePack8.z,FramePack8.w,FramePack9.x);
  vec3 f12=FramePack9.yzw;
  vec3 p=vertex_position.xyz*w0+f1*w1+f2*w2+f3*w3+f4*w4+f5*w5+f6*w6+f7*w7+f8*w8+f9*w9+f10*w10+f11*w11+f12*w12;
  vec4 world=model*vec4(p,1.0);
  wNormal=normalize((model*vec4(VertexNormal,0.0)).xyz);
  return vp*world;
}
]]
local PIXEL=[[
uniform vec4 materialColor;
uniform float useTexture;
uniform float opacity;
uniform float unlit;
uniform float forceOpaque;
uniform float envMode;
uniform vec3 effectTint;
varying vec3 wNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec3 nn=normalize(wNormal);
  vec2 envUV=vec2(nn.x*0.5+0.5,0.5-nn.y*0.5);
  vec4 t=Texel(texture,mix(uv,envUV,envMode));
  float texA=mix(1.0,t.a,useTexture);
  float a=mix(texA,1.0,forceOpaque)*materialColor.a*opacity*color.a;
  if (a<0.025) discard;
  // Keep the source effect's keyed colour on textured groups too. Its RGB was
  // previously folded into materialColor, then discarded by this texture mix.
  vec3 base=mix(materialColor.rgb,t.rgb,useTexture)*effectTint;
  if (unlit > 0.5) return vec4(base,a);
  vec3 n=normalize(wNormal);
  vec3 l=normalize(vec3(-0.38,0.84,0.39));
  float key=0.70+0.30*abs(dot(n,l));
  return vec4(base*key,a);
}
]]
local shaderStatic,shaderMorph
local modelUseSerial=0
local runtimeMeshHits,runtimeMeshWrites,runtimeMeshFallbacks=0,0,0
local hardCacheQueue,hardCacheSeen={},{}
local hardCacheState={running=false,total=0,done=0,failed=0,last=nil}

local function key(inst,entry)
  local entryKey=entry and (entry.runtimeIdentifier or
    (tostring(entry.phase or "?")..":"..tostring(entry.identifier or entry.index or "?"))) or "?"
  return tostring(inst and inst.serial or "?")..":"..tostring(entryKey)
end
local function remove(t,k) t[k]=nil end

local function readLua(path)
  if not (Assets and type(Assets.read)=="function") then return nil,"generated asset service unavailable" end
  local src,err=Assets.read(path);if type(src)~="string" then return nil,err or ("missing "..tostring(path)) end
  local f,e=load(src,"@generated/"..tostring(path));if not f then return nil,e end
  local ok,v=pcall(f);if not ok then return nil,v end
  return v
end
local function imageFromRaw(spec)
  if not (spec and spec.path and love and love.image and love.graphics) then return nil end
  if H.textureCache[spec.path] then return H.textureCache[spec.path] end
  local bytes=Assets and Assets.read and Assets.read(spec.path)
  if type(bytes)~="string" then return nil,"missing "..tostring(spec.path) end
  local ok,d=pcall(love.image.newImageData,spec.w,spec.h,"rgba8",bytes);if not ok then return nil,d end
  local ok2,img=pcall(love.graphics.newImage,d);if not ok2 then return nil,img end
  if img.setFilter then pcall(img.setFilter,img,"linear","linear",8) end
  if img.setWrap then
    local function wn(v) v=tonumber(v) or 0;if v==1 then return "repeat" elseif v==2 then return "mirroredrepeat" end;return "clamp" end
    pcall(img.setWrap,img,wn(spec.wrapS),wn(spec.wrapT))
  end
  H.textureCache[spec.path]=img
  return img
end
local function ensureShader(morph)
  -- Do not use `morph and shaderMorph or shaderStatic`: when the morph
  -- shader is cold and the static shader is warm it returns the WRONG shader.
  -- That silently removed every animated Type-2 body on its first w0 upload.
  local current
  if morph then current=shaderMorph else current=shaderStatic end
  if current then return current end
  if not (love and love.graphics and love.graphics.newShader) then return nil,"LÖVE shader unavailable" end
  local ok,sh=pcall(love.graphics.newShader,morph and VERTEX_MORPH or VERTEX_STATIC,PIXEL)
  if not ok then return nil,sh end
  if morph then shaderMorph=sh else shaderStatic=sh end
  return sh
end

local function decodedVertices(group,expectedStride,checkpoint)
  if type(group)~="table" then return nil,"Waza vertex group missing" end
  if type(group.vertices)=="table" then return group.vertices end -- legacy cache
  local packed=group.verticesPacked
  if type(packed)~="string" then return nil,"Waza packed vertex payload missing" end
  local stride=tonumber(group.vertexStride) or tonumber(expectedStride) or 8
  if stride~=expectedStride then
    return nil,("Waza vertex stride %s does not match expected %s"):format(tostring(stride),tostring(expectedStride))
  end
  local rows={}
  for line in packed:gmatch("[^\r\n]+") do
    local row={}
    for token in line:gmatch("[^,]+") do
      local n=tonumber(token);if n==nil then return nil,"Waza packed vertex contains non-number" end
      row[#row+1]=n
    end
    if #row~=stride then return nil,("Waza packed vertex row has %d scalars; expected %d"):format(#row,stride) end
    rows[#rows+1]=row
    if checkpoint and #rows%128==0 then checkpoint() end
  end
  if #rows==0 then return nil,"Waza packed vertex payload empty" end
  group.vertices=rows;group.verticesPacked=nil
  return rows
end

-- Packed effects must not survive a different extractor/schema just because
-- their filename (or a missing cache size) happens to match. This namespace
-- refreshes only Waza binary sidecars; source/arena/actor/audio caches survive.
local RUNTIME_MESH_VERSION=2
local function extractorRevision() return tonumber(V and V.MoveFXExtractor and V.MoveFXExtractor.revision) or 0 end
local function runtimeRoot(path)
  return tostring(path or "cache/waza/model_cache.lua"):gsub("%.lua$","").."_runtime_v2_r"..extractorRevision()
end
local function runtimeMetaPath(path) return runtimeRoot(path).."/base.lua" end
local function runtimeBinPath(path,i) return runtimeRoot(path)..("/base_%02d.f32"):format(tonumber(i) or 0) end
local function sourceSize(path) local info=Assets and Assets.info and Assets.info(path) or nil;return info and tonumber(info.size) or nil end
local function runtimeUsable(meta,path,size)
  if type(meta)~="table" or tonumber(meta.runtimeMeshVersion)~=RUNTIME_MESH_VERSION
      or meta.sourcePath~=path or tonumber(meta.extractorRevision)~=extractorRevision()
      or type(meta.groups)~="table" or #meta.groups==0 then return false end
  local recorded=tonumber(meta.sourceSize)
  if size and recorded~=size then return false end
  local stride=(tonumber(meta.morphFrames) or 0)>0 and 44 or 8;local bpv=stride*4
  for i,g in ipairs(meta.groups) do
    local expected=runtimeBinPath(path,i)
    if type(g)~="table" or (g.runtimeBin~=nil and g.runtimeBin~=expected) then return false end
    local bin=g.runtimeBin or expected
    local info=Assets and Assets.info and Assets.info(bin) or nil
    if not info then return false end
    local n=tonumber(info.size)
    local count=tonumber(type(g)=="table" and g.vertexCount)
    if not count or count<3 or count%3~=0 or count~=math.floor(count) then return false end
    if n and n~=count*bpv then return false end
  end
  return true
end
local function compactGroup(g,path,i)
  local o={};for k,v in pairs(g or {}) do if k~="vertices" and k~="verticesPacked" then o[k]=v end end
  o.runtimeBin=runtimeBinPath(path,i)
  o.vertexCount=type(g.vertices)=="table" and #g.vertices or tonumber(g.vertexCount)
  return o
end
local function writeRuntimeMeta(path,cache,size)
  if not (RuntimeMeshCache and RuntimeMeshCache.writeLua) then return false end
  local o={}
  for k,v in pairs(cache or {}) do if k~="groups" then o[k]=v end end
  o.runtimeMeshVersion=RUNTIME_MESH_VERSION;o.sourcePath=path;o.extractorRevision=extractorRevision()
  o.sourceSize=size
  o.groups={};for i,g in ipairs(cache.groups or {}) do o.groups[i]=compactGroup(g,path,i) end
  local ok=RuntimeMeshCache.writeLua(runtimeMetaPath(path),o);if ok then runtimeMeshWrites=runtimeMeshWrites+1 end;return ok
end

local function loadCache(path)
  if not path then return nil,"Waza model cache missing" end
  if H.modelCache[path]~=nil then
    local hit=H.modelCache[path]
    if type(hit)=="table" then modelUseSerial=modelUseSerial+1;hit.__cbeUse=modelUseSerial end
    return hit or nil,H.modelErrors[path]
  end
  if not (love and love.graphics and love.graphics.newMesh) then return nil,"LÖVE mesh API unavailable" end
  local size=sourceSize(path)
  local cache,err,fromRuntime
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    local rt=select(1,RuntimeMeshCache.readLua(runtimeMetaPath(path)))
    if runtimeUsable(rt,path,size) then cache=rt;fromRuntime=true;runtimeMeshHits=runtimeMeshHits+1 end
  end
  if not cache then cache,err=readLua(path) end
  if not cache then H.modelCache[path]=false;H.modelErrors[path]=tostring(err);return nil,err end
  local morph=(tonumber(cache.morphFrames) or 0)>0
  local fmt=morph and FORMAT_MORPH or FORMAT_STATIC
  local textures,groups={},{}
  local canonicalFallback=nil
  for i,g in ipairs(cache.groups or {}) do
    local img
    if g.texture then
      local tp=g.texture.path;img=textures[tp]
      if not img then
        local why;img,why=imageFromRaw(g.texture)
        if not img then H.modelCache[path]=false;H.modelErrors[path]=tostring(why);return nil,why end
        textures[tp]=img
      end
    end
    local stride=morph and 44 or 8
    local mesh,vErr,vertices
    if fromRuntime and RuntimeMeshCache and type(RuntimeMeshCache.meshFromPath)=="function" then
      mesh,vErr=RuntimeMeshCache.meshFromPath(fmt,g.runtimeBin or runtimeBinPath(path,i),stride,"static")
    end
    if not mesh then
      local sourceGroup=g
      -- Same fail-open rule as trainer meshes: compact runtime metadata omits
      -- the textual vertex payload. A backend that rejects the persistent f32
      -- sidecar must reopen the canonical Waza cache instead of treating the
      -- effect as empty/invisible (Windows has already exposed this class of
      -- backend-specific sidecar failure for trainer models).
      if fromRuntime and type(g.vertices)~="table" and type(g.verticesPacked)~="string" then
        if canonicalFallback==nil then canonicalFallback=select(1,readLua(path)) or false end
        if canonicalFallback and canonicalFallback.groups and canonicalFallback.groups[i] then
          sourceGroup=canonicalFallback.groups[i];runtimeMeshFallbacks=runtimeMeshFallbacks+1
        end
      end
      vertices,vErr=decodedVertices(sourceGroup,stride)
      if not vertices then H.modelCache[path]=false;H.modelErrors[path]=tostring(vErr);return nil,vErr end
      local ok,built=pcall(love.graphics.newMesh,fmt,vertices,"triangles","static")
      if not ok then H.modelCache[path]=false;H.modelErrors[path]=tostring(built);return nil,built end
      mesh=built
      if RuntimeMeshCache and RuntimeMeshCache.supported and RuntimeMeshCache.supported() then RuntimeMeshCache.writeRows(runtimeBinPath(path,i),vertices,stride) end
    end
    if img then mesh:setTexture(img) end
    local effectLike=g.effect==true or (g.useConstant==true and g.useDiffuseLighting==false)
    groups[#groups+1]={mesh=mesh,image=img,diffuse=g.diffuse or {1,1,1},alpha=tonumber(g.alpha) or 1,
      xlu=g.xlu==true,noz=g.noz==true,renderFlags=tonumber(g.renderFlags) or 0,textureTexgen=g.textureTexgen,
      shadow=g.shadow==true,effect=g.effect==true,useConstant=g.useConstant==true,
      useVertexColor=g.useVertexColor==true,useDiffuseLighting=g.useDiffuseLighting~=false,
      -- GameCube Waza effect/constant passes are frequently additive/TEV-light
      -- carriers. Treating a black mask as opaque alpha geometry is what can
      -- turn a correct move into a one-frame black screen in the portable path.
      luminous=effectLike}
  end
  if #groups==0 then H.modelCache[path]=false;H.modelErrors[path]="Waza model cache empty";return nil,H.modelErrors[path] end
  if not fromRuntime and RuntimeMeshCache and RuntimeMeshCache.packSupported and RuntimeMeshCache.packSupported() then
    local all=true;local bpv=(morph and 44 or 8)*4
    for i=1,#(cache.groups or {}) do local info=Assets.info and Assets.info(runtimeBinPath(path,i)) or nil;local n=info and tonumber(info.size);if not info or (n and (n<bpv or n%bpv~=0)) then all=false;break end end
    if all then writeRuntimeMeta(path,cache,size) end
  end
  local out={groups=groups,bounds=cache.bounds,source=cache.source,textures=textures,morph=morph,
    morphFrames=tonumber(cache.morphFrames) or 0,startFrame=tonumber(cache.startFrame) or 0,endFrame=tonumber(cache.endFrame) or 0,
    animation=cache.animation}
  modelUseSerial=modelUseSerial+1;out.__cbeUse=modelUseSerial
  H.modelCache[path]=out;H.modelErrors[path]=nil;return out
end

-- CPU/disk-only runtime-sidecar backfill. This is the core of Hard Cache
-- Save for MoveFX: older portable caches may contain the exact canonical Waza
-- model but no binary sidecar because their cache backend omitted file sizes.
-- Bake one model per stable overworld scheduler slice and allocate no GPU mesh.
local function bakeRuntimeCache(path,checkpoint)
  local size=sourceSize(path)
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    local meta=select(1,RuntimeMeshCache.readLua(runtimeMetaPath(path)))
    if runtimeUsable(meta,path,size) then return true,"ready" end
  end
  if not (RuntimeMeshCache and RuntimeMeshCache.packSupported and RuntimeMeshCache.packSupported()) then return false,"float32 pack API unavailable" end
  local cache,err=readLua(path);if type(cache)~="table" then return false,err end
  local stride=(tonumber(cache.morphFrames) or 0)>0 and 44 or 8
  for i,g in ipairs(cache.groups or {}) do
    local rows,why=decodedVertices(g,stride,checkpoint);if not rows then return false,why end
    local ok,werr=RuntimeMeshCache.writeRows(runtimeBinPath(path,i),rows,stride,checkpoint);if not ok then return false,werr end
  end
  if #(cache.groups or {})==0 then return false,"Waza model cache empty" end
  local ok=writeRuntimeMeta(path,cache,size)
  if RuntimeMeshCache.invalidateLua then RuntimeMeshCache.invalidateLua(runtimeMetaPath(path)) end
  return ok==true,ok and "baked" or "metadata write failed"
end

local function collectHardCachePaths(value,depth,seenTables)
  depth=(depth or 0)+1;if depth>14 or type(value)~="table" then return end
  seenTables=seenTables or {};if seenTables[value] then return end;seenTables[value]=true
  for k,v in pairs(value) do
    if k=="cache" and type(v)=="string" and v:match("^cache/movefx/") and v:match("%.lua$") then
      if not hardCacheSeen[v] then hardCacheSeen[v]=true;hardCacheQueue[#hardCacheQueue+1]=v end
    elseif type(v)=="table" then collectHardCachePaths(v,depth,seenTables) end
  end
end

local hardTask=nil
local hardDeadline=0
local function hardClock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end
local function hardCheckpoint()
  if hardClock()>=hardDeadline then coroutine.yield("cpu-slice") end
end
local function hardSlice()
  local ok,platform=pcall(function() return love.system.getOS() end)
  return ok and platform=="Android" and 0.003 or 0.006
end
function H.queueHardCacheSpecs(specs)
  hardTask=nil
  hardCacheQueue={};hardCacheSeen={};hardCacheState={running=false,total=0,done=0,failed=0,last=nil}
  for _,spec in ipairs(type(specs)=="table" and specs or {}) do collectHardCachePaths(spec,0,{}) end
  hardCacheState.total=#hardCacheQueue;hardCacheState.running=#hardCacheQueue>0
  return #hardCacheQueue
end
function H.pumpHardCache(maxItems)
  maxItems=math.max(1,math.floor(tonumber(maxItems) or 1));local n=0
  hardDeadline=hardClock()+hardSlice()
  while n<maxItems and #hardCacheQueue>0 do
    local path=hardCacheQueue[1]
    if not hardTask then hardTask=coroutine.create(function() return bakeRuntimeCache(path,hardCheckpoint) end) end
    local resumed,ok,why=coroutine.resume(hardTask)
    if resumed and coroutine.status(hardTask)~="dead" then break end
    hardTask=nil;table.remove(hardCacheQueue,1);n=n+1
    hardCacheState.last=path
    if resumed and ok then hardCacheState.done=hardCacheState.done+1
    else hardCacheState.failed=hardCacheState.failed+1;H.modelErrors[path]=tostring(resumed and why or ok) end
    if hardClock()>=hardDeadline then break end
  end
  hardCacheState.running=#hardCacheQueue>0
  return {processed=n,pending=#hardCacheQueue,running=hardCacheState.running,done=hardCacheState.done,failed=hardCacheState.failed}
end
function H.cancelHardCache() hardTask=nil;hardCacheQueue={};hardCacheSeen={};hardCacheState.running=false end

function H.hardCacheStatus() return {running=hardCacheState.running,pending=#hardCacheQueue,total=hardCacheState.total,done=hardCacheState.done,failed=hardCacheState.failed,last=hardCacheState.last} end

local function pageForAsset(asset,localFrame)
  local anim=type(asset)=="table" and asset.animation
  if not (type(anim)=="table" and anim.animated==true and type(anim.pages)=="table" and #anim.pages>0) then
    return asset and asset.cache,nil
  end
  local f=math.max(0,tonumber(localFrame) or 0)
  local selected=anim.pages[#anim.pages]
  for _,page in ipairs(anim.pages) do
    if f>= (tonumber(page.startFrame) or 0) and f<= (tonumber(page.endFrame) or math.huge) then selected=page;break end
  end
  return selected and selected.cache,selected
end

local function loadModel(asset,localFrame)
  local path,page=pageForAsset(asset,localFrame)
  local model,err=loadCache(path)
  if not model and page and asset and asset.cache then model,err=loadCache(asset.cache);page=nil end
  if model then model.asset=asset end
  return model,err,page
end

local function morphWeights(page,localFrame)
  local w={0,0,0,0,0,0,0,0,0,0,0,0,0}
  if not page then w[1]=1;return w end
  local start=tonumber(page.startFrame) or 0
  local n=math.max(0,math.min(12,tonumber(page.morphFrames) or ((tonumber(page.endFrame) or start)-start)))
  if n<=0 then w[1]=1;return w end
  local x=math.max(0,math.min(n,(tonumber(localFrame) or 0)-start))
  local i=math.floor(x);local t=x-i
  if i>=n then w[n+1]=1
  else w[i+1]=1-t;w[i+2]=t end
  return w
end
local function modelSpan(model,basis)
  local b=model and (model.normalizationBounds or model.bounds)
  local mn,mx=b and b.min,b and b.max
  if not (mn and mx) then return 16 end
  local sx=math.abs((tonumber(mx[1]) or 0)-(tonumber(mn[1]) or 0))
  local sy=math.abs((tonumber(mx[2]) or 0)-(tonumber(mn[2]) or 0))
  local sz=math.abs((tonumber(mx[3]) or 0)-(tonumber(mn[3]) or 0))
  if basis and basis.groundField then return math.max(.001,sx,sz) end
  return math.max(.001,sx,sy,sz)
end
local MODEL_REACH={[58]=85.9,[62]=103.45}
local function modelMatrix(basis,model,asset)
  local o,r,u,f=basis.origin,basis.right,basis.up,basis.forward
  -- Type-2 HSD effects are raw source models, unlike Pokemon bodies which are
  -- normalized to a 16-unit cache height. Scaling them with actor.worldScale
  -- directly made a large source object enormous and a tiny source object
  -- microscopic. Fit the source bounds to the same live combat-space target
  -- span used by GPT1 instead. For ordinary ~16-unit assets this naturally
  -- collapses to essentially the previous Pokemon-relative scale.
  if basis.aimed or basis.fieldWave or (asset and asset.transformOnly) then
    -- Keep authored animation growth: fitting each morph page to its own
    -- bounds shrank a beam as it extended. Scale source axes consistently.
    local v=basis.sourceUnits
    -- Positive-Z reach measured from the final source HSD pages.
    local reach=MODEL_REACH[basis.moveId] or 100
    local z=v.z*100/reach
    return {r[1]*v.x,u[1]*v.y,f[1]*z,o[1],r[2]*v.x,u[2]*v.y,f[2]*z,o[2],r[3]*v.x,u[3]*v.y,f[3]*z,o[3],0,0,0,1}
  end
  local desired=math.max(.10,tonumber(basis.modelTargetSpan) or tonumber(basis.referenceVisualHeight) or 16)
  local span=modelSpan(asset or (model and model.asset) or model,basis)
  local s=math.max(.01,math.min(24,desired/span))
  return {
    r[1]*s,u[1]*s,f[1]*s,o[1],
    r[2]*s,u[2]*s,f[2]*s,o[2],
    r[3]*s,u[3]*s,f[3]*s,o[3],
    0,0,0,1,
  }
end

-- A linked particle uses a part on the source effect model, NOT a Pokemon
-- body-map slot. Source 0x801D8B38 / 0x801D97F0 resolves flag 1 + linkedEntryKey
-- this way. The cache contains authored JOBJ matrices for the requested parts.
function H.linkedParticleFrame(ctx,inst,entry)
  if not (inst and entry and (tonumber(entry.flags) or 0)%2==1) then return nil end
  local wanted=tonumber(entry.linkedEntryKey)
  if not wanted or wanted<=0 then return nil,"invalid linked effect-model identity" end
  local linked
  for _,state in ipairs(inst.entries or {}) do
    local e=state.entry
    if e and e.phase==entry.phase and tonumber(e.identifier)==wanted and e.kind=="model" then linked=state;break end
  end
  if not linked or not linked.started then return nil,"linked effect-model has not started" end
  local e=linked.entry;local asset=e.modelAsset;local desc=asset and asset.parts
  if not (desc and desc.path) then return nil,"linked effect-model parts cache unavailable" end
  local data=H.partsCache[desc.path]
  if data==nil then
    local why;data,why=readLua(desc.path)
    if not (type(data)=="table" and data.revision==1 and type(data.tracks)=="table") then
      H.modelErrors[desc.path]=tostring(why or "invalid effect-model parts cache");H.partsCache[desc.path]=false
      return nil,H.modelErrors[desc.path]
    end
    H.partsCache[desc.path]=data
  end
  if data==false then return nil,H.modelErrors[desc.path] end
  local track=data.tracks[tonumber(entry.partIndex)]
  if not (track and track[1]) then return nil,"requested effect-model part is absent" end
  local frame=math.max(0,math.min(tonumber(data.endFrame) or 0,
    (tonumber(inst.frame) or 0)-(tonumber(linked.startFrame) or 0)))
  local first=math.floor(frame)+1;local a=track[first] or track[#track];local b=track[first+1] or a;local t=frame-math.floor(frame)
  local part={};for k=1,12 do part[k]=a[k]+(b[k]-a[k])*t end
  local originSide=inst.role=="damage" and inst.target or inst.side
  local otherSide=originSide==inst.side and inst.target or inst.side
  local basis=CSM:wazaBasis(ctx,originSide,otherSide,e.attachment,{moveId=(inst.spec and inst.spec.moveId) or inst.moveId,
    style=inst.spec and inst.spec.style,role=inst.role,sourceStrict=true,positionType=e.positionType,flags=e.flags})
  if not basis then return nil,"linked effect-model world basis unavailable" end
  local m=modelMatrix(basis,nil,asset)
  local function column(i)
    local x,y,z=m[i],m[i+4],m[i+8];local n=math.sqrt(x*x+y*y+z*z)
    if n<1e-9 then return nil end
    return {x/n,y/n,z/n},n
  end
  local right,x=column(1);local up,y=column(2);local forward,z=column(3)
  if not (right and up and forward) then return nil,"singular linked effect-model transform" end
  basis.origin={m[4],m[8],m[12]};basis.right=right;basis.up=up;basis.forward=forward
  basis.sourceUnits={x=x,y=y,z=z};basis.modelLinked=true
  return {basis=basis,part=part,modelIdentifier=wanted,partIndex=entry.partIndex,frame=frame}
end

-- Source type 2 is proven by the retail main.dol dispatcher/loader to be the
-- Waza HSD effect-model entry. 1.6 compiles its HSD data during MoveFX cache
-- extraction and instantiates the cached model at the authored sequence frame.
local function modelStart(ctx,inst,entry,eventName,state)
  local asset=entry and entry.modelAsset
  if not (type(asset)=="table" and asset.cache) then
    H.modelErrors[key(inst,entry)]=tostring(entry and entry.modelError or "type-2 model asset unavailable")
    return false
  end
  local k=key(inst,entry)
  H.models[k]={context=ctx,instance=inst,entry=entry,state=state,asset=asset,startedFrame=inst.frame,rawPath=entry.rawPath,
    dataOffset=entry.dataOffset,dataSize=entry.dataSize or entry.embeddedSize,dataMagic=entry.dataMagic}
  H.lastModel=H.models[k]
  return true
end
local function modelUpdate(ctx,inst,entry,frame,state)
  local asset=entry and entry.modelAsset
  local anim=asset and asset.animation
  local localFrame=(tonumber(frame) or tonumber(inst.frame) or 0)-(tonumber(state and state.startFrame) or 0)
  if type(anim)=="table" and (anim.animated==true or anim.partsAnimated==true) then
    return localFrame < (tonumber(anim.endFrame) or 0) and true or "done"
  end
  -- Until the remaining Type-2 payload words prove a separate object lifetime,
  -- a static source model remains alive through the authored Waza timeline.
  return (tonumber(frame) or 0)<(tonumber(inst.sourceEndFrame) or 1) and true or "done"
end
local function modelFinish(ctx,inst,entry) remove(H.models,key(inst,entry));return true end
local function modelCancel(ctx,inst,entry) remove(H.models,key(inst,entry));return true end
local function opaqueStart(ctx,inst,entry)
  H.opaque[#H.opaque+1]={context=ctx,serial=inst.serial,frame=inst.frame,entryType=entry.entryType,
    kind=entry.kind,index=entry.index,identifier=entry.identifier,rawPath=entry.rawPath,
    rawOffset=entry.rawOffset,rawSize=entry.rawSize,payloadOffset=entry.payloadOffset,
    commonMode=entry.commonMode,words=entry.words,subtype=entry.subtype,mode=entry.mode,value=entry.value,effectType=entry.effectType,effectFrames=entry.effectFrames}
  while #H.opaque>512 do table.remove(H.opaque,1) end
  return true
end
local function opaqueFinish() return true end

local function controllerSide(inst)
  if not inst then return "player" end
  -- Damage rows operate on the struck owner; attack/controller rows on source.
  return (inst.role=="damage" and inst.target) or inst.side or "player"
end
local function controllerState(inst)
  local side=controllerSide(inst);H.controllers[side]=H.controllers[side] or {};return H.controllers[side],side
end
local function signed32(v)
  v=tonumber(v) or 0;v=v%4294967296
  return v>=2147483648 and (v-4294967296) or v
end

-- Source type 1 is the retail sequence wait/stop controller. GC6E01 converts
-- subtype-0 source frames by video-vsync/60; CBE's presentation scheduler is
-- fixed at 60 Hz, so the serialized count is already the exact runtime delay.
-- Other subtype payload words are preserved bit-exactly rather than inventing
-- RNG or easing semantics that are not in the retail dispatcher.
local function type1Start(ctx,inst,entry,event,state)
  local mode=tonumber(entry.subtype) or 0;if mode<0 or mode>3 then return false end
  -- Retail wazaSequenceEntryUpdate only treats runtime subtype 0 as the
  -- sequence-boundary waiter. Source subtype 1/2 entries return immediately;
  -- subtype 3 is normalized by the loader to subtype 0 with a zero delay after
  -- its auxiliary table is consumed. Older CBE made 1/2 into waits and could
  -- stop an otherwise valid move chapter at the wrong frame.
  state.controllerImmediate=(mode==1 or mode==2)
  local delay=(mode==0) and math.max(0,math.floor(tonumber(entry.controllerParam) or 0)) or 0
  state.controllerDelay=delay;state.controllerMode=mode
  return true
end
local function type1Update(ctx,inst,entry,frame,state)
  if state.controllerImmediate then return "done" end
  local elapsed=(tonumber(frame) or 0)-(tonumber(state.startFrame) or 0)
  if elapsed < (tonumber(state.controllerDelay) or 0) then return true end
  if Waza and type(Waza.requestStop)=="function" then Waza:requestStop(inst,"type1-sequence-boundary") end
  return "done"
end

-- Source type 6 is a zero-duration owner/model controller. The names below are
-- direct counterparts of the GC6E01 wazaSequenceEntryStart dispatch.
local function type6Start(ctx,inst,entry)
  local st,side=controllerState(inst);local op=entry.controllerOp
  if op=="visibility_off" then st.hidden=true
  elseif op=="visibility_on" then st.hidden=false
  elseif op=="ambient_enable" then st.ambient=true
  elseif op=="ambient_clear" then st.ambient=false
  elseif op=="remove_root_null" then st.rootNull=false
  elseif op=="lighting_override_enable" then st.lightingOverride=true
  elseif op=="field_effect_clear" then st.fieldEffect=false
  elseif op=="lighting_override_activate" then st.lightingActive=true
  elseif op=="lighting_override_clear" then st.lightingActive=false;st.lightingOverride=false
  elseif op=="sequence_cleanup" then
    if Waza and type(Waza.requestStop)=="function" then Waza:requestStop(inst,"type6-sequence-cleanup") end
  else return false end
  st.lastOp=op;st.serial=inst.serial;st.frame=inst.frame;st.side=side
  return true
end

function H.actorVisible(_,side)
  local st=H.controllers[tostring(side or "")]
  if st and st.hidden==true then return false end
  return nil
end
function H.actorControllerState(_,side) return H.controllers[tostring(side or "")] end

local function effectStart(ctx,inst,entry,event,state)
  local family=tonumber(entry.effectType);if not family or family<0 or family>12 then return false end
  local k=key(inst,entry);local duration=math.max(1,math.floor(tonumber(entry.effectFrames) or tonumber(entry.effect and entry.effect.frames) or 1))
  local rec={context=ctx,instance=inst,entry=entry,state=state,family=family,effect=entry.effect or {},startedFrame=inst.frame,duration=duration,assets=entry.effectAssets or {},history={}}
  rec.textureSpec=entry.effectTextureAsset
  if not rec.textureSpec then for _,a in ipairs(rec.assets) do if type(a)=="table" and type(a.texture)=="table" then rec.textureSpec=a.texture;break end end end
  H.effects[k]=rec;state.effectEndFrame=(tonumber(state.startFrame) or inst.frame)+duration
  if type(entry.effectModelAsset)=="table" and entry.effectModelAsset.cache then
    H.models[k]={context=ctx,instance=inst,entry=entry,state=state,asset=entry.effectModelAsset,startedFrame=inst.frame,rawPath=entry.rawPath,effectRec=rec}
  end
  return true
end
local function effectUpdate(ctx,inst,entry,frame,state)
  return ((tonumber(frame) or 0)<(tonumber(state.effectEndFrame) or ((tonumber(state.startFrame) or 0)+1))) and true or "done"
end
local function releaseDynamicMeshes(rec)
  for _,mesh in pairs(rec and rec.dynamicMeshes or {}) do if mesh and mesh.release then pcall(mesh.release,mesh) end end
  if rec then rec.dynamicMeshes=nil end
end
local function effectFinish(ctx,inst,entry)
  local k=key(inst,entry);local rec=H.effects[k]
  releaseDynamicMeshes(rec)
  H.effects[k]=nil;H.models[k]=nil;return true
end

function H.install()
  if H.installed or not (Waza and type(Waza.registerHandler)=="function") then return false end
  Waza:registerHandler("model","cbe-waza-model",{start=modelStart,update=modelUpdate,finish=modelFinish,cancel=modelCancel})
  -- Type-3 stays on Colosseum's particle-bank path. 1.9.13 registered an
  -- HSD-model interpretation here; the retail loader instead passes these
  -- resources through loadParticle() and fn_801190DC.
  if Audio then
    Waza:registerHandler("sound","cbe-waza-audio",{
      start=function(...) return Audio:start(...) end,
      update=function(...) return Audio:update(...) end,
      finish=function(...) return Audio:finish(...) end,
      cancel=function(...) return Audio:cancel(...) end})
  end
  Waza:registerHandler("type1","cbe-waza-controller",{start=type1Start,update=type1Update,finish=opaqueFinish,cancel=opaqueFinish})
  Waza:registerHandler("type4","cbe-waza-tracefx",{start=effectStart,update=effectUpdate,finish=effectFinish,cancel=effectFinish})
  Waza:registerHandler("type6","cbe-waza-owner-controller",{start=type6Start,finish=opaqueFinish,cancel=opaqueFinish})
  H.installed=true
  return true
end


local function graphicsScope(g,fn)
  local okPush,pushErr=pcall(g.push,"all")
  if not okPush then return false,nil,pushErr end
  local ok,value=pcall(fn)
  pcall(g.setShader)
  pcall(g.setDepthMode)
  pcall(g.pop)
  if not ok then return false,nil,value end
  return true,value,nil
end

local function modelRenderFault(rec,grp,err)
  local inst=rec and rec.instance
  H.drawError=("Type-2 render fault move=%s entry=%s: %s")
    :format(tostring(inst and inst.moveId or "?"),tostring(rec and rec.entry and rec.entry.index or "?"),tostring(err))
  H.renderFaults=(tonumber(H.renderFaults) or 0)+1
  if type(grp)=="table" then
    grp._cbeRenderFaults=(tonumber(grp._cbeRenderFaults) or 0)+1
    if grp._cbeRenderFaults>=3 then grp._cbeRenderDisabled=true end
  end
end

local function effectRGBA(c,alpha)
  c=type(c)=="table" and c or {255,255,255,255};local a=(tonumber(c[4]) or 255)/255
  return (tonumber(c[1]) or 255)/255,(tonumber(c[2]) or 255)/255,(tonumber(c[3]) or 255)/255,math.max(0,math.min(1,a*(alpha or 1)))
end
local function lerp(a,b,t)return (tonumber(a) or 0)+((tonumber(b) or 0)-(tonumber(a) or 0))*t end
local function effectSides(rec)
  local inst=rec and rec.instance;if not inst then return "player","enemy" end
  local origin=(inst.role=="damage") and inst.target or inst.side
  local other=origin==inst.side and inst.target or inst.side
  return origin or "player",other or "enemy"
end
local function sourceBasis(ctx,rec,attachment)
  if not (CSM and type(CSM.wazaBasis)=="function") then return nil end
  local inst=rec.instance;local originSide,other=effectSides(rec)
  local ok,b=pcall(CSM.wazaBasis,CSM,ctx,originSide,other,attachment~=nil and attachment or (rec.entry and rec.entry.attachment),
    {moveId=(inst.spec and inst.spec.moveId) or inst.moveId,style=inst.spec and inst.spec.style,role=inst.role,sourceStrict=true,positionType=rec.entry and rec.entry.positionType,flags=rec.entry and rec.entry.flags})
  return ok and b or nil
end
local function sourceLocalPoint(ctx,rec,pos,attachment)
  if not (type(pos)=="table" and CSM and type(CSM.wazaLocalPoint)=="function") then return nil end
  local inst=rec.instance;local originSide,other=effectSides(rec)
  local ok,p=pcall(CSM.wazaLocalPoint,CSM,ctx,originSide,other,attachment~=nil and attachment or (rec.entry and rec.entry.attachment),pos,
    {moveId=(inst.spec and inst.spec.moveId) or inst.moveId,style=inst.spec and inst.spec.style,role=inst.role,sourceStrict=true,positionType=rec.entry and rec.entry.positionType,flags=rec.entry and rec.entry.flags})
  return ok and p or nil
end
local function projectSource(ctx,p)
  if not (CSM and type(CSM.projectWazaWorld)=="function") then return nil end
  local ok,x,y=pcall(CSM.projectWazaWorld,CSM,ctx,p);if ok then return x,y end
end
local function effectProgress(rec)
  local inst=rec and rec.instance
  local frame=(tonumber(inst and inst.frame) or 0)+(tonumber(inst and inst.accumulator) or 0)*60-(tonumber(rec and rec.startedFrame) or 0)
  return math.max(0,math.min(1,frame/math.max(1,tonumber(rec and rec.duration) or 1))),frame
end
local function effectImage(rec)
  if rec.image==false then return nil end
  if rec.image then return rec.image end
  if type(rec.textureSpec)~="table" then rec.image=false;return nil end
  local img,err=imageFromRaw(rec.textureSpec)
  if not img then H.drawError=("Type-4 source texture load failed family=%s move=%s: %s")
    :format(tostring(rec.family),tostring(rec.instance and rec.instance.moveId),tostring(err));rec.image=false;return nil end
  rec.image=img;return img
end
local function keyedColor(keys,p,default)
  -- Aura/blur keys are scalar energy, not RGBA. Do not index a scalar as a
  -- colour: this used to abort the complete world pass for e.g. Mega Punch.
  if type(default)~="table" then default={255,255,255,255} end
  if type(keys)=="table" and type(keys[1])=="table"
      and type(keys[1].from)~="table" and type(keys[1].to)~="table" then return default end
  if type(keys)~="table" or #keys==0 then return default end
  local total=0
  for _,k in ipairs(keys) do local d=tonumber(k.duration) or 0;if d>0 and d<100000 then total=total+d end end
  if total<=0 then return keys[#keys].to or keys[1].from or default end
  local at=p*total;local elapsed=0
  for _,k in ipairs(keys) do
    local d=tonumber(k.duration) or 0
    if d>0 and d<100000 then
      if at<=elapsed+d then
        local t=math.max(0,math.min(1,(at-elapsed)/d));local a=type(k.from)=="table" and k.from or default;local b=type(k.to)=="table" and k.to or a
        return {lerp(a[1],b[1],t),lerp(a[2],b[2],t),lerp(a[3],b[3],t),lerp(a[4],b[4],t)}
      end
      elapsed=elapsed+d
    end
  end
  return keys[#keys].to or default
end
local function keyedScalar(e,p,default)
  local keys=e and e.keys
  if type(keys)~="table" or #keys==0 then return tonumber(e and e.value) or default end
  local total=0;for _,k in ipairs(keys) do local d=tonumber(k.duration) or 0;if d>0 and d<100000 then total=total+d end end
  if total<=0 then return tonumber(keys[#keys].to) or tonumber(keys[1].from) or default end
  local at=p*total;local elapsed=0
  for _,k in ipairs(keys) do local d=tonumber(k.duration) or 0;if d>0 and d<100000 then
    if at<=elapsed+d then return lerp(k.from,k.to,math.max(0,math.min(1,(at-elapsed)/d))) end;elapsed=elapsed+d end end
  return tonumber(keys[#keys].to) or default
end
local function angle2(y,x)
  if type(math.atan2)=="function" then return math.atan2(y,x) end
  -- Lua 5.3+ accepts atan(y,x); the manual quadrant fallback keeps this safe
  -- on stripped Lua/LuaJIT hosts that expose only one-argument atan.
  local ok,v=pcall(math.atan,y,x);if ok and type(v)=="number" then return v end
  if x>0 then return math.atan(y/x) end
  if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
  return y>0 and math.pi*.5 or (y<0 and -math.pi*.5 or 0)
end
local function drawTexturedSegment(g,img,x1,y1,x2,y2,width)
  if not (img and x1 and y1 and x2 and y2) then return false end
  local dx,dy=x2-x1,y2-y1;local len=math.sqrt(dx*dx+dy*dy);if len<.25 then return false end
  local iw,ih=math.max(1,img:getWidth()),math.max(1,img:getHeight())
  g.draw(img,(x1+x2)*.5,(y1+y2)*.5,angle2(dy,dx),len/iw,math.max(.5,tonumber(width) or ih)/ih,iw*.5,ih*.5)
  return true
end
local function drawTraceRibbon(g,img,rec,e,p)
  local bA=sourceBasis(rec.context or {},rec,e.partA or (rec.entry and rec.entry.attachment))
  local bB=sourceBasis(rec.context or {},rec,e.partB or (rec.entry and rec.entry.attachment))
  if not (bA and bB and bA.origin and bB.origin) then return false end
  local ax,ay=projectSource(rec.context or {},bA.origin);local bx,by=projectSource(rec.context or {},bB.origin)
  if not (ax and bx) then return false end
  local frame=math.floor((tonumber(rec.instance and rec.instance.frame) or 0)+.5)
  if rec.historyFrame~=frame then
    rec.historyFrame=frame;rec.history[#rec.history+1]={ax=ax,ay=ay,bx=bx,by=by}
    local maxn=math.max(2,math.min(128,tonumber(e.maxSegments) or 24));while #rec.history>maxn do table.remove(rec.history,1) end
  end
  if #rec.history<2 then return false end
  local live=math.max(2,math.min(#rec.history,tonumber(e.liveSegments) or #rec.history))
  local first=#rec.history-live+1;local verts={}
  for i=first,#rec.history do
    local h=rec.history[i];local v=(i-first)/math.max(1,live-1);local fade=.18+.82*v
    verts[#verts+1]={h.ax,h.ay,0,v,1,1,1,fade}
    verts[#verts+1]={h.bx,h.by,1,v,1,1,1,fade}
  end
  local fmt={{"VertexPosition","float",2},{"VertexTexCoord","float",2},{"VertexColor","float",4}}
  rec.dynamicMeshes=rec.dynamicMeshes or {}
  local mesh=rec.dynamicMeshes.trace;local capacity=rec.traceCapacity or 0
  if not mesh or #verts>capacity then
    if mesh and mesh.release then pcall(mesh.release,mesh) end
    capacity=math.min(256,math.max(8,capacity*2,#verts))
    local ok,built=pcall(g.newMesh,fmt,capacity,"strip","stream")
    if not ok or not built then rec.dynamicMeshes.trace=nil;rec.traceCapacity=nil;return false end
    mesh=built;rec.dynamicMeshes.trace=mesh;rec.traceCapacity=capacity
  end
  local ok=pcall(mesh.setVertices,mesh,verts)
  if not ok then return false end
  if mesh.setDrawRange then mesh:setDrawRange(1,#verts) end
  if img then pcall(mesh.setTexture,mesh,img) end
  return pcall(g.draw,mesh)
end

local COLOR_MESH_FORMAT={{"VertexPosition","float",2},{"VertexColor","float",4}}
local function drawDynamicColorMesh(g,rec,slot,verts)
  rec.dynamicMeshes=rec.dynamicMeshes or {};local mesh=rec.dynamicMeshes[slot]
  if mesh and mesh.setVertices then
    local ok=pcall(mesh.setVertices,mesh,verts)
    if not ok then if mesh.release then pcall(mesh.release,mesh) end;mesh=nil;rec.dynamicMeshes[slot]=nil end
  end
  if not mesh then
    local ok,built=pcall(g.newMesh,COLOR_MESH_FORMAT,verts,"triangles","stream");if not ok or not built then return false end
    mesh=built;rec.dynamicMeshes[slot]=mesh
  end
  return pcall(g.draw,mesh)
end
local function drawSoftEllipseRing(g,rec,slot,cx,cy,rx,ry,thickness,alpha)
  local verts={};local segments=48;local inner=math.max(.05,1-math.max(.02,math.min(.45,tonumber(thickness) or .10)))
  for i=0,segments-1 do
    local a0=i/segments*math.pi*2;local a1=(i+1)/segments*math.pi*2
    local x0,y0=cx+math.cos(a0)*rx,cy+math.sin(a0)*ry;local x1,y1=cx+math.cos(a1)*rx,cy+math.sin(a1)*ry
    local ix0,iy0=cx+math.cos(a0)*rx*inner,cy+math.sin(a0)*ry*inner
    local ix1,iy1=cx+math.cos(a1)*rx*inner,cy+math.sin(a1)*ry*inner
    verts[#verts+1]={ix0,iy0,1,1,1,0};verts[#verts+1]={x0,y0,1,1,1,alpha};verts[#verts+1]={x1,y1,1,1,1,alpha}
    verts[#verts+1]={ix0,iy0,1,1,1,0};verts[#verts+1]={x1,y1,1,1,1,alpha};verts[#verts+1]={ix1,iy1,1,1,1,0}
  end
  return drawDynamicColorMesh(g,rec,slot,verts)
end
local function drawAuraField(g,rec,cx,cy,rx,ry,alpha)
  local verts={};local segments=56
  for i=0,segments-1 do
    local a0=i/segments*math.pi*2;local a1=(i+1)/segments*math.pi*2
    verts[#verts+1]={cx,cy,1,1,1,alpha}
    verts[#verts+1]={cx+math.cos(a0)*rx,cy+math.sin(a0)*ry,1,1,1,0}
    verts[#verts+1]={cx+math.cos(a1)*rx,cy+math.sin(a1)*ry,1,1,1,0}
  end
  return drawDynamicColorMesh(g,rec,"aura",verts)
end

-- World-space implementation of the thirteen retail Type-4 effect families.
-- Full-screen families (filter/blur/distortion) are applied later in drawPost
-- so they can operate on the completed arena framebuffer instead of faking a
-- target-space ring.
local function drawProceduralEffects(ctx)
  if not (love and love.graphics) then return false end
  local g=love.graphics;local drew=false
  for _,rec in pairs(H.effects) do
    local fam=tonumber(rec.family) or -1;local e=rec.effect or {};local inst=rec.instance;rec.context=ctx
    if fam~=2 and fam~=8 and fam~=10 and not (rec.entry and rec.entry.effectModelAsset) then
      local b=sourceBasis(ctx,rec);local p=effectProgress(rec)
      if b and b.origin and b.target then
        local x1,y1=projectSource(ctx,b.origin);local x2,y2=projectSource(ctx,b.target)
        if x1 and x2 then
          local c=keyedColor(e.keys,p,e.color or e.colorA or {255,255,255,255})
          local r,gc,bb,a=effectRGBA(c,1-p*.12)
          g.push("all");g.setColor(r,gc,bb,a)
          if fam==0 then
            -- surfEffectStart: source-timed concentric surface waves anchored to
            -- the effect owner. Use serialized colour keyframes directly.
            pcall(g.setBlendMode,"add","alphamultiply")
            local radius=math.max(12,math.min(180,(tonumber(e.count) or 4)*7+42*p))
            for i=0,math.max(1,math.min(6,tonumber(e.count) or 3))-1 do
              local q=(p+i*.17)%1;g.setColor(r,gc,bb,1)
              drew=drawSoftEllipseRing(g,rec,i+1,x2,y2,radius*(.35+.8*q),radius*(.12+.32*q),.08+.05*q,a*(1-q)*.45) or drew
            end
          elseif fam==1 then
            -- electronStartEffect: branch chains use the actual serialized GS
            -- texture and authored count/depth. Descriptor vectors remain in
            -- Pokemon-local source units and are transformed by wazaLocalPoint.
            local img=effectImage(rec)
            local ws=sourceLocalPoint(ctx,rec,e.start);local we=sourceLocalPoint(ctx,rec,e.endv)
            local sx,sy,ex,ey;if ws then sx,sy=projectSource(ctx,ws) end;if we then ex,ey=projectSource(ctx,we) end
            sx,sy=sx or x1,sy or y1;ex,ey=ex or x2,ey or y2
            local count=math.max(1,math.min(16,tonumber(e.partA) or 3));local depth=math.max(1,math.min(5,tonumber(e.partB) or 2))
            if img then
              pcall(g.setBlendMode,"add","alphamultiply")
              for branch=1,count do
                local px,py=sx,sy;local dx,dy=ex-sx,ey-sy;local len=math.max(1,math.sqrt(dx*dx+dy*dy));local nx,ny=-dy/len,dx/len
                local pieces=math.max(3,depth*3)
                for j=1,pieces do
                  local t0=(j-1)/pieces;local t1=j/pieces
                  local amp=len*(.018+.009*depth)*(1-p*.25)
                  local j0=(j==1) and 0 or math.sin((branch*37+j*19+(inst.serial or 0)*11)*1.731)*amp
                  local j1=(j==pieces) and 0 or math.sin((branch*37+(j+1)*19+(inst.serial or 0)*11)*1.731)*amp
                  local ax=sx+dx*t0+nx*j0;local ay=sy+dy*t0+ny*j0;local bx=sx+dx*t1+nx*j1;local by=sy+dy*t1+ny*j1
                  drew=drawTexturedSegment(g,img,ax,ay,bx,by,math.max(2,math.abs(tonumber(e.width) or 3))) or drew
                end
              end
            end
          elseif fam==3 then
            -- lightningStartEffect: textured source bolt with authored endpoint
            -- vectors and colour ramp, distinct from the electron branch system.
            local img=effectImage(rec);local ws=sourceLocalPoint(ctx,rec,e.start);local we=sourceLocalPoint(ctx,rec,e.endv)
            local sx,sy,ex,ey;if ws then sx,sy=projectSource(ctx,ws) end;if we then ex,ey=projectSource(ctx,we) end;sx,sy=sx or x1,sy or y1;ex,ey=ex or x2,ey or y2
            if img then
              pcall(g.setBlendMode,"add","alphamultiply");local dx,dy=ex-sx,ey-sy;local len=math.max(1,math.sqrt(dx*dx+dy*dy));local nx,ny=-dy/len,dx/len
              local pieces=math.max(5,math.min(24,tonumber(e.mode) or 10));local lastx,lasty=sx,sy
              for j=1,pieces do local t=j/pieces;local amp=len*.035*(1-.35*p);local jitter=(j==pieces) and 0 or math.sin((j*29+(inst.serial or 0)*13)*2.07)*amp
                local nxp=sx+dx*t+nx*jitter;local nyp=sy+dy*t+ny*jitter;drew=drawTexturedSegment(g,img,lastx,lasty,nxp,nyp,math.max(3,math.abs(tonumber(e.values and e.values[1]) or 4))) or drew;lastx,lasty=nxp,nyp end
            end
          elseif fam==4 then
            local img=effectImage(rec);if img then pcall(g.setBlendMode,"alpha","alphamultiply");drew=drawTraceRibbon(g,img,rec,e,p) or drew end
          elseif fam==9 then
            -- auraEffectStart: additive owner-centred glow. Scalar keyframes
            -- drive radius/energy rather than a fabricated attack projectile.
            pcall(g.setBlendMode,"add","alphamultiply");local v=math.abs(keyedScalar(e,p,1));local rad=math.max(10,math.min(180,22+v*18))*(.72+.28*math.sin(math.pi*p))
            g.setColor(r,gc,bb,1);drew=drawAuraField(g,rec,x1,y1,rad,rad*1.28,a*.34) or drew
          elseif fam==12 then
            -- billboardEffectStart: exact source GS texture, screen-facing by
            -- definition. Source scalars control sprite scale/rotation.
            local img=effectImage(rec);if img then
              pcall(g.setBlendMode,"alpha","alphamultiply")
              local scale=math.max(.08,math.min(8,math.abs(tonumber(e.a) or 1)*(0.7+0.3*math.sin(math.pi*p))))
              g.draw(img,x2,y2,(tonumber(e.b) or 0)*p,scale,scale,img:getWidth()*.5,img:getHeight()*.5);drew=true
            end
          end
          g.pop()
        end
      end
    end
  end
  return drew
end

local DISTORT_SHADER=[[
extern number amount;
extern number frequency;
extern number phase;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec2 q=uv;
  q.x += sin((uv.y+phase)*frequency)*amount;
  q.y += sin((uv.x+phase*0.73)*frequency*0.81)*amount*0.55;
  return Texel(texture,q)*color;
}
]]
local function releasePost()
  for _,c in ipairs({H.postCanvas,H.postHistory}) do if c and c.release then pcall(c.release,c) end end
  H.postCanvas=nil;H.postHistory=nil;H.postW=0;H.postH=0;H.postHistoryValid=false
end
local function ensurePost(w,h)
  if H.postCanvas and H.postHistory and H.postW==w and H.postH==h then return true end
  releasePost()
  if not (love and love.graphics and love.graphics.newCanvas) then return false end
  local ok,a=pcall(love.graphics.newCanvas,w,h,{dpiscale=1,msaa=0});if not ok then ok,a=pcall(love.graphics.newCanvas,w,h) end
  if not ok or not a then return false end
  local ok2,b=pcall(love.graphics.newCanvas,w,h,{dpiscale=1,msaa=0});if not ok2 then ok2,b=pcall(love.graphics.newCanvas,w,h) end
  if not ok2 or not b then if a.release then pcall(a.release,a) end;return false end
  H.postCanvas,H.postHistory,H.postW,H.postH=a,b,w,h;H.postHistoryValid=false
  return true
end
local function ensureDistortShader()
  if H.distortShader then return H.distortShader end
  if not (love and love.graphics and love.graphics.newShader) then return nil end
  local ok,sh=pcall(love.graphics.newShader,DISTORT_SHADER);if ok then H.distortShader=sh;return sh end
  H.drawError=tostring(sh);return nil
end
local function activePostFamilies()
  local filter,blur,distort
  for _,rec in pairs(H.effects) do
    local fam=tonumber(rec.family)
    if fam==2 then filter=rec elseif fam==8 then blur=rec elseif fam==10 then distort=rec end
  end
  return filter,blur,distort
end

-- Post-process Type-4 source families after the complete arena/actor/trainer
-- frame exists. This is the correct integration point for Colosseum's filter,
-- motion-blur and distortion systems; drawing target-space stand-ins earlier
-- in the world pass would fundamentally change what those Waza entries mean.
function H.drawPost(ctx,sourceCanvas,w,h)
  local filter,blur,distort=activePostFamilies()
  if not (filter or blur or distort) then H.postHistoryValid=false;return false end
  local g=love and love.graphics;if not (g and sourceCanvas and w and h and ensurePost(w,h)) then return false end
  local ok,err=pcall(function()
    g.push("all");if g.origin then g.origin() end;if g.setScissor then g.setScissor() end;g.setShader();g.setDepthMode();g.setBlendMode("alpha","alphamultiply")

    -- Distortion is a real framebuffer sample/displace pass. The serialized
    -- descriptor's three float controls scale amplitude/frequency/phase.
    if distort then
      g.setCanvas(H.postCanvas);g.clear(0,0,0,0);g.setColor(1,1,1,1);g.draw(sourceCanvas,0,0)
      g.setCanvas(sourceCanvas);g.clear(0,0,0,0)
      local sh=ensureDistortShader();local p,frame=effectProgress(distort);local vals=distort.effect and distort.effect.values or {}
      if sh then
        g.setShader(sh)
        local amount=math.max(0.001,math.min(.045,math.abs(tonumber(vals[1]) or .9)*.006*(.45+.55*math.sin(math.pi*p))))
        local freq=math.max(8,math.min(90,math.abs(tonumber(vals[2]) or 3)*8+18))
        sh:send("amount",amount);sh:send("frequency",freq);sh:send("phase",(tonumber(frame) or 0)*.012+(tonumber(vals[3]) or 0)*.01)
      end
      g.setColor(1,1,1,1);g.draw(H.postCanvas,0,0);g.setShader()
    end

    -- Retail blur keeps framebuffer history. Reuse a persistent canvas across
    -- frames and composite it with source-keyframed energy instead of merely
    -- smearing particles inside the MoveFX layer.
    if blur then
      local p=effectProgress(blur);local strength=math.abs(keyedScalar(blur.effect or {},p,.5));strength=math.max(.04,math.min(.72,strength*.28))
      if H.postHistoryValid then
        g.setCanvas(sourceCanvas);g.setBlendMode("alpha","alphamultiply");g.setColor(1,1,1,strength)
        local drift=math.max(0,math.min(4,strength*4));g.draw(H.postHistory,-drift,0);g.draw(H.postHistory,drift,0)
      end
      g.setCanvas(H.postHistory);g.clear(0,0,0,0);g.setBlendMode("alpha","alphamultiply");g.setColor(1,1,1,1);g.draw(sourceCanvas,0,0);H.postHistoryValid=true
      g.setCanvas(sourceCanvas)
    else H.postHistoryValid=false end

    if filter then
      g.setCanvas(sourceCanvas);g.setShader();g.setBlendMode("alpha","alphamultiply")
      local p=effectProgress(filter);local e=filter.effect or {};local c=e.color or {255,255,255,255};local r,gg,b,a=effectRGBA(c,1)
      local energy=math.sin(math.pi*p);local scale=math.abs(tonumber(e.a) or tonumber(e.c) or 1);local alpha=math.max(0,math.min(.92,a*energy*math.max(.12,math.min(1,scale))))
      g.setColor(r,gg,b,alpha);g.rectangle("fill",0,0,w,h)
    end
    g.setColor(1,1,1,1);g.setShader();g.setCanvas(sourceCanvas);g.pop()
  end)
  if not ok then H.postErrors=(tonumber(H.postErrors) or 0)+1;H.drawError="Type-4 postprocess: "..tostring(err);pcall(g.setCanvas,sourceCanvas);pcall(g.setShader);return false end
  return true
end

local function shiftedBasis(base,x,y,z,scale,yaw)
  local b={};for k,v in pairs(base or {}) do b[k]=v end
  local u=type(base.sourceUnits)=="table" and base.sourceUnits or {x=1,y=1,z=1}
  local ux=tonumber(u.x) or tonumber(u[1]) or 1;local uy=tonumber(u.y) or tonumber(u[2]) or 1;local uz=tonumber(u.z) or tonumber(u[3]) or 1
  local r,up,f=base.right or {1,0,0},base.up or {0,1,0},base.forward or {0,0,1};local o=base.origin or {0,0,0}
  local angle=tonumber(yaw) or 0
  if angle~=0 then
    local ca,sa=math.cos(angle),math.sin(angle)
    local oldR,oldF=r,f
    r={oldR[1]*ca+oldF[1]*sa,oldR[2]*ca+oldF[2]*sa,oldR[3]*ca+oldF[3]*sa}
    f={oldF[1]*ca-oldR[1]*sa,oldF[2]*ca-oldR[2]*sa,oldF[3]*ca-oldR[3]*sa}
    b.right=r;b.forward=f
  end
  local ox=(tonumber(x) or 0)*ux;local oy=(tonumber(y) or 0)*uy;local oz=(tonumber(z) or 0)*uz
  b.origin={o[1]+r[1]*ox+up[1]*oy+f[1]*oz,o[2]+r[2]*ox+up[2]*oy+f[2]*oz,o[3]+r[3]*ox+up[3]*oy+f[3]*oz}
  local t=base.target or o;b.target={t[1]+r[1]*ox+up[1]*oy+f[1]*oz,t[2]+r[2]*ox+up[2]*oy+f[2]*oz,t[3]+r[3]*ox+up[3]*oy+f[3]*oz}
  local sm=math.max(.04,math.min(8,tonumber(scale) or 1));b.modelTargetSpan=(tonumber(base.modelTargetSpan) or tonumber(base.referenceVisualHeight) or 16)*sm
  return b
end
local function stable01(serial,index,salt)
  local n=((tonumber(serial) or 1)*73856093+(tonumber(index) or 1)*19349663+(tonumber(salt) or 0)*83492791)%2147483647
  return n/2147483647
end

function H.drawWorld(ctx)
  if not (love and love.graphics and CSM and type(CSM.wazaBasis)=="function") then return false end
  local vp=ctx and ctx.services and (ctx.services.vp or ctx.services.stageVP)
  if type(vp)~="table" then return false end
  local g=love.graphics;local jobs={}
  for _,rec in pairs(H.models) do
    local inst,entry=rec.instance,rec.entry
    local originSide=(inst and inst.role=="damage") and inst.target or (inst and inst.side)
    local otherSide=originSide==(inst and inst.side) and (inst and inst.target) or (inst and inst.side)
    local er=rec.effectRec;local ee=er and er.effect or nil;local family=tonumber(er and er.family)
    local attachment=entry and entry.attachment
    if ee and (family==5 or family==7 or family==11) then attachment=ee.partA or attachment end
    local okBasis,basis=pcall(CSM.wazaBasis,CSM,ctx,originSide,otherSide,attachment,{
      moveId=inst and ((inst.spec and inst.spec.moveId) or inst.moveId),style=inst and inst.spec and inst.spec.style,role=inst and inst.role,
      sourceStrict=true,positionType=entry and entry.positionType,flags=entry and entry.flags})
    local frac=(tonumber(inst and inst.accumulator) or 0)*60
    local localFrame=(tonumber(inst and inst.frame) or 0)+frac-(tonumber(rec.state and rec.state.startFrame) or tonumber(rec.startedFrame) or 0)
    local model,err,page
    if not rec.asset.transformOnly then model,err,page=loadModel(rec.asset,localFrame) end
    if okBasis and basis and model then
      if er and tonumber(er.family)==5 then
        -- leaffx: retail clones the embedded leaf model up to 32 times and
        -- drives each clone along a randomized Bezier path. Reconstruct that
        -- source behavior from the exact descriptor floats instead of drawing
        -- one stationary copy of the leaf asset.
        local e=er.effect or {};local vals=e.values or {};local p=effectProgress(er)
        local count=math.max(1,math.min(32,math.floor(tonumber(e.partA) or 1)))
        for li=1,count do
          local r1=stable01(inst and inst.serial,li,1);local r2=stable01(inst and inst.serial,li,2);local r3=stable01(inst and inst.serial,li,3)
          local scale=math.abs((tonumber(vals[1]) or 1)+(tonumber(vals[2]) or 0)*(r1*2-1));if scale<.05 then scale=1 end
          local h0=(tonumber(vals[3]) or 0)+(tonumber(vals[4]) or 0)*(r2*2-1)
          local radius=math.abs((tonumber(vals[5]) or .5)+(tonumber(vals[6]) or 0)*(r3*2-1))
          local speed=math.abs(tonumber(vals[7]) or .7)+.15
          local angle=r1*math.pi*2+(tonumber(inst and inst.frame) or 0)*.015*(.6+r2)
          local x=math.cos(angle)*radius+math.sin((p+r3)*math.pi*2)*radius*.28
          local z=math.sin(angle)*radius+math.cos((p+r2)*math.pi*2)*radius*.28
          local y=h0+(1-p)*radius*.45-p*speed
          jobs[#jobs+1]={rec=rec,basis=shiftedBasis(basis,x,y,z,scale,angle),model=model,page=page,
            localFrame=localFrame+(li-1)*.35,tint=keyedColor(e.keys,p,e.color)}
        end
      elseif er and tonumber(er.family)==6 then
        -- enviroEffectStart: keep the embedded HSD model and its environment
        -- texture generation, while applying the descriptor's local-space
        -- start/velocity/count/scalar controls in the live attacker basis.
        local e=er.effect or {};local vals=e.values or {};local p=effectProgress(er)
        local start=e.start or {0,0,0};local velocity=e.velocity or {0,0,0}
        local count=math.max(1,math.min(32,math.floor(tonumber(e.countA) or 1)))
        local spread=math.abs(tonumber(vals[2]) or 0);local baseScale=math.abs(tonumber(vals[1]) or 1)
        if baseScale<.02 or baseScale>16 then baseScale=1 end
        for mi=1,count do
          local lane=mi-(count+1)*.5;local phase=(mi-1)/math.max(1,count)
          local x=(tonumber(start[1]) or 0)+(tonumber(velocity[1]) or 0)*p+lane*spread
          local y=(tonumber(start[2]) or 0)+(tonumber(velocity[2]) or 0)*p
          local z=(tonumber(start[3]) or 0)+(tonumber(velocity[3]) or 0)*p
          jobs[#jobs+1]={rec=rec,basis=shiftedBasis(basis,x,y,z,baseScale,(p+phase)*math.pi*2),model=model,page=page,
            localFrame=localFrame+phase,tint=keyedColor(e.keys,p,e.color),environment=true}
        end
      elseif er and tonumber(er.family)==7 then
        -- seaEffectStart: the source wave model carries the authored shape and
        -- animation; descriptor vectors place and advect it in battle space.
        local e=er.effect or {};local p=effectProgress(er);local start=e.start or {0,0,0};local velocity=e.velocity or {0,0,0}
        local scale=math.abs(tonumber(e.a) or 1);if scale<.02 or scale>16 then scale=1 end
        local wave=math.sin(p*math.pi*2)*math.max(-8,math.min(8,tonumber(e.b) or 0))
        local x=(tonumber(start[1]) or 0)+(tonumber(velocity[1]) or 0)*p
        local y=(tonumber(start[2]) or 0)+(tonumber(velocity[2]) or 0)*p+wave
        local z=(tonumber(start[3]) or 0)+(tonumber(velocity[3]) or 0)*p
        jobs[#jobs+1]={rec=rec,basis=shiftedBasis(basis,x,y,z,scale),model=model,page=page,localFrame=localFrame,
          tint=keyedColor(e.keys,p,e.color)}
      elseif er and tonumber(er.family)==11 then
        -- patchiruEffectStart is an attachment/model family. partA selects the
        -- source anchor above; partB/mode control facing without replacing the
        -- embedded source model with a generated sprite.
        local e=er.effect or {};local p=effectProgress(er)
        local turns=(tonumber(e.mode) or 0)~=0 and p*(tonumber(e.partB) or 1) or 0
        jobs[#jobs+1]={rec=rec,basis=shiftedBasis(basis,0,0,0,1,turns*math.pi*2),model=model,page=page,
          localFrame=localFrame,tint=keyedColor(e.keys,p,e.color)}
      else jobs[#jobs+1]={rec=rec,basis=basis,model=model,page=page,localFrame=localFrame,
        tint=er and keyedColor((er.effect or {}).keys,effectProgress(er),(er.effect or {}).color) or nil} end
    elseif err then H.drawError=tostring(err) end
  end
  local proceduralDrew=drawProceduralEffects(ctx)
  if #jobs==0 then return proceduralDrew end
  local drew=proceduralDrew
  local ok,value,scopeErr=graphicsScope(g,function()
    local function pass(kind)
      if kind=="add" then pcall(g.setBlendMode,"add","alphamultiply")
      else pcall(g.setBlendMode,"alpha","alphamultiply") end
      for _,job in ipairs(jobs) do
        local sh,serr=ensureShader(job.model.morph)
        if sh then
          local okJob,jobErr=pcall(function()
            g.setShader(sh);sh:send("vp","row",vp);sh:send("model","row",modelMatrix(job.basis,job.model,job.rec and job.rec.asset))
            if job.model.morph then
              local weights=morphWeights(job.page,job.localFrame)
              for wi=0,12 do sh:send("w"..wi,weights[wi+1] or 0) end
            end
            for _,grp in ipairs(job.model.groups) do
              if not grp._cbeRenderDisabled then
                local class=grp.luminous and "add" or (grp.xlu and "alpha" or "solid")
                if class==kind then
                  local okGrp,grpErr=pcall(function()
                    local d=grp.diffuse or {1,1,1};local tr,tg,tb,ta=effectRGBA(job.tint,1)
                    if not job.tint then tr,tg,tb,ta=1,1,1,1 end
                    sh:send("materialColor",{tonumber(d[1]) or 1,tonumber(d[2]) or 1,tonumber(d[3]) or 1,(tonumber(grp.alpha) or 1)*ta})
                    sh:send("effectTint",{tr,tg,tb})
                    sh:send("useTexture",grp.image and 1 or 0);sh:send("opacity",1);sh:send("forceOpaque",0)
                    sh:send("envMode",job.environment and 1 or 0)
                    sh:send("unlit",(grp.luminous or grp.effect or grp.useConstant or not grp.useDiffuseLighting) and 1 or 0)
                    g.setDepthMode("lequal",class=="solid" and not grp.noz)
                    g.setColor(1,1,1,1);g.draw(grp.mesh);drew=true
                  end)
                  if not okGrp then modelRenderFault(job.rec,grp,grpErr);pcall(g.setShader,sh) end
                end
              end
            end
          end)
          if not okJob then modelRenderFault(job.rec,nil,jobErr);pcall(g.setShader) end
        else H.drawError=tostring(serr) end
      end
    end
    pass("solid");pass("alpha");pass("add")
    return drew
  end)
  if not ok then modelRenderFault(jobs[1] and jobs[1].rec,nil,scopeErr);return false end
  if value and not H.drawError then H.drawError=nil end
  return value==true
end

-- Draw one compiled GC6E01 type-2 source asset at an explicit world transform.
-- Capture uses this seam for the real Poké Ball model/texture/animation from
-- snatch_* WZX banks instead of rebuilding a lookalike sphere in PlayerTrainer.
function H.drawAsset(ctx,asset,vp,worldModel,localFrame,opts)
  opts=type(opts)=="table" and opts or {}
  if not (type(asset)=="table" and asset.cache and type(vp)=="table" and type(worldModel)=="table") then return false,"invalid source asset draw" end
  local model,err,page=loadModel(asset,localFrame)
  if not model then return false,err end
  local g=love and love.graphics;if not g then return false,"LÖVE graphics unavailable" end
  local opacity=math.max(0,math.min(1,tonumber(opts.opacity) or 1))
  local drew=false
  local ok,value,scopeErr=graphicsScope(g,function()
    local sh,serr=ensureShader(model.morph);if not sh then error(serr or "source model shader unavailable") end
    if opts.cullMode and g.setMeshCullMode then pcall(g.setMeshCullMode,opts.cullMode) end
    g.setShader(sh);sh:send("vp","row",vp);sh:send("model","row",worldModel)
    sh:send("effectTint",{1,1,1})
    if model.morph then
      local weights=morphWeights(page,localFrame)
      for wi=0,12 do sh:send("w"..wi,weights[wi+1] or 0) end
    end
    local function pass(kind)
      if kind=="add" then pcall(g.setBlendMode,"add","alphamultiply") else pcall(g.setBlendMode,"alpha","alphamultiply") end
      for _,grp in ipairs(model.groups or {}) do
        if not grp._cbeRenderDisabled then
          local class=opts.forceOpaque and "solid" or (grp.luminous and "add" or (grp.xlu and "alpha" or "solid"))
          if class==kind then
            local d=grp.diffuse or {1,1,1}
            local materialAlpha=opts.forceOpaque and 1 or (tonumber(grp.alpha) or 1)
            sh:send("materialColor",{tonumber(d[1]) or 1,tonumber(d[2]) or 1,tonumber(d[3]) or 1,materialAlpha})
            sh:send("useTexture",grp.image and 1 or 0);sh:send("opacity",opts.forceOpaque and 1 or opacity);sh:send("forceOpaque",opts.forceOpaque and 1 or 0)
            sh:send("envMode",0)
            local forcedUnlit=opts.unlit
            sh:send("unlit",forcedUnlit~=nil and (forcedUnlit and 1 or 0) or ((grp.luminous or grp.effect or grp.useConstant or not grp.useDiffuseLighting) and 1 or 0))
            if opts.depthAlways then
              g.setDepthMode("always",false)
            else
              -- Closed solid props (capture balls in particular) must write
              -- depth so their back shell cannot draw through the front shell.
              local writeDepth=(opts.forceOpaque==true) or (class=="solid" and not grp.noz)
              g.setDepthMode("lequal",writeDepth)
            end
            g.setColor(1,1,1,1);g.draw(grp.mesh);drew=true
          end
        end
      end
    end
    pass("solid");pass("alpha");pass("add")
    return drew
  end)
  if not ok then return false,scopeErr end
  return value==true,nil,model.bounds
end

function H.prewarm()
  -- Compile the two tiny HSD effect shaders during the normal game-ready
  -- frame rather than on the first Type-2 Waza draw.  Model/texture caches
  -- remain lazy; this moves only shader compilation off battle-critical frames.
  local okStatic,staticErr=ensureShader(false)
  local okMorph,morphErr=ensureShader(true)
  if not okStatic and staticErr then H.drawError=tostring(staticErr) end
  if not okMorph and morphErr then H.drawError=tostring(morphErr) end
  return okStatic~=nil or okMorph~=nil
end

-- Camera direction now follows the SAME live WazaSequence and source fight
-- geometry that position GPT1 particles and Type-2 HSD models. This is not a
-- fabricated per-move camera table: source timing, attachment selection,
-- attacker/target axis and actor-normalized scale all come from the decoded
-- Colosseum bank. A retail fight_common CObj probe gives a ~39.09 degree normal
-- battle lens, used here as the neutral source lens until the remaining camera
-- controller subtype is fully decoded.
local SOURCE_CAMERA_FOV=math.rad(39.09)
local function cadd(a,b,s)return {(a[1] or 0)+(b[1] or 0)*(s or 1),(a[2] or 0)+(b[2] or 0)*(s or 1),(a[3] or 0)+(b[3] or 0)*(s or 1)} end
local function clerp(a,b,t)return {(a[1] or 0)+((b[1] or 0)-(a[1] or 0))*t,(a[2] or 0)+((b[2] or 0)-(a[2] or 0))*t,(a[3] or 0)+((b[3] or 0)-(a[3] or 0))*t} end
local function cdist(a,b)local x=(b[1] or 0)-(a[1] or 0);local y=(b[2] or 0)-(a[2] or 0);local z=(b[3] or 0)-(a[3] or 0);return math.sqrt(x*x+y*y+z*z) end
local function csmooth(t)t=math.max(0,math.min(1,tonumber(t) or 0));return t*t*(3-2*t) end
local cameraContinuity={session=nil,currentSerial=nil,transitionFrom=nil,transitionStartFrame=0,lastPose=nil}
local function latestCameraInstance()
  local best
  for _,inst in ipairs(Waza and Waza.active or {}) do
    if type(inst)=="table" and not inst.done and type(inst.spec)=="table" then
      local owns=true
      if type(Waza.canOwn)=="function" then local ok,v=pcall(Waza.canOwn,Waza,inst.spec,inst.role);owns=ok and v==true end
      if owns and (not best or (tonumber(inst.serial) or 0)>(tonumber(best.serial) or 0)) then best=inst end
    end
  end
  return best
end
local function cameraAttachment(inst)
  local fallback
  for _,st in ipairs(inst and inst.entries or {}) do
    local e=st.entry
    if type(e)=="table" and (e.kind=="model" or e.kind=="particle") then
      fallback=fallback or e.attachment
      if st.started and not st.closed then return e.attachment end
    end
  end
  return fallback
end
local function offsetEye(focus,forward,right,back,side,height)
  local eye=cadd(focus,forward,-back)
  eye=cadd(eye,right,side)
  eye[2]=(eye[2] or 0)+height
  return eye
end
function H.cameraPose(ctx)
  if not (Waza and CSM and type(CSM.wazaBasis)=="function") then return nil end
  local inst=latestCameraInstance();if not inst then return nil end
  local role=tostring(inst.role or "attack")
  local originSide=role=="damage" and inst.target or inst.side
  local otherSide=originSide==inst.side and inst.target or inst.side
  local attachment=cameraAttachment(inst)
  local ok,basis=pcall(CSM.wazaBasis,CSM,ctx,originSide,otherSide,attachment,{
    moveId=(inst.spec and inst.spec.moveId) or inst.moveId,style=inst.spec and inst.spec.style,role=role,sourceStrict=true})
  if not ok or type(basis)~="table" or type(basis.origin)~="table" or type(basis.target)~="table" then return nil end

  local src,dst=basis.origin,basis.target
  local forward=type(basis.forward)=="table" and basis.forward or {0,0,-1}
  local right=type(basis.right)=="table" and basis.right or {1,0,0}
  local frame=(tonumber(inst.frame) or 0)+(tonumber(inst.accumulator) or 0)*60
  local total=math.max(1,tonumber(inst.sourceEndFrame) or 1)
  local p=math.max(0,math.min(1,frame/total));local sp=csmooth(p)
  local style=V.WazaPhasePolicy and V.WazaPhasePolicy.cameraStyle(inst.spec) or tostring(inst.spec and inst.spec.style or "impact"):lower()
  local fight=math.max(10,tonumber(basis.fightDistance) or cdist(src,dst))
  local sh=math.max(2.8,tonumber(basis.sourceVisualHeight) or 5.5)
  local th=math.max(2.8,tonumber(basis.targetVisualHeight) or sh)
  local avgH=(sh+th)*.5
  local focus,eye,fov=clerp(src,dst,.5),nil,SOURCE_CAMERA_FOV

  if role=="damage" then
    -- Hold the struck actor's live source pose. The authored reaction supplies
    -- the impact motion; do not add an unrelated shake waveform to every move.
    focus={src[1],src[2]+sh*.05,src[3]}
    eye=offsetEye(focus,forward,right,fight*.29,fight*.22,sh*.52)
    fov=math.rad(35.5)
  elseif style=="projectile" then
    -- The reference launch shot holds the attacker and its mouth-origin stream;
    -- the target receives its own damage shot. Do not chase the projectile
    -- across the entire arena before that authored phase boundary.
    focus=clerp(src,dst,.08);focus[2]=focus[2]+sh*.03
    eye=offsetEye(focus,forward,right,fight*.20,fight*.30,sh*.48)
    fov=math.rad(36.5)
  elseif style=="wave" then
    focus=clerp(src,dst,.5);focus[2]=focus[2]+avgH*.02
    eye=offsetEye(focus,forward,right,fight*.17,fight*.52,avgH*.68)
    fov=math.rad(40.0)
  elseif style=="contact" then
    focus=clerp(src,dst,.28);focus[2]=focus[2]+avgH*.04
    eye=offsetEye(focus,forward,right,fight*.23,fight*.36,avgH*.50)
    fov=math.rad(36.0)
  elseif style=="aura" or style=="self" then
    focus={src[1],src[2]+sh*.08,src[3]}
    eye=offsetEye(focus,forward,right,fight*.30,fight*.26,sh*.62)
    fov=math.rad(34.5)
  elseif style=="target" then
    focus={dst[1],dst[2]+th*.05,dst[3]}
    eye=offsetEye(focus,forward,right,fight*.28,-fight*.25,th*.57)
    fov=math.rad(35.5)
  else -- A readable held attack composition while exact retail curves are pending.
    focus=clerp(src,dst,.25);focus[2]=focus[2]+avgH*.04
    eye=offsetEye(focus,forward,right,fight*.25,-fight*.34,avgH*.56)
    fov=math.rad(36.0)
  end
  -- Chapter changes are cuts, including hit/launch changes. Live actor motion
  -- still moves the focus within each shot through Camera's velocity limiter.

  local k=tonumber(ctx and ctx.arena and ctx.arena.figureScale) or tonumber(ctx and ctx.services and ctx.services.figureScale) or 1
  eye={eye[1]*k,eye[2]*k,eye[3]*k};focus={focus[1]*k,focus[2]*k,focus[3]*k}
  local pose={eye=eye,focus=focus,fov=fov,sourceSerial=inst.serial,sourceFrame=frame,sourceProgress=p,
    sourceStyle=style,sourceRole=role,presentationSerial=inst.presentationSerial,blend=.10,cut=true}
  cameraContinuity.lastPose={eye={eye[1],eye[2],eye[3]},focus={focus[1],focus[2],focus[3]},fov=fov}
  return pose
end
function H.activeModels() local out={};for _,row in pairs(H.models) do out[#out+1]=row end;return out end
function H.finish() releasePost();if H.distortShader and H.distortShader.release then pcall(H.distortShader.release,H.distortShader) end;H.distortShader=nil;for _,rec in pairs(H.effects) do releaseDynamicMeshes(rec) end;H.models={};H.effects={};H.controllers={player={},enemy={}};cameraContinuity={session=nil,currentSerial=nil,transitionFrom=nil,transitionStartFrame=0,lastPose=nil};return true end

local function releaseLoveObject(obj,seen)
  if obj==nil then return end
  seen=seen or {}
  if seen[obj] then return end
  seen[obj]=true
  pcall(function()
    local release=obj.release
    if type(release)=="function" then release(obj) end
  end)
end

-- Release battle-used Waza GPU assets on Android without deleting the generated
-- model/texture files in mod.cache. Shader programs stay resident, avoiding a
-- compile hitch on the next move while preventing an unbounded per-move VRAM
-- cache from growing throughout a long mobile play session.
function H.trimRuntimeMemory()
  -- Keep only the four most recently used Waza effect models. The previous
  -- all-or-nothing purge guaranteed that common source effect meshes/textures
  -- were reparsed and reuploaded in the next battle. Four entries keep the
  -- working set tiny on mobile while avoiding that repeated first-use hitch.
  local ranked={}
  for path,asset in pairs(H.modelCache) do
    if type(asset)=="table" then ranked[#ranked+1]={path=path,asset=asset,use=tonumber(asset.__cbeUse) or 0} end
  end
  table.sort(ranked,function(a,b)return a.use>b.use end)
  local keep={};for i=1,math.min(4,#ranked) do keep[ranked[i].path]=true end
  local keptImages={}
  for path in pairs(keep) do
    local asset=H.modelCache[path]
    if type(asset)=="table" then
      for _,g in ipairs(asset.groups or {}) do if type(g)=="table" and g.image then keptImages[g.image]=true end end
      for _,img in pairs(asset.textures or {}) do if img then keptImages[img]=true end end
    end
  end
  local seen={}
  for path,asset in pairs(H.modelCache) do
    if not keep[path] and type(asset)=="table" then
      for _,g in ipairs(asset.groups or {}) do
        if type(g)=="table" then
          releaseLoveObject(g.mesh,seen)
          if g.image and not keptImages[g.image] then releaseLoveObject(g.image,seen) end
        end
      end
      for _,img in pairs(asset.textures or {}) do if not keptImages[img] then releaseLoveObject(img,seen) end end
      H.modelCache[path]=nil;H.modelErrors[path]=nil
    elseif asset==false then
      -- Failed cache entries are tiny; keep the failure memo so a malformed
      -- source effect is not reparsed every battle.
    end
  end
  for key,img in pairs(H.textureCache or {}) do
    if not keptImages[img] then releaseLoveObject(img,seen);H.textureCache[key]=nil end
  end
  H.partsCache={};releasePost();for _,rec in pairs(H.effects) do releaseDynamicMeshes(rec) end;H.models={};H.effects={};H.controllers={player={},enemy={}};H.opaque={};H.lastModel=nil
  cameraContinuity={session=nil,currentSerial=nil,transitionFrom=nil,transitionStartFrame=0,lastPose=nil}
  -- Meshes/textures above are explicitly released. Avoid a stop-the-world Lua
  -- collection on the battle-end seam; BattleRuntime performs incremental GC
  -- while the player is back in the overworld.
  return true
end

H._test={runtimeUsable=runtimeUsable,runtimeRoot=runtimeRoot,runtimeMetaPath=runtimeMetaPath,bakeRuntimeCache=bakeRuntimeCache,modelMatrix=modelMatrix,morphWeights=morphWeights,ensureShader=ensureShader,keyedColor=keyedColor,drawTraceRibbon=drawTraceRibbon,releaseDynamicMeshes=releaseDynamicMeshes}

function H.status()
  local m=0;for _ in pairs(H.models) do m=m+1 end
  local cached=0;for _,v in pairs(H.modelCache) do if v then cached=cached+1 end end
  return {installed=H.installed,activeModels=m,cachedModels=cached,opaqueEntries=#H.opaque,drawError=H.drawError,renderFaults=H.renderFaults or 0,runtimeMeshHits=runtimeMeshHits,runtimeMeshWrites=runtimeMeshWrites,runtimeMeshFallbacks=runtimeMeshFallbacks,hardCache=H.hardCacheStatus(),
    provenSourceTypes={controller=1,model=2,particle=3,effect=4,sound=5,ownerController=6},opaqueSourceTypes={},
    cameraDecoder="selected Waza chapter cuts + held live-attachment framing; retail camera curves not decoded",
    modelDecoder="native-HSD-60Hz-morph-pages-v4-safe-tev-pass"}
end
return H
