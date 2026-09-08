-- Slot-owned retail ball_open chapters. Never run the side-wide Waza owner
-- controller: it would hide or move the partner that has already arrived.
local V=...
local R={version=1,serial=0}
local balls={POKE_BALL='monsterball',GREAT_BALL='superball',ULTRA_BALL='hyperball',MASTER_BALL='masterball',
 SAFARI_BALL='safariball',NET_BALL='netball',DIVE_BALL='diveball',NEST_BALL='nestball',
 REPEAT_BALL='repeatball',TIMER_BALL='timerball',LUXURY_BALL='gorgeousball',PREMIER_BALL='puremiyaball'}
function R.begin(s,r)
 local ctx=s.context;if not ctx then return end
 R.serial=R.serial+1
 local key=r.mon and (r.mon.pokeball or r.mon.pokeBall or r.mon.ball)
 local stem=balls[tostring(key or 'POKE_BALL'):upper()] or 'monsterball'
 local spec=V.MoveFXExtractor and V.MoveFXExtractor.peek(nil,{name=stem})
 local release={age=0,serial='release-'..R.serial,entries={},models={},stem=stem}
 r.release=release
 if not spec then release.error='Source ball_open cache unavailable';return end
 spec=V.WazaPhasePolicy.select(spec,{phase='open'});release.spec=spec
 local entries={}
 for _,phase in ipairs(spec.wazaPhases or {})do if phase.name=='open' then
  for _,e in ipairs(phase.entries or {})do local copy={};for k,v in pairs(e)do copy[k]=v end;entries[#entries+1]=copy end
 end end
 release.entries=V.WazaSequenceRuntime.resolveEntryStarts(entries,{0,0,0,0})
 local x,z,dx,dz=V.DoublesPresenter.anchor(ctx,r.slot)
 if not x then return end
 local k=(ctx.services or {}).figureScale or .38
 local height=r.actor and (r.actor.height or 16)*(r.actor.worldScale or 1) or 16
 local origin={x/k,((ctx.groundY or 0)+3.85)/k,z/k}
 release.origin={x,(ctx.groundY or 0)+3.85,z}
 -- The verified retail open prop's button is local +Z, like the PKX actor.
 -- Keep it facing into the field through
 -- the stationary open chapter, including mirrored/diagonal enemy lanes.
 dx,dz=tonumber(dx) or 0,tonumber(dz) or (r.slot:match('^player') and -1 or 1)
 local length=math.sqrt(dx*dx+dz*dz)
 if length<.0001 then dx,dz,length=0,(r.slot:match('^player') and -1 or 1),1 end
 release.forward={dx/length,dz/length}
 release.geometry={origin=origin,target={origin[1]+release.forward[1],origin[2],origin[3]+release.forward[2]},actor=r.actor,
  style='self',sourceVisualHeight=height,targetVisualHeight=height,referenceVisualHeight=height,
  fightDistance=1,sourceUnits={x=height/100,y=height/100,z=height/100}}
end
function R.update(s,r,dt)
 local a=r.release;if not a then return end
 a.age=a.age+dt
 if a.age>=50/60 and not a.cryPlayed then
  a.cryPlayed=true
  local ok,Sound=pcall(V.engineRequire or require,'src.core.Sound')
  local data=s.screen and s.screen.game and s.screen.game.data
  if ok and Sound.playCry and data and r.mon then
   local played,err=pcall(Sound.playCry,data,r.mon.species,11)
   if not played then a.cryError=tostring(err)end
  end
 end
 local frame=a.age*60
 if r.actor then r.actor.releaseFlash=math.max(0,math.min(1,(1.5-a.age)/.35)) end
 for _,row in ipairs(a.entries)do if not row.started and frame>=row.startFrame then
  row.started=true;local e=row.entry
  if e.kind=='particle' and a.geometry then
   V.CurrentSpriteModels:stageReleaseParticles(s.context,r.slot:match('^player') and 'player' or 'enemy',a.spec,e,a.geometry,a.serial)
  elseif e.kind=='model' and e.modelAsset then
   a.models[#a.models+1]={asset=e.modelAsset,start=row.startFrame,stop=row.startFrame+math.max(30,tonumber((e.timingPoints or {})[2]) or 30)}
  elseif e.kind=='sound' and V.WazaAudioRuntime then
   V.WazaAudioRuntime:start(s.context,{spec=a.spec,serial=a.serial,frame=frame,presentation="release"},e)
  end
 end end
end
function R.draw(s,ctx)
 local vp=ctx.services and ctx.services.stageVP
 if not (vp and V.WazaHandlers and V.WazaHandlers.drawAsset) then return end
 for _,r in ipairs(s.actorOrder or {})do local a=r.release
  if r.visible and a and a.origin then
   local p=a.origin;local u=1.1
   local forward=a.forward or {0,-1};local sn,cs=forward[1],forward[2]
   local matrix={u*cs,0,u*sn,p[1],0,u,0,p[2],-u*sn,0,u*cs,p[3],0,0,0,1}
   for _,m in ipairs(a.models)do local frame=a.age*60
    if frame>=m.start and frame<m.stop then
     local ok,why=V.WazaHandlers.drawAsset(ctx,m.asset,vp,matrix,frame-m.start,{opacity=1,cullMode='none'})
     if not ok then a.error=tostring(why) end
    end
   end
  end
 end
end
function R.finish(s,r)
 if r.actor then r.actor.releaseFlash=0 end
 local a=r.release
 if a and V.WazaAudioRuntime then
  for _,row in ipairs(a.entries)do if row.started and row.entry.kind=='sound' then
   V.WazaAudioRuntime:cancel(s.context,{serial=a.serial},row.entry)
  end end
 end
 r.release=nil
end
return R
