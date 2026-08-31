local W={revision=3}

-- Lossless, loader-evidence-backed WazaSequence indexer for Pokemon Colosseum
-- WZX members (GC6E01).
--
-- Parsing and interpretation are deliberately separate.  Every SequenceEntry
-- retains its exact source byte range inside the runtime-cached WZX member.  A
-- handler may understand a type today, tomorrow, or never; unknown payload
-- bytes are not thrown away simply because CBE cannot render them yet.
--
-- The source-entry layouts below are derived from the retail main.dol sequence
-- loader/dispatcher, not from visual guesses:
--   source type 2 -> model entry
--   source type 3 -> particle entry
--   source type 0 -> invalid in on-disc WazaSequence data
-- Retail entry-start/update dispatch now also proves source type 5 is the GameSound entry.
-- Types 1/4/6 remain conservatively named until their semantics are proven.

local KIND={
  [1]="type1",
  [2]="model",
  [3]="particle",
  [4]="type4",
  [5]="sound",
  [6]="type6",
}

local function be32(s,p)
  local a,b,c,d=s:byte(p+1,p+4);if not d then return nil end
  return ((a*256+b)*256+c)*256+d
end
local function signed32(v)
  return v and (v>=2147483648 and v-4294967296 or v) or nil
end
local function saneRange(off,size,n)
  return type(off)=="number" and type(size)=="number" and off>=0 and size>=0 and off+size<=n
end
local function align32(n) return math.floor((math.max(0,n)+31)/32)*32 end
local function hex(bytes)
  local out={}
  for i=1,#bytes do out[#out+1]=string.format("%02X",bytes:byte(i)) end
  return table.concat(out)
