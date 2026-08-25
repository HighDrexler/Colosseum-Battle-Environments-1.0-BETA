local U={active=false,disabled=false,lastDraw=0,lastLabel=nil}

local function graphicsReady()
  if U.disabled then return false end
  if not (love and love.graphics) then return false end
  if love.graphics.isActive then
    local ok,v=pcall(love.graphics.isActive)
    if ok and not v then return false end
  end
  return type(love.graphics.getDimensions)=="function" and type(love.graphics.present)=="function"
end

local function stageInfo(label)
  local s=tostring(label or "BUILDING CACHE"):upper()
  if s:find("DISC",1,true) then return 1,"VALIDATING COLOSSEUM DISC" end
  if s:find("FSYS",1,true) then return 2,"INDEXING COLOSSEUM ARCHIVES" end
  if s:find("ARENA",1,true) then return 3,"BUILDING ARENA CACHE" end
  if s:find("TRAINER",1,true) then return 4,"BUILDING TRAINER CACHE" end
  if s:find("TRANSITION",1,true) then return 5,"BUILDING TRANSITION CACHE" end
  if s:find("AUDIO",1,true) then return 6,"BUILDING AUDIO CACHE" end
  if s:find("VERIFY",1,true) or s:find("READY",1,true) then return 7,"FINALIZING GENERATED RUNTIME" end
  return 1,"BUILDING GENERATED RUNTIME"
end

local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function printWrapped(g,text,x,y,w)
  if type(g.printf)=="function" then g.printf(tostring(text or ""),x,y,w,"left") else g.print(tostring(text or ""),x,y) end
end

local function beginFrame(heightOverride)
  local g=love.graphics
  local w,h=g.getDimensions()
  if g.push then g.push("all") end
  if g.setCanvas then g.setCanvas() end
  if g.origin then g.origin() end
  g.clear(0.035,0.045,0.04,1)
  local panelW=math.min(w-48,760);local panelH=math.min(h-48,heightOverride or 390)
  local x=(w-panelW)/2;local y=(h-panelH)/2
  g.setColor(0.08,0.10,0.09,0.98);g.rectangle("fill",x,y,panelW,panelH,8,8)
  g.setColor(0.54,0.50,0.26,1);g.rectangle("fill",x,y,panelW,5)
  return g,panelW,panelH,x,y
end

local function endFrame(g)
  if g.pop then g.pop() end
  g.present()
end

