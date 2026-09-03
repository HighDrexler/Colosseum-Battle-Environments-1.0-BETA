local V=...
local function platformOS()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok and v then return tostring(v) end
  end
  return "Unknown"
end
local ANDROID_RUNTIME=platformOS()=="Android"
local mod,Mat4=V.mod,V.Mat4
local GeneratedAssets=V.GeneratedAssets
local RuntimeMeshCache=V.RuntimeMeshCache
local Dex=V.ColosseumDex
local A={version=1}

-- CBE's own Colosseum-sourced battle actors.
--
-- This publishes the SAME `battleActors` v1 capability that CurrentSpriteModels
-- already arbitrates for third-party providers (see PORTABLE_BATTLE_ACTORS.md).
-- CBE therefore consumes its own Pokemon models through the documented public
-- seam rather than through a private back door: an external provider with a
-- higher priority still wins, and a species we cannot supply still falls back
-- to the resolved 2D sprite for that side alone.
--
-- Everything drawn here is source geometry in a source-authored pose. The only
-- runtime-authored motion is the blend WEIGHT between two authored frames.

-- Base position/UV/normal plus twelve authored-frame positions.  The twelve
-- vec3 frame streams are losslessly packed into nine vec4 attributes so the
-- shader stays comfortably below the generic vertex-attribute limit on the
-- Gen1Recomp/LÖVE backends. 1.5.32 used one attribute per frame and could fail
-- shader linking at Frame12, which made the actor provider fail open to 2D.
-- STRIDE remains compact at 44 floats: 8 base + 9*4 packed-frame floats.
local FORMAT={
  {"VertexPosition","float",3},
  {"VertexTexCoord","float",2},
  {"VertexNormal","float",3},
  {"FramePack1","float",4},
  {"FramePack2","float",4},
  {"FramePack3","float",4},
  {"FramePack4","float",4},
  {"FramePack5","float",4},
  {"FramePack6","float",4},
  {"FramePack7","float",4},
  {"FramePack8","float",4},
  {"FramePack9","float",4},
}

local VERTEX=[[
uniform mat4 vp;
uniform mat4 model;
// w[0] weights the base (frame 0) stream; w[1..12] weight authored frames.
// Exactly two are non-zero at any time, so this is a linear interpolation
// between two real Colosseum frames -- never a synthesized pose.
uniform float w0;
uniform float w1;
uniform float w2;
uniform float w3;
uniform float w4;
uniform float w5;
uniform float w6;
uniform float w7;
uniform float w8;
uniform float w9;
uniform float w10;
uniform float w11;
uniform float w12;
uniform float hitFlash;
attribute vec3 VertexNormal;
attribute vec4 FramePack1;
attribute vec4 FramePack2;
attribute vec4 FramePack3;
attribute vec4 FramePack4;
attribute vec4 FramePack5;
attribute vec4 FramePack6;
attribute vec4 FramePack7;
attribute vec4 FramePack8;
attribute vec4 FramePack9;
varying vec3 worldPos;
varying vec3 worldNormal;

vec4 position(mat4 transform_projection, vec4 vertex_position) {
  // Losslessly unpack 12 authored vec3 poses from 9 vec4 attributes.
  vec3 f1  = FramePack1.xyz;
  vec3 f2  = vec3(FramePack1.w, FramePack2.x, FramePack2.y);
  vec3 f3  = vec3(FramePack2.z, FramePack2.w, FramePack3.x);
  vec3 f4  = FramePack3.yzw;
  vec3 f5  = FramePack4.xyz;
  vec3 f6  = vec3(FramePack4.w, FramePack5.x, FramePack5.y);
  vec3 f7  = vec3(FramePack5.z, FramePack5.w, FramePack6.x);
  vec3 f8  = FramePack6.yzw;
  vec3 f9  = FramePack7.xyz;
  vec3 f10 = vec3(FramePack7.w, FramePack8.x, FramePack8.y);
  vec3 f11 = vec3(FramePack8.z, FramePack8.w, FramePack9.x);
  vec3 f12 = FramePack9.yzw;
  vec3 p = vertex_position.xyz * w0
         + f1 * w1 + f2 * w2 + f3 * w3 + f4 * w4
         + f5 * w5 + f6 * w6 + f7 * w7 + f8 * w8
         + f9 * w9 + f10 * w10 + f11 * w11 + f12 * w12;
  vec4 world = model * vec4(p,1.0);
  worldPos = world.xyz;
  worldNormal = normalize((model * vec4(normalize(VertexNormal),0.0)).xyz);
  return vp * world;
}
]]

local PIXEL=[[
uniform vec3 cameraEye;
uniform vec4 tintColor;
uniform vec4 materialColor;
uniform float useTexture;
uniform float opacity;
uniform float hitFlash;
uniform float spawnFlash;
uniform float shinyShift;
varying vec3 worldPos;
varying vec3 worldNormal;

// Colosseum ships a `rare_` model for only 35 species. For every other Pokemon
// the source game recolours at runtime, so we do the same: a hue-rotation of
// the sampled texel rather than a second model or an invented palette.
vec3 hueShift(vec3 c, float a) {
  const vec3 k = vec3(0.57735);
  float ca = cos(a);
  return c*ca + cross(k,c)*sin(a) + k*dot(k,c)*(1.0-ca);
}

vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec4 texel = Texel(texture,uv);
  float texAlpha = mix(1.0, texel.a, useTexture);
  float a = texAlpha * materialColor.a * tintColor.a * opacity * color.a;
  if (a < 0.08) discard;
  vec3 base = mix(materialColor.rgb, texel.rgb, useTexture);
  if (shinyShift > 0.001) base = clamp(hueShift(base,shinyShift),0.0,1.0);
  vec3 n = normalize(worldNormal);
  vec3 lightDir = normalize(vec3(-0.42,0.82,0.38));
  float key = abs(dot(n,lightDir));
  float hemi = clamp(n.y*0.5+0.5,0.0,1.0);
  vec3 viewDir = normalize(cameraEye-worldPos);
  float rim = pow(1.0-clamp(abs(dot(n,viewDir)),0.0,1.0),2.4);
  float light = 0.72 + key*0.24 + hemi*0.07;
  vec3 rgb = base * light;
  rgb += vec3(0.055,0.075,0.10)*rim;
  rgb = clamp((rgb-vec3(0.5))*1.035+vec3(0.5),vec3(0.0),vec3(1.0));
  rgb = mix(rgb, vec3(1.0), spawnFlash);
  rgb = mix(rgb, vec3(1.0,0.86,0.86), hitFlash);
  return vec4(rgb*tintColor.rgb,a);
}
]]

local shader
local scenes={}          -- [dex] = {groups,bounds,clip,morphFrames,...}
local sceneErrors={}     -- [dex] = last load error, so we fail open once per species
local extractor,discOpener
local metadataReader
local pendingExtract={}
local sourceMetadata={}
local sceneUseSerial=0
local idleWarmQueue={}
local idleWarmSeen={}
local idleWarmGame=nil
local idleWarmNextAt=0
local actionWarmQueue={}
local actionWarmSeen={}
local actionWarmNextAt=0
local perf={sceneLoads=0,sceneHits=0,actionBuilds=0,actionPrewarms=0,actorAcquires=0,residentAcquireHits=0,reactionClamps=0,reactionFallbacks=0,actionDrawFallbacks=0,floorClamps=0,idleWarmLoads=0,idleWarmMs=0,residentTrimKept=0,residentTrimReleased=0,runtimeBaseHits=0,runtimeBaseWrites=0,runtimeActionHits=0,runtimeActionWrites=0}

local function log(level,fmt,...)
  local l=mod and mod.log
  if l and type(l[level])=="function" then pcall(l[level],l,"[ColosseumActors] "..fmt,...) end
end
local function readLua(path)
  local src,err=GeneratedAssets.read(path)
  if not src then return nil,err or ("missing "..path) end
  local chunk,lerr=load(src,"@"..tostring(mod.path or mod.id).."/"..path)
  if not chunk then return nil,lerr end
  local ok,value=pcall(chunk)
  if not ok then return nil,value end
  return value
end
local function runtimeRoot(dex) return ("cache/pokemon/%d/runtime_mesh_v1"):format(tonumber(dex) or 0) end
local function runtimeBasePath(dex) return runtimeRoot(dex).."/base.lua" end
local function runtimeBaseBinPath(dex,i) return runtimeRoot(dex)..("/base_%02d.f32"):format(tonumber(i) or 0) end
local function runtimeActionTag(name) return tostring(name or "action"):gsub("[^%w_%-]","_") end
local function runtimeActionManifestPath(dex,name) return runtimeRoot(dex).."/action_"..runtimeActionTag(name)..".lua" end
local function runtimeActionBinPath(dex,name,i) return runtimeRoot(dex).."/action_"..runtimeActionTag(name)..("_%02d.f32"):format(tonumber(i) or 0) end
local function runtimeActionFloorPath(dex,name) return runtimeRoot(dex).."/action_"..runtimeActionTag(name).."_floor.lua" end
local function sourceRevision(dex)
  if not (extractor and type(extractor.revPath)=="function") then return nil end
  local body=GeneratedAssets.read(extractor.revPath(dex))
  return type(body)=="string" and body or nil
end
local function validRuntimeMeta(meta,stamp)
  return type(meta)=="table" and tonumber(meta.runtimeMeshVersion)==1 and type(stamp)=="string" and meta.stamp==stamp
end
local function runtimeBinLooksValid(path,stride)
  if not (path and GeneratedAssets and type(GeneratedAssets.info)=="function") then return false end
  local info=GeneratedAssets.info(path)
  local size=info and tonumber(info.size)
  local bytesPerVertex=(tonumber(stride) or 44)*4
  return size and size>=bytesPerVertex and size%bytesPerVertex==0
end
local function runtimeBaseUsable(meta,stamp,dex)
  if not validRuntimeMeta(meta,stamp) or type(meta.groups)~="table" or #meta.groups==0 then return false end
  for i,g in ipairs(meta.groups) do
    local path=type(g)=="table" and (g.runtimeBin or runtimeBaseBinPath(dex,i)) or nil
    if not path or not runtimeBinLooksValid(path,44) then return false end
  end
  return true
end
local function copyWithoutVertices(g)
  local out={}
  for k,v in pairs(g or {}) do if k~="vertices" and k~="verticesPacked" then out[k]=v end end
  return out
end
local function writeRuntimeBase(dex,cache,floorMin,stamp)
  if not (RuntimeMeshCache and RuntimeMeshCache.writeLua and type(stamp)=="string") then return false end
  local out={runtimeMeshVersion=1,stamp=stamp,floorMinY=floorMin}
  for k,v in pairs(cache or {}) do if k~="groups" then out[k]=v end end
  out.groups={}
  for i,g in ipairs(cache.groups or {}) do
    local c=copyWithoutVertices(g);c.runtimeBin=runtimeBaseBinPath(dex,i);out.groups[i]=c
  end
  local ok=RuntimeMeshCache.writeLua(runtimeBasePath(dex),out)
  if ok then perf.runtimeBaseWrites=(perf.runtimeBaseWrites or 0)+1 end
  return ok
end

