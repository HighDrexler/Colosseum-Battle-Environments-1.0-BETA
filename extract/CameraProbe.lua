local V=...
local FSYS,HSD=V.FSYS,V.HSD
local C={revision=1}

-- Structural walker for Colosseum .cam members (FSYS fileType 0x18).
--
-- The format probe established that a .cam IS a standard HSD archive: the
-- header at offset 0 parses cleanly under HSD.lua's own archiveAt rules and
-- carries exactly one public symbol, "scene_data". Everything needed to read it
-- therefore already exists in this codebase -- archive:ptr, archive:publicSymbol
-- and the FOBJ keyframe decoder used for trainer poses.
--
-- What is NOT yet known is the layout of the camera descriptor that scene_data
-- points at. Rather than guess offsets and ship a reader that silently produces
-- garbage, this resolves the pointer graph and dumps every reachable node with
-- each word interpreted three ways at once -- as u32, as f32, and as a
-- data-section pointer. Camera structures are unusually easy to recognise that
-- way: a near/far pair, an eye/interest position triple and a field-of-view all
-- have distinctive float signatures.
--
-- The report this writes is what a real HSD_CObjDesc reader gets written
-- against, in one pass rather than several.

local function u32(s,p) local a,b,c,d=s:byte(p,p+3);if not d then return nil end;return ((a*256+b)*256+c)*256+d end
local function f32(s,p)
  local v=u32(s,p);if not v then return nil end
  local sign=v>=2147483648 and -1 or 1;if sign<0 then v=v-2147483648 end
  local e=math.floor(v/8388608);local m=v%8388608
  if e==255 then return nil end
  if e==0 then return sign*(m/8388608)*2^-126 end
  return sign*(1+m/8388608)*2^(e-127)
end

-- A float is "interesting" if it is finite and in a range real scene data uses.
local function plausibleFloat(v)
  if type(v)~="number" or v~=v then return false end
  local a=math.abs(v)
  return v==0 or (a>=1e-4 and a<=1e6)
end

