local V = ...
local GeneratedAssets=V.GeneratedAssets
local T = {}

local STYLE_ID = "colosseum_pokeball"
local SFX_ID = "COLOSSEUM_ENV_BATTLE_TRANSITION"
-- 1.4.8 uses only the actual distortion/entry cue from the supplied Colosseum
-- reference (source-video 1.757s..2.435s). 1.4.6 accidentally cut the tail of
-- the full clip instead, which is a different sound. The source-cache DSP
-- sample is deliberately NOT a runtime fallback: it is one sample used by the
-- MusyX macro, not the complete battle-entry cue, and substituting it is the
-- "wrong blip" regression this pass removes.
local REFERENCE_SFX_ASSET = "assets/audio/colosseum_battle_entry_sting.wav"
local MASK_A = "assets/transition/wipe_ball00.rgba"
local MASK_B = "assets/transition/wipe_ball01.rgba"
local WIPE_SECONDS = 0.62
local BLACK_HOLD_SECONDS = 0.0
local REFERENCE_SFX_SECONDS = 0.678
local installed = false
local rendererPatched = false
local clockPatched = false
local masks = {}
local sfxRegistered = false
local gen2Patched = false
local screenEventInstalled = false
local lastSoundAt = -1000
local gen2LiveAttachLogged = false

local function clamp(v,a,b)
  if v<a then return a elseif v>b then return b else return v end
end
local function smooth(v)
  v=clamp(v,0,1)
  return v*v*(3-2*v)
end
local function log(mod,level,msg)
  local l=mod and mod.log
  if l and type(l[level])=="function" then pcall(l[level],l,msg) end
end
local function exists(_,asset) return GeneratedAssets.exists(asset) end
local function transitionAssetsAvailable(mod)
  return exists(mod,MASK_A) and exists(mod,MASK_B)
end

local function shouldOwnTransition(mod,game)
  if not transitionAssetsAvailable(mod) then return false end
  local catalog=V and V.ArenaCatalog
  if catalog and type(catalog.enabled)=="function" then
    local ok,on=pcall(catalog.enabled,game)
    if ok and not on then return false end
  end
  return true
end

-- The shared transition.style hook is consumed by both engines, but only Gen 1
-- understands CBE's registry style id. Gold owns a separate transition state
-- whose stock style must remain spin/speckle/zoom/sine so its lifecycle stays
-- valid; CBE replaces only that live state's presentation.
local function isGen2Transition(game,ctx)
  local audio=game and game.data and game.data.audio
  if type(audio)=="table" and tonumber(audio.generation)==2 then return true end
  -- Gen 2's hook context carries these raw selector inputs; Gen 1's does not.
  if type(ctx)=="table" and (ctx.environment~=nil or ctx.playerLevel~=nil or ctx.enemyLevel~=nil) then
    return true
  end
  return false
end
local transitionSource=nil
local transitionSourceAsset=nil

local function now()
  if love and love.timer and love.timer.getTime then
    local ok,t=pcall(love.timer.getTime)
    if ok and type(t)=="number" then return t end
  end
  return os.clock()
end

local function fileDataFromBytes(bytes,name)
  if type(bytes)~="string" or #bytes<44 then return nil end
  if not (love and love.filesystem and love.filesystem.newFileData) then return nil end
  local ok,fd=pcall(love.filesystem.newFileData,bytes,name)
  return ok and fd or nil
end

local function loadTransitionSource()
  if transitionSource then return transitionSource end
  if not (love and love.audio and love.audio.newSource) then return nil end

  -- Exact parity target: the transition-only section of the supplied source
  -- reference. Do not substitute the generated DSP cache sample here: that
  -- sample is only one component of the original MusyX SFX macro and audibly
  -- produces the wrong short blip on its own.
  local bytes=GeneratedAssets.packageRead(REFERENCE_SFX_ASSET)
  local fd=fileDataFromBytes(bytes,"colosseum_battle_entry_sting.wav")
  transitionSourceAsset=fd and REFERENCE_SFX_ASSET or nil
  if not fd then return nil end

  local ok,src=pcall(love.audio.newSource,fd,"static")
  if not ok or not src then return nil end
  transitionSource=src
  sfxRegistered=true
  return src
