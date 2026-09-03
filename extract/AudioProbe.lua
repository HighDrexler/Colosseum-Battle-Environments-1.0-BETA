local V=...
local FSYS=V.FSYS
local PortableMusyX=V.PortableMusyX
local A={}
local serial=0

-- loopFrame is the sequence header's loopStartTick integrated through its
-- tempo table at 48 kHz. It is format metadata, not copied audio.
local THEMES={
  {source="battle5_song",setup=51,loopFrame=7181,intro="assets/audio/themes/normal_battle_intro.wav",loop="assets/audio/themes/normal_battle_loop.wav"},
  {source="battle8_song",setup=4,loopFrame=493908,intro="assets/audio/themes/first_battle_intro.wav",loop="assets/audio/themes/first_battle_loop.wav"},
  {source="battle7_song",setup=72,loopFrame=322765,intro="assets/audio/themes/cipher_peon_intro.wav",loop="assets/audio/themes/cipher_peon_loop.wav"},
  {source="mirrorbo_song",setup=65,loopFrame=9575,intro="assets/audio/themes/miror_b_intro.wav",loop="assets/audio/themes/miror_b_loop.wav"},
  {source="battle9plus_song",setup=49,loopFrame=2311138,intro="assets/audio/themes/cipher_admin_intro.wav",loop="assets/audio/themes/cipher_admin_loop.wav"},
  {source="miraclebo_song",setup=44,loopFrame=9575,intro="assets/audio/themes/mirakle_b_intro.wav",loop="assets/audio/themes/mirakle_b_loop.wav"},
  {source="battle2_song",setup=24,loopFrame=573696,intro="assets/audio/themes/semifinal_intro.wav",loop="assets/audio/themes/semifinal_loop.wav"},
  {source="battle6_song",setup=76,loopFrame=391138,intro="assets/audio/themes/final_battle_intro.wav",loop="assets/audio/themes/final_battle_loop.wav"},
  {source="tool_battle1_song",setup=20,loopFrame=468525,intro="assets/audio/themes/link_1_intro.wav",loop="assets/audio/themes/link_1_loop.wav"},
  {source="tool_battle2_song",setup=21,loopFrame=482190,intro="assets/audio/themes/link_2_intro.wav",loop="assets/audio/themes/link_2_loop.wav"},
  {source="tool_battle3_song",setup=22,loopFrame=444292,intro="assets/audio/themes/link_3_intro.wav",loop="assets/audio/themes/link_3_loop.wav"},
}


local ONE_SHOTS={
  -- bgm_archive.fsys index/setup 9 is the retail Colosseum Snag-success jingle.
  -- Render it from the user's own disc exactly like the existing battle themes.
  {source="me_snatch_song",setup=9,output="assets/audio/capture/me_snatch.wav"},
}

local function memberMap(archive)
  local out={}
  for _,entry in ipairs(archive:list()) do out[entry.name:lower()]=entry end
  return out
end

