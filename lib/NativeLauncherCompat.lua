-- Cross-platform compatibility / media-normalization bridge for the
-- Gen1Recomp launcher-owned Pokemon Colosseum import.
--
-- CBE never trusts the selected filename or extension.  Once the launcher has
-- granted the private import, this module identifies the *content* and exposes
-- one canonical 1,459,978,240-byte GC6E01 logical disc address space to every
-- extractor.  Supported physical representations are:
--   * raw ISO/GCM (extension is irrelevant);
--   * safely trailing-trimmed / scrubbed raw images (missing tail is zero-fill,
--     but only when the FST proves no referenced file was cut);
--   * Dolphin block-sparse GameCube CISO;
--   * the same raw/CISO payload behind a small common wrapper/header.
--
-- Admission is still launcher-owned.  1.6.0's manifest keeps the canonical
-- ISO + known tested CISO MD5s for old launchers and also declares GameCube
-- structural metadata (disc id/revision, CISO/scrubbed support) understood by
-- representation-aware launchers.  CBE itself then performs a stronger second
-- structural check: GameCube magic + FST integrity + the core Colosseum FSYS
-- members actually used by the runtime.  Optional audio is intentionally not
-- part of source validity.
local M={}

local IMPORT_ID="pokemon_colosseum_usa"
local IMPORT_PATH="baseroms/pokemon_colosseum_usa.iso"
local EXPECTED_SIZE=1459978240
local CISO_HEADER=0x8000
local CACHE_ROOT="cbe_generated_v2"
local MAX_PREFIX_SCAN=0x8000
local COMMON_PREFIXES={0,512,0x8000}
local REQUIRED_FSYS={
  "people_archive.fsys","fight_common.fsys","M1_water_colo.fsys",
  "D2_crater_colo.fsys","T1_ancient_colo.fsys","D4_casino_colo.fsys",
}

local function safeCachePath(path)
  assert(type(path)=="string" and path~="","cache path is required")
  path=path:gsub("\\","/")
  assert(path:sub(1,1)~="/" and not path:match("^%a:"),"absolute cache path rejected")
  assert(not path:find("../",1,true) and path~=".." and not path:find("/..",1,true),"cache path traversal rejected")
  return CACHE_ROOT.."/"..path
end

local function le32(s,p)
  local a,b,c,d=s:byte(p,p+3);if not d then return nil end
  return a+b*256+c*65536+d*16777216
end
local function be32(s,p)
  local a,b,c,d=s:byte(p,p+3);if not d then return nil end
  return ((a*256+b)*256+c)*256+d
