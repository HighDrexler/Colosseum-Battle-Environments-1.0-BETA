local V=...
local Waza=V and V.WazaSequenceRuntime
local Assets=V and V.GeneratedAssets
local CSM=V and V.CurrentSpriteModels
local Audio=V and V.WazaAudioRuntime
local H={installed=false,models={},opaque={},lastModel=nil,modelCache={},modelErrors={},textureCache={},drawError=nil}

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
varying vec3 wNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec4 t=Texel(texture,uv);
  float texA=mix(1.0,t.a,useTexture);
  float a=mix(texA,1.0,forceOpaque)*materialColor.a*opacity*color.a;
  if (a<0.025) discard;
  vec3 base=mix(materialColor.rgb,t.rgb,useTexture);
  if (unlit > 0.5) return vec4(base,a);
  vec3 n=normalize(wNormal);
  vec3 l=normalize(vec3(-0.38,0.84,0.39));
  float key=0.70+0.30*abs(dot(n,l));
  return vec4(base*key,a);
}
]]
local shaderStatic,shaderMorph

local function key(inst,entry)
  return tostring(inst and inst.serial or "?")..":"..tostring(entry and entry.index or "?")
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
  local current=morph and shaderMorph or shaderStatic
  if current then return current end
  if not (love and love.graphics and love.graphics.newShader) then return nil,"LÖVE shader unavailable" end
  local ok,sh=pcall(love.graphics.newShader,morph and VERTEX_MORPH or VERTEX_STATIC,PIXEL)
  if not ok then return nil,sh end
  if morph then shaderMorph=sh else shaderStatic=sh end
  return sh
end

local function decodedVertices(group,expectedStride)
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
  end
  if #rows==0 then return nil,"Waza packed vertex payload empty" end
  group.vertices=rows;group.verticesPacked=nil
  return rows
end

local function loadCache(path)
  if not path then return nil,"Waza model cache missing" end
  if H.modelCache[path]~=nil then return H.modelCache[path] or nil,H.modelErrors[path] end
  if not (love and love.graphics and love.graphics.newMesh) then return nil,"LÖVE mesh API unavailable" end
  local cache,err=readLua(path);if not cache then H.modelCache[path]=false;H.modelErrors[path]=tostring(err);return nil,err end
  local morph=(tonumber(cache.morphFrames) or 0)>0
  local fmt=morph and FORMAT_MORPH or FORMAT_STATIC
  local textures,groups={},{}
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
    local vertices,vErr=decodedVertices(g,morph and 44 or 8)
    if not vertices then H.modelCache[path]=false;H.modelErrors[path]=tostring(vErr);return nil,vErr end
    local ok,mesh=pcall(love.graphics.newMesh,fmt,vertices,"triangles","static")
    if not ok then H.modelCache[path]=false;H.modelErrors[path]=tostring(mesh);return nil,mesh end
    if img then mesh:setTexture(img) end
    local effectLike=g.effect==true or (g.useConstant==true and g.useDiffuseLighting==false)
    groups[#groups+1]={mesh=mesh,image=img,diffuse=g.diffuse or {1,1,1},alpha=tonumber(g.alpha) or 1,
      xlu=g.xlu==true,noz=g.noz==true,renderFlags=tonumber(g.renderFlags) or 0,
      shadow=g.shadow==true,effect=g.effect==true,useConstant=g.useConstant==true,
      useVertexColor=g.useVertexColor==true,useDiffuseLighting=g.useDiffuseLighting~=false,
      -- GameCube Waza effect/constant passes are frequently additive/TEV-light
      -- carriers. Treating a black mask as opaque alpha geometry is what can
      -- turn a correct move into a one-frame black screen in the portable path.
      luminous=effectLike}
  end
  if #groups==0 then H.modelCache[path]=false;H.modelErrors[path]="Waza model cache empty";return nil,H.modelErrors[path] end
  local out={groups=groups,bounds=cache.bounds,source=cache.source,textures=textures,morph=morph,
    morphFrames=tonumber(cache.morphFrames) or 0,startFrame=tonumber(cache.startFrame) or 0,endFrame=tonumber(cache.endFrame) or 0,
    animation=cache.animation}
  H.modelCache[path]=out;H.modelErrors[path]=nil;return out
end

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
  local b=model and model.bounds
  local mn,mx=b and b.min,b and b.max
  if not (mn and mx) then return 16 end
  local sx=math.abs((tonumber(mx[1]) or 0)-(tonumber(mn[1]) or 0))
  local sy=math.abs((tonumber(mx[2]) or 0)-(tonumber(mn[2]) or 0))
  local sz=math.abs((tonumber(mx[3]) or 0)-(tonumber(mn[3]) or 0))
  if basis and basis.groundField then return math.max(.001,sx,sz) end
  return math.max(.001,sx,sy,sz)