end

local function playStartSound(state)
  local t=now()
  if state and state.__colosseumTransitionSound then return end
  if state then state.__colosseumTransitionSound=true end

  -- Gen 1's registered draw and Gen 2's constructor/screen.pushed bridge are
  -- deliberately redundant entry seams. Never double-trigger the cue.
  if t-lastSoundAt<0.20 then return end
  lastSoundAt=t

  -- This is a one-shot presentation SFX only. CBE must never touch the
  -- engine's music volume/state here: Gen1Recomp owns battle-theme start,
  -- victory flow, and post-battle map restoration.
  local src=loadTransitionSource()
  if not src then return end
  pcall(src.stop,src)
  pcall(src.setLooping,src,false)
  pcall(src.seek,src,0)
  pcall(src.play,src)
end

local function loadMask(mod,path)
  local hit=masks[path]
  if hit~=nil then return hit or nil end
  if not (love and love.image and love.image.newImageData and love.graphics and love.graphics.newImage) then
    masks[path]=false
    return nil
  end
  local bytes=GeneratedAssets.read(path)
  if not bytes then masks[path]=false return nil end
  local ok,data=pcall(love.image.newImageData,256,256,"rgba8",bytes)
  if not ok then masks[path]=false return nil end
  local ok2,img=pcall(love.graphics.newImage,data)
  if not ok2 then masks[path]=false return nil end
  pcall(img.setFilter,img,"linear","linear")
  masks[path]=img
  return img
end

local function drawMask(img,cx,cy,size,rot,alpha)
  if not img or size<=0 or alpha<=0 then return end
  local s=size/256
  love.graphics.setColor(0,0,0,alpha)
  love.graphics.draw(img,cx,cy,rot,s,s,128,128)
end

-- A restrained two-stage version of Colosseum's source Pokeball mask. The
-- old seven-ball fan sprayed enormous mask cards across the screen and looked
-- especially rough when GAME SPEED caused frames to be skipped. This keeps one
-- visual focal point and lets the final blackout do the actual coverage.
local function drawFull(mod,wipe,ww,wh)
  if not wipe or not wipe.prog or wipe.prog<=0 then return end
  local p=clamp(wipe.prog,0,1)
  local a=loadMask(mod,MASK_A)
  local b=loadMask(mod,MASK_B)

  if not (a or b) then
    love.graphics.setColor(0,0,0,smooth((p-0.20)/0.80))
    love.graphics.rectangle("fill",0,0,ww,wh)
    love.graphics.setColor(1,1,1,1)
    return
  end

  local cx,cy=ww*0.5,wh*0.5
  local minDim=math.min(ww,wh)

  -- The first source mask appears quickly as a readable Pokeball emblem.
  local q1=smooth(p/0.40)
  if q1>0 then
    local size=minDim*(0.045+0.43*q1)
    drawMask(a or b,cx,cy,size,(1-q1)*-0.18,0.98)
  end

  -- The second mask grows through the first and becomes the actual wipe. It
  -- intentionally does not have to cover every pixel; the black resolve below
  -- removes enlarged-mask striping before it can dominate the image.
  local q2=smooth((p-0.18)/0.58)
  if q2>0 then
    local size=minDim*(0.12+1.18*q2)
    drawMask(b or a,cx,cy,size,(1-q2)*0.13,0.98)
  end

  -- Resolve cleanly to black. Starting this while the large Pokeball is still
  -- readable hides source-mask aliasing on 1440p/4K and guarantees ultrawide
  -- coverage without spawning more giant mask copies.
  local veil=smooth((p-0.56)/0.38)
  if veil>0 then
    love.graphics.setColor(0,0,0,veil)
    love.graphics.rectangle("fill",0,0,ww,wh)
  end
  if p>=0.985 then
    love.graphics.setColor(0,0,0,1)
    love.graphics.rectangle("fill",0,0,ww,wh)
  end
  love.graphics.setColor(1,1,1,1)
end

