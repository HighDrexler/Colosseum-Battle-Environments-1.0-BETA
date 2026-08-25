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

-- Pokemon Colosseum/XD FSYS members use the SysDolphin 0x1000-byte LZSS ring.
-- The u32 at +0x08 is the total compressed member size including the 0x10 header.
function F.decompressLZSS(blob,expected,opts)
  assert(type(blob)=="string" and blob:sub(1,4)=="LZSS","missing LZSS header")
  opts=opts or {}
  expected=expected or u32(blob,5)
  local packedSize=u32(blob,9)
  local maxOutput=tonumber(opts.maxOutput) or (64*1024*1024)
  assert(expected and expected>=0 and expected<=maxOutput,("LZSS output outside safety limit: %s / %s"):format(tostring(expected),tostring(maxOutput)))
  assert(packedSize and packedSize>=16 and packedSize<=#blob,"bad LZSS header")
  local src=17;local srcEnd=packedSize
  local ring={};for i=0,4095 do ring[i]=0 end
  local rp=0xFEE
  -- Do not retain one Lua string object per decompressed byte. Large Colosseum
  -- members can be several MiB and the old byte-table implementation could
  -- spend minutes/GBs of transient memory before table.concat. Flush modest
  -- string chunks instead.
  local chunks,chunk,chunkN={}, {},0
  local outN=0;local nextHeartbeat=256*1024
  local function flush()
    if chunkN==0 then return end
    chunks[#chunks+1]=table.concat(chunk);chunk={};chunkN=0
  end
  local function heartbeat(force)
    if type(opts.progress)~="function" then return end
    if force or outN>=nextHeartbeat then
      nextHeartbeat=outN+256*1024
      pcall(opts.progress,outN,expected or 0)
    end
  end
  local function emit(b)
    outN=outN+1
    assert(outN<=maxOutput,"LZSS output exceeded safety limit")
    chunkN=chunkN+1;chunk[chunkN]=string.char(b)
    if chunkN>=8192 then flush() end
    ring[rp]=b;rp=(rp+1)%4096
    heartbeat(false)
  end
  while src<=srcEnd and (not expected or expected==0 or outN<expected) do
    local flags=blob:byte(src);src=src+1;if not flags then break end
    for bit=0,7 do
      if src>srcEnd or (expected and expected>0 and outN>=expected) then break end
      local literal=(math.floor(flags/(2^bit))%2)==1
      if literal then
        local b=blob:byte(src);src=src+1;if not b then break end
        emit(b)
      else
        local b0,b1=blob:byte(src,src+1);src=src+2;if not b1 then break end
        local mp=b0+(math.floor(b1/16)%16)*256;local n=(b1%16)+3
        for _=1,n do
          if expected and expected>0 and outN>=expected then break end
          local b=ring[mp] or 0;mp=(mp+1)%4096;emit(b)
        end
      end
    end
  end
  flush();heartbeat(true)
  if expected and expected>0 then assert(outN==expected,("LZSS short output: %d/%d"):format(outN,expected)) end
  return table.concat(chunks)
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
