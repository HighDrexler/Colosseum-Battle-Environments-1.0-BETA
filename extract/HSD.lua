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
-- Affine inverse (3x3 block via cofactor/adjugate, translation solved from it).
-- Needed to build a per-bone skinning matrix (world * invert(bindWorld)) for
-- vertices genuinely blended across more than one joint -- see the comment on
-- envelopeWorld below for why a single-bone envelope does not need this.
local function invertAffine(m)
  local a,b,c,tx=m[1],m[2],m[3],m[4]
  local d,e,f,ty=m[5],m[6],m[7],m[8]
  local g,h,i,tz=m[9],m[10],m[11],m[12]
  local det=a*(e*i-f*h)-b*(d*i-f*g)+c*(d*h-e*g)
  if abs(det)<1e-12 then return ident() end
  local id=1/det
  local A,B,C=(e*i-f*h)*id,(c*h-b*i)*id,(b*f-c*e)*id
  local D,E,F=(f*g-d*i)*id,(a*i-c*g)*id,(c*d-a*f)*id
  local G,H,I=(d*h-e*g)*id,(b*g-a*h)*id,(a*e-b*d)*id
  return {A,B,C,-(A*tx+B*ty+C*tz), D,E,F,-(D*tx+E*ty+F*tz), G,H,I,-(G*tx+H*ty+I*tz), 0,0,0,1}
end
local function point(m,x,y,z)return m[1]*x+m[2]*y+m[3]*z+m[4],m[5]*x+m[6]*y+m[7]*z+m[8],m[9]*x+m[10]*y+m[11]*z+m[12] end
-- A world matrix's scale along each local axis is the length of that axis's
-- column; an isotropic-equivalent single number (their geometric mean) is
-- near zero exactly when at least one axis has collapsed, even if the other
-- two look fine. Used to spot a joint whose world transform is degenerate
-- (collapses whatever mesh hangs off it to a point) without needing to know
-- anything about skinning, hidden flags, or the pose sampler -- see the
-- comment on noteJointWorld in extractRoot for why this is tracked per-joint
-- rather than per texture-merged render group.
local function worldScaleTrans(m)
  local sx=sqrt(m[1]*m[1]+m[5]*m[5]+m[9]*m[9])
  local sy=sqrt(m[2]*m[2]+m[6]*m[6]+m[10]*m[10])
  local sz=sqrt(m[3]*m[3]+m[7]*m[7]+m[11]*m[11])
  local scale=(sx*sy*sz)^(1/3)
  local trans=sqrt(m[4]*m[4]+m[8]*m[8]+m[12]*m[12])
  return scale,trans,sx,sy,sz
end
local function normal(m,x,y,z)local a,b,c=m[1]*x+m[2]*y+m[3]*z,m[5]*x+m[6]*y+m[7]*z,m[9]*x+m[10]*y+m[11]*z;local l=sqrt(a*a+b*b+c*c);if l<1e-9 then return 0,1,0 end;return a/l,b/l,c/l end
local function hasFlag(v,bit) return (tonumber(v) or 0)%(bit*2)>=bit end
local function hsdMatrix4x3(a,p)
  if not p or p+0x30>a.base+a.fileSize then return nil end
  local b=a.blob;local m={}
  for i=0,11 do
    local v=f32(b,p+i*4+1);if not finite(v) then return nil end;m[i+1]=v
  end
  return {m[1],m[2],m[3],m[4], m[5],m[6],m[7],m[8], m[9],m[10],m[11],m[12], 0,0,0,1}
