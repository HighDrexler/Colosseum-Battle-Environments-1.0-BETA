-- Read-only, deterministic progress-aware selection. No save writes, RNG, source
-- extraction, or graphics calls. Heavy disk probes run on BattleCache's worker.
local V=...
local P={version=2,batchSize=30}
local Dex=V.ColosseumDex
local function tableOrEmpty(t)return type(t)=='table' and t or {} end
local function num(n)local v=tonumber(n);return v and v==v and v~=math.huge and v~=-math.huge and v or nil end
local function egg(m)return m and (m.isEgg==true or m.egg==true or m.species=='EGG')end
local function unwrap(m)return type(m)=='table' and (type(m.mon)=='table' and m.mon or m) or nil end
local function key(d,v)return tostring(d)..((v=='shiny' and Dex.rare[d]) and ':shiny' or ':normal')end
function P.units()
  local rows={}
  for d=1,251 do
    rows[#rows+1]={dex=d,variant='normal',key=key(d,'normal'),
      variants=Dex.rare[d] and {'normal'} or {'normal','shiny'}}
    if Dex.rare[d] then rows[#rows+1]={dex=d,variant='shiny',key=key(d,'shiny'),variants={'shiny'}} end
  end
  return rows
end
-- Read-only startup eligibility probe. It validates only persisted generated
-- files and stops as soon as the reuse threshold is proven. No source extraction,
-- model preparation, GPU upload or cache write is performed here. Existing caches
-- from earlier releases therefore gain REUSE CACHE without being rebuilt.
function P.reuseInfo(probe,checkpoint,threshold)
  if type(probe)~='function' then return nil,'cache probe unavailable' end
  checkpoint=checkpoint or function()end
  threshold=math.max(1,math.floor(tonumber(threshold) or P.batchSize))
  local units=P.units();local done,appearances=0,0
  for i,row in ipairs(units)do
    checkpoint(('Checking reusable cache %d / %d'):format(i,#units))
    if probe(row.dex,row.variant,checkpoint)==true then
      done=done+1;appearances=appearances+#(row.variants or {row.variant})
      if done>=threshold then
        return {eligible=true,cachedModels=done,cachedAppearances=appearances,
          minimum=true,scanned=i,totalModels=#units,totalAppearances=502,threshold=threshold}
      end
    end
  end
  return {eligible=false,cachedModels=done,cachedAppearances=appearances,
    minimum=false,scanned=#units,totalModels=#units,totalAppearances=502,threshold=threshold}
end
function P.rank(game,save,checkpoint)
  local data=tableOrEmpty(game and game.data);save=tableOrEmpty(save)
  checkpoint=checkpoint or function()end
  local units,byKey=P.units(),{}
  local gen=V.GenerationCompat and V.GenerationCompat.current() or 1
  for _,r in ipairs(units)do
    r.score=(gen==1 and r.dex>151) and -10 or 0;r.reason='remaining catalog';byKey[r.key]=r
  end
  local resolved,defs={},{}
  for id,def in pairs(tableOrEmpty(data.pokemon))do
    if type(def)=='table' then
      local n=num(def.dex or def.index or def.number)
      if n and n%1==0 and n>=1 and n<=251 then
        resolved[tostring(id):upper()]=n;defs[n]=def
        if def.id then resolved[tostring(def.id):upper()]=n end
        if def.name then resolved[tostring(def.name):upper()]=n end
      end
    end
  end
  for _,r in ipairs(units)do
    local def=defs[r.dex];r.name=def and (def.name or def.id)
  end
  local function dex(species)
    if species==nil then return nil end
    local n=resolved[tostring(species):upper()] or num(species)
    return n and n%1==0 and n>=1 and n<=251 and n or nil
  end
  local function add(d,v,score,reason)
    local r=d and byKey[key(d,v)]
    if r and score>r.score then r.score=score;r.reason=reason end
  end
  local function species(d,score,reason)
    add(d,'normal',score,reason)
    -- Unobserved rare shinies are lower priority, not lost. An owned shiny
    -- receives the exact same top priority as an owned ordinary appearance.
    if d and Dex.rare[d] then add(d,'shiny',math.max(1,score-500000),'shiny counterpart') end
  end
  local levels,owned,partyCount={}, {},0
  local function mon(m,score,reason,required)
    local raw=unwrap(m);if not raw or egg(raw)then return end
    local d,v=V.ModelIdentity.resolve(game,m)
    if not d then if required then return nil,v end;return end
    add(d,v,score,reason)
    local level=num(raw.level)
    owned[d]=math.max(owned[d] or 0,level or 0)
    if required then
      partyCount=partyCount+1
      if level and level>=1 and level<=100 then levels[#levels+1]=level end
    end
    return true
  end
  local party=tableOrEmpty(save.party or save.pokemon or save.team)
  for i=1,math.min(6,#party)do
    local raw=unwrap(party[i])
    if raw and not egg(raw)then local ok,err=mon(party[i],1000000-i,'current team',true);if not ok then return nil,err end end
  end
  local caughtCount,seenCount=0,0
  local function dexSet(set,score,reason)
    local count,seen=0,{}
    for id,has in pairs(tableOrEmpty(set))do
      if has~=false and has~=0 and has~=nil then
        local d
        if type(has)=='table' then local raw=unwrap(has);d=raw and dex(raw.species or raw.dex)
        elseif type(id)=='number' and type(has)=='string' then d=dex(has)
        else d=dex(id)end
        if d and not seen[d]then
          seen[d]=true;count=count+1;species(d,score,reason)
          if reason=='caught' then owned[d]=owned[d] or 0 end
        end
      end
    end
    return count
  end
  local pokedex=tableOrEmpty(save.pokedex)
  caughtCount=dexSet(pokedex.caught or pokedex.owned,800000,'caught')
  seenCount=dexSet(pokedex.seen,600000,'seen')
  -- Native boxed Pokemon are direct lists, not a second model lifecycle.
  for _,box in pairs(tableOrEmpty(save.boxes))do
    for _,m in ipairs(tableOrEmpty(box))do mon(m,850000,'owned in PC',false)end
  end
  for _,m in ipairs(tableOrEmpty(save.box))do mon(m,850000,'owned in PC',false)end
  table.sort(levels)
  local level=#levels>0 and levels[math.floor((#levels+1)/2)] or 5
  local maps=tableOrEmpty(data.gen2Maps or data.maps)
  local pos=tableOrEmpty(save.position)
  local current=pos.map or pos.mapId or save.map or save.spawn
  if type(current)=='table' then current=current.id end
  local nearby={}
  if current then
    nearby[current]=true
    local map=tableOrEmpty(maps[current])
    for _,c in pairs(tableOrEmpty(map.connections))do
      local dest=type(c)=='table' and (c.map or c.mapId or c.destMap) or c
      if type(dest)=='string' then nearby[dest]=true end
    end
    for _,c in pairs(tableOrEmpty(map.warps))do
      local dest=type(c)=='table' and (c.destMap or c.targetMap or c.map)
      if type(dest)=='string' then nearby[dest]=true end
    end
  end
  local slotsVisited=0
  local function slot(s,mapId,trainer)
    local d=dex(s.species);if not d then return end
    slotsVisited=slotsVisited+1
    local low=num(s.level or s.minLevel);local high=num(s.maxLevel) or low
    local distance=low and math.max(0,low-level,level-(high or low)) or 100
    local closeness=math.max(0,100-math.min(100,distance))*10
    local score,reason
    if mapId and mapId==current then score,reason=900000+closeness,'current-area encounter'
    elseif mapId and nearby[mapId]then score,reason=750000+closeness,'nearby encounter'
    elseif distance<=10 then score,reason=400000+closeness,trainer and 'level-matched trainer' or 'level-matched encounter'
    else score,reason=1000+closeness,'other encounter'end
    species(d,score,reason)
    if slotsVisited%64==0 then checkpoint('Ranking encounters for team level '..level)end
  end
  local function walk(node,mapId,trainer,depth,visited)
    if type(node)~='table' or (depth or 0)>8 then return end
    visited=visited or {};if visited[node]then return end;visited[node]=true
    if node.species then slot(node,mapId,trainer);return end
    for _,v in pairs(node)do if type(v)=='table'then walk(v,mapId,trainer,(depth or 0)+1,visited)end end
  end
  local enc=tableOrEmpty(data.gen2Encounters or data.encounters)
  if data.gen2Encounters then
    for _,kind in ipairs{'grass','water','swarmGrass','swarmWater'}do
      for mapId,row in pairs(tableOrEmpty(enc[kind]))do walk(row,mapId,false)end
    end
    for mapId,setId in pairs(tableOrEmpty(enc.trees))do walk(tableOrEmpty(enc.treeSets)[setId],mapId,false)end
    for mapId,setId in pairs(tableOrEmpty(enc.rocks))do walk(tableOrEmpty(enc.treeSets)[setId],mapId,false)end
    -- Other source-backed encounter classes still contribute level relevance.
    for _,kind in ipairs{'fishGroups','fish','fishing','bugContest'}do walk(enc[kind],nil,false)end
  else
    for mapId,row in pairs(enc)do walk(row,mapId,false)end
  end
  for _,roamer in ipairs(tableOrEmpty(save.roamers))do if roamer.map then walk(roamer,roamer.map,false)end end
  walk(data.gen2Trainers or data.trainers,nil,true)
  -- Direct evolutions likely to become relevant soon. Never infer species from
  -- National Dex adjacency; branch/item/trade methods use the actual dataset.
  for d,ownedLevel in pairs(owned)do
    for _,e in ipairs(tableOrEmpty(defs[d] and defs[d].evolutions))do
      local target=dex(e.species or e.to or e.target)
      local requirement=num(e.level);local threshold=math.max(level,ownedLevel)
      if not requirement or requirement<=threshold+8 then species(target,700000,'near-term evolution')end
    end
  end
  if partyCount==0 then
    local starters=gen==2 and {152,155,158} or {1,4,7}
    local ok,version=pcall(function()local G=(V.engineRequire or require)('src.core.GameVersion');return G.get()end)
    if gen==1 and ok and version=='yellow'then starters={25}end
    for _,d in ipairs(starters)do species(d,950000,'starter')end
  end
  table.sort(units,function(a,b)
    if a.score~=b.score then return a.score>b.score end
    if a.dex~=b.dex then return a.dex<b.dex end
    return a.variant=='normal' and b.variant~='normal'
  end)
  return units,{level=level,caught=caughtCount,seen=seenCount,map=current,partyCount=partyCount}
end
function P.select(game,save,probe,checkpoint)
  checkpoint=checkpoint or function()end
  local ranked,profile=P.rank(game,save,checkpoint)
  if not ranked then return nil,profile end
  local rows,done,appearances={},0,0
  for i,row in ipairs(ranked)do
    checkpoint(('Checking saved cache %d / %d'):format(i,#ranked))
    local ready=probe(row.dex,row.variant,checkpoint)==true
    if ready then done=done+1;appearances=appearances+#row.variants
    elseif #rows<P.batchSize then rows[#rows+1]=row end
  end
  return rows,{profile=profile,cachedModels=done,cachedAppearances=appearances,
    totalModels=#ranked,totalAppearances=502,batchLimit=P.batchSize}
end
return P