end
local function modelMatrix(basis,model)
  local o,r,u,f=basis.origin,basis.right,basis.up,basis.forward
  -- Type-2 HSD effects are raw source models, unlike Pokemon bodies which are
  -- normalized to a 16-unit cache height. Scaling them with actor.worldScale
  -- directly made a large source object enormous and a tiny source object
  -- microscopic. Fit the source bounds to the same live combat-space target
  -- span used by GPT1 instead. For ordinary ~16-unit assets this naturally
  -- collapses to essentially the previous Pokemon-relative scale.
  local desired=math.max(.10,tonumber(basis.modelTargetSpan) or tonumber(basis.referenceVisualHeight) or 16)
  local span=modelSpan(model,basis)
  local s=math.max(.01,math.min(24,desired/span))
  return {
    r[1]*s,u[1]*s,f[1]*s,o[1],
    r[2]*s,u[2]*s,f[2]*s,o[2],
    r[3]*s,u[3]*s,f[3]*s,o[3],
    0,0,0,1,
  }
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
  if type(anim)=="table" and anim.animated==true then
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
    commonMode=entry.commonMode,words=entry.words,subtype=entry.subtype,mode=entry.mode,value=entry.value}
  while #H.opaque>512 do table.remove(H.opaque,1) end
  return true
end
local function opaqueFinish() return true end

function H.install()
  if H.installed or not (Waza and type(Waza.registerHandler)=="function") then return false end
  Waza:registerHandler("model","cbe-waza-model",{start=modelStart,update=modelUpdate,finish=modelFinish,cancel=modelCancel})
  if Audio then
    Waza:registerHandler("sound","cbe-waza-audio",{
      start=function(...) return Audio:start(...) end,
      update=function(...) return Audio:update(...) end,
      finish=function(...) return Audio:finish(...) end,
      cancel=function(...) return Audio:cancel(...) end})
  end
  for _,kind in ipairs({"type1","type4","type6"}) do
    Waza:registerHandler(kind,"cbe-waza-"..kind,{start=opaqueStart,finish=opaqueFinish,cancel=opaqueFinish})
  end
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

