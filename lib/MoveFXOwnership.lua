local V=...
local Compat=V.GenerationCompat
local MoveFX=V.MoveFXExtractor
local MoveFXVM=V.MoveFXVM
local WazaSequence=V.WazaSequenceRuntime

-- CBE move-FX ownership gate.
--
-- The engine must still RUN its native animation scripts because they carry
-- battle pacing / queue timing / SFX.  When CBE has a real Colosseum WZX bank,
-- however, the Game Boy/GBC visual layer must not be composited over the 3D
-- arena.  This module suppresses only the native visual presentation while the
-- mapped move's stock script continues to advance normally underneath.
local O={
  installed=false,activeBattle=nil,active=nil,capture=nil,last=nil,
  gen1View=nil,gen2View=nil,gen2AnimView=nil,
  gen1AnimWrapper=nil,gen1EffectWrapper=nil,presentWrapper=nil,objectsWrapper=nil,stepWrapper=nil,queueWrapper=nil,
  suppressions=0,failOpen=0,error=nil,
}

local function prepare(value)
  return Compat and Compat.prepare(value) or value
end
local function matches(a,b)
  return (Compat and Compat.matches and Compat.matches(a,b)) or a==b
end
local function battleOf(ctx,payload)
  local b=type(payload)=="table" and payload.battle or nil
  if not b and type(ctx)=="table" then b=ctx.battle or (ctx.kind and ctx) end
  return prepare(b)
end
local function cbeOwnsWorld(battle)
  local host=V and V.StandaloneHost
  if host and type(host.status)=="function" then
    local ok,st=pcall(host.status)
    if ok and type(st)=="table" and st.active==true then return true end
  end
  local bridge=V and V.StadiumBridge
  if bridge and type(bridge.ownsArena)=="function" then
    local ok,v=pcall(bridge.ownsArena,battle)
    if ok and v==true then return true end
  end
  return false
end
local function moveParts(payload)
  payload=type(payload)=="table" and payload or {}
  local move=type(payload.move)=="table" and payload.move
    or type(payload.moveDef)=="table" and payload.moveDef
    or type(payload.definition)=="table" and payload.definition or nil
  local id=payload.moveId or payload.index or payload.moveIndex or payload.id
  if id==nil and type(payload.move)~="table" then id=payload.move end
  if id==nil and move then id=move.index or move.moveId or move.id or move.name end
  return id,move
end
local function specReady(spec)
  if type(spec)~="table" then return false end
  -- 1.6 ownership is decided by the same first-class Waza scheduler that will
  -- present the move. Today the scheduler can claim a move when at least one
  -- typed Waza particle/effect entry resolves to an executable GPT1 root. As
  -- model/camera handlers mature they can extend canOwn() without changing the
  -- engine interception contract.
  if WazaSequence and type(WazaSequence.canOwn)=="function" then
    local ok,owns=pcall(WazaSequence.canOwn,WazaSequence,spec)
    if ok and owns then return true end
  end
  if not (type(spec.textures)=="table" and #spec.textures>0
      and type(spec.generatorPrograms)=="table" and #spec.generatorPrograms>0
      and MoveFXVM and type(MoveFXVM.hasRole)=="function") then return false end
  return MoveFXVM.hasRole(spec,"attack") or MoveFXVM.hasRole(spec,"damage")
end
local function readySpec(id,move)
  if not MoveFX then return nil,"move FX extractor unavailable" end
  local lastErr="source WZX unavailable"
  if type(MoveFX.peek)=="function" then
    local ok,spec,err=pcall(MoveFX.peek,id,move)
    if ok and specReady(spec) then return spec end
    lastErr=tostring(err or spec or lastErr)
  end
  -- Never extract from the source disc on a visible move boundary. Recent
  -- fidelity builds did this synchronously and the renderer sat on a black or
  -- stale frame until WZX decode/cache serialization finished. Queue the bank
  -- for later preparation instead. The native script still supplies timing and
  -- unsuppressed audio, but its Crystal/GB visual layer remains hidden while CBE
  -- owns the arena so a source-cache failure cannot masquerade as source FX.
  if type(MoveFX.queuePrefetch)=="function" then
    pcall(MoveFX.queuePrefetch,id,move,O.activeBattle)
    lastErr="source WZX queued; cache not ready on presentation boundary"
  end
  return nil,lastErr
