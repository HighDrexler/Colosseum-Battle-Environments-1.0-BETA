local M={}
local IMPORT_ID="pokemon_colosseum_usa"
local ISO_SIZE=1459978240
local CISO_HEADER_SIZE=0x8000
local MAX_IMPORT_READ=8*1024*1024

local function u32be(s,p)
  local a,b,c,d=s:byte(p,p+3);if not d then return nil end
  return ((a*256+b)*256+c)*256+d
end
local function u32le(s,p)
  local a,b,c,d=s:byte(p,p+3);if not d then return nil end
  return a+b*256+c*65536+d*16777216
end
local function cstring(s,p)
  p=(p or 0)+1;local e=s:find("\0",p,true) or (#s+1);return s:sub(p,e-1)
end
local function clean(s) return (tostring(s or ""):gsub("[%z\1-\31]","_")) end
local function powerOfTwo(n)
  if not n or n<1 then return false end
  while n>1 do if n%2~=0 then return false end;n=n/2 end
  return true
end

function M.open(mod)
  assert(mod and mod.imports,"mod.imports is required")
  local info,err=mod.imports:info(IMPORT_ID);assert(info,err or "Colosseum source unavailable")
  local containerSize=assert(tonumber(info.size),"Colosseum source size unavailable")
  assert(containerSize>0,"Colosseum source is empty")

  local self={mod=mod,info=info,files={},byPath={},byBase={},containerSize=containerSize,logicalSize=ISO_SIZE}
  local function rawRead(offset,length)
    assert(type(offset)=="number" and type(length)=="number" and offset>=0 and length>=0,"invalid source range")
    if length==0 then return "" end
    assert(offset+length<=containerSize,"source read exceeds imported container")
    local parts={};local at=offset;local left=length
    while left>0 do
      local n=math.min(left,MAX_IMPORT_READ)
      local bytes,e=self.mod.imports:read(IMPORT_ID,at,n);assert(bytes,e or "source read failed")
      assert(#bytes==n,"short source read")
      parts[#parts+1]=bytes;at=at+n;left=left-n
    end
    return table.concat(parts)
  end

  local probe=rawRead(0,math.min(containerSize,CISO_HEADER_SIZE))
  if probe:sub(1,4)=="CISO" then
    assert(#probe>=CISO_HEADER_SIZE,"truncated GameCube CISO header")
    local blockSize=u32le(probe,5)
    assert(blockSize and blockSize>=32768 and blockSize<=16*1024*1024 and powerOfTwo(blockSize),"unsupported GameCube CISO block size")
    local map=probe:sub(9,CISO_HEADER_SIZE)
    local blockCount=math.floor((ISO_SIZE+blockSize-1)/blockSize)
    assert(blockCount<=#map,"GameCube CISO map is too small for a full disc")
    local physical={};local used=0
    for i=1,blockCount do
      local flag=map:byte(i)
      assert(flag==0 or flag==1,"invalid GameCube CISO allocation map")
      if flag==1 then physical[i]=used;used=used+1 end
    end
    assert(physical[1]==0,"GameCube CISO does not contain the disc header block")
    local dataEnd=CISO_HEADER_SIZE+used*blockSize
    assert(dataEnd<=containerSize,"GameCube CISO is truncated")
    self.sourceFormat="ciso"
    self.ciso={headerSize=CISO_HEADER_SIZE,blockSize=blockSize,blockCount=blockCount,usedBlocks=used,trailingBytes=containerSize-dataEnd,physical=physical}
    function self:read(offset,length)
      assert(type(offset)=="number" and type(length)=="number" and offset>=0 and length>=0,"invalid disc range")
      if length==0 then return "" end
      assert(offset+length<=self.logicalSize,"disc read exceeds logical ISO")
      local parts={};local at=offset;local left=length
      while left>0 do
        local logicalIndex=math.floor(at/blockSize)+1
        local inBlock=at%blockSize
        local n=math.min(left,blockSize-inBlock)
        local physicalIndex=physical[logicalIndex]
        if physicalIndex==nil then
          parts[#parts+1]=string.rep("\0",n)
        else
          parts[#parts+1]=rawRead(CISO_HEADER_SIZE+physicalIndex*blockSize+inBlock,n)
        end
        at=at+n;left=left-n
      end
      return table.concat(parts)
    end
  else
    assert(containerSize==ISO_SIZE,"unexpected Colosseum ISO/GCM source size")
    self.sourceFormat="iso"
    function self:read(offset,length)
      assert(type(offset)=="number" and type(length)=="number" and offset>=0 and length>=0,"invalid disc range")
      assert(offset+length<=self.logicalSize,"disc read exceeds source")
      return rawRead(offset,length)
    end
  end

  local header=self:read(0,0x440)
  assert(header:sub(1,6)=="GC6E01","source is not Pokémon Colosseum USA")
  assert(header:byte(7)==0 and header:byte(8)==0,"unsupported Colosseum disc revision")
  assert(u32be(header,0x1C+1)==0xC2339F3D,"invalid GameCube disc magic")
  local fstOff,fstSize=u32be(header,0x424+1),u32be(header,0x428+1)
  assert(fstOff and fstSize and fstOff>0 and fstSize>=12 and fstOff+fstSize<=self.logicalSize,"invalid GameCube FST")
  local root=self:read(fstOff,12);local count=u32be(root,9)
  assert(count and count>0 and count<200000,"invalid GameCube FST entry count")
  local tableBytes=count*12;assert(tableBytes<=fstSize,"invalid GameCube FST table size")
  local entries=self:read(fstOff,tableBytes);local names=self:read(fstOff+tableBytes,fstSize-tableBytes)
  local rows={}
  for i=0,count-1 do
    local p=i*12+1;local a,b,c=u32be(entries,p),u32be(entries,p+4),u32be(entries,p+8)
    rows[i]={dir=math.floor(a/0x1000000)~=0,name=clean(cstring(names,a%0x1000000)),a=b,b=c}
  end
  local function visit(idx,prefix)
    local d=assert(rows[idx],"missing FST directory");local i=idx+1
    while i<d.b do
      local e=assert(rows[i],"missing FST child");local path=(prefix=="" and e.name) or (prefix.."/"..e.name)
      if e.dir then visit(i,path);i=e.b else
        assert(e.a+e.b<=self.logicalSize,"FST member exceeds disc")
        local f={path=path,offset=e.a,size=e.b,index=i};self.files[#self.files+1]=f
        self.byPath[path:lower()]=f
        local base=path:match("([^/]+)$"):lower();self.byBase[base]=self.byBase[base] or {};self.byBase[base][#self.byBase[base]+1]=f
        i=i+1
      end
    end
  end
  visit(0,"")
  table.sort(self.files,function(a,b)return a.path<b.path end)
  self.header=header;self.fstOffset=fstOff;self.fstSize=fstSize
  function self:file(path)
    if not path then return nil end
    local q=tostring(path):lower();local hit=self.byPath[q];if hit then return hit end
    local base=q:match("([^/]+)$");local hits=self.byBase[base];return hits and hits[1] or nil
  end
  function self:find(pattern)
    pattern=tostring(pattern or ""):lower();local out={}
    for _,f in ipairs(self.files) do if f.path:lower():find(pattern,1,true) then out[#out+1]=f end end
    return out
  end
  function self:readFile(file,off,len)
    if type(file)=="string" then file=assert(self:file(file),"disc file not found: "..file) end
    off=off or 0;len=len or (file.size-off);assert(off>=0 and len>=0 and off+len<=file.size,"file read exceeds member")
    return self:read(file.offset+off,len)
  end
  return self
end

function M.serializeIndex(disc)
  local out={"return {discId=\"GC6E01\",format=",string.format("%q",disc.sourceFormat or "iso"),",containerSize=",disc.containerSize or disc.info.size,",logicalSize=",disc.logicalSize or ISO_SIZE,",fstOffset=",disc.fstOffset,",fstSize=",disc.fstSize,",files={\n"}
  for _,f in ipairs(disc.files) do out[#out+1]=string.format("{%q,%d,%d},\n",f.path,f.offset,f.size) end
  out[#out+1]="}}\n";return table.concat(out)
end
M.ISO_SIZE=ISO_SIZE
return M
