-- 0.0.63: Mt. Battle presentation-quality pass
-- Clean structural rebuild. The battlefield, rim, support body, bridge, crater,
-- lava and horizon geology form one continuous environment; no decorative
-- industrial fragment is allowed to hover without a physical support path.
local groups={}
local function V(x,y,z,u,v,r,g,b,a) return {x,y,z,u or 0,v or 0,r or 1,g or 1,b or 1,a or 1} end
local function G(tex,w,h,diff,amb,spec,shine,xlu)
  local g={vertices={},alpha=1,xlu=xlu and true or false,noz=false,
    diffuse=diff or {1,1,1},ambient=amb or {.42,.39,.39},specular=spec or {.03,.03,.03},shininess=shine or 3}
  if tex then g.texture={path=tex,w=w,h=h} end
  groups[#groups+1]=g; return g
end
local function T(g,a,b,c) g.vertices[#g.vertices+1]=a;g.vertices[#g.vertices+1]=b;g.vertices[#g.vertices+1]=c end
local function Q(g,a,b,c,d) T(g,a,b,c);T(g,a,c,d) end

local ROOT="cache/stages/d2_crater/textures/"
local METAL=ROOT.."tex_0f4120_128x128_f14.rgba"
local TRIM=ROOT.."tex_07cec0_128x64_f14.rgba"
local ROCK=ROOT.."tex_0ce920_256x256_f14.rgba"
local ROCK2=ROOT.."tex_061ec0_256x256_f14.rgba"
local LAVA=ROOT.."tex_0ca920_128x256_f14.rgba"
local LAVA2=ROOT.."tex_0ea920_128x128_f14.rgba"
local TRUSS=ROOT.."tex_0fd8e0_256x256_f14.rgba"

local deck=G(METAL,128,128,{.77,.75,.72},{.38,.36,.35},{.10,.09,.08},10)
local deckDark=G(METAL,128,128,{.38,.38,.40},{.22,.21,.22},{.05,.05,.05},5)
local deckPanel=G(METAL,128,128,{.60,.59,.60},{.30,.29,.30},{.08,.075,.07},8)
local trim=G(TRIM,128,64,{.82,.62,.22},{.36,.27,.13},{.06,.045,.02},6)
local rock=G(ROCK,256,256,{.38,.34,.34},{.17,.15,.16},{.005,.004,.004},1)
local rockDark=G(ROCK2,256,256,{.23,.22,.23},{.105,.10,.11},{.003,.002,.002},1)
local lava=G(LAVA,128,256,{1.00,.57,.24},{.65,.26,.10},{.02,.01,.005},1)
local lava2=G(LAVA2,128,128,{1.00,.67,.29},{.70,.31,.11},{.02,.01,.005},1)
local truss=G(TRUSS,256,256,{.42,.39,.39},{.22,.20,.20},{.04,.04,.04},4,true)
local marking=G(nil,nil,nil,{.74,.19,.23},{.34,.08,.09},{.02,.01,.01},2)
local numberMark=G(nil,nil,nil,{.82,.78,.72},{.42,.37,.34},{.02,.02,.02},2)

local function ring(g,r0,r1,y0,y1,segments,uv,tint)
  segments=segments or 128;uv=uv or .018;tint=tint or {1,1,1,1}
  if r0<=.001 then
    for i=0,segments-1 do
      local a0=i/segments*math.pi*2;local a1=(i+1)/segments*math.pi*2
      T(g,V(0,y0,0,.5,.5,tint[1],tint[2],tint[3],tint[4]),
        V(math.cos(a0)*r1,y1,math.sin(a0)*r1,math.cos(a0)*r1*uv,math.sin(a0)*r1*uv,tint[1],tint[2],tint[3],tint[4]),
        V(math.cos(a1)*r1,y1,math.sin(a1)*r1,math.cos(a1)*r1*uv,math.sin(a1)*r1*uv,tint[1],tint[2],tint[3],tint[4]))
    end; return
  end
  for i=0,segments-1 do
    local a0=i/segments*math.pi*2;local a1=(i+1)/segments*math.pi*2
    local c0,s0=math.cos(a0),math.sin(a0);local c1,s1=math.cos(a1),math.sin(a1)
    T(g,V(c0*r0,y0,s0*r0,c0*r0*uv,s0*r0*uv,tint[1],tint[2],tint[3],tint[4]),V(c0*r1,y1,s0*r1,c0*r1*uv,s0*r1*uv,tint[1],tint[2],tint[3],tint[4]),V(c1*r1,y1,s1*r1,c1*r1*uv,s1*r1*uv,tint[1],tint[2],tint[3],tint[4]))
    T(g,V(c0*r0,y0,s0*r0,c0*r0*uv,s0*r0*uv,tint[1],tint[2],tint[3],tint[4]),V(c1*r1,y1,s1*r1,c1*r1*uv,s1*r1*uv,tint[1],tint[2],tint[3],tint[4]),V(c1*r0,y0,s1*r0,c1*r0*uv,s1*r0*uv,tint[1],tint[2],tint[3],tint[4]))
  end
end
local function sectorRing(g,r0,r1,a0,a1,y,tint)
  tint=tint or {1,1,1,1}
  local steps=5
  for i=0,steps-1 do
    local t0=i/steps;local t1=(i+1)/steps
    local p0=a0+(a1-a0)*t0;local p1=a0+(a1-a0)*t1
    local c0,s0=math.cos(p0),math.sin(p0);local c1,s1=math.cos(p1),math.sin(p1)
    Q(g,V(c0*r0,y,s0*r0,c0*r0*.026,s0*r0*.026,tint[1],tint[2],tint[3],tint[4]),
      V(c0*r1,y,s0*r1,c0*r1*.026,s0*r1*.026,tint[1],tint[2],tint[3],tint[4]),
      V(c1*r1,y,s1*r1,c1*r1*.026,s1*r1*.026,tint[1],tint[2],tint[3],tint[4]),
      V(c1*r0,y,s1*r0,c1*r0*.026,s1*r0*.026,tint[1],tint[2],tint[3],tint[4]))
  end
end
local function wallRing(g,r,y0,y1,segments,uv)
  segments=segments or 128;uv=uv or .02
  for i=0,segments-1 do
    local a0=i/segments*math.pi*2;local a1=(i+1)/segments*math.pi*2
    Q(g,V(math.cos(a0)*r,y0,math.sin(a0)*r,i/segments*8,y0*uv),V(math.cos(a1)*r,y0,math.sin(a1)*r,(i+1)/segments*8,y0*uv),V(math.cos(a1)*r,y1,math.sin(a1)*r,(i+1)/segments*8,y1*uv),V(math.cos(a0)*r,y1,math.sin(a0)*r,i/segments*8,y1*uv))
  end
end
local function box(g,x,y,z,sx,sy,sz,rot)
  rot=rot or 0;local c,s=math.cos(rot),math.sin(rot)
  local function P(px,py,pz,u,v) local rx=px*c+pz*s;local rz=-px*s+pz*c;return V(x+rx,y+py,z+rz,u,v) end
  local x0,x1=-sx/2,sx/2;local z0,z1=-sz/2,sz/2;local y0,y1=0,sy
  Q(g,P(x0,y0,z0,0,1),P(x1,y0,z0,1,1),P(x1,y1,z0,1,0),P(x0,y1,z0,0,0));Q(g,P(x1,y0,z1,0,1),P(x0,y0,z1,1,1),P(x0,y1,z1,1,0),P(x1,y1,z1,0,0))
  Q(g,P(x0,y0,z1,0,1),P(x0,y0,z0,1,1),P(x0,y1,z0,1,0),P(x0,y1,z1,0,0));Q(g,P(x1,y0,z0,0,1),P(x1,y0,z1,1,1),P(x1,y1,z1,1,0),P(x1,y1,z0,0,0))
  Q(g,P(x0,y1,z0,0,1),P(x1,y1,z0,1,1),P(x1,y1,z1,1,0),P(x0,y1,z1,0,0))
end
local function boulder(g,x,y,z,rx,ry,rz,seed)
  -- Compact fractured crag used only where a loose rock mass is appropriate.
  -- Keep the polygon count low and the profile discontinuous; most importantly,
  -- tile the D2 rock atlas by world scale instead of stretching one 256px copy
  -- across an entire formation (the main cause of the clay/plastic read).
  local seg=7
  local rings={
    {t=0.00,r=.72},{t=.13,r=1.03},{t=.30,r=.91},{t=.46,r=1.00},
    {t=.62,r=.67},{t=.77,r=.72},{t=.90,r=.37},{t=1.00,r=.055},
  }
  local phase=seed or 1
  local leanX=math.sin(phase*1.37)*rx*.16
  local leanZ=math.cos(phase*.91)*rz*.13
  local tileU=math.max(2.3,(rx+rz)*.034)
  local tileV=math.max(2.4,ry*.064)
  local function P(i,j)
    local q=rings[j]; local a=i/seg*math.pi*2
    local n=1+.18*math.sin(a*2+phase)+.10*math.cos(a*5-phase*.73)+.05*math.sin(a*7+phase*.31)
    local t=q.t; local ox=leanX*(t-.30); local oz=leanZ*(t-.30)
    local shade=.66+.25*(.5+.5*math.sin(a*1.72+phase*.61))
    return V(x+ox+math.cos(a)*rx*q.r*n, y-ry+2*ry*t, z+oz+math.sin(a)*rz*q.r*n,
      (i/seg)*tileU+phase*.071,t*tileV+phase*.043,shade,shade*.96,shade*.95,1)
  end
  for j=1,#rings-1 do
    for i=0,seg-1 do
      local i1=(i+1)%seg
      local p00,p01,p10,p11=P(i,j),P(i1,j),P(i,j+1),P(i1,j+1)
      -- Alternate diagonals so repeated crags do not all expose the same planar fan.
      if (i+j)%2==0 then T(g,p00,p10,p11);T(g,p00,p11,p01)
      else T(g,p00,p10,p01);T(g,p10,p11,p01) end
    end
  end
end

local function rockNeedle(g,x,baseY,z,rx,height,rz,seed,leanX,leanZ)
  -- Narrow fractured outcrop, not a cone. Large source texture tiling prevents
  -- broad smooth gradients on distant peaks and keeps the backdrop at the same
  -- texel/detail density as the arena machinery.
  local seg=7; seed=seed or 1; leanX=leanX or 0; leanZ=leanZ or 0
  local rings={{t=0,r=1.00},{t=.18,r=.82},{t=.34,r=.94},{t=.52,r=.61},{t=.68,r=.67},{t=.83,r=.31},{t=1,r=.018}}
  local tileU=math.max(2.6,(rx+rz)*.037)
  local tileV=math.max(3.0,height*.024)
  local function P(i,j)
    local q=rings[j];local a=i/seg*math.pi*2
    local n=1+.17*math.sin(a*2+seed)+.085*math.cos(a*5-seed*.8)
    local t=q.t;local skew=t*t
    local shade=.63+.28*(.5+.5*math.cos(a*1.51+seed*.53))
    return V(x+leanX*skew+math.cos(a)*rx*q.r*n,baseY+height*t,z+leanZ*skew+math.sin(a)*rz*q.r*n,
      (i/seg)*tileU+seed*.057,t*tileV+seed*.031,shade,shade*.95,shade*.93,1)
  end
  for j=1,#rings-1 do
    for i=0,seg-1 do
      local i1=(i+1)%seg
      local p00,p01,p10,p11=P(i,j),P(i1,j),P(i,j+1),P(i1,j+1)
      if (i+j)%2==0 then T(g,p00,p10,p11);T(g,p00,p11,p01)
      else T(g,p00,p10,p01);T(g,p10,p11,p01) end
    end
  end
end

local function mountainRidge(g,a,r,baseY,width,height,depth,seed)
  -- A connected mountain wall built as fractured front/back escarpments around a
  -- jagged ridgeline. This replaces the old collection of rotational blobs. In a
  -- wide battle shot the eye now sees a continuous mountain formation: foothill,
  -- shelf, cliff face, ridge, rear slope. Every panel has a flat triangle normal.
  local c,sn=math.cos(a),math.sin(a); local tx,tz=-sn,c
  local cols=10
  local front,ledge,ridge,back={},{},{},{}
  for i=0,cols do
    local q=i/cols; local lateral=(q-.5)*width
    local edge=math.sin(math.pi*q)
    local wob=math.sin(seed+i*1.73)*depth*.10+math.cos(seed*.43+i*.91)*depth*.055
    local h=height*(.34+.66*edge)*(1+.12*math.sin(seed*.71+i*2.11))
    -- Two intentional notches prevent every mountain from becoming one perfect pyramid.
    if i==3 or i==7 then h=h*(.74+.07*math.sin(seed+i)) end
    local baseNoise=math.sin(seed*1.9+i*.77)*5.0
    local rr=r+wob
    local function P(rad,yy,lat,u,v,shade)
      return V(c*rad+tx*lat,yy,sn*rad+tz*lat,u,v,shade,shade*.96,shade*.94,1)
    end
    local u=q*math.max(3.6,width*.020)+seed*.041
    front[i+1]=P(rr-depth*.42,baseY+baseNoise,lateral,u,0,.70)
    ledge[i+1]=P(rr-depth*.17,baseY+h*.29,lateral+math.sin(i+seed)*depth*.035,u+.17,h*.007,.73)
    ridge[i+1]=P(rr+depth*.02,baseY+h,lateral+math.sin(i*1.41+seed)*depth*.055,u+.31,h*.019,.66)
    back[i+1]=P(rr+depth*.62,baseY-7+baseNoise*.35,lateral,u+.54,h*.023,.56)
  end
  for i=1,cols do
    -- fractured lower apron
    if i%2==0 then
      T(g,front[i],ledge[i+1],ledge[i]);T(g,front[i],front[i+1],ledge[i+1])
      T(g,ledge[i],ridge[i+1],ridge[i]);T(g,ledge[i],ledge[i+1],ridge[i+1])
    else
      T(g,front[i],front[i+1],ledge[i]);T(g,front[i+1],ledge[i+1],ledge[i])
      T(g,ledge[i],ledge[i+1],ridge[i]);T(g,ledge[i+1],ridge[i+1],ridge[i])
    end
    -- rear slope closes the silhouette and gives oblique camera cuts real depth
    T(g,ridge[i],ridge[i+1],back[i+1]);T(g,ridge[i],back[i+1],back[i])
  end
  -- End caps make the formation a solid mass instead of a stage-flat backdrop.
  T(g,front[1],ledge[1],ridge[1]);T(g,front[1],ridge[1],back[1])
  local n=#front;T(g,front[n],ridge[n],ledge[n]);T(g,front[n],back[n],ridge[n])
end
local function beam(g,x,y,z,len,thick,rot) box(g,x,y,z,len,thick,thick,rot) end

local function lavaFall(g,a,r,yTop,yBottom,width,depth,seed)
  -- Subdivided, slightly irregular molten volume.  The old four-corner ribbon
  -- could scroll its texture but its silhouette remained a perfectly flat card.
  -- Dense rows give the GPU lava deformation actual vertices to work with, while
  -- a shallow return shell keeps oblique cameras from exposing a paper-thin edge.
  local c,s=math.cos(a),math.sin(a)
  local tx,tz=-s,c
  local hw=(width or 26)*.5
  local d=depth or 4.0
  local cols,rows=7,18
  local height=math.max(1,yTop-yBottom)
  local repeatV=math.max(2.5,height/24)
  seed=seed or 1
  local function front(ix,iy)
    local u=ix/cols; local t=iy/rows
    local side=-hw+u*(hw*2)
    -- Break the waterfall crown itself. A perfectly horizontal top edge makes
    -- even a deep reservoir read like a Minecraft source block. The lip is
    -- irregular only near the spill edge and rapidly converges to the normal
    -- flowing sheet below it.
    local crown=(1.0-t)*(1.0-t)*(1.0-t)*(
      math.sin(u*math.pi*3.0+seed*.83)*1.85
      +math.sin(u*math.pi*7.0-seed*.41)*.72)
    local y=yTop-t*height+crown
    local wobble=math.sin(t*math.pi*3.0+seed)*1.4*(.25+.75*t)
      +math.sin(u*math.pi*4.0+seed*.7)*.65*t
    local rr=r+wobble
    return V(c*rr+tx*side,y,s*rr+tz*side,u,t*repeatV)
  end
  for iy=0,rows-1 do
    for ix=0,cols-1 do
      local p00,p10,p01,p11=front(ix,iy),front(ix+1,iy),front(ix,iy+1),front(ix+1,iy+1)
      T(g,p00,p01,p11);T(g,p00,p11,p10)
    end
  end
  -- Narrow side/back shell; darker edge treatment in the shader provides most
  -- of the thickness cue, so this can stay deliberately cheap.
  local function P(side,y,back,u,v)
    local rr=r+(back and d or 0)
    return V(c*rr+tx*side,y,s*rr+tz*side,u,v*repeatV)
  end
  Q(g,P(hw,yBottom,true,0,repeatV),P(-hw,yBottom,true,1,repeatV),P(-hw,yTop,true,1,0),P(hw,yTop,true,0,0))
  Q(g,P(-hw,yBottom,true,0,repeatV),P(-hw,yBottom,false,1,repeatV),P(-hw,yTop,false,1,0),P(-hw,yTop,true,0,0))
  Q(g,P(hw,yBottom,false,0,repeatV),P(hw,yBottom,true,1,repeatV),P(hw,yTop,true,1,0),P(hw,yTop,false,0,0))
end
local function RP(a,r,side,y,u,v)
  local c,s=math.cos(a),math.sin(a); local tx,tz=-s,c
  return V(c*r+tx*side,y,s*r+tz*side,u or 0,v or 0)
end
local function channelShelf(g,a,r0,r1,y,side0,side1,uv)
  uv=uv or .025
  Q(g,RP(a,r0,side0,y,r0*uv,side0*uv),RP(a,r1,side0,y,r1*uv,side0*uv),
      RP(a,r1,side1,y,r1*uv,side1*uv),RP(a,r0,side1,y,r0*uv,side1*uv))
end
local function channelTaper(g,a,r0,r1,y0,y1,half0,half1,uv)
  uv=uv or .025
  Q(g,RP(a,r0,-half0,y0,r0*uv,-half0*uv),RP(a,r1,-half1,y1,r1*uv,-half1*uv),
      RP(a,r1, half1,y1,r1*uv, half1*uv),RP(a,r0, half0,y0,r0*uv, half0*uv))
end
local function channelSideWall(g,a,r0,r1,y0,y1,side,uv)
  uv=uv or .025
  Q(g,RP(a,r0,side,y0,r0*uv,y0*uv),RP(a,r1,side,y0,r1*uv,y0*uv),
      RP(a,r1,side,y1,r1*uv,y1*uv),RP(a,r0,side,y1,r0*uv,y1*uv))
end
local function channelBackWall(g,a,r,y0,y1,side0,side1,uv)
  uv=uv or .025
  Q(g,RP(a,r,side1,y0,side1*uv,y0*uv),RP(a,r,side0,y0,side0*uv,y0*uv),
      RP(a,r,side0,y1,side0*uv,y1*uv),RP(a,r,side1,y1,side1*uv,y1*uv))
end
local function lavaApron(g,a,rFront,rBack,y,width,seed)
  local hw=width*.5
  local rows=4
  for j=0,rows-1 do
    local t0=j/rows; local t1=(j+1)/rows
    local rr0=rFront+(rBack-rFront)*t0; local rr1=rFront+(rBack-rFront)*t1
    local w0=hw*(1-.18*t0)+math.sin(seed+t0*4.1)*1.1
    local w1=hw*(1-.18*t1)+math.sin(seed+t1*4.1)*1.1
    Q(g,RP(a,rr0,-w0,y,t0,0),RP(a,rr1,-w1,y,t1,0),RP(a,rr1,w1,y,t1,1),RP(a,rr0,w0,y,t0,1))
  end
end

local function volcanicSpire(g,a,r,baseY,height,baseR,seed)
  -- Source-like jagged caldera crown: one broad fractured foot and several
  -- connected needles, never a vertical stack of spheres. The side peaks overlap
  -- the main footprint so there are no floating seams from any battle camera.
  local c,s=math.cos(a),math.sin(a);local tx,tz=-s,c
  boulder(g,c*r,baseY+height*.16,s*r,baseR*1.35,height*.24,baseR*1.05,seed+.2)
  rockNeedle(g,c*(r-2),baseY+height*.08,s*(r-2),baseR*.91,height*.92,baseR*.76,seed+1.1,
    tx*baseR*.16-c*baseR*.06,tz*baseR*.16-s*baseR*.06)
  rockNeedle(g,c*(r+4)+tx*baseR*.64,baseY+height*.10,s*(r+4)+tz*baseR*.64,
    baseR*.48,height*.60,baseR*.43,seed+3.7,-tx*baseR*.11, -tz*baseR*.11)
  rockNeedle(g,c*(r+1)-tx*baseR*.62,baseY+height*.06,s*(r+1)-tz*baseR*.62,
    baseR*.42,height*.49,baseR*.38,seed+5.9,tx*baseR*.08,tz*baseR*.08)
end

local function offsetRing(g,cx,cz,r0,r1,y,segments,tint)
  tint=tint or {1,1,1,1};segments=segments or 48
  for i=0,segments-1 do
    local a0=i/segments*math.pi*2;local a1=(i+1)/segments*math.pi*2
    Q(g,V(cx+math.cos(a0)*r0,y,cz+math.sin(a0)*r0,0,0,tint[1],tint[2],tint[3],tint[4]),
      V(cx+math.cos(a0)*r1,y,cz+math.sin(a0)*r1,1,0,tint[1],tint[2],tint[3],tint[4]),
      V(cx+math.cos(a1)*r1,y,cz+math.sin(a1)*r1,1,1,tint[1],tint[2],tint[3],tint[4]),
      V(cx+math.cos(a1)*r0,y,cz+math.sin(a1)*r0,0,1,tint[1],tint[2],tint[3],tint[4]))
  end
end

local function summitTower(a,r,baseY,height)
  -- Platform 100 is ringed by substantial industrial towers and access spans.
  -- These are deliberately large, supported pieces of architecture rather than
  -- the tiny isolated posts from the previous pass.
  local c,s=math.cos(a),math.sin(a);local tx,tz=-s,c
  local x,z=c*r,s*r;local half=24
  -- rock/concrete footing tied into the crater wall
  boulder(rockDark,x,baseY-5,z,31,20,29,700+a*9)
  box(deckDark,x,baseY-12,z,42,18,38,-a)
  -- paired steel legs + top gantry
  for _,side in ipairs({-1,1}) do
    local px,pz=x+tx*side*half,z+tz*side*half
    box(deckDark,px,baseY,pz,7,height,8,-a)
    box(trim,px,baseY+height-4,pz,10,4.5,11,-a)
  end
  beam(truss,x,baseY+height*.38,z,half*2+8,5,-a-math.pi*.5)
  beam(truss,x,baseY+height*.70,z,half*2+8,5,-a-math.pi*.5)
  beam(truss,x,baseY+height-7,z,half*2+16,6,-a-math.pi*.5)
  -- radial access bridge into the arena, with warm hazard rails on both sides
  local inner=171;local outer=r-5;local mid=(inner+outer)*.5;local len=outer-inner
  box(deckDark,c*mid,16,s*mid,len,8,31,-a)
  box(deck,c*mid,24.1,s*mid,len,2.2,27,-a)
  for _,side in ipairs({-1,1}) do
    box(trim,c*mid+tx*side*15.5,26.0,s*mid+tz*side*15.5,len,3.0,3.2,-a)
  end
  -- exterior landing gives the gantry a visible destination instead of ending
  -- in empty air; its underside is carried by the same tower footing.
  box(deckDark,c*(r+26),baseY+8,s*(r+26),62,12,56,-a)
  box(deck,c*(r+26),baseY+20,s*(r+26),56,2.2,50,-a)
  box(trim,c*(r+26)+tx*29,baseY+22,s*(r+26)+tz*29,54,3,3,-a)
  box(trim,c*(r+26)-tx*29,baseY+22,s*(r+26)-tz*29,54,3,3,-a)
end

-- Battle deck: deliberately clean and broad, with source-derived metal and
-- restrained red rings. Every marking is coplanar/flush enough to avoid shards.
ring(deck,0,150,.10,.10,160,.026,{.92,.92,.91,1})
ring(deckDark,150,162,.08,.10,160,.023,{.86,.85,.84,1})
ring(trim,157,166,.12,.12,160,.030,{.98,.90,.65,1})
-- Interlocked radial deck plates break the enormous flat circle into authored
-- construction bays. Small gaps leave the source metal visible and avoid a
-- painted-on checkerboard; the red battle markings stay above the plates.
for i=0,11 do
  local step=math.pi*2/12;local a0=i*step+.028;local a1=(i+1)*step-.028
  local q=(i%2==0) and .96 or .86
  sectorRing(deckPanel,43,146,a0,a1,.132,{q,q*.99,q,1})
end
for i=0,23 do
  local a=i/24*math.pi*2;local r=101
  beam(deckDark,math.cos(a)*r,.137,math.sin(a)*r,94,1.15,-a)
end
-- Source Platform 100 uses a giant painted 100 rather than a generic Poké Ball
-- court. Keep restrained battle rings for readability, then lay the unmistakable
-- summit numeral across the center in worn pale paint.
ring(marking,34,37,.175,.175,128,.02,{.84,.27,.29,1})
ring(marking,90,93,.175,.175,128,.02,{.72,.18,.21,1})
box(marking,0,.165,0,2.4,.10,128,0)
box(numberMark,-42,.181,-2,4.2,.08,50,0)
box(numberMark,-37,.181,-26,14,.08,4.2,0)
offsetRing(numberMark,-7,-2,14,18,.182,52,{.93,.90,.84,1})
offsetRing(numberMark,31,-2,14,18,.182,52,{.93,.90,.84,1})

-- A low segmented perimeter curb gives the broad deck a readable thickness in
-- close shots without walling off the combatants or hiding the caldera.
for i=0,11 do
  local a=(i+.5)/12*math.pi*2
  box(deckDark,math.cos(a)*163,-1.1,math.sin(a)*163,17,6.8,4.2,-a-math.pi*.5)
  box(trim,math.cos(a)*164,5.3,math.sin(a)*164,12,1.8,3.2,-a-math.pi*.5)
end

-- Deep platform body and tapered rock shoulder eliminate the old floating-disc
-- read. The metal deck has a real understructure before it meets the volcano.
wallRing(deckDark,162,-20,.10,144,.022)
ring(deckDark,126,162,-20,-20,144,.023,{.72,.70,.69,1})
wallRing(trim,166,-7,.3,144,.028)
for i=0,11 do local a=i/12*math.pi*2; box(deckDark,math.cos(a)*146,-30,math.sin(a)*146,20,31,28,a) end
for i=0,11 do local a=(i+.5)/12*math.pi*2; beam(truss,math.cos(a)*135,-23,math.sin(a)*135,56,6,a+math.pi/2) end

-- Volcanic pedestal reaches the platform underside from below. Layered boulder
-- rings conceal every mechanical-to-rock joint from low camera angles.
for row=0,2 do
  local count=14+row*4; local rr=147+row*24; local yy=-39-row*16
  for i=0,count-1 do local a=(i+(row*.37))/count*math.pi*2;local sz=22+((i*7+row*3)%13);boulder(row==0 and rockDark or rock,math.cos(a)*rr,yy,math.sin(a)*rr,sz*1.25,18+row*5,sz,1.7+i*.31+row) end
end

-- Connected rear access bridge/service landing. Sparse structural beams replace
-- the previous field of arbitrary boxes/scaffolds.
box(deckDark,0,-5,-225,72,12,128,0);box(deck,0,7,-225,66,2.2,128,0)
box(trim,-34,5,-225,5,5,128,0);box(trim,34,5,-225,5,5,128,0)
box(deckDark,0,-14,-310,130,22,64,0);box(deck,0,8,-310,124,2.0,58,0)
for _,x in ipairs({-47,47}) do box(deckDark,x,-40,-310,14,48,42,0);boulder(rockDark,x,-49,-310,30,24,34,5+x*.01) end
for z=-270,-185,28 do beam(truss,0,-15,z,76,6,0) end

-- Crater bowl: layered escarpments rather than a necklace of round rocks. The
-- first shelf stays low enough to expose Platform 100 machinery while establishing
-- that the combat deck is physically embedded into the volcanic summit.
ring(rockDark,188,510,-54,-88,176,.010,{.76,.72,.72,1})
for i,a in ipairs({-2.88,-2.45,-2.02,-1.58,-1.15,-.70,-.24,.23,.70,1.15,1.59,2.04,2.49,2.90}) do
  local r=274+((i*31)%58)
  mountainRidge((i%3==0) and rockDark or rock,a,r,-79,112+((i*19)%40),54+((i*13)%28),58+((i*17)%24),31+i*1.17)
end

-- High volcanic skyline. Broad overlapping ridge masses create recognisable
-- mountain formations with ravines and shoulders. Sparse needles are used only
-- as accents, never as the entire background silhouette.
local ridgeDefs={
  {-2.76,374,174,158,94,61},{-2.17,399,188,184,104,72},
  {-1.55,382,178,142,88,83},{-.92,405,205,192,112,94},
  {.78,399,190,176,102,105},{1.39,378,178,151,90,116},
  {2.02,410,210,198,116,127},{2.63,386,184,165,96,138},
}
for _,d in ipairs(ridgeDefs) do
  mountainRidge(rock,d[1],d[2],-88,d[3],d[4],d[5],d[6])
end
-- Far rear crown: darker, taller formations with deliberate sunset/sky windows.
for i,a in ipairs({-2.48,-1.82,-1.10,1.10,1.79,2.45}) do
  mountainRidge(rockDark,a,485+((i*17)%38),-105,190+((i*23)%42),205+((i*29)%75),120+((i*11)%35),170+i*1.63)
end
-- A few hard volcanic teeth break the ridge lines and frame the lava falls.
for i,a in ipairs({-2.31,-1.43,-.78,.91,1.52,2.29}) do
  local r=402+((i*27)%48);local c,sn=math.cos(a),math.sin(a)
  rockNeedle((i%2==0) and rockDark or rock,c*r,-77,sn*r,28+((i*7)%14),118+((i*19)%58),25+((i*5)%11),220+i*2.1,
    -sn*(10+((i*3)%7)),math.cos(a)*(10+((i*3)%7)))
end

-- Upper lava shelves and waterfalls. 0.0.56 replaces the old overlapping
-- centerline boulders with a true recessed rock channel. Lava now has a visible
-- feed shelf, clear side banks, a back wall and a flanked receiving basin, so no
-- rock volume needs to occupy the same space as the molten sheet.
local fallDefs={
  {-2.22,374,88,-57,30},{-1.67,408,112,-58,38},{-1.05,365,72,-56,26},
  {1.04,370,84,-56,28},{1.60,414,118,-58,40},{2.18,382,92,-57,31}
}
for i,d in ipairs(fallDefs) do
  local a,r,yt,yb,w=d[1],d[2],d[3],d[4],d[5]
  local c,s=math.cos(a),math.sin(a); local tx,tz=-s,math.cos(a)
  local half=w*.5
  local bank=half+5.5
  local backR=r+18
  local frontR=r-9

  -- Continuous cliff mass sits BEHIND the lava corridor. Side walls define the
  -- notch explicitly; organic boulders live outside those walls, never through
  -- the center of the waterfall.
  channelBackWall(rock,a,backR,yb-15,yt-13,-bank,bank,.021)
  channelSideWall(rock,a,frontR-4,backR+8,yb-15,yt-13,-bank,.021)
  channelSideWall(rock,a,frontR-4,backR+8,yb-15,yt-13, bank,.021)
  channelShelf(rock,a,r-1,backR+13,yt-13,-bank-w*.72,-bank,.022)
  channelShelf(rock,a,r-1,backR+13,yt-13, bank,bank+w*.72,.022)

  -- Layer natural rock outside the carved banks. Because the nearest edge is
  -- always beyond `bank`, these lobes can soften the channel without clipping it.
  for tier=0,4 do
    local t=tier/4
    local yy=yb-11+t*(yt-yb-18)
    local rr=r+10+math.sin(i*1.7+t*4.0)*5
    local sz=w*(.31+.045*(tier%2))
    local offset=bank+sz*.92+3
    boulder(rock,c*rr+tx*(-offset),yy,s*rr+tz*(-offset),sz,15+sz*.45,sz*.86,190+i*7+tier*.61)
    boulder(rock,c*rr+tx*( offset),yy,s*rr+tz*( offset),sz,15+sz*.45,sz*.86,230+i*7+tier*.57)
  end
  -- Backing geology grows upward behind the notch, giving the waterfall a real
  -- mountain spine while maintaining a safe radial gap from the molten surface.
  volcanicSpire(rock,a,r+58,-78,(yt+78)*1.06,w*1.20,270+i*1.23)

  -- Deep upper source reservoir. The old feeder began almost exactly at the
  -- cliff edge, which made the waterfall look like a Minecraft stream spawned
  -- on a block. The molten surface now starts well behind the visible lip, sits
  -- in a rock-walled basin, and drains downhill through an overflow notch before
  -- becoming the vertical fall. From battle height the player can trace the
  -- entire path: reservoir -> sloped feeder -> spill lip -> waterfall.
  local sourceTex=(i%2==0) and LAVA2 or LAVA
  local reservoir=G(sourceTex,128,(i%2==0) and 128 or 256,{1.00,.66,.21},{.77,.30,.08},{.02,.01,.003},1)
  reservoir.flow=0
  local sourceFront=backR+12
  local sourceBack=backR+84+w*.24
  -- Sink the reservoir below the surrounding cliff crown.  Only the narrow
  -- overflow throat should reach the visible lip; the broad source pool lives
  -- deeper inside the mountain instead of sitting on top like a placed tile.
  local sourceY=yt-10.6
  local sourceHalf=half*1.32
  -- The source is a widening volcanic throat, not a rectangular shelf.  The
  -- narrow mouth connects to the overflow notch; deeper inside the mountain
  -- the molten surface broadens into an irregular reservoir and rises subtly
  -- toward a partially hidden rear pool.
  local rA=sourceFront
  local rB=sourceFront+18+w*.05
  local rC=sourceFront+43+w*.10
  local rD=sourceBack
  channelTaper(reservoir,a,rA,rB,sourceY-.18,sourceY+.05,sourceHalf*.72,sourceHalf*1.12,.030)
  channelTaper(reservoir,a,rB,rC,sourceY+.05,sourceY+.34,sourceHalf*1.12,sourceHalf*1.52,.030)
  channelTaper(reservoir,a,rC,rD,sourceY+.34,sourceY+.68,sourceHalf*1.52,sourceHalf*1.27,.030)
  local basinHalf=sourceHalf*1.62
  -- Dark rock basin follows the broad rear reservoir, leaving only the forward
  -- overflow throat open.  A high back wall and rock shoulders hide the hard
  -- end so the lava reads as continuing deeper into the caldera.
  channelSideWall(rockDark,a,sourceFront-4,sourceBack+10,sourceY-12,sourceY+10,-basinHalf-5,.023)
  channelSideWall(rockDark,a,sourceFront-4,sourceBack+10,sourceY-12,sourceY+10, basinHalf+5,.023)
  channelBackWall(rockDark,a,sourceBack+10,sourceY-13,sourceY+15,-basinHalf-6,basinHalf+6,.023)
  -- A real source mouth: rock continues across the front of the reservoir on
  -- both sides, leaving only a narrow eroded slot for the feeder. From the
  -- battlefield the broad molten pool is therefore glimpsed *behind* rock,
  -- rather than appearing as a flat orange shelf balanced on the cliff.
  local mouthHalf=sourceHalf*.78
  channelBackWall(rock,a,sourceFront+5,sourceY-7,sourceY+7,-basinHalf-4,-mouthHalf,.023)
  channelBackWall(rock,a,sourceFront+5,sourceY-7,sourceY+7, mouthHalf, basinHalf+4,.023)
  channelShelf(rock,a,sourceFront-5,sourceFront+13,sourceY+6.6,-basinHalf-7,-mouthHalf,.022)
  channelShelf(rock,a,sourceFront-5,sourceFront+13,sourceY+6.6, mouthHalf, basinHalf+7,.022)
  channelShelf(rock,a,sourceFront,sourceBack+13,sourceY-1.2,-basinHalf-14,-basinHalf-4,.022)
  channelShelf(rock,a,sourceFront,sourceBack+13,sourceY-1.2, basinHalf+4, basinHalf+14,.022)
  -- The feeder visibly narrows and descends from the pool to the eroded cliff
  -- lip. Its rear width matches the reservoir throat, eliminating the old
  -- block-on-block seam at the top of the waterfall.
  local feed=G(sourceTex,128,(i%2==0) and 128 or 256,{1.00,.64,.20},{.76,.29,.08},{.02,.01,.003},1)
  feed.flow=0
  channelTaper(feed,a,sourceFront+3,frontR-1,sourceY-.18,yt-13.35,sourceHalf*.70,half*.80,.032)
  -- Rock shoulders continue around the feeder and curl over the mouth.  The
  -- inner pair is deliberately close to the throat but remains outside the
  -- molten width, creating the impression that lava is escaping from a deeper
  -- fissure in the caldera wall.
  for _,side in ipairs({-1,1}) do
    local off=side*(basinHalf+9)
    boulder(rock,c*(backR+24)+tx*off,sourceY-6,s*(backR+24)+tz*off,w*.60,20,w*.74,365+i*7+side)
    boulder(rock,c*(backR+53)+tx*(off*.92),sourceY+1,s*(backR+53)+tz*(off*.92),w*.70,22,w*.80,395+i*7+side)
    local inner=side*(mouthHalf+w*.36)
    boulder(rock,c*(sourceFront+1)+tx*inner,sourceY+1.0,s*(sourceFront+1)+tz*inner,w*.34,11,w*.42,425+i*7+side)
  end

  local fallTex=(i%2==0) and LAVA2 or LAVA
  local fg=G(fallTex,128,(i%2==0) and 128 or 256,{1.00,.62,.19},{.74,.28,.08},{.02,.01,.003},1)
  fg.flow=1
  lavaFall(fg,a,frontR,yt-13,yb,w,4.0,20+i*1.37)

  -- Receiving lava is now a tapered apron in the open channel instead of three
  -- rectangular boxes intersecting a central boulder. Rock banks remain outside
  -- it and the apron sinks into the lower moat/channel system.
  local impact=G(LAVA2,128,128,{1.00,.70,.24},{.72,.30,.08},{.02,.01,.003},1)
  impact.flow=0
  lavaApron(impact,a,r-34,r+3,yb-.85,w*1.75,17+i*.93)
  lavaApron(impact,a,r-58,r-30,yb-1.05,w*.96,31+i*1.11)
  for _,side in ipairs({-1,1}) do
    local off=side*(w*.92+7)
    boulder(rock,c*(r-11)+tx*off,yb-10,s*(r-11)+tz*off,w*.48,11,w*.62,310+i*3+side)
    boulder(rockDark,c*(r-38)+tx*(off*.78),yb-13,s*(r-38)+tz*(off*.78),w*.42,10,w*.55,340+i*3+side)
  end
end

-- Connected lava moat + four channels. All lava terminates in the crater floor
-- or emerges beneath actual rock lips, rather than hanging as effect cards.
ring(lava,185,232,-51,-50,160,.018,{1,1,1,1})
ring(lava2,198,218,-49.7,-49.7,160,.020,{1,1,1,1})
for _,a in ipairs({math.pi*.25,math.pi*.75,math.pi*1.25,math.pi*1.75}) do
  local c,s=math.cos(a),math.sin(a)
  for j=0,5 do
    local r=224+j*30; local w=20+j*3
    box(lava,c*r,-53-j*2.1,s*r,w,1.5,35,a)
    boulder(rock,c*(r+5),-60-j*2.1,s*(r+5),w*.95,8,24,33+j+a)
  end
end

-- Platform 100's defining non-lava silhouette is its heavy industrial access
-- infrastructure. Restore four anchored tower/bridge assemblies around the disc
-- instead of tiny decorative posts. They remain outside combat space and every
-- span terminates in a supported landing.
for i=0,3 do
  local a=math.pi*.25+i*math.pi*.5
  summitTower(a,258,-43,92+(i%2)*12)
end

-- Smaller fan/service pylons sit directly on the deck rim between the towers.
-- These keep the recognizable Mt. Battle machinery close to camera without
-- competing with the large outer gantries.
for i=0,3 do
  local a=i*math.pi*.5;local x,z=math.cos(a)*174,math.sin(a)*174
  box(deckDark,x,-21,z,15,39,15,-a);box(trim,x,18,z,21,5,21,-a)
  beam(truss,x,4,z,34,4.5,-a-math.pi*.5)
end

local total=0;for _,g in ipairs(groups) do total=total+#g.vertices end
return {version=23,source="D2 Mt. Battle Platform 100 / organic basalt ridge and sunset summit presentation",prototype=false,
 bounds={-650,650,-180,220,-650,650},groups=groups,vertexCount=total,groupCount=#groups,crowdOriginal=0,crowdKept=0,crowdPolicy="none",
 fidelity="Platform 100 numeral / interlocked metal deck / restored tower-and-bridge gantries / connected fractured mountain ridges / organic seam-free basalt / recessed upper lava reservoirs / animated waterfalls / connected crater lava / late-day sunset atmosphere"}
