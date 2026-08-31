local V=...
local GeneratedAssets=V.GeneratedAssets
local M={}
local installed=false
local hookInstalled=false
local gameRef=nil
local modRef=nil
local randomBattleTheme=nil
local missingWarned={}

-- Battle-theme library rendered from the user's Pokemon Colosseum ROM.
-- UI ids stay stable even if the underlying extracted sequence/cache layout changes.
local THEMES={
  {id="normal",label="NORMAL BATTLE",seq="battle5",song="COLOSSEUM_ENV_NORMAL",intro="assets/audio/themes/normal_battle_intro.wav",loop="assets/audio/themes/normal_battle_loop.wav"},
  {id="first",label="FIRST BATTLE",seq="battle8",song="COLOSSEUM_ENV_FIRST",intro="assets/audio/themes/first_battle_intro.wav",loop="assets/audio/themes/first_battle_loop.wav"},
  {id="cipher_peon",label="CIPHER PEON",seq="battle7",song="COLOSSEUM_ENV_CIPHER_PEON",intro="assets/audio/themes/cipher_peon_intro.wav",loop="assets/audio/themes/cipher_peon_loop.wav"},
  {id="miror_b",label="MIROR B.",seq="mirrorbo",song="COLOSSEUM_ENV_MIROR_B",intro="assets/audio/themes/miror_b_intro.wav",loop="assets/audio/themes/miror_b_loop.wav"},
  {id="cipher_admin",label="CIPHER ADMIN",seq="battle9plus",song="COLOSSEUM_ENV_CIPHER_ADMIN",intro="assets/audio/themes/cipher_admin_intro.wav",loop="assets/audio/themes/cipher_admin_loop.wav"},
  {id="mirakle_b",label="MIRAKLE B.",seq="miraclebo",song="COLOSSEUM_ENV_MIRAKLE_B",intro="assets/audio/themes/mirakle_b_intro.wav",loop="assets/audio/themes/mirakle_b_loop.wav"},
  {id="semifinal",label="SEMI-FINAL",seq="battle2",song="COLOSSEUM_ENV_SEMIFINAL",intro="assets/audio/themes/semifinal_intro.wav",loop="assets/audio/themes/semifinal_loop.wav"},
  {id="final",label="FINAL BATTLE",seq="battle6",song="COLOSSEUM_ENV_FINAL",intro="assets/audio/themes/final_battle_intro.wav",loop="assets/audio/themes/final_battle_loop.wav"},
  {id="link1",label="BATTLE MODE 1",seq="tool_battle1",song="COLOSSEUM_ENV_LINK1",intro="assets/audio/themes/link_1_intro.wav",loop="assets/audio/themes/link_1_loop.wav"},
  {id="link2",label="BATTLE MODE 2",seq="tool_battle2",song="COLOSSEUM_ENV_LINK2",intro="assets/audio/themes/link_2_intro.wav",loop="assets/audio/themes/link_2_loop.wav"},
  {id="link3",label="BATTLE MODE 3",seq="tool_battle3",song="COLOSSEUM_ENV_LINK3",intro="assets/audio/themes/link_3_intro.wav",loop="assets/audio/themes/link_3_loop.wav"},
}
local OPTIONS={{id="random",label="RANDOM"}}
for _,t in ipairs(THEMES) do OPTIONS[#OPTIONS+1]=t end
OPTIONS[#OPTIONS+1]={id="original",label="ORIGINAL / OFF",original=true}
local BY_ID={}
for _,t in ipairs(OPTIONS) do BY_ID[t.id]=t end

local function log(mod,level,msg)
  local l=mod and mod.log;if l and type(l[level])=="function" then pcall(l[level],l,msg) end
end
local fileDataCache={}
local function assetData(asset)
  local hit=fileDataCache[asset]
  if hit~=nil then return hit or nil end
  local bytes,readErr=GeneratedAssets.read(asset)
  if type(bytes)~="string" then fileDataCache[asset]=false;return nil,readErr end
  -- A half-written or stale cache file must never become a fatal music source.
  -- The generated assets are PCM WAV; reject obvious cache corruption before
  -- handing bytes to LÖVE and simply fall back to original game audio.
  if #bytes<44 or bytes:sub(1,4)~="RIFF" or bytes:sub(9,12)~="WAVE" then
    fileDataCache[asset]=false;return nil,"generated WAV failed RIFF/WAVE validation"
  end
  if not (love and love.filesystem and love.filesystem.newFileData) then
    fileDataCache[asset]=false;return nil,"love.filesystem.newFileData unavailable"
  end
  local ok,fd=pcall(love.filesystem.newFileData,bytes,asset:match("[^/]+$") or "cbe.wav")
  if not ok or not fd then fileDataCache[asset]=false;return nil,tostring(fd or "FileData creation failed") end
  fileDataCache[asset]=fd
  return fd
end
local function assetPath(_,asset) return assetData(asset) end
local function themeAvailable(theme)
  if not theme then return false end
  return assetData(theme.intro)~=nil and assetData(theme.loop)~=nil
end
local function settings(game)
  if not (game and game.save) then return {music="normal"} end
  local s=game.save.colosseumBattle;if type(s)~="table" then s={};game.save.colosseumBattle=s end
  -- migrate the v14-v16 selector: the old generic Colosseum choice was Normal Battle;
  -- old Kanto-forcing choices are intentionally retired rather than kept hidden.
  if s.music=="colosseum" or s.music=="wild" or s.music=="trainer" or s.music=="gym" then s.music="normal" end
  if not BY_ID[s.music] then s.music="normal" end
  return s
end
local function requestKind(song,ctx)
  local s=tostring(song or ""):lower()
  if s:find("defeatedtrainer",1,true) or s:find("defeatedwildmon",1,true) or s:find("defeatedgymleader",1,true) or s:find("victory",1,true) then return "result" end
  if s:find("wildbattle",1,true) or s:find("trainerbattle",1,true) or s:find("gymleaderbattle",1,true) or s:find("finalbattle",1,true) then return "battle" end
  if type(ctx)=="table" then
    local reason=tostring(ctx.reason or ctx.kind or ctx.state or ""):lower()
    if reason=="victory" then return "result" end
    if reason=="battle" or reason=="battle_music" then return "battle" end
  end
end
local function ensureSongs(game)
  game=game or gameRef or (modRef and modRef.game)
  local data=game and game.data
  local songs=data and data.audio and data.audio.songs
  if not songs then installed=false;return false,0 end
  local available=0
  for _,theme in ipairs(THEMES) do
    local intro=assetPath(modRef,theme.intro);local loop=assetPath(modRef,theme.loop)
    if intro and loop then
      songs[theme.song]={file=intro,loopFile=loop}
      available=available+1
      missingWarned[theme.id]=nil
    elseif not missingWarned[theme.id] then
      missingWarned[theme.id]=true
      log(modRef,"warn","Optional Colosseum theme unavailable; using original game audio when selected: "..theme.id)
    end
  end
  installed=available>0
  return installed,available
end
local function chooseRandom(game)
  ensureSongs(game or gameRef)
  local available={}
  for _,theme in ipairs(THEMES) do
    if themeAvailable(theme) then available[#available+1]=theme end
  end
  if #available<1 then randomBattleTheme=nil;return nil end
  randomBattleTheme=available[math.random(1,#available)]
  return randomBattleTheme
end
function M.themeOptions(game)
  ensureSongs(game or gameRef);local out={}
  local haveTheme=false
  for _,t in ipairs(THEMES) do if themeAvailable(t) then haveTheme=true break end end
  if haveTheme then
    out[#out+1]={id="random",label="RANDOM"}
    for _,t in ipairs(THEMES) do if themeAvailable(t) then out[#out+1]={id=t.id,label=t.label} end end
  end
  out[#out+1]={id="original",label=haveTheme and "ORIGINAL / OFF" or "ORIGINAL / CACHE REQUIRED"}
  return out
end
function M.themeLabel(game,mode)
  local t=BY_ID[mode or M.getMode(game)];return (t and t.label) or "NORMAL BATTLE"
end
function M.nextMode(game,current)
  current=current or M.getMode(game);local options=M.themeOptions(game);local at=0
  for i,o in ipairs(options) do if o.id==current then at=i;break end end
  return options[(at%#options)+1].id
end
function M.install(mod)
  modRef=modRef or mod;gameRef=(mod and mod.game) or gameRef;ensureSongs(gameRef)
  if hookInstalled then return installed end
  if not (mod and mod.hooks and type(mod.hooks.wrap)=="function") then return false end
  mod.hooks:wrap("music.select",function(next,song,ctx)
    local selected=next(song,ctx);local game=(modRef and modRef.game) or gameRef;local mode=settings(game).music;local kind=requestKind(selected,ctx) or requestKind(song,ctx)
    if mode=="original" then randomBattleTheme=nil;return selected end
    if mode=="random" then
      if kind=="battle" then
        ensureSongs(game)
        local theme=randomBattleTheme
        if not (theme and themeAvailable(theme)) then theme=chooseRandom(game) end
        if theme and themeAvailable(theme) then return theme.song end
      elseif kind=="result" then
        randomBattleTheme=nil
      else
        -- map/field music means the prior battle lifecycle is over.
        randomBattleTheme=nil
      end
      return selected
    end
    randomBattleTheme=nil
    local theme=BY_ID[mode] or BY_ID.normal
    ensureSongs(game)
    if kind=="battle" and theme and theme.song and themeAvailable(theme) then return theme.song end
    return selected
  end,1200)
  hookInstalled=true;installed=ensureSongs(gameRef) or installed;return installed
end
function M.attachGame(game) gameRef=game or gameRef;return ensureSongs(gameRef) end
function M.getMode(game) return settings(game or gameRef).music end
function M.setMode(game,mode)
  game=game or gameRef;local s=settings(game);if BY_ID[mode] then s.music=mode end;randomBattleTheme=nil;ensureSongs(game);return s.music
end
function M.resetRuntime()
  randomBattleTheme=nil
  missingWarned={}
  fileDataCache={}
  if gameRef then ensureSongs(gameRef) end
  return true
end
function M.status()
  local list={};local available=0
  for _,t in ipairs(THEMES) do
    local ready=themeAvailable(t);if ready then available=available+1 end
    list[#list+1]={id=t.id,label=t.label,sequence=t.seq,song=t.song,available=ready}
  end
  return {installed=installed,hookInstalled=hookInstalled,availableThemes=available,totalThemes=#THEMES,mode=M.getMode(gameRef),modeLabel=M.themeLabel(gameRef),themeOptions=M.themeOptions(gameRef),themes=list,randomChoice=randomBattleTheme and randomBattleTheme.id or nil,renderer="CBE generated-audio cache / MusyX source compiler (optional/fail-open)",sourceGroup="snd_music"}
end
return M
