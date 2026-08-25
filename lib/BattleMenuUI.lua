local V=...
local mod=V.mod
local U={installed=false}
local fontCache={}
local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function topState(game)
  local states=game and game.stack and game.stack.states
  return type(states)=="table" and states[#states] or nil
end
local function scaleForWindow()
  local w,h=love.graphics.getDimensions();return clamp(math.min(w/1280,h/720),.78,1.72)
end
local function font(sz)
  sz=math.max(9,math.floor(sz+.5));if fontCache[sz] then return fontCache[sz] end
  local ok,f=pcall(love.graphics.newFont,sz)
  f=(ok and f) or love.graphics.getFont();if f and f.setFilter then pcall(f.setFilter,f,"nearest","nearest") end
  fontCache[sz]=f;return f
end
local function text(s,x,y,sz,col,align,w)
  local g=love.graphics;g.setFont(font(sz));g.setColor(col[1],col[2],col[3],col[4] or 1)
  if align and w then g.printf(tostring(s or ""),x,y,w,align) else g.print(tostring(s or ""),x,y) end
end
local function plate(x,y,w,h,u)
  local g=love.graphics;local c=14*u
  -- Soft hanging shadow, then the same long beveled GameCube-console language
  -- used by the user's Colosseum UI overhaul.
  g.setColor(0,0,0,.34)
  g.polygon("fill",x+c+7*u,y+8*u,x+w-c+7*u,y+8*u,x+w+7*u,y+c+8*u,x+w-c+7*u,y+h+8*u,x+c+7*u,y+h+8*u,x+7*u,y+h-c+8*u,x+7*u,y+c+8*u)
  g.setColor(.072,.084,.080,.955)
  g.polygon("fill",x+c,y,x+w-c,y,x+w,y+c,x+w-c,y+h,x+c,y+h,x,y+h-c,x,y+c)
  g.setColor(.46,.48,.43,.94);g.setLineWidth(math.max(1,1.35*u))
  g.line(x+c+4*u,y+3*u,x+w-c-4*u,y+3*u);g.line(x+4*u,y+c+2*u,x+4*u,y+h-c-2*u)
  g.setColor(.18,.20,.18,.72);g.line(x+8*u,y+h-5*u,x+w-c-5*u,y+h-5*u)
end
local function selector(x,y,h,u)
  local g=love.graphics;g.setColor(.96,.53,.23,1)
  g.polygon("fill",x+9*u,y+h*.50,x,y+h*.26,x,y+h*.74)
end
local function drawState(game,state)
  if not (state and state.__cbeBattleMenu and love and love.graphics) then return false end
  local g=love.graphics;local sw,sh=g.getDimensions();local u=scaleForWindow()
  local rows=state.__cbeRows or state.items or state.entries or {}
  local count=#rows;local visible=math.min(tonumber(state.__cbeMaxVisible) or 8,math.max(1,count))
  local rowH=39*u;local panelW=clamp(520*u,420,sw*.62);local panelH=(85+visible*39+18)*u
  local x=clamp(sw*.075,18*u,sw-panelW-18*u);local y=clamp((sh-panelH)*.50,24*u,sh-panelH-24*u)
  g.push("all")
  -- Glass rather than a black-screen state: the actual battlefield/overworld
  -- remains visible behind the settings surface.
  g.setColor(.015,.027,.026,.18);g.rectangle("fill",0,0,sw,sh)
  plate(x,y,panelW,panelH,u)
  -- Header tab projects above the main plate, matching the battle move tab.
  local tabW=math.min(panelW*.66,360*u)
  g.setColor(.13,.15,.14,.98)
  g.polygon("fill",x+22*u,y-20*u,x+tabW,y-20*u,x+tabW+15*u,y,x+14*u,y)
  text(state.__cbeTitle or "COLOSSEUM BATTLE",x+34*u,y-17*u,15*u,{.96,.91,.72,1})
  text(state.__cbeSubtitle or "ENVIRONMENT / AUDIO / TRAINERS",x+30*u,y+18*u,9*u,{.50,.56,.51,1})
  local index=tonumber(state.index) or 1
  local scroll=tonumber(state.scroll) or tonumber(state.scrollOffset) or 0
  -- Menu implementations disagree whether scroll is zero- or one-based. Pick
  -- the window that contains the authoritative selected index.
  local first=math.max(1,math.min(index,math.floor(scroll)+1))
  if index-first>=visible then first=index-visible+1 end
  if count<=visible then first=1 end
  local top=y+58*u
  for slot=1,visible do
    local i=first+slot-1;local row=rows[i];if not row then break end
    local ry=top+(slot-1)*rowH;local selected=i==index
    if selected then
      g.setColor(.30,.32,.29,.82)
      g.polygon("fill",x+30*u,ry+3*u,x+panelW-31*u,ry+3*u,x+panelW-21*u,ry+rowH-5*u,x+30*u,ry+rowH-5*u)
      selector(x+18*u,ry,rowH,u)
    elseif slot%2==0 then
      g.setColor(.11,.125,.115,.34);g.rectangle("fill",x+31*u,ry+3*u,panelW-58*u,rowH-7*u)
    end
    local label=tostring((type(row)=="table" and row.label) or row or "")
    -- Native picker labels use a textual > marker. The Colosseum triangle owns
    -- selection visually, so remove only that leading compatibility marker.
    label=label:gsub("^%s*>%s*",""):gsub("^%s%s","")
    text(label,x+43*u,ry+9*u,14*u,selected and {.99,.94,.74,1} or {.76,.80,.73,1})
  end
  if count>visible then
    text(("%d / %d"):format(index,count),x+panelW-112*u,y+panelH-28*u,9*u,{.52,.57,.52,1},"right",82*u)
  end
  text("A: SELECT     B: BACK",x+31*u,y+panelH-27*u,9*u,{.48,.53,.48,1})
  g.pop();return true
end
function U.mark(menu,title,rows,maxVisible,subtitle)
  if type(menu)=="table" then
    menu.__cbeBattleMenu=true;menu.__cbeTitle=title or "COLOSSEUM BATTLE";menu.__cbeRows=rows or menu.__cbeRows
    menu.__cbeMaxVisible=maxVisible or menu.__cbeMaxVisible or 8;menu.__cbeSubtitle=subtitle or menu.__cbeSubtitle
  end
  return menu
end
function U.install()
  if U.installed then return true end
  if not (mod and mod.hooks and type(mod.hooks.wrap)=="function") then return false end
  mod.hooks:wrap("screen.render_visible",function(next,state)
    if type(state)=="table" and state.__cbeBattleMenu then return false end
    return next(state)
  end,21500)
  mod.hooks:wrap("render.hud",function(next,game,viewport)
    local out=next(game,viewport);local state=topState(game)
    if state and state.__cbeBattleMenu then pcall(drawState,game,state) end
    return out
  end,21500)
  U.installed=true;return true
end
function U.status() return {installed=U.installed,style="colosseum-beveled-glass"} end
return U
