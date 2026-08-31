local V=...
local FSYS,GX,HSD=V.FSYS,V.GXTexture,V.HSD
local Waza=V.WazaSequenceExtractor
local M={revision=14,mod=nil,openDisc=nil,memory={},negative={},pending={},pendingKeys={},prefetchStats={queued=0,completed=0,failed=0}}

local MOVE={
  [33]={stem="taiatari",phases={"attack","damage"},style="impact",tint={1.00,0.96,0.82}}, -- Tackle
  [40]={stem="dokubari",phases={"attack","damage"},style="projectile",tint={0.72,0.42,0.92}}, -- Poison Sting
  [45]={stem="nakigoe",phases={"attack","sp1"},style="aura",tint={0.92,0.96,1.00}}, -- Growl
  [52]={stem="hinoko",phases={"attack","damage","sp1"},style="projectile",tint={1.00,0.48,0.12}}, -- Ember
  [53]={stem="kaenhousya",phases={"attack","damage","sp1"},style="projectile",tint={1.00,0.42,0.12}}, -- Flamethrower
  [57]={stem="naminori",phases={"attack","damage","sp1"},style="wave",tint={0.36,0.72,1.00}}, -- Surf
  [59]={stem="fubuki",phases={"attack","damage","sp1"},style="wave",tint={0.72,0.92,1.00}}, -- Blizzard
  [63]={stem="hakai",phases={"attack","damage"},style="projectile",tint={1.00,0.86,0.34}}, -- Hyper Beam
  [64]={stem="tsutsuku",phases={"attack","damage"},style="impact",tint={1.00,0.95,0.82}}, -- Peck
  [81]={stem="itowohaku",phases={"attack","damage"},style="projectile",tint={0.80,0.95,0.64}}, -- String Shot
  [85]={stem="10manvolt",phases={"attack","damage"},style="target",tint={1.00,0.90,0.12}}, -- Thunderbolt
  [106]={stem="katakunaru",phases={"special"},style="self",tint={0.86,0.88,0.92}}, -- Harden
  [172]={stem="kaenguruma",phases={"attack","damage","sp1"},style="contact",tint={1.00,0.38,0.08}}, -- Flame Wheel
  [193]={stem="miyaburu",phases={"attack","damage"},style="target",tint={0.80,0.70,1.00}}, -- Foresight
}
local NAME={
  tackle=33,poisonsting=40,growl=45,ember=52,flamethrower=53,surf=57,blizzard=59,hyperbeam=63,
  peck=64,stringshot=81,thunderbolt=85,harden=106,flamewheel=172,foresight=193,
}

-- Colosseum uses a mixture of romanised Japanese and English WZX stems. These
-- are the Gen-I/II move names whose normalized English identifier is itself an
-- exact source stem. Keeping this discovery path separate from the curated
-- table above expands verified coverage without guessing a Japanese filename.
local DIRECT={}
for _,name in ipairs({
  "karatechop","cometpunch","sonicboom","counter","megadrain","solarbeam",
  "teleport","barrier","smog","flash","sketch","triplekick","aeroblast",
  "machpunch","lockon","gigadrain","endure","spark","present","megahorn",
  "encore","irontail","metalclaw","crosschop","mirrorcoat","shadowball",
}) do DIRECT[name]=name end

