local W={revision=12}

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
-- Retail entry-start/update dispatch proves source type 1 sequencing controllers,
-- type 4 procedural/effect descriptors, type 5 GameSound entries, and type 6
-- owner/model controllers. All six on-disc entry kinds are retained and decoded.

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
local function beFloat(s,p)
  local bits=be32(s,p);if not bits then return nil end
  local sign=1;if bits>=2147483648 then sign=-1;bits=bits-2147483648 end
  local exp=math.floor(bits/8388608);local mant=bits-exp*8388608
  if exp==255 then return mant==0 and sign*1e30 or 0 end
  if exp==0 then return sign*(mant/8388608)*(2^-126) end
  return sign*(1+mant/8388608)*(2^(exp-127))
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

local TYPE6_OPS={
  [0]="ambient_enable",[1]="ambient_clear",[2]="visibility_off",[3]="visibility_on",
  [4]="remove_root_null",[5]="lighting_override_enable",[6]="field_effect_clear",
  [7]="lighting_override_activate",[8]="lighting_override_clear",[9]="sequence_cleanup",
}
local TYPE4_FAMILIES={
  [0]={name="surface",runtime="world",artifact=nil},
  [1]={name="electron",runtime="world",artifact="texture"},
  [2]={name="filter",runtime="framebuffer",artifact=nil},
  [3]={name="lightning",runtime="world",artifact="texture"},
  [4]={name="trace",runtime="world",artifact="texture"},
  [5]={name="leaf",runtime="model",artifact="model"},
  [6]={name="environment_model",runtime="model",artifact="model"},
  [7]={name="sea_model",runtime="model",artifact="model"},
  [8]={name="blur",runtime="framebuffer",artifact=nil},
  [9]={name="aura",runtime="world",artifact=nil},
  [10]={name="distortion",runtime="framebuffer",artifact=nil},
  [11]={name="patchiru_model",runtime="model",artifact="model"},
  [12]={name="billboard",runtime="world",artifact="texture"},
}
local function color32(v)
  v=tonumber(v) or 0
  return {v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256}