local function classify(a,word,floatValue)
  local bits={}
  if word==0 then bits[#bits+1]="null" end
  -- Raw data-section offsets are how HSD stores every internal pointer.
  if word>0 and word<a.dataSize then bits[#bits+1]=("ptr->data+0x%X"):format(word) end
  if plausibleFloat(floatValue) and floatValue~=0 then
    bits[#bits+1]=("f=%.5g"):format(floatValue)
  end
  if word>0 and word<4096 then bits[#bits+1]=("int=%d"):format(word) end
  return table.concat(bits,"  ")
end

local function dumpNode(a,addr,label,out,bytes)
  bytes=bytes or 0x40
  out[#out+1]=("--- %s @ data+0x%X (file 0x%X) ---"):format(label,addr-a.data,addr)
  local limit=math.min(bytes,(a.data+a.dataSize)-addr)
  for off=0,limit-4,4 do
    local w=u32(a.blob,addr+off+1)
    if not w then break end
    local fv=f32(a.blob,addr+off+1)
    out[#out+1]=("  +0x%02X  %08X   %s"):format(off,w,classify(a,w,fv))
  end
end

-- Walk outward from a root, following any word that resolves to a valid
-- data-section pointer. Bounded hard: a malformed file must not turn the probe
-- into an unbounded traversal.
local function walk(a,root,out,maxNodes,maxDepth)
  local seen,order={},{}
  local function visit(addr,label,depth)
    if not addr or seen[addr] or depth>maxDepth or #order>=maxNodes then return end
    if addr<a.data or addr>=a.data+a.dataSize then return end
    seen[addr]=true
    order[#order+1]={addr=addr,label=label,depth=depth}
    dumpNode(a,addr,label,out)
    for off=0,0x3C,4 do
      local w=u32(a.blob,addr+off+1)
      if w and w>0 and w<a.dataSize then
        local child=a.data+w
        visit(child,("%s+0x%02X"):format(label,off),depth+1)
      end
    end
  end
  visit(root,"scene_data",0)
  return #order
end

-- Float triples that look like world positions are the fastest way to spot the
-- eye/interest pair without knowing the struct.
local function scanTriples(a,out)
  out[#out+1]="--- plausible float triples across the data section ---"
  local found=0
  for off=0,a.dataSize-12,4 do
    local x=f32(a.blob,a.data+off+1)
    local y=f32(a.blob,a.data+off+4+1)
    local z=f32(a.blob,a.data+off+8+1)
    if plausibleFloat(x) and plausibleFloat(y) and plausibleFloat(z)
        and not (x==0 and y==0 and z==0) then
      local mag=math.max(math.abs(x),math.abs(y),math.abs(z))
      -- Colosseum world coordinates sit in roughly this band; tighter than
      -- "any float" and far more selective in practice.
      if mag>=0.5 and mag<=20000 then
        found=found+1
        if found<=40 then
          out[#out+1]=("  data+0x%04X  (%.4g, %.4g, %.4g)"):format(off,x,y,z)
        end
      end
    end
  end
  out[#out+1]=("  total plausible triples: %d"):format(found)
end

local function probeMember(arc,entry,out)
  out[#out+1]=("=========== CAM %s (type=0x%02X, %d stored) ===========")
    :format(tostring(entry.name),entry.fileType or 0,entry.storedSize or 0)
  local ok,blob=pcall(arc.extract,arc,entry,{maxOutput=8*1024*1024})
  if not ok or type(blob)~="string" then
    out[#out+1]="  extract failed: "..tostring(blob)
    return
  end
  out[#out+1]=("bytes=%d"):format(#blob)

  local okA,a=pcall(HSD.findArchive,blob)
  if not okA or not a then
    out[#out+1]="  no HSD archive resolved -- this member is NOT the expected DAT shape"
    return
  end
  out[#out+1]=("archive base=0x%X fileSize=%d dataSize=%d relocs=%d pubs=%d")
    :format(a.base,a.fileSize,a.dataSize,a.relocCount,a.publicCount)

  local syms={}
  local okS,list=pcall(a.publicSymbols,a)
  if okS then
    for _,s in ipairs(list) do
      syms[#syms+1]=("%s -> data+0x%X"):format(tostring(s.name),(s.ptr or a.data)-a.data)
    end
  end
  out[#out+1]="public symbols: "..(#syms>0 and table.concat(syms,", ") or "(none)")

  local scene=a:publicSymbol("scene_data")
  if not scene then
    out[#out+1]="  scene_data symbol absent -- dumping the data head instead"
    dumpNode(a,a.data,"data",out,0x80)
    return
  end

  local nodes=walk(a,scene,out,24,4)
  out[#out+1]=("walked %d reachable nodes from scene_data"):format(nodes)
  scanTriples(a,out)
  out[#out+1]=""
end

local DEFAULT_ARCHIVES={
  "fight_common.fsys",      -- cam_party_a_1: the battle-adjacent camera
  "fight_demo.fsys",
  "camera_shake_data.fsys",
  "D4_casino_colo.fsys",    -- cam_casino_colo_intro + cam_ending_houou_*
  "D2_crater_colo.fsys",
}

function C.run(mod,disc,progress,generated,opts)
  opts=opts or {}
  progress=progress or function() end
  local out={
    "CBE camera format probe / revision "..tostring(C.revision),
    "",
    "A .cam member is a standard HSD archive carrying one public symbol,",
    "scene_data. HSD.lua can already open it; what is missing is the camera",
    "descriptor layout. Each word below is shown as u32, as f32, and as a",
    "data-section pointer, because that is enough to recognise a near/far pair,",
    "an eye/interest triple and a field of view without knowing the struct.",
    "",
  }
  local wanted=opts.archives or DEFAULT_ARCHIVES
  local perArchive=tonumber(opts.membersPerArchive) or 2
  for i,name in ipairs(wanted) do
    progress(("CAMERA PROBE %d/%d"):format(i,#wanted),i-1,#wanted)
    out[#out+1]=("########### %s ###########"):format(name)
    local file=disc:file(name)
    if not file then
      out[#out+1]="  not on disc"
    else
      local okArc,arc=pcall(FSYS.open,disc,file)
      if not okArc then
        out[#out+1]="  FSYS open failed: "..tostring(arc)
      else
        local cams={}
        for _,e in ipairs(arc:list()) do
          if e.fileType==0x18 then cams[#cams+1]=e end
        end
        out[#out+1]=("  %d camera members present"):format(#cams)
        for _,e in ipairs(cams) do out[#out+1]=("    %s (%d bytes)"):format(tostring(e.name),e.storedSize or 0) end
        for n=1,math.min(perArchive,#cams) do probeMember(arc,cams[n],out) end
      end
    end
    out[#out+1]=""
  end
  local text=table.concat(out,"\n").."\n"
  local ok,err=mod.cache:write("build/camera_probe.txt",text)
  assert(ok,err or "camera probe write failed")
  if generated then generated[#generated+1]="build/camera_probe.txt" end
  progress("CAMERA PROBE COMPLETE",1,1)
  return {path="build/camera_probe.txt",bytes=#text}
end

return C
