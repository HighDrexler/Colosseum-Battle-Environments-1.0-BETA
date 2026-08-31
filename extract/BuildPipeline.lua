local V=...
local Disc,FSYS=V.GameCubeDisc,V.FSYS
local ArenaBuilder,TrainerExtractor,TransitionBuilder,AudioProbe=V.ArenaBuilder,V.TrainerExtractor,V.TransitionBuilder,V.AudioProbe
local FormatProbe=V.FormatProbe
local CameraProbe=V.CameraProbe
local MoveFXExtractor=V.MoveFXExtractor
local B={cacheVersion=2,extractorRevision=12}
local EXPECTED_MARKER="cbe-runtime=2\nextractor=12\n"
local LEGACY_EXPECTED_MARKER="cbe-runtime=2\nextractor=11\n"
local VISUAL_CORE={
  "cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua",
  "cache/trainers/red/model_cache.lua","cache/trainers/leaf/model_cache.lua","cache/trainers/wes/model_cache.lua","cache/trainers/brendan/model_cache.lua","cache/trainers/may/model_cache.lua","cache/trainers/cooltrainer_m/model_cache.lua","cache/trainers/cooltrainer_f/model_cache.lua","cache/trainers/dakim/model_cache.lua","cache/trainers/nascour/model_cache.lua","cache/trainers/miror_b/model_cache.lua","cache/trainers/generic/index.lua",
  "cache/capture/index.lua",
  "assets/transition/wipe_ball00.rgba","assets/transition/wipe_ball01.rgba",
}
local LEGACY_VISUAL_CORE={}
for _,path in ipairs(VISUAL_CORE) do if path~="cache/capture/index.lua" then LEGACY_VISUAL_CORE[#LEGACY_VISUAL_CORE+1]=path end end
local AUDIO_MARKER="cbe-audio=3\nassets=24\nsource=GC6E01\n"
local TRAINER_IDENTITY_MARKER=[=[cbe-trainer-identity=11
red=people_archive.fsys/akami_m_b1.dat
leaf=people_archive.fsys/akami_f_b1.dat
wes=field_common.fsys/ken_b1.dat
brendan=people_archive.fsys/agb_m_b1.dat
may=people_archive.fsys/agb_f_b1.dat
cooltrainer_m=people_archive.fsys/traner_m_b1.dat
cooltrainer_f=people_archive.fsys/traner_f_b1.dat
dakim=people_archive.fsys/battleyama_b1.dat
nascour=people_archive.fsys/boss999_b1.dat
miror_b=people_archive.fsys/boss555_b1.dat
pose=native-hsd-scene-root;clip1-nonbind-base;coherent-clipfamilies-v6;source-hand-topology;exact-end-effector;procedural=residual-only
]=]
local ARENA_MARKER=[=[cbe-arena=6
water=GC6E01/M1_water_colo.fsys/M1_water_colo.dat/source-hsd-scene
orre=GC6E01/T1_ancient_colo.fsys/T1_ancient_colo.dat/source-hsd-scene
realgam=GC6E01/D4_casino_colo.fsys/D4_casino_colo.dat/source-hsd-scene
wildlands=grounded-solid-grass
routing=battle-start-binding-reset
vertex-contract=hsd-normal-not-tint
texture-wrap=source-gx
summit=GC6E01/D2_crater_colo.fsys/D2_crater_colo.dat/source-hsd-scene
mt-battle-material=exact-source-gx;neutral-backdrop;extended-depth
orre-distance=full-T1-scene;realgam-distance=full-D4-scene;extended-depth
]=]
local AUDIO_CORE={
  "assets/audio/themes/cipher_admin_intro.wav","assets/audio/themes/cipher_admin_loop.wav",
  "assets/audio/themes/cipher_peon_intro.wav","assets/audio/themes/cipher_peon_loop.wav",
  "assets/audio/themes/final_battle_intro.wav","assets/audio/themes/final_battle_loop.wav",
  "assets/audio/themes/first_battle_intro.wav","assets/audio/themes/first_battle_loop.wav",
  "assets/audio/themes/link_1_intro.wav","assets/audio/themes/link_1_loop.wav",
  "assets/audio/themes/link_2_intro.wav","assets/audio/themes/link_2_loop.wav",
  "assets/audio/themes/link_3_intro.wav","assets/audio/themes/link_3_loop.wav",
  "assets/audio/themes/mirakle_b_intro.wav","assets/audio/themes/mirakle_b_loop.wav",
  "assets/audio/themes/miror_b_intro.wav","assets/audio/themes/miror_b_loop.wav",
  "assets/audio/themes/normal_battle_intro.wav","assets/audio/themes/normal_battle_loop.wav",
  "assets/audio/themes/semifinal_intro.wav","assets/audio/themes/semifinal_loop.wav",
  "assets/audio/capture/me_snatch.wav",
  "assets/audio/colosseum_battle_transition.wav",
}
local function call(obj,name,...)
  if not obj or type(obj[name])~="function" then return nil,"unavailable" end
  local ok,a,b=pcall(obj[name],obj,...);if not ok then return nil,tostring(a) end;return a,b
end
local function exists(mod,path)local v=select(1,call(mod.cache,"info",path));return type(v)=="table" and (v.type==nil or v.type=="file")end
local function read(mod,path)local v=select(1,call(mod.cache,"read",path));return type(v)=="string" and v or nil end
local function write(mod,path,data,generated)
  local ok,err=call(mod.cache,"write",path,data);assert(ok,err or ("cache write failed: "..path));if generated then generated[#generated+1]=path end
end
local function del(mod,path)call(mod.cache,"delete",path)end
local function luaList(paths)local o={"return {\n"};for _,p in ipairs(paths)do o[#o+1]=string.format("%q,\n",p)end;o[#o+1]="}\n";return table.concat(o)end
local function stateText(s)
  local keys={"cache_version","extractor_revision","current_stage","message","disc_id","disc_region","source_size","fst_files","fsys_files","source_fingerprint","visual_ready","audio_ready","trainer_resolved","trainer_total","trainer_diagnostic","trainer_first_error","trainer_source_error"}
  local o={};for _,k in ipairs(keys)do if s[k]~=nil then o[#o+1]=k.."="..tostring(s[k]) end end;return table.concat(o,"\n").."\n"
end
local function cleanupPrevious(mod)
  local raw=read(mod,"build/generated_paths.lua");if not raw then return end
  -- `local ok,paths=chunk and pcall(chunk)` truncates to one value in Lua, so
  -- paths was always nil and this cleanup silently did nothing. Every rebuild
  -- left the previous run's generated files on disk.
  local chunk=load(raw,"@generated/build/generated_paths.lua")
  if not chunk then return end
  local ok,paths=pcall(chunk)
  if ok and type(paths)=="table" then for _,p in ipairs(paths)do del(mod,p)end end
end
local function stage(mod,id,generated)
  local p="build/stage_"..id..".complete";write(mod,p,EXPECTED_MARKER,generated)
end
local function pending(mod,id,text,generated)
  write(mod,"build/stage_"..id..".pending",tostring(text or "pending").."\n",generated)
end
local function baseVisualReady(mod)
  if read(mod,".cbe-visual-v2.complete")~=EXPECTED_MARKER then return false end
  for _,p in ipairs(VISUAL_CORE)do if not exists(mod,p)then return false end end
  return true
end
local function legacyBaseVisualReady(mod)
  if read(mod,".cbe-visual-v2.complete")~=LEGACY_EXPECTED_MARKER then return false end
  for _,p in ipairs(LEGACY_VISUAL_CORE)do if not exists(mod,p)then return false end end
  return true
end
local function trainerIdentityReady(mod)
  return read(mod,".cbe-trainer-identity-v11.complete")==TRAINER_IDENTITY_MARKER
end
local function arenaReady(mod)
  return read(mod,".cbe-arena-v6.complete")==ARENA_MARKER
end
local function visualReady(mod)
  return baseVisualReady(mod) and trainerIdentityReady(mod) and arenaReady(mod)
end
local function audioReady(mod)
  if read(mod,".cbe-audio-v1.complete")~=AUDIO_MARKER then return false end
  for _,p in ipairs(AUDIO_CORE)do if not exists(mod,p)then return false end end
  return true
end
local function finishManifest(mod,generated)
  local paths={};for _,p in ipairs(generated)do paths[#paths+1]=p end;paths[#paths+1]="build/generated_paths.lua"
  write(mod,"build/generated_paths.lua",luaList(paths),nil)
end
local function previousGenerated(mod)
  local raw=read(mod,"build/generated_paths.lua")
  local chunk=raw and load(raw,"@generated/build/generated_paths.lua")
  -- Same one-value `and` truncation as above: this always returned {}, so an
  -- incremental stage rebuild dropped every previously generated path from the
  -- manifest instead of carrying it forward.
  if not chunk then return {} end
  local ok,paths=pcall(chunk)
  if not ok or type(paths)~="table" then return {} end
  local out,seen={},{}
  for _,path in ipairs(paths)do
    if path~="build/generated_paths.lua" and not seen[path] then
      seen[path]=true;out[#out+1]=path
    end
  end
  return out
end
local arenasOnly,trainersOnly
local function audioPlatformSupported()
  if AudioProbe and type(AudioProbe.platformSupported)=="function" then
    local ok,supported,osName=pcall(AudioProbe.platformSupported)
    if ok then return supported~=false,osName end
  end
  return true,"unknown"
end

local function audioOnly(mod,progress)
  local generated=previousGenerated(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="audio",message="Resuming generated audio cache",disc_id="GC6E01",
    disc_region="USA",visual_ready=1,audio_ready=0}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/audio_warning.txt");del(mod,"build/stage_audio.pending")
  local audioSupported,osName=audioPlatformSupported()
  if not audioSupported then
    state.current_stage="ready_visual";state.message=("Runtime ready; optional Colosseum audio unavailable on %s (visual cache is complete)"):format(tostring(osName or "this platform"))
    del(mod,"build/audio_warning.txt");del(mod,".cbe-audio-v1.complete")
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated);save();finishManifest(mod,generated)
    return {state="READY / AUDIO UNAVAILABLE",visualReady=true,audioReady=false,audioUnavailable=true,message=state.message}
  end
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    local audio=AudioProbe.run(mod,disc,progress,generated)
    assert(audio and audio.ready,("audio cache incomplete (%s/%s)")
      :format(tostring(audio and audio.complete or 0),tostring(audio and audio.total or 24)))
    stage(mod,"audio",generated)
    state.audio_ready=1;state.current_stage="ready";state.message="Runtime ready; generated audio cache 24/24"
    del(mod,"build/audio_warning.txt")
    write(mod,".cbe-audio-v1.complete",AUDIO_MARKER,generated)
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    save();finishManifest(mod,generated)
    return {state="READY",visualReady=true,audioReady=true,message=state.message}
  end)
  if ok then return result end
  local msg=tostring(result)
  state.current_stage="ready_visual"
  state.message="Runtime ready; optional Colosseum audio unavailable: "..msg
  del(mod,"build/error.txt")
  pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
  pcall(function()write(mod,"build/audio_warning.txt",msg.."\n",nil)end)
  pending(mod,"audio",msg,nil)
  del(mod,".cbe-audio-v1.complete");write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,nil)
  pcall(function()finishManifest(mod,generated)end)
  return {state="READY / AUDIO OPTIONAL",visualReady=true,audioReady=false,audioUnavailable=true,message=state.message}
end

-- Upgrade an existing visual cache in place. All trainer models are rewritten
-- from exact battle-member identities; arenas/transitions remain reusable and
-- audio is reused only when its current marker is valid. This path also compiles the native
-- snatch_* ball bank here, so an existing 1.5.61 install does NOT rebuild all
-- five arenas merely to gain source hand anchors and authentic ball props.
trainersOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="trainers",message="Rebuilding exact trainer battle models in native HSD non-bind battle stance",disc_id="GC6E01",
    disc_region="USA",visual_ready=0,audio_ready=hadAudio and 1 or 0,trainer_resolved=0,trainer_total=10,trainer_diagnostic="build/trainer_scan.txt"}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/stage_trainers.pending");del(mod,".cbe-runtime-v2.complete")
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    local trainer=TrainerExtractor.run(mod,disc,progress,generated,{directOnly=true}) or {}
    state.trainer_resolved=tonumber(trainer.resolvedCount) or 0
    state.trainer_total=tonumber(trainer.total) or 10
    state.trainer_first_error=trainer.firstError;state.trainer_source_error=trainer.firstSourceError
    assert(trainer.ready==true,("exact trainer cache incomplete (%d/%d): %s")
      :format(state.trainer_resolved,state.trainer_total,tostring(trainer.firstError or trainer.firstSourceError or trainer.diagnostic)))
    stage(mod,"trainers",generated)
    write(mod,".cbe-trainer-identity-v11.complete",TRAINER_IDENTITY_MARKER,generated)
    for i=1,10 do del(mod,(".cbe-trainer-identity-v%d.complete"):format(i)) end
    state.current_stage="capture";state.message="Compiling native Colosseum capture balls from snatch_* source";save()
    assert(MoveFXExtractor and type(MoveFXExtractor.extractCaptureAssets)=="function","capture source extractor unavailable")
    local captureResult=MoveFXExtractor.extractCaptureAssets(mod,disc,progress,generated)
    assert(captureResult and captureResult.ready,"native capture source cache incomplete")
    stage(mod,"capture",generated)
    for _,path in ipairs(VISUAL_CORE) do assert(exists(mod,path),"generated visual runtime missing: "..path) end
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=1
    if hadAudio then
      state.current_stage="ready";state.message="Runtime ready; source-hand trainer cache + native capture-ball bank rebuilt; generated audio cache reused"
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    else
      state.current_stage="audio";state.message="Source-hand trainer cache + native capture-ball bank rebuilt; generated audio cache pending"
    end
    save();finishManifest(mod,generated)
    return {state=hadAudio and "READY" or "VISUAL READY / AUDIO PENDING",visualReady=true,audioReady=hadAudio,
      trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
  end)
  if ok then
    if not arenaReady(mod) then return arenasOnly(mod,progress) end
    if not hadAudio then return audioOnly(mod,progress) end
    return result
  end
  local msg=tostring(result)
  state.current_stage="trainer_identity_failed";state.message=msg
  pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
  pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
  pending(mod,"trainers",msg,nil)
  del(mod,".cbe-trainer-identity-v11.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="TRAINER CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,
    trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,
    trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg}
end

-- Arena-only migration: rebuild Orre and Realgam from their complete T1/D4
-- source HSD scenes while preserving Water/Wildlands/Mt. Battle and all trainer,
-- transition and audio caches. This is intentionally independent from the
-- global extractor revision.
arenasOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local hadTrainers=trainerIdentityReady(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="arenas",message="Rebuilding Orre + Realgam full-distance source HSD scenes",disc_id="GC6E01",disc_region="USA",
    visual_ready=0,audio_ready=hadAudio and 1 or 0,trainer_resolved=hadTrainers and 10 or 0,trainer_total=10}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/stage_arenas.pending");del(mod,".cbe-runtime-v2.complete");del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete");del(mod,".cbe-arena-v4.complete");del(mod,".cbe-arena-v5.complete");del(mod,".cbe-arena-v6.complete")
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    if type(ArenaBuilder.repair)=="function" then ArenaBuilder.repair(mod,disc,progress,generated)
    else ArenaBuilder.run(mod,disc,progress,generated) end
    stage(mod,"arenas",generated)
    write(mod,".cbe-arena-v6.complete",ARENA_MARKER,generated);del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete");del(mod,".cbe-arena-v4.complete");del(mod,".cbe-arena-v5.complete")
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=hadTrainers and 1 or 0
    if hadTrainers and hadAudio then
      state.current_stage="ready";state.message="Runtime ready; Orre + Realgam full-distance source HSD rebuilt, other arena/trainer/audio caches reused"
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    elseif hadTrainers then
      state.current_stage="audio";state.message="Orre + Realgam full-distance source HSD rebuilt; generated audio cache pending"
    else
      state.current_stage="trainers";state.message="Orre + Realgam full-distance source HSD rebuilt; exact trainer cache pending"
    end
    save();finishManifest(mod,generated)
    return {state=(hadTrainers and hadAudio) and "READY" or (hadTrainers and "VISUAL READY / AUDIO PENDING" or "ARENAS READY / TRAINERS PENDING"),
      visualReady=hadTrainers,audioReady=hadAudio,message=state.message}
  end)
  if ok then
    if not hadTrainers then return trainersOnly(mod,progress) end
    if not hadAudio then return audioOnly(mod,progress) end
    return result
  end
  local msg=tostring(result)
  state.current_stage="arena_repair_failed";state.message=msg
  pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
  pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
    pending(mod,"arenas",msg,nil);del(mod,".cbe-arena-v6.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="ARENA CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,message=msg}
