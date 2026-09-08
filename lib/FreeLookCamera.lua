-- User composition layered on the LIVE cinematic pose, never director ownership.
-- No engine input mutation; touch/mouse gestures start only in the arena region.
local V=...;local F={version=2,state={}}
local function clamp(x,a,b)return math.max(a,math.min(b,x))end
local function atan2(y,x)
 if math.atan2 then return math.atan2(y,x) end
 if x>0 then return math.atan(y/x) end
 if x<0 then return math.atan(y/x)+(y>=0 and math.pi or -math.pi) end
 return y>0 and math.pi/2 or (y<0 and -math.pi/2 or 0)
end
local function doubles(ctx)
 local d=V.DoublesRuntime;local f=d and (d.presentation or d.combat)
 return type(f)=='function' and f(ctx and ctx.battle) or nil
end
function F.allowed(ctx)
 local battle=ctx and ctx.battle;local d=doubles(ctx)
 local screen=d and d.screen or (battle and (battle._view or battle))
 local game=ctx and (ctx.game or (screen and screen.game))
 if not screen or not game then return false end
 local p=game.save and game.save.colosseumBattle
 if p and p.freeLookEnabled==false then return false end
 if game.stack and game.stack.top then
  local top=game.stack:top()
  if top~=screen and top~=battle then return false end
 end
 if d then
  if d.progressing then return false end
  local phase=d.core.phase
  if phase~='command' and phase~='replace' and phase~='present' and phase~='resolving' then return false end
  if phase=='command' or phase=='replace' then
   local ui=d.consumer and d.consumer.states and d.consumer.states[d.core.id]
   if ui and ui.page~='commands' and ui.page~='moves' and ui.page~='targets' then return false end
  end
  return true
 end
 return screen.phase=='menu' or screen.phase=='moves'
end

local function inside(x,y,w,h)return x and y and x>w*.12 and x<w*.88 and y>h*.16 and y<h*.68 end
local function down(key)return love and love.keyboard and love.keyboard.isDown and love.keyboard.isDown(key) end
function F.reset() F.state={} end
local function contextState(ctx)
 local s=F.state
 if s.context~=ctx then F.reset();s=F.state;s.context=ctx end
 s.yawOffset=s.yawOffset or 0;s.pitchOffset=s.pitchOffset or 0
 s.zoomLog=s.zoomLog or 0;s.panX=s.panX or 0;s.panY=s.panY or 0
 return s
end
local function dolly(s,amount)
 s.zoomLog=clamp(s.zoomLog+amount,math.log(.60),math.log(1.65));s.active=true
end
-- Pure pose composition: even with no fresh input, a changed cinematic base
-- yields a changed result. Never mutate base or adopt the result into a director.
function F.compose(base,s)
 if not (base and base.eye and base.focus) then return nil end
 local dx,dy,dz=base.eye[1]-base.focus[1],base.eye[2]-base.focus[2],base.eye[3]-base.focus[3]
 local radius=math.max(.001,math.sqrt(dx*dx+dy*dy+dz*dz))
 local yaw=atan2(dx,dz)+(s.yawOffset or 0)
 local pitch=clamp(atan2(dy,math.sqrt(dx*dx+dz*dz))+(s.pitchOffset or 0),math.rad(-18),math.rad(65))
 local range=radius*math.exp(s.zoomLog or 0)
 local panX,panY=s.panX or 0,s.panY or 0
 local focus={base.focus[1]+math.cos(yaw)*panX,base.focus[2]+panY,base.focus[3]-math.sin(yaw)*panX}
 local r=range*math.cos(pitch)
 return {eye={focus[1]+math.sin(yaw)*r,focus[2]+range*math.sin(pitch),focus[3]+math.cos(yaw)*r},
   focus=focus,fov=base.fov,curve=base.curve or 0}
end
function F.wheel(game,dx,dy)
 local s=F.state;local ctx=s.context
 if not ctx or not F.allowed(ctx) or not s.base then return false end
 local owner=ctx.game or (ctx.battle and ctx.battle.game)
 if owner~=game then return false end
 if not (love and love.mouse and love.graphics) then return false end
 local x,y=love.mouse.getPosition();local w,h=love.graphics.getDimensions()
 if not inside(x,y,w,h) or (tonumber(dy) or 0)==0 then return false end
 dolly(s,-clamp(tonumber(dy) or 0,-8,8)*.12)
 return true
