-- Screen-space cache UI shared by Gen I/II. No source reads, GPU model loads or
-- save writes. The controller renders this AFTER the cartridge palette pass.
local Screen={version=3}
local fonts={}
local color={bg={.028,.044,.049,1},panel={.065,.10,.11,1},edge={.29,.40,.39,1},
  inset={.039,.064,.069,1},ink={.92,.94,.88,1},muted={.60,.72,.70,1},
  accent={1,.31,.15,1},ok={.45,.80,.66,1},error={1,.53,.38,1}}
local function clamp(n,a,b)return math.max(a,math.min(b,n))end
local function font(size)
  size=math.max(7,math.floor(size+.5))
  if not fonts[size] then
    fonts[size]=love.graphics.newFont(size)
    if fonts[size].setFilter then fonts[size]:setFilter('linear','linear') end
  end
  return fonts[size]
end
local function shorten(f,value,width)
  local t=tostring(value or ''):gsub('[\r\n\t]+',' ')
  if f:getWidth(t)<=width then return t end
  local chars={};for c in t:gmatch('[%z\1-\127\194-\244][\128-\191]*')do chars[#chars+1]=c end
  while #chars>0 do
    chars[#chars]=nil
    local s=table.concat(chars)..'...'
    if f:getWidth(s)<=width then return s end
  end
  return ''
end
local function text(t,x,y,w,size,c,align)
  local G=love.graphics;local f=font(size);t=shorten(f,t,math.max(0,w))
  G.setFont(f);G.setColor(c or color.ink)
  if align=='right' then x=x+w-f:getWidth(t)
  elseif align=='center' then x=x+(w-f:getWidth(t))/2 end
  G.print(t,math.floor(x+.5),math.floor(y+.5))
end
local function plate(x,y,w,h,c,line)
  local G=love.graphics;G.setColor(c);G.setLineWidth(1)
  G.rectangle(line and 'line' or 'fill',x,y,w,h)
end
function Screen.layout(w,h)
  local portrait=h>w*1.25
  local margin=math.max(8,math.min(34,w*.035,h*.04))
  local pw=math.min(portrait and 650 or 980,w-2*margin)
  -- Reserve the lower portrait band for mobile controls, not for tiny GB text.
  local avail=portrait and h*.76 or h
  local ph=math.min(portrait and 550 or 590,avail-2*margin)
  local s=portrait and math.min(pw/400,ph/490,1.1) or math.min(pw/620,ph/460,1.2)
  local pad=math.max(10,24*s)
  return {x=(w-pw)/2,y=portrait and margin or (h-ph)/2,w=pw,h=ph,
    s=s,pad=pad,portrait=portrait}
end
local function elapsed(s,now)
  local n=math.max(0,math.floor((s.finishedAt or now)-(s.startedAt or now)))
  if n>=3600 then return ('%dh %02dm elapsed'):format(math.floor(n/3600),math.floor(n/60)%60) end
  return ('%d:%02d elapsed'):format(math.floor(n/60),n%60)
end
local function nameFor(s,row)
  if not row or not row.dex then return 'Checking saved model files' end
  if row.name then return row.name end
  if not s.displayNames then
    s.displayNames={}
    for _,def in pairs(s.game and s.game.data and s.game.data.pokemon or {})do
      if type(def)=='table' then
        local n=tonumber(def.dex or def.index or def.number)
        if n then s.displayNames[n]=def.name or def.id end
      end
    end
  end
  return s.displayNames[row.dex] or ('Pokemon #'..row.dex)
end
function Screen.draw(s,w,h,inventory,now)
  local G=love.graphics;local l=Screen.layout(w,h);local z,p=l.s,l.pad
  local x,y,bw=l.x+p,l.y+p,l.w-2*p
  s.buttons={};s.layout=l
  G.push('all');G.origin();G.setShader();if G.setScissor then G.setScissor()end
  if G.setBlendMode then G.setBlendMode('alpha')end
  plate(0,0,w,h,color.bg)
  plate(l.x+4,l.y+5,l.w,l.h,{0,0,0,.32})
  plate(l.x,l.y,l.w,l.h,color.panel);plate(l.x,l.y,l.w,l.h,color.edge,true)
  plate(l.x,l.y,math.max(3,4*z),l.h,color.accent)
  text('COLOSSEUM / MODEL LIBRARY',x,y,bw,12*z,color.muted)
  local title=s.selector and 'Battle cache' or (s.error and 'Preparation paused' or
    (s.complete and (#s.rows==0 and 'Catalog complete' or 'Batch saved') or
      (s.mode=='quick' and 'Quick Start' or (s.full and 'Full catalog' or 'Preparing models'))))
  text(title,x,y+23*z,bw,30*z,color.ink)
  local sub=s.selector and ((not s.reuseChecked)
      and 'Checking saved cache. No model extraction starts until you select a mode.'
      or 'Choose a mode. No model extraction starts until you select it.') or
    (s.complete and 'Completed models are stored on this device.' or
      (s.mode=='quick' and (l.portrait and '30 new models. Saved for future sessions.' or 'Adding up to 30 uncached models for your save.') or
        (s.full and 'Preparing all normal and shiny appearances.' or 'Loading the exact models this session needs.')))
  text(sub,x,y+66*z,bw,14*z,color.muted)
  local contentY=y+106*z
  local footerY=l.y+l.h-p-30*z
  local contentEnd=footerY-34*z
  local function button(key,label,bx,by,bw2,bh,focused,detail)
    local selected=focused or false
    plate(bx,by,bw2,bh,selected and {.13,.22,.23,1} or color.inset)
    plate(bx,by,bw2,bh,selected and color.accent or color.edge,true)
    if selected then plate(bx,by,3*z,bh,color.accent)end
    local fs=detail and 19*z or 14*z
    text(label,bx+12*z,by+(detail and 9*z or (bh-font(fs):getHeight())/2),bw2-24*z,fs,color.ink)
    if detail then text(detail,bx+12*z,by+34*z,bw2-24*z,12*z,color.muted)end
    s.buttons[#s.buttons+1]={key=key,x=bx,y=by,w=bw2,h=bh}
  end
  if s.selector then
    local gap=10*z
    local labels
    if not s.reuseChecked then
      -- Do not briefly present QUICK START / CURRENT TEAM as the apparent default
      -- while Android is still proving whether an existing cache qualifies for
      -- REUSE. The controller blocks selection during this read-only probe too.
      labels={{'wait','CHECKING SAVED CACHE','Looking for 30+ reusable models. This check does not extract or write models.'}}
    else
      labels={
        {'quick','QUICK START / 30 NEW','Team, caught, seen, nearby and level-relevant.'},
        {'full','FULL CATALOG','All 251 species, normal + shiny. Optional.'},
        {'b','MAIN MENU','Leave now. Your existing cache stays saved.'}}
      if s.startupRequest then
        if s.reuseEligible then
          table.insert(labels,1,{'reuse','REUSE CACHE',
            s.startupRequest.newGame and 'Use saved models; load only required starters, then begin New Game.'
              or 'Use saved models; load only required team models, then Continue.'})
        else
          table.insert(labels,1,{'startup',s.startupRequest.newGame and 'STARTER MODELS ONLY' or 'CURRENT TEAM ONLY',
            s.startupRequest.newGame and 'Prepare native starters, then begin New Game.' or 'Reuse / prepare your team, then Continue.'})
        end
      elseif s.reuseEligible then
        table.insert(labels,1,{'reuse','REUSE CACHE','Reuse saved models; load only the current team. No 30-model batch.'})
      end
    end
    local rowH=math.min(64*z,(contentEnd-contentY-(#labels-1)*gap)/#labels)
    for i,row in ipairs(labels)do
      button(row[1],row[2],x,contentY+(i-1)*(rowH+gap),bw,rowH,s.reuseChecked and s.choice==i,row[3])
    end
    local status
    if s.reuseEligible then
      local n=s.reuseInfo and tonumber(s.reuseInfo.cachedModels) or 30
      status=('Reusable cache detected: %d+ saved models. Reuse skips the 30-new batch.'):format(math.max(30,n or 30))
    elseif not s.reuseChecked then
      status='Checking existing cache (read only). Completed model files are preserved.'
    elseif s.reuseChecked and s.reuseProbeError then
      status='Existing-cache check unavailable. Team/starter-only and manual cache modes remain available.'
    elseif inventory then
      status=('Saved: %d / 270 models | %d / 502 appearances'):format(inventory.cachedModels,inventory.cachedAppearances)
    else
      status='Completed files are checked before selecting each batch.'
    end
    text(status,x,footerY-17*z,bw,12*z,color.muted)
    text('A: SELECT    B: BACK',x,footerY+9*z,bw,12*z,color.ink)
  else
    local done=math.min(#s.rows,math.max(0,s.index-1));local total=#s.rows
    local label=s.planning and 'CHECKING YOUR SAVED CACHE' or (s.complete and 'PERSISTED ON DEVICE' or 'THIS PASS')
    text(label,x,contentY,bw,12*z,color.muted)
    local progress=s.planning and 'Selecting relevant models...' or
      (s.complete and total==0 and 'No new models needed' or
        ('%d / %d %s'):format(done,total,s.batchInfo and 'new models saved' or 'appearances ready'))
    text(progress,x,contentY+23*z,bw,25*z,s.error and color.error or color.ink)
    local barY=contentY+64*z
    plate(x,barY,bw,8*z,color.inset)
    local q=total>0 and done/total or (s.complete and 1 or 0)
    if q>0 then plate(x,barY,bw*q,8*z,s.error and color.error or color.ok)end
    local row=s.rows[s.index]
    local model=s.complete and 'Quick Start will select the next new batch.' or nameFor(s,row)
    if row and row.variant=='shiny' then model=model..' / shiny' end
    text(model,x,barY+25*z,bw,18*z,color.ink)
    local stage=s.error and tostring(s.error) or (s.complete and 'No re-extraction on restart.' or s.label or 'Checking generated data...')
    text(stage,x,barY+53*z,bw,12*z,s.error and color.error or color.muted)
    local info=s.batchInfo or inventory
    local by=math.min(barY+91*z,contentEnd-29*z)
    if info then
      text(('DISK CACHE  %d / 270 models  |  %d / 502 appearances'):format(info.cachedModels,info.cachedAppearances),x,by,bw,12*z,color.ok)
    else text('Disk files persist. Graphics memory is session-only.',x,by,bw,12*z,color.muted)end
    text(elapsed(s,now),x,by+23*z,bw,12*z,color.muted,'right')
    local note=s.battle and 'Exact Colosseum models required. No sprite substitution.' or
      (s.error and 'Error details are saved in the model-cache log.' or 'Leaving preserves every completed model.')
    text(note,x,footerY-24*z,bw,12*z,color.muted)
    local keys={}
    if s.error then keys[#keys+1]={'a','A: RETRY'} end
    if not s.battle then keys[#keys+1]={s.complete and 'a' or 'b',s.complete and 'A: MAIN MENU' or 'B: MAIN MENU'} end
    if s.error then keys[#keys+1]={'start','EXIT GAME'} end
    local gap=10*z;local buttonW=(bw-math.max(0,#keys-1)*gap)/math.max(1,#keys)
    for i,k in ipairs(keys)do button(k[1],k[2],x+(i-1)*(buttonW+gap),footerY,buttonW,30*z,i==1)end
  end
  G.pop()
end
Screen._test={shorten=shorten}
-- Faults keep the native battle visible and paused. This compact message is
-- never used for ordinary cache misses or successful model buffering.
function Screen.drawRuntimeError(w,h)
  if not (love and love.graphics) then return end
  local G=love.graphics;if not w then w,h=G.getDimensions() end
  local size=math.max(10,math.min(18,w/45));local f=font(size)
  local message='Model unavailable. A: retry | START: exit.\nDetails: model-cache-error.txt'
  G.push('all');G.origin();G.setShader();if G.setScissor then G.setScissor() end
  G.setFont(f);G.setColor(color.panel);G.rectangle('fill',0,0,w,f:getHeight()*3+16)
  G.setColor(color.error);G.printf(message,12,8,math.max(1,w-24),'center');G.pop()
end
return Screen
