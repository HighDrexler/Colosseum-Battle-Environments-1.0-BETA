-- CBE universal in-process MusyX audio renderer (alpha).
-- MusyX behavior is implemented from the AxioDL/amuse MIT-licensed reference;
-- attribution/license text is retained in third_party/amuse/LICENSE.txt.
-- All copyrighted source bytes arrive over the compute-thread channel from the
-- user's launcher-validated GC6E01 import. No host executable is spawned.
require("love.thread")
local okFfi,ffi=pcall(require,"ffi")
assert(okFfi and ffi,"CBE MusyX renderer requires LuaJIT FFI in the compute worker")

local inputName,outputName=...
local input=love.thread.getChannel(inputName)
local output=love.thread.getChannel(outputName)
local payload=input:demand()
local RATE=tonumber(payload and payload.sampleRate) or 32000
local TICKS_PER_BEAT=384
local currentSource="preparing in-process MusyX renderer"

local function send(value) output:push(value) end
local function trimLog(text)
  text=tostring(text or ""):gsub("\r","\n"):gsub("\n+"," / ")
  if #text>1600 then text=text:sub(1,1600).."..." end
  return text
end
local function u16le(s,o)local a,b=s:byte(o,o+1);assert(b,"u16le past end");return a+b*256 end
local function u32le(s,o)local a,b,c,d=s:byte(o,o+3);assert(d,"u32le past end");return a+b*256+c*65536+d*16777216 end
local function u16be(s,o)local a,b=s:byte(o,o+1);assert(b,"u16be past end");return a*256+b end
local function u32be(s,o)local a,b,c,d=s:byte(o,o+3);assert(d,"u32be past end");return a*16777216+b*65536+c*256+d end
local function s16be(s,o)local v=u16be(s,o);return v>=32768 and v-65536 or v end
local function s8(v)return v>=128 and v-256 or v end
local function le16(v)v=v%65536;return string.char(v%256,math.floor(v/256)%256)end
local function le32(v)v=v%4294967296;return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
local function wav16(raw,rate,channels)
  local dataBytes=#raw
  return "RIFF"..le32(36+dataBytes).."WAVEfmt "..le32(16)..le16(1)..le16(channels)
    ..le32(rate)..le32(rate*channels*2)..le16(channels*2)..le16(16)
    .."data"..le32(dataBytes)..raw
end
local function clamp(v,lo,hi)if v<lo then return lo elseif v>hi then return hi end return v end