local function draw(label,current,total,force,finalText)
  if not graphicsReady() then return end
  local now=(love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
  if not force and U.lastLabel==label and now-U.lastDraw<0.045 then return end
  U.lastDraw=now;U.lastLabel=label;U.active=true
  local ok=pcall(function()
    local g,panelW,_,x,y=beginFrame()
    g.setColor(0.90,0.86,0.65,1);g.print("COLOSSEUM SOURCE CACHE",x+28,y+24)
    g.setColor(0.70,0.74,0.69,1);g.print("BUILDING GENERATED RUNTIME FROM YOUR VALIDATED GC6E01 DISC",x+28,y+56)

    local stage,stageName=stageInfo(label)
    local c=tonumber(current) or 0;local t=tonumber(total) or 0
    local localFrac=t>0 and clamp(c/t,0,1) or 0
    local overall=clamp(((stage-1)+localFrac)/7,0,1)
    g.setColor(0.94,0.92,0.78,1);g.print(("STAGE %d / 7   %s"):format(stage,stageName),x+28,y+104)
    g.setColor(0.86,0.88,0.82,1);g.print(tostring(label or stageName),x+28,y+132)
    if t>0 then g.setColor(0.66,0.70,0.65,1);g.print(("%d / %d"):format(c,t),x+28,y+158) end

    local bx=x+28;local by=y+198;local bw=panelW-56;local bh=24
    g.setColor(0.15,0.17,0.15,1);g.rectangle("fill",bx,by,bw,bh,4,4)
    g.setColor(0.68,0.62,0.32,1);g.rectangle("fill",bx,by,math.max(2,bw*overall),bh,4,4)
    g.setColor(0.78,0.80,0.74,1);g.print(("OVERALL CACHE  %d%%"):format(math.floor(overall*100+0.5)),bx,by+34)

    g.setColor(0.58,0.62,0.57,1)
    g.print("First launch after importing the disc or updating the extractor can take ~30-90 seconds.",x+28,y+275)
    g.print("The current source/member is shown above; progress heartbeats confirm the build is still active.",x+28,y+301)
    if finalText then g.setColor(0.90,0.86,0.65,1);printWrapped(g,finalText,x+28,y+330,panelW-56) end
    endFrame(g)
    if love.event and love.event.pump then love.event.pump() end
  end)
  if not ok then U.disabled=true end
end

local function short(v,n)
  v=tostring(v or ""):gsub("[%s\r\n]+"," ")
  n=n or 150
  if #v>n then return v:sub(1,n-3).."..." end
  return v
end

local function failureFrame(state,message,trainerFirst,trainerSource)
  if not graphicsReady() then return false end
  local ok=pcall(function()
    local g,panelW,_,x,y=beginFrame(470)
    g.setColor(0.90,0.86,0.65,1);g.print("COLOSSEUM SOURCE CACHE",x+28,y+24)
    g.setColor(0.86,0.70,0.64,1);g.print("GENERATED RUNTIME IS NOT READY",x+28,y+58)
    g.setColor(0.94,0.92,0.78,1);g.print(tostring(state or "CACHE BUILD FAILED"),x+28,y+104)
    g.setColor(0.72,0.75,0.70,1);printWrapped(g,message or "The generated runtime did not complete.",x+28,y+136,panelW-56)
    if trainerFirst and trainerFirst~="" then
      g.setColor(0.86,0.82,0.68,1);g.print("TRAINER TARGET",x+28,y+204)
      g.setColor(0.68,0.71,0.66,1);printWrapped(g,short(trainerFirst,170),x+166,y+204,panelW-194)
    end
    if trainerSource and trainerSource~="" then
      g.setColor(0.86,0.82,0.68,1);g.print("SOURCE DETAIL",x+28,y+236)
      g.setColor(0.68,0.71,0.66,1);printWrapped(g,short(trainerSource,210),x+166,y+236,panelW-194)
    end
    g.setColor(0.58,0.62,0.57,1);g.print("CBE will not initialize an incomplete generated runtime.",x+28,y+314)
    g.setColor(0.84,0.84,0.75,1);g.print("R  RETRY CACHE BUILD",x+28,y+356)
    g.print("ENTER  CONTINUE WITHOUT CBE",x+28,y+384)
    g.print("ESC  EXIT GAME",x+28,y+412)
    endFrame(g)
  end)
  if not ok then U.disabled=true return false end
  return true
end

local function isDown(key)
  if not (love and love.keyboard and type(love.keyboard.isDown)=="function") then return false end
  local ok,v=pcall(love.keyboard.isDown,key);return ok and v==true
end

function U.update(label,current,total)
  draw(label,current,total,false,nil)
end

function U.finish(state,message)
  if not U.active then return end
  local label=tostring(state or "CACHE BUILD COMPLETE")
  draw(label,7,7,true,message or state)
end

-- Startup is synchronous, so a failed first-run build needs its own tiny event
-- loop. This prevents an incomplete CBE runtime from silently falling through
-- into gameplay while still allowing an explicit vanilla-game escape hatch.
function U.failureGate(state,message,trainerFirst,trainerSource)
  if not failureFrame(state,message,trainerFirst,trainerSource) then return "continue" end
  local prevR,prevEnter,prevEsc=true,true,true
  local armedAt=((love.timer and love.timer.getTime and love.timer.getTime()) or os.clock())+0.20
  while true do
    if love.event and love.event.pump then pcall(love.event.pump) end
    if love.event and type(love.event.poll)=="function" then
      local ok,iter=pcall(love.event.poll)
      if ok and iter then
        for name in iter do
          if name=="quit" then return "exit" end
        end
      end
    end
    local now=(love.timer and love.timer.getTime and love.timer.getTime()) or os.clock()
    local r=isDown("r")
    local ent=isDown("return") or isDown("kpenter")
    local esc=isDown("escape")
    if now>=armedAt then
      if r and not prevR then return "retry" end
      if ent and not prevEnter then return "continue" end
      if esc and not prevEsc then
        if love.event and love.event.quit then pcall(love.event.quit) end
        return "exit"
      end
    end
    prevR,prevEnter,prevEsc=r,ent,esc
    failureFrame(state,message,trainerFirst,trainerSource)
    if love.timer and love.timer.sleep then love.timer.sleep(0.05) end
  end
end

return U
