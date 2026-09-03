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
local function normalizeJointPositions(points,s,cx,baseY,cz)
  if type(points)~="table" then return points end
  for _,p in ipairs(points) do
    if type(p)=="table" then
      p[1]=((tonumber(p[1]) or 0)-cx)*s
      p[2]=((tonumber(p[2]) or 0)-baseY)*s
      p[3]=((tonumber(p[3]) or 0)-cz)*s
    end
  end
  return points
end
local function normalize(model,targetHeight)
  local mn,mx=model.bounds.min,model.bounds.max;local h=math.max(1e-6,mx[2]-mn[2]);local s=targetHeight/h
  local cx=(mn[1]+mx[1])/2;local cz=(mn[3]+mx[3])/2
  local nmin={1e30,1e30,1e30};local nmax={-1e30,-1e30,-1e30}
  for _,g in ipairs(model.groups) do for _,v in ipairs(g.vertices) do
    v[1]=(v[1]-cx)*s;v[2]=(v[2]-mn[2])*s;v[3]=(v[3]-cz)*s
    for k=1,3 do if v[k]<nmin[k] then nmin[k]=v[k] end;if v[k]>nmax[k] then nmax[k]=v[k] end end
  end end
  normalizeJointPositions(model.jointPositions,s,cx,mn[2],cz)
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
  normalizeJointPositions(model.jointPositions,s,cx,mn[2],cz)
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
  for _,q in ipairs(sample.jointPositions or {}) do
    q[1]=(tonumber(q[1]) or 0)-dx;q[2]=(tonumber(q[2]) or 0)-dy;q[3]=(tonumber(q[3]) or 0)-dz
  end
  sample.bounds={min=mn,max=mx,center={(mn[1]+mx[1])/2,(mn[2]+mx[2])/2,(mn[3]+mx[3])/2}}
  return true
