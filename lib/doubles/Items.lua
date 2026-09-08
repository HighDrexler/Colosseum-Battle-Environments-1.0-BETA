-- Native item arithmetic, with the doubles scheduler owning turns and stock.
local V=... or {};local req=V.engineRequire or require
local I={version=1}
local function clone(t,seen)
 if type(t)~='table' then return t end
 seen=seen or {};if seen[t] then return seen[t] end
 local out={};seen[t]=out;for k,v in pairs(t)do out[k]=clone(v,seen)end;return out
end
local battleItems={X_ATTACK=true,X_DEFEND=true,X_DEFENSE=true,X_SPEED=true,X_SPECIAL=true,X_SP_ATK=true,X_ACCURACY=true,DIRE_HIT=true,GUARD_SPEC=true}
local ppItems={ETHER=true,MAX_ETHER=true,ELIXER=true,MAX_ELIXER=true,MYSTERYBERRY=true}
local fullMask={FULL_HEAL=true,FULL_RESTORE=true,HEAL_POWDER=true,MIRACLEBERRY=true}
local function effects(a)return req(a.generation==2 and 'src.core.gen2.ItemEffects' or 'src.inventory.ItemEffects')end
function I.save(a)return a.host.save or (a.host.game and a.host.game.save)end
function I.classify(a,id)
 if type(id)~='string' or not (a.data.items and a.data.items[id]) then return nil end
 local E=effects(a)
 if battleItems[id] then
  if a.generation==2 and not (a.native.X_ITEMS[id] or a.native.SUBSTATUS_ITEMS[id]) then return nil end
  if a.generation==1 and (id=='X_DEFENSE' or id=='X_SP_ATK') then return nil end
  return 'battle'
 end
 if a.generation==2 then
  local kind=E.partyAction(id,a.data)
  if kind=='heal' or kind=='status' or kind=='revive' or (kind=='pp' and ppItems[id]) then return kind end
 elseif E.isBattleMedicine(id) then return 'medicine'
 elseif ppItems[id] and id~='MYSTERYBERRY' then return 'pp' end
end
function I.available(a,id)
 local save=I.save(a);local n=save and save.inventory and tonumber(save.inventory[id]) or 0
 for _,action in pairs(a.core.commands)do if action.kind=='item' and action.item==id then n=n-1 end end
 return math.max(0,n)
end
function I.apply(a,id,mon,moveIndex,preview)
 local E=effects(a);local kind=I.classify(a,id);local active=a.core:slotFor(mon)
 if not kind then return false,{'This item cannot be used in doubles.'} end
 if not mon or mon.egg or mon.isEgg then return false,{'Choose a Pokemon, not an Egg.'} end
 if kind=='battle' and (not active or active.side~='player' or mon.hp<=0) then return false,{'Choose an active Pokemon.'} end
 if kind=='pp' and id~='ELIXER' and id~='MAX_ELIXER' then
  if type(moveIndex)~='number' or moveIndex%1~=0 or not (mon.moves and mon.moves[moveIndex]) then return false,{'Choose a move to restore.'} end
 end
 -- A native item may inspect the non-user (Gen I's status-stat behaviour).
 -- Never alias that battler to the item recipient or provide an empty record.
 local opponent
 if active then
  local foes=a.core:aliveSlots(active.side=='player' and 'enemy' or 'player')
  opponent=foes[1]
 end
 local target=preview and clone(mon) or mon
 if a.generation==2 then
  if kind=='battle' then
   if preview then
    local field=a.native.SUBSTATUS_ITEMS[id]
    if field and mon.volatile and mon.volatile[field] then return false,{'It will not have any effect.'}end
    return true,{}
   end
   a:bind(active,opponent or active)
   return a.k:useBattleItem(id),{}
  end
  local result=kind=='pp' and E.usePpItem(id,target,moveIndex,a.data) or E.useOnMon(id,target,a.data)
  if active and fullMask[id] then
   local volatile=mon.volatile or {}
   if volatile.confuseCount then
    if not preview then volatile.confuseCount=nil end
    if not result.used then result={used=true,text=a:name(mon)..' came to its senses.'}end
   end
  end
  return result.used==true,{result.text}
 end
 local save=I.save(a);local kernel=a.k
 if preview then
  save={player=clone(save.player),party={target},inventory={}}
  local battler=active and clone(active.battler) or nil
  if battler then battler.mon=target end
  kernel={player=battler,enemy=opponent and clone(opponent.battler) or nil,
   ruleset=clone(a.k.ruleset),kind='trainer',participants={}}
 else
  if active then a:bind(active,opponent or active)end
 end
 local result,messages=E.use(a.data,save,id,target,kernel,moveIndex)
 if result=='consumed' and not preview and active and active.battler.curMoves then
  for i,m in ipairs(mon.moves or {})do
   local current=active.battler.curMoves[i]
   if current and current.id==m.id then current.pp=m.pp end
  end
 end
 return result=='consumed',messages or {}
end
function I.validate(a,request,executing)
 local kind=I.classify(a,request.item)
 if not kind then return false,'This item cannot be used in doubles.' end
 local save=I.save(a);local inventory=save and save.inventory or {}
 local count=executing and (tonumber(inventory[request.item]) or 0) or I.available(a,request.item)
 if count<1 then return false,'No unreserved copies of this item remain.' end
 local index=request.partyIndex
 if type(index)~='number' or index%1~=0 then return false,'Choose a party Pokemon.' end
 local mon=a.core.playerParty[index]
 if not mon or (request.targetMon and mon~=request.targetMon) then return false,'Item target changed.' end
 local ok,messages=I.apply(a,request.item,mon,request.moveIndex,true)
 return ok,ok and nil or (messages[1] or 'It will not have any effect.'),mon
end
function I.perform(a,action)
 local ok,why,mon=I.validate(a,action,true)
 if not ok then a:message(why);return false end
 local used,messages=I.apply(a,action.item,mon,action.moveIndex,false)
 if used then
  local inventory=I.save(a).inventory
  inventory[action.item]=inventory[action.item]-1
  if inventory[action.item]<=0 then inventory[action.item]=nil end
  a:message('Used '..(a.data.items[action.item].name or action.item)..' on '..a:name(mon)..'.')
 end
 for _,text in ipairs(messages)do a:message(text)end
 return used
end
function I.snapshot(a)
 local rows={};local save=I.save(a)
 for id,count in pairs(save and save.inventory or {})do
  local kind=I.classify(a,id)
  if kind and count>0 then rows[#rows+1]={id=id,name=a.data.items[id].name or id,count=count,available=I.available(a,id),target=kind=='battle' and 'active-player' or 'party',moveRequired=kind=='pp' and id~='ELIXER' and id~='MAX_ELIXER'}end
 end
 table.sort(rows,function(x,y)return x.id<y.id end);return rows
end
return I
