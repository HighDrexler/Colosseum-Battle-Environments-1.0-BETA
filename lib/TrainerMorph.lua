local V=...
local M={}

-- ---------------------------------------------------------------------------
-- Unified trainer morph binding (1.7.22)
--
-- Before this module there were two divergent trainer animation paths:
--
--   * non-Windows declared FIFTEEN vertex attributes (position, texcoord,
--     normal, breath, look, gesture1..5, reaction1..5) and a shader with ten
--     morph weights;
--   * Windows declared seven and only ever carried TWO morph slots, so Windows
--     ran visibly poorer trainer animation than every other platform, could not
--     use the compact runtime .f32 mesh sidecar, and had to keep every dense
--     Lua vertex row resident in order to rewrite meshes on the fly.
--
-- Fifteen enabled vertex attributes is above the eight GLES2 guarantees and at
-- the 16 that most mobile drivers cap at, which is a real robustness risk on
-- weaker Android hardware.
--
-- The key observation is that TrainerPerformance's adjacent-frame timeline
-- never produces more than TWO non-zero source-pose weights at a time. The ten
-- attribute slots existed only so the pose data could live statically in the
-- vertex buffer; the shader never blended more than two of them. So two
-- attribute slots are sufficient, and the Windows shader was always the
-- correct general design -- it simply had no way to reach the other eight
-- poses.
--
-- This module keeps the dense 44-float mesh EXACTLY as the cache and the
-- runtime sidecar already store it (no cache format change, no rebuild), and
-- rebinds whichever two source poses are currently active into two shader
-- attribute slots. Every platform now runs the same seven-attribute shader and
-- the same ten source poses.
-- ---------------------------------------------------------------------------

-- Dense mesh layout. Unchanged: this is what trainer cache formatVersion 26
-- and the 44-float runtime sidecars already contain.
M.DENSE_STRIDE=44
M.DENSE_FORMAT={
  {"VertexPosition","float",3},
  {"VertexTexCoord","float",2},
  {"VertexNormal","float",3},
  {"BreathPosition","float",3},
  {"LookPosition","float",3},
  {"Gesture1Position","float",3},
  {"Gesture2Position","float",3},
  {"Gesture3Position","float",3},
  {"Gesture4Position","float",3},
  {"Gesture5Position","float",3},
  {"Reaction1Position","float",3},
  {"Reaction2Position","float",3},
  {"Reaction3Position","float",3},
  {"Reaction4Position","float",3},
  {"Reaction5Position","float",3},
}

-- Compact layout used only by the CPU fallback path below.
M.COMPACT_STRIDE=20
M.COMPACT_FORMAT={
  {"VertexPosition","float",3},
  {"VertexTexCoord","float",2},
  {"VertexNormal","float",3},
  {"BreathPosition","float",3},
  {"LookPosition","float",3},
  {"ActionAPosition","float",3},
  {"ActionBPosition","float",3},
}

M.POSE_OFFSET={
  breath=9,look=12,
  gesture1=15,gesture2=18,gesture3=21,gesture4=24,gesture5=27,
  reaction1=30,reaction2=33,reaction3=36,reaction4=39,reaction5=42,
}
M.ACTION_KEYS={
  "gesture1","gesture2","gesture3","gesture4","gesture5",
  "reaction1","reaction2","reaction3","reaction4","reaction5",
}
-- Dense attribute name backing each source-pose weight.
M.ATTRIBUTE={
  gesture1="Gesture1Position",gesture2="Gesture2Position",gesture3="Gesture3Position",
  gesture4="Gesture4Position",gesture5="Gesture5Position",
  reaction1="Reaction1Position",reaction2="Reaction2Position",reaction3="Reaction3Position",
  reaction4="Reaction4Position",reaction5="Reaction5Position",
}

-- Seven-attribute vertex program. This is the previously Windows-only shader,
-- which is now the shader for every platform. Its blend math is unchanged:
-- the two active poses are combined by relative weight, then mixed against the
-- bind pose by their total, and idle breath/look remain a secondary layer that
-- fades out while an authored action owns the body.
M.VERTEX=[[
uniform mat4 vp; uniform mat4 model;
uniform float breathMix; uniform float lookMix;
uniform float actionAMix; uniform float actionBMix; uniform float sourcePoseGain;
attribute vec3 VertexNormal;
attribute vec3 BreathPosition;
attribute vec3 LookPosition;
attribute vec3 ActionAPosition;
attribute vec3 ActionBPosition;
varying vec3 worldPos; varying vec3 worldNormal;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  vec3 base=vertex_position.xyz;
  float a=max(actionAMix,0.0)*sourcePoseGain;
  float b=max(actionBMix,0.0)*sourcePoseGain;
  float sum=a+b;
  float action=clamp(sum,0.0,1.0);
  vec3 p=base;
  if (sum>0.0001) {
    vec3 target=(ActionAPosition*a+ActionBPosition*b)/sum;
    p=mix(base,target,action);
  }
  float secondary=1.0-action;
  p+=(BreathPosition-base)*breathMix*secondary;
  p+=(LookPosition-base)*lookMix*secondary;
  vec4 world=model*vec4(p,1.0); worldPos=world.xyz;
  worldNormal=normalize((model*vec4(normalize(VertexNormal),0.0)).xyz);
  return vp*world;
}]]

function M.densePose(row,key)
  local i=M.POSE_OFFSET[key] or 1
  return tonumber(row and row[i]) or tonumber(row and row[1]) or 0,
         tonumber(row and row[i+1]) or tonumber(row and row[2]) or 0,
         tonumber(row and row[i+2]) or tonumber(row and row[3]) or 0
end

