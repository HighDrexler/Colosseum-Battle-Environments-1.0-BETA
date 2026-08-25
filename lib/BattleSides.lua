local S={}

function S.value(value)
  if value==nil then return nil end
  if type(value)=="string" then
    local key=value:lower()
    if key=="player" or key=="ally" or key=="friendly" or key=="p1" then return "player" end
    if key=="enemy" or key=="opponent" or key=="foe" or key=="p2" then return "enemy" end
    local n=tonumber(value)
    if n==1 then return "player" elseif n==2 then return "enemy" end
    return nil
  end
  if type(value)=="number" then
    if value==1 then return "player" elseif value==2 then return "enemy" end
    return nil
  end
  if type(value)=="table" then
    if type(value.isPlayer)=="boolean" then return value.isPlayer and "player" or "enemy" end
    for _,key in ipairs({"side","index","id","name","team","ownerSide"}) do
      local resolved=S.value(value[key])
      if resolved then return resolved end
    end
  end
  return nil
end

function S.object(ctx,obj)
  if not obj then return nil end
  local explicit=S.value(obj)
  if explicit then return explicit end
  local battle=type(ctx)=="table" and (ctx.battle or (ctx.kind and ctx)) or nil
  if battle then
    if obj==battle.player then return "player" end
    if obj==battle.enemy then return "enemy" end
    if battle.player and obj==battle.player.mon then return "player" end
    if battle.enemy and obj==battle.enemy.mon then return "enemy" end
    local model=battle._model
    if model and obj==model.player then return "player" end
    if model and obj==model.enemy then return "enemy" end
  end
  return nil
end

function S.payload(ctx,payload,fields)
  if type(payload)~="table" then return nil end
  for _,key in ipairs(fields or {}) do
    local resolved=S.object(ctx,payload[key])
    if resolved then return resolved end
  end
  return nil
end

function S.other(side)
  if side=="player" then return "enemy" end
  if side=="enemy" then return "player" end
  return nil
end

return S
