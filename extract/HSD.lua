local V=...
local GX=V.GXTexture
local H={}
local floor,abs,sqrt=math.floor,math.abs,math.sqrt
local function u16(s,p)local a,b=s:byte(p,p+1);if not b then return nil end;return a*256+b end
local function s16(s,p)local v=u16(s,p);if not v then return nil end;return v>=32768 and v-65536 or v end
local function u32(s,p)local a,b,c,d=s:byte(p,p+3);if not d then return nil end;return ((a*256+b)*256+c)*256+d end
local function f32(s,p)
  local v=u32(s,p);if not v then return nil end
  local sign=v>=2147483648 and -1 or 1;if sign<0 then v=v-2147483648 end
  local e=floor(v/8388608);local m=v%8388608
  if e==255 then return 0/0 end
  if e==0 then return sign*(m/8388608)*2^-126 end
  return sign*(1+m/8388608)*2^(e-127)
end
local function finite(x)return type(x)=="number" and x==x and abs(x)<1e12 end
local function cstr(s,p)local e=s:find("\0",p,true) or (#s+1);return s:sub(p,e-1) end
local function ident()return {1,0,0,0,0,1,0,0,0,0,1,0,0,0,0,1} end
local function mul(a,b)
  local o={};for r=0,3 do for c=0,3 do local q=0;for k=0,3 do q=q+a[r*4+k+1]*b[k*4+c+1] end;o[r*4+c+1]=q end end;return o
end
local function localM(rx,ry,rz,sx,sy,sz,tx,ty,tz)
  local cx,snx=math.cos(rx),math.sin(rx);local cy,sny=math.cos(ry),math.sin(ry);local cz,snz=math.cos(rz),math.sin(rz)
  return {
    cz*cy*sx,(cz*sny*snx-snz*cx)*sy,(cz*sny*cx+snz*snx)*sz,tx,
    snz*cy*sx,(snz*sny*snx+cz*cx)*sy,(snz*sny*cx-cz*snx)*sz,ty,
    -sny*sx,cy*snx*sy,cy*cx*sz,tz,
    0,0,0,1,
  }
end
local function point(m,x,y,z)return m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12] end
local function normal(m,x,y,z)local a,b,c=m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z;local l=sqrt(a*a+b*b+c*c);if l<1e-9 then return 0,1,0 end;return a/l,b/l,c/l end
local function align32(n)return n+((0x20-(n%0x20))%0x20) end

-- HSD animation FOBJ payloads are little-endian even though the surrounding
-- DAT structs are big-endian. Keep the readers separate so native trainer
-- animation sampling cannot accidentally reuse the geometry readers.
local function le16(s,p)local a,b=s:byte(p,p+1);if not b then return nil end;return a+b*256 end
local function les16(s,p)local v=le16(s,p);if not v then return nil end;return v>=32768 and v-65536 or v end
local function lef32(s,p)
  local a,b,c,d=s:byte(p,p+3);if not d then return nil end
  local v=a+b*256+c*65536+d*16777216
  local sign=v>=2147483648 and -1 or 1;if sign<0 then v=v-2147483648 end
  local e=floor(v/8388608);local m=v%8388608
  if e==255 then return 0/0 end
  if e==0 then return sign*(m/8388608)*2^-126 end
  return sign*(1+m/8388608)*2^(e-127)