end
-- Exact descriptor families consumed by GC6E01 fn_801364A8.  Embedded source
-- ranges are preserved so MoveFX extraction can materialize every artifact.
local function decodeType4(blob,e,limit)
  local base=tonumber(e and e.payloadOffset);local n=#blob
  if not base or base<0 or base+0x0C>n then return end
  local p=base+0x0C;local stop=math.max(p,math.min(n,tonumber(limit) or n))
  local typ=tonumber(e.effectType) or 0
  local family=TYPE4_FAMILIES[typ]
  local q={family=typ,familyName=family and family.name or "unknown",runtime=family and family.runtime or "unsupported",
    requiredArtifact=family and family.artifact or nil,frames=tonumber(e.effectFrames) or 0,
    headerWord=tonumber(e.effectHeaderWord) or 0,paramsOffset=p,artifacts={}}
  local function u(o)return be32(blob,p+o)end
  local function f(o)return beFloat(blob,p+o)end
  local function vec(o)return {f(o) or 0,f(o+4) or 0,f(o+8) or 0}end
  local function artifact(kind,off,size,meta)
    off=tonumber(off);size=tonumber(size)
    if not off or not size or size<=0 or off<0 or off+size>stop then return end
    local a={kind=kind,offset=off,size=size,alignedSize=align32(size)}
    if type(meta)=="table" then for k,v in pairs(meta)do a[k]=v end end
    q.artifacts[#q.artifacts+1]=a
  end
  if typ==0 then
    q.mode=u(0);q.count=u(4) or 0;q.layoutMode=u(8) or 0;q.flags=u(0x0C) or 0;q.keys={}
    -- fn_80137780 shifts the key table four bytes earlier only when the
    -- serialized layout selector at +08 is 1/2; +0C is the independent
    -- RGB/alpha behavior flag word.
    local off=((q.layoutMode==1 or q.layoutMode==2) and -4 or 0);local start=p+off+0x10
    for i=0,math.min(q.count,4096)-1 do local a=start+i*0x10;if a+0x10>stop then break end
      q.keys[#q.keys+1]={from=color32(be32(blob,a) or 0),to=color32(be32(blob,a+4) or 0),duration=be32(blob,a+8) or 0,raw=be32(blob,a+0x0C) or 0} end
  elseif typ==1 then
    q.start=vec(0);q.endv=vec(0x0C);q.controlA=vec(0x18);q.controlB=vec(0x24);q.width=f(0x30);q.scale=f(0x34);q.speed=f(0x38)
    q.partA=u(0x3C);q.partB=u(0x40);q.color=color32(u(0x44) or 0);q.flags=u(0x48);artifact("texture",align32(p+0x54),u(0x4C) or 0,{wrap="source"})
  elseif typ==2 then q.color=color32(u(0) or 0);q.a=f(4);q.b=f(8);q.i0=u(0x0C);q.i1=u(0x10);q.c=f(0x14)
  elseif typ==3 then
    q.colorA=color32(u(0) or 0);q.colorB=color32(u(4) or 0);q.part=u(8);q.start=vec(0x0C);q.endv=vec(0x18);q.values={}
    for o=0x24,0x44,4 do q.values[#q.values+1]=f(o) or 0 end;q.mode=u(0x48);artifact("texture",align32(p+0x54),u(0x4C) or 0,{wrap="mirror"})
  elseif typ==4 then q.color=color32(u(0) or 0);q.maxSegments=u(4);q.liveSegments=u(8);q.partA=u(0x0C);artifact("texture",align32(p+0x18),u(0x10) or 0,{wrap="clamp"})
  elseif typ==5 then
    q.values={};for o=0,0x24,4 do q.values[#q.values+1]=f(o) or 0 end;q.partA=u(0x28);q.partB=u(0x2C);q.param=u(0x30);artifact("model",align32(p+0x3C),u(0x34) or 0,{family=5})
  elseif typ==6 then
    q.start=vec(0);q.color=color32(u(0x0C) or 0);q.velocity=vec(0x10);q.countA=u(0x1C);q.countB=u(0x20);q.values={}
    for o=0x24,0x34,4 do q.values[#q.values+1]=f(o) or 0 end;q.modelMode=u(0x3C);q.modelParam=u(0x40);artifact("model",align32(p+((q.modelMode==1) and -4 or 0)+0x44),u(0x38) or 0,{family=6})
  elseif typ==7 then q.start=vec(0);q.color=color32(u(0x0C) or 0);q.velocity=vec(0x10);q.partA=u(0x1C);q.partB=u(0x20);q.a=f(0x24);q.b=f(0x28);artifact("model",align32(p+0x34),u(0x2C) or 0,{family=7})
  elseif typ==8 then
    q.a=u(0);q.b=u(4);q.count=u(8) or 0;q.mode=u(0x0C);q.keys={}
    if q.mode==2 then for i=0,math.min(q.count,4096)-1 do local a=p+0x10+i*0x10;if a+0x10>stop then break end;q.keys[#q.keys+1]={from=beFloat(blob,a) or 0,to=beFloat(blob,a+4) or 0,duration=be32(blob,a+8) or 0,raw=be32(blob,a+0x0C) or 0} end elseif q.mode==1 then q.value=beFloat(blob,p+8) or 0 end
  elseif typ==9 then
    q.count=u(0) or 0;q.mode=u(4);q.param=u(8);q.keys={};local start=(q.mode==3) and (p+0x0C) or (p+8)
    if q.mode==2 or q.mode==3 then for i=0,math.min(q.count,4096)-1 do local a=start+i*0x10;if a+0x10>stop then break end;q.keys[#q.keys+1]={from=beFloat(blob,a) or 0,to=beFloat(blob,a+4) or 0,duration=be32(blob,a+8) or 0,raw=be32(blob,a+0x0C) or 0} end end
  elseif typ==10 then q.color=color32(u(0) or 0);q.flags={u(4) or 0,u(8) or 0,u(0x0C) or 0,u(0x10) or 0,u(0x14) or 0};q.values={f(0x18) or 0,f(0x1C) or 0,f(0x20) or 0}
  elseif typ==11 then q.partA=u(8);q.partB=u(0x0C);q.mode=u(0x10);artifact("model",align32(p+0x18),u(0) or 0,{family=11})
  elseif typ==12 then q.partA=u(0);q.partB=u(4);q.a=f(8);q.b=f(0x0C);q.mode=u(0x14);q.extra=(q.mode==2) and f(0x18) or nil;artifact("texture",align32(p+((q.mode==1) and 0x18 or 0x1C)),u(0x10) or 0,{wrap="source"}) end
  e.effect=q;e.effectArtifacts=q.artifacts;e.effectFamilyName=q.familyName;e.effectRuntime=q.runtime
  e.effectRequiredArtifact=q.requiredArtifact;e.effectSupported=family~=nil
end

local function commonSizeAt(blob,at)
  -- GC6E01 serialized common header, verified against the source WZX corpus
  -- and the 1.9.11 retail-layout audit. Mode 1 omits the final resource-link
  -- word; every other mode keeps the normal 0x70-byte common record.
  local mode=be32(blob,at+0x68) or 0
  if mode==1 then return 0x6C end
  return 0x70
end

local function plausibleHeader(blob,at,expectedIdentifier)
  if not saneRange(at,0x6C,#blob) then return false end
  local id=be32(blob,at)
  local typ=be32(blob,at+0x04)
  if not id or not typ or typ<1 or typ>6 then return false end
  if expectedIdentifier~=nil and tonumber(id)~=tonumber(expectedIdentifier) then return false end
  local cs=commonSizeAt(blob,at)
  if not saneRange(at,cs,#blob) then return false end
  for _,off in ipairs({0x14,0x18,0x1C}) do
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
    -- Serialized source layout. Runtime-node offsets are different and must
    -- never be substituted here.
    attachment=be32(blob,at+0x08) or 0,
    positionType=be32(blob,at+0x0C) or 0,
    anchorEntry=be32(blob,at+0x10) or 0,
    linkedEntryKey=be32(blob,at+0x10) or 0,
    localPoint=be32(blob,at+0x14) or 0,
    sourceIndex=be32(blob,at+0x14) or 0,
    anchorPoint=be32(blob,at+0x18) or 0,
    targetIndex=be32(blob,at+0x18) or 0,
    timingIndex=be32(blob,at+0x1C) or 0,
    timingPoints=(function()
      local t={};for i=0,15 do t[#t+1]=signed32(be32(blob,at+0x20+i*4)) or 0 end;return t
    end)(),
    flags=be32(blob,at+0x60) or 0,
    flags60=be32(blob,at+0x60) or 0,
    partIndex=be32(blob,at+0x64) or 0,
    flags64=be32(blob,at+0x64) or 0,
    commonMode=mode,
    state=mode==2 and (be32(blob,at+0x6C) or 0) or 0,
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
    e.subtype=be32(blob,extra) or 0;e.controllerMode=e.subtype
    e.controllerParam=be32(blob,extra+0x04) or 0;e.controllerParamFloat=beFloat(blob,extra+0x04);e.controllerAux=be32(blob,extra+0x08) or 0
    e.tableCount=(e.subtype==3) and e.controllerParam or 0
    local tail=0
    if e.subtype==3 then
      if e.tableCount<0 or e.tableCount>65535 then return e,nil,"invalid type1 table count" end
      tail=e.tableCount*8;e.tableOffset=extra+0x0C;e.tableSize=tail;e.controllerTable={}
      if not saneRange(e.tableOffset,tail,n) then return e,nil,"truncated type1 table" end
      for i=0,e.tableCount-1 do e.controllerTable[#e.controllerTable+1]={a=be32(blob,e.tableOffset+i*8) or 0,b=be32(blob,e.tableOffset+i*8+4) or 0} end
    end
    finish=extra+0x0C+tail

  elseif e.entryType==2 then
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
    local sizeOffset=0x08
    local formatOffset=sizeOffset+0x04
    local directOffset=formatOffset+0x04
    if not saneRange(extra,directOffset,n) then return e,nil,"truncated particle payload" end
    e.particleWords=wordList(blob,extra,directOffset/4)
    e.selector=be32(blob,extra) or 0
    e.animationMode=be32(blob,extra+0x04) or 0
    e.particleDataSize=be32(blob,extra+sizeOffset) or 0
    e.particleFormat=be32(blob,extra+formatOffset) or 0
    e.effectMode=e.particleFormat
    -- Compatibility alias for old caches/callers; runtime selection now uses
    -- `selector`, matching fn_801190DC(resource, selector, animationMode & 1).
    e.rootRef=e.selector
    local prefix=directOffset+((e.particleFormat==3) and 4 or 0)
    if e.particleFormat==3 then
      if not saneRange(extra,directOffset+4,n) then return e,nil,"truncated particle format-3 payload" end
      e.format3Word=be32(blob,extra+directOffset) or 0
    end
    e.dataOffset=extra+prefix
    if (tonumber(e.state) or 0)~=0 then
      e.sharedResource=true
      e.dataSize=0
      finish=e.dataOffset
    else
      if e.particleDataSize<0 or not saneRange(e.dataOffset,e.particleDataSize,n) then
        return e,nil,"invalid/truncated particle data"
      end
      e.dataSize=e.particleDataSize
      if e.dataSize>0 then
        e.dataMagic=blob:sub(e.dataOffset+1,math.min(n,e.dataOffset+4))
        if e.dataMagic=="GPT1" then e.gptOffset=e.dataOffset end
      end
      finish=e.dataOffset+align32(e.particleDataSize)
    end

  elseif e.entryType==4 then
    -- Procedural effect descriptor. fn_801364A8 consumes the descriptor with
    -- effect family at +00 and authored frame count at +04, then advances a
    -- family-specific variable payload. Preserve the complete range and expose
    -- the proven family/duration now; W.parse locates the next sequential row
    -- to delimit the variable body losslessly.
    if not saneRange(extra,0x0C,n) then return e,nil,"truncated type4 effect descriptor" end
    e.effectType=be32(blob,extra) or 0
    e.effectFrames=be32(blob,extra+0x04) or 0
    e.effectHeaderWord=be32(blob,extra+0x08) or 0
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
    e.controllerOp=TYPE6_OPS[e.subtype] or "unknown_controller"
    e.controllerSupported=TYPE6_OPS[e.subtype]~=nil
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

  -- The pointer handed to retail wazaSequenceLoadData begins with a sequence
  -- root record. fn_801DC5F0 consumes its kind/flags/mode and optional resource
  -- before the numbered entry list. Older CBE parsers found entry 1 by resync
  -- and silently threw this root away, losing source camera/visibility/resource
  -- policy. Decode it conservatively, then locate the first numbered row.
  -- The WZX sequence root is the file-leading common record.  The numbered
  -- SequenceEntry list starts later at 0xA0 + aligned embedded root resource.
  -- Treating entry 1 as the root (the 1.9.14 regression) reads typed entry
  -- payload bytes as sequence kind/flags and collapses real attack motions to
  -- slot 0.  Dig, for example, carries kind 3 at root +0x70 while entry 1's
  -- model payload happens to contain zero at the old guessed location.
  local rootOffset=0
  local firstEntry=at
  if count>1 and not plausibleHeader(blob,firstEntry,1) then
    firstEntry=findExpectedHeader(blob,at,1,n-at)
  end
  if not firstEntry then return nil,"WazaSequence entry 1 unavailable" end
  local root={offset=rootOffset,rawSize=math.max(0,firstEntry-rootOffset)}
  local rootCommon=commonSizeAt(blob,rootOffset)
  root.commonSize=rootCommon;root.commonMode=be32(blob,rootOffset+0x68) or 0
  local rp=rootOffset+rootCommon
  if rp+0x18<=firstEntry and saneRange(rp,0x18,n) then
    root.kind=be32(blob,rp) or 0
    root.declaredCount=be32(blob,rp+0x04) or 0
    root.flags=be32(blob,rp+0x08) or 0
    root.variant=be32(blob,rp+0x0C) or 0
    root.mode=be32(blob,rp+0x10) or 0
    root.embeddedSize=be32(blob,rp+0x14) or 0
    root.payloadOffset=rp
  end
  at=firstEntry

  local out={
    revision=W.revision,
    phase=opts.phase,
    member=opts.member,
    rawSize=n,
    declaredCount=count,
    hsdSize=hsdSize,
    sequenceOffset=at,
    rootOffset=rootOffset,
    root=root,
    sequenceFlags=tonumber(root.flags) or 0,
    sequenceKind=tonumber(root.kind) or 0,
    cameraActive=true,
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
    if entry.entryType==4 then decodeType4(blob,entry,nextAt) end
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
  if phase:match("^damage") or phase=="status" then return "damage" end
  return "attack"
end

function W.status()
  return {revision=W.revision,source="GC6E01 WZX loader-evidence typed timeline index",
    provenTypes={controller=1,model=2,particle=3,effect=4,sound=5,ownerController=6},opaqueTypes={}}
end

W._internal={parseEntry=parseKnownEntry,plausibleHeader=plausibleHeader,findExpectedHeader=findExpectedHeader,
  commonSizeAt=commonSizeAt,align32=align32,type4Families=TYPE4_FAMILIES}
return W
