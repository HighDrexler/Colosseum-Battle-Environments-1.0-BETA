-- Four-battler cinematography. Read-only: no battle input, targets or rules are
-- changed. All poses use STAGE coordinates and the existing venue safety guard.
local V=...
local C={version=1}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function smooth(x)x=clamp(x,0,1);return x*x*(3-2*x)end
local function mix(a,b,t)return a+(b-a)*t end
local function copy(p)return {eye={p.eye[1],p.eye[2],p.eye[3]},focus={p.focus[1],p.focus[2],p.focus[3]},fov=p.fov or .8,curve=0}end
local function point(s,ctx,id,token)
  if not id then return end
  local x,z=V.DoublesPresenter.anchor(ctx,id);if not x then return end
  local slot=s.core.slots and s.core.slots[id]
  local rec=s.actors and s.actors[token or (slot and slot.battlerId)]
  local a=rec and rec.actor
  local k=(ctx.services or {}).figureScale or (ctx.arena or {}).figureScale or .38
  local h=clamp(a and (a.height or 16)*(a.worldScale or 1)*k or 7,2,26)
  return {x,(ctx.groundY or 0)+h*.52,z},h,rec
end
local function framing(points,height,fov,aspect)
  if #points==0 then return {0,6,0},38 end
  local minx,maxx,minz,maxz=points[1][1],points[1][1],points[1][3],points[1][3]
  local y=0
  for _,p in ipairs(points)do minx=math.min(minx,p[1]);maxx=math.max(maxx,p[1]);minz=math.min(minz,p[3]);maxz=math.max(maxz,p[3]);y=y+p[2] end
  local radius=math.sqrt((maxx-minx)^2+(maxz-minz)^2)*.53+height*.62+2
  return {(minx+maxx)*.5,y/#points,(minz+maxz)*.5},math.max(23,radius/math.tan(fov*.5)/math.min(1.35,aspect))
end
function C.neutral(base)
  local out=copy(base);out.eye[2]=out.eye[2]+3;out.fov=math.min(1.45,out.fov*1.26);return out
end
local function guard(p,ctx)
  return V.Camera and V.Camera.guardPose and V.Camera:guardPose(p,ctx.arena,'passive') or p
end
function C.pose(base,s,ctx)
  if not (s and s.core and ctx and V.DoublesPresenter)then return C.neutral(base)end
  local e=s.core.currentEvent;local m=s.movePresentation
  local clock=tonumber(s.visualClock) or 0
  local state=s.doublesCamera
  -- Render contexts may be reconstructed each draw. The combat core owns this
  -- camera's lifetime; resetting on table identity discards smoothing every frame.
  if not state or state.core~=s.core then state={core=s.core,lastClock=clock};s.doublesCamera=state end
  local size=(ctx.services or {}).renderSize or {};local aspect=(size.width or 1280)/math.max(1,size.height or 720)
  local bx,bz=base.eye[1]-base.focus[1],base.eye[3]-base.focus[3]
  local yaw=math.atan2(bx,bz)
  local phase='command';local pose
  local kind=e and e.kind
  local age=tonumber(s.core.eventTime) or 0
  local points={};local maxH=5
  for _,r in ipairs(s.actorOrder or {})do if r.visible and not r.structuralHidden then
    local p,h=point(s,ctx,r.slot,r.battlerId);if p then points[#points+1]=p;maxH=math.max(maxH,h)end
  end end
  local fov=math.rad(43)
  local focus,range=framing(points,maxH,fov,aspect)
  local elevation=.24+math.sin(clock*.15)*.022
  local variant=((tonumber(e and e.eventId) or tonumber(s.core.turn) or 1)%3)-1
  -- Small anchored arcs between events, not a perpetual orbit through scenery.
  yaw=yaw+math.sin(clock*.18)*.055
  local p,h,r
  -- Lua's and-expression truncates multi-return values. Resolve explicitly.
  if e then p,h,r=point(s,ctx,e.slot,e.battlerId)end
  if e and (e.presentationConsumed or (kind=='move' and not m and state.phase=='impact'
      and state.eventId==e.eventId)) then
    -- Channel completion precedes the controller's following update. Holding
    -- this already-finished impact avoids a one-frame jump back to launch or
    -- transit while the same event is still the controller's current record.
    if state.pose then state.lastClock=clock;return copy(state.pose)end
  elseif p and kind=='send' and not e.alreadyPresented then
    local send=r and r.sendout
    if send and (send.phase or 0)<.79 and V.Camera and V.Camera.sendoutShot then
      local side=e.slot:match('^player') and 'player' or 'enemy'
      pose=V.Camera:sendoutShot(ctx,ctx.arena,side);phase='trainer-throw'
    end
    if not pose then
      phase='sendout-reveal';focus=p;range=math.max(21,h*3.15);fov=math.rad(37.5)
      yaw=yaw+(e.slot:match('^player') and -.30 or .30)+variant*.12;elevation=.12
    end
  elseif p and kind=='recall' then
    phase='recall';focus=p;range=math.max(24,h*3.35);fov=math.rad(39)
    yaw=yaw+(e.slot:match('^player') and -.38 or .38);elevation=.22
  elseif p and kind=='faint' then
    phase='faint';focus={p[1],(ctx.groundY or 0)+h*.32,p[3]};range=math.max(22,h*3.0)
    yaw=yaw+(e.slot:match('^player') and .36 or -.36)+smooth(age/2)*.12;elevation=.14;fov=math.rad(36.5)
  elseif p and kind=='move' then
    local targetPoints={};local mh=h
    for _,id in ipairs(e.targets or {})do
      if id~=e.slot then local t,th=point(s,ctx,id,(e.targetBattlers or {})[id]);if t then targetPoints[#targetPoints+1]=t;mh=math.max(mh,th)end end
    end
    local all={p};for _,t in ipairs(targetPoints)do all[#all+1]=t end
    local centre,wide=framing(all,mh,math.rad(41),aspect)
    local elapsed=m and (m.chapterAge or 0) or age
    local launchEnd=m and m.impactTime and math.min(.65,m.impactTime*.60) or .48
    local transit=smooth((elapsed-launchEnd)/.40)
    if #targetPoints>1 then transit=1 end
    phase=transit<.2 and 'launch' or 'transit'
    focus={mix(p[1],centre[1],transit),mix(p[2],centre[2],transit),mix(p[3],centre[3],transit)}
    range=mix(math.max(23,h*3.1),wide,transit);fov=math.rad(41);elevation=.19
    local handed=e.slot:match('^player') and -1 or 1
    yaw=yaw+handed*(.35+variant*.11)+transit*handed*.17
    elevation=elevation+smooth(transit)*.045+variant*.016
    if m and m.impactStarted and #targetPoints>0 then
      local impact=m.impactAge or 0
      -- Preserve travel readability as the composition moves towards impact;
      -- do not recut once per receiving-HP notification.
      local t=smooth(impact/.48)
      local receive,rr=framing(targetPoints,mh,math.rad(38.5),aspect)
      focus={mix(focus[1],receive[1],t),mix(focus[2],receive[2],t),mix(focus[3],receive[3],t)}
      range=mix(range,math.max(rr,mh*3.2),t);yaw=yaw-handed*.32*t
      fov=mix(fov,math.rad(38.5),t);elevation=mix(elevation,.16+variant*.015,t);phase='impact'
    end
  elseif p and (kind=='damage' or kind=='reaction' or kind=='heal' or kind=='status')then
    phase=kind;focus=p;range=math.max(23,h*3.2);fov=math.rad(38)
    yaw=yaw+(e.slot:match('^player') and .27 or -.27)+variant*.10;elevation=.22
  end
  if not pose then
    pose={focus=focus,eye={focus[1]+math.sin(yaw)*range,focus[2]+math.max(3,range*elevation),focus[3]+math.cos(yaw)*range},fov=fov,curve=0}
    pose=guard(pose,ctx)
  end
  local dt=clamp(clock-(state.lastClock or clock),0,.1);state.lastClock=clock
  if state.pose then
    -- At most one interpolation step per presentation update, independent of
    -- render count, refresh rate, game speed or repeated world draw requests.
    local a=1-math.exp(-dt*(phase=='command' and 4.5 or 8.0))
    for i=1,3 do state.pose.eye[i]=mix(state.pose.eye[i],pose.eye[i],a);state.pose.focus[i]=mix(state.pose.focus[i],pose.focus[i],a)end
    state.pose.fov=mix(state.pose.fov,pose.fov,a)
    state.pose=guard(state.pose,ctx)
  else state.pose=copy(pose)end
  state.phase=phase;state.eventId=e and e.eventId;state.target=pose
  return copy(state.pose)
end
function C.adopt(s,pose)
  if s and s.doublesCamera and pose then s.doublesCamera.pose=copy(pose) end
end
function C.status(s)
  local c=s and s.doublesCamera
  return {active=c~=nil,shot=c and c.phase,eventId=c and c.eventId,clock=c and c.lastClock}
end
return C
