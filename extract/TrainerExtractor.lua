local V=...
local HSD,FSYS=V.HSD,V.FSYS
local T={}
local TARGETS={
  -- Battle actors are selected by authoritative GC6E01 member name.  The old
  -- vertex-count heuristic could call a Cipher agent "Wes", a gym NPC
  -- "Brendan", and a generic trainer "Dakim".  Apart from being the wrong
  -- people, several of those A1 field meshes are unsuitable battle bind poses.
  -- B1 members are the disc's battle models and are stable extraction inputs.
  {id="red",modelId=0x02,height=16.101305,verts=2550,scaleMul=1.62,playerScaleMul=1.00,pivotY=7.4,exactArchive="people_archive.fsys",exactName="akami_m_b1.dat",directSource=true},
  {id="leaf",modelId=0x03,height=15.735957,verts=2328,scaleMul=1.66,playerScaleMul=1.02,pivotY=7.3,exactArchive="people_archive.fsys",exactName="akami_f_b1.dat",directSource=true},
  {id="wes",modelId=0x01,height=17.406225,verts=3069,scaleMul=1.50,playerScaleMul=.93,pivotY=8.0,exactArchive="field_common.fsys",exactName="ken_b1.dat",directSource=true},
  -- Identity audit against the known-good source caches and GC6E01 battle assets:
  -- akami_* are the Kanto Red/Leaf battle actors; agb_* are Brendan/May.
  -- Keep these as separate exact members. Never alias Red/Leaf to the Hoenn pair.
  {id="brendan",modelId=0x0B,height=16.86189,verts=2442,scaleMul=1.55,playerScaleMul=.96,pivotY=7.7,exactArchive="people_archive.fsys",exactName="agb_m_b1.dat",directSource=true},
  {id="may",modelId=0x0A,height=16.25281,verts=2493,scaleMul=1.60,playerScaleMul=.99,pivotY=7.5,exactArchive="people_archive.fsys",exactName="agb_f_b1.dat",directSource=true},
  {id="cooltrainer_m",modelId=0x35,height=17.69574,verts=3105,scaleMul=1.47,pivotY=8.1,exactArchive="people_archive.fsys",exactName="traner_m_b1.dat",directSource=true},
  {id="cooltrainer_f",modelId=0x36,height=16.49731,verts=2283,scaleMul=1.58,pivotY=7.6,exactArchive="people_archive.fsys",exactName="traner_f_b1.dat",directSource=true},
  {id="dakim",modelId=0x0D,height=34.61308,verts=2544,scaleMul=1.0,playerScaleMul=.62,pivotY=12.8,exactArchive="people_archive.fsys",exactName="battleyama_b1.dat",directSource=true,nativeIdleProbe=true},
  {id="nascour",modelId=0x11,height=22.98924,verts=2415,scaleMul=1.48,playerScaleMul=.92,pivotY=12.2,exactArchive="people_archive.fsys",exactName="boss999_b1.dat",directSource=true},
  {id="miror_b",modelId=0x0F,height=26.78492,verts=2361,scaleMul=1.28,playerScaleMul=.80,pivotY=11.3,exactArchive="people_archive.fsys",exactName="boss555_b1.dat",directSource=true},
}
local function q(s)return string.format("%q",s) end
local function num(x)if x~=x or x==math.huge or x==-math.huge then return "0" end;return ("%.7g"):format(x) end
local function signature(tex)
  if not tex then return "none" end
  return table.concat({tex.w,tex.h,tex.format,tex.rgba:sub(1,48)},":")
