local V=...
local FSYS,HSD=V.FSYS,V.HSD
local Waza=V.WazaSequenceExtractor
local Probe={revision=2}

-- Structural probe for WZX/WazaSequence and standalone CAM data. WZX now has
-- a lossless typed indexer; this report records the exact entry walk produced by
-- that parser against representative source moves so runtime footage can be
-- compared with a deterministic source timeline. Standalone CAM remains a raw
-- structure probe until its parameter curves are decoded.
--
-- Nothing here is redistributed: the probe runs against the user's own disc and
-- emits offsets, magic values and histograms -- never asset payloads.

local function u32(s,p) local a,b,c,d=s:byte(p,p+3);if not d then return nil end;return ((a*256+b)*256+c)*256+d end
local function f32(s,p)
  local v=u32(s,p);if not v then return nil end
  local sign=v>=2147483648 and -1 or 1;if sign<0 then v=v-2147483648 end
  local e=math.floor(v/8388608);local m=v%8388608
  if e==255 then return nil end
  if e==0 then return sign*(m/8388608)*2^-126 end
  return sign*(1+m/8388608)*2^(e-127)
end
local function printable(s)
  return (s:gsub("[^\32-\126]","."))
end
local function hexdump(blob,offset,length)
  local out={}
  local last=math.min(#blob,offset+length)
  for base=offset,last-1,16 do
    local row=blob:sub(base+1,math.min(base+16,last))
    local hex={}
    for i=1,#row do hex[i]=("%02X"):format(row:byte(i)) end
    while #hex<16 do hex[#hex+1]="  " end
    out[#out+1]=("  %08X  %s  |%s|"):format(base,table.concat(hex," "),printable(row))
  end
  return table.concat(out,"\n")
end

-- Pull ASCII runs of >=4 chars. Effect formats almost always carry symbol or
-- resource names, and those names are the fastest route into the structure.
local function strings(blob,minLen,limit)
  minLen=minLen or 4;limit=limit or 40
  local out,run,start={},{},nil
  local function flush()
    if #run>=minLen then out[#out+1]=("@0x%X %s"):format(start,table.concat(run)) end
    run={};start=nil
  end
  for i=1,#blob do
    local b=blob:byte(i)
    if b>=32 and b<=126 then
      if not start then start=i-1 end
      run[#run+1]=string.char(b)
    else
      flush()
      if #out>=limit then break end
    end
  end
  flush()
  return out
end

-- Plausible-float census. A particle/effect blob is usually dense with small
-- floats; a script/bytecode blob is not. This one number separates the two
-- likeliest shapes before anyone reads a single byte by hand.
local function floatDensity(blob,stride)
  stride=stride or 4
  local total,plausible=0,0
  for p=1,#blob-3,stride do
    local v=f32(blob,p)
    total=total+1
    if v and v==v and math.abs(v)>1e-6 and math.abs(v)<1e6 then plausible=plausible+1 end
  end
  if total==0 then return 0 end
  return plausible/total
end

-- WZX is NOT HSD. Probe revision 1 reported "EMBEDDED HSD ARCHIVES: 32" with
-- every entry reading size=256 data=0 relocs=0 pubs=0 symbols=[] -- those are
-- findArchives' brute-force scan validating on garbage, not real archives. The
-- actual payload marker is the GPT1 chunk. Report that specifically so the
-- false positives stop being mistaken for progress.
local function gpt1Report(blob)
  local lines={}
  local at=blob:find("GPT1",1,true)
  if not at then
    lines[#lines+1]="GPT1: not present"
    return lines
  end
  at=at-1
  lines[#lines+1]=("GPT1 chunk at 0x%X"):format(at)
  for off=0,7 do
    local v=u32(blob,at+4+off*4+1)
    if v then lines[#lines+1]=("  u32[+0x%02X] = 0x%08X (%d)"):format(4+off*4,v,v) end
  end
  lines[#lines+1]="  header bytes preceding GPT1 (the WZX wrapper):"
  lines[#lines+1]=hexdump(blob,math.max(0,at-0x40),0x40)
  lines[#lines+1]="  GPT1 body head:"
  lines[#lines+1]=hexdump(blob,at,0xC0)
  -- Any further GPT1 chunks: a multi-emitter effect would repeat the marker.
  local count,pos=1,at+4
  while true do
    local nxt=blob:find("GPT1",pos+1,true)
    if not nxt then break end
    count=count+1;pos=nxt
    if count<=8 then lines[#lines+1]=("  additional GPT1 at 0x%X"):format(nxt-1) end
    if count>256 then break end
  end
  lines[#lines+1]=("  total GPT1 chunks: %d"):format(count)
  return lines
end

local function describeCommon(blob,isWzx)
  local lines={}
  lines[#lines+1]=("bytes=%d"):format(#blob)
  lines[#lines+1]=("magic=%q  u32@0=0x%08X  u32@4=0x%08X  u32@8=0x%08X  u32@12=0x%08X")
    :format(printable(blob:sub(1,4)),u32(blob,1) or 0,u32(blob,5) or 0,u32(blob,9) or 0,u32(blob,13) or 0)
  lines[#lines+1]=("floatDensity=%.3f"):format(floatDensity(blob))

  -- Does an HSD archive live inside? Many GameCube effect containers embed one
  -- for their billboard/particle geometry. If so, half the work is already done
  -- because HSD.lua can read it.
  if isWzx then
    for _,l in ipairs(gpt1Report(blob)) do lines[#lines+1]=l end
    -- Deliberately skip the HSD scan for WZX: it only produces noise here.
    lines[#lines+1]="HSD scan skipped for WZX (revision 1's 32 'archives' were all false positives)."
    lines[#lines+1]="head:"
    lines[#lines+1]=hexdump(blob,0,0x140)
    return table.concat(lines,"\n")
  end

  local ok,archives=pcall(HSD.findArchives,blob)
  if ok and type(archives)=="table" and #archives>0 then
    lines[#lines+1]=("EMBEDDED HSD ARCHIVES: %d"):format(#archives)
    for i,a in ipairs(archives) do
      if i>4 then break end
      local syms={}
      local okSym,list=pcall(a.publicSymbols,a)
      if okSym then
        for j,s in ipairs(list) do
          if j>8 then break end
          syms[#syms+1]=tostring(s.name)
        end
      end
      lines[#lines+1]=("  archive @0x%X size=%d data=%d relocs=%d pubs=%d symbols=[%s]")
        :format(a.base,a.fileSize,a.dataSize,a.relocCount,a.publicCount,table.concat(syms,","))
    end
  else
    lines[#lines+1]="EMBEDDED HSD ARCHIVES: none found"
  end

  local strs=strings(blob,4,30)
  lines[#lines+1]=("ascii runs: %d"):format(#strs)
  for i,s in ipairs(strs) do
    if i>24 then break end
    lines[#lines+1]="  "..s
  end

  lines[#lines+1]="head:"
  lines[#lines+1]=hexdump(blob,0,256)
  return table.concat(lines,"\n")
end

local function readMember(disc,archiveName,progress)
  local file=disc:file(archiveName)
  if not file then return nil,"archive not on disc: "..archiveName end
  local ok,arc=pcall(FSYS.open,disc,file)
  if not ok then return nil,"FSYS open failed: "..tostring(arc) end
  local list=arc:list()
  if #list==0 then return nil,"archive has no members" end
  local entry=list[1]
  local okBlob,blob=pcall(arc.extract,arc,entry,{maxOutput=32*1024*1024})
  if not okBlob or type(blob)~="string" then return nil,"extract failed: "..tostring(blob) end
  return blob,entry
end

-- Probe a representative spread rather than everything: a handful of each
-- format is enough to establish structure, and a bounded probe cannot turn into
-- an accidental full-disc decode.
-- Names verified against the real GC6E01 file table. Probe revision 1 guessed
-- three of these wrong (wzx_hakaikousen / wzx_jishin / wzx_status_doku do not
-- exist) and wasted a third of the sample.
local DEFAULT_WZX={
  "wzx_10manvolt_attack.fsys",   -- Thunderbolt, attack phase
  "wzx_10manvolt_damage.fsys",   -- same move, damage phase: reveals phase split
  "wzx_kaenhousya_attack.fsys",  -- Flamethrower
  "wzx_hakai_attack.fsys",       -- Hyper Beam
  "wzx_fubuki_attack.fsys",      -- Blizzard
  "wzx_doku_status.fsys",        -- a status overlay: likely a different shape
  "wzx_solarbeam_special.fsys",  -- a "special" variant, for comparison
}

-- Camera data lives in far more places than fight_common. 160 members of type
-- 0x18 exist across the disc, including the Realgam/Orre colosseum archives CBE
-- already opens for arenas.
local DEFAULT_CAM={
  "fight_common.fsys","fight_demo.fsys","camera_shake_data.fsys",
  "D4_casino_colo.fsys","D2_crater_colo.fsys","T1_ancient_colo.fsys",
}

local function describeWaza(blob,name)
  if not (Waza and type(Waza.parse)=="function") then return "typed Waza parser unavailable" end
  local phase=tostring(name or ""):lower():match("_([^_]+)%.fsys$")
  local ok,timeline,err=pcall(Waza.parse,blob,{phase=phase,member=name})
  if not ok or type(timeline)~="table" then return "typed Waza parse failed: "..tostring(ok and err or timeline) end
  local lines={("typed Waza: parsed=%d declared=%d complete=%s durationFrames=%d")
    :format(tonumber(timeline.parsedCount) or 0,tonumber(timeline.declaredCount) or 0,tostring(timeline.complete==true),tonumber(timeline.durationFrames) or 0)}
  if timeline.parseError then lines[#lines+1]="  parseError="..tostring(timeline.parseError) end
  for _,e in ipairs(timeline.entries or {}) do
    lines[#lines+1]=("  #%d off=0x%X type=%d kind=%s id=%s start=%s hit=%s finish=%s attach=%s raw=%d gpt=%s")
      :format(tonumber(e.index) or 0,tonumber(e.offset) or 0,tonumber(e.entryType) or -1,tostring(e.kind),
        tostring(e.identifier),tostring(e.start),tostring(e.hit),tostring(e.finish),tostring(e.attachment),tonumber(e.rawSize) or 0,
        e.gptOffset and ("0x"..string.format("%X",e.gptOffset)) or "-")
  end
  return table.concat(lines,"\n")
end

function Probe.run(mod,disc,progress,generated,opts)
  opts=opts or {}
  progress=progress or function() end
  local out={
    "CBE source format probe / revision "..tostring(Probe.revision),
    "Formats: WZX (FSYS fileType 0x20) WazaSequence, CAM (0x18) camera cuts.",
    "Purpose: validate typed WazaSequence indexing and preserve raw CAM structure.",
    "",
  }

  local wanted=opts.wzx or DEFAULT_WZX
  for i,name in ipairs(wanted) do
    progress(("PROBE WZX %d/%d"):format(i,#wanted),i-1,#wanted)
    out[#out+1]=("=========== WZX %s ==========="):format(name)
    local blob,entry=readMember(disc,name,progress)
    if not blob then
      out[#out+1]="  UNAVAILABLE: "..tostring(entry)
    else
      out[#out+1]=("member=%s fileType=0x%02X stored=%d")
        :format(tostring(entry.name),entry.fileType or 0,entry.storedSize or 0)
      out[#out+1]=describeWaza(blob,name)
      out[#out+1]=describeCommon(blob,true)
    end
    out[#out+1]=""
  end

  -- Camera data rides inside fight_common alongside menu and tool members, so
  -- enumerate the whole archive and dump only the 0x18 (.cam) entries.
  for _,name in ipairs(opts.cam or DEFAULT_CAM) do
    progress("PROBE CAM",0,1)
    out[#out+1]=("=========== CAM container %s ==========="):format(name)
    local file=disc:file(name)
    if not file then
      out[#out+1]="  UNAVAILABLE: not on disc"
    else
      local ok,arc=pcall(FSYS.open,disc,file)
      if not ok then
        out[#out+1]="  FSYS open failed: "..tostring(arc)
      else
        for _,e in ipairs(arc:list()) do
          out[#out+1]=("  member idx=%d name=%s type=0x%02X bytes=%d")
            :format(e.index,tostring(e.name),e.fileType or 0,e.storedSize or 0)
        end
        for _,e in ipairs(arc:list()) do
          if e.fileType==0x18 then
            out[#out+1]=("--- CAM member %s ---"):format(tostring(e.name))
            local okB,blob=pcall(arc.extract,arc,e,{maxOutput=8*1024*1024})
            if okB and type(blob)=="string" then
              out[#out+1]=describeCommon(blob)
              -- Camera data is small; a fuller dump is affordable and is what
              -- actually lets a reader be written.
              out[#out+1]="full dump:"
              out[#out+1]=hexdump(blob,0,math.min(#blob,2048))
            else
              out[#out+1]="  extract failed: "..tostring(blob)
            end
          end
        end
      end
    end
    out[#out+1]=""
  end

  local text=table.concat(out,"\n").."\n"
  local ok,err=mod.cache:write("build/format_probe.txt",text)
  assert(ok,err or "probe write failed")
  if generated then generated[#generated+1]="build/format_probe.txt" end
  progress("PROBE COMPLETE",1,1)
  return {path="build/format_probe.txt",bytes=#text}
end

return Probe
