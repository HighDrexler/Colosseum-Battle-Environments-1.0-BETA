local V=...
local mod=V.mod
local GeneratedAssets=V.GeneratedAssets
local C={schema=17,lastAction=nil,cacheVersion=2,extractorRevision=15}
local AUDIO_MARKER="cbe-audio=3\nassets=24\nsource=GC6E01\n"
local PORTABLE_AUDIO_MARKER="cbe-audio-portable=core2\nsource=GC6E01\ntransition=dsp92\ndecoder=fresh-history\n"
local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-portable=4\nsource=GC6E01\nassets=24\nrate=32000\nrenderer=lua-musyx-battle-fidelity-v3-loop-boundary\n"
local ARENA_MARKER=[=[cbe-arena=7
water=GC6E01/M1_water_colo.fsys/M1_water_colo.dat/source-hsd-scene-v32
orre=GC6E01/T1_ancient_colo.fsys/T1_ancient_colo.dat/source-hsd-scene-v32
realgam=GC6E01/D4_casino_colo.fsys/D4_casino_colo.dat/source-hsd-scene-v32
wildlands=grounded-solid-grass-v18
routing=battle-start-binding-reset
vertex-contract=hsd-normal-not-tint
material-contract=source-diffuse-ambient-specular-shininess
texture-wrap=source-gx
summit=GC6E01/D2_crater_colo.fsys/D2_crater_colo.dat/source-hsd-scene-v32
source-parity=water+orre+realgam+summit-full-refresh
mt-battle-material=exact-source-gx;neutral-backdrop;extended-depth
orre-distance=full-T1-scene;realgam-distance=full-D4-scene;extended-depth
]=]
local TRAINER_IDENTITY_MARKER=[=[cbe-trainer-identity=12
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
pose=native-hsd-scene-root;clip1-nonbind-base;dense-clipfamilies-v7;five-sample-adjacent-interpolation;source-hand-topology;exact-end-effector;procedural=residual-only
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
  "cache/capture/index.lua",
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
  "assets/audio/capture/me_snatch.wav",
  "assets/audio/colosseum_battle_transition.wav",
}
local COMPONENTS={
  arenas={"cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua"},
  trainers={"cache/trainers/red/model_cache.lua","cache/trainers/leaf/model_cache.lua","cache/trainers/wes/model_cache.lua","cache/trainers/brendan/model_cache.lua","cache/trainers/may/model_cache.lua","cache/trainers/cooltrainer_m/model_cache.lua","cache/trainers/cooltrainer_f/model_cache.lua","cache/trainers/dakim/model_cache.lua","cache/trainers/nascour/model_cache.lua","cache/trainers/miror_b/model_cache.lua","cache/trainers/generic/index.lua"},
  audio=AUDIO_CORE,
  capture={"cache/capture/index.lua"},
  transition={"assets/transition/wipe_ball00.rgba","assets/transition/wipe_ball01.rgba"},
}
local STAGES={"disc","fsys","arenas","trainers","capture","transition","audio_portable","audio","verify"}

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
  local romReady=rom~=nil
  local state=parseState(read("build/state.txt"))
  local err=read("build/error.txt");if type(err)=="string" then err=err:gsub("[%s\r\n]+$","") end
  local audioWarning=read("build/audio_warning.txt");if type(audioWarning)=="string" then audioWarning=audioWarning:gsub("[%s\r\n]+$","") end
  local marker=read(".cbe-runtime-v2.complete")
  local visualMarker=read(".cbe-visual-v2.complete")
  local runtimeMissing={}
  for _,p in ipairs(RUNTIME_CORE) do if not exists(p) then runtimeMissing[#runtimeMissing+1]=p end end
  local audioMissing={}
  for _,p in ipairs(AUDIO_CORE) do if not exists(p) then audioMissing[#audioMissing+1]=p end end
  local trainerIdentityMarker=read(".cbe-trainer-identity-v12.complete")
  local arenaMarker=read(".cbe-arena-v7.complete")
  local visualReady=#runtimeMissing==0 and visualMarker=="cbe-runtime=2\nextractor=15\n" and trainerIdentityMarker==TRAINER_IDENTITY_MARKER and arenaMarker==ARENA_MARKER
  local audioMarker=read(".cbe-audio-v1.complete")
  local portableAudioMarker=read(".cbe-audio-portable-v1.complete")
  local portableAudioPrimaryMarker=read(".cbe-audio-portable-v4.complete")
  local portableAudioFallbackMarker=read("build/audio_portable_v4.complete")
  local portableAudioFullMarker=(portableAudioPrimaryMarker==PORTABLE_AUDIO_FULL_MARKER and portableAudioPrimaryMarker) or portableAudioFallbackMarker
  local portableWav=read("assets/audio/colosseum_battle_transition.wav")
  local portableAudioCoreReady=portableAudioMarker==PORTABLE_AUDIO_MARKER and type(portableWav)=="string" and #portableWav>=44 and portableWav:sub(1,4)=="RIFF" and portableWav:sub(9,12)=="WAVE"
  local portableAudioReady=#audioMissing==0 and portableAudioCoreReady and (portableAudioPrimaryMarker==PORTABLE_AUDIO_FULL_MARKER or portableAudioFallbackMarker==PORTABLE_AUDIO_FULL_MARKER)
  local audioReady=#audioMissing==0 and (audioMarker==AUDIO_MARKER or portableAudioReady)
  local fullRuntimeReady=visualReady and audioReady and marker=="cbe-runtime=2\nextractor=15\n"
  local runtimeReady=visualReady
  local counts={};for id,paths in pairs(COMPONENTS) do counts[id]=count(paths) end
  local stage={};for _,id in ipairs(STAGES) do stage[id]=exists("build/stage_"..id..".complete") end
  local status
  if fullRuntimeReady then status="RUNTIME READY"
  elseif runtimeReady and portableAudioCoreReady and not audioReady then status="RUNTIME READY / PORTABLE AUDIO CORE"
  elseif runtimeReady and not audioReady then status="RUNTIME READY / COLOSSEUM AUDIO UNAVAILABLE"
  elseif state.current_stage=="arena_repair_failed" then status="ARENA CACHE REPAIR FAILED"
  elseif state.current_stage=="trainer_identity_failed" then status="TRAINER CACHE REPAIR FAILED"
  elseif state.current_stage=="partial_trainers" then status="CACHE PARTIAL / TRAINERS PENDING"
  elseif err and err~="" then status="EXTRACTION FAILED"
  elseif romReady then status="ROM IMPORTED / BUILD PENDING"
  else status="IMPORT REQUIRED" end
  return {
    schema=C.schema,ready=runtimeReady,runtimeReady=runtimeReady,fullRuntimeReady=fullRuntimeReady,visualReady=visualReady,audioReady=audioReady,portableAudioReady=portableAudioReady,portableAudioCoreReady=portableAudioCoreReady,
    sourceReady=romReady,sourceImported=romReady,sourceStatus=status,source=status,
    generated=visualReady or runtimeReady or exists("build/generated_paths.lua"),generatedRuntime=runtimeReady,marker=marker,visualMarker=visualMarker,audioMarker=audioMarker,portableAudioMarker=portableAudioMarker,portableAudioFullMarker=portableAudioFullMarker,trainerIdentityMarker=trainerIdentityMarker,arenaMarker=arenaMarker,
    files=tonumber(state.fst_files) or 0,sourceFiles=tonumber(state.fst_files) or 0,
    sourceBytes=romReady and (tonumber(rom.size) or 1459978240) or 0,
    sourceSizeLabel=prettyBytes(romReady and (tonumber(rom.size) or 1459978240) or 0),
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
    currentStage=state.current_stage,audioWarning=audioWarning,lastAction=err or audioWarning or state.message or C.lastAction,
  }
end

local function callReset(name)
  local m=V[name]
  if m and type(m.resetRuntime)=="function" then pcall(m.resetRuntime,m) end
  if m and type(m.invalidate)=="function" then pcall(m.invalidate,m) end
end
function C.resetRuntime()
  for _,name in ipairs({"Arena","Trainer","TrainerRoster","PlayerTrainer","CurrentSpriteModels","Transition","Music","StandaloneHost","PokemonActors"}) do callReset(name) end
  collectgarbage("collect")
  C.lastAction="Runtime objects cleared. Generated assets reload on next use."
  return true,C.lastAction
end
function C.resetGenerated()
  -- Public mod.cache deliberately has no recursive filesystem surface.  The
  -- extractor owns a manifest of every generated path and deletes it here.
  -- Lazily extracted Pokemon caches are written long after the build manifest
  -- is finalized, so they carry their own manifest. Clear them first; otherwise
  -- stale species models survive a rebuild.
  local pokemonRaw=read("cache/pokemon/manifest.lua")
  if pokemonRaw then
    local pchunk=load(pokemonRaw,"@generated/cache/pokemon/manifest.lua")
    local pok,plist=false,nil
    if pchunk then pok,plist=pcall(pchunk) end
    if pok and type(plist)=="table" then
      for _,entry in ipairs(plist) do
        if type(entry)=="table" then
          for _,path in ipairs(entry.paths or {}) do GeneratedAssets.delete(path) end
        end
      end
    end
    GeneratedAssets.delete("cache/pokemon/manifest.lua")
  end
  -- 1.7.4 can create compact metadata sidecars at runtime for species whose
  -- model cache predates that format. They may not appear in the historical
  -- species manifest, so clear them explicitly with the generated runtime.
  for dex=1,251 do GeneratedAssets.delete(("cache/pokemon/%d/metadata_v1.lua"):format(dex)) end
  GeneratedAssets.delete("build/format_probe.txt")
  GeneratedAssets.delete("build/camera_probe.txt")

  local raw=read("build/generated_paths.lua")
  if raw then
    local chunk=load(raw,"@generated/build/generated_paths.lua")
    -- Same one-value `and` truncation: "clear generated runtime" deleted only
    -- the marker files below and never the generated assets themselves.
    local ok,paths=false,nil
    if chunk then ok,paths=pcall(chunk) end
    if ok and type(paths)=="table" then for _,path in ipairs(paths) do GeneratedAssets.delete(path) end end
  end
  for _,path in ipairs({".cbe-runtime-v2.complete",".cbe-visual-v2.complete",".cbe-audio-v1.complete",".cbe-audio-portable-v1.complete",".cbe-audio-portable-v2.complete",".cbe-audio-portable-v3.complete",".cbe-audio-portable-v3.pending",".cbe-audio-portable-v4.complete",".cbe-audio-portable-v4.pending","build/audio_portable_v4.complete","build/audio_portable_v4.migrating",".cbe-trainer-identity-v1.complete",".cbe-trainer-identity-v2.complete",".cbe-trainer-identity-v3.complete",".cbe-trainer-identity-v4.complete",".cbe-trainer-identity-v5.complete",".cbe-trainer-identity-v6.complete",".cbe-trainer-identity-v7.complete",".cbe-trainer-identity-v8.complete",".cbe-trainer-identity-v9.complete",".cbe-trainer-identity-v10.complete",".cbe-trainer-identity-v11.complete",".cbe-trainer-identity-v12.complete",".cbe-arena-v2.complete",".cbe-arena-v3.complete",".cbe-arena-v4.complete",".cbe-arena-v5.complete",".cbe-arena-v6.complete",".cbe-arena-v7.complete","build/error.txt","build/audio_warning.txt","build/state.txt","build/generated_paths.lua","build/stage_trainers.pending","build/stage_audio.pending"}) do GeneratedAssets.delete(path) end
  for _,id in ipairs(STAGES) do GeneratedAssets.delete("build/stage_"..id..".complete");GeneratedAssets.delete("build/stage_"..id..".pending") end
  C.lastAction="Generated CBE runtime cleared. Reload CBE to rebuild from the imported disc."
  return true,C.lastAction
end
function C.status() return C.inspect() end
function C.prettyBytes(n) return prettyBytes(n) end
return C