end
local function normalize(model,targetHeight)
  local mn,mx=model.bounds.min,model.bounds.max;local h=math.max(1e-6,mx[2]-mn[2]);local s=targetHeight/h
  local cx=(mn[1]+mx[1])/2;local cz=(mn[3]+mx[3])/2
  local nmin={1e30,1e30,1e30};local nmax={-1e30,-1e30,-1e30}
  for _,g in ipairs(model.groups) do for _,v in ipairs(g.vertices) do
    v[1]=(v[1]-cx)*s;v[2]=(v[2]-mn[2])*s;v[3]=(v[3]-cz)*s
    for k=1,3 do if v[k]<nmin[k] then nmin[k]=v[k] end;if v[k]>nmax[k] then nmax[k]=v[k] end end
  end end
  model.bounds={min=nmin,max=nmax,center={(nmin[1]+nmax[1])/2,(nmin[2]+nmax[2])/2,(nmin[3]+nmax[3])/2}}
  return model
end
-- Normalize a second native-pose sample against the BASE pose transform.
-- This preserves authored joint motion instead of independently re-centering
-- each frame, which would turn ordinary idle translation into fake deformation.
local function normalizeLike(model,targetHeight,referenceBounds)
  if not (model and model.bounds and referenceBounds) then return model end
  local mn,mx=referenceBounds.min,referenceBounds.max
  local h=math.max(1e-6,mx[2]-mn[2]);local s=targetHeight/h
  local cx=(mn[1]+mx[1])/2;local cz=(mn[3]+mx[3])/2
  local nmin={1e30,1e30,1e30};local nmax={-1e30,-1e30,-1e30}
  for _,g in ipairs(model.groups or {}) do for _,v in ipairs(g.vertices or {}) do
    v[1]=(v[1]-cx)*s;v[2]=(v[2]-mn[2])*s;v[3]=(v[3]-cz)*s
    for k=1,3 do if v[k]<nmin[k] then nmin[k]=v[k] end;if v[k]>nmax[k] then nmax[k]=v[k] end end
  end end
  model.bounds={min=nmin,max=nmax,center={(nmin[1]+nmax[1])/2,(nmin[2]+nmax[2])/2,(nmin[3]+nmax[3])/2}}
  return model
