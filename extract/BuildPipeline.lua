local V=...
local Disc,FSYS=V.GameCubeDisc,V.FSYS
local ArenaBuilder,TrainerExtractor,TransitionBuilder,AudioProbe=V.ArenaBuilder,V.TrainerExtractor,V.TransitionBuilder,V.AudioProbe
local FormatProbe=V.FormatProbe
local CameraProbe=V.CameraProbe
local MoveFXExtractor=V.MoveFXExtractor
local WazaSfxBuilder=V.WazaSfxBuilder
local LauncherCompat=V.LauncherCompat or {}
local BUILD_VERSION=tostring(V.BuildVersion or "unknown")
local PLATFORM_OS=tostring(V.PlatformOS or "Unknown")
local DIAG_PATH="build/android_storage_diagnostic.txt"
local B={cacheVersion=2,extractorRevision=15}
local function memoryFence()
  if type(collectgarbage)=="function" then pcall(collectgarbage,"collect") end
end
local EXPECTED_MARKER="cbe-runtime=2\nextractor=15\n"
local LEGACY_EXPECTED_MARKER="cbe-runtime=2\nextractor=14\n"
local VISUAL_CORE={
  "cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/M3_shrine_1F_bf_cache.lua","cache/M3_cave_1F_1_bf_cache.lua","cache/S1_out_bf_cache.lua","cache/M2_earth_colo_cache.lua","cache/M4_bottom_colo_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua","cache/D1_labo_B1_bf_cache.lua",
  "cache/trainers/red/model_cache.lua","cache/trainers/leaf/model_cache.lua","cache/trainers/wes/model_cache.lua","cache/trainers/brendan/model_cache.lua","cache/trainers/may/model_cache.lua","cache/trainers/cooltrainer_m/model_cache.lua","cache/trainers/cooltrainer_f/model_cache.lua","cache/trainers/dakim/model_cache.lua","cache/trainers/nascour/model_cache.lua","cache/trainers/miror_b/model_cache.lua","cache/trainers/generic/index.lua",
  "cache/capture/index.lua",
  "assets/transition/wipe_ball00.rgba","assets/transition/wipe_ball01.rgba",
}
local LEGACY_VISUAL_CORE={}
for _,path in ipairs(VISUAL_CORE) do if path~="cache/capture/index.lua" then LEGACY_VISUAL_CORE[#LEGACY_VISUAL_CORE+1]=path end end
local AUDIO_MARKER="cbe-audio=4\nassets=24\nsource=GC6E01\nrenderer=amuse-refresh-v1\n"
local AUDIO_SOURCE_RECOVERY_PATH=".cbe-audio-source-recovery-v1.migrated"
local AUDIO_SOURCE_RECOVERY_MARKER="cbe-audio-source-recovery=3\nbaseline=1.9.12\ncanonical=portable-v9-cross-platform-48k\n"
local MOVEFX_FULL_MARKER="cbe-movefx-full=4\nsource=GC6E01\nmoves=251\nextractor=33\nwaza=12\nruntime=retail-serialized-layout-v12+generator-particle-v15+linked-model-parts-v1\naudio=gamesound-table-v3\n"
local MOVEFX_FULL_PATH=".cbe-movefx-full-v4.complete"
local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-portable=9\nsource=GC6E01\nassets=24\nrate=48000\nrenderer=lua-musyx-canonical-v9-cross-platform-48k\nloop=source-sng-header-plus-region-sentinel\n"
local AUDIO_EXHAUSTED_PATH=".cbe-audio-exhausted-v1.complete"
local AUDIO_EXHAUSTED_MARKER="cbe-audio-exhausted=1\nsource=GC6E01\ncontract=best-effort-all-renderers-v2\nportable=v7-48k\n"
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
-- Only the immediately preceding complete arena contract can use the scoped
-- Relic refresh. Any other difference still requires the full arena repair.
local PREVIOUS_ARENA_MARKER=ARENA_MARKER:gsub("relic%-chamber=[^\n]+",
  "relic-chamber=retail-renderpass-filter+central-overhang-reject+source-half-shell+understory-ground-detail+dapple-light+camera-guard-v4",1)
-- The shipping baseline also predates source TOBJ transforms/color stages.
-- It needs every retail arena refreshed, while retaining unrelated caches.
local LEGACY_ARENA_MARKER=PREVIOUS_ARENA_MARKER:gsub("source%-texture%-state=[^\n]+\n","",1):gsub("source%-instances=[^\n]+\n","",1)
-- The delivered fidelity checkpoint has current UV/color/Relic caches but
-- predates native scene instances. Only Water and Deep contain those objects.
local CHECKPOINT_ARENA_MARKER=ARENA_MARKER:gsub("source%-instances=[^\n]+\n","",1)
local ARENA_CORE={
  "cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/M3_shrine_1F_bf_cache.lua","cache/M3_cave_1F_1_bf_cache.lua","cache/S1_out_bf_cache.lua","cache/M2_earth_colo_cache.lua","cache/M4_bottom_colo_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua","cache/D1_labo_B1_bf_cache.lua",
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
local function call(obj,name,...)
  if not obj or type(obj[name])~="function" then return nil,"unavailable" end
  local ok,a,b=pcall(obj[name],obj,...);if not ok then return nil,tostring(a) end;return a,b
end
local function exists(mod,path)local v=select(1,call(mod.cache,"info",path));return type(v)=="table" and (v.type==nil or v.type=="file")end
local function read(mod,path)local v=select(1,call(mod.cache,"read",path));return type(v)=="string" and v or nil end
local function readLuaTable(mod,path)
  local raw=read(mod,path)
  if not raw then return nil end
  local chunk=load(raw,"@generated/"..tostring(path))
  if not chunk then return nil end
  local ok,value=pcall(chunk)
  return ok and type(value)=="table" and value or nil
end
local function write(mod,path,data,generated)
  local ok,err=call(mod.cache,"write",path,data);assert(ok,err or ("cache write failed: "..path));if generated then generated[#generated+1]=path end
end
local function diagValue(v)
  if v==nil then return "nil" end
  if type(v)=="boolean" then return v and "true" or "false" end
  return tostring(v):gsub("[\r\n]+"," ")
end
local function cacheStorageProbe(mod)
  local path="build/diagnostics/storage_probe/nested/probe.txt"
  local payload="cbe-storage-probe-v1\n"
  local wrote,werr=call(mod.cache,"write",path,payload)
  if wrote~=true then return false,("mod.cache nested write failed [%s]: %s"):format(path,diagValue(werr)) end
  local got,rerr=call(mod.cache,"read",path)
  if type(got)~="string" then
    call(mod.cache,"delete",path)
    return false,("mod.cache nested read failed [%s]: %s"):format(path,diagValue(rerr))
  end
  if got~=payload then
    call(mod.cache,"delete",path)
    return false,("mod.cache readback mismatch [%s]: wrote %d bytes, read %d bytes"):format(path,#payload,#got)
  end
  local info,ierr=call(mod.cache,"info",path)
  if type(info)~="table" then
    call(mod.cache,"delete",path)
    return false,("mod.cache info failed [%s]: %s"):format(path,diagValue(ierr))
  end
  local deleted,derr=call(mod.cache,"delete",path)
  if deleted~=true then return false,("mod.cache delete failed [%s]: %s"):format(path,diagValue(derr)) end
  return true,"nested write/read/info/delete passed"
end
local function importProbe(mod)
  local info,err=call(mod.imports,"info","pokemon_colosseum_usa")
  if type(info)~="table" then return nil,err end
  local bytes,rerr=call(mod.imports,"read","pokemon_colosseum_usa",0,0x440)
  local readOk=type(bytes)=="string" and #bytes==0x440
  return {
    ok=readOk,readError=readOk and nil or rerr,headerBytes=type(bytes)=="string" and #bytes or 0,
    size=info.size,physicalSize=info.physicalSize,logicalSize=info.logicalSize,container=info.container,
    validated=info.validated,normalized=info.normalized,structuralValidated=info.structuralValidated,fstFiles=info.fstFiles,
  }
end
local function diagnosticText(diag)
  local o={
    "cbe_version="..BUILD_VERSION,
    "platform="..PLATFORM_OS,
    "extractor_revision="..tostring(B.extractorRevision),
    "cache_bridge="..diagValue(LauncherCompat.cacheBridge),
    "import_bridge="..diagValue(LauncherCompat.importBridge),
    "native_range_imports="..diagValue(LauncherCompat.nativeRangeImports),
    "mobile_safe="..diagValue(LauncherCompat.mobileSafe),
    "cache_probe="..diagValue(diag.cacheProbe),
    "cache_probe_detail="..diagValue(diag.cacheProbeDetail),
  }
  local imp=diag.importInfo
  if type(imp)=="table" then
    o[#o+1]="import_probe="..(imp.ok and "PASS" or "FAIL")
    o[#o+1]="import_read_error="..diagValue(imp.readError)
    o[#o+1]="import_header_bytes="..diagValue(imp.headerBytes)
    o[#o+1]="import_container="..diagValue(imp.container)
    o[#o+1]="import_size="..diagValue(imp.size)
    o[#o+1]="import_physical_size="..diagValue(imp.physicalSize)
    o[#o+1]="import_logical_size="..diagValue(imp.logicalSize)
    o[#o+1]="import_validated="..diagValue(imp.validated)
    o[#o+1]="import_normalized="..diagValue(imp.normalized)
    o[#o+1]="import_structural_validated="..diagValue(imp.structuralValidated)
    o[#o+1]="import_fst_files="..diagValue(imp.fstFiles)
  else
    o[#o+1]="import_probe=FAIL"
    o[#o+1]="import_read_error="..diagValue(diag.importError)
  end
  o[#o+1]="current_stage="..diagValue(diag.stage)
  o[#o+1]="last_error="..diagValue(diag.error)
  o[#o+1]="diagnostic_path="..DIAG_PATH
  return table.concat(o,"\n").."\n"
end
local function writeDiagnostic(mod,diag)
  local ok,err=call(mod.cache,"write",DIAG_PATH,diagnosticText(diag))
  return ok==true,err
end
local function del(mod,path)call(mod.cache,"delete",path)end
local function luaList(paths)local o={"return {\n"};for _,p in ipairs(paths)do o[#o+1]=string.format("%q,\n",p)end;o[#o+1]="}\n";return table.concat(o)end
local function stateText(s)
  local keys={"cache_version","extractor_revision","current_stage","message","disc_id","disc_region","source_size","fst_files","fsys_files","source_fingerprint","visual_ready","movefx_ready","movefx_source_ready","movefx_source_total","movefx_full_visual_ready","movefx_sfx_ready","movefx_sfx_total","audio_ready","audio_exhausted","portable_audio_ready","trainer_resolved","trainer_total","trainer_diagnostic","trainer_first_error","trainer_source_error"}
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
local function captureSourceReady(mod)
  local idx=readLuaTable(mod,"cache/capture/index.lua")
  -- Revision 6 separates structural capture-bank readiness from source
  -- completeness. A missing optional ball model may use an explicit fallback,
  -- but can no longer make the entire generated CBE runtime unusable.
  if type(idx)~="table" or tonumber(idx.revision)~=6 or idx.ready~=true then return false end
  for _,id in ipairs({"poke","great","ultra","master","safari","net","nest","repeatball","timer","dive","premier","luxury"}) do
    local row=idx.balls and idx.balls[id]
    if not (type(row)=="table" and type(row.phases)=="table") then return false end
    if row.sourceReady==true then
      if row.fallback==true or row.staticSource~=true then return false end
    elseif row.fallback~=true then return false end
  end
  return true
end
local function trainerIdentityReady(mod)
  return read(mod,".cbe-trainer-identity-v16.complete")==TRAINER_IDENTITY_MARKER
end
local function arenaFilesReady(mod)
  for _,path in ipairs(ARENA_CORE) do
    if not exists(mod,path) then return false end
  end
  return true
end
local function arenaReady(mod)
  return read(mod,".cbe-arena-v10.complete")==ARENA_MARKER and arenaFilesReady(mod)
end
local function relicRepairBaseReady(mod)
  local arenaMarker=read(mod,".cbe-arena-v10.complete")
  if (arenaMarker~=PREVIOUS_ARENA_MARKER and arenaMarker~=LEGACY_ARENA_MARKER and arenaMarker~=CHECKPOINT_ARENA_MARKER)
      or read(mod,".cbe-visual-v2.complete")~=EXPECTED_MARKER then return false end
  -- An interrupted/missing arena cache must select the full arena repair,
  -- without falling through to global cleanup of healthy actors and audio.
  local arenaPaths={};for _,path in ipairs(ARENA_CORE) do arenaPaths[path]=true end
  for _,path in ipairs(VISUAL_CORE) do if not arenaPaths[path] and not exists(mod,path) then return false end end
  return true
end
local function arenaRuntimeSidecarsReady(mod)
  return read(mod,ARENA_RUNTIME_SIDECAR_PATH)==ARENA_RUNTIME_SIDECAR_MARKER
end
local function visualReady(mod)
  return baseVisualReady(mod) and trainerIdentityReady(mod) and arenaReady(mod) and arenaRuntimeSidecarsReady(mod) and captureSourceReady(mod)
end
local function moveFxReady(mod,allowPartial)
  if read(mod,MOVEFX_FULL_PATH)~=MOVEFX_FULL_MARKER then
    if not allowPartial or not exists(mod,"build/stage_movefx.complete") then return false end
  end
  if not exists(mod,"cache/movefx/index.lua") or not exists(mod,"build/movefx_coverage.txt") then return false end
  local index=readLuaTable(mod,"cache/movefx/index.lua")
  if type(index)~="table" or tonumber(index.revision)~=(MoveFXExtractor and MoveFXExtractor.revision or 33) or tonumber(index.wazaRevision)~=(V.WazaSequenceExtractor and V.WazaSequenceExtractor.revision or 12)
      or tonumber(index.total)~=251 or tonumber(index.ready)~=251 or (not allowPartial and tonumber(index.fullVisualReady)~=251) or tonumber(index.missing)~=0
      or type(index.moves)~="table" then return false end
  for id=1,251 do
    local row=index.moves[id]
    if type(row)~="table" or row.missing==true or not row.stem or (not allowPartial and row.fullVisualReady~=true) then return false end
    if allowPartial and not exists(mod,"cache/movefx/"..row.stem.."/effect.lua") then return false end
  end
  if not (WazaSfxBuilder and type(WazaSfxBuilder.ready)=="function") then return false end
  local ok,ready=pcall(WazaSfxBuilder.ready,mod)
  return ok and ready==true
end

local function audioReady(mod)
  if read(mod,AUDIO_SOURCE_RECOVERY_PATH)~=AUDIO_SOURCE_RECOVERY_MARKER then return false end
  local canonical=false
  if AudioProbe and type(AudioProbe.portableFullReady)=="function" then
    local ok,ready=pcall(AudioProbe.portableFullReady,mod);canonical=ok and ready==true
  else
    canonical=read(mod,".cbe-audio-portable-v9.complete")==PORTABLE_AUDIO_FULL_MARKER
      or read(mod,"build/audio_portable_v9.complete")==PORTABLE_AUDIO_FULL_MARKER
  end
  if not canonical then return false end
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
local arenasOnly,trainersOnly,moveFxOnly,captureOnly,sidecarsOnly
local function audioPlatformSupported()
  if AudioProbe and type(AudioProbe.platformSupported)=="function" then
    local ok,supported,osName=pcall(AudioProbe.platformSupported)
    if ok then return supported~=false,osName end
  end
  return true,"unknown"
end

local AUDIO_DIAGNOSTIC_PATH="build/audio_diagnostic.txt"
local BROKEN_CANONICAL_V8_MARKERS={
  ".cbe-audio-canonical-v8.complete",".cbe-audio-canonical-v8.pending",
  "build/audio_canonical_v8.complete","build/audio_canonical_v8.migrating",
}
local function enforceSourceRecoveryAudio(mod,progress,generated)
  if read(mod,AUDIO_SOURCE_RECOVERY_PATH)==AUDIO_SOURCE_RECOVERY_MARKER then return false end
  if progress then progress("AUDIO / clean 1.9.12 canonical cross-platform migration",0,24) end
  -- Never trust soundtrack WAVs from an older renderer contract. Previous builds
  -- could produce Amuse WAVs on Windows and Portable MusyX WAVs elsewhere (or a
  -- mixed set after a failed Windows primary). Purge all 24 outputs exactly once,
  -- then regenerate every platform from the same GC6E01 Portable MusyX contract.
  for _,path in ipairs(AUDIO_CORE) do del(mod,path) end
  for _,path in ipairs({
    ".cbe-audio-v1.complete",
    ".cbe-audio-portable-v1.complete",
    ".cbe-audio-portable-v2.complete",
    ".cbe-audio-portable-v3.complete",".cbe-audio-portable-v3.pending",
    ".cbe-audio-portable-v4.complete",".cbe-audio-portable-v4.pending",
    "build/audio_portable_v4.complete","build/audio_portable_v4.migrating",
    ".cbe-audio-portable-v5.complete",".cbe-audio-portable-v5.pending",
    "build/audio_portable_v5.complete","build/audio_portable_v5.migrating",
    ".cbe-audio-portable-v6.complete",".cbe-audio-portable-v6.pending",
    "build/audio_portable_v6.complete","build/audio_portable_v6.migrating",
    ".cbe-audio-portable-v7.complete",".cbe-audio-portable-v7.pending",
    "build/audio_portable_v7.complete","build/audio_portable_v7.migrating",
    ".cbe-audio-portable-v9.complete",".cbe-audio-portable-v9.pending",
    "build/audio_portable_v9.complete","build/audio_portable_v9.migrating",
    "build/audio_portable_v9_assets.lua",
    AUDIO_EXHAUSTED_PATH,
    "build/audio_warning.txt","build/audio_diagnostic.txt","build/audio_portable_report.txt",
    "build/audio_canonical_report.txt","build/audio_source_manifest.txt",
  }) do del(mod,path) end
  for _,path in ipairs(BROKEN_CANONICAL_V8_MARKERS) do del(mod,path) end
  write(mod,AUDIO_SOURCE_RECOVERY_PATH,AUDIO_SOURCE_RECOVERY_MARKER,generated)
  return true
end
local function audioDiagnostic(mod,osName,renderErr,generated)
  local rows={
    "cbe_version="..BUILD_VERSION,
    "platform="..tostring(osName or PLATFORM_OS),
    "required_assets=24",
    "audio_contract=canonical-v9-cross-platform-48k",
    "authoritative_renderer=lua-musyx-canonical-v9-cross-platform-48k",
    "render_error="..diagValue(renderErr),
  }
  pcall(function()write(mod,AUDIO_DIAGNOSTIC_PATH,table.concat(rows,"\n").."\n",generated)end)
end
local function attemptRequiredAudio(mod,disc,progress,generated)
  enforceSourceRecoveryAudio(mod,progress,generated)
  local _,osName=audioPlatformSupported()
  -- One renderer owns the runtime cache on every platform. Windows Amuse is no
  -- longer a production-output branch: renderer selection by OS was itself a
  -- parity bug because the same GC6E01 source could yield different WAVs.
  local okCanonical,canonical=pcall(AudioProbe.runPortableFull,mod,disc,progress,generated)
  if okCanonical and canonical and canonical.ready and tonumber(canonical.complete)==24 then
    del(mod,".cbe-audio-v1.complete")
    del(mod,AUDIO_DIAGNOSTIC_PATH)
    return {ready=true,portable=true,canonical=true,result=canonical,osName=osName}
  end
  local renderErr=tostring(canonical or "canonical Portable MusyX renderer returned an incomplete cache")
  audioDiagnostic(mod,osName,renderErr,generated)
  return nil,renderErr,osName
end

local function audioRequiredFailure(mod,state,generated,message,why,osName)
  state.current_stage="audio_required_failed";state.audio_ready=0;state.audio_exhausted=0
  state.message=message or "Required GC6E01 audio cache is incomplete; CBE runtime withheld until retry succeeds"
  del(mod,AUDIO_EXHAUSTED_PATH);del(mod,".cbe-runtime-v2.complete")
  pcall(function()write(mod,"build/audio_warning.txt",state.message.."\n"..tostring(why or "").."\n",generated)end)
  pcall(function()write(mod,"build/error.txt",state.message.."\n"..tostring(why or "").."\n",generated)end)
  return {state="AUDIO REQUIRED / RETRY",runtimeReady=false,visualReady=true,audioReady=false,audioExhausted=false,audioUnavailable=true,
    message=state.message,diagnosticPath=AUDIO_DIAGNOSTIC_PATH,osName=osName}
end

local function audioOnly(mod,progress,forceAttempt)
  local generated=previousGenerated(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="audio",message="Building required canonical Colosseum audio cache",disc_id="GC6E01",
    disc_region="USA",visual_ready=1,audio_ready=0,audio_exhausted=0}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/audio_warning.txt");del(mod,"build/stage_audio.pending");del(mod,".cbe-runtime-v2.complete");del(mod,AUDIO_EXHAUSTED_PATH)
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    local audio,why,osName=attemptRequiredAudio(mod,disc,progress,generated)
    if not (audio and audio.ready) then
      local failed=audioRequiredFailure(mod,state,generated,
        "Required Colosseum soundtrack cache failed; visual cache retained, CBE runtime withheld until audio retry succeeds",
        why,osName)
      pcall(function()pending(mod,"audio","required canonical renderer incomplete; retry required",generated)end)
      save();finishManifest(mod,generated)
      return failed
    end
    stage(mod,"audio",generated)
    stage(mod,"audio_portable",generated);state.portable_audio_ready=1;del(mod,".cbe-audio-v1.complete")
    state.audio_ready=1;state.audio_exhausted=0;state.current_stage="ready"
    state.message=("Runtime ready; canonical GC6E01 soundtrack cache 24/24 generated with the same renderer on %s"):format(tostring(audio.osName or osName or "this platform"))
    del(mod,"build/audio_warning.txt");del(mod,"build/error.txt");del(mod,AUDIO_EXHAUSTED_PATH)
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    save();finishManifest(mod,generated)
    return {state="READY",runtimeReady=true,visualReady=true,audioReady=true,audioExhausted=false,portableAudioReady=audio.portable==true,message=state.message,audioPrimaryError=nil,diagnosticPath=nil}
  end)
  if ok then return result end
  local msg=tostring(result)
  -- Reaching this branch means the audio-attempt controller itself failed before
  -- it could exhaust its renderer list (for example source/cache access vanished).
  -- The visual runtime still survives, but do not falsely stamp "all renderers failed".
  state.current_stage="audio_controller_failed";state.audio_ready=0;state.audio_exhausted=0;state.message="Audio extraction controller failed before canonical renderer completed: "..msg
  del(mod,".cbe-runtime-v2.complete");del(mod,AUDIO_EXHAUSTED_PATH)
  pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
  pcall(function()write(mod,"build/error.txt",state.message.."\n",nil)end)
  pcall(function()pending(mod,"audio",state.message,nil)end)
  pcall(function()finishManifest(mod,generated)end)
  return {state="AUDIO CONTROLLER FAILED",runtimeReady=false,visualReady=true,audioReady=false,audioExhausted=false,audioUnavailable=true,message=state.message,diagnosticPath=AUDIO_DIAGNOSTIC_PATH}
end

-- Focused capture-bank migration. 1.8.4 resolves retail balls from complete
-- snatch member HSD roots first and keeps arenas, trainers, all 251 MoveFX banks and audio
-- intact and rebuild just cache/capture from the already validated import.
captureOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="capture",message="Rebuilding decoded-HSD Colosseum capture-ball bank",disc_id="GC6E01",
    disc_region="USA",visual_ready=0,audio_ready=hadAudio and 1 or 0}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/stage_capture.pending");save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    local capture,captureErr=MoveFXExtractor.extractCaptureAssets(mod,disc,progress,generated)
    assert(capture and capture.ready,
      captureErr or (capture and capture.message) or "capture bank generation failed")
    assert(captureSourceReady(mod),"capture bank validation failed after extraction")
    stage(mod,"capture",generated)
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=1;state.current_stage=hadAudio and "ready" or "audio"
    state.message=("Runtime ready; Colosseum capture bank generated (%s/12 retail HSD source, %s explicit fallback)"):format(
      tostring(capture and capture.sourceReady or 0),tostring(capture and capture.fallbackBalls or 0))
    if hadAudio then write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated) end
    save();finishManifest(mod,generated)
    return {state=hadAudio and "READY" or "VISUAL READY / AUDIO PENDING",visualReady=true,audioReady=hadAudio,
      captureSourceReady=capture and capture.sourceReady or 0,captureFallback=capture and capture.fallbackBalls or 0,message=state.message}
  end)
  if ok then if hadAudio then return result else return audioOnly(mod,progress,true) end end
  local msg=tostring(result);pending(mod,"capture",msg,generated);state.current_stage="failed_capture";state.message=msg;save();finishManifest(mod,generated)
  return {state="FAILED / CAPTURE SOURCE",visualReady=false,audioReady=hadAudio,message=msg,diagnosticPath="build/capture_source.txt"}
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
    if not arenaRuntimeSidecarsReady(mod) then
      state.message="Packing arena runtime sidecars for first-entry scene loads";save()
      assert(ArenaBuilder and type(ArenaBuilder.runtimeSidecars)=="function","arena runtime sidecar builder unavailable")
      local sidecars=ArenaBuilder.runtimeSidecars(mod,progress,generated);assert(sidecars and sidecars.ready,"arena runtime sidecar build incomplete")
      write(mod,ARENA_RUNTIME_SIDECAR_PATH,ARENA_RUNTIME_SIDECAR_MARKER,generated)
    end
    stage(mod,"trainers",generated)
    write(mod,".cbe-trainer-identity-v16.complete",TRAINER_IDENTITY_MARKER,generated)
    for i=1,15 do del(mod,(".cbe-trainer-identity-v%d.complete"):format(i)) end
    if not captureSourceReady(mod) then
      state.current_stage="capture";state.message="Compiling native Colosseum capture balls from snatch_* source";save()
      assert(MoveFXExtractor and type(MoveFXExtractor.extractCaptureAssets)=="function","capture source extractor unavailable")
      local captureResult,captureErr=MoveFXExtractor.extractCaptureAssets(mod,disc,progress,generated)
      assert(captureResult and captureResult.ready,captureErr or (captureResult and captureResult.message) or "native capture source cache incomplete")
      stage(mod,"capture",generated)
    end
    for _,path in ipairs(VISUAL_CORE) do assert(exists(mod,path),"generated visual runtime missing: "..path) end
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=1
    if hadAudio then
      state.current_stage="ready";state.message="Runtime ready; trainer cache rebuilt; native capture-bank ready; generated audio cache reused"
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    else
      state.current_stage="audio";state.message="Trainer cache rebuilt; native capture-bank ready; generated audio cache pending"
    end
    save();finishManifest(mod,generated)
    return {state=hadAudio and "READY" or "VISUAL READY / AUDIO PENDING",visualReady=true,audioReady=hadAudio,
      trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
  end)
  if ok then
    if not arenaReady(mod) then return arenasOnly(mod,progress) end
    if not hadAudio then return audioOnly(mod,progress,true) end
    return result
  end
  local msg=tostring(result)
  state.current_stage="trainer_identity_failed";state.message=msg
  pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
  pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
  pending(mod,"trainers",msg,nil)
  del(mod,".cbe-trainer-identity-v16.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="TRAINER CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,
    trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,
    trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg}
end

-- Arena-only migration. The exact preceding complete contract needs only
-- Relic; older/incomplete arena caches use the full source-venue repair.
-- Wildlands and all trainer, transition, MoveFX and audio caches stay reusable.
-- This is intentionally independent from the global extractor revision.
arenasOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local hadTrainers=trainerIdentityReady(mod)
  local priorArenaMarker=read(mod,".cbe-arena-v10.complete")
  local preservePrevious=priorArenaMarker==PREVIOUS_ARENA_MARKER or priorArenaMarker==LEGACY_ARENA_MARKER or priorArenaMarker==CHECKPOINT_ARENA_MARKER
  local scope
  if arenaFilesReady(mod) then
    if priorArenaMarker==PREVIOUS_ARENA_MARKER then scope="relic-scenes"
    elseif priorArenaMarker==CHECKPOINT_ARENA_MARKER then scope="source-instances" end
  end
  local refreshMessage=scope=="source-instances" and "Refreshing Water and Deep source crowd instances; other arenas retained"
    or (scope and "Refreshing Relic Chamber and Relic Cave source fidelity; other arenas retained" or "Refreshing source arena fidelity: native texture transforms, material colors and scene instances")
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="arenas",message=refreshMessage,disc_id="GC6E01",disc_region="USA",
    visual_ready=0,audio_ready=hadAudio and 1 or 0,trainer_resolved=hadTrainers and 10 or 0,trainer_total=10}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/stage_arenas.pending");del(mod,".cbe-runtime-v2.complete");del(mod,ARENA_RUNTIME_SIDECAR_PATH);del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete");del(mod,".cbe-arena-v4.complete");del(mod,".cbe-arena-v5.complete");del(mod,".cbe-arena-v6.complete");del(mod,".cbe-arena-v7.complete");del(mod,".cbe-arena-v8.complete");del(mod,".cbe-arena-v9.complete")
  -- The previous marker already fails arenaReady. Retain it until commit so
  -- cancellation, process exit or a failed write can retry the same scope.
  if not preservePrevious then del(mod,".cbe-arena-v10.complete") end
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    if type(ArenaBuilder.repair)=="function" then ArenaBuilder.repair(mod,disc,progress,generated,{scope=scope})
    else ArenaBuilder.run(mod,disc,progress,generated) end
    assert(ArenaBuilder and type(ArenaBuilder.runtimeSidecars)=="function","arena runtime sidecar builder unavailable")
    local sidecars=ArenaBuilder.runtimeSidecars(mod,progress,generated);assert(sidecars and sidecars.ready,"arena runtime sidecar build incomplete")
    write(mod,ARENA_RUNTIME_SIDECAR_PATH,ARENA_RUNTIME_SIDECAR_MARKER,generated)
    stage(mod,"arenas",generated)
    write(mod,".cbe-arena-v10.complete",ARENA_MARKER,generated);del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete");del(mod,".cbe-arena-v4.complete");del(mod,".cbe-arena-v5.complete");del(mod,".cbe-arena-v6.complete");del(mod,".cbe-arena-v7.complete");del(mod,".cbe-arena-v8.complete")
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=hadTrainers and 1 or 0
    local refreshed=scope=="source-instances" and "Water and Deep source scene instances"
      or (scope and "Relic Chamber and Relic Cave source fidelity" or "Arena source fidelity")
    if hadTrainers and hadAudio then
      state.current_stage="ready";state.message="Runtime ready; "..refreshed.." refreshed; trainer/MoveFX/audio caches reused"
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    elseif hadTrainers then
      state.current_stage="audio";state.message=refreshed.." refresh complete; generated audio cache pending"
    else
      state.current_stage="trainers";state.message=refreshed.." refresh complete; exact trainer cache pending"
    end
    save();finishManifest(mod,generated)
    return {state=(hadTrainers and hadAudio) and "READY" or (hadTrainers and "VISUAL READY / AUDIO PENDING" or "ARENAS READY / TRAINERS PENDING"),
      visualReady=hadTrainers,audioReady=hadAudio,message=state.message}
  end)
  if ok then
    if not hadTrainers then return trainersOnly(mod,progress) end
    if not hadAudio then return audioOnly(mod,progress,true) end
    return result
  end
  local msg=tostring(result)
  state.current_stage="arena_repair_failed";state.message=msg
  pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
  pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
  pending(mod,"arenas",msg,nil)
  if preservePrevious then
    -- A failure after the marker write is also retryable. Before that write,
    -- leaving the old marker untouched is sufficient even on abrupt exit.
    if read(mod,".cbe-arena-v10.complete")~=priorArenaMarker then
      pcall(function()write(mod,".cbe-arena-v10.complete",priorArenaMarker,nil)end)
    end
  else del(mod,".cbe-arena-v10.complete") end
  del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="ARENA CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,message=msg}
end

-- One-time cache promotion for installs whose canonical arena caches predate
-- build-time runtime sidecars. No disc/HSD extraction is repeated: each source
-- cache is parsed once here, packed, then future scene loads bypass it.
sidecarsOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,current_stage="arena_runtime_sidecars",
    message="Packing existing arena caches for first-entry scene loads",disc_id="GC6E01",disc_region="USA",visual_ready=0,audio_ready=hadAudio and 1 or 0}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,ARENA_RUNTIME_SIDECAR_PATH);del(mod,".cbe-runtime-v2.complete");save()
  local ok,result=pcall(function()
    assert(ArenaBuilder and type(ArenaBuilder.runtimeSidecars)=="function","arena runtime sidecar builder unavailable")
    local r=ArenaBuilder.runtimeSidecars(mod,progress,generated);assert(r and r.ready,"arena runtime sidecar build incomplete")
    write(mod,ARENA_RUNTIME_SIDECAR_PATH,ARENA_RUNTIME_SIDECAR_MARKER,generated)
    state.visual_ready=1;state.current_stage=hadAudio and "ready" or "audio"
    state.message=("Arena runtime cache ready (%d packed, %d reused); first-entry source-Lua parse removed"):format(tonumber(r.built) or 0,tonumber(r.reused) or 0)
    if hadAudio then write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated) end
    save();finishManifest(mod,generated)
    return {state=hadAudio and "READY" or "VISUAL READY / AUDIO PENDING",runtimeReady=hadAudio,visualReady=true,audioReady=hadAudio,message=state.message}
  end)
  if ok then if not hadAudio then return audioOnly(mod,progress,true) end;return result end
  local msg=tostring(result);state.current_stage="arena_runtime_sidecars_failed";state.message=msg;pcall(save);pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end);del(mod,ARENA_RUNTIME_SIDECAR_PATH);del(mod,".cbe-runtime-v2.complete");pcall(function()finishManifest(mod,generated)end)
  return {state="ARENA RUNTIME CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,message=msg}
end

-- Full 251-move migration.  This is deliberately independent from arena,
-- trainer and soundtrack markers: 1.7.11 can add the complete WZX + GameSound
-- cache to an existing 1.7.10 installation without touching the expensive
-- caches that already work.  Once the marker/index/WAV set validates, later
-- launches are zero-disc-I/O just like the soundtrack cache.
moveFxOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="movefx",message="Building complete 251-move Colosseum Waza cache",disc_id="GC6E01",disc_region="USA",
    visual_ready=1,movefx_ready=0,audio_ready=hadAudio and 1 or 0}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/movefx_warning.txt");del(mod,MOVEFX_FULL_PATH);del(mod,".cbe-movefx-full-v3.complete");del(mod,".cbe-movefx-full-v2.complete");del(mod,".cbe-movefx-full-v1.complete")
  if WazaSfxBuilder and WazaSfxBuilder.markerPath then del(mod,WazaSfxBuilder.markerPath) end
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    assert(MoveFXExtractor and type(MoveFXExtractor.extractAllMoves)=="function","full MoveFX extractor unavailable")
    progress("MOVEFX FULL CACHE / 251 MOVES",0,2)
    local fx=MoveFXExtractor.extractAllMoves(mod,disc,progress,generated)
    assert(fx and fx.ready and tonumber(fx.sourceReady)==251 and tonumber(fx.missing)==0,
      ("complete MoveFX bank scan failed (%s/251 ready, %s missing)"):format(
        tostring(fx and fx.sourceReady or 0),tostring(fx and fx.missing or "?")))
    local fullVisual=fx.fullVisualReady==true and tonumber(fx.fullVisualCount)==251
    state.movefx_source_ready=tonumber(fx.sourceReady) or 0;state.movefx_source_total=tonumber(fx.total) or 251;state.movefx_full_visual_ready=tonumber(fx.fullVisualCount) or 0
    if not fullVisual then
      write(mod,"build/movefx_warning.txt",("MoveFX executable-chain audit incomplete (%s/251); source cache retained and audio extraction continues. See build/movefx_coverage.txt\n"):format(tostring(fx and fx.fullVisualCount or 0)),generated)
    end
    state.current_stage="move_audio";state.message=("Rendering %d unique retail Waza GameSound IDs"):format(#(fx.soundIds or {}));save()
    assert(WazaSfxBuilder and type(WazaSfxBuilder.run)=="function","Waza GameSound cache builder unavailable")
    local audio=WazaSfxBuilder.run(mod,disc,WazaSfxBuilder.withReleaseSounds(fx.soundIds),progress,generated)
    assert(audio and audio.ready,"Waza GameSound cache incomplete")
    state.movefx_sfx_ready=tonumber(audio.complete) or 0;state.movefx_sfx_total=tonumber(audio.total) or 0
    if fullVisual then write(mod,MOVEFX_FULL_PATH,MOVEFX_FULL_MARKER,generated) else del(mod,MOVEFX_FULL_PATH) end
    del(mod,".cbe-movefx-full-v3.complete");del(mod,".cbe-movefx-full-v2.complete");del(mod,".cbe-movefx-full-v1.complete");stage(mod,"movefx",generated)
    state.movefx_ready=fullVisual and 1 or 0;state.current_stage=fullVisual and "ready" or "movefx_partial"
    state.message=("Runtime ready; Waza source %d/%d, executable visual chains %d/%d, GameSound %d/%d cached"):format(
      state.movefx_source_ready,state.movefx_source_total,state.movefx_full_visual_ready,state.movefx_source_total,state.movefx_sfx_ready,state.movefx_sfx_total)
    if not fullVisual then state.message=state.message.."; visual chains remain pending (see build/movefx_coverage.txt)" end
    save();finishManifest(mod,generated)
    return {state=fullVisual and "READY" or "READY / MOVEFX VISUAL PENDING",visualReady=true,moveFxReady=fullVisual,audioReady=hadAudio,
      moveFxSourceReady=state.movefx_source_ready,moveFxSourceTotal=state.movefx_source_total,moveFxFullVisualReady=state.movefx_full_visual_ready,
      moveFxSfxReady=state.movefx_sfx_ready,moveFxSfxTotal=state.movefx_sfx_total,message=state.message}
  end)
  if not ok then
    local msg=tostring(result);state.current_stage="movefx_failed";state.message=msg
    pcall(function()write(mod,"build/movefx_warning.txt",msg.."\n",generated)end);save();finishManifest(mod,generated)
    return {state="READY / MOVEFX CACHE PENDING",visualReady=true,moveFxReady=false,audioReady=hadAudio,message=msg}
  end
  if not hadAudio then return audioOnly(mod,progress,true) end
  return result
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
  local diag={stage="startup",error=nil}
  local cacheOK,cacheDetail=cacheStorageProbe(mod)
  diag.cacheProbe=cacheOK and "PASS" or "FAIL";diag.cacheProbeDetail=cacheDetail
  local importInfo,importErr=importProbe(mod);diag.importInfo=importInfo;diag.importError=importErr
  writeDiagnostic(mod,diag)
  if not cacheOK then
    local msg=cacheDetail.."; CBE generated cache is not writable/readable on this Android filesystem"
    diag.error=msg;writeDiagnostic(mod,diag)
    return {state="FAILED",visualReady=false,audioReady=false,message=msg,diagnosticPath=DIAG_PATH,storageDiagnostic=true}
  end
  if not (importInfo and importInfo.ok) then
    local msg=("mod.imports bounded source read failed: %s"):format(diagValue((importInfo and importInfo.readError) or importErr))
    diag.error=msg;writeDiagnostic(mod,diag)
    return {state="FAILED",visualReady=false,audioReady=false,message=msg,diagnosticPath=DIAG_PATH,storageDiagnostic=true}
  end
  pcall(B.ensureFormatProbe,mod,progress,false)
  -- Independent one-cue migration: never invalidate the 24-asset soundtrack.
  if MoveFXExtractor and MoveFXExtractor.ensureReleaseBanks then
    local ok,why=pcall(function()
      local paths=previousGenerated(mod);local disc
      MoveFXExtractor.ensureReleaseBanks(mod,function() disc=disc or Disc.open(mod);return disc end,progress,paths)
      if V.WazaSfxBuilder and V.WazaSfxBuilder.ensureReleaseAudio then
        V.WazaSfxBuilder.ensureReleaseAudio(mod,function() disc=disc or Disc.open(mod);return disc end,progress,paths)
      end
      finishManifest(mod,paths)
    end)
    if not ok then write(mod,"build/ball_release_warning.txt",tostring(why),nil) end
  end
  if AudioProbe and AudioProbe.runBossIntro then
    local ok,why=pcall(function()
      if not AudioProbe.bossIntroReady(mod) then
        local paths=previousGenerated(mod)
        AudioProbe.runBossIntro(mod,Disc.open(mod),progress,paths)
        finishManifest(mod,paths)
      end
    end)
    if not ok then write(mod,"build/boss_intro_warning.txt",tostring(why),nil) end
  end
  -- Incremental migration: keep expensive arena/transition caches and rebuild
  -- only stale trainer topology/native capture data; audio repairs separately
  -- when its marker changes (1.5.65 bumps it for PCM16 me_snatch).
  if legacyBaseVisualReady(mod) and arenaReady(mod) then
    return trainersOnly(mod,progress)
  end
  if (baseVisualReady(mod) or relicRepairBaseReady(mod)) and trainerIdentityReady(mod) and not arenaReady(mod) then
    return arenasOnly(mod,progress)
  end
  if baseVisualReady(mod) and not trainerIdentityReady(mod) then
    return trainersOnly(mod,progress)
  end
  if baseVisualReady(mod) and trainerIdentityReady(mod) and arenaReady(mod) and not captureSourceReady(mod) then
    return captureOnly(mod,progress)
  end
  if baseVisualReady(mod) and trainerIdentityReady(mod) and arenaReady(mod) and captureSourceReady(mod) and not arenaRuntimeSidecarsReady(mod) then
    return sidecarsOnly(mod,progress)
  end
  if visualReady(mod) and not moveFxReady(mod,true) then
    return moveFxOnly(mod,progress)
  end
  if visualReady(mod) then
    if audioReady(mod) then
      del(mod,AUDIO_EXHAUSTED_PATH)
      return {state="READY",runtimeReady=true,visualReady=true,audioReady=true,audioExhausted=false,message="Persistent generated runtime already present; audio cache reused."}
    end
    -- A matching exhausted marker proves this exact build already tried every
    -- renderer available on this platform. Do not impose that expensive failure
    -- loop every boot; any real cache-repair/rebuild below forces a fresh attempt.
    return audioOnly(mod,progress,false)
  end

  cleanupPrevious(mod)
  for _,p in ipairs({".cbe-runtime-v2.complete",".cbe-visual-v2.complete",".cbe-movefx-full-v1.complete",".cbe-movefx-full-v2.complete",".cbe-movefx-full-v3.complete",MOVEFX_FULL_PATH,".cbe-waza-sfx-v1.complete","build/waza_sfx_v1.complete",".cbe-audio-v1.complete",".cbe-audio-portable-v1.complete",".cbe-audio-portable-v2.complete",".cbe-audio-portable-v3.complete",".cbe-audio-portable-v3.pending",".cbe-audio-portable-v4.complete",".cbe-audio-portable-v4.pending","build/audio_portable_v4.complete","build/audio_portable_v4.migrating",".cbe-audio-portable-v5.complete",".cbe-audio-portable-v5.pending","build/audio_portable_v5.complete","build/audio_portable_v5.migrating",".cbe-audio-portable-v6.complete",".cbe-audio-portable-v6.pending","build/audio_portable_v6.complete","build/audio_portable_v6.migrating",".cbe-audio-portable-v7.complete",".cbe-audio-portable-v7.pending","build/audio_portable_v7.complete","build/audio_portable_v7.migrating",".cbe-audio-portable-v9.complete",".cbe-audio-portable-v9.pending","build/audio_portable_v9.complete","build/audio_portable_v9.migrating","build/audio_portable_v9_assets.lua",".cbe-audio-canonical-v8.complete",".cbe-audio-canonical-v8.pending","build/audio_canonical_v8.complete","build/audio_canonical_v8.migrating","build/audio_canonical_report.txt","build/audio_source_manifest.txt",AUDIO_EXHAUSTED_PATH,".cbe-trainer-identity-v1.complete",".cbe-trainer-identity-v2.complete",".cbe-trainer-identity-v3.complete",".cbe-trainer-identity-v4.complete",".cbe-trainer-identity-v5.complete",".cbe-trainer-identity-v6.complete",".cbe-trainer-identity-v7.complete",".cbe-trainer-identity-v8.complete",".cbe-trainer-identity-v9.complete",".cbe-trainer-identity-v10.complete",".cbe-trainer-identity-v11.complete",".cbe-trainer-identity-v12.complete",".cbe-trainer-identity-v13.complete",".cbe-trainer-identity-v14.complete",".cbe-trainer-identity-v15.complete",".cbe-trainer-identity-v16.complete",ARENA_RUNTIME_SIDECAR_PATH,".cbe-arena-v2.complete",".cbe-arena-v3.complete",".cbe-arena-v4.complete",".cbe-arena-v5.complete",".cbe-arena-v6.complete",".cbe-arena-v7.complete",".cbe-arena-v8.complete",".cbe-arena-v9.complete",".cbe-arena-v10.complete","build/error.txt","build/audio_warning.txt","build/audio_diagnostic.txt","build/audio_portable_report.txt","build/stage_trainers.pending","build/stage_audio.pending"})do del(mod,p)end
  local generated={}
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,current_stage="disc",message="Opening validated GC6E01 source",disc_id="GC6E01",disc_region="USA",visual_ready=0,movefx_ready=0,audio_ready=0,trainer_resolved=0,trainer_total=10,trainer_diagnostic="build/trainer_scan.txt"}
  diag.stage=state.current_stage;writeDiagnostic(mod,diag)
  local function saveState()
    diag.stage=state.current_stage;writeDiagnostic(mod,diag)
    write(mod,"build/state.txt",stateText(state),generated)
  end
  local function update(label,current,total)progress(label,current,total)end
  local ok,result=pcall(function()
    update("DISC / FST",0,9)
    local disc=Disc.open(mod)
    state.source_size=disc.info.size;state.fst_files=#disc.files;state.source_fingerprint=("GC6E01:%d:%d:%d"):format(disc.info.size,disc.fstOffset,disc.fstSize)
    write(mod,"build/disc_index.lua",Disc.serializeIndex(disc),generated)
    state.message="GameCube FST indexed";saveState();stage(mod,"disc",generated)

    state.current_stage="fsys";state.message="Validating Colosseum FSYS archives";saveState();update("FSYS VALIDATION",1,9)
    local fsysCount=0;for _,f in ipairs(disc.files)do if f.path:lower():match("%.fsys$")then fsysCount=fsysCount+1 end end
    state.fsys_files=fsysCount
    assert(fsysCount>1000,("unexpected FSYS inventory (%d)"):format(fsysCount))
    local people=assert(disc:file("people_archive.fsys"),"people_archive.fsys missing")
    local parc=FSYS.open(disc,people);assert(#parc:list()>20,"people_archive.fsys did not parse")
    write(mod,"build/fsys.lua",string.format("return {count=%d,peopleMembers=%d}\n",fsysCount,#parc:list()),generated)
    parc=nil;people=nil;memoryFence()
    state.message="FSYS transport validated";saveState();stage(mod,"fsys",generated)

    state.current_stage="arenas";state.message="Generating CBE arena runtime";saveState();update("ARENAS",2,9)
    ArenaBuilder.run(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(ArenaBuilder and type(ArenaBuilder.runtimeSidecars)=="function","arena runtime sidecar builder unavailable")
    local arenaSidecars=ArenaBuilder.runtimeSidecars(mod,function(label,c,t)update(label,c,t)end,generated);assert(arenaSidecars and arenaSidecars.ready,"arena runtime sidecar build incomplete")
    write(mod,ARENA_RUNTIME_SIDECAR_PATH,ARENA_RUNTIME_SIDECAR_MARKER,generated)
    stage(mod,"arenas",generated);write(mod,".cbe-arena-v10.complete",ARENA_MARKER,generated);memoryFence()

    state.current_stage="trainers";state.message="Extracting trainer HSD models, native poses, and GX textures";saveState();update("TRAINERS",3,9)
    local trainer=TrainerExtractor.run(mod,disc,function(label,c,t)update(label,c,t)end,generated) or {}
    state.trainer_resolved=tonumber(trainer.resolvedCount) or 0;state.trainer_total=tonumber(trainer.total) or 10;state.trainer_first_error=trainer.firstError;state.trainer_source_error=trainer.firstSourceError
    local trainerReady=trainer.ready==true
    if trainerReady then stage(mod,"trainers",generated);write(mod,".cbe-trainer-identity-v16.complete",TRAINER_IDENTITY_MARKER,generated);for i=1,15 do del(mod,(".cbe-trainer-identity-v%d.complete"):format(i)) end;state.message="Trainer source cache complete"
    else pending(mod,"trainers",("resolved %d/%d; see %s"):format(state.trainer_resolved,state.trainer_total,state.trainer_diagnostic),generated);state.message=("Trainer cache partial (%d/%d); diagnostics recorded"):format(state.trainer_resolved,state.trainer_total) end
    trainer=nil;saveState();memoryFence()

    state.current_stage="capture";state.message="Extracting native Colosseum ball models and source capture clips";saveState();update("CAPTURE SOURCE",4,9)
    assert(MoveFXExtractor and type(MoveFXExtractor.extractCaptureAssets)=="function","capture source extractor unavailable")
    local capture,captureErr=MoveFXExtractor.extractCaptureAssets(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(capture and capture.ready,captureErr or (capture and capture.message) or "native capture source cache incomplete")
    capture=nil;stage(mod,"capture",generated);memoryFence()

    state.current_stage="transition";state.message="Generating battle transition masks";saveState();update("TRANSITION",5,9)
    TransitionBuilder.run(mod,disc,function(label,c,t)update(label,c,t)end,generated);stage(mod,"transition",generated);memoryFence()

    state.current_stage="movefx";state.message="Building all 251 Colosseum Waza move banks";saveState();update("MOVEFX FULL CACHE",6,9)
    assert(MoveFXExtractor and type(MoveFXExtractor.extractAllMoves)=="function","full MoveFX extractor unavailable")
    local fullMoveFx=MoveFXExtractor.extractAllMoves(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(fullMoveFx and fullMoveFx.ready and tonumber(fullMoveFx.sourceReady)==251 and tonumber(fullMoveFx.missing)==0,
      ("complete MoveFX source cache failed (%s/251 ready, %s missing)"):format(
        tostring(fullMoveFx and fullMoveFx.sourceReady or 0),tostring(fullMoveFx and fullMoveFx.missing or "?")))
    local fullVisual=fullMoveFx.fullVisualReady==true and tonumber(fullMoveFx.fullVisualCount)==251
    state.movefx_source_ready=tonumber(fullMoveFx.sourceReady) or 0;state.movefx_source_total=tonumber(fullMoveFx.total) or 251;state.movefx_full_visual_ready=tonumber(fullMoveFx.fullVisualCount) or 0
    if not fullVisual then
      write(mod,"build/movefx_warning.txt",("MoveFX executable-chain audit incomplete (%s/251); source cache retained and audio extraction continues. See build/movefx_coverage.txt\n"):format(tostring(fullMoveFx and fullMoveFx.fullVisualCount or 0)),generated)
    end
    state.current_stage="move_audio";state.message="Rendering retail Waza GameSound SFX cache";saveState()
    assert(WazaSfxBuilder and type(WazaSfxBuilder.run)=="function","Waza GameSound cache builder unavailable")
    local fullMoveAudio=WazaSfxBuilder.run(mod,disc,WazaSfxBuilder.withReleaseSounds(fullMoveFx.soundIds),function(label,c,t)update(label,c,t)end,generated)
    assert(fullMoveAudio and fullMoveAudio.ready,"Waza GameSound cache failed")
    state.movefx_sfx_ready=tonumber(fullMoveAudio.complete) or 0;state.movefx_sfx_total=tonumber(fullMoveAudio.total) or 0;state.movefx_ready=fullVisual and 1 or 0
    if fullVisual then write(mod,MOVEFX_FULL_PATH,MOVEFX_FULL_MARKER,generated) else del(mod,MOVEFX_FULL_PATH) end
    del(mod,".cbe-movefx-full-v3.complete");del(mod,".cbe-movefx-full-v2.complete");del(mod,".cbe-movefx-full-v1.complete");stage(mod,"movefx",generated);fullMoveFx=nil;fullMoveAudio=nil;memoryFence()

    -- A partial trainer cache is a visual failure and must be repaired before
    -- the required soundtrack stage. Never let an audio renderer error hide the
    -- actual visual/trainer diagnostic.
    if not trainerReady then
      state.visual_ready=0;state.current_stage="partial_trainers";state.message=("Visual cache completed through arenas/transition; trainer HSD unresolved %d/%d. See %s"):format(state.trainer_total-state.trainer_resolved,state.trainer_total,state.trainer_diagnostic)
      saveState();finishManifest(mod,generated);update("CACHE PARTIAL / TRAINERS PENDING",7,9)
      return {state="CACHE PARTIAL / TRAINERS PENDING",visualReady=false,audioReady=audioReady(mod),files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message}
    end

    -- Visual completeness is recorded independently so an audio retry never
    -- rebuilds expensive arenas/trainers/MoveFX. Audio itself is now a hard source-
    -- presentation dependency: visual cache may persist, but CBE runtime is not
    -- stamped ready until the canonical 24/24 soundtrack cache is complete.
    state.current_stage="verify";state.message="Verifying generated visual runtime";saveState();update("VERIFY VISUAL",7,9)
    for _,p in ipairs(VISUAL_CORE)do assert(exists(mod,p),"generated visual runtime missing: "..p)end
    stage(mod,"verify",generated)
    state.visual_ready=1
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    del(mod,".cbe-runtime-v2.complete")
    saveState();finishManifest(mod,generated)

    state.current_stage="audio";state.audio_ready=0;state.audio_exhausted=0
    del(mod,AUDIO_EXHAUSTED_PATH)
    state.message="Building required canonical Colosseum soundtrack cache";saveState();update("AUDIO EXTRACTION 0/24",8,9)
    local audio,why,osName=attemptRequiredAudio(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    if not (audio and audio.ready) then
      local failed=audioRequiredFailure(mod,state,generated,
        "Required Colosseum soundtrack cache failed; visual cache retained, CBE runtime withheld until audio retry succeeds",
        why,osName)
      failed.files=#disc.files;failed.fsys=fsysCount;failed.trainerResolved=state.trainer_resolved;failed.trainerTotal=state.trainer_total;failed.trainerDiagnostic=state.trainer_diagnostic
      pcall(function()pending(mod,"audio","required canonical renderer incomplete; retry required",generated)end)
      saveState();finishManifest(mod,generated);update("AUDIO REQUIRED / RETRY",8,9)
      return failed
    end
    stage(mod,"audio",generated)
    stage(mod,"audio_portable",generated);state.portable_audio_ready=1;del(mod,".cbe-audio-v1.complete")
    state.audio_ready=1;state.audio_exhausted=0;state.current_stage="ready"
    local movefxNote=(tonumber(state.movefx_full_visual_ready) or 0)<251
      and ("; MoveFX visual chains %d/251 remain pending (see build/movefx_coverage.txt)"):format(tonumber(state.movefx_full_visual_ready) or 0) or ""
    state.message=("Runtime ready; canonical GC6E01 soundtrack cache 24/24 generated with the same renderer on %s"):format(tostring(audio.osName or "this platform"))..movefxNote
    del(mod,"build/audio_warning.txt");del(mod,"build/error.txt");del(mod,AUDIO_EXHAUSTED_PATH)
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    saveState();finishManifest(mod,generated);update("RUNTIME READY / AUDIO 24/24",9,9)
    return {state="READY",runtimeReady=true,visualReady=true,moveFxReady=state.movefx_ready==1,audioReady=true,audioExhausted=false,portableAudioReady=audio.portable==true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message,audioPrimaryError=nil,diagnosticPath=nil}
  end)
  if not ok then
    local msg=tostring(result)
    local failedStage=state.current_stage
    local visualSurvived=true
    for _,p in ipairs(VISUAL_CORE)do if not exists(mod,p)then visualSurvived=false;break end end
    if (failedStage=="audio" or failedStage=="audio_portable") and visualSurvived then
      state.current_stage="audio_controller_failed";state.audio_ready=0;state.audio_exhausted=0
      state.message="Audio extraction controller failed before the required canonical renderer completed: "..msg
      del(mod,".cbe-runtime-v2.complete");del(mod,".cbe-audio-v1.complete");del(mod,AUDIO_EXHAUSTED_PATH)
      pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
      pcall(function()write(mod,"build/error.txt",state.message.."\n",nil)end)
      pcall(function()pending(mod,"audio",state.message,nil)end)
      pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()finishManifest(mod,generated)end)
      return {state="AUDIO CONTROLLER FAILED",runtimeReady=false,visualReady=true,audioReady=false,audioExhausted=false,audioUnavailable=true,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message,diagnosticPath=AUDIO_DIAGNOSTIC_PATH}
    end
    state.current_stage="failed";state.message=msg
    diag.stage=failedStage;diag.error=msg;writeDiagnostic(mod,diag)
    pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
    pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
    if visualSurvived then
      pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
      del(mod,".cbe-runtime-v2.complete")
    else del(mod,".cbe-visual-v2.complete");del(mod,".cbe-runtime-v2.complete") end
    del(mod,".cbe-audio-v1.complete")
    -- Preserve any successful stage outputs and diagnostics for the next test.
    pcall(function()finishManifest(mod,generated)end)
    return {state=visualSurvived and "FAILED / VISUAL CACHE PRESERVED" or "FAILED",visualReady=visualSurvived,audioReady=false,audioUnavailable=visualSurvived,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg,diagnosticPath=DIAG_PATH,storageDiagnostic=true}
  end
  return result
end
B.marker=EXPECTED_MARKER
B.audioMarker=AUDIO_MARKER
B.audioExhaustedMarker=AUDIO_EXHAUSTED_MARKER
B.audioExhaustedPath=AUDIO_EXHAUSTED_PATH
B.moveFxMarker=MOVEFX_FULL_MARKER
B.moveFxReady=moveFxReady
B.moveFxCacheReady=function(mod)return moveFxReady(mod,true)end
B.trainerIdentityMarker=TRAINER_IDENTITY_MARKER
B.arenaMarker=ARENA_MARKER
B.visualCore=VISUAL_CORE
B.audioCore=AUDIO_CORE
return B