local function requiredMember(archive,map,name,archiveName)
  local entry=map[name:lower()]
  assert(entry,("audio source %s/%s: member missing"):format(archiveName,name))
  local ok,data=pcall(archive.extract,archive,entry,{maxOutput=64*1024*1024})
  assert(ok,("audio source %s/%s: %s"):format(archiveName,name,tostring(data)))
  assert(type(data)=="string" and #data>0,("audio source %s/%s: empty decoded member"):format(archiveName,name))
  return data
end

local function directFile(disc,name)
  local file=disc:file(name)
  assert(file,("audio source disc/%s: file missing"):format(name))
  local ok,data=pcall(disc.readFile,disc,file)
  assert(ok,("audio source disc/%s: %s"):format(name,tostring(data)))
  assert(type(data)=="string" and #data>0,("audio source disc/%s: empty file"):format(name))
  return data
end

local function writeAsset(mod,path,bytes,generated)
  assert(type(bytes)=="string" and #bytes>=44,("audio output %s: renderer returned no WAV data"):format(path))
  assert(bytes:sub(1,4)=="RIFF" and bytes:sub(9,12)=="WAVE",("audio output %s: renderer returned an invalid WAV"):format(path))
  local ok,err=mod.cache:write(path,bytes)
  assert(ok,("audio output %s: cache write failed: %s"):format(path,tostring(err or "unknown error")))
  generated[#generated+1]=path
end


local PORTABLE_MARKER="cbe-audio-portable=core2\nsource=GC6E01\ntransition=dsp92\ndecoder=fresh-history\n"
local PORTABLE_FULL_MARKER="cbe-audio-portable=5\nsource=GC6E01\nassets=24\nrate=48000\nrenderer=lua-musyx-battle-fidelity-v4-source-mix-48k\n"
local PORTABLE_RATE=48000
local PORTABLE_FULL_PATH=".cbe-audio-portable-v5.complete"
-- Android cache backends have proven less reliable with tiny hidden marker
-- files than with normal generated/build entries. Keep a redundant non-hidden
-- marker and migration journal so a process restart can never turn a valid or
-- partially completed soundtrack into a destructive full recache.
local PORTABLE_FULL_FALLBACK_PATH="build/audio_portable_v5.complete"
local PORTABLE_PENDING_PATH=".cbe-audio-portable-v5.pending"
local PORTABLE_MIGRATION_PATH="build/audio_portable_v5.migrating"
local LEGACY_V2_PATH=".cbe-audio-portable-v2.complete"
local LEGACY_V3_PATH=".cbe-audio-portable-v3.complete"
local LEGACY_V4_PATH=".cbe-audio-portable-v4.complete"
local LEGACY_V4_FALLBACK_PATH="build/audio_portable_v4.complete"

-- The battle-transition cue is a raw GameCube DSP-ADPCM sample, not a MusyX
-- sequence. Decode it directly in portable Lua so Android can generate real
-- Colosseum audio without cmd.exe/amuserender. Keep this path bounded: read
-- only the sample's ADPCM frame range from snd_se_battle.samp.
local function u16be(s,o)local a,b=s:byte(o,o+1);assert(b,"truncated u16be");return a*256+b end
local function u32be(s,o)local a,b,c,d=s:byte(o,o+3);assert(d,"truncated u32be");return a*16777216+b*65536+c*256+d end
local function s16be(s,o)local v=u16be(s,o);return v>=32768 and v-65536 or v end
local function le16(v)v=v%65536;return string.char(v%256,math.floor(v/256)%256)end
local function le32(v)v=v%4294967296;return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256)end
local function wav16(raw,rate,channels)
  local n=#raw
  return "RIFF"..le32(36+n).."WAVEfmt "..le32(16)..le16(1)..le16(channels)..le32(rate)
    ..le32(rate*channels*2)..le16(channels*2)..le16(16).."data"..le32(n)..raw
end
local function dspEntry(sdir,sampleId,source)
  for o=1,#sdir-31,32 do
    local id=u16be(sdir,o);if id==65535 then break end
    if id==sampleId then
      local e={offset=u32be(sdir,o+4),rate=u16be(sdir,o+14),rawCount=u32be(sdir,o+16),adpcm=u32be(sdir,o+28)}
      local format=math.floor(e.rawCount/16777216);e.count=e.rawCount%16777216
      assert(format==0 or format==1,source..": sample is not GameCube DSP ADPCM (format "..format..")")
      assert(e.adpcm>0 and e.adpcm+39<=#sdir,source..": DSP coefficient block exceeds SDIR")
      return e
    end
  end
  error(source..": sample id "..sampleId.." missing from SDIR",0)
end
local function decodeDspSlice(sdir,samp,e,source)
  local expected=math.ceil(e.count/14)*8
  assert(#samp>=expected,source..": sample data is truncated")
  local coefs={}
  for i=0,7 do coefs[i]={s16be(sdir,e.adpcm+9+i*4),s16be(sdir,e.adpcm+11+i*4)} end
  -- Fresh DSP playback starts with predictor history (0,0). The SDIR history
  -- belongs to loop turnover state and must not color the first transient.
  local prev2,prev1=0,0
  local parts,bytes,done={},{},0
  while done<e.count do
    local frame=1+math.floor(done/14)*8
    local header=samp:byte(frame);assert(header,source..": missing DSP frame")
    local predictor=math.floor(header/16);local exponent=header%16
    assert(predictor<=7,source..": invalid DSP predictor "..predictor)
    local c1,c2=coefs[predictor][1],coefs[predictor][2]
    local n=math.min(14,e.count-done)
    for i=0,n-1 do
      local packed=samp:byte(frame+1+math.floor(i/2));assert(packed,source..": truncated DSP nibble")
      local nibble=(i%2==0) and math.floor(packed/16) or packed%16;if nibble>=8 then nibble=nibble-16 end
      local sample=math.floor((nibble*2^exponent*2048+1024+c1*prev1+c2*prev2)/2048)
      if sample>32767 then sample=32767 elseif sample< -32768 then sample=-32768 end
      prev2,prev1=prev1,sample;local v=sample%65536
      bytes[#bytes+1]=string.char(v%256,math.floor(v/256))
      if #bytes>=4096 then parts[#parts+1]=table.concat(bytes);bytes={} end
    end
    done=done+n
  end
  if #bytes>0 then parts[#parts+1]=table.concat(bytes) end
  return wav16(table.concat(parts),e.rate,1)
end
local function cacheRead(mod,path)
  if not (mod and mod.cache and type(mod.cache.read)=="function") then return nil end
  local ok,v=pcall(mod.cache.read,mod.cache,path);return ok and type(v)=="string" and v or nil
end
local function cacheWrite(mod,path,data,generated)
  local ok,a,b=pcall(mod.cache.write,mod.cache,path,data)
  assert(ok and a~=false and a~=nil,"audio cache write failed: "..path.." / "..tostring(b or a))
  if generated then generated[#generated+1]=path end
end
local function cacheInfo(mod,path)
  if not (mod and mod.cache and type(mod.cache.info)=="function") then return nil end
  local ok,v=pcall(mod.cache.info,mod.cache,path);return ok and type(v)=="table" and v or nil
end
local function cacheDelete(mod,path)
  if not (mod and mod.cache and type(mod.cache.delete)=="function") then return false end
  local ok,v=pcall(mod.cache.delete,mod.cache,path);return ok and v~=false
end
local PORTABLE_ASSETS={}
for _,theme in ipairs(THEMES) do PORTABLE_ASSETS[#PORTABLE_ASSETS+1]=theme.intro;PORTABLE_ASSETS[#PORTABLE_ASSETS+1]=theme.loop end
for _,shot in ipairs(ONE_SHOTS) do PORTABLE_ASSETS[#PORTABLE_ASSETS+1]=shot.output end
PORTABLE_ASSETS[#PORTABLE_ASSETS+1]="assets/audio/colosseum_battle_transition.wav"
local function portableAssetReady(mod,path)
  local info=cacheInfo(mod,path)
  return info~=nil and (tonumber(info.size) or 0)>=44
end
local function portableAssetsReady(mod)
  for _,path in ipairs(PORTABLE_ASSETS) do if not portableAssetReady(mod,path) then return false end end
  return true
end
local function generatedManifestMentions(mod,path)
  local raw=cacheRead(mod,"build/generated_paths.lua")
  return type(raw)=="string" and raw:find(path,1,true)~=nil
end
local function writePortableFullMarkers(mod,generated)
  cacheWrite(mod,PORTABLE_FULL_PATH,PORTABLE_FULL_MARKER,generated)
  cacheWrite(mod,PORTABLE_FULL_FALLBACK_PATH,PORTABLE_FULL_MARKER,generated)
end
function A.portableCoreReady(mod)
  local marker=cacheRead(mod,".cbe-audio-portable-v1.complete")
  local wav=cacheRead(mod,"assets/audio/colosseum_battle_transition.wav")
  return marker==PORTABLE_MARKER and type(wav)=="string" and #wav>=44 and wav:sub(1,4)=="RIFF" and wav:sub(9,12)=="WAVE"
end
function A.runPortableCore(mod,disc,progress,generated)
  progress=progress or function()end
  if A.portableCoreReady(mod) then
    progress("AUDIO PORTABLE 1/1 / cached Colosseum battle transition",1,1)
    return {ready=true,complete=1,total=1,renderer="portable Lua DSP-ADPCM",cached=true}
  end
  progress("AUDIO PORTABLE 0/1 / locating battle DSP sample",0,1)
  local commonFile=assert(disc:file("common.fsys"),"audio source common.fsys: archive missing")
  local common=FSYS.open(disc,commonFile);local members=memberMap(common)
  local source="common.fsys/snd_se_battle_sdir + disc/snd_se_battle.samp / sample 92 (SFX 0x00CC)"
  local sdir=requiredMember(common,members,"snd_se_battle_sdir","common.fsys")
  local e=dspEntry(sdir,92,source)
  local sampFile=assert(disc:file("snd_se_battle.samp"),"audio source disc/snd_se_battle.samp: file missing")
  local byteCount=math.ceil(e.count/14)*8
  assert(e.offset+byteCount<=sampFile.size,source..": DSP sample exceeds SAMP")
  local samp=disc:readFile(sampFile,e.offset,byteCount)
  local wav=decodeDspSlice(sdir,samp,e,source)
  writeAsset(mod,"assets/audio/colosseum_battle_transition.wav",wav,generated)
  cacheWrite(mod,".cbe-audio-portable-v1.complete",PORTABLE_MARKER,generated)
  progress("AUDIO PORTABLE 1/1 / Colosseum battle transition cached",1,1)
  return {ready=true,complete=1,total=1,renderer="portable Lua DSP-ADPCM",sampleBytes=byteCount}
end

function A.portableFullReady(mod)
  if not A.portableCoreReady(mod) or not portableAssetsReady(mod) then return false end
  local primary=cacheRead(mod,PORTABLE_FULL_PATH)
  local fallback=cacheRead(mod,PORTABLE_FULL_FALLBACK_PATH)
  if primary==PORTABLE_FULL_MARKER or fallback==PORTABLE_FULL_MARKER then
    -- Self-heal whichever redundant completion marker disappeared.
    if primary~=PORTABLE_FULL_MARKER then pcall(cacheWrite,mod,PORTABLE_FULL_PATH,PORTABLE_FULL_MARKER,nil) end
    if fallback~=PORTABLE_FULL_MARKER then pcall(cacheWrite,mod,PORTABLE_FULL_FALLBACK_PATH,PORTABLE_FULL_MARKER,nil) end
    return true
  end
  -- If the process died after the final WAV was committed but before the final
  -- marker write, promote the completed v5 migration instead of reopening and
  -- resynthesizing the disc. Never infer v5 from an older portable cache alone.
  local migrating=cacheRead(mod,PORTABLE_MIGRATION_PATH)==PORTABLE_FULL_MARKER
  local pending=cacheRead(mod,PORTABLE_PENDING_PATH)==PORTABLE_FULL_MARKER
  local manifestV5=generatedManifestMentions(mod,PORTABLE_FULL_PATH) or generatedManifestMentions(mod,PORTABLE_FULL_FALLBACK_PATH)
  if migrating or pending or manifestV5 then
    pcall(writePortableFullMarkers,mod,nil)
    cacheDelete(mod,PORTABLE_PENDING_PATH);cacheDelete(mod,PORTABLE_MIGRATION_PATH)
    return true
  end
  return false
end

local function portablePayload(mod,disc)
  local commonFile=assert(disc:file("common.fsys"),"audio source common.fsys: archive missing")
  local bgmFile=assert(disc:file("bgm_archive.fsys"),"audio source bgm_archive.fsys: archive missing")
  local common=FSYS.open(disc,commonFile);local bgm=FSYS.open(disc,bgmFile)
  local commonMembers,bgmMembers=memberMap(common),memberMap(bgm)
  local songs={}
  for _,theme in ipairs(THEMES) do
    if not portableAssetReady(mod,theme.intro) or not portableAssetReady(mod,theme.loop) then
      songs[#songs+1]={source="bgm_archive.fsys/"..theme.source,setup=theme.setup,loopFrame=theme.loopFrame,
        introPath=theme.intro,loopPath=theme.loop,sequence=requiredMember(bgm,bgmMembers,theme.source,"bgm_archive.fsys")}
    end
  end
  local oneShots={}
  for _,shot in ipairs(ONE_SHOTS) do
    if not portableAssetReady(mod,shot.output) then
      oneShots[#oneShots+1]={source="bgm_archive.fsys/"..shot.source,setup=shot.setup,outputPath=shot.output,
        sequence=requiredMember(bgm,bgmMembers,shot.source,"bgm_archive.fsys")}
    end
  end
  return {sampleRate=PORTABLE_RATE,songs=songs,oneShots=oneShots,music={
    proj=requiredMember(common,commonMembers,"snd_music_proj","common.fsys"),
    pool=requiredMember(common,commonMembers,"snd_music_pool","common.fsys"),
    sdir=requiredMember(common,commonMembers,"snd_music_sdir","common.fsys"),
    samp=directFile(disc,"snd_music.samp"),
  }}
end

function A.runPortableFull(mod,disc,progress,generated)
  progress=progress or function()end
  assert(PortableMusyX and type(PortableMusyX.renderAll)=="function","portable MusyX renderer module unavailable")
  if A.portableFullReady(mod) then
    progress("AUDIO PORTABLE 24/24 / cached Colosseum soundtrack stability v3",24,24)
    return {ready=true,complete=24,total=24,renderer="portable Lua MusyX battle fidelity v4 / source pan+volume / 48 kHz",cached=true,rate=PORTABLE_RATE}
  end

  -- v4 is a one-time audio-only migration. It trims the generated loop WAV at
  -- the real MusyX loop-end tick instead of baking a release/reverb tail into
  -- every repetition. Most importantly, migration is transactional: once a v4
  -- journal exists, a restart only resumes missing WAVs and NEVER deletes valid
  -- partial work. This directly fixes Android relaunches falling back to 1/24.
  local pendingV5=cacheRead(mod,PORTABLE_PENDING_PATH)==PORTABLE_FULL_MARKER
  local migratingV5=cacheRead(mod,PORTABLE_MIGRATION_PATH)==PORTABLE_FULL_MARKER
  if not pendingV5 and not migratingV5 then
    local legacyV2=cacheRead(mod,LEGACY_V2_PATH)~=nil
    local legacyV3=cacheRead(mod,LEGACY_V3_PATH)~=nil or generatedManifestMentions(mod,LEGACY_V3_PATH)
    local legacyV4=cacheRead(mod,LEGACY_V4_PATH)~=nil or cacheRead(mod,LEGACY_V4_FALLBACK_PATH)~=nil
      or generatedManifestMentions(mod,LEGACY_V4_PATH) or generatedManifestMentions(mod,LEGACY_V4_FALLBACK_PATH)
    if legacyV2 or legacyV3 or legacyV4 then
      -- Audio-only invalidation: portable v5 changes the actual PCM renderer.
      -- Arena/Pokemon/trainer/MoveFX caches remain untouched.
      for _,theme in ipairs(THEMES) do cacheDelete(mod,theme.intro);cacheDelete(mod,theme.loop) end
      for _,shot in ipairs(ONE_SHOTS) do cacheDelete(mod,shot.output) end
      cacheDelete(mod,LEGACY_V2_PATH);cacheDelete(mod,LEGACY_V3_PATH)
      progress("AUDIO PORTABLE / one-time v5 48 kHz source-render migration",0,24)
    end
    cacheWrite(mod,PORTABLE_PENDING_PATH,PORTABLE_FULL_MARKER,generated)
    cacheWrite(mod,PORTABLE_MIGRATION_PATH,PORTABLE_FULL_MARKER,generated)
  elseif not pendingV5 then
    -- Hidden pending marker vanished but the non-hidden journal survived.
    cacheWrite(mod,PORTABLE_PENDING_PATH,PORTABLE_FULL_MARKER,generated)
  elseif not migratingV5 then
    -- Likewise repair the durable journal from the pending marker.
    cacheWrite(mod,PORTABLE_MIGRATION_PATH,PORTABLE_FULL_MARKER,generated)
  end

  local transition=A.runPortableCore(mod,disc,progress,generated)
  assert(transition and transition.ready,"portable battle transition extraction failed")
  local ready={};local complete=0
  for _,path in ipairs(PORTABLE_ASSETS) do ready[path]=portableAssetReady(mod,path);if ready[path] then complete=complete+1 end end
  progress(("AUDIO PORTABLE %d/24 / locating MusyX battle sources"):format(complete),complete,24)
  local payload=portablePayload(mod,disc)
  local expectedEmitted=#payload.songs*2+#payload.oneShots
  local result=PortableMusyX.renderAll(payload,function(message)
    if message.kind=="source" then
      progress(("AUDIO PORTABLE %d/24 / %s"):format(complete,tostring(message.source or "MusyX source")),complete,24)
    elseif message.kind=="heartbeat" then
      local frame,total=tonumber(message.frame) or 0,tonumber(message.total) or 0
      local pct=total>0 and math.floor(frame*100/total) or 0
      progress(("AUDIO PORTABLE %d/24 / %s / %d%%"):format(complete,tostring(message.source or "rendering"),pct),complete,24)
    elseif message.kind=="asset" then
      local path=tostring(message.path)
      if not ready[path] then
        writeAsset(mod,path,message.bytes,generated);ready[path]=true;complete=complete+1
      end
      progress(("AUDIO PORTABLE %d/24 / %s"):format(complete,tostring(message.source or path)),complete,24)
    end
  end)
  assert(result and tonumber(result.complete)==expectedEmitted,("portable MusyX renderer completed with %s/%d requested sequence assets"):format(tostring(result and result.complete),expectedEmitted))
  assert(complete==24,("portable audio cache completed with %d/24 assets"):format(complete))
  writePortableFullMarkers(mod,generated)
  cacheDelete(mod,PORTABLE_PENDING_PATH);cacheDelete(mod,PORTABLE_MIGRATION_PATH)
  cacheDelete(mod,LEGACY_V2_PATH);cacheDelete(mod,LEGACY_V3_PATH);cacheDelete(mod,LEGACY_V4_PATH);cacheDelete(mod,LEGACY_V4_FALLBACK_PATH)
  assert(A.portableFullReady(mod),"portable audio completion marker written but generated soundtrack cache failed validation")
  progress("AUDIO PORTABLE 24/24 / 48 kHz source-render cache verified",24,24)
  return {ready=true,complete=24,total=24,renderer=result.renderer or "portable Lua MusyX battle fidelity v4 / source pan+volume / 48 kHz",rate=PORTABLE_RATE}
end

local function now()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

local function render(mod,payload,progress,generated)
  assert(love and love.thread and type(love.thread.newThread)=="function",
    'audio renderer: host sandbox does not expose love.thread to this mod')
  serial=serial+1
  local token=("%d_%d"):format(serial,math.floor(now()*1000000)%1000000000)
  local inputName="cbe_audio_import_in_"..token
  local outputName="cbe_audio_import_out_"..token
  local input=love.thread.getChannel(inputName)
  local output=love.thread.getChannel(outputName)
  input:clear();output:clear()
  local workerPath=tostring(mod.path).."/extract/AudioWorker.lua"
  local okThread,thread=pcall(love.thread.newThread,workerPath)
  assert(okThread and thread,"audio renderer worker "..workerPath..": "..tostring(thread))
  input:push(payload)
  local okStart,startErr=pcall(thread.start,thread,inputName,outputName)
  assert(okStart,"audio renderer worker start: "..tostring(startErr))

  local complete=0
  local active="preparing renderer"
  local activeAt=now()
  local lastHeartbeat=-1
  while true do
    local message=output:pop()
    if message then
      if message.kind=="source" then
        active=tostring(message.source or "audio source")
        activeAt=now()
        progress(("AUDIO %d/24 / %s"):format(complete,active),complete,24)
      elseif message.kind=="asset" then
        writeAsset(mod,tostring(message.path),message.bytes,generated)
        complete=complete+1
        progress(("AUDIO %d/24 / %s"):format(complete,tostring(message.source or message.path)),complete,24)
      elseif message.kind=="error" then
        error(("audio source %s: %s"):format(tostring(message.source or active),tostring(message.error or "conversion failed")),0)
      elseif message.kind=="done" then
        assert(complete==24,("audio renderer completed with %d/24 cached assets"):format(complete))
        input:clear();output:clear()
        return complete
      end
    end
    local workerErr=thread.getError and thread:getError()
    if workerErr then error(("audio source %s: worker crashed: %s"):format(active,tostring(workerErr)),0) end
    local t=now()
    if t-lastHeartbeat>=0.20 then
      lastHeartbeat=t
      progress(("AUDIO %d/24 / %s / %ds"):format(complete,active,math.floor(t-activeAt)),complete,24)
    end
    if love.timer and love.timer.sleep then love.timer.sleep(0.04) end
  end
end


function A.platformSupported()
  local osName=nil
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok then osName=tostring(v or "") end
  end
  -- The bundled Amuse renderer is a Windows executable. Android/iOS/macOS/Linux
  -- must never be sent through cmd.exe; visuals remain fully usable without it.
  if osName=="" or osName==nil then return false,"unknown" end
  return osName=="Windows",osName
end
function A.run(mod,disc,progress,generated)
  progress=progress or function()end
  local supported,osName=A.platformSupported()
  assert(supported,("Colosseum music conversion is unavailable on %s; visual CBE runtime remains supported"):format(tostring(osName or "this platform")))
  progress("AUDIO 0/24 / locating MusyX sources",0,24)
  local commonFile=assert(disc:file("common.fsys"),"audio source common.fsys: archive missing")
  local bgmFile=assert(disc:file("bgm_archive.fsys"),"audio source bgm_archive.fsys: archive missing")
  local common=FSYS.open(disc,commonFile)
  local bgm=FSYS.open(disc,bgmFile)
  local commonMembers,bgmMembers=memberMap(common),memberMap(bgm)

  local renderer=mod:read("third_party/amuse/amuserender.exe")
  assert(type(renderer)=="string" and #renderer>0,
    "audio renderer third_party/amuse/amuserender.exe: bundled converter missing")

  local songs={}
  for _,theme in ipairs(THEMES) do
    songs[#songs+1]={
      source="bgm_archive.fsys/"..theme.source,
      setup=theme.setup,loopFrame=theme.loopFrame,
      introPath=theme.intro,loopPath=theme.loop,
      sequence=requiredMember(bgm,bgmMembers,theme.source,"bgm_archive.fsys"),
    }
  end

  local oneShots={}
  for _,shot in ipairs(ONE_SHOTS) do
    oneShots[#oneShots+1]={source="bgm_archive.fsys/"..shot.source,setup=shot.setup,outputPath=shot.output,
      sequence=requiredMember(bgm,bgmMembers,shot.source,"bgm_archive.fsys")}
  end

  local payload={
    renderer=renderer,sampleRate=48000,songs=songs,oneShots=oneShots,
    music={
      proj=requiredMember(common,commonMembers,"snd_music_proj","common.fsys"),
      pool=requiredMember(common,commonMembers,"snd_music_pool","common.fsys"),
      sdir=requiredMember(common,commonMembers,"snd_music_sdir","common.fsys"),
      samp=directFile(disc,"snd_music.samp"),
    },
    transition={
      source="common.fsys/snd_se_battle_sdir + disc/snd_se_battle.samp / sample 92 (SFX 0x00CC)",
      outputPath="assets/audio/colosseum_battle_transition.wav",sampleId=92,
      sdir=requiredMember(common,commonMembers,"snd_se_battle_sdir","common.fsys"),
      samp=directFile(disc,"snd_se_battle.samp"),
    },
  }
  local complete=render(mod,payload,progress,generated)
  progress("AUDIO 24/24 / generated cache verified",complete,24)
  return {ready=true,complete=complete,total=24,renderer="CBE import worker / Amuse"}
end

A.themes=THEMES
A.portableMarker=PORTABLE_MARKER
A.portableFullMarker=PORTABLE_FULL_MARKER
A.portableAssets=PORTABLE_ASSETS
return A
