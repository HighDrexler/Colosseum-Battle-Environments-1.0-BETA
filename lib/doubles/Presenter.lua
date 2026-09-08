-- Four independently animated handles backed by CBE's existing shared caches.
-- Source move chapters bind exact slot pairs without duplicating geometry caches.
local V=...
local P={}
local function call(actor,method,...)
  if actor and type(actor[method])=='function' then return pcall(actor[method],actor,...) end
end
function P.begin(s)
  s.actors={};s.actorOrder={};s.visualClock=0;s.openingThrown={}
  s.context=s.context or (V.StandaloneHost and V.StandaloneHost.session and V.StandaloneHost.session.context)
  local old=V.CurrentSpriteModels
  -- Transfer the two already-resident opening handles instead of rebuilding.
  for _,side in ipairs({'player','enemy'}) do
    local slot=s.core.slots[side..'-left'];local rec=old.stadiumActors and old.stadiumActors[side]
    if old.modeId=="cbe:colosseum-pokemon" and rec and rec.actor and slot.mon then
      local r={actor=rec.actor,slot=slot.id,battlerId=slot.battlerId,mon=slot.mon,battler=slot.battler,visible=not s.groupedOpening,transferred=not s.groupedOpening}
      if s.groupedOpening then call(r.actor,'spawn',0) end
      s.actors[slot.battlerId]=r;s.actorOrder[#s.actorOrder+1]=r;old.stadiumActors[side]=nil
    end
  end
  if s.groupedOpening then
    for _,e in ipairs(s.core.queue)do if e.kind=='send' and e.opening then
      local side=e.slot:match('^player') and 'player' or 'enemy';local names={}
      for _,lane in ipairs({'left','right'})do local slot=s.core.slots[side..'-'..lane];if slot.mon then names[#names+1]=s.adapter:name(slot.mon) end end
      e.text=(side=='player' and 'Go! ' or 'Opponent sent out ')..table.concat(names,' and ')..'!'
    end end
  end
end
function P.event(s,e)
  if e.kind=='send' then
    local r=s.actors[e.battlerId]
    if not r then
      r={slot=e.slot,battlerId=e.battlerId,mon=e.mon,battler=e.battler}
      s.actors[e.battlerId]=r;s.actorOrder[#s.actorOrder+1]=r
    end
    -- Fast text advancement must never overlap two occupants in one position.
    for _,old in ipairs(s.actorOrder) do
      if old~=r and old.slot==e.slot and old.visible then
        old.visible=false;call(old.actor,'release');old.actor=nil
      end
    end
    r.visible=true;r.retireAt=nil;r.structuralHidden=nil
    if r.transferred then
      r.transferred=nil;r.spawnAge=nil;e.alreadyPresented=true
      local side=e.slot:match('^player') and 'player' or 'enemy';s.openingThrown=s.openingThrown or {};s.openingThrown[side]=true
    else
      r.spawnAge=0;r.spawnProgress=0;call(r.actor,'spawn',0)
      local side=e.slot:match('^player') and 'player' or 'enemy';s.openingThrown=s.openingThrown or {}
      local releaseOnly=e.opening and s.openingThrown[side]==true
      if e.opening then s.openingThrown[side]=true end
      r.sendout={event=e,phase=releaseOnly and 1 or 0,elapsed=0,releaseOnly=releaseOnly};e.presentationPending=true
      e.duration=4.1
    end
  else
    local r=s.actors[e.battlerId]
    if not r then return end
    if e.kind=='visibility' then
      r.structuralHidden=e.hidden==true
    elseif e.kind=='move' then
      if V.DoublesMovePresentation then V.DoublesMovePresentation.begin(s,e) else call(r.actor,'attack',e.move,e.moveDef,{}) end
    elseif e.kind=='damage' or e.kind=='reaction' then
      if V.DoublesMovePresentation then V.DoublesMovePresentation.begin(s,e) else call(r.actor,'hit',{damage=e.amount,target={mon={hp=e.hp},hp=e.hp}},{}) end
    elseif e.kind=='faint' or e.kind=='recall' then
      r.structuralHidden=nil
      call(r.actor,e.kind,e.kind=='faint' and 'collapse' or 'switch')
      r.terminal={event=e,kind=e.kind,age=0};r.retireAt=nil;e.presentationPending=true
    end
  end
end
local function tryAcquire(s,r)
  if r.actor or not r.mon or not s.context then return false end
  if r.attempted and (not r.retryAt or (s.visualClock or 0)<r.retryAt) then return false end
  r.attempted=true
  local api=V.PokemonActors.service
  local selected=not V.BattleSettings or V.BattleSettings.pokemonModelsEnabled(s.screen.game)~=false
  if not selected then r.spriteMode=true;return true end
  local def=s.screen.game.data.pokemon[r.mon.species]
  local dex=tonumber(def and (def.dex or def.index or def.number) or r.mon.dex)
  if V.ModelIdentity then dex=V.ModelIdentity.resolve(s.screen.game,r.mon) end
  if not dex then
    r.error='No National Dex mapping'
    if V.BattleCache then V.BattleCache.noteRenderError(s.screen.game,r.error) end
    return true
  end
  local slot=s.core.slots[r.slot]
  local opts={side=slot.side,context=s.context,battler=r.battler,doublesPosition=r.slot,doublesBattlerId=r.battlerId}
  local ok,actor,why=pcall(api.acquireCached,'selected',dex,(V.ShinySupport and V.ShinySupport.variant(r.mon)) or (r.mon.shiny and 'shiny' or 'normal'),opts)
  if not ok or not actor then ok,actor,why=pcall(api.acquire,'selected',dex,(V.ShinySupport and V.ShinySupport.variant(r.mon)) or (r.mon.shiny and 'shiny' or 'normal'),opts) end
  if ok and actor then
    r.actor=actor;r.spriteMode=nil;r.retryAt=nil;r.error=nil;call(actor,'spawn',r.spawnProgress or 1);call(actor,'idle')
  else
    r.error=tostring(ok and why or actor)
    r.spriteMode=nil;r.retryAt=(s.visualClock or 0)+0.1
    if V.BattleCache then V.BattleCache.noteRenderError(s.screen.game,r.error) end
    -- The selected Colosseum source owns this position even on an error.
    -- The readiness screen reports the error; no sprite provider is permitted.
  end
  return true
end
function P.update(s,dt)
  dt=math.max(0,math.min(.1,tonumber(dt) or 0));s.visualClock=(s.visualClock or 0)+dt
  for i=#(s.actorOrder or {}),1,-1 do
    local r=s.actorOrder[i]
    if r.visible==false and not r.actor then s.actors[r.battlerId]=nil;table.remove(s.actorOrder,i) end
  end
  local acquired=false
  for _,r in ipairs(s.actorOrder or {}) do
    if r.visible then
      if not acquired then acquired=tryAcquire(s,r) end
      local send=r.sendout
      if send then
        send.elapsed=send.elapsed+dt
        if not send.started and s.context then
          local side=r.slot:match('^player') and 'player' or 'enemy'
          local trainer=side=='player' and V.PlayerTrainer or V.Trainer
          local x,z,dx,dz=P.anchor(s.context,r.slot)
          if x then
            local ok,duration
            if not send.releaseOnly then ok,duration=call(trainer,'beginSendout',{x,(s.context.groundY or 0)+3.85,z},{dx,dz}) end
            send.trainer=ok and duration and trainer or nil
            send.duration=tonumber(duration) or 1.48;send.started=true;send.elapsed=0
            send.event.duration=(send.releaseOnly and 0 or send.duration)+2.65
          end
        end
        local ok,status=call(send.trainer,'sendoutStatus')
        if send.releaseOnly then send.phase=1
        elseif ok and status and status.active then send.phase=math.max(send.phase,status.phase or 0)
        elseif send.trainer then
          -- A disappeared action has completed or was cancelled; never rewind it.
          send.phase=1
        else send.phase=math.min(1,send.elapsed/(send.duration or 1.48)) end
        if send.phase>=.79 then
          if not send.releaseStarted then
            send.releaseStarted=true;send.releaseAge=0
            if V.ReleasePresentation then V.ReleasePresentation.begin(s,r) end
          end
          send.releaseAge=send.releaseAge+dt
          -- Source ball_open: opening model ends at frame 30, energy holds
          -- another 20 frames before the owner is revealed.
          r.spawnProgress=math.max(0,math.min(1,(send.releaseAge-50/60)/.32))
          if V.ReleasePresentation then V.ReleasePresentation.update(s,r,dt) end
        end
        if (send.phase>=1 and (send.releaseAge or 0)>=2.65) or send.elapsed>math.max(12,(send.duration or 1.48)*5) then
          r.spawnProgress=1;r.spawnAge=nil;send.event.presentationPending=nil
          call(send.trainer,'clearSendoutTarget');r.sendout=nil
        end
      end
      if r.actor then
        if r.spawnProgress~=nil then call(r.actor,'spawn',r.spawnProgress)
        elseif r.spawnAge and r.spawnAge<.6 then r.spawnAge=r.spawnAge+dt;call(r.actor,'spawn',math.min(1,r.spawnAge/.6)) end
        call(r.actor,'update',dt)
      end
      if r.spawnProgress==1 and not r.sendout then r.spawnProgress=nil;if V.ReleasePresentation then V.ReleasePresentation.finish(s,r) end;r.release=nil end
      local terminal=r.terminal
      if terminal then
        terminal.age=terminal.age+dt
        local actor=r.actor
        local ok,duration=call(actor,'terminalDuration',terminal.kind)
        duration=ok and tonumber(duration) or (terminal.kind=='faint' and 1.23 or .5)
        local age=actor and actor[terminal.kind=='faint' and 'faintAge' or 'recallAge']
        -- An actor waiting behind a hurt clip has not started its terminal bank.
        local waiting=actor and (terminal.kind=='faint' and actor.pendingFaint or actor.pendingRecall)
        age=tonumber(age) or (not waiting and terminal.age or 0)
        if age>=duration or terminal.age>30 then
          if terminal.age>30 then s.presentationError='Terminal animation timed out: '..tostring(r.battlerId) end
          terminal.event.presentationPending=nil;r.terminal=nil
          r.visible=false;call(r.actor,'release');r.actor=nil
        end
      elseif r.retireAt and s.visualClock>=r.retireAt then
        r.visible=false;call(r.actor,'release');r.actor=nil
      end
    end
  end
  if V.DoublesMovePresentation and s.movePresentation then V.DoublesMovePresentation.update(s,dt)
  elseif V.CurrentSpriteModels.updateReleaseFx then V.CurrentSpriteModels:updateReleaseFx(s.context,dt) end
end
function P.actorAnchor(context,id)
  local arena=context.arena or {};local side=id:match('^player') and 'player' or 'enemy'
  local a=arena[side];local b=arena[side=='player' and 'enemy' or 'player']
  if not (a and b) then return nil end
  local dx,dz=b[1]-a[1],b[2]-a[2];local distance=math.max(1,math.sqrt(dx*dx+dz*dz))
  local lane=id:find('left',1,true) and -1 or 1
  local spread=math.max(9,math.min(16,distance*.28))
  return a[1]-dz/distance*spread*lane,a[2]+dx/distance*spread*lane,dx,dz
end
function P.anchor(context,id)
  local x,z,dx,dz=P.actorAnchor(context,id);if not x then return end
  local k=tonumber(context.arena and context.arena.figureScale) or tonumber((context.services or {}).figureScale) or 1
  return x*k,z*k,dx*k,dz*k
end
-- Event-specific shots are read-only; speed/target decisions remain in Core.
-- Send-outs and hit reactions focus the actual slot rather than "other side".
function P.camera(base,s,context)
  if V.DoublesCamera then return V.DoublesCamera.pose(base,s,context) end
  local wide={eye={base.eye[1],base.eye[2]+3,base.eye[3]},focus={base.focus[1],base.focus[2],base.focus[3]},
    fov=math.min(1.5,(base.fov or .8)*1.26),curve=0}
  if not (s and context and s.core) then return wide end
  local event=s.core.currentEvent
  if not event or not event.slot then return wide end
  local kind=event.kind=='reaction' and 'damage' or event.kind
  if kind=='send' and event.alreadyPresented then return wide end
  if kind~='send' and kind~='move' and kind~='damage' and kind~='heal' and kind~='faint' then return wide end
  local x,z,dx,dz=P.anchor(context,event.slot)
  if not x then return wide end
  local distance=math.max(1,math.sqrt(dx*dx+dz*dz));dx=dx/distance;dz=dz/distance
  local ground=context.groundY or 0
  local height=9
  local rec=s.actors and s.actors[event.battlerId]
  if kind=='send' and rec and rec.sendout and rec.sendout.phase<.79 and V.Camera and V.Camera.sendoutShot then
    local side=event.slot:match('^player') and 'player' or 'enemy'
    local pose=V.Camera:sendoutShot(context,context.arena,side)
    if pose then return pose end
  end
  if rec and rec.actor and rec.actor.scene and rec.actor.scene.bounds then
    local bound=rec.actor.scene.bounds
    height=math.max(5,math.min(18,(bound.max[2] or 9)-(bound.min[2] or 0)))
    if rec.actor.height then height=math.max(3,math.min(20,rec.actor.height*(rec.actor.worldScale or 1)*((context.services or {}).figureScale or context.arena.figureScale or .38))) end
  end
  local focus={x,ground+height*.48,z}
  local range=math.max(24,height*2.5)
  -- Keep the vetted arena viewing side. A lane-relative yaw could put the
  -- second enemy's camera behind the stadium shell, looking through lava.
  local ax,az=base.eye[1]-base.focus[1],base.eye[3]-base.focus[3]
  local axisLength=math.max(1,math.sqrt(ax*ax+az*az));ax=ax/axisLength;az=az/axisLength
  local eye={x+ax*range,ground+height*.63+4,z+az*range}
  if kind=='send' then
    -- Grounded, full-body reveal, held through materialization and recovery.
    eye[2]=ground+math.max(3,height*.35);focus[2]=ground+height*.52
  end
  local fov=.78
  if kind=='move' and type(event.targets)=='table' and #event.targets>0 then
    local function point(id)
      local px,pz=P.anchor(context,id);if not px then return nil end
      local slot=s.core.slots and s.core.slots[id]
      local r=slot and s.actors and s.actors[slot.battlerId]
      local actor=r and r.actor
      local h=actor and (actor.height or 16)*(actor.worldScale or 1)*((context.services or {}).figureScale or context.arena.figureScale or .38) or height
      local pos={px,ground+h*.5,pz}
      if actor and actor.attachment then
        local ok,a=pcall(actor.attachment,actor,'center')
        if ok and a and a.position then
          local k=(context.services or {}).figureScale or context.arena.figureScale or .38
          pos={a.position[1]*k,a.position[2]*k,a.position[3]*k}
        end
      end
      return pos,math.max(3,h)
    end
    local src,sh=point(event.slot)
    local points={src};local maxHeight=sh
    for _,id in ipairs(event.targets)do local pos,h=point(id);if pos then points[#points+1]=pos;maxHeight=math.max(maxHeight,h)end end
    local minx,maxx,minz,maxz=src[1],src[1],src[3],src[3]
    local sy=0
    for _,p in ipairs(points)do minx=math.min(minx,p[1]);maxx=math.max(maxx,p[1]);minz=math.min(minz,p[3]);maxz=math.max(maxz,p[3]);sy=sy+p[2]end
    local centre={(minx+maxx)/2,sy/#points,(minz+maxz)/2}
    local span=math.sqrt((maxx-minx)^2+(maxz-minz)^2)
    local age=s.movePresentation and s.movePresentation.chapterAge or s.core.eventTime or 0
    -- One held launch composition, then reveal the full action lane. Spread
    -- moves use their complete target set from the start, never an arbitrary foe.
    local t=#event.targets>1 and 1 or math.max(0,math.min(1,(age-.42)/.36));t=t*t*(3-2*t)
    focus={src[1]+(centre[1]-src[1])*t,src[2]+(centre[2]-src[2])*t,src[3]+(centre[3]-src[3])*t}
    local size=(context.services or {}).renderSize or {}
    local aspect=(size.width or 1280)/math.max(1,size.height or 720)
    fov=math.rad(39.09)
    local launchRange=math.max(23,sh*3.3)
    local trackRange=math.max(launchRange,(span*.58+maxHeight)/math.tan(fov*.5)/math.min(1.45,aspect))
    local radius=launchRange+(trackRange-launchRange)*t
    eye={focus[1]+ax*radius,focus[2]+math.max(5,maxHeight*.7)+radius*.12,focus[3]+az*radius}
  elseif kind=='damage' then
    -- Stay on the established viewing side and frame the actual receiving lane.
    fov=math.rad(36.5);eye[2]=ground+height*.72+3
  end
  -- Damage deliberately frames one actual slot; retain arena bounds without
  -- the singles guard forcing both side centres into this close-up.
  local pose={eye=eye,focus=focus,fov=fov,curve=0}
  return V.Camera and V.Camera.guardPose and V.Camera:guardPose(pose,context.arena,kind=='send' and 'switch' or (kind=='damage' and 'passive' or kind)) or pose
end
function P.draw(s,context)
  s.context=context
  local api=V.PokemonActors.service;local services=context.services or {}
  local vp=api.worldUnits and services.stageVP or services.vp
  local g=love and love.graphics;if not g or not vp then return false end
  local jobs={}
  local function fault(why)
    s.renderError=tostring(why or 'Colosseum actor renderer failed')
    if V.BattleCache then V.BattleCache.noteRenderError(s.screen and s.screen.game or context.game,s.renderError) end
  end
  for _,r in ipairs(s.actorOrder or {}) do if r.visible and r.actor and (r.spawnProgress or 1)>.001 and (not V.DoublesMovePresentation or V.DoublesMovePresentation.visible(s,r)) then
    local x,z,dx,dz=P.actorAnchor(context,r.slot)
    if x then
      local ok,matrix=call(r.actor,'matrix',x,context.groundY or 0,z,dx,dz)
      if ok and matrix then jobs[#jobs+1]={r=r,matrix=matrix} else fault(matrix or 'Colosseum matrix unavailable') end
    end
  end end
  if #jobs>0 then
    local ok,accepted,why=pcall(api.withRenderer,vp,function()
      for _,job in ipairs(jobs) do
        local buildOK,built=true,true
        if type(job.r.actor.build)=='function' then buildOK,built=call(job.r.actor,'build') end
        if buildOK and built~=false then
          local drawn,value=call(job.r.actor,'draw',job.matrix,0)
          if not drawn or value==false then fault(value or 'Colosseum actor draw failed') end
        else fault(built or 'Colosseum actor build failed') end
      end
      return true
    end,{eye=services.camera and services.camera.pose and services.camera.pose.eye,
      width=services.renderSize and services.renderSize.width,height=services.renderSize and services.renderSize.height,context=context})
    if not ok or accepted==false then fault(ok and why or accepted) end
  end
  if V.ReleasePresentation then V.ReleasePresentation.draw(s,context) end
  if V.DoublesMovePresentation and s.movePresentation then V.DoublesMovePresentation.draw(s,context)
  elseif V.CurrentSpriteModels.drawReleaseFx then V.CurrentSpriteModels:drawReleaseFx(context) end
  -- Models explicitly OFF honour the resolved sprite, not the
  -- Colosseum icon atlas. This is a simple four-position fallback, not another
  -- 3D provider's private model API.
  if services.project then
    g.push('all');g.setShader();g.setDepthMode();g.setColor(1,1,1,1)
    for _,r in ipairs(s.actorOrder or {}) do if r.visible and r.spriteMode and (r.spawnProgress or 1)>.001 and (not V.DoublesMovePresentation or V.DoublesMovePresentation.visible(s,r)) then
      local image=r.battler and r.battler.sprite
      if not image and s.generation==2 and s.screen.pic then local ok,v=pcall(s.screen.pic,s.screen,r.mon,r.slot:match('player')~=nil);if ok then image=v end end
      local x,z=P.actorAnchor(context,r.slot)
      if image and x then
        local px,py=services.project(x,context.groundY or 0,z)
        if px and py then
          local w,h=image:getDimensions();local height=math.max(30,math.min(140,(services.renderSize.height or 600)*.15))
          local scale=height/math.max(1,h)
          g.draw(image,px,py,0,scale,scale,w/2,h)
        end
      end
    end end
    g.pop()
  end
  local old=V.CurrentSpriteModels
  old.drawn.player=true;old.drawn.enemy=true;old.presented.player=true;old.presented.enemy=true
  return true
end
function P.finish(s)
  if V.DoublesMovePresentation then V.DoublesMovePresentation.finish(s) end
  if V.CurrentSpriteModels.clearReleaseFx then V.CurrentSpriteModels:clearReleaseFx() end
  if V.ReleasePresentation then for _,r in ipairs(s.actorOrder or {})do V.ReleasePresentation.finish(s,r) end end
  call(V.PlayerTrainer,'clearSendoutTarget');call(V.Trainer,'clearSendoutTarget')
  for _,r in ipairs(s.actorOrder or {}) do call(r.actor,'release');r.actor=nil;r.visible=false end
  s.actorOrder={};s.actors={}
  local old=V.CurrentSpriteModels
  if old.drawn then old.drawn.player=false;old.drawn.enemy=false end
end
return P