end
local function clear(reason)
  if O.active then O.last={moveId=O.active.moveId,reason=reason or "clear",stem=O.active.stem} end
  O.active=nil
end

function O:begin(ctx)
  self.activeBattle=battleOf(ctx)
  self.capture=nil
  clear("battle-begin")
end
function O:finish(ctx,reason)
  local b=battleOf(ctx)
  if not b or not self.activeBattle or matches(self.activeBattle,b) then
    clear(reason or "battle-finish")
    self.capture=nil
    self.activeBattle=nil
  end
end

function O:event(ctx,name,payload)
  local b=battleOf(ctx,payload)
  if b and self.activeBattle and not matches(self.activeBattle,b) then return false end
  if b and not self.activeBattle then self.activeBattle=b end

  -- Gen 2 resolves semantic move events before the battle screen replays its
  -- visible queue. StandaloneHost synthesizes battle.presentation_move at the
  -- actual on-screen boundary; never arm visual suppression from the early
  -- pure-model event or we can blank unrelated animation frames.
  if b and b.__cbeGeneration==2 and name=="battle.move_used" then
    return false
  end

  if name=="battle.ball_thrown" then
    if not cbeOwnsWorld(b or self.activeBattle) then return false end
    self.capture={battle=b or self.activeBattle,caught=type(payload)=="table" and payload.caught==true or false,
      shakes=type(payload)=="table" and tonumber(payload.shakes) or 0,ball=type(payload)=="table" and payload.ball or nil}
    self.suppressions=self.suppressions+1
    return true
  end
  if name=="battle.turn_ended" or name=="battle.ended" then
    self.capture=nil
  end

  local isMove=name=="battle.move_used" or name=="battle.presentation_move"
  if isMove then
    local id,move=moveParts(payload)
    local spec,err=readySpec(id,move)
    if spec then
      if self.active and self.active.stem==spec.stem
          and (not b or not self.active.battle or matches(self.active.battle,b)) then
        return true
      end
      self.active={battle=b or self.activeBattle,moveId=id,move=move,stem=spec.stem,
        spec=spec,source=name,started=true}
      -- Decode the small static source-SE objects at the move boundary rather
      -- than on the exact type-5 Waza frame. This keeps authored sound timing
      -- precise without globally preloading hundreds of WAVs or growing an
      -- unbounded audio working set. Missing/incomplete source audio remains a
      -- no-op here and therefore still fails open to the native move SFX.
      local audio=V and V.WazaAudioRuntime
      if audio and type(audio.prewarmSpec)=="function" then pcall(audio.prewarmSpec,spec) end
      self.suppressions=self.suppressions+1
      self.error=nil
      return true
    end
    -- Keep native timing/audio alive, but do not restore native visuals inside
    -- a CBE arena. A missing source Waza remains an explicit source-runtime
    -- failure instead of silently presenting Crystal/GB move art.
    clear("unmapped-or-unready")
    self.failOpen=self.failOpen+1
    self.error=err
    return false
  end
  if name=="battle.turn_ended" or name=="battle.ended" then clear(name) end
  return self.active~=nil
end

function O:ownsNativeAudio(battle)
  if not self.active then return false end
  local b=prepare(battle)
  if self.active.battle and b and not matches(self.active.battle,b) then return false end
  local audio=V and V.WazaAudioRuntime
  local readyFn=audio and (audio.readyForSpec or audio.prewarmSpec)
  if type(readyFn)~="function" then return false end
  local ok,complete=pcall(readyFn,self.active.spec)
  return ok and complete==true
end

function O:suppresses(battle)
  if not self.active then return false end
  local b=prepare(battle)
  if self.active.battle and b and not matches(self.active.battle,b) then return false end
  return true
end

function O:suppressesCapture(battle)
  if not self.capture then return false end
  local b=prepare(battle)
  if self.capture.battle and b and not matches(self.capture.battle,b) then return false end
  return true
end

function O:suppressesNativeVisuals(battle)
  -- A CBE arena is a source-only presentation surface. Native Gen1/Gen2
  -- animation scripts still RUN for battle pacing and unsuppressed audio, but
  -- their sprites/palette effects/screen transforms must never composite over
  -- the Colosseum world. 1.7.12/1.7.13 exposed Crystal/GB visuals whenever a
  -- Waza failed to arm, which hid the actual source-runtime regression.
  if cbeOwnsWorld(prepare(battle)) then return true end
  return self:suppressesCapture(battle) or self:suppresses(battle)
