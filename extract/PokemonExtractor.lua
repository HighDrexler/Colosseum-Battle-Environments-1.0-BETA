local V=...
local HSD,FSYS,Dex,PKXMetadata=V.HSD,V.FSYS,V.ColosseumDex,V.PKXMetadata
local P={revision=29}

-- Colosseum Pokemon battle-model extractor.
--
-- Unlike TrainerExtractor, nothing here is heuristic. Every species maps to
-- exactly one archive (pkx_<stem>.fsys) holding exactly one LZSS member of
-- fileType 0x1E, so there is no fingerprinting, no vertex-count scoring and no
-- "best candidate" pass. The species name IS the address; a miss is a hard
-- error, never a silent fallback onto the wrong Pokemon.
--
-- POSE / ANIMATION CONTRACT
--
-- We deliberately do not synthesize motion. Every pose written to the cache is
-- an authored HSD frame sampled out of the source model's own animation set.
-- The cache carries a base frame plus up to MORPH_SLOTS additional authored
-- frames of the same clip; the runtime blends between consecutive frames, so
-- what plays back is Colosseum's own animation resampled, not a procedural
-- approximation of it.
--
-- Clip 0 in a GC6E01 character archive is the bind/T pose (this is the same
-- convention TrainerExtractor documented for the B1 trainer members). Clip 1 is
-- the first authored non-bind stance. We probe outward from there rather than
-- assuming, and record what we found in the diagnostic so the mapping can be
-- corrected from real data instead of guessed at again.

local MORPH_SLOTS=12         -- dense complete authored poses carried beside the base frame
local STRIDE=44              -- 8 base floats + 9 vec4 packs carrying 12 authored positions
local MAX_CLIP_PROBE=8       -- how many clips to inspect when hunting the idle

-- Maximum RMS displacement, as a fraction of model height, that a pose may move
-- geometry away from the bind pose before it is treated as broken rather than
-- animated.
--
-- This is the check the vertex-count invariant could not make. A corrupted pose
-- does not LOSE vertices -- the display lists are identical either way -- it
-- puts them in the wrong places, because every mesh inherits its joint's world
-- matrix and a mis-sampled joint drags its whole part off. The result is a full
-- vertex count assembled into scattered blobs, which is exactly what shipped.
--
-- A real battle idle breathes by a few percent of body height. Anything past
-- this is a joint sampling failure, not animation.
local POSE_COHERENCE_MAX=0.16

local function q(s) return string.format("%q",tostring(s)) end
local function num(x)
  if type(x)~="number" or x~=x or x==math.huge or x==-math.huge then return "0" end
  return ("%.6g"):format(x)
end
local function safe(v) return (tostring(v or ""):gsub("[%c\r\n]","?")) end
local function signature(tex)
  if not tex then return "none" end
  return table.concat({tex.w,tex.h,tex.format,tex.rgba:sub(1,48)},":")
end

-- Normalize the base frame to a known world height, and record the transform so
-- every later frame of the same clip can be mapped through the SAME transform.
-- Re-centering each frame independently would cancel out exactly the root
-- translation that makes the animation read, which is the bug TrainerExtractor
-- hit with normalizeLike.
local function measure(model,targetHeight)
  local mn,mx=model.bounds.min,model.bounds.max
  local h=math.max(1e-6,mx[2]-mn[2])
  return {s=targetHeight/h,cx=(mn[1]+mx[1])/2,cy=mn[2],cz=(mn[3]+mx[3])/2}
end
local function applyTransform(model,t)
  local nmin={1e30,1e30,1e30};local nmax={-1e30,-1e30,-1e30}
  for _,g in ipairs(model.groups or {}) do
    for _,v in ipairs(g.vertices or {}) do
      v[1]=(v[1]-t.cx)*t.s;v[2]=(v[2]-t.cy)*t.s;v[3]=(v[3]-t.cz)*t.s
      for k=1,3 do
        if v[k]<nmin[k] then nmin[k]=v[k] end
        if v[k]>nmax[k] then nmax[k]=v[k] end
      end
    end
  end
  -- Joint origins live in the same HSD source space as the skinned vertices.
  -- Apply the identical one-time model normalization so a PKX body-map point
  -- can be multiplied by Actor.worldMatrix and land on the visible Pokemon.
  for _,j in ipairs(model.jointPositions or {}) do
    j[1]=((tonumber(j[1]) or 0)-t.cx)*t.s
    j[2]=((tonumber(j[2]) or 0)-t.cy)*t.s
    j[3]=((tonumber(j[3]) or 0)-t.cz)*t.s
  end
  model.bounds={min=nmin,max=nmax,center={(nmin[1]+nmax[1])/2,(nmin[2]+nmax[2])/2,(nmin[3]+nmax[3])/2}}
  return model
end

-- Two samples are usable as morph targets for one another only if their group
-- and vertex topology match exactly. Display-list decoding is deterministic for
-- a given root, so this should always hold; we verify rather than assume,
-- because a mismatch silently scrambles the mesh instead of failing loudly.
local function topologyMatches(base,sample)
  if not (base and sample) then return false end
  local bg,sg=base.groups or {},sample.groups or {}
  if #bg~=#sg then return false end
  for i=1,#bg do
    if #(bg[i].vertices or {})~=#(sg[i].vertices or {}) then return false end
  end
  return true
end

-- Mean per-vertex displacement between two frames, normalized by model height.
-- Used to reject a "clip" that is really a static pose, and to report how much
-- motion each candidate clip actually carries.
local function motionRatio(base,sample,height)
  if not topologyMatches(base,sample) then return nil end
  local H=math.max(.001,height or 1)
  local sum,n=0,0
  for gi,g in ipairs(base.groups) do
    local sgv=sample.groups[gi].vertices
    for vi,v in ipairs(g.vertices) do
      local o=sgv[vi]
      local dx=(o[1] or 0)-(v[1] or 0)
      local dy=(o[2] or 0)-(v[2] or 0)
      local dz=(o[3] or 0)-(v[3] or 0)
      sum=sum+dx*dx+dy*dy+dz*dz;n=n+1
    end
  end
  if n<12 then return nil end
  return math.sqrt(sum/n)/H
end

local function finite(v)
  return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end

local function modelHeight(model)
  local b=model and model.bounds
  return b and b.min and b.max and math.max(.001,(tonumber(b.max[2]) or 0)-(tonumber(b.min[2]) or 0)) or 1
end

local function boundsCenterAndSpan(model)
  local b=model and model.bounds
  if not (b and b.min and b.max) then return nil end
  local min,max=b.min,b.max
  for i=1,3 do if not (finite(min[i]) and finite(max[i])) then return nil end end
  local dx,dy,dz=max[1]-min[1],max[2]-min[2],max[3]-min[3]
  if dx<0 or dy<0 or dz<0 then return nil end
  return {(min[1]+max[1])*.5,(min[2]+max[2])*.5,(min[3]+max[3])*.5},math.sqrt(dx*dx+dy*dy+dz*dz)
end

-- A topology match alone is not enough for a usable battle action: genuinely
-- corrupt HSD samples can collapse or explode while still retaining the same
-- vertex count.  However, Damage/Damage2/Faint are SOURCE-AUTHORED reaction
-- clips and are intentionally allowed to move the whole body a long distance.
-- Revision 24 used small centre/RMS drift limits here; those limits rejected the
-- real Colosseum recoil/stumble frames and silently replaced them with frame 0.
-- For verified reaction slots, reject only impossible geometry.  Other actions
-- keep the conservative displacement guard used for fail-open clip probing.
local REACTION_SLOT={damage=true,damageHeavy=true,faint=true}
local ACTION_DRIFT_MAX={idle=1.25,idleB=1.25,idleC=1.25,idleD=1.25,idleE=1.25,
  statusA=1.75,statusB=1.75,specialC=2.25,
  physicalA=3.5,physicalB=3.5,physicalC=3.5,physicalD=3.5,physicalE=3.5,takeFlight=5.0}
local function actionPoseUsable(template,sample,label)
  if not topologyMatches(template,sample) then return false,"topology mismatch" end
  local tc,ts=boundsCenterAndSpan(template)
  local sc,ss=boundsCenterAndSpan(sample)
  if not (tc and sc and ts and ss) then return false,"non-finite bounds" end
  local H=modelHeight(template)
  if ss<math.max(.01,ts*.08) then return false,("collapsed span %.4f vs %.4f"):format(ss,ts) end
  if ss>ts*7.0 then return false,("exploded span %.4f vs %.4f"):format(ss,ts) end
  local dx,dy,dz=sc[1]-tc[1],sc[2]-tc[2],sc[3]-tc[3]
  local centerDistance=math.sqrt(dx*dx+dy*dy+dz*dz)/H
  if REACTION_SLOT[label] then
    -- Native reactions can contain dramatic root translation (knock-back,
    -- stagger, aerial recoil and the fall itself).  Six body-heights is already
    -- far outside any legitimate Colosseum reaction and remains a useful guard
    -- against a corrupt matrix without censoring authored animation.
    if centerDistance>6.0 then
      return false,("reaction center displaced %.3f model heights"):format(centerDistance)
    end
    return true,nil,centerDistance
  end
  if centerDistance>3.5 then
    return false,("center displaced %.3f model heights"):format(centerDistance)
  end
  local drift=motionRatio(template,sample,H)
  local limit=ACTION_DRIFT_MAX[label] or 2.25
  if not drift then return false,"pose displacement unavailable" end
  if drift>limit then return false,("pose drift %.3f exceeds %.2f"):format(drift,limit) end
  return true,nil,drift
end

