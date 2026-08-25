-- 0.0.51: ORRE WILDLANDS / MAX RUNTIME NATURALISM PASS
-- Generic wild outdoor battle biome.  The arena is intentionally nature-first:
-- textured meadow/forest floor, layered grass, barked tapering trees, visible
-- branch hierarchy, cutout leaf sprays, roots, undergrowth, rock and water.
local groups={}
local function V(x,y,z,u,v,r,g,b,a) return {x,y,z,u or 0,v or 0,r or 1,g or 1,b or 1,a or 1} end
local function G(tex,w,h,diff,amb,spec,shine,xlu)
  local g={vertices={},alpha=1,xlu=xlu and true or false,noz=false,
    diffuse=diff or {1,1,1},ambient=amb or {.5,.5,.5},specular=spec or {.01,.01,.01},shininess=shine or 1}
  if tex then g.texture={path=tex,w=w,h=h} end
  groups[#groups+1]=g;return g
end
local function T(g,a,b,c) g.vertices[#g.vertices+1]=a;g.vertices[#g.vertices+1]=b;g.vertices[#g.vertices+1]=c end
local function Q(g,a,b,c,d) T(g,a,b,c);T(g,a,c,d) end
local function clamp(v,a,b) if v<a then return a elseif v>b then return b end return v end
local function mix(a,b,t) return a+(b-a)*t end
local function hash01(n)
  -- Deterministic pseudo-random helper used for vegetation placement.  The
  -- old golden-angle/modulo radii were mathematically neat but visibly drew
  -- concentric grass rings around the battle field.  Hashing independent X/Z
  -- coordinates keeps the authored density reproducible without landscaping
  -- the meadow into a target pattern.
  local v=math.sin(n*12.9898+78.233)*43758.5453123
  return v-math.floor(v)
end
local function norm3(x,y,z) local l=math.sqrt(x*x+y*y+z*z);if l<.000001 then return 1,0,0 end;return x/l,y/l,z/l end

local ROOT="cache/stages/wildlands/"
local GROUND=ROOT.."ground_meadow_128.rgba"
local FOREST=ROOT.."ground_forest_128.rgba"
local BARK=ROOT.."bark_128.rgba"
local LEAFA=ROOT.."leaf_cluster_a_128.rgba"
local LEAFB=ROOT.."leaf_cluster_b_128.rgba"
local LEAFC=ROOT.."leaf_cluster_c_128.rgba"
local ROCK="cache/stages/d2_crater/textures/tex_0ce920_256x256_f14.rgba"

-- Ground ------------------------------------------------------------------
local meadow=G(GROUND,128,128,{.68,.79,.61},{.35,.52,.29},{.004,.004,.003},1)
local forestFloor=G(FOREST,128,128,{.64,.74,.57},{.30,.45,.25},{.003,.003,.003},1)
local soil=G(FOREST,128,128,{.60,.54,.40},{.29,.25,.18},{.002,.002,.002},1)
local moss=G(GROUND,128,128,{.52,.71,.47},{.27,.46,.23},{.002,.002,.002},1)
local N=144
local function groundH(x,z)
  local r=math.sqrt(x*x+z*z);local q=clamp((r-70)/115,0,1)
  local n=math.sin(x*.038+z*.012)*.42+math.cos(z*.046-x*.014)*.31+math.sin((x+z)*.021)*.24
  return n*(.14+.88*q)+q*q*.86
end
local function outerH(x,z)
  local r=math.sqrt(x*x+z*z);local a=math.atan(z,x);local t=clamp((r-155)/480,0,1)
  return groundH(x,z)+.9+t*13+t*t*16+(math.sin(a*2.0+.4)*5.8+math.sin(a*5.0-r*.007)*3.5+math.cos(a*9+r*.013)*1.8)*t
end
local function gv(x,z,outer)
  local y=outer and outerH(x,z) or groundH(x,z)
  local n=.5+.5*math.sin(x*.054+math.sin(z*.019)*1.7)*math.cos(z*.043-x*.011)
  local c=outer and {.78+.05*n,.88+.05*n,.73+.03*n} or {.86+.04*n,.94+.035*n,.82+.03*n}
  return V(x,y,z,x*.035,z*.035,c[1],c[2],c[3],1)
end
local rings={0,24,48,72,96,122,148,170}
for ri=1,#rings-1 do
  local r0,r1=rings[ri],rings[ri+1]
  for i=0,N-1 do local a0=2*math.pi*i/N;local a1=2*math.pi*(i+1)/N
    local p00,p01,p10,p11=gv(math.cos(a0)*r0,math.sin(a0)*r0,false),gv(math.cos(a1)*r0,math.sin(a1)*r0,false),gv(math.cos(a0)*r1,math.sin(a0)*r1,false),gv(math.cos(a1)*r1,math.sin(a1)*r1,false)
    T(meadow,p00,p10,p11);T(meadow,p00,p11,p01)
  end
end
local outer={170,210,260,320,390,465,545,620}
for ri=1,#outer-1 do
  local r0,r1=outer[ri],outer[ri+1]
  for i=0,N-1 do local a0=2*math.pi*i/N;local a1=2*math.pi*(i+1)/N
    local p00,p01,p10,p11=gv(math.cos(a0)*r0,math.sin(a0)*r0,true),gv(math.cos(a1)*r0,math.sin(a1)*r0,true),gv(math.cos(a0)*r1,math.sin(a0)*r1,true),gv(math.cos(a1)*r1,math.sin(a1)*r1,true)
    T(forestFloor,p00,p10,p11);T(forestFloor,p00,p11,p01)
  end
end
local function patch(g,cx,cz,rx,rz,seed,tint)
  local seg=20;local cy=groundH(cx,cz)+.10;local c=V(cx,cy,cz,cx*.035,cz*.035,tint[1],tint[2],tint[3],1)
  for i=0,seg-1 do
    local function p(a,k) local wob=1+.13*math.sin(k*2.7+seed)+.06*math.sin(k*5.1+seed*.7);local x=cx+math.cos(a)*rx*wob;local z=cz+math.sin(a)*rz*wob;return V(x,groundH(x,z)+.09,z,x*.035,z*.035,tint[1],tint[2],tint[3],1) end
    T(g,c,p(2*math.pi*i/seg,i),p(2*math.pi*(i+1)/seg,i+1))
  end
end
for i,p in ipairs({{-102,50,27,15},{94,-50,25,14},{-18,115,21,12},{120,95,24,14},{-130,-80,24,15},{45,-130,20,12}}) do patch(moss,p[1],p[2],p[3],p[4],i,{.73,.93,.66}) end
for i,p in ipairs({{-122,106,20,11},{125,-116,24,14},{-148,-20,18,10},{143,33,21,12}}) do patch(soil,p[1],p[2],p[3],p[4],20+i,{.78,.72,.56}) end

-- Tree materials ----------------------------------------------------------
local trunks=G(BARK,128,128,{.92,.82,.70},{.42,.34,.26},{.006,.005,.004},2)
local branches=G(BARK,128,128,{.88,.78,.65},{.40,.32,.24},{.005,.004,.003},2)
local roots=G(BARK,128,128,{.84,.76,.62},{.38,.30,.22},{.004,.003,.003},2)
local leafA=G(LEAFA,128,128,{1,1,1},{.46,.58,.38},{.002,.002,.002},1)
local leafB=G(LEAFB,128,128,{1,1,1},{.43,.54,.36},{.002,.002,.002},1)
local leafC=G(LEAFC,128,128,{1,1,1},{.48,.60,.39},{.002,.002,.002},1)
-- Textured grass billboards minify into hundreds of detached green/white
-- flecks at battle-camera distance. Keep the actual solid blade geometry and
-- remove that alpha-card layer entirely; foliage cards remain for tree crowns.
local grassGeo=G(nil,nil,nil,{.37,.70,.24},{.19,.40,.13},{.001,.001,.001},1)
local ferns=G(nil,nil,nil,{.30,.61,.19},{.16,.34,.10},{.001,.001,.001},1)

local function tube(g,x0,y0,z0,x1,y1,z1,r0,r1,seg,tint,twist)
  local ax,ay,az=norm3(x1-x0,y1-y0,z1-z0);local rx,ry,rz=0,1,0;if math.abs(ay)>.86 then rx,ry,rz=1,0,0 end
  local ux,uy,uz=norm3(ay*rz-az*ry,az*rx-ax*rz,ax*ry-ay*rx);local vx,vy,vz=ay*uz-az*uy,az*ux-ax*uz,ax*uy-ay*ux
  seg=seg or 10;twist=twist or 0
  for i=0,seg-1 do local a0=2*math.pi*i/seg+twist;local a1=2*math.pi*(i+1)/seg+twist
    local function p(x,y,z,r,a,v) local cs,sn=math.cos(a),math.sin(a);local sh=.88+.12*(.5+.5*math.cos(a-.7));return V(x+(ux*cs+vx*sn)*r,y+(uy*cs+vy*sn)*r,z+(uz*cs+vz*sn)*r,a/(2*math.pi),v,tint[1]*sh,tint[2]*sh,tint[3]*sh,1) end
    Q(g,p(x0,y0,z0,r0,a0,1),p(x0,y0,z0,r0,a1,1),p(x1,y1,z1,r1,a1,0),p(x1,y1,z1,r1,a0,0))
  end
end
local function rootWedge(cx,base,cz,a,len,w,h,tint)
  local cs,sn=math.cos(a),math.sin(a);local px,pz=-sn,cs;local ex,ez=cx+cs*len,cz+sn*len
  local apex=V(cx,base+h,cz,.5,0,tint[1],tint[2],tint[3],1)
  local p0=V(cx+px*w,base,cz+pz*w,0,1,tint[1],tint[2],tint[3],1);local p1=V(cx-px*w,base,cz-pz*w,1,1,tint[1],tint[2],tint[3],1)
  local p2=V(ex-px*w*.18,base-.12,ez-pz*w*.18,1,0,tint[1]*.9,tint[2]*.9,tint[3]*.9,1);local p3=V(ex+px*w*.18,base-.12,ez+pz*w*.18,0,0,tint[1]*.9,tint[2]*.9,tint[3]*.9,1)
  T(roots,p0,p1,apex);T(roots,p1,p2,apex);T(roots,p2,p3,apex);T(roots,p3,p0,apex)
end

-- Alpha-cut foliage cards.  Several crossing/tilted planes per branch tip
-- produce an irregular leafy crown without the solid poly-ball silhouette.
local function leafQuad(g,cx,cy,cz,w,h,yaw,tilt,seed)
  local dx,dz=math.cos(yaw),math.sin(yaw);local rx,rz=-dz,dx;local ux,uy,uz=math.sin(tilt)*dx,math.cos(tilt),math.sin(tilt)*dz
  local hw,hh=w*.5,h*.5;local jitter=.08*math.sin(seed*1.9)
  local function p(sx,sy,u,v)
    return V(cx+rx*hw*sx+ux*hh*sy,cy+uy*hh*sy+jitter,cz+rz*hw*sx+uz*hh*sy,u,v,1,1,1,1)
  end
  Q(g,p(-1,-1,0,1),p(1,-1,1,1),p(1,1,1,0),p(-1,1,0,0))
end
local function foliageSpray(cx,cy,cz,scale,seed,dense)
  local n=dense and 8 or 6
  for i=1,n do
    local g=(i%3==0) and leafC or ((i%2==0) and leafB or leafA)
    local yaw=seed*.47+i*2.399963;local tilt=(-.20+.10*((i+seed)%5))
    local w=scale*(1.00+.17*math.sin(seed+i*1.7));local h=scale*(.78+.15*math.cos(seed*.8+i))
    local ox=math.cos(yaw*1.7)*scale*.16;local oz=math.sin(yaw*1.7)*scale*.16;local oy=((i%3)-1)*scale*.08
    leafQuad(g,cx+ox,cy+oy,cz+oz,w,h,yaw,tilt,seed+i)
  end
end

local function treeAt(cx,cz,scale,seed,ancient)
  local r=math.sqrt(cx*cx+cz*cz);local base=(r<170 and groundH(cx,cz) or outerH(cx,cz))-.15
  local trunkR=(ancient and 5.5 or 2.7)*scale;local trunkH=(ancient and 48 or 33)*scale
  local leanX=(math.sin(seed*1.37)*2.3+(ancient and math.sin(seed*.43)*2.0 or 0))*scale;local leanZ=(math.cos(seed*1.11)*2.1+(ancient and math.cos(seed*.51)*1.7 or 0))*scale
  local bark=ancient and {.97,.90,.77} or {.79,.68,.54}
  local x1,y1,z1=cx+leanX*.18,base+trunkH*.27,cz+leanZ*.18
  local x2,y2,z2=cx+leanX*.44,base+trunkH*.53,cz+leanZ*.44
  local x3,y3,z3=cx+leanX*.72,base+trunkH*.76,cz+leanZ*.72
  local x4,y4,z4=cx+leanX,base+trunkH,cz+leanZ
  tube(trunks,cx,base,cz,x1,y1,z1,trunkR,trunkR*.88,12,bark,seed*.07)
  tube(trunks,x1,y1,z1,x2,y2,z2,trunkR*.88,trunkR*.69,11,bark,seed*.11)
  tube(trunks,x2,y2,z2,x3,y3,z3,trunkR*.69,trunkR*.48,10,bark,seed*.15)
  tube(trunks,x3,y3,z3,x4,y4,z4,trunkR*.48,trunkR*.28,9,bark,seed*.19)
  local rootsN=ancient and 9 or 6
  for j=1,rootsN do rootWedge(cx,base+.04,cz,2*math.pi*j/rootsN+seed*.24,(ancient and 19 or 10)*scale,(ancient and 3.5 or 1.8)*scale,(ancient and 4.7 or 2.2)*scale,bark) end
  local branchN=ancient and 11 or 8
  for j=1,branchN do
    local a=2*math.pi*j/branchN+seed*.37+(j%2)*.18;local t=.43+.43*((j*3)%7)/6
    local ox=mix(x2,x4,t);local oy=mix(y2,y4,t);local oz=mix(z2,z4,t)
    local len=(ancient and 23 or 15)*scale*(.82+.20*math.sin(seed+j*1.7));local rise=(3.2+5.0*math.sin(seed*.5+j*.79))*scale
    local ex=ox+math.cos(a)*len*.50;local ez=oz+math.sin(a)*len*.50;local ey=oy+rise*.35
    local tx=ox+math.cos(a)*len;local tz=oz+math.sin(a)*len;local ty=oy+rise
    tube(branches,ox,oy,oz,ex,ey,ez,trunkR*.31,trunkR*.18,7,bark,a)
    tube(branches,ex,ey,ez,tx,ty,tz,trunkR*.18,trunkR*.065,6,bark,a+.27)
    -- two twig forks, each with its own foliage spray
    for k=-1,1,2 do
      local aa=a+k*(.42+.08*math.sin(seed+j));local tl=len*.38
      local sx=ex+math.cos(aa)*tl;local sz=ez+math.sin(aa)*tl;local sy=ey+(2.5+k*.5)*scale
      tube(branches,ex,ey,ez,sx,sy,sz,trunkR*.14,trunkR*.035,5,bark,aa)
      foliageSpray(sx,sy+2.0*scale,sz,(ancient and 11.2 or 7.8)*scale,seed+j*11+k,ancient)
    end
    foliageSpray(tx,ty+2.1*scale,tz,(ancient and 12.5 or 8.5)*scale,seed+j*5.7,ancient)
  end
  foliageSpray(x4,y4+7*scale,z4,(ancient and 17 or 11.5)*scale,seed+91,true)
  foliageSpray(x4-5*scale,y4+13*scale,z4+3*scale,(ancient and 15 or 10.5)*scale,seed+109,true)
end

-- Tree distribution keeps the battle field open but builds a thick, layered
-- forest wall with foreground/mid/far silhouettes.
local treeList={}
for i=1,42 do local a=2*math.pi*i/42+.10*math.sin(i*1.61);local r=186+((i*47)%132)+10*math.sin(i*2.17);treeList[#treeList+1]={math.cos(a)*r,math.sin(a)*r,.82+.075*(i%6),i,false} end
for i=1,30 do local a=2*math.pi*i/30+.08*math.sin(i*.9)+.21;local r=315+((i*61)%175);treeList[#treeList+1]={math.cos(a)*r,math.sin(a)*r,.88+.10*(i%5),60+i,false} end
local ancients={{-198,150,1.25,151,true},{210,164,1.22,152,true},{-235,-184,1.31,153,true},{244,-168,1.27,154,true},{-365,54,1.39,155,true},{372,88,1.37,156,true},{-338,286,1.31,157,true},{346,-278,1.35,158,true}}
for _,t in ipairs(treeList) do treeAt(t[1],t[2],t[3],t[4],t[5]) end
for _,t in ipairs(ancients) do treeAt(t[1],t[2],t[3],t[4],t[5]) end

-- Grass -------------------------------------------------------------------
local clears={{-18,72,24},{18,-72,24},{60,124,27},{-60,-124,27}}
local function clearActor(x,z) for _,p in ipairs(clears) do local dx,dz=x-p[1],z-p[2];if dx*dx+dz*dz<p[3]*p[3] then return true end end return false end
local function grassCard(cx,cz,h,w,yaw,seed)
  -- Deliberately disabled.  Solid blade() geometry below supplies the meadow
  -- detail without transparent cards floating above the ground in motion.
end
local function blade(cx,cz,h,w,a,bend,seed)
  local base=(math.sqrt(cx*cx+cz*cz)<170 and groundH(cx,cz) or outerH(cx,cz))+.07;local dx,dz=math.cos(a),math.sin(a);local px,pz=-dz,dx;local mx,mz=cx+dx*bend*.45,cz+dz*bend*.45;local tx,tz=cx+dx*bend,cz+dz*bend
  local c=.88+.10*math.sin(seed*2.1)
  local l0=V(cx+px*w,base,cz+pz*w,0,1,.42*c,.78*c,.27*c,1);local r0=V(cx-px*w,base,cz-pz*w,1,1,.36*c,.71*c,.23*c,1)
  local l1=V(mx+px*w*.6,base+h*.55,mz+pz*w*.6,.1,.45,.46*c,.82*c,.28*c,1);local r1=V(mx-px*w*.6,base+h*.55,mz-pz*w*.6,.9,.45,.39*c,.75*c,.24*c,1)
  local tip=V(tx,base+h,tz,.5,0,.52*c,.88*c,.31*c,1);Q(grassGeo,l0,r0,r1,l1);T(grassGeo,l1,r1,tip)
end
-- Inner meadow: irregular field growth rather than radial rings.  We scatter
-- candidates over a square, reject outside the playable meadow, and modulate
-- acceptance with broad low-frequency patches.  This produces natural gaps,
-- thick pockets and crossing clumps without any repeated circular radius.
for i=1,700 do
  local x=(hash01(i*3.117+7.3)-.5)*382
  local z=(hash01(i*7.931+31.7)-.5)*382
  local rr=math.sqrt(x*x+z*z)
  local patch=.54+.25*math.sin(x*.031+math.sin(z*.017)*1.7)+.18*math.cos(z*.027-x*.011)
  local accept=clamp(.56+patch*.30,0.42,.93)
  if rr<190 and rr>105 and hash01(i*11.73+2.1)<accept*.82 and not clearActor(x,z) then
    local h=1.55+hash01(i*5.27+13.0)*1.55
    local a=hash01(i*9.41+4.6)*math.pi*2
    local cluster=hash01(i*17.19+8.2)
    grassCard(x,z,h*(1.88+.26*cluster),1.72+.70*hash01(i*2.53+1.4),a,i)
    if cluster>.22 then grassCard(x+.35*math.sin(a),z-.35*math.cos(a),h*(1.48+.28*cluster),1.40+.55*hash01(i*3.71+5.2),a+1.57,i+10000) end
    local blades=cluster>.68 and 3 or 2
    for j=1,blades do
      local ja=a+j*1.73+hash01(i*23+j)*.48
      local ox=(hash01(i*31+j*7)-.5)*1.35
      local oz=(hash01(i*37+j*11)-.5)*1.35
      blade(x+ox,z+oz,h*(.52+.09*j),.22+.08*hash01(i+j*19),ja,.45+.48*hash01(i*43+j),i*7+j)
    end
  end
end

-- Outer meadow/forest transition.  Independent hashed coordinates and broad
-- patch noise replace the old annular modulo bands, so distant grass also
-- reads as terrain ecology rather than concentric rings around the arena.
for i=1,1850 do
  local x=(hash01(i*4.913+19.7)-.5)*1110
  local z=(hash01(i*8.447+71.2)-.5)*1110
  local rr=math.sqrt(x*x+z*z)
  local patch=.50+.28*math.sin(x*.018-z*.011)+.17*math.cos(z*.024+x*.009)
  if rr>164 and rr<552 and hash01(i*13.57+3.4)<clamp(.46+patch*.22,.28,.76) then
    local h=2.45+hash01(i*5.83+20.0)*3.15
    local a=hash01(i*6.71+2.3)*math.pi*2
    grassCard(x,z,h,2.15+.95*hash01(i*3.17),a,20000+i)
    if hash01(i*17.3)>.27 then
      grassCard(x+.55*math.sin(a),z-.55*math.cos(a),h*(.72+.22*hash01(i*2.9)),1.9+.85*hash01(i*7.1),a+1.57,30000+i)
    end
  end
end

-- Understory --------------------------------------------------------------
local function fernAt(cx,cz,scale,seed)
  local base=outerH(cx,cz)+.08
  for j=1,9 do local a=2*math.pi*j/9+seed*.19;local len=5.3*scale*(.82+.17*math.sin(seed+j));local wid=.72*scale;local dx,dz=math.cos(a),math.sin(a);local px,pz=-dz,dx
    local mx,my,mz=cx+dx*len*.50,base+1.35*scale,cz+dz*len*.50;local tx,ty,tz=cx+dx*len,base+.5*scale,cz+dz*len
    Q(ferns,V(cx+px*wid,base,cz+pz*wid,0,1,.28,.61,.18,1),V(cx-px*wid,base,cz-pz*wid,1,1,.25,.57,.17,1),V(mx-px*wid*.45,my,mz-pz*wid*.45,.82,.45,.31,.66,.19,1),V(mx+px*wid*.45,my,mz+pz*wid*.45,.18,.45,.34,.69,.20,1));T(ferns,V(mx+px*wid*.45,my,mz+pz*wid*.45,.18,.45,.34,.69,.20,1),V(mx-px*wid*.45,my,mz-pz*wid*.45,.82,.45,.31,.66,.19,1),V(tx,ty,tz,.5,0,.39,.73,.22,1))
  end
end
for i=1,170 do local a=i*2.17+.4;local rr=180+((i*53)%345);fernAt(math.cos(a)*rr,math.sin(a)*rr,.76+.075*(i%6),i) end
for i=1,120 do local a=i*2.09;local rr=176+((i*47)%350);local x,z=math.cos(a)*rr,math.sin(a)*rr;local y=outerH(x,z)+4.0;foliageSpray(x,y,z,6.4+(i%4)*.8,400+i,false) end

-- Rock --------------------------------------------------------------------
local rocks=G(ROCK,256,256,{.62,.54,.45},{.31,.27,.21},{.01,.01,.01},2)
local rockMoss=G(GROUND,128,128,{.62,.82,.54},{.29,.46,.24},{.002,.002,.002},1)
local function boulder(cx,cz,rx,ry,rz,seed)
  local r=math.sqrt(cx*cx+cz*cz);local base=(r<170 and groundH(cx,cz) or outerH(cx,cz))-1;local seg=14;local levels={{0,1},{.28,.97},{.58,.75},{.82,.43},{1,.10}};local pts={}
  for k,l in ipairs(levels) do pts[k]={};for i=0,seg-1 do local a=2*math.pi*i/seg;local wob=1+.10*math.sin(seed*1.7+i*2.03+k*.7)+.04*math.sin(i*4.7-seed);pts[k][i+1]={cx+math.cos(a)*rx*l[2]*wob,base+ry*l[1],cz+math.sin(a)*rz*l[2]*wob} end end
  for k=1,#levels-1 do for i=1,seg do local j=i%seg+1;local p0,p1,p2,p3=pts[k][i],pts[k][j],pts[k+1][j],pts[k+1][i];local sh=.75+.04*k
    Q(rocks,V(p0[1],p0[2],p0[3],p0[1]*.02,p0[3]*.02,sh,sh*.90,sh*.78,1),V(p1[1],p1[2],p1[3],p1[1]*.02,p1[3]*.02,sh,sh*.90,sh*.78,1),V(p2[1],p2[2],p2[3],p2[1]*.02,p2[3]*.02,sh+.02,(sh+.02)*.90,(sh+.02)*.78,1),V(p3[1],p3[2],p3[3],p3[1]*.02,p3[3]*.02,sh+.02,(sh+.02)*.90,(sh+.02)*.78,1)) end end
  if seed%2==0 then local cy=base+ry*.84;for i=0,11 do local a0=2*math.pi*i/12;local a1=2*math.pi*(i+1)/12;T(rockMoss,V(cx,cy+ry*.06,cz,cx*.03,cz*.03,.72,.90,.65,1),V(cx+math.cos(a0)*rx*.35,cy,cz+math.sin(a0)*rz*.35,0,1,.66,.84,.59,1),V(cx+math.cos(a1)*rx*.35,cy,cz+math.sin(a1)*rz*.35,1,1,.66,.84,.59,1)) end end
end
local rockList={{-146,118,18,18,17,1},{151,-130,21,17,19,2},{-182,-119,25,23,21,3},{178,143,23,20,20,4},{-291,94,34,29,29,5},{308,-98,39,34,33,6},{-346,-184,46,40,39,7},{342,198,43,37,37,8},{-472,32,59,53,51,9},{466,-22,58,51,49,10},{-414,286,51,45,47,11},{418,-297,56,49,51,12}}
for _,r in ipairs(rockList) do boulder(r[1],r[2],r[3],r[4],r[5],r[6]) end
for i=1,42 do local a=i*2.41;local rr=170+((i*67)%385);boulder(math.cos(a)*rr,math.sin(a)*rr,3.5+(i%4)*1.3,3.2+(i%3)*1.1,4+(i%5),30+i) end

-- Stream ------------------------------------------------------------------
local water=G(nil,nil,nil,{.22,.55,.69},{.12,.30,.40},{.08,.10,.12},16,true);water.alpha=.76;water.flow=1
local banks=G(FOREST,128,128,{.74,.84,.64},{.31,.46,.26},{.002,.002,.002},1)
local reeds=G(nil,nil,nil,{.34,.62,.20},{.18,.35,.11},{.001,.001,.001},1)
local pts={};for i=0,32 do local z=-470+i*29;local x=-332+35*math.sin(i*.41)+13*math.sin(i*.93);pts[#pts+1]={x,outerH(x,z)+.15,z} end
for i=1,#pts-1 do local p0,p1=pts[i],pts[i+1];local dx,dz=p1[1]-p0[1],p1[3]-p0[3];local len=math.max(.001,math.sqrt(dx*dx+dz*dz));local px,pz=-dz/len,dx/len;local w0=8.5+1.4*math.sin(i*.7);local w1=8.5+1.4*math.sin((i+1)*.7)
  Q(water,V(p0[1]+px*w0,p0[2],p0[3]+pz*w0,0,i*.22,.61,.82,.92,.76),V(p0[1]-px*w0,p0[2],p0[3]-pz*w0,1,i*.22,.61,.82,.92,.76),V(p1[1]-px*w1,p1[2],p1[3]-pz*w1,1,(i+1)*.22,.61,.82,.92,.76),V(p1[1]+px*w1,p1[2],p1[3]+pz*w1,0,(i+1)*.22,.61,.82,.92,.76))
  local bw=5.2;Q(banks,V(p0[1]+px*w0,p0[2]+.02,p0[3]+pz*w0,p0[1]*.035,p0[3]*.035,.88,.96,.82,1),V(p0[1]+px*(w0+bw),p0[2]+.9,p0[3]+pz*(w0+bw),0,0,.80,.91,.74,1),V(p1[1]+px*(w1+bw),p1[2]+.9,p1[3]+pz*(w1+bw),1,1,.80,.91,.74,1),V(p1[1]+px*w1,p1[2]+.02,p1[3]+pz*w1,1,0,.88,.96,.82,1))
  Q(banks,V(p0[1]-px*(w0+bw),p0[2]+.9,p0[3]-pz*(w0+bw),0,0,.80,.91,.74,1),V(p0[1]-px*w0,p0[2]+.02,p0[3]-pz*w0,1,0,.88,.96,.82,1),V(p1[1]-px*w1,p1[2]+.02,p1[3]-pz*w1,1,1,.88,.96,.82,1),V(p1[1]-px*(w1+bw),p1[2]+.9,p1[3]-pz*(w1+bw),0,1,.80,.91,.74,1))
  if i%2==0 then for side=-1,1,2 do local cx=p0[1]+px*(w0+2.5)*side;local cz=p0[3]+pz*(w0+2.5)*side;local base=p0[2]+.7;for j=1,5 do local off=(j-3)*.7;local bx=cx+dx/len*off;local bz=cz+dz/len*off;local h=3.1+.42*j;T(reeds,V(bx-.15,base,bz,0,1,.30,.58,.18,1),V(bx+.15,base,bz,1,1,.30,.58,.18,1),V(bx+.18*side,base+h,bz,.5,0,.39,.68,.22,1)) end end end
end

-- Distant forest/horizon --------------------------------------------------
local cliffs=G(ROCK,256,256,{.56,.50,.42},{.29,.25,.20},{.008,.008,.006},2)
local farLeaf=G(LEAFB,128,128,{.82,.93,.79},{.38,.50,.33},{.001,.001,.001},1)
for i=0,35 do local a0=2*math.pi*i/36;local a1=2*math.pi*(i+1)/36;local r0=580+18*math.sin(i*1.7);local r1=580+18*math.sin((i+1)*1.7);local x0,z0=math.cos(a0)*r0,math.sin(a0)*r0;local x1,z1=math.cos(a1)*r1,math.sin(a1)*r1;local y0=outerH(x0,z0)-5;local y1=outerH(x1,z1)-5;local t0=y0+19+8*(.5+.5*math.sin(i*.83));local t1=y1+19+8*(.5+.5*math.sin((i+1)*.83));Q(cliffs,V(x0,y0,z0,0,1,.65,.58,.49,1),V(x1,y1,z1,1,1,.65,.58,.49,1),V(x1,t1,z1,1,0,.60,.54,.46,1),V(x0,t0,z0,0,0,.60,.54,.46,1)) end
for i=1,78 do local a=2*math.pi*i/78+.03*math.sin(i*1.3);local r=500+((i*23)%86);local x,z=math.cos(a)*r,math.sin(a)*r;local y=outerH(x,z)+24;for k=0,2 do leafQuad(farLeaf,x+math.cos(a+k*2.1)*6,y+k*3,z+math.sin(a+k*2.1)*6,24+(i%4)*3,19+(i%3)*3,a+k*1.05,.04,800+i+k) end end

local total=0;for _,g in ipairs(groups) do total=total+#g.vertices end
return {version=17,source="Pokemon Colosseum / Orre Wildlands grounded solid-grass artifact cleanup",prototype=false,bounds={min={-650,-8,-650},max={650,155,650}},groupCount=#groups,vertexCount=total,groups=groups}
