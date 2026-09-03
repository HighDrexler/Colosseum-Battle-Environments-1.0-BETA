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
  "cache/M1_water_cache.lua","cache/orre_colosseum_cache.lua","cache/realgam_colosseum_cache.lua","cache/outdoor_wild_cache.lua","cache/D2_mt_battle_platform100_cache.lua",
  "cache/trainers/red/model_cache.lua","cache/trainers/leaf/model_cache.lua","cache/trainers/wes/model_cache.lua","cache/trainers/brendan/model_cache.lua","cache/trainers/may/model_cache.lua","cache/trainers/cooltrainer_m/model_cache.lua","cache/trainers/cooltrainer_f/model_cache.lua","cache/trainers/dakim/model_cache.lua","cache/trainers/nascour/model_cache.lua","cache/trainers/miror_b/model_cache.lua","cache/trainers/generic/index.lua",
  "cache/capture/index.lua",
  "assets/transition/wipe_ball00.rgba","assets/transition/wipe_ball01.rgba",
}
local LEGACY_VISUAL_CORE={}
for _,path in ipairs(VISUAL_CORE) do if path~="cache/capture/index.lua" then LEGACY_VISUAL_CORE[#LEGACY_VISUAL_CORE+1]=path end end
local AUDIO_MARKER="cbe-audio=3\nassets=24\nsource=GC6E01\n"
local MOVEFX_FULL_MARKER="cbe-movefx-full=2\nsource=GC6E01\nmoves=251\nextractor=17\nwaza=4\nruntime=retail-selector-resource-link-v2\naudio=snd_se_battle-sfxgroup-v1\n"
local MOVEFX_FULL_PATH=".cbe-movefx-full-v2.complete"
local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-portable=4\nsource=GC6E01\nassets=24\nrate=32000\nrenderer=lua-musyx-battle-fidelity-v3-loop-boundary\n"
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
  local keys={"cache_version","extractor_revision","current_stage","message","disc_id","disc_region","source_size","fst_files","fsys_files","source_fingerprint","visual_ready","movefx_ready","movefx_source_ready","movefx_source_total","movefx_sfx_ready","movefx_sfx_total","audio_ready","portable_audio_ready","trainer_resolved","trainer_total","trainer_diagnostic","trainer_first_error","trainer_source_error"}
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
  return read(mod,".cbe-trainer-identity-v12.complete")==TRAINER_IDENTITY_MARKER
end
local function arenaReady(mod)
  return read(mod,".cbe-arena-v7.complete")==ARENA_MARKER
end
local function visualReady(mod)
  return baseVisualReady(mod) and trainerIdentityReady(mod) and arenaReady(mod) and captureSourceReady(mod)
end
local function moveFxReady(mod)
  if read(mod,MOVEFX_FULL_PATH)~=MOVEFX_FULL_MARKER then return false end
  if not exists(mod,"cache/movefx/index.lua") or not exists(mod,"build/movefx_coverage.txt") then return false end
  local index=readLuaTable(mod,"cache/movefx/index.lua")
  if type(index)~="table" or tonumber(index.revision)~=16
      or tonumber(index.total)~=251 or tonumber(index.ready)~=251 or tonumber(index.missing)~=0
      or type(index.moves)~="table" then return false end
  for id=1,251 do
    local row=index.moves[id]
    if type(row)~="table" or row.missing==true or not row.stem then return false end
  end
  if not (WazaSfxBuilder and type(WazaSfxBuilder.ready)=="function") then return false end
  local ok,ready=pcall(WazaSfxBuilder.ready,mod)
  return ok and ready==true
end

local function audioReady(mod)
  local desktop=read(mod,".cbe-audio-v1.complete")==AUDIO_MARKER
  local portable=false
  if AudioProbe and type(AudioProbe.portableFullReady)=="function" then
    local ok,ready=pcall(AudioProbe.portableFullReady,mod);portable=ok and ready==true
  else
    portable=read(mod,".cbe-audio-portable-v4.complete")==PORTABLE_AUDIO_FULL_MARKER or read(mod,"build/audio_portable_v4.complete")==PORTABLE_AUDIO_FULL_MARKER
  end
  if not desktop and not portable then return false end
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
local arenasOnly,trainersOnly,moveFxOnly,captureOnly
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
    local okPortable,portable=pcall(function()
      -- A completed 24/24 portable marker is the same zero-disc-I/O fast path
      -- as desktop audio: never reopen the logical disc just to rediscover it.
      if AudioProbe and type(AudioProbe.portableFullReady)=="function" and AudioProbe.portableFullReady(mod) then
        progress("AUDIO PORTABLE 24/24 / cached Colosseum soundtrack",24,24)
        return {ready=true,complete=24,total=24,cached=true}
      end
      local disc=Disc.open(mod)
      return AudioProbe.runPortableFull(mod,disc,progress,generated)
    end)
    if okPortable and portable and portable.ready then
      stage(mod,"audio_portable",generated);stage(mod,"audio",generated)
      state.portable_audio_ready=1;state.audio_ready=1;state.current_stage="ready"
      state.message=("Runtime ready; portable Colosseum soundtrack cache 24/24 generated on %s"):format(tostring(osName or "this platform"))
      del(mod,"build/audio_warning.txt");del(mod,".cbe-audio-v1.complete")
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated);save();finishManifest(mod,generated)
      return {state="READY",visualReady=true,audioReady=true,portableAudioReady=true,message=state.message}
    end
    local why=tostring(portable or "portable MusyX extraction unavailable")
    state.current_stage="ready_visual";state.audio_ready=0;state.message=("Runtime ready; optional Colosseum audio unavailable on %s: %s"):format(tostring(osName or "this platform"),why)
    pcall(function()write(mod,"build/audio_warning.txt",why.."\n",generated)end);del(mod,".cbe-audio-v1.complete");del(mod,".cbe-audio-portable-v2.complete");del(mod,".cbe-audio-portable-v3.complete");del(mod,".cbe-audio-portable-v4.complete");del(mod,"build/audio_portable_v4.complete")
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated);save();finishManifest(mod,generated)
    return {state="READY / AUDIO UNAVAILABLE",visualReady=true,audioReady=false,portableAudioReady=false,audioUnavailable=true,message=state.message}
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
  if ok then if hadAudio then return result else return audioOnly(mod,progress) end end
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
    stage(mod,"trainers",generated)
    write(mod,".cbe-trainer-identity-v12.complete",TRAINER_IDENTITY_MARKER,generated)
    for i=1,11 do del(mod,(".cbe-trainer-identity-v%d.complete"):format(i)) end
    state.current_stage="capture";state.message="Compiling native Colosseum capture balls from snatch_* source";save()
    assert(MoveFXExtractor and type(MoveFXExtractor.extractCaptureAssets)=="function","capture source extractor unavailable")
    local captureResult,captureErr=MoveFXExtractor.extractCaptureAssets(mod,disc,progress,generated)
    assert(captureResult and captureResult.ready,captureErr or (captureResult and captureResult.message) or "native capture source cache incomplete")
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
  del(mod,".cbe-trainer-identity-v12.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="TRAINER CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,
    trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,
    trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg}