function M.staticCompactVertex(x,y,z,u,v,nx,ny,nz)
  nx,ny,nz=nx or 0,ny or 1,nz or 0
  return {x,y,z,u,v,nx,ny,nz,x,y,z,x,y,z,x,y,z,x,y,z}
end

function M.compactVertex(row,keyA,keyB)
  local bx,by,bz=M.densePose(row,nil)
  local brx,bry,brz=M.densePose(row,"breath")
  local lx,ly,lz=M.densePose(row,"look")
  local ax,ay,az=M.densePose(row,keyA)
  local bx2,by2,bz2=M.densePose(row,keyB)
  return {bx,by,bz,tonumber(row[4]) or 0,tonumber(row[5]) or 0,
    tonumber(row[6]) or 0,tonumber(row[7]) or 1,tonumber(row[8]) or 0,
    brx,bry,brz,lx,ly,lz,ax,ay,az,bx2,by2,bz2}
end

-- The two heaviest source-pose weights, highest first. Identical selection to
-- the previous windowsActionPair.
function M.actionPair(motion)
  motion=motion or {}
  local keyA,keyB,wA,wB=nil,nil,0,0
  for _,key in ipairs(M.ACTION_KEYS) do
    local w=math.max(0,tonumber(motion[key]) or 0)
    if w>wA then keyB,wB=keyA,wA;keyA,wA=key,w
    elseif w>wB then keyB,wB=key,w end
  end
  return keyA,wA,keyB,wB
end

-- ---------------------------------------------------------------------------
-- Binding strategy
--
-- Preferred: rebind the dense mesh's own pose attributes into the two shader
-- slots with Mesh:attachAttribute. No extra buffers, no uploads, no cache
-- change -- and the pair only changes about four times across a ~1.5s clip.
--
-- LOVE moved attachAttribute's argument order between 11.2 and 11.3, and some
-- forks omit it entirely, so the exact call is probed once at runtime and the
-- CPU rewrite below is kept as a fallback.
-- ---------------------------------------------------------------------------
local attachStyle=nil   -- "step4" | "name3" | false
local probed=false

local function probeAttach()
  if probed then return attachStyle end
  probed=true;attachStyle=false
  if not (love and love.graphics and type(love.graphics.newMesh)=="function") then return attachStyle end
  local ok,m=pcall(love.graphics.newMesh,M.DENSE_FORMAT,3,"triangles","static")
  if not ok or not m or type(m.attachAttribute)~="function" then return attachStyle end
  -- 11.3+: (name, mesh, step, attachname)
  if pcall(m.attachAttribute,m,"Gesture1Position",m,"pervertex","ActionAPosition") then attachStyle="step4"
  -- 11.2: (name, mesh, attachname)
  elseif pcall(m.attachAttribute,m,"Gesture1Position",m,"ActionAPosition") then attachStyle="name3" end
  pcall(function() if m.release then m:release() end end)
  return attachStyle
end

-- "attached" keeps the dense mesh and rebinds; "dynamic" rewrites compact
-- vertex rows on the CPU when the active pair changes.
function M.mode()
  return probeAttach() and "attached" or "dynamic"
end
function M.attachStyle() return probeAttach() end
function M.dense() return M.mode()=="attached" end

local function attachOne(mesh,sourceAttr,slot)
  if attachStyle=="step4" then
    return pcall(mesh.attachAttribute,mesh,sourceAttr,mesh,"pervertex",slot)
  end
  return pcall(mesh.attachAttribute,mesh,sourceAttr,mesh,slot)
end

M.rebinds=0
M.rewrites=0

-- Point the two shader slots at the currently active source poses. Call once
-- per frame before drawing a trainer's groups; it is a no-op unless the active
-- pair actually changed.
function M.bindPair(groups,motion)
  local keyA,_,keyB=M.actionPair(motion)
  local pair=tostring(keyA or "base").."|"..tostring(keyB or "base")
  local dense=M.dense()
  for _,grp in ipairs(groups or {}) do
    if grp.mesh and grp.posePair~=pair then
      if dense then
        -- With no action active both mixes are zero, so the bind pose is a
        -- correct and cheap thing to leave bound.
        local a=M.ATTRIBUTE[keyA] or "VertexPosition"
        local b=M.ATTRIBUTE[keyB] or "VertexPosition"
        local okA=attachOne(grp.mesh,a,"ActionAPosition")
        local okB=attachOne(grp.mesh,b,"ActionBPosition")
        if okA and okB then grp.posePair=pair;M.rebinds=M.rebinds+1 end
      else
        local source=grp.poseSourceRows
        if type(source)=="table" then
          local rows={}
          for i,row in ipairs(source) do rows[i]=M.compactVertex(row,keyA,keyB) end
          if pcall(grp.mesh.setVertices,grp.mesh,rows) then
            grp.posePair=pair;M.rewrites=M.rewrites+1
          end
        end
      end
    end
  end
end

-- Send the seven-attribute shader's morph uniforms.
function M.sendMixes(shader,motion)
  motion=motion or {}
  local _,wA,_,wB=M.actionPair(motion)
  shader:send("breathMix",motion.breath or 0)
  shader:send("lookMix",motion.look or 0)
  shader:send("actionAMix",wA or 0)
  shader:send("actionBMix",wB or 0)
  shader:send("sourcePoseGain",1)
end

function M.status()
  return {version=1,mode=M.mode(),attachStyle=probeAttach() or "unavailable",
    shaderAttributes=7,previousAttributes={nonWindows=15,windows=7},
    sourcePoses=10,rebinds=M.rebinds,rewrites=M.rewrites,
    denseStride=M.DENSE_STRIDE,unifiedAcrossPlatforms=true}
end

return M