end
local function ceildiv(a,b) return math.floor((a+b-1)/b) end
local function zeros(n) return n>0 and string.rep("\0",n) or "" end
local function cstring(s,offset)
  offset=tonumber(offset) or -1
  if offset<0 or offset>=#s then return nil end
  local p=offset+1;local e=s:find("\0",p,true) or (#s+1)
  return s:sub(p,e-1)
end

local function validDiscHeader(bytes)
  return type(bytes)=="string" and #bytes>=0x440
    and bytes:sub(1,6)=="GC6E01"
    and bytes:byte(7)==0 and bytes:byte(8)==0
    and be32(bytes,0x1C+1)==0xC2339F3D
end

local function copyInfo(info)
  local out={}
  if type(info)=="table" then for k,v in pairs(info) do out[k]=v end end
  return out
end

local function makeLegacyImports(mod,status)
  local sourceBlob=nil
  local imports={}
  function imports:info(id)
    if id~=IMPORT_ID then return nil,"unknown import: "..tostring(id) end
    if type(mod.info)~="function" then return nil,"mod:info is unavailable" end
    local info=mod:info(IMPORT_PATH)
    if not info or (info.type and info.type~="file") then
      return nil,"launcher import is not installed"
    end
    return {id=IMPORT_ID,file=IMPORT_PATH,size=tonumber(info.size),type="file",validated=true}
  end
  function imports:read(id,offset,length)
    local info,err=self:info(id);if not info then return nil,err end
    offset=tonumber(offset);length=tonumber(length)
    if not offset or not length or offset<0 or length<0 or offset%1~=0 or length%1~=0 then
      return nil,"invalid import read range"
    end
    if not info.size or offset+length>info.size then return nil,"import read exceeds source" end
    if length==0 then return "" end
    if sourceBlob==nil then
      local bytes,readErr=mod:read(IMPORT_PATH)
      if type(bytes)~="string" then return nil,readErr or "launcher import could not be read" end
      if #bytes~=info.size then
        return nil,("launcher import read returned %d bytes; expected %d"):format(#bytes,info.size)
      end
      sourceBlob=bytes;status.sourceBuffered=true
    end
    return sourceBlob:sub(offset+1,offset+length)
  end
  function imports:release()
    sourceBlob=nil;status.sourceBuffered=false;collectgarbage("collect");return true
  end
  return imports
end

local function makeLogicalImports(base,status)
  local descriptor=nil

  local function baseInfo()
    local ok,info,err=pcall(base.info,base,IMPORT_ID)
    if not ok then return nil,tostring(info) end
    if not info then return nil,err or "launcher import is not installed" end
    local size=tonumber(info.size)
    if not size or size<=0 then return nil,"launcher import size is unavailable" end
    return info,size
  end

  local function readPhysical(offset,length,knownSize)
    if length==0 then return "" end
    if offset<0 or length<0 or (knownSize and offset+length>knownSize) then
      return nil,"physical import read exceeds source"
    end
    local ok,bytes,err=pcall(base.read,base,IMPORT_ID,offset,length)
    if not ok then return nil,tostring(bytes) end
    if type(bytes)~="string" then return nil,err or "launcher import could not be read" end
    if #bytes~=length then return nil,("short physical import read (%d/%d)"):format(#bytes,length) end
    return bytes
  end

  local function readCiso(d,offset,length)
    if length==0 then return "" end
    local out={};local at=offset;local left=length;local bs=d.blockSize
    while left>0 do
      local bi=math.floor(at/bs);local inside=at-bi*bs
      local take=math.min(left,bs-inside);local poff=d.blockPhysical[bi]
      if poff then
        local bytes,err=readPhysical(poff+inside,take,d.physicalSize)
        if not bytes then return nil,err end
        out[#out+1]=bytes
      else
        out[#out+1]=zeros(take)
      end
      at=at+take;left=left-take
    end
    return table.concat(out)
  end

  local function readRaw(d,offset,length)
    if length==0 then return "" end
    local payload=d.payloadSize
    if offset>=payload then return zeros(length) end
    local real=math.min(length,payload-offset)
    local bytes,err=readPhysical(d.rawOffset+offset,real,d.physicalSize)
    if not bytes then return nil,err end
    if real<length then bytes=bytes..zeros(length-real) end
    return bytes
  end

  local function logicalRead(d,offset,length)
    offset=tonumber(offset);length=tonumber(length)
    if not offset or not length or offset<0 or length<0 or offset%1~=0 or length%1~=0 then
      return nil,"invalid import read range"
    end
    if offset+length>EXPECTED_SIZE then return nil,"import read exceeds logical source" end
    if d.container=="ciso" then return readCiso(d,offset,length) end
    return readRaw(d,offset,length)
  end

  local function validateFst(d)
    local header,err=logicalRead(d,0,0x440);if not header then return nil,err end
    if not validDiscHeader(header) then return nil,"source is not Pokemon Colosseum USA GC6E01 revision 0" end
    local fstOff,fstSize=be32(header,0x424+1),be32(header,0x428+1)
    if not fstOff or not fstSize or fstOff<=0 or fstSize<12 or fstOff+fstSize>EXPECTED_SIZE then
      return nil,"invalid GameCube FST range"
    end
    local fst,ferr=logicalRead(d,fstOff,fstSize);if not fst then return nil,ferr end
    local count=be32(fst,9)
    if not count or count<=0 or count>=200000 or count*12>fstSize then
      return nil,"invalid GameCube FST root"
    end
    local tableBytes=count*12;local entries=fst:sub(1,tableBytes);local names=fst:sub(tableBytes+1)
    local rows={};local maxFileEnd=0
    for i=0,count-1 do
      local p=i*12+1;local word,a,b=be32(entries,p),be32(entries,p+4),be32(entries,p+8)
      if not word or a==nil or b==nil then return nil,"truncated GameCube FST entry" end
      local kind=math.floor(word/0x1000000);local nameOff=word%0x1000000
      local name=i==0 and "" or cstring(names,nameOff)
      if i>0 and (not name or name=="") then return nil,"invalid GameCube FST name offset" end
      if kind==0 then
        local fileEnd=a+b
        if fileEnd>EXPECTED_SIZE then return nil,"GameCube FST file range exceeds logical disc" end
        if d.container=="raw-trimmed" and fileEnd>d.payloadSize then
          return nil,("trimmed GameCube image ends inside a referenced file (%d > %d)"):format(fileEnd,d.payloadSize)
        end
        if fileEnd>maxFileEnd then maxFileEnd=fileEnd end
      elseif kind==1 then
        if i==0 then
          if b~=count then return nil,"invalid GameCube FST root span" end
        elseif b<=i or b>count then return nil,"invalid GameCube FST directory span" end
      else
        return nil,"invalid GameCube FST entry type"
      end
      rows[i]={dir=kind==1,name=name,a=a,b=b}
    end

    local found={};local fileCount=0
    local function visit(idx,prefix)
      local dir=rows[idx];if not dir or not dir.dir then return nil,"invalid GameCube FST directory" end
      local i=idx+1
      while i<dir.b do
        local e=rows[i];if not e then return nil,"missing GameCube FST child" end
        local path=(prefix=="" and e.name) or (prefix.."/"..e.name)
        if e.dir then
          local ok,why=visit(i,path);if not ok then return nil,why end
          i=e.b
        else
          fileCount=fileCount+1
          local baseName=path:match("([^/]+)$"):lower()
          for _,wanted in ipairs(REQUIRED_FSYS) do
            if baseName==wanted:lower() then found[wanted]={offset=e.a,size=e.b,path=path} end
          end
          i=i+1
        end
      end
      return true
    end
    local ok,why=visit(0,"");if not ok then return nil,why end
    if fileCount<1000 then return nil,("unexpected Pokemon Colosseum FST inventory (%d files)"):format(fileCount) end
    for _,wanted in ipairs(REQUIRED_FSYS) do
      local f=found[wanted]
      if not f then return nil,"required Colosseum source archive missing: "..wanted end
      if f.size<4 then return nil,"truncated Colosseum source archive: "..wanted end
      local magic,merr=logicalRead(d,f.offset,4);if not magic then return nil,merr end
      if magic~="FSYS" then return nil,"invalid Colosseum source archive: "..wanted end
    end
    return {fstOffset=fstOff,fstSize=fstSize,fileCount=fileCount,maxFileEnd=maxFileEnd,criticalArchives=#REQUIRED_FSYS}
  end

  local function cisoAt(prefix,physicalSize)
    if prefix<0 or prefix+CISO_HEADER>physicalSize then return nil end
    local head,err=readPhysical(prefix,CISO_HEADER,physicalSize);if not head then return nil,err end
    if head:sub(1,4)~="CISO" then return nil end
    local bs=le32(head,5)
    if not bs or bs<0x8000 or bs>64*1024*1024 or bs%0x8000~=0 then return nil,"invalid CISO block size" end
    local blocks=ceildiv(EXPECTED_SIZE,bs)
    if 8+blocks>CISO_HEADER then return nil,"CISO block map exceeds header" end
    local blockPhysical={};local used=0
    for bi=0,blocks-1 do
      if (head:byte(9+bi) or 0)~=0 then
        blockPhysical[bi]=prefix+CISO_HEADER+used*bs;used=used+1
      end
    end
    if not blockPhysical[0] then return nil,"CISO does not contain logical disc block 0" end
    local minimum=prefix+CISO_HEADER+used*bs
    if physicalSize<minimum then return nil,("CISO is truncated (needs at least %d bytes, got %d)"):format(minimum,physicalSize) end
    -- Writers occasionally append a short tail.  Keep the check bounded but
    -- representation-agnostic: one sparse block plus a small wrapper margin.
    if physicalSize>minimum+bs+MAX_PREFIX_SCAN then
      return nil,("CISO trailing payload is implausibly large (%d bytes)"):format(physicalSize-minimum)
    end
    return {container="ciso",containerOffset=prefix,physicalSize=physicalSize,logicalSize=EXPECTED_SIZE,
      blockSize=bs,blockCount=blocks,blockPhysical=blockPhysical,usedBlocks=used}
  end

  local function rawAt(prefix,physicalSize)
    if prefix<0 or prefix+0x440>physicalSize then return nil end
    local header,err=readPhysical(prefix,0x440,physicalSize);if not header then return nil,err end
    if not validDiscHeader(header) then return nil end
    local payload=physicalSize-prefix
    if payload<0x440 then return nil,"raw GameCube source is truncated" end
    local d={container=payload<EXPECTED_SIZE and "raw-trimmed" or "raw",rawOffset=prefix,
      payloadSize=payload,physicalSize=physicalSize,logicalSize=EXPECTED_SIZE}
    if payload>EXPECTED_SIZE then d.trailingBytes=payload-EXPECTED_SIZE end
    return d
  end

  local function detect()
    if descriptor then return descriptor end
    local upstream,physicalSize=baseInfo();if not upstream then return nil,physicalSize end
    local tried={};local lastReason=nil
    for _,prefix in ipairs(COMMON_PREFIXES) do
      if not tried[prefix] then
        tried[prefix]=true
        local d,why=cisoAt(prefix,physicalSize)
        if d then
          local fst,ferr=validateFst(d)
          if fst then d.fst=fst;d.upstream=upstream;descriptor=d;break end
          lastReason=ferr
        elseif why then lastReason=why end
        d,why=rawAt(prefix,physicalSize)
        if d then
          local fst,ferr=validateFst(d)
          if fst then d.fst=fst;d.upstream=upstream;descriptor=d;break end
          lastReason=ferr
        elseif why then lastReason=why end
      end
    end
    if not descriptor then
      return nil,lastReason or "source is not a structurally valid Pokemon Colosseum USA GC6E01 ISO/GCM/CISO"
    end
    local d=descriptor
    status.container=(d.container=="ciso" and "CISO")
      or (d.container=="raw-trimmed" and "RAW ISO/GCM (TRIMMED/SCRUBBED)")
      or "RAW ISO/GCM"
    status.physicalSize=d.physicalSize;status.logicalSize=EXPECTED_SIZE
    status.containerOffset=d.containerOffset or d.rawOffset or 0
    status.fstFiles=d.fst and d.fst.fileCount or 0
    status.structuralValidated=true;status.mobileSafe=status.sourceBuffered~=true
    if d.container=="ciso" then status.cisoBlockSize=d.blockSize;status.cisoUsedBlocks=d.usedBlocks end
    return d
  end

  local imports={}
  function imports:info(id)
    if id~=IMPORT_ID then return nil,"unknown import: "..tostring(id) end
    local d,err=detect();if not d then return nil,err end
    local out=copyInfo(d.upstream)
    out.id=IMPORT_ID;out.size=EXPECTED_SIZE;out.logicalSize=EXPECTED_SIZE
    out.physicalSize=d.physicalSize;out.container=d.container;out.validated=true;out.normalized=true
    out.structuralValidated=true;out.fstFiles=d.fst and d.fst.fileCount or 0
    out.containerOffset=d.containerOffset or d.rawOffset or 0
    if d.container=="ciso" then out.blockSize=d.blockSize;out.usedBlocks=d.usedBlocks end
    return out
  end
  function imports:read(id,offset,length)
    if id~=IMPORT_ID then return nil,"unknown import: "..tostring(id) end
    local d,err=detect();if not d then return nil,err end
    return logicalRead(d,offset,length)
  end
  function imports:release()
    descriptor=nil
    if type(base.release)=="function" then pcall(base.release,base) end
    status.sourceBuffered=false
    return true
  end
  function imports:physicalInfo()
    local d,err=detect();if not d then return nil,err end
    return {container=d.container,physicalSize=d.physicalSize,logicalSize=EXPECTED_SIZE,
      containerOffset=d.containerOffset or d.rawOffset or 0,blockSize=d.blockSize,
      usedBlocks=d.usedBlocks,fstFiles=d.fst and d.fst.fileCount or 0,structuralValidated=true}
  end
  return imports
end

function M.install(mod)
  assert(type(mod)=="table","CBE launcher bridge requires mod API")
  local hadNative=mod.imports~=nil
  local status={
    source="launcher required_imports",sourcePath=IMPORT_PATH,
    cache="Gen1Recomp per-mod compatibility overlay",sourceBuffered=false,
    expectedSize=EXPECTED_SIZE,logicalSize=EXPECTED_SIZE,
  }

  local base=mod.imports
  if not base then
    base=makeLegacyImports(mod,status)
    status.importBridge="legacy mod:read adapter + content-validated logical media view"
  else
    status.importBridge="native mod.imports + content-validated logical media view"
  end
  rawset(mod,"imports",makeLogicalImports(base,status))
  status.nativeRangeImports=hadNative==true
  status.mobileSafe=hadNative==true

  if not mod.cache then
    local fs=love and love.filesystem
    assert(fs and type(fs.read)=="function" and type(fs.write)=="function" and type(fs.getInfo)=="function",
      "Gen1Recomp per-mod filesystem compatibility overlay is unavailable")
    local cache={}
    function cache:info(path) return fs.getInfo(safeCachePath(path)) end
    function cache:read(path) return fs.read(safeCachePath(path)) end
    function cache:write(path,data)
      assert(type(data)=="string","cache writes require string bytes")
      return fs.write(safeCachePath(path),data)
    end
    function cache:delete(path)
      local full=safeCachePath(path);if not fs.getInfo(full) then return true end
      local ok,err=fs.remove(full);if ok==false then return false,err end;return true
    end
    rawset(mod,"cache",cache);status.cacheBridge="legacy filesystem overlay adapter"
  else
    status.cacheBridge="native mod.cache"
  end
  return status
end

return M
