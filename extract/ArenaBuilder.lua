local V=...
local HSD,FSYS=V and V.HSD,V and V.FSYS
local A={arenaRevision=16}
local floor,abs,sin,cos=math.floor,math.abs,math.sin,math.cos
local SPECS={
  ["cache/stages/d2_crater/textures/tex_0f4120_128x128_f14.rgba"]={128,128,"metal"},
  ["cache/stages/d2_crater/textures/tex_07cec0_128x64_f14.rgba"]={128,64,"trim"},
  ["cache/stages/d2_crater/textures/tex_0ce920_256x256_f14.rgba"]={256,256,"rock"},
  ["cache/stages/d2_crater/textures/tex_061ec0_256x256_f14.rgba"]={256,256,"rock_dark"},
  ["cache/stages/d2_crater/textures/tex_0ca920_128x256_f14.rgba"]={128,256,"lava"},
  ["cache/stages/d2_crater/textures/tex_0ea920_128x128_f14.rgba"]={128,128,"lava_hot"},
  ["cache/stages/d2_crater/textures/tex_0fd8e0_256x256_f14.rgba"]={256,256,"truss"},
  ["cache/stages/d2_crater/textures/tex_0c2120_256x256_f14.rgba"]={256,256,"sky"},
  ["cache/stages/d2_crater/textures/tex_0d6920_128x128_f1.rgba"]={128,128,"cloud"},
  ["cache/stages/wildlands/ground_meadow_128.rgba"]={128,128,"meadow"},
  ["cache/stages/wildlands/ground_forest_128.rgba"]={128,128,"forest"},
  ["cache/stages/wildlands/bark_128.rgba"]={128,128,"bark"},
  ["cache/stages/wildlands/leaf_cluster_a_128.rgba"]={128,128,"leaf1"},
  ["cache/stages/wildlands/leaf_cluster_b_128.rgba"]={128,128,"leaf2"},
  ["cache/stages/wildlands/leaf_cluster_c_128.rgba"]={128,128,"leaf3"},
}
local PACKAGED_TEXTURES={
  ["cache/stages/wildlands/ground_meadow_128.rgba"]="assets/cbe/wildlands/ground_meadow_128.rgba",
  ["cache/stages/wildlands/ground_forest_128.rgba"]="assets/cbe/wildlands/ground_forest_128.rgba",
  ["cache/stages/wildlands/bark_128.rgba"]="assets/cbe/wildlands/bark_128.rgba",
  ["cache/stages/wildlands/leaf_cluster_a_128.rgba"]="assets/cbe/wildlands/leaf_cluster_a_128.rgba",
  ["cache/stages/wildlands/leaf_cluster_b_128.rgba"]="assets/cbe/wildlands/leaf_cluster_b_128.rgba",
  ["cache/stages/wildlands/leaf_cluster_c_128.rgba"]="assets/cbe/wildlands/leaf_cluster_c_128.rgba",
}
local ARENAS={
  {cache="cache/M1_water_cache.lua",id="water",label="WATER COLOSSEUM",
    sourceFsys="M1_water_colo.fsys",sourceMember="M1_water_colo.dat",textureRoot="cache/stages/water/source",
    minVertices=40000,minGroups=150,maxVertices=240000,maxDisplayOps=1200000,maxSceneRoots=32,maxJobjs=12000,maxDobjs=36000,maxPobjs=60000,
    crowdOffsets={[0x0d5b60]=true,[0x0ddb60]=true}},
  {cache="cache/orre_colosseum_cache.lua",id="orre_colosseum",label="ORRE COLOSSEUM",
    sourceFsys="T1_ancient_colo.fsys",sourceMember="T1_ancient_colo.dat",textureRoot="cache/stages/orre/source",
    minVertices=35000,minGroups=35,maxVertices=280000,maxDisplayOps=1600000,maxSceneRoots=32,maxJobjs=18000,maxDobjs=54000,maxPobjs=90000,
    crowdOffsets={[0x10f240]=true,[0x111240]=true}},
  {cache="cache/M3_shrine_1F_bf_cache.lua",id="relic_chamber",label="RELIC CHAMBER",
    sourceFsys="M3_shrine_1F_bf.fsys",sourceMember="M3_shrine_1F_bf.dat",textureRoot="cache/stages/relic_chamber/source",
    -- The retail forest has nested nonuniform scales with inverse child
    -- rotations. HSD parent-scale compensation preserves those authored shapes;
    -- ordinary SRT composition sheared the trees/leaves into giant sheets. Keep
    -- all native scene groups instead of deleting their overlapping bounds.
    honorRenderPass=true,skipShadowMaterials=true,nativeScaleCompensation=true,
    minVertices=2000,minGroups=8,maxVertices=360000,maxDisplayOps=1900000,maxSceneRoots=40,maxJobjs=22000,maxDobjs=66000,maxPobjs=110000},
  {cache="cache/M3_cave_1F_1_bf_cache.lua",id="relic_cave",label="RELIC CAVE",
    sourceFsys="M3_cave_1F_1_bf.fsys",sourceMember="M3_cave_1F_1_bf.dat",textureRoot="cache/stages/relic_cave/source",
    nativeScaleCompensation=true,
    minVertices=2000,minGroups=8,maxVertices=280000,maxDisplayOps=1500000,maxSceneRoots=32,maxJobjs=16000,maxDobjs=48000,maxPobjs=80000},
  {cache="cache/S1_out_bf_cache.lua",id="outskirts",label="OUTSKIRTS",
    sourceFsys="S1_out_bf.fsys",sourceMember="S1_out_bf.dat",textureRoot="cache/stages/outskirts/source",
    honorRenderPass=true,skipShadowMaterials=true,
    minVertices=2000,minGroups=8,maxVertices=340000,maxDisplayOps=1800000,maxSceneRoots=36,maxJobjs=20000,maxDobjs=60000,maxPobjs=100000},
  {cache="cache/M2_earth_colo_cache.lua",id="pyrite_colosseum",label="PYRITE COLOSSEUM",
    sourceFsys="M2_earth_colo.fsys",sourceMember="M2_earth_colo.dat",textureRoot="cache/stages/pyrite/source",
    minVertices=8000,minGroups=20,maxVertices=340000,maxDisplayOps=1900000,maxSceneRoots=40,maxJobjs=20000,maxDobjs=60000,maxPobjs=100000},
  {cache="cache/M4_bottom_colo_cache.lua",id="deep_colosseum",label="DEEP COLOSSEUM",
    sourceFsys="M4_bottom_colo.fsys",sourceMember="M4_bottom_colo.dat",textureRoot="cache/stages/deep/source",
    -- Deep is another retail HSD battle scene, not a generic dark room.  Keep
    -- only passes the GameCube would actually submit, otherwise dormant/shadow
    -- carrier geometry fills the outer chamber and reads as the muddy slabs seen
    -- in the 1.9.25-1.9.29 presentation.  Raise the traversal budgets so the
    -- complete rotor/pipe/stand/wall perimeter can survive the canonical cache.
    honorRenderPass=true,skipShadowMaterials=true,
    minVertices=8000,minGroups=20,maxVertices=460000,maxDisplayOps=2600000,maxSceneRoots=64,maxJobjs=30000,maxDobjs=90000,maxPobjs=150000},
  {cache="cache/realgam_colosseum_cache.lua",id="realgam_colosseum",label="REALGAM COLOSSEUM",
    sourceFsys="D4_casino_colo.fsys",sourceMember="D4_casino_colo.dat",textureRoot="cache/stages/realgam/source",
    minVertices=50000,minGroups=100,maxVertices=380000,maxDisplayOps=2100000,maxSceneRoots=40,maxJobjs=22000,maxDobjs=66000,maxPobjs=110000,
    crowdOffsets={[0x0bed60]=true,[0x0c0d60]=true},backdrop={offset=0x09ed60,x=0,y=336,w=512,h=176,path="cache/stages/realgam/source/sky_512x176.rgba"}},
  {cache="cache/D1_labo_B1_bf_cache.lua",id="cipher_lab_underground",label="CIPHER LAB UNDERGROUND",
    sourceFsys="D1_labo_B1_bf.fsys",sourceMember="D1_labo_B1_bf.dat",textureRoot="cache/stages/cipher_lab/source",
    minVertices=30000,minGroups=10,maxVertices=300000,maxDisplayOps=1800000,maxSceneRoots=64,
    maxJobjs=20000,maxDobjs=60000,maxPobjs=100000,honorRenderPass=true,skipShadowMaterials=true},
  {recipe="recipes/arenas/outdoor_wild.lua",cache="cache/outdoor_wild_cache.lua",id="outdoor_wild",label="ORRE WILDLANDS"},
  {cache="cache/D2_mt_battle_platform100_cache.lua",id="mt_battle_summit",label="MT. BATTLE SUMMIT",
    sourceFsys="D2_crater_colo.fsys",sourceMember="D2_crater_colo.dat",textureRoot="cache/stages/d2_crater/textures",
    minVertices=8000,minGroups=20,maxVertices=360000,maxDisplayOps=1900000,maxSceneRoots=40,maxJobjs=18000,maxDobjs=54000,maxPobjs=90000},
}local function clamp(v)return v<0 and 0 or (v>255 and 255 or floor(v+.5)) end
local function rgba(r,g,b,a)return string.char(clamp(r),clamp(g),clamp(b),clamp(a or 255))end
local function hash(s)local h=17;for i=1,#s do h=(h*131+s:byte(i))%104729 end;return h end
local function noise(x,y,seed)return .5+.24*sin((x+seed*.13)*.173)+.16*cos((y-seed*.19)*.137)+.10*sin((x+y+seed)*.071)end
local function checker(x,y,n)return ((floor(x/n)+floor(y/n))%2)==0 and 1 or 0 end
local function makeTexture(path,w,h,kind)
  local out={};local seed=hash(path);local n=0
  local function put(r,g,b,a)n=n+1;out[n]=rgba(r,g,b,a)end
  for y=0,h-1 do for x=0,w-1 do
    local u=x/math.max(1,w-1);local v=y/math.max(1,h-1);local q=noise(x,y,seed);local r,g,b,a=128,128,128,255
    if kind=="metal" then local c=130+55*q+18*checker(x,y,16);r,g,b=c*.88,c*.88,c*.92
    elseif kind=="trim" then local c=115+80*q;r,g,b=c*1.25,c*.82,c*.28
    elseif kind=="truss" then local line=(x%24<4 or y%24<4) and 1 or 0;local c=80+55*q+70*line;r,g,b=c*.75,c*.78,c*.82;a=line==1 and 255 or 0
    elseif kind=="sky" then
      local t=v*v*(3-2*v)
      r=70+(198-70)*t+8*(q-.5);g=80+(205-80)*t+9*(q-.5);b=94+(207-94)*t+11*(q-.5);a=255
    elseif kind=="cloud" then
      local p=.62*q+.24*(.5+.5*sin(x*.055+seed))+.14*(.5+.5*cos(y*.071-seed*.3))
      local c=185+55*p;r,g,b=c,c*.99,c*.97;a=clamp((p-.34)*420)
    elseif kind=="rock" or kind=="rock_dark" then
      -- Organic volcanic relief for Mt. Battle. Keep the texture dense enough
      -- to hold up beside the arena machinery, but avoid any axis-aligned
      -- checker or crossing periodic fields: once this atlas repeats over a
      -- large ridge those patterns read as a literal mesh laid over the rock.
      -- Rotated/warped frequency bands produce strata, mineral breakup and
      -- occasional fissures without a visible square cadence.
      local wx=x+math.sin(y*.031+seed*.017)*9.0+math.sin(y*.009-seed*.023)*5.0
      local wy=y+math.sin(x*.027-seed*.019)*7.0+math.cos(x*.011+seed*.029)*4.0
      local q2=noise(wx*1.37+wy*.23,wy*1.49-wx*.19,seed+37)
      local q3=noise(wx*3.61-wy*.47,wy*3.17+wx*.31,seed+91)
      local mineral=.5+.5*math.sin(wx*.173+wy*.119+math.sin((wx-wy)*.041)*2.1+seed*.071)
      local strata=.5+.5*math.sin(wy*.118+math.sin(wx*.033+seed*.013)*2.55+math.sin((wx+wy)*.014)*1.15)
      local seam=math.abs(math.sin(wx*.052+wy*.021+math.sin(wy*.037)*1.65+seed*.117))
      local fissure=math.max(0,(seam-.905)/.095)
      fissure=fissure*fissure*(3-2*fissure)
      local base=(kind=="rock" and 66 or 43)
      local c=base+45*q+24*q2+12*q3+8*(strata-.5)+5*(mineral-.5)-39*fissure
      local warm=.5+.5*math.sin(wy*.026-wx*.015+seed*.03)
      r=c*(.99+.045*warm);g=c*(.80+.035*strata);b=c*(.77+.032*q3)
    elseif kind=="lava" or kind=="lava_hot" then local wave=.5+.5*sin(x*.11+y*.06+seed);local hot=.55*q+.45*wave;r=190+65*hot;g=45+140*hot;b=8+38*hot
    elseif kind=="meadow" then r,g,b=68+35*q,116+72*q,48+30*q
    elseif kind=="forest" then r,g,b=47+30*q,82+50*q,35+24*q
    elseif kind=="bark" then local stripe=.5+.5*sin(x*.35+seed);r,g,b=72+45*q+20*stripe,48+30*q,30+22*q
    elseif kind:find("leaf",1,true) then
      local dx=(u-.5)*2;local dy=(v-.5)*2;local lobes=.72+.14*sin(math.atan(dy,dx)*5+seed);local d=(dx*dx+dy*dy)^.5;a=d<lobes and clamp(220+35*q) or 0;r,g,b=48+45*q,105+90*q,35+42*q
    else local c=110+80*q;r,g,b=c,c,c end
    put(r,g,b,a)
  end end
  return table.concat(out)
