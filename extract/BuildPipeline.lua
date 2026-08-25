local V=...
local Disc,FSYS=V.GameCubeDisc,V.FSYS
local ArenaBuilder,TrainerExtractor,TransitionBuilder,AudioProbe=V.ArenaBuilder,V.TrainerExtractor,V.TransitionBuilder,V.AudioProbe
local B={cacheVersion=2,extractorRevision=11}
local EXPECTED_MARKER="cbe-runtime=2\nextractor=11\n"
local VISUAL_CORE={
  "cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua",
  "cache/trainers/red/model_cache.lua","cache/trainers/leaf/model_cache.lua","cache/trainers/wes/model_cache.lua","cache/trainers/brendan/model_cache.lua","cache/trainers/may/model_cache.lua","cache/trainers/cooltrainer_m/model_cache.lua","cache/trainers/cooltrainer_f/model_cache.lua","cache/trainers/dakim/model_cache.lua","cache/trainers/nascour/model_cache.lua","cache/trainers/miror_b/model_cache.lua","cache/trainers/generic/index.lua",
  "assets/transition/wipe_ball00.rgba","assets/transition/wipe_ball01.rgba",
}
local AUDIO_MARKER="cbe-audio=2\nassets=23\nsource=GC6E01\nrenderer=musyx-in-process-alpha\nrate=32000\n"
local TRAINER_IDENTITY_MARKER=[=[cbe-trainer-identity=7
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
pose=native-hsd-clip1-frame0;dakim=clip1-auto-idle-phase
]=]
local ARENA_MARKER=[=[cbe-arena=4
water=GC6E01/M1_water_colo.fsys/M1_water_colo.dat/source-hsd-scene
orre=GC6E01/T1_ancient_colo.fsys/T1_ancient_colo.dat/source-hsd-scene
realgam=GC6E01/D4_casino_colo.fsys/D4_casino_colo.dat/source-hsd-scene
wildlands=grounded-solid-grass
routing=battle-start-binding-reset
vertex-contract=hsd-normal-not-tint
texture-wrap=source-gx
summit=presentation-v23-organic-basalt-no-grid
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
  local keys={"cache_version","extractor_revision","current_stage","message","disc_id","disc_region","source_size","source_format","logical_size","fst_files","fsys_files","source_fingerprint","visual_ready","audio_ready","trainer_resolved","trainer_total","trainer_diagnostic","trainer_first_error","trainer_source_error"}
  local o={};for _,k in ipairs(keys)do if s[k]~=nil then o[#o+1]=k.."="..tostring(s[k]) end end;return table.concat(o,"\n").."\n"
end
local function cleanupPrevious(mod)
  local raw=read(mod,"build/generated_paths.lua");if not raw then return end
  local chunk=load(raw,"@generated/build/generated_paths.lua");local ok,paths=chunk and pcall(chunk)
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
local function trainerIdentityReady(mod)
  return read(mod,".cbe-trainer-identity-v7.complete")==TRAINER_IDENTITY_MARKER
end
local function arenaReady(mod)
  return read(mod,".cbe-arena-v4.complete")==ARENA_MARKER
end
local function visualReady(mod)
  return baseVisualReady(mod) and trainerIdentityReady(mod) and arenaReady(mod)
end
local function audioReady(mod)
  if read(mod,".cbe-audio-v2.complete")~=AUDIO_MARKER then return false end
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
  local ok,paths=chunk and pcall(chunk)
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

local function audioOnly(mod,progress)
  local generated=previousGenerated(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="audio",message="Resuming generated audio cache",disc_id="GC6E01",
    disc_region="USA",visual_ready=1,audio_ready=0}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/stage_audio.pending")
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    local audio=AudioProbe.run(mod,disc,progress,generated)
    assert(audio and audio.ready,("audio cache incomplete (%s/%s)")
      :format(tostring(audio and audio.complete or 0),tostring(audio and audio.total or 23)))
    stage(mod,"audio",generated)
    state.audio_ready=1;state.current_stage="ready";state.message="Runtime ready; generated audio cache 23/23"
    write(mod,".cbe-audio-v2.complete",AUDIO_MARKER,generated);del(mod,".cbe-audio-v1.complete")
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    save();finishManifest(mod,generated)
    return {state="READY",visualReady=true,audioReady=true,message=state.message}
  end)
  if ok then return result end
  local msg=tostring(result)
  state.current_stage="audio_failed";state.message=msg
  pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
  pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
  pending(mod,"audio",msg,nil)
  del(mod,".cbe-audio-v2.complete");del(mod,".cbe-audio-v1.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="VISUAL READY / AUDIO FAILED",visualReady=true,audioReady=false,message=msg}
end

-- Upgrade an existing visual cache in place. All trainer models are rewritten
-- from exact battle-member identities; arenas, transitions and all 23 generated
-- WAVs remain untouched and reusable.
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
    write(mod,".cbe-trainer-identity-v7.complete",TRAINER_IDENTITY_MARKER,generated)
    del(mod,".cbe-trainer-identity-v1.complete");del(mod,".cbe-trainer-identity-v2.complete");del(mod,".cbe-trainer-identity-v3.complete");del(mod,".cbe-trainer-identity-v4.complete");del(mod,".cbe-trainer-identity-v5.complete");del(mod,".cbe-trainer-identity-v6.complete")
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=1
    if hadAudio then
      state.current_stage="ready";state.message="Runtime ready; native trainer non-bind stance cache rebuilt and generated audio cache reused"
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    else
      state.current_stage="audio";state.message="Native trainer non-bind stance cache rebuilt; generated audio cache pending"
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
  del(mod,".cbe-trainer-identity-v7.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="TRAINER CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,
    trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,
    trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg}
end

-- Arena-only migration: the summit-only repair path refreshes Mt. Battle's D2
-- procedural textures and Platform 100 cache only. Existing Water/Orre/Realgam/
-- Wildlands, trainer, transition and audio caches remain untouched. This is
-- intentionally independent from the global extractor revision.
arenasOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local hadTrainers=trainerIdentityReady(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="arenas",message="Rebuilding corrected Mt. Battle Summit",disc_id="GC6E01",disc_region="USA",
    visual_ready=0,audio_ready=hadAudio and 1 or 0,trainer_resolved=hadTrainers and 10 or 0,trainer_total=10}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/stage_arenas.pending");del(mod,".cbe-runtime-v2.complete");del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete");del(mod,".cbe-arena-v4.complete")
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    if type(ArenaBuilder.repair)=="function" then ArenaBuilder.repair(mod,disc,progress,generated)
    else ArenaBuilder.run(mod,disc,progress,generated) end
    stage(mod,"arenas",generated)
    write(mod,".cbe-arena-v4.complete",ARENA_MARKER,generated);del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete")
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=hadTrainers and 1 or 0
    if hadTrainers and hadAudio then
      state.current_stage="ready";state.message="Runtime ready; Mt. Battle rebuilt, all other arena/trainer/audio caches reused"
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    elseif hadTrainers then
      state.current_stage="audio";state.message="Mt. Battle rebuilt; generated audio cache pending"
    else
      state.current_stage="trainers";state.message="Mt. Battle rebuilt; exact trainer cache pending"
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
    pending(mod,"arenas",msg,nil);del(mod,".cbe-arena-v4.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="ARENA CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,message=msg}
end

function B.run(mod,progress)
  assert(mod and mod.imports and mod.cache,"Gen1Recomp mod.imports/mod.cache API unavailable")
  progress=progress or function()end
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
  for _,p in ipairs({".cbe-runtime-v2.complete",".cbe-visual-v2.complete",".cbe-audio-v2.complete",".cbe-audio-v1.complete",".cbe-trainer-identity-v1.complete",".cbe-trainer-identity-v2.complete",".cbe-trainer-identity-v3.complete",".cbe-trainer-identity-v4.complete",".cbe-trainer-identity-v5.complete",".cbe-trainer-identity-v6.complete",".cbe-trainer-identity-v7.complete",".cbe-arena-v2.complete",".cbe-arena-v3.complete",".cbe-arena-v4.complete","build/error.txt","build/stage_trainers.pending","build/stage_audio.pending"})do del(mod,p)end
  local generated={}
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,current_stage="disc",message="Opening validated GC6E01 source",disc_id="GC6E01",disc_region="USA",visual_ready=0,audio_ready=0,trainer_resolved=0,trainer_total=10,trainer_diagnostic="build/trainer_scan.txt"}
  local function saveState()write(mod,"build/state.txt",stateText(state),generated)end
  local function update(label,current,total)progress(label,current,total)end
  local ok,result=pcall(function()
    update("DISC / FST",0,7)
    local disc=Disc.open(mod)
    state.source_size=disc.containerSize or disc.info.size;state.source_format=disc.sourceFormat or "iso";state.logical_size=disc.logicalSize or disc.info.size;state.fst_files=#disc.files;state.source_fingerprint=("GC6E01:%s:%d:%d:%d:%d"):format(state.source_format,state.source_size,state.logical_size,disc.fstOffset,disc.fstSize)
    write(mod,"build/disc_index.lua",Disc.serializeIndex(disc),generated)
    state.message="GameCube FST indexed";saveState();stage(mod,"disc",generated)

    state.current_stage="fsys";state.message="Validating Colosseum FSYS archives";saveState();update("FSYS VALIDATION",1,7)
    local fsysCount=0;for _,f in ipairs(disc.files)do if f.path:lower():match("%.fsys$")then fsysCount=fsysCount+1 end end
    state.fsys_files=fsysCount
    assert(fsysCount>1000,("unexpected FSYS inventory (%d)"):format(fsysCount))
    local people=assert(disc:file("people_archive.fsys"),"people_archive.fsys missing")
    local parc=FSYS.open(disc,people);assert(#parc:list()>20,"people_archive.fsys did not parse")
    write(mod,"build/fsys.lua",string.format("return {count=%d,peopleMembers=%d}\n",fsysCount,#parc:list()),generated)
    state.message="FSYS transport validated";saveState();stage(mod,"fsys",generated)

    state.current_stage="arenas";state.message="Generating CBE arena runtime";saveState();update("ARENAS",2,7)
    ArenaBuilder.run(mod,disc,function(label,c,t)update(label,c,t)end,generated);stage(mod,"arenas",generated);write(mod,".cbe-arena-v4.complete",ARENA_MARKER,generated)

    state.current_stage="trainers";state.message="Extracting trainer HSD models, native poses, and GX textures";saveState();update("TRAINERS",3,7)
    local trainer=TrainerExtractor.run(mod,disc,function(label,c,t)update(label,c,t)end,generated) or {}
    state.trainer_resolved=tonumber(trainer.resolvedCount) or 0;state.trainer_total=tonumber(trainer.total) or 10;state.trainer_first_error=trainer.firstError;state.trainer_source_error=trainer.firstSourceError
    local trainerReady=trainer.ready==true
    if trainerReady then stage(mod,"trainers",generated);write(mod,".cbe-trainer-identity-v7.complete",TRAINER_IDENTITY_MARKER,generated);del(mod,".cbe-trainer-identity-v1.complete");del(mod,".cbe-trainer-identity-v2.complete");del(mod,".cbe-trainer-identity-v3.complete");del(mod,".cbe-trainer-identity-v4.complete");del(mod,".cbe-trainer-identity-v5.complete");del(mod,".cbe-trainer-identity-v6.complete");state.message="Trainer source cache complete"
    else pending(mod,"trainers",("resolved %d/%d; see %s"):format(state.trainer_resolved,state.trainer_total,state.trainer_diagnostic),generated);state.message=("Trainer cache partial (%d/%d); diagnostics recorded"):format(state.trainer_resolved,state.trainer_total) end
    saveState()

    state.current_stage="transition";state.message="Generating battle transition masks";saveState();update("TRANSITION",4,7)
    TransitionBuilder.run(mod,disc,function(label,c,t)update(label,c,t)end,generated);stage(mod,"transition",generated)

    state.current_stage="audio";state.message="Rendering platform-neutral in-process MusyX audio";saveState();update("AUDIO SOURCE",5,7)
    local audio=AudioProbe.run(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(audio and audio.ready,("audio cache incomplete (%s/%s)")
      :format(tostring(audio and audio.complete or 0),tostring(audio and audio.total or 23)))
    stage(mod,"audio",generated);state.audio_ready=1
    write(mod,".cbe-audio-v2.complete",AUDIO_MARKER,generated);del(mod,".cbe-audio-v1.complete")

    if not trainerReady then
      state.visual_ready=0;state.current_stage="partial_trainers";state.message=("Source cache completed through arenas/transition/audio probe; trainer HSD unresolved %d/%d. See %s"):format(state.trainer_total-state.trainer_resolved,state.trainer_total,state.trainer_diagnostic)
      saveState();finishManifest(mod,generated);update("CACHE PARTIAL / TRAINERS PENDING",6,7)
      return {state="CACHE PARTIAL / TRAINERS PENDING",visualReady=false,audioReady=state.audio_ready==1,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message}
    end

    state.current_stage="verify";state.message="Verifying generated visual runtime";saveState();update("VERIFY",6,7)
    for _,p in ipairs(VISUAL_CORE)do assert(exists(mod,p),"generated visual runtime missing: "..p)end
    stage(mod,"verify",generated)
    state.visual_ready=1;state.current_stage="ready";state.message="Runtime ready; generated audio cache 23/23"
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    saveState();finishManifest(mod,generated)
    update("RUNTIME READY / AUDIO 23/23",7,7)
    return {state="READY",visualReady=true,audioReady=true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
  end)
  if not ok then
    local msg=tostring(result)
    local failedStage=state.current_stage
    state.current_stage=failedStage=="audio" and "audio_failed" or "failed";state.message=msg;pcall(function()write(mod,"build/state.txt",stateText(state),nil)end);pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
    local visualSurvived=true
    for _,p in ipairs(VISUAL_CORE)do if not exists(mod,p)then visualSurvived=false;break end end
    if visualSurvived then pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
    else del(mod,".cbe-visual-v2.complete") end
    del(mod,".cbe-audio-v2.complete");del(mod,".cbe-audio-v1.complete");del(mod,".cbe-runtime-v2.complete")
    -- Preserve any successful stage outputs and diagnostics for the next test.
    pcall(function()finishManifest(mod,generated)end)
    return {state=visualSurvived and "VISUAL READY / AUDIO FAILED" or "FAILED",visualReady=visualSurvived,audioReady=false,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg}
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
