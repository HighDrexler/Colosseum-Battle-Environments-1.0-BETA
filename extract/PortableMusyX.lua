-- Portable, source-backed renderer for the subset of Nintendo/MusyX data used
-- by Pokemon Colosseum's battle music. It intentionally does not depend on a
-- host executable: Android can synthesize the player's own GC6E01 data into
-- the same PCM16 cache layout consumed by CBE's Music runtime.
--
-- This is not a general MusyX implementation. It implements the SongGroup,
-- page/keymap/layer, DSP-ADPCM, ADSR, and SoundMacro operations that are
-- actually present in Colosseum's 11 battle sequences, Snag-success cue, and battle SFXGroup.
local P={}

local okFfi,ffi=pcall(require,"ffi")
if not okFfi then ffi=nil end

local floor,ceil,min,max,abs=math.floor,math.ceil,math.min,math.max,math.abs
local pow=math.pow or function(a,b)return a^b end
local sqrt=math.sqrt

-- Amuse applies a deliberately nonlinear volume law before routing each voice.
-- Keeping this table identical to Amuse is much more important than adding an
-- arbitrary master gain: the old portable renderer's linear gain + 0.28 master
-- attenuation changed the balance between quiet and loud instruments.
local VOLUME_TABLE={
0.000000,0.000031,0.000153,0.000397,0.000702,0.001129,0.001648,0.002228,0.002930,0.003723,
0.004608,0.005585,0.006653,0.007843,0.009125,0.010498,0.011963,0.013550,0.015198,0.016999,
0.018860,0.020844,0.022919,0.025117,0.027406,0.029817,0.032319,0.034944,0.037660,0.040468,
0.043428,0.046480,0.049623,0.052889,0.056276,0.059786,0.063387,0.067110,0.070956,0.074923,
0.078982,0.083163,0.087466,0.091922,0.096469,0.101138,0.105930,0.110843,0.115879,0.121036,
0.126347,0.131748,0.137303,0.142979,0.148778,0.154729,0.160772,0.166997,0.173315,0.179785,
0.186407,0.193121,0.200018,0.207007,0.214179,0.221473,0.228919,0.236488,0.244209,0.252083,
0.260079,0.268258,0.276559,0.285012,0.293649,0.302408,0.311319,0.320383,0.329600,0.339000,
0.348521,0.358226,0.368084,0.378094,0.388287,0.398633,0.409131,0.419813,0.430647,0.441664,
0.452864,0.464217,0.475753,0.487442,0.499313,0.511399,0.523606,0.536027,0.548631,0.561419,
0.574389,0.587542,0.600879,0.614399,0.628132,0.642018,0.656148,0.670431,0.684927,0.699637,
0.714530,0.729637,0.744926,0.760430,0.776147,0.792077,0.808191,0.824549,0.841090,0.857845,
0.874844,0.892056,0.909452,0.927122,0.945006,0.963073,0.981414,1.000000,1.000000,
}
local DLS_VOLUME_TABLE={
0.000000,0.000062,0.000248,0.000558,0.000992,0.001550,0.002232,0.003038,0.003968,0.005022,
0.006200,0.007502,0.008928,0.010478,0.012152,0.013950,0.015872,0.017918,0.020088,0.022382,
0.024800,0.027342,0.030008,0.032798,0.035712,0.038750,0.041912,0.045198,0.048608,0.052142,
0.055800,0.059582,0.063488,0.067518,0.071672,0.075950,0.080352,0.084878,0.089528,0.094302,
0.099200,0.104222,0.109368,0.114638,0.120032,0.125550,0.131192,0.136958,0.142848,0.148862,
0.155000,0.161262,0.167648,0.174158,0.180792,0.187550,0.194432,0.201438,0.208568,0.215822,
0.223200,0.230702,0.238328,0.246078,0.253953,0.261951,0.270073,0.278319,0.286689,0.295183,
0.303801,0.312543,0.321409,0.330399,0.339513,0.348751,0.358113,0.367599,0.377209,0.386943,
0.396801,0.406783,0.416889,0.427119,0.437473,0.447951,0.458553,0.469279,0.480129,0.491103,
0.502201,0.513423,0.524769,0.536239,0.547833,0.559551,0.571393,0.583359,0.595449,0.607663,
0.620001,0.632463,0.645049,0.657759,0.670593,0.683551,0.696633,0.709839,0.723169,0.736623,
0.750202,0.763904,0.777730,0.791680,0.805754,0.819952,0.834274,0.848720,0.863290,0.877984,
0.892802,0.907744,0.922810,0.938000,0.953314,0.968752,0.984314,1.000000,1.000000,
}
local MIDI_TO_TIME={
0,10,20,30,40,50,60,70,80,90,100,110,110,120,130,140,150,160,170,190,200,220,230,250,270,290,310,330,350,380,
410,440,470,500,540,580,620,660,710,760,820,880,940,1000,1000,1100,1200,1300,1400,1500,1600,1700,1800,2000,2100,2300,2400,2600,2800,3000,
3200,3500,3700,4000,4300,4600,4900,5300,5700,6100,6500,7000,7500,8100,8600,9300,9900,10000,11000,12000,13000,14000,15000,16000,17000,18000,19000,21000,22000,24000,
26000,28000,30000,32000,34000,37000,39000,42000,45000,49000,50000,55000,60000,65000,
}

local function u16be(s,o)local a,b=s:byte(o,o+1);assert(b,"truncated u16be");return a*256+b end
local function s16be(s,o)local v=u16be(s,o);return v>=32768 and v-65536 or v end
local function u32be(s,o)local a,b,c,d=s:byte(o,o+3);assert(d,"truncated u32be");return a*16777216+b*65536+c*256+d end
local function u16le(s,o)local a,b=s:byte(o,o+1);assert(b,"truncated u16le");return a+b*256 end
local function u32le(s,o)local a,b,c,d=s:byte(o,o+3);assert(d,"truncated u32le");return a+b*256+c*65536+d*16777216 end
local function s32le(s,o)local v=u32le(s,o);return v>=2147483648 and v-4294967296 or v end
local function s8(s,o)local v=s:byte(o);assert(v,"truncated s8");return v>=128 and v-256 or v end
local function le16(v)v=v%65536;return string.char(v%256,floor(v/256)%256)end
local function le32(v)v=v%4294967296;return string.char(v%256,floor(v/256)%256,floor(v/65536)%256,floor(v/16777216)%256)end
local function clamp(v,lo,hi)if v<lo then return lo elseif v>hi then return hi end return v end
local function lookupTableExact(t,vol)
  local x=(tonumber(vol) or 0)*127;if x<0 then x=0 elseif x>127 then x=127 end
  local f=floor(x);local c=ceil(x);local a=t[f+1] or 0
  if f==c then return a end
  local b=t[c+1] or a;local q=x-f;return a*(1-q)+b*q
end
local VOLUME_FAST,DLS_VOLUME_FAST={},{}
for i=0,4095 do
  local v=i/4095;VOLUME_FAST[i+1]=lookupTableExact(VOLUME_TABLE,v);DLS_VOLUME_FAST[i+1]=lookupTableExact(DLS_VOLUME_TABLE,v)
