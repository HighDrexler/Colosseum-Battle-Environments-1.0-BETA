-- Verified source-atlas registry, shared by extraction and both render paths.
-- Identifies source audience atlases by BOTH arena namespace and source offset.
-- No generic cheering, timing, density, culling, or GameSound IDs are invented.
local P={version=1}
local definitions={
  water={root='cache/stages/water/source/',offsets={0x0d5b60,0x0ddb60}},
  orre_colosseum={root='cache/stages/orre/source/',offsets={0x10f240,0x111240}},
  pyrite_colosseum={root='cache/stages/pyrite/source/',offsets={0x103580,0x10b580}},
  deep_colosseum={root='cache/stages/deep/source/',offsets={0x09d8c0,0x09f8c0,0x0a18c0,0x0a98c0}},
  realgam_colosseum={root='cache/stages/realgam/source/',offsets={0x0bed60,0x0c0d60}},
  mt_battle_summit={root='cache/stages/d2_crater/textures/',offsets={0x106ee0,0x108ee0,0x10aee0,0x10cee0}},
  relic_chamber={offsets={}},relic_cave={offsets={}},outskirts={offsets={}},outdoor_wild={offsets={}},
}
local sets={}
for id,def in pairs(definitions)do
  local set={};for _,offset in ipairs(def.offsets)do set[offset]=true end;sets[id]=set
end
function P.hasSourceAudience(arenaId)
  local def=definitions[arenaId]
  return def~=nil and #def.offsets>0
end
function P.classifySourceTexture(arenaId,path)
  local def=definitions[arenaId]
  if not def or not def.root or type(path)~='string' then return nil end
  if path:sub(1,#def.root)~=def.root then return nil end
  local leaf=path:sub(#def.root+1)
  local offset=leaf:match('^tex_([%da-fA-F]+)_%d+x%d+_f%d+%.rgba$')
  offset=offset and tonumber(offset,16)
  if not offset or not sets[arenaId][offset]then return nil end
  return {kind='source-audience',arenaId=arenaId,sourceOffset=offset,
    placement='preserve-authored',audio='verified-source-cue-required'}
end
function P.classifyPath(path)
 for id in pairs(definitions)do local match=P.classifySourceTexture(id,path);if match then return match end end
end
return P
