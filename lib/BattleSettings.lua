local S={}
local installed=false
local modRef,Trainer,Music,ArenaCatalog,BattleMenuUI,CacheManager,TrainerRoster,Compat
local GEN1_START=table.concat({"Start","Menu"})

local function prefs(game)
  if not (game and game.save) then
    return {
      music="normal",arena="auto",arenasEnabled=true,cameraEnabled=true,pokemonModelsEnabled=true,
      playerModel="red",enemyTrainerModel="auto",rivalModel="leaf",
    }
  end
  local p=game.save.colosseumBattle
  if type(p)~="table" then p={}; game.save.colosseumBattle=p end
  if p.arenasEnabled==nil then p.arenasEnabled=true end
  p.arenasEnabled=p.arenasEnabled and true or false
  if p.cameraEnabled==nil then p.cameraEnabled=true end
  p.cameraEnabled=p.cameraEnabled and true or false
  -- Colosseum Pokemon ownership is independent from the arena/camera toggles.
  -- ON means CBE's GC6E01 actors win presentation arbitration; OFF means CBE
  -- declines them and the user's normal resolved sprite/model pipeline wins.
  if p.pokemonModelsEnabled==nil then p.pokemonModelsEnabled=true end
  p.pokemonModelsEnabled=p.pokemonModelsEnabled and true or false

  -- Migrate older boolean trainer settings into the current model selectors.
  local legacy=p.sprites
  if p.playerModel==nil then
    p.playerModel=(p.playerTrainerModel==false or legacy=="off") and "off" or "red"
  end
  if p.enemyTrainerModel==nil then
    p.enemyTrainerModel=(p.enemyTrainerModels==false or legacy=="off" or legacy=="player") and "off" or "auto"
  end
  if p.rivalModel==nil then p.rivalModel="leaf" end
  if TrainerRoster and TrainerRoster.normalizeChoice then
    p.playerModel=TrainerRoster.normalizeChoice(p.playerModel,"player")
    p.enemyTrainerModel=TrainerRoster.normalizeChoice(p.enemyTrainerModel,"enemy")
    p.rivalModel=TrainerRoster.normalizeChoice(p.rivalModel,"rival")
  else
    p.playerModel=tostring(p.playerModel or "red"):lower()
    p.enemyTrainerModel=tostring(p.enemyTrainerModel or "auto"):lower()
    p.rivalModel=tostring(p.rivalModel or "leaf"):lower()
  end
  -- Keep old diagnostic fields coherent for external tooling.
  p.playerTrainerModel=p.playerModel~="off"
  p.enemyTrainerModels=p.enemyTrainerModel~="off"

  local validMusic={random=true,normal=true,first=true,cipher_peon=true,miror_b=true,cipher_admin=true,mirakle_b=true,semifinal=true,final=true,link1=true,link2=true,link3=true,original=true}
  if p.music=="colosseum" or p.music=="wild" or p.music=="trainer" or p.music=="gym" then p.music="normal" end
  if not validMusic[p.music] then p.music="normal" end
  local validArena={auto=true,water=true,orre_colosseum=true,realgam_colosseum=true,outdoor_wild=true,mt_battle_summit=true}
  if not validArena[p.arena] then p.arena="auto" end
  return p
end
local function startMenuId()
  if Compat and type(Compat.current)=="function" then
    local ok,generation=pcall(Compat.current)
    if ok and tonumber(generation)==2 then return "Gen2StartMenu" end
  end
  return GEN1_START
end
local function onStack(stack,state)
  local states=stack and stack.states
  if not (state and type(states)=="table") then return false end
  for _,candidate in ipairs(states) do if candidate==state then return true end end
  return false