local function patchRenderer(mod)
  local ok,Renderer=pcall(require,"src.render.Renderer")
  if not ok or not Renderer or type(Renderer.drawBattleWipe)~="function" then return false end
  Renderer.__colosseumBattleWipes=Renderer.__colosseumBattleWipes or {}
  Renderer.__colosseumBattleWipes[STYLE_ID]=function(wipe,ww,wh)
    return drawFull(mod,wipe,ww,wh)
  end
  if not Renderer.__colosseumBattleWipeDispatcher then
    Renderer.__colosseumBattleWipeDispatcher=true
    local original=Renderer.drawBattleWipe
    Renderer.drawBattleWipe=function(self,wipe,ww,wh,ox,oy,vpw,vph,sx,sy)
      local dispatch=Renderer.__colosseumBattleWipes
      local fn=wipe and dispatch and dispatch[wipe.style]
      if fn then return fn(wipe,ww,wh,ox,oy,vpw,vph,sx,sy) end
      return original(self,wipe,ww,wh,ox,oy,vpw,vph,sx,sy)
    end
  end
  rendererPatched=true
  return true
end

-- Gen1Recomp's stock battle transition advances one tick per simulation
-- update. GAME SPEED can run several updates between rendered frames, which is
-- correct for Game Boy wipes but turns a high-resolution custom wipe into a
-- slideshow. Only our style is diverted to wall-clock time; every native and
-- third-party transition keeps the engine's original update path untouched.
local function patchClock(mod)
  local ok,BattleTransition=pcall(require,"src.render.BattleTransition")
  if not ok or not BattleTransition or type(BattleTransition.update)~="function" then return false end
  if not BattleTransition.__colosseumRealTimeOriginal then
    BattleTransition.__colosseumRealTimeOriginal=BattleTransition.update
    BattleTransition.update=function(self,dt)
      if self.style~=STYLE_ID then
        return BattleTransition.__colosseumRealTimeOriginal(self,dt)
      end
      local t=now()
      if not self.__colosseumRealStart then self.__colosseumRealStart=t end
      local elapsed=math.max(0,t-self.__colosseumRealStart)
      local len=math.max(1,tonumber(self.wipeLen) or 60)
      self.phase="wipe"
      self.t=math.min(len,(elapsed/WIPE_SECONDS)*len)
      if elapsed>=WIPE_SECONDS+BLACK_HOLD_SECONDS and not self.__colosseumDone then
        self.__colosseumDone=true
        self.game.stack:pop()
        if self.onDone then self.onDone() end
      end
    end
  end
  clockPatched=true
  return true
end