function H.drawWorld(ctx)
  if not (love and love.graphics and CSM and type(CSM.wazaBasis)=="function") then return false end
  local vp=ctx and ctx.services and (ctx.services.stageVP or ctx.services.vp)
  if type(vp)~="table" then return false end
  local g=love.graphics;local jobs={}
  for _,rec in pairs(H.models) do
    local inst,entry=rec.instance,rec.entry
    local originSide=(inst and inst.role=="damage") and inst.target or (inst and inst.side)
    local otherSide=originSide==(inst and inst.side) and (inst and inst.target) or (inst and inst.side)
    local okBasis,basis=pcall(CSM.wazaBasis,CSM,ctx,originSide,otherSide,entry and entry.attachment,{
      moveId=inst and inst.moveId,style=inst and inst.spec and inst.spec.style,role=inst and inst.role})
    local frac=(tonumber(inst and inst.accumulator) or 0)*60
    local localFrame=(tonumber(inst and inst.frame) or 0)+frac-(tonumber(rec.state and rec.state.startFrame) or tonumber(rec.startedFrame) or 0)
    local model,err,page=loadModel(rec.asset,localFrame)
    if okBasis and basis and model then jobs[#jobs+1]={rec=rec,basis=basis,model=model,page=page,localFrame=localFrame}
    elseif err then H.drawError=tostring(err) end
  end
  if #jobs==0 then return false end
  local drew=false
  local ok,value,scopeErr=graphicsScope(g,function()
    local function pass(kind)
      if kind=="add" then pcall(g.setBlendMode,"add","alphamultiply")
      else pcall(g.setBlendMode,"alpha","alphamultiply") end
      for _,job in ipairs(jobs) do
        local sh,serr=ensureShader(job.model.morph)
        if sh then
          local okJob,jobErr=pcall(function()
            g.setShader(sh);sh:send("vp","row",vp);sh:send("model","row",modelMatrix(job.basis,job.model))
            if job.model.morph then
              local weights=morphWeights(job.page,job.localFrame)
              for wi=0,12 do sh:send("w"..wi,weights[wi+1] or 0) end
            end
            for _,grp in ipairs(job.model.groups) do
              if not grp._cbeRenderDisabled then
                local class=grp.luminous and "add" or (grp.xlu and "alpha" or "solid")
                if class==kind then
                  local okGrp,grpErr=pcall(function()
                    local d=grp.diffuse or {1,1,1}
                    sh:send("materialColor",{tonumber(d[1]) or 1,tonumber(d[2]) or 1,tonumber(d[3]) or 1,tonumber(grp.alpha) or 1})
                    sh:send("useTexture",grp.image and 1 or 0);sh:send("opacity",1);sh:send("forceOpaque",0)
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
    moveId=inst.moveId,style=inst.spec and inst.spec.style,role=role})
  if not ok or type(basis)~="table" or type(basis.origin)~="table" or type(basis.target)~="table" then return nil end

  local src,dst=basis.origin,basis.target
  local forward=type(basis.forward)=="table" and basis.forward or {0,0,-1}
  local right=type(basis.right)=="table" and basis.right or {1,0,0}
  local frame=(tonumber(inst.frame) or 0)+(tonumber(inst.accumulator) or 0)*60
  local total=math.max(1,tonumber(inst.sourceEndFrame) or 1)
  local p=math.max(0,math.min(1,frame/total));local sp=csmooth(p)
  local style=tostring(inst.spec and inst.spec.style or "impact"):lower()
  local fight=math.max(10,tonumber(basis.fightDistance) or cdist(src,dst))
  local sh=math.max(2.8,tonumber(basis.sourceVisualHeight) or 5.5)
  local th=math.max(2.8,tonumber(basis.targetVisualHeight) or sh)
  local avgH=(sh+th)*.5
  local focus,eye,fov=clerp(src,dst,.5),nil,SOURCE_CAMERA_FOV

  if role=="damage" then
    -- Damage Waza rows are authored around the struck Pokemon. Keep the target
    -- large enough to read the source hit model/particles and use a short,
    -- deterministic impact vibration rather than allowing the semantic camera
    -- to cut away from the Waza while it is still active.
    focus={src[1],src[2]+sh*.05,src[3]}
    local pulse=math.max(0,1-math.abs(p-.20)/.20)
    local shake=math.sin(frame*1.77)*avgH*.025*pulse
    eye=offsetEye(focus,forward,right,fight*.29,fight*.22+shake,sh*.52+math.cos(frame*1.31)*avgH*.012*pulse)
    fov=math.rad(35.5)
  elseif style=="projectile" then
    -- Track along the actual source attachment->target line. Lead the effect a
    -- little rather than orbiting either Pokemon, matching Colosseum's readable
    -- side-on projectile staging.
    local t=csmooth(math.max(0,math.min(1,(p-.04)/.88)))
    focus=clerp(src,dst,t)
    local lead=clerp(focus,dst,.12)
    focus={lead[1],lead[2]+avgH*.03,lead[3]}
    eye=offsetEye(focus,forward,right,fight*.18,fight*(.34-.07*t),avgH*(.58-.08*t))
    fov=math.rad(36.5+2.0*t)
  elseif style=="wave" then
    local t=csmooth(math.max(0,math.min(1,(p-.06)/.82)))
    focus=clerp(src,dst,.30+.42*t);focus[2]=focus[2]+avgH*.02
    eye=offsetEye(focus,forward,right,fight*.17,fight*.37,avgH*.68)
    fov=math.rad(40.0)
  elseif style=="contact" then
    local t=csmooth(p)
    focus=clerp(src,dst,.18+.72*t);focus[2]=focus[2]+avgH*.04
    local impact=math.max(0,1-math.abs(p-.68)/.18)
    eye=offsetEye(focus,forward,right,fight*(.23-.07*t),fight*(.28-.07*t)+math.sin(frame*1.9)*avgH*.016*impact,avgH*(.50-.10*t))
    fov=math.rad(36.0-1.5*impact)
  elseif style=="aura" or style=="self" then
    focus={src[1],src[2]+sh*.08,src[3]}
    local drift=math.sin(sp*math.pi)*fight*.045
    eye=offsetEye(focus,forward,right,fight*.30,fight*.26+drift,sh*.62)
    fov=math.rad(34.5)
  elseif style=="target" then
    focus={dst[1],dst[2]+th*.05,dst[3]}
    eye=offsetEye(focus,forward,right,fight*.28,-fight*.25,th*.57)
    fov=math.rad(35.5)
  else -- impact / unknown source style
    local t=csmooth(math.max(0,math.min(1,p/.72)))
    focus=clerp(src,dst,.40+.55*t);focus[2]=focus[2]+avgH*.04
    local impact=math.max(0,1-math.abs(p-.62)/.20)
    eye=offsetEye(focus,forward,right,fight*.25,-fight*(.25-.04*t)+math.sin(frame*1.83)*avgH*.018*impact,avgH*.56)
    fov=math.rad(36.0)
  end

  return {eye=eye,focus=focus,fov=fov,sourceSerial=inst.serial,sourceFrame=frame,sourceProgress=p,
    sourceStyle=style,sourceRole=role,blend=.20}
end
function H.activeModels() local out={};for _,row in pairs(H.models) do out[#out+1]=row end;return out end
function H.finish() H.models={};return true end
function H.status()
  local m=0;for _ in pairs(H.models) do m=m+1 end
  local cached=0;for _,v in pairs(H.modelCache) do if v then cached=cached+1 end end
  return {installed=H.installed,activeModels=m,cachedModels=cached,opaqueEntries=#H.opaque,drawError=H.drawError,renderFaults=H.renderFaults or 0,
    provenSourceTypes={model=2,particle=3,sound=5},opaqueSourceTypes={1,4,6},
    cameraDecoder="WazaSequence source-timeline + live source fight geometry + fight_common CObj baseline lens; remaining raw controller subtype pending",
    modelDecoder="native-HSD-60Hz-morph-pages-v4-safe-tev-pass"}
end
return H
