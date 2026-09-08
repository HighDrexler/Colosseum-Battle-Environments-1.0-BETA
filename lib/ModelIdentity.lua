-- Read-only National Dex and colour identity, shared by battle/cache consumers.
local V=...
local M={version=1}
function M.resolve(game,battler)
  if type(battler)~="table" then return nil,"Pokemon identity unavailable" end
  local mon=type(battler.mon)=="table" and battler.mon or battler
  local species=mon.species or mon.id
  local defs=game and game.data and game.data.pokemon
  local def=defs and (defs[species] or defs[tostring(species)])
  local dex=tonumber(def and (def.dex or def.index or def.number))
    or tonumber(mon.dex or mon.speciesIndex or mon.nationalDex)
  if not dex and type(species)=="number" then dex=species end
  if not dex and defs and species then
    local wanted=tostring(species):upper()
    for _,candidate in pairs(defs) do
      if type(candidate)=="table" and (tostring(candidate.id):upper()==wanted
          or tostring(candidate.name):upper()==wanted) then
        dex=tonumber(candidate.dex or candidate.index or candidate.number);break
      end
    end
  end
  if not dex or dex%1~=0 or dex<1 or dex>251 then
    return nil,"No supported National Dex mapping for "..tostring(species)
  end
  return dex,V.ShinySupport.variant(battler)
end
return M