-- 1.5.52 exhaustive source-stem sweep. Colosseum names many WZX banks from
-- the Japanese move identifier rather than the localized English move name.
-- Keep a broad Gen-I/II alias roster, but NEVER claim an alias by itself:
-- acquire() probes the user's actual GC6E01 FST and only accepts an exact
-- source archive hit. Wrong/unused aliases therefore remain a cheap miss and
-- native visuals stay authoritative.
local SOURCE_STEM_ALIASES={
  [1]={"hataku"},
  [2]={"karatechop","karatechoppu"},
  [3]={"oufukubinta","oufuku"},
  [4]={"renzokupunch","renzokupanchi","renzoku"},
  [5]={"megatonpunch","megatonpanchi"},
  [6]={"nekonikoban"},
  [7]={"honoonopunch","honoonopanchi","honoonopanti"},
  [8]={"reitoupunch","reitoupanchi"},
  [9]={"kaminaripunch","kaminaripanchi"},
  [10]={"hikkaku"},
  [11]={"hasamu"},
  [12]={"hasamiguillotine","hasamigirochin","hasami"},
  [13]={"kamaitachi"},
  [14]={"tsuruginomai","turuginomai"},
  [15]={"iaigiri"},
  [16]={"kazeokoshi"},
  [17]={"tsubasadeutsu","tsubasa"},
  [18]={"fukitobashi"},
  [19]={"sorawotobu"},
  [20]={"shimetsukeru"},
  [21]={"tatakitsukeru","tataki"},
  [22]={"tsurunomuchi","tsuru"},
  [23]={"fumitsuke"},
  [24]={"nidogeri"},
  [25]={"megatonkick","megatonkikku"},
  [26]={"tobigeri"},
  [27]={"mawashigeri","mawashi"},
  [28]={"sunakake"},
  [29]={"zutsuki"},
  [30]={"tsunodetsuku","tsuno"},
  [31]={"midarezuki","midareduki"},
  [32]={"tsunodrill","tsunodoriru"},
  [33]={"taiatari"},
  [34]={"noshikakari"},
  [35]={"makitsuku"},
  [36]={"tosshin"},
  [37]={"abareru"},
  [38]={"sutemitackle","sutemi"},
  [39]={"shippowofuru"},
  [40]={"dokubari"},
  [41]={"doubleneedle","daburuniidoru"},
  [42]={"missilebari","misairubari"},
  [43]={"niramitsukeru","niramitukeru"},
  [44]={"kamitsuku","kamituku"},
  [45]={"nakigoe"},
  [46]={"hoeru"},
  [47]={"utau"},
  [48]={"chouonpa","tyouonpa"},
  [49]={"sonicboom","sonikkubuumu"},
  [50]={"kanashibari"},
  [51]={"youkaieki"},
  [52]={"hinoko"},
  [53]={"kaenhousya","kaenhousha"},
  [54]={"shiroikiri"},
  [55]={"mizudeppou"},
  [56]={"hydropump","haidoroponpu"},
  [57]={"naminori"},
  [58]={"reitoubeam","reitoubiimu"},
  [59]={"fubuki"},
  [60]={"saikekousen","psybeam","psyche"},
  [61]={"bubblekousen","baburukousen","barburukousen"},
  [62]={"aurorabeam","oororabiimu","ourorabeam"},
  [63]={"hakaikousen","hakai"},
  [64]={"tsutsuku"},
  [65]={"drillkuchibashi","dorirukuchibashi","drill"},
  [66]={"jigokuguruma","jigoku"},
  [67]={"ketaguri"},
  [68]={"counter","kauntaa"},
  [69]={"chikyuunage","chikyunage"},
  [70]={"kairiki"},
  [71]={"suitoru"},
  [72]={"megadrain","megadorein"},
  [73]={"yadoriginotane","yadorigi"},
  [74]={"seichou","seityou"},
  [75]={"happacutter","happakattaa","happa"},
  [76]={"solarbeam","sooraabiimu"},
  [77]={"dokunokona"},
  [78]={"shibiregona","shibire"},
  [79]={"nemurigona","nemuri"},
  [80]={"hanabiranomai","hanabira"},
  [81]={"itowohaku"},
  [82]={"ryuunoikari","ryunoikari"},
  [83]={"honoonouzu"},
  [84]={"denkishoock","denkisyokku","denkiskock","denkishock"},
  [85]={"10manvolt","10manboruto"},
  [86]={"denjiha"},
  [87]={"kaminari"},
  [88]={"iwaotoshi"},
  [89]={"jishin","jisin"},
  [90]={"jiware","ziware"},
  [91]={"anawohoru"},
  [92]={"dokudoku"},
  [93]={"nenriki"},
  [94]={"psychokinesis","saikokineshisu","psycho"},
  [95]={"saiminjutsu","saimin"},
  [96]={"yoganopose","yoga"},
  [97]={"kousokuidou","kousoku"},
  [98]={"denkousekka","denkou"},
  [99]={"ikari"},
  [100]={"teleport","tereport"},
  [101]={"nighthead","naitoheddo"},
  [102]={"monomane"},
  [103]={"iyanaoto"},
  [104]={"kagebunshin"},
  [105]={"jikosaisei"},
  [106]={"katakunaru"},
  [107]={"chiisakunaru","tiisakunaru"},
  [108]={"enmaku"},
  [109]={"ayashiihikari","ayashii"},
  [110]={"karanikomoru"},
  [111]={"marukunaru"},
  [112]={"barrier","bariaa"},
  [113]={"hikarinokabe","hikari"},
  [114]={"kuroikiri"},
  [115]={"reflect","rifurekutaa","reflector"},
  [116]={"kiaidame"},
  [117]={"gaman"},
  [118]={"yubiwofuru"},
  [119]={"oumugaeshi","oumugaesi"},
  [120]={"jibaku"},
  [121]={"tamagobakudan","tamagobomb"},
  [122]={"shitadenameru","shita"},
  [123]={"smog","sumoggu"},
  [124]={"hedorokougeki"},
  [125]={"honekonbou"},
  [126]={"daimonji"},
  [127]={"takinobori","taki"},
  [128]={"karadehasamu"},
  [129]={"speedstar","supiidosutaa"},
  [130]={"rocketzutsuki","rokettouzuki","rocket"},
  [131]={"togecannon","togekyanon"},
  [132]={"karamitsuku","karami"},
  [133]={"dowasure"},
  [134]={"spoonmage","supuunmage"},
  [135]={"tamagoumi"},
  [136]={"tobihizageri","tobihiza"},
  [137]={"hebinirami"},
  [138]={"yumekui"},
  [139]={"dokugas","dokugasu"},
  [140]={"tamanage"},
  [141]={"kyuuketsu"},
  [142]={"akumanokiss","akumanokissu"},
  [143]={"godbird","goddobaado"},
  [144]={"henshin"},
  [145]={"awa"},
  [146]={"piyopiyopunch","piyopiyopanchi","piyopiyo"},
  [147]={"kinokonohoushi","kinoko"},
  [148]={"flash","furasshu"},
  [149]={"psychowave","saikowave"},
  [150]={"haneru"},
  [151]={"tokeru"},
  [152]={"crabhammer","kurabuhanmaa","kurabuhanmer"},
  [153]={"daibakuhatsu"},
  [154]={"midarehikkaki"},
  [155]={"honeboomerang","honebuumeran","honeboomeran"},
  [156]={"nemuru"},
  [157]={"iwanadare"},
  [158]={"hissatsumaeba","hissatsu"},
  [159]={"kakubaru"},
  [160]={"texture","tekusuchaa"},
  [161]={"triattack","toraiatakku","tryattack"},
  [162]={"ikarinomaeba"},
  [163]={"kirisaku"},
  [164]={"migawari"},
  [165]={"waruagaki"},
  [166]={"sketch","sukecchi"},
  [167]={"triplekick","toripurukikku"},
  [168]={"dorobou"},
  [169]={"kumonosu"},
  [170]={"kokoronome"},
  [171]={"akumu"},
  [172]={"kaenguruma"},
  [173]={"ibiki"},
  [174]={"noroi"},
  [175]={"jitabata"},
  [176]={"texture2","tekusuchaa2"},
  [177]={"aeroblast","earoburasuto"},
  [178]={"watahoushi","wata"},
  [179]={"kishikaisei","kisikaisei"},
  [180]={"urami"},
  [181]={"konayuki"},
  [182]={"mamoru"},
  [183]={"machpunch","mahapanchi"},
  [184]={"kowaikao"},
  [185]={"damashiuchi","damasiuti"},
  [186]={"tenshinokiss","tenshinokissu"},
  [187]={"haradaiko"},
  [188]={"hedorobakudan"},
  [189]={"dorokake"},
  [190]={"octanhou","okutanhou"},
  [191]={"makibishi","makibisi"},
  [192]={"denjihou"},
  [193]={"miyaburu"},
  [194]={"michizure","michidure"},
  [195]={"horobinouta"},
  [196]={"kogoerukaze"},
  [197]={"mikiri"},
  [198]={"bonerush","boonrasshu","boonrush"},
  [199]={"lockon","rokkuon"},
  [200]={"gekirin"},
  [201]={"sunaarashi"},
  [202]={"gigadrain","gigadorein"},
  [203]={"koraeru","endure"},
  [204]={"amaeru"},
  [205]={"korogaru"},
  [206]={"mineuchi"},
  [207]={"ibaru"},
  [208]={"milkonomi","mirukunomi","milknomi"},
  [209]={"spark","supaaku"},
  [210]={"renzokugiri"},
  [211]={"haganenotsubasa","hagane"},
  [212]={"kuroimanazashi"},
  [213]={"meromero"},
  [214]={"negoto"},
  [215]={"iyashinosuzu"},
  [216]={"ongaeshi"},
  [217]={"present","purezento"},
  [218]={"yatsuatari"},
  [219]={"shinpinomamori","sinpi"},
  [220]={"itamiwake"},
  [221]={"seinaruhonoo","seinaru"},
  [222]={"magnitude","magunichuudo","magunityuudo"},
  [223]={"bakuretsupunch","bakuretsupanchi","bakuretsu"},
  [224]={"megahorn","megahoon"},
  [225]={"ryuunoibuki","ryunoibuki"},
  [226]={"batontouch","batontacchi"},
  [227]={"encore","ankooru"},
  [228]={"oiuchi","oiuti"},
  [229]={"kousokuspin","kousokusupin"},
  [230]={"amaikaori"},
  [231]={"irontail","aiantairu"},
  [232]={"metalclaw","metarukuroo"},
  [233]={"ateminage"},
  [234]={"asanohizashi","asanohizasi"},
  [235]={"kougousei"},
  [236]={"tsukinohikari","tukinohikari"},
  [237]={"mezamerupower","mezamerupawaa"},
  [238]={"crosschop","kurosuchoppu"},
  [239]={"tatsumaki"},
  [240]={"amagoi"},
  [241]={"nihonbare"},
  [242]={"kamikudaku"},
  [243]={"mirrorcoat","miraakooto"},
  [244]={"jikoanji"},
  [245]={"shinsoku"},
  [246]={"genshinochikara","genshi"},
  [247]={"shadowball","shadoobooru"},
  [248]={"miraiyochi"},
  [249]={"iwakudaki"},
  [250]={"uzushio","uzusio"},
  [251]={"fukurodataki","hukuro"},
}

