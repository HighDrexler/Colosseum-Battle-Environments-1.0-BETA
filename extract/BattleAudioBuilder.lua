-- Builds only three small source-backed cues. Completed cues survive interruption;
-- neither the full soundtrack's v9 marker nor model/arena caches are touched.
local V=...
local P,F,S=assert(V.PortableMusyX),assert(V.FSYS),assert(V.BattleAudioSpec)
local B={version=1}
local Fidelity=V.AudioFidelity
local function read(cache,path)
 local ok,b=pcall(cache.read,cache,path);return ok and type(b)=="string" and b or nil
end
local function write(cache,path,bytes)
 local ok,a,b=pcall(cache.write,cache,path,bytes)
 assert(ok and a~=false and a~=nil,"battle audio write failed: "..path.." / "..tostring(b or a))
 assert(read(cache,path)==bytes,"battle audio readback failed: "..path)
end
local function member(archive,name)
 for _,e in ipairs(archive:list())do
  local n=e.name:lower()
  if n==name or n==name..".fdat" or n==name..".dat" then
   return assert(archive:extract(e,{maxOutput=64*1024*1024}))
  end
 end
 error("battle audio source missing: "..name,0)
end
local function be16(bytes,at)local a,b=bytes:byte(at,at+1);assert(b,"truncated source table");return a*256+b end
function B.validateExpSource(rel,ctx)
 local o=0x141654+S.expGameSound*12+1
 assert(type(rel)=="string" and #rel>=0x14BF3C,"GC6E01 GameSound table truncated")
 assert(be16(rel,0x14BF38+1)==0 and be16(rel,0x14BF3A+1)==1236,"GameSound count mismatch")
 assert(rel:byte(o)>=128 and rel:byte(o+1)==S.expGroup and be16(rel,o+4)==S.expSfx,"EXP GameSound mapping mismatch")
 assert(ctx.project.groupId==S.expGroup and P.hasSfx(ctx,S.expSfx),"EXP SFX group mismatch")
 -- Source macro: SetNote 68, StartSample 9, WaitMs 48, Loop to step 1.
 -- Looping the renderer's release tail would introduce a false gap at every tick.
 local macro=assert(ctx.pool.macros[S.expMacro],"EXP SoundMacro missing")
 assert(macro:sub(25,56)==string.char(0,0,68,25,0,0,1,0,0,0,9,16,0,0,0,0,
  1,0,0,7,0,48,0,0,0,0,1,5,255,255,0,0),"EXP source cycle changed")
end
local function le32(n)return string.char(n%256,math.floor(n/256)%256,math.floor(n/65536)%256,math.floor(n/16777216)%256)end
function B.trimExp(wav,stats)
 local cue=S.cues[1]
 assert(S.validWav(wav,cue.rate),"invalid EXP render")
 assert(stats and stats.entry and stats.entry.obj==S.expMacro,"EXP SFX resolves to wrong macro")
 local n=math.floor(cue.rate*S.expCycleMs/1000)*4
 assert(#wav-44>=n,"EXP render shorter than source cycle")
 return wav:sub(1,4)..le32(n+36)..wav:sub(9,40)..le32(n)..wav:sub(45,44+n)
end
function B.run(mod,openDisc,progress)
 assert(mod and mod.cache,"battle audio cache unavailable")
 progress=progress or function()end
 local cache=mod.cache
 local quality=Fidelity and Fidelity.resolve(mod) or "fast"
 local result={ready=true,complete=0,built=0,reused=0,total=#S.cues,errors={},cues={}}
 local disc,common,bgm,music,sfx
 local function source()
  if not disc then disc=assert(openDisc(),"Colosseum source unavailable")end
  if not common then common=F.open(disc,assert(disc:file("common.fsys")))end
 end
 local function direct(name)return assert(disc:readFile(assert(disc:file(name))))end
 for i,cue in ipairs(S.cues)do
  local wav=read(cache,cue.path)
  if S.ready(cue,wav,read(cache,S.markerPath(cue))) then
   result.reused=result.reused+1;result.complete=result.complete+1;result.cues[cue.id]={cached=true,bytes=#wav}
  else
   local ok,why=pcall(function()
    progress("BATTLE AUDIO / "..cue.id:upper(),i-1,#S.cues)
    source()
    local stats
    local function heartbeat(frame,total)
     progress("BATTLE AUDIO / "..cue.id:upper(),i-1+math.min(.95,(frame or 0)/math.max(1,total or 1)),#S.cues)
    end
    if cue.id=="exp" then
     sfx=sfx or P.prepareSfx({sfx={proj=member(common,"snd_se_proj"),pool=member(common,"snd_se_pool"),
      sdir=member(common,"snd_se_sdir"),samp=direct("snd_se.samp")}})
     B.validateExpSource(member(common,"common_rel"),sfx)
     wav,stats=P.renderSfx(sfx,S.expSfx,cue.rate,heartbeat,{quality=quality})
     wav=B.trimExp(wav,stats)
    else
     music=music or P.prepare({music={proj=member(common,"snd_music_proj"),pool=member(common,"snd_music_pool"),
      sdir=member(common,"snd_music_sdir"),samp=direct("snd_music.samp")}})
     bgm=bgm or F.open(disc,assert(disc:file("bgm_archive.fsys")))
     local unused;wav,unused,stats=P.renderSong(music,member(bgm,cue.sequence),cue.setup,nil,cue.rate,heartbeat,{quality=quality})
    end
    assert(S.validWav(wav,cue.rate) and stats and stats.peak>0.000001,"silent/invalid battle cue")
    -- The marker authenticates THIS exact file, not just its presence. A partial
    -- write or interrupted overwrite can never be promoted as ready.
    write(cache,cue.path,wav)
    write(cache,S.markerPath(cue),S.marker(cue,wav))
    if Fidelity then Fidelity.record(mod,cue.path,wav,quality) end
    result.built=result.built+1;result.complete=result.complete+1
    result.cues[cue.id]={bytes=#wav,frames=(#wav-44)/4,peak=stats.peak,voices=stats.voices,clipped=stats.clipped}
   end)
   if not ok then result.ready=false;result.errors[cue.id]=tostring(why)end
  end
  progress("BATTLE AUDIO / "..result.complete.." READY",i,#S.cues)
 end
 return result
end
return B
