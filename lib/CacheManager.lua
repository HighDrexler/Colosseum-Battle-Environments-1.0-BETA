local V=...
local mod=V.mod
local GeneratedAssets=V.GeneratedAssets
local C={schema=14,lastAction=nil,cacheVersion=2,extractorRevision=11}
local AUDIO_MARKER="cbe-audio=2\nassets=23\nsource=GC6E01\nrenderer=musyx-in-process-alpha\nrate=32000\n"
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
local RUNTIME_CORE={
  "cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua",
  "cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua",
  "cache/D2_mt_battle_platform100_cache.lua",
  "cache/trainers/red/model_cache.lua","cache/trainers/leaf/model_cache.lua",
  "cache/trainers/wes/model_cache.lua","cache/trainers/brendan/model_cache.lua",
  "cache/trainers/may/model_cache.lua","cache/trainers/cooltrainer_m/model_cache.lua",
  "cache/trainers/cooltrainer_f/model_cache.lua","cache/trainers/dakim/model_cache.lua",
  "cache/trainers/nascour/model_cache.lua","cache/trainers/miror_b/model_cache.lua",
  "cache/trainers/generic/index.lua",
  "assets/transition/wipe_ball00.rgba","assets/transition/wipe_ball01.rgba",
}
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
local COMPONENTS={
  arenas={"cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua"},
  trainers={"cache/trainers/red/model_cache.lua","cache/trainers/leaf/model_cache.lua","cache/trainers/wes/model_cache.lua","cache/trainers/brendan/model_cache.lua","cache/trainers/may/model_cache.lua","cache/trainers/cooltrainer_m/model_cache.lua","cache/trainers/cooltrainer_f/model_cache.lua","cache/trainers/dakim/model_cache.lua","cache/trainers/nascour/model_cache.lua","cache/trainers/miror_b/model_cache.lua","cache/trainers/generic/index.lua"},
  audio=AUDIO_CORE,
  transition={"assets/transition/wipe_ball00.rgba","assets/transition/wipe_ball01.rgba"},
}
local STAGES={"disc","fsys","arenas","trainers","transition","audio","verify"}

local function importInfo()
  if not (mod.imports and type(mod.imports.info)=="function") then return nil end
  local ok,v=pcall(mod.imports.info,mod.imports,"pokemon_colosseum_usa")
  return ok and v or nil
end
local function read(path) return GeneratedAssets.read(path) end
local function exists(path) return GeneratedAssets.exists(path) end
local function parseState(raw)
  local out={}
  if type(raw)~="string" then return out end
  for line in raw:gmatch("[^\r\n]+") do local k,v=line:match("^([%w_%.%-]+)=(.*)$");if k then out[k]=v end end
  return out
end
local function prettyBytes(n)
  n=tonumber(n) or 0
  if n>=1024^3 then return ("%.2f GiB"):format(n/(1024^3)) end
  if n>=1024^2 then return ("%.1f MiB"):format(n/(1024^2)) end
  if n>=1024 then return ("%.1f KiB"):format(n/1024) end
  return tostring(n).." B"