end

local BALL_ANIMS={
  TOSS_ANIM=true,GREATTOSS_ANIM=true,ULTRATOSS_ANIM=true,BLOCKBALL_ANIM=true,POOF_ANIM=true,
}
local OWNED_MOVE_TAIL_ANIMS={SHAKE_ANIM=true,HIDEPIC_ANIM=true,SHOWPIC_ANIM=true}
local function token(v)
  if v==nil then return nil end
  return tostring(v):upper():gsub("[^A-Z0-9]","")
end
local function activeMoveTokens()
  local out={}
  local a=O.active
  local function add(v) local k=token(v);if k and k~="" then out[k]=true end end
  if not a then return out end
  add(a.moveId)
  local m=a.move
  if type(m)=="table" then add(m.id);add(m.name);add(m.index);add(m.moveId) end
  return out
end
function O:suppressesAnim(battle,animName)
  -- Stock move visuals are timing-only while the CBE compositor owns the
  -- battlefield. A source failure stays visible in CBE diagnostics instead of
  -- silently reverting to Crystal/GB art.
  if cbeOwnsWorld(prepare(battle)) then return true end
  if self:suppressesCapture(battle) then
    if animName==nil then return true end
    local raw=tostring(animName)
    if BALL_ANIMS[raw] or OWNED_MOVE_TAIL_ANIMS[raw] then return true end
    -- Capture ownership is visual-only.  Do not suppress an unrelated move if
    -- a third-party battle implementation overlaps events, but every stock ball
    -- and ball-tail animation is forbidden inside a CBE arena.
    return false
  end
  if not self:suppresses(battle) then return false end
  if animName and BALL_ANIMS[tostring(animName)] then return false end
  if animName==nil then return true end
  local raw=tostring(animName)
  if OWNED_MOVE_TAIL_ANIMS[raw] then return true end
  local k=token(animName);local candidates=activeMoveTokens()
  if candidates[k] then return true end
  -- THRASH is a stock alias used by the Gen1 animation queue while the semantic
  -- move still identifies the source move. Generic SHAKE/HIDEPIC/SHOWPIC rows
  -- are likewise part of the immediate move/damage visual tail when a Waza is
  -- active. Capture toss rows remain exempt above.
  if k=="THRASH" then return true end
  return false
end

local function installGen1()
  local req=V.engineRequire or require
  local okState,BattleState=pcall(req,"src.battle.BattleState")
  if not okState or type(BattleState)~="table" then return false,tostring(BattleState) end
  if type(BattleState.drawAnimLayer)=="function" and BattleState.drawAnimLayer~=O.gen1AnimWrapper then
    local inner=BattleState.drawAnimLayer
    O.gen1AnimWrapper=function(self,colorized,...)
      -- Keep AnimPlayer running for queue timing/SFX, but do not composite its
      -- Game Boy OAM sprites into a Colosseum arena when the source WZX owns
      -- the move. This is the top-right native sprite leak seen in 1.5.40.
      if self.animPlaying and O:suppressesAnim(self,self.animName) then return end
      return inner(self,colorized,...)
    end
    BattleState.drawAnimLayer=O.gen1AnimWrapper
  end
  if type(BattleState.applyAnimEffect)=="function" and BattleState.applyAnimEffect~=O.gen1EffectWrapper then
    local innerEffect=BattleState.applyAnimEffect
    O.gen1EffectWrapper=function(self,ev,...)
      if self.animPlaying and O:suppressesAnim(self,self.animName) then
        -- Gen I's animation player carries two different responsibilities in
        -- the same row stream: pacing/sound, and visual Game Boy screen/pic
        -- effects.  drawAnimLayer suppression only removed OAM sprites; palette
        -- events such as SE_DARK_SCREEN_PALETTE / SE_DARK_SCREEN_FLASH still
        -- reached BattleState.fx and could black/invert the entire 3D arena.
        -- Once a verified Colosseum WazaSequence owns the move, preserve sound
        -- dispatch but quarantine every SE_* native visual. The AnimPlayer
        -- itself continues stepping, so battle timing is unchanged.
        local effect=type(ev)=="table" and tostring(ev.effect or "") or ""
        if effect:match("^SFX_") then return innerEffect(self,ev,...) end
        if type(ev)=="table" and ev.sound and type(self.playAnimSound)=="function" then
          pcall(self.playAnimSound,self,ev.sound)
        end
        return
      end
      return innerEffect(self,ev,...)
    end
    BattleState.applyAnimEffect=O.gen1EffectWrapper
  end
  O.gen1View=BattleState
  return true
