local F={}
local function u32(s,p)local a,b,c,d=s:byte(p,p+3);if not d then return nil end;return ((a*256+b)*256+c)*256+d end
local function zstr(s)local p=s:find("\0",1,true);return p and s:sub(1,p-1) or s end
local function hex(n)return string.format("0x%X",tonumber(n) or 0) end
local MODEL_TYPES={
  [0x02]={ext="dat",model=true}, -- mdat/model data
  [0x04]={ext="dat",model=true}, -- DAT/HSD
  [0x18]={ext="cam",model=false},
  [0x1E]={ext="pkx",model=true}, -- battle model wrapper + DAT/HSD
  [0x20]={ext="wzx",model=false},
}

-- Pre-interned single-byte strings. Every decompressed byte used to allocate
-- through string.char(); an array index costs neither a C call nor a hash.
local CHR={};for i=0,255 do CHR[i]=string.char(i) end

-- Pokemon Colosseum/XD FSYS members use the SysDolphin 0x1000-byte LZSS ring.
-- The u32 at +0x08 is the total compressed member size including the 0x10 header.
--
-- PERFORMANCE: this decoder runs over every arena, trainer, Pokemon, Waza and
-- audio member on the disc, so it is the single hottest function in the whole
-- cache build. The emit()/heartbeat() closures, the 2^bit flag test, the two
-- modulo wraps and the per-byte string.char() were all on the per-output-byte
-- path. They are inlined here; output is byte-identical.
function F.decompressLZSS(blob,expected,opts)
  assert(type(blob)=="string" and blob:sub(1,4)=="LZSS","missing LZSS header")
  opts=opts or {}
  expected=expected or u32(blob,5)
  local packedSize=u32(blob,9)
  local maxOutput=tonumber(opts.maxOutput) or (64*1024*1024)
  assert(expected and expected>=0 and expected<=maxOutput,("LZSS output outside safety limit: %s / %s"):format(tostring(expected),tostring(maxOutput)))
  assert(packedSize and packedSize>=16 and packedSize<=#blob,"bad LZSS header")

  local byte,concat,chr=string.byte,table.concat,CHR
  local progress=type(opts.progress)=="function" and opts.progress or nil
  local src=17;local srcEnd=packedSize
  local ring={};for i=0,4095 do ring[i]=0 end
  local rp=0xFEE
  -- Do not retain one Lua string object per decompressed byte. Large Colosseum
  -- members can be several MiB and the old byte-table implementation could
  -- spend minutes/GBs of transient memory before table.concat. Flush modest
  -- string chunks instead.
  local chunks,chunkCount={},0
  local chunk,chunkN={},0
  local outN=0;local nextHeartbeat=262144
  local bounded=(expected and expected>0)
  local limit=bounded and expected or maxOutput

  while src<=srcEnd and outN<limit do
    local flags=byte(blob,src);src=src+1
    if not flags then break end
    for _=1,8 do
      if src>srcEnd or outN>=limit then break end
      -- Consume the flag word one bit at a time by halving it, which is the
      -- same test as floor(flags/2^bit)%2 without the per-bit exponentiation.
      local literal=flags%2
      flags=(flags-literal)*0.5
      if literal==1 then
        local b=byte(blob,src);src=src+1
        if not b then break end
        outN=outN+1
        chunkN=chunkN+1;chunk[chunkN]=chr[b]
        ring[rp]=b;rp=rp+1;if rp>=4096 then rp=0 end
      else
        local b0,b1=byte(blob,src,src+1);src=src+2
        if not b1 then break end
        local hi=b1-b1%16
        local mp=b0+hi*16
        local n=b1-hi+3
        if outN+n>limit then n=limit-outN end
        for _=1,n do
          local b=ring[mp];mp=mp+1;if mp>=4096 then mp=0 end
          chunkN=chunkN+1;chunk[chunkN]=chr[b]
          ring[rp]=b;rp=rp+1;if rp>=4096 then rp=0 end
        end
        outN=outN+n
      end
      if chunkN>=8192 then
        chunkCount=chunkCount+1;chunks[chunkCount]=concat(chunk,"",1,chunkN);chunkN=0
      end
    end
    -- One heartbeat per flag group rather than per output byte.
    if progress and outN>=nextHeartbeat then
      nextHeartbeat=outN+262144
      pcall(progress,outN,expected or 0)
    end
  end
  if chunkN>0 then chunkCount=chunkCount+1;chunks[chunkCount]=concat(chunk,"",1,chunkN) end
  if progress then pcall(progress,outN,expected or 0) end
  if bounded then assert(outN==expected,("LZSS short output: %d/%d"):format(outN,expected))
  else assert(outN<maxOutput,"LZSS output exceeded safety limit") end
  return concat(chunks,"",1,chunkCount)
end
local function readName(disc,file,offset)
  if not offset or offset<=0 or offset>=file.size then return nil end
  local n=math.min(256,file.size-offset)
  local ok,raw=pcall(disc.readFile,disc,file,offset,n)
  if not ok or type(raw)~="string" then return nil end
  local name=zstr(raw)
  if name=="" then return nil end
  return name:gsub("[%c\r\n]","")
end

-- Correct Colosseum/XD FSYS layout:
--   header +0x0C : entry count
--   header +0x40 : pointer to the metadata-pointer list
-- Metadata entries:
--   +0x02 u8 file type, +0x04 u32 data address, +0x0C u32 flags,
--   +0x14 u32 stored file size, +0x1C full filename ptr, +0x24 short name ptr.
local function parseCanonical(disc,file)
  if file.size<0x44 then return nil,"FSYS header too small" end
  local hdr=disc:readFile(file,0,math.min(file.size,0x60))
  if hdr:sub(1,4)~="FSYS" then return nil,"not an FSYS archive" end
  local count=u32(hdr,0x0C+1)
  local listPtr=u32(hdr,0x40+1)
  if not count or count<=0 or count>10000 then return nil,"invalid FSYS entry count" end
  if not listPtr or listPtr<=0 or listPtr+count*4>file.size then return nil,"invalid FSYS metadata list" end
  local ptrs=disc:readFile(file,listPtr,count*4)
  local entries={}
  for i=0,count-1 do
    local entryOff=u32(ptrs,i*4+1)
    if entryOff and entryOff>0 and entryOff+0x28<=file.size then
      local ebuf=disc:readFile(file,entryOff,0x28)
      local fileType=ebuf:byte(0x02+1) or 0
      local dataOff=u32(ebuf,0x04+1)
      local flags=u32(ebuf,0x0C+1) or 0
      local stored=u32(ebuf,0x14+1)
      local fullNamePtr=u32(ebuf,0x1C+1)
      local shortNamePtr=u32(ebuf,0x24+1)
      if dataOff and stored and stored>0 and dataOff>0 and dataOff+stored<=file.size then
        local meta=MODEL_TYPES[fileType]
        local name=readName(disc,file,fullNamePtr) or readName(disc,file,shortNamePtr)
        local ext=meta and meta.ext or nil
        if not name then name=("entry_%04d%s"):format(i,ext and ("."..ext) or "")
        elseif ext and not name:lower():match("%."..ext.."$") and not name:match("%.[%w%d]+$") then name=name.."."..ext end
        entries[#entries+1]={
          index=i,name=name,dataOffset=dataOff,storedSize=stored,entryOffset=entryOff,
          fileType=fileType,flags=flags,compressed=(math.floor(flags/0x80000000)%2)==1,
          ext=ext,modelKind=meta and meta.model==true or false,
        }
      end
    end
  end
  if #entries==0 then return nil,"FSYS contains no readable canonical entries" end
  return {entries=entries,count=count,listPtr=listPtr,layout="canonical"}
end

function F.open(disc,file)
  if type(file)=="string" then file=assert(disc:file(file),"FSYS not found: "..file) end
  local parsed,err=parseCanonical(disc,file)
  assert(parsed,err or "FSYS parse failed")
  local self={disc=disc,file=file,count=#parsed.entries,entries=parsed.entries,headerCount=parsed.count,metadataListOffset=parsed.listPtr,layout=parsed.layout}
  function self:list() return self.entries end
  function self:modelEntries()
    local out={};for _,e in ipairs(self.entries) do if e.modelKind then out[#out+1]=e end end;return out
  end
  function self:member(key)
    if type(key)=="number" then
      for _,e in ipairs(self.entries) do if e.index==key then return e end end
      return self.entries[key]
    end
    local q=tostring(key or ""):lower()
    for _,e in ipairs(self.entries) do if e.name:lower()==q then return e end end
    for _,e in ipairs(self.entries) do if e.name:lower():find(q,1,true) then return e end end
  end
  function self:extract(key,opts)
    local e=type(key)=="table" and key or assert(self:member(key),"FSYS member not found: "..tostring(key))
    local raw=self.disc:readFile(self.file,e.dataOffset,e.storedSize)
    assert(type(raw)=="string" and #raw==e.storedSize,("FSYS short member read %s (%d/%d)"):format(tostring(e.name),type(raw)=="string" and #raw or 0,e.storedSize))
    if e.compressed or raw:sub(1,4)=="LZSS" then
      assert(raw:sub(1,4)=="LZSS",("FSYS compressed flag without LZSS header for %s type=%s"):format(tostring(e.name),hex(e.fileType)))
      local packed=u32(raw,9)
      assert(packed and packed>=16 and packed<=#raw,("bad LZSS packed size for %s"):format(tostring(e.name)))
      return F.decompressLZSS(raw:sub(1,packed),u32(raw,5),opts),e
    end
    return raw,e
  end
  return self
end
return F