end
local POSE_OFFSET={
  breath=9,look=12,
  gesture1=15,gesture2=18,gesture3=21,gesture4=24,gesture5=27,
  reaction1=30,reaction2=33,reaction3=36,reaction4=39,reaction5=42,
}
local function sameTopology(base,sample)
  if not (base and sample and #(base.groups or {})==#(sample.groups or {})) then return false end
  for gi,g in ipairs(base.groups or {}) do
    local sg=sample.groups[gi]
    if not sg or #(g.vertices or {})~=#(sg.vertices or {}) then return false end
  end
  return true
end
local function attachPose(base,sample,name)
  local off=POSE_OFFSET[name]
  if not off or not sameTopology(base,sample) then return false end
  for gi,g in ipairs(base.groups or {}) do
    local sg=sample.groups[gi]
    for vi,v in ipairs(g.vertices or {}) do
      local q=sg.vertices[vi];v[off]=q[1];v[off+1]=q[2];v[off+2]=q[3]
    end
  end
  if type(sample.jointPositions)=="table" then
    base.poseJointPositions=base.poseJointPositions or {}
    local copy={}
    for i,p in ipairs(sample.jointPositions) do copy[i]={tonumber(p[1]) or 0,tonumber(p[2]) or 0,tonumber(p[3]) or 0} end
    base.poseJointPositions[name]=copy
  end
  return true
end
local function poseMetrics(base,sample,height)
  if not sameTopology(base,sample) then return nil end
  local H=math.max(.001,tonumber(height) or 1)
  local minY=base.bounds and base.bounds.min and base.bounds.min[2] or 0
  local sum,upper,lower,head,n,nu,nl,nh=0,0,0,0,0,0,0,0
  local left,right,nLeft,nRight=0,0,0,0
  local torsoDy,torsoN,maxD=0,0,0
  for gi,g in ipairs(base.groups or {}) do
    local sg=sample.groups[gi]
    for vi,v in ipairs(g.vertices or {}) do
      local q=sg.vertices[vi]
      local dx=(q[1] or 0)-(v[1] or 0);local dy=(q[2] or 0)-(v[2] or 0);local dz=(q[3] or 0)-(v[3] or 0)
      local d2=dx*dx+dy*dy+dz*dz;local d=math.sqrt(d2);if d>maxD then maxD=d end
      local yn=((v[2] or 0)-minY)/H
      sum=sum+d2;n=n+1
      if yn>=.32 then
        upper=upper+d2;nu=nu+1
        if (v[1] or 0)<0 then left=left+d2;nLeft=nLeft+1 else right=right+d2;nRight=nRight+1 end
      else lower=lower+d2;nl=nl+1 end
      if yn>=.72 then head=head+d2;nh=nh+1 end
      if yn>=.28 and yn<=.78 then torsoDy=torsoDy+dy;torsoN=torsoN+1 end
    end
  end
  if n<24 then return nil end
  local function rr(v,c)return c>0 and math.sqrt(v/c)/H or 0 end
  local l=rr(left,nLeft);local r=rr(right,nRight)
  return {overall=rr(sum,n),upper=rr(upper,nu),lower=rr(lower,nl),head=rr(head,nh),
    left=l,right=r,asym=math.abs(l-r),torsoDy=(torsoN>0 and torsoDy/torsoN/H or 0),max=maxD/H}
end
local function finiteMetric(m)
  if type(m)~="table" then return false end
  for _,k in ipairs({"overall","upper","lower","head","left","right","asym","torsoDy","max"}) do
    local v=tonumber(m[k]);if not v or v~=v or v==math.huge or v==-math.huge then return false end
  end
  return m.overall<=.78 and m.max<=1.85
end
local function sourcePoseSample(base,clip,frame,targetHeight,referenceBounds)
  if not (HSD and type(HSD.extractNativePose)=="function") then return nil end
  local sample=HSD.extractNativePose(base,clip,frame,{textures=false,maxVertices=30000,maxDisplayOps=120000,maxJobjs=1536,maxDobjs=6144,maxPobjs=12288})
  if not sample then return nil end
  normalizeLike(sample,targetHeight,referenceBounds)
  if not alignSampleFeet(base,sample,targetHeight) then return nil end
  local metrics=poseMetrics(base,sample,targetHeight)
  if not finiteMetric(metrics) then return nil end
  return {model=sample,clip=clip,frame=frame,metrics=metrics}
end
local function chooseCandidate(list,score,used,keyMode)
  local best,bestScore=nil,math.huge
  for _,c in ipairs(list or {}) do
    local id=(keyMode=="frame") and (tostring(c.clip)..":"..string.format("%.4f",tonumber(c.frame) or 0)) or tostring(c.clip)
    if not (used and used[id]) then
      local sc=score(c.metrics or {},c)
      if sc and sc==sc and sc<bestScore then best,bestScore=c,sc end
    end
  end
  if best and used then
    local id=(keyMode=="frame") and (tostring(best.clip)..":"..string.format("%.4f",tonumber(best.frame) or 0)) or tostring(best.clip)
    used[id]=true
  end
  return best
end
local function attachSourcePoseBank(model,target,referenceBounds,progressLabel)
  model.nativePoseMap={};model.nativeClipCount=0
  if not (HSD and type(HSD.nativeAnimationInfo)=="function" and type(HSD.extractNativePose)=="function") then return model end
  local idleInfo,clipCount=HSD.nativeAnimationInfo(model,1)
  clipCount=tonumber(clipCount) or (idleInfo and tonumber(idleInfo.clipCount)) or 0
  model.nativeClipCount=clipCount
  local idleCandidates={}
  local actionByClip={}
  local function sample(clip,frame)
    return sourcePoseSample(model,clip,frame,target.height,referenceBounds)
  end
  if idleInfo and (tonumber(idleInfo.endFrame) or 0)>1 then
    local e=tonumber(idleInfo.endFrame) or 1
    for _,f in ipairs({.16,.34,.52,.70,.88}) do
      local c=sample(1,e*f);if c and (c.metrics.overall or 0)>=.0012 then idleCandidates[#idleCandidates+1]=c end
    end
  end

  -- Build coherent source CLIP families rather than independently selecting one
  -- frame from several unrelated clips.  1.5.54's semantic classifier could
  -- choose COMMAND from clip 4, ARM from clip 7 and SETTLE from clip 9; even
  -- though every endpoint was source-authored, transitioning between them made
  -- the trainer look like a robot teleporting between unrelated silhouettes.
  -- For each B1 action clip, retain an authored anticipation/mid/follow-through
  -- sequence. We then choose one gesture clip and one reaction clip and map
  -- their ordered frames onto the shader's existing source-pose channels.
  local last=math.min(math.max(1,clipCount-1),12)
  for clip=2,last do
    local info=HSD.nativeAnimationInfo(model,clip)
    local e=info and tonumber(info.endFrame) or 0
    if e and e>1 then
      local row={clip=clip,endFrame=e,samples={}}
      for _,f in ipairs({.20,.36,.52,.68,.84}) do
        local c=sample(clip,e*f)
        if c and (c.metrics.overall or 0)>=.0012 then
          c.phase=f;row.samples[#row.samples+1]=c
        end
      end
      if #row.samples>=3 then actionByClip[#actionByClip+1]=row end
    end
  end

  local idleUsed={}
  local breath=chooseCandidate(idleCandidates,function(m)return math.abs((m.overall or 0)-.018)+(m.max or 0)*.025 end,idleUsed,"frame")
  local look=chooseCandidate(idleCandidates,function(m)return -((m.head or 0)*1.4-(m.lower or 0)*.35)+(m.overall or 0)*.18 end,idleUsed,"frame")

  local function clipScore(row,kind)
    local best=-math.huge
    for _,c in ipairs(row.samples or {}) do
      local m=c.metrics or {};local sc
      if kind=="gesture" then
        -- Battle throw/command clips are strongly one-hand-led. Prefer motion
        -- on the source actor's lead side and penalize equally large opposite
        -- arm travel; this rejects the broad two-arm "swimming" silhouettes
        -- that the old strongest-upper-body classifier could accidentally pick.
        local leadSide=tonumber(target and target.releaseSide) or -1
        local lead=(leadSide<0) and (m.left or 0) or (m.right or 0)
        local off=(leadSide<0) and (m.right or 0) or (m.left or 0)
        sc=lead*1.95+(m.asym or 0)*1.10+(m.upper or 0)*.62-off*.42-(m.lower or 0)*.22+(m.overall or 0)*.12
      else
        sc=(m.lower or 0)*.74+(m.upper or 0)*.46+(m.overall or 0)*.58+math.abs(m.torsoDy or 0)*1.05
      end
      if sc>best then best=sc end
    end
    return best
  end
  local gesture,reaction=nil,nil
  for _,row in ipairs(actionByClip) do
    if not gesture or clipScore(row,"gesture")>clipScore(gesture,"gesture") then gesture=row end
  end
  for _,row in ipairs(actionByClip) do
    local penalty=(gesture and row.clip==gesture.clip and #actionByClip>1) and .22 or 0
    local score=clipScore(row,"reaction")-penalty
    if not reaction or score>(reaction._score or -math.huge) then reaction=row;reaction._score=score end
  end

  local function nearestPhase(row,want)
    local best,bestD=nil,math.huge
    for _,c in ipairs(row and row.samples or {}) do
      local d=math.abs((tonumber(c.phase) or 0)-want)
      if d<bestD then best,bestD=c,d end
    end
    return best
  end
  -- 1.7.1: retain FIVE chronological samples from each selected native B1 clip.
  -- The previous 3-pose gesture / 2-pose reaction approximation could only draw
  -- straight-line morphs between widely separated silhouettes; arms therefore
  -- appeared to "swim" through the torso even though the endpoints came from
  -- Colosseum.  Five samples preserve the actual source clip arc closely enough
  -- for the runtime to interpolate adjacent authored frames rather than inventing
  -- intermediate body motion.
  local phases={.20,.36,.52,.68,.84}
  local gestureFrames,reactionFrames={},{}
  for i,f in ipairs(phases) do
    gestureFrames[i]=nearestPhase(gesture,f)
    reactionFrames[i]=nearestPhase(reaction,f)
  end

  -- Sparse-model fail-open: stay source-only. If one sample is unavailable,
  -- borrow the nearest retained frame from that SAME selected clip family. We
  -- never synthesize limb geometry and never cross-blend unrelated clips.
  local function fillSameFamily(frames,row)
    local first
    for _,c in ipairs(frames) do if c then first=c;break end end
    if not first and row then first=nearestPhase(row,.52) end
    for i=1,#phases do
      if not frames[i] then
        local best,bestD=nil,math.huge
        for j,c in ipairs(frames) do if c then
          local d=math.abs(j-i);if d<bestD then best,bestD=c,d end
        end end
        frames[i]=best or first
      end
    end
  end
  fillSameFamily(gestureFrames,gesture)
  fillSameFamily(reactionFrames,reaction)

  local all={}
  for _,row in ipairs(actionByClip) do for _,c in ipairs(row.samples or {}) do all[#all+1]=c end end
  local strongest=function(m)return -(m.overall or 0) end
  if not gestureFrames[1] then
    local c=chooseCandidate(all,strongest)
    for i=1,5 do gestureFrames[i]=c end
  end
  if not reactionFrames[1] then
    local c=chooseCandidate(all,function(m)return -((m.lower or 0)+(m.overall or 0)*.5) end)
    for i=1,5 do reactionFrames[i]=c end
  end
  breath=breath or look
  look=look or breath

  local selected={breath=breath,look=look}
  for i=1,5 do selected["gesture"..i]=gestureFrames[i] end
  for i=1,5 do selected["reaction"..i]=reactionFrames[i] end
  for name,c in pairs(selected) do
    if c and attachPose(model,c.model,name) then
      model.nativePoseMap[name]={clip=c.clip,frame=c.frame,phase=c.phase,metrics=c.metrics}
    end
  end
  model.nativeGestureClip=gesture and gesture.clip or nil
  model.nativeReactionClip=reaction and reaction.clip or nil
  model.nativeGestureEndFrame=gesture and gesture.endFrame or nil
  model.nativeReactionEndFrame=reaction and reaction.endFrame or nil
  return model
end

-- Pick the actual source JOBJ that best behaves like the trainer's throwing
-- hand. The extractor has exact world-space joint origins for the B1 model and
-- for every retained source pose, so runtime ball release no longer has to
-- guess from shoulder height / model width. Colosseum's player battle actors
-- use the negative-X arm as the lead throwing side in this normalized basis.
local function selectReleaseJoint(model,target)
  local base=model and model.jointPositions
  if type(base)~="table" or #base==0 then return nil end
  local poses=model.poseJointPositions or {}
  local action=poses.gesture3 or poses.gesture4 or poses.gesture2 or base
  local parents=model.jointParents or {}
  local b=model.bounds or {};local mn=b.min or {0,0,0};local mx=b.max or {0,16,0};local center=b.center or {0,8,0}
  local h=math.max(.001,(tonumber(mx[2]) or 16)-(tonumber(mn[2]) or 0))
  local side=tonumber(target and target.releaseSide) or -1
  local childCount={}
  for i,parent in ipairs(parents) do
    parent=tonumber(parent) or 0
    if parent>0 then childCount[parent]=(childCount[parent] or 0)+1 end
  end
  local best,bestScore=nil,-1e30
  for i,p in ipairs(action) do
    local q=base[i] or p
    local bx,by=tonumber(q[1]) or 0,tonumber(q[2]) or 0
    local sideX=side*(bx-(tonumber(center[1]) or 0))/h
    local baseY=(by-(tonumber(mn[2]) or 0))/h
    local leaf=(#parents==#base) and ((childCount[i] or 0)==0) or nil
    -- Select from the SOURCE REST SKELETON, not the moving throw pose. The real
    -- wrist/hand drops below the old 0.54-height gate during Colosseum's throw,
    -- which caused the renderer to reject it and attach the ball to the elbow.
    -- The arm hand is a lateral upper-body end effector in the rest skeleton.
    if sideX>.10 and baseY>.56 and baseY<.90 and (leaf~=false) then
      local ax,ay,az=tonumber(p[1]) or bx,tonumber(p[2]) or by,tonumber(p[3]) or (tonumber(q[3]) or 0)
      local dx=ax-bx;local dy=ay-by;local dz=az-(tonumber(q[3]) or 0)
      local move=math.sqrt(dx*dx+dy*dy+dz*dz)/h
      local reach=sideX
      local handBand=1-math.min(1,math.abs(baseY-.74)/.18)
      local leafBonus=(leaf==true) and 2.4 or 0
      local score=reach*7.0+move*1.25+handBand*.9+leafBonus
      if score>bestScore then best,bestScore=i,score end
    end
  end
  model.releaseJoint=best
  model.releaseJointScore=bestScore>-1e20 and bestScore or nil
  model.releaseSide=side
  return best
end

local function cacheLua(target,model,texturePaths,sourceName)
  local b=model.bounds
  local poseMap={}
  local function pointsLua(points)
    local rows={}
    for _,p in ipairs(points or {}) do rows[#rows+1]="{"..num(p[1] or 0)..","..num(p[2] or 0)..","..num(p[3] or 0).."}" end
    return "{"..table.concat(rows,",").."}"
  end
  local function intsLua(values)
    local rows={}
    for _,v in ipairs(values or {}) do rows[#rows+1]=tostring(math.floor(tonumber(v) or 0)) end
    return "{"..table.concat(rows,",").."}"
  end
  local poseJoints={}
  for _,name in ipairs({"breath","look","gesture1","gesture2","gesture3","gesture4","gesture5","reaction1","reaction2","reaction3","reaction4","reaction5"}) do
    local pts=model.poseJointPositions and model.poseJointPositions[name]
    if type(pts)=="table" then poseJoints[#poseJoints+1]=name.."="..pointsLua(pts) end
  end
  for _,name in ipairs({"breath","look","gesture1","gesture2","gesture3","gesture4","gesture5","reaction1","reaction2","reaction3","reaction4","reaction5"}) do
    local p=model.nativePoseMap and model.nativePoseMap[name]
    if p then poseMap[#poseMap+1]=name.."={clip="..num(p.clip)..",frame="..num(p.frame)..",rms="..num(p.metrics and p.metrics.overall or 0).."}" end
  end
  local out={"-- Generated locally from the user's Pokemon Colosseum GC6E01 disc.\nreturn {formatVersion=26,morphFormat=\"source-hsd-dense-clipfamilies-v7-five-sample-adjacent-interpolation\",source=",q("Pokemon Colosseum / "..target.id.." / "..sourceName),
    ",sourceRoot=",q(model.sourceRootMode or "unknown"),",nativeClipCount=",num(model.nativeClipCount or 0),",poseMap={",table.concat(poseMap,","),"},releaseJoint=",num(model.releaseJoint or 0),",releaseSide=",num(model.releaseSide or -1),",releaseJointScore=",num(model.releaseJointScore or 0),",jointPositions=",pointsLua(model.jointPositions),",jointParents=",intsLua(model.jointParents),",poseJointPositions={",table.concat(poseJoints,","),"},bounds={min={",num(b.min[1]),",",num(b.min[2]),",",num(b.min[3]),"},max={",num(b.max[1]),",",num(b.max[2]),",",num(b.max[3]),"},center={",num(b.center[1]),",",num(b.center[2]),",",num(b.center[3]),"}},groups={\n"}
  for gi,g in ipairs(model.groups) do
    out[#out+1]="{material="..q("source_group_"..gi)
    local function color3(v,default)
      v=type(v)=="table" and v or default or {1,1,1}
      return "{"..num(tonumber(v[1]) or 1)..","..num(tonumber(v[2]) or 1)..","..num(tonumber(v[3]) or 1).."}"
    end
    out[#out+1] = ",diffuse="..color3(g.diffuse,{1,1,1})..",ambient="..color3(g.ambient,{0,0,0})..",specular="..color3(g.specular,{0,0,0})
      ..",alpha="..num(tonumber(g.alpha) or 1)..",shininess="..num(tonumber(g.shininess) or 0)
      ..",xlu="..tostring(g.xlu==true)..",noz="..tostring(g.noz==true)..",renderFlags="..num(tonumber(g.renderFlags) or 0)
      ..",shadow="..tostring(g.shadow==true)..",effect="..tostring(g.effect==true)
      ..",useConstant="..tostring(g.useConstant==true)..",useVertexColor="..tostring(g.useVertexColor==true)
      ..",useDiffuseLighting="..tostring(g.useDiffuseLighting~=false)..",textureSlot="..num(tonumber(g.textureSlot) or -1)
    local tp=texturePaths[gi]
    if tp then out[#out+1]=",texture={path="..q(tp.path)..",w="..tp.w..",h="..tp.h.."}" end
    out[#out+1]=",vertices={\n"
    for _,v in ipairs(g.vertices) do
      local x,y,z,u,w,nx,ny,nz=v[1],v[2],v[3],v[4] or 0,v[5] or 0,v[6] or 0,v[7] or 1,v[8] or 0
      local row={x,y,z,u,w,nx,ny,nz}
      for _,off in ipairs({9,12,15,18,21,24,27,30,33,36,39,42}) do
        row[#row+1]=v[off] or x;row[#row+1]=v[off+1] or y;row[#row+1]=v[off+2] or z
      end
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

  local archives={};local diag={"CBE trainer scan / extractor rev 13 / dense native B1 clip-family bank v7 / five-sample adjacent interpolation / semantic scene root","mode="..(options.directOnly and "exact-source repair" or "full"),"archives requested="..#archiveNames}
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
    local opts={textures=true,maxRoots=32,maxVertices=30000,maxDisplayOps=120000,maxJobjs=1536,maxDobjs=6144,maxPobjs=12288,
      nativePose={clip=1,frame=0},semanticRootsOnly=true}
    local model,err=HSD.extractModel(blob,opts)
    local rootMode="scene-modelset"
    if not model then
      -- Keep a fail-open path for unusual B1 assets, but never let generic
      -- relocation-root selection outrank an available authoritative scene root.
      opts.semanticRootsOnly=nil
      model,err=HSD.extractModel(blob,opts);rootMode="generic-fallback"
    end
    assert(model,err or ("trainer HSD decode failed: "..src.key))
    model.sourceRootMode=rootMode
    local ref={min={model.bounds.min[1],model.bounds.min[2],model.bounds.min[3]},max={model.bounds.max[1],model.bounds.max[2],model.bounds.max[3]}}
    normalize(model,target.height)
    attachSourcePoseBank(model,target,ref,label)
    selectReleaseJoint(model,target)
    return model
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
      local model=decodeWinner(best.source,target);local texturePaths={};local textureMap={}
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
      local poseCount=0;for _ in pairs(model.nativePoseMap or {}) do poseCount=poseCount+1 end
      local nativePose=("clip1/frame0 + %d dense source pose targets / %d clips / root=%s"):format(poseCount,tonumber(model.nativeClipCount) or 0,tostring(model.sourceRootMode or "?"))
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

  local report={"return {version=6,resolved={"}
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