end

-- Structural probe for the two source formats CBE still cannot read: WZX move
-- effects and CAM camera cuts. It writes a report, never a parser.
--
-- This MUST run ahead of the cache-completeness short-circuits below. An
-- existing complete installation returns READY from B.run without executing a
-- single stage, so a probe wired into the stage list would never run on exactly
-- the installs most likely to already be set up -- which is what happened on the
-- first 1.5.0 build. Guarded by its own output file so it runs once, and any
-- failure is written INTO that file so there is always something to report.
function B.ensureFormatProbe(mod,progress,force)
  if not (FormatProbe and type(FormatProbe.run)=="function") then return false,"probe unavailable" end
  -- Each report is guarded INDEPENDENTLY. Gating both on one condition meant a
  -- camera-probe failure left its report missing forever, so the whole block
  -- re-ran and re-opened the disc on every single launch.
  local wantFormat=force or not exists(mod,"build/format_probe.txt")
  local wantCamera=force or not exists(mod,"build/camera_probe.txt")
  if not (wantFormat or wantCamera) then return true,"already present" end
  progress=progress or function()end

  local okDisc,disc=pcall(Disc.open,mod)
  if not okDisc then
    local msg="format probe could not open the source disc: "..tostring(disc)
    if wantFormat then pcall(function()write(mod,"build/format_probe.txt",msg.."\n",nil)end) end
    if wantCamera then pcall(function()write(mod,"build/camera_probe.txt",msg.."\n",nil)end) end
    return false,msg
  end

  local failures={}
  -- Separate pcalls: a WZX failure must not cost us the camera report, and a
  -- camera failure must not cost us the WZX report. Each writes its own reason
  -- into its own file so there is always something to send back.
  if wantFormat then
    local ok,err=pcall(FormatProbe.run,mod,disc,progress,nil)
    if not ok then
      failures[#failures+1]="format: "..tostring(err)
      pcall(function()write(mod,"build/format_probe.txt","format probe failed: "..tostring(err).."\n",nil)end)
    end
  end
  if wantCamera then
    if CameraProbe and type(CameraProbe.run)=="function" then
      local ok,err=pcall(CameraProbe.run,mod,disc,progress,nil)
      if not ok then
        failures[#failures+1]="camera: "..tostring(err)
        pcall(function()write(mod,"build/camera_probe.txt","camera probe failed: "..tostring(err).."\n",nil)end)
      end
    else
      pcall(function()write(mod,"build/camera_probe.txt","camera probe module unavailable\n",nil)end)
    end
  end
  if #failures>0 then return false,table.concat(failures,"; ") end
  return true,"written"
end

function B.run(mod,progress)
  assert(mod and mod.imports and mod.cache,"Gen1Recomp mod.imports/mod.cache API unavailable")
  progress=progress or function()end
  pcall(B.ensureFormatProbe,mod,progress,false)
  -- Incremental migration: keep expensive arena/transition caches and rebuild
  -- only stale trainer topology/native capture data; audio repairs separately
  -- when its marker changes (1.5.65 bumps it for PCM16 me_snatch).
  if legacyBaseVisualReady(mod) and arenaReady(mod) then
    return trainersOnly(mod,progress)
  end
  if baseVisualReady(mod) and trainerIdentityReady(mod) and not arenaReady(mod) then
    return arenasOnly(mod,progress)
  end
  if baseVisualReady(mod) and not trainerIdentityReady(mod) then
    return trainersOnly(mod,progress)
  end
  if visualReady(mod) then
    if audioReady(mod) then
      return {state="READY",visualReady=true,audioReady=true,message="Persistent generated runtime already present; audio cache reused."}
    end
    return audioOnly(mod,progress)
  end

  cleanupPrevious(mod)
  for _,p in ipairs({".cbe-runtime-v2.complete",".cbe-visual-v2.complete",".cbe-audio-v1.complete",".cbe-trainer-identity-v1.complete",".cbe-trainer-identity-v2.complete",".cbe-trainer-identity-v3.complete",".cbe-trainer-identity-v4.complete",".cbe-trainer-identity-v5.complete",".cbe-trainer-identity-v6.complete",".cbe-trainer-identity-v7.complete",".cbe-trainer-identity-v8.complete",".cbe-trainer-identity-v9.complete",".cbe-trainer-identity-v10.complete",".cbe-trainer-identity-v11.complete",".cbe-arena-v2.complete",".cbe-arena-v3.complete",".cbe-arena-v4.complete",".cbe-arena-v5.complete",".cbe-arena-v6.complete","build/error.txt","build/audio_warning.txt","build/stage_trainers.pending","build/stage_audio.pending"})do del(mod,p)end
  local generated={}
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,current_stage="disc",message="Opening validated GC6E01 source",disc_id="GC6E01",disc_region="USA",visual_ready=0,audio_ready=0,trainer_resolved=0,trainer_total=10,trainer_diagnostic="build/trainer_scan.txt"}
  local function saveState()write(mod,"build/state.txt",stateText(state),generated)end
  local function update(label,current,total)progress(label,current,total)end
  local ok,result=pcall(function()
    update("DISC / FST",0,8)
    local disc=Disc.open(mod)
    state.source_size=disc.info.size;state.fst_files=#disc.files;state.source_fingerprint=("GC6E01:%d:%d:%d"):format(disc.info.size,disc.fstOffset,disc.fstSize)
    write(mod,"build/disc_index.lua",Disc.serializeIndex(disc),generated)
    state.message="GameCube FST indexed";saveState();stage(mod,"disc",generated)

    state.current_stage="fsys";state.message="Validating Colosseum FSYS archives";saveState();update("FSYS VALIDATION",1,8)
    local fsysCount=0;for _,f in ipairs(disc.files)do if f.path:lower():match("%.fsys$")then fsysCount=fsysCount+1 end end
    state.fsys_files=fsysCount
    assert(fsysCount>1000,("unexpected FSYS inventory (%d)"):format(fsysCount))
    local people=assert(disc:file("people_archive.fsys"),"people_archive.fsys missing")
    local parc=FSYS.open(disc,people);assert(#parc:list()>20,"people_archive.fsys did not parse")
    write(mod,"build/fsys.lua",string.format("return {count=%d,peopleMembers=%d}\n",fsysCount,#parc:list()),generated)
    state.message="FSYS transport validated";saveState();stage(mod,"fsys",generated)

    state.current_stage="arenas";state.message="Generating CBE arena runtime";saveState();update("ARENAS",2,8)
    ArenaBuilder.run(mod,disc,function(label,c,t)update(label,c,t)end,generated);stage(mod,"arenas",generated);write(mod,".cbe-arena-v6.complete",ARENA_MARKER,generated)

    state.current_stage="trainers";state.message="Extracting trainer HSD models, native poses, and GX textures";saveState();update("TRAINERS",3,8)
    local trainer=TrainerExtractor.run(mod,disc,function(label,c,t)update(label,c,t)end,generated) or {}
    state.trainer_resolved=tonumber(trainer.resolvedCount) or 0;state.trainer_total=tonumber(trainer.total) or 10;state.trainer_first_error=trainer.firstError;state.trainer_source_error=trainer.firstSourceError
    local trainerReady=trainer.ready==true
    if trainerReady then stage(mod,"trainers",generated);write(mod,".cbe-trainer-identity-v11.complete",TRAINER_IDENTITY_MARKER,generated);for i=1,10 do del(mod,(".cbe-trainer-identity-v%d.complete"):format(i)) end;state.message="Trainer source cache complete"
    else pending(mod,"trainers",("resolved %d/%d; see %s"):format(state.trainer_resolved,state.trainer_total,state.trainer_diagnostic),generated);state.message=("Trainer cache partial (%d/%d); diagnostics recorded"):format(state.trainer_resolved,state.trainer_total) end
    saveState()

    state.current_stage="capture";state.message="Extracting native Colosseum ball models and source capture clips";saveState();update("CAPTURE SOURCE",4,8)
    assert(MoveFXExtractor and type(MoveFXExtractor.extractCaptureAssets)=="function","capture source extractor unavailable")
    local capture=MoveFXExtractor.extractCaptureAssets(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(capture and capture.ready,(capture and capture.message) or "native capture source cache incomplete")
    stage(mod,"capture",generated)

    state.current_stage="transition";state.message="Generating battle transition masks";saveState();update("TRANSITION",5,8)
    TransitionBuilder.run(mod,disc,function(label,c,t)update(label,c,t)end,generated);stage(mod,"transition",generated)

    -- A partial trainer cache is a visual failure and must be repaired before
    -- optional music work. Never let an audio converter error hide the actual
    -- visual/trainer diagnostic.
    if not trainerReady then
      state.visual_ready=0;state.current_stage="partial_trainers";state.message=("Visual cache completed through arenas/transition; trainer HSD unresolved %d/%d. See %s"):format(state.trainer_total-state.trainer_resolved,state.trainer_total,state.trainer_diagnostic)
      saveState();finishManifest(mod,generated);update("CACHE PARTIAL / TRAINERS PENDING",6,8)
      return {state="CACHE PARTIAL / TRAINERS PENDING",visualReady=false,audioReady=audioReady(mod),files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message}
    end

    -- Visual runtime is the product boundary. Mark it READY before touching the
    -- optional platform-specific music converter so an audio failure can never
    -- withhold arenas, Pokemon, trainers, MoveFX, transitions or menus.
    state.current_stage="verify";state.message="Verifying generated visual runtime";saveState();update("VERIFY VISUAL",6,8)
    for _,p in ipairs(VISUAL_CORE)do assert(exists(mod,p),"generated visual runtime missing: "..p)end
    stage(mod,"verify",generated)
    state.visual_ready=1
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    saveState();finishManifest(mod,generated)

    local audioSupported,osName=audioPlatformSupported()
    if not audioSupported then
      state.current_stage="ready_visual";state.audio_ready=0
      state.message=("Runtime ready; optional Colosseum audio unavailable on %s"):format(tostring(osName or "this platform"))
      del(mod,"build/audio_warning.txt");del(mod,".cbe-audio-v1.complete")
      saveState();finishManifest(mod,generated);update("RUNTIME READY / AUDIO UNAVAILABLE",8,8)
      return {state="READY / AUDIO UNAVAILABLE",visualReady=true,audioReady=false,audioUnavailable=true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
    end

    state.current_stage="audio";state.message="Indexing optional MusyX source archives";saveState();update("OPTIONAL AUDIO SOURCE",7,8)
    local audio=AudioProbe.run(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(audio and audio.ready,("audio cache incomplete (%s/%s)")
      :format(tostring(audio and audio.complete or 0),tostring(audio and audio.total or 24)))
    stage(mod,"audio",generated);state.audio_ready=1
    del(mod,"build/audio_warning.txt")
    write(mod,".cbe-audio-v1.complete",AUDIO_MARKER,generated)
    state.current_stage="ready";state.message="Runtime ready; generated audio cache 24/24"
    saveState();finishManifest(mod,generated)
    update("RUNTIME READY / AUDIO 24/24",8,8)
    return {state="READY",visualReady=true,audioReady=true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
  end)
  if not ok then
    local msg=tostring(result)
    local failedStage=state.current_stage
    local visualSurvived=true
    for _,p in ipairs(VISUAL_CORE)do if not exists(mod,p)then visualSurvived=false;break end end
    if failedStage=="audio" and visualSurvived then
      state.current_stage="ready_visual";state.audio_ready=0
      state.message="Runtime ready; optional Colosseum audio unavailable: "..msg
      del(mod,"build/error.txt");del(mod,".cbe-audio-v1.complete")
      pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
      pcall(function()write(mod,"build/audio_warning.txt",msg.."\n",nil)end)
      pcall(function()pending(mod,"audio",msg,nil)end)
      pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()finishManifest(mod,generated)end)
      return {state="READY / AUDIO OPTIONAL",visualReady=true,audioReady=false,audioUnavailable=true,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message}
    end
    state.current_stage="failed";state.message=msg
    pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
    pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
    if visualSurvived then
      pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)end)
    else del(mod,".cbe-visual-v2.complete");del(mod,".cbe-runtime-v2.complete") end
    del(mod,".cbe-audio-v1.complete")
    -- Preserve any successful stage outputs and diagnostics for the next test.
    pcall(function()finishManifest(mod,generated)end)
    return {state=visualSurvived and "READY / DEGRADED" or "FAILED",visualReady=visualSurvived,audioReady=false,audioUnavailable=visualSurvived,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg}
  end
  return result
end
B.marker=EXPECTED_MARKER
B.audioMarker=AUDIO_MARKER
B.trainerIdentityMarker=TRAINER_IDENTITY_MARKER
B.arenaMarker=ARENA_MARKER
B.visualCore=VISUAL_CORE
B.audioCore=AUDIO_CORE
return B
