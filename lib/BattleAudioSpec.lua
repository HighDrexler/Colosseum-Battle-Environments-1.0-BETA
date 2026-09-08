-- Small, independently versioned reward-audio cache. Does not invalidate v9 BGM.
local S={version=1,source="GC6E01",expGameSound=1232,expGroup=6,expSfx=975,expMacro=390,expCycleMs=48}
S.cues={
 {id="exp",path="assets/audio/battle_cues/exp_gain.wav",rate=32000},
 {id="level",path="assets/audio/battle_cues/level_up.wav",rate=48000,sequence="level_up_song",setup=1},
 {id="victory",path="assets/audio/battle_cues/victory.wav",rate=48000,sequence="me_win_song",setup=10},
}
S.levelNames={Level_Up=true,Sfx_DexFanfare5079=true}
function S.markerPath(cue)return "build/battle_audio_v1/"..cue.id..".complete"end
local function le(s,o,n)local v=0;for i=n-1,0,-1 do local b=s:byte(o+i);if not b then return nil end;v=v*256+b end;return v end
function S.validWav(bytes,rate)
 if type(bytes)~="string" or #bytes<48 or #bytes>4*1024*1024 then return false end
 return bytes:sub(1,4)=="RIFF" and bytes:sub(9,16)=="WAVEfmt " and le(bytes,5,4)==#bytes-8
  and le(bytes,17,4)==16 and le(bytes,21,2)==1 and le(bytes,23,2)==2
  and le(bytes,25,4)==rate and le(bytes,29,4)==rate*4 and le(bytes,33,2)==4
  and le(bytes,35,2)==16 and bytes:sub(37,40)=="data" and le(bytes,41,4)==#bytes-44
  and (#bytes-44)%4==0
end
function S.checksum(bytes)
 local a,b=1,0
 for i=1,#bytes do a=(a+bytes:byte(i))%65521;b=(b+a)%65521 end
 return string.format("%08x",b*65536+a)
end
function S.marker(cue,bytes)
 return ("cbe-battle-audio=%d\nsource=%s\ncue=%s\nrate=%d\nbytes=%d\nadler32=%s\n"):format(S.version,S.source,cue.id,cue.rate,#bytes,S.checksum(bytes))
end
function S.ready(cue,bytes,marker)
 return S.validWav(bytes,cue.rate) and marker==S.marker(cue,bytes)
end
return S