local function parseProject(proj)
  assert(type(proj)=="string" and #proj>=40,"music PROJ is truncated")
  local endOff=u32be(proj,1)
  local normalOff=u32be(proj,29)
  local drumOff=u32be(proj,33)
  local setupOff=u32be(proj,37)
  assert(endOff>setupOff and endOff<=#proj,"music PROJ header offsets are invalid")
  local function pages(first,last)
    local out={};local p=first+1
    while p+5<=last do
      local obj=u16be(proj,p);if obj==65535 then break end
      local priority,maxVoices,program=proj:byte(p+2,p+4)
      out[program]={object=obj,priority=priority,maxVoices=maxVoices}
      p=p+6
    end
    return out
  end
  local normal=pages(normalOff,drumOff)
  local drum=pages(drumOff,setupOff)
  local setups={};local p=setupOff+1
  while p+83<=endOff do
    local sid=u16be(proj,p);local channels={}
    for ch=0,15 do
      local q=p+4+ch*5
      channels[ch+1]={program=proj:byte(q),volume=proj:byte(q+1),pan=proj:byte(q+2),reverb=proj:byte(q+3),chorus=proj:byte(q+4)}
    end
    setups[sid]=channels;p=p+84
  end
  return {normal=normal,drum=drum,setups=setups}
end

local function commandBytes(pool,p)
  local a,b,c,d,e,f,g,h=pool:byte(p,p+7)
  assert(h,"truncated SoundMacro command")
  return {d,c,b,a,h,g,f,e}
end
local function cmdU16(c,i)return c[i]+c[i+1]*256 end
local function cmdU32(c,i)return c[i]+c[i+1]*256+c[i+2]*65536+c[i+3]*16777216 end

local function parsePool(pool)
  assert(type(pool)=="string" and #pool>=16,"music POOL is truncated")
  local macroOff=u32be(pool,1);local tableOff=u32be(pool,5);local keymapOff=u32be(pool,9);local layerOff=u32be(pool,13)
  assert(macroOff<tableOff and tableOff<=keymapOff and keymapOff<=layerOff and layerOff<#pool,"music POOL offsets are invalid")
  local macros={};local p=macroOff+1
  while p+7<=tableOff do
    local size=u32be(pool,p);if size==0 or size==65535 or size==4294967295 then break end
    assert(size>=8 and p+size-1<=#pool,"SoundMacro chunk exceeds POOL")
    local id=u16be(pool,p+4);local commands={};local q=p+8;local last=p+size-1
    while q+7<=last do commands[#commands+1]=commandBytes(pool,q);q=q+8 end
    macros[id]=commands;p=p+size
  end
  local tables={};p=tableOff+1
  while p+7<=keymapOff do
    local size=u32be(pool,p);if size==0 or size==65535 or size==4294967295 then break end
    assert(size>=8 and p+size-1<=#pool,"table chunk exceeds POOL")
    local id=u16be(pool,p+4);tables[id]=pool:sub(p+8,p+size-1);p=p+size
  end
  local keymaps={};p=keymapOff+1
  while p+7<=layerOff do
    local size=u32be(pool,p);if size==0 or size==65535 or size==4294967295 then break end
    assert(size>=8 and p+size-1<=#pool,"keymap chunk exceeds POOL")
    local id=u16be(pool,p+4);local data=p+8;local entries={}
    for key=0,127 do
      local q=data+key*8;if q+7>p+size-1 then break end
      entries[key+1]={object=u16be(pool,q),transpose=s8(pool:byte(q+2)),pan=pool:byte(q+3),priority=s8(pool:byte(q+4))}
    end
    keymaps[id]=entries;p=p+size
  end
  local layers={};p=layerOff+1
  while p+7<=#pool do
    local size=u32be(pool,p);if size==0 or size==65535 or size==4294967295 then break end
    if size<12 or p+size-1>#pool then break end
    local id=u16be(pool,p+4);local data=p+8;local count=u32be(pool,data);local entries={}
    for i=0,count-1 do
      local q=data+4+i*12;if q+11>p+size-1 then break end
      entries[#entries+1]={object=u16be(pool,q),lo=pool:byte(q+2),hi=pool:byte(q+3),transpose=s8(pool:byte(q+4)),volume=pool:byte(q+5),priority=s8(pool:byte(q+6)),span=pool:byte(q+7),pan=pool:byte(q+8)}
    end
    layers[id]=entries;p=p+size
  end
  return {macros=macros,tables=tables,keymaps=keymaps,layers=layers}
end

local function parseSampleDirectory(sdir)
  local out={}
  for p=1,#sdir-31,32 do
    local id=u16be(sdir,p);if id==65535 then break end
    local raw=u32be(sdir,p+16)
    out[id]={id=id,offset=u32be(sdir,p+4),base=sdir:byte(p+12),rate=u16be(sdir,p+14),format=math.floor(raw/16777216),count=raw%16777216,loopStart=u32be(sdir,p+20),loopLen=u32be(sdir,p+24),adpcm=u32be(sdir,p+28)}
  end
  return out
end

local function parseRegion(sequence,p)
  local headerSize=u32be(sequence,p);local pos=p+4+headerSize;local tick=0;local events={}
  while pos+3<=#sequence do
    local delta=u16be(sequence,pos);local a,b=sequence:byte(pos+2,pos+3);pos=pos+4;tick=tick+delta
    if a==0 and b==0 then
      -- no-op
    elseif a==255 and b==255 then break
    elseif a<128 and b<128 then
      assert(pos+1<=#sequence,"note length exceeds sequence")
      local len=u16be(sequence,pos);pos=pos+2;events[#events+1]={tick=tick,kind="note",key=a,vel=b,len=len}
    elseif a>=128 and b>=128 then events[#events+1]={tick=tick,kind="cc",ctrl=b%128,value=a%128}
    elseif a>=128 then events[#events+1]={tick=tick,kind="pc",program=a%128}
    else error("unsupported MusyX region command",0) end
  end
  return events
end

local function parseSong(sequence)
  assert(type(sequence)=="string" and #sequence>=24,"song sequence is truncated")
  local trackOff=u32be(sequence,1);local regionIndexOff=u32be(sequence,5);local channelOff=u32be(sequence,9);local tempoOff=u32be(sequence,13);local initialTempo=u32be(sequence,17)
  assert(trackOff>0 and regionIndexOff>trackOff and channelOff>regionIndexOff,"song header offsets are invalid")
  local tracks,channels={},{}
  for i=0,63 do tracks[i+1]=u32be(sequence,trackOff+1+i*4);channels[i+1]=sequence:byte(channelOff+1+i) or 255 end
  local firstRegion=u32be(sequence,regionIndexOff+1);local regionCount=math.floor((firstRegion-regionIndexOff)/4)
  assert(regionCount>0 and regionCount<65536,"song region index is invalid")
  local regions={}
  for i=0,regionCount-1 do
    local ptr=u32be(sequence,regionIndexOff+1+i*4);regions[i+1]=parseRegion(sequence,ptr+1)
  end
  local events={};local loopTick=nil;local endTick=0
  for ti=1,64 do
    local start=tracks[ti];local channel=channels[ti]
    if start and start>0 and start<regionIndexOff and channel~=255 then
      local bound=regionIndexOff
      for j=ti+1,64 do local n=tracks[j];if n and n>start and n<bound then bound=n end end
      local pos=start
      while pos+12<=bound do
        local regionStart=u32be(sequence,pos+1);local dataIndex=s16be(sequence,pos+9);local loopIndex=u16be(sequence,pos+11);pos=pos+12
        if dataIndex==-1 then if regionStart>endTick then endTick=regionStart end;break
        elseif dataIndex==-2 then
          if regionStart>endTick then endTick=regionStart end
          local target=start+loopIndex*12
          if target+12<=bound then
            local t=u32be(sequence,target+1);if not loopTick or t<loopTick then loopTick=t end
          end
          break
        elseif dataIndex>=0 and dataIndex<regionCount then
          local reg=regions[dataIndex+1]
          for _,e in ipairs(reg) do
            local c={tick=regionStart+e.tick,track=ti,channel=channel,kind=e.kind}
            if e.kind=="note" then c.key=e.key;c.vel=e.vel;c.len=e.len
            elseif e.kind=="cc" then c.ctrl=e.ctrl;c.value=e.value else c.program=e.program end
            events[#events+1]=c
          end
        end
      end
    end
  end
  assert(loopTick and loopTick>0,"song sequence has no usable loop point")
  local dedup={[0]=initialTempo}
  if tempoOff and tempoOff>0 then
    local p=tempoOff+1
    while p+7<=#sequence do
      local tick=u32be(sequence,p);if tick==4294967295 then break end
      dedup[tick]=u32be(sequence,p+4);p=p+8
    end
  end
  local tempos={};for tick,bpm in pairs(dedup)do tempos[#tempos+1]={tick=tick,bpm=bpm}end
  table.sort(tempos,function(a,b)return a.tick<b.tick end)
  local priority={pc=0,cc=1,note=2}
  table.sort(events,function(a,b)
    if a.tick~=b.tick then return a.tick<b.tick end
    local pa,pb=priority[a.kind],priority[b.kind];if pa~=pb then return pa<pb end
    return a.track<b.track
  end)
  return {events=events,tempos=tempos,loopTick=loopTick,endTick=endTick}
end

local function tickToSeconds(tick,tempos)
  local sec,last,bpm=0,0,tempos[1].bpm
  for i=2,#tempos do
    local t=tempos[i]
    if tick<=t.tick then break end
    sec=sec+(t.tick-last)*60/(bpm*TICKS_PER_BEAT);last=t.tick;bpm=t.bpm
  end
  return sec+(tick-last)*60/(bpm*TICKS_PER_BEAT)
end
local function tickToFrame(tick,tempos)return math.floor(tickToSeconds(tick,tempos)*RATE+0.5)end

local function resolveObject(db,object,key,transpose,volume,pan,depth,out)
  transpose=transpose or 0;volume=volume or 127;pan=pan or 64;depth=depth or 0;out=out or {}
  if depth>8 or object==65535 then return out end
  if object<16384 then out[#out+1]={macro=object,key=key+transpose,volume=volume,pan=pan};return out end
  if object<32768 then
    local map=db.keymaps[object];local e=map and map[key+1]
    if e then resolveObject(db,e.object,key,transpose+e.transpose,volume,e.pan~=0 and e.pan or pan,depth+1,out)end
    return out
  end
  local layer=db.layers[object]
  if layer then
    for _,e in ipairs(layer)do
      if key>=e.lo and key<=e.hi then resolveObject(db,e.object,key,transpose+e.transpose,math.floor(volume*e.volume/127),e.pan~=64 and e.pan or pan,depth+1,out)end
    end
  end
  return out
end

local function recipeFor(db,macroId,key,velocity)
  local commands=db.macros[macroId];if not commands then return nil end
  local r={sample=nil,adsr=nil,pitch=key*100,initVel=velocity,curVel=velocity,fadeMs=0,sampleOffset=0}
  for _,c in ipairs(commands)do
    local op=c[1]
    if op==0x0c then r.adsr=cmdU16(c,2)
    elseif op==0x0d then
      local original=c[6]~=0;local base=original and r.initVel or r.curVel
      r.curVel=clamp(math.floor(base*c[2]/127)+s8(c[3]),0,127)
    elseif op==0x10 then
      r.sample=cmdU16(c,2);local mode=s8(c[4]);local off=cmdU32(c,5)
      if mode==1 then off=math.floor(off*(127-r.curVel)/127) elseif mode==2 then off=math.floor(off*r.curVel/127) end
      r.sampleOffset=off
    elseif op==0x14 then
      local msSwitch=c[6]~=0;local t=cmdU16(c,7);r.fadeMs=msSwitch and t or math.floor(t*1000/1000)
    elseif op==0x18 then r.pitch=r.pitch+s8(c[2])*100+s8(c[3])
    elseif op==0x19 then r.pitch=c[2]*100+s8(c[3])
    elseif op==0x04 or op==0x07 then break end
  end
  return r.sample and r or nil
end

local function adsrFor(db,id)
  local d=id and db.tables[id]
  if d and #d==8 then return u16le(d,1),u16le(d,3),u16le(d,5),u16le(d,7) end
  return 0,0,4096,30
end

local function decodeDsp(meta,sdir,samp,source)
  assert(meta,source..": sample metadata missing")
  assert(meta.format==0 or meta.format==1,source..": unsupported sample format "..tostring(meta.format))
  local frames=math.ceil(meta.count/14)
  assert(meta.offset+frames*8<=#samp,source..": sample data exceeds SAMP")
  assert(meta.adpcm>0 and meta.adpcm+39<=#sdir,source..": DSP coefficient block exceeds SDIR")
  local coefs={}
  for i=0,7 do coefs[i+1]={s16be(sdir,meta.adpcm+9+i*4),s16be(sdir,meta.adpcm+11+i*4)}end
  local prev2=s16be(sdir,meta.adpcm+5);local prev1=s16be(sdir,meta.adpcm+7)
  local out=ffi.new("int16_t[?]",meta.count);local done=0
  while done<meta.count do
    local p=meta.offset+1+math.floor(done/14)*8;local header=samp:byte(p);local predictor=math.floor(header/16);local exponent=header%16
    assert(predictor<=7,source..": invalid DSP predictor")
    local c1,c2=coefs[predictor+1][1],coefs[predictor+1][2];local n=math.min(14,meta.count-done)
    for i=0,n-1 do
      local packed=samp:byte(p+1+math.floor(i/2));local nib=(i%2==0) and math.floor(packed/16) or packed%16;if nib>=8 then nib=nib-16 end
      local sample=math.floor((nib*2^exponent*2048+1024+c1*prev1+c2*prev2)/2048)
      sample=clamp(sample,-32768,32767);prev2,prev1=prev1,sample;out[done+i]=sample
    end
    done=done+n
  end
  return out
end

local function collectVoices(song,project,db,sampleMeta,setupId,source)
  local setup=project.setups[setupId];assert(setup,source..": MIDI setup "..tostring(setupId).." missing")
  local state={};for ch=0,15 do local s=setup[ch+1];state[ch+1]={program=s.program,volume=s.volume,pan=s.pan,expression=127,reverb=s.reverb,chorus=s.chorus}end
  local voices={};local unresolved=0;local maxFrame=tickToFrame(song.endTick,song.tempos)
  for _,e in ipairs(song.events)do
    local ch=e.channel;local st=state[ch+1]
    if st then
      if e.kind=="pc" then
        local pages=ch==9 and project.drum or project.normal;if pages[e.program] then st.program=e.program end
      elseif e.kind=="cc" then
        if e.ctrl==7 then st.volume=e.value elseif e.ctrl==10 then st.pan=e.value elseif e.ctrl==11 then st.expression=e.value elseif e.ctrl==91 then st.reverb=e.value elseif e.ctrl==93 then st.chorus=e.value end
      elseif e.kind=="note" then
        local pages=ch==9 and project.drum or project.normal;local page=pages[st.program]
        if page then
          local resolved=resolveObject(db,page.object,e.key)
          if #resolved==0 then unresolved=unresolved+1 end
          local startFrame=tickToFrame(e.tick,song.tempos);local offFrame=tickToFrame(e.tick+e.len,song.tempos)
          for _,obj in ipairs(resolved)do
            local rec=recipeFor(db,obj.macro,obj.key,e.vel)
            if rec then
              local meta=sampleMeta[rec.sample]
              if not meta then error(source..": sample "..tostring(rec.sample).." missing from SDIR",0)end
              local attack,decay,sustain,release=adsrFor(db,rec.adsr);if rec.fadeMs>attack then attack=rec.fadeMs end
              local amp=(rec.curVel/127)*(st.volume/127)*(st.expression/127)*(obj.volume/127)
              local pan=clamp(st.pan+(obj.pan-64),0,127)
              local endFrame=offFrame+math.floor(release*RATE/1000+0.5);if endFrame>maxFrame then maxFrame=endFrame end
              voices[#voices+1]={startFrame=startFrame,offFrame=offFrame,sample=rec.sample,pitch=rec.pitch,amp=amp,pan=pan,attack=attack,decay=decay,sustain=sustain,release=release,sampleOffset=rec.sampleOffset}
            end
          end
        else unresolved=unresolved+1 end
      end
    end
  end
  assert(#voices>0,source..": no playable MusyX voices resolved")
  assert(unresolved==0,source..": "..tostring(unresolved).." note/object resolutions were incomplete")
  return voices,maxFrame
end

local function envelopeBase(v,frame)
  local a=math.floor(v.attack*RATE/1000+0.5);local d=math.floor(v.decay*RATE/1000+0.5);local sustain=clamp(v.sustain/4096,0,1)
  if a>0 and frame<a then return frame/a end
  if d>0 and frame<a+d then return 1-(1-sustain)*(frame-a)/d end
  return sustain
end
local function mixSong(song,voices,db,sampleMeta,sdir,samp,source,maxFrame)
  local total=math.max(maxFrame+1,tickToFrame(song.endTick,song.tempos)+1)
  assert(total>1 and total<RATE*15*60,source..": rendered duration is unreasonable")
  local left=ffi.new("float[?]",total);local right=ffi.new("float[?]",total)
  local decoded={};local peak=0
  for vi,v in ipairs(voices)do
    local meta=sampleMeta[v.sample];local pcm=decoded[v.sample]
    if not pcm then pcm=decodeDsp(meta,sdir,samp,source.." / sample "..tostring(v.sample));decoded[v.sample]=pcm end
    local step=(meta.rate*2^((v.pitch-meta.base*100)/1200))/RATE
    if step>0 then
      local releaseFrames=math.floor(v.release*RATE/1000+0.5);local localOff=math.max(0,v.offFrame-v.startFrame);local n=localOff+releaseFrames+1
      local looped=meta.loopLen>0 and meta.loopStart~=4294967295 and meta.loopStart<meta.count
      local loopStart=meta.loopStart;local loopEnd=math.min(meta.count,meta.loopStart+meta.loopLen);local loopLen=math.max(1,loopEnd-loopStart)
      if not looped then n=math.min(n,math.floor((meta.count-1-math.min(meta.count-1,v.sampleOffset))/step)+1) end
      local theta=(v.pan/127)*math.pi/2;local lg=math.cos(theta)*v.amp;local rg=math.sin(theta)*v.amp
      local offLevel=envelopeBase(v,localOff)
      for i=0,n-1 do
        local dst=v.startFrame+i;if dst>=total then break end
        local pos=v.sampleOffset+i*step
        if looped and pos>=loopEnd then pos=loopStart+((pos-loopStart)%loopLen) end
        if pos>=meta.count-1 then if not looped then break else pos=math.min(pos,meta.count-1)end end
        local i0=math.floor(pos);local frac=pos-i0;local i1=math.min(i0+1,meta.count-1)
        local sample=(tonumber(pcm[i0])*(1-frac)+tonumber(pcm[i1])*frac)/32768
        local env
        if i>=localOff then
          if releaseFrames>0 then env=offLevel*math.max(0,1-(i-localOff)/releaseFrames) else env=0 end
        else env=envelopeBase(v,i) end
        local l=left[dst]+sample*env*lg;local r=right[dst]+sample*env*rg;left[dst]=l;right[dst]=r
      end
    end
    if vi%250==0 or vi==#voices then send({kind="progress",source=source,label=("mixing voices %d/%d"):format(vi,#voices)}) end
  end
  for i=0,total-1 do local a=math.abs(tonumber(left[i]));local b=math.abs(tonumber(right[i]));if a>peak then peak=a end;if b>peak then peak=b end end
  local gain=peak>0.95 and 0.95/peak or 1
  return left,right,total,gain
end

local function pcmRange(left,right,startFrame,count,gain)
  local parts={};local block=4096
  for base=0,count-1,block do
    local n=math.min(block,count-base);local out=ffi.new("int16_t[?]",n*2)
    for i=0,n-1 do
      local idx=startFrame+base+i;local l=clamp(tonumber(left[idx])*gain,-1,1);local r=clamp(tonumber(right[idx])*gain,-1,1)
      out[i*2]=l>=0 and math.floor(l*32767+0.5) or math.ceil(l*32768-0.5)
      out[i*2+1]=r>=0 and math.floor(r*32767+0.5) or math.ceil(r*32768-0.5)
    end
    parts[#parts+1]=ffi.string(out,n*4)
  end
  return table.concat(parts)
end

local function renderTheme(songSpec,project,db,sampleMeta,sdir,samp)
  local source=tostring(songSpec.source or "MusyX song");currentSource=source;send({kind="source",source=source.." / in-process 32 kHz"})
  local song=parseSong(assert(songSpec.sequence,source..": sequence bytes missing"))
  local loopFrame=tickToFrame(song.loopTick,song.tempos)
  if tonumber(songSpec.loopFrame) then
    local expected=math.floor(tonumber(songSpec.loopFrame)*RATE/48000+0.5)
    assert(math.abs(loopFrame-expected)<=1,("%s: derived loop frame %d does not match validated reference %d"):format(source,loopFrame,expected))
  end
  local voices,maxFrame=collectVoices(song,project,db,sampleMeta,assert(tonumber(songSpec.setup),source..": setup missing"),source)
  send({kind="progress",source=source,label=("parsed %d voices / loop frame %d"):format(#voices,loopFrame)})
  local left,right,total,gain=mixSong(song,voices,db,sampleMeta,sdir,samp,source,maxFrame)
  assert(loopFrame>0 and loopFrame<total,("%s: loop frame %d outside %d-frame render"):format(source,loopFrame,total))
  local intro=wav16(pcmRange(left,right,0,loopFrame,gain),RATE,2)
  local loop=wav16(pcmRange(left,right,loopFrame,total-loopFrame,gain),RATE,2)
  left=nil;right=nil;collectgarbage("collect")
  return intro,loop,loopFrame,#voices,total
end

local function decodeTransition(sdir,samp,sampleId,source)
  local meta=parseSampleDirectory(sdir)[sampleId];assert(meta,source..": sample id missing")
  local pcm=decodeDsp(meta,sdir,samp,source);return wav16(ffi.string(pcm,meta.count*2),meta.rate,1)
end

local function run()
  assert(type(payload)=="table","audio worker payload missing")
  assert(type(payload.music)=="table","music source group missing")
  assert(RATE>=22050 and RATE<=48000,"unsupported in-process output rate")
  local proj=assert(payload.music.proj,"music PROJ bytes missing");local pool=assert(payload.music.pool,"music POOL bytes missing")
  local sdir=assert(payload.music.sdir,"music SDIR bytes missing");local samp=assert(payload.music.samp,"music SAMP bytes missing")
  local project=parseProject(proj);local db=parsePool(pool);local sampleMeta=parseSampleDirectory(sdir)
  send({kind="progress",source="MusyX source group",label=("in-process tables ready / %d Hz"):format(RATE)})
  for _,song in ipairs(payload.songs or {})do
    local intro,loop,loopFrame,voiceCount,total=renderTheme(song,project,db,sampleMeta,sdir,samp)
    local source=tostring(song.source or "song")
    send({kind="asset",source=("%s intro / %d voices"):format(source,voiceCount),path=song.introPath,bytes=intro})
    send({kind="asset",source=("%s loop / %d frames"):format(source,total-loopFrame),path=song.loopPath,bytes=loop})
    collectgarbage("collect")
  end
  local transition=assert(payload.transition,"transition source missing");local source=tostring(transition.source or "battle transition")
  currentSource=source;send({kind="source",source=source.." / in-process DSP"})
  local wav=decodeTransition(assert(transition.sdir,source..": SDIR missing"),assert(transition.samp,source..": SAMP missing"),assert(tonumber(transition.sampleId),source..": sample id missing"),source)
  send({kind="asset",source=source,path=transition.outputPath,bytes=wav});send({kind="done"})
end

local ok,err=xpcall(run,debug.traceback)
if not ok then send({kind="error",source=currentSource,error=trimLog(err)})end