-- Gold/Silver/Crystal own a separate transition screen and can also have that
-- screen replaced by another UI mod through the shared Screens registry.  A
-- class-only monkey-patch therefore is not sufficient: if the registry hands
-- Gold a different factory, the builtin table CBE patched never executes.
--
-- The authoritative seam is the *instance* after it is pushed.  Every screen
-- produced by Screens.push is stamped with screenId before StateStack emits
-- screen.pushed, including third-party replacements.  Decorating that live
-- instance preserves all other Gen 2/UI compatibility while guaranteeing the
-- same CBE wipe is what the player actually sees.
local function decorateGen2State(mod,state)
  if type(state)~="table" then return false end
  if state.__cbeGen2TransitionDecorated then
    playStartSound(state)
    return true
  end
  local game=state.game or (V and V.mod and V.mod.game) or (mod and mod.game)
  if not shouldOwnTransition(mod,game) then return false end

  state.__cbeGen2TransitionDecorated=true
  state.__cbeOriginalUpdate=state.update
  state.__cbeOriginalDraw=state.draw
  state.__cbeOriginalDrawWidescreen=state.drawWidescreen
  state.__cbeOriginalDrawsWidescreen=state.drawsWidescreen
  state.__cbePresentationStyle=STYLE_ID
  -- Gold's BattleTransition is intentionally transparent over the live world.
  -- Keep that invariant even if a registry replacement forgot to declare it.
  state.isOpaque=false
  state.__cbeRealStart=now()
  state.__cbeProgress=0

  -- Keep the screen's original lifecycle/update semantics. This preserves the
  -- stock pop/onDone behavior and any registry replacement's callback timing;
  -- CBE owns only the visible transition layer.
  local originalUpdate=state.__cbeOriginalUpdate
  state.update=function(self,dt)
    local elapsed=math.max(0,now()-(self.__cbeRealStart or now()))
    self.__cbeProgress=clamp(elapsed/WIPE_SECONDS,0,1)
    -- The stock Gold transition has a public finish() that performs its own
    -- pop + onDone exactly once. Once the CBE wipe and final resolve are
    -- complete, use that native exit instead of sitting on a black frame while
    -- Gold's hidden flash/outro counters continue for another second. Registry
    -- replacement screens keep their original lifecycle unless they were built
    -- by the stock class wrapper below.
    if self.__cbeStockGen2Transition
        and elapsed>=WIPE_SECONDS+BLACK_HOLD_SECONDS
        and not self.__cbeFinishRequested
        and type(self.finish)=="function" then
      self.__cbeFinishRequested=true
      return self:finish()
    end
    if type(originalUpdate)=="function" then
      return originalUpdate(self,dt)
    end
  end

  -- Contained fallback: Game2 has already painted the overworld before it
  -- draws a transparent stack state, so only the CBE mask belongs here.
  state.draw=function(self,...)
    return drawFull(mod,{prog=self.__cbeProgress or 0},160,144)
  end

  -- THIS is the Gen 2 bug fixed in 1.4.8. Game2 gives a widescreen transition
  -- state ownership of the entire frame and therefore does NOT draw the world
  -- for it first. 1.4.5-1.4.7 replaced Gold's drawWidescreen with the black
  -- CBE mask alone, making the Pokeball black-on-black/invisible. Repaint the
  -- frozen live world exactly as Gold's stock transition does, then overlay
  -- the same CBE mask Gen 1 uses.
  state.drawWidescreen=function(self,w,h,...)
    local world=self.world
    if world and type(world.draw)=="function" then
      world:draw()
    elseif type(self.__cbeOriginalDrawWidescreen)=="function" then
      -- Compatibility fallback for a third-party transition screen that owns
      -- its own background instead of exposing `world`.
      self.__cbeOriginalDrawWidescreen(self,w,h,...)
    end
    return drawFull(mod,{prog=self.__cbeProgress or 0},w,h)
  end
  state.drawsWidescreen=function() return true end
  state.wantsFillScale=function() return true end

  playStartSound(state)
  if not gen2LiveAttachLogged then
    gen2LiveAttachLogged=true
    log(mod,"info","CBE attached Pokeball presentation to live Gen2BattleTransition")
  end
  return true
end

local function patchGen2(mod)
  local req=(V and V.engineRequire) or require
  local ok,BattleTransition=pcall(req,"src.ui.gen2.BattleTransition")
  if not ok or type(BattleTransition)~="table" or type(BattleTransition.new)~="function" then
    log(mod,"warn","Gen 2 Colosseum battle transition class unavailable; screen.pushed bridge remains active")
    return false
  end

  -- Keep the direct class path for the stock engine and for test drivers that
  -- instantiate BattleTransition.new directly instead of using Screens.push.
  if not BattleTransition.__cbeOriginalNew then
    BattleTransition.__cbeOriginalNew=BattleTransition.new
    BattleTransition.new=function(game,opts)
      local state=BattleTransition.__cbeOriginalNew(game,opts)
      if type(state)=="table" then state.__cbeStockGen2Transition=true end
      decorateGen2State(mod,state)
      return state
    end
  end
  -- Do NOT add STYLE_ID to Gold's STYLES table. Gold's update state machine
  -- only implements spin/speckle/zoom/sine; accepting a foreign style id makes
  -- its outro fall into the wrong branch. The live-state decorator supplies
  -- CBE's visuals while the native style remains intact.
  gen2Patched=true
  return true
end