end
local function alignSampleFeet(base,sample,height)
  if not (base and sample and #(base.groups or {})==#(sample.groups or {})) then return false end
  local floorY=base.bounds and base.bounds.min and base.bounds.min[2] or 0
  local limit=floorY+math.max(.001,height or 1)*.12
  local dx,dy,dz,n=0,0,0,0
  for gi,g in ipairs(base.groups or {}) do
    local sg=sample.groups[gi];if not sg or #(g.vertices or {})~=#(sg.vertices or {}) then return false end
    for vi,v in ipairs(g.vertices or {}) do if (v[2] or 0)<=limit then
      local q=sg.vertices[vi];dx=dx+((q[1] or 0)-(v[1] or 0));dy=dy+((q[2] or 0)-(v[2] or 0));dz=dz+((q[3] or 0)-(v[3] or 0));n=n+1
    end end
  end
  if n<12 then return true end
  dx,dy,dz=dx/n,dy/n,dz/n
  local mn={1e30,1e30,1e30};local mx={-1e30,-1e30,-1e30}
  for _,g in ipairs(sample.groups or {}) do for _,q in ipairs(g.vertices or {}) do
    q[1]=q[1]-dx;q[2]=q[2]-dy;q[3]=q[3]-dz
    for k=1,3 do if q[k]<mn[k] then mn[k]=q[k] end;if q[k]>mx[k] then mx[k]=q[k] end end
  end end
  sample.bounds={min=mn,max=mx,center={(mn[1]+mx[1])/2,(mn[2]+mx[2])/2,(mn[3]+mx[3])/2}}
  return true
end
local function poseRmsRatio(base,sample,height)
  if not (base and sample and #(base.groups or {})==#(sample.groups or {})) then return nil end
  local H=math.max(.001,height or 1);local half=math.max(.001,math.abs(base.bounds.min[1] or 0),math.abs(base.bounds.max[1] or 0))
  local sum,n=0,0
  -- Score the arm/upper-body band rather than whole-body root translation or
  -- Dakim's long lower garment. The sample is foot-aligned first, then this
  -- metric looks for a readable but non-extreme change in his actual silhouette.
  for gi,g in ipairs(base.groups or {}) do
    local sg=sample.groups[gi];if not sg or #(g.vertices or {})~=#(sg.vertices or {}) then return nil end
    for vi,v in ipairs(g.vertices or {}) do
      local yn=((v[2] or 0)-(base.bounds.min[2] or 0))/H;local side=math.abs(v[1] or 0)/half
      if yn>=.30 and yn<=.76 and side>=.18 then
        local q=sg.vertices[vi];local dx=(q[1] or 0)-(v[1] or 0);local dy=(q[2] or 0)-(v[2] or 0);local dz=(q[3] or 0)-(v[3] or 0)
        sum=sum+dx*dx+dy*dy+dz*dz;n=n+1
      end
    end
  end
  if n<24 then return nil end
  return math.sqrt(sum/n)/H
end
local function attachIdleSample(base,sample)
  if not (base and sample and #(base.groups or {})==#(sample.groups or {})) then return false end
  for gi,g in ipairs(base.groups or {}) do
    local sg=sample.groups[gi];if not sg or #(g.vertices or {})~=#(sg.vertices or {}) then return false end
  end
  for gi,g in ipairs(base.groups or {}) do
    local sg=sample.groups[gi]
    for vi,v in ipairs(g.vertices or {}) do local q=sg.vertices[vi];v[9]=q[1];v[10]=q[2];v[11]=q[3] end
  end
  return true
end

local function mergeGroups(model)
  local map,out={},{}
  for _,g in ipairs(model.groups) do
    local key=signature(g.texture);local dst=map[key]
    if not dst then dst={vertices={},texture=g.texture};map[key]=dst;out[#out+1]=dst end
    for _,v in ipairs(g.vertices) do dst.vertices[#dst.vertices+1]=v end
  end
  model.groups=out;return model
end
local function cacheLua(target,model,texturePaths,sourceName)
  local b=model.bounds;local out={"-- Generated locally from the user's Pokemon Colosseum GC6E01 disc.\nreturn {formatVersion=21,morphFormat=\"source-hsd-native-nonbind-v4-dakim-idle\",source=",q("Pokemon Colosseum / "..target.id.." / "..sourceName),",bounds={min={",num(b.min[1]),",",num(b.min[2]),",",num(b.min[3]),"},max={",num(b.max[1]),",",num(b.max[2]),",",num(b.max[3]),"},center={",num(b.center[1]),",",num(b.center[2]),",",num(b.center[3]),"}},groups={\n"}
  for gi,g in ipairs(model.groups) do
    out[#out+1]="{material="..q("source_group_"..gi)
    local tp=texturePaths[gi]
    if tp then out[#out+1]=",texture={path="..q(tp.path)..",w="..tp.w..",h="..tp.h.."}" end
    out[#out+1]=",vertices={\n"
    for _,v in ipairs(g.vertices) do
      local x,y,z,u,w,nx,ny,nz=v[1],v[2],v[3],v[4] or 0,v[5] or 0,v[6] or 0,v[7] or 1,v[8] or 0
      local row={x,y,z,u,w,nx,ny,nz}
      -- BreathPosition carries a second AUTHORED frame only for Dakim. Every
      -- other trainer falls back to base XYZ here, preserving stable silhouettes
      -- untouched. This is a source-frame blend, not procedural limb skinning.
      row[#row+1]=v[9] or x;row[#row+1]=v[10] or y;row[#row+1]=v[11] or z
      for _=1,6 do row[#row+1]=x;row[#row+1]=y;row[#row+1]=z end
      row[#row+1]=0
      local parts={};for i=1,#row do parts[i]=num(row[i]) end;out[#out+1]="{"..table.concat(parts,",").."},\n"
    end
    out[#out+1]="}},\n"
  end
  out[#out+1]="}}\n";return table.concat(out)
end
local function write(mod,path,data,paths)
  local ok,err=mod.cache:write(path,data);assert(ok,err or ("cache write failed: "..path));if paths then paths[#paths+1]=path end
end
local function openArchive(disc,name)
  local f=disc:file(name);if not f then return nil end
  local ok,arc=pcall(FSYS.open,disc,f);if not ok then return nil end
  return arc
end
local function basename(path)return tostring(path or ""):match("([^/]+)$") or tostring(path or "") end
local function safeName(v)return tostring(v or ""):gsub("[%c\r\n]","?") end
local function join(list,sep)local out={};for i,v in ipairs(list or {}) do out[i]=tostring(v) end;return table.concat(out,sep or ",") end

function T.run(mod,disc,progress,generated,options)
  options=options or {}
  local runTargets={}
  for _,target in ipairs(TARGETS) do
    if not options.directOnly or target.directSource then runTargets[#runTargets+1]=target end
  end
  local archiveNames,archiveSeen={},{}
  local function want(name)
    local key=tostring(name or ""):lower();if archiveSeen[key] then return end
    archiveSeen[key]=true;archiveNames[#archiveNames+1]=name
  end
  want("people_archive.fsys");want("field_common.fsys");want("fight_common.fsys")
  -- Pick up alternate character containers without opening the full 1000+ FSYS
  -- inventory. This makes the extractor resilient to naming differences while
  -- keeping first-run source reads bounded.
  for _,f in ipairs(disc.files or {}) do
    local p=tostring(f.path or ""):lower()
    if p:match("%.fsys$") and (p:find("people",1,true) or p:find("person",1,true) or p:find("trainer",1,true) or p:find("chara",1,true)) then
      want(f.path)
      if #archiveNames>=12 then break end
    end
  end

  local archives={};local diag={"CBE trainer scan / extractor rev 11 / native trainer pose 4 / clip1 non-bind + Dakim idle phase blend","mode="..(options.directOnly and "exact-source repair" or "full"),"archives requested="..#archiveNames}
  for _,name in ipairs(archiveNames) do
    local arc=openArchive(disc,name)
    if arc then
      archives[#archives+1]={name=name,arc=arc}
      diag[#diag+1]=( "archive OK %s members=%d" ):format(safeName(name),#arc:list())
    else
      diag[#diag+1]="archive MISS "..safeName(name)
    end
  end
  assert(#archives>0,"trainer source FSYS archives not found on Colosseum disc")
  local sources={}
  local allMembers=0
  for _,a in ipairs(archives) do
    local modelEntries=type(a.arc.modelEntries)=="function" and a.arc:modelEntries() or {}
    allMembers=allMembers+#a.arc:list()
    diag[#diag+1]=( "archive MODEL %s modelMembers=%d total=%d layout=%s" ):format(safeName(a.name),#modelEntries,#a.arc:list(),tostring(a.arc.layout or "?"))
    for _,e in ipairs(modelEntries) do
      sources[#sources+1]={archive=a.name,arc=a.arc,entry=e,key=a.name..":"..e.index}
    end
  end
  -- Older/unknown archives may omit useful file-type metadata. Keep a bounded
  -- fallback to all members only if canonical model typing produced nothing.
  if #sources==0 then
    for _,a in ipairs(archives) do for _,e in ipairs(a.arc:list()) do sources[#sources+1]={archive=a.name,arc=a.arc,entry=e,key=a.name..":"..e.index} end end
    diag[#diag+1]="MODEL FILTER FALLBACK: no typed DAT/PKX members"
  end
  assert(#sources>0,"trainer source archives contain no model members")
  diag[#diag+1]=( "source model members=%d / total members=%d" ):format(#sources,allMembers)

  -- Compact scan records. We retain no decoded mesh until a target wins.
  local summaries={};local scanStats={extractOK=0,extractFail=0,hsdOK=0,hsdFail=0}
  local inspectedSources=0;local firstSourceError=nil
  local function inspect(src)
    if not src then return nil,"missing source" end
    local hit=summaries[src.key];if hit~=nil then return hit.summary,hit.error end
    inspectedSources=inspectedSources+1
    local sourceLabel=safeName(src.entry.name)
    progress(("TRAINER SOURCE %d/%d  %s"):format(inspectedSources,#sources,sourceLabel),inspectedSources-1,#sources)
    local ok,blob=pcall(src.arc.extract,src.arc,src.entry,{
      maxOutput=64*1024*1024,
      progress=function(done,total)
        local pct=(tonumber(total) or 0)>0 and math.floor((tonumber(done) or 0)*100/(tonumber(total) or 1)) or 0
        progress(("TRAINER DECOMPRESS %d/%d  %s  %d%%"):format(inspectedSources,#sources,sourceLabel,pct),inspectedSources-1,#sources)
      end,
    })
    if not ok or type(blob)~="string" then
      scanStats.extractFail=scanStats.extractFail+1
      local err="FSYS extract: "..safeName(blob)
      if not firstSourceError then firstSourceError=safeName(src.archive)..":"..safeName(src.entry.name).." :: "..err end
      summaries[src.key]={summary=false,error=err,fileType=src.entry.fileType,ext=src.entry.ext};progress("TRAINER SOURCE SCAN",inspectedSources,#sources);return nil,err
    end
    scanStats.extractOK=scanStats.extractOK+1
    local model,err=HSD.extractModel(blob,{
      textures=false,maxRoots=8,maxVertices=30000,maxDisplayOps=80000,maxJobjs=1024,maxDobjs=4096,maxPobjs=8192,
      progress=function(root,totalRoots)
        progress(("TRAINER HSD %d/%d  %s  ROOT %d/%d"):format(inspectedSources,#sources,sourceLabel,tonumber(root) or 0,tonumber(totalRoots) or 0),inspectedSources-1,#sources)
      end,
    })
    if not model then
      scanStats.hsdFail=scanStats.hsdFail+1
      local d=HSD.describe(blob);local archiveBits={}
      for _,a in ipairs(d.archives or {}) do archiveBits[#archiveBits+1]=( "@0x%X pubs=%d roots=%d syms=%s" ):format(a.base or 0,a.publicCount or 0,a.candidateRoots or 0,join(a.symbols or {},"|")) end
      local detail=(err or "HSD decode failed")
      if #archiveBits>0 then detail=detail.." ["..table.concat(archiveBits," ; ").."]" end
      if not firstSourceError then firstSourceError=safeName(src.archive)..":"..safeName(src.entry.name).." :: "..safeName(detail) end
      summaries[src.key]={summary=false,error=detail,bytes=#blob,fileType=src.entry.fileType,ext=src.entry.ext};progress("TRAINER SOURCE SCAN",inspectedSources,#sources);return nil,detail
    end
    scanStats.hsdOK=scanStats.hsdOK+1
    local h=model.bounds and model.bounds.max and model.bounds.min and (model.bounds.max[2]-model.bounds.min[2]) or 0
    local summary={vertexCount=tonumber(model.vertexCount) or 0,groupCount=#(model.groups or {}),height=h,archiveBase=model.archive and model.archive.base or 0}
    summaries[src.key]={summary=summary,error=nil,bytes=#blob,fileType=src.entry.fileType,ext=src.entry.ext};progress("TRAINER SOURCE SCAN",inspectedSources,#sources);return summary,nil
  end
  local function decodeWinner(src,target)
    local label=safeName(src.entry.name)
    local ok,blob=pcall(src.arc.extract,src.arc,src.entry,{
      maxOutput=64*1024*1024,
      progress=function(done,total)
        local pct=(tonumber(total) or 0)>0 and math.floor((tonumber(done) or 0)*100/(tonumber(total) or 1)) or 0
        progress(("TRAINER FINAL DECOMPRESS  %s  %d%%"):format(label,pct),0,1)
      end,
    });assert(ok and type(blob)=="string",blob or ("trainer source read failed: "..src.key))
    local opts={textures=true,maxRoots=16,maxVertices=30000,maxDisplayOps=120000,maxJobjs=1536,maxDobjs=6144,maxPobjs=12288,nativePose={clip=1,frame=0}}
    local model,err=HSD.extractModel(blob,opts);assert(model,err or ("trainer HSD decode failed: "..src.key))
    if target.nativeIdleProbe then
      local ref={min={model.bounds.min[1],model.bounds.min[2],model.bounds.min[3]},max={model.bounds.max[1],model.bounds.max[2],model.bounds.max[3]}}
      normalize(model,target.height)
      local best,bestFrame,bestRatio,bestScore=nil,nil,nil,1e30
      -- Stay inside clip 1, the now-validated non-bind stance. Probe several
      -- phases and choose a MODERATE real source displacement: enough to free
      -- Dakim from the frozen frame-0 statue, nowhere near an action extreme.
      for _,frame in ipairs({8,16,24,32,40}) do
        local sample,sErr=HSD.extractModel(blob,{textures=false,maxRoots=16,maxVertices=30000,maxDisplayOps=120000,maxJobjs=1536,maxDobjs=6144,maxPobjs=12288,nativePose={clip=1,frame=frame}})
        if sample then
          normalizeLike(sample,target.height,ref)
          alignSampleFeet(model,sample,target.height)
          local ratio=poseRmsRatio(model,sample,target.height)
          if ratio and ratio>=.004 and ratio<=.12 then
            local score=math.abs(ratio-.052)
            if score<bestScore then best,bestFrame,bestRatio,bestScore=sample,frame,ratio,score end
          end
        end
      end
      if best and attachIdleSample(model,best) then
        model.nativeIdleFrame=bestFrame;model.nativeIdleRatio=bestRatio
      else
        model.nativeIdleFrame=0;model.nativeIdleRatio=0
      end
      return model
    end
    return normalize(model,target.height)
  end
  local used={};local resolved={};local unresolved={}
  local function sourceByHint(hint)
    hint=tostring(hint):lower()
    for _,s in ipairs(sources) do if tostring(s.entry.name):lower()==hint then return s end end
    for _,s in ipairs(sources) do if tostring(s.entry.name):lower():find(hint,1,true) then return s end end
  end
  local function sourceByExact(target)
    local wantedArchive=tostring(target.exactArchive or ""):lower()
    local wantedName=tostring(target.exactName or ""):lower()
    for _,s in ipairs(sources) do
      if basename(s.archive):lower()==wantedArchive and tostring(s.entry.name or ""):lower()==wantedName then return s end
    end
  end

  for ti,target in ipairs(runTargets) do
    progress("TRAINER "..target.id:upper(),ti-1,#runTargets)
    local candidates={};local seen={}
    -- Exact aliases (the two GBA-link geometry variants) may intentionally
    -- share one authoritative member. Heuristic candidates remain exclusive.
    local function add(s)if s and (target.exactName or not used[s.key]) and not seen[s.key] then seen[s.key]=true;candidates[#candidates+1]=s end end
    if target.exactName then
      add(sourceByExact(target))
    else
      for _,h in ipairs(target.hints or {}) do add(sourceByHint(h)) end
      for _,a in ipairs(archives) do if basename(a.name):lower()=="people_archive.fsys" then
        for d=-4,4 do local e=a.arc:member(target.modelId+d);if e then add({archive=a.name,arc=a.arc,entry=e,key=a.name..":"..e.index}) end end
      end end
    end
    local best,bestScore=nil,1e30
    local function consider(s)
      local m=inspect(s);if not m then return end
      local dv=math.abs(m.vertexCount-target.verts)/math.max(1,target.verts)
      local compact=(m.height>0 and m.height<5000) and 0 or .25
      local dg=math.abs(m.groupCount-4)*.008
      local sc=dv+dg+compact
      if sc<bestScore then best,bestScore={source=s,summary=m},sc end
    end
    for _,s in ipairs(candidates) do consider(s) end
    if not target.exactName and (not best or bestScore>.22) then for _,s in ipairs(sources) do if not used[s.key] then consider(s) end end end

    if not best or (not target.exactName and bestScore>=.70) then
      local reason
      if target.exactName then
        local exact=sourceByExact(target)
        if not exact then reason=("exact source missing: %s:%s"):format(target.exactArchive,target.exactName)
        else
          local _,sourceErr=inspect(exact)
          reason=("exact source failed: %s:%s :: %s"):format(target.exactArchive,target.exactName,safeName(sourceErr or "HSD decode failed"))
        end
      else
        reason=not best and "no decodable HSD trainer candidate" or ("best fingerprint outside tolerance %.3f (%s:%s v=%d g=%d)"):format(bestScore,safeName(best.source.archive),safeName(best.source.entry.name),best.summary.vertexCount,best.summary.groupCount)
      end
      unresolved[target.id]=reason
      diag[#diag+1]=( "UNRESOLVED %s: %s" ):format(target.id,reason)
    else
      used[best.source.key]=true
      local model=mergeGroups(decodeWinner(best.source,target));local texturePaths={};local textureMap={}
      for gi,g in ipairs(model.groups) do if g.texture then
        local sig=signature(g.texture);local tp=textureMap[sig]
        if not tp then
          local path=("cache/trainers/%s/textures/source_%02d.rgba"):format(target.id,gi)
          write(mod,path,g.texture.rgba,generated);tp={path=path,w=g.texture.w,h=g.texture.h};textureMap[sig]=tp
        end
        texturePaths[gi]=tp
      end end
      local cachePath=("cache/trainers/%s/model_cache.lua"):format(target.id)
      local sourceName=best.source.archive.." :: "..best.source.entry.name
      write(mod,cachePath,cacheLua(target,model,texturePaths,sourceName),generated)
      local nativePose=(target.id=="dakim" and model.nativeIdleFrame and model.nativeIdleFrame>0) and ("clip1/frame0 + idle-frame"..tostring(model.nativeIdleFrame)..(" rms=%.4f"):format(model.nativeIdleRatio or 0)) or "clip1/frame0"
      resolved[target.id]={archive=best.source.archive,entry=best.source.entry.index,name=best.source.entry.name,score=bestScore,vertices=model.vertexCount,groups=#model.groups,cache=cachePath,archiveBase=model.archive and model.archive.base or 0,nativePose=nativePose}
      diag[#diag+1]=( "%s %s <- %s:%s idx=%d score=%.4f vertices=%d groups=%d hsdBase=0x%X nativePose=%s" ):format(target.exactName and "EXACT" or "RESOLVED",target.id,safeName(best.source.archive),safeName(best.source.entry.name),tonumber(best.source.entry.index) or -1,bestScore,model.vertexCount,#model.groups,resolved[target.id].archiveBase,nativePose)
    end
  end

  local resolvedCount=0;for _ in pairs(resolved) do resolvedCount=resolvedCount+1 end
  local unresolvedCount=0;for _ in pairs(unresolved) do unresolvedCount=unresolvedCount+1 end
  diag[#diag+1]=( "scan stats: extracted=%d extractFail=%d hsdModels=%d hsdFail=%d" ):format(scanStats.extractOK,scanStats.extractFail,scanStats.hsdOK,scanStats.hsdFail)
  diag[#diag+1]=( "targets: resolved=%d unresolved=%d" ):format(resolvedCount,unresolvedCount)

  -- Surface representative failed members. This is intentionally bounded so a
  -- bad archive cannot produce a multi-megabyte diagnostic file.
  local emitted=0
  for _,s in ipairs(sources) do
    local r=summaries[s.key]
    if r and r.error and emitted<40 then
      diag[#diag+1]=( "FAIL %s idx=%s type=0x%02X ext=%s name=%s bytes=%s :: %s" ):format(safeName(s.archive),tostring(s.entry.index),tonumber(r.fileType or s.entry.fileType) or 0,tostring(r.ext or s.entry.ext or "?"),safeName(s.entry.name),tostring(r.bytes or "?"),safeName(r.error))
      emitted=emitted+1
    end
  end
  write(mod,"build/trainer_scan.txt",table.concat(diag,"\n").."\n",generated)

  local report={"return {version=4,resolved={"}
  for _,t in ipairs(runTargets) do local r=resolved[t.id];if r then report[#report+1]=string.format("%s={archive=%q,entry=%d,name=%q,score=%.6f,vertices=%d,groups=%d,archiveBase=%d},",t.id,r.archive,r.entry,r.name,r.score,r.vertices,r.groups,r.archiveBase or 0) end end
  report[#report+1]="},firstSourceError="..string.format("%q",firstSourceError or "")..",unresolved={"
  for _,t in ipairs(runTargets) do if unresolved[t.id] then report[#report+1]=string.format("%s=%q,",t.id,unresolved[t.id]) end end
  report[#report+1]="}}\n";write(mod,"build/trainers.lua",table.concat(report),generated)

  if unresolvedCount>0 then
    local firstError
    for _,t in ipairs(runTargets) do if unresolved[t.id] then firstError=t.id..": "..unresolved[t.id];break end end
    progress(("TRAINERS PARTIAL %d/%d"):format(resolvedCount,#runTargets),resolvedCount,#runTargets)
    return {ready=false,resolved=resolved,unresolved=unresolved,resolvedCount=resolvedCount,total=#runTargets,diagnostic="build/trainer_scan.txt",firstError=firstError,firstSourceError=firstSourceError}
  end

  local function entry(id,label)
    local t;for _,x in ipairs(TARGETS) do if x.id==id then t=x break end end
    return string.format("%s={id=%q,label=%q,cache=%q,scaleMul=%s,playerScaleMul=%s,enemyWorldHeight=6.90,pivotY=%s,playerPivotY=%s,rig=%q,directSource=%s}",id,id,label,"cache/trainers/"..id.."/model_cache.lua",tostring(t.scaleMul or 1),tostring(t.playerScaleMul or t.scaleMul or 1),tostring(t.pivotY),tostring(t.pivotY),id,tostring(t.directSource==true))
  end
  local modelRows={entry("red","RED"),entry("leaf","GREEN / LEAF"),entry("wes","WES / SETH"),entry("brendan","BRENDAN"),entry("may","MAY"),entry("cooltrainer_m","COOLTRAINER M"),entry("cooltrainer_f","COOLTRAINER F"),entry("dakim","DAKIM"),entry("nascour","NASCOUR"),entry("miror_b","MIROR B.")}
  local idx="return {version=2,models={"..table.concat(modelRows,",").."},players={},rivals={},archetypes={default_m={cache=\"cache/trainers/cooltrainer_m/model_cache.lua\",id=\"cooltrainer_m\",rig=\"cooltrainer_m\",scaleMul=1.47,pivotY=8.1},young_m={cache=\"cache/trainers/cooltrainer_m/model_cache.lua\",id=\"cooltrainer_m\",rig=\"cooltrainer_m\",scaleMul=1.47,pivotY=8.1},young_f={cache=\"cache/trainers/cooltrainer_f/model_cache.lua\",id=\"cooltrainer_f\",rig=\"cooltrainer_f\",scaleMul=1.58,pivotY=7.6}}}\n"
  write(mod,"cache/trainers/generic/index.lua",idx,generated)
  progress("TRAINERS READY",#runTargets,#runTargets)
  return {ready=true,resolved=resolved,unresolved={},resolvedCount=#runTargets,total=#runTargets,diagnostic="build/trainer_scan.txt",firstSourceError=firstSourceError}
end
return T