end
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
local function nativeClipInfo(a,root,clipIndex)
  local clips=nativeAnimations(a,root)
  local ci=math.max(0,math.floor(tonumber(clipIndex) or 0))
  local ar=clips[ci+1]
  if not ar then return nil,#clips end
  local maxEnd=0
  local aobjs=0
  local seen={}
  local function walk(aj,depth)
    if not aj or seen[aj] or depth>256 then return end
    seen[aj]=true
    local aobj=a:ptr(aj+0x08)
    if aobj then
      aobjs=aobjs+1
      local ef=f32(a.blob,aobj+0x04+1)
      if finite(ef) and ef>=0 and ef<100000 and ef>maxEnd then maxEnd=ef end
    end
    walk(a:ptr(aj),depth+1)
    walk(a:ptr(aj+0x04),depth+1)
  end
  walk(ar,0)
  return {clip=ci,endFrame=maxEnd,frameCount=math.max(1,math.floor(maxEnd+.5)+1),aobjCount=aobjs,clipCount=#clips},#clips
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

-- Deep archive discovery for bounded one-time extraction jobs such as retail
-- capture .fdat members. Normal trainer/arena paths intentionally keep the
-- fast 64 KiB search in findArchives(); this variant may scan the full member.
function H.findArchivesDeep(blob,maxBytes)
  if type(blob)~="string" then return {} end
  local out,seen={},{}
  local limit=math.min(tonumber(maxBytes) or #blob,#blob)-0x20
  if limit<0 then return out end
  for base=0,limit,4 do
    local a=archiveAt(blob,base)
    if a and not seen[base] then seen[base]=true;out[#out+1]=a end
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
-- Legacy 1.5.20 helper-geometry heuristic. The old build tried to identify
-- invisible/helper meshes from texture presence, relative size and distance after
-- decoding. That can remove legitimate small untextured parts and is no longer
-- part of normal Pokemon extraction. Native JOBJ render-pass flags are now the
-- source of truth; this function remains only behind opts.filterPlaceholders for
-- controlled diagnostics.
local PLACEHOLDER_MAX_VERT_FRACTION=0.15
local PLACEHOLDER_MIN_DISTANCE_RATIO=1.5
local function groupBounds(verts)
  local min,max={1e30,1e30,1e30},{-1e30,-1e30,-1e30}
  for _,v in ipairs(verts) do
    for k=1,3 do if v[k]<min[k] then min[k]=v[k] end;if v[k]>max[k] then max[k]=v[k] end end
  end
  return min,max
end
local function filterPlaceholderGroups(groups)
  if #groups<2 then return groups,{} end
  local totalVerts=0
  for _,g in ipairs(groups) do totalVerts=totalVerts+#g.vertices end
  if totalVerts==0 then return groups,{} end
  -- Anchor on the group with the most vertices, textured or not: on a real
  -- model that is, overwhelmingly, going to be part of the body, and it does
  -- not depend on any group actually being textured (a fully vertex-colored
  -- source model would have none).
  local mainIdx,mainCount=1,#groups[1].vertices
  for i,g in ipairs(groups) do if #g.vertices>mainCount then mainIdx,mainCount=i,#g.vertices end end
  local mainMin,mainMax=groupBounds(groups[mainIdx].vertices)
  local mainCenter={(mainMin[1]+mainMax[1])/2,(mainMin[2]+mainMax[2])/2,(mainMin[3]+mainMax[3])/2}
  local mainExtent=sqrt((mainMax[1]-mainMin[1])^2+(mainMax[2]-mainMin[2])^2+(mainMax[3]-mainMin[3])^2)
  if mainExtent<1e-6 then return groups,{} end
  local kept,removed={},{}
  for i,g in ipairs(groups) do
    local isPlaceholder=false
    if i~=mainIdx and not g.texture then
      local frac=#g.vertices/totalVerts
      if frac<PLACEHOLDER_MAX_VERT_FRACTION then
        local gmin,gmax=groupBounds(g.vertices)
        local gcenter={(gmin[1]+gmax[1])/2,(gmin[2]+gmax[2])/2,(gmin[3]+gmax[3])/2}
        local d=sqrt((gcenter[1]-mainCenter[1])^2+(gcenter[2]-mainCenter[2])^2+(gcenter[3]-mainCenter[3])^2)
        if d>mainExtent*PLACEHOLDER_MIN_DISTANCE_RATIO then isPlaceholder=true end
      end
    end
    if isPlaceholder then
      removed[#removed+1]={index=i,vertices=#g.vertices}
    else
      kept[#kept+1]=g
    end
  end
  return kept,removed
end
-- Native HSD envelope skinning. PNMTXIDX selects an entry in the POBJ-local
-- envelope palette (slot * 3). Each envelope entry stores one or more
-- {HSD_JOBJ*, weight} pairs. Runtime deformation uses the joint's current world
-- matrix, its stored inverse-bind matrix, and (when present) the mesh owner's
-- envelope coordinate system. A 100% single-bone envelope hanging directly from
-- SKELETON_ROOT is a special runtime fast path: it uses joint.world with no IBM.
local MAX_ENVELOPE_BONES=24
local JOBJ_SKELETON=0x00000001
local JOBJ_SKELETON_ROOT=0x00000002

local function inverseBindFor(budget,jobj)
  local cached=budget.inverseBindResolved[jobj]
  if cached~=nil then return cached or ident() end
  local j=jobj
  while j do
    local m=budget.inverseBindByJobj[j]
    if m then budget.inverseBindResolved[jobj]=m;return m end
    j=budget.parentByJobj[j]
  end
  budget.inverseBindMissing=(budget.inverseBindMissing or 0)+1
  -- Native envelopes are expected to reference a joint with a stored IBM. If
  -- neither that joint nor an ancestor has one, HSD's importer-side semantics
  -- reduce to identity rather than inventing an inverse from the current pose.
  -- Using the posed world transform here feeds animation back into the bind
  -- correction and is exactly the kind of frame-dependent drift we must avoid.
  local m=ident()
  budget.inverseBindResolved[jobj]=m
  return m
end

local function findSkeletonOwner(budget,jobj)
  local j=jobj
  while j do
    local flags=budget.flagsByJobj[j] or 0
    if hasFlag(flags,JOBJ_SKELETON_ROOT) or hasFlag(flags,JOBJ_SKELETON) then return j end
    j=budget.parentByJobj[j]
  end
end

-- Mirrors HSD's _HSD_mkEnvelopeModelNodeMtx semantics used by native PKX
-- models. This owner-relative coordinate system is the piece the old CBE
-- Pokemon path omitted entirely; omitting it disassembles even 100%-single-bone
-- envelopes when the mesh owner is below a skeleton node.
local function envelopeCoordSystem(budget,ownerJobj)
  if not ownerJobj then return nil end
  local cached=budget.envelopeCoordCache[ownerJobj]
  if cached~=nil then return cached or nil end
  local ownerFlags=budget.flagsByJobj[ownerJobj] or 0
  if hasFlag(ownerFlags,JOBJ_SKELETON_ROOT) then budget.envelopeCoordCache[ownerJobj]=false;return nil end
  local skel=findSkeletonOwner(budget,ownerJobj)
  if not skel then budget.envelopeCoordCache[ownerJobj]=false;return nil end
  local ownerWorld=budget.worldByJobj[ownerJobj] or ident()
  local ownerInvBind=inverseBindFor(budget,ownerJobj)
  local coord
  if skel==ownerJobj then
    coord=invertAffine(ownerInvBind)
  elseif hasFlag(budget.flagsByJobj[skel] or 0,JOBJ_SKELETON_ROOT) then
    coord=mul(invertAffine(budget.worldByJobj[skel] or ident()),ownerWorld)
  else
    local skelWorld=budget.worldByJobj[skel] or ident()
    coord=mul(invertAffine(mul(skelWorld,ownerInvBind)),ownerWorld)
  end
  budget.envelopeCoordCache[ownerJobj]=coord
  return coord
end

local function legacyEnvelopeWorld(a,pobj,v,defaultWorld,budget)
  local raw=v[0] and tonumber(v[0][1]) or 0;local index=floor(raw/3)
  local tablePtr=a:ptr(pobj+0x14);local envelope=tablePtr and a:ptr(tablePtr+index*4) or nil
  if not envelope then return defaultWorld end
  local bones={};local p=envelope
  for _=1,MAX_ENVELOPE_BONES do
    local bone=a:ptr(p);if not bone then break end
    local w=f32(a.blob,p+4+1);local bw=budget.worldByJobj[bone]
    if bw and w and w>0 then bones[#bones+1]={bone=bone,bw=bw,w=w} end;p=p+8
  end
  if #bones==0 then return defaultWorld end
  if #bones==1 then return bones[1].bw end
  local acc,total={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0},0
  for _,e in ipairs(bones) do for k=1,16 do acc[k]=acc[k]+e.bw[k]*e.w end;total=total+e.w end
  if total>1e-6 and abs(total-1)>1e-4 then for k=1,16 do acc[k]=acc[k]/total end end
  return acc
end

local function envelopeWorld(a,pobj,v,defaultWorld,budget,ownerJobj)
  if budget.skinFix==false then return legacyEnvelopeWorld(a,pobj,v,defaultWorld,budget) end
  local raw=v[0] and tonumber(v[0][1]) or 0
  local index=floor(raw/3)
  local byPobj=budget.envelopeWorldCache[pobj]
  if not byPobj then byPobj={};budget.envelopeWorldCache[pobj]=byPobj end
  local cached=byPobj[index]
  if cached~=nil then return cached or defaultWorld end
  local tablePtr=a:ptr(pobj+0x14)
  local envelope=tablePtr and a:ptr(tablePtr+index*4) or nil
  if not envelope then byPobj[index]=false;return defaultWorld end

  local entries={};local p=envelope
  for _=1,MAX_ENVELOPE_BONES do
    local bone=a:ptr(p);if not bone then break end
    local w=f32(a.blob,p+4+1)
    if budget.worldByJobj[bone] and w and w>0 then entries[#entries+1]={bone=bone,w=w} end
    p=p+8
  end
  if #entries==0 then byPobj[index]=false;return defaultWorld end

  local coord=envelopeCoordSystem(budget,ownerJobj)
  local matrix
  if #entries==1 and entries[1].w>=0.999999 then
    local e=entries[1];matrix=e and budget.worldByJobj[e.bone]
    if coord then
      matrix=mul(mul(matrix,inverseBindFor(budget,e.bone)),coord)
      budget.singleEnvelopeCoord=(budget.singleEnvelopeCoord or 0)+1
    else
      budget.singleEnvelopeNoCoord=(budget.singleEnvelopeNoCoord or 0)+1
    end
  else
    local acc={0,0,0,0,0,0,0,0,0,0,0,0,0,0,0,0}
    for _,e in ipairs(entries) do
      local contribution=mul(budget.worldByJobj[e.bone],inverseBindFor(budget,e.bone))
      for k=1,16 do acc[k]=acc[k]+contribution[k]*e.w end
    end
    matrix=coord and mul(acc,coord) or acc
    budget.envelopeBlendsMulti=(budget.envelopeBlendsMulti or 0)+1
  end
  budget.envelopeBlends=(budget.envelopeBlends or 0)+1
  if coord then budget.envelopeCoordEntries=(budget.envelopeCoordEntries or 0)+1 end
  byPobj[index]=matrix
  return matrix
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
local function parseDisplay(a,pobj,world,budget,ownerJobj)
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
        local vertexWorld
        if pobjFlags%0x4000>=0x2000 then
          vertexWorld=envelopeWorld(a,pobj,v,world,budget,ownerJobj)
        else
          vertexWorld=world
        end
        local x,y,z=pos[1] or 0,pos[2] or 0,pos[3] or 0;local wx,wy,wz=point(vertexWorld,x,y,z)
        local uv=v[13] or {0,0};local nr=v[10] or v[25] or {0,1,0};local nx,ny,nz=normal(vertexWorld,nr[1] or 0,nr[2] or 1,nr[3] or 0)
        rows[#rows+1]={wx,wy,wz,uv[1] or 0,uv[2] or 0,nx,ny,nz}
      end
    end
    if budget.exhausted then break end
  end
  return rows
end
local function decodeTextureObject(a,tobj,slot)
  if not tobj then return nil end
  local img=a:ptr(tobj+0x4C);if not img then return nil end
  local b=a.blob;local data=a:ptr(img);local w,h=u16(b,img+5),u16(b,img+7);local fmt=u32(b,img+9)
  if not data or not w or not h or not fmt or w==0 or h==0 or w>2048 or h>2048 then return nil end
  local n=GX.dataSize(w,h,fmt);if data+n>a.base+a.fileSize then return nil end
  local palette,palFmt,pp=nil,nil,nil;local tlut=a:ptr(tobj+0x50)
  if tlut then pp=a:ptr(tlut);palFmt=u32(b,tlut+5);local count=u16(b,tlut+0x0C+1) or 0;if pp and count>0 and pp+count*2<=a.base+a.fileSize then palette=b:sub(pp+1,pp+count*2) end end
  -- A venue commonly references the same large atlas from many DOBJ groups.
  -- Pure-Lua GX decoding is expensive, so cache immutable decoded pixels per
  -- archive/image/palette identity while retaining each TOBJ's own render state.
  a._decodedTextures=a._decodedTextures or {}
  local key=("%d:%d:%d:%d:%d"):format(data,w,h,fmt,pp or -1)
  local rgba=a._decodedTextures[key]
  if not rgba then
    local ok,decoded=pcall(GX.decode,b:sub(data+1,data+n),w,h,fmt,palette,palFmt)
    if not ok then return nil end
    rgba=decoded;a._decodedTextures[key]=rgba
  end
  -- Preserve source TOBJ metadata. The current actor shader only consumes the
  -- image/wrap state, but keeping the remaining values with the group prevents
  -- us from having to rediscover which texture stage was actually enabled.
  local wrapS=u32(b,tobj+0x34+1)
  local wrapT=u32(b,tobj+0x38+1)
  return {
    w=w,h=h,format=fmt,rgba=rgba,dataOffset=data-a.data,
    wrapS=wrapS,wrapT=wrapT,slot=slot or 0,
    texgen=u32(b,tobj+0x0C+1) or 0,
    flags=u32(b,tobj+0x40+1) or 0,
  }
end

-- HSD_MOBJ can carry a chain of up to eight TOBJs, while RenderFlags TEX0..TEX7
-- decides which stages are actually sampled. 1.5.24 always decoded the FIRST
-- pointer in the chain even when TEX0 was disabled; that can bind a shadow/
-- auxiliary map as the Pokemon's diffuse image or report an active material as
-- "untextured". Match the native material contract and select the first ENABLED
-- stage instead.
local function firstEnabledTexture(a,mobj)
  if not mobj then return nil end
  local b=a.blob
  local renderFlags=u32(b,mobj+0x04+1) or 0
  local tobj=a:ptr(mobj+0x08)
  local slot=0
  while tobj and slot<8 do
    local enabled=(math.floor(renderFlags/(2^(slot+4)))%2)==1
    if enabled then
      local tex=decodeTextureObject(a,tobj,slot)
      if tex then return tex end
    end
    tobj=a:ptr(tobj+0x04)
    slot=slot+1
  end
  return nil
end

local function materialInfo(a,mobj)
  if not mobj then return nil end
  local b=a.blob
  local flags=u32(b,mobj+0x04+1) or 0
  local mat=a:ptr(mobj+0x0C)
  local info={
    -- SysDolphin HSD_MOBJ RENDER_MODE bits. Preserve the full word instead of
    -- collapsing it to xlu/no-z; Pokemon materials rely on constant color,
    -- alpha and special shadow/effect passes even when no ordinary texture is
    -- attached.
    renderFlags=flags,
    xlu=(math.floor(flags/0x40000000)%2)==1,
    noz=(math.floor(flags/0x20000000)%2)==1,
    shadow=(math.floor(flags/0x04000000)%2)==1,
    effect=(math.floor(flags/0x02000000)%2)==1,
    useConstant=(math.floor(flags/0x1)%2)==1,
    useVertexColor=(math.floor(flags/0x2)%2)==1,
    useDiffuseLighting=(math.floor(flags/0x4)%2)==1,
    textureMask=math.floor(flags/0x10)%256,
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
-- Return only the authoritative HSD_SceneModelSet roots advertised by
-- scene_data. Character PKX files already tell us exactly which JOBJ root(s)
-- belong to the model; relocation-derived "plausible" roots are only a recovery
-- heuristic for malformed/legacy assets and can decode arbitrary data blocks as
-- extra geometry. Pokemon extraction opts into this semantic-only path.
local function semanticModelRoots(a,maxRoots)
  maxRoots=tonumber(maxRoots) or 192
  local roots,seen={},{}
  local scene=a:publicSymbol("scene_data")
  local sets=scene and a:ptr(scene) or nil
  if not sets then return roots end
  for i=0,maxRoots-1 do
    local modelSet=a:ptr(sets+i*4)
    if not modelSet then break end
    local root=a:ptr(modelSet)
    if root and plausibleJobj(a,root) and not seen[root] then
      seen[root]=true
      roots[#roots+1]=root
    end
  end
  return roots
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
  local worldByJobj={};local mapSeen={};local jointWorlds={};local jointIndexByJobj={};local jointParents={}
  local parentByJobj={};local flagsByJobj={};local inverseBindByJobj={}
  local function jobjSRT(j)
    local v=pose and pose[j]
    if v then return v[1],v[2],v[3],v[4],v[5],v[6],v[7],v[8],v[9] end
    local b=a.blob;return f32(b,j+0x14+1) or 0,f32(b,j+0x18+1) or 0,f32(b,j+0x1C+1) or 0,
      f32(b,j+0x20+1) or 1,f32(b,j+0x24+1) or 1,f32(b,j+0x28+1) or 1,
      f32(b,j+0x2C+1) or 0,f32(b,j+0x30+1) or 0,f32(b,j+0x34+1) or 0
  end
  local function mapWorld(j,parent,parentJobj,depth)
    if not j or mapSeen[j] or depth>256 or not plausibleJobj(a,j) then return end
    mapSeen[j]=true
    parentByJobj[j]=parentJobj
    flagsByJobj[j]=u32(a.blob,j+0x04+1) or 0
    local ibp=a:ptr(j+0x38);if ibp then inverseBindByJobj[j]=hsdMatrix4x3(a,ibp) end
    -- PNMTXIDX is resolved inside each enveloped POBJ's own matrix palette; it
    -- is deliberately NOT interpreted as an index into this JOBJ traversal.
    local rx,ry,rz,sx,sy,sz,tx,ty,tz=jobjSRT(j)
    local world=mul(parent,localM(rx,ry,rz,sx,sy,sz,tx,ty,tz));worldByJobj[j]=world
    -- ModelSequence/PKX body-map indices address the model's ordered JOBJ
    -- array. HSD builds that order with the same child-before-sibling DFS used
    -- here. Preserve the full source joint origin table so battle particles can
    -- attach to Mouth/Chest/Tail/Hands instead of a percentage of model height.
    local ji=#jointWorlds
    jointIndexByJobj[j]=ji
    jointWorlds[ji+1]={world[4] or 0,world[8] or 0,world[12] or 0}
    -- Preserve the source skeleton topology as 1-based parent indices.  This
    -- lets trainer/capture code select a real arm end-effector instead of
    -- guessing "hand" from height alone (which rejects a lowered throwing
    -- wrist and can incorrectly attach the ball to an elbow/shoulder).
    local parentIndex=parentJobj and jointIndexByJobj[parentJobj] or nil
    jointParents[ji+1]=parentIndex and (parentIndex+1) or 0
    mapWorld(a:ptr(j+0x08),world,j,depth+1);mapWorld(a:ptr(j+0x0C),parent,parentJobj,depth+1)
  end
  mapWorld(root,ident(),nil,0)
  local budget={displayOps=0,vertices=0,maxDisplayOps=opts.maxDisplayOps or 80000,maxVertices=opts.maxVertices or 30000,jobjs=0,dobjs=0,pobjs=0,shapeIndexMap=opts.shapeIndexMap~=false,worldByJobj=worldByJobj,parentByJobj=parentByJobj,flagsByJobj=flagsByJobj,inverseBindByJobj=inverseBindByJobj,inverseBindResolved={},envelopeCoordCache={},envelopeWorldCache={},skinFix=opts.skinFix~=false,honorRenderPass=opts.honorRenderPass==true,skipShadowMaterials=opts.skipShadowMaterials==true,filterPlaceholders=opts.filterPlaceholders==true}
  local maxJobjs=opts.maxJobjs or 1024;local maxDobjs=opts.maxDobjs or 4096;local maxPobjs=opts.maxPobjs or 8192
  -- Keep joint-world diagnostics because they are useful for detecting a truly
  -- degenerate source transform. Enveloped vertices are placed by their palette
  -- matrices below; this statistic is diagnostic only and never substitutes for
  -- HSD skinning semantics.
  local jointSeen={};local jointStats={}
  local function noteJointWorld(j,world)
    if jointSeen[j] then return end
    jointSeen[j]=true
    local scale,trans=worldScaleTrans(world)
    jointStats[#jointStats+1]={jobj=j,scale=scale,trans=trans}
  end
  local function walk(j,parent,depth)
    if budget.exhausted or not j or seen[j] or depth>256 or not plausibleJobj(a,j) then return end
    budget.jobjs=budget.jobjs+1;if budget.jobjs>maxJobjs then budget.exhausted="JOBJ traversal budget";return end
    seen[j]=true
    local b=a.blob;local rx,ry,rz,sx,sy,sz,tx,ty,tz=jobjSRT(j)
    local world=mul(parent,localM(rx,ry,rz,sx,sy,sz,tx,ty,tz))
    local flags=u32(b,j+0x04+1) or 0
    -- SysDolphin HSD_JObj visibility/type bits. Pokemon extraction honors both
    -- explicit HIDDEN and the native OPA/XLU/TEXEDGE render-pass membership;
    -- zero-pass helper geometry must never become an ordinary CBE mesh.
    local isSpline=hasFlag(flags,0x00004000)       -- JOBJ_SPLINE
    local isParticle=hasFlag(flags,0x00000020)     -- JOBJ_PTCL
    local isHidden=hasFlag(flags,0x00000010)       -- JOBJ_HIDDEN
    -- Native Colosseum renders JOBJ geometry only when it participates in at
    -- least one OPA/XLU/TEXEDGE pass. Earlier CBE drew zero-pass helper/proxy
    -- geometry as ordinary white meshes; this is the source-faithful filter for
    -- that class of junk and replaces the 1.5.20 spatial guess.
    local noRenderPass=not (hasFlag(flags,0x00040000) or hasFlag(flags,0x00080000) or hasFlag(flags,0x00100000))
    if isHidden then budget.hiddenJobjs=(budget.hiddenJobjs or 0)+1 end
    if budget.honorRenderPass and noRenderPass then budget.nonRenderJobjs=(budget.nonRenderJobjs or 0)+1 end
    -- JOBJ_USE_QUATERNION (1<<17): when set, the three "rotation" floats are
    -- quaternion components, not Euler angles. Reading them as Euler yields
    -- wrong orientations. Counted here so the diagnostic can say whether any
    -- joint in a given model actually uses it.
    if flags%0x40000>=0x20000 then budget.quatJobjs=(budget.quatJobjs or 0)+1 end
    local skipJobjGeometry=isSpline or isParticle or isHidden or (budget.honorRenderPass and noRenderPass)
    local dobj=nil
    if not skipJobjGeometry then dobj=a:ptr(j+0x10) end
    local localD=0
    while dobj and localD<256 and not budget.exhausted do
      localD=localD+1;budget.dobjs=budget.dobjs+1;if budget.dobjs>maxDobjs then budget.exhausted="DOBJ traversal budget";break end
      local mobj=a:ptr(dobj+0x08);local pobj=a:ptr(dobj+0x0C)
      local tex,texLoaded=nil,false
      local mat=materialInfo(a,mobj);local localP=0

      -- Native HSD dispatches at DOBJ granularity, not merely JOBJ granularity:
      -- opaque materials render only through an OPA owner, while XLU materials
      -- require XLU/TEXEDGE. 1.5.24 treated "owner has ANY render pass" as
      -- permission to draw every DOBJ hanging from it, which can surface
      -- auxiliary material chains the game never submits in that pass.
      local dobjPassOK=true
      if budget.honorRenderPass and mat then
        if mat.xlu then
          dobjPassOK=hasFlag(flags,0x00080000) or hasFlag(flags,0x00100000)
        else
          dobjPassOK=hasFlag(flags,0x00040000)
        end
        if not dobjPassOK then budget.nonRenderDobjs=(budget.nonRenderDobjs or 0)+1 end
      end

      -- RENDER_SHADOW is a dedicated source shadow pass, not body-surface
      -- geometry. CBE already owns arena-side grounding/shadows, and drawing the
      -- caster/pass mesh as an ordinary diffuse mesh is exactly how a white
      -- box/plate can appear around an otherwise recognizable Pokemon.
      local shadowPass=mat and mat.shadow and budget.skipShadowMaterials
      if shadowPass then budget.shadowDobjs=(budget.shadowDobjs or 0)+1 end
      if not dobjPassOK or shadowPass then pobj=nil end

      while pobj and localP<1024 and not budget.exhausted do
        localP=localP+1;budget.pobjs=budget.pobjs+1;if budget.pobjs>maxPobjs then budget.exhausted="POBJ traversal budget";break end
        local rows=parseDisplay(a,pobj,world,budget,j)
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
              tex=nil
              if opts.textures~=false then tex=firstEnabledTexture(a,mobj) end
              texLoaded=true
            end
            for _,v in ipairs(rows) do for k=1,3 do if v[k]<min[k] then min[k]=v[k] end;if v[k]>max[k] then max[k]=v[k] end end end
            vertices=vertices+#rows;budget.vertices=vertices
            noteJointWorld(j,world)
            groups[#groups+1]={vertices=rows,texture=tex,
              alpha=mat and mat.alpha or 1,xlu=mat and mat.xlu or false,noz=mat and mat.noz or false,
              diffuse=mat and mat.diffuse or nil,ambient=mat and mat.ambient or nil,
              specular=mat and mat.specular or nil,shininess=mat and mat.shininess or nil,
              renderFlags=mat and mat.renderFlags or 0,shadow=mat and mat.shadow or false,
              effect=mat and mat.effect or false,useConstant=mat and mat.useConstant or false,
              useVertexColor=mat and mat.useVertexColor or false,
              useDiffuseLighting=mat and mat.useDiffuseLighting or false,
              textureSlot=tex and tex.slot or -1}
          end
        end
        pobj=a:ptr(pobj+0x04)
      end
      dobj=a:ptr(dobj+0x04)
    end
    walk(a:ptr(j+0x08),world,depth+1);walk(a:ptr(j+0x0C),parent,depth+1)
  end
  walk(root,ident(),0)
  local jointScaleMin,jointScaleMax,jointScaleMedian,jointOutliers=nil,nil,nil,0
  if #jointStats>0 then
    local sorted={}
    for i,js in ipairs(jointStats) do sorted[i]=js.scale end
    table.sort(sorted)
    jointScaleMin,jointScaleMax=sorted[1],sorted[#sorted]
    jointScaleMedian=sorted[math.ceil(#sorted/2)]
    for _,s in ipairs(sorted) do
      if jointScaleMedian>1e-6 and (s<jointScaleMedian*0.1 or s>jointScaleMedian*10) then jointOutliers=jointOutliers+1 end
    end
  end
  local filteredGroups,removedGroups=groups,{}
  if budget.filterPlaceholders then filteredGroups,removedGroups=filterPlaceholderGroups(groups) end
  local placeholderVerts=0
  for _,r in ipairs(removedGroups) do placeholderVerts=placeholderVerts+r.vertices end
  local stats={vertices=vertices,shapePobjs=budget.shapePobjs or 0,envelopePobjs=budget.envelopePobjs or 0,displayOps=budget.displayOps or 0,jobjs=budget.jobjs or 0,pobjs=budget.pobjs or 0,nativeClipCount=clipCount,nativePoseApplied=pose~=nil,envelopeBlends=budget.envelopeBlends or 0,
    envelopeBlendsMulti=budget.envelopeBlendsMulti or 0,skinFix=budget.skinFix,
    hiddenJobjs=budget.hiddenJobjs or 0,quatJobjs=budget.quatJobjs or 0,
    jointCount=#jointStats,jointScaleMin=jointScaleMin,jointScaleMedian=jointScaleMedian,jointScaleMax=jointScaleMax,jointScaleOutliers=jointOutliers,
    envelopeCoordEntries=budget.envelopeCoordEntries or 0,singleEnvelopeCoord=budget.singleEnvelopeCoord or 0,singleEnvelopeNoCoord=budget.singleEnvelopeNoCoord or 0,inverseBindMissing=budget.inverseBindMissing or 0,
    honorRenderPass=budget.honorRenderPass,nonRenderJobjs=budget.nonRenderJobjs or 0,
    nonRenderDobjs=budget.nonRenderDobjs or 0,shadowDobjs=budget.shadowDobjs or 0,
    placeholderGroupsRemoved=#removedGroups,placeholderVertsRemoved=placeholderVerts}
  if budget.exhausted then return nil,budget.exhausted,stats end
  if vertices<60 then return nil,"too few renderable vertices",stats end
  -- Bounds cover source-visible geometry accepted by the decoder. The optional
  -- legacy spatial placeholder filter (normally OFF) runs after these numbers.
  return {groups=filteredGroups,vertexCount=vertices,jointPositions=jointWorlds,jointParents=jointParents,
    bounds={min=min,max=max,center={(min[1]+max[1])/2,(min[2]+max[2])/2,(min[3]+max[3])/2}}},nil,stats
end

local function archiveDiag(a)
  local names={};for _,s in ipairs(a:publicSymbols()) do if s.name and s.name~="" then names[#names+1]=s.name end end
  local roots=candidateRoots(a,128)
  return {base=a.base,fileSize=a.fileSize,dataSize=a.dataSize,relocations=a.relocCount,publicCount=a.publicCount,symbols=names,candidateRoots=#roots}
end

-- Test-only hooks. Nothing in the mod itself reads H._internal; it exists so
-- the matrix algebra behind envelope skinning can be verified directly
-- against known cases instead of only through a full binary archive.
H._internal={mul=mul,ident=ident,localM=localM,point=point,invertAffine=invertAffine,worldScaleTrans=worldScaleTrans,hsdMatrix4x3=hsdMatrix4x3,filterPlaceholderGroups=filterPlaceholderGroups,groupBounds=groupBounds}

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
    local roots=semanticModelRoots(a,(tonumber(opts.maxSceneRoots) or 31)+1)
    for _,root in ipairs(roots) do
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
  if total<60 then return nil,("no renderable HSD scene modelsets (%d roots)"):format(rootCount) end
  return {groups=groups,vertexCount=total,sceneRoots=rootCount,
    bounds={min=min,max=max,center={(min[1]+max[1])/2,(min[2]+max[2])/2,(min[3]+max[3])/2}}}
end

-- Return the source HSD animation timing for a model previously decoded by
-- extractModel. Type-2 Waza effect models use this to stay on the retail 60 Hz
-- animation clock instead of guessing a display duration.
function H.nativeAnimationInfo(model,clipIndex)
  if type(model)~="table" or not model.archive or not model.root then return nil,"decoded HSD model required" end
  return nativeClipInfo(model.archive,model.root,clipIndex or 0)
end

-- Re-evaluate one exact source HSD animation frame against the same archive/root
-- selected by extractModel. Keeping root identity fixed guarantees topology is
-- stable enough for Waza GPU morph pages and avoids candidate-root reselection.
function H.extractNativePose(model,clipIndex,frame,opts)
  if type(model)~="table" or not model.archive or not model.root then return nil,"decoded HSD model required" end
  opts=opts or {}
  local o={}
  for k,v in pairs(opts) do o[k]=v end
  o.nativePose={clip=tonumber(clipIndex) or 0,frame=tonumber(frame) or 0}
  return extractRoot(model.archive,model.root,o)
end

-- Enumerate every renderable HSD JOBJ model root in a source blob.
-- Capture extraction uses this because the retail snatch_*.fdat member can
-- contain several HSD roots: the physical ball is not guaranteed to be the
-- largest root and is not guaranteed to live inside a Waza type-2 payload.
function H.extractModels(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local archives=H.findArchives(blob)
  if #archives==0 and type(H.findArchivesDeep)=="function" then archives=H.findArchivesDeep(blob,#blob) end
  if #archives==0 then return nil,"HSD archive not found" end
  local out={};local rootCount=0;local lastBudget=nil
  for _,a in ipairs(archives) do
    local roots=opts.semanticRootsOnly
      and semanticModelRoots(a,opts.maxRoots or 192)
      or candidateRoots(a,opts.maxRoots or 192)
    for ri,root in ipairs(roots) do
      rootCount=rootCount+1
      if type(opts.progress)=="function" and (ri==1 or ri%8==0) then pcall(opts.progress,ri,#roots) end
      local model,why,stats=extractRoot(a,root,opts)
      if why then lastBudget=why end
      if model then
        model.archive=a;model.root=root;model.stats=stats
        model.semanticRootsOnly=opts.semanticRootsOnly==true
        model.semanticRootCount=#roots
        out[#out+1]=model
      end
    end
  end
  if #out==0 then
    local suffix=lastBudget and ("; last guard="..tostring(lastBudget)) or ""
    return nil,("no renderable HSD JOBJ models found (%d archive%s, %d candidate root%s%s)"):format(
      #archives,#archives==1 and "" or "s",rootCount,rootCount==1 and "" or "s",suffix)
  end
  table.sort(out,function(a,b)return (tonumber(a.vertexCount) or 0)>(tonumber(b.vertexCount) or 0) end)
  return out
end

function H.extractModel(blob,opts)
  opts=opts or {}
  if type(blob)~="string" then return nil,"HSD source is not bytes" end
  local archives=H.findArchives(blob);if #archives==0 then return nil,"HSD archive not found" end
  local best=nil;local rootCount=0;local lastBudget=nil;local maxPartial=0;local shapeSeen=0
  for _,a in ipairs(archives) do
    -- Character PKX files expose authoritative model roots through scene_data.
    -- When semanticRootsOnly is requested (PokemonActors), do NOT let a larger
    -- relocation-derived false root beat the real model merely because garbage
    -- pointers happened to decode into extra triangles.
    local roots=opts.semanticRootsOnly
      and semanticModelRoots(a,opts.maxRoots or 192)
      or candidateRoots(a,opts.maxRoots or 192)
    for ri,root in ipairs(roots) do
      rootCount=rootCount+1
      if type(opts.progress)=="function" and (ri==1 or ri%8==0) then pcall(opts.progress,ri,#roots) end
      local model,why,stats=extractRoot(a,root,opts)
      if why then lastBudget=why end
      if stats then
        if (stats.vertices or 0)>maxPartial then maxPartial=stats.vertices or 0 end
        if (stats.shapePobjs or 0)>shapeSeen then shapeSeen=stats.shapePobjs or 0 end
      end
      if model and (not best or model.vertexCount>best.vertexCount) then
        best=model;best.archive=a;best.root=root;best.stats=stats
        best.semanticRootsOnly=opts.semanticRootsOnly==true
        best.semanticRootCount=#roots
      end
    end
  end
  if not best then
    local suffix=lastBudget and ("; last guard="..tostring(lastBudget)) or ""
    if opts.semanticRootsOnly then suffix=suffix.."; semantic scene-modelset roots only" end
    suffix=suffix..("; max partial=%d; shape POBJs=%d"):format(maxPartial,shapeSeen)
    return nil,("no renderable HSD JOBJ model found (%d archive%s, %d candidate root%s%s)"):format(#archives,#archives==1 and "" or "s",rootCount,rootCount==1 and "" or "s",suffix)
  end
  return best
end
return H
