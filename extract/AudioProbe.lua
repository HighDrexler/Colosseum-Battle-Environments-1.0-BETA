local V=...
local FSYS=V.FSYS
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

local function now()
  return love and love.timer and love.timer.getTime and love.timer.getTime() or os.clock()
end

local function render(mod,payload,progress,generated)
  assert(love and love.thread and type(love.thread.newThread)=="function",
    'audio renderer: CBE needs its existing "compute" permission')
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
  if osName=="" or osName==nil then return true,"unknown" end
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
return A