end
local function lookupVolume(vol,dls)
  if vol<=0 then return 0 elseif vol>=1 then return 1 end
  local idx=floor(vol*4095+0.5)+1;return (dls and DLS_VOLUME_FAST or VOLUME_FAST)[idx]
end
local function midiTime(v)return (MIDI_TO_TIME[clamp(floor(tonumber(v) or 0),0,103)+1] or 0)/1000 end
local function wav16(raw,rate,channels)
  return "RIFF"..le32(36+#raw).."WAVEfmt "..le32(16)..le16(1)..le16(channels)..le32(rate)
    ..le32(rate*channels*2)..le16(channels*2)..le16(16).."data"..le32(#raw)..raw
end
local function reverseWords8(raw)
  return raw:sub(1,4):reverse()..raw:sub(5,8):reverse()
end
local function validWav(bytes)
  return type(bytes)=="string" and #bytes>=44 and bytes:sub(1,4)=="RIFF" and bytes:sub(9,12)=="WAVE"
end

local function parseProject(proj)
  assert(type(proj)=="string" and #proj>=48,"portable MusyX: PROJ missing/truncated")
  local groupEnd=u32be(proj,1)
  assert(groupEnd<=#proj and groupEnd>=40,"portable MusyX: unsupported PROJ group")
  local groupId=u16be(proj,5)
  local groupType=u16be(proj,7)
  assert(groupType==0,"portable MusyX: snd_music group is not a SongGroup")
  local pageOff=u32be(proj,29)
  local drumOff=u32be(proj,33)
  local midiOff=u32be(proj,37)
  local normal,drum={},{}
  local o=pageOff+1
  while o+5<=#proj and u16be(proj,o)~=65535 do
    local obj=u16be(proj,o);local priority=proj:byte(o+2);local maxVoices=proj:byte(o+3);local program=proj:byte(o+4)
    normal[program]={obj=obj,priority=priority,maxVoices=maxVoices};o=o+6
  end
  o=drumOff+1
  while o+5<=#proj and u16be(proj,o)~=65535 do
    local obj=u16be(proj,o);local priority=proj:byte(o+2);local maxVoices=proj:byte(o+3);local program=proj:byte(o+4)
    drum[program]={obj=obj,priority=priority,maxVoices=maxVoices};o=o+6
  end
  local setups={};o=midiOff+1
  while o+83<=groupEnd do
    local songId=u16be(proj,o);o=o+4
    local chans={}
    for ch=0,15 do
      chans[ch]={program=proj:byte(o),volume=proj:byte(o+1),pan=proj:byte(o+2),reverb=proj:byte(o+3),chorus=proj:byte(o+4)}
      o=o+5
    end
    setups[songId]=chans
  end
  return {groupId=groupId,normal=normal,drum=drum,setups=setups}
end

-- GameCube SFXGroup project reader.  Amuse's retail parser reads the SFX
-- table from GroupHeader.pageTableOff as: u16 count, u16 pad, then count
-- SFXEntry records (SFX id, PageObject id, priority/max voices, default
-- velocity/pan/key).  Keeping this separate from parseProject makes the
-- existing battle-music SongGroup path completely unchanged.
local function parseSfxProject(proj)
  assert(type(proj)=="string" and #proj>=40,"portable MusyX SFX: PROJ missing/truncated")
  local groupEnd=u32be(proj,1)
  assert(groupEnd<=#proj and groupEnd>=40,"portable MusyX SFX: unsupported PROJ group")
  local groupId=u16be(proj,5)
  local groupType=u16be(proj,7)
  assert(groupType==1,"portable MusyX SFX: snd_se_battle group is not an SFXGroup")
  local pageOff=u32be(proj,29)
  local o=pageOff+1
  assert(o+3<=#proj,"portable MusyX SFX: page table missing")
  local count=u16be(proj,o);o=o+4
  local entries={}
  for i=1,count do
    assert(o+9<=#proj and o+9<=groupEnd,"portable MusyX SFX: truncated SFX entry "..i)
    local id=u16be(proj,o)
    entries[id]={id=id,obj=u16be(proj,o+2),priority=proj:byte(o+4),maxVoices=proj:byte(o+5),
      velocity=proj:byte(o+6),pan=proj:byte(o+7),key=proj:byte(o+8)}
    o=o+10
  end
  return {groupId=groupId,entries=entries,count=count}
end

local function parsePool(pool)
  assert(type(pool)=="string" and #pool>=20,"portable MusyX: POOL missing/truncated")
  local smOff=u32be(pool,1)+1
  local tableOff=u32be(pool,5)+1
  local keymapOff=u32be(pool,9)+1
  local layerOff=u32be(pool,13)+1
  local function objects(first,last)
    local out={};local o=first
    while o+7<=last and u32be(pool,o)~=4294967295 do
      local size=u32be(pool,o);local id=u16be(pool,o+4)
      assert(size>=8 and o+size-1<=#pool,"portable MusyX: malformed POOL object")
      out[id]=pool:sub(o+8,o+size-1);o=o+size
    end
    return out
  end
  local macros=objects(smOff,tableOff-1)
  local rawTables=objects(tableOff,keymapOff-1)
  local rawKeymaps=objects(keymapOff,layerOff-1)
  local rawLayers=objects(layerOff,#pool)
  local tables={}
  for id,data in pairs(rawTables) do
    if #data==8 then
      local attack=u16le(data,1);local decay=u16le(data,3);local sustain=u16le(data,5);local release=u16le(data,7)
      tables[id]={kind="adsr",attack=attack/1000,decay=(decay==32768) and 0 or decay/1000,
        sustain=clamp(sustain/4096,0,1),release=release/1000}
    elseif #data==20 then
      local attack=s32le(data,1);local decay=s32le(data,5);local sustain=u16le(data,9);local release=u16le(data,11)
      local velToAttack=s32le(data,13);local keyToDecay=s32le(data,17)
      local function tc(v)return v==-2147483648 and 0 or pow(2,v/(1200*65536)) end
      tables[id]={kind="dls",attack=tc(attack),decay=tc(decay),sustain=clamp(sustain/4096,0,1),release=release/1000,
        velToAttack=velToAttack,keyToDecay=keyToDecay}
    else
      local curve={kind="curve",data={}}
      for i=1,#data do curve.data[i]=data:byte(i) end
      tables[id]=curve
    end
  end
  local keymaps={}
  for id,data in pairs(rawKeymaps) do
    local arr={}
    for key=0,127 do
      local o=key*8+1
      if o+4<=#data then arr[key]={obj=u16be(data,o),transpose=s8(data,o+2),pan=s8(data,o+3),priority=s8(data,o+4)} end
    end
    keymaps[id]=arr
  end
  local layers={}
  for id,data in pairs(rawLayers) do
    local count=#data>=4 and u32be(data,1) or 0;local arr={}
    for i=0,count-1 do
      local o=5+i*12
      if o+8<=#data then
        arr[#arr+1]={obj=u16be(data,o),keyLo=s8(data,o+2),keyHi=s8(data,o+3),transpose=s8(data,o+4),
          volume=s8(data,o+5),priority=s8(data,o+6),span=s8(data,o+7),pan=s8(data,o+8)}
      end
    end
    layers[id]=arr
  end
  return {macros=macros,tables=tables,keymaps=keymaps,layers=layers}
end

local function parseSdir(sdir)
  assert(type(sdir)=="string" and #sdir>=32,"portable MusyX: SDIR missing/truncated")
  local out={}
  for o=1,#sdir-31,32 do
    local id=u16be(sdir,o);if id==65535 then break end
    local rawCount=u32be(sdir,o+16)
    local e={id=id,offset=u32be(sdir,o+4),pitch=sdir:byte(o+12),rate=u16be(sdir,o+14),
      format=floor(rawCount/16777216),count=rawCount%16777216,loopStart=u32be(sdir,o+20),loopLength=u32be(sdir,o+24),adpcm=u32be(sdir,o+28)}
    e.looped=e.loopLength>0 and e.loopStart~=4294967295
    out[id]=e
  end
  return out
end

local function parseSong(seq)
  assert(type(seq)=="string" and #seq>=64,"portable MusyX: SNG missing/truncated")
  local trackIdxOff=u32be(seq,1);local regionIdxOff=u32be(seq,5);local chanMapOff=u32be(seq,9);local tempoOff=u32be(seq,13)
  local initialRaw=u32be(seq,17);local initialTempo=initialRaw%2147483648
  local trackIdx={};local maxRegion=-1
  for i=0,63 do trackIdx[i]=u32be(seq,trackIdxOff+1+i*4) end
  local chanMap={};for i=0,63 do chanMap[i]=seq:byte(chanMapOff+1+i) or 0 end
  local tracks={};local loopEndCounts={};local loopTrackCount=0
  for ti=0,63 do
    local at=trackIdx[ti]
    if at and at>0 and at+12<=#seq then
      local regs={};local o=at+1
      while o+11<=#seq do
        local startTick=u32be(seq,o);local regionIndex=s16be(seq,o+8);local loopTo=s16be(seq,o+10)
        regs[#regs+1]={startTick=startTick,regionIndex=regionIndex,loopTo=loopTo}
        o=o+12
        if regionIndex==-2 then
          -- MusyX TrackRegion -2 is the loop sentinel. Its startTick is the
          -- authored loop-end tick and loopTo identifies the earlier region.
          -- The old portable renderer discarded both fields and therefore put
          -- up to six seconds of voice/reverb tail inside the file that the
          -- host loops forever.
          loopTrackCount=loopTrackCount+1;loopEndCounts[startTick]=(loopEndCounts[startTick] or 0)+1
        end
        if regionIndex<0 then break end
        if regionIndex>maxRegion then maxRegion=regionIndex end
      end
      tracks[#tracks+1]={channel=chanMap[ti],regions=regs}
    end
  end
  local regionOffsets={}
  for i=0,maxRegion do regionOffsets[i]=u32be(seq,regionIdxOff+1+i*4) end
  local tempos={}
  if tempoOff and tempoOff>0 then
    local o=tempoOff+1
    while o+7<=#seq do
      local tick=u32be(seq,o);local tempo=u32be(seq,o+4)
      if tick==4294967295 then break end
      tempos[#tempos+1]={tick=tick,tempo=tempo%2147483648};o=o+8
    end
  end
  table.sort(tempos,function(a,b)return a.tick<b.tick end)
  local events={};local serial=0
  local function add(ev)serial=serial+1;ev.serial=serial;events[#events+1]=ev end
  for _,track in ipairs(tracks) do
    local ch=track.channel
    for _,reg in ipairs(track.regions) do
      if reg.regionIndex<0 then break end
      local ro=regionOffsets[reg.regionIndex]
      if ro then
        local o=ro+13 -- 12-byte region header
        local tick=reg.startTick
        while o+1<=#seq do
          local delta=0
          while true do
            assert(o+1<=#seq,"portable MusyX: truncated event time")
            local part=u16be(seq,o)
            if o+3<=#seq and seq:byte(o+2)==0 and seq:byte(o+3)==0 then delta=delta+part;o=o+4 else delta=delta+part;o=o+2;break end
          end
          tick=tick+delta
          assert(o+1<=#seq,"portable MusyX: truncated event")
          local a,b=seq:byte(o,o+1)
          if a==255 and b==255 then o=o+2;break
          elseif a>=128 and b>=128 then add({tick=tick,kind="ctrl",ch=ch,ctrl=b%128,value=a%128});o=o+2
          elseif a>=128 then add({tick=tick,kind="program",ch=ch,program=a%128});o=o+2
          else
            assert(o+3<=#seq,"portable MusyX: truncated note")
            add({tick=tick,kind="note",ch=ch,key=a%128,velocity=b%128,length=u16be(seq,o+2)});o=o+4
          end
        end
      end
    end
  end
  table.sort(events,function(a,b)
    if a.tick~=b.tick then return a.tick<b.tick end
    local pa=(a.kind=="note") and 2 or 1;local pb=(b.kind=="note") and 2 or 1
    if pa~=pb then return pa<pb end
    return a.serial<b.serial
  end)
  local loopEndTick=nil
  if loopTrackCount>0 then
    -- A stereo PCM loop can only have one boundary. Colosseum's music tracks
    -- normally agree on the sentinel tick; require unanimity rather than guess
    -- if an unusual source song uses independent channel periods.
    for tick,count in pairs(loopEndCounts) do if count==loopTrackCount then loopEndTick=tick;break end end
  end
  return {initialTempo=initialTempo,tempos=tempos,events=events,loopEndTick=loopEndTick,loopTrackCount=loopTrackCount}
end

local function tickSeconds(song,tick)
  local sec,curTick,tempo=0,0,song.initialTempo
  for _,change in ipairs(song.tempos) do
    if change.tick>tick then break end
    if change.tick>curTick then sec=sec+(change.tick-curTick)/(tempo*384/60) end
    curTick=change.tick;tempo=change.tempo
  end
  if tick>curTick then sec=sec+(tick-curTick)/(tempo*384/60) end
  return sec
end

local function resolveObject(pool,obj,key,seen,out,transpose,volume,pan)
  seen=seen or {};out=out or {};transpose=transpose or 0;volume=volume or 1;pan=pan or 64
  if seen[obj] then return out end
  seen[obj]=true
  if obj>=32768 then
    local list=pool.layers[obj]
    if list then
      for _,m in ipairs(list) do
        if key>=m.keyLo and key<=m.keyHi then
          local v=volume
          if m.volume>=0 then v=v*clamp(m.volume/127,0,1) end
          local p=(m.pan==-128) and pan or m.pan
          resolveObject(pool,m.obj,clamp(key+m.transpose,0,127),seen,out,transpose+m.transpose,v,p)
        end
      end
    end
  elseif obj>=16384 then
    local km=pool.keymaps[obj];local m=km and km[clamp(key,0,127)]
    if m then resolveObject(pool,m.obj,clamp(key+m.transpose,0,127),seen,out,transpose+m.transpose,volume,(m.pan==-128) and pan or m.pan) end
  else
    out[#out+1]={macro=obj,transpose=transpose,volume=volume,pan=pan}
  end
  seen[obj]=nil
  return out
end

local function compileMacro(pool,id)
  pool.compiled=pool.compiled or {};local hit=pool.compiled[id];if hit then return hit end
  local data=pool.macros[id];if not data then return nil end
  local spec={id=id,noteAdd=0,waitKeyOff=true,waitSampleEnd=true,fadeIn=0,volumeScale=nil,dlsVol=false}
  local postKeyOff=false
  for o=1,#data-7,8 do
    local c=reverseWords8(data:sub(o,o+7));local op=c:byte(1)
    if op==0 then break
    elseif op==0x0c then spec.adsrId=u16le(c,2);spec.adsrDls=c:byte(4)~=0
    elseif op==0x0d then spec.volumeScale={scale=s8(c,2),add=s8(c,3),tableId=u16le(c,4),original=c:byte(6)~=0}
    elseif op==0x0f then
      local msSwitch=c:byte(6)~=0;local n=u16le(c,7)
      spec.postEnvelope={scale=s8(c,2),add=s8(c,3),tableId=u16le(c,4),msSwitch=msSwitch,value=n}
    elseif op==0x10 then spec.sampleId=u16le(c,2)
    elseif op==0x14 then
      local msSwitch=c:byte(6)~=0;local n=u16le(c,7)
      spec.fadeIn={scale=s8(c,2),add=s8(c,3),tableId=u16le(c,4),msSwitch=msSwitch,value=n}
    elseif op==0x16 then
      spec.adsrCtrl={attack=c:byte(2),decay=c:byte(3),sustain=c:byte(4),release=c:byte(5)}
    elseif op==0x18 then spec.noteAdd=spec.noteAdd+s8(c,2)
    elseif op==0x19 then spec.noteSet=s8(c,2)
    elseif op==0x1c then
      local msSwitch=c:byte(6)~=0;local n=u16le(c,7)
      spec.vibrato={level=s8(c,2)*100+s8(c,3),modwheel=c:byte(4)~=0,msSwitch=msSwitch,value=n}
    elseif op==0x21 then spec.volumeScaleDls={scale=(function()local v=u16le(c,2);return v>=32768 and v-65536 or v end)(),original=c:byte(4)~=0}
    elseif op==0x58 then spec.dlsVol=c:byte(2)~=0
    elseif op==0x59 then spec.keygroup={group=c:byte(2),killNow=c:byte(3)~=0}
    elseif op==0x07 then
      local keyOff=c:byte(2)~=0;local sampleEnd=c:byte(4)~=0;local n=u16le(c,7)
      if n==65535 and not postKeyOff then spec.waitKeyOff=keyOff;spec.waitSampleEnd=sampleEnd;postKeyOff=true end
    end
  end
  local adsr=pool.tables[spec.adsrId]
  if adsr and (adsr.kind=="adsr" or adsr.kind=="dls") then spec.adsr=adsr else spec.adsr=nil end
  pool.compiled[id]=spec;return spec
end

local function decodeDsp(sdir,samp,entry,cache)
  local hit=cache[entry.id];if hit then return hit end
  assert(entry.format==0 or entry.format==1,"portable MusyX: sample "..entry.id.." is not DSP-ADPCM")
  local byteCount=ceil(entry.count/14)*8
  assert(entry.offset+byteCount<=#samp,"portable MusyX: DSP sample exceeds SAMP")
  assert(entry.adpcm>0 and entry.adpcm+39<=#sdir,"portable MusyX: DSP coefficients exceed SDIR")
  local coefs={}
  for i=0,7 do coefs[i]={s16be(sdir,entry.adpcm+9+i*4),s16be(sdir,entry.adpcm+11+i*4)} end
  local arr=ffi and ffi.new("int16_t[?]",entry.count) or nil
  local packedParts,packedBytes={},{}
  local loopHist2=s16be(sdir,entry.adpcm+5);local loopHist1=s16be(sdir,entry.adpcm+7)
  -- Amuse starts a DSP sample with zero predictor history. The SDIR history is
  -- restored only when a loop turns over; using it at sample start colors every transient.
  local prev2,prev1=0,0;local done=0
  while done<entry.count do
    local frame=entry.offset+1+floor(done/14)*8;local header=samp:byte(frame);assert(header,"portable MusyX: missing DSP frame")
    local predictor=floor(header/16);local exponent=header%16;assert(predictor<=7,"portable MusyX: invalid DSP predictor")
    local c1,c2=coefs[predictor][1],coefs[predictor][2];local n=min(14,entry.count-done)
    for i=0,n-1 do
      local packed=samp:byte(frame+1+floor(i/2));assert(packed,"portable MusyX: truncated DSP nibble")
      local nib=(i%2==0) and floor(packed/16) or packed%16;if nib>=8 then nib=nib-16 end
      local sample=floor((nib*2^exponent*2048+1024+c1*prev1+c2*prev2)/2048)
      sample=clamp(sample,-32768,32767);prev2,prev1=prev1,sample
      if ffi then
        arr[done]=sample
      else
        local v=sample%65536
        packedBytes[#packedBytes+1]=string.char(v%256,floor(v/256))
        if #packedBytes>=4096 then packedParts[#packedParts+1]=table.concat(packedBytes);packedBytes={} end
      end
      done=done+1
    end
  end
  if not ffi and #packedBytes>0 then packedParts[#packedParts+1]=table.concat(packedBytes) end
  hit={pcm=ffi and arr or table.concat(packedParts),count=entry.count,rate=entry.rate,pitch=(entry.pitch==0 and 60 or entry.pitch),looped=entry.looped,
    loopStart=entry.loopStart,loopEnd=entry.loopStart+entry.loopLength,loopHist1=loopHist1,loopHist2=loopHist2}
  cache[entry.id]=hit;return hit
end

local function pcmAt(sample,index)
  local i=floor(index);if i<0 or i>=sample.count then return 0 end
  local q=index-i
  if ffi then
    local a=tonumber(sample.pcm[i]);if q<=0 or i+1>=sample.count then return a end
    local b=tonumber(sample.pcm[i+1]);return a+(b-a)*q
  end
  local o=i*2+1;local lo,hi=sample.pcm:byte(o,o+1);if not hi then return 0 end
  local a=lo+hi*256;if a>=32768 then a=a-65536 end
  if q<=0 or i+1>=sample.count then return a end
  lo,hi=sample.pcm:byte(o+2,o+3);if not hi then return a end
  local b=lo+hi*256;if b>=32768 then b=b-65536 end
  return a+(b-a)*q
end

local function adsrTimes(adsr,ctrl,ctrlSpec,key,vel)
  if ctrlSpec then
    return midiTime(ctrl[ctrlSpec.attack] or 0),midiTime(ctrl[ctrlSpec.decay] or 0),
      clamp((ctrl[ctrlSpec.sustain] or 0)/127,0,1),midiTime(ctrl[ctrlSpec.release] or 0)
  end
  if not adsr then return 0,0,1,0 end
  if adsr.kind=="dls" then
    local a=adsr.attack or 0;local d=adsr.decay or 0
    if adsr.velToAttack and adsr.velToAttack~=-2147483648 then a=a+(vel or 0)*(adsr.velToAttack/65536/1000)/128 end
    if adsr.keyToDecay and adsr.keyToDecay~=-2147483648 then d=d+(key or 0)*(adsr.keyToDecay/65536/1000)/128 end
    return max(0,a),max(0,d),adsr.sustain or 1,adsr.release or 0
  end
  return adsr.attack or 0,adsr.decay or 0,adsr.sustain or 1,adsr.release or 0
end
local function adsrPreValues(a,d,s,t)
  if a>0 and t<a then return t/a end
  if d>0 and t<a+d then return 1-(1-s)*((t-a)/d) end
  return s
end
local function refreshVoiceAdsr(v)
  local a,d,s,r=adsrTimes(v.adsr,v.ctrl,v.adsrCtrl,v.key,v.velocity)
  v.adsrA,v.adsrD,v.adsrS,v.adsrR=a,d,s,r
end
local function adsrAtVoice(v,t)
  if not v.adsr and not v.adsrCtrl then return 1 end
  local a,d,s,r=v.adsrA or 0,v.adsrD or 0,v.adsrS or 1,v.adsrR or 0
  if v.keyoff and t>=v.keyoff then
    if r<=0 then return 0 end
    if v.releaseStart==nil then v.releaseStart=adsrPreValues(a,d,s,v.keyoff) end
    local q=(t-v.keyoff)/r;if q>=1 then return 0 end
    return min(v.releaseStart,1-q)
  end
  return adsrPreValues(a,d,s,t)
end

local function noteVoices(project,pool,sdirEntries,song,setupId,outputRate)
  local setup=project.setups[setupId];assert(setup,"portable MusyX: setup "..tostring(setupId).." missing")
  local chan={}
  local relevant={[1]=true,[7]=true,[10]=true,[20]=true,[22]=true,[23]=true,[24]=true,[91]=true,[93]=true}
  for ch=0,15 do
    local src=setup[ch] or {program=0,volume=127,pan=64,reverb=0,chorus=0}
    local ctrl={[1]=0,[7]=127,[10]=64,[91]=src.reverb or 0,[93]=src.chorus or 0}
    chan[ch]={program=src.program,volume=src.volume,pan=src.pan,reverb=src.reverb or 0,chorus=src.chorus or 0,ctrl=ctrl,automation={}}
    ctrl[7]=src.volume or 127;ctrl[10]=src.pan or 64
  end
  local voices={};local lastSec=0
  local function pushAuto(st,sec,ctrl,value)
    st.ctrl[ctrl]=value
    if relevant[ctrl] then st.automation[#st.automation+1]={sec=sec,ctrl=ctrl,value=value} end
    if ctrl==7 then st.volume=value elseif ctrl==10 then st.pan=value elseif ctrl==91 then st.reverb=value elseif ctrl==93 then st.chorus=value end
  end
  local function bootstrapAdsr(st,spec,sec)
    local a=spec and spec.adsrCtrl;if not a then return end
    if (st.ctrl[a.sustain] or 0)==0 then
      pushAuto(st,sec,a.attack,10);pushAuto(st,sec,a.sustain,127);pushAuto(st,sec,a.release,10)
    end
  end
  for _,ev in ipairs(song.events) do
    local st=chan[ev.ch] or chan[0];local evSec=tickSeconds(song,ev.tick)
    if ev.kind=="program" then st.program=ev.program
    elseif ev.kind=="ctrl" then pushAuto(st,evSec,ev.ctrl,ev.value)
    elseif ev.kind=="note" and ev.velocity>0 then
      local page=((ev.ch==9) and project.drum or project.normal)[st.program]
      if page then
        local mappings=resolveObject(pool,page.obj,ev.key)
        local startSec=evSec;local offSec=tickSeconds(song,ev.tick+ev.length)
        if startSec>lastSec then lastSec=startSec end
        for _,map in ipairs(mappings) do
          local spec=compileMacro(pool,map.macro)
          local entry=spec and spec.sampleId and sdirEntries[spec.sampleId]
          if entry then
            bootstrapAdsr(st,spec,startSec)
            local key=(spec.noteSet~=nil) and spec.noteSet or (ev.key+map.transpose+(spec.noteAdd or 0));key=clamp(key,0,127)
            local pitchCents=key*100
            local basePitch=(entry.pitch==0 and 60 or entry.pitch)*100
            local ratio=pow(2,(pitchCents-basePitch)/1200)
            local macroVol=1
            if spec.volumeScale then
              local vs=spec.volumeScale;local sourceVel=ev.velocity
              local eval=clamp(floor(sourceVel*vs.scale/127+vs.add),0,127)
              local curve=pool.tables[vs.tableId]
              if curve and curve.kind=="curve" and #curve.data>=128 then macroVol=(curve.data[eval+1] or 0)/127 else macroVol=eval/127 end
            elseif spec.volumeScaleDls then
              local vs=spec.volumeScaleDls;macroVol=ev.velocity*vs.scale/4096/127
            end
            local keyoff=nil;if spec.waitKeyOff then keyoff=max(0,offSec-startSec) end
            local ctrl={};for k,v in pairs(st.ctrl) do ctrl[k]=v end
            local fadeIn=0
            if type(spec.fadeIn)=="table" then
              local q=spec.fadeIn.msSwitch and 1000 or (song.initialTempo*384/60)
              fadeIn=(spec.fadeIn.value or 0)/q
            end
            local vib=nil
            if spec.vibrato then
              local q=spec.vibrato.msSwitch and 1000 or (song.initialTempo*384/60)
              vib={level=spec.vibrato.level,modwheel=spec.vibrato.modwheel,period=(spec.vibrato.value or 0)/q}
            end
            local objectVolume=clamp(map.volume or 1,0,1)
            local channelVolume=clamp((st.volume or 127)/127,0,1)
            local resolvedVolume=objectVolume*channelVolume
            voices[#voices+1]={startSec=startSec,startFrame=floor(startSec*outputRate+0.5),keyoff=keyoff,
              sampleId=spec.sampleId,baseStep=entry.rate*ratio/outputRate,velocity=ev.velocity,macroVolume=macroVol,dlsVol=spec.dlsVol,
              objectVolume=objectVolume,initialUserVol=resolvedVolume,targetUserVol=resolvedVolume,userVol=resolvedVolume,
              pan=((map.pan~=nil and tonumber(map.pan)~= -128) and clamp(tonumber(map.pan) or 64,0,127) or (st.pan or 64)),reverb=st.reverb or 0,chorus=st.chorus or 0,adsr=spec.adsr,adsrCtrl=spec.adsrCtrl,ctrl=ctrl,
              fadeIn=fadeIn,waitSampleEnd=spec.waitSampleEnd,vibrato=vib,key=key,keygroup=spec.keygroup,
              automation=st.automation,autoIndex=#st.automation+1}
          end
        end
      end
    end
  end
  for _,v in ipairs(voices) do refreshVoiceAdsr(v);v.userSlewStep=1/max(1,outputRate*0.005);v.reverbGain=lookupVolume(clamp((v.reverb or 0)/127,0,1),v.dlsVol) end
  table.sort(voices,function(a,b)if a.startFrame~=b.startFrame then return a.startFrame<b.startFrame end return (a.sampleId or 0)<(b.sampleId or 0) end)
  return voices,lastSec
end

-- Build the voice graph used by Engine::fxStart for a retail SFXGroup entry.
-- Unlike a SongGroup there is no sequencer note length: GameSound starts the
-- PageObject at the entry's authored default key/velocity and the SoundMacro
-- retires naturally at sample/envelope end.  A hard render ceiling below keeps
-- a malformed/intentional looping macro from creating an unbounded cache file.
local function sfxVoices(project,pool,sdirEntries,sfxId,outputRate)
  local entry=project and project.entries and project.entries[tonumber(sfxId)]
  if not entry then return nil,"GameSound id "..tostring(sfxId).." missing from SFXGroup" end
  local key=clamp(tonumber(entry.key) or 60,0,127)
  local velocity=clamp(tonumber(entry.velocity) or 127,0,127)
  local mappings=resolveObject(pool,entry.obj,key)
  local voices={}
  for _,map in ipairs(mappings or {}) do
    local spec=compileMacro(pool,map.macro)
    local sampleEntry=spec and spec.sampleId and sdirEntries[spec.sampleId]
    if sampleEntry then
      local resolvedKey=(spec.noteSet~=nil) and spec.noteSet or (key+(map.transpose or 0)+(spec.noteAdd or 0))
      resolvedKey=clamp(resolvedKey,0,127)
      local pitchCents=resolvedKey*100
      local basePitch=(sampleEntry.pitch==0 and 60 or sampleEntry.pitch)*100
      local ratio=pow(2,(pitchCents-basePitch)/1200)
      local macroVol=1
      if spec.volumeScale then
        local vs=spec.volumeScale
        local eval=clamp(floor(velocity*vs.scale/127+vs.add),0,127)
        local curve=pool.tables[vs.tableId]
        if curve and curve.kind=="curve" and #curve.data>=128 then macroVol=(curve.data[eval+1] or 0)/127 else macroVol=eval/127 end
      elseif spec.volumeScaleDls then
        macroVol=velocity*spec.volumeScaleDls.scale/4096/127
      end
      local ctrl={[1]=0,[7]=127,[10]=tonumber(entry.pan) or 64,[91]=0,[93]=0}
      local fadeIn=0
      if type(spec.fadeIn)=="table" then fadeIn=(spec.fadeIn.value or 0)/1000 end
      local vib=nil
      if spec.vibrato then
        vib={level=spec.vibrato.level,modwheel=spec.vibrato.modwheel,period=(spec.vibrato.value or 0)/1000}
      end
      local baseUser=clamp(tonumber(map.volume) or 1,0,1)
      local voice={startSec=0,startFrame=0,keyoff=nil,sampleId=spec.sampleId,
        baseStep=sampleEntry.rate*ratio/outputRate,velocity=velocity,macroVolume=macroVol,dlsVol=spec.dlsVol,
        objectVolume=baseUser,initialUserVol=baseUser,targetUserVol=baseUser,userVol=baseUser,
        pan=tonumber(entry.pan) or 64,reverb=0,chorus=0,adsr=spec.adsr,adsrCtrl=spec.adsrCtrl,ctrl=ctrl,
        fadeIn=fadeIn,waitSampleEnd=spec.waitSampleEnd,vibrato=vib,key=resolvedKey,keygroup=spec.keygroup,
        automation={},autoIndex=1}
      refreshVoiceAdsr(voice);voice.userSlewStep=1/max(1,outputRate*0.005);voice.reverbGain=0
      voices[#voices+1]=voice
    end
  end
  if #voices==0 then return nil,"GameSound id "..tostring(sfxId).." resolved no playable SoundMacro sample" end
  table.sort(voices,function(a,b)return (a.sampleId or 0)<(b.sampleId or 0) end)
  return voices,nil,entry
end

local function newReverbLine(tap)
  tap=max(1,floor(tap));local n=tap+2;local data={};for i=1,n do data[i]=0 end
  return {n=n,data=data,inp=1,out=((0-tap)%n)+1,last=0}
end
local function advanceLine(line)
  line.inp=line.inp+1;if line.inp>line.n then line.inp=1 end
  line.out=line.out+1;if line.out>line.n then line.out=1 end
end
local function newReverb(rate)
  local ratio=rate/32000;local timeSamples=3.0*rate
  local function comb(delay)
    local tap=max(1,floor(delay*ratio));local l=newReverbLine(tap);l.coef=pow(10,tap*-3/timeSamples);return l
  end
  local function ap(delay)return newReverbLine(max(1,floor(delay*ratio))) end
  local function channel()
    local preN=max(1,floor(rate*0.1)-1);local pre={};for i=1,preN do pre[i]=0 end
    return {comb1=comb(1789),comb2=comb(1999),ap1=ap(433),ap2=ap(149),lp=0,pre=pre,preN=preN,preP=1}
  end
  return {left=channel(),right=channel(),allpass=0.5,damping=0.55,wet=0.48,dry=0.12}
end
local function reverbSample(rv,c,input)
  local sample2=c.pre[c.preP] or 0;c.pre[c.preP]=input;c.preP=c.preP+1;if c.preP>c.preN then c.preP=1 end
  local l1,l2=c.comb1,c.comb2
  l1.data[l1.inp]=l1.coef*l1.last+sample2;l2.data[l2.inp]=l2.coef*l2.last+sample2
  l1.last=l1.data[l1.out] or 0;l2.last=l2.data[l2.out] or 0;advanceLine(l1);advanceLine(l2)
  local ap1=c.ap1;local written=rv.allpass*ap1.last+l1.last+l2.last
  ap1.data[ap1.inp]=written;local low=-(rv.allpass*written-ap1.last);ap1.last=ap1.data[ap1.out] or 0;advanceLine(ap1)
  c.lp=rv.damping*c.lp+low*0.3
  local ap2=c.ap2;written=rv.allpass*ap2.last+c.lp;ap2.data[ap2.inp]=written
  local allpass=-(rv.allpass*written-ap2.last);ap2.last=ap2.data[ap2.out] or 0;advanceLine(ap2)
  return rv.wet*allpass+rv.dry*input
end
local function updatePan(v)
  local front=clamp(((v.pan or 64)-64)/63,-1,1)
  v.left=sqrt(-front*0.5+0.5);v.right=sqrt(front*0.5+0.5)
end
local function applyAutomation(v,absSec)
  local list=v.automation or {};local i=v.autoIndex or 1
  while i<=#list and (list[i].sec or 0)<=absSec+1e-9 do
    local e=list[i];v.ctrl[e.ctrl]=e.value
    if e.ctrl==7 then v.targetUserVol=(tonumber(v.objectVolume) or 1)*clamp(e.value/127,0,1)
    elseif e.ctrl==10 then v.pan=e.value;updatePan(v)
    elseif e.ctrl==91 then v.reverb=e.value;v.reverbGain=lookupVolume(clamp(e.value/127,0,1),v.dlsVol)
    elseif e.ctrl==1 and v.vibrato then v.mod=e.value end
    if v.adsrCtrl and (e.ctrl==v.adsrCtrl.attack or e.ctrl==v.adsrCtrl.decay or e.ctrl==v.adsrCtrl.sustain or e.ctrl==v.adsrCtrl.release) then refreshVoiceAdsr(v) end
    i=i+1
  end
  v.autoIndex=i
end
local function renderPcm(project,pool,sdir,samp,song,setupId,outputRate,minFrames,progress,sampleCache,preparedVoices,opts)
  opts=type(opts)=="table" and opts or {}
  local voices,lastSec
  if type(preparedVoices)=="table" then voices=preparedVoices;lastSec=tonumber(opts.lastSec) or 0
  else voices,lastSec=noteVoices(project,pool,sdir,song,setupId,outputRate) end
  sampleCache=sampleCache or {};local block=512;local active={};local nextVoice=1;local parts={};local frame=0
  local maxTail=tonumber(opts.maxTail) or 6
  local releaseFloor=tonumber(opts.releaseFloor) or 1
  local totalFrames=max(minFrames or 0,floor((lastSec+maxTail)*outputRate+0.5))
  if totalFrames<outputRate then totalFrames=outputRate end
  local peak=0;local clipped=0;local rv=newReverb(outputRate)
  while frame<totalFrames do
    local n=min(block,totalFrames-frame)
    local mix=ffi and ffi.new("double[?]",n*2) or {};local rev=ffi and ffi.new("double[?]",n*2) or {}
    if not ffi then for i=1,n*2 do mix[i]=0;rev[i]=0 end end
    while nextVoice<=#voices and voices[nextVoice].startFrame<frame+n do
      local v=voices[nextVoice]
      if v.startFrame>=frame then
        -- Keygroups are global in Amuse. The Colosseum battle bank uses killNow
        -- for its three keygroup voices, so a new one hard-stops an older peer.
        if v.keygroup and v.keygroup.group and v.keygroup.group~=0 then
          local kept={}
          for _,old in ipairs(active) do
            if old.keygroup and old.keygroup.group==v.keygroup.group and v.keygroup.killNow then old._killed=true else kept[#kept+1]=old end
          end
          active=kept
        end
        local entry=sdir[v.sampleId];v.sample=decodeDsp(sdir._raw,samp,entry,sampleCache);v.pos=0;v.localStart=v.startFrame-frame
        updatePan(v);v.mod=v.ctrl[1] or 0;active[#active+1]=v
      end
      nextVoice=nextVoice+1
    end
    local survivors={}
    for _,v in ipairs(active) do
      local sample=v.sample or decodeDsp(sdir._raw,samp,sdir[v.sampleId],sampleCache);v.sample=sample
      local startI=max(0,v.localStart or 0);v.localStart=0
      local alive=not v._killed
      for i=startI,n-1 do
        if not alive then break end
        local globalFrame=frame+i;local t=(globalFrame-v.startFrame)/outputRate;local absSec=globalFrame/outputRate
        applyAutomation(v,absSec)
        if v.targetUserVol~=v.userVol then
          local step=v.userSlewStep
          if v.targetUserVol<v.userVol then v.userVol=max(v.targetUserVol,v.userVol-step) else v.userVol=min(v.targetUserVol,v.userVol+step) end
        end
        local env=adsrAtVoice(v,t)
        local envelopeVol=1
        if v.fadeIn and v.fadeIn>0 and t<v.fadeIn then envelopeVol=clamp(t/v.fadeIn,0,1) end
        if env<=0 and v.keyoff then alive=false;break end
        local idx=v.pos
        if idx>=sample.count then
          if sample.looped and sample.loopEnd>sample.loopStart then
            local span=sample.loopEnd-sample.loopStart;idx=sample.loopStart+((idx-sample.loopStart)%span);v.pos=idx
          else alive=false;break end
        elseif sample.looped and idx>=sample.loopEnd and sample.loopEnd>sample.loopStart then
          local span=sample.loopEnd-sample.loopStart;idx=sample.loopStart+((idx-sample.loopStart)%span);v.pos=idx
        end
        local sv=pcmAt(sample,idx)/32768
        local level=clamp(v.userVol*(v.macroVolume or 1)*envelopeVol*env*(v.velocity/127),0,1)
        local gain=lookupVolume(level,v.dlsVol)
        local dry=sv*gain;local reverbGain=v.reverbGain or 0
        local l=dry*v.left;local r=dry*v.right;local rl=dry*reverbGain*v.left;local rr=dry*reverbGain*v.right
        local mi=i*2
        if ffi then
          mix[mi]=mix[mi]+l;mix[mi+1]=mix[mi+1]+r;rev[mi]=rev[mi]+rl;rev[mi+1]=rev[mi+1]+rr
        else
          mix[mi+1]=mix[mi+1]+l;mix[mi+2]=mix[mi+2]+r;rev[mi+1]=rev[mi+1]+rl;rev[mi+2]=rev[mi+2]+rr
        end
        local vibCents=0
        if v.vibrato and v.vibrato.period and v.vibrato.period>0 then
          local scale=v.vibrato.modwheel and ((v.ctrl[1] or 0)/127) or 1
          if scale~=0 then
            local phase=(t/v.vibrato.period)%1;local tri
            if phase<0.25 then tri=phase/0.25 elseif phase>=0.75 then tri=(phase-0.75)/0.25-1 else tri=(phase-0.25)/0.5*-2+1 end
            vibCents=(v.vibrato.level or 0)*tri*scale
          end
        end
        if vibCents~=0 then v.pos=v.pos+v.baseStep*pow(2,vibCents/1200) else v.pos=v.pos+v.baseStep end
      end
      if alive then survivors[#survivors+1]=v end
    end
    active=survivors
    local bytes={}
    for i=0,n-1 do
      local mi=i*2
      local dl=ffi and tonumber(mix[mi]) or mix[mi+1] or 0;local dr=ffi and tonumber(mix[mi+1]) or mix[mi+2] or 0
      local rvl=ffi and tonumber(rev[mi]) or rev[mi+1] or 0;local rvr=ffi and tonumber(rev[mi+1]) or rev[mi+2] or 0
      local ol=dl+reverbSample(rv,rv.left,rvl);local orr=dr+reverbSample(rv,rv.right,rvr)
      local x=ol;if abs(x)>peak then peak=abs(x) end;if abs(x)>1 then clipped=clipped+1 end
      if x>1 then x=1 elseif x< -1 then x=-1 end
      local q=x>=0 and floor(x*32767+0.5) or ceil(x*32768-0.5);q=q%65536;bytes[#bytes+1]=string.char(q%256,floor(q/256))
      x=orr;if abs(x)>peak then peak=abs(x) end;if abs(x)>1 then clipped=clipped+1 end
      if x>1 then x=1 elseif x< -1 then x=-1 end
      q=x>=0 and floor(x*32767+0.5) or ceil(x*32768-0.5);q=q%65536;bytes[#bytes+1]=string.char(q%256,floor(q/256))
    end
    parts[#parts+1]=table.concat(bytes);frame=frame+n
    if progress and frame%(outputRate*4)<block then progress(frame,totalFrames) end
    if nextVoice>#voices and #active==0 and frame>=(minFrames or 0) and frame>floor((lastSec+releaseFloor)*outputRate) then totalFrames=frame end
  end
  return table.concat(parts),peak,#voices,clipped
end

function P.prepare(payload)
  assert(type(payload)=="table" and type(payload.music)=="table","portable MusyX: payload missing")
  local project=parseProject(payload.music.proj);local pool=parsePool(payload.music.pool);local sdir=parseSdir(payload.music.sdir)
  sdir._raw=payload.music.sdir
  return {project=project,pool=pool,sdir=sdir,samp=payload.music.samp,sampleCache={}}
end

function P.prepareSfx(payload)
  assert(type(payload)=="table" and type(payload.sfx)=="table","portable MusyX SFX: payload missing")
  local project=parseSfxProject(payload.sfx.proj);local pool=parsePool(payload.sfx.pool);local sdir=parseSdir(payload.sfx.sdir)
  sdir._raw=payload.sfx.sdir
  return {project=project,pool=pool,sdir=sdir,samp=payload.sfx.samp,sampleCache={}}
end

function P.hasSfx(ctx,id)
  return type(ctx)=="table" and type(ctx.project)=="table" and type(ctx.project.entries)=="table"
    and ctx.project.entries[math.floor(tonumber(id) or -1)]~=nil
end

function P.renderSfx(ctx,sfxId,outputRate,progress)
  assert(type(ctx)=="table" and type(ctx.project)=="table","portable MusyX SFX: context missing")
  outputRate=tonumber(outputRate) or 32000
  sfxId=math.floor(tonumber(sfxId) or -1);assert(sfxId>=0,"portable MusyX SFX: invalid GameSound id")
  local voices,why,entry=sfxVoices(ctx.project,ctx.pool,ctx.sdir,sfxId,outputRate)
  assert(voices,why)
  -- Retail battle SEs are one-shots. Most naturally retire at sample/macro end;
  -- four seconds is only a safety ceiling for malformed or deliberately-looped
  -- source macros and prevents one bad ID from exploding the generated cache.
  local pcm,peak,count,clipped=renderPcm(nil,ctx.pool,ctx.sdir,ctx.samp,nil,nil,outputRate,0,progress,ctx.sampleCache,voices,{maxTail=4,releaseFloor=.08,lastSec=0})
  local wav=wav16(pcm,outputRate,2);assert(validWav(wav),"portable MusyX SFX: generated invalid WAV")
  return wav,{frames=#pcm/4,peak=peak,voices=count,rate=outputRate,clipped=clipped,sfxId=sfxId,entry=entry}
end

function P.renderSong(ctx,sequence,setupId,loopFrame48,outputRate,progress)
  outputRate=tonumber(outputRate) or 22050
  local song=parseSong(sequence)
  local loopOut=loopFrame48 and floor(loopFrame48*outputRate/48000+0.5) or nil
  local loopEndOut=nil
  if loopOut and song.loopEndTick then
    loopEndOut=floor(tickSeconds(song,song.loopEndTick)*outputRate+0.5)
    if loopEndOut<=loopOut then loopEndOut=nil end
  end
  local minFrames=loopOut and (loopEndOut or (loopOut+outputRate*6)) or outputRate*2
  local pcm,peak,voices,clipped=renderPcm(ctx.project,ctx.pool,ctx.sdir,ctx.samp,song,setupId,outputRate,minFrames,progress,ctx.sampleCache)
  local frames=#pcm/4
  if loopOut then
    assert(loopOut>0 and loopOut<frames,("portable MusyX: scaled loop frame %d outside render %d"):format(loopOut,frames))
    local cut=loopOut*4
    local loopEndFrame=loopEndOut and min(loopEndOut,frames) or frames
    assert(loopEndFrame>loopOut,"portable MusyX: empty loop segment")
    local intro=wav16(pcm:sub(1,cut),outputRate,2)
    local loop=wav16(pcm:sub(cut+1,loopEndFrame*4),outputRate,2)
    assert(validWav(intro) and validWav(loop),"portable MusyX: generated invalid theme WAV")
    return intro,loop,{frames=frames,loopEndFrame=loopEndFrame,sourceLoopEndTick=song.loopEndTick,peak=peak,voices=voices,rate=outputRate,clipped=clipped}
  end
  local wav=wav16(pcm,outputRate,2);assert(validWav(wav),"portable MusyX: generated invalid WAV")
  return wav,nil,{frames=frames,peak=peak,voices=voices,rate=outputRate,clipped=clipped}
end

function P.renderAll(payload,send)
  send=send or function()end
  local rate=tonumber(payload.sampleRate) or 22050
  local ctx=P.prepare(payload)
  local complete=0
  for i,song in ipairs(payload.songs or {}) do
    local source=tostring(song.source or ("song "..i));send({kind="source",source=source})
    local intro,loop,stats=P.renderSong(ctx,assert(song.sequence,source..": sequence missing"),assert(tonumber(song.setup),source..": setup missing"),assert(tonumber(song.loopFrame),source..": loop frame missing"),rate,
      function(frame,total) send({kind="heartbeat",source=source,frame=frame,total=total}) end)
    assert(stats.peak>0.00001,source..": portable synthesis produced silence")
    send({kind="asset",source=source.." intro",path=song.introPath,bytes=intro,stats=stats});complete=complete+1
    send({kind="asset",source=source.." loop",path=song.loopPath,bytes=loop,stats=stats});complete=complete+1
    intro=nil;loop=nil;if collectgarbage then pcall(collectgarbage,"step",300) end
  end
  for i,shot in ipairs(payload.oneShots or {}) do
    local source=tostring(shot.source or ("one-shot "..i));send({kind="source",source=source})
    local wav,_,stats=P.renderSong(ctx,assert(shot.sequence,source..": sequence missing"),assert(tonumber(shot.setup),source..": setup missing"),nil,rate,
      function(frame,total) send({kind="heartbeat",source=source,frame=frame,total=total}) end)
    assert(stats.peak>0.00001,source..": portable synthesis produced silence")
    send({kind="asset",source=source,path=shot.outputPath,bytes=wav,stats=stats});complete=complete+1
    wav=nil;if collectgarbage then pcall(collectgarbage,"step",300) end
  end
  return {complete=complete,rate=rate,renderer="portable Lua MusyX battle fidelity v4 / source pan+volume / 48 kHz"}
end

P.validWav=validWav
return P
