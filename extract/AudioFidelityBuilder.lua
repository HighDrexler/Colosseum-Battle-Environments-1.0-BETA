-- Optional, restart-time music/cue upgrade. Keeps v9/model caches and resumes
-- completed source units. A small durable write journal protects intro/loop
-- pairs AND their metadata; recovery runs before the ordinary startup gate.
local V=...
local F,P,FSYS,A,S,B=assert(V.AudioFidelity),assert(V.PortableMusyX),assert(V.FSYS),assert(V.AudioProbe),assert(V.BattleAudioSpec),assert(V.BattleAudioBuilder)
local U={version=1}
local TX=F.root.."transaction/"
local JOURNAL,COMMIT=TX.."journal.txt",TX.."committed.txt"
local function validPath(path)
  return type(path)=="string" and (path:match("^assets/audio/[%w_./%-]+$") or path:match("^build/[%w_./%-]+$"))
    and not path:find("..",1,true) and path:sub(1,#TX)~=TX
end
-- Missing is different from present-but-unreadable. Never treat a failed old
-- asset read as an absent original, or skip a journal known to exist.
local function durableRead(mod,path)
  local bytes=F.read(mod,path)
  if mod.cache and type(mod.cache.info)=="function" then
    local ok,info=pcall(mod.cache.info,mod.cache,path)
    assert(ok,"audio transaction info failed: "..path)
    if info and info.type~="directory" then
      assert(type(bytes)=="string","audio transaction file unreadable: "..path)
      local size=tonumber(info.size)
      assert(not size or #bytes==size,"audio transaction read truncated: "..path)
    end
  end
  return bytes
end
local function decodeJournal(raw)
  assert(type(raw)=="string" and raw:sub(1,24)=="cbe-audio-transaction=1\n", "invalid audio transaction journal")
  local rows={}
  for line in raw:gmatch("[^\n]+") do
    if line:sub(1,5)=="file\t" then
      local path,present,oldSize,oldHash,newSize,newHash=line:match("^file\t([^\t]+)\t([01])\t(%d+)\t(%x+)\t(%d+)\t(%x+)$")
      assert(validPath(path) and #rows<16,"unsafe audio transaction entry")
      rows[#rows+1]={path=path,old=present=="1",oldSize=tonumber(oldSize),oldHash=oldHash,newSize=tonumber(newSize),newHash=newHash}
    end
  end
  assert(#rows>0,"empty audio transaction journal")
  return rows
end
local function matches(bytes,size,hash)return type(bytes)=="string" and #bytes==size and F.checksum(bytes)==hash end
local function cleanup(mod,rows)
  -- Journal first: after a verified commit/rollback no recovery is required.
  F.remove(mod,JOURNAL)
  for i=1,#rows do pcall(F.remove,mod,TX.."old_"..i);pcall(F.remove,mod,TX.."new_"..i) end
  pcall(F.remove,mod,COMMIT)
end
function U.recover(mod)
  local raw=durableRead(mod,JOURNAL)
  if not raw then return true end
  local rows=decodeJournal(raw)
  local committed=F.read(mod,COMMIT)==F.checksum(raw)
  if committed then
    for _,r in ipairs(rows) do if not matches(F.read(mod,r.path),r.newSize,r.newHash) then committed=false;break end end
  end
  if not committed then
    -- Verify EVERY backup before touching any target. If storage is damaged,
    -- leave the journal intact rather than claiming an unsafe cache is ready.
    local backups={}
    for i,r in ipairs(rows) do
      if r.old then
        local bytes=F.read(mod,TX.."old_"..i)
        assert(matches(bytes,r.oldSize,r.oldHash),"audio rollback backup damaged: "..r.path)
        backups[i]=bytes
      end
    end
    for i,r in ipairs(rows) do
      if r.old then F.write(mod,r.path,backups[i]) else F.remove(mod,r.path) end
    end
  end
  cleanup(mod,rows)
  return true
end
function U.commit(mod,writes)
  U.recover(mod)
  assert(type(writes)=="table" and #writes>0 and #writes<=16,"invalid audio transaction")
  local lines={"cbe-audio-transaction=1\n"};local paths={}
  F.remove(mod,COMMIT)
  for i,w in ipairs(writes) do
    assert(validPath(w.path) and not paths[w.path] and type(w.bytes)=="string","invalid audio transaction write")
    paths[w.path]=true
    local old=durableRead(mod,w.path)
    if old then F.write(mod,TX.."old_"..i,old) else F.remove(mod,TX.."old_"..i) end
    F.write(mod,TX.."new_"..i,w.bytes)
    lines[#lines+1]=table.concat({"file",w.path,old and "1" or "0",tostring(old and #old or 0),F.checksum(old or ""),tostring(#w.bytes),F.checksum(w.bytes)},"\t").."\n"
  end
  local raw=table.concat(lines);F.write(mod,JOURNAL,raw)
  local ok,why=pcall(function()
    for _,w in ipairs(writes) do F.write(mod,w.path,w.bytes) end
    F.write(mod,COMMIT,F.checksum(raw))
  end)
  if not ok then
    local recovered,recoveryError=pcall(U.recover,mod)
    error(tostring(why)..(recovered and " (previous audio restored)" or " / RECOVERY REQUIRED: "..tostring(recoveryError)),0)
  end
  -- Failed housekeeping does not undo a verified commit; next boot completes it.
  pcall(cleanup,mod,decodeJournal(raw))
  return true
end
local function member(ar,name)
  for _,e in ipairs(ar:list())do
    local n=e.name:lower()
    if n==name or n==name..".fdat" or n==name..".dat" then return assert(ar:extract(e,{maxOutput=64*1024*1024})) end
  end
  error("audio fidelity source missing: "..name,0)
end
function U.plan()
  local out={}
  for _,t in ipairs(A.themes) do out[#out+1]={id=t.source,sequence=t.source,setup=t.setup,rate=48000,loop=true,paths={t.intro,t.loop},soundtrack=true} end
  out[#out+1]={id="me_snatch_song",sequence="me_snatch_song",setup=9,rate=48000,paths={"assets/audio/capture/me_snatch.wav"},soundtrack=true}
  out[#out+1]={id="fanfare00_song",sequence="fanfare00_song",setup=12,rate=48000,paths={"assets/audio/intro/fanfare00.wav"},boss=true}
  for _,c in ipairs(S.cues) do out[#out+1]={id=c.id,sequence=c.sequence,setup=c.setup,rate=c.rate,paths={c.path},cue=c} end
  return out
end
function U.run(mod,openDisc,progress)
  U.recover(mod)
  local quality=F.pending(mod)
  if not quality then return {ready=true,requested=false,built=0,reused=0} end
  progress=progress or function()end
  local plan=U.plan();local result={requested=true,ready=true,quality=quality,complete=0,total=#plan,built=0,reused=0,units={}}
  local disc,common,bgm,music,sfx
  local function report(state,err)
    local raw=("cbe-audio-fidelity-status=1\nstate=%s\nquality=%s\ncomplete=%d\ntotal=%d\n"):format(state,quality,result.complete,result.total)
    if err then raw=raw.."error="..tostring(err):gsub("[\r\n]+"," ").."\n" end
    F.write(mod,F.reportPath,raw)
  end
  local function source()
    if not disc then disc=assert(openDisc(),"Colosseum source unavailable") end
    if not common then common=FSYS.open(disc,assert(disc:file("common.fsys"))) end
  end
  local function direct(name)return assert(disc:readFile(assert(disc:file(name))))end
  report("building")
  for _,unit in ipairs(plan) do
    local hit=true
    for _,path in ipairs(unit.paths) do if not F.assetReady(mod,path,nil,quality) then hit=false;break end end
    if hit then
      result.reused=result.reused+1;result.complete=result.complete+1
      result.units[#result.units+1]={id=unit.id,cached=true}
    else
      local ok,why=pcall(function()
        progress("AUDIO FIDELITY / "..quality:upper().." / "..unit.id,result.complete,#plan)
        source()
        local function heartbeat(frame,total)
          progress("AUDIO FIDELITY / "..quality:upper().." / "..unit.id,result.complete+math.min(.95,(frame or 0)/math.max(1,total or 1)),#plan)
        end
        local outputs,stats={}
        if unit.id=="exp" then
          sfx=sfx or P.prepareSfx({sfx={proj=member(common,"snd_se_proj"),pool=member(common,"snd_se_pool"),sdir=member(common,"snd_se_sdir"),samp=direct("snd_se.samp")}})
          B.validateExpSource(member(common,"common_rel"),sfx)
          outputs[1],stats=P.renderSfx(sfx,S.expSfx,unit.rate,heartbeat,{quality=quality})
          outputs[1]=B.trimExp(outputs[1],stats)
        else
          music=music or P.prepare({music={proj=member(common,"snd_music_proj"),pool=member(common,"snd_music_pool"),sdir=member(common,"snd_music_sdir"),samp=direct("snd_music.samp")}})
          bgm=bgm or FSYS.open(disc,assert(disc:file("bgm_archive.fsys")))
          outputs[1],outputs[2],stats=P.renderSong(music,member(bgm,unit.sequence),unit.setup,unit.loop or nil,unit.rate,heartbeat,{quality=quality})
        end
        assert(stats and stats.peak>0.000001,"silent audio fidelity render")
        local writes,assets={},{}
        for i,path in ipairs(unit.paths) do
          local bytes=outputs[i]
          assert(P.validWav(bytes) and #bytes>44,"invalid audio fidelity output: "..path)
          assets[path]=#bytes
          writes[#writes+1]={path=path,bytes=bytes}
          writes[#writes+1]={path=F.stampPath(path),bytes=F.stamp(path,bytes,quality)}
        end
        if unit.soundtrack then
          writes[#writes+1]={path=A.portableLedgerPath,bytes=A.fidelityLedger(mod,assets)}
        elseif unit.boss then
          writes[#writes+1]={path=A.bossMarkerPath,bytes=A.bossMarker(outputs[1])}
        elseif unit.cue then
          writes[#writes+1]={path=S.markerPath(unit.cue),bytes=S.marker(unit.cue,outputs[1])}
        end
        U.commit(mod,writes)
        result.built=result.built+1;result.complete=result.complete+1
        result.units[#result.units+1]={id=unit.id,frames=stats.frames,peak=stats.peak,clipped=stats.clipped,quality=quality}
      end)
      if not ok then
        result.ready=false;result.error=tostring(why)
        local safe=pcall(U.recover,mod);result.recoveryRequired=not safe
        pcall(report,"incomplete",why)
        return result
      end
    end
    report("building")
    progress("AUDIO FIDELITY / "..result.complete.." OF "..#plan.." READY",result.complete,#plan)
  end
  report("ready")
  F.remove(mod,F.requestPath)
  return result
end
U.journalPath,U.commitPath=JOURNAL,COMMIT
return U
