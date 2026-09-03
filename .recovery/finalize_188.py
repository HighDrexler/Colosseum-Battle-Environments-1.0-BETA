from pathlib import Path
import re

ROOT=Path(__file__).resolve().parents[1]
p=ROOT/'extract/BuildPipeline.lua'
s=p.read_text(encoding='utf-8')

# Existing verified visual runtime: canonical cache hit or the common audio-only
# repair path. Remove the old platform split here first so the cold-cache rewrite
# below cannot accidentally begin at this earlier occurrence.
early_pattern=r'''  if visualReady\(mod\) then\n    if audioReady\(mod\) then\n      return \{state="READY",visualReady=true,audioReady=true,message="Persistent generated runtime already present; audio cache reused\."\}\n    end\n.*?    return audioOnly\(mod,progress\)\n  end\n'''
early_replacement='''  if visualReady(mod) then
    if audioReady(mod) then
      return {state="READY",visualReady=true,audioReady=true,message="Persistent generated runtime already present; canonical audio cache reused."}
    end
    return audioOnly(mod,progress)
  end
'''
s,n=re.subn(early_pattern,lambda m: early_replacement,s,count=1,flags=re.S)
if n!=1:
    raise SystemExit(f'visual-ready audio fastpath patch failed: {n}')

# Full cold-cache builder: after visual verification, run the same canonical
# renderer on every host instead of the old Windows/non-Windows split.
pattern=r'''    local audioSupported,osName=audioPlatformSupported\(\)\n.*?    return \{state="READY",visualReady=true,audioReady=true,files=#disc\.files,fsys=fsysCount,trainerResolved=state\.trainer_resolved,trainerTotal=state\.trainer_total,trainerDiagnostic=state\.trainer_diagnostic,message=state\.message\}\n'''
replacement='''    state.current_stage="audio";state.audio_ready=0
    state.message="Generating canonical source-backed Colosseum soundtrack cache";saveState();update("CANONICAL AUDIO 1/24",8,9)
    assert(AudioProbe and type(AudioProbe.runCanonicalFull)=="function","canonical MusyX renderer unavailable")
    local audio=AudioProbe.runCanonicalFull(mod,disc,function(label,c,t)update(label,c,t)end,generated)
    assert(audio and audio.ready and tonumber(audio.complete)==24,("canonical audio cache incomplete (%s/24)"):format(tostring(audio and audio.complete or 0)))
    assert(audioReady(mod),"canonical renderer returned success but cache identity/assets failed validation")
    stage(mod,"audio_portable",generated);stage(mod,"audio",generated)
    state.portable_audio_ready=1;state.audio_ready=1;state.current_stage="ready"
    state.message="Runtime ready; canonical Colosseum soundtrack cache 24/24"
    del(mod,"build/audio_warning.txt");del(mod,".cbe-audio-v1.complete");del(mod,".cbe-audio-exhausted-v1.complete")
    write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)
    saveState();finishManifest(mod,generated);update("RUNTIME READY / AUDIO 24/24",9,9)
    return {state="READY",visualReady=true,audioReady=true,canonicalAudioReady=true,files=#disc.files,fsys=fsysCount,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,message=state.message}
'''
s,n=re.subn(pattern,lambda m: replacement,s,count=1,flags=re.S)
if n!=1:
    raise SystemExit(f'cold-cache audio block patch failed: {n}')

# A real attempted canonical failure is fail-open only for the already-verified
# visual runtime and records exhaustion so ordinary boots do not recache forever.
pattern=r'''    if \(failedStage=="audio" or failedStage=="audio_portable"\) and visualSurvived then\n.*?      return \{state="READY / AUDIO OPTIONAL",visualReady=true,audioReady=false,audioUnavailable=true,trainerResolved=state\.trainer_resolved,trainerTotal=state\.trainer_total,trainerDiagnostic=state\.trainer_diagnostic,trainerFirstError=state\.trainer_first_error,trainerSourceError=state\.trainer_source_error,message=state\.message\}\n    end'''
replacement='''    if (failedStage=="audio" or failedStage=="audio_portable") and visualSurvived then
      state.current_stage="ready_visual";state.audio_ready=0
      state.message="Runtime ready; canonical Colosseum audio extraction failed after renderer attempt: "..msg
      del(mod,"build/error.txt");del(mod,".cbe-audio-v1.complete")
      pcall(function()write(mod,".cbe-audio-exhausted-v1.complete",AUDIO_EXHAUSTED_MARKER,generated)end)
      pcall(function()write(mod,"build/audio_diagnostic.txt",msg.."\\n",generated)end)
      pcall(function()write(mod,"build/audio_warning.txt",msg.."\\n",generated)end)
      pcall(function()write(mod,"build/state.txt",stateText(state),nil)end)
      pcall(function()write(mod,".cbe-visual-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()write(mod,".cbe-runtime-v2.complete",EXPECTED_MARKER,generated)end)
      pcall(function()finishManifest(mod,generated)end)
      return {state="READY / AUDIO EXTRACTION FAILED",visualReady=true,audioReady=false,audioUnavailable=true,trainerResolved=state.trainer_resolved,trainerTotal=state.trainer_total,trainerDiagnostic=state.trainer_diagnostic,trainerFirstError=state.trainer_first_error,trainerSourceError=state.trainer_source_error,message=state.message}
    end'''
s,n=re.subn(pattern,lambda m: replacement,s,count=1,flags=re.S)
if n!=1:
    raise SystemExit(f'cold-cache audio failure block patch failed: {n}')

if 'audioPlatformSupported' in s or 'AudioProbe.runPortableFull' in s or 'AudioProbe.run(' in s:
    raise SystemExit('platform-split/reference audio call remains in production BuildPipeline')
p.write_text(s,encoding='utf-8')

# Recovery patch typo: startSec is already seconds.
p=ROOT/'extract/PortableMusyX.lua'
s=p.read_text(encoding='utf-8').replace('v.keyoff=max(0,absSec-v.startSec/outputRate)','v.keyoff=max(0,absSec-v.startSec)')
p.write_text(s,encoding='utf-8')

print('finalized canonical full-build path')