end
local function count(paths)
  local have=0
  for _,p in ipairs(paths) do if exists(p) then have=have+1 end end
  return {have=have,total=#paths}
end

function C.inspect()
  local rom=importInfo()
  local sourceSize=rom and tonumber(rom.size) or nil
  local romReady=sourceSize==1459978240 or sourceSize==664830528
  local state=parseState(read("build/state.txt"))
  local err=read("build/error.txt");if type(err)=="string" then err=err:gsub("[%s\r\n]+$","") end
  local marker=read(".cbe-runtime-v2.complete")
  local visualMarker=read(".cbe-visual-v2.complete")
  local runtimeMissing={}
  for _,p in ipairs(RUNTIME_CORE) do if not exists(p) then runtimeMissing[#runtimeMissing+1]=p end end
  local audioMissing={}
  for _,p in ipairs(AUDIO_CORE) do if not exists(p) then audioMissing[#audioMissing+1]=p end end
  local trainerIdentityMarker=read(".cbe-trainer-identity-v7.complete")
  local arenaMarker=read(".cbe-arena-v4.complete")
  local visualReady=#runtimeMissing==0 and visualMarker=="cbe-runtime=2\nextractor=11\n" and trainerIdentityMarker==TRAINER_IDENTITY_MARKER and arenaMarker==ARENA_MARKER
  local audioMarker=read(".cbe-audio-v2.complete")
  local audioReady=#audioMissing==0 and audioMarker==AUDIO_MARKER
  local runtimeReady=visualReady and audioReady and marker=="cbe-runtime=2\nextractor=11\n"
  local counts={};for id,paths in pairs(COMPONENTS) do counts[id]=count(paths) end
  local stage={};for _,id in ipairs(STAGES) do stage[id]=exists("build/stage_"..id..".complete") end
  local status
  if runtimeReady then status="RUNTIME READY"
  elseif visualReady and not audioReady then status="VISUAL RUNTIME READY / AUDIO PENDING"
  elseif state.current_stage=="arena_repair_failed" then status="ARENA CACHE REPAIR FAILED"
  elseif state.current_stage=="trainer_identity_failed" then status="TRAINER CACHE REPAIR FAILED"
  elseif state.current_stage=="partial_trainers" then status="CACHE PARTIAL / TRAINERS PENDING"
  elseif err and err~="" then status="EXTRACTION FAILED"
  elseif romReady then status="ROM IMPORTED / BUILD PENDING"
  else status="IMPORT REQUIRED" end
  return {
    schema=C.schema,ready=runtimeReady,runtimeReady=runtimeReady,visualReady=visualReady,audioReady=audioReady,
    sourceReady=romReady,sourceImported=romReady,sourceStatus=status,source=status,
    generated=visualReady or runtimeReady or exists("build/generated_paths.lua"),generatedRuntime=runtimeReady,marker=marker,visualMarker=visualMarker,audioMarker=audioMarker,trainerIdentityMarker=trainerIdentityMarker,arenaMarker=arenaMarker,
    files=tonumber(state.fst_files) or 0,sourceFiles=tonumber(state.fst_files) or 0,
    sourceBytes=romReady and sourceSize or 0,
    sourceSizeLabel=prettyBytes(romReady and sourceSize or 0),
    sourceFormat=state.source_format or (sourceSize==664830528 and "ciso" or (sourceSize==1459978240 and "iso" or nil)),
    logicalSourceBytes=tonumber(state.logical_size) or (romReady and 1459978240 or 0),
    sourceFingerprint=state.source_fingerprint or (romReady and "GC6E01 / launcher-validated" or nil),
    missing=runtimeMissing,audioMissing=audioMissing,componentCounts=counts,stages=stage,
    discId="GC6E01",discRegion="USA",cacheVersion=C.cacheVersion,
    extractionCacheVersion=C.cacheVersion,extractorRevision=C.extractorRevision,
    trainerResolved=tonumber(state.trainer_resolved) or counts.trainers.have,
    trainerTotal=tonumber(state.trainer_total) or 10,
    trainerDiagnostic=state.trainer_diagnostic,
    trainerFirstError=state.trainer_first_error,
    trainerSourceError=state.trainer_source_error,
    sourceAccess=romReady and "VALIDATED / BOUNDED" or "NOT AVAILABLE",
    currentStage=state.current_stage,lastAction=err or state.message or C.lastAction,
  }
end

local function callReset(name)
  local m=V[name]
  if m and type(m.resetRuntime)=="function" then pcall(m.resetRuntime,m) end
  if m and type(m.invalidate)=="function" then pcall(m.invalidate,m) end
end
function C.resetRuntime()
  for _,name in ipairs({"Arena","Trainer","TrainerRoster","PlayerTrainer","CurrentSpriteModels","Transition","Music","StandaloneHost"}) do callReset(name) end
  collectgarbage("collect")
  C.lastAction="Runtime objects cleared. Generated assets reload on next use."
  return true,C.lastAction
end
function C.resetGenerated()
  -- Public mod.cache deliberately has no recursive filesystem surface.  The
  -- extractor owns a manifest of every generated path and deletes it here.
  local raw=read("build/generated_paths.lua")
  if raw then
    local chunk=load(raw,"@generated/build/generated_paths.lua")
    local ok,paths=chunk and pcall(chunk)
    if ok and type(paths)=="table" then for _,path in ipairs(paths) do GeneratedAssets.delete(path) end end
  end
  for _,path in ipairs({".cbe-runtime-v2.complete",".cbe-visual-v2.complete",".cbe-audio-v2.complete",".cbe-audio-v1.complete",".cbe-trainer-identity-v1.complete",".cbe-trainer-identity-v2.complete",".cbe-trainer-identity-v3.complete",".cbe-trainer-identity-v4.complete",".cbe-trainer-identity-v5.complete",".cbe-trainer-identity-v6.complete",".cbe-trainer-identity-v7.complete",".cbe-arena-v2.complete",".cbe-arena-v3.complete",".cbe-arena-v4.complete","build/error.txt","build/state.txt","build/generated_paths.lua","build/stage_trainers.pending","build/stage_audio.pending"}) do GeneratedAssets.delete(path) end
  for _,id in ipairs(STAGES) do GeneratedAssets.delete("build/stage_"..id..".complete");GeneratedAssets.delete("build/stage_"..id..".pending") end
  C.lastAction="Generated CBE runtime cleared. Reload CBE to rebuild from the imported disc."
  return true,C.lastAction
end
function C.status() return C.inspect() end
function C.prettyBytes(n) return prettyBytes(n) end
return C