end
local function wordList(blob,off,count)
  local out={}
  for i=0,(count or 0)-1 do out[#out+1]=be32(blob,off+i*4) or 0 end
  return out
end

local function commonSizeAt(blob,at)
  -- loadTotalSequence's common-entry loader checks source +0x68.  Mode 1 uses
  -- a 0x6C-byte common block; every other observed mode uses 0x70.
  return (be32(blob,at+0x68)==1) and 0x6C or 0x70
end

local function plausibleHeader(blob,at,expectedIdentifier)
  if not saneRange(at,0x6C,#blob) then return false end
  local id=be32(blob,at)
  local typ=be32(blob,at+0x04)
  if not id or not typ or typ<1 or typ>6 then return false end
  if expectedIdentifier~=nil and tonumber(id)~=tonumber(expectedIdentifier) then return false end
  local cs=commonSizeAt(blob,at)
  if not saneRange(at,cs,#blob) then return false end
  -- These words are used by the sequence runtime as frame-domain/control
  -- values.  Negative sentinels are valid; absurd random payload values are a
  -- strong false-header signal.
  for _,off in ipairs({0x10,0x14,0x18}) do
    local v=signed32(be32(blob,at+off))
    if v==nil or v < -0x100000 or v > 0x100000 then return false end
  end
  return true
end

local function header(blob,at,index)
  local typ=be32(blob,at+0x04)
  local commonSize=commonSizeAt(blob,at)
  local mode=be32(blob,at+0x68) or 0
  return {
    index=index,
    offset=at,
    identifier=be32(blob,at) or 0,
    entryType=typ,
    kind=KIND[typ] or ("type"..tostring(typ)),
    -- Retail common-loader timing dependency fields. These were historically
    -- mislabelled start/hit/finish in CBE; they are identifiers/point indices,
    -- not literal frame numbers.
    anchorEntry=be32(blob,at+0x10) or 0,
    localPoint=be32(blob,at+0x14) or 0,
    anchorPoint=be32(blob,at+0x18) or 0,
    attachment=be32(blob,at+0x1C) or 0,
    timingPoints=(function()
      local t={};for i=0,15 do t[#t+1]=signed32(be32(blob,at+0x20+i*4)) or 0 end;return t
    end)(),
    flags60=be32(blob,at+0x60) or 0,
    flags64=be32(blob,at+0x64) or 0,
    commonMode=mode,
    commonSize=commonSize,
    headerHex=hex(blob:sub(at+1,math.min(#blob,at+commonSize))),
  }
end

local function findExpectedHeader(blob,fromAt,expectedIdentifier,limit)
  local first=math.max(0,math.floor(tonumber(fromAt) or 0))
  local stop=math.min(#blob-0x6C, first+(tonumber(limit) or #blob))
  -- Source structures are word aligned.  Preserve the source residue so a
  -- structurally valid but non-0x20-aligned entry can still be found.
  local residue=first%4
  local at=first
  if at%4~=residue then at=at+((residue-at)%4) end
  while at<=stop do
    if plausibleHeader(blob,at,expectedIdentifier) then return at end
    at=at+4
  end
  return nil
end

local function parseKnownEntry(blob,at,index)
  if not plausibleHeader(blob,at,index) then return nil,nil,"invalid SequenceEntry header" end
  local e=header(blob,at,index)
  local n=#blob
  local extra=at+e.commonSize
  local finish
  e.extraOffset=extra
  e.payloadOffset=extra

  if e.entryType==1 then
    -- Retail loader: fixed 0x0C payload; subtype 3 appends count*8 bytes.
    if not saneRange(extra,0x0C,n) then return e,nil,"truncated type1 payload" end
    e.words=wordList(blob,extra,3)
    e.subtype=be32(blob,extra) or 0
    e.tableCount=be32(blob,extra+0x04) or 0
    local tail=0
    if e.subtype==3 then
      if e.tableCount<0 or e.tableCount>65535 then return e,nil,"invalid type1 table count" end
      tail=e.tableCount*8
      e.tableOffset=extra+0x0C
      e.tableSize=tail
      if not saneRange(e.tableOffset,tail,n) then return e,nil,"truncated type1 table" end
    end
    finish=extra+0x0C+tail

  elseif e.entryType==2 then
    -- Model-entry loader: source model size @ payload+0x1C and embedded HSD data
    -- begins at align32(payload+0x24).
    if not saneRange(extra,0x24,n) then return e,nil,"truncated model payload" end
    e.modelWords=wordList(blob,extra,9)
    e.embeddedSize=be32(blob,extra+0x1C) or 0
    e.dataOffset=align32(extra+0x24)
    if e.embeddedSize<0 or not saneRange(e.dataOffset,e.embeddedSize,n) then
      return e,nil,"invalid/truncated model data"
    end
    e.dataSize=e.embeddedSize
    if e.dataSize>0 then e.dataMagic=blob:sub(e.dataOffset+1,math.min(n,e.dataOffset+4)) end
    finish=e.dataOffset+align32(e.embeddedSize)

  elseif e.entryType==3 then
    -- Particle-entry loader.  The type-specific header is 0x10 bytes.  Mode 3
    -- has one additional source word before particle data.  Later entries may
    -- contain no GPT1 of their own and instead reference a previously loaded
    -- particle bank; retain the range either way.
    if not saneRange(extra,0x10,n) then return e,nil,"truncated particle payload" end
    e.particleWords=wordList(blob,extra,4)
    e.rootRef=be32(blob,extra) or 0
    e.effectParam=be32(blob,extra+0x04) or 0
    e.particleDataSize=be32(blob,extra+0x08) or 0
    e.particleMode=be32(blob,extra+0x0C) or 0
    e.effectMode=e.particleMode -- compatibility with the existing GPT1 runtime
    local prefix=(e.particleMode==3) and 0x14 or 0x10
    if e.particleMode==3 then
      if not saneRange(extra,0x14,n) then return e,nil,"truncated particle mode-3 payload" end
      e.mode3Word=be32(blob,extra+0x10) or 0
    end
    e.dataOffset=extra+prefix
    if e.particleDataSize<0 or not saneRange(e.dataOffset,e.particleDataSize,n) then
      return e,nil,"invalid/truncated particle data"
    end
    e.dataSize=e.particleDataSize
    if e.dataSize>0 then
      e.dataMagic=blob:sub(e.dataOffset+1,math.min(n,e.dataOffset+4))
      if e.dataMagic=="GPT1" then e.gptOffset=e.dataOffset end
    end
    finish=e.dataOffset+align32(e.particleDataSize)

  elseif e.entryType==4 then
    -- The retail loader delegates type 4 to a dedicated variable-layout helper.
    -- Until every subtype is decoded, preserve it losslessly and use the next
    -- sequential source identifier as the structural boundary.  Sequential ids
    -- are a strong invariant of real WZX members and avoid false headers inside
    -- embedded model/particle data.
    e.words=wordList(blob,extra,math.min(8,math.floor(math.max(0,n-extra)/4)))
    finish=nil -- resolved by W.parse with the next expected identifier

  elseif e.entryType==5 then
    -- Loader advances 8 bytes for modes 1/2 in payload word 1, otherwise 12.
    if not saneRange(extra,0x08,n) then return e,nil,"truncated type5 payload" end
    local mode=be32(blob,extra+0x04) or 0
    local size=(mode==1 or mode==2) and 0x08 or 0x0C
    if not saneRange(extra,size,n) then return e,nil,"truncated type5 extended payload" end
    e.words=wordList(blob,extra,size/4)
    -- Retail wazaSequenceEntryStart type-5 branch copies payload word 0 into
    -- runtime +0x78 and passes it directly to the GameSound start/status path.
    -- Runtime +0x7C is payload word 1 and selects the special sound route when
    -- bit 0 is set. Preserve the old generic aliases for cache compatibility,
    -- but expose the proven semantics explicitly.
    e.soundId=be32(blob,extra) or 0
    e.soundMode=mode
    e.soundParam=(size>=0x0C) and (be32(blob,extra+0x08) or 0) or nil
    e.subtype=e.soundId
    e.mode=e.soundMode
    finish=extra+size

  elseif e.entryType==6 then
    -- Loader source payload is fixed at eight bytes. Runtime subtype dispatches
    -- 0..9, but those semantics are intentionally not guessed here.
    if not saneRange(extra,0x08,n) then return e,nil,"truncated type6 payload" end
    e.words=wordList(blob,extra,2)
    e.subtype=be32(blob,extra) or 0
    e.value=be32(blob,extra+0x04) or 0
    finish=extra+0x08
  else
    return e,nil,"unsupported on-disc WazaSequence type"
  end

  return e,finish,nil
end

local function finalizeRange(e,nextAt,n)
  local finish=tonumber(nextAt) or n
  finish=math.max(e.payloadOffset or e.offset,math.min(n,finish))
  e.rawOffset=e.offset
  e.rawSize=math.max(0,finish-e.offset)
  e.payloadSize=math.max(0,finish-(e.payloadOffset or finish))
  return e
end

function W.parse(blob,opts)
  opts=type(opts)=="table" and opts or {}
  if type(blob)~="string" then return nil,"WZX blob missing" end
  local n=#blob
  if n<0xA0 then return nil,"WZX too small" end
  local count=be32(blob,0x74) or 0
  local hsdSize=be32(blob,0x84) or 0
  if count<1 or count>4096 then return nil,"invalid WazaSequence entry count" end
  local at=0xA0+align32(hsdSize)
  if at>n then return nil,"WazaSequence starts outside WZX" end

  local out={
    revision=W.revision,
    phase=opts.phase,
    member=opts.member,
    rawSize=n,
    declaredCount=count,
    hsdSize=hsdSize,
    sequenceOffset=at,
    entries={},
    complete=true,
    maxFrame=0,
    kindCounts={},
    parser="GC6E01 retail loader evidence",
  }

  -- Retail WZX count includes the sequence root/sentinel; concrete source rows
  -- are identifiers 1..count-1.
  local wanted=math.max(0,count-1)
  for index=1,wanted do
    if not plausibleHeader(blob,at,index) then
      local resync=findExpectedHeader(blob,at,index,n-at)
      if not resync then
        out.complete=false
        out.parseError=("entry %d header unavailable at 0x%X"):format(index,at)
        break
      end
      out.resyncs=out.resyncs or {}
      out.resyncs[#out.resyncs+1]={index=index,from=at,to=resync,reason="sequential-id structural resync"}
      at=resync
    end

    local entry,decodedEnd,err=parseKnownEntry(blob,at,index)
    if not entry then
      out.complete=false;out.parseError=err or ("entry %d parse failed"):format(index);break
    end
    entry.phase=opts.phase

    local nextAt
    if index<wanted then
      if decodedEnd and plausibleHeader(blob,decodedEnd,index+1) then
        nextAt=decodedEnd
      elseif decodedEnd then
        local aligned=align32(decodedEnd)
        if aligned~=decodedEnd and plausibleHeader(blob,aligned,index+1) then nextAt=aligned end
      end
      if not nextAt then
        -- Type 4 deliberately arrives here without a decodedEnd. Known entries
        -- can also contain alignment/padding that the source loader skips. The
        -- next sequential identifier is authoritative for the lossless range.
        local searchFrom=decodedEnd or (entry.payloadOffset or (at+entry.commonSize))
        nextAt=findExpectedHeader(blob,searchFrom,index+1,n-searchFrom)
      end
      if not nextAt then
        out.complete=false
        out.parseError=("entry %d cannot locate sequential entry %d after 0x%X"):format(index,index+1,decodedEnd or at)
        finalizeRange(entry,decodedEnd or n,n)
        out.entries[#out.entries+1]=entry
        break
      end
    else
      -- For a known final entry use the exact loader-derived end. For the still
      -- opaque variable type 4 retain the remainder of the WZX member.
      nextAt=decodedEnd or n
    end

    if err then entry.parseWarning=err end
    finalizeRange(entry,nextAt,n)
    out.entries[#out.entries+1]=entry
    out.kindCounts[entry.kind]=(out.kindCounts[entry.kind] or 0)+1
    at=nextAt
  end

  out.parsedCount=#out.entries
  if out.parsedCount~=wanted then out.complete=false end
  -- Absolute entry start times depend on the runtime Waza timing context and
  -- are resolved by WazaSequenceRuntime from anchorEntry/localPoint/anchorPoint.
  out.durationFrames=nil
  out.duration=nil
  return out
end

function W.roleForPhase(phase)
  phase=tostring(phase or "all"):lower()
  if phase=="damage" or phase=="status" then return "damage" end
  return "attack"
end

function W.status()
  return {revision=W.revision,source="GC6E01 WZX loader-evidence typed timeline index",
    provenTypes={model=2,particle=3,sound=5},opaqueTypes={1,4,6}}
end

W._internal={parseEntry=parseKnownEntry,plausibleHeader=plausibleHeader,findExpectedHeader=findExpectedHeader,
  commonSizeAt=commonSizeAt,align32=align32}
return W