local function addUnique(out,seen,value)
  value=tostring(value or ""):lower():gsub("[^%w]","")
  if value~="" and not seen[value] then seen[value]=true;out[#out+1]=value end
end
local function stemVariants(value,out,seen)
  value=tostring(value or ""):lower():gsub("[^%w]","")
  addUnique(out,seen,value)
  -- The retail filenames mix Hepburn, Kunrei-style digraphs and a handful of
  -- English loan-word spellings. Generate only conservative equivalent forms;
  -- every result is still required to exist exactly in the disc FST.
  local swaps={
    {"sha","sya"},{"shu","syu"},{"sho","syo"},{"shi","si"},
    {"cha","tya"},{"chu","tyu"},{"cho","tyo"},{"chi","ti"},
    {"ja","zya"},{"ju","zyu"},{"jo","zyo"},{"ji","zi"},
  }
  for _,pair in ipairs(swaps) do
    if value:find(pair[1],1,true) then addUnique(out,seen,(value:gsub(pair[1],pair[2]))) end
    if value:find(pair[2],1,true) then addUnique(out,seen,(value:gsub(pair[2],pair[1]))) end
  end
end
local function sourceStemCandidates(p,id,move)
  local out,seen={},{}
  stemVariants(p and p.stem,out,seen)
  for _,v in ipairs((p and p.stems) or {}) do stemVariants(v,out,seen) end
  for _,v in ipairs(SOURCE_STEM_ALIASES[tonumber(id)] or {}) do stemVariants(v,out,seen) end
  if type(move)=="table" then stemVariants(move.name or move.id or move.move,out,seen) end
  return out
end

-- Retail camera/composition roles for source banks whose move TYPE alone is
-- misleading. These are not synthetic FX substitutions: they only influence
-- how CBE frames the exact WZX bank that was found on the Colosseum disc.
local SOURCE_STYLE_OVERRIDES={
  [17]="contact",    -- Wing Attack / wzx_tsubasa_*
  [60]="projectile", -- Psybeam / wzx_psyche_*
  [94]="target",     -- Psychic / wzx_psycho_* envelopes the target
}

local TYPE_TINT={
  FIRE={1.00,.42,.12},WATER={.34,.70,1.00},ICE={.70,.92,1.00},
  ELECTRIC={1.00,.90,.12},GRASS={.48,.86,.34},POISON={.72,.42,.92},
  PSYCHIC={.92,.50,1.00},DARK={.48,.38,.72},GHOST={.64,.48,.88},
  ROCK={.74,.64,.46},GROUND={.72,.56,.36},STEEL={.72,.78,.86},
}

local function inferredProfile(stem,move)
  local category=type(move)=="table" and tostring(move.category or move.damageClass or move.class or ""):lower() or ""
  local power=type(move)=="table" and tonumber(move.power) or nil
  local typ=type(move)=="table" and tostring(move.type or ""):upper():gsub("[^A-Z]","") or ""
  local style=(category:find("status",1,true) or (power and power<=0)) and "target" or "impact"
  if style~="target" and (typ=="FIRE" or typ=="WATER" or typ=="ICE" or typ=="ELECTRIC"
      or typ=="GRASS" or typ=="POISON" or typ=="PSYCHIC" or typ=="GHOST") then style="projectile" end
  return {stem=stem,phases={},style=style,tint=TYPE_TINT[typ] or {1,1,1},direct=true}
end

local function norm(s)
  return tostring(s or ""):lower():gsub("[^%w]","")
end
local function profile(moveId,move)
  local id=tonumber(moveId)
  local p=id and MOVE[id] or nil
  if not p and id and SOURCE_STEM_ALIASES[id] then
    p=inferredProfile(SOURCE_STEM_ALIASES[id][1],move);p.stems=SOURCE_STEM_ALIASES[id];p.candidate=true
  end
  if not p and type(move)=="table" then
    local key=norm(move.name or move.id or move.move)
    local mapped=NAME[key]
    p=mapped and MOVE[mapped] or nil; id=id or mapped
    if not p and id and SOURCE_STEM_ALIASES[id] then
      p=inferredProfile(SOURCE_STEM_ALIASES[id][1],move);p.stems=SOURCE_STEM_ALIASES[id];p.candidate=true
    end
    if not p and DIRECT[key] then p=inferredProfile(DIRECT[key],move) end
    -- 1.5.35 exact-stem discovery: do not restrict source-backed discovery to
    -- a tiny hand-maintained English list. Every named move may probe an exact
    -- wzx_<normalized-name>_* archive. acquire() only accepts the candidate if
    -- that archive actually exists on the user's Colosseum disc, so this adds
    -- coverage without guessing or suppressing vanilla effects on a false hit.
    if not p and key~="" then
      p=inferredProfile(key,move);p.candidate=true
    end
  end
  if p and id and SOURCE_STYLE_OVERRIDES[id] then
    local copy={};for k,v in pairs(p) do copy[k]=v end
    copy.style=SOURCE_STYLE_OVERRIDES[id]
    p=copy
  end
  return p,id
end

local function describe(moveId,move)
  local p,id=profile(moveId,move)
  if not p then return nil end
  local stems=sourceStemCandidates(p,id,move)
  return {moveId=id,stem=stems[1] or p.stem,stems=stems,style=p.style,tint=p.tint,phases=p.phases}
end
function M.describe(moveId,move) return describe(moveId,move) end
function M.mapped(moveId,move) return describe(moveId,move)~=nil end

local function be16(s,p)
  local a,b=s:byte(p+1,p+2); if not b then return nil end
  return a*256+b
end
local function be32(s,p)
  local a,b,c,d=s:byte(p+1,p+4); if not d then return nil end
  return ((a*256+b)*256+c)*256+d
end

local function beFloat(s,p)
  local bits=be32(s,p);if not bits then return nil end
  local sign=1
  if bits>=2147483648 then sign=-1;bits=bits-2147483648 end
  local exp=math.floor(bits/8388608)
  local mant=bits-exp*8388608
  if exp==255 then return mant==0 and sign*1e30 or 0 end
  if exp==0 then return sign*(mant/8388608)*(2^-126) end
  return sign*(1+mant/8388608)*(2^(exp-127))
end
local function hex(bytes)
  local out={}
  for i=1,#bytes do out[#out+1]=string.format("%02X",bytes:byte(i)) end
  return table.concat(out)
end
local function saneRange(off,size,n)
  return type(off)=="number" and type(size)=="number" and off>=0 and size>=0 and off+size<=n
end
local function cacheReadLua(path)
  local mod=M.mod;if not (mod and mod.cache and type(mod.cache.read)=="function") then return nil end
  local ok,src=pcall(mod.cache.read,mod.cache,path); if not ok or type(src)~="string" then return nil end
  local f=load(src,"@generated/"..path);if not f then return nil end
  local ok2,v=pcall(f);return ok2 and v or nil
end
local function write(path,data)
  local mod=M.mod; if not (mod and mod.cache and type(mod.cache.write)=="function") then return false,"cache unavailable" end
  local ok,a,b=pcall(mod.cache.write,mod.cache,path,data)
  if not ok then return false,tostring(a) end
  if a==false or a==nil then return false,tostring(b or "cache write failed") end
  if type(M.buildGenerated)=="table" then
    local seen=M.buildGeneratedSeen or {};M.buildGeneratedSeen=seen
    if not seen[path] then seen[path]=true;M.buildGenerated[#M.buildGenerated+1]=path end
  end
  return true
end
local function serialize(v)
  local t=type(v)
  if t=="nil" then return "nil" elseif t=="number" then return ("%.9g"):format(v)
  elseif t=="boolean" then return v and "true" or "false" elseif t=="string" then return string.format("%q",v)
  elseif t=="table" then
    local out={"{"};local n=#v
    for i=1,n do out[#out+1]=serialize(v[i]);out[#out+1]="," end
    for k,x in pairs(v) do
      if not (type(k)=="number" and k>=1 and k<=n and k%1==0) then
        out[#out+1]="["..serialize(k).."]="..serialize(x).."," end
    end
    out[#out+1]="}";return table.concat(out)
  end
  return "nil"
end

local function textureTraits(rgba,w,h)
  local minx,miny,maxx,maxy=w,h,-1,-1
  local live=0;local alphaSum=0
  for i=0,w*h-1 do
    local a=rgba:byte(i*4+4) or 0
    alphaSum=alphaSum+a
    if a>10 then
      live=live+1
      local x=i%w;local y=math.floor(i/w)
      if x<minx then minx=x end;if x>maxx then maxx=x end
      if y<miny then miny=y end;if y>maxy then maxy=y end
    end
  end
  local cw,ch=w,h
  if live>0 then cw=maxx-minx+1;ch=maxy-miny+1 end
  local coverage=live/math.max(1,w*h)
  local contentScale=math.max(w,h)/math.max(1,math.max(cw,ch))
  return {coverage=coverage,meanAlpha=alphaSum/math.max(1,w*h*255),
    contentW=cw,contentH=ch,contentScale=math.max(1,math.min(4,contentScale))}
end
local function intensityAlpha(rgba)
  local out={};local n=#rgba
  for p=1,n,4 do
    local r=rgba:byte(p) or 0
    local g=rgba:byte(p+1) or r
    local b=rgba:byte(p+2) or r
    local i=math.max(r,g,b)
    out[#out+1]=string.char(r,g,b,i)
  end
  return table.concat(out)
end


local function parseGPT1(blob,gptOff,bank,out,maxTextures,sequence)
  local n=#blob
  -- WZX places the top-level GPT1 generator REF directly 0x10 bytes before
  -- the embedded GPT1 payload. This is the source root that the sequence
  -- actually starts; the PTL table itself is a template bank, not a list of
  -- generators that should all be emitted at once.
  local rootRef=(gptOff>=0x10) and be32(blob,gptOff-0x10) or nil
  local ptlRel,txgRel,refRel=be32(blob,gptOff+4),be32(blob,gptOff+8),be32(blob,gptOff+0x10)
  if not (ptlRel and txgRel) then return end
  local ptl=gptOff+ptlRel;local txg=gptOff+txgRel
  local ref=refRel and refRel>0 and (gptOff+refRel) or nil
  if not (saneRange(ptl,12,n) and saneRange(txg,4,n)) then return end
  local genCount=be32(blob,ptl+8) or 0
  local offsets={}
  if genCount>0 and genCount<4096 then
    for i=0,genCount-1 do offsets[i+1]=be32(blob,ptl+12+i*4) end
    for i=1,genCount do
      local rel=offsets[i];local ga=rel and (ptl+rel) or nil
      if ga and saneRange(ga,0x3C,n) then
        local nextRel=offsets[i+1]
        local cmdEnd=nextRel and (ptl+nextRel) or txg
        cmdEnd=math.min(cmdEnd,n)
        local life=be16(blob,ga+4) or 0
        local maxParticles=be16(blob,ga+6) or 0
        if life>out.maxLifetime then out.maxLifetime=life end
        local params={}
        for j=0,11 do params[j+1]=beFloat(blob,ga+0x0C+j*4) or 0 end
        local cmdStart=ga+0x3C
        local commands=(cmdEnd>cmdStart and saneRange(cmdStart,cmdEnd-cmdStart,n))
          and blob:sub(cmdStart+1,cmdEnd) or ""
        local refId=(ref and saneRange(ref+(i-1)*4,4,n)) and be32(blob,ref+(i-1)*4) or nil
        out.programs[#out.programs+1]={
          bank=bank,bankIndex=i,genType=be16(blob,ga) or 0,unknown02=be16(blob,ga+2) or 0,
          lifetime=life,maxParticles=maxParticles,flags=be32(blob,ga+8) or 0,
          params=params,commandHex=hex(commands),refId=refId,rootRef=rootRef,gptOffset=gptOff,
          root=(rootRef~=nil and refId~=nil and tonumber(refId)==tonumber(rootRef)) or false,
          sequence=sequence,
        }
      end
    end
    out.generators=out.generators+genCount
  end
  local count=be32(blob,txg) or 0
  if count<1 or count>128 then return end
  for ci=0,count-1 do
    if #out.textures>=maxTextures then break end
    local rel=be32(blob,txg+4+ci*4)
    local ca=rel and (txg+rel) or nil
    if ca and saneRange(ca,0x18,n) then
      local nb=be32(blob,ca) or 0
      local fmt=be32(blob,ca+4)
      local w,h=be32(blob,ca+0x0C),be32(blob,ca+0x10)
      if fmt and w and h and nb>0 and nb<=64 and w>=8 and h>=8 and w<=512 and h<=512 then
        local okSize,size=pcall(GX.dataSize,w,h,fmt)
        if okSize and type(size)=="number" and size>0 and size<=4*1024*1024 then
          for ti=0,nb-1 do
            if #out.textures>=maxTextures then break end
            local texRel=be32(blob,ca+0x18+ti*4)
            local start=texRel and (txg+texRel) or nil
            if start and saneRange(start,size,n) then
              local src=blob:sub(start+1,start+size)
              local okDec,rgba=pcall(GX.decode,src,w,h,fmt)
              if okDec and type(rgba)=="string" and #rgba==w*h*4 then
                local gray=(fmt==0 or fmt==1)
                -- Preserve GX intensity pixels. Older CBE revisions converted
                -- I4/I8 to a white alpha mask, destroying the intensity value
                -- Colosseum's Prim/Env TEV combiner uses to shade particle
                -- gradients. The runtime shader now consumes the source value.
                out.raw[#out.raw+1]={bytes=rgba,w=w,h=h,fmt=fmt,gray=gray,bank=bank,container=ci,texture=ti}
                out.textures[#out.textures+1]={w=w,h=h,fmt=fmt,gray=gray,bank=bank,container=ci,texture=ti}
              end
            end
          end
        end
      end
    end
  end
end

local function scanGPT1(blob,out)
  local sequenceMap=scanSequenceGPT1(blob)
  out.gptBanks=out.gptBanks or {}
  local pos=1;local bank=0
  while true do
    local s=blob:find("GPT1",pos,true);if not s then break end
    bank=bank+1
    local gptOff=s-1
    out.gptBanks[gptOff]=bank
    parseGPT1(blob,gptOff,bank,out,32,sequenceMap[gptOff])
    pos=s+4
    -- Keep scanning generator programs even after the texture decode cap is hit.
    -- Later GPT1 banks can still contain executable child/damage programs that
    -- reference textures already present in an earlier bank.
    if bank>=12 then break end
  end
end

-- Preserve the source WazaSequence sound commands even before the MusyX group
-- renderer is connected. The old GPT1 signature scan silently discarded them,
-- making a later audio replacement impossible without re-reading the disc.
-- Values are kept losslessly as the five source u32 fields plus entry timing.
local function scanSoundEntries(blob,out)
  -- Deprecated in 1.6.0. Earlier CBE revisions guessed source type 4 was sound.
  -- The retail dispatcher proved that label was speculative, so audio commands
  -- now remain losslessly preserved in the typed Waza timeline until their
  -- actual source type/subtype is identified from main.dol.
  return
end

-- Compile a proven type-2 Waza effect model once at extraction/cache time.
-- The retail sequence scheduler owns WHEN it exists; this cache contains only
-- source HSD geometry/material state so battle playback never reparses HSD.
local WAZA_MODEL_PAGE_SLOTS=12

local function wazaModelTopologyMatches(a,b)
  if not (a and b and #(a.groups or {})==#(b.groups or {})) then return false end
  for gi,g in ipairs(a.groups or {}) do
    local h=b.groups[gi]
    if not h or #(g.vertices or {})~=#(h.vertices or {}) then return false end
  end
  return true
end

local function wazaModelMotion(a,b)
  if not wazaModelTopologyMatches(a,b) then return math.huge end
  local maxd=0
  for gi,g in ipairs(a.groups or {}) do
    local h=b.groups[gi]
    for vi,v in ipairs(g.vertices or {}) do
      local q=h.vertices[vi]
      local dx=(tonumber(v[1]) or 0)-(tonumber(q[1]) or 0)
      local dy=(tonumber(v[2]) or 0)-(tonumber(q[2]) or 0)
      local dz=(tonumber(v[3]) or 0)-(tonumber(q[3]) or 0)
      local d=math.sqrt(dx*dx+dy*dy+dz*dz)
      if d>maxd then maxd=d end
    end
  end
  return maxd
end

local function wazaModelGroupShell(g,texSpec)
  return {vertices={},texture=texSpec,diffuse=g.diffuse,ambient=g.ambient,specular=g.specular,
    alpha=g.alpha,shininess=g.shininess,xlu=g.xlu==true,noz=g.noz==true,renderFlags=g.renderFlags,
    textureSlot=g.textureSlot,shadow=g.shadow==true,effect=g.effect==true,
    useConstant=g.useConstant==true,useVertexColor=g.useVertexColor==true,
    useDiffuseLighting=g.useDiffuseLighting~=false}
end

-- Type-2 Waza models can be every bit as dense as a Pokemon body. Never emit
-- their vertex scalars as one gigantic Lua table: LuaJIT has the same 65,536
-- constant ceiling that previously broke Charizard's Pokemon cache. Pack each
-- render group's rows into one string and expand it only after the metadata
-- chunk has loaded. Static rows use 8 floats; animated Waza pages use 44.
local function packedWazaVertices(vertices,stride)
  local rows={}
  stride=tonumber(stride) or 8
  for _,v in ipairs(vertices or {}) do
    local parts={}
    for i=1,stride do parts[i]=("%.9g"):format(tonumber(v[i]) or 0) end
    rows[#rows+1]=table.concat(parts,",")
  end
  return table.concat(rows,"\n")
end
local function packWazaGroups(groups,stride)
  local out={}
  for gi,g in ipairs(groups or {}) do
    local copy={}
    for k,v in pairs(g) do if k~="vertices" then copy[k]=v end end
    copy.vertexStride=stride
    copy.verticesPacked=packedWazaVertices(g.vertices,stride)
    out[gi]=copy
  end
  return out
end

local function wazaModelPage(base,poses,startFrame,endFrame,textureSpecs)
  local slotCount=math.max(0,math.min(WAZA_MODEL_PAGE_SLOTS,endFrame-startFrame))
  local groups={}
  for gi,g in ipairs(base.groups or {}) do
    local out=wazaModelGroupShell(g,textureSpecs[gi])
    for vi,v in ipairs(g.vertices or {}) do
      local row={v[1] or 0,v[2] or 0,v[3] or 0,v[4] or 0,v[5] or 0,v[6] or 0,v[7] or 1,v[8] or 0}
      for slot=1,WAZA_MODEL_PAGE_SLOTS do
        local frame=startFrame+math.min(slot,slotCount)
        local pose=poses[frame]
        local q=pose and pose.groups and pose.groups[gi] and pose.groups[gi].vertices and pose.groups[gi].vertices[vi] or v
        row[#row+1]=q[1] or v[1] or 0;row[#row+1]=q[2] or v[2] or 0;row[#row+1]=q[3] or v[3] or 0
      end
      out.vertices[vi]=row
    end
    groups[gi]=out
  end
  return {revision=3,source="GC6E01 WazaSequence type-2 HSD animated page",startFrame=startFrame,endFrame=endFrame,
    morphFrames=slotCount,groups=packWazaGroups(groups,44),bounds=base.bounds,vertexCount=base.vertexCount}
end

-- Compile a proven type-2 Waza effect model once at extraction/cache time.
-- Unlike the 1.6 bootstrap cache, this preserves the model's native HSD clip.
-- HSD curves are evaluated at each authored 60 Hz frame during extraction and
-- packed into overlapping 12-target GPU pages, so runtime playback is source
-- motion rather than an authored CBE approximation.
local function compileWazaModel(blob,entry,stem,phase)
  if not (HSD and type(HSD.extractModel)=="function" and type(blob)=="string"
      and type(entry)=="table" and tonumber(entry.dataOffset) and tonumber(entry.dataSize)) then
    return nil,"Waza model extractor unavailable"
  end
  local off,size=tonumber(entry.dataOffset),tonumber(entry.dataSize)
  if off<0 or size<=0 or off+size>#blob then return nil,"Waza model source range invalid" end
  local source=blob:sub(off+1,off+size)
  local decodeOpts={textures=true,maxRoots=48,maxVertices=90000,maxDisplayOps=300000,maxJobjs=4096,maxDobjs=12000,maxPobjs=20000}
  local model,err=HSD.extractModel(source,decodeOpts)
  if not model then return nil,err or "Waza HSD model decode failed" end

  local ident=tonumber(entry.identifier) or tonumber(entry.index) or 0
  local textureSpecs={};local textureCount=0
  for gi,g in ipairs(model.groups or {}) do
    local texSpec=nil;local t=g.texture
    if t and type(t.rgba)=="string" and tonumber(t.w) and tonumber(t.h) then
      local path=("cache/movefx/%s/models/%s_%03d_tex_%03d.rgba"):format(stem,phase,ident,gi)
      local okWrite,why=write(path,t.rgba)
      if not okWrite then return nil,why end
      texSpec={path=path,w=t.w,h=t.h,wrapS=t.wrapS,wrapT=t.wrapT,format=t.format,dataOffset=t.dataOffset}
      textureCount=textureCount+1
    end
    textureSpecs[gi]=texSpec
  end

  local animInfo=nil
  if type(HSD.nativeAnimationInfo)=="function" then animInfo=select(1,HSD.nativeAnimationInfo(model,0)) end
  local endFrame=animInfo and math.max(0,math.floor(tonumber(animInfo.endFrame) or 0)) or 0
  if endFrame>600 then return nil,("Waza model source animation exceeds safety bound: %d frames"):format(endFrame) end
  local animated=false;local poses={[0]=model};local maxMotion=0
  if endFrame>0 and type(HSD.extractNativePose)=="function" then
    -- Probe across the full clip first so static Type-2 objects do not pay the
    -- cost/storage of an animation page bank merely because an empty AOBJ exists.
    local probeFrames={math.max(1,math.floor(endFrame*.25)),math.max(1,math.floor(endFrame*.5)),
      math.max(1,math.floor(endFrame*.75)),endFrame}
    for _,fr in ipairs(probeFrames) do
      if not poses[fr] then
        local pose=select(1,HSD.extractNativePose(model,0,fr,decodeOpts))
        if pose and wazaModelTopologyMatches(model,pose) then poses[fr]=pose;maxMotion=math.max(maxMotion,wazaModelMotion(model,pose)) end
      end
    end
    animated=maxMotion>1e-5
  end

  local pages={}
  if animated then
    -- Evaluate every authored frame. Page boundaries overlap exactly and the
    -- runtime only blends adjacent source frames, matching the 60 Hz Waza clock.
    for fr=1,endFrame do
      if not poses[fr] then
        local pose,why=HSD.extractNativePose(model,0,fr,decodeOpts)
        if not pose then return nil,("Waza model animation frame %d decode failed: %s"):format(fr,tostring(why)) end
        if not wazaModelTopologyMatches(model,pose) then return nil,("Waza model animation topology changed at frame %d"):format(fr) end
        poses[fr]=pose
      end
    end
    local start=0
    while start<endFrame do
      local stop=math.min(endFrame,start+WAZA_MODEL_PAGE_SLOTS)
      local page=wazaModelPage(poses[start] or model,poses,start,stop,textureSpecs)
      local path=("cache/movefx/%s/models/%s_%03d_anim_%03d.lua"):format(stem,phase,ident,#pages+1)
      local okWrite,why=write(path,"return "..serialize(page).."\n")
      if not okWrite then return nil,why end
      pages[#pages+1]={cache=path,startFrame=start,endFrame=stop,morphFrames=stop-start}
      start=stop
    end
  end

  -- Static/base cache remains useful for truly static models and as a robust
  -- fail-open if an old runtime sees the asset without animation-page support.
  local groups={}
  for gi,g in ipairs(model.groups or {}) do
    groups[#groups+1]=wazaModelGroupShell(g,textureSpecs[gi]);groups[#groups].vertices=g.vertices
  end
  if #groups==0 then return nil,"Waza effect model has no drawable groups" end
  local cachePath=("cache/movefx/%s/models/%s_%03d.lua"):format(stem,phase,ident)
  local cache={revision=3,source="GC6E01 WazaSequence type-2 HSD",phase=phase,identifier=entry.identifier,
    bounds=model.bounds,vertexCount=model.vertexCount,groups=packWazaGroups(groups,8),
    animation={clip=0,endFrame=endFrame,frameCount=endFrame+1,animated=animated,maxMotion=maxMotion,pages=pages}}
  local okWrite,why=write(cachePath,"return "..serialize(cache).."\n")
  if not okWrite then return nil,why end
  return {cache=cachePath,groups=#groups,vertices=tonumber(model.vertexCount) or 0,textures=textureCount,bounds=model.bounds,
    animation={clip=0,endFrame=endFrame,frameCount=endFrame+1,animated=animated,maxMotion=maxMotion,pages=pages}}
end

local function extractWZX(disc,stem,phase)
  local file=disc and disc:file("wzx_"..stem.."_"..phase..".fsys")
  if not file then return nil,"source FSYS missing" end
  local okArc,arc=pcall(FSYS.open,disc,file); if not okArc or not arc then return nil,tostring(arc) end
  local list=arc:list() or {};local entry
  for _,e in ipairs(list) do if tostring(e.name or ""):lower():find("%.wzx$",1,false) then entry=e;break end end
  entry=entry or list[1];if not entry then return nil,"empty FSYS" end
  local blob,err=arc:extract(entry,{maxOutput=64*1024*1024})
  if not blob then return nil,err end
  local out={textures={},raw={},sounds={},programs={},maxLifetime=0,generators=0,phase=phase,member=entry.name,blob=blob}
  if Waza and type(Waza.parse)=="function" then
    local okTimeline,timeline,why=pcall(Waza.parse,blob,{phase=phase,member=entry.name})
    if okTimeline and type(timeline)=="table" then out.waza=timeline
    else out.wazaError=tostring(okTimeline and why or timeline) end
  end
  scanGPT1(blob,out)
  scanSoundEntries(blob,out)
  return out
end


local function cachedRoleReady(spec,role)
  if type(spec)~="table" then return false end
  local banks={}
  for _,t in ipairs(spec.textures or {}) do banks[tonumber(t.bank) or 1]=true end
  for _,g in ipairs(spec.generatorPrograms or {}) do
    local phase=tostring(g.phase or "all"):lower()
    local gRole=(phase=="damage" or phase=="status") and "damage" or "attack"
    if gRole==role and g.root==true and type(g.commandHex)=="string" and #g.commandHex>=2
        and banks[tonumber(g.bank) or 1] then return true end
  end
  return false
end

local ATTACK_PHASES={"attack","special","sp1","all"}
local DAMAGE_PHASES={"damage","status"}
local CANONICAL={attack=true,special=true,sp1=true,all=true,damage=true,status=true}
local function phasesFor(disc,stem,preferred)
  local found,variants={},{}
  local function exists(phase)
    phase=tostring(phase or ""):lower()
    if phase=="" then return false end
    if found[phase]~=nil then return found[phase] end
    found[phase]=disc:file("wzx_"..stem.."_"..phase..".fsys") and true or false
    return found[phase]
  end
  for _,phase in ipairs(preferred or {}) do exists(phase) end
  if type(disc.find)=="function" then
    local prefix="wzx_"..stem.."_"
    for _,file in ipairs(disc:find(prefix)) do
      local base=tostring(file.path or ""):lower():match("([^/]+)$") or ""
      local phase=base:match("^"..prefix:gsub("([^%w])","%%%1").."(.+)%.fsys$")
      if phase then
        found[phase]=true
        if not CANONICAL[phase] then variants[#variants+1]=phase end
      end
    end
  end
  -- One source attack program and one source damage program are selected.
  -- sp1/special and species-named files are alternates, not simultaneous layers.
  local out={}
  for _,phase in ipairs(ATTACK_PHASES) do if exists(phase) then out[#out+1]=phase;break end end
  for _,phase in ipairs(DAMAGE_PHASES) do if exists(phase) then out[#out+1]=phase;break end end
  table.sort(variants)
  return out,variants
end

M._internal={scanSequenceGPT1=scanSequenceGPT1,scanGPT1=scanGPT1,compileWazaModel=compileWazaModel}

-- Build the exact Colosseum capture-ball prop bank from the user's GC6E01 disc.
-- Every supported ball has its own WZX family; the ~7 KB type-2 HSD object in
-- those sequences is the source ball model (including its source texture and,
-- where authored, the native HSD clip used by shake/land/miss). No procedural
-- sphere or hand-authored recolor is used when this cache is available.
local CAPTURE_BALLS={
  poke={suffix="monster",aliases={"POKE_BALL","POKEBALL","MONSTER_BALL","BALL"}},
  great={suffix="super",aliases={"GREAT_BALL","GREATBALL","SUPER_BALL"}},
  ultra={suffix="hyper",aliases={"ULTRA_BALL","ULTRABALL","HYPER_BALL"}},
  master={suffix="master",aliases={"MASTER_BALL","MASTERBALL"}},
  safari={suffix="safari",aliases={"SAFARI_BALL","SAFARIBALL"}},
  net={suffix="net",aliases={"NET_BALL","NETBALL"}},
  nest={suffix="nest",aliases={"NEST_BALL","NESTBALL"}},
  repeatball={suffix="repeat",aliases={"REPEAT_BALL","REPEATBALL"}},
  timer={suffix="timer",aliases={"TIMER_BALL","TIMERBALL"}},
  dive={suffix="dive",aliases={"DIVE_BALL","DIVEBALL"}},
  premier={suffix="premire",aliases={"PREMIER_BALL","PREMIERBALL","PREMIRE_BALL"}},
  luxury={suffix="gorgeus",aliases={"LUXURY_BALL","LUXURYBALL","GORGEOUS_BALL","GORGEOUS"}},
}
local CAPTURE_PHASES={
  throw="snatch_attack",
  land="snatch_ball_land",
  shake="snatch_shake",
  miss="snatch_miss",
}
local function captureArchiveName(base,suffix)
  return "wzx_"..base..((suffix and suffix~="") and ("_"..suffix) or "")..".fsys"
end
local function captureSource(disc,archiveName)
  local file=disc and disc:file(archiveName);if not file then return nil,"source archive missing: "..archiveName end
  local okArc,arc=pcall(FSYS.open,disc,file);if not okArc or not arc then return nil,tostring(arc) end
  local list=arc:list() or {};local entry
  for _,candidate in ipairs(list) do
    if tostring(candidate.name or ""):lower():find("%.wzx$",1,false) then entry=candidate;break end
  end
  entry=entry or list[1];if not entry then return nil,"empty source archive: "..archiveName end
  local okBlob,blob=pcall(arc.extract,arc,entry,{maxOutput=64*1024*1024})
  if not okBlob or type(blob)~="string" then return nil,tostring(blob or "capture WZX extraction failed") end
  local okTimeline,timeline,why=pcall(Waza.parse,blob,{phase="capture",member=entry.name})
  if not okTimeline or type(timeline)~="table" then return nil,tostring(okTimeline and why or timeline) end
  return {blob=blob,timeline=timeline,member=entry.name,archive=archiveName}
end
local function captureBallEntry(timeline)
  local best,bestSize=nil,-1
  for _,entry in ipairs((timeline and timeline.entries) or {}) do
    if entry.kind=="model" then
      local size=tonumber(entry.dataSize or entry.embeddedSize) or 0
      -- The ball prop is consistently the compact ~7 KB type-2 object. Large
      -- entries are trainer/snag-machine/effect assemblies; tiny entries are
      -- helper planes. Keep a broad source-safe window for regional variants.
      if size>=3000 and size<=24000 and size>bestSize then best,bestSize=entry,size end
    end
  end
  return best,bestSize
end
function M.extractCaptureAssets(mod,disc,progress,generated)
  if not (mod and disc and Waza and type(Waza.parse)=="function") then return nil,"capture source extractor unavailable" end
  local previousMod,previousGenerated=M.mod,M.buildGenerated
  M.mod=mod;M.buildGenerated=generated;M.buildGeneratedSeen={}
  local index={revision=2,source="GC6E01 native snatch WZX type-2 ball models",balls={},aliases={}}
  local ids={"poke","great","ultra","master","safari","net","nest","repeatball","timer","dive","premier","luxury"}
  local failures={}
  local okRun,runErr=pcall(function()
    for bi,id in ipairs(ids) do
      if type(progress)=="function" then pcall(progress,"CAPTURE BALLS / "..id:upper(),bi-1,#ids) end
      local def=CAPTURE_BALLS[id];local row={id=id,suffix=def.suffix,phases={}}
      for phase,base in pairs(CAPTURE_PHASES) do
        local archive=captureArchiveName(base,def.suffix)
        local src,why=captureSource(disc,archive)
        if src then
          local entry,size=captureBallEntry(src.timeline)
          if entry then
            local stem="capture/"..id
            local asset,aerr=compileWazaModel(src.blob,entry,stem,phase)
            if asset then
              asset.sourceArchive=archive;asset.sourceMember=src.member;asset.sourceEntry=entry.identifier;asset.sourceBytes=size
              row.phases[phase]=asset
              local rawPath=("cache/capture/source/%s_%s.wzx"):format(id,phase)
              write(rawPath,src.blob);row.phases[phase].rawPath=rawPath
            else failures[#failures+1]=id.."/"..phase..": "..tostring(aerr) end
          else failures[#failures+1]=id.."/"..phase..": source ball type-2 model not found" end
        else failures[#failures+1]=id.."/"..phase..": "..tostring(why) end
      end
      -- Shake is the most compact/consistent source family and is mandatory;
      -- other phases may fail open to that exact same source prop.
      if not row.phases.shake then error("native capture ball missing for "..id) end
      index.balls[id]=row
      for _,alias in ipairs(def.aliases or {}) do index.aliases[tostring(alias):upper()]=id end
    end
    write("cache/capture/index.lua","return "..serialize(index).."\n")
    write("build/capture_source.txt",table.concat(failures,"\n")..(#failures>0 and "\n" or ""))
    if type(progress)=="function" then pcall(progress,"CAPTURE BALLS READY",#ids,#ids) end
  end)
  M.mod=previousMod;M.buildGenerated=previousGenerated;M.buildGeneratedSeen=nil
  if not okRun then return nil,tostring(runErr) end
  return {ready=true,count=#ids,failures=failures,index="cache/capture/index.lua"}
end

function M.install(mod,openDisc)
  M.mod=mod;M.openDisc=openDisc;return true
end
function M.cachePath(stem) return "cache/movefx/"..stem.."/effect.lua" end

function M.acquire(moveId,move)
  local p,id=profile(moveId,move);if not p then return nil,"unmapped move" end
  local candidates=sourceStemCandidates(p,id,move)
  if #candidates==0 then return nil,"no source stem candidates" end
  -- Cache hits are tried across every equivalent stem before touching the disc.
  for _,candidate in ipairs(candidates) do
    if M.memory[candidate]~=nil then
      if M.memory[candidate] then return M.memory[candidate] end
    else
      local cached=cacheReadLua(M.cachePath(candidate))
      if type(cached)=="table" and cached.revision==M.revision and cached.stem==candidate then
        M.memory[candidate]=cached;return cached
      end
    end
  end
  local negKey=tostring(id or norm(type(move)=="table" and (move.name or move.id or move.move) or moveId))
  if M.negative[negKey] then return nil,M.negative[negKey] end
  if type(M.openDisc)~="function" then return nil,"source disc opener unavailable" end
  local okDisc,disc=pcall(M.openDisc);if not okDisc or not disc then return nil,"source disc unavailable: "..tostring(disc) end
  local key,phases,variants
  local attempted={}
  for _,candidate in ipairs(candidates) do
    local found,var=phasesFor(disc,candidate,p.phases)
    attempted[#attempted+1]=candidate
    if #found>0 then key=candidate;phases=found;variants=var;break end
    M.memory[candidate]=false
  end
  if not key then
    local why="no source WZX archive for candidates: "..table.concat(attempted,",")
    M.negative[negKey]=why
    return nil,why
  end

  local banks,errors={},nil
  for _,phase in ipairs(phases) do
    local fx,err=extractWZX(disc,key,phase)
    if fx and (#fx.textures>0 or #fx.sounds>0 or #fx.programs>0
        or (type(fx.waza)=="table" and #(fx.waza.entries or {})>0)) then
      banks[#banks+1]=fx
    else errors=err or errors end
  end
  local meta={revision=M.revision,stem=key,moveId=id,style=p.style,tint=p.tint,stemCandidates=candidates,
    phase=banks[1] and banks[1].phase or nil,generators=0,maxLifetime=0,
    textures={},phases={},variants=variants or {},sounds={},generatorPrograms={},wazaPhases={},wazaModels=0,wazaModelErrors={},
    source="GC6E01 WazaSequence timeline + typed native handlers"}
  local nextGlobalBank=0
  for _,bankFx in ipairs(banks) do
    local phaseMeta={name=bankFx.phase,first=#meta.textures+1,count=0,generators=bankFx.generators or 0,roots=0,maxLifetime=bankFx.maxLifetime or 0}
    meta.generators=meta.generators+(bankFx.generators or 0)
    meta.maxLifetime=math.max(meta.maxLifetime,bankFx.maxLifetime or 0)

    -- GPT1 bank numbers are local to each WZX phase. Attack and damage files
    -- both commonly begin at bank 1; leaving those local ids unchanged merges
    -- unrelated texture tables at runtime and makes textureIndex select the
    -- wrong art. Remap every phase-local bank to a unique effect-global id and
    -- apply the same map to programs and textures.
    local bankMap={}
    local function globalBank(localBank)
      localBank=tonumber(localBank) or 1
      if not bankMap[localBank] then nextGlobalBank=nextGlobalBank+1;bankMap[localBank]=nextGlobalBank end
      return bankMap[localBank]
    end

    -- Preserve the complete WZX member byte-for-byte beside the interpreted
    -- cache. Unknown WazaSequence entry payloads can therefore be decoded in a
    -- later runtime revision without asking the user to re-import or re-extract
    -- the source disc. The typed timeline stores offsets into this raw copy.
    local rawWazaPath=("cache/movefx/%s/%s.wzx"):format(key,bankFx.phase)
    if type(bankFx.blob)=="string" then write(rawWazaPath,bankFx.blob) end
    if type(bankFx.waza)=="table" then
      local timeline={}
      for k,v in pairs(bankFx.waza) do if k~="entries" then timeline[k]=v end end
      timeline.rawPath=rawWazaPath
      timeline.entries={}
      for _,entry in ipairs(bankFx.waza.entries or {}) do
        local copy={};for k,v in pairs(entry) do copy[k]=v end
        copy.rawPath=rawWazaPath
        local localBank=entry.gptOffset and bankFx.gptBanks and bankFx.gptBanks[entry.gptOffset] or nil
        -- A real type-3 SequenceEntry does not necessarily embed a new GPT1.
        -- Flamethrower/Blizzard/Thunderbolt commonly load one bank in the first
        -- row and have later rows select another generator from it by REF id.
        -- Resolve those rows against the extracted generator table so the Waza
        -- scheduler can dispatch each authored particle beat independently.
        if not localBank and entry.kind=="particle" and entry.rootRef~=nil then
          local matchedOffset
          for _,program in ipairs(bankFx.programs or {}) do
            if program.refId~=nil and tonumber(program.refId)==tonumber(entry.rootRef) then
              localBank=tonumber(program.bank) or nil
              matchedOffset=program.gptOffset
              break
            end
          end
          if localBank then copy.resolvedGPTOffset=matchedOffset;copy.sharedParticleBank=true end
        end
        if localBank then
          copy.sourceBank=localBank
          copy.bank=globalBank(localBank)
        end
        if copy.kind=="model" then
          local asset,assetErr=compileWazaModel(bankFx.blob,entry,key,bankFx.phase)
          if asset then
            copy.modelAsset=asset;meta.wazaModels=meta.wazaModels+1
          else
            copy.modelError=tostring(assetErr or "Waza model decode unavailable")
            meta.wazaModelErrors[#meta.wazaModelErrors+1]={phase=bankFx.phase,identifier=copy.identifier,error=copy.modelError}
          end
        elseif copy.kind=="sound" then
          -- Type 5 is proven by retail wazaSequenceEntryStart/Update to be a
          -- GameSound command. Keep a flat index as well as the timed Waza row
          -- so the audio source compiler can discover every required SE id.
          meta.sounds[#meta.sounds+1]={phase=bankFx.phase,identifier=copy.identifier,
            soundId=copy.soundId,soundMode=copy.soundMode,soundParam=copy.soundParam,
            rawPath=rawWazaPath,sourceType=5}
        end
        timeline.entries[#timeline.entries+1]=copy
      end
      meta.wazaPhases[#meta.wazaPhases+1]=timeline
      phaseMeta.wazaEntries=#timeline.entries
      phaseMeta.wazaComplete=timeline.complete==true
      phaseMeta.wazaDurationFrames=timeline.durationFrames
    elseif bankFx.wazaError then
      phaseMeta.wazaError=bankFx.wazaError
    end

    for _,sound in ipairs(bankFx.sounds or {}) do
      local copy={phase=bankFx.phase};for k,v in pairs(sound) do copy[k]=v end
      meta.sounds[#meta.sounds+1]=copy
    end
    for _,program in ipairs(bankFx.programs or {}) do
      local copy={phase=bankFx.phase}
      for k,v in pairs(program) do copy[k]=v end
      copy.sourceBank=tonumber(program.bank) or 1
      copy.bank=globalBank(copy.sourceBank)
      if copy.root==true then phaseMeta.roots=phaseMeta.roots+1 end
      meta.generatorPrograms[#meta.generatorPrograms+1]=copy
    end
    for i,spec in ipairs(bankFx.raw) do
      local texPath=("cache/movefx/%s/%s_%02d.rgba"):format(key,bankFx.phase,i)
      -- GX I4/I8 return intensity in the color channels; for particle sheets the
      -- same intensity is also the coverage mask. Keeping alpha at 255 rendered
      -- every unused black texel as an opaque rectangular card. Preserve RGB
      -- intensity for Prim/Env interpolation while mirroring it into alpha.
      local runtimeBytes=spec.gray and intensityAlpha(spec.bytes) or spec.bytes
      local okWrite=write(texPath,runtimeBytes)
      if okWrite then
        local traits=textureTraits(runtimeBytes,spec.w,spec.h)
        local sourceBank=tonumber(spec.bank) or 1
        meta.textures[#meta.textures+1]={path=texPath,w=spec.w,h=spec.h,fmt=spec.fmt,gray=spec.gray,
          bank=globalBank(sourceBank),sourceBank=sourceBank,container=spec.container,texture=spec.texture,phase=bankFx.phase,
          coverage=traits.coverage,meanAlpha=traits.meanAlpha,contentW=traits.contentW,contentH=traits.contentH,
          contentScale=traits.contentScale}
        phaseMeta.count=phaseMeta.count+1
      end
    end
    phaseMeta.duration=math.max(.12,math.min(2.4,(tonumber(phaseMeta.maxLifetime) or 0)/60))
    if phaseMeta.count>0 then meta.phases[#meta.phases+1]=phaseMeta end
  end
  local latest=tonumber(meta.maxLifetime) or 0
  for _,program in ipairs(meta.generatorPrograms) do
    local start=program.sequence and tonumber(program.sequence.start) or 0
    if start and start>0 and start<3600 then latest=math.max(latest,start+(tonumber(program.lifetime) or 0)) end
  end
  local wazaLatest=0
  for _,phase in ipairs(meta.wazaPhases or {}) do
    wazaLatest=math.max(wazaLatest,tonumber(phase.durationFrames) or 0)
  end
  latest=math.max(latest,wazaLatest)
  meta.duration=math.max(.32,math.min(8.0,latest/60))
  meta.wazaReady=#(meta.wazaPhases or {})>0
  local rootCount=0;for _,g in ipairs(meta.generatorPrograms) do if g.root==true then rootCount=rootCount+1 end end
  meta.rootGenerators=rootCount
  meta.attackReady=cachedRoleReady(meta,"attack")
  meta.damageReady=cachedRoleReady(meta,"damage")
  if #meta.textures==0 then meta.duration=.6;meta.note=errors or "WZX has no decoded GPT1 texture bank" end
  -- Persist the phase metadata itself.  Earlier revisions wrote through an
  -- undefined `path`, so expensive WZX extraction could succeed for the live
  -- session yet silently miss its metadata cache on the next launch.
  local path=M.cachePath(key)
  write(path,"return "..serialize(meta).."\n")
  M.memory[key]=meta
  return meta
end

function M.peek(moveId,move)
  local p,id=profile(moveId,move);if not p then return nil,"unmapped move" end
  for _,key in ipairs(sourceStemCandidates(p,id,move)) do
    if M.memory[key]~=nil then if M.memory[key] then return M.memory[key] end
    else
      local cached=cacheReadLua(M.cachePath(key))
      if type(cached)=="table" and cached.revision==M.revision and cached.stem==key then
        M.memory[key]=cached;return cached
      end
    end
  end
  return nil,"not prefetched"
end

local function slotMoveId(slot)
  if type(slot)=="number" or type(slot)=="string" then return slot,nil end
  if type(slot)~="table" then return nil,nil end
  local def=type(slot.move)=="table" and slot.move or slot
  local id=slot.index or slot.moveId or slot.id or (type(slot.move)~="table" and slot.move) or slot.name
  return id,def
end

local function resolveMoveDef(battle,id,def)
  if type(def)=="table" and (def.name or def.power or def.type or def.category) then return def end
  local data=battle and battle.game and battle.game.data
  local moves=data and data.moves
  if type(moves)=="table" and id~=nil then
    if moves[id] then return moves[id] end
    local sid=tostring(id)
    if moves[sid] then return moves[sid] end
  end
  return type(def)=="table" and def or nil
end

local function prefetchKey(id,def)
  local d=describe(id,def)
  if not d then return nil end
  return tostring(d.stem or id or (type(def)=="table" and def.name) or "unknown")
end

-- Runtime discovery is intentionally QUEUED. Extraction is completed only at
-- non-attack presentation seams: game.ready, battle.started before CBE opens
-- its world, or the authoritative switch boundary before the replacement uses
-- a move. It is never run from a visible move/damage/capture frame. Older
-- builds synchronously extracted at impact-time and could produce black frames.
function M.queuePrefetch(moveId,move,battle)
  local def=resolveMoveDef(battle,moveId,move)
  local key=prefetchKey(moveId,def)
  if not key then return false,"unmapped move" end
  local cached=M.peek(moveId,def)
  if type(cached)=="table" then return true,"cached" end
  if M.pendingKeys[key] then return true,"queued" end
  M.pendingKeys[key]=true
  M.pending[#M.pending+1]={id=moveId,move=def,key=key}
  M.prefetchStats.queued=M.prefetchStats.queued+1
  return true,"queued"
end

function M.queueBattler(battle,battler)
  local mon=battler and (battler.mon or battler)
  local slots=mon and mon.moves or (battler and battler.moves)
  if type(slots)~="table" then return {requested=0,ready=0,queued=0,failed=0} end
  local out={requested=0,ready=0,queued=0,failed=0};local seen={}
  for _,slot in pairs(slots) do
    local id,def=slotMoveId(slot);def=resolveMoveDef(battle,id,def)
    local key=prefetchKey(id,def)
    if key and not seen[key] then
      seen[key]=true;out.requested=out.requested+1
      local spec=M.peek(id,def)
      if type(spec)=="table" then out.ready=out.ready+1
      else
        local ok=M.queuePrefetch(id,def,battle)
        if ok then out.queued=out.queued+1 else out.failed=out.failed+1 end
      end
    end
  end
  return out
end


function M.queueParty(game,maxMons)
  if type(game)~="table" or type(game.save)~="table" then return {requested=0,ready=0,queued=0,failed=0} end
  local party=game.save.party or game.save.pokemon or game.save.team
  if type(party)~="table" then return {requested=0,ready=0,queued=0,failed=0} end
  local limit=math.max(1,math.floor(tonumber(maxMons) or 1))
  local total={requested=0,ready=0,queued=0,failed=0};local used=0
  local battle={game=game}
  for _,mon in ipairs(party) do
    if used>=limit then break end
    if type(mon)=="table" then
      used=used+1
      local r=M.queueBattler(battle,{mon=mon})
      for k,v in pairs(r) do total[k]=(total[k] or 0)+(tonumber(v) or 0) end
    end
  end
  total.mons=used
  return total
end

function M.queueBattle(battle)
  local total={requested=0,ready=0,queued=0,failed=0}
  for _,side in ipairs({"player","enemy"}) do
    local r=M.queueBattler(battle,battle and battle[side])
    for k,v in pairs(r) do total[k]=(total[k] or 0)+(tonumber(v) or 0) end
  end
  return total
end

-- Backward-compatible names now queue only. No caller can accidentally turn
-- `prefetch` back into a synchronous presentation-path extractor.
M.prefetchBattler=M.queueBattler
M.prefetchBattle=M.queueBattle

function M.pumpPrefetch(maxItems)
  maxItems=math.max(0,math.floor(tonumber(maxItems) or 1))
  local out={processed=0,ready=0,failed=0,pending=#M.pending}
  while out.processed<maxItems and #M.pending>0 do
    local job=table.remove(M.pending,1);M.pendingKeys[job.key]=nil
    out.processed=out.processed+1
    local ok,spec,err=pcall(M.acquire,job.id,job.move)
    if ok and type(spec)=="table" then
      out.ready=out.ready+1;M.prefetchStats.completed=M.prefetchStats.completed+1
    else
      out.failed=out.failed+1;M.prefetchStats.failed=M.prefetchStats.failed+1
    end
  end
  out.pending=#M.pending
  return out
end

function M.clear()
  M.memory={};M.negative={};M.pending={};M.pendingKeys={};M.prefetchStats={queued=0,completed=0,failed=0};return true
end
function M.status() return {revision=M.revision,wazaRevision=Waza and Waza.revision or nil,cached=M.memory,negative=M.negative,sourceAliases=251,prefetch=true,peek=true,pending=#M.pending,prefetchStats=M.prefetchStats,
  prefetchPolicy="lead-party WZX warmed at game.ready; current battle banks completed before CBE world presentation begins; no source extraction on visible move/damage frames"} end
return M