end

local function installGen2()
  local req=V.engineRequire or require
  local okView,AnimView=pcall(req,"src.ui.gen2.BattleAnimView")
  local okState,BattleState=pcall(req,"src.ui.gen2.BattleState")
  if not okView or type(AnimView)~="table" then return false,tostring(AnimView) end
  if not okState or type(BattleState)~="table" then return false,tostring(BattleState) end

  if type(AnimView.present)=="function" and AnimView.present~=O.presentWrapper then
    local inner=AnimView.present
    O.presentWrapper=function(self,runner,drawBg,battle)
      if O:suppressesNativeVisuals(battle) then
        -- Keep the untouched battle panel/HUD, but bypass SCX/SCY/BGP effects
        -- from the stock move animation. The runner itself continues stepping.
        if type(drawBg)=="function" then return drawBg() end
        return
      end
      return inner(self,runner,drawBg,battle)
    end
    AnimView.present=O.presentWrapper
  end

  if type(AnimView.drawObjects)=="function" and AnimView.drawObjects~=O.objectsWrapper then
    local inner=AnimView.drawObjects
    O.objectsWrapper=function(self,runner,battle)
      if O:suppressesNativeVisuals(battle) then return end
      return inner(self,runner,battle)
    end
    AnimView.drawObjects=O.objectsWrapper
  end

  -- Hold ownership through the move's immediate wBattleAfterAnim damage shake,
  -- then release as soon as that native visual chain is finished. This avoids
  -- suppressing a later unmapped move in a 4x-speed battle.
  if type(BattleState.stepAnim)=="function" and BattleState.stepAnim~=O.stepWrapper then
    local inner=BattleState.stepAnim
    O.stepWrapper=function(self,...)
      local owned=O:suppresses(self)
      local result=inner(self,...)
      if owned and self.anim==nil and self.pendingAfterAnim==nil then clear("gen2-native-chain-finished") end
      return result
    end
    BattleState.stepAnim=O.stepWrapper
  end

  -- Some moves have no stock animation script (or BATTLE SCENE is disabled).
  -- If advanceQueue does not arm an anim, release immediately after the event.
  if type(BattleState.advanceQueue)=="function" and BattleState.advanceQueue~=O.queueWrapper then
    local inner=BattleState.advanceQueue
    O.queueWrapper=function(self,...)
      local row=self.queue and self.queue[1]
      local wasMove=type(row)=="table" and row.kind=="move" and not row.missed
      -- This is the generation-2 authoritative VISIBLE boundary regardless of
      -- which arena compositor owns the world. Arm ownership here too so CBE
      -- does not depend on StandaloneHost being the active host.
      if wasMove and not O:suppresses(self) then
        O:event({battle=self},"battle.presentation_move",{battle=self,moveId=row.move,move=row.moveDef})
      end
      local result=inner(self,...)
      if wasMove and O:suppresses(self) and self.anim==nil and self.pendingAfterAnim==nil then
        clear("gen2-no-native-script")
      end
      return result
    end
    BattleState.advanceQueue=O.queueWrapper
  end

  O.gen2View=BattleState;O.gen2AnimView=AnimView
  return true
end

function O.install()
  -- Install both presentation intercepts from the mod itself. No Gen1Recomp
  -- source patch is required: wrappers are transparent until a verified WZX
  -- bank owns the active move.
  local ok1,err1=installGen1()
  local ok2,err2=installGen2()
  O.installed=(ok1 or ok2) and true or false
  O.error=O.installed and nil or tostring(err1 or err2)
  return O.installed,O.error
end

function O.status()
  return {installed=O.installed,active=O.active and true or false,capture=O.capture and true or false,
    moveId=O.active and O.active.moveId or nil,stem=O.active and O.active.stem or nil,
    suppressions=O.suppressions,failOpen=O.failOpen,error=O.error,last=O.last,
    sourceAudioComplete=O.active and O:ownsNativeAudio(O.active.battle) or false,
    policy="CBE arena owns all move visuals source-only; native animation scripts remain timing/audio-only; native move SFX suppress only when every type-5 GameSound is cached"}
end
return O