end
local function textureBytes(mod,path,spec)
  local packaged=PACKAGED_TEXTURES[path]
  if packaged then
    local bytes=assert(mod:read(packaged),"missing CBE-authored texture: "..packaged)
    assert(#bytes==spec[1]*spec[2]*4,("bad CBE-authored texture size: %s"):format(packaged))
    return bytes
  end
  return makeTexture(path,spec[1],spec[2],spec[3])
end
local function write(mod,path,data,generated)local ok,err=mod.cache:write(path,data);assert(ok,err or ("cache write failed: "..path));generated[#generated+1]=path end
local function num(v)
  v=tonumber(v) or 0
  if v~=v or v==math.huge or v==-math.huge then return "0" end
  if math.abs(v)<0.00000005 then return "0" end
  return string.format("%.8g",v)
end
local function vec(v)
  if type(v)~="table" then return nil end
  local o={"{"};for i=1,#v do if i>1 then o[#o+1]="," end;o[#o+1]=num(v[i]) end;o[#o+1]="}";return table.concat(o)
end
-- Append a vector straight into the output buffer. vec() built a throwaway
-- table and ran table.concat for EVERY vertex of an arena; at hundreds of
-- thousands of vertices per venue that dominated the write stage's garbage.
-- Produces exactly the same characters as vec().
local function vecInto(out,n,v)
  n=n+1;out[n]="{"
  for i=1,#v do
    if i>1 then n=n+1;out[n]="," end
    n=n+1;out[n]=num(v[i])
  end
  n=n+1;out[n]="}"
  return n
end
local function serializeSourceArena(model,source,crowdOriginal)
  local out={"-- Generated from the user-supplied Pokemon Colosseum GC6E01 disc.\nreturn {version=33,source=",string.format("%q",source),",prototype=false,"}
  if model.textureStateVersion then out[#out+1]="textureStateVersion="..num(model.textureStateVersion).."," end
  local b=model.bounds or {};out[#out+1]="bounds={min="..(vec(b.min) or "{0,0,0}")..",max="..(vec(b.max) or "{0,0,0}").."},"
  out[#out+1]="groupCount="..tostring(#(model.groups or {}))..",vertexCount="..tostring(tonumber(model.vertexCount) or 0)..","
  out[#out+1]="crowdOriginal="..tostring(crowdOriginal or 0)..",crowdPolicy="..string.format("%q",model.crowdPolicy or "source-hsd-crowd")..",groups={\n"
  for _,g in ipairs(model.groups or {}) do
    out[#out+1]="{"
    if g.texture then
      out[#out+1]="texture={path="..string.format("%q",g.texture.path)..",w="..tostring(g.texture.w)..",h="..tostring(g.texture.h)
      if g.texture.wrapS~=nil then out[#out+1]=",wrapS="..tostring(g.texture.wrapS) end
      if g.texture.wrapT~=nil then out[#out+1]=",wrapT="..tostring(g.texture.wrapT) end
      for _,key in ipairs({"coordinateMode","colorMap","alphaMap","blending"}) do
        if g.texture[key]~=nil then out[#out+1]=","..key.."="..num(g.texture[key]) end
      end
      out[#out+1]="},"
    end
    out[#out+1]="alpha="..num(g.alpha or 1)..",xlu="..tostring(g.xlu and true or false)..",noz="..tostring(g.noz and true or false)..","
    out[#out+1]="renderFlags="..tostring(tonumber(g.renderFlags) or 0)..",effect="..tostring(g.effect and true or false)
      ..",useConstant="..tostring(g.useConstant and true or false)..",useVertexColor="..tostring(g.useVertexColor and true or false)
      ..",useDiffuseLighting="..tostring(g.useDiffuseLighting and true or false)..",textureSlot="..tostring(tonumber(g.textureSlot) or -1)..","
    if g.diffuse then out[#out+1]="diffuse="..vec(g.diffuse).."," end
    if g.ambient then out[#out+1]="ambient="..vec(g.ambient).."," end
    if g.specular then out[#out+1]="specular="..vec(g.specular).."," end
    if g.shininess then out[#out+1]="shininess="..num(g.shininess).."," end
    out[#out+1]="vertices={"
    local n=#out
    for _,v in ipairs(g.vertices or {}) do n=vecInto(out,n,v);n=n+1;out[n]="," end
    n=n+1;out[n]="}},\n"
  end
  out[#out+1]="}}\n";return table.concat(out)
end
local function cropRGBA(bytes,w,h,x,y,cw,ch)
  x,y,cw,ch=tonumber(x) or 0,tonumber(y) or 0,tonumber(cw) or w,tonumber(ch) or h
  assert(x>=0 and y>=0 and cw>0 and ch>0 and x+cw<=w and y+ch<=h,"invalid source texture crop")
  local rows={};local stride=w*4
  for yy=0,ch-1 do
    local first=(y+yy)*stride+x*4+1
    rows[#rows+1]=bytes:sub(first,first+cw*4-1)
  end
  return table.concat(rows)
end
local function sourceGroupFilter(spec)
  if not spec.sourceRadius then return nil end
  return function(rows,mat)
    local minx,maxx,miny,maxy,minz,maxz=1e30,-1e30,1e30,-1e30,1e30,-1e30
    local sx,sy,sz,n=0,0,0,0
    for _,v in ipairs(rows or {}) do
      local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
      sx=sx+x;sy=sy+y;sz=sz+z;n=n+1
      minx=math.min(minx,x);maxx=math.max(maxx,x);miny=math.min(miny,y);maxy=math.max(maxy,y);minz=math.min(minz,z);maxz=math.max(maxz,z)
    end
    if n==0 then return false end
    local cx,cy,cz=sx/n,sy/n,sz/n
    local ex,ey,ez=maxx-minx,maxy-miny,maxz-minz
    local span=math.max(ex,ey,ez)

    if spec.keepHighBackdrop and cy>500 and span>3000 then return true end
    if spec.sourceRadius then
      local radial=math.sqrt(cx*cx+cz*cz)
      if radial>spec.sourceRadius or span>(spec.sourceMaxSpan or 1e30) then return false end
    end
    return true
  end
end

-- Runtime arena sidecars are part of the generated cache, not a first-view
-- optimization. The canonical Lua remains the debuggable/authoritative source,
-- but shipping only that source forces a weak device to parse hundreds of
-- thousands of numeric literals, reconstruct normals and rebucket materials at
-- the exact moment a battle scene is opening. Mirror Arena.lua's pure geometry
-- preparation here so every venue can enter from packed float32 on its FIRST
-- runtime load as well as every later one.
local ARENA_RUNTIME_MESH_VERSION=7
local ARENA_RUNTIME_SETTINGS={
  -- Wide source envelopes retain architecture/background depth; runtime still
  -- rejects pathological helper geometry and writes compact f32 sidecars.
  cipher_lab_underground={sceneRadiusRaw=1800,maxGroupSpanRaw=4000,vertexRadiusRaw=1750},
  water={sceneRadiusRaw=1100,maxGroupSpanRaw=2600,vertexRadiusRaw=1050},
  orre_colosseum={sceneRadiusRaw=3200,maxGroupSpanRaw=7200,vertexRadiusRaw=3100},
  relic_chamber={sceneRadiusRaw=7800,maxGroupSpanRaw=20000,vertexRadiusRaw=7400},
  relic_cave={sceneRadiusRaw=2800,maxGroupSpanRaw=6800,vertexRadiusRaw=2700},
  outskirts={sceneRadiusRaw=16000,maxGroupSpanRaw=42000,vertexRadiusRaw=15000},
  pyrite_colosseum={sceneRadiusRaw=3600,maxGroupSpanRaw=8600,vertexRadiusRaw=3500},
  deep_colosseum={sceneRadiusRaw=12000,maxGroupSpanRaw=32000,vertexRadiusRaw=11500},
  outdoor_wild={sceneRadiusRaw=620,maxGroupSpanRaw=1350,vertexRadiusRaw=610},
  realgam_colosseum={sceneRadiusRaw=4400,maxGroupSpanRaw=9000,vertexRadiusRaw=4300},
  mt_battle_summit={sceneRadiusRaw=7000,maxGroupSpanRaw=15000,vertexRadiusRaw=6900},
}
local runtimeUnpack=table.unpack or unpack
local function runtimeSafeId(id)return tostring(id or "water"):gsub("[^%w_%-]","_")end
local function runtimeRoot(id)return "cache/runtime_mesh_v7/arenas/"..runtimeSafeId(id)end
local function runtimeMetaPath(id)return runtimeRoot(id).."/scene.lua"end
local function runtimeBinPath(id,bucket,i)return runtimeRoot(id)..("/%s_%03d.f32"):format(tostring(bucket),tonumber(i) or 0)end
local function runtimeRead(mod,path)
  local ok,v=pcall(mod.cache.read,mod.cache,path);if ok and type(v)=="string" then return v end
end
local function runtimeInfo(mod,path)
  local ok,v=pcall(mod.cache.info,mod.cache,path);if ok and type(v)=="table" then return v end
end
local function runtimeReadLua(mod,path)
  local src=runtimeRead(mod,path);if not src then return nil end
  local f=load(src,"@generated/"..path);if not f then return nil end
  local ok,v=pcall(f);if ok then return v end
end
local function runtimeUsable(mod,meta,spec,sourceSize,sourceFingerprint)
  if type(meta)~="table" or tonumber(meta.runtimeMeshVersion)~=ARENA_RUNTIME_MESH_VERSION then return false end
  if tonumber(meta.sourceSize)~=tonumber(sourceSize) or tostring(meta.sourceCache or "")~=tostring(spec.cache or "") then return false end
  if not sourceFingerprint or meta.sourceFingerprint~=sourceFingerprint then return false end
  if spec.id=="water" and meta.audienceRevision~=2 then return false end
  local total=0
  for _,bucket in ipairs({"opaque","cutout","crowd","translucent","additive"}) do
    local rows=meta[bucket];if type(rows)~="table" then return false end
    for i,g in ipairs(rows) do
      local path=type(g)=="table" and (g.runtimeBin or runtimeBinPath(spec.id,bucket,i)) or nil
      local info=path and runtimeInfo(mod,path) or nil;if not info then return false end;local size=tonumber(info.size)
      if size and (size<144 or size%48~=0) then return false end
      total=total+1
    end
  end
  return total>0
end
local function runtimeAlphaInfo(bytes)
  local hasZero,hasFraction=false,false
  for i=4,#(bytes or ""),4 do local a=bytes:byte(i);if a==0 then hasZero=true elseif a and a<255 then hasFraction=true;break end end
  return hasZero and not hasFraction,hasFraction
end
local function runtimeGroupStats(vertices)
  local x,y,z,n=0,0,0,0
  local minx,maxx,miny,maxy,minz,maxz=math.huge,-math.huge,math.huge,-math.huge,math.huge,-math.huge
  for _,v in ipairs(vertices or {}) do
    local vx,vy,vz=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    x=x+vx;y=y+vy;z=z+vz;n=n+1
    minx=math.min(minx,vx);maxx=math.max(maxx,vx);miny=math.min(miny,vy);maxy=math.max(maxy,vy);minz=math.min(minz,vz);maxz=math.max(maxz,vz)
  end
  if n==0 then return {0,0,0},0,{0,0,0} end
  local extent={maxx-minx,maxy-miny,maxz-minz};return {x/n,y/n,z/n},math.max(extent[1],extent[2],extent[3]),extent
end
local function runtimeCrowdPhases(vertices)
  local n=#(vertices or {});if n<3 then return nil end
  local parent={};for i=1,n do parent[i]=i end
  local function find(a)while parent[a]~=a do parent[a]=parent[parent[a]];a=parent[a] end;return a end
  local function union(a,b)a,b=find(a),find(b);if a~=b then parent[b]=a end end
  local first={};local function key(v)return ("%.3f|%.3f|%.3f"):format(tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0) end
  for i,v in ipairs(vertices or {}) do local k=key(v);if first[k] then union(i,first[k]) else first[k]=i end end
  for i=1,n,3 do if vertices[i+2] then union(i,i+1);union(i,i+2) end end
  local comps={}
  for i,v in ipairs(vertices or {}) do local r=find(i);local c=comps[r];if not c then c={sx=0,sy=0,sz=0,n=0,idx={}};comps[r]=c end
    c.sx=c.sx+(tonumber(v[1]) or 0);c.sy=c.sy+(tonumber(v[2]) or 0);c.sz=c.sz+(tonumber(v[3]) or 0);c.n=c.n+1;c.idx[#c.idx+1]=i end
  local phase={}
  for _,c in pairs(comps) do local cx,cy,cz=c.sx/math.max(1,c.n),c.sy/math.max(1,c.n),c.sz/math.max(1,c.n)
    local h=math.sin(cx*.173+cy*.311+cz*.137)*43758.5453;local q=h-math.floor(h);for _,i in ipairs(c.idx) do phase[i]=q end end
  return phase
end
local function runtimeWithNormals(vertices,mode,vertexRadius)
  local out={};local v=vertices or {};local crowdPhase=(mode==4) and runtimeCrowdPhases(v) or nil
  for i=1,#v,3 do local a,b,c=v[i],v[i+1],v[i+2]
    if a and b and c then
      local ar=math.sqrt((a[1] or 0)^2+(a[3] or 0)^2);local br=math.sqrt((b[1] or 0)^2+(b[3] or 0)^2);local cr=math.sqrt((c[1] or 0)^2+(c[3] or 0)^2)
      if math.min(ar,br,cr)<=vertexRadius then
        local abx,aby,abz=(b[1] or 0)-(a[1] or 0),(b[2] or 0)-(a[2] or 0),(b[3] or 0)-(a[3] or 0)
        local acx,acy,acz=(c[1] or 0)-(a[1] or 0),(c[2] or 0)-(a[2] or 0),(c[3] or 0)-(a[3] or 0)
        local nx=aby*acz-abz*acy;local ny=abz*acx-abx*acz;local nz=abx*acy-aby*acx;local len=math.sqrt(nx*nx+ny*ny+nz*nz)
        if len<.000001 then nx,ny,nz=0,1,0 else nx,ny,nz=nx/len,ny/len,nz/len end
        for j,src in ipairs({a,b,c}) do
          local r,g,bv,av=1,1,1,1;local vnx,vny,vnz=nx,ny,nz
          if #src>=12 then
            r,g,bv,av=src[6] or 1,src[7] or 1,src[8] or 1,src[9] or 1
            vnx,vny,vnz=src[10] or nx,src[11] or ny,src[12] or nz
            local nl=math.sqrt(vnx*vnx+vny*vny+vnz*vnz)
            if nl>0.000001 then vnx,vny,vnz=vnx/nl,vny/nl,vnz/nl else vnx,vny,vnz=nx,ny,nz end
          elseif #src>=9 then r,g,bv,av=src[6] or 1,src[7] or 1,src[8] or 1,src[9] or 1
          elseif #src==8 then vnx,vny,vnz=src[6] or nx,src[7] or ny,src[8] or nz;local nl=math.sqrt(vnx*vnx+vny*vny+vnz*vnz);if nl>.000001 then vnx,vny,vnz=vnx/nl,vny/nl,vnz/nl else vnx,vny,vnz=nx,ny,nz end end
          if crowdPhase then
            -- Keep source RGBA intact. Normal direction is unchanged; its
            -- length carries card phase, decoded before shader normalization.
            local scale=1+(crowdPhase[i+j-1] or .5)
            vnx,vny,vnz=vnx*scale,vny*scale,vnz*scale
          end
          out[#out+1]={src[1] or 0,src[2] or 0,src[3] or 0,src[4] or 0,src[5] or 0,r,g,bv,av,vnx,vny,vnz}
        end
      end
    end
  end
  return out
end
local function runtimeSourcePath(g)return g and g.texture and tostring(g.texture.path or "") or ""end
local function runtimeSourceGroundShadow(g,arenaId)
  if (arenaId~="outskirts" and arenaId~="orre_colosseum") or g.texture or not g.xlu or not g.noz then return false end
  local rows=g.vertices or {};if #rows<3 then return false end
  for _,v in ipairs(rows) do
    local y=tonumber(v[2]);if not y or y<-.1 or y>3 then return false end
  end
  return true
end
local function runtimeDropGhost(g,arenaId)
  local path=runtimeSourcePath(g)
  if not g.texture and g.xlu and g.noz then return not runtimeSourceGroundShadow(g,arenaId) end
  if path:find("tex_05db60_",1,true) and g.xlu and g.noz then return true end
  if path:find("cache/stages/orre/source/tex_055ec0_",1,true) then return true end
  if path:find("cache/stages/realgam/source/tex_0d4560_",1,true) and g.xlu and g.noz then return true end
  return false
end
local function runtimeMaterialDetail(g)
  local path=runtimeSourcePath(g)
  -- Do not sharpen source-backed HSD atlases: 1:1 texture fidelity is more
  -- important than synthetic close-detail. Wildlands is intentionally authored.
  if path:find("cache/stages/wildlands/ground_",1,true) or path:find("cache/stages/wildlands/bark_",1,true) then return 1 end
  return 0
end
local function runtimeMaterialMode(g,binaryAlpha,arenaId)
  local path=runtimeSourcePath(g)
  if binaryAlpha and path:find("cache/stages/d2_crater/textures/tex_0fd8e0_",1,true) then return 3 end
  if binaryAlpha and (path:find("cache/stages/wildlands/leaf_cluster_",1,true) or path:find("cache/stages/wildlands/grass_tuft_",1,true)) then return 3.25 end
  if path:find("cache/stages/d2_crater/textures/tex_0ca920_",1,true) or path:find("cache/stages/d2_crater/textures/tex_0be120_",1,true) or path:find("cache/stages/d2_crater/textures/tex_0ea920_",1,true) then return 5 end
  if path:find("cache/stages/d2_crater/textures/tex_0ce920_",1,true) or path:find("cache/stages/d2_crater/textures/tex_061ec0_",1,true) or path:find("cache/stages/d2_crater/textures/tex_0f4120_",1,true) or path:find("cache/stages/d2_crater/textures/tex_07cec0_",1,true) then return 0 end
  if path:find("tex_0cbb60_",1,true) then return 2 end
  if path:find("tex_0cdb60_",1,true) or path:find("tex_081b60_",1,true) then return 1 end
  if binaryAlpha and V.ArenaAudienceProfile and V.ArenaAudienceProfile.classifySourceTexture(arenaId,path) then return 4 end
  if binaryAlpha and (path:find("tex_05c560_",1,true) or path:find("/source/",1,true)) then return 3 end
  return 0
end
local function runtimePackRows(rows)
  if not (love and love.data and type(love.data.pack)=="function") then return nil,"love.data.pack unavailable" end
  local stride=12;local rowFmt=string.rep("f",stride);local batch=64;local batchFmt=string.rep(rowFmt,batch);local buf,chunks={},{};local i=1
  while i<=#rows do local take=math.min(batch,#rows-i+1);local k=0
    for r=i,i+take-1 do local row=rows[r];for j=1,stride do local v=tonumber(row[j]) or 0;if v~=v or v==math.huge or v==-math.huge then v=0 end;k=k+1;buf[k]=v end end
    local ok,bytes=pcall(love.data.pack,"string",take==batch and batchFmt or string.rep(rowFmt,take),runtimeUnpack(buf,1,k));if not ok or type(bytes)~="string" then return nil,tostring(bytes) end
    chunks[#chunks+1]=bytes;i=i+take
  end
  return table.concat(chunks)
end
local function runtimeKeySort(a,b)local ta,tb=type(a),type(b);if ta==tb then return tostring(a)<tostring(b) end;return ta<tb end
local function runtimeSerialize(v,seen,depth)
  local t=type(v);if t=="nil" then return "nil" elseif t=="boolean" then return v and "true" or "false" elseif t=="number" then return num(v) elseif t=="string" then return string.format("%q",v) elseif t~="table" then return "nil" end
  depth=(depth or 0)+1;if depth>24 then return "nil" end;seen=seen or {};if seen[v] then return "nil" end;seen[v]=true
  local keys={};for k in pairs(v) do if type(k)=="string" or type(k)=="number" then keys[#keys+1]=k end end;table.sort(keys,runtimeKeySort)
  local out={"{"};for _,k in ipairs(keys) do local ks=type(k)=="number" and ("["..num(k).."]") or ("["..string.format("%q",k).."]");out[#out+1]=ks.."="..runtimeSerialize(v[k],seen,depth).."," end
  out[#out+1]="}";seen[v]=nil;return table.concat(out)
end
local function runtimeCompactEntry(g,textureSpec,bin)
  return {runtimeBin=bin,texture=textureSpec,alpha=g.alpha,noz=g.noz,center=g.center,span=g.span,extent=g.extent,mode=g.mode,flow=g.flow,detail=g.detail,texelStep=g.texelStep,
    diffuse=g.diffuse,ambient=g.ambient,specular=g.specular,shininess=g.shininess,renderFlags=g.renderFlags,effect=g.effect,
    useConstant=g.useConstant,useVertexColor=g.useVertexColor,useDiffuseLighting=g.useDiffuseLighting,textureSlot=g.textureSlot}
end
local function writeRuntimeSidecarFromCache(mod,spec,cache,sourceSize,generated,progress,sourceFingerprint)
  local settings=ARENA_RUNTIME_SETTINGS[spec.id] or ARENA_RUNTIME_SETTINGS.water
  local runtimeRows={opaque={},cutout={},crowd={},translucent={},additive={}};local textureAlpha={}
  local culled,oversizeCulled,crowdOutliers,crowdKept=0,0,0,0
  for gi,g in ipairs(cache.groups or {}) do
    if progress and (gi==1 or gi%24==0 or gi==#cache.groups) then progress((spec.label or spec.id:upper()).." / RUNTIME MESH",gi,#cache.groups) end
    local center,span,extent=runtimeGroupStats(g.vertices);local radial=math.sqrt((center[1] or 0)^2+(center[3] or 0)^2)
    if radial>settings.sceneRadiusRaw or span>settings.maxGroupSpanRaw or runtimeDropGhost(g,spec.id) then culled=culled+1;if span>settings.maxGroupSpanRaw then oversizeCulled=oversizeCulled+1 end
    else
      local path=g.texture and g.texture.path;local binaryAlpha=false
      if path then
        local known=textureAlpha[path]
        if known==nil then local bytes=runtimeRead(mod,path);known=bytes and select(1,runtimeAlphaInfo(bytes)) or false;textureAlpha[path]=known end
        binaryAlpha=known==true
      end
      local mode=runtimeMaterialMode(g,binaryAlpha,spec.id);local rows=runtimeWithNormals(g.vertices,mode,settings.vertexRadiusRaw)
      if #rows==0 then culled=culled+1
      else
        local detail=runtimeMaterialDetail(g);local tw=(g.texture and tonumber(g.texture.w)) or 1;local th=(g.texture and tonumber(g.texture.h)) or 1
        local maxXZ=math.max((extent and extent[1]) or 0,(extent and extent[3]) or 0);local inferred=((mode==1 or mode==5) and extent and (extent[2] or 0)>math.max(35,maxXZ*1.30)) and 1 or 0
        local flow=(g.flow~=nil) and tonumber(g.flow) or inferred;flow=flow or 0
        if mode>3.10 and mode<3.40 then local wp=tostring(g.texture and g.texture.path or "");flow=wp:find("grass_tuft_",1,true) and 1 or .35 end
        local entry={alpha=tonumber(g.alpha) or 1,noz=g.noz and true or false,center=center,span=span,extent=extent,mode=mode,flow=flow,detail=detail,texelStep={1/math.max(1,tw),1/math.max(1,th)},diffuse=g.diffuse or {1,1,1},ambient=g.ambient or {1,1,1},specular=g.specular or {0,0,0},shininess=tonumber(g.shininess) or 0,renderFlags=tonumber(g.renderFlags) or 0,effect=g.effect and true or false,useConstant=g.useConstant and true or false,useVertexColor=g.useVertexColor and true or false,useDiffuseLighting=g.useDiffuseLighting~=false,textureSlot=tonumber(g.textureSlot) or -1}
        local bucket
        if mode==2 then bucket="additive" elseif mode==1 then bucket="translucent" elseif mode==4 then
          local cpath=tostring(g.texture and g.texture.path or "");if cache.crowdPolicy=="source-hsd-crowd" or spec.id~="water" or (center[2] or 0)<=84 then bucket="crowd" else culled=culled+1;crowdOutliers=crowdOutliers+1 end
        elseif mode>=3 and mode<3.5 then bucket="cutout" elseif not g.xlu then bucket="opaque" else bucket="translucent" end
        if bucket then
          local ri=#runtimeRows[bucket]+1;local bin=runtimeBinPath(spec.id,bucket,ri);local bytes,perr=runtimePackRows(rows);assert(bytes,perr or "arena runtime pack failed")
          write(mod,bin,bytes,generated);runtimeRows[bucket][ri]=runtimeCompactEntry(entry,g.texture,bin);if bucket=="crowd" then crowdKept=crowdKept+1 end
        end
      end
    end
  end
  local meta={runtimeMeshVersion=ARENA_RUNTIME_MESH_VERSION,audienceRevision=2,textureStateVersion=cache.textureStateVersion,sourceFingerprint=sourceFingerprint,sourceSize=sourceSize,sourceCache=spec.cache,bounds=cache.bounds,source=cache.source,
    culled=culled,oversizeCulled=oversizeCulled,crowdOutliers=crowdOutliers,crowdOriginal=tonumber(cache.crowdOriginal) or 0,crowdKept=crowdKept,
    crowdPolicy=cache.crowdPolicy or "none",opaque=runtimeRows.opaque,cutout=runtimeRows.cutout,crowd=runtimeRows.crowd,translucent=runtimeRows.translucent,additive=runtimeRows.additive}
  write(mod,runtimeMetaPath(spec.id),"return "..runtimeSerialize(meta).."\n",generated)
  return true
end
function A.runtimeSidecars(mod,progress,generated)
  generated=generated or {};progress=progress or function()end
  local built,kept=0,0
  for i,spec in ipairs(ARENAS) do
    local src=assert(runtimeRead(mod,spec.cache),"missing arena source cache for runtime sidecar: "..tostring(spec.cache));local sourceSize=#src;local sourceFingerprint=assert(V.ArenaCacheIdentity,"arena cache identity module missing").fingerprint(src)
    local prior=runtimeReadLua(mod,runtimeMetaPath(spec.id))
    if runtimeUsable(mod,prior,spec,sourceSize,sourceFingerprint) then kept=kept+1;progress((spec.label or spec.id:upper()).." / RUNTIME MESH REUSED",i,#ARENAS)
    else
      progress((spec.label or spec.id:upper()).." / RUNTIME MESH PREP",i-1,#ARENAS)
      local chunk,err=load(src,"@generated/"..spec.cache);assert(chunk,err);local ok,cache=pcall(chunk);assert(ok and type(cache)=="table",cache or "invalid arena cache")
      writeRuntimeSidecarFromCache(mod,spec,cache,sourceSize,generated,progress,sourceFingerprint);cache=nil;built=built+1
    end
  end
  write(mod,"build/arena_runtime_sidecars.lua",("return {version=%d,built=%d,reused=%d,total=%d}\n"):format(ARENA_RUNTIME_MESH_VERSION,built,kept,#ARENAS),generated)
  return {ready=true,built=built,reused=kept,total=#ARENAS}
end

local function buildSourceArenaFromDisc(mod,disc,progress,generated,spec)
  assert(HSD and FSYS,"source HSD arena extractor unavailable")
  local file=assert(disc:file(spec.sourceFsys),spec.sourceFsys.." missing from GC6E01")
  local arc=FSYS.open(disc,file)
  local entry=arc:member(spec.sourceMember) or arc:member((spec.sourceMember or ""):gsub("%.dat$",""))
  if not (entry and entry.modelKind) then
    for _,e in ipairs(arc:modelEntries()) do if e.fileType==0x02 then entry=e;break end end
  end
  assert(entry and entry.modelKind,(spec.sourceMember or spec.id).." model member missing")
  local label=spec.label or spec.id:upper()
  progress(label.." / DECOMPRESS",0,3)
  local blob=arc:extract(entry,{maxOutput=64*1024*1024,progress=function(c,t) progress(label.." / DECOMPRESS",c,t) end})
  progress(label.." / HSD SCENE",1,3)
  local model,err=HSD.extractSceneModel(blob,{
    preserveVertexColors=true,textures=true,sourceTextureState=true,nativeSceneInstances=true,maxSceneRoots=spec.maxSceneRoots or 16,maxVertices=spec.maxVertices or 180000,
    maxDisplayOps=spec.maxDisplayOps or 700000,maxJobjs=spec.maxJobjs or 6000,
    maxDobjs=spec.maxDobjs or 16000,maxPobjs=spec.maxPobjs or 28000,
    groupFilter=sourceGroupFilter(spec),
    honorRenderPass=spec.honorRenderPass==true,
    skipShadowMaterials=spec.skipShadowMaterials==true,
    -- Relic's deeply nested nonuniform scales require native HSD parent-scale
    -- compensation. Naive SRT sheared leaves/trees into enormous foreground
    -- sheets; deleting those groups then removed most of its forest backdrop.
    nativeScaleCompensation=spec.nativeScaleCompensation==true,
    progress=function(c,t) progress(("%s / MODELSET %d"):format(label,c),c,t) end,
  })
  assert(model,err or (label.." HSD scene decode failed"))
  assert((model.vertexCount or 0)>=(spec.minVertices or 1) and #(model.groups or {})>=(spec.minGroups or 1),
    ("%s source scene unexpectedly small (%d vertices / %d groups)"):format(label,model.vertexCount or 0,#(model.groups or {})))
  local written,textureCount,crowdOriginal={},0,0
  local backdropWritten=false
  for _,g in ipairs(model.groups) do
    local t=g.texture
    if t and t.rgba and t.dataOffset then
      local path=("%s/tex_%06x_%dx%d_f%d.rgba"):format(spec.textureRoot,t.dataOffset,t.w,t.h,t.format or 0)
      if not written[path] then
        write(mod,path,t.rgba,generated);written[path]=true;textureCount=textureCount+1
      end
      if V.ArenaAudienceProfile and V.ArenaAudienceProfile.classifySourceTexture(spec.id,path) then crowdOriginal=crowdOriginal+1 end
      if spec.backdrop and not backdropWritten and t.dataOffset==spec.backdrop.offset then
        local b=spec.backdrop
        write(mod,b.path,cropRGBA(t.rgba,t.w,t.h,b.x,b.y,b.w,b.h),generated)
        backdropWritten=true
      end
      g.texture={path=path,w=t.w,h=t.h,wrapS=t.wrapS,wrapT=t.wrapT,
        coordinateMode=t.coordinateMode,colorMap=t.colorMap,alphaMap=t.alphaMap,blending=t.blending}
    elseif t then
      g.texture=nil
    end
  end
  if spec.backdrop then assert(backdropWritten,label.." source backdrop texture was not decoded") end
  progress(label.." / SERIALIZE",2,3)
  local source=("Pokemon Colosseum GC6E01 / %s:%s / %d semantic modelsets / %d source textures")
    :format(file.path or spec.sourceFsys,entry.name or spec.sourceMember,model.sceneRoots or 0,textureCount)
  -- Source HSD audience cards retain their exact authored placement. Runtime
  -- depth/cutout handling may animate their pixels, but never re-sectors them.
  model.crowdPolicy="source-hsd-crowd"
  write(mod,spec.cache,serializeSourceArena(model,source,crowdOriginal),generated)
  progress(label.." / READY",3,3)
  return {groups=#model.groups,vertices=model.vertexCount,source=source,textures=textureCount,crowdOriginal=crowdOriginal}
end
function A.repair(mod,disc,progress,generated,options)
  -- The pipeline may request the proven two-scene Relic or instance migration,
  -- but only a complete venue cache may take that scope. Otherwise restore every retail
  -- scene, retain existing Wildlands, and leave actor/audio/FX caches alone.
  local function cacheExists(path)
    if not (mod and mod.cache and type(mod.cache.info)=="function") then return false end
    local ok,info=pcall(mod.cache.info,mod.cache,path)
    return ok and type(info)=="table" and (info.type==nil or info.type=="file")
  end
  local complete=true
  for _,arena in ipairs(ARENAS) do if not cacheExists(arena.cache) then complete=false;break end end
  local requestedScope=options and options.scope
  local scope=complete and (requestedScope=="relic-scenes" or requestedScope=="source-instances") and requestedScope or nil
  local scoped=scope~=nil
  local sourceArenas={}
  for _,arena in ipairs(ARENAS) do if arena.sourceFsys then
    if not scoped or (scope=="relic-scenes" and (arena.id=="relic_chamber" or arena.id=="relic_cave"))
        or (scope=="source-instances" and (arena.id=="water" or arena.id=="deep_colosseum")) then sourceArenas[#sourceArenas+1]=arena end
  end end
  local rebuildWild=not cacheExists("cache/outdoor_wild_cache.lua")
  local total=#sourceArenas+(rebuildWild and 1 or 0)
  local mode=complete and "all-source-colors" or "full"
  if scoped then mode=scope end
  local report={"return {revision="..tostring(A.arenaRevision)..",mode="..string.format("%q",mode)..","}
  local repairLabel=scope=="source-instances" and "WATER + DEEP / SOURCE INSTANCE REFRESH"
    or (scoped and "RELIC CHAMBER + CAVE / SOURCE FIDELITY REFRESH" or "ALL ARENAS / SOURCE COLOR AND MATERIAL REFRESH")
  progress(repairLabel,0,math.max(1,total))
  for step,arena in ipairs(sourceArenas) do
    progress((arena.label or arena.id).." / FULL SOURCE HSD",step-1,math.max(1,total))
    local value=buildSourceArenaFromDisc(mod,disc,progress,generated,arena)
    report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q,textures=%d},",arena.id,arena.cache,tonumber(value.groups) or 0,tonumber(value.vertices) or 0,tostring(value.source or "GC6E01 source"),tonumber(value.textures) or 0)
  end
  if rebuildWild then
    local wild
    for _,arena in ipairs(ARENAS) do if arena.recipe then wild=arena;break end end
    assert(wild,"Wildlands arena recipe missing")
    progress("ORRE WILDLANDS / AUTHORED PARITY",#sourceArenas,math.max(1,total))
    local keys={};for path in pairs(SPECS) do if path:find("cache/stages/wildlands/",1,true) then keys[#keys+1]=path end end;table.sort(keys)
    for _,path in ipairs(keys) do local sp=SPECS[path];write(mod,path,textureBytes(mod,path,sp),generated) end
    local src=assert(mod:read(wild.recipe),"missing arena recipe: "..wild.recipe);local chunk,err=load(src,"@"..wild.recipe);assert(chunk,err)
    local ok,recipe=pcall(chunk);assert(ok,recipe);assert(type(recipe)=="table" and type(recipe.groups)=="table" and #recipe.groups>0,"invalid arena recipe: "..wild.id)
    write(mod,wild.cache,src,generated)
    report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q,textures=%d},",wild.id,wild.cache,#recipe.groups,tonumber(recipe.vertexCount) or 0,tostring(recipe.source or "recipe"),#keys)
  end
  report[#report+1]="}\n";write(mod,"build/arena_repair.lua",table.concat(report),generated)
  progress("ARENA SOURCE FIDELITY READY",math.max(1,total),math.max(1,total));return true
end
function A.run(mod,disc,progress,generated)
  -- Every selectable venue except Wildlands is source-backed; all venue textures are decoded from GC6E01.
  local keys={}
  for p in pairs(SPECS) do
    if p:find("cache/stages/wildlands/",1,true) then keys[#keys+1]=p end
  end
  table.sort(keys)
  for i,p in ipairs(keys)do local sp=SPECS[p];progress("ARENA TEXTURE "..i,i-1,#keys);write(mod,p,textureBytes(mod,p,sp),generated)end
  local report={"return {"}
  for i,a in ipairs(ARENAS)do
    progress("ARENA "..a.id:upper(),i-1,#ARENAS)
    local value
    if a.sourceFsys then
      value=buildSourceArenaFromDisc(mod,disc,progress,generated,a)
    else
      local src=assert(mod:read(a.recipe),"missing arena recipe: "..a.recipe)
      local chunk,err=load(src,"@"..a.recipe);assert(chunk,err);local ok,recipe=pcall(chunk);assert(ok,recipe)
      assert(type(recipe)=="table" and type(recipe.groups)=="table" and #recipe.groups>0,"invalid arena recipe: "..a.id)
      write(mod,a.cache,src,generated);value={groups=#recipe.groups,vertices=tonumber(recipe.vertexCount) or 0,source=tostring(recipe.source or "recipe")}
    end
    report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q},",a.id,a.cache,tonumber(value.groups) or 0,tonumber(value.vertices) or 0,tostring(value.source or "recipe"))
  end
  report[#report+1]="}\n";write(mod,"build/arenas.lua",table.concat(report),generated)
  progress("ARENAS READY",#ARENAS,#ARENAS)
  return true
end
A._test={writeRuntimeSidecar=writeRuntimeSidecarFromCache,arenas=ARENAS,runtimeWithNormals=runtimeWithNormals,runtimeMaterialMode=runtimeMaterialMode,runtimeUsable=runtimeUsable,buildSourceArena=buildSourceArenaFromDisc,runtimeDropGhost=runtimeDropGhost}
return A
