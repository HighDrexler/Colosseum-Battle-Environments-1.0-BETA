local V=...
local HSD,FSYS=V and V.HSD,V and V.FSYS
local A={arenaRevision=9}
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
  {
    cache="cache/M1_water_cache.lua",id="water",label="WATER COLOSSEUM",
    sourceFsys="M1_water_colo.fsys",sourceMember="M1_water_colo.dat",textureRoot="cache/stages/water/source",
    minVertices=40000,minGroups=150,maxVertices=180000,maxDisplayOps=600000,maxJobjs=4096,maxDobjs=10000,maxPobjs=20000,
    crowdOffsets={[0x0d5b60]=true,[0x0ddb60]=true},
  },
  {
    cache="cache/orre_colosseum_cache.lua",id="orre_colosseum",label="ORRE COLOSSEUM",
    sourceFsys="T1_ancient_colo.fsys",sourceMember="T1_ancient_colo.dat",textureRoot="cache/stages/orre/source",
    -- Preserve the complete T1 source scene. The old 560-unit extraction radius
    -- discarded the remote desert/ruin geometry before runtime ever saw it.
    minVertices=35000,minGroups=35,maxVertices=180000,maxDisplayOps=1100000,
    maxSceneRoots=24,maxJobjs=12000,maxDobjs=36000,maxPobjs=60000,
    crowdOffsets={[0x10f240]=true,[0x111240]=true},
  },
  {
    cache="cache/realgam_colosseum_cache.lua",id="realgam_colosseum",label="REALGAM COLOSSEUM",
    sourceFsys="D4_casino_colo.fsys",sourceMember="D4_casino_colo.dat",textureRoot="cache/stages/realgam/source",
    -- Preserve the complete D4 tower/casino exterior. The old 600-unit radius
    -- removed dozens of distant tower, support and skyline groups.
    minVertices=50000,minGroups=100,maxVertices=320000,maxDisplayOps=1800000,
    maxSceneRoots=32,maxJobjs=18000,maxDobjs=54000,maxPobjs=90000,
    crowdOffsets={[0x0bed60]=true,[0x0c0d60]=true},
    backdrop={offset=0x09ed60,x=0,y=336,w=512,h=176,path="cache/stages/realgam/source/sky_512x176.rgba"},
  },
  {recipe="recipes/arenas/outdoor_wild.lua",cache="cache/outdoor_wild_cache.lua",id="outdoor_wild"},
  {
    cache="cache/D2_mt_battle_platform100_cache.lua",id="mt_battle_summit",label="MT. BATTLE SUMMIT",
    sourceFsys="D2_crater_colo.fsys",sourceMember="D2_crater_colo.dat",textureRoot="cache/stages/d2_crater/textures",
    -- Platform 100 must come from the stage archive, not CBE-authored geology.
    -- Preserve the whole HSD scene so the crater wall, bridge, deck, pylons,
    -- distant background and their original UV/material relationships survive.
    minVertices=8000,minGroups=20,maxVertices=300000,maxDisplayOps=1400000,
    maxSceneRoots=32,maxJobjs=12000,maxDobjs=36000,maxPobjs=60000,
  },
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
  local out={"-- Generated from the user-supplied Pokemon Colosseum GC6E01 disc.\nreturn {version=32,source=",string.format("%q",source),",prototype=false,"}
  local b=model.bounds or {};out[#out+1]="bounds={min="..(vec(b.min) or "{0,0,0}")..",max="..(vec(b.max) or "{0,0,0}").."},"
  out[#out+1]="groupCount="..tostring(#(model.groups or {}))..",vertexCount="..tostring(tonumber(model.vertexCount) or 0)..","
  out[#out+1]="crowdOriginal="..tostring(crowdOriginal or 0)..",crowdPolicy="..string.format("%q",model.crowdPolicy or "source-hsd-crowd")..",groups={\n"
  for _,g in ipairs(model.groups or {}) do
    out[#out+1]="{"
    if g.texture then
      out[#out+1]="texture={path="..string.format("%q",g.texture.path)..",w="..tostring(g.texture.w)..",h="..tostring(g.texture.h)
      if g.texture.wrapS~=nil then out[#out+1]=",wrapS="..tostring(g.texture.wrapS) end
      if g.texture.wrapT~=nil then out[#out+1]=",wrapT="..tostring(g.texture.wrapT) end
      out[#out+1]="},"
    end
    out[#out+1]="alpha="..num(g.alpha or 1)..",xlu="..tostring(g.xlu and true or false)..",noz="..tostring(g.noz and true or false)..","
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
  return function(rows)
    local minx,maxx,miny,maxy,minz,maxz=1e30,-1e30,1e30,-1e30,1e30,-1e30
    local sx,sy,sz,n=0,0,0,0
    for _,v in ipairs(rows or {}) do
      local x,y,z=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
      sx=sx+x;sy=sy+y;sz=sz+z;n=n+1
      minx=math.min(minx,x);maxx=math.max(maxx,x);miny=math.min(miny,y);maxy=math.max(maxy,y);minz=math.min(minz,z);maxz=math.max(maxz,z)
    end
    if n==0 then return false end
    local cx,cy,cz=sx/n,sy/n,sz/n
    local span=math.max(maxx-minx,maxy-miny,maxz-minz)
    if spec.keepHighBackdrop and cy>500 and span>3000 then return true end
    local radial=math.sqrt(cx*cx+cz*cz)
    return radial<=spec.sourceRadius and span<=(spec.sourceMaxSpan or 1e30)
  end
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
    textures=true,maxSceneRoots=spec.maxSceneRoots or 16,maxVertices=spec.maxVertices or 180000,
    maxDisplayOps=spec.maxDisplayOps or 700000,maxJobjs=spec.maxJobjs or 6000,
    maxDobjs=spec.maxDobjs or 16000,maxPobjs=spec.maxPobjs or 28000,
    groupFilter=sourceGroupFilter(spec),
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
      if spec.crowdOffsets and spec.crowdOffsets[t.dataOffset] then crowdOriginal=crowdOriginal+1 end
      if spec.backdrop and not backdropWritten and t.dataOffset==spec.backdrop.offset then
        local b=spec.backdrop
        write(mod,b.path,cropRGBA(t.rgba,t.w,t.h,b.x,b.y,b.w,b.h),generated)
        backdropWritten=true
      end
      g.texture={path=path,w=t.w,h=t.h,wrapS=t.wrapS,wrapT=t.wrapT}
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
function A.repair(mod,disc,progress,generated)
  -- 1.7.17 parity migration: refresh every disc-backed venue through the
  -- current HSD/material serializer, then materialize the current authored
  -- Wildlands recipe. Earlier incremental migrations preserved older Water,
  -- Mt. Battle and Wildlands caches, so presentation fixes could fail to reach
  -- an otherwise healthy existing install.
  local sourceIndexes={1,2,3,5}
  local total=#sourceIndexes+1
  local report={"return {revision="..tostring(A.arenaRevision)..","}
  progress("ARENA PARITY REFRESH",0,total)
  for step,index in ipairs(sourceIndexes) do
    local arena=ARENAS[index]
    progress((arena.label or arena.id).." / FULL SOURCE HSD",step-1,total)
    local value=buildSourceArenaFromDisc(mod,disc,progress,generated,arena)
    report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q,textures=%d},",
      arena.id,arena.cache,tonumber(value.groups) or 0,tonumber(value.vertices) or 0,
      tostring(value.source or "GC6E01 source"),tonumber(value.textures) or 0)
  end
  local wild=ARENAS[4]
  progress("ORRE WILDLANDS / AUTHORED PARITY",#sourceIndexes,total)
  local keys={}
  for path in pairs(SPECS) do
    if path:find("cache/stages/wildlands/",1,true) then keys[#keys+1]=path end
  end
  table.sort(keys)
  for _,path in ipairs(keys) do
    local sp=SPECS[path]
    write(mod,path,textureBytes(mod,path,sp),generated)
  end
  local src=assert(mod:read(wild.recipe),"missing arena recipe: "..wild.recipe)
  local chunk,err=load(src,"@"..wild.recipe);assert(chunk,err)
  local ok,recipe=pcall(chunk);assert(ok,recipe)
  assert(type(recipe)=="table" and type(recipe.groups)=="table" and #recipe.groups>0,"invalid arena recipe: "..wild.id)
  write(mod,wild.cache,src,generated)
  report[#report+1]=string.format("%s={cache=%q,groups=%d,vertices=%d,source=%q,textures=%d},",
    wild.id,wild.cache,#recipe.groups,tonumber(recipe.vertexCount) or 0,tostring(recipe.source or "recipe"),#keys)
  report[#report+1]="}\n"
  write(mod,"build/arena_repair.lua",table.concat(report),generated)
  progress("ARENA PARITY REFRESH READY",total,total)
  return true
end
function A.run(mod,disc,progress,generated)
  -- Mt. Battle is source-backed in revision 7. Only Wildlands still needs
  -- CBE-authored texture generation; D2 texture paths are written from the
  -- exact GX textures decoded from D2_crater_colo.dat.
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
return A