end

-- Arena-only migration: rebuild every disc-backed venue from its complete
-- source HSD scene while preserving Wildlands and all trainer, transition,
-- MoveFX and audio caches. This is intentionally independent from the global
-- extractor revision.
arenasOnly=function(mod,progress)
  local generated=previousGenerated(mod)
  local hadAudio=audioReady(mod)
  local hadTrainers=trainerIdentityReady(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="arenas",message="Refreshing source-backed arenas plus current Wildlands presentation recipe",disc_id="GC6E01",disc_region="USA",
    visual_ready=0,audio_ready=hadAudio and 1 or 0,trainer_resolved=hadTrainers and 10 or 0,trainer_total=10}
  local function save()write(mod,"build/state.txt",stateText(state),generated)end
  del(mod,"build/error.txt");del(mod,"build/stage_arenas.pending");del(mod,".cbe-runtime-v2.complete");del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete");del(mod,".cbe-arena-v4.complete");del(mod,".cbe-arena-v5.complete");del(mod,".cbe-arena-v6.complete");del(mod,".cbe-arena-v7.complete")
  save()
  local ok,result=pcall(function()
    local disc=Disc.open(mod)
    if type(ArenaBuilder.repair)=="function" then ArenaBuilder.repair(mod,disc,progress,generated)
    else ArenaBuilder.run(mod,disc,progress,generated) end
    stage(mod,"arenas",generated)
    write(mod,".cbe-arena-v7.complete",ARENA_MARKER,generated);del(mod,".cbe-arena-v2.complete");del(mod,".cbe-arena-v3.complete");del(mod,".cbe-arena-v4.complete");del(mod,".cbe-arena-v5.complete");del(mod,".cbe-arena-v6.complete")
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    state.visual_ready=hadTrainers and 1 or 0
    if hadTrainers and hadAudio then
      state.current_stage="ready";state.message="Runtime ready; source arenas and Wildlands presentation refreshed; trainer/MoveFX/audio caches reused"
      write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    elseif hadTrainers then
      state.current_stage="audio";state.message="Disc-backed arena source-parity refresh complete; generated audio cache pending"
    else
      state.current_stage="trainers";state.message="Disc-backed arena source-parity refresh complete; exact trainer cache pending"
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
    pending(mod,"arenas",msg,nil);del(mod,".cbe-arena-v7.complete");del(mod,".cbe-runtime-v2.complete")
  pcall(function()finishManifest(mod,generated)end)
  return {state="ARENA CACHE REPAIR FAILED",visualReady=false,audioReady=hadAudio,message=msg}
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
  del(mod,"build/error.txt");del(mod,"build/movefx_warning.txt");del(mod,MOVEFX_FULL_PATH);del(mod,".cbe-movefx-full-v1.complete")
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
    state.movefx_source_ready=tonumber(fx.sourceReady) or 0;state.movefx_source_total=tonumber(fx.total) or 251
    state.current_stage="move_audio";state.message=("Rendering %d unique retail Waza GameSound IDs"):format(#(fx.soundIds or {}));save()
    assert(WazaSfxBuilder and type(WazaSfxBuilder.run)=="function","Waza GameSound cache builder unavailable")
    local audio=WazaSfxBuilder.run(mod,disc,fx.soundIds or {},progress,generated)
    assert(audio and audio.ready,"Waza GameSound cache incomplete")
    state.movefx_sfx_ready=tonumber(audio.complete) or 0;state.movefx_sfx_total=tonumber(audio.total) or 0
    write(mod,MOVEFX_FULL_PATH,MOVEFX_FULL_MARKER,generated);del(mod,".cbe-movefx-full-v1.complete");stage(mod,"movefx",generated)
    state.movefx_ready=1;state.current_stage="ready"
    state.message=("Runtime ready; full Waza cache %d/%d source move banks, GameSound %d/%d cached"):format(
      state.movefx_source_ready,state.movefx_source_total,state.movefx_sfx_ready,state.movefx_sfx_total)
    save();finishManifest(mod,generated)
    return {state="READY",visualReady=true,moveFxReady=true,audioReady=hadAudio,
      moveFxSourceReady=state.movefx_source_ready,moveFxSourceTotal=state.movefx_source_total,
      moveFxSfxReady=state.movefx_sfx_ready,moveFxSfxTotal=state.movefx_sfx_total,message=state.message}
  end)
  if not ok then
    local msg=tostring(result);state.current_stage="movefx_failed";state.message=msg
    pcall(function()write(mod,"build/movefx_warning.txt",msg.."\n",generated)end);save();finishManifest(mod,generated)
    return {state="READY / MOVEFX CACHE PENDING",visualReady=true,moveFxReady=false,audioReady=hadAudio,message=msg}
  end
  if not hadAudio then return audioOnly(mod,progress) end
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
  if baseVisualReady(mod) and trainerIdentityReady(mod) and arenaReady(mod) and not captureSourceReady(mod) then
    return captureOnly(mod,progress)
  end
  if visualReady(mod) and not moveFxReady(mod) then
    return moveFxOnly(mod,progress)
  end
  if visualReady(mod) then
    if audioReady(mod) then
      return {state="READY",visualReady=true,audioReady=true,message="Persistent generated runtime already present; audio cache reused."}
    end
    -- Android/non-Windows full portable audio has its own 24/24 completion
    -- contract. Once present this is a true no-op cache hit: no disc/FST open,
    -- no state rewrite, and no generated-manifest churn on later launches.
    local audioSupported,osName=audioPlatformSupported()
    if not audioSupported and AudioProbe and type(AudioProbe.portableFullReady)=="function" then
      local okPortable,readyPortable=pcall(AudioProbe.portableFullReady,mod)
      if okPortable and readyPortable then
        return {state="READY",visualReady=true,audioReady=true,portableAudioReady=true,
          message=("Persistent generated runtime already present; portable Colosseum soundtrack 24/24 reused on %s with zero source-disc work."):format(tostring(osName or "this platform"))}
      end
    end
    return audioOnly(mod,progress)
  end

  cleanupPrevious(mod)
  for _,p in ipairs({".cbe-runtime-v2.complete",".cbe-visual-v2.complete",".cbe-movefx-full-v1.complete",MOVEFX_FULL_PATH,".cbe-waza-sfx-v1.complete","build/waza_sfx_v1.complete",".cbe-audio-v1.complete",".cbe-audio-portable-v1.complete",".cbe-audio-portable-v2.complete",".cbe-audio-portable-v3.complete",".cbe-audio-portable-v3.pending",".cbe-audio-portable-v4.complete",".cbe-audio-portable-v4.pending","build/audio_portable_v4.complete","build/audio_portable_v4.migrating",".cbe-trainer-identity-v1.complete",".cbe-trainer-identity-v2.complete",".cbe-trainer-identity-v3.complete",".cbe-trainer-identity-v4.complete",".cbe-trainer-identity-v5.complete",".cbe-trainer-identity-v6.complete",".cbe-trainer-identity-v7.complete",".cbe-trainer-identity-v8.complete",".cbe-trainer-identity-v9.complete",".cbe-trainer-identity-v10.complete",".cbe-trainer-identity-v11.complete",".cbe-trainer-identity-v12.complete",".cbe-arena-v2.complete",".cbe-arena-v3.complete",".cbe-arena-v4.complete",".cbe-arena-v5.complete",".cbe-arena-v6.complete",".cbe-arena-v7.complete","build/error.txt","build/audio_warning.txt","build/stage_trainers.pending","build/stage_audio.pending"})do del(mod,p)end
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
    ArenaBuilder.run(mod,disc,function(label,c,t)update(label,c,t)end,generated);stage(mod,"arenas",generated);write(mod,".cbe-arena-v7.complete",ARENA_MARKER,generated);memoryFence()

    state.current_stage="trainers";state.message="Extracting trainer HSD models, native poses, and GX textures";saveState();update("TRAINERS",3,9)
    local trainer=TrainerExtractor.run(mod,disc,function(label,c,t)update(label,c,t)end,generated) or {}
    state.trainer_resolved=tonumber(trainer.resolvedCount) or 0;state.trainer_total=tonumber(trainer.total) or 10;state.trainer_first_error=trainer.firstError;state.trainer_source_error=trainer.firstSourceError
    local trainerReady=trainer.ready==true
    if trainerReady then stage(mod,"trainers",generated);write(mod,".cbe-trainer-identity-v12.complete",TRAINER_IDENTITY_MARKER,generated);for i=1,11 do del(mod,(".cbe-trainer-identity-v%d.complete"):format(i)) end;state.message="Trainer source cache complete"
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
    state.movefx_source_ready=tonumber(fullMoveFx.sourceReady) or 0;state.movefx_source_total=tonumber(fullMoveFx.total) or 251
    state.current_stage="move_audio";state.message="Rendering retail Waza GameSound SFX cache";saveState()
    assert(WazaSfxBuilder and type(WazaSfxBuilder.run)=="function","Waza GameSound cache builder unavailable")
    local fullMoveAudio=WazaSfxBuilder.run(mod,disc,fullMoveFx.soundIds or {},function(label,c,t)update(label,c,t)end,generated)
    assert(fullMoveAudio and fullMoveAudio.ready,"Waza GameSound cache failed")
    state.movefx_sfx_ready=tonumber(fullMoveAudio.complete) or 0;state.movefx_sfx_total=tonumber(fullMoveAudio.total) or 0;state.movefx_ready=1
    write(mod,MOVEFX_FULL_PATH,MOVEFX_FULL_MARKER,generated);del(mod,".cbe-movefx-full-v1.complete");stage(mod,"movefx",generated);fullMoveFx=nil;fullMoveAudio=nil;memoryFence()

    -- A partial trainer cache is a visual failure and must be repaired before
    -- optional music work. Never let an audio converter error hide the actual
    -- visual/trainer diagnostic.
    if not trainerReady then
      state.visual_ready=0;state.current_stage="partial_trainers";state.message=("Visual cache completed through arenas/transition; trainer HSD unresolved %d/%d. See %s"):format(state.trainer_total-state.trainer_resolved,state.trainer_total,state.trainer_diagnostic)
      saveState();finishManifest(mod,generated);update("CACHE PARTIAL / TRAINERS PENDING",7,9)
      return {state="CACHE PARTIAL / TRAINERS PENDING",visualReady=false,audioReady=audioReady(mod),files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message}
    end

    -- Visual runtime is the product boundary. Mark it READY before touching the
    -- optional platform-specific music converter so an audio failure can never
    -- withhold arenas, Pokemon, trainers, MoveFX, transitions or menus.
    state.current_stage="verify";state.message="Verifying generated visual runtime";saveState();update("VERIFY VISUAL",7,9)
    for _,p in ipairs(VISUAL_CORE)do assert(exists(mod,p),"generated visual runtime missing: "..p)end
    stage(mod,"verify",generated)
    state.visual_ready=1
    write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    saveState();finishManifest(mod,generated)

    local audioSupported,osName=audioPlatformSupported()
    if not audioSupported then
      state.current_stage="audio_portable";state.audio_ready=0
      state.message=("Generating portable Colosseum soundtrack cache on %s"):format(tostring(osName or "this platform"));saveState();update("PORTABLE AUDIO 1/24",8,9)
      local okPortable,portable=pcall(AudioProbe.runPortableFull,mod,disc,function(label,c,t)update(label,c,t)end,generated)
      if okPortable and portable and portable.ready then
        stage(mod,"audio_portable",generated);stage(mod,"audio",generated);state.portable_audio_ready=1;state.audio_ready=1;state.current_stage="ready"
        state.message=("Runtime ready; portable Colosseum soundtrack cache 24/24 generated on %s"):format(tostring(osName or "this platform"))
        del(mod,"build/audio_warning.txt");del(mod,".cbe-audio-v1.complete")
        saveState();finishManifest(mod,generated);update("RUNTIME READY / AUDIO 24/24",9,9)
        return {state="READY",visualReady=true,audioReady=true,portableAudioReady=true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
      end
      local why=tostring(portable or "portable MusyX extraction unavailable")
      state.current_stage="ready_visual";state.portable_audio_ready=0;state.audio_ready=0
      state.message=("Runtime ready; optional Colosseum audio unavailable on %s: %s"):format(tostring(osName or "this platform"),why)
      pcall(function()write(mod,"build/audio_warning.txt",why.."\n",generated)end);del(mod,".cbe-audio-v1.complete");del(mod,".cbe-audio-portable-v2.complete");del(mod,".cbe-audio-portable-v3.complete");del(mod,".cbe-audio-portable-v4.complete");del(mod,"build/audio_portable_v4.complete")
      saveState();finishManifest(mod,generated);update("RUNTIME READY / AUDIO UNAVAILABLE",9,9)
      return {state="READY / AUDIO UNAVAILABLE",visualReady=true,audioReady=false,portableAudioReady=false,audioUnavailable=true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
    end

    state.current_stage="audio";state.message="Indexing optional MusyX source archives";saveState();update("OPTIONAL AUDIO SOURCE",8,9)
    local audio=AudioProbe.run(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(audio and audio.ready,("audio cache incomplete (%s/%s)")
      :format(tostring(audio and audio.complete or 0),tostring(audio and audio.total or 24)))
    stage(mod,"audio",generated);state.audio_ready=1
    del(mod,"build/audio_warning.txt")
    write(mod,".cbe-audio-v1.complete",AUDIO_MARKER,generated)
    state.current_stage="ready";state.message="Runtime ready; generated audio cache 24/24"
    saveState();finishManifest(mod,generated)
    update("RUNTIME READY / AUDIO 24/24",9,9)
    return {state="READY",visualReady=true,audioReady=true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
  end)
  if not ok then
    local msg=tostring(result)
    local failedStage=state.current_stage
    local visualSurvived=true
    for _,p in ipairs(VISUAL_CORE)do if not exists(mod,p)then visualSurvived=false;break end end
    if (failedStage=="audio" or failedStage=="audio_portable") and visualSurvived then
      state.current_stage="ready_visual";state.audio_ready=0
      state.message="Runtime ready; optional Colosseum audio unavailable: "..msg
      del(mod,"build/error.txt");del(mod,".cbe-audio-v1.complete");del(mod,".cbe-audio-portable-v2.complete");del(mod,".cbe-audio-portable-v3.complete");del(mod,".cbe-audio-portable-v4.complete");del(mod,"build/audio_portable_v4.complete")
      pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
      pcall(function()write(mod,"build/audio_warning.txt",msg.."\n",nil)end)
      pcall(function()pending(mod,"audio",msg,nil)end)
      pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()finishManifest(mod,generated)end)
      return {state="READY / AUDIO OPTIONAL",visualReady=true,audioReady=false,audioUnavailable=true,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message}
    end
    state.current_stage="failed";state.message=msg
    diag.stage=failedStage;diag.error=msg;writeDiagnostic(mod,diag)
    pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
    pcall(function()write(mod,"build/error.txt",msg.."\n",nil)end)
    if visualSurvived then
      pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)end)
    else del(mod,".cbe-visual-v2.complete");del(mod,".cbe-runtime-v2.complete") end
    del(mod,".cbe-audio-v1.complete")
    -- Preserve any successful stage outputs and diagnostics for the next test.
    pcall(function()finishManifest(mod,generated)end)
    return {state=visualSurvived and "READY / DEGRADED" or "FAILED",visualReady=visualSurvived,audioReady=false,audioUnavailable=visualSurvived,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=msg,diagnosticPath=DIAG_PATH,storageDiagnostic=true}
  end
  return result
end
B.marker=EXPECTED_MARKER
B.audioMarker=AUDIO_MARKER
B.moveFxMarker=MOVEFX_FULL_MARKER
B.moveFxReady=moveFxReady
B.trainerIdentityMarker=TRAINER_IDENTITY_MARKER
B.arenaMarker=ARENA_MARKER
B.visualCore=VISUAL_CORE
B.audioCore=AUDIO_CORE
return B
