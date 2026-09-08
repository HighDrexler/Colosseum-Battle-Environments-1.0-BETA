-- Pure presentation identity and Colosseum PKX colour parameters.
-- No shiny rolls, save edits, species palettes or provider overrides.
local S={version=1}
local attackShiny={[2]=true,[3]=true,[6]=true,[7]=true,[10]=true,[11]=true,[14]=true,[15]=true}
function S.isShiny(mon)
  if type(mon)~='table' then return false end
  local rows,seen={mon},{};local i=1;local explicit=false
  while rows[i] and i<=16 do
    local row=rows[i];i=i+1
    if not seen[row] then
      seen[row]=true
      if row.shiny==true or row.isShiny==true then return true end
      if row.shiny==false or row.isShiny==false then explicit=true end
      for _,key in ipairs({'mon','pokemon','partyMon'}) do
        local child=row[key]
        if type(child)=='table' and not seen[child] and #rows<16 then rows[#rows+1]=child end
      end
    end
  end
  -- A resolved explicit flag is authoritative (custom shiny-roll mods included).
  if explicit then return false end
  for _,row in ipairs(rows) do
    local dv=row.dvs or row.DVs
    if type(dv)=='table' and tonumber(dv.defense)==10 and tonumber(dv.speed)==10
      and tonumber(dv.special)==10 and attackShiny[tonumber(dv.attack)] then return true end
  end
  return false
end
function S.variant(mon) return S.isShiny(mon) and 'shiny' or 'normal' end
local function u32(s,o)
  local a,b,c,d=s:byte(o+1,o+4)
  if not d then return nil end
  return ((a*256+b)*256+c)*256+d
end
local function gain(b)
  if b<=127 then return b/127 end
  return 1+(b-127)/128
end
function S.validFilter(f)
  if type(f)~='table' or type(f.route)~='table' or type(f.gain)~='table' then return false end
  for i=1,3 do
    local r,g=f.route[i],f.gain[i]
    if type(r)~='number' or r~=math.floor(r) or r<0 or r>3
      or type(g)~='number' or g~=g or g<0 or g>2 then return false end
  end
  return true
end
-- Retail Colosseum: last 20 bytes, four big-endian channel selectors then ARGB.
-- Bounds must lie AFTER the declared animation metadata, not inside a truncated
-- slot. Routing affects RGB only; transparency remains the original material's.
function S.parseFilter(blob,minimumOffset)
  if type(blob)~='string' then return nil end
  local o=#blob-20
  if o<math.max(0,tonumber(minimumOffset) or 0) then return nil end
  local route={u32(blob,o),u32(blob,o+4),u32(blob,o+8)}
  local a,r,g,b=blob:byte(o+17,o+20)
  if not b then return nil end
  local f={version=1,route=route,gain={gain(r),gain(g),gain(b)},rawARGB={a,r,g,b}}
  return S.validFilter(f) and f or nil
end
function S.filterField(f)
  if not S.validFilter(f) then return '' end
  return ('shinyFilter={version=1,route={%d,%d,%d},gain={%.17g,%.17g,%.17g}},')
    :format(f.route[1],f.route[2],f.route[3],f.gain[1],f.gain[2],f.gain[3])
end
S.identityRows={{1,0,0,0},{0,1,0,0},{0,0,1,0}}
S.identityGain={1,1,1}
function S.uniforms(f)
  if not S.validFilter(f) then return S.identityRows,S.identityGain end
  local rows={}
  for i=1,3 do
    local row={0,0,0,0};row[f.route[i]+1]=1;rows[i]=row
  end
  return rows,f.gain
end
-- CPU equivalent used for format/regression tests, never for per-pixel runtime.
function S.apply(f,rgba)
  if not S.validFilter(f) then return {rgba[1],rgba[2],rgba[3],rgba[4]} end
  local out={nil,nil,nil,rgba[4]}
  for i=1,3 do out[i]=math.max(0,math.min(1,(rgba[f.route[i]+1] or 1)*f.gain[i])) end
  return out
end
return S
