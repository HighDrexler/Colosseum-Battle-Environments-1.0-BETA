-- CBE audio conversion worker. All game data arrives over a channel after
-- being read through mod.imports; only generated WAV bytes go back.
require("love.filesystem")
require("love.thread")
local ffi=require("ffi")

local inputName,outputName=...
local input=love.thread.getChannel(inputName)
local output=love.thread.getChannel(outputName)
local payload=input:demand()

local function send(value) output:push(value) end
local function u16le(s,o)local a,b=s:byte(o,o+1);return a+b*256 end
local function u32le(s,o)local a,b,c,d=s:byte(o,o+3);return a+b*256+c*65536+d*16777216 end
local function u16be(s,o)local a,b=s:byte(o,o+1);return a*256+b end
local function u32be(s,o)local a,b,c,d=s:byte(o,o+3);return a*16777216+b*65536+c*256+d end
local function s16be(s,o)local v=u16be(s,o);return v>=32768 and v-65536 or v end
local function le16(v)v=v%65536;return string.char(v%256,math.floor(v/256)%256)end
local function le32(v)v=v%4294967296;return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end

local function wav16(raw,rate,channels)
  local dataBytes=#raw
  return "RIFF"..le32(36+dataBytes).."WAVEfmt "..le32(16)..le16(1)..le16(channels)
    ..le32(rate)..le32(rate*channels*2)..le16(channels*2)..le16(16)
    .."data"..le32(dataBytes)..raw
end

