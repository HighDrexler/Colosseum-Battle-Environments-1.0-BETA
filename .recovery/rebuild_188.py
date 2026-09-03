from pathlib import Path
import json, re, sys

VERSION = "1.8.8-recovery.1"
ROOT = Path(__file__).resolve().parents[1]

def read(path):
    return (ROOT/path).read_text(encoding="utf-8")

def write(path, text):
    (ROOT/path).write_text(text, encoding="utf-8")

def rep(text, old, new, label):
    if old not in text:
        raise SystemExit(f"missing patch anchor: {label}")
    return text.replace(old, new, 1)

def sub(text, pattern, repl, label, flags=0):
    out, n = re.subn(pattern, repl, text, count=1, flags=flags)
    if n != 1:
        raise SystemExit(f"missing/ambiguous patch anchor: {label} ({n})")
    return out

# ---------------------------------------------------------------------------
# Package identity
# ---------------------------------------------------------------------------
p = ROOT/"main.lua"
s = p.read_text(encoding="utf-8")
s = sub(s, r'local VERSION="[^"]+"', f'local VERSION="{VERSION}"', "main version")
p.write_text(s, encoding="utf-8")

p = ROOT/"manifest.json"
data = json.loads(p.read_text(encoding="utf-8"))
data["version"] = VERSION
p.write_text(json.dumps(data, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

# ---------------------------------------------------------------------------
# Presentation time must be wall-time invariant at 1x/2x/4x/8x.
# ---------------------------------------------------------------------------
p = ROOT/"lib/TrainerPerformance.lua"
s = p.read_text(encoding="utf-8")
s = rep(s,
    'function A.realDt(ctx,dt) return math.max(0,tonumber(dt) or 0) end',
    'function A.realDt(ctx,dt) return math.max(0,tonumber(dt) or 0)/battleSpeed(ctx) end',
    "trainer presentation clock")
p.write_text(s, encoding="utf-8")

p = ROOT/"lib/CurrentSpriteModels.lua"
s = p.read_text(encoding="utf-8")
s = sub(s,
    r'local function actorDelta\(context,dt\)\n(?:  .*\n)*?  return math\.max\(0,tonumber\(dt\) or 0\)\nend',
    'local function actorDelta(context,dt)\n  local TP=V and V.TrainerPerformance\n  if TP and type(TP.realDt)=="function" then return TP.realDt(context,dt) end\n  return math.max(0,tonumber(dt) or 0)\nend',
    "pokemon presentation clock")
p.write_text(s, encoding="utf-8")

# ---------------------------------------------------------------------------
# PortableMusyX source sequencing corrections recovered from the 1.8.8 audit.
# ---------------------------------------------------------------------------
p = ROOT/"extract/PortableMusyX.lua"
s = p.read_text(encoding="utf-8")

packed = r'''local function decodeUnsignedPacked(data,o)
  local a=data:byte(o);assert(a,"portable MusyX: truncated packed unsigned")
  if a>=128 then local b=data:byte(o+1);assert(b,"portable MusyX: truncated packed unsigned");return b+(a%128)*256,o+2 end
  return a,o+1
end
local function decodeSignedPacked(data,o)
  local a=data:byte(o);assert(a,"portable MusyX: truncated packed signed")
  if a>=128 then
    local b=data:byte(o+1);assert(b,"portable MusyX: truncated packed signed")
    local v=b+(a%128)*256
    -- SongState::DecodeSignedValue sign-extends bit 14 into bit 15.
    if v>=16384 then v=v-32768 end
    return v,o+2
  end
  -- MusyX's one-byte form is NOT signed 7-bit: 0x40..0x7f expands
  -- to positive 0xc0..0xff.
  if a>=64 then return a+128,o+1 end
  return a,o+1
end

'''
s = rep(s, 'local function parseSong(seq)\n', packed + 'local function parseSong(seq)\n', "packed signed decoder")

continuous = r'''        local pitchOff=u32be(seq,ro+5);local modOff=u32be(seq,ro+9)
        local function addContinuous(off,kind)
          if not off or off==0 or off>=#seq then return end
          local q=off+1;local ctick=reg.startTick;local accum=0;local guard=0
          while q<=#seq and guard<65536 do
            guard=guard+1
            if seq:byte(q)==128 and seq:byte(q+1)==0 then break end
            local dt=0;local dv
            repeat
              local part;part,q=decodeUnsignedPacked(seq,q);dt=dt+part
              dv,q=decodeSignedPacked(seq,q)
            until dv~=0 or q>#seq
            ctick=ctick+dt;accum=accum+(dv or 0)
            if kind=="pitch" then
              add({tick=ctick,kind="pitch",ch=ch,value=clamp(accum/8191,-1,1)})
            else
              add({tick=ctick,kind="mod",ch=ch,value=clamp(floor(accum/127),0,127)})
            end
          end
        end
        addContinuous(pitchOff,"pitch");addContinuous(modOff,"mod")
'''
s = rep(s,
    '      if ro then\n        local o=ro+13 -- 12-byte region header\n',
    '      if ro then\n' + continuous + '        local o=ro+13 -- 12-byte region header\n',
    "continuous pitch/mod streams")

# Setup volume/pan are ChannelState properties; CC7/CC10 still boot 127/64.
s = rep(s, '    ctrl[7]=src.volume or 127;ctrl[10]=src.pan or 64\n', '', "CC7/CC10 initialization")
s = rep(s,
    '  local relevant={[1]=true,[7]=true,[10]=true,[20]=true,[22]=true,[23]=true,[24]=true,[91]=true,[93]=true}',
    '  local relevant={[1]=true,[6]=true,[7]=true,[10]=true,[20]=true,[22]=true,[23]=true,[24]=true,[64]=true,[91]=true,[93]=true,[100]=true,[101]=true,[128]=true}',
    "sequencer controller set")

# Don't manufacture controller ADSR values that aren't present in the source.
s = sub(s,
    r'  local function bootstrapAdsr\(st,spec,sec\)\n.*?  end\n  for _,ev in ipairs\(song\.events\) do',
    '  local function bootstrapAdsr(st,spec,sec) return end\n  for _,ev in ipairs(song.events) do',
    "ADSR bootstrap", re.S)

# RPN 0 controls pitch wheel range; continuous streams are delivered as source automation.
s = rep(s,
    '    if ctrl==7 then st.volume=value elseif ctrl==10 then st.pan=value elseif ctrl==91 then st.reverb=value elseif ctrl==93 then st.chorus=value end\n',
    '    if ctrl==7 then st.ctrlVolume=value elseif ctrl==10 then st.ctrlPan=value elseif ctrl==91 then st.reverb=value elseif ctrl==93 then st.chorus=value\n'
    '    elseif ctrl==101 then st.rpnMsb=value elseif ctrl==100 then st.rpnLsb=value\n'
    '    elseif ctrl==6 and (st.rpnMsb or 0)==0 and (st.rpnLsb or 0)==0 then st.pitchRange=value end\n',
    "RPN pitch range")
s = rep(s,
    '    if ev.kind=="program" then st.program=ev.program\n    elseif ev.kind=="ctrl" then pushAuto(st,evSec,ev.ctrl,ev.value)\n',
    '    if ev.kind=="program" then st.program=ev.program\n    elseif ev.kind=="ctrl" then pushAuto(st,evSec,ev.ctrl,ev.value)\n'
    '    elseif ev.kind=="pitch" then pushAuto(st,evSec,128,ev.value)\n'
    '    elseif ev.kind=="mod" then pushAuto(st,evSec,1,ev.value)\n',
    "continuous event dispatch")

# Preserve finite waits before StartSample instead of moving the transient early.
s = rep(s,
    '  local spec={id=id,noteAdd=0,waitKeyOff=true,waitSampleEnd=true,fadeIn=0,volumeScale=nil,dlsVol=false}\n',
    '  local spec={id=id,noteAdd=0,waitKeyOff=true,waitSampleEnd=true,fadeIn=0,volumeScale=nil,dlsVol=false,preSampleWaitMs=0,preSampleWaitTicks=0}\n',
    "macro pre-sample wait state")
s = rep(s,
    '    elseif op==0x07 then\n      local keyOff=c:byte(2)~=0;local sampleEnd=c:byte(4)~=0;local n=u16le(c,7)\n      if n==65535 and not postKeyOff then spec.waitKeyOff=keyOff;spec.waitSampleEnd=sampleEnd;postKeyOff=true end\n',
    '    elseif op==0x07 then\n      local keyOff=c:byte(2)~=0;local sampleEnd=c:byte(4)~=0;local msSwitch=c:byte(6)~=0;local n=u16le(c,7)\n'
    '      if n~=65535 and not spec.sampleId then if msSwitch then spec.preSampleWaitMs=spec.preSampleWaitMs+n else spec.preSampleWaitTicks=spec.preSampleWaitTicks+n end end\n'
    '      if n==65535 and not postKeyOff then spec.waitKeyOff=keyOff;spec.waitSampleEnd=sampleEnd;postKeyOff=true end\n',
    "finite pre-StartSample wait")

s = rep(s,
    '        local startSec=evSec;local offSec=tickSeconds(song,ev.tick+ev.length)\n',
    '        local startSec=evSec;local offSec=tickSeconds(song,ev.tick+ev.length)\n'
    '        -- Same channel/note retriggers key off the previous voice before replacement.\n'
    '        for _,old in ipairs(voices) do if old.channel==ev.ch and old.triggerKey==ev.key and not old._retriggered then old.keyoff=max(0,startSec-old.startSec);old._retriggered=true end end\n',
    "same-note retrigger")
s = rep(s,
    '          if entry then\n            bootstrapAdsr(st,spec,startSec)\n',
    '          if entry then\n            bootstrapAdsr(st,spec,startSec)\n'
    '            local waitSec=(spec.preSampleWaitMs or 0)/1000 + (spec.preSampleWaitTicks or 0)/(song.initialTempo*384/60)\n'
    '            startSec=startSec+waitSec\n',
    "apply pre-sample wait")

# Sequencer note length always produces key-off. Pedal may defer the actual release.
s = rep(s,
    '            local keyoff=nil;if spec.waitKeyOff then keyoff=max(0,offSec-startSec) end\n',
    '            local keyoff=max(0,offSec-startSec)\n',
    "note-length keyoff")
s = rep(s,
    '              fadeIn=fadeIn,waitSampleEnd=spec.waitSampleEnd,vibrato=vib,key=key,keygroup=spec.keygroup,\n',
    '              fadeIn=fadeIn,waitSampleEnd=spec.waitSampleEnd,vibrato=vib,key=key,keygroup=spec.keygroup,channel=ev.ch,triggerKey=ev.key,\n'
    '              pitchRange=st.pitchRange or 2,pitchWheel=st.ctrl[128] or 0,pedal=(st.ctrl[64] or 0)>64,rpnMsb=st.rpnMsb or 0,rpnLsb=st.rpnLsb or 0,\n',
    "voice source-controller state")

# Pedal/sustain and pitch automation.
s = rep(s,
    '  if v.keyoff and t>=v.keyoff then\n    if r<=0 then return 0 end\n',
    '  if v.keyoff and t>=v.keyoff then\n'
    '    if v.pedal then v.noteOffPending=true;v.keyoff=nil;return adsrPreValues(a,d,s,t) end\n'
    '    if r<=0 then return 0 end\n',
    "sustain pedal keyoff")
s = rep(s,
    '    elseif e.ctrl==91 then v.reverb=e.value;v.reverbGain=lookupVolume(clamp(e.value/127,0,1),v.dlsVol)\n    elseif e.ctrl==1 and v.vibrato then v.mod=e.value end\n',
    '    elseif e.ctrl==91 then v.reverb=e.value;v.reverbGain=lookupVolume(clamp(e.value/127,0,1),v.dlsVol)\n'
    '    elseif e.ctrl==1 then v.mod=e.value\n'
    '    elseif e.ctrl==128 then v.pitchWheel=e.value\n'
    '    elseif e.ctrl==101 then v.rpnMsb=e.value\n'
    '    elseif e.ctrl==100 then v.rpnLsb=e.value\n'
    '    elseif e.ctrl==6 and (v.rpnMsb or 0)==0 and (v.rpnLsb or 0)==0 then v.pitchRange=e.value\n'
    '    elseif e.ctrl==64 then v.pedal=e.value>64;if not v.pedal and v.noteOffPending then v.keyoff=max(0,absSec-v.startSec/outputRate);v.noteOffPending=false end end\n',
    "automation pitch/pedal")

# pitch wheel participates in sample stepping together with vibrato.
s = rep(s,
    '        if vibCents~=0 then v.pos=v.pos+v.baseStep*pow(2,vibCents/1200) else v.pos=v.pos+v.baseStep end\n',
    '        local wheelCents=(tonumber(v.pitchWheel) or 0)*(tonumber(v.pitchRange) or 2)*100\n'
    '        local totalCents=vibCents+wheelCents\n'
    '        if totalCents~=0 then v.pos=v.pos+v.baseStep*pow(2,totalCents/1200) else v.pos=v.pos+v.baseStep end\n',
    "pitch wheel stepping")

p.write_text(s, encoding="utf-8")

# ---------------------------------------------------------------------------
# AudioProbe: one canonical renderer/cache identity on every host.
# Native Amuse remains only as a named developer/reference oracle.
# ---------------------------------------------------------------------------
p = ROOT/"extract/AudioProbe.lua"
s = p.read_text(encoding="utf-8")
s = rep(s,
    'local PORTABLE_FULL_MARKER="cbe-audio-portable=5\\nsource=GC6E01\\nassets=24\\nrate=48000\\nrenderer=lua-musyx-battle-fidelity-v4-source-mix-48k\\n"\n',
    'local PORTABLE_FULL_MARKER="cbe-audio-canonical=8\\nsource=GC6E01\\nassets=24\\nrate=48000\\nrenderer=lua-musyx-battle-canonical-v8\\n"\n',
    "canonical audio marker")
s = rep(s, 'local PORTABLE_FULL_PATH=".cbe-audio-portable-v5.complete"', 'local PORTABLE_FULL_PATH=".cbe-audio-canonical-v8.complete"', "canonical primary marker")
s = rep(s, 'local PORTABLE_FULL_FALLBACK_PATH="build/audio_portable_v5.complete"', 'local PORTABLE_FULL_FALLBACK_PATH="build/audio_canonical_v8.complete"', "canonical fallback marker")
s = rep(s, 'local PORTABLE_PENDING_PATH=".cbe-audio-portable-v5.pending"', 'local PORTABLE_PENDING_PATH=".cbe-audio-canonical-v8.pending"', "canonical pending marker")
s = rep(s, 'local PORTABLE_MIGRATION_PATH="build/audio_portable_v5.migrating"', 'local PORTABLE_MIGRATION_PATH="build/audio_canonical_v8.migrating"', "canonical migration marker")
# Previous production renderer marker is now legacy and must force an audio-only regeneration.
s = rep(s,
    'local LEGACY_V4_FALLBACK_PATH="build/audio_portable_v4.complete"\n',
    'local LEGACY_V4_FALLBACK_PATH="build/audio_portable_v4.complete"\nlocal LEGACY_V5_PATH=".cbe-audio-portable-v5.complete"\nlocal LEGACY_V5_FALLBACK_PATH="build/audio_portable_v5.complete"\nlocal LEGACY_V6_PATH=".cbe-audio-portable-v6.complete"\nlocal LEGACY_V6_FALLBACK_PATH="build/audio_portable_v6.complete"\n',
    "legacy audio markers")
s = s.replace('function A.portableFullReady(mod)', 'function A.canonicalFullReady(mod)', 1)
s = s.replace('A.portableFullReady(mod)', 'A.canonicalFullReady(mod)')
s = s.replace('function A.runPortableFull(mod,disc,progress,generated)', 'function A.runCanonicalFull(mod,disc,progress,generated)', 1)

# Canonical-v8 always starts a new transaction by deleting sequence-derived WAVs once.
old = '''    local legacyV2=cacheRead(mod,LEGACY_V2_PATH)~=nil
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
'''
new = '''    -- Canonical v8 is a new PCM/cache identity. Delete sequence-derived old
    -- soundtrack WAVs exactly once when opening this transaction, even if an
    -- older marker disappeared. Visual/arena/Pokemon/trainer/MoveFX caches stay intact.
    for _,theme in ipairs(THEMES) do cacheDelete(mod,theme.intro);cacheDelete(mod,theme.loop) end
    for _,shot in ipairs(ONE_SHOTS) do cacheDelete(mod,shot.output) end
    for _,path in ipairs({LEGACY_V2_PATH,LEGACY_V3_PATH,LEGACY_V4_PATH,LEGACY_V4_FALLBACK_PATH,
      LEGACY_V5_PATH,LEGACY_V5_FALLBACK_PATH,LEGACY_V6_PATH,LEGACY_V6_FALLBACK_PATH,".cbe-audio-v1.complete"}) do cacheDelete(mod,path) end
    progress("AUDIO CANONICAL / one-time v8 source-render migration",0,24)
'''
s = rep(s, old, new, "canonical migration transaction")
s = s.replace('A.portableFullMarker=PORTABLE_FULL_MARKER', 'A.canonicalFullMarker=PORTABLE_FULL_MARKER\nA.portableFullMarker=PORTABLE_FULL_MARKER')
s = rep(s, 'A.portableAssets=PORTABLE_ASSETS\nreturn A', 'A.portableAssets=PORTABLE_ASSETS\nA.runReferenceAmuse=A.run\nA.portableFullReady=A.canonicalFullReady\nreturn A', "reference renderer export")
p.write_text(s, encoding="utf-8")

# ---------------------------------------------------------------------------
# BuildPipeline: production uses only runCanonicalFull; audio is mandatory to
# attempt, but a proven failure is fail-open for the verified visual runtime.
# ---------------------------------------------------------------------------
p = ROOT/"extract/BuildPipeline.lua"
s = p.read_text(encoding="utf-8")
s = rep(s,
    'local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-portable=4\\nsource=GC6E01\\nassets=24\\nrate=32000\\nrenderer=lua-musyx-battle-fidelity-v3-loop-boundary\\n"\n',
    'local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-canonical=8\\nsource=GC6E01\\nassets=24\\nrate=48000\\nrenderer=lua-musyx-battle-canonical-v8\\n"\nlocal AUDIO_EXHAUSTED_MARKER="best-effort-all-renderers-v1\\ncanonical=8\\n"\n',
    "pipeline canonical marker")

s = sub(s,
    r'local function audioReady\(mod\)\n.*?\nend\nlocal function finishManifest',
    '''local function audioReady(mod)
  local canonical=false
  if AudioProbe and type(AudioProbe.canonicalFullReady)=="function" then
    local ok,ready=pcall(AudioProbe.canonicalFullReady,mod);canonical=ok and ready==true
  end
  if not canonical then return false end
  for _,p in ipairs(AUDIO_CORE) do if not exists(mod,p) then return false end end
  return true
end
local function audioExhausted(mod)
  return read(mod,".cbe-audio-exhausted-v1.complete")==AUDIO_EXHAUSTED_MARKER
end
local function finishManifest''',
    "pipeline audioReady", re.S)

s = sub(s,
    r'local function audioPlatformSupported\(\)\n.*?\nend\n\nlocal function audioOnly\(mod,progress\)\n.*?\nend\n\n-- Focused capture-bank migration',
    '''local function audioOnly(mod,progress)
  local generated=previousGenerated(mod)
  local state={cache_version=B.cacheVersion,extractor_revision=B.extractorRevision,
    current_stage="audio",message="Rendering canonical source-backed Colosseum audio",disc_id="GC6E01",
    disc_region="USA",visual_ready=1,audio_ready=0}
  local function save() write(mod,"build/state.txt",stateText(state),generated) end
  del(mod,"build/error.txt");del(mod,"build/audio_warning.txt");del(mod,"build/stage_audio.pending")

  if audioReady(mod) then
    stage(mod,"audio",generated);state.audio_ready=1;state.current_stage="ready";state.message="Runtime ready; canonical Colosseum audio cache 24/24"
    del(mod,".cbe-audio-exhausted-v1.complete");write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    save();finishManifest(mod,generated)
    return {state="READY",visualReady=true,audioReady=true,canonicalAudioReady=true,message=state.message}
  end

  -- A previous complete attempt that failed is intentionally reusable on an
  -- ordinary boot. Any visual/cache rebuild clears this marker via CacheManager.
  if audioExhausted(mod) then
    state.current_stage="ready_visual";state.message="Runtime ready; canonical Colosseum audio extraction previously failed"
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated);save();finishManifest(mod,generated)
    return {state="READY / AUDIO EXTRACTION FAILED",visualReady=true,audioReady=false,audioUnavailable=true,message=state.message}
  end

  save()
  local ok,result=pcall(function()
    assert(AudioProbe and type(AudioProbe.runCanonicalFull)=="function","canonical MusyX renderer unavailable")
    local disc=Disc.open(mod)
    local audio=AudioProbe.runCanonicalFull(mod,disc,progress,generated)
    assert(audio and audio.ready and tonumber(audio.complete)==24,("canonical audio cache incomplete (%s/24)"):format(tostring(audio and audio.complete or 0)))
    assert(audioReady(mod),"canonical audio renderer returned success but cache identity/assets failed validation")
    stage(mod,"audio_portable",generated);stage(mod,"audio",generated)
    state.portable_audio_ready=1;state.audio_ready=1;state.current_stage="ready";state.message="Runtime ready; canonical Colosseum audio cache 24/24"
    del(mod,".cbe-audio-exhausted-v1.complete");del(mod,"build/audio_warning.txt");del(mod,".cbe-audio-v1.complete")
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated);save();finishManifest(mod,generated)
    return {state="READY",visualReady=true,audioReady=true,canonicalAudioReady=true,message=state.message}
  end)
  if ok then return result end

  local msg=tostring(result)
  state.current_stage="ready_visual";state.audio_ready=0
  state.message="Runtime ready; canonical Colosseum audio extraction failed after renderer attempt: "..msg
  del(mod,"build/error.txt");write(mod,".cbe-audio-exhausted-v1.complete",AUDIO_EXHAUSTED_MARKER,generated)
  pcall(function()write(mod,"build/audio_diagnostic.txt",msg.."\\n",generated)end)
  pcall(function()write(mod,"build/audio_warning.txt",msg.."\\n",generated)end)
  write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated);save();finishManifest(mod,generated)
  return {state="READY / AUDIO EXTRACTION FAILED",visualReady=true,audioReady=false,audioUnavailable=true,message=state.message}
end

-- Focused capture-bank migration''',
    "canonical audioOnly", re.S)

# Explicit contract guard: production pipeline may not call the reference renderer.
if 'AudioProbe.run(' in s:
    raise SystemExit('production BuildPipeline still calls AudioProbe.run reference renderer')
p.write_text(s, encoding="utf-8")

# ---------------------------------------------------------------------------
# CacheManager reflects the canonical marker and exhaustion state.
# ---------------------------------------------------------------------------
p = ROOT/"lib/CacheManager.lua"
s = p.read_text(encoding="utf-8")
s = rep(s,
    'local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-portable=4\\nsource=GC6E01\\nassets=24\\nrate=32000\\nrenderer=lua-musyx-battle-fidelity-v3-loop-boundary\\n"\n',
    'local PORTABLE_AUDIO_FULL_MARKER="cbe-audio-canonical=8\\nsource=GC6E01\\nassets=24\\nrate=48000\\nrenderer=lua-musyx-battle-canonical-v8\\n"\nlocal AUDIO_EXHAUSTED_MARKER="best-effort-all-renderers-v1\\ncanonical=8\\n"\n',
    "cache canonical marker")
s = s.replace('read(".cbe-audio-portable-v4.complete")', 'read(".cbe-audio-canonical-v8.complete")')
s = s.replace('read("build/audio_portable_v4.complete")', 'read("build/audio_canonical_v8.complete")')
s = rep(s,
    '  local audioReady=#audioMissing==0 and (audioMarker==AUDIO_MARKER or portableAudioReady)\n  local fullRuntimeReady=visualReady and audioReady and marker=="cbe-runtime=2\\nextractor=15\\n"\n  local runtimeReady=visualReady\n',
    '  local audioReady=#audioMissing==0 and portableAudioReady\n  local audioExhausted=read(".cbe-audio-exhausted-v1.complete")==AUDIO_EXHAUSTED_MARKER\n  local fullRuntimeReady=visualReady and audioReady and marker=="cbe-runtime=2\\nextractor=15\\n"\n  local runtimeReady=visualReady and (audioReady or audioExhausted)\n',
    "cache runtime readiness")
s = rep(s,
    '  if fullRuntimeReady then status="RUNTIME READY"\n',
    '  if fullRuntimeReady then status="RUNTIME READY"\n  elseif runtimeReady and audioExhausted then status="RUNTIME READY / AUDIO EXTRACTION FAILED"\n',
    "cache exhausted status")
# Ensure manual generated-cache reset clears canonical transaction/exhaustion markers.
s = rep(s,
    '".cbe-audio-portable-v4.pending","build/audio_portable_v4.complete","build/audio_portable_v4.migrating",',
    '".cbe-audio-portable-v4.pending","build/audio_portable_v4.complete","build/audio_portable_v4.migrating",".cbe-audio-canonical-v8.complete",".cbe-audio-canonical-v8.pending","build/audio_canonical_v8.complete","build/audio_canonical_v8.migrating",".cbe-audio-exhausted-v1.complete",',
    "cache reset canonical markers")
p.write_text(s, encoding="utf-8")

# Recovery note is intentionally explicit that this is reconstructed, not the
# vanished byte-identical archive.
(ROOT/"RECOVERY_1.8.8.md").write_text(f'''# CBE {VERSION}\n\nThis package is a recovery rebuild created after the original ChatGPT-hosted 1.8.8 archive became unavailable during a platform incident. It is reconstructed from the last materialized 1.8.4 source plus the recorded 1.8.5-1.8.8 source/audio corrections. It is not represented as byte-identical to the vanished archive.\n\nRecovery targets retained here:\n- one source-backed canonical MusyX renderer/cache identity on Windows and Android/non-Windows;\n- 24/24 soundtrack cache transaction with redundant completion markers;\n- old native/portable audio markers cannot satisfy canonical readiness;\n- source-correct packed signed continuous pitch/mod decoding;\n- source note-length key-off, same-note retrigger, sustain/RPN pitch automation, fresh DSP history and source loop boundaries;\n- presentation-only Pokemon/trainer animation clocks invariant to battle fast-forward;\n- audio attempt is required, while a proven renderer failure fails open to the verified visual runtime without repeating every boot.\n''', encoding="utf-8")

print("recovery patch applied", VERSION)
