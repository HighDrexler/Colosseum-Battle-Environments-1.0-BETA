local V=...
local mod=V.mod
local GeneratedAssets=V.GeneratedAssets
local C={schema=20,lastAction=nil,cacheVersion=2,extractorRevision=15}
local HARD_CACHE_MARKER="build/hard_cache_v5.complete"
local PREVIOUS_HARD_CACHE_MARKER="build/hard_cache_v4.complete"
local LEGACY_HARD_CACHE_MARKER="build/hard_cache_v3.complete"
local OLDER_HARD_CACHE_MARKER="build/hard_cache_v2.complete"
local inspectMemo=nil
local inspectMemoAt=-math.huge
local INSPECT_TTL=0.40
local function nowClock()
  if love and love.timer and type(love.timer.getTime)=="function" then local ok,v=pcall(love.timer.getTime);if ok and type(v)=="number" then return v end end
  return os.clock()
end
local function invalidateInspect() inspectMemo=nil;inspectMemoAt=-math.huge end
local AUDIO_MARKER="cbe-audio=4\nassets=24\nsource=GC6E01\nrenderer=amuse-refresh-v1\n"
local PORTABLE_AUDIO_MARKER="cbe-audio-portable=core2\nsource=GC6E01\ntransition=dsp92\ndecoder=fresh-history\n"
local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-portable=9\nsource=GC6E01\nassets=24\nrate=48000\nrenderer=lua-musyx-canonical-v9-cross-platform-48k\nloop=source-sng-header-plus-region-sentinel\n"
local AUDIO_EXHAUSTED_PATH=".cbe-audio-exhausted-v1.complete"
local AUDIO_EXHAUSTED_MARKER="cbe-audio-exhausted=1\nsource=GC6E01\ncontract=best-effort-all-renderers-v2\nportable=v7-48k\n"
local ARENA_MARKER=[=[cbe-arena=10
water=GC6E01/M1_water_colo.fsys/M1_water_colo.dat/source-hsd-scene-v33
orre=GC6E01/T1_ancient_colo.fsys/T1_ancient_colo.dat/source-hsd-scene-v33
relic_chamber=GC6E01/M3_shrine_1F_bf.fsys/M3_shrine_1F_bf.dat/source-hsd-scene-v33
relic_cave=GC6E01/M3_cave_1F_1_bf.fsys/M3_cave_1F_1_bf.dat/source-hsd-scene-v33
outskirts=GC6E01/S1_out_bf.fsys/S1_out_bf.dat/source-hsd-scene-v33
pyrite=GC6E01/M2_earth_colo.fsys/M2_earth_colo.dat/source-hsd-scene-v33
deep=GC6E01/M4_bottom_colo.fsys/M4_bottom_colo.dat/source-hsd-scene-v33+retail-pass-v2
realgam=GC6E01/D4_casino_colo.fsys/D4_casino_colo.dat/source-hsd-scene-v33
wildlands=grounded-solid-grass-v18
summit=GC6E01/D2_crater_colo.fsys/D2_crater_colo.dat/source-hsd-scene-v33
routing=battle-start-binding-reset
vertex-contract=hsd-source-rgba+authored-normal-v12
cipher_lab=GC6E01/D1_labo_B1_bf.fsys/D1_labo_B1_bf.dat
audience=namespace-qualified-six-venues+rgba-preserved
arena-schema=16
material-contract=source-renderflags+diffuse+ambient+specular+shininess+gx-wrap
texture-policy=source-atlas-no-cbe-sharpen
source-texture-state=static-tobj-uv+color-stage-v1
source-instances=native-jobj-instance-v1
scene-envelope=extended-source-shell-v4
relic-chamber=retail-source-complete+native-scale-compensation+source-material-color+cave-scale-compensation-v5
outskirts=retail-renderpass-filter+desert-floor-blend+source-shell-v3+sand-drift-v2
deep=retail-renderpass-filter+outer-shell-v4+source-neutral-lighting+long-depth-clarity
source-parity=water+orre+relic-chamber+relic-cave+outskirts+pyrite+deep+realgam+summit-full-refresh
]=]
local PREVIOUS_ARENA_MARKER=ARENA_MARKER:gsub("relic%-chamber=[^\n]+",
  "relic-chamber=retail-renderpass-filter+central-overhang-reject+source-half-shell+understory-ground-detail+dapple-light+camera-guard-v4",1)