local function materialSignature(g)
  local function c(v)
    if type(v)~="table" then return "-" end
    return ("%.5f,%.5f,%.5f"):format(tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0)
  end
  return table.concat({
    signature(g.texture),
    tostring(g.renderFlags or 0),
    ("a=%.5f"):format(tonumber(g.alpha) or 1),
    "d="..c(g.diffuse),"a2="..c(g.ambient),"s="..c(g.specular),
    "x="..tostring(g.xlu==true),"z="..tostring(g.noz==true),
    "sh="..tostring(g.shadow==true),"ef="..tostring(g.effect==true),
    "ts="..tostring(g.textureSlot or -1),
  },"|")
end

-- Merge only groups whose complete SOURCE material state matches. Older builds
-- keyed solely by decoded texture bytes, which silently collapsed every
-- untextured DOBJ into one giant white bucket and also merged textured surfaces
-- that happened to share an atlas while using different alpha/material state.
-- That is why F5 showed a 144-vertex "group 1" cube/plate on Weedle: it was not
-- one source mesh at all, it was a synthetic CBE bucket created by this merge.
local function mergeGroups(model)
  local map,out={},{}
  for _,g in ipairs(model.groups) do
    local key=materialSignature(g)
    local dst=map[key]
    if not dst then
      dst={
        vertices={},texture=g.texture,
        alpha=g.alpha,xlu=g.xlu,noz=g.noz,
        diffuse=g.diffuse,ambient=g.ambient,specular=g.specular,shininess=g.shininess,
        renderFlags=g.renderFlags,shadow=g.shadow,effect=g.effect,
        useConstant=g.useConstant,useVertexColor=g.useVertexColor,
        useDiffuseLighting=g.useDiffuseLighting,textureSlot=g.textureSlot,
      }
      map[key]=dst;out[#out+1]=dst
    end
    for _,v in ipairs(g.vertices) do dst.vertices[#dst.vertices+1]=v end
  end
  model.groups=out
  return model
end

-- Budgets are deliberately far above the trainer path's. Those values were
-- tuned for one human actor decoded out of a 100+ member people_archive, where
-- a runaway root had to be cheap to abandon. A Pokemon PKX holds exactly one
-- model and is read on demand, so the guards only need to stop genuinely
-- malformed data -- not to bound a search. A budget trip here is far worse than
-- a slow decode: extractRoot returns nil on exhaustion, and extractModel then
-- happily settles for whichever partial SUB-root decoded, which renders as a
-- fragment of the Pokemon rather than as a visible failure.
local DECODE={
  textures=true,maxRoots=64,maxVertices=200000,
  maxDisplayOps=600000,maxJobjs=8192,maxDobjs=24576,maxPobjs=49152,
  maxSceneRoots=64,
  -- Pokemon PKX files advertise their real character root(s) through
  -- HSD_SceneDesc.modelsets. Never let relocation-derived "plausible" JOBJ
  -- guesses compete by vertex count: the F5 capture proved those guesses can
  -- decode extra garbage geometry that is not part of the source model.
  semanticRootsOnly=true,
  -- Pokemon PKX shadow-pass DOBJ(s) are not ordinary body geometry. CBE owns
  -- arena-side grounding; importing the source caster/pass mesh as diffuse
  -- geometry produces the white box/plate seen in the 1.5.24 F5 capture.
  skipShadowMaterials=true,
}
-- Set once at the top of P.extractSpecies from opts.skinFix and read by every
-- decode in that call. A single extraction runs synchronously top to bottom
-- with no concurrent species in flight, so a shared upvalue here is safe and
-- avoids threading a new parameter through every decodeBest call site that
-- exists purely to reach chooseIdleClip/attachFrames' internal re-decodes.
local currentSkinFix=true
local currentRenderPassFilter=true
local function decodeOpts(clip,frame,withTextures)
  local o={}
  for k,v in pairs(DECODE) do o[k]=v end
  o.textures=withTextures and true or false
  o.skinFix=currentSkinFix
  o.honorRenderPass=currentRenderPassFilter
  o.filterPlaceholders=false
  if clip~=nil then o.nativePose={clip=clip,frame=frame or 0} end
  return o
end

-- Decode one pose as completely as the source allows.
--
-- The production "single" path is now semantic-root-only: H.extractModel is
-- instructed to consider only the JOBJ roots listed by scene_data's
-- HSD_SceneModelSet table. Relocation-derived candidate roots remain available
-- to generic HSD callers, but Pokemon extraction no longer lets a false root
-- win simply because it decodes more triangles.
--
-- We still probe the scene-union path for diagnostics/F10. AUTO prefers one
-- authoritative semantic character root; forced SCENE deliberately unions all
-- semantic model-set roots for comparison.
local function decodeBest(blob,clip,frame,withTextures,trail,label,mode)
  mode=mode or "auto"
  local opts=decodeOpts(clip,frame,withTextures)

  local scene=nil
  if type(HSD.extractSceneModel)=="function" then
    local ok,value=pcall(HSD.extractSceneModel,blob,opts)
    if ok then scene=value end
  end
  local single,singleErr=HSD.extractModel(blob,opts)
  local sv=scene and tonumber(scene.vertexCount) or 0
  local nv=single and tonumber(single.vertexCount) or 0

  -- Choosing whichever decode had MORE vertices was wrong, and every fix built
  -- on top of that default (the 1.9x duplication-rejection guard in 1.5.9)
  -- was patching the SYMPTOM of that default, not the default itself, which is
  -- why it didn't move these two test species at all: a small extra root
  -- doesn't inflate the vertex count anywhere near 2x, so it always slid under
  -- the guard.
  --
  -- HSD.lua's own comment on H.extractSceneModel says what it's actually for:
  -- an ARENA legitimately has several HSD_SceneModelSet roots that must all be
  -- on screen at once (venue shell, crowd, water), so it unions every root it
  -- can find. A PKX's scene_data table is not guaranteed to hold only the body.
  -- The same array slot can carry a shadow decal, a held-item/particle anchor,
  -- or a menu-icon LOD next to the real model -- objects that belong in the
  -- source game's scene graph but were never meant to be composited into one
  -- mesh. Unioning all of them is exactly a small correctly-shaped body plus
  -- one or two small detached shapes floating near it, which is what every
  -- screenshot in this thread has shown, for every species tried.
  --
  -- That risk was carried as an untested "supports both, in case a Pokemon
  -- splits its body across roots" hypothesis since 1.5.0 -- it never had
  -- supporting data, because nothing ever reported how many roots scene mode
  -- was combining. TrainerExtractor never took this risk: HSD.lua says plainly
  -- "Trainer extraction wants one best actor root" and uses extractModel alone.
  -- A Pokemon PKX holds exactly one character, same as a trainer DAT, so it
  -- gets the same default: prefer the single best root whenever it produced a
  -- real model, and fall back to the scene union only when the single-root
  -- walk found nothing at all.
  local DUPLICATION_FACTOR=1.9
  local chosen,path
  if mode=="scene" and scene then
    chosen,path=scene,"scene(forced)"
  elseif mode=="single" and single then
    chosen,path=single,"single(forced)"
  elseif single and nv>0 then
    chosen,path=single,"single"
  elseif scene and sv>0 then
    chosen,path=scene,"scene(single unavailable)"
  end

  if trail and label then
    trail[#trail+1]=("%s scene=%d verts/%s roots  single=%d verts  ratio=%.2f  -> %s")
      :format(label,sv,tostring(scene and scene.sceneRoots or "-"),nv,
        (nv>0) and (sv/nv) or 0,tostring(path))
    if scene and single and nv>0 and sv>=nv*DUPLICATION_FACTOR then
      trail[#trail+1]=("  note: scene path would have returned %.2fx the single-root geometry -- "
        .."single was used regardless, since scene is no longer preferred by default."):format(sv/nv)
    elseif scene and single then
      trail[#trail+1]=("  note: scene found %s root(s) totalling %d verts vs single's %d -- "
        .."single was used; force scene mode (F10) on this species to compare directly."):format(tostring(scene.sceneRoots or "?"),sv,nv)
    end
    if not chosen then
      trail[#trail+1]=("%s both paths failed: %s"):format(label,safe(singleErr))
    end
  end
  if chosen then return chosen,path,tonumber(chosen.vertexCount) or 0 end
  return nil,nil,0,singleErr
end

-- Bounds computed from raw min/max are destroyed by a handful of stray vertices:
-- one vertex left at the origin by a bad envelope transform stretches the model's
-- measured height, and normalizing against that height shrinks the real body to a
-- speck. Compare raw bounds against a trimmed 1st/99th percentile so the
-- diagnostic can distinguish "geometry is missing" from "geometry is scattered".
local function boundsReport(model)
  local xs,ys,zs={},{},{}
  for _,g in ipairs(model.groups or {}) do
    for _,v in ipairs(g.vertices or {}) do
      xs[#xs+1]=v[1];ys[#ys+1]=v[2];zs[#zs+1]=v[3]
    end
  end
  if #ys<8 then return nil end
  table.sort(xs);table.sort(ys);table.sort(zs)
  -- Trim at least one element per end. A pure percentile is a no-op on small
  -- meshes -- 1% of a few dozen vertices rounds to zero -- which is exactly
  -- where a single stray vertex does the most damage to the bounding box.
  local function trimmed(t)
    local n=#t
    local cut=math.max(1,math.floor(n*0.01))
    if n-2*cut<4 then return t[n]-t[1] end
    return t[n-cut]-t[1+cut]
  end
  local rawH=ys[#ys]-ys[1]
  local trimH=trimmed(ys)
  local rawW=xs[#xs]-xs[1]
  local trimW=trimmed(xs)
  return {
    rawH=rawH,trimH=trimH,rawW=rawW,trimW=trimW,
    heightRatio=(trimH>1e-9) and (rawH/trimH) or 0,
    widthRatio=(trimW>1e-9) and (rawW/trimW) or 0,
    count=#ys,
  }
end

-- Pick the clip that best reads as a looping battle idle: enough authored
-- movement to be visibly alive, not so much that we have grabbed an attack or a
-- faint. Returns the clip index plus the diagnostic trail that produced it.
local function chooseIdleClip(blob,targetHeight,trail,mode)
  local base=decodeBest(blob,0,0,false,trail,"bind",mode)
  if not base then return nil,nil,"clip probe: bind frame did not decode" end
  -- nativeClipCount only rides on the single-root path's stats, so ask for it
  -- explicitly rather than assuming the winning decode carried it.
  local probe=HSD.extractModel(blob,decodeOpts(0,0,false))
  local clipCount=(probe and probe.stats and tonumber(probe.stats.nativeClipCount)) or 0
  trail[#trail+1]=("clips=%d"):format(clipCount)
  if clipCount<2 then
    -- Only a bind pose exists. Static is the honest result; do not fabricate.
    return 0,clipCount,"only a bind clip is present"
  end
  -- THE INVARIANT: posing a model must not change how much of it decodes.
  -- Same root, same display lists, same vertices -- only joint transforms move.
  -- If a clip yields FEWER vertices than the bind pose, that clip's joint data
  -- is derailing the display-list walk (a bad transform trips a decode budget or
  -- an envelope lookup), and the pose is destroying geometry rather than
  -- animating it. Such a clip is rejected outright no matter how good its
  -- motion score looks, because a well-animated fragment is still a fragment.
  local referenceVerts=tonumber(base.vertexCount) or 0
  trail[#trail+1]=("bind-pose reference vertices=%d"):format(referenceVerts)

  local bestClip,bestScore,bestRatio=nil,1e30,nil
  local limit=math.min(clipCount-1,MAX_CLIP_PROBE)
  for clip=1,limit do
    local a=decodeBest(blob,clip,0,false,nil,nil,mode)
    local b=decodeBest(blob,clip,12,false,nil,nil,mode)
    local av=a and tonumber(a.vertexCount) or 0
    if referenceVerts>0 and av<referenceVerts*0.995 then
      trail[#trail+1]=("clip %d REJECTED: %d verts vs %d at bind (%.1f%% lost)")
        :format(clip,av,referenceVerts,(1-av/referenceVerts)*100)
      a=nil
    end
    if a and b then
      local t=measure(a,targetHeight)
      applyTransform(a,t);applyTransform(b,t)
      local r=motionRatio(a,b,targetHeight)
      -- Coherence: how far this pose moves geometry away from the BIND pose.
      -- Measured against a bind copy put through the same transform, so the two
      -- are directly comparable.
      local bindCopy=decodeBest(blob,0,0,false,nil,nil,mode)
      local drift=nil
      if bindCopy then
        applyTransform(bindCopy,t)
        drift=motionRatio(bindCopy,a,targetHeight)
      end
      if drift and drift>POSE_COHERENCE_MAX then
        trail[#trail+1]=("clip %d REJECTED: drifts %.3f from bind (max %.2f). "
          .."Joint sampling is displacing geometry, not animating it.")
          :format(clip,drift,POSE_COHERENCE_MAX)
      elseif r then
        trail[#trail+1]=("clip %d motion=%.5f drift=%s")
          :format(clip,r,drift and ("%.4f"):format(drift) or "?")
        -- Target a moderate, idle-sized displacement. An attack or faint clip
        -- displaces far more; a duplicated bind pose displaces ~0.
        if r>=.0015 then
          local score=math.abs(r-.030)
          if score<bestScore then bestClip,bestScore,bestRatio=clip,score,r end
        end
      else
        trail[#trail+1]=("clip %d topology mismatch"):format(clip)
      end
    else
      trail[#trail+1]=("clip %d did not decode"):format(clip)
    end
  end
  if not bestClip then
    return 0,clipCount,"no clip carried usable authored motion"
  end
  trail[#trail+1]=("selected clip %d motion=%.5f"):format(bestClip,bestRatio or 0)
  return bestClip,clipCount,nil
end

-- Sample MORPH_SLOTS authored frames across the chosen clip and attach them to
-- the base model's vertices. Frames that fail to decode or mismatch topology
-- collapse to the base position, so a partially-readable clip degrades to a
-- shorter loop rather than corrupting the mesh.
local function attachFrames(blob,base,clip,transform,targetHeight,spacing,trail,decodeMode,actionLabel)
  local attached=0
  local validSlots={}
  base.jointFrames=base.jointFrames or {}
  for slot=1,MORPH_SLOTS do
    local frame=slot*spacing
    local sample=decodeBest(blob,clip,frame,false,nil,nil,decodeMode)
    if sample then applyTransform(sample,transform) end
    local usable,reason
    if sample then
      if actionLabel then usable,reason=actionPoseUsable(base,sample,actionLabel)
      else usable=topologyMatches(base,sample);reason=usable and nil or "topology mismatch" end
    else reason="frame did not decode" end
    for gi,g in ipairs(base.groups) do
      local sv=usable and sample.groups[gi].vertices or nil
      for vi,v in ipairs(g.vertices) do
        local o=sv and sv[vi] or v
        local at=6+slot*3            -- slots start after x,y,z,u,v,nx,ny,nz
        v[at+1]=o[1];v[at+2]=o[2];v[at+3]=o[3]
      end
    end
    -- Carry the exact sampled HSD joint origins beside the morph vertex bank.
    -- If a source frame is rejected, keep the proven frame-0 joints just like
    -- the vertices rather than feeding bad damage geometry into attachments.
    local joints=(usable and sample and sample.jointPositions) or base.jointPositions or {}
    local jf={}
    for ji,j in ipairs(joints) do jf[ji]={j[1] or 0,j[2] or 0,j[3] or 0} end
    base.jointFrames[slot]=jf
    validSlots[slot]=usable and true or false
    if usable then
      attached=attached+1
    else
      trail[#trail+1]=("%sframe %.3f unusable (%s); slot %d holds base")
        :format(actionLabel and ("native "..actionLabel.." ") or "",frame,tostring(reason or "invalid pose"),slot)
    end
  end
  return attached,validSlots
end


-- 1.5.29: build one authored morph bank for each distinct PKX battle action.
-- The PKX wrapper is authoritative here: its slots map semantic actions such as
-- Physical, Damage and Faint to actual DAT animation indices and carry the
-- source timing in 60 Hz ticks. Previous CBE releases cached only one HSD clip
-- and then tried to make every other action look different by moving the whole
-- actor procedurally. That is why a complete model still moved unlike Colosseum.
local function copyGroupShell(g)
  return {
    vertices={},texture=g.texture,alpha=g.alpha,xlu=g.xlu,noz=g.noz,
    diffuse=g.diffuse,ambient=g.ambient,specular=g.specular,shininess=g.shininess,
    renderFlags=g.renderFlags,shadow=g.shadow,effect=g.effect,
    useConstant=g.useConstant,useVertexColor=g.useVertexColor,
    useDiffuseLighting=g.useDiffuseLighting,textureSlot=g.textureSlot,
  }
end

local function actionSpacing(duration,endFrame)
  duration=tonumber(duration) or 0
  endFrame=tonumber(endFrame)
  -- PKX timing points are expressed on the battle's 60 Hz clock, but the HSD
  -- AOBJ animation itself is authored at ~30 source frames/sec.  Using
  -- duration*60 as an HSD frame index sampled twice past the real clip and
  -- left many reactions holding their terminal pose for half their playback.
  -- Prefer the exact HSD endFrame discovered from the selected source root;
  -- the duration remains authoritative for real-time playback.
  if endFrame and endFrame>0.5 then
    return math.max(.25,endFrame/MORPH_SLOTS)
  end
  if duration>0.02 then
    local frameCount=duration*30
    return math.max(.25,math.max(1,frameCount-1)/MORPH_SLOTS)
  end
  return 4
end

local function buildActionModel(blob,template,clip,transform,duration,endFrame,trail,decodeMode,label)
  clip=tonumber(clip)
  if clip==nil or clip<0 then return nil,"no animation index" end
  local first=decodeBest(blob,clip,0,false,nil,nil,decodeMode)
  if not first then return nil,"frame 0 did not decode" end
  applyTransform(first,transform)
  local usable,poseErr=actionPoseUsable(template,first,label)
  if not usable then return nil,"frame 0 "..tostring(poseErr or "pose invalid") end

  local model={groups={},bounds=first.bounds,vertexCount=template.vertexCount,jointPositions=first.jointPositions}
  for gi,tg in ipairs(template.groups or {}) do
    local fg=first.groups[gi]
    local outg=copyGroupShell(tg)
    for vi,tv in ipairs(tg.vertices or {}) do
      local fv=fg.vertices[vi]
      -- UV/material topology is invariant. Positions come from this action's
      -- frame 0; normals/UVs remain the proven body cache streams.
      local v={fv[1],fv[2],fv[3],tv[4] or 0,tv[5] or 0,tv[6] or 0,tv[7] or 1,tv[8] or 0}
      outg.vertices[vi]=v
    end
    model.groups[gi]=outg
  end
  local spacing=actionSpacing(duration,endFrame)
  local attached,validSlots=attachFrames(blob,model,clip,transform,nil,spacing,trail,decodeMode,label)
  if attached<1 then return nil,"no authored target frames decoded" end
  return model,nil,spacing,attached,validSlots
end


-- Reaction animations are the most visually sensitive authored clips in battle.
-- A single 12-target morph bank only gives roughly 12-15 Hz pose density on a
-- normal Damage/Faint clip, which is visibly stepped compared with Colosseum.
-- Keep the GPU's proven 12-target attribute layout, but divide reaction clips
-- into overlapping pages sampled from the source timeline. Page boundaries
-- share the exact same authored source frame, so runtime can switch pages with
-- no pose discontinuity.
local function denseReactionIntervals(label,duration,endFrame)
  if label~="damage" and label~="damageHeavy" and label~="faint" then return MORPH_SLOTS end
  local sourceIntervals=math.max(1,math.floor((tonumber(endFrame) or 0)+.5))
  if sourceIntervals<=1 then
    local seconds=math.max(.05,tonumber(duration) or 0)
    sourceIntervals=math.max(1,math.floor(seconds*30+.5)-1)
  end
  -- Reactions are the most noticeable clips in battle. Carry substantially
  -- more of the real HSD timeline, but never manufacture more samples than the
  -- source clip actually contains. Runtime still interpolates adjacent source
  -- poses, so this yields smooth motion without vertex-space overshoot.
  return math.max(MORPH_SLOTS,math.min(72,sourceIntervals))
end

local function buildActionPage(blob,template,clip,transform,spacing,startInterval,slotCount,trail,decodeMode,label)
  local baseFrame=startInterval*spacing
  local first=decodeBest(blob,clip,baseFrame,false,nil,nil,decodeMode)
  if not first then return nil,"page base frame did not decode" end
  applyTransform(first,transform)
  local usable,poseErr=actionPoseUsable(template,first,label)
  if not usable then return nil,"page base "..tostring(poseErr or "pose invalid") end

  local model={groups={},bounds=first.bounds,vertexCount=template.vertexCount,
    jointPositions=first.jointPositions,jointFrames={}}
  for gi,tg in ipairs(template.groups or {}) do
    local fg=first.groups[gi]
    local outg=copyGroupShell(tg)
    for vi,tv in ipairs(tg.vertices or {}) do
      local fv=fg.vertices[vi]
      outg.vertices[vi]={fv[1],fv[2],fv[3],tv[4] or 0,tv[5] or 0,tv[6] or 0,tv[7] or 1,tv[8] or 0}
    end
    model.groups[gi]=outg
  end

  local validSlots={}
  local attached=0
  for slot=1,MORPH_SLOTS do
    local usableSlot=slot<=slotCount
    local frame=(startInterval+math.min(slot,slotCount))*spacing
    local sample=usableSlot and decodeBest(blob,clip,frame,false,nil,nil,decodeMode) or nil
    if sample then applyTransform(sample,transform) end
    local ok,reason=false,nil
    if sample then ok,reason=actionPoseUsable(template,sample,label)
    elseif usableSlot then reason="frame did not decode" end
    for gi,g in ipairs(model.groups or {}) do
      local sv=ok and sample.groups[gi].vertices or nil
      for vi,v in ipairs(g.vertices or {}) do
        local o=sv and sv[vi] or v
        local at=6+slot*3
        v[at+1]=o[1];v[at+2]=o[2];v[at+3]=o[3]
      end
    end
    local joints=(ok and sample and sample.jointPositions) or model.jointPositions or {}
    local jf={}
    for ji,j in ipairs(joints) do jf[ji]={j[1] or 0,j[2] or 0,j[3] or 0} end
    model.jointFrames[slot]=jf
    validSlots[slot]=ok and true or false
    if ok then attached=attached+1
    elseif usableSlot then
      trail[#trail+1]=("native %s dense frame %.3f unusable (%s); page slot %d bridges")
        :format(label,frame,tostring(reason or "invalid pose"),slot)
    end
  end
  if attached<1 then return nil,"dense page has no authored target frames" end
  return {
    model=model,morphFrames=slotCount,validSlots=validSlots,
    startInterval=startInterval,endInterval=startInterval+slotCount,
    attached=attached,
  }
end

local function buildActionPages(blob,template,clip,transform,duration,endFrame,trail,decodeMode,label)
  local intervals=denseReactionIntervals(label,duration,endFrame)
  if intervals<=MORPH_SLOTS then return nil end
  local finalFrame=tonumber(endFrame)
  if not finalFrame or finalFrame<=0.5 then finalFrame=math.max(1,(tonumber(duration) or .25)*30-1) end
  local spacing=math.max(.25,finalFrame/intervals)
  local pages={}
  local start=0
  local validTotal=0
  while start<intervals do
    local count=math.min(MORPH_SLOTS,intervals-start)
    local page,err=buildActionPage(blob,template,clip,transform,spacing,start,count,trail,decodeMode,label)
    if not page then return nil,err end
    page.startPhase=start/intervals
    page.endPhase=(start+count)/intervals
    pages[#pages+1]=page
    validTotal=validTotal+(page.attached or 0)
    start=start+count
  end
  return pages,nil,spacing,intervals,validTotal
end

local function extractActionBanks(blob,template,transform,metadata,clipCount,trail,decodeMode)
  local actions={}
  if not (metadata and type(metadata.slots)=="table") then
    trail[#trail+1]="PKX action banks: metadata unavailable; retaining legacy single-clip fallback"
    return actions
  end

  -- Runtime semantics consume six action classes: idle, physical, special,
  -- status, damage and faint. Older extraction decoded every alternate
  -- Physical/Idle/Status slot up front even though the runtime only ever uses
  -- those alternates as fallbacks when the primary slot is absent or invalid.
  -- For a large species that multiplied HSD decode work and cache size several
  -- times over. Resolve the same fallback order here and cache only the first
  -- usable source clip for each semantic class. Visible behavior is unchanged:
  -- if Physical A fails we still try B/C/D/E, etc.; we just stop once the exact
  -- bank the runtime would select has been proven.
  local semanticOrder={
    {"idle",     {"idle","idleB","idleC","idleD","idleE"}},
    {"physicalA",{"physicalA","physicalB","physicalC","physicalD","physicalE"}},
    {"specialC", {"specialC","statusA","statusB"}},
    {"statusA",  {"statusA","statusB","specialC"}},
    {"damage",   {"damage"}},
    {"faint",    {"faint"}},
  }

  local ownerByClip={}
  local failedClip={}

  local function slotInfo(key)
    local slot=metadata.slots[key]
    local clip=slot and tonumber(slot.animationIndex) or nil
    local duration=slot and tonumber(slot.duration) or 0
    if not clip or clip<0 or (clipCount and clipCount>0 and clip>=clipCount) then return nil end
    return slot,clip,duration
  end

  local function buildSemantic(requestKey,candidates)
    for _,sourceKey in ipairs(candidates) do
      local slot,clip,duration=slotInfo(sourceKey)
      if slot then
        local clipInfo=nil
        if HSD and type(HSD.nativeAnimationInfo)=="function" then
          local okInfo,value=pcall(HSD.nativeAnimationInfo,template,clip)
          if okInfo and type(value)=="table" then clipInfo=value end
        end
        local endFrame=clipInfo and tonumber(clipInfo.endFrame) or nil
        local owner=ownerByClip[clip]
        if owner then
          actions[requestKey]={alias=owner,clip=clip,duration=duration}
          trail[#trail+1]=("native %-11s -> clip %d (source %s, alias %s) duration %.3fs")
            :format(requestKey,clip,sourceKey,owner,duration)
          return true
        end

        if not failedClip[clip] then
          local pages,pageErr,pageSpacing,pageIntervals,pageValid=
            buildActionPages(blob,template,clip,transform,duration,endFrame,trail,decodeMode,requestKey)
          if pages then
            ownerByClip[clip]=requestKey
            actions[requestKey]={pages=pages,clip=clip,duration=duration,frameSpacing=pageSpacing,sourceEndFrame=endFrame,
              totalIntervals=pageIntervals,validMorphFrames=pageValid,dense=true}
            trail[#trail+1]=("native %-11s -> clip %d (source %s) dense=%d intervals / %d pages valid=%d spacing=%.3f duration=%.3fs")
              :format(requestKey,clip,sourceKey,pageIntervals,#pages,pageValid or 0,pageSpacing,duration)
            return true
          end

          local model,err,spacing,attached,validSlots=
            buildActionModel(blob,template,clip,transform,duration,endFrame,trail,decodeMode,requestKey)
          if model then
            ownerByClip[clip]=requestKey
            actions[requestKey]={model=model,clip=clip,duration=duration,frameSpacing=spacing,sourceEndFrame=endFrame,
              morphFrames=MORPH_SLOTS,validMorphFrames=attached,validSlots=validSlots}
            trail[#trail+1]=("native %-11s -> clip %d (source %s) %d/%d valid targets playback=%d spacing=%.3f duration=%.3fs")
              :format(requestKey,clip,sourceKey,attached,MORPH_SLOTS,MORPH_SLOTS,spacing,duration)
            return true
          end
          failedClip[clip]=tostring(pageErr or err or "source bank rejected")
        end

        trail[#trail+1]=("native %-11s source %-11s clip %d rejected: %s; trying fallback")
          :format(requestKey,sourceKey,clip,tostring(failedClip[clip]))
      end
    end
    trail[#trail+1]=("native %-11s unavailable after source fallback sweep"):format(requestKey)
    return false
  end

  for _,spec in ipairs(semanticOrder) do buildSemantic(spec[1],spec[2]) end
  return actions
end

local function jointLua(joints)
  local out={"{"}
  for _,j in ipairs(joints or {}) do
    out[#out+1]="{"..num(j[1] or 0)..","..num(j[2] or 0)..","..num(j[3] or 0).."},"
  end
  out[#out+1]="}"
  return table.concat(out)
end
local function jointFramesLua(frames)
  local out={"{"}
  for slot=1,MORPH_SLOTS do out[#out+1]=jointLua(frames and frames[slot] or {}).."," end
  out[#out+1]="}"
  return table.concat(out)
end
local function validSlotsLua(slots)
  local out={"{"}
  for slot=1,MORPH_SLOTS do out[#out+1]=(slots and slots[slot] and "true" or "false").."," end
  out[#out+1]="}"
  return table.concat(out)
end


-- Store dense vertex payloads as strings instead of Lua numeric table literals.
-- Large species such as Charizard can exceed Lua/LuaJIT's 65,536-constant
-- function limit when every scalar is emitted directly into model_cache.lua.
-- One packed string per render group keeps the generated chunk tiny while
-- preserving exactly the same 44-float vertex rows. PokemonActors expands the
-- strings only after the cache chunk has loaded.
local function normalizedVertexRow(v)
  local row={v[1],v[2],v[3],v[4] or 0,v[5] or 0,v[6] or 0,v[7] or 1,v[8] or 0}
  for slot=1,MORPH_SLOTS do
    local at=6+slot*3
    row[#row+1]=v[at+1] or v[1]
    row[#row+1]=v[at+2] or v[2]
    row[#row+1]=v[at+3] or v[3]
  end
  return row
end
-- Emits the same "a,b,c\n..." blob as before, but writes each component
-- straight into one buffer instead of building a per-vertex parts table and
-- running table.concat once per vertex. A single Pokemon body is thousands of
-- vertices and this runs for every species and every action page.
local function packedVerticesLua(vertices)
  local out,n={},0
  local first=true
  for _,v in ipairs(vertices or {}) do
    local row=normalizedVertexRow(v)
    if first then first=false else n=n+1;out[n]="\n" end
    for i=1,STRIDE do
      if i>1 then n=n+1;out[n]="," end
      n=n+1;out[n]=num(row[i])
    end
  end
  return q(table.concat(out,"",1,n))
end
local unpackArgs=table.unpack or unpack
-- Batched exactly like RuntimeMeshCache.packRows: one love.data.pack call and
-- one intermediate string per 64 vertices instead of per vertex. Identical
-- output bytes.
local RUNTIME_PACK_BATCH=64
local function runtimeVerticesBytes(vertices)
  if not (love and love.data and type(love.data.pack)=="function") then return nil end
  vertices=vertices or {}
  local count=#vertices
  if count==0 then return nil end
  local rowFmt=string.rep("f",STRIDE)
  local batchFmt=string.rep(rowFmt,RUNTIME_PACK_BATCH)
  local buf={}
  local chunks,chunkCount={},0
  local i=1
  while i<=count do
    local take=count-i+1;if take>RUNTIME_PACK_BATCH then take=RUNTIME_PACK_BATCH end
    local k=0
    for r=i,i+take-1 do
      local row=normalizedVertexRow(vertices[r])
      for j=1,STRIDE do k=k+1;buf[k]=row[j] end
    end
    local ok,bytes=pcall(love.data.pack,"string",
      take==RUNTIME_PACK_BATCH and batchFmt or string.rep(rowFmt,take),unpackArgs(buf,1,k))
    if not ok or type(bytes)~="string" then return nil end
    chunkCount=chunkCount+1;chunks[chunkCount]=bytes
    i=i+take
  end
  return table.concat(chunks,"",1,chunkCount)
end

local function appendPackedActionGroups(out,model)
  out[#out+1]="groups={\n"
  for _,g in ipairs((model and model.groups) or {}) do
    out[#out+1]="{vertexStride="..tostring(STRIDE)..",verticesPacked="..packedVerticesLua(g.vertices).."},\n"
  end
  out[#out+1]="}"
end

local ACTION_ORDER={"idle","physicalA","specialC","statusA","damage","faint"}

local function actionPayloadLua(a)
  local out={"-- Generated native Pokemon action bank.\nreturn {clip="..tostring(a.clip or -1)
    ..",duration="..num(a.duration or 0)}
  if a.pages then
    out[#out+1] = ",dense=true,frameSpacing="..tostring(a.frameSpacing or 1)
      ..",totalIntervals="..tostring(a.totalIntervals or 0)..",pages={\n"
    for _,page in ipairs(a.pages or {}) do
      out[#out+1]="{startPhase="..num(page.startPhase or 0)..",endPhase="..num(page.endPhase or 1)
        ..",morphFrames="..tostring(page.morphFrames or 0)
        ..",validSlots="..validSlotsLua(page.validSlots)
        ..",jointPositions="..jointLua(page.model and page.model.jointPositions)
        ..",jointFrames="..jointFramesLua(page.model and page.model.jointFrames)..","
      appendPackedActionGroups(out,page.model)
      out[#out+1]="},\n"
    end
    out[#out+1]="}"
  else
    out[#out+1] = ",frameSpacing="..tostring(a.frameSpacing or 1)
      ..",morphFrames="..tostring(a.morphFrames or 0)
      ..",validSlots="..validSlotsLua(a.validSlots)
      ..",jointPositions="..jointLua(a.model and a.model.jointPositions)
      ..",jointFrames="..jointFramesLua(a.model and a.model.jointFrames)..","
    appendPackedActionGroups(out,a.model)
  end
  out[#out+1]="}\n"
  return table.concat(out)
end

local function metadataCacheLua(metadata)
  if type(metadata)~="table" then return nil end
  local out={"-- Compact PKX runtime metadata generated from the user's GC6E01 disc.\nreturn {revision=1,bodyMap={"}
  local keys={"origin","mouth","chest","tail","eye_left","eye_right","hand_left","hand_right","additional_1","additional_2","additional_3","additional_4","foot_left","foot_right","center","additional_5"}
  for _,key in ipairs(keys) do out[#out+1]="["..q(key).."]="..tostring(tonumber(metadata.bodyMap and metadata.bodyMap[key]) or -1).."," end
  out[#out+1]="},slots={"
  local slotKeys={"idle","statusA","physicalA","physicalB","physicalC","physicalD","statusB","physicalE","damage","damageHeavy","faint","idleB","specialC","idleC","idleD","idleE","takeFlight"}
  for _,key in ipairs(slotKeys) do
    local slot=metadata.slots and metadata.slots[key]
    if type(slot)=="table" then
      out[#out+1]="["..q(key).."]={animationIndex="..tostring(tonumber(slot.animationIndex) or -1)..",duration="..num(slot.duration or 0).."},"
    end
  end
  out[#out+1]="}}\n"
  return table.concat(out)
end

local function cacheLua(stem,dex,model,texturePaths,clip,clipCount,frameSpacing,attached,sourceName,decodeMode,actionRefs,runtimeBins,runtimeStamp)
  local b=model.bounds
  local out={
    "-- Generated locally from the user's own Pokemon Colosseum GC6E01 disc.\n",
    "return {formatVersion=4,poseFormat=\"source-hsd-authored-pages-v4-split-actions\",\n",
    "dex=",tostring(dex),",stem=",q(stem),",source=",q(sourceName),",\n",
    "clip=",tostring(clip),",clipCount=",tostring(clipCount),
    ",frameSpacing=",tostring(frameSpacing),",morphFrames=",tostring(attached),
    ",morphSlots=",tostring(MORPH_SLOTS),",\n",
    "vertexCount=",tostring(model.vertexCount or 0),
    ",groupCount=",tostring(#(model.groups or {})),
    ",requestedDecodeMode=",q(tostring(decodeMode or "auto")),
    ",decodePath=",q(tostring(model.__cbeDecodePath or "?")),
    ",heightRatio=",num(model.__cbeHeightRatio or 0),
    ",widthRatio=",num(model.__cbeWidthRatio or 0),
    ",envBlends=",tostring(model.__cbeEnvBlends or 0),
    ",envPobjs=",tostring(model.__cbeEnvPobjs or 0),
    ",envBlendsMulti=",tostring(model.__cbeEnvBlendsMulti or 0),
    ",skinFix=",tostring(model.__cbeSkinFix~=false),
    ",poseDrift=",num(model.__cbeDrift or 0),
    ",hiddenJobjs=",tostring(model.__cbeHidden or 0),
    ",quatJobjs=",tostring(model.__cbeQuat or 0),
    ",jointCount=",tostring(model.__cbeJointCount or 0),
    ",jointScaleMin=",num(model.__cbeJointScaleMin or 0),
    ",jointScaleMedian=",num(model.__cbeJointScaleMedian or 0),
    ",jointScaleMax=",num(model.__cbeJointScaleMax or 0),
    ",jointScaleOutliers=",tostring(model.__cbeJointScaleOutliers or 0),
    ",renderPassFilter=",tostring(model.__cbeRenderPassFilter~=false),
    ",nonRenderJobjs=",tostring(model.__cbeNonRenderJobjs or 0),
    ",nonRenderDobjs=",tostring(model.__cbeNonRenderDobjs or 0),
    ",shadowDobjs=",tostring(model.__cbeShadowDobjs or 0),
    ",semanticRootsOnly=",tostring(model.__cbeSemanticRootsOnly==true),
    ",semanticRootCount=",tostring(model.__cbeSemanticRootCount or 0),
    ",envelopeCoordEntries=",tostring(model.__cbeEnvelopeCoordEntries or 0),
    ",singleEnvelopeCoord=",tostring(model.__cbeSingleEnvelopeCoord or 0),
    ",singleEnvelopeNoCoord=",tostring(model.__cbeSingleEnvelopeNoCoord or 0),
    ",inverseBindMissing=",tostring(model.__cbeInverseBindMissing or 0),
    ",placeholderGroupsRemoved=",tostring(model.__cbePlaceholderGroupsRemoved or 0),
    ",placeholderVertsRemoved=",tostring(model.__cbePlaceholderVertsRemoved or 0),",\n",
    "bounds={min={",num(b.min[1]),",",num(b.min[2]),",",num(b.min[3]),
    "},max={",num(b.max[1]),",",num(b.max[2]),",",num(b.max[3]),
    "},center={",num(b.center[1]),",",num(b.center[2]),",",num(b.center[3]),"}},\n",
    "jointPositions=",jointLua(model.jointPositions),",jointFrames=",jointFramesLua(model.jointFrames),",\n",
    "groups={\n",
  }
  if runtimeBins then
    table.insert(out,3,"runtimeMeshVersion=1,stamp="..q(runtimeStamp or "")..",\n")
  end
  for gi,g in ipairs(model.groups) do
    out[#out+1]="{material="..q("pkx_group_"..gi)
    local tp=texturePaths[gi]
    if tp then out[#out+1]=",texture={path="..q(tp.path)..",w="..tp.w..",h="..tp.h..",wrapS="..tostring(tp.wrapS or 0)..",wrapT="..tostring(tp.wrapT or 0).."}" end
    local d=g.diffuse or {1,1,1}
    local a=g.ambient or {1,1,1}
    local sp=g.specular or {0,0,0}
    out[#out+1]=",diffuse={"..num(d[1] or 1)..","..num(d[2] or 1)..","..num(d[3] or 1).."}"
    out[#out+1]=",ambient={"..num(a[1] or 1)..","..num(a[2] or 1)..","..num(a[3] or 1).."}"
    out[#out+1]=",specular={"..num(sp[1] or 0)..","..num(sp[2] or 0)..","..num(sp[3] or 0).."}"
    out[#out+1]=",alpha="..num(g.alpha or 1)
    out[#out+1]=",shininess="..num(g.shininess or 0)
    out[#out+1]=",xlu="..tostring(g.xlu==true)..",noz="..tostring(g.noz==true)
    out[#out+1]=",renderFlags="..tostring(g.renderFlags or 0)
    out[#out+1]=",shadow="..tostring(g.shadow==true)..",effect="..tostring(g.effect==true)
    out[#out+1]=",textureSlot="..tostring(g.textureSlot or -1)
    if runtimeBins and runtimeBins[gi] then
      out[#out+1]=",vertexStride="..tostring(STRIDE)..",runtimeBin="..q(runtimeBins[gi]).."},\n"
    else
      out[#out+1]=",vertexStride="..tostring(STRIDE)..",verticesPacked="..packedVerticesLua(g.vertices).."},\n"
    end
  end
  out[#out+1]="},\nactions={\n"
  for _,key in ipairs(ACTION_ORDER) do
    local a=actionRefs and actionRefs[key]
    if a then
      out[#out+1]="["..q(key).."]={clip="..tostring(a.clip or -1)..",duration="..num(a.duration or 0)
      if a.alias then out[#out+1]=",alias="..q(a.alias)
      elseif a.path then out[#out+1]=",path="..q(a.path) end
      out[#out+1]="},\n"
    end
  end
  out[#out+1]="}}\n"
  return table.concat(out)
end

local function write(mod,path,data,generated)
  local ok,err=mod.cache:write(path,data)
  assert(ok,err or ("cache write failed: "..path))
  if generated then generated[#generated+1]=path end
end

function P.cachePath(dex) return ("cache/pokemon/%d/model_cache.lua"):format(tonumber(dex) or 0) end
function P.revPath(dex) return ("cache/pokemon/%d/rev.txt"):format(tonumber(dex) or 0) end

-- Stamp identifying the extraction that produced a species cache. Species are
-- extracted lazily and then reused forever, so WITHOUT this stamp an improved
-- extractor never touches a Pokemon that was already built by an older one --
-- the fix ships, the cache is reused verbatim, and nothing changes on screen.
-- That is exactly what happened between 1.5.0 and 1.5.1.
--
-- Bump P.revision whenever the emitted geometry, pose sampling or vertex layout
-- changes, and every previously cached species rebuilds on next encounter.
local function stampOptions(opts)
  opts=opts or {}
  return {
    skinFix=opts.skinFix~=false,
    renderPassFilter=opts.renderPassFilter~=false,
    decodeMode=tostring(opts.decodeMode or "auto"),
  }
end

function P.stamp(opts)
  local o=stampOptions(opts)
  return ("pkx-extractor=%d\nstride=%d\nmorphSlots=%d\nskinFix=%s\nrenderPassFilter=%s\ndecodeMode=%s\n")
    :format(P.revision,STRIDE,MORPH_SLOTS,tostring(o.skinFix),tostring(o.renderPassFilter),o.decodeMode)
end

function P.isCached(mod,dex,opts)
  if not (mod.cache and mod.cache.info) then return false end
  local info=mod.cache:info(P.cachePath(dex))
  if not (type(info)=="table" and (info.type==nil or info.type=="file")) then return false end
  -- Cache validity includes every debug option that changes emitted geometry.
  -- Without this, an F4/F6/F10 A/B extraction survives a restart under a
  -- different on-screen toggle state. The global overlay can then say ON while
  -- the actual species cache says filter=OFF -- exactly what the 1.5.21 F5
  -- screenshots exposed.
  local ok,raw=pcall(mod.cache.read,mod.cache,P.revPath(dex))
  return ok and raw==P.stamp(opts)
end

P.MANIFEST="cache/pokemon/manifest.lua"

-- Species are extracted lazily, long after BuildPipeline has finished writing
-- build/generated_paths.lua. Without a manifest of their own they would survive
-- a "clear generated runtime", leaving stale models behind after a rebuild.
-- CacheManager reads this file and deletes everything it names.
local function readManifest(mod)
  local ok,raw=pcall(mod.cache.read,mod.cache,P.MANIFEST)
  if not ok or type(raw)~="string" then return {} end
  local chunk=load(raw,"@generated/"..P.MANIFEST)
  -- NOT `local ok,value=chunk and pcall(chunk)`. In Lua an `and` expression
  -- yields exactly ONE value, so that form silently discards pcall's second
  -- return and `value` is always nil.
  if not chunk then return {} end
  local okRun,value=pcall(chunk)
  if not okRun or type(value)~="table" then return {} end
  return value
end

function P.manifestPaths(mod)
  local out={}
  for _,entry in ipairs(readManifest(mod)) do
    if type(entry)=="table" then
      for _,path in ipairs(entry.paths or {}) do out[#out+1]=path end
    end
  end
  out[#out+1]=P.MANIFEST
  return out
end

local function recordManifest(mod,dex,stem,paths)
  local list=readManifest(mod)
  local replaced=false
  for i,entry in ipairs(list) do
    if type(entry)=="table" and tonumber(entry.dex)==tonumber(dex) then
      list[i]={dex=dex,stem=stem,paths=paths};replaced=true;break
    end
  end
  if not replaced then list[#list+1]={dex=dex,stem=stem,paths=paths} end
  local out={"-- Generated. Lazily extracted Colosseum Pokemon caches.\nreturn {\n"}
  for _,entry in ipairs(list) do
    out[#out+1]=("{dex=%d,stem=%s,paths={"):format(tonumber(entry.dex) or 0,q(entry.stem))
    for _,path in ipairs(entry.paths or {}) do out[#out+1]=q(path).."," end
    out[#out+1]="}},\n"
  end
  out[#out+1]="}\n"
  pcall(mod.cache.write,mod.cache,P.MANIFEST,table.concat(out))
end

-- Extract exactly one species. This is the lazy unit: the runtime calls it the
-- first time a Pokemon is sent out, and never again for that species.
-- targetHeight is in the same authored world units the arena/trainer caches use.
function P.extractSpecies(mod,disc,dex,opts)
  opts=opts or {}
  local targetHeight=tonumber(opts.targetHeight) or 16.0
  local progress=opts.progress or function() end
  local generated=opts.generated
  currentSkinFix=opts.skinFix~=false
  currentRenderPassFilter=opts.renderPassFilter~=false

  -- Flight recorder: written BEFORE any decode work, unconditionally, so that
  -- if this call never returns at all (a native/engine-level fault that a
  -- Lua pcall around this whole function cannot catch or report), there is
  -- still a file on disk naming exactly which species and options were being
  -- attempted at the moment of the failure. This is the only way to get real
  -- evidence out of a crash that leaves no on-screen trace and no log of its
  -- own -- it does not diagnose anything by itself, it just guarantees a
  -- next-of-kin note survives. Overwritten on every call, so it always
  -- reflects the most recent attempt; look for cache/pokemon/_last_attempt.txt
  -- (inside the mod's cache folder) after a crash and send its contents back.
  pcall(function()
    mod.cache:write("cache/pokemon/_last_attempt.txt",
      ("dex=%s skinFix=%s renderPassFilter=%s decodeMode=%s time=%s\n")
        :format(tostring(dex),tostring(currentSkinFix),tostring(currentRenderPassFilter),
          tostring(opts.decodeMode or "auto"),tostring(os.time and os.time() or "?")))
  end)

  local archiveName,stem=Dex.archive(dex,opts.variant,opts.unownForm)
  if not archiveName then return nil,("dex %s has no Colosseum asset"):format(tostring(dex)) end

  local trail={("pkx %s dex=%s archive=%s"):format(safe(stem),tostring(dex),safe(archiveName))}

  local file=disc:file(archiveName)
  if not file then return nil,("source archive missing: "..archiveName) end
  local okArc,arc=pcall(FSYS.open,disc,file)
  if not okArc then return nil,("FSYS open failed for %s: %s"):format(archiveName,safe(arc)) end

  local members=arc:list()
  if #members==0 then return nil,("archive %s has no members"):format(archiveName) end
  -- Exactly one member is expected. If a disc revision ever ships more, prefer
  -- the typed model member rather than blindly taking index 0.
  local entry=members[1]
  local typed=arc:modelEntries()
  if #typed>0 then entry=typed[1] end
  trail[#trail+1]=("member %s type=0x%02X bytes=%d"):format(safe(entry.name),entry.fileType or 0,entry.storedSize or 0)

  progress(("POKEMON %s DECOMPRESS"):format(stem:upper()),0,1)
  local okBlob,blob=pcall(arc.extract,arc,entry,{
    maxOutput=48*1024*1024,
    progress=function(done,total)
      local pct=(tonumber(total) or 0)>0 and math.floor((tonumber(done) or 0)*100/total) or 0
      progress(("POKEMON %s DECOMPRESS %d%%"):format(stem:upper(),pct),0,1)
    end,
  })
  if not okBlob or type(blob)~="string" then
    return nil,("LZSS extract failed for %s: %s"):format(archiveName,safe(blob))
  end
  trail[#trail+1]=("decompressed bytes=%d"):format(#blob)

  progress(("POKEMON %s CLIPS"):format(stem:upper()),0,1)
  local decodeMode=tostring(opts.decodeMode or "auto")
  trail[#trail+1]="decode mode: "..decodeMode
  trail[#trail+1]="skin fix: "..(currentSkinFix and "on (native IBM + owner-coordinate envelope matrices)" or "off (legacy raw-world envelope path)")
  trail[#trail+1]="source render-pass filter: "..(currentRenderPassFilter and "on (skip JOBJ geometry the Colosseum renderer never submits)" or "off (diagnostic legacy draw-all)")
  local clip,clipCount,clipNote=chooseIdleClip(blob,targetHeight,trail,decodeMode)
  if clipNote then trail[#trail+1]="note: "..clipNote end
  clip=clip or 0

  progress(("POKEMON %s DECODE"):format(stem:upper()),0,1)
  local attachedOverride=nil
  local base,decodePath,_,decodeErr=decodeBest(blob,clip,0,true,trail,"final",decodeMode)
  if not base then
    return nil,("HSD decode failed for %s: %s"):format(archiveName,safe(decodeErr))
  end

  -- Last line of defence. If the selected pose still decodes less geometry than
  -- the bind pose, take the bind pose instead: a complete static Pokemon is
  -- strictly better than an animated fragment, and the diagnostic says so
  -- plainly rather than leaving a mystery on screen.
  -- Report geometry health BEFORE normalizing, while the numbers are still in
  -- source units and directly comparable across species.
  local pre=boundsReport(base)
  if pre then
    trail[#trail+1]=("pre-normalize height raw=%.4f trimmed=%.4f ratio=%.2f | width raw=%.4f trimmed=%.4f ratio=%.2f | verts=%d")
      :format(pre.rawH,pre.trimH,pre.heightRatio,pre.rawW,pre.trimW,pre.widthRatio,pre.count)
    if pre.heightRatio>1.6 or pre.widthRatio>1.6 then
      trail[#trail+1]="WARNING: outlier vertices detected. A few strays are inflating the bounding box, "
        .."which shrinks the visible body when the model is normalized. Likely an envelope/bind transform "
        .."issue on skinned POBJs rather than missing geometry."
    end
  end

  local transform=measure(base,targetHeight)
  applyTransform(base,transform)

  -- Coherence is measured only AFTER normalization, and the bind copy is put
  -- through the SAME transform. Comparing a normalized model against one still
  -- in raw source units makes every clip look catastrophically incoherent --
  -- which is exactly what an earlier ordering of this check did, rejecting even
  -- a gentle two-percent idle.
  local bindRef=decodeBest(blob,0,0,true,nil,nil,decodeMode)
  local bindVerts=bindRef and tonumber(bindRef.vertexCount) or 0
  local poseVerts=tonumber(base.vertexCount) or 0
  local finalDrift=nil
  if clip>0 and bindRef then
    applyTransform(bindRef,transform)
    finalDrift=motionRatio(bindRef,base,targetHeight)
  end
  local lostGeometry=(clip>0 and bindVerts>0 and poseVerts<bindVerts*0.995)
  local incoherent=(finalDrift~=nil and finalDrift>POSE_COHERENCE_MAX)
  if clip>0 and (lostGeometry or incoherent) then
    trail[#trail+1]=("FALLBACK TO BIND POSE: clip %d %s. Cached static and correctly "
      .."assembled instead of animated and scattered.")
      :format(clip,lostGeometry
        and ("decoded %d verts vs %d at bind"):format(poseVerts,bindVerts)
        or ("drifts %.3f from bind, past the %.2f limit"):format(finalDrift,POSE_COHERENCE_MAX))
    base=bindRef
    decodePath=(decodePath or "?").."/bind-fallback"
    clip=0
    attachedOverride=0
  end
  base.__cbeDrift=finalDrift or 0
  trail[#trail+1]=("decoded via %s: vertices=%d groups=%d")
    :format(tostring(decodePath),base.vertexCount or 0,#(base.groups or {}))

  -- Frame spacing is a guess only in its magnitude, never in its source: every
  -- sampled frame is still an authored HSD frame. If a clip turns out shorter
  -- than MORPH_SLOTS*spacing, the tail frames clamp to the clip's last key,
  -- which reads as a hold rather than as a glitch.
  local metadata=nil
  if PKXMetadata and type(PKXMetadata.parse)=="function" then
    local okMeta,value=pcall(PKXMetadata.parse,blob)
    if okMeta and type(value)=="table" then metadata=value
    else trail[#trail+1]="PKX metadata parse failed: "..safe(value) end
  end
  local actions=extractActionBanks(blob,base,transform,metadata,clipCount or 0,trail,decodeMode)

  local spacing=math.max(1,math.floor(tonumber(opts.frameSpacing) or 4))
  local attached=0
  if attachedOverride==0 then clip=0 end
  if clip>0 then
    progress(("POKEMON %s FRAMES"):format(stem:upper()),0,1)
    attached=attachFrames(blob,base,clip,transform,targetHeight,spacing,trail,decodeMode)
    trail[#trail+1]=("authored frames attached=%d/%d spacing=%d"):format(attached,MORPH_SLOTS,spacing)
  else
    trail[#trail+1]="static: no authored clip selected"
  end

  base.__cbeDecodePath=decodePath
  -- HSD envelope diagnostics. These counts are palette/deformation matrices,
  -- not vertex counts; a species can be completely single-bone weighted and
  -- still require owner-coordinate + inverse-bind correction.
  local st=base.stats or {}
  base.__cbeEnvBlends=tonumber(st.envelopeBlends) or 0
  base.__cbeEnvPobjs=tonumber(st.envelopePobjs) or 0
  base.__cbeEnvBlendsMulti=tonumber(st.envelopeBlendsMulti) or 0
  base.__cbeSkinFix=currentSkinFix
  base.__cbeHidden=tonumber(st.hiddenJobjs) or 0
  base.__cbeQuat=tonumber(st.quatJobjs) or 0
  trail[#trail+1]=("envelopes: %d matrices (%d multi-bone) across %d enveloped meshes")
    :format(base.__cbeEnvBlends,base.__cbeEnvBlendsMulti,base.__cbeEnvPobjs)
  -- Every contributing joint's own world matrix, independent of which
  -- texture-merged render group its vertices end up bucketed into below.
  -- Skinning, hidden joints, pose drift and single-vs-scene decode are all
  -- ruled out for these test species -- this checks a mechanism none of
  -- those touch: a joint with a near-zero world scale collapses whatever is
  -- attached to it to a point, regardless of how correct its LOCAL SRT and
  -- its neighbors' world matrices are.
  base.__cbeJointCount=tonumber(st.jointCount) or 0
  base.__cbeJointScaleMin=tonumber(st.jointScaleMin) or 0
  base.__cbeJointScaleMedian=tonumber(st.jointScaleMedian) or 0
  base.__cbeJointScaleMax=tonumber(st.jointScaleMax) or 0
  base.__cbeJointScaleOutliers=tonumber(st.jointScaleOutliers) or 0
  trail[#trail+1]=("joint world scale: %d contributing joints, min=%.4f median=%.4f max=%.4f, %d outlier(s) >=10x off median")
    :format(base.__cbeJointCount,base.__cbeJointScaleMin,base.__cbeJointScaleMedian,base.__cbeJointScaleMax,base.__cbeJointScaleOutliers)
  -- Source-faithful PKX placement diagnostics. The previous builds focused on
  -- a made-up global PNMTXIDX->JOBJ mapping; native HSD instead uses an envelope
  -- palette plus an owner-relative coordinate matrix and each deformer joint's
  -- stored inverse-bind matrix. These counters tell us whether the corrected
  -- path is being exercised by a real species.
  base.__cbeRenderPassFilter=currentRenderPassFilter
  base.__cbeNonRenderJobjs=tonumber(st.nonRenderJobjs) or 0
  base.__cbeNonRenderDobjs=tonumber(st.nonRenderDobjs) or 0
  base.__cbeShadowDobjs=tonumber(st.shadowDobjs) or 0
  base.__cbeSemanticRootsOnly=base.semanticRootsOnly==true
  base.__cbeSemanticRootCount=tonumber(base.semanticRootCount) or 0
  base.__cbeEnvelopeCoordEntries=tonumber(st.envelopeCoordEntries) or 0
  base.__cbeSingleEnvelopeCoord=tonumber(st.singleEnvelopeCoord) or 0
  base.__cbeSingleEnvelopeNoCoord=tonumber(st.singleEnvelopeNoCoord) or 0
  base.__cbeInverseBindMissing=tonumber(st.inverseBindMissing) or 0
  trail[#trail+1]=("source visibility: %d non-render JOBJ(s) + %d DOBJ pass mismatch(es) skipped; %d shadow-pass DOBJ(s) quarantined")
    :format(base.__cbeNonRenderJobjs,base.__cbeNonRenderDobjs,base.__cbeShadowDobjs)
  trail[#trail+1]=("root selection: %s (%d semantic model-set root%s)")
    :format(base.__cbeSemanticRootsOnly and "scene-modelset-only" or "scene-union/legacy",
      base.__cbeSemanticRootCount,base.__cbeSemanticRootCount==1 and "" or "s")
  trail[#trail+1]=("envelope coord: %d palette entries use owner coord; single-bone coord=%d no-coord=%d; missing IBM fallbacks=%d")
    :format(base.__cbeEnvelopeCoordEntries,base.__cbeSingleEnvelopeCoord,base.__cbeSingleEnvelopeNoCoord,base.__cbeInverseBindMissing)
  if pre then base.__cbeHeightRatio=pre.heightRatio;base.__cbeWidthRatio=pre.widthRatio end

  -- 1.5.20 guessed at junk geometry from texture/size/distance. That can cut
  -- legitimate untextured parts and still misses helpers near the body. 1.5.21
  -- disables that heuristic; source JOBJ render-pass flags now decide visibility.
  base.__cbePlaceholderGroupsRemoved=tonumber(st.placeholderGroupsRemoved) or 0
  base.__cbePlaceholderVertsRemoved=tonumber(st.placeholderVertsRemoved) or 0

  base=mergeGroups(base)
  -- Action banks use the exact same source DOBJ/material grouping as the body.
  -- Merge after sampling, then reject any bank that no longer matches the
  -- proven base topology rather than risking a scrambled action mesh.
  for key,a in pairs(actions or {}) do
    if a.model then
      a.model=mergeGroups(a.model)
      if not topologyMatches(base,a.model) then
        trail[#trail+1]=("native %s rejected after material merge: topology mismatch"):format(key)
        actions[key]=nil
      end
    end
  end

  local texturePaths,textureMap={},{}
  for gi,g in ipairs(base.groups) do
    if g.texture then
      local sig=signature(g.texture)
      local tp=textureMap[sig]
      if not tp then
        local path=("cache/pokemon/%d/tex_%02d.rgba"):format(dex,gi)
        write(mod,path,g.texture.rgba,generated)
        tp={path=path,w=g.texture.w,h=g.texture.h}
        textureMap[sig]=tp
      end
      -- Wrap state belongs to the TOBJ/material use, not to the shared image.
      texturePaths[gi]={path=tp.path,w=tp.w,h=tp.h,wrapS=g.texture.wrapS or 0,wrapT=g.texture.wrapT or 0}
    end
  end

  for gi,g in ipairs(base.groups or {}) do
    local d=g.diffuse or {1,1,1}
    trail[#trail+1]=("  group %d: %d verts%s slot=%d diffuse=%.3f,%.3f,%.3f alpha=%.3f flags=0x%08X%s%s")
      :format(gi,#(g.vertices or {}),
        g.texture and (" tex %dx%d"):format(g.texture.w or 0,g.texture.h or 0) or " (untextured)",
        g.textureSlot or -1,d[1] or 1,d[2] or 1,d[3] or 1,g.alpha or 1,g.renderFlags or 0,
        g.shadow and " SHADOW" or "",g.effect and " EFFECT" or "")
  end

  local sourceName=archiveName.." :: "..tostring(entry.name)
  local cachePath=P.cachePath(dex)
  local diagPath=("cache/pokemon/%d/extract.txt"):format(dex)

  -- Keep large native action payloads out of model_cache.lua. Stats/Data and
  -- battle entry need the base body immediately; embedding every attack/hurt
  -- bank in the same Lua chunk forced the loader to parse megabytes of packed
  -- strings before a single model could appear. Each semantic bank now has its
  -- own generated file and the main cache carries only tiny references. Old v3
  -- inline caches remain runtime-compatible, so this performance format does
  -- not force existing users through another extraction rebuild.
  local actionRefs,actionPaths={},{}
  for _,key in ipairs(ACTION_ORDER) do
    local a=actions and actions[key]
    if a then
      if a.alias then
        actionRefs[key]={alias=a.alias,clip=a.clip,duration=a.duration}
      else
        local path=("cache/pokemon/%d/actions/%s.lua"):format(dex,key)
        write(mod,path,actionPayloadLua(a),generated)
        actionRefs[key]={path=path,clip=a.clip,duration=a.duration}
        actionPaths[#actionPaths+1]=path
      end
    end
  end

  local metadataPath=("cache/pokemon/%d/metadata_v1.lua"):format(dex)
  local metadataLua=metadataCacheLua(metadata)
  if metadataLua then write(mod,metadataPath,metadataLua,generated) end
  write(mod,cachePath,cacheLua(stem,dex,base,texturePaths,clip,clipCount or 0,spacing,attached,sourceName,decodeMode,actionRefs),generated)

  -- Runtime-ready float32 sidecars are emitted while the freshly decoded HSD
  -- vertex tables are already in memory. On Android this avoids serializing the
  -- exact same geometry to CSV and immediately reparsing thousands of tonumber
  -- calls before the first visible send-out. The textual cache remains the
  -- canonical/fail-open source on hosts without love.data.pack.
  local runtimePaths={}
  local runtimeBins={}
  local runtimeOK=love and love.data and type(love.data.pack)=="function"
  if runtimeOK then
    for gi,g in ipairs(base.groups or {}) do
      local bytes=runtimeVerticesBytes(g.vertices)
      local path=("cache/pokemon/%d/runtime_mesh_v1/base_%02d.f32"):format(dex,gi)
      if not bytes then runtimeOK=false;break end
      local okWrite=write(mod,path,bytes,generated)
      if okWrite==false then runtimeOK=false;break end
      runtimeBins[gi]=path;runtimePaths[#runtimePaths+1]=path
    end
  end
  local stamp=P.stamp({skinFix=currentSkinFix,renderPassFilter=currentRenderPassFilter,decodeMode=decodeMode})
  if runtimeOK and #runtimeBins==#(base.groups or {}) and #runtimeBins>0 then
    local runtimeMeta=("cache/pokemon/%d/runtime_mesh_v1/base.lua"):format(dex)
    write(mod,runtimeMeta,cacheLua(stem,dex,base,texturePaths,clip,clipCount or 0,spacing,attached,sourceName,decodeMode,actionRefs,runtimeBins,stamp),generated)
    runtimePaths[#runtimePaths+1]=runtimeMeta
    trail[#trail+1]="runtime mesh sidecar: READY (direct float32 upload)"
  else
    trail[#trail+1]="runtime mesh sidecar: deferred to first runtime materialization"
  end
  write(mod,diagPath,table.concat(trail,"\n").."\n",generated)

  -- Written LAST, after every other artifact for this species has landed. A
  -- crash mid-extract therefore leaves an unstamped cache, which isCached
  -- rejects -- so a half-written species rebuilds instead of rendering broken.
  local revPath=P.revPath(dex)
  write(mod,revPath,stamp,generated)

  local written={cachePath,diagPath,revPath}
  for _,path in ipairs(runtimePaths) do written[#written+1]=path end
  if metadataLua then written[#written+1]=metadataPath end
  for _,path in ipairs(actionPaths) do written[#written+1]=path end
  local seenTex={}
  for _,tp in pairs(texturePaths) do
    if tp and not seenTex[tp.path] then seenTex[tp.path]=true;written[#written+1]=tp.path end
  end
  recordManifest(mod,dex,stem,written)

  -- Companion to the flight-recorder write at the top of this function: if
  -- _last_attempt.txt names this dex but this line never got appended, the
  -- crash happened somewhere between those two points, for this species,
  -- under these options -- that narrows a "the game just died" report down
  -- to an actual place in the code instead of nothing at all.
  pcall(function()
    mod.cache:write("cache/pokemon/_last_attempt.txt",
      ("dex=%s skinFix=%s renderPassFilter=%s decodeMode=%s time=%s COMPLETED\n")
        :format(tostring(dex),tostring(currentSkinFix),tostring(currentRenderPassFilter),
          tostring(opts.decodeMode or "auto"),tostring(os.time and os.time() or "?")))
  end)

  progress(("POKEMON %s READY"):format(stem:upper()),1,1)
  return {
    dex=dex,stem=stem,cache=cachePath,archive=archiveName,
    vertices=base.vertexCount,groups=#base.groups,
    clip=clip,clipCount=clipCount or 0,morphFrames=attached,
    nativeActions=(function() local n=0;for _ in pairs(actions or {}) do n=n+1 end;return n end)(),
    bounds=base.bounds,trail=trail,
  }
end

-- Optional batch prefetch. Never called during first-run setup by default: the
-- full roster is ~40 MB compressed and pure-Lua LZSS plus HSD decoding would
-- turn a first launch into a tens-of-minutes stall. Exposed so a settings
-- screen can offer a deliberate background warm-up.
function P.prefetch(mod,disc,list,progress,generated)
  progress=progress or function() end
  local done,failed={},{}
  for i,dex in ipairs(list or {}) do
    progress(("PREFETCH %d/%d"):format(i,#list),i-1,#list)
    if P.isCached(mod,dex,{skinFix=true,renderPassFilter=true,decodeMode="auto"}) then
      done[#done+1]=dex
    else
      local ok,err=P.extractSpecies(mod,disc,dex,{progress=progress,generated=generated})
      if ok then done[#done+1]=dex else failed[#failed+1]={dex=dex,error=tostring(err)} end
    end
  end
  return {cached=done,failed=failed,total=#(list or {})}
end

return P
