-- Relic Chamber foreground-presentation guard.
--
-- M3_shrine_1F_bf is a real retail battle scene, but its original camera rails
-- never put the lens through the large foliage/root carrier cards around the
-- shrine clearing. CBE's free battle camera can. The rule here is intentionally
-- strict: authentic perimeter foliage remains, but NO source card/branch/overhang
-- is allowed to sit between the camera and the protected battle frame.
local R={}

local function finite(v)
  return type(v)=="number" and v==v and v~=math.huge and v~=-math.huge
end
local function clamp(v,a,b)
  if v<a then return a elseif v>b then return b end return v
end
local function norm3(x,y,z)
  local l=math.sqrt(x*x+y*y+z*z)
  if l<1e-6 then return nil end
  return x/l,y/l,z/l,l
end
local function worldPoint(x,y,z,scale,yaw)
  x,y,z=x*scale,y*scale,z*scale
  if yaw~=0 then
    local cs,sn=math.cos(yaw),math.sin(yaw)
    x,z=cs*x+sn*z,-sn*x+cs*z
  end
  return x,y,z
end
local function worldCenter(g,scale,yaw)
  local c=g.center or {0,0,0}
  return worldPoint(tonumber(c[1]) or 0,tonumber(c[2]) or 0,tonumber(c[3]) or 0,scale,yaw)
end

-- View-adaptive final safety net. ArenaBuilder now rejects the giant battle-core
-- overhead sheets at extraction time; this catches smaller/irregular leaf and
-- branch cards that are legitimate perimeter scenery but become foreground junk
-- from one particular CBE camera angle.
function R.shouldCull(g,pose,scale,yaw,aspect)
  if not (g and pose and pose.eye and pose.focus and pose.fov and g.center and g.extent) then return false end
  scale=tonumber(scale) or .25;yaw=tonumber(yaw) or 0;aspect=clamp(tonumber(aspect) or 16/9,1.0,2.5)

  local e=g.extent
  local sx=math.abs((tonumber(e[1]) or 0)*scale)
  local sy=math.abs((tonumber(e[2]) or 0)*scale)
  local sz=math.abs((tonumber(e[3]) or 0)*scale)
  local longest=math.max(sx,sy,sz)
  if longest<2.0 then return false end
  local shortest=math.max(.12,math.min(sx>0 and sx or longest,sy>0 and sy or longest,sz>0 and sz or longest))
  local cx,cy,cz=worldCenter(g,scale,yaw)
  local mode=tonumber(g.mode) or 0
  local sourceCutout=(mode>2.5 and mode<3.5)
  local maxXZ=math.max(sx,sz)
  local broadHorizontal=sx>7 and sz>7 and sy<math.max(7.0,maxXZ*.48)
  local elongated=(longest/shortest)>2.1 and longest>7
  local opaqueCarrier=(mode<.5 and elongated and sy<8.5)
  local elevated=(cy+sy*.5)>3.2
  local overheadArtifact=(mode<.5 and elevated and sx>12 and sz>12 and maxXZ>22 and sy<math.max(11.0,maxXZ*.52) and longest>24)
  if not elevated or not (sourceCutout or broadHorizontal or opaqueCarrier or overheadArtifact) then return false end

  local ex,ey,ez=tonumber(pose.eye[1]) or 0,tonumber(pose.eye[2]) or 0,tonumber(pose.eye[3]) or 0
  local tx,ty,tz=tonumber(pose.focus[1]) or 0,tonumber(pose.focus[2]) or 0,tonumber(pose.focus[3]) or 0
  local fx,fy,fz,focusDepth=norm3(tx-ex,ty-ey,tz-ez)
  if not fx then return false end
  local rx,rz=-fz,fx
  local rl=math.sqrt(rx*rx+rz*rz);if rl<1e-6 then return false end
  rx,rz=rx/rl,rz/rl
  local ux,uy,uz=-rz*fy,rz*fx-rx*fz,rx*fy
  local tanHalf=math.tan(clamp(tonumber(pose.fov) or math.rad(40),math.rad(24),math.rad(70))*.5)
  if tanHalf<1e-5 then return false end

  local rawC=g.center;local rawE=g.extent
  local rcx,rcy,rcz=tonumber(rawC[1]) or 0,tonumber(rawC[2]) or 0,tonumber(rawC[3]) or 0
  local hx,hy,hz=(tonumber(rawE[1]) or 0)*.5,(tonumber(rawE[2]) or 0)*.5,(tonumber(rawE[3]) or 0)*.5
  local minx,maxx,miny,maxy=math.huge,-math.huge,math.huge,-math.huge
  local minDepth,maxDepth=math.huge,-math.huge
  local projected=0
  for _,dx in ipairs({-hx,hx}) do
    for _,dy in ipairs({-hy,hy}) do
      for _,dz in ipairs({-hz,hz}) do
        local wx,wy,wz=worldPoint(rcx+dx,rcy+dy,rcz+dz,scale,yaw)
        local qx,qy,qz=wx-ex,wy-ey,wz-ez
        local depth=qx*fx+qy*fy+qz*fz
        minDepth=math.min(minDepth,depth);maxDepth=math.max(maxDepth,depth)
        if depth>.15 then
          local px=(qx*rx+qz*rz)/(depth*tanHalf*aspect)
          local py=(qx*ux+qy*uy+qz*uz)/(depth*tanHalf)
          if finite(px) and finite(py) then
            minx=math.min(minx,px);maxx=math.max(maxx,px)
            miny=math.min(miny,py);maxy=math.max(maxy,py)
            projected=projected+1
          end
        end
      end
    end
  end
  if projected==0 or maxDepth<.18 then return false end

  -- Geometry completely beyond the battlers is genuine backdrop and stays.
  -- Everything else is judged by how much of the readable battle window it
  -- covers, not by the object's centre ray.
  if minDepth>focusDepth*1.04 and not overheadArtifact then return false end
  local vx0,vx1=math.max(-1,minx),math.min(1,maxx)
  local vy0,vy1=math.max(-1,miny),math.min(1,maxy)
  if vx1<=vx0 or vy1<=vy0 then return false end
  local visibleArea=(vx1-vx0)*(vy1-vy0)/4
  local px0,px1=-.99,.99
  local py0,py1=-.92,.94
  local ox=math.max(0,math.min(vx1,px1)-math.max(vx0,px0))
  local oy=math.max(0,math.min(vy1,py1)-math.max(vy0,py0))
  local cover=(ox*oy)/math.max(.001,(px1-px0)*(py1-py0))
  local inFront=minDepth<focusDepth*.96

  -- Hard rule: no leaf/branch card in front of the fight. Even a relatively
  -- small one is distracting when it crosses a Pokemon or HUD-adjacent view.
  if sourceCutout and inFront and visibleArea>.008 and ox>.12 and oy>.10 then return true end
  if overheadArtifact and visibleArea>.015 and miny<.72 and maxy>-.98 then return true end
  if broadHorizontal and inFront and (cover>.018 or (visibleArea>.035 and ox>.24)) then return true end
  if opaqueCarrier and inFront and cover>.025 then return true end

  -- Very near geometry gets one final conservative test; this is what prevents
  -- branch tips from flashing through during camera interpolation between shots.
  local centerDist=math.sqrt((cx-ex)^2+(cy-ey)^2+(cz-ez)^2)
  if centerDist<24 and inFront and visibleArea>.010 and (sourceCutout or elongated) then return true end
  return false
end

return R
