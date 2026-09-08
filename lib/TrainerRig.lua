local R={version=16}

-- Source-authored trainer landmarks retained by the release renderer.
-- Procedural skeletal deformation was retired before 1.0.0; these measurements
-- are used only to place trainer-thrown Poké Balls against each model's real scale.
local PROFILES={
  red={shoulder=0.763,halfWidth=0.95,shoulderRadius=0.191},
  leaf={shoulder=0.744,halfWidth=0.92,shoulderRadius=0.188},
  wes={shoulder=0.732,halfWidth=0.82,shoulderRadius=0.208},
  brendan={shoulder=0.740,halfWidth=0.92,shoulderRadius=0.176},
  may={shoulder=0.770,halfWidth=0.92,shoulderRadius=0.168},
  cooltrainer_m={shoulder=0.747,halfWidth=0.86,shoulderRadius=0.193},
  cooltrainer_f={shoulder=0.766,halfWidth=0.90,shoulderRadius=0.188},
  dakim={shoulder=0.650,halfWidth=0.78,shoulderRadius=0.337},
  nascour={shoulder=0.728,halfWidth=0.74,shoulderRadius=0.261},
  miror_b={shoulder=0.633,halfWidth=0.76,shoulderRadius=0.174},
}

function R.profile(name,bounds)
  local p=PROFILES[tostring(name or ""):lower()] or PROFILES.dakim
  local min=bounds and bounds.min or nil
  local max=bounds and bounds.max or nil
  local center=bounds and bounds.center or nil
  local minY=min and tonumber(min[2]) or 0
  local maxY=max and tonumber(max[2]) or 20
  local minX=min and tonumber(min[1]) or -5
  local maxX=max and tonumber(max[1]) or 5
  local centerX=center and tonumber(center[1]) or ((minX+maxX)*.5)
  local centerZ=center and tonumber(center[3]) or 0
  local halfWidth=math.max(math.abs(minX-centerX),math.abs(maxX-centerX))*p.halfWidth
  return {
    minY=minY,height=math.max(.01,maxY-minY),halfWidth=halfWidth,
    centerX=centerX,centerZ=centerZ,shoulder=p.shoulder,shoulderRadius=p.shoulderRadius,
  }
end

function R.status()
  return {
    version=16,mode="native-hsd-landmark-metadata",proceduralDeformation=false,
    purpose="trainer throw/release anchoring",
    profiles={"red","leaf","wes","brendan","may","cooltrainer_m","cooltrainer_f","dakim","nascour","miror_b"},
  }
end

local function clamp(v,a,b) return math.max(a,math.min(b,v)) end

function R.mixJointPoint(base,poses,index,motion)
  local p=base and base[index];if type(p)~="table" then return nil end
  motion=motion or {}
  local x,y,z=tonumber(p[1]) or 0,tonumber(p[2]) or 0,tonumber(p[3]) or 0
  local weights={}
  local sum=0
  for i=1,5 do
    local gw=math.max(tonumber(motion["gesture"..i]) or 0,0)
    local rw=math.max(tonumber(motion["reaction"..i]) or 0,0)
    weights[#weights+1]={"gesture"..i,gw};sum=sum+gw
    weights[#weights+1]={"reaction"..i,rw};sum=sum+rw
  end
  local action=clamp(sum,0,1)
  if sum>.0001 then
    local tx,ty,tz,tw=0,0,0,0
    for _,row in ipairs(weights) do
      local name,w=row[1],row[2]
      local q=poses and poses[name] and poses[name][index]
      if q and w>0 then
        tx=tx+(tonumber(q[1]) or x)*w
        ty=ty+(tonumber(q[2]) or y)*w
        tz=tz+(tonumber(q[3]) or z)*w
        tw=tw+w
      end
    end
    if tw>.0001 then
      x=x+(tx/tw-x)*action;y=y+(ty/tw-y)*action;z=z+(tz/tw-z)*action
    end
  else
    -- Old-cache compatibility during a failed/partial rebuild.
    local legacy={{"arm",motion.arm},{"shift",motion.shift},{"settle",motion.settle},{"command",motion.command},{"brace",motion.brace}}
    local tx,ty,tz,tw=0,0,0,0
    for _,row in ipairs(legacy) do
      local q=poses and poses[row[1]] and poses[row[1]][index];local w=math.max(tonumber(row[2]) or 0,0)
      if q and w>0 then tx=tx+(tonumber(q[1]) or x)*w;ty=ty+(tonumber(q[2]) or y)*w;tz=tz+(tonumber(q[3]) or z)*w;tw=tw+w end
    end
    if tw>.0001 then
      action=clamp(tw,0,1);x=x+(tx/tw-x)*action;y=y+(ty/tw-y)*action;z=z+(tz/tw-z)*action
    end
  end
  local secondary=1-action
  local function secondaryPose(name,w)
    local q=poses and poses[name] and poses[name][index]
    if q and w~=0 then
      x=x+((tonumber(q[1]) or x)-(tonumber(p[1]) or x))*w*secondary
      y=y+((tonumber(q[2]) or y)-(tonumber(p[2]) or y))*w*secondary
      z=z+((tonumber(q[3]) or z)-(tonumber(p[3]) or z))*w*secondary
    end
  end
  secondaryPose("breath",tonumber(motion.breath) or 0)
  secondaryPose("look",tonumber(motion.look) or 0)
  return {x,y,z}
end

return R