end
local function packed(s,p,limit)
  local result,shift=0,0
  for _=1,5 do
    if p>(limit or #s) then return nil,p end
    local b=s:byte(p);p=p+1;if not b then return nil,p end
    result=result+(b%128)*(2^shift)
    if b<128 then return result,p end
    shift=shift+7
  end
  return nil,p
end
local function animScalar(blob,p,fmt,scale,limit)
  scale=scale or 1
  if fmt==0 then local v=lef32(blob,p);return v and v/scale or nil,p+4 end
  if fmt==0x20 then local v=les16(blob,p);return v and v/scale or nil,p+2 end
  if fmt==0x40 then local v=le16(blob,p);return v and v/scale or nil,p+2 end
  local b=blob:byte(p);if not b then return nil,p+1 end
  if fmt==0x60 and b>=128 then b=b-256 end
  return b/scale,p+1
end
local function decodeFobj(a,fd)
  local blob=a.blob;local len=u32(blob,fd+0x04+1) or 0;local start=f32(blob,fd+0x08+1) or 0
  local track=blob:byte(fd+0x0C+1) or 0;local vf=blob:byte(fd+0x0D+1) or 0;local tf=blob:byte(fd+0x0E+1) or 0
  local data=a:ptr(fd+0x10);if not data or len<=0 or len>16*1024*1024 then return track,{} end
  local p,limit=data+1,math.min(data+len,#blob);local clock=0;local keys={}
  local vfmt=vf-(vf%0x20);local tfmt=tf-(tf%0x20);local vscale=2^(vf%0x20);local tscale=2^(tf%0x20)
  while p<=limit do
    local code;code,p=packed(blob,p,limit);if not code then break end
    local op=code%16;local count=floor(code/16)+1;if op==0 or op>6 then break end
    for _=1,count do
      if p>limit+1 then break end
      local value,tan,time=0,0,0
      if op==1 or op==2 or op==3 then value,p=animScalar(blob,p,vfmt,vscale,limit);time,p=packed(blob,p,limit)
      elseif op==4 then value,p=animScalar(blob,p,vfmt,vscale,limit);tan,p=animScalar(blob,p,tfmt,tscale,limit);time,p=packed(blob,p,limit)
      elseif op==5 then tan,p=animScalar(blob,p,tfmt,tscale,limit)
      elseif op==6 then value,p=animScalar(blob,p,vfmt,vscale,limit) end
      if value==nil or tan==nil then break end
      keys[#keys+1]={frame=clock,value=value,tan=tan or 0,op=op};clock=clock+(time or 0)
    end
  end
  if start~=0 then
    local kept={};for _,k in ipairs(keys) do k.frame=k.frame-start;if k.frame>=0 then kept[#kept+1]=k end end;keys=kept
  end
  return track,keys
end
local function fobjValue(keys,frame)
  if not keys or #keys==0 then return nil end
  if #keys>1 and frame>=keys[#keys].frame then return keys[#keys].value end
  local p0,p1,d0,d1,t0,t1=0,0,0,0,0,0;local opPrev,op=1,1
  for _,k in ipairs(keys) do
    opPrev=op;op=k.op
    if op==1 or op==2 then p0=p1;p1=k.value;d0=d1;if opPrev~=5 then d1=0 end;t0=t1;t1=k.frame
    elseif op==3 then p0=p1;d0=d1;p1=k.value;d1=0;t0=t1;t1=k.frame
    elseif op==4 then p0=p1;p1=k.value;d0=d1;d1=k.tan;t0=t1;t1=k.frame
    elseif op==5 then d0=d1;d1=k.tan
    elseif op==6 then p0=k.value;p1=k.value end
    if t1>frame and op~=5 then break end
    opPrev=op
  end
  if frame<=t0 then return p0 end;if frame>=t1 then return p1 end
  if t0==t1 or opPrev==1 or opPrev==6 then return p0 end
  local time=frame-t0;local span=t1-t0
  if opPrev==2 then return p0+(p1-p0)*(time/span) end
  if opPrev==3 or opPrev==4 or opPrev==5 then
    local inv=1/span;local f1=time*time;local f2=inv*inv*f1*time;local f3=3*f1*inv*inv;local f4=f2-f1*inv;local f2b=2*f2*inv
    return d1*f4+d0*(time+(f4-f1*inv))+p0*(1+(f2b-f3))+p1*(-f2b+f3)
  end
  return p0
end
local function findModelSet(a,root)
  local scene=a:publicSymbol("scene_data");local sets=scene and a:ptr(scene) or nil;if not sets then return nil end
  for i=0,127 do local ms=a:ptr(sets+i*4);if not ms then break end;if a:ptr(ms)==root then return ms end end
end
local function nativeAnimations(a,root)
  local ms=findModelSet(a,root);local arr=ms and a:ptr(ms+0x04) or nil;local out={};if not arr then return out end
  for i=0,63 do local r=a:ptr(arr+i*4);if not r then break end;out[#out+1]=r end
  return out
end
local function nativePose(a,root,clipIndex,frame)
  -- nativePose clip ids are zero-based at the extractor boundary. Lua tables are
  -- one-based, so clip 0 addresses the first HSD animation entry. GC6E01 B1
  -- trainer archives expose that entry as a bind/T pose; clip 1 is the first
  -- usable non-bind battle stance. Keep the API semantics explicit so clip 0
  -- cannot be mistaken for an authored idle again.
  local clips=nativeAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local ar=clips[ci+1];if not ar then return nil,#clips end
  local pose={};local seenJ,seenA={},{ }
  local function pair(j,aj,depth)
    if not j or not aj or seenJ[j] or seenA[aj] or depth>256 then return end
    seenJ[j]=true;seenA[aj]=true
    local b=a.blob;local s={
      f32(b,j+0x14+1) or 0,f32(b,j+0x18+1) or 0,f32(b,j+0x1C+1) or 0,
      f32(b,j+0x20+1) or 1,f32(b,j+0x24+1) or 1,f32(b,j+0x28+1) or 1,
      f32(b,j+0x2C+1) or 0,f32(b,j+0x30+1) or 0,f32(b,j+0x34+1) or 0}
    local aobj=a:ptr(aj+0x08);local fd=aobj and a:ptr(aobj+0x08) or nil;local guard=0
    while fd and guard<64 do guard=guard+1;local track,keys=decodeFobj(a,fd);local v=fobjValue(keys,frame or 0)
      if v~=nil then if track>=1 and track<=3 then s[track]=v elseif track>=5 and track<=7 then s[track+2]=v elseif track>=8 and track<=10 then s[track-4]=v end end
      fd=a:ptr(fd)
    end
    pose[j]=s
    pair(a:ptr(j+0x08),a:ptr(aj),depth+1);pair(a:ptr(j+0x0C),a:ptr(aj+0x04),depth+1)
  end
  pair(root,ar,0);return pose,#clips
end

local function archiveAt(blob,base)
  local fileSize,dataSize,relocs,pubs,ext=u32(blob,base+1),u32(blob,base+5),u32(blob,base+9),u32(blob,base+13),u32(blob,base+17)
  if not (fileSize and dataSize and relocs and pubs and ext) then return nil end
  if fileSize<0x20 or base+fileSize>#blob or dataSize>=fileSize or relocs>200000 or pubs>8192 or ext>8192 then return nil end
  local data=base+0x20;local reloc=data+dataSize;local public=reloc+relocs*4;local external=public+pubs*8;local strings=external+ext*8
  if strings>base+fileSize then return nil end
  local a={blob=blob,base=base,fileSize=fileSize,dataSize=dataSize,data=data,reloc=reloc,relocCount=relocs,public=public,publicCount=pubs,external=external,externalCount=ext,strings=strings}
  function a:ptr(field)
    local raw=u32(blob,field+1);if not raw or raw==0 then return nil end
    local p=self.data+raw;if p<self.data or p>=self.data+self.dataSize then return nil end;return p
  end
  function a:publicSymbol(name)
    for i=0,self.publicCount-1 do local p=self.public+i*8;local ro,no=u32(blob,p+1),u32(blob,p+5);if ro and no then local npos=self.strings+no;if npos<self.base+self.fileSize then local n=cstr(blob,npos+1);if n==name then return self.data+ro end end end end
  end
  function a:publicSymbols()
    local out={}
    for i=0,self.publicCount-1 do
      local p=self.public+i*8;local ro,no=u32(blob,p+1),u32(blob,p+5)
      if ro and no then
        local npos=self.strings+no
        if npos<self.base+self.fileSize then out[#out+1]={name=cstr(blob,npos+1),ptr=self.data+ro} end
      end
    end
    return out
  end
  return a
end

local function knownArchiveOffsets(blob)
  local out,seen={},{}
  local function add(v)if type(v)=="number" and v>=0 and v<=#blob-0x20 and not seen[v] then seen[v]=true;out[#out+1]=v end end
  add(0);add(0x20);add(0x40)
  -- Pokemon Colosseum PKX: fixed 0x40-byte wrapper followed by the DAT.
  -- Pokemon XD PKX: dynamic animation/GPT1 wrapper. Supporting both here is
  -- cheap and also makes diagnostics useful if a source archive mixes formats.
  if #blob>=0x84 then
    local first=u32(blob,1);local at40=u32(blob,0x41)
    if first and at40 and first~=at40 then
      local gpt=u32(blob,9) or 0;local anim=u32(blob,0x11) or 17
      if anim>0 and anim<128 then add(align32(0x84+anim*0xD0)+align32(gpt)) end
      add(0xE60+align32(gpt))
    elseif first and at40 and first==at40 then add(0x40) end
  end
  return out,seen
end

function H.findArchives(blob)
  local out={};local offsets,seen=knownArchiveOffsets(blob)
  local function add(base)
    if not seen["a"..base] then
      local a=archiveAt(blob,base)
      if a then seen["a"..base]=true;out[#out+1]=a end
    end
  end
  for _,base in ipairs(offsets) do add(base) end
  -- DAT/PKX trainer members overwhelmingly resolve at one of the canonical
  -- wrapper offsets above. Do not brute-force another 16K candidate headers
  -- when a canonical archive already validated; that cost multiplied by the
  -- 100+ people_archive members was a major first-run stall.
  if #out==0 then
    -- Some FSYS members carry a proprietary preamble. Only then search a
    -- bounded 64 KiB prefix; archiveAt performs strict structural validation.
    local max=math.min(0x10000,#blob-0x20)
    for base=0,max,4 do add(base) end
  end
  table.sort(out,function(a,b)return a.base<b.base end)
  return out
end

function H.findArchive(blob)
  local archives=H.findArchives(blob)
  for _,a in ipairs(archives) do if a:publicSymbol("scene_data") then return a end end
  return archives[1]
end

local function readComp(blob,p,ctype,frac)
  frac=frac or 0
  if ctype==4 then return f32(blob,p),4 end
  if ctype==0 then return (blob:byte(p) or 0)/(2^frac),1 end
  if ctype==1 then local v=blob:byte(p) or 0;if v>=128 then v=v-256 end;return v/(2^frac),1 end
  if ctype==2 then return (u16(blob,p) or 0)/(2^frac),2 end
  if ctype==3 then return (s16(blob,p) or 0)/(2^frac),2 end
  return 0,1
end
local function componentCount(attr,cnt,directMode)
  if attr==9 then return cnt==0 and 2 or 3 end
  -- GX normal component-count values are not simple scalar counts:
  --   XYZ  (0): one 3-component normal
  --   NBT  (1): one index/direct record containing N+B+T (9 scalars)
  --   NBT3 (2): THREE indices (one each for N/B/T), each selecting a
  --             normal-sized 3-scalar record.  Direct NBT3 still carries
  --             all three vectors inline.
  -- Treating NBT3 as one 9-scalar indexed record shifts the display-list
  -- cursor by 2 missing indices and corrupts every following attribute.
  if attr==10 then
    if cnt==0 then return 3 end
    if cnt==1 then return 9 end
    if cnt==2 then return directMode and 9 or 3 end
    return 3
  end
  -- Some HSD serializers expose the tangent basis as GX_VA_NBT (25).
  if attr==25 then return (cnt==2 and not directMode) and 3 or 9 end
  if attr>=13 and attr<=20 then return cnt==0 and 1 or 2 end
  if attr==11 or attr==12 then return 4 end
  return 1
end
local function colorDirectBytes(ctype)
  -- GX color component types are a different enum from numeric GXCompType.
  -- RGB565/RGBA4=2, RGB8/RGBA6=3, RGBX8/RGBA8=4 bytes.
  if ctype==0 or ctype==3 then return 2 end
  if ctype==1 or ctype==4 then return 3 end
  if ctype==2 or ctype==5 then return 4 end
  return 4
end
local function parseDescs(a,p)
  local out={};local blob=a.blob
  for _=0,31 do
    if not p or p+0x17>=a.base+a.fileSize then break end
    local attr=u32(blob,p+1);if not attr or attr==255 then break end
    local typ,cnt,ctype=u32(blob,p+5),u32(blob,p+9),u32(blob,p+13)
    local scale=blob:byte(p+0x10+1) or 0;local stride=u16(blob,p+0x12+1) or 0
    -- HSD_VtxDescList.base_ptr is a RAW data-section offset, not a nullable
    -- relocated object pointer. Offset 0 is therefore valid and means the
    -- attribute buffer begins at byte 0 of the DAT data section. Trainer
    -- meshes in Colosseum commonly use base_ptr=0 for positions. Passing this
    -- field through a:ptr() incorrectly converted that valid buffer into nil,
    -- leaving every trainer POBJ with zero decodable position vertices.
    local rawBase=u32(blob,p+0x14+1)
    local arr=(rawBase and rawBase<a.dataSize) and (a.data+rawBase) or nil
    out[#out+1]={attr=attr,type=typ,count=cnt,ctype=ctype,frac=scale,stride=stride,array=arr}
    p=p+0x18
  end
  return out
end
local function indexed(desc,idx,blob)
  if not desc.array then return nil end
  local n=componentCount(desc.attr,desc.count,false);local sz=(desc.ctype==4 and 4) or ((desc.ctype==2 or desc.ctype==3) and 2 or 1);local stride=desc.stride>0 and desc.stride or n*sz
  local p=desc.array+idx*stride+1;local v={};for i=1,n do local q,d=readComp(blob,p,desc.ctype,desc.frac);v[i]=q;p=p+d end;return v
end
local function direct(desc,blob,p)
  local n=componentCount(desc.attr,desc.count,true);local v={};for i=1,n do local q,d=readComp(blob,p,desc.ctype,desc.frac);v[i]=q;p=p+d end;return v,p
end
local function readVertex(descs,blob,p,posMap)
  local out={}
  for _,d in ipairs(descs) do
    if d.attr<=8 then
      -- Matrix indices are normally DIRECT/INDEX8 (one byte), but honor
      -- INDEX16 if a source explicitly declares it so the stream stays aligned.
      local idx
      if d.type==1 or d.type==2 then idx=blob:byte(p) or 0;p=p+1
      elseif d.type==3 then idx=u16(blob,p) or 0;p=p+2 end
      -- Preserve PNMTXIDX. Enveloped HSD vertices use this value (in multiples
      -- of three GX matrix rows) to select their bind joint/envelope.
      if d.attr==0 and idx~=nil then out[0]={idx} end
    elseif d.type==0 then
    elseif d.type==1 then
      if d.attr==11 or d.attr==12 then
        -- Direct vertex colors are packed GX colors, not four generic numeric
        -- components. We do not need the color for CBE geometry, but consuming
        -- the exact packed width is critical or every following attribute/vertex
        -- is decoded at the wrong byte offset.
        p=p+colorDirectBytes(d.ctype)
      else
        local v;v,p=direct(d,blob,p);out[d.attr]=v
      end
    elseif d.type==2 then
      local idx=blob:byte(p) or 0;p=p+1
      local dataIdx=(d.attr==9 and posMap and posMap[idx]) or idx
      out[d.attr]=indexed(d,dataIdx,blob)
      -- GX_NRM_NBT3 encodes THREE independent indices in the display list.
      -- CBE only needs the first (normal) vector for lighting, but we must
      -- consume the binormal+tangent indices to keep the stream aligned.
      if (d.attr==10 or d.attr==25) and d.count==2 then p=p+2 end
    elseif d.type==3 then
      local idx=u16(blob,p) or 0;p=p+2
      local dataIdx=(d.attr==9 and posMap and posMap[idx]) or idx
      out[d.attr]=indexed(d,dataIdx,blob)
      if (d.attr==10 or d.attr==25) and d.count==2 then p=p+4 end
    else return nil,p end
  end
  return out,p
end
local function envelopeWorld(a,pobj,v,defaultWorld,budget)
  local raw=v[0] and tonumber(v[0][1]) or 0
  local index=floor(raw/3)
  local byPobj=budget.envelopeWorldCache[pobj]
  if not byPobj then byPobj={};budget.envelopeWorldCache[pobj]=byPobj end
  local cached=byPobj[index]
  if cached~=nil then return cached or defaultWorld end
  local tablePtr=a:ptr(pobj+0x14)
  local envelope=tablePtr and a:ptr(tablePtr+index*4) or nil
  local bone=envelope and a:ptr(envelope) or nil
  local weight=envelope and f32(a.blob,envelope+4+1) or nil
  -- Match HSDLib's bind-pose export: a rigid one-weight envelope uses that
  -- bone's world transform; blended envelopes retain the parent transform.
  local selected=(bone and weight and math.abs(weight-1)<.0001 and budget.worldByJobj[bone]) or defaultWorld
  byPobj[index]=selected
  return selected
end
local function triangles(kind,verts,out)
  if kind==0x90 then for i=1,#verts-2,3 do out[#out+1]={verts[i],verts[i+1],verts[i+2]} end
  elseif kind==0x80 then for i=1,#verts-3,4 do out[#out+1]={verts[i],verts[i+1],verts[i+2]};out[#out+1]={verts[i],verts[i+2],verts[i+3]} end
  elseif kind==0x98 then for i=3,#verts do if i%2==1 then out[#out+1]={verts[i-2],verts[i-1],verts[i]} else out[#out+1]={verts[i-1],verts[i-2],verts[i]} end end
  elseif kind==0xA0 then for i=3,#verts do out[#out+1]={verts[1],verts[i-1],verts[i]} end end
end
local POBJ_SHAPEANIM=0x1000
local function appendDescs(dst,src)
  for _,d in ipairs(src or {}) do dst[#dst+1]=d end
end
local function shapeVertexMap(a,shape)
  if not shape then return nil end
  local count=u32(a.blob,shape+0x04+1) or 0
  if count<=0 or count>200000 then return nil end
  local tables=a:ptr(shape+0x0C);if not tables then return nil end
  local first=a:ptr(tables);if not first then return nil end
  local map={}
  for i=0,count-1 do
    local v=s16(a.blob,first+i*2+1);if v==nil then break end
    map[i]=v>=0 and v or 0
  end
  return map
end
local function parsePobjDescs(a,pobj)
  local basePtr=a:ptr(pobj+0x08);if not basePtr then return {},nil end
  local out=parseDescs(a,basePtr)
  local flags=u16(a.blob,pobj+0x0C+1) or 0
  local map=nil
  if flags%0x2000>=POBJ_SHAPEANIM then
    local shape=a:ptr(pobj+0x14)
    if shape then
      -- Match SysDolphin/HSDLib HSD_POBJ.ToGXAttributes(): shape-animated
      -- polygons concatenate their ShapeSet vertex and normal descriptors onto
      -- the base POBJ attribute list. Omitting these descriptors makes CBE read
      -- too few bytes per display-list vertex and desynchronizes the command
      -- stream after the first animated vertex. Static arena POBJs don't hit
      -- this path, which is why the bug presented as trainer-only.
      local vertexPtr=a:ptr(shape+0x08)
      if vertexPtr and vertexPtr~=basePtr then appendDescs(out,parseDescs(a,vertexPtr)) end
      local normalPtr=a:ptr(shape+0x14)
      if normalPtr then appendDescs(out,parseDescs(a,normalPtr)) end
      map=shapeVertexMap(a,shape)
    end
  end
  return out,map
end
local function parseDisplay(a,pobj,world,budget)
  budget=budget or {displayOps=0,vertices=0,maxDisplayOps=80000,maxVertices=30000}
  local blob=a.blob;local pobjFlags=u16(blob,pobj+0x0C+1) or 0
  if pobjFlags%0x2000>=POBJ_SHAPEANIM then budget.shapePobjs=(budget.shapePobjs or 0)+1 end
  if pobjFlags%0x4000>=0x2000 then budget.envelopePobjs=(budget.envelopePobjs or 0)+1 end
  local nDisplay=u16(blob,pobj+0x0E+1) or 0;local dl=a:ptr(pobj+0x10)
  if not dl or nDisplay==0 then return {} end
  local descs,posMap=parsePobjDescs(a,pobj);if budget.shapeIndexMap==false then posMap=nil end;if #descs==0 then return {} end
  local byteLen=nDisplay*32
  if byteLen<=0 or byteLen>8*1024*1024 then budget.exhausted="display-list byte budget";return {} end
  local pend=math.min(a.base+a.fileSize,dl+byteLen);local p=dl+1;local tris={};local guard=0
  while p+2<=pend and guard<8192 and not budget.exhausted do
    guard=guard+1;local op=blob:byte(p) or 0;p=p+1
    if op~=0 then
      local kind=floor(op/8)*8;local n=u16(blob,p) or 0;p=p+2
      if n>20000 then budget.exhausted="primitive vertex count";break end
      local vs={}
      for _=1,n do
        if p>pend then break end
        budget.displayOps=budget.displayOps+1
        if budget.displayOps>(budget.maxDisplayOps or 80000) then budget.exhausted="display decode operation budget";break end
        local v;v,p=readVertex(descs,blob,p,posMap);if not v then break end;vs[#vs+1]=v
      end
      if budget.exhausted then break end
      triangles(kind,vs,tris)
      if #tris>20000 then budget.exhausted="triangle budget";break end
    end
  end
  if guard>=8192 then budget.exhausted="display command budget" end
  local rows={}
  for _,tri in ipairs(tris) do
    for _,v in ipairs(tri) do
      if budget.vertices+#rows>=(budget.maxVertices or 30000) then budget.exhausted="mesh vertex budget";break end
      local pos=v[9];if pos and #pos>=2 then
        local vertexWorld=(pobjFlags%0x4000>=0x2000) and envelopeWorld(a,pobj,v,world,budget) or world
        local x,y,z=pos[1] or 0,pos[2] or 0,pos[3] or 0;local wx,wy,wz=point(vertexWorld,x,y,z)
        local uv=v[13] or {0,0};local nr=v[10] or v[25] or {0,1,0};local nx,ny,nz=normal(vertexWorld,nr[1] or 0,nr[2] or 1,nr[3] or 0)
        rows[#rows+1]={wx,wy,wz,uv[1] or 0,uv[2] or 0,nx,ny,nz}
      end
    end
    if budget.exhausted then break end
  end
  return rows
end
local function firstTexture(a,mobj)
  if not mobj then return nil end
  local tobj=a:ptr(mobj+0x08);if not tobj then return nil end
  local img=a:ptr(tobj+0x4C);if not img then return nil end
  local b=a.blob;local data=a:ptr(img);local w,h=u16(b,img+5),u16(b,img+7);local fmt=u32(b,img+9)
  if not data or not w or not h or not fmt or w==0 or h==0 or w>2048 or h>2048 then return nil end
  local n=GX.dataSize(w,h,fmt);if data+n>a.base+a.fileSize then return nil end
  local palette,palFmt,pp=nil,nil,nil;local tlut=a:ptr(tobj+0x50)
  if tlut then pp=a:ptr(tlut);palFmt=u32(b,tlut+5);local count=u16(b,tlut+0x0C+1) or 0;if pp and count>0 and pp+count*2<=a.base+a.fileSize then palette=b:sub(pp+1,pp+count*2) end end
  -- A venue commonly references the same large atlas from many DOBJ groups.
  -- Pure-Lua GX decoding is expensive, so cache immutable decoded pixels per
  -- archive/image/palette identity while retaining each TOBJ's own wrap state.
  a._decodedTextures=a._decodedTextures or {}
  local key=("%d:%d:%d:%d:%d"):format(data,w,h,fmt,pp or -1)
  local rgba=a._decodedTextures[key]
  if not rgba then
    local ok,decoded=pcall(GX.decode,b:sub(data+1,data+n),w,h,fmt,palette,palFmt)
    if not ok then return nil end
    rgba=decoded;a._decodedTextures[key]=rgba
  end
  -- Preserve the source GX wrap state. HSD_TOBJ stores WrapS/WrapT as
  -- GXWrapMode values at 0x34/0x38 (CLAMP=0, REPEAT=1, MIRROR=2).
  -- Earlier CBE source arenas discarded this and then force-repeated every
  -- Orre/Realgam texture, which changes source atlas placement.
  local wrapS=u32(b,tobj+0x34+1)
  local wrapT=u32(b,tobj+0x38+1)
  return {w=w,h=h,format=fmt,rgba=rgba,dataOffset=data-a.data,wrapS=wrapS,wrapT=wrapT}
end
local function materialInfo(a,mobj)
  if not mobj then return nil end
  local b=a.blob
  local flags=u32(b,mobj+0x04+1) or 0
  local mat=a:ptr(mobj+0x0C)
  local info={
    -- SysDolphin HSD_MOBJ RENDER_MODE bits.
    xlu=(math.floor(flags/0x40000000)%2)==1,
    noz=(math.floor(flags/0x20000000)%2)==1,
  }
  if mat and mat+0x13<a.base+a.fileSize then
    local function color(off)
      return {(b:byte(mat+off+1) or 255)/255,(b:byte(mat+off+2) or 255)/255,(b:byte(mat+off+3) or 255)/255}
    end
    info.ambient=color(0x00)
    info.diffuse=color(0x04)
    info.specular=color(0x08)
    local alpha=f32(b,mat+0x0C+1);if finite(alpha) then info.alpha=math.max(0,math.min(1,alpha)) end
    local shine=f32(b,mat+0x10+1);if finite(shine) then info.shininess=math.max(0,shine) end
  end
  return info
end
local function plausibleJobj(a,p)
  if not p or p<a.data or p+0x3F>=a.data+a.dataSize then return false end
  local b=a.blob;local flags=u32(b,p+0x04+1) or 0
  local sx,sy,sz=f32(b,p+0x20+1),f32(b,p+0x24+1),f32(b,p+0x28+1)
  local tx,ty,tz=f32(b,p+0x2C+1),f32(b,p+0x30+1),f32(b,p+0x34+1)
  -- Bit 31 appears in older SysDolphin/HSD tooling as a legacy JOBJ/shadow
  -- marker. Do not reject an otherwise coherent joint solely because it is set.
  return finite(sx) and finite(sy) and finite(sz) and finite(tx) and finite(ty) and finite(tz)
    and abs(sx)<10000 and abs(sy)<10000 and abs(sz)<10000
    and abs(tx)<1e8 and abs(ty)<1e8 and abs(tz)<1e8
end
local function candidateRoots(a,maxRoots)
  maxRoots=tonumber(maxRoots) or 192
  local raw,rawSeen,roots,rootSeen={}, {},{},{}
  local function full()return #roots>=maxRoots end
  local function addRaw(p)if p and not rawSeen[p] then rawSeen[p]=true;raw[#raw+1]=p end end
  local function addRoot(p)
    if not full() and plausibleJobj(a,p) and not rootSeen[p] then rootSeen[p]=true;roots[#roots+1]=p end
  end
  local scene=a:publicSymbol("scene_data")
  if scene then
    addRaw(scene)
    -- SysDolphin HSD_SceneDesc.modelsets is NOT an inline/contiguous run of
    -- HSD_SceneModelSet structs. It is a NULL-terminated array of pointers to
    -- model-set structs. Each model-set's first field is the root JOBJ pointer.
    --
    -- The old contiguous interpretation could fill maxRoots with plausible
    -- garbage before this real pointer-array path ran. Character DATs then
    -- reported dozens of candidate roots while never testing their actual
    -- skeleton. Keep the semantic scene roots first and authoritative.
    local sets=a:ptr(scene)
    if sets then
      for i=0,127 do
        if full() then break end
        local modelSet=a:ptr(sets+i*4)
        if not modelSet then break end
        addRoot(a:ptr(modelSet)) -- HSD_SceneModelSet.joint
      end
    end
    -- Keep secondary scene pointers available only as later fallbacks.
    for off=4,0x0C,4 do addRaw(a:ptr(scene+off)) end
  end
  -- Preserve semantic/public roots ahead of relocation-derived guesses.
  for _,sym in ipairs(a:publicSymbols()) do addRaw(sym.ptr);addRoot(sym.ptr);if full() then break end end
  for _,p in ipairs(raw) do
    if full() then break end
    addRoot(p);for off=0,0x40,4 do if full() then break end;addRoot(a:ptr(p+off)) end
  end
  -- Relocations are a fallback pool. Cap them: malformed/complex files can
  -- expose thousands of plausible float blocks that are not JOBJ roots.
  if not full() then
    local relocLimit=math.min(a.relocCount,20000)
    for i=0,relocLimit-1 do
      local fieldOff=u32(a.blob,a.reloc+i*4+1)
      if fieldOff and fieldOff<a.dataSize then addRoot(a:ptr(a.data+fieldOff)) end
      if full() then break end
    end
  end
  return roots
end
local function extractRoot(a,root,opts)
  opts=opts or {}
  local groups={};local seen={};local min={1e30,1e30,1e30};local max={-1e30,-1e30,-1e30};local vertices=0
  local pose,clipCount=nil,0
  if opts.nativePose then pose,clipCount=nativePose(a,root,tonumber(opts.nativePose.clip) or 0,tonumber(opts.nativePose.frame) or 0) end
  local worldByJobj={};local mapSeen={}
  local function jobjSRT(j)
    local v=pose and pose[j]
    if v then return v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8],v[9] end
    local b=a.blob;return f32(b,j+0x14+1) or 0,f32(b,j+0x18+1) or 0,f32(b,j+0x1C+1) or 0,
      f32(b,j+0x20+1) or 1,f32(b,j+0x24+1) or 1,f32(b,j+0x28+1) or 1,
      f32(b,j+0x2C+1) or 0,f32(b,j+0x30+1) or 0,f32(b,j+0x34+1) or 0
  end
  local function mapWorld(j,parent,depth)
    if not j or mapSeen[j] or depth>256 or not plausibleJobj(a,j) then return end
    mapSeen[j]=true
    local b=a.blob;local rx,ry,rz,sx,sy,sz,tx,ty,tz=jobjSRT(j)
    local world=mul(parent,localM(rx,ry,rz,sx,sy,sz,tx,ty,tz));worldByJobj[j]=world
    mapWorld(a:ptr(j+0x08),world,depth+1);mapWorld(a:ptr(j+0x0C),parent,depth+1)
  end
  mapWorld(root,ident(),0)
  local budget={displayOps=0,vertices=0,maxDisplayOps=opts.maxDisplayOps or 80000,maxVertices=opts.maxVertices or 30000,jobjs=0,dobjs=0,pobjs=0,shapeIndexMap=opts.shapeIndexMap~=false,worldByJobj=worldByJobj,envelopeWorldCache={}}
  local maxJobjs=opts.maxJobjs or 1024;local maxDobjs=opts.maxDobjs or 4096;local maxPobjs=opts.maxPobjs or 8192
  local function walk(j,parent,depth)
    if budget.exhausted or not j or seen[j] or depth>256 or not plausibleJobj(a,j) then return end
    budget.jobjs=budget.jobjs+1;if budget.jobjs>maxJobjs then budget.exhausted="JOBJ traversal budget";return end
    seen[j]=true
    local b=a.blob;local rx,ry,rz,sx,sy,sz,tx,ty,tz=jobjSRT(j)
    local world=mul(parent,localM(rx,ry,rz,sx,sy,sz,tx,ty,tz))
    local flags=u32(b,j+0x04+1) or 0
    local isSpline=flags%0x8000>=0x4000
    local isParticle=flags%0x40>=0x20
    local dobj=(isSpline or isParticle) and nil or a:ptr(j+0x10);local localD=0
    while dobj and localD<256 and not budget.exhausted do
      localD=localD+1;budget.dobjs=budget.dobjs+1;if budget.dobjs>maxDobjs then budget.exhausted="DOBJ traversal budget";break end
      local mobj=a:ptr(dobj+0x08);local pobj=a:ptr(dobj+0x0C)
      local tex,texLoaded=nil,false
      local mat=materialInfo(a,mobj);local localP=0
      while pobj and localP<1024 and not budget.exhausted do
        localP=localP+1;budget.pobjs=budget.pobjs+1;if budget.pobjs>maxPobjs then budget.exhausted="POBJ traversal budget";break end
        local rows=parseDisplay(a,pobj,world,budget)
        if #rows>0 then
          local accept=true
          if type(opts.groupFilter)=="function" then
            local okFilter,result=pcall(opts.groupFilter,rows,mat)
            accept=okFilter and result~=false
          end
          if accept then
            -- Decode each DOBJ's source texture only if at least one polygon
            -- survives the arena envelope. This avoids spending most of a
            -- first-run cache build decoding distant sky/tower effect atlases
            -- that CBE will never render.
            if not texLoaded then
              tex=opts.textures==false and nil or firstTexture(a,mobj)
              texLoaded=true
            end
            for _,v in ipairs(rows) do for k=1,3 do if v[k]<min[k] then min[k]=v[k] end;if v[k]>max[k] then max[k]=v[k] end end end
            vertices=vertices+#rows;budget.vertices=vertices
            groups[#groups+1]={vertices=rows,texture=tex,
              alpha=mat and mat.alpha or 1,xlu=mat and mat.xlu or false,noz=mat and mat.noz or false,
              diffuse=mat and mat.diffuse or nil,ambient=mat and mat.ambient or nil,
              specular=mat and mat.specular or nil,shininess=mat and mat.shininess or nil}
          end
        end
        pobj=a:ptr(pobj+0x04)
      end
      dobj=a:ptr(dobj+0x04)
    end
    walk(a:ptr(j+0x08),world,depth+1);walk(a:ptr(j+0x0C),parent,depth+1)
  end
  walk(root,ident(),0)
  local stats={vertices=vertices,shapePobjs=budget.shapePobjs or 0,envelopePobjs=budget.envelopePobjs or 0,displayOps=budget.displayOps or 0,jobjs=budget.jobjs or 0,pobjs=budget.pobjs or 0,nativeClipCount=clipCount,nativePoseApplied=pose~=nil}
  if budget.exhausted then return nil,budget.exhausted,stats end
  if vertices<60 then return nil,"too few renderable vertices",stats end
  return {groups=groups,vertexCount=vertices,bounds={min=min,max=max,center={(min[1]+max[1])/2,(min[2]+max[2])/2,(min[3]+max[3])/2}}},nil,stats
end

local function archiveDiag(a)
  local names={};for _,s in ipairs(a:publicSymbols()) do if s.name and s.name~="" then names[#names+1]=s.name end end
  local roots=candidateRoots(a,128)
  return {base=a.base,fileSize=a.fileSize,dataSize=a.dataSize,relocations=a.relocCount,publicCount=a.publicCount,symbols=names,candidateRoots=#roots}
end

function H.describe(blob)
  local d={bytes=type(blob)=="string" and #blob or 0,archives={}}
  if type(blob)~="string" then d.error="not a string";return d end
  local archives=H.findArchives(blob)
  for _,a in ipairs(archives) do d.archives[#d.archives+1]=archiveDiag(a) end
  if #archives==0 then d.error="HSD archive not found" end
  return d
end

-- Arena scenes can contain several HSD_SceneModelSet roots (venue shell,
-- crowd/effects, water). Trainer extraction wants one best actor root, but an
-- arena must combine every semantic model-set root or entire galleries and
-- effect layers disappear. This path intentionally avoids relocation guesses.
function H.extractSceneModel(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local archives=H.findArchives(blob);if #archives==0 then return nil,"HSD archive not found" end
  local groups,total={},0
  local min,max={1e30,1e30,1e30},{-1e30,-1e30,-1e30}
  local rootCount,seenRoot=0,{}
  for _,a in ipairs(archives) do
    local scene=a:publicSymbol("scene_data")
    local sets=scene and a:ptr(scene) or nil
    if sets then
      for i=0,(tonumber(opts.maxSceneRoots) or 31) do
        local modelSet=a:ptr(sets+i*4);if not modelSet then break end
        local root=a:ptr(modelSet)
        if root and not seenRoot[root] then
          seenRoot[root]=true;rootCount=rootCount+1
          if type(opts.progress)=="function" then pcall(opts.progress,rootCount,0) end
          local model=select(1,extractRoot(a,root,opts))
          if model then
            for _,g in ipairs(model.groups or {}) do groups[#groups+1]=g end
            total=total+(tonumber(model.vertexCount) or 0)
            for k=1,3 do min[k]=math.min(min[k],model.bounds.min[k]);max[k]=math.max(max[k],model.bounds.max[k]) end
          end
        end
      end
    end
  end
  if total<60 then return nil,("no renderable HSD scene modelsets (%d roots)"):format(rootCount) end
  return {groups=groups,vertexCount=total,sceneRoots=rootCount,
    bounds={min=min,max=max,center={(min[1]+max[1])/2,(min[2]+max[2])/2,(min[3]+max[3])/2}}}
end

function H.extractModel(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local archives=H.findArchives(blob);if #archives==0 then return nil,"HSD archive not found" end
  local best=nil;local rootCount=0;local lastBudget=nil;local maxPartial=0;local shapeSeen=0
  for _,a in ipairs(archives) do
    local roots=candidateRoots(a,opts.maxRoots or 192)
    for ri,root in ipairs(roots) do
      rootCount=rootCount+1
      if type(opts.progress)=="function" and (ri==1 or ri%8==0) then pcall(opts.progress,ri,#roots) end
      local model,why,stats=extractRoot(a,root,opts)
      if why then lastBudget=why end
      if stats then
        if (stats.vertices or 0)>maxPartial then maxPartial=stats.vertices or 0 end
        if (stats.shapePobjs or 0)>shapeSeen then shapeSeen=stats.shapePobjs or 0 end
      end
      if model and (not best or model.vertexCount>best.vertexCount) then best=model;best.archive=a;best.root=root;best.stats=stats end
    end
  end
  if not best then
    local suffix=lastBudget and ("; last guard="..tostring(lastBudget)) or ""
    suffix=suffix..("; max partial=%d; shape POBJs=%d"):format(maxPartial,shapeSeen)
    return nil,("no renderable HSD JOBJ model found (%d archive%s, %d candidate root%s%s)"):format(#archives,#archives==1 and "" or "s",rootCount,rootCount==1 and "" or "s",suffix)
  end
  return best
end
return H
