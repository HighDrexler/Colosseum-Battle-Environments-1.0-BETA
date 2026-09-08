-- Only finished battle text receives an automatic acknowledgement. Native
-- animation, HP, sound and presentation gates still own queue progression.
local V=...
local A={states=setmetatable({},{__mode='k'})}
function A.enabled(game)
 local p=game and game.save and game.save.colosseumBattle
 return not p or p.autoProgressEnabled~=false
end
function A.readDelay(text)
 return math.min(3,math.max(.8,#tostring(text or '')/45))
end
function A.ready(screen,generation)
 if not A.enabled(screen.game) or screen.tutorial or screen.demo or screen.waitingUI then return nil end
 local stack=screen.game and screen.game.stack
 if stack and stack.top and stack:top()~=screen then return nil end
 if screen.__cbeDoublesActive and screen.phase=='cbe_doubles' then return nil end
 if generation==1 then
  local item=screen.current
  if screen.phase~='messages' or not item or item.choice or item.auto then return nil end
  if screen.waitingSound or (screen.waitFrames or 0)>0 then return nil end
  if screen.msgWaiting and (screen.msgPreWait or 0)<=0 then return item,screen.lineIndex,'page' end
  if screen.msgPrompt and (screen.msgPromptWait or 0)<=0 then return item,screen.lineIndex,'end' end
 else
  if screen.phase~='resolving' and screen.phase~='intro' then return nil end
  if not screen.message or (screen.messageTimer or 0)<=0 or (screen.messageDelay or 0)>0 or screen.waitSfx then return nil end
  if screen.typedText~=screen.message or (screen.typer and not screen.typer:done()) then return nil end
  if screen.anim and not (screen.anim:done() and screen.anim.keepSprites) then return nil end
  if screen.hpAnim or screen.faintSlide or screen.backpicSlide then return nil end
  return screen.message,screen.typer,'end'
 end
end
function A.update(screen,generation,dt)
 local t=love and love.timer and love.timer.getTime and love.timer.getTime()
 local st=A.states[screen] or {};A.states[screen]=st
 local elapsed=t and math.max(0,math.min(.1,t-(st.time or t))) or math.max(0,math.min(.1,dt or 0))
 st.time=t
 local key,page,kind=A.ready(screen,generation)
 if not key then st.key=nil;st.age=0;return false end
 if key~=st.key or page~=st.page or kind~=st.kind then st.key=key;st.page=page;st.kind=kind;st.age=0 end
 st.age=(st.age or 0)+elapsed
 local text=generation==1 and (screen.current.text or '') or screen.message
 if st.age<A.readDelay(text) then return false end
 st.age=0;return true
end
function A.call(inner,screen,auto,...)
 if not auto then return inner(screen,...) end
 -- Scope the synthetic edge to this one completed-message update. Never
 -- change the shared input object's pressed state or feed a command menu.
 local game=screen.game;local original=game.input
 local proxy=setmetatable({wasPressed=function(_,key)
  return key=='a' or (original and original.wasPressed and original:wasPressed(key)) or false
 end},{__index=function(_,key)
  local value=original and original[key]
  if type(value)=='function' then return function(_,...)return value(original,...)end end
  return value
 end})
 game.input=proxy
 local result={pcall(inner,screen,...)};game.input=original
 if not result[1] then error(result[2],0) end
 return (table.unpack or unpack)(result,2)
end
function A.install()
 if A.installed then return end
 local generation=V.GenerationCompat.current()
 local cls=(V.engineRequire or require)(generation==2 and 'src.ui.gen2.BattleState' or 'src.battle.BattleState')
 local inner=cls.update
 cls.update=function(screen,dt,...)
  return A.call(inner,screen,A.update(screen,generation,dt),dt,...)
 end
 A.installed=true
end
return A
