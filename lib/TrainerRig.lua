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

return R