local function compactMetadataLua(metadata)
  if type(metadata)~="table" then return nil end
  local function q(v) return string.format("%q",tostring(v)) end
  local out={"return {revision=1,bodyMap={"}
  local bodyKeys={"origin","mouth","chest","tail","eye_left","eye_right","hand_left","hand_right","additional_1","additional_2","additional_3","additional_4","foot_left","foot_right","center","additional_5"}
  for _,key in ipairs(bodyKeys) do out[#out+1]="["..q(key).."]="..tostring(tonumber(metadata.bodyMap and metadata.bodyMap[key]) or -1).."," end
  out[#out+1]="},slots={"
  for key,slot in pairs(metadata.slots or {}) do
    if type(key)=="string" and type(slot)=="table" then
      out[#out+1]="["..q(key).."]={animationIndex="..tostring(tonumber(slot.animationIndex) or -1)..",duration="..string.format("%.9g",tonumber(slot.duration) or 0).."},"
    end
  end
  out[#out+1]="}}\n"
  return table.concat(out)
end
local function metadataCachePath(dex) return ("cache/pokemon/%d/metadata_v1.lua"):format(tonumber(dex) or 0) end
local function writeMetadataCache(dex,metadata)
  if not (mod and mod.cache and type(mod.cache.write)=="function") then return false end
  local src=compactMetadataLua(metadata);if not src then return false end
  local ok,a=pcall(mod.cache.write,mod.cache,metadataCachePath(dex),src)
  return ok and a~=false and a~=nil
end

local function imageFromRaw(spec)
  local bytes,err=GeneratedAssets.read(spec.path)
  if not bytes then return nil,err or ("missing "..tostring(spec.path)) end
  local ok,data=pcall(love.image.newImageData,spec.w,spec.h,"rgba8",bytes)
  if not ok then return nil,data end
  local ok2,img=pcall(love.graphics.newImage,data)
  if not ok2 then return nil,img end
  if img.setFilter then
    if not pcall(img.setFilter,img,"linear","linear",16) then
      pcall(img.setFilter,img,"linear","linear")
    end
  end
  if img.setWrap then
    local function wrapName(v)
      v=tonumber(v) or 0
      if v==1 then return "repeat" end
      if v==2 then return "mirroredrepeat" end
      return "clamp"
    end
    pcall(img.setWrap,img,wrapName(spec.wrapS),wrapName(spec.wrapT))
  end
  return img
end

local function ensureShader()
  if shader then return shader end
  if not (love and love.graphics and love.graphics.newShader) then return nil,"LOVE graphics unavailable" end
  local ok,sh=pcall(love.graphics.newShader,VERTEX,PIXEL)
  if not ok or not sh then return nil,tostring(sh or "shader compile failed") end
  shader=sh
  return shader
end

-- Pokemon cache format v3 stores each dense 44-float vertex group as one
-- newline-delimited string.  Older caches used a gigantic Lua table literal;
-- sufficiently detailed species (Charizard is the first reproduced case) can
-- exceed Lua/LuaJIT's 65,536-constant limit before the chunk even executes.
-- Expand the packed payload only after the tiny metadata chunk has loaded.
local function decodedVertices(group)
  if type(group)~="table" then return nil,"vertex group missing" end
  if type(group.vertices)=="table" then return group.vertices end -- legacy/fail-open
  local packed=group.verticesPacked
  if type(packed)~="string" then return nil,"vertex payload missing" end
  local stride=tonumber(group.vertexStride) or 44
  if stride~=44 then return nil,("unsupported vertex stride %s"):format(tostring(stride)) end
  local vertices={}
  local rowNo=0
  for line in packed:gmatch("[^\r\n]+") do
    rowNo=rowNo+1
    local row={}
    for token in line:gmatch("[^,]+") do
      local value=tonumber(token)
      if value==nil then return nil,("vertex row %d contains non-number %q"):format(rowNo,tostring(token)) end
      row[#row+1]=value
    end
    if #row~=stride then
      return nil,("vertex row %d has %d scalars; expected %d"):format(rowNo,#row,stride)
    end
    vertices[#vertices+1]=row
  end
  if #vertices==0 then return nil,"packed vertex payload empty" end
  -- Drop the source string once expanded; scenes keep only the GPU mesh.
  group.vertices=vertices
  group.verticesPacked=nil
  return vertices
end

-- Build the GPU scene for one species from its generated cache. Returns nil and
-- an error string on any failure; the caller then declines that side, which
-- CurrentSpriteModels turns into a 2D sprite fallback for that Pokemon only.
local function loadScene(dex)
  local hit=scenes[dex]
  if hit then perf.sceneHits=perf.sceneHits+1;return hit end
  if sceneErrors[dex] then return nil,sceneErrors[dex] end
  if not (love and love.graphics and love.image and love.graphics.newMesh) then
    return nil,"LOVE mesh API unavailable"
  end
  local path=extractor and extractor.cachePath(dex) or ("cache/pokemon/%d/model_cache.lua"):format(dex)
  local stamp=sourceRevision(dex)
  local cache,err,fromRuntime
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    local rt=select(1,RuntimeMeshCache.readLua(runtimeBasePath(dex)))
    if runtimeBaseUsable(rt,stamp,dex) then cache=rt;fromRuntime=true;perf.runtimeBaseHits=(perf.runtimeBaseHits or 0)+1 end
  end
  if not cache then cache,err=readLua(path) end
  if not cache then sceneErrors[dex]=tostring(err);return nil,sceneErrors[dex] end
  local sh,serr=ensureShader()
  if not sh then sceneErrors[dex]=tostring(serr);return nil,sceneErrors[dex] end

  local textures,groups={},{}
  local sceneFloorMinY=tonumber(cache.floorMinY) or math.huge
  local runtimeBaseComplete=(RuntimeMeshCache and RuntimeMeshCache.supported and RuntimeMeshCache.supported()) and true or false
  for i,g in ipairs(cache.groups or {}) do
    local img
    if g.texture then
      img=textures[g.texture.path]
      if not img then
        local ierr
        img,ierr=imageFromRaw(g.texture)
        if not img then sceneErrors[dex]=tostring(ierr);return nil,sceneErrors[dex] end
        textures[g.texture.path]=img
      end
    end
    local mesh,verr,vertices
    local binPath=g.runtimeBin or runtimeBaseBinPath(dex,i)
    if fromRuntime and RuntimeMeshCache and type(RuntimeMeshCache.meshFromPath)=="function" then
      mesh,verr=RuntimeMeshCache.meshFromPath(FORMAT,binPath,44,"static")
    end
    if not mesh then
      vertices,verr=decodedVertices(g)
      if not vertices then
        sceneErrors[dex]=("dex %d mesh %d vertex cache: %s"):format(dex,i,tostring(verr))
        return nil,sceneErrors[dex]
      end
      -- Cache the ACTUAL lowest authored vertex, not merely the model origin.
      for _,v in ipairs(vertices) do
        local y=tonumber(v[2])
        if y and y<sceneFloorMinY then sceneFloorMinY=y end
      end
      local ok,built=pcall(love.graphics.newMesh,FORMAT,vertices,"triangles","static")
      if not ok then
        sceneErrors[dex]=("dex %d mesh %d: %s"):format(dex,i,tostring(built))
        return nil,sceneErrors[dex]
      end
      mesh=built
      if runtimeBaseComplete then
        local wok=RuntimeMeshCache.writeRows(binPath,vertices,44)
        if not wok then runtimeBaseComplete=false end
      end
    end
    if img then mesh:setTexture(img) end
    local d=g.diffuse or {1,1,1}
    groups[#groups+1]={
      mesh=mesh,image=img,textured=img~=nil,
      diffuse={tonumber(d[1]) or 1,tonumber(d[2]) or 1,tonumber(d[3]) or 1},
      alpha=tonumber(g.alpha) or 1,
      xlu=g.xlu==true,noz=g.noz==true,
      renderFlags=tonumber(g.renderFlags) or 0,
      shadow=g.shadow==true,effect=g.effect==true,
      textureSlot=tonumber(g.textureSlot) or -1,
    }
  end
  if #groups==0 then sceneErrors[dex]="cache contained no drawable groups";return nil,sceneErrors[dex] end

  -- Build the separately sampled PKX action banks. Reaction banks may contain
  -- multiple overlapping dense pages; each page still uses the same proven
  -- 12-target GPU vertex format and shares the base source material state.
  --
  -- A handful of retail Damage/Faint clips contain large root translations that
  -- are valid in Colosseum's original stage/camera choreography but can cross
  -- the portable camera when transplanted into a different arena. Preserve the
  -- authored body deformation, but clamp only pathological whole-body travel so
  -- a hit can never turn the Pokemon mesh into a camera-filling black/texture
  -- frame. This is presentation-space stabilization, not a different animation.
  local function reactionClass(name)
    name=tostring(name or "")
    if name=="damage" or name:match("^damage/page%d+$") then return "damage" end
    if name=="damageHeavy" or name:match("^damageHeavy/page%d+$") then return "damageHeavy" end
    if name=="faint" or name:match("^faint/page%d+$") then return "faint" end
    return nil
  end
  local function stabilizeReactionRows(rawGroups,name)
    local reaction=reactionClass(name)
    if not reaction then return 0 end
    local b=cache.bounds or {};local mn,mx=b.min or {0,0,0},b.max or {0,16,0}
    local ref={((mn[1] or 0)+(mx[1] or 0))*.5,((mn[2] or 0)+(mx[2] or 0))*.5,((mn[3] or 0)+(mx[3] or 0))*.5}
    local height=math.max(.001,math.abs((mx[2] or 16)-(mn[2] or 0)))
    local centers,counts={},{}
    for slot=0,12 do centers[slot]={0,0,0};counts[slot]=0 end
    for _,ag in ipairs(rawGroups or {}) do
      local rows=decodedVertices(ag)
      if rows then for _,v in ipairs(rows) do
        for slot=0,12 do
          local at=(slot==0) and 1 or (9+(slot-1)*3)
          local c=centers[slot];c[1]=c[1]+(tonumber(v[at]) or 0);c[2]=c[2]+(tonumber(v[at+1]) or 0);c[3]=c[3]+(tonumber(v[at+2]) or 0);counts[slot]=counts[slot]+1
        end
      end end
    end
    local corr={};local changed=0
    -- Colosseum reaction DATs include root travel that is authored together with
    -- the original stage/camera.  CBE transplants the deforming body into other
    -- arenas, so retain the body pose but keep the whole-body centre near its
    -- field anchor.  The old limits were intentionally permissive and dense
    -- `damage/pageN` banks accidentally bypassed them completely, allowing a
    -- perfectly valid hurt frame to move below the deck or far outside camera.
    local hlim=(reaction=="faint") and .72*height or .40*height
    local up=(reaction=="faint") and .52*height or .28*height
    local down=(reaction=="faint") and .82*height or .30*height
    for slot=0,12 do
      local n=counts[slot];local c=centers[slot]
      if n>0 then c={c[1]/n,c[2]/n,c[3]/n} else c={ref[1],ref[2],ref[3]} end
      local dx,dz=c[1]-ref[1],c[3]-ref[3];local r=math.sqrt(dx*dx+dz*dz)
      local tx,tz=dx,dz;if r>hlim and r>0 then local q=hlim/r;tx,tz=dx*q,dz*q end
      local dy=c[2]-ref[2];local ty=math.max(-down,math.min(up,dy))
      corr[slot]={dx-tx,dy-ty,dz-tz}
      if math.abs(corr[slot][1])+math.abs(corr[slot][2])+math.abs(corr[slot][3])>1e-5 then changed=changed+1 end
    end
    if changed==0 then return 0 end
    for _,ag in ipairs(rawGroups or {}) do
      local rows=decodedVertices(ag)
      if rows then for _,v in ipairs(rows) do
        for slot=0,12 do local at=(slot==0) and 1 or (9+(slot-1)*3);local c=corr[slot];v[at]=v[at]-c[1];v[at+1]=v[at+1]-c[2];v[at+2]=v[at+2]-c[3] end
      end end
    end
    perf.reactionClamps=(perf.reactionClamps or 0)+changed
    return changed
  end
  local function buildRuntimeActionGroups(name,count,floorSlots)
    if not (RuntimeMeshCache and type(RuntimeMeshCache.meshFromPath)=="function") then return nil end
    count=math.floor(tonumber(count) or 0);if count<=0 or count~=#groups then return nil end
    local agroups={}
    for i=1,count do
      local baseg=groups[i];if not baseg then return nil end
      local mesh=select(1,RuntimeMeshCache.meshFromPath(FORMAT,runtimeActionBinPath(dex,name,i),44,"static"))
      if not mesh then
        for _,g in ipairs(agroups) do pcall(function() if g.mesh and g.mesh.release then g.mesh:release() end end) end
        return nil
      end
      if baseg.image then mesh:setTexture(baseg.image) end
      agroups[i]={mesh=mesh,image=baseg.image,textured=baseg.textured,diffuse=baseg.diffuse,alpha=baseg.alpha,
        xlu=baseg.xlu,noz=baseg.noz,renderFlags=baseg.renderFlags,shadow=baseg.shadow,effect=baseg.effect,textureSlot=baseg.textureSlot}
    end
    if type(floorSlots)~="table" then
      local fm=select(1,RuntimeMeshCache.readLua(runtimeActionFloorPath(dex,name)))
      if validRuntimeMeta(fm,stamp) then floorSlots=fm.floorMinYSlots end
    end
    agroups._floorMinYSlots=type(floorSlots)=="table" and floorSlots or nil
    return agroups
  end

  local function buildActionGroups(rawGroups,name)
    local floorMeta=RuntimeMeshCache and RuntimeMeshCache.readLua and select(1,RuntimeMeshCache.readLua(runtimeActionFloorPath(dex,name))) or nil
    if validRuntimeMeta(floorMeta,stamp) then
      local direct=buildRuntimeActionGroups(name,tonumber(floorMeta.groupCount) or #groups,floorMeta.floorMinYSlots)
      if direct then return direct end
    end
    if type(rawGroups)~="table" then return nil end
    stabilizeReactionRows(rawGroups,name)
    local agroups={};local valid=true
    local minYSlots={}
    for slot=0,12 do minYSlots[slot+1]=math.huge end
    for i,ag in ipairs(rawGroups or {}) do
      local baseg=groups[i]
      if not baseg then valid=false;break end
      local vertices,verr=decodedVertices(ag)
      if not vertices then
        valid=false
        log("warn","dex %d native %s mesh %d vertex cache failed: %s",dex,tostring(name),i,tostring(verr))
        break
      end
      -- Each packed action row contains the base position followed by up to
      -- twelve sampled source poses. Record their lower bounds while the rows
      -- are already decoded so floor collision never adds work to draw().
      for _,v in ipairs(vertices) do
        for slot=0,12 do
          local at=(slot==0) and 1 or (9+(slot-1)*3)
          local y=tonumber(v[at+1])
          if y and y<minYSlots[slot+1] then minYSlots[slot+1]=y end
        end
      end
      local ok,mesh=pcall(love.graphics.newMesh,FORMAT,vertices,"triangles","static")
      if not ok then
        valid=false
        log("warn","dex %d native %s mesh %d failed: %s",dex,tostring(name),i,tostring(mesh))
        break
      end
      if baseg.image then mesh:setTexture(baseg.image) end
      agroups[i]={
        mesh=mesh,image=baseg.image,textured=baseg.textured,
        diffuse=baseg.diffuse,alpha=baseg.alpha,xlu=baseg.xlu,noz=baseg.noz,
        renderFlags=baseg.renderFlags,shadow=baseg.shadow,effect=baseg.effect,
        textureSlot=baseg.textureSlot,
      }
    end
    if not valid or #agroups~=#groups then return nil end
    for i=1,13 do if minYSlots[i]==math.huge then minYSlots[i]=sceneFloorMinY end end
    agroups._floorMinYSlots=minYSlots
    if RuntimeMeshCache and RuntimeMeshCache.supported and RuntimeMeshCache.supported() and type(stamp)=="string" then
      local all=true
      for i,ag in ipairs(rawGroups or {}) do
        local rows=ag.vertices or decodedVertices(ag)
        local ok=rows and RuntimeMeshCache.writeRows(runtimeActionBinPath(dex,name,i),rows,44)
        if not ok then all=false;break end
      end
      if all then RuntimeMeshCache.writeLua(runtimeActionFloorPath(dex,name),{runtimeMeshVersion=1,stamp=stamp,groupCount=#groups,floorMinYSlots=minYSlots}) end
    end
    return agroups
  end

  -- Keep native action banks in their compact generated-cache form until an
  -- action is actually needed. Older builds expanded every attack/status/hurt/
  -- faint bank and uploaded every GPU mesh before the Pokemon could render.
  -- On a detailed species that means millions of scalar parses + many mesh
  -- uploads on the exact battle/menu transition frame. Base body/idle geometry
  -- is enough to present the Pokemon immediately; action banks are materialized
  -- on demand and common battle banks are opportunistically warmed later.
  local actionSpecs=cache.actions or {}
  local actions={}
  local actionFailures={}

  local scene={
    dex=dex,formatVersion=tonumber(cache.formatVersion) or 1,
    groups=groups,actions=actions,actionSpecs=actionSpecs,actionFailures=actionFailures,
    _buildActionGroups=buildActionGroups,
    bounds=cache.bounds,textures=textures,
    floorMinY=(sceneFloorMinY~=math.huge and sceneFloorMinY) or (cache.bounds and cache.bounds.min and tonumber(cache.bounds.min[2])) or 0,
    jointPositions=cache.jointPositions or {},jointFrames=cache.jointFrames or {},
    clip=tonumber(cache.clip) or 0,
    clipCount=tonumber(cache.clipCount) or 0,
    morphFrames=math.max(0,math.min(12,tonumber(cache.morphFrames) or 0)),
    stem=cache.stem,source=cache.source,
    vertexCount=tonumber(cache.vertexCount) or 0,
    groupCount=tonumber(cache.groupCount) or #groups,
    requestedDecodeMode=tostring(cache.requestedDecodeMode or "auto"),
    decodePath=tostring(cache.decodePath or "?"),
    heightRatio=tonumber(cache.heightRatio) or 0,
    widthRatio=tonumber(cache.widthRatio) or 0,
    envBlends=tonumber(cache.envBlends) or 0,
    envPobjs=tonumber(cache.envPobjs) or 0,
    envBlendsMulti=tonumber(cache.envBlendsMulti) or 0,
    skinFix=cache.skinFix~=false,
    poseDrift=tonumber(cache.poseDrift) or 0,
    hiddenJobjs=tonumber(cache.hiddenJobjs) or 0,
    quatJobjs=tonumber(cache.quatJobjs) or 0,
    jointCount=tonumber(cache.jointCount) or 0,
    jointScaleMin=tonumber(cache.jointScaleMin) or 0,
    jointScaleMedian=tonumber(cache.jointScaleMedian) or 0,
    jointScaleMax=tonumber(cache.jointScaleMax) or 0,
    jointScaleOutliers=tonumber(cache.jointScaleOutliers) or 0,
    renderPassFilter=cache.renderPassFilter~=false,
    nonRenderJobjs=tonumber(cache.nonRenderJobjs) or 0,
    nonRenderDobjs=tonumber(cache.nonRenderDobjs) or 0,
    shadowDobjs=tonumber(cache.shadowDobjs) or 0,
    semanticRootsOnly=cache.semanticRootsOnly==true,
    semanticRootCount=tonumber(cache.semanticRootCount) or 0,
    envelopeCoordEntries=tonumber(cache.envelopeCoordEntries) or 0,
    singleEnvelopeCoord=tonumber(cache.singleEnvelopeCoord) or 0,
    singleEnvelopeNoCoord=tonumber(cache.singleEnvelopeNoCoord) or 0,
    inverseBindMissing=tonumber(cache.inverseBindMissing) or 0,
    placeholderGroupsRemoved=tonumber(cache.placeholderGroupsRemoved) or 0,
    placeholderVertsRemoved=tonumber(cache.placeholderVertsRemoved) or 0,
  }
  scene._buildRuntimeActionGroups=buildRuntimeActionGroups
  scene._runtimeStamp=stamp
  if not fromRuntime and runtimeBaseComplete and type(stamp)=="string" then
    writeRuntimeBase(dex,cache,(sceneFloorMinY~=math.huge and sceneFloorMinY) or (cache.bounds and cache.bounds.min and tonumber(cache.bounds.min[2])) or 0,stamp)
  end
  scenes[dex]=scene
  perf.sceneLoads=perf.sceneLoads+1
  local actionCount=0;for _ in pairs(actionSpecs) do actionCount=actionCount+1 end
  log("info","loaded %s (dex %d): %d groups, %d fallback frames, %d indexed native action slots (lazy GPU)",
    tostring(cache.stem),dex,#groups,scene.morphFrames,actionCount)
  return scene
end

-- Materialize one cached native action into GPU meshes. This is intentionally
-- outside loadScene(): information surfaces and battle entry need only the base
-- body immediately, while exact attack/damage/faint banks can be built when
-- they are first requested. The compact packed strings remain untouched until
-- then, which cuts both transition CPU and resident RAM/VRAM substantially.
local function runtimeActionEntry(scene,name,meta)
  if not (validRuntimeMeta(meta,scene and scene._runtimeStamp) and scene._buildRuntimeActionGroups) then return nil end
  if meta.alias then return {alias=tostring(meta.alias),clip=tonumber(meta.clip),duration=tonumber(meta.duration) or 0} end
  if type(meta.pages)=="table" and #meta.pages>0 then
    local pages={}
    for pi,page in ipairs(meta.pages) do
      local pgroups=scene._buildRuntimeActionGroups(name.."/page"..pi,tonumber(page.groupCount),page.floorMinYSlots)
      if not pgroups then return nil end
      pages[#pages+1]={groups=pgroups,startPhase=tonumber(page.startPhase) or 0,endPhase=tonumber(page.endPhase) or 1,
        morphFrames=tonumber(page.morphFrames) or 0,jointPositions=page.jointPositions or {},jointFrames=page.jointFrames or {},
        floorMinYSlots=pgroups._floorMinYSlots,validSlots=page.validSlots,dense=true}
    end
    return {pages=pages,dense=true,clip=tonumber(meta.clip) or -1,duration=tonumber(meta.duration) or 0,
      frameSpacing=tonumber(meta.frameSpacing) or 1,totalIntervals=tonumber(meta.totalIntervals) or 0}
  end
  local agroups=scene._buildRuntimeActionGroups(name,tonumber(meta.groupCount),meta.floorMinYSlots)
  if not agroups then return nil end
  return {groups=agroups,clip=tonumber(meta.clip) or -1,duration=tonumber(meta.duration) or 0,frameSpacing=tonumber(meta.frameSpacing) or 1,
    morphFrames=tonumber(meta.morphFrames) or 0,jointPositions=meta.jointPositions or {},jointFrames=meta.jointFrames or {},
    floorMinYSlots=agroups._floorMinYSlots,validSlots=meta.validSlots}
end
local function runtimeActionMeta(scene,name,a)
  if not (scene and a and type(scene._runtimeStamp)=="string") then return nil end
  local out={runtimeMeshVersion=1,stamp=scene._runtimeStamp,clip=a.clip,duration=a.duration,frameSpacing=a.frameSpacing,
    totalIntervals=a.totalIntervals,morphFrames=a.morphFrames,jointPositions=a.jointPositions,jointFrames=a.jointFrames,validSlots=a.validSlots}
  if a.alias then out.alias=a.alias
  elseif type(a.pages)=="table" then
    out.pages={}
    for i,p in ipairs(a.pages) do out.pages[i]={startPhase=p.startPhase,endPhase=p.endPhase,morphFrames=p.morphFrames,
      jointPositions=p.jointPositions,jointFrames=p.jointFrames,validSlots=p.validSlots,groupCount=type(p.groups)=="table" and #p.groups or 0} end
  else out.groupCount=type(a.groups)=="table" and #a.groups or 0 end
  return out
end

local function materializeSceneAction(scene,name)
  if not (scene and name) then return nil end
  if scene.actions and scene.actions[name] then return scene.actions[name] end
  scene.actionFailures=scene.actionFailures or {}
  if scene.actionFailures[name] then return nil end
  local a=scene.actionSpecs and scene.actionSpecs[name]
  if type(a)~="table" then
    scene.actionFailures[name]=true
    return nil
  end

  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" then
    local meta=select(1,RuntimeMeshCache.readLua(runtimeActionManifestPath(scene.dex,name)))
    local runtimeEntry=runtimeActionEntry(scene,name,meta)
    if runtimeEntry then
      scene.actions[name]=runtimeEntry
      if scene.actionSpecs then scene.actionSpecs[name]=nil end
      perf.actionBuilds=perf.actionBuilds+1;perf.runtimeActionHits=(perf.runtimeActionHits or 0)+1
      return runtimeEntry
    end
  end

  -- v4 caches keep large native banks in separate files so model_cache.lua can
  -- load quickly on battle/menu entry. Load only the requested bank here. v3
  -- inline specs fall through unchanged for backward compatibility.
  if a.path then
    local payload,perr=readLua(a.path)
    if type(payload)~="table" then
      scene.actionFailures[name]=true
      log("warn","dex %s native action %s cache %s failed: %s",
        tostring(scene.dex or "?"),tostring(name),tostring(a.path),tostring(perr))
      return nil
    end
    payload.clip=payload.clip or a.clip
    payload.duration=payload.duration or a.duration
    a=payload
  end

  perf.actionBuilds=perf.actionBuilds+1
  local entry
  if a.alias then
    entry={alias=tostring(a.alias),clip=tonumber(a.clip),duration=tonumber(a.duration) or 0}
  elseif type(a.pages)=="table" and #a.pages>0 then
    local pages={};local valid=true
    for pi,page in ipairs(a.pages) do
      local pgroups=scene._buildActionGroups and scene._buildActionGroups(page.groups,name.."/page"..pi)
      if not pgroups then valid=false;break end
      pages[#pages+1]={
        groups=pgroups,
        startPhase=math.max(0,math.min(1,tonumber(page.startPhase) or 0)),
        endPhase=math.max(0,math.min(1,tonumber(page.endPhase) or 1)),
        morphFrames=math.max(0,math.min(12,tonumber(page.morphFrames) or 0)),
        jointPositions=page.jointPositions or {},jointFrames=page.jointFrames or {},
        floorMinYSlots=pgroups._floorMinYSlots,
        validSlots=page.validSlots,dense=true,
      }
    end
    if valid and #pages>0 then
      entry={pages=pages,dense=true,clip=tonumber(a.clip) or -1,
        duration=tonumber(a.duration) or 0,frameSpacing=tonumber(a.frameSpacing) or 1,
        totalIntervals=tonumber(a.totalIntervals) or 0}
    end
  else
    local agroups=scene._buildActionGroups and scene._buildActionGroups(a.groups,name)
    if agroups then
      entry={groups=agroups,clip=tonumber(a.clip) or -1,duration=tonumber(a.duration) or 0,
        frameSpacing=tonumber(a.frameSpacing) or 1,morphFrames=math.max(0,math.min(12,tonumber(a.morphFrames) or 0)),
        jointPositions=a.jointPositions or {},jointFrames=a.jointFrames or {},
        floorMinYSlots=agroups._floorMinYSlots,validSlots=a.validSlots}
    end
  end

  if not entry then
    scene.actionFailures[name]=true
    log("warn","dex %s native action %s could not be materialized; procedural/base fallback remains available",
      tostring(scene.dex or "?"),tostring(name))
    return nil
  end

  scene.actions[name]=entry
  if RuntimeMeshCache and type(RuntimeMeshCache.writeLua)=="function" then
    local meta=runtimeActionMeta(scene,name,a)
    if meta and RuntimeMeshCache.writeLua(runtimeActionManifestPath(scene.dex,name),meta) then perf.runtimeActionWrites=(perf.runtimeActionWrites or 0)+1 end
  end
  -- Release the packed source payload once its GPU representation exists. Alias
  -- metadata is tiny but clearing it too keeps one ownership rule for all slots.
  if scene.actionSpecs then scene.actionSpecs[name]=nil end
  return entry
end

local PREWARM_ORDER={"damage","faint","physicalA","specialC","statusA"}
local function prewarmScene(scene)
  if not (scene and scene.actionSpecs) then return false end
  local now=(love and love.timer and love.timer.getTime and love.timer.getTime()) or 0
  if now>0 and scene._nextPrewarmAt and now<scene._nextPrewarmAt then return false end
  local start=tonumber(scene._prewarmIndex) or 1
  for i=start,#PREWARM_ORDER do
    scene._prewarmIndex=i+1
    local key=PREWARM_ORDER[i]
    if scene.actionSpecs[key] and not (scene.actionFailures and scene.actionFailures[key]) then
      local entry=materializeSceneAction(scene,key)
      local guard=0
      while entry and entry.alias and guard<8 do
        entry=materializeSceneAction(scene,tostring(entry.alias))
        guard=guard+1
      end
      if entry then perf.actionPrewarms=perf.actionPrewarms+1 end
      if now>0 then scene._nextPrewarmAt=now+0.10 end
      return entry~=nil
    end
  end
  return false
end

-- ---------------------------------------------------------------- actor ----

local Actor={}
Actor.__index=Actor

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end

-- LuaJIT/Lua 5.1 exposes the quadrant-aware function as math.atan2. Passing a
-- second argument to math.atan is silently ignored there. The old code did
-- exactly that, so the straight-ahead arena gave both battlers yaw 0: the
-- enemy happened to be correct while the player never received its pi turn.
-- Keep a small fallback for hosts that expose only the Lua 5.3 math surface.
local function atan2(y,x)
  y=tonumber(y) or 0;x=tonumber(x) or 0
  if type(math.atan2)=="function" then return math.atan2(y,x) end
  if x>0 then return math.atan(y/x) end
  if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
  if y>0 then return math.pi*.5 end
  if y<0 then return -math.pi*.5 end
  return 0
end

-- Pure and exported for regression tests. Local PKX +Z is aimed at the
-- opponent. This gives enemy=0 and player=pi in the default straight arena,
-- while diagonal recipes retain their authored target line.
function A.facingYaw(towardX,towardZ)
  return atan2(towardX,towardZ)
end

function Actor.new(dex,variant,scene,opts)
  opts=type(opts)=="table" and opts or {}
  return setmetatable({
    dex=dex,variant=variant,scene=scene,
    side=opts.side,
    informationSurface=opts.context and opts.context.services and opts.context.services.informationSurface==true,
    clock=0,state="spawn",stateAge=0,
    action=nil,actionAge=0,spawnScale=0,
    hitAge=nil,hitStrength=1,faintAge=nil,faintKind=nil,pendingFaint=nil,pendingHits=nil,
    pendingAttack=nil,pendingRecall=nil,
    recallAge=nil,recallReason=nil,recallScale=nil,
    height=(scene.bounds and scene.bounds.max and scene.bounds.min
      and (scene.bounds.max[2]-scene.bounds.min[2])) or 16,
  },Actor)
end

local SPECIAL_TYPES={FIRE=true,WATER=true,GRASS=true,ELECTRIC=true,ICE=true,PSYCHIC=true,DRAGON=true,DARK=true}
local function moveSlot(moveDef)
  local category=type(moveDef)=="table" and (moveDef.category or moveDef.damageClass or moveDef.class) or nil
  category=tostring(category or ""):lower()
  if category:find("status",1,true) then return "statusA" end
  if category:find("special",1,true) then return "specialC" end
  if category:find("physical",1,true) then return "physicalA" end
  -- Gen1Recomp's Gen-I move table intentionally mirrors the cartridge and has
  -- no modern damageClass field: id/index/name/type/power/effect are the source
  -- fields. Power 0 is the authoritative status discriminator; for damaging
  -- moves the pre-split elemental types select Colosseum's special-action slot.
  if type(moveDef)=="table" then
    local power=tonumber(moveDef.power)
    if power~=nil and power<=0 then return "statusA" end
    local typ=tostring(moveDef.type or ""):upper():gsub("[^A-Z]","")
    if SPECIAL_TYPES[typ] then return "specialC" end
  end
  return "physicalA"
end

local NATIVE_FALLBACKS={
  idle={"idle","idleB","idleC","idleD","idleE"},
  statusA={"statusA","statusB","specialC"}, statusB={"statusB","statusA","specialC"},
  specialC={"specialC","statusA","statusB"},
  physicalA={"physicalA","physicalB","physicalC","physicalD","physicalE"},
  damage={"damage"},damageHeavy={"damageHeavy"},
  faint={"faint"},takeFlight={"takeFlight"},
}

local function resolveSceneAction(scene,name,allowBuild)
  if not (scene and scene.actions) then return nil,nil,nil end
  if allowBuild==nil then allowBuild=true end
  local wanted=NATIVE_FALLBACKS[name] or {name}
  for _,key in ipairs(wanted) do
    local entry=scene.actions[key]
    if not entry and allowBuild then entry=materializeSceneAction(scene,key) end
    if entry then
      local duration=tonumber(entry.duration) or 0
      local resolved=entry;local guard=0
      while resolved and resolved.alias and guard<8 do
        local alias=tostring(resolved.alias)
        resolved=scene.actions[alias]
        if not resolved and allowBuild then resolved=materializeSceneAction(scene,alias) end
        guard=guard+1
      end
      if resolved and (resolved.groups or (type(resolved.pages)=="table" and #resolved.pages>0)) then
        if duration<=0 then duration=tonumber(resolved.duration) or 0 end
        return resolved,key,duration
      end
    end
  end
  return nil,nil,nil
end

function Actor:selectNativeSlot(name)
  self.requestedNativeSlot=name
  local slot=self.sourceMetadata and self.sourceMetadata.slots and self.sourceMetadata.slots[name]
  self.nativeSlot=slot
  self.nativeClip=slot and slot.animationIndex or nil

  -- Idle is already represented by the base source-authored body bank loaded
  -- with the species. Do not force a second full idle GPU bank onto the battle
  -- entry or Stats-menu frame. If the idle action has been warmed, use it;
  -- otherwise animate the base bank at the authoritative source duration.
  local allowBuild=(name~="idle") or not self.informationSurface
  local action,resolvedName,duration=resolveSceneAction(self.scene,name,allowBuild)
  self.nativeAction=action
  self.nativeActionName=resolvedName
  local slotDuration=slot and tonumber(slot.duration) or 0
  if (not duration or duration<=0.02) and slotDuration>0.02 then duration=slotDuration end
  self.nativeDuration=(duration and duration>0.02) and duration or nil
  self.nativeSlotSampled=action~=nil
  self.clipClock=0
  return self.nativeSlotSampled,slot
end

-- Colosseum's WazaSequence does not store absolute start frames for every
-- entry. It synchronizes against timing points from the Pokemon's currently
-- selected native PKX motion. PKXMetadata stores those four values in seconds;
-- expose the exact 60 Hz source ticks expected by the retail Waza scheduler.
function Actor:wazaTimingPoints()
  local slot=self.nativeSlot
  local src=slot and slot.timing
  local out={}
  for i=1,4 do
    local sec=type(src)=="table" and tonumber(src[i]) or nil
    if sec then out[i]=math.floor(math.max(0,sec)*60+.5) end
  end
  -- Point zero is the sequence origin even for metadata rows whose first timed
  -- event is later in the clip. Preserve the authored PKX value when present;
  -- if an unusual slot omitted it, the scheduler's explicit fallback handles it.
  return out
end

local ATTACK_DURATION=0.85
local HIT_DURATION=0.46
local FAINT_DURATION=0.95
local RECALL_DURATION=0.48
local FAINT_REMOVAL_TAIL=0.28

function Actor:stateDuration(kind)
  if self.nativeAction and self.nativeDuration and self.nativeDuration>0 then return self.nativeDuration end
  if kind=="attack" then return ATTACK_DURATION end
  if kind=="hit" then return HIT_DURATION end
  if kind=="faint" then return FAINT_DURATION end
  return RECALL_DURATION
end

function Actor:terminalDuration(kind)
  local base=self:stateDuration(kind)
  if kind=="faint" then return base+FAINT_REMOVAL_TAIL end
  return base
end

function Actor:update(dt)
  local step=math.max(0,tonumber(dt) or 0)
  self.clock=self.clock+step
  self.clipClock=(self.clipClock or 0)+step
  self.stateAge=(self.stateAge or 0)+step
  if self.action then
    self.actionAge=self.actionAge+step
    if self.actionAge>self:stateDuration("attack") then
      self.action=nil;self.actionAge=0
      if not self.hitAge and not self.faintAge and not self.recallAge then
        self:selectNativeSlot("idle");self:transition("idle")
      end
    end
  end
  if self.hitAge then
    self.hitAge=self.hitAge+step
    if self.hitAge>self:stateDuration("hit") then
      self.hitAge=nil
      -- A lethal hit is still a hit. BattleState can mark the battler fainted
      -- before its later faint presentation event arrives; older CBE builds
      -- therefore destroyed the actor at 0 HP before the Damage bank could
      -- finish. Queue faint behind the complete hurt clip instead of replacing
      -- it, so every impact remains visible and then flows into the authored KO.
      if self.pendingHits and #self.pendingHits>0 then
        local nextHit=table.remove(self.pendingHits,1)
        self:hit(nextHit)
      elseif self.pendingFaint then
        local disposition=self.pendingFaint
        self.pendingFaint=nil
        self:faint(disposition)
      elseif self.pendingRecall then
        local reason=self.pendingRecall
        self.pendingRecall=nil
        self:recall(reason)
      elseif self.pendingAttack then
        local q=self.pendingAttack
        self.pendingAttack=nil
        self:attack(q.moveId,q.moveDef)
      elseif not self.action and not self.faintAge and not self.recallAge then
        self:selectNativeSlot("idle");self:transition("idle")
      end
    end
  end
  if self.faintAge then self.faintAge=self.faintAge+step end
  if self.recallAge then self.recallAge=self.recallAge+step end

  -- Warm common native battle banks only after the actor is fully visible and
  -- idle. This keeps extraction/cache parsing/GPU uploads off black transition
  -- frames and completely out of read-only Stats showrooms. One bank at most
  -- every 100 ms avoids a single giant startup spike while usually having the
  -- exact attack/damage/faint bank resident before the player uses it.
  if not self.informationSurface and self.state=="idle"
      and (tonumber(self.spawnScale) or 0)>=0.999 and (tonumber(self.stateAge) or 0)>=0.18 then
    prewarmScene(self.scene)
  end
end

function Actor:transition(state)
  state=tostring(state or "idle")
  if self.state~=state then self.state=state;self.stateAge=0 end
end

function Actor:spawn(progress)
  local p=clamp(tonumber(progress) or 1,0,1)
  self.spawnScale=p
  if p<1 then
    if self.state~="faint" and self.state~="removal" then self:transition("spawn") end
  elseif self.state=="spawn" then
    self:selectNativeSlot("idle");self:transition("idle")
  end
end

function Actor:idle()
  -- Native Damage owns the actor until its authored duration is complete.
  -- Text/turn state can request idle on the same frame as impact; accepting that
  -- request used to truncate the source hurt clip. Ignore it and let update()
  -- perform the single deterministic Damage -> next-state handoff.
  if self.hitAge then return false end
  if self.state~="faint" and self.state~="recall" and self.state~="removal" then
    self.action=nil;self.actionAge=0;self:selectNativeSlot("idle");self:transition("idle")
    return true
  end
  return false
end

local FRAME_RATE=11

-- Continuous source-pose playback. 1.5.45 only interpolated Damage/Faint;
-- attacks still rounded to one of twelve cached poses, which made otherwise
-- correct Colosseum clips look like stop-motion. Every verified native bank now
-- interpolates on source timing. When all neighbouring samples decoded we use a
-- low-tension cubic Hermite/Catmull path for C1-continuous motion; if extraction
-- left a hole, playback falls back to linear interpolation between the nearest
-- validated source samples instead of ever popping through the frame-0 body.
local function addWeight(w,idx,value,n)
  if math.abs(value)<1e-9 then return end
  if idx<0 then idx=0 elseif idx>n then idx=n end
  w[idx+1]=(w[idx+1] or 0)+value
end

local function slotValid(mask,idx)
  if idx==0 then return true end
  if type(mask)~="table" then return true end
  local v=mask[idx]
  return v==true or v==1
end

local function nearestValid(mask,idx,dir,n)
  local i=idx
  while i>=0 and i<=n do
    if slotValid(mask,i) then return i end
    i=i+dir
  end
  return nil
end

local function linearValidWeights(w,t,n,mask)
  local lo=math.floor(t);local hi=math.ceil(t)
  lo=nearestValid(mask,lo,-1,n) or nearestValid(mask,lo,1,n) or 0
  hi=nearestValid(mask,hi,1,n) or nearestValid(mask,hi,-1,n) or lo
  if hi<lo then lo,hi=hi,lo end
  if hi==lo then w[lo+1]=1;return w end
  local f=clamp((t-lo)/(hi-lo),0,1)
  w[lo+1]=1-f;w[hi+1]=(w[hi+1] or 0)+f
  return w
end

local function cubicWeights(w,t,n,mask,looping)
  local i=math.floor(t);local f=t-i
  if i>=n then w[n+1]=1;return w end
  local i1=i;local i2=i+1
  -- A cubic segment is only safe when the two segment endpoints themselves are
  -- real samples. Missing samples are handled by nearest-valid linear playback.
  if not slotValid(mask,i1) or not slotValid(mask,i2) then
    return linearValidWeights(w,t,n,mask)
  end
  local function wrap(v)
    if looping then
      local total=n+1
      return ((v%total)+total)%total
    end
    return math.max(0,math.min(n,v))
  end
  local i0=wrap(i-1);local i3=wrap(i+2)
  if not slotValid(mask,i0) or not slotValid(mask,i3) then
    return linearValidWeights(w,t,n,mask)
  end
  local f2,f3=f*f,f*f*f
  -- Hermite form with restrained source tangents. Standard Catmull-Rom uses
  -- gain .5; .38 keeps continuous velocity without overshooting highly
  -- articulated Pokemon limbs between sparse source samples.
  local g=.38
  local h00=2*f3-3*f2+1
  local h10=f3-2*f2+f
  local h01=-2*f3+3*f2
  local h11=f3-f2
  addWeight(w,i0,-h10*g,n)
  addWeight(w,i1,h00-h11*g,n)
  addWeight(w,i2,h01+h10*g,n)
  addWeight(w,i3,h11*g,n)
  return w
end

-- `validSlots` is indexed 1..12 for the authored targets; base frame 0 is
-- always validated. `smoothNative` is true for source-backed action banks.
function A.frameWeights(clock,morphFrames,action,duration,looping,smoothNative,validSlots)
  local w={0,0,0,0,0,0,0,0,0,0,0,0,0}
  local n=math.max(0,math.min(12,tonumber(morphFrames) or 0))
  if n<1 then w[1]=1;return w end
  local dur=tonumber(duration)
  if dur and dur>0.02 then
    local c=math.max(0,tonumber(clock) or 0)
    local t
    if looping then
      local phase=(c%dur)/dur
      t=phase*(n+1)
      -- Keep the cyclic segment inside the 0..n sample ring.
      if t>n then
        local f=t-n
        if smoothNative and slotValid(validSlots,n) and slotValid(validSlots,0) then
          w[n+1]=1-f;w[1]=f;return w
        end
        w[n+1]=1-f;w[1]=f;return w
      end
    else
      t=clamp(c/dur,0,1)*n
    end
    if smoothNative and n>=3 then return cubicWeights(w,t,n,validSlots,looping) end
    return linearValidWeights(w,t,n,validSlots)
  end
  local total=n+1
  local speed=(action=="attack") and (FRAME_RATE*2.1) or FRAME_RATE
  local t=((tonumber(clock) or 0)*speed)%total
  if t<0 then t=t+total end
  return linearValidWeights(w,t,n,validSlots)
end

function Actor:playbackBank()
  local bank=self.nativeAction
  if not bank then return self.scene,self.clipClock or self.clock,self.nativeDuration,false end
  if type(bank.pages)=="table" and #bank.pages>0 then
    local duration=math.max(.001,tonumber(self.nativeDuration) or tonumber(bank.duration) or 1)
    local phase=clamp((tonumber(self.clipClock) or 0)/duration,0,1)
    local page=bank.pages[#bank.pages]
    for _,candidate in ipairs(bank.pages) do
      if phase<=((tonumber(candidate.endPhase) or 1)+1e-7) then page=candidate;break end
    end
    local a=tonumber(page.startPhase) or 0
    local b=math.max(a+1e-6,tonumber(page.endPhase) or 1)
    local localPhase=clamp((phase-a)/(b-a),0,1)
    return page,localPhase,1,true
  end
  return bank,self.clipClock or self.clock,self.nativeDuration,false
end

function Actor:frameWeights()
  local bank,clock,duration,dense=self:playbackBank()
  local n=bank and bank.morphFrames or self.scene.morphFrames
  local looping=(self.state=="idle" or self.state=="spawn") and not dense
  -- Native playback uses non-negative interpolation between real source poses.
  -- Dense reaction pages make those neighbours tightly spaced; sparse banks are
  -- still kept linear rather than inventing cubic vertex-space overshoot that
  -- does not exist in Colosseum's skeletal evaluator.
  return A.frameWeights(clock,n,self.action,duration,looping,
    false,bank and bank.validSlots)
end

local function weightedFloorMinY(actor)
  local bank=actor and actor:playbackBank()
  local mins=bank and bank.floorMinYSlots
  if type(mins)=="table" then
    local w=actor:frameWeights();local y,total=0,0
    for i=1,13 do
      local weight=tonumber(w and w[i]) or 0
      local v=tonumber(mins[i])
      if weight~=0 and v then y=y+v*weight;total=total+weight end
    end
    if total>1e-7 then return y/total end
  end
  return tonumber(actor and actor.scene and actor.scene.floorMinY)
    or tonumber(actor and actor.scene and actor.scene.bounds and actor.scene.bounds.min and actor.scene.bounds.min[2]) or 0
end

-- Return a conservative local-space lower Y after CBE's fallback pitch/roll.
-- Native HSD actions normally use no extra whole-actor rotation, but fallback
-- recoil/faint motion does.  Clamping only the unrotated minY let a corner of a
-- rotated model pass through the arena even though its origin remained above 0.
local function rotatedFloorMinY(actor,authoredMinY,pitch,roll)
  if math.abs(pitch or 0)<1e-7 and math.abs(roll or 0)<1e-7 then return authoredMinY end
  local b=actor and actor.scene and actor.scene.bounds or nil
  local mn=b and b.min or {-1,authoredMinY,-1}
  local mx=b and b.max or {1,(authoredMinY or 0)+(actor and actor.height or 1),1}
  local minY=math.huge
  local cp,sp=math.cos(pitch or 0),math.sin(pitch or 0)
  local cr,sr=math.cos(roll or 0),math.sin(roll or 0)
  for _,xx in ipairs({tonumber(mn[1]) or -1,tonumber(mx[1]) or 1}) do
    for _,yy in ipairs({tonumber(authoredMinY) or 0,tonumber(mx[2]) or 1}) do
      for _,zz in ipairs({tonumber(mn[3]) or -1,tonumber(mx[3]) or 1}) do
        -- model = Ry * Rz * Rx * S; yaw leaves Y unchanged.
        local y1=yy*cp-zz*sp
        local x1=xx
        local y2=x1*sr+y1*cr
        if y2<minY then minY=y2 end
      end
    end
  end
  return minY~=math.huge and minY or authoredMinY
end

function Actor:matrix(x,groundY,z,towardX,towardZ)
  local s=self.worldScale or 1
  -- Use the portable quadrant-aware helper above; LuaJIT's math.atan ignores a
  -- second argument and was the source of the player-side orientation bug.
  local yaw=A.facingYaw(towardX or 0,towardZ or 1)
  local lift,pitch,roll=0,0,0

  -- Spawn scale comes from BattleState.growInScale. A newly acquired actor
  -- outside a send-out boundary defaults to full size. Keep that authoritative
  -- scale, then add only presentation-space lift/flash around it.
  local spawn=clamp(self.spawnScale==nil and 1 or self.spawnScale,0,1)
  s=s*spawn
  if spawn<1 and not self.recallAge and not self.faintAge then
    lift=lift+(1-spawn)*0.9
  end

  if self.action=="attack" and not self.nativeAction then
    local u=clamp(self.actionAge/self:stateDuration("attack"),0,1)
    local push=math.sin(u*math.pi)*0.9
    x=x+math.sin(yaw)*push;z=z+math.cos(yaw)*push
  end
  if self.hitAge and not self.nativeAction then
    local u=clamp(self.hitAge/self:stateDuration("hit"),0,1)
    local strength=clamp(tonumber(self.hitStrength) or 1,0.65,1.45)
    local kick=math.sin(u*math.pi)*(1-u)*0.72*strength
    local shake=math.sin(u*math.pi*5)*(1-u)*0.12*strength
    x=x-math.sin(yaw)*kick+math.cos(yaw)*shake
    z=z-math.cos(yaw)*kick-math.sin(yaw)*shake
    roll=roll+math.sin(u*math.pi)*0.06
  end
  if self.faintAge then
    local u=clamp(self.faintAge/self:stateDuration("faint"),0,1)
    -- If the exact native faint clip is present, keep the world transform
    -- restrained and let the authored frames speak. Otherwise use a compact
    -- whole-actor collapse as the portable fallback.
    if self.nativeSlotSampled then
      -- The authored Colosseum faint bank owns root/body motion completely.
      -- Do not add a second CBE-authored vertical drift on top of it.
    else
      roll=roll+u*(math.pi*0.46)
      lift=lift-u*0.12*self.height*(self.worldScale or 1)
    end
  end
  if self.recallAge then
    local timerU=clamp(self.recallAge/RECALL_DURATION,0,1)
    local keep=self.recallScale~=nil and clamp(self.recallScale,0,1) or (1-timerU)
    local u=1-keep
    -- Return is distinct from faint: contract toward the field anchor and rise
    -- slightly, giving the later ROM-derived ball/energy FX a stable endpoint.
    -- When Gen1Recomp exposes shrinkOutScale, CurrentSpriteModels feeds that
    -- exact 5/7 -> 3/7 -> 0 contract here; other hosts use the timer fallback.
    s=s*keep
    lift=lift+u*1.25
  end

  -- The arena floor is a SOLID presentation plane. Preserve every authored
  -- vertex/pose, but translate the complete actor upward if its currently
  -- sampled source geometry would penetrate Y=groundY. This handles flying,
  -- serpentine, damage and attack poses uniformly across every species.
  local authoredMinY=weightedFloorMinY(self)
  local collisionMinY=rotatedFloorMinY(self,authoredMinY,pitch,roll)
  self.forceBasePlayback=false
  -- Last-resort reaction guard.  A live battler is more important than a bad
  -- decoded pose: if a source reaction would require lifting the complete model
  -- by an implausible fraction of its own height, hold the resident base body for
  -- that frame instead of launching it above the camera or below the deck.  The
  -- corrected dense-page stabilizer should make this rare; it is an invariant
  -- backstop for older/generated caches and unusual species.
  if (self.hitAge or self.faintAge) then
    local baseMin=tonumber(self.scene and self.scene.floorMinY) or 0
    local h=math.max(.001,tonumber(self.height) or 1)
    if collisionMinY < baseMin-h*.58 then
      self.forceBasePlayback=true
      authoredMinY=baseMin
      collisionMinY=rotatedFloorMinY(self,baseMin,pitch,roll)
      perf.reactionFallbacks=(perf.reactionFallbacks or 0)+1
    end
  end
  -- Include every previously authored presentation lift in the collision
  -- equation. The old clamp solved only `minY * scale`; a fallback faint could
  -- then add a negative whole-body lift afterwards and sink through the deck
  -- despite reporting a successful floor clamp. Final invariant:
  --   groundY + lift + collisionMinY*scale >= groundY.
  local floorLift=math.max(0,-(collisionMinY*s+lift))
  if floorLift>1e-5 then
    lift=lift+floorLift+.002
    perf.floorClamps=(perf.floorClamps or 0)+1
  end
  self.floorLift=floorLift
  self.authoredMinY=authoredMinY
  local m=Mat4.translate(x,(groundY or 0)+lift,z)
  m=Mat4.mul(m,Mat4.rotateY(yaw))
  if roll~=0 then m=Mat4.mul(m,Mat4.rotateZ(roll)) end
  if pitch~=0 then m=Mat4.mul(m,Mat4.rotateX(pitch)) end
  m=Mat4.mul(m,Mat4.scale(s,s,s))
  self.worldMatrix=m
  return m
end

function Actor:bodyMap()
  return self.sourceMetadata and self.sourceMetadata.bodyMap or nil
end

local function matrixPoint(m,p)
  if not (type(m)=="table" and type(p)=="table") then return nil end
  local x,y,z=tonumber(p[1]) or 0,tonumber(p[2]) or 0,tonumber(p[3]) or 0
  return {
    (m[1] or 1)*x+(m[2] or 0)*y+(m[3] or 0)*z+(m[4] or 0),
    (m[5] or 0)*x+(m[6] or 1)*y+(m[7] or 0)*z+(m[8] or 0),
    (m[9] or 0)*x+(m[10] or 0)*y+(m[11] or 1)*z+(m[12] or 0),
  }
end

-- Return the current authored HSD joint origin in the actor's normalized local
-- model space. The cache carries the same twelve source frames as the mesh, so
-- attachments remain on the mouth/chest/hands while an authored action plays.
function Actor:jointPosition(bone)
  bone=tonumber(bone)
  if not bone or bone<0 then return nil,"invalid body-map bone" end
  local bank=self:playbackBank()
  local base=bank and bank.jointPositions
  local frames=bank and bank.jointFrames
  local j=base and base[bone+1]
  if not j then return nil,("sampled joint %d unavailable"):format(bone) end
  local w=self:frameWeights()
  local x,y,z=(tonumber(j[1]) or 0)*(w[1] or 0),(tonumber(j[2]) or 0)*(w[1] or 0),(tonumber(j[3]) or 0)*(w[1] or 0)
  local total=w[1] or 0
  for slot=1,12 do
    local weight=w[slot+1] or 0
    if weight~=0 then
      local fj=frames and frames[slot] and frames[slot][bone+1]
      if fj then
        x=x+(tonumber(fj[1]) or 0)*weight
        y=y+(tonumber(fj[2]) or 0)*weight
        z=z+(tonumber(fj[3]) or 0)*weight
        total=total+weight
      else
        x=x+(tonumber(j[1]) or 0)*weight
        y=y+(tonumber(j[2]) or 0)*weight
        z=z+(tonumber(j[3]) or 0)*weight
        total=total+weight
      end
    end
  end
  if total<=1e-9 then return {j[1] or 0,j[2] or 0,j[3] or 0} end
  return {x/total,y/total,z/total}
end

function Actor:attachmentIndex(bone)
  local localPos,err=self:jointPosition(bone)
  if not localPos then return nil,err end
  if not self.worldMatrix then return nil,"actor world matrix unavailable" end
  local world=matrixPoint(self.worldMatrix,localPos)
  if not world then return nil,"joint world transform failed" end
  return {boneIndex=tonumber(bone),localPosition=localPos,position=world,source="pkx-body-map-hsd-joints"}
end

function Actor:attachment(name)
  local map=self:bodyMap();local bone=map and map[name]
  if bone==nil or bone<0 then return nil,"PKX body-map slot unavailable" end
  local out,err=self:attachmentIndex(bone)
  if out then out.name=name end
  return out,err
end

function Actor:build() return true end

-- Morph-weight uniform names. Building these with ("w"..i) meant thirteen
-- string concatenations (and thirteen interning lookups) per actor per frame,
-- for names that never change.
local W_UNIFORM={}
for i=0,12 do W_UNIFORM[i]="w"..i end
-- Reused scratch for the two per-group vector uniforms. love:send copies the
-- values immediately, so a single table is safe and removes two allocations
-- per material group per actor per frame.
local MATERIAL_RGBA={1,1,1,1}
local TINT_WHITE={1,1,1,1}

-- Was a closure defined inside Actor:draw, i.e. allocated every frame.
local function setBaseWeights()
  shader:send(W_UNIFORM[0],1)
  for i=1,12 do shader:send(W_UNIFORM[i],0) end
end

function Actor:draw(matrix)
  local sc=self.scene
  if not (sc and shader) then return false end
  local w=self:frameWeights()
  love.graphics.setShader(shader)
  shader:send("model","row",matrix)
  for i=0,12 do shader:send(W_UNIFORM[i],w[i+1]) end
  local hitU=self.hitAge and clamp(self.hitAge/self:stateDuration("hit"),0,1) or 1
  local spawn=clamp(self.spawnScale==nil and 1 or self.spawnScale,0,1)
  local spawnFlash=(spawn<1 and not self.recallAge and not self.faintAge) and (1-spawn)*0.68 or 0
  local hitFlash=self.hitAge and (1-hitU)*0.72*clamp(tonumber(self.hitStrength) or 1,0.65,1.45) or 0
  shader:send("hitFlash",hitFlash)
  shader:send("spawnFlash",spawnFlash)
  shader:send("shinyShift",self.shinyShift or 0)

  local opacity=self.opacity or 1
  if spawn<1 and not self.recallAge and not self.faintAge then
    opacity=opacity*(0.34+spawn*0.66)
  end
  if self.recallAge then
    local u=self.recallScale~=nil and (1-clamp(self.recallScale,0,1))
      or clamp(self.recallAge/RECALL_DURATION,0,1)
    opacity=opacity*(1-u)
  elseif self.faintAge then
    local clip=self:stateDuration("faint")
    if self.nativeSlotSampled then
      -- Preserve the complete authored faint clip. 1.5.29 began fading the
      -- model at 62% of the native animation, which visually amputated the
      -- death performance before Colosseum's source pose had finished. Only
      -- after the final authored frame do we run CBE's short removal tail.
      local tail=clamp((self.faintAge-clip)/FAINT_REMOVAL_TAIL,0,1)
      opacity=opacity*(1-tail)
    else
      local u=clamp(self.faintAge/clip,0,1)
      if u>0.72 then opacity=opacity*(1-(u-0.72)/0.28) end
    end
  end
  shader:send("opacity",clamp(opacity,0,1))
  -- Spawn uses a brief white materialization flash through spawnFlash above.
  -- This is intentionally a generic lifecycle cue, not mislabeled as a
  -- Colosseum move/GPT1 effect.
  shader:send("tintColor",TINT_WHITE)
  love.graphics.setColor(1,1,1,1)
  -- F5 isolates one group at a time so a stray shape can be identified by
  -- sight instead of guessed at from vertex counts alone.
  local only=A.isolateGroup
  local playback=self:playbackBank()
  local drawGroups=(not self.forceBasePlayback and playback and playback.groups) or sc.groups
  if self.forceBasePlayback then setBaseWeights() end
  local drawFault=false
  for i,grp in ipairs(drawGroups) do
    if not only or only==i then
      -- Preserve the source HSD material state per render group. 1.5.24 threw
      -- this away after extraction, so every untextured material rendered as
      -- opaque white and every alpha-controlled helper surface became solid.
      local d=grp.diffuse
      MATERIAL_RGBA[1]=(d and d[1]) or 1;MATERIAL_RGBA[2]=(d and d[2]) or 1
      MATERIAL_RGBA[3]=(d and d[3]) or 1;MATERIAL_RGBA[4]=grp.alpha or 1
      shader:send("materialColor",MATERIAL_RGBA)
      shader:send("useTexture",grp.textured and 1 or 0)
      if love.graphics.setDepthMode then
        love.graphics.setDepthMode("lequal",not (grp.noz or grp.xlu))
      end
      local okDraw=grp.mesh and pcall(love.graphics.draw,grp.mesh)
      if not okDraw then drawFault=true;break end
    end
  end
  -- A source action GPU bank is optional presentation data. If one group is
  -- malformed on a particular backend, draw the always-resident base body in
  -- the SAME frame. Never convert a damage-animation fault into invisibility.
  if drawFault and drawGroups~=sc.groups then
    setBaseWeights()
    for i,grp in ipairs(sc.groups) do
      if not only or only==i then
        local d=grp.diffuse
        MATERIAL_RGBA[1]=(d and d[1]) or 1;MATERIAL_RGBA[2]=(d and d[2]) or 1
        MATERIAL_RGBA[3]=(d and d[3]) or 1;MATERIAL_RGBA[4]=grp.alpha or 1
        shader:send("materialColor",MATERIAL_RGBA)
        shader:send("useTexture",grp.textured and 1 or 0)
        if love.graphics.setDepthMode then love.graphics.setDepthMode("lequal",not (grp.noz or grp.xlu)) end
        if grp.mesh then pcall(love.graphics.draw,grp.mesh) end
      end
    end
    perf.actionDrawFallbacks=(perf.actionDrawFallbacks or 0)+1
  end
  if love.graphics.setDepthMode then love.graphics.setDepthMode("lequal",true) end
  love.graphics.setShader()
  return true
end

function Actor:attack(moveId,moveDef)
  if self.state=="faint" or self.state=="recall" or self.state=="removal" then return false end
  -- A later turn event is allowed to arrive while the target is still inside
  -- its source Damage clip. Queue it; never use an attack event as permission to
  -- cut the reaction short. This is the Colosseum ordering contract:
  -- Damage -> (Faint | Recall | Attack | Idle).
  if self.hitAge then
    self.pendingAttack={moveId=moveId,moveDef=moveDef}
    return true
  end
  self.action="attack";self.actionAge=0;self:transition("attack")
  self.lastMove=moveId;self.lastMoveDef=moveDef
  self:selectNativeSlot(moveSlot(moveDef))
  return true
end
function Actor:hit(payload)
  -- Damage is a reaction, never a visibility state. Keep the actor alive and
  -- let CurrentSpriteModels suppress the engine's stock blink for 3D providers.
  -- Once the authored faint/recall tail has started, a late duplicate damage
  -- event must not pull the actor back out of that terminal presentation.
  if self.state=="faint" or self.state=="recall" or self.state=="removal" then return false end
  local damage=type(payload)=="table" and tonumber(payload.damage) or nil
  local target=type(payload)=="table" and payload.target or nil
  local mon=target and target.mon
  local hp=tonumber(target and (target.hp or target.currentHP or target.currentHp))
    or tonumber(mon and (mon.hp or mon.currentHP or mon.currentHp))
  if hp and hp<=0 then self.pendingFaint=self.pendingFaint or "collapse" end
  -- Some hosts expose the same resolved hit through more than one presentation
  -- wrapper. If HP-after is available it is an authoritative de-duplication key:
  -- replaying the same HP result must not restart Damage at frame zero. Genuine
  -- multi-hit attacks change HP on every strike and therefore remain distinct.
  if hp~=nil then
    local sig=tostring(hp).."|"..tostring(damage or "?")
    local now=tonumber(self.clock) or 0
    self._recentHitSignatures=self._recentHitSignatures or {}
    local seenAt=tonumber(self._recentHitSignatures[sig])
    if seenAt and now-seenAt<0.20 then return true end
    self._recentHitSignatures[sig]=now
  end

  -- Never snap an in-progress native reaction back to its first source frame.
  -- Queue a genuine next strike and play it after the current Damage clip. This
  -- gives multi-hit moves one complete authored reaction per impact and keeps a
  -- lethal final strike ordered ahead of Faint.
  if self.hitAge then
    self.pendingHits=self.pendingHits or {}
    if #self.pendingHits<5 then self.pendingHits[#self.pendingHits+1]=payload end
    return true
  end

  local maxHp=tonumber(target and (target.maxHP or target.maxHp))
    or tonumber(mon and mon.stats and mon.stats.hp)
    or tonumber(mon and mon.maxHP)
  local ratio=(damage and maxHp and maxHp>0) and damage/maxHp or 0.12
  local strength=0.82+clamp(ratio,0,0.65)*0.9
  if type(payload)=="table" and payload.crit then strength=strength+0.18 end
  if type(payload)=="table" and tonumber(payload.typeMult) and tonumber(payload.typeMult)>10 then
    strength=strength+0.12
  end
  self.hitStrength=clamp(strength,0.65,1.45)
  -- Damage is source-authoritative. Revision-27 extraction keeps the exact PKX
  -- Damage slot's root motion and authored body deformation; only impossible
  -- topology/collapse/explosion samples are rejected. Starting a reaction owns
  -- the model until that source duration completes.
  self.action=nil;self.actionAge=0
  self.hitAge=0
  self:transition("hit")
  local sampled=self:selectNativeSlot("damage")
  if not sampled then
    -- No validated source damage bank: keep the resident body and use the
    -- compact procedural recoil fallback. This is a per-species fail-open,
    -- never a visibility change.
    self.nativeSlot=nil;self.nativeClip=nil;self.nativeAction=nil
    self.nativeActionName=nil;self.nativeDuration=nil;self.nativeSlotSampled=false
    self.clipClock=0
  end
end
function Actor:faint(disposition)
  if self.state=="faint" then return true end
  -- Do not let a lethal damage result skip the actual take-damage animation.
  -- Gen1/Gen2 can publish the faint semantic as soon as HP reaches zero while
  -- the visible damage beat is still in progress. Remember the KO and begin it
  -- immediately after the hurt bank completes.
  if self.hitAge then
    self.pendingFaint=disposition or "collapse"
    return true
  end
  self.pendingFaint=nil
  self.pendingHits=nil
  self.pendingAttack=nil;self.pendingRecall=nil
  self.action=nil;self.actionAge=0
  self.hitAge=nil
  self.recallAge=nil
  self.faintAge=0
  self.faintKind=disposition or "collapse"
  self:transition("faint")
  self:selectNativeSlot("faint")
  return true
end
function Actor:recall(reason)
  if self.state=="faint" or self.state=="removal" then return false end
  if self.hitAge then
    self.pendingRecall=reason or "switch"
    return true
  end
  self.action=nil;self.actionAge=0
  self.hitAge=nil
  self.faintAge=nil
  self.pendingFaint=nil;self.pendingHits=nil;self.pendingAttack=nil;self.pendingRecall=nil
  self.recallAge=0
  self.recallScale=nil
  self.recallReason=reason or "switch"
  self:transition("recall")
  return true
end
function Actor:setRecallScale(scale)
  if self.state~="recall" then return false end
  if type(scale)=="number" then self.recallScale=clamp(scale,0,1) end
  return true
end
function Actor:terminalComplete()
  if self.state=="faint" then
    return (tonumber(self.faintAge) or 0)>=self:terminalDuration("faint")
  end
  if self.state=="recall" then
    if self.recallScale~=nil and self.recallScale<=0 and (tonumber(self.recallAge) or 0)>0.05 then
      return true
    end
    return (tonumber(self.recallAge) or 0)>=RECALL_DURATION
  end
  return self.state=="removal"
end
function Actor:remove(reason)
  self.removeReason=reason or "removed"
  self:transition("removal")
end
function Actor:release()
  -- Meshes are shared per species through `scenes`, so an actor holds no GPU
  -- resource of its own. Releasing must not free the shared scene.
  self.scene=nil
end

-- ------------------------------------------------------------- service ----

-- Height the model is scaled to, expressed in the ACTOR VP's units.
--
-- This is not the same space the trainer path works in, which is what made 6.9
-- wrong. Our service declares worldUnits=false, so drawStadiumActors hands us
-- services.vp rather than services.stageVP, and CurrentSpriteModels states the
-- difference plainly at its targetGeometry helper: "The arena's actor VP
-- includes figureScale" -- roughly 0.38. A 6.9-unit model therefore rendered at
-- about 2.6 effective units while trainers render near 6.4, so every Pokemon
-- came out ~2.4x undersized and read as a fragment rather than a small model.
--
-- The extractor normalizes every species to a height of 16, so a value near 16
-- is very close to 1:1 with the cache and lands in the trainers' size band once
-- figureScale is applied. Tune live with F7/F8; the overlay shows the result.
-- A 1.70 m Pokemon should occupy the same final stage height as a human
-- trainer. Trainers are authored at about 6.9 stage units, while portable
-- actors are drawn through the arena's figureScale VP. 18.16 is the fallback
-- actor-space reference for the default .38 figure scale; acquire() derives the
-- exact reference from the active arena so custom arenas stay calibrated too.
local HUMAN_WORLD_HEIGHT=6.90
local DEFAULT_FIGURE_SCALE=.38
local WORLD_HEIGHT=HUMAN_WORLD_HEIGHT/DEFAULT_FIGURE_SCALE
local HUMAN_REFERENCE_METERS=1.70
-- Physical scale remains the baseline, but battle readability gets a floor. A
-- literal 0.20-0.30 m model can be physically accurate and still be nearly
-- impossible to read at a handheld/1080p battle camera. The floor is a
-- presentation exception only; battle data and Pokédex height stay untouched.
local MIN_READABLE_RELATIVE=.29
-- Raw Pokédex height is NOT a literal standing-height multiplier. It mixes
-- height, body length and extreme fantasy proportions (Ekans is the clearest
-- example: 6'7" describes its long body, not a six-foot-tall battle stance).
-- Every species therefore passes through the same soft allometric curve before
-- body-type compensation. Small Pokemon are lifted for readability; giants are
-- compressed progressively instead of linearly taking over the stadium.
local SCALE_CURVE_EXP=.72
local MAX_READABLE_RELATIVE=1.58
local TINY_SPECIES_FLOOR={
  [10]=.32, -- Caterpie
  [13]=.34, -- Weedle: long/thin silhouette needs a slightly stronger floor
  [50]=.32, -- Diglett
  [19]=.31, -- Rattata
  [21]=.31, -- Spearow
}
-- Long/coiled silhouettes consume substantially more screen area than their
-- standing height suggests, so a few extreme bodies use a slightly tighter
-- visual ceiling while still reading as clearly larger than a human trainer.
local LARGE_SPECIES_CEILING={
  [95]=1.38,  -- Onix
  [130]=1.34, -- Gyarados
  [131]=1.48, -- Lapras
  [143]=1.42, -- Snorlax
  [149]=1.46, -- Dragonite
  [208]=1.42, -- Steelix
  [249]=1.50, -- Lugia
  [250]=1.50, -- Ho-Oh
}

-- Species whose canonical Pokédex "height" is visually much closer to body
-- LENGTH than standing height. The global curve still applies first; these
-- factors convert the published measurement into the compact/coiled battle
-- silhouette actually authored in Colosseum. This is not an Ekans-only hack:
-- the complete Gen-I/II elongated-body family is handled by the same rule.
local LENGTH_MEASURED_FACTOR={
  [23]=.50,  -- Ekans
  [24]=.54,  -- Arbok
  [95]=.42,  -- Onix
  [130]=.47, -- Gyarados
  [148]=.52, -- Dragonair
  [162]=.62, -- Furret
  [206]=.60, -- Dunsparce
  [208]=.42, -- Steelix
}

local function normalizedPresentationRelative(meters,dex)
  local raw=meters and meters>0 and (meters/HUMAN_REFERENCE_METERS) or .72
  raw=math.max(.04,raw)
  local curved=raw^SCALE_CURVE_EXP
  local body=LENGTH_MEASURED_FACTOR[tonumber(dex)] or 1
  return curved*body,raw,curved,body
end
local scaleTrim=1.0

local function actorWorldScale(actor)
  local h=tonumber(actor and actor.height) or 0
  local reference=tonumber(actor and actor.referenceActorHeight) or WORLD_HEIGHT
  local relative=tonumber(actor and actor.physicalScale) or .72
  local target=reference*relative*scaleTrim
  return (h>0.01) and (target/h) or (relative*scaleTrim)
end

local function dexHeightMeters(opts)
  local ctx=opts and opts.context
  local game=(ctx and ctx.game) or (ctx and ctx.battle and ctx.battle.game)
  local battler=opts and opts.battler
  local mon=battler and (battler.mon or battler)
  local species=mon and mon.species
  local data=game and game.data
  local def=data and data.pokemon and species and data.pokemon[species]
  local e=def and def.dexEntry
  if e then
    if tonumber(e.heightM) and tonumber(e.heightM)>0 then return tonumber(e.heightM) end
    local ft,inch=tonumber(e.heightFt),tonumber(e.heightIn)
    if ft then return (ft*12+(inch or 0))*0.0254 end
  end
  -- Gold/Silver extraction stores the source Pokedex height as the digits the
  -- cart prints (e.g. 204 == 2'04"). Convert that authoritative field here.
  local g2=data and data.gen2Pokedex and data.gen2Pokedex.entries
  local raw=g2 and species and g2[species] and tonumber(g2[species].height)
  if raw and raw>0 then
    local ft=math.floor(raw/100);local inch=raw%100
    return (ft*12+inch)*0.0254
  end
  return nil
end         -- runtime multiplier, adjusted with F7/F8

function A.available(source,dex)
  dex=tonumber(dex)
  if not (dex and Dex.supported(dex)) then return false end
  if scenes[dex] then return true end
  if extractor and mod.cache and extractor.isCached(mod,dex,{skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode}) then return true end
  -- Not yet extracted. Report available only if we can still reach the source
  -- disc to build it on demand; otherwise decline cleanly so the 2D seam runs.
  return discOpener~=nil
end

function A.acquire(source,dex,variant,opts)
  perf.actorAcquires=perf.actorAcquires+1
  dex=tonumber(dex)
  if not (dex and Dex.supported(dex)) then return nil,"unsupported dex" end

  -- A resident GPU scene has already passed the extractor stamp check for this
  -- session. Re-reading rev.txt/cache metadata on every Summary reopen or actor
  -- reacquire was pure filesystem churn, especially noticeable on Gen-I menu
  -- transitions. Debug rebuild toggles explicitly clear scenes[dex], so this
  -- fast path cannot hide an intentional re-extraction.
  local resident=scenes[dex]
  if resident then perf.residentAcquireHits=perf.residentAcquireHits+1 end

  -- isCached now also rejects a cache written by a DIFFERENT extractor
  -- revision, so an improved extractor rebuilds species that an older one had
  -- already cached. Drop any GPU scene we built from the stale cache too,
  -- otherwise the old meshes stay resident for the rest of the session.
  if not resident and extractor and not extractor.isCached(mod,dex,{skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode}) then
    if scenes[dex] then scenes[dex]=nil;sceneErrors[dex]=nil end
    if pendingExtract[dex] then return nil,"extraction already failed this session" end
    if not discOpener then return nil,"source disc unavailable for on-demand extraction" end
    local okDisc,disc=pcall(discOpener)
    if not okDisc or not disc then
      pendingExtract[dex]=true
      return nil,"source disc could not be opened: "..tostring(disc)
    end
    -- extractSpecies returns (result) on success and (nil,message) on failure,
    -- so pcall gives us three values. Keep the message: a species that cannot
    -- be built should say why in the log, not just vanish into the 2D fallback.
    local ok,result,extractErr=pcall(extractor.extractSpecies,mod,disc,dex,
      {targetHeight=16.0,decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true})
    if not ok then
      pendingExtract[dex]=true
      log("error","extraction raised for dex %d: %s",dex,tostring(result))
      return nil,tostring(result)
    end
    if not result then
      pendingExtract[dex]=true
      log("warn","extraction declined dex %d: %s",dex,tostring(extractErr))
      return nil,tostring(extractErr or "extraction failed")
    end
  end

  local scene,serr=resident,nil
  if not scene then scene,serr=loadScene(dex) end
  if not scene then return nil,serr end
  sceneUseSerial=sceneUseSerial+1;scene.__cbeLastUse=sceneUseSerial

  local actor=Actor.new(dex,variant,scene,opts)
  local metadataKey=tostring(dex)..":"..tostring(variant or "normal")
  local metadata=sourceMetadata[metadataKey]
  if metadata==nil then
    -- Runtime metadata is tiny but older builds re-opened the 1.46 GB import,
    -- parsed the species FSYS and inflated the PKX wrapper on the first actor
    -- acquisition of EVERY app session. Persist the body-map/slot subset next
    -- to the model cache so a generated visual cache is actually self-serving.
    local cached=select(1,readLua(metadataCachePath(dex)))
    if type(cached)=="table" and tonumber(cached.revision)==1 then metadata=cached end
  end
  if metadata==nil and metadataReader and discOpener then
    local okDisc,disc=pcall(discOpener)
    if okDisc and disc then
      local okMeta,value,metaErr=pcall(metadataReader.inspectSpecies,disc,dex,variant)
      if okMeta and value then metadata=value;pcall(writeMetadataCache,dex,value)
      else log("warn","PKX metadata unavailable for dex %d: %s",dex,tostring(okMeta and metaErr or value)) end
    end
  end
  sourceMetadata[metadataKey]=metadata or false
  if metadata==false then metadata=nil end
  actor.sourceMetadata=metadata
  actor:selectNativeSlot("idle")
  A._liveActors=A._liveActors or setmetatable({},{__mode="v"})
  A._liveActors[#A._liveActors+1]=actor
  -- Preserve species-relative physical scale. Previous builds normalized every
  -- Pokemon to effectively the same battle height, turning Weedle into a kaiju
  -- while making large Pokemon such as Arcanine read too small beside trainers.
  -- The cache remains normalized for numerical stability; runtime scale restores
  -- the Pokedex height relative to a ~1.70 m trainer. Extreme giant species are
  -- softly capped only to keep the arena/camera numerically usable.
  local h=actor.height
  local meters=dexHeightMeters(opts)
  local normalizedRelative,rawRelative,curveRelative,bodyFactor=
    normalizedPresentationRelative(meters,dex)
  local floor=TINY_SPECIES_FLOOR[dex] or MIN_READABLE_RELATIVE
  local ceiling=LARGE_SPECIES_CEILING[dex] or MAX_READABLE_RELATIVE
  local relative=math.min(math.max(normalizedRelative,floor),ceiling)
  local ctx=opts and opts.context
  local figureScale=tonumber(ctx and ctx.arena and ctx.arena.figureScale) or DEFAULT_FIGURE_SCALE
  figureScale=math.max(.08,figureScale)
  actor.physicalHeightMeters=meters
  actor.sourcePhysicalScale=rawRelative
  actor.allometricScale=curveRelative
  actor.bodyLengthFactor=bodyFactor
  actor.physicalScale=relative
  actor.presentationScaleFloor=floor
  actor.presentationScaleCeiling=ceiling
  actor.readabilityBoost=(rawRelative>0) and (relative/rawRelative) or 1
  actor.largeBodyCompression=(relative>0 and rawRelative>relative) and (rawRelative/relative) or 1
  actor.referenceActorHeight=HUMAN_WORLD_HEIGHT/figureScale
  actor.worldScale=actorWorldScale(actor)
  -- Species without a source `rare_` model get the runtime recolour instead.
  actor.shinyShift=(variant=="shiny" and not Dex.rare[dex]) and 2.4 or 0
  return actor
end

-- CBE draws into the caller's active target. We do not clear, do not touch the
-- canvas, and restore every render state we change -- the contract every
-- battleActors provider is held to.
function A.withRenderer(vp,callback,opts)
  local sh,err=ensureShader()
  if not sh then return false,err end
  local g=love.graphics
  local okPush,pushErr=pcall(g.push,"all")
  if not okPush then return false,pushErr end
  local ok,result=pcall(function()
    g.setDepthMode("lequal",true)
    g.setBlendMode("alpha","alphamultiply")
    if g.setMeshCullMode then g.setMeshCullMode("none") end
    sh:send("vp","row",vp)
    sh:send("cameraEye",(opts and opts.eye) or {54,24,13})
    return callback()
  end)
  pcall(g.setShader)
  pcall(g.setDepthMode)
  pcall(g.pop)
  A.drewThisFrame=true
  if not ok then return false,result end
  return result
end

-- ---------------------------------------------------------------- debug ----
--
-- Diagnostics that live in the generated cache are only useful if they can be
-- read, and that cache sits in an application data folder that is genuinely
-- hard to find. This draws the same facts over the battle instead, so a
-- screenshot carries everything needed to diagnose a bad model.
--
-- Toggle with F9. Costs nothing while off.

A.debug=false
A.drewThisFrame=false
-- "auto" applies the duplicate-root rejection. The forced modes exist so the
-- correct decode can be identified in one battle instead of one release: if
-- auto still looks wrong, F10 switches strategy and re-extracts on the spot.
A.decodeMode="auto"
local DECODE_MODES={"auto","single","scene"}
-- Native HSD envelope placement. F6 keeps a legacy comparison path available,
-- but the default now uses each deformer joint's stored inverse-bind matrix and
-- the mesh owner's HSD envelope coordinate system. This matters even when every
-- envelope is 100% single-bone -- exactly the case reported by the broken test
-- species in 1.5.20.
A.skinFix=true
-- Source visibility filter. F4 toggles native JOBJ OPA/XLU/TEXEDGE pass
-- membership. Earlier builds decoded zero-pass helper/proxy geometry as visible
-- white meshes and then tried to remove it with a spatial heuristic.
A.renderPassFilter=true
A._sourceVisibilitySafetyLock=true
A._lastF4Notice=nil
-- Show one render group at a time (F5), cycling through every group present
-- on any currently-live actor, then back to "all". Pure render-time filter --
-- no re-extraction, so it is free to step through and answers "which of these
-- shapes is the stray one" by looking rather than by reasoning about vertex
-- counts and hoping.
A.isolateGroup=nil
local debugKeyHeld=false
local csm=nil   -- CurrentSpriteModels, injected by install()

-- A.rebuildSpecies() only drops the cache -- it does not touch any Actor
-- already on the field, which keeps its own captured `scene` reference from
-- whenever it was last sent out. Without this, F6/F10 only affect the NEXT
-- send-out: the Pokemon currently in battle keeps rendering its pre-toggle
-- geometry, the overlay's per-species block reads the now-empty scene cache
-- and says "no species loaded yet", and it looks exactly like the toggle did
-- nothing when it simply was never exercised on what's on screen. Re-extract
-- and re-load every currently-live actor's species immediately so a toggle is
-- visible on the very next frame, not after a manual withdraw-and-resend.
local function refreshLiveActors()
  if not (extractor and discOpener) then return 0 end
  local dexes,seen={},{}
  for _,rec in pairs(A._liveActors or {}) do
    if rec and rec.dex and not seen[rec.dex] then seen[rec.dex]=true;dexes[#dexes+1]=rec.dex end
  end
  for _,dex in ipairs(dexes) do
    -- Do not rely on the caller having cleared the in-memory scene cache
    -- first (A.rebuildSpecies() normally does, but this must be correct on
    -- its own): loadScene() below returns whatever is already cached in
    -- `scenes[dex]` before it looks at the freshly rewritten cache file, so a
    -- stale in-memory hit would silently make this whole refresh a no-op.
    scenes[dex]=nil;sceneErrors[dex]=nil
    local okDisc,disc=pcall(discOpener)
    if okDisc and disc then
      pcall(extractor.extractSpecies,mod,disc,dex,
        {targetHeight=16.0,decodeMode=A.decodeMode,skinFix=A.skinFix,renderPassFilter=true})
    end
  end
  local refreshed=0
  for _,rec in pairs(A._liveActors or {}) do
    if rec and rec.dex then
      local scene=loadScene(rec.dex)
      if scene then
        rec.scene=scene
        local h=(scene.bounds and scene.bounds.max and scene.bounds.min
          and (scene.bounds.max[2]-scene.bounds.min[2])) or rec.height
        rec.height=h
        rec.worldScale=actorWorldScale(rec)
        refreshed=refreshed+1
      end
    end
  end
  A._lastRefresh={dexes=#dexes,refreshed=refreshed}
  return refreshed
end

local trimDownHeld,trimUpHeld,modeKeyHeld,skinKeyHeld,isolateKeyHeld,rigidKeyHeld=false,false,false,false,false,false
local function pollDebugKey()
  if not (love and love.keyboard and love.keyboard.isDown) then return end
  local ok,down=pcall(love.keyboard.isDown,"f9")
  if not ok then return end
  if down and not debugKeyHeld then A.debug=not A.debug end
  debugKeyHeld=down and true or false

  -- Live scale tuning. Coordinate spaces here are easy to reason about wrongly
  -- and expensive to iterate on through a rebuild, so the value is adjustable
  -- in-battle and shown in the overlay: find the number that looks right and it
  -- can be baked in as the default.
  local okM,md=pcall(love.keyboard.isDown,"f10")
  if okM and md and not modeKeyHeld then
    local i=1
    for n,name in ipairs(DECODE_MODES) do if name==A.decodeMode then i=n end end
    A.decodeMode=DECODE_MODES[(i % #DECODE_MODES)+1]
    A.rebuildSpecies()      -- drop caches so any future send-out re-extracts
    refreshLiveActors()     -- and re-decode what's on screen right now
  end
  modeKeyHeld=okM and md or false

  local okS,sk=pcall(love.keyboard.isDown,"f6")
  if okS and sk and not skinKeyHeld then
    A.skinFix=not A.skinFix
    A.rebuildSpecies()      -- drop caches so any future send-out re-extracts
    refreshLiveActors()     -- and re-decode what's on screen right now
  end
  skinKeyHeld=okS and sk or false

  local okR,rk=pcall(love.keyboard.isDown,"f4")
  if okR and rk and not rigidKeyHeld then
    -- SAFETY LOCK: do not ever re-extract source zero-pass JOBJ geometry from
    -- a live battle keypress. Multiple real runtime tests have shown that the
    -- visibility-OFF path can terminate the host below Lua (pcall cannot catch
    -- a native/GPU crash). The production source-faithful filter therefore
    -- stays ON. F4 is retained only as a visible diagnostic acknowledgement so
    -- an old testing habit cannot kill the game.
    A.renderPassFilter=true
    A._lastF4Notice="BLOCKED: source-visibility filtering is safety-locked ON; no re-extract performed"
  end
  rigidKeyHeld=okR and rk or false

  local okI,ik=pcall(love.keyboard.isDown,"f5")
  if okI and ik and not isolateKeyHeld then
    local maxGroups=0
    for _,rec in pairs(A._liveActors or {}) do
      if rec and rec.scene and rec.scene.groups then maxGroups=math.max(maxGroups,#rec.scene.groups) end
    end
    if maxGroups>0 then
      if not A.isolateGroup then A.isolateGroup=1
      elseif A.isolateGroup>=maxGroups then A.isolateGroup=nil
      else A.isolateGroup=A.isolateGroup+1 end
    end
  end
  isolateKeyHeld=okI and ik or false

  local okD,dn=pcall(love.keyboard.isDown,"f7")
  local okU,up=pcall(love.keyboard.isDown,"f8")
  local changed=false
  if okD and dn and not trimDownHeld then scaleTrim=math.max(0.1,scaleTrim-0.1);changed=true end
  if okU and up and not trimUpHeld then scaleTrim=math.min(6.0,scaleTrim+0.1);changed=true end
  trimDownHeld=okD and dn or false
  trimUpHeld=okU and up or false
  if changed then
    -- Live actors cache worldScale at acquire time; drop them so the next frame
    -- rebuilds at the new trim. Scenes (the meshes) are untouched and shared.
    for _,rec in pairs(A._liveActors or {}) do
      if rec and rec.height and rec.height>0.01 then
        rec.worldScale=actorWorldScale(rec)
      end
    end
  end
end

local function debugLines()
  local modVer=(mod and mod.exports and mod.exports.version) or "?"
  local out={"CBE POKEMON ACTORS  [F9]   MOD VERSION: "..tostring(modVer)}

  -- ARBITRATION comes first. Everything below it is meaningless if this
  -- provider was never selected -- which is precisely the failure that went
  -- undiagnosed for four releases, because the 2D sprite fallback looks
  -- exactly like "the 3D models are broken".
  local mode,modeId,owner,err="?","?","?",nil
  if csm and type(csm.status)=="function" then
    local okS,st=pcall(csm.status)
    if okS and type(st)=="table" then
      mode=tostring(st.presentationMode)
      modeId=tostring(st.presentationId)
      owner=tostring(st.actorOwner or "-")
      err=st.stadiumError
    end
  end
  local selected=(mode=="stadium")
  out[#out+1]=("presentation mode: %s   id: %s"):format(mode,modeId)
  out[#out+1]=("actor owner: %s"):format(owner)
  out[#out+1]=selected and "SELECTED -- this provider is rendering"
    or "NOT SELECTED -- you are seeing 2D sprites, not these models"
  out[#out+1]=("renderer invoked this frame: %s"):format(A.drewThisFrame and "yes" or "no")
  if err then out[#out+1]=("actor error: %s"):format(tostring(err)) end
  out[#out+1]=("species supported %d | on-demand extraction: %s")
    :format(Dex.speciesCount,discOpener and "available" or "NO DISC ACCESS")
  out[#out+1]=("perf scenes %d load / %d hit | actions %d built (%d warm) | acquires %d (%d resident)")
    :format(perf.sceneLoads,perf.sceneHits,perf.actionBuilds,perf.actionPrewarms,perf.actorAcquires,perf.residentAcquireHits)
  out[#out+1]=("SCALE  height %.1f  trim %.2f  =%.1f units   [F7 smaller / F8 bigger]")
    :format(WORLD_HEIGHT,scaleTrim,WORLD_HEIGHT*scaleTrim)
  out[#out+1]=("DECODE MODE  %s   [F10 cycles: auto / single / scene -- re-extracts]")
    :format(A.decodeMode:upper())
  out[#out+1]=("HSD ENVELOPE FIX  %s   [F6 toggles source IBM + owner-coordinate skinning -- re-extracts]")
    :format(A.skinFix and "ON" or "OFF (legacy CBE placement)")
  out[#out+1]="SOURCE VISIBILITY  ON   [F4 SAFETY-LOCKED: zero-pass source geometry is quarantined]"
  if A._lastF4Notice then out[#out+1]="F4: "..A._lastF4Notice end
  if A._lastRefresh then
    out[#out+1]=("last F6/F10 refresh: %d/%d actor(s) currently on the field re-decoded")
      :format(A._lastRefresh.refreshed,A._lastRefresh.dexes)
  end
  out[#out+1]=("ISOLATE GROUP  %s   [F5 cycles through one group at a time -- no re-extract]")
    :format(A.isolateGroup and ("#"..A.isolateGroup) or "OFF (showing all)")
  local any=false
  for dex,sc in pairs(scenes) do
    any=true
    out[#out+1]=("dex %d  %s"):format(dex,tostring(sc.stem))
    out[#out+1]=("   verts %d   groups %d   via %s")
      :format(sc.vertexCount or 0,sc.groupCount or 0,tostring(sc.decodePath))
    -- Per-group counts (and texture presence) make a stray or duplicated mesh
    -- obvious at a glance, and pair with F5 to isolate the suspect visually.
    local parts={}
    for i,g in ipairs(sc.groups or {}) do
      local n=(g.mesh and g.mesh.getVertexCount) and g.mesh:getVertexCount() or 0
      parts[#parts+1]=("g%d=%d%s"):format(i,n,g.textured and "t" or "")
      if i>=8 then break end
    end
    if #parts>0 then out[#out+1]="   groups  "..table.concat(parts,"  ").."   (t = has a texture)" end
    if A.isolateGroup and sc.groups and sc.groups[A.isolateGroup] then
      local ig=sc.groups[A.isolateGroup]
      local d=ig.diffuse or {1,1,1}
      out[#out+1]=("   F5 g%d material  tex=%s slot=%d  diffuse=%.2f,%.2f,%.2f  alpha=%.3f  xlu=%s noz=%s flags=0x%08X%s%s")
        :format(A.isolateGroup,ig.textured and "YES" or "NO",ig.textureSlot or -1,
          d[1] or 1,d[2] or 1,d[3] or 1,ig.alpha or 1,
          ig.xlu and "Y" or "N",ig.noz and "Y" or "N",ig.renderFlags or 0,
          ig.shadow and " SHADOW" or "",ig.effect and " EFFECT" or "")
    end
    local ac,pending=0,0
    for _ in pairs(sc.actions or {}) do ac=ac+1 end
    for _ in pairs(sc.actionSpecs or {}) do pending=pending+1 end
    out[#out+1]=("   fallback clip %d/%d frames %d | PKX native banks %d resident / %d indexed")
      :format(sc.clip or 0,sc.clipCount or 0,sc.morphFrames or 0,ac,ac+pending)
    local b=sc.bounds
    if b and b.min and b.max then
      out[#out+1]=("   bounds  x %.2f..%.2f  y %.2f..%.2f  z %.2f..%.2f")
        :format(b.min[1] or 0,b.max[1] or 0,b.min[2] or 0,b.max[2] or 0,b.min[3] or 0,b.max[3] or 0)
    end
    -- >1.6 means a few stray vertices are inflating the box, which shrinks the
    -- body once the model is normalized to battle height.
    local hr,wr=sc.heightRatio or 0,sc.widthRatio or 0
    out[#out+1]=("   outlier ratio  height %.2f  width %.2f%s")
      :format(hr,wr,(hr>1.6 or wr>1.6) and "   <-- SCATTERED GEOMETRY" or "")
    out[#out+1]=("   skinning  %d envelope matrices (%d multi-bone) across %d enveloped meshes  fix=%s")
      :format(sc.envBlends or 0,sc.envBlendsMulti or 0,sc.envPobjs or 0,sc.skinFix and "ON" or "OFF")
    out[#out+1]=("   joints  %d hidden skipped   %d quaternion%s")
      :format(sc.hiddenJobjs or 0,sc.quatJobjs or 0,
        (sc.quatJobjs or 0)>0 and "  <-- ROTATIONS READ AS EULER" or "")
    -- Per-JOBJ world-scale diagnostic. Useful for spotting a truly degenerate
    -- source transform, but it is not a substitute for envelope placement.
    local jn=sc.jointCount or 0
    if jn>0 then
      out[#out+1]=("   joint world scale  %d contributing  min %.4f  median %.4f  max %.4f  %d outlier(s)%s")
        :format(jn,sc.jointScaleMin or 0,sc.jointScaleMedian or 0,sc.jointScaleMax or 0,
          sc.jointScaleOutliers or 0,
          (sc.jointScaleOutliers or 0)>0 and "  <-- A JOINT IS COLLAPSING OR EXPLODING" or "")
    end
    out[#out+1]=("   source visibility  %d zero-pass JOBJ(s) + %d DOBJ pass mismatch(es) skipped; %d shadow pass(es) quarantined  filter=%s")
      :format(sc.nonRenderJobjs or 0,sc.nonRenderDobjs or 0,sc.shadowDobjs or 0,sc.renderPassFilter and "ON" or "OFF")
    out[#out+1]=("   root selection  %s   semantic roots=%d")
      :format(sc.semanticRootsOnly and "SCENE-MODELSET ONLY" or "LEGACY/SCENE UNION",
        sc.semanticRootCount or 0)
    local cacheMismatch=(sc.renderPassFilter~=A.renderPassFilter)
      or (sc.skinFix~=A.skinFix)
      or (not sc.semanticRootsOnly)
      or (tostring(sc.requestedDecodeMode or "auto")~=tostring(A.decodeMode or "auto"))
    if cacheMismatch then
      out[#out+1]=("   !!! CACHE OPTION MISMATCH: cache skin=%s visibility=%s semanticRoot=%s mode=%s | current skin=%s visibility=%s semanticRoot=ON mode=%s")
        :format(sc.skinFix and "ON" or "OFF",sc.renderPassFilter and "ON" or "OFF",
          sc.semanticRootsOnly and "ON" or "OFF",tostring(sc.requestedDecodeMode or "auto"),
          A.skinFix and "ON" or "OFF",A.renderPassFilter and "ON" or "OFF",tostring(A.decodeMode or "auto"))
    end
    out[#out+1]=("   envelope coord  %d entries  single-bone: %d with coord / %d root-direct  IBM fallbacks %d")
      :format(sc.envelopeCoordEntries or 0,sc.singleEnvelopeCoord or 0,sc.singleEnvelopeNoCoord or 0,sc.inverseBindMissing or 0)
    if (sc.placeholderGroupsRemoved or 0)>0 then
      out[#out+1]=("   legacy placeholder heuristic unexpectedly removed %d group(s) / %d vertices")
        :format(sc.placeholderGroupsRemoved,sc.placeholderVertsRemoved or 0)
    else
      out[#out+1]="   placeholder heuristic OFF -- visibility comes from source JOBJ flags"
    end
    local drift=sc.poseDrift or 0
    out[#out+1]=("   pose  %s   drift from bind %.4f%s")
      :format((sc.clip or 0)==0 and "BIND (static, correctly assembled)" or ("clip "..tostring(sc.clip)),
        drift,drift>0.16 and "  <-- INCOHERENT" or "")
  end
  if not any then
    local live={}
    for _,rec in pairs(A._liveActors or {}) do if rec and rec.dex then live[#live+1]=rec.dex end end
    if #live>0 then
      out[#out+1]=("no species in the scene cache, but %d actor(s) are on the field (dex %s) -- "
        .."re-decode failed silently; check the log")
        :format(#live,table.concat(live,","))
    else
      out[#out+1]="no species loaded yet"
    end
  end
  for dex,err in pairs(sceneErrors) do
    out[#out+1]=("dex %d FAILED: %s"):format(dex,tostring(err))
  end
  for dex in pairs(pendingExtract) do
    out[#out+1]=("dex %d extraction declined this session"):format(dex)
  end
  return out
end

local function drawDebug()
  if not A.debug then return end
  local g=love and love.graphics
  if not g then return end
  local lines=debugLines()
  g.push("all")
  g.setShader()
  g.setDepthMode()
  g.setBlendMode("alpha","alphamultiply")
  -- Positioned clear of the battle HUD. This draws during the world pass, so
  -- the UI composites over it no matter what; the fix is to sit below the HP
  -- panels rather than to fight the draw order.
  local pad,lh=10,15
  local w=600
  local h=pad*2+#lines*lh
  local x,y=8,170
  g.setColor(0,0,0,0.88)
  g.rectangle("fill",x,y,w,h)
  g.setColor(0.35,0.9,0.65,0.5)
  g.rectangle("line",x,y,w,h)
  for i,line in ipairs(lines) do
    if i==1 then g.setColor(1,0.95,0.5,1) else g.setColor(0.78,0.97,0.88,1) end
    g.print(line,x+pad,y+pad+(i-1)*lh)
  end
  g.pop()
end

function A.status()
  local loaded,failed=0,0
  for _ in pairs(scenes) do loaded=loaded+1 end
  for _ in pairs(sceneErrors) do failed=failed+1 end
  return {
    version=1,provider="COLOSSEUM_BATTLE_ENVIRONMENTS:colosseum-pokemon",
    source="GC6E01 pkx battle models + native PKX presentation metadata",
    speciesSupported=Dex.speciesCount,
    scenesLoaded=loaded,scenesFailed=failed,
    pose="source-hsd-authored-frames",nativeMetadataReader=metadataReader~=nil,
    shaderReady=shader~=nil,
    debugOverlay=A.debug,
    diagnostic=debugLines(),
    onDemandExtraction=discOpener~=nil,
    performance={sceneLoads=perf.sceneLoads,sceneHits=perf.sceneHits,actionBuilds=perf.actionBuilds,
      actionPrewarms=perf.actionPrewarms,actorAcquires=perf.actorAcquires,residentAcquireHits=perf.residentAcquireHits,
      battlePrewarms=perf.battlePrewarms or 0,battlePrewarmMs=perf.battlePrewarmMs or 0,
      switchPrewarms=perf.switchPrewarms or 0,floorClamps=perf.floorClamps or 0,
      idleWarmLoads=perf.idleWarmLoads or 0,idleWarmMs=perf.idleWarmMs or 0,idleWarmPending=#idleWarmQueue,
      residentTrimKept=perf.residentTrimKept or 0,residentTrimReleased=perf.residentTrimReleased or 0,
      reactionClamps=perf.reactionClamps or 0,reactionFallbacks=perf.reactionFallbacks or 0,
      actionDrawFallbacks=perf.actionDrawFallbacks or 0,deferredActionWarms=perf.deferredActionWarms or 0,
      deferredActionPending=#actionWarmQueue,runtimeBaseHits=perf.runtimeBaseHits or 0,runtimeBaseWrites=perf.runtimeBaseWrites or 0,
      runtimeActionHits=perf.runtimeActionHits or 0,runtimeActionWrites=perf.runtimeActionWrites or 0},
  }
end

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

local function releaseGroups(groups,seen)
  if type(groups)~="table" then return end
  for _,g in ipairs(groups) do
    if type(g)=="table" then
      releaseLoveObject(g.mesh,seen)
      releaseLoveObject(g.image,seen)
    end
  end
end

-- Android devices have a smaller shared RAM/VRAM budget than desktop, but
-- purging EVERY Pokemon after EVERY battle turns the generated cache back into
-- a repeated parse/upload tax. Keep a small player-party working set resident
-- and release everything else. Disk caches are never deleted here.
function A.trimRuntimeMemory(opts)
  opts=type(opts)=="table" and opts or {}
  local keep={}
  local game=opts.game
  local keepParty=math.max(0,math.floor(tonumber(opts.keepParty) or 0))
  if game and keepParty>0 and type(game.save)=="table" then
    local party=game.save.party or game.save.pokemon or game.save.team
    local added=0
    if type(party)=="table" then
      for _,mon in ipairs(party) do
        local species=type(mon)=="table" and ((mon.mon and mon.mon.species) or mon.species) or nil
        local def=species~=nil and game.data and game.data.pokemon and game.data.pokemon[species] or nil
        local dex=tonumber(def and (def.dex or def.index or def.number)) or tonumber(species)
        if dex and scenes[dex] and not keep[dex] then
          keep[dex]=true;added=added+1
          if added>=keepParty then break end
        end
      end
    end
  end
  local keepRecent=math.max(0,math.floor(tonumber(opts.keepRecent) or 0))
  if keepRecent>0 then
    local recent={}
    for dex,scene in pairs(scenes) do
      if not keep[dex] and type(scene)=="table" then recent[#recent+1]={dex=dex,use=tonumber(scene.__cbeLastUse) or 0} end
    end
    table.sort(recent,function(a,b)return a.use>b.use end)
    for i=1,math.min(keepRecent,#recent) do keep[recent[i].dex]=true end
  end
  -- Soft resident cap: do not churn GPU scenes at every battle boundary while
  -- the total working set is still modest. 1.7.9 always collapsed immediately
  -- to party+2-recent, which meant routes with 3-5 encounter species could
  -- repeatedly evict/re-upload the same bodies. Keep everything up to the cap;
  -- only when it is exceeded do the party/recent priorities above become an
  -- actual eviction policy. This preserves low-memory boundedness without
  -- manufacturing a reload tax after every battle.
  local softLimit=math.max(0,math.floor(tonumber(opts.softLimit) or 0))
  if softLimit>0 then
    local total,mandatory=0,0
    for dex,scene in pairs(scenes) do
      if type(scene)=="table" then
        total=total+1
        if keep[dex] then mandatory=mandatory+1 end
      end
    end
    if total<=softLimit then
      for dex,scene in pairs(scenes) do if type(scene)=="table" then keep[dex]=true end end
    else
      local fill={}
      for dex,scene in pairs(scenes) do
        if type(scene)=="table" and not keep[dex] then
          fill[#fill+1]={dex=dex,use=tonumber(scene.__cbeLastUse) or 0}
        end
      end
      table.sort(fill,function(a,b)return a.use>b.use end)
      local slots=math.max(0,softLimit-mandatory)
      for i=1,math.min(slots,#fill) do keep[fill[i].dex]=true end
    end
  end
  local seen={};local kept,released=0,0
  for dex,scene in pairs(scenes) do
    if keep[dex] then
      kept=kept+1
    elseif type(scene)=="table" then
      releaseGroups(scene.groups,seen)
      if type(scene.textures)=="table" then
        for _,img in pairs(scene.textures) do releaseLoveObject(img,seen) end
      end
      for _,entry in pairs(scene.actions or {}) do
        if type(entry)=="table" then
          releaseGroups(entry.groups,seen)
          for _,page in ipairs(entry.pages or {}) do if type(page)=="table" then releaseGroups(page.groups,seen) end end
        end
      end
      scenes[dex]=nil;sceneErrors[dex]=nil;pendingExtract[dex]=nil
      released=released+1
    end
  end
  perf.residentTrimKept=(perf.residentTrimKept or 0)+kept
  perf.residentTrimReleased=(perf.residentTrimReleased or 0)+released
  -- Do not force a full Lua GC here. On mobile that stop-the-world collection
  -- can land immediately before the next battle/menu open. Released GPU objects
  -- are already explicitly released; BattleRuntime advances Lua GC incrementally
  -- during ordinary overworld frames.
  local q={}
  for _,row in ipairs(actionWarmQueue) do if row.scene and scenes[row.scene.dex]==row.scene then q[#q+1]=row else actionWarmSeen[row.id]=nil end end
  actionWarmQueue=q
  return true,{kept=kept,released=released}
end

function A.resetRuntime()
  A.cancelPartyPrewarm()
  A.trimRuntimeMemory({keepParty=0,keepRecent=0})
  shader=nil;sceneUseSerial=0;sourceMetadata={}
  actionWarmQueue={};actionWarmSeen={};actionWarmNextAt=0
  perf={sceneLoads=0,sceneHits=0,actionBuilds=0,actionPrewarms=0,actorAcquires=0,residentAcquireHits=0,
    battlePrewarms=0,battlePrewarmMs=0,switchPrewarms=0,floorClamps=0,idleWarmLoads=0,idleWarmMs=0,
    residentTrimKept=0,residentTrimReleased=0,reactionClamps=0,reactionFallbacks=0,actionDrawFallbacks=0,
    runtimeBaseHits=0,runtimeBaseWrites=0,runtimeActionHits=0,runtimeActionWrites=0,deferredActionWarms=0}
  return true
end

function A.gcStep(k)
  if type(collectgarbage)~="function" then return false end
  local ok=pcall(collectgarbage,"step",math.max(16,math.floor(tonumber(k) or 64)))
  return ok
end

-- Forget every cached species so the next send-out re-extracts from the disc.
-- Deletes the generated files as well as the in-memory scenes, so this is a
-- real rebuild rather than just dropping GPU state.
function A.rebuildSpecies()
  local removed=0
  if extractor and type(extractor.manifestPaths)=="function" and mod.cache then
    local ok,paths=pcall(extractor.manifestPaths,mod)
    if ok and type(paths)=="table" then
      for _,path in ipairs(paths) do
        if pcall(mod.cache.delete,mod.cache,path) then removed=removed+1 end
      end
    end
    for dex=1,251 do pcall(mod.cache.delete,mod.cache,metadataCachePath(dex)) end
  end
  A.resetRuntime()
  return true,removed
end

local function battlerDex(game,battler)
  local mon=type(battler)=="table" and (battler.mon or battler) or nil
  local species=mon and mon.species
  if species==nil then return nil end
  local def=game and game.data and game.data.pokemon and game.data.pokemon[species]
  local dex=tonumber(def and (def.dex or def.index or def.number))
  if not dex and tonumber(species) and Dex.supported(tonumber(species)) then dex=tonumber(species) end
  return dex
end

local function resolveSlotMove(game,slot)
  if type(slot)=="table" then
    if type(slot.move)=="table" then return slot.move end
    if slot.name or slot.power or slot.category or slot.damageClass or slot.type then return slot end
  end
  local id=type(slot)=="table" and (slot.id or slot.moveId or slot.index or slot.move) or slot
  local moves=game and game.data and game.data.moves
  return type(moves)=="table" and id~=nil and (moves[id] or moves[tostring(id)]) or nil
end

local function requiredActionKeys(game,battler)
  local wanted={damage=true,faint=true}
  local mon=type(battler)=="table" and (battler.mon or battler) or nil
  local slots=mon and mon.moves or (type(battler)=="table" and battler.moves)
  if type(slots)=="table" then
    for _,slot in pairs(slots) do wanted[moveSlot(resolveSlotMove(game,slot))]=true end
  end
  local out={}
  for _,key in ipairs({"damage","faint","physicalA","specialC","statusA"}) do
    if wanted[key] then out[#out+1]=key end
  end
  return out
end

local function warmActionKey(scene,key)
  if not (scene and key and scene.actionSpecs and scene.actionSpecs[key]) then return false end
  if scene.actions and scene.actions[key] then return true end
  local entry=materializeSceneAction(scene,key)
  local guard=0
  while entry and entry.alias and guard<8 do
    entry=materializeSceneAction(scene,tostring(entry.alias));guard=guard+1
  end
  if entry then perf.actionPrewarms=perf.actionPrewarms+1;return true end
  return false
end

local function warmRequiredActions(scene,game,battler)
  local warmed=0
  for _,key in ipairs(requiredActionKeys(game,battler)) do
    if warmActionKey(scene,key) then warmed=warmed+1 end
  end
  return warmed
end

local function queueRequiredActions(scene,game,battler)
  if not scene then return 0 end
  local added=0
  for _,key in ipairs(requiredActionKeys(game,battler)) do
    if scene.actionSpecs and scene.actionSpecs[key] and not (scene.actions and scene.actions[key]) then
      local id=tostring(scene.dex or "?")..":"..key
      if not actionWarmSeen[id] then
        actionWarmSeen[id]=true
        actionWarmQueue[#actionWarmQueue+1]={scene=scene,key=key,id=id}
        added=added+1
      end
    end
  end
  return added
end

function A.pumpActionPrewarm(maxJobs)
  maxJobs=math.max(1,math.floor(tonumber(maxJobs) or 1))
  if #actionWarmQueue==0 then return 0,0 end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local now=clock and clock() or 0
  if ANDROID_RUNTIME and now>0 and now<actionWarmNextAt then return 0,#actionWarmQueue end
  local done=0
  while done<maxJobs and #actionWarmQueue>0 do
    local row=table.remove(actionWarmQueue,1)
    if row then
      actionWarmSeen[row.id]=nil
      if row.scene and scenes[row.scene.dex]==row.scene and warmActionKey(row.scene,row.key) then done=done+1 end
    end
  end
  local after=clock and clock() or now
  if ANDROID_RUNTIME then actionWarmNextAt=(after>0 and after or now)+0.16 end
  perf.deferredActionWarms=(perf.deferredActionWarms or 0)+done
  return done,#actionWarmQueue
end


local function prewarmBattler(game,battler,side,allowExtract,warmActions)
  local dex=battlerDex(game,battler)
  if not (dex and Dex.supported(dex)) then return false,"unsupported battler",0 end
  local cached=extractor and mod and mod.cache and type(extractor.isCached)=="function"
    and extractor.isCached(mod,dex,{skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode})
  if not cached and not allowExtract then return false,"not cached",0 end
  -- Use the exact acquisition path the visible actor will use. This resolves the
  -- compact cache, GPU meshes, source metadata and idle bank now, so the later
  -- send-out is a resident hash-table hit rather than a multi-megabyte parse.
  local ctx={game=game,battle={game=game},arena={figureScale=DEFAULT_FIGURE_SCALE},services={prewarm=true}}
  local actor,err=A.acquire("cbe-prewarm",dex,"normal",{context=ctx,battler=battler,side=side})
  if not actor then return false,err,0 end
  local actions=0
  if warmActions~=false then actions=warmRequiredActions(actor.scene,game,battler)
  else queueRequiredActions(actor.scene,game,battler) end
  return true,nil,actions
end
local function prewarmBaseBattler(game,battler,side)
  local dex=battlerDex(game,battler)
  if not (dex and Dex.supported(dex)) then return false,"unsupported battler",nil end
  if scenes[dex] then return true,nil,dex end
  local cached=extractor and mod and mod.cache and type(extractor.isCached)=="function"
    and extractor.isCached(mod,dex,{skinFix=A.skinFix,renderPassFilter=true,decodeMode=A.decodeMode})
  if not cached then return false,"not cached",dex end
  -- Information-surface acquisition intentionally builds only the base/idle
  -- body. Native attack/damage/faint banks remain packed on disk until battle.
  -- This makes the persistent cache useful to party/stats/model screens without
  -- paying the much larger combat-action GPU bill during overworld idle time.
  local ctx={game=game,battle={game=game},arena={figureScale=DEFAULT_FIGURE_SCALE},services={prewarm=true,informationSurface=true}}
  local actor,err=A.acquire("cbe-idle-warm",dex,"normal",{context=ctx,battler=battler,side=side})
  return actor~=nil,err,dex
end

-- Materialize every already-extracted party Pokemon's BASE body at the
-- game-ready seam. This deliberately avoids action banks and never starts ISO
-- extraction. Paying these compact runtime-mesh uploads while the save is
-- entering the world is preferable to doing one expensive species upload on
-- an arbitrary overworld frame that may also become an encounter frame.
function A.prewarmPartyBase(game)
  idleWarmQueue={};idleWarmSeen={};idleWarmGame=game;idleWarmNextAt=0
  if type(game)~="table" or type(game.save)~="table" then return 0,0 end
  local party=game.save.party or game.save.pokemon or game.save.team
  if type(party)~="table" then return 0,0 end
  local warmed,failed,seen=0,0,{}
  for _,mon in ipairs(party) do
    local dex=battlerDex(game,mon)
    if dex and Dex.supported(dex) and not seen[dex] then
      seen[dex]=true
      local ok=prewarmBaseBattler(game,mon,"player")
      if ok then warmed=warmed+1 else failed=failed+1 end
    end
  end
  return warmed,failed
end

function A.queuePartyPrewarm(game)
  idleWarmQueue={};idleWarmSeen={};idleWarmGame=game;idleWarmNextAt=0
  if type(game)~="table" or type(game.save)~="table" then return 0 end
  local party=game.save.party or game.save.pokemon or game.save.team
  if type(party)~="table" then return 0 end
  for _,mon in ipairs(party) do
    local dex=battlerDex(game,mon)
    if dex and Dex.supported(dex) and not idleWarmSeen[dex] and not scenes[dex] then
      idleWarmSeen[dex]=true
      idleWarmQueue[#idleWarmQueue+1]={battler=mon,side="player",dex=dex}
    end
  end
  return #idleWarmQueue
end

function A.pumpPartyPrewarm(game)
  game=game or idleWarmGame
  if not ANDROID_RUNTIME or #idleWarmQueue==0 or type(game)~="table" then return false,#idleWarmQueue end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local now=clock and clock() or 0
  if now>0 and now<idleWarmNextAt then return false,#idleWarmQueue end
  local row=table.remove(idleWarmQueue,1)
  if not row then return false,0 end
  local t0=now
  local ok,err=prewarmBaseBattler(game,row.battler,row.side)
  local t1=clock and clock() or t0
  perf.idleWarmLoads=(perf.idleWarmLoads or 0)+(ok and 1 or 0)
  perf.idleWarmMs=(perf.idleWarmMs or 0)+math.max(0,(t1-t0)*1000)
  -- Leave breathing room between species uploads. The work happens while the
  -- overworld is already interactive instead of stacking six models onto one
  -- battle/menu transition frame.
  idleWarmNextAt=(t1>0 and t1 or now)+0.55
  if not ok and err then log("warn","Android cached-party warm dex %s skipped: %s",tostring(row.dex),tostring(err)) end
  return ok,#idleWarmQueue
end

function A.cancelPartyPrewarm()
  idleWarmQueue={};idleWarmSeen={};idleWarmGame=nil;idleWarmNextAt=0
end

function A.prewarmParty(game)
  -- Game-ready is early enough to materialize every CACHED player-party body
  -- and the exact action categories their current moves need. No disc extraction
  -- is started here, so loading a save cannot turn into a six-species import.
  if type(game)~="table" or type(game.save)~="table" then return 0 end
  local party=game.save.party or game.save.pokemon or game.save.team
  if type(party)~="table" then return 0 end
  local warmed,seen=0,{}
  for _,mon in ipairs(party) do
    local dex=battlerDex(game,mon)
    if dex and not seen[dex] then
      seen[dex]=true
      local ok=prewarmBattler(game,mon,"player",false,true)
      if ok then warmed=warmed+1 end
    end
  end
  return warmed
end

-- Hard battle-entry readiness gate. The active pair is prepared before CBE
-- opens its arena world, including the opponent that cannot be known at
-- game.ready. If an opponent was not imported yet we permit source extraction
-- here: a single transition hold is preferable to an empty slot followed by a
-- multi-second pop-in on the visible send-out frame.
function A.prewarmBattle(battle)
  local game=battle and battle.game
  if type(game)~="table" then return {ready=0,failed=0,actions=0,rosterReady=0,elapsedMs=0} end
  local clock=(love and love.timer and love.timer.getTime) or os.clock
  local t0=clock and clock() or 0
  local out={ready=0,failed=0,actions=0,rosterReady=0,rosterActions=0,errors={}}
  local seen={}

  -- The two visible battlers are mandatory. An uncached active opponent may be
  -- extracted here so any unavoidable work is paid behind the transition,
  -- never on its first rendered send-out frame.
  for _,side in ipairs({"player","enemy"}) do
    local battler=battle and battle[side]
    if battler then
      local dex=battlerDex(game,battler);if dex then seen[dex]=true end
      -- Android pays only the base body/texture upload at battle.started and
      -- spreads native damage/faint/move-bank uploads across the trainer/sendout
      -- presentation that follows. This keeps exact source actions while avoiding
      -- a single multi-bank main-thread spike on the transition boundary.
      local ok,err,actions=prewarmBattler(game,battler,side,true,not ANDROID_RUNTIME)
      if ok then
        out.ready=out.ready+1;out.actions=out.actions+(tonumber(actions) or 0)
        if ANDROID_RUNTIME then out.deferredActions=(out.deferredActions or 0)+queueRequiredActions(scenes[dex],game,battler) end
      else out.failed=out.failed+1;out.errors[side]=tostring(err) end
    end
  end

  -- A generated Pokemon cache is only useful for smooth switching if its packed
  -- scene/action data is already resident. Trainer rosters are known at battle
  -- construction time (Gen 1 `enemyParty`, Gen 2's equivalent), so materialize
  -- every ALREADY-CACHED bench species here as well. Never trigger fresh disc
  -- extraction for a bench slot: that could turn a six-mon trainer intro into a
  -- long load. An uncached replacement is instead paid for at prewarmSwitch's
  -- authoritative switch boundary before the model becomes visible.
  if not ANDROID_RUNTIME then
    local rosters={
      {side="enemy",list=battle and battle.enemyParty},
      {side="player",list=battle and battle.playerParty},
      {side="player",list=game.save and (game.save.party or game.save.pokemon or game.save.team)},
    }
    for _,roster in ipairs(rosters) do
      if type(roster.list)=="table" then
        for _,mon in ipairs(roster.list) do
          local dex=battlerDex(game,mon)
          if dex and not seen[dex] then
            seen[dex]=true
            local ok,_,actions=prewarmBattler(game,mon,roster.side,false,true)
            if ok then
              out.rosterReady=out.rosterReady+1
              out.rosterActions=out.rosterActions+(tonumber(actions) or 0)
            end
          end
        end
      end
    end
  else
    -- Android keeps only the active pair resident at the arena-entry seam.
    -- Bench species are prepared at the authoritative switch boundary instead,
    -- avoiding a six-model + arena + trainer GPU/heap spike on mobile devices.
    out.androidBenchDeferred=true
  end

  local t1=clock and clock() or t0
  out.elapsedMs=math.max(0,(t1-t0)*1000)
  perf.battlePrewarms=(perf.battlePrewarms or 0)+1
  perf.battlePrewarmMs=(perf.battlePrewarmMs or 0)+out.elapsedMs
  return out
end

function A.prewarmSwitch(battle,side,battler)
  local game=battle and battle.game
  battler=battler or (battle and side and battle[side])
  if not (game and battler) then return false,"missing replacement" end
  local ok,err,actions=prewarmBattler(game,battler,side,true,not ANDROID_RUNTIME)
  if ok then
    perf.switchPrewarms=(perf.switchPrewarms or 0)+1
    if ANDROID_RUNTIME then
      local dex=battlerDex(game,battler);local sc=dex and scenes[dex]
      if sc then queueRequiredActions(sc,game,battler) end
    end
  end
  return ok,err,actions
end

-- Wired from main.lua. `openDisc` is a zero-arg function returning an opened
-- GameCubeDisc, kept as a closure so this module never learns the host path.
function A.install(pokemonExtractor,openDisc,currentSpriteModels,pkxMetadataReader)
  extractor=pokemonExtractor
  discOpener=openDisc
  csm=currentSpriteModels
  metadataReader=pkxMetadataReader
  -- Compile/link the actor shader while the mod is initializing whenever the
  -- graphics context is already available. This moves driver work away from
  -- the exact first-send-out frame; hosts that initialize graphics later still
  -- fall back to the normal lazy ensureShader() path.
  local ok,sh,prewarmErr=pcall(ensureShader)
  if not ok then
    log("warn","Pokemon actor shader prewarm failed: %s",tostring(sh))
  elseif not sh and prewarmErr and tostring(prewarmErr)~="LOVE graphics unavailable" then
    log("warn","Pokemon actor shader prewarm declined: %s",tostring(prewarmErr))
  end
  return true
end

-- Per-frame entry point for the overlay, wrapped around CurrentSpriteModels'
-- own drawWorld. That runs every frame of a CBE battle regardless of which
-- presentation mode won, so the overlay can report being UNSELECTED -- which
-- withRenderer, by definition, never could.
function A.debugFrame()
  pcall(pollDebugKey)
  pcall(drawDebug)
  A.drewThisFrame=false
end

-- The published capability. Registering it through CBE's own documented
-- battleCompatibility host keeps discovery order-independent.
A.service={
  version=1,
  portable=true,
  priority=100000,
  worldUnits=false,
  selected=function(context)
    local settings=V.BattleSettings
    if settings and type(settings.pokemonModelsEnabled)=="function" then
      local game=(context and context.game) or (context and context.battle and context.battle.game) or (mod and mod.game)
      local ok,value=pcall(settings.pokemonModelsEnabled,game)
      if ok then return value~=false end
    end
    return true
  end,
  available=function(source,dex) return A.available(source,dex) end,
  acquire=function(source,dex,variant,opts) return A.acquire(source,dex,variant,opts) end,
  withRenderer=function(vp,cb,opts) return A.withRenderer(vp,cb,opts) end,
  status=function() return A.status() end,
}

-- Test-only hook. F6/F10 both go through love.keyboard, which a headless test
-- harness doesn't have, so this lets the actual re-decode-in-place logic be
-- exercised directly instead of only through a GUI key press.
A._test={refreshLiveActors=refreshLiveActors}

return A