end
local function reopen(game,id,parent)
  local ok,Screens=pcall(require,"src.ui.Screens")
  if ok and Screens and game and game.stack then
    id=id or startMenuId()
    local top=type(game.stack.top)=="function" and game.stack:top() or nil
    -- Gold's injected START row does not pop its parent. Preserve that exact
    -- live instance under CBE so its engine-owned onChoose/onClose callbacks,
    -- cursor and other mods' rows remain intact when CBE closes.
    if parent and onStack(game.stack,parent) then return parent end
    if top and top.screenId==id then return top end
    -- If the parent really was consumed (Gen 1's generic menu does this), ask
    -- the game to construct it. Direct Screens.push("Gen2StartMenu") omits
    -- Gold's required callbacks and creates a menu that draws but cannot act.
    if type(game.openStartMenu)=="function" then
      game:openStartMenu()
      return type(game.stack.top)=="function" and game.stack:top() or nil
    end
    return Screens.push(game,id)
  end
end
local function openBattleMenu(game,returnId,returnParent)
  local ok,Menu=pcall(require,"src.ui.Menu")
  if not ok or not Menu then return end
  local p=prefs(game)
  if ArenaCatalog and ArenaCatalog.sync then ArenaCatalog.sync(game) end
  if ArenaCatalog and ArenaCatalog.selected then p.arena=ArenaCatalog.selected(game) end
  local menu
  local environmentToggle={keepOpen=true}
  local cameraToggle={keepOpen=true}
  local pokemonModelsToggle={keepOpen=true}
  local musicRow={keepOpen=true}
  local arenaRow={keepOpen=true}
  local playerTrainerRow={keepOpen=true}
  local enemyTrainerRow={keepOpen=true}
  local rivalRow={keepOpen=true}
  local cacheRow={keepOpen=true}
  local function refresh()
    environmentToggle.label="COLOSSEUM ARENAS  "..(p.arenasEnabled and "ON" or "OFF")
    cameraToggle.label="COLOSSEUM CAMERA  "..(p.cameraEnabled and "ON" or "OFF")
    pokemonModelsToggle.label="COLOSSEUM MODELS  "..(p.pokemonModelsEnabled and "ON" or "OFF")
    local musicLabel=(Music and Music.themeLabel and Music.themeLabel(game,p.music)) or tostring(p.music):upper()
    musicRow.label="MUSIC    "..musicLabel
    local arenaLabel="AUTO"
    if ArenaCatalog and ArenaCatalog.options then
      for _,opt in ipairs(ArenaCatalog.options()) do if opt.id==p.arena then arenaLabel=opt.label break end end
    end
    arenaRow.label="ARENA    "..arenaLabel
    local function choiceLabel(id,role)
      if id=="off" then return "OFF" end
      if id=="auto" then return "AUTO" end
      local label=(TrainerRoster and TrainerRoster.label and TrainerRoster.label(id)) or tostring(id):upper()
      local ready=(TrainerRoster and TrainerRoster.available and TrainerRoster.available(id))
      return label..((ready==false) and " *MISSING" or "")
    end
    playerTrainerRow.label="PLAYER MODEL     "..choiceLabel(p.playerModel,"player")
    enemyTrainerRow.label="ENEMY TRAINERS   "..choiceLabel(p.enemyTrainerModel,"enemy")
    rivalRow.label="RIVAL MODEL      "..choiceLabel(p.rivalModel,"rival")
    local cs=CacheManager and CacheManager.inspect and CacheManager.inspect() or {sourceReady=false,sourceStatus="UNKNOWN"}
    cacheRow.label="ROM SOURCE   "..(cs.sourceReady and "READY" or tostring(cs.sourceStatus or "NOT IMPORTED"))
  end
  environmentToggle.onSelect=function()
    p.arenasEnabled=not p.arenasEnabled
    if ArenaCatalog and ArenaCatalog.setEnabled then ArenaCatalog.setEnabled(game,p.arenasEnabled) end
    refresh()
  end
  cameraToggle.onSelect=function()
    p.cameraEnabled=not p.cameraEnabled
    refresh()
  end
  pokemonModelsToggle.onSelect=function()
    p.pokemonModelsEnabled=not p.pokemonModelsEnabled
    refresh()
  end
  musicRow.onSelect=function()
    local options=(Music and Music.themeOptions and Music.themeOptions(game)) or {{id="normal",label="NORMAL BATTLE"},{id="original",label="ORIGINAL / OFF"}}
    local rows={}
    for _,opt in ipairs(options) do
      local captured=opt
      rows[#rows+1]={
        label=((captured.id==p.music) and "> " or "  ")..captured.label,
        onSelect=function()
          p.music=captured.id
          if Music and Music.setMode then Music.setMode(game,p.music) end
          refresh()
        end,
      }
    end
    local picker=Menu.new(game,rows,{tx=1,ty=1,tw=19,maxVisible=8})
    if BattleMenuUI and BattleMenuUI.mark then BattleMenuUI.mark(picker,"BATTLE MUSIC",rows,8,"COLOSSEUM SOUNDTRACK") end
    for i,opt in ipairs(options) do if opt.id==p.music then picker.index=i;picker:clampScroll();break end end
    game.stack:push(picker)
  end

  arenaRow.onSelect=function()
    local options=(ArenaCatalog and ArenaCatalog.options and ArenaCatalog.options()) or {{id="auto",label="AUTO"},{id="water",label="WATER COLOSSEUM"}}
    local rows={}
    for _,opt in ipairs(options) do
      local captured=opt
      rows[#rows+1]={
        label=((captured.id==p.arena) and "> " or "  ")..captured.label,
        onSelect=function()
          local chosen=captured.id
          if ArenaCatalog and ArenaCatalog.setSelected then chosen=ArenaCatalog.setSelected(game,captured.id) end
          p.arena=chosen or captured.id
          refresh()
        end,
      }
    end
    local picker=Menu.new(game,rows,{tx=1,ty=1,tw=19,maxVisible=8})
    if BattleMenuUI and BattleMenuUI.mark then BattleMenuUI.mark(picker,"BATTLE ENVIRONMENT",rows,8,"COLOSSEUM ARENA SELECT") end
    for i,opt in ipairs(options) do if opt.id==p.arena then picker.index=i;picker:clampScroll();break end end
    game.stack:push(picker)
  end
  cacheRow.onSelect=function()
    local cs=CacheManager and CacheManager.inspect and CacheManager.inspect()
      or {ready=false,runtimeReady=false,sourceReady=false,sourceStatus="UNKNOWN",source="UNKNOWN",files=0,sizeLabel="0 B",componentCounts={}}
    local function componentLabel(id,label)
      local c=cs.componentCounts and cs.componentCounts[id]
      if not c then return label.."   UNKNOWN" end
      return ("%s   %d/%d%s"):format(label,c.have or 0,c.total or 0,(c.have==c.total) and "  READY" or "")
    end
    local rows={
      {label="ROM SOURCE   "..tostring(cs.sourceStatus or "UNKNOWN"),keepOpen=true},
      {label="RUNTIME     "..(cs.runtimeReady and "FULL RUNTIME READY" or (cs.visualReady and "VISUAL READY / AUDIO PENDING" or tostring(cs.sourceStatus or "BUILD PENDING"))),keepOpen=true},
      {label="SOURCE      "..tostring(cs.source or "UNKNOWN"),keepOpen=true},
      {label="DISC        "..tostring(cs.discId or "GC6E01").." / "..tostring(cs.discRegion or "USA"),keepOpen=true},
      {label="EXTRACT V"..tostring(cs.extractionCacheVersion or 1).." / REV "..tostring(cs.extractorRevision or 1),keepOpen=true},
      {label="SOURCE API  "..tostring(cs.sourceAccess or "UNKNOWN"),keepOpen=true},
      {label="SOURCE DATA "..tostring(cs.sourceSizeLabel or "0 B").." / "..tostring(cs.sourceFiles or 0).." FILES",keepOpen=true},
      {label=componentLabel("arenas","ARENAS"),keepOpen=true},
      {label=("TRAINERS   %d/%d%s"):format(cs.trainerResolved or 0,cs.trainerTotal or 10,(cs.trainerResolved or 0)==(cs.trainerTotal or 10) and "  READY" or ""),keepOpen=true},
      {label=componentLabel("audio","AUDIO"),keepOpen=true},
      {label=componentLabel("transition","TRANSITION"),keepOpen=true},
    }
    if cs.sourceFingerprint then rows[#rows+1]={label="FINGERPRINT RECORDED",keepOpen=true} end
    if cs.trainerFirstError then rows[#rows+1]={label="TRAINER FIRST   "..tostring(cs.trainerFirstError),keepOpen=true} end
    if cs.trainerSourceError then rows[#rows+1]={label="TRAINER DETAIL  "..tostring(cs.trainerSourceError),keepOpen=true} end
    if cs.trainerDiagnostic and (cs.trainerResolved or 0)<(cs.trainerTotal or 10) then rows[#rows+1]={label="TRAINER DIAG   "..tostring(cs.trainerDiagnostic),keepOpen=true} end
    if cs.lastAction then rows[#rows+1]={label="LAST   "..tostring(cs.lastAction),keepOpen=true} end
    rows[#rows+1]={label="RESET RUNTIME CACHE",keepOpen=true,onSelect=function()
      if CacheManager and CacheManager.resetRuntime then CacheManager.resetRuntime() end
      refresh()
    end}
    if cs.generated then
      local armed=false
      local resetRow={label="RESET GENERATED RUNTIME",keepOpen=true}
      resetRow.onSelect=function()
        if not armed then armed=true;resetRow.label="CONFIRM RESET GENERATED";return end
        if CacheManager and CacheManager.resetGenerated then CacheManager.resetGenerated() end
        resetRow.label="RESET GENERATED RUNTIME";armed=false;refresh()
      end
      rows[#rows+1]=resetRow
    end
    rows[#rows+1]={label="ROM FILE   LAUNCHER > MODS > IMPORT",keepOpen=true}
    rows[#rows+1]={label="BACK",onSelect=function() end}
    local picker=Menu.new(game,rows,{tx=1,ty=1,tw=29,maxVisible=10})
    if BattleMenuUI and BattleMenuUI.mark then
      BattleMenuUI.mark(picker,"COLOSSEUM ROM SOURCE",rows,10,"REQUIRED ROM / GENERATED RUNTIME STATUS")
    end
    game.stack:push(picker)
  end
  local function openTrainerPicker(role,current,setter,title)
    local options=(TrainerRoster and TrainerRoster.options and TrainerRoster.options(role)) or {{id="off",label="OFF",available=true}}
    local rows={}
    for _,opt in ipairs(options) do
      local captured=opt
      local suffix=(captured.available==false) and " *MISSING" or ""
      rows[#rows+1]={
        label=((captured.id==current) and "> " or "  ")..captured.label..suffix,
        onSelect=function() setter(captured.id);refresh() end,
      }
    end
    local picker=Menu.new(game,rows,{tx=1,ty=1,tw=24,maxVisible=9})
    if BattleMenuUI and BattleMenuUI.mark then BattleMenuUI.mark(picker,title,rows,9,"COLOSSEUM TRAINER MODEL") end
    for i,opt in ipairs(options) do if opt.id==current then picker.index=i;picker:clampScroll();break end end
    game.stack:push(picker)
  end
  playerTrainerRow.onSelect=function()
    openTrainerPicker("player",p.playerModel,function(id) p.playerModel=id;p.playerTrainerModel=id~="off" end,"PLAYER MODEL")
  end
  enemyTrainerRow.onSelect=function()
    openTrainerPicker("enemy",p.enemyTrainerModel,function(id)
      p.enemyTrainerModel=id;p.enemyTrainerModels=id~="off"
      if Trainer and Trainer.setMode then Trainer:setMode(game,id=="off" and "off" or "all") end
    end,"ENEMY TRAINERS")
  end
  rivalRow.onSelect=function()
    openTrainerPicker("rival",p.rivalModel,function(id) p.rivalModel=id end,"RIVAL MODEL")
  end
  local back={label="BACK",onSelect=function() reopen(game,returnId,returnParent) end}
  refresh()
  -- Trainer presentation is intentionally three independent ownership rows:
  -- player Red, ordinary/special enemy trainers, and the Kanto rival substitute.
  local mainRows={environmentToggle,cameraToggle,pokemonModelsToggle,musicRow,arenaRow,playerTrainerRow,enemyTrainerRow,rivalRow,cacheRow,back}
  menu=Menu.new(game,mainRows,{tx=1,ty=2,tw=24,maxVisible=10,onCancel=function() reopen(game,returnId,returnParent) end})
  menu.screenId="CbeBattleSettings"
  if BattleMenuUI and BattleMenuUI.mark then
    BattleMenuUI.mark(menu,"COLOSSEUM BATTLE",mainRows,10,"ENVIRONMENT / CAMERA / POKEMON / AUDIO / TRAINERS / ROM SOURCE")
  end
  game.stack:push(menu)
end

function S.install(mod,trainer,music,arenaCatalog,battleMenuUI,cacheManager,trainerRoster,compat)
  if installed then return true end
  modRef,Trainer,Music,ArenaCatalog,BattleMenuUI,CacheManager,TrainerRoster,Compat=mod,trainer,music,arenaCatalog,battleMenuUI,cacheManager,trainerRoster,compat
  if BattleMenuUI and BattleMenuUI.install then BattleMenuUI.install() end
  if not (mod and mod.hooks and type(mod.hooks.wrap)=="function") then return false end
  mod.hooks:wrap("ui.start_menu.items",function(next,game,items)
    local out=next(game,items)
    if type(out)~="table" then out=items end
    for _,entry in ipairs(out) do
      if entry.__colosseumBattleEntry or tostring(entry.label or ""):upper()=="BATTLE" then return out end
    end
    local at=#out+1
    for i,entry in ipairs(out) do
      if tostring(entry.label or ""):upper()=="OPTION" then at=i;break end
    end
    table.insert(out,at,{label="BATTLE",__colosseumBattleEntry=true,onSelect=function()
      -- Gen 1's generic StartMenu pops before invoking onSelect. Gold's
      -- injected-row arm intentionally does not. Keep a live Gold parent on
      -- the stack; a synthetic replacement lacks onChoose/onClose and is dead.
      local parent=game and game.stack and type(game.stack.top)=="function" and game.stack:top() or nil
      local returnId=(parent and (parent.screenId==GEN1_START or parent.screenId=="Gen2StartMenu"))
        and parent.screenId or startMenuId()
      local returnParent=(parent and parent.screenId==returnId) and parent or nil
      openBattleMenu(game,returnId,returnParent)
    end})
    return out
  end,650)
  installed=true
  return true
end
function S.prefs(game) return prefs(game) end
function S.cameraEnabled(game) return prefs(game or (modRef and modRef.game)).cameraEnabled~=false end
function S.pokemonModelsEnabled(game) return prefs(game or (modRef and modRef.game)).pokemonModelsEnabled~=false end
function S.setCameraEnabled(game,value)
  local p=prefs(game or (modRef and modRef.game)); p.cameraEnabled=value~=false; return p.cameraEnabled
end
function S.status(game)
  local p=prefs(game or (modRef and modRef.game))
  return {
    installed=installed,arenasEnabled=p.arenasEnabled,cameraEnabled=p.cameraEnabled,pokemonModelsEnabled=p.pokemonModelsEnabled,
    music=p.music,musicLabel=Music and Music.themeLabel and Music.themeLabel(game,p.music),
    arena=p.arena,playerModel=p.playerModel,enemyTrainerModel=p.enemyTrainerModel,rivalModel=p.rivalModel,
    playerTrainerModel=p.playerTrainerModel,enemyTrainerModels=p.enemyTrainerModels,
    cache=CacheManager and CacheManager.status and CacheManager.status() or nil,
  }
end
return S