local function parseFloatWav(wav,source)
  assert(type(wav)=="string" and #wav>=44 and wav:sub(1,4)=="RIFF" and wav:sub(9,12)=="WAVE",
    source..": converter output is not RIFF/WAVE")
  local pos,fmt,dataPos,dataLen=13
  while pos+7<=#wav do
    local id=wav:sub(pos,pos+3)
    local size=u32le(wav,pos+4)
    local body=pos+8
    assert(body+size-1<=#wav,source..": truncated WAV chunk "..id)
    if id=="fmt " then fmt={tag=u16le(wav,body),channels=u16le(wav,body+2),rate=u32le(wav,body+4),bits=u16le(wav,body+14)}
    elseif id=="data" then dataPos,dataLen=body,size;break end
    pos=body+size+(size%2)
  end
  assert(fmt and dataPos,source..": converter WAV is missing fmt/data")
  assert(fmt.tag==3 and fmt.bits==32,source..": converter WAV is not 32-bit IEEE float")
  assert(fmt.channels==2,source..": converter WAV is not stereo")
  assert(dataLen%(fmt.channels*4)==0,source..": converter WAV has a partial frame")
  return fmt,dataPos,dataLen
end

local function floatRangeToPcm(wav,dataPos,dataLen,startFrame,frameCount,channels)
  local raw=wav:sub(dataPos,dataPos+dataLen-1)
  local src=ffi.cast("const float*",raw)
  local blockFrames=4096
  local parts={}
  for base=0,frameCount-1,blockFrames do
    local n=math.min(blockFrames,frameCount-base)
    local out=ffi.new("int16_t[?]",n*channels)
    for i=0,n*channels-1 do
      local v=tonumber(src[(startFrame+base)*channels+i])
      if v~=v then v=0 elseif v>1 then v=1 elseif v< -1 then v=-1 end
      if v>=0 then out[i]=math.floor(v*32767+0.5) else out[i]=math.ceil(v*32768-0.5) end
    end
    parts[#parts+1]=ffi.string(out,n*channels*2)
  end
  return table.concat(parts)
end

local function splitSongWav(wav,loopFrame,source)
  local fmt,dataPos,dataLen=parseFloatWav(wav,source)
  local frames=dataLen/(fmt.channels*4)
  assert(loopFrame>0 and loopFrame<frames,
    ("%s: loop frame %d is outside rendered length %d"):format(source,loopFrame,frames))
  local introRaw=floatRangeToPcm(wav,dataPos,dataLen,0,loopFrame,fmt.channels)
  local loopRaw=floatRangeToPcm(wav,dataPos,dataLen,loopFrame,frames-loopFrame,fmt.channels)
  return wav16(introRaw,fmt.rate,fmt.channels),wav16(loopRaw,fmt.rate,fmt.channels)
end

local function decodeDspSample(sdir,samp,sampleId,source)
  local entry
  for o=1,#sdir-31,32 do
    local id=u16be(sdir,o)
    if id==65535 then break end
    if id==sampleId then
      entry={offset=u32be(sdir,o+4),rate=u16be(sdir,o+14),rawCount=u32be(sdir,o+16),adpcm=u32be(sdir,o+28)}
      break
    end
  end
  assert(entry,source..": sample id "..sampleId.." missing from SDIR")
  local format=math.floor(entry.rawCount/16777216)
  local count=entry.rawCount%16777216
  assert(format==0 or format==1,source..": sample is not GameCube DSP ADPCM (format "..format..")")
  assert(entry.offset+math.ceil(count/14)*8<=#samp,source..": sample data exceeds SAMP")
  assert(entry.adpcm>0 and entry.adpcm+39<=#sdir,source..": DSP coefficient block exceeds SDIR")
  local coefs={}
  for i=0,7 do coefs[i]={s16be(sdir,entry.adpcm+9+i*4),s16be(sdir,entry.adpcm+11+i*4)} end
  local prev2=s16be(sdir,entry.adpcm+5)
  local prev1=s16be(sdir,entry.adpcm+7)
  local parts,bytes={},{}
  local done=0
  while done<count do
    local frame=entry.offset+1+math.floor(done/14)*8
    local header=samp:byte(frame)
    local predictor=math.floor(header/16)
    local exponent=header%16
    assert(predictor<=7,source..": invalid DSP predictor "..predictor)
    local c1,c2=coefs[predictor][1],coefs[predictor][2]
    local n=math.min(14,count-done)
    for i=0,n-1 do
      local packed=samp:byte(frame+1+math.floor(i/2))
      local nibble=(i%2==0) and math.floor(packed/16) or packed%16
      if nibble>=8 then nibble=nibble-16 end
      local sample=math.floor((nibble*2^exponent*2048+1024+c1*prev1+c2*prev2)/2048)
      if sample>32767 then sample=32767 elseif sample< -32768 then sample=-32768 end
      prev2,prev1=prev1,sample
      local v=sample%65536
      bytes[#bytes+1]=string.char(v%256,math.floor(v/256))
      if #bytes>=4096 then parts[#parts+1]=table.concat(bytes);bytes={} end
    end
    done=done+n
  end
  if #bytes>0 then parts[#parts+1]=table.concat(bytes) end
  return wav16(table.concat(parts),entry.rate,1)
end

local function trimLog(text)
  text=tostring(text or ""):gsub("\r","\n"):gsub("\n+"," / ")
  if #text>1200 then text=text:sub(1,1200).."..." end
  return text
end

local workRel="cbe_audio_import_"..tostring(outputName):gsub("[^%w_]","_")
local root=love.filesystem.getSaveDirectory()
local sep=package.config:sub(1,1)
local workAbs=root..sep..workRel:gsub("/",sep)
local files={}
local currentSource="preparing audio source group"
local function put(name,bytes)
  local rel=workRel.."/"..name
  local ok,err=love.filesystem.write(rel,bytes)
  assert(ok,"temporary file "..name..": "..tostring(err))
  files[#files+1]=rel
  return workAbs..sep..name
end
local function clean()
  for i=#files,1,-1 do pcall(love.filesystem.remove,files[i]) end
  pcall(love.filesystem.remove,workRel)
end
local function quote(s)return '"'..tostring(s):gsub('"','""')..'"'end

local function executeRenderer(exe,proj,song,logPath,inputPath,cmdPath)
  local cmd=table.concat({"@echo off\r\ncd /d ",quote(workAbs),"\r\n",quote(exe)," ",quote(proj)," ",quote(song),
    " -r 48000 < ",quote(inputPath)," > ",quote(logPath)," 2>&1\r\nexit /b %errorlevel%\r\n"})
  local rel=workRel.."/render.cmd"
  local ok,err=love.filesystem.write(rel,cmd)
  assert(ok,"temporary command file: "..tostring(err))
  files[#files+1]=rel
  local a,b,c=os.execute('cmd.exe /d /s /c ""'..tostring(cmdPath):gsub('"','""')..'""')
  return a==0 or a==true and (c==nil or c==0),a,b,c
end

local function run()
  assert(type(payload)=="table","audio worker payload missing")
  assert(love.filesystem.createDirectory(workRel),"unable to create audio worker directory")
  local exe=put("amuserender.exe",assert(payload.renderer,"renderer bytes missing"))
  local proj=put("snd_music.proj",assert(payload.music.proj,"music PROJ bytes missing"))
  put("snd_music.pool",assert(payload.music.pool,"music POOL bytes missing"))
  put("snd_music.sdir",assert(payload.music.sdir,"music SDIR bytes missing"))
  put("snd_music.samp",assert(payload.music.samp,"music SAMP bytes missing"))
  local inputPath=put("setup.txt","")
  local logPath=put("render.log","")
  local cmdPath=workAbs..sep.."render.cmd"
  local outRel=workRel.."/snd_music-Song.wav"

  for index,song in ipairs(payload.songs or {}) do
    local source=tostring(song.source or ("song "..index))
    currentSource=source
    send({kind="source",source=source})
    local songRel=workRel.."/source.song"
    local sequence=assert(song.sequence,source..": sequence bytes missing")
    local okSong,errSong=love.filesystem.write(songRel,sequence)
    assert(okSong,source..": temporary sequence write: "..tostring(errSong));files[#files+1]=songRel
    love.filesystem.write(workRel.."/setup.txt",tostring(song.setup).."\r\n")
    love.filesystem.write(workRel.."/render.log","")
    love.filesystem.remove(outRel)
    local okExec,a,b,c=executeRenderer(exe,proj,workAbs..sep.."source.song",logPath,inputPath,cmdPath)
    if not okExec then
      local log=love.filesystem.read(workRel.."/render.log")
      error(("%s: amuserender exit (%s,%s,%s): %s"):format(source,tostring(a),tostring(b),tostring(c),trimLog(log)),0)
    end
    local wav,readErr=love.filesystem.read(outRel)
    assert(type(wav)=="string",source..": rendered WAV missing: "..tostring(readErr))
    local intro,loop=splitSongWav(wav,assert(tonumber(song.loopFrame),source..": loop frame missing"),source)
    send({kind="asset",source=source.." intro",path=song.introPath,bytes=intro})
    send({kind="asset",source=source.." loop",path=song.loopPath,bytes=loop})
    love.filesystem.remove(songRel);love.filesystem.remove(outRel)
  end

  for index,shot in ipairs(payload.oneShots or {}) do
    local source=tostring(shot.source or ("one-shot "..index))
    currentSource=source
    send({kind="source",source=source})
    local songRel=workRel.."/source.song"
    local sequence=assert(shot.sequence,source..": sequence bytes missing")
    local okSong,errSong=love.filesystem.write(songRel,sequence)
    assert(okSong,source..": temporary sequence write: "..tostring(errSong));files[#files+1]=songRel
    love.filesystem.write(workRel.."/setup.txt",tostring(shot.setup).."\r\n")
    love.filesystem.write(workRel.."/render.log","")
    love.filesystem.remove(outRel)
    local okExec,a,b,c=executeRenderer(exe,proj,workAbs..sep.."source.song",logPath,inputPath,cmdPath)
    if not okExec then
      local log=love.filesystem.read(workRel.."/render.log")
      error(("%s: amuserender exit (%s,%s,%s): %s"):format(source,tostring(a),tostring(b),tostring(c),trimLog(log)),0)
    end
    local wav,readErr=love.filesystem.read(outRel)
    assert(type(wav)=="string",source..": rendered WAV missing: "..tostring(readErr))
    -- Amuse renders 32-bit IEEE-float WAVs. Theme assets already convert that
    -- stream to portable PCM16 when they are split; one-shots must do the same.
    -- Caching me_snatch as raw float made support/backend behavior inconsistent
    -- and is the most likely reason the catch cue could sound clipped/wrong.
    local fmt,dataPos,dataLen=parseFloatWav(wav,source)
    local frames=dataLen/(fmt.channels*4)
    local raw=floatRangeToPcm(wav,dataPos,dataLen,0,frames,fmt.channels)
    local pcm=wav16(raw,fmt.rate,fmt.channels)
    send({kind="asset",source=source,path=assert(shot.outputPath,source..": output path missing"),bytes=pcm})
    love.filesystem.remove(songRel);love.filesystem.remove(outRel)
  end

  local transition=assert(payload.transition,"transition source missing")
  local source=tostring(transition.source or "battle transition")
  currentSource=source
  send({kind="source",source=source})
  local wav=decodeDspSample(assert(transition.sdir,source..": SDIR bytes missing"),
    assert(transition.samp,source..": SAMP bytes missing"),assert(tonumber(transition.sampleId),source..": sample id missing"),source)
  send({kind="asset",source=source,path=transition.outputPath,bytes=wav})
  clean()
  send({kind="done"})
end

local ok,err=xpcall(run,debug.traceback)
if not ok then
  clean()
  send({kind="error",source=currentSource,error=trimLog(err)})
end