local function installScreenEventBridge(mod)
  if screenEventInstalled then return true end
  local events=mod and mod.events
  if not (events and type(events.on)=="function") then return false end
  events:on("screen.pushed",function(payload)
    local state=type(payload)=="table" and payload.state or nil
    if type(state)~="table" then return end

    -- Screens.push stamps this id on both the builtin Gold transition and any
    -- registry replacement before screen.pushed fires.
    if state.screenId=="Gen2BattleTransition" then
      decorateGen2State(mod,state)
      return
    end

    -- Gen 1's transition is not necessarily constructed through Screens, but
    -- when another mod does route it through the stack event this gives the
    -- start cue the same reliable early seam without changing its renderer.
    if state.style==STYLE_ID then playStartSound(state) end
  end)
  screenEventInstalled=true
  return true
end

function T.install(mod)
  -- Patch both generation render paths up front. GenerationCompat can be queried
  -- before GameVersion has finished switching to Gold/Silver, so deciding which
  -- patch to install from one cached generation value caused the Gen 2 wipe to
  -- disappear while the rest of CBE still worked. Both patches are inert unless
  -- their own transition class/style is active.
  patchRenderer(mod)
  patchClock(mod)
  patchGen2(mod)
  installScreenEventBridge(mod)

  if installed then return true end

  -- Gen 1 transition registry. Gen 2 ignores this registry, but registering it
  -- when present is harmless and keeps one installation path for both games.
  local transition=mod and mod.content and mod.content.transitions
  if transition and type(transition.register)=="function" then
    local okReg,errReg=pcall(transition.register,transition,STYLE_ID,{
      frames=60,
      draw=function(state,prog)
        playStartSound(state)
        local r=state and state.game and state.game.renderer
        if r then
          patchRenderer(mod); patchClock(mod)
          r.battleWipe={style=STYLE_ID,prog=prog}
          return
        end
        if love and love.graphics then
          love.graphics.setColor(0,0,0,smooth((prog-0.28)/0.72))
          love.graphics.rectangle("fill",0,0,160,144)
          love.graphics.setColor(1,1,1,1)
        end
      end,
    })
    if not okReg then
      log(mod,"warn","Colosseum Gen 1 battle transition registration failed: "..tostring(errReg))
    end
  end

  -- Shared style hook. Gen 1 consumes CBE's registered style here. Gold also
  -- calls this hook, but must keep its native spin/speckle/zoom/sine style; the
  -- live Gen2BattleTransition decorator above owns only its visible presentation.
  if mod.hooks and type(mod.hooks.wrap)=="function" then
    mod.hooks:wrap("transition.style",function(next,ctx)
      local prior=next(ctx)
      local game=(ctx and (ctx.game or (ctx.state and ctx.state.game))) or (V and V.mod and V.mod.game)
      if not shouldOwnTransition(mod,game) then return prior end
      -- Gold must keep its native internal style so its own update/finish state
      -- remains valid. The live Gen2BattleTransition instance is decorated by
      -- patchGen2/screen.pushed instead. Gen 1 continues to consume CBE's
      -- registered style normally.
      if isGen2Transition(game,ctx) then return prior end
      return STYLE_ID
    end,1200)
  end

  installed=true
  log(mod,"info","Colosseum Pokeball battle entry active on Gen 1 + Gen 2; Gold world-backed live-screen bridge enabled")
  return true
end

function T.resetRuntime()
  masks={}
  transitionSource=nil
  transitionSourceAsset=nil
  sfxRegistered=false
  lastSoundAt=-1000
  gen2LiveAttachLogged=false
  return true
end

function T.status()
  return {
    installed=installed,
    rendererPatched=rendererPatched,
    clockPatched=clockPatched,
    gen2Patched=gen2Patched,
    screenEventInstalled=screenEventInstalled,
    style=STYLE_ID,
    realTime=true,
    wipeSeconds=WIPE_SECONDS,
    blackHoldSeconds=BLACK_HOLD_SECONDS,
    startSfx=sfxRegistered and SFX_ID or false,
    startAsset=transitionSourceAsset or REFERENCE_SFX_ASSET,
    referenceAsset=REFERENCE_SFX_ASSET,
    referenceSfxSeconds=REFERENCE_SFX_SECONDS,
    musicDuckedDuringWipe=false,
    generatedFallbackAsset=false,
    maskA=MASK_A,
    maskB=MASK_B,
  }
end

return T
