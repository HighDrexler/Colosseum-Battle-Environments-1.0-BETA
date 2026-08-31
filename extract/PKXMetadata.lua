local V=...
local FSYS,Dex=V.FSYS,V.ColosseumDex
local P={version=1}

-- Additive reader for the Colosseum PKX wrapper. This deliberately does not
-- participate in HSD model/root/material extraction. It reads only the battle
-- metadata surrounding the DAT payload: the 17 native animation slots, their
-- referenced DAT clip indices/timing, the 16 body-map bone references, and the
-- location of any source GPT1 bank embedded in the PKX.

local BODY_KEYS={
  "origin","mouth","chest","tail","eye_left","eye_right","hand_left","hand_right",
  "additional_1","additional_2","additional_3","additional_4",
  "foot_left","foot_right","center","additional_5",
}

local SLOT_KEYS={
  [0]="idle",[1]="statusA",[2]="physicalA",[3]="physicalB",
  [4]="physicalC",[5]="physicalD",[6]="statusB",[7]="physicalE",
  [8]="damage",[9]="damageHeavy",[10]="faint",[11]="idleB",
  [12]="specialC",[13]="idleC",[14]="idleD",[15]="idleE",[16]="takeFlight",
}

local function u16(s,o)
  local a,b=s:byte(o+1,o+2);if not b then return nil end
  return a*256+b
end
local function u32(s,o)
  local a,b,c,d=s:byte(o+1,o+4);if not d then return nil end
  return ((a*256+b)*256+c)*256+d
end
local function s32(s,o)
  local v=u32(s,o);if not v then return nil end
  return v>=2147483648 and (v-4294967296) or v
end
local function align32(n)
  n=math.max(0,tonumber(n) or 0)
  return math.floor((n+31)/32)*32
end

local function parseSlot(blob,offset,index)
  local slot={
    index=index,key=SLOT_KEYS[index] or ("slot"..index),
    animType=u32(blob,offset) or 0,
    subAnimCount=u32(blob,offset+0x04) or 0,
    damageFlags=u32(blob,offset+0x08) or 0,
    timing={},bodyMap={},subAnimations={},
    terminator=u32(blob,offset+0xCC) or 0,
  }
  for i=0,3 do slot.timing[i+1]=(u32(blob,offset+0x10+i*4) or 0)/60 end
  for i,key in ipairs(BODY_KEYS) do slot.bodyMap[key]=s32(blob,offset+0x4C+(i-1)*4) or -1 end
  local n=math.max(0,math.min(8,slot.subAnimCount))
  for i=0,n-1 do
    local motion=u32(blob,offset+0x8C+i*8) or 0
    local animation=u32(blob,offset+0x90+i*8) or 0
    -- Colosseum uses the inverse of XD's motion polarity: zero is active.
    slot.subAnimations[#slot.subAnimations+1]={
      motionType=motion,animationIndex=animation,active=motion==0,
    }
  end
  for _,sub in ipairs(slot.subAnimations) do
    if sub.active then slot.animationIndex=sub.animationIndex;break end
  end
  if slot.animationIndex==nil and slot.subAnimations[1] then
    slot.animationIndex=slot.subAnimations[1].animationIndex
  end
  slot.duration=math.max(slot.timing[1] or 0,slot.timing[2] or 0,
    slot.timing[3] or 0,slot.timing[4] or 0)
  return slot
end

function P.parse(blob)
  if type(blob)~="string" or #blob<0x40 then return nil,"PKX is truncated" end
  local datSize=u32(blob,0)
  local gpt1Length=u32(blob,0x04)
  local count=u32(blob,0x08)
  if not datSize or datSize<0x20 then return nil,"invalid Colosseum DAT size" end
  if not count or count<1 or count>17 then return nil,"invalid PKX animation slot count" end
  -- Colosseum repeats the DAT size at the embedded DAT header (offset 0x40).
  -- A mismatch identifies XD or a non-PKX payload and is rejected explicitly.
  if u32(blob,0x40)~=datSize then return nil,"not a Colosseum PKX wrapper" end
  local datOffset=0x40
  local gpt1Offset=datOffset+align32(datSize)
  local metadataOffset=gpt1Offset+align32(gpt1Length or 0)
  if metadataOffset+count*0xD0>#blob then return nil,"PKX animation metadata is truncated" end

  local out={
    format="colosseum-pkx-metadata-v1",datSize=datSize,datOffset=datOffset,
    gpt1Length=gpt1Length or 0,gpt1Offset=gpt1Offset,
    animationSlotCount=count,metadataOffset=metadataOffset,
    particleOrientation=s32(blob,0x0C) or 0,
    slots={},slotsByIndex={},bodyMap={},bodyKeys=BODY_KEYS,
  }
  for i=0,count-1 do
    local slot=parseSlot(blob,metadataOffset+i*0xD0,i)
    out.slots[slot.key]=slot;out.slotsByIndex[i]=slot
  end
  local idle=out.slots.idle or out.slotsByIndex[0]
  if idle then for _,key in ipairs(BODY_KEYS) do out.bodyMap[key]=idle.bodyMap[key] end end
  return out
end

function P.inspectSpecies(disc,dex,variant,unownForm)
  if not (disc and FSYS and Dex) then return nil,"PKX metadata source unavailable" end
  local archiveName,stem=Dex.archive(dex,variant,unownForm)
  if not archiveName then return nil,stem end
  local file=disc:file(archiveName)
  if not file then return nil,"source archive missing: "..archiveName end
  local okArc,arc=pcall(FSYS.open,disc,file)
  if not okArc or not arc then return nil,"FSYS open failed: "..tostring(arc) end
  local entries=arc:modelEntries()
  local entry=entries[1] or arc:list()[1]
  if not entry then return nil,"PKX archive has no member" end
  local okBlob,blob=pcall(arc.extract,arc,entry,{maxOutput=48*1024*1024})
  if not okBlob or type(blob)~="string" then return nil,"PKX extract failed: "..tostring(blob) end
  local metadata,err=P.parse(blob)
  if metadata then
    metadata.archive=archiveName;metadata.stem=stem;metadata.member=entry.name
  end
  return metadata,err
end

P.bodyKeys=BODY_KEYS
P.slotKeys=SLOT_KEYS
P._test={u16=u16,u32=u32,s32=s32,align32=align32}
return P