end
function F.pose(ctx,base)
 if not (love and love.graphics and base and base.eye and base.focus) then return nil end
 local s=contextState(ctx);s.base=base
 if down('home') then F.reset();return nil end
 local allowed=F.allowed(ctx)
 if not allowed then
  local d=doubles(ctx);local game=ctx and (ctx.game or (ctx.battle and ctx.battle.game))
  local prefs=game and game.save and game.save.colosseumBattle
  if not d or (prefs and prefs.freeLookEnabled==false) then F.reset();return nil end
  -- Overlay ownership blocks sampling, not the underlying automatic shots.
  s.mode=nil;s.drag=nil;s.pinch=nil
 else
  local w,h=love.graphics.getDimensions()
  local x,y,mode,pinch,bothInside
  local touch=love.touch;local ids=touch and touch.getTouches and touch.getTouches() or {}
  if #ids==1 then
   x,y=touch.getPosition(ids[1]);mode='orbit-touch:'..tostring(ids[1])
  elseif #ids==2 then
   local ax,ay=touch.getPosition(ids[1]);local bx,by=touch.getPosition(ids[2])
   x,y=(ax+bx)*.5,(ay+by)*.5;pinch=math.sqrt((ax-bx)^2+(ay-by)^2)
   local a,b=tostring(ids[1]),tostring(ids[2]);if b<a then a,b=b,a end
   mode='two-touch:'..a..':'..b;bothInside=inside(ax,ay,w,h) and inside(bx,by,w,h)
  elseif #ids==0 and love.mouse then
   x,y=love.mouse.getPosition()
   if love.mouse.isDown(2) then mode=(down('lshift') or down('rshift')) and 'dolly' or 'orbit'
   elseif love.mouse.isDown(3) then mode='pan' end
  end
  if mode then
   if s.mode~=mode then
    s.mode=mode;s.drag=inside(x,y,w,h) and bothInside~=false;s.x=x;s.y=y;s.pinch=pinch
   elseif s.drag then
    local dx,dy=x-s.x,y-s.y;s.x=x;s.y=y
    local changed=math.abs(dx)+math.abs(dy)>.01
    local vx,vy,vz=base.eye[1]-base.focus[1],base.eye[2]-base.focus[2],base.eye[3]-base.focus[3]
    local radius=math.sqrt(vx*vx+vy*vy+vz*vz)*math.exp(s.zoomLog)
    if pinch and s.pinch then
     if pinch>1 and s.pinch>1 and math.abs(pinch-s.pinch)>.01 then dolly(s,math.log(s.pinch/pinch)) end
     if changed then
      s.panX=clamp(s.panX-dx*radius/math.max(w,h),-16,16)
      s.panY=clamp(s.panY-dy*radius/math.max(w,h),-12,20);s.active=true
     end
    elseif changed and mode=='pan' then
     s.panX=clamp(s.panX-dx*radius/math.max(w,h),-16,16)
     s.panY=clamp(s.panY-dy*radius/math.max(w,h),-12,20);s.active=true
    elseif changed and mode=='dolly' then dolly(s,dy/h*2.4)
    elseif changed then
     s.yawOffset=(s.yawOffset-dx/w*5+math.pi)%(2*math.pi)-math.pi
     s.pitchOffset=clamp(s.pitchOffset-dy/h*3,math.rad(-50),math.rad(60));s.active=true
    end
    s.pinch=pinch
   end
  else s.mode=nil;s.drag=nil;s.pinch=nil end
 end
 if not s.active then return nil end
 local pose=F.compose(base,s)
 if V.Camera and V.Camera.guardFreePose then pose=V.Camera:guardFreePose(pose,ctx.arena)
 elseif V.Camera and V.Camera.guardPose then pose=V.Camera:guardPose(pose,ctx.arena,'passive') end
 s.pose=pose
 return pose
end
-- Chain the engine's map-zoom entry points only when a live battle gesture owns
-- the wheel. Other menus, overworld zoom and either generation retain originals.
function F.install()
 local installed=0
 for _,name in ipairs({'src.core.Game','src.core.Game2'}) do
  local ok,game=pcall(require,name)
  if ok and type(game)=='table' and type(game.wheelmoved)=='function' then
   local inner=game.wheelmoved
   if game.__cbeWheelWrapper~=inner then
    local wrapper=function(self,x,y,...)
     if F.wheel(self,x,y) then return true end
     return inner(self,x,y,...)
    end
    game.__cbeWheelWrapper=wrapper;game.wheelmoved=wrapper;installed=installed+1
   end
  end
 end
 return installed
end
return F