local CHECKPOINT_ARENA_MARKER=ARENA_MARKER:gsub("source%-instances=[^\n]+\n","",1)
local ARENA_RUNTIME_SIDECAR_PATH=".cbe-arena-runtime-sidecars-v2.complete"
local ARENA_RUNTIME_SIDECAR_MARKER="cbe-arena-runtime-sidecars=2\nformat=7\nstage=build-time\nsource=canonical-arena-cache\nwater-audience=source-banks-v2\n"
local TRAINER_IDENTITY_MARKER=[=[cbe-trainer-identity=16
red=pkx_akami_m_a1.fsys/akami_m_a1.pkx
leaf=pkx_akami_f_a1.fsys/akami_f_a1.pkx
wes=people_archive.fsys/ken_a1.dat
brendan=pkx_agb_m_a1.fsys/agb_m_a1.pkx
may=pkx_agb_f_a1.fsys/agb_f_a1.pkx
cooltrainer_m=people_archive.fsys/traner_m_a1.dat
cooltrainer_f=people_archive.fsys/traner_f_a1.dat
dakim=people_archive.fsys/battleyama_a1.dat
nascour=people_archive.fsys/boss999_a1.dat
miror_b=people_archive.fsys/boss555_a1.dat
pose=native-hsd-scene-root;clip1-nonbind-base;dense-clipfamilies-v8;retail-motion-role-filter;five-sample-adjacent-interpolation;source-hand-topology;exact-end-effector;runtime-sidecar=extraction-time-f32;native-tracks=1;a1-battle-action-banks=1;authored-displacement=1;procedural=residual-only
]=]
local RUNTIME_CORE={
  "cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua",
  "cache/M3_shrine_1F_bf_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua",
  "cache/D2_mt_battle_platform100_cache.lua","cache/D1_labo_B1_bf_cache.lua",
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
  arenas={"cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/M3_shrine_1F_bf_cache.lua","cache/M3_cave_1F_1_bf_cache.lua","cache/S1_out_bf_cache.lua","cache/M2_earth_colo_cache.lua","cache/M4_bottom_colo_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua","cache/D1_labo_B1_bf_cache.lua"},
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
local function audioLedgerReady()
  -- Match AudioProbe v9 without reading the large WAV bodies. The ledger is a
  -- tiny generated data file containing the exact committed byte size for all
  -- 24 canonical outputs, so a partial/truncated write cannot survive restart
  -- merely because the filename and completion marker still exist.
  local raw=read("build/audio_portable_v9_assets.lua")
  if type(raw)~="string" or not raw:find("version=9",1,true) then return false end
  local sizes={}
  for path,size in raw:gmatch('%["([^"]+)"%]=%{size=(%d+)%}') do sizes[path]=tonumber(size) end
  for _,path in ipairs(AUDIO_CORE) do
    local expected=sizes[path];local info=GeneratedAssets.info(path)
    if not expected or expected<44 or not info then return false end
    local actual=tonumber(info.size)
    if actual~=nil and actual~=expected then return false end
    -- Gen1Recomp portable mode exposes file existence without a byte-size
    -- field. AudioProbe v9 read-backs every newly written WAV before recording
    -- this ledger, so marker + ledger + file existence remains transactional.
    if actual==nil and not GeneratedAssets.exists(path) then return false end
  end
  return true
end

function C.inspect()
  local now=nowClock()
  if inspectMemo and now-inspectMemoAt<INSPECT_TTL then return inspectMemo end
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
  local trainerIdentityMarker=read(".cbe-trainer-identity-v16.complete")
  local arenaMarker=read(".cbe-arena-v10.complete")
  local arenaRuntimeSidecarMarker=read(ARENA_RUNTIME_SIDECAR_PATH)
  local visualReady=#runtimeMissing==0 and visualMarker=="cbe-runtime=2\nextractor=15\n"
    and trainerIdentityMarker==TRAINER_IDENTITY_MARKER and arenaMarker==ARENA_MARKER
    and arenaRuntimeSidecarMarker==ARENA_RUNTIME_SIDECAR_MARKER
  local audioMarker=read(".cbe-audio-v1.complete")
  local portableAudioMarker=read(".cbe-audio-portable-v1.complete")
  local portableAudioPrimaryMarker=read(".cbe-audio-portable-v9.complete")
  local portableAudioFallbackMarker=read("build/audio_portable_v9.complete")
  local portableAudioFullMarker=(portableAudioPrimaryMarker==PORTABLE_AUDIO_FULL_MARKER and portableAudioPrimaryMarker) or portableAudioFallbackMarker
  -- Do not read the complete transition WAV just to render a status/menu row.
  -- The v9 ledger was written only after transactional WAV read-back, so marker
  -- + ledger + generated-file existence is the same portable integrity contract
  -- without pulling an audio body through mod.cache on every diagnostic poll.
  local portableAudioCoreReady=portableAudioMarker==PORTABLE_AUDIO_MARKER and exists("assets/audio/colosseum_battle_transition.wav")
  local portableAudioReady=#audioMissing==0 and portableAudioCoreReady and audioLedgerReady()
    and (portableAudioPrimaryMarker==PORTABLE_AUDIO_FULL_MARKER or portableAudioFallbackMarker==PORTABLE_AUDIO_FULL_MARKER)
  local audioReady=#audioMissing==0 and portableAudioReady
  local audioExhausted=false
  local fullRuntimeReady=visualReady and audioReady and marker=="cbe-runtime=2\nextractor=15\n"
  local degradedRuntimeReady=false
  local runtimeReady=fullRuntimeReady
  local counts={};for id,paths in pairs(COMPONENTS) do counts[id]=count(paths) end
  local arenaUpgradeScope
  if counts.arenas.have==counts.arenas.total then
    if arenaMarker==PREVIOUS_ARENA_MARKER then arenaUpgradeScope="relic-scenes"
    elseif arenaMarker==CHECKPOINT_ARENA_MARKER then arenaUpgradeScope="source-instances" end
  end
  local stage={};for _,id in ipairs(STAGES) do stage[id]=exists("build/stage_"..id..".complete") end
  local status
  if fullRuntimeReady then status="RUNTIME READY"
  elseif state.current_stage=="audio_required_failed" or state.current_stage=="audio_controller_failed" then status="AUDIO REQUIRED / RETRY"
  elseif visualReady and portableAudioCoreReady and not audioReady then status="VISUAL CACHE READY / AUDIO REQUIRED"
  elseif visualReady and not audioReady then status="VISUAL CACHE READY / AUDIO REQUIRED"
  elseif state.current_stage=="arena_repair_failed" then status="ARENA CACHE REPAIR FAILED"
  elseif state.current_stage=="trainer_identity_failed" then status="TRAINER CACHE REPAIR FAILED"
  elseif state.current_stage=="partial_trainers" then status="CACHE PARTIAL / TRAINERS PENDING"
  elseif err and err~="" then status="EXTRACTION FAILED"
  elseif romReady then status="ROM IMPORTED / BUILD PENDING"
  else status="IMPORT REQUIRED" end
  local out={
    schema=C.schema,ready=runtimeReady,runtimeReady=runtimeReady,fullRuntimeReady=fullRuntimeReady,degradedRuntimeReady=degradedRuntimeReady,visualReady=visualReady,audioReady=audioReady,audioExhausted=audioExhausted,portableAudioReady=portableAudioReady,portableAudioCoreReady=portableAudioCoreReady,
    sourceReady=romReady,sourceImported=romReady,sourceStatus=status,source=status,
    generated=visualReady or runtimeReady or exists("build/generated_paths.lua"),generatedRuntime=runtimeReady,marker=marker,visualMarker=visualMarker,audioMarker=audioMarker,portableAudioMarker=portableAudioMarker,portableAudioFullMarker=portableAudioFullMarker,audioExhaustedMarker=audioExhausted and AUDIO_EXHAUSTED_MARKER or nil,trainerIdentityMarker=trainerIdentityMarker,arenaMarker=arenaMarker,arenaRuntimeSidecarMarker=arenaRuntimeSidecarMarker,
    files=tonumber(state.fst_files) or 0,sourceFiles=tonumber(state.fst_files) or 0,
    sourceBytes=romReady and (tonumber(rom.size) or 1459978240) or 0,
    sourceSizeLabel=prettyBytes(romReady and (tonumber(rom.size) or 1459978240) or 0),
    sourceFingerprint=state.source_fingerprint or (romReady and "GC6E01 / launcher-validated" or nil),
    missing=runtimeMissing,audioMissing=audioMissing,componentCounts=counts,stages=stage,
    arenaUpgradeScope=arenaUpgradeScope,
    discId="GC6E01",discRegion="USA",cacheVersion=C.cacheVersion,
    extractionCacheVersion=C.cacheVersion,extractorRevision=C.extractorRevision,
    trainerResolved=tonumber(state.trainer_resolved) or counts.trainers.have,
    trainerTotal=tonumber(state.trainer_total) or 10,
    trainerDiagnostic=state.trainer_diagnostic,
    trainerFirstError=state.trainer_first_error,
    trainerSourceError=state.trainer_source_error,
    sourceAccess=romReady and "VALIDATED / BOUNDED" or "NOT AVAILABLE",
    currentStage=state.current_stage,audioWarning=audioWarning,lastAction=err or audioWarning or state.message or C.lastAction,
    hardCacheReady=exists(HARD_CACHE_MARKER),hardCacheRegistry=GeneratedAssets.registryStatus and GeneratedAssets.registryStatus() or nil,
  }
  inspectMemo=out;inspectMemoAt=now
  return out
end

function C.hardCacheStatus()
  local r=V.ResidentPrewarm
  local hs=r and type(r.status)=="function" and r.status().hardCache or nil
  hs=type(hs)=="table" and hs or {running=false,pending=0,total=0,done=0,failed=0,stage="idle"}
  hs.ready=not hs.running and hs.stage~="failed" and GeneratedAssets.exists(HARD_CACHE_MARKER) and true or false
  hs.needsShinyRefresh=not hs.ready and GeneratedAssets.exists(PREVIOUS_HARD_CACHE_MARKER) or false
  hs.teamReady=GeneratedAssets.exists("build/hard_cache_team_v1.complete") and true or false
  hs.registry=GeneratedAssets.registryStatus and GeneratedAssets.registryStatus() or nil
  return hs
end
function C.hardCacheSave(game,scope)
  scope=scope=="team" and "team" or "full"
  invalidateInspect()
  if not (game and V.ResidentPrewarm and type(V.ResidentPrewarm.queueHardCache)=="function") then
    C.lastAction="Hard Cache Save unavailable until the game runtime is ready.";return false,C.lastAction
  end
  -- The coordinator removes only the selected scope marker, after accepting
  -- the request. A repeated click must not invalidate a job already in progress.
  local ok,n,why=pcall(V.ResidentPrewarm.queueHardCache,game,scope)
  if not ok then C.lastAction="Hard Cache Save failed to queue: "..tostring(n);return false,C.lastAction end
  if why=="already-running" then
    C.lastAction="Cache preparation is already running; its scope and progress were kept."
    return true,C.lastAction
  end
  C.lastAction=("%s queued (%d jobs). Pause/resume in CACHE PREPARATION; existing files are reused."):format(scope=="team" and "Current team" or "Team + PC",tonumber(n) or 0)
  return true,C.lastAction
end

function C.pauseHardCache(value)
  local r=V.ResidentPrewarm
  if not (r and r.pauseHardCache) then return false end
  return r.pauseHardCache(value)
end

local function callReset(name)
  local m=V[name]
  if m and type(m.resetRuntime)=="function" then pcall(m.resetRuntime,m) end
  if m and type(m.invalidate)=="function" then pcall(m.invalidate,m) end
end
function C.resetRuntime()
  invalidateInspect()
  for _,name in ipairs({"ResidentPrewarm","Arena","Trainer","TrainerRoster","PlayerTrainer","CurrentSpriteModels","Transition","Music","StandaloneHost","PokemonActors","WazaHandlers"}) do callReset(name) end
  if GeneratedAssets.invalidateInfo then GeneratedAssets.invalidateInfo() end
  if V.RuntimeMeshCache and type(V.RuntimeMeshCache.invalidateLua)=="function" then V.RuntimeMeshCache.invalidateLua() end
  collectgarbage("collect")
  C.lastAction="Runtime objects cleared. Generated assets reload on next use."
  return true,C.lastAction
end
function C.resetGenerated()
  invalidateInspect()
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
  for _,path in ipairs({".cbe-runtime-v2.complete",".cbe-visual-v2.complete",".cbe-audio-v1.complete",".cbe-audio-portable-v1.complete",".cbe-audio-portable-v2.complete",".cbe-audio-portable-v3.complete",".cbe-audio-portable-v3.pending",".cbe-audio-portable-v4.complete",".cbe-audio-portable-v4.pending","build/audio_portable_v4.complete","build/audio_portable_v4.migrating",".cbe-audio-portable-v5.complete",".cbe-audio-portable-v5.pending","build/audio_portable_v5.complete","build/audio_portable_v5.migrating",".cbe-audio-portable-v6.complete",".cbe-audio-portable-v6.pending","build/audio_portable_v6.complete","build/audio_portable_v6.migrating",".cbe-audio-portable-v7.complete",".cbe-audio-portable-v7.pending","build/audio_portable_v7.complete","build/audio_portable_v7.migrating",".cbe-audio-portable-v9.complete",".cbe-audio-portable-v9.pending","build/audio_portable_v9.complete","build/audio_portable_v9.migrating","build/audio_portable_v9_assets.lua",AUDIO_EXHAUSTED_PATH,".cbe-trainer-identity-v1.complete",".cbe-trainer-identity-v2.complete",".cbe-trainer-identity-v3.complete",".cbe-trainer-identity-v4.complete",".cbe-trainer-identity-v5.complete",".cbe-trainer-identity-v6.complete",".cbe-trainer-identity-v7.complete",".cbe-trainer-identity-v8.complete",".cbe-trainer-identity-v9.complete",".cbe-trainer-identity-v10.complete",".cbe-trainer-identity-v11.complete",".cbe-trainer-identity-v12.complete",".cbe-trainer-identity-v13.complete",".cbe-trainer-identity-v14.complete",".cbe-trainer-identity-v15.complete",".cbe-trainer-identity-v16.complete",".cbe-arena-runtime-sidecars-v2.complete",".cbe-arena-v2.complete",".cbe-arena-v3.complete",".cbe-arena-v4.complete",".cbe-arena-v5.complete",".cbe-arena-v6.complete",".cbe-arena-v7.complete",".cbe-arena-v8.complete",".cbe-arena-v9.complete",".cbe-arena-v10.complete","build/error.txt","build/audio_warning.txt","build/audio_diagnostic.txt","build/audio_portable_report.txt","build/state.txt","build/generated_paths.lua","build/stage_trainers.pending","build/stage_audio.pending"}) do GeneratedAssets.delete(path) end
  for _,id in ipairs(STAGES) do GeneratedAssets.delete("build/stage_"..id..".complete");GeneratedAssets.delete("build/stage_"..id..".pending") end
  GeneratedAssets.delete("build/hard_cache_team_v1.complete")
  GeneratedAssets.delete(HARD_CACHE_MARKER)
  GeneratedAssets.delete(PREVIOUS_HARD_CACHE_MARKER)
  GeneratedAssets.delete(LEGACY_HARD_CACHE_MARKER)
  GeneratedAssets.delete(OLDER_HARD_CACHE_MARKER)
  if GeneratedAssets.clearInfoRegistry then GeneratedAssets.clearInfoRegistry(true) end
  if V.RuntimeMeshCache and type(V.RuntimeMeshCache.invalidateLua)=="function" then V.RuntimeMeshCache.invalidateLua() end
  C.lastAction="Generated CBE runtime cleared. Reload CBE to rebuild from the imported disc."
  return true,C.lastAction
end
function C.status() return C.inspect() end
function C.prettyBytes(n) return prettyBytes(n) end
return C
