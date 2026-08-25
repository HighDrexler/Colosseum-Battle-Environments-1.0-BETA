local G={}
local floor=math.floor
local function be16(s,p)local a,b=s:byte(p,p+1);if not b then return 0 end;return a*256+b end
local function c8(v)return string.char(math.max(0,math.min(255,floor(v+0.5)))) end
local function rgba(r,g,b,a)return c8(r)..c8(g)..c8(b)..c8(a) end
local function expand4(v)return v*17 end
local function expand5(v)return floor(v*255/31+.5) end
local function expand6(v)return floor(v*255/63+.5) end
local function rgb565(v)return expand5(floor(v/2048)%32),expand6(floor(v/32)%64),expand5(v%32),255 end
-- Correct RGB5A3 expansion: high bit clear = AAA RGB4. Keep this separate to avoid bit ops.
local function rgb5a3c(v)
  if v>=32768 then return expand5(floor((v-32768)/1024)%32),expand5(floor(v/32)%32),expand5(v%32),255 end
  local a=floor(v/4096)%8;local r=floor(v/256)%16;local g=floor(v/16)%16;local b=v%16
  return r*17,g*17,b*17,floor(a*255/7+.5)
end
local function palColor(pal,fmt,idx)
  local v=be16(pal,idx*2+1)
  if fmt==0 then local a=floor(v/256);local i=v%256;return i,i,i,a
  elseif fmt==1 then return rgb565(v)
  else return rgb5a3c(v) end
end
local function set(px,w,h,x,y,r,g,b,a)
  if x>=0 and y>=0 and x<w and y<h then px[y*w+x+1]=rgba(r,g,b,a) end
end
local function blockLoop(w,h,bw,bh,fn)
  local bi=0
  for by=0,h-1,bh do for bx=0,w-1,bw do bi=fn(bx,by,bi) end end
end
function G.dataSize(w,h,fmt)
  local bw,bh,bytes=4,4,32
  if fmt==0 or fmt==8 then bw,bh,bytes=8,8,32
  elseif fmt==1 or fmt==2 or fmt==9 then bw,bh,bytes=8,4,32
  elseif fmt==6 then bw,bh,bytes=4,4,64
  elseif fmt==14 then bw,bh,bytes=8,8,32 end
  return math.ceil(w/bw)*math.ceil(h/bh)*bytes
end
function G.decode(data,w,h,fmt,palette,palFmt)
  assert(type(data)=="string" and w>0 and h>0,"bad GX texture")
  local px={};for i=1,w*h do px[i]="\0\0\0\0" end
  if fmt==0 then -- I4
    blockLoop(w,h,8,8,function(bx,by,o)
      for y=0,7 do for x=0,7,2 do local q=data:byte(o+1) or 0;o=o+1;local a=expand4(floor(q/16));local b=expand4(q%16);set(px,w,h,bx+x,by+y,a,a,a,255);set(px,w,h,bx+x+1,by+y,b,b,b,255) end end;return o end)
  elseif fmt==1 then -- I8
    blockLoop(w,h,8,4,function(bx,by,o)for y=0,3 do for x=0,7 do local q=data:byte(o+1) or 0;o=o+1;set(px,w,h,bx+x,by+y,q,q,q,255) end end;return o end)
  elseif fmt==2 then -- IA4
    blockLoop(w,h,8,4,function(bx,by,o)for y=0,3 do for x=0,7 do local q=data:byte(o+1) or 0;o=o+1;local a=expand4(floor(q/16));local i=expand4(q%16);set(px,w,h,bx+x,by+y,i,i,i,a) end end;return o end)
  elseif fmt==3 then -- IA8
    blockLoop(w,h,4,4,function(bx,by,o)for y=0,3 do for x=0,3 do local a=data:byte(o+1) or 0;local i=data:byte(o+2) or 0;o=o+2;set(px,w,h,bx+x,by+y,i,i,i,a) end end;return o end)
  elseif fmt==4 or fmt==5 then
    blockLoop(w,h,4,4,function(bx,by,o)for y=0,3 do for x=0,3 do local v=be16(data,o+1);o=o+2;local r,g,b,a;if fmt==4 then r,g,b,a=rgb565(v) else r,g,b,a=rgb5a3c(v) end;set(px,w,h,bx+x,by+y,r,g,b,a) end end;return o end)
  elseif fmt==6 then -- RGBA8: 32-byte AR plane + 32-byte GB plane per 4x4 block
    blockLoop(w,h,4,4,function(bx,by,o)local ar=o;local gb=o+32;for y=0,3 do for x=0,3 do local a=data:byte(ar+1) or 0;local r=data:byte(ar+2) or 0;local g=data:byte(gb+1) or 0;local b=data:byte(gb+2) or 0;ar=ar+2;gb=gb+2;set(px,w,h,bx+x,by+y,r,g,b,a) end end;return o+64 end)
  elseif fmt==8 or fmt==9 or fmt==10 then
    assert(type(palette)=="string","paletted GX texture without TLUT")
    if fmt==8 then
      blockLoop(w,h,8,8,function(bx,by,o)for y=0,7 do for x=0,7,2 do local q=data:byte(o+1) or 0;o=o+1;for k,idx in ipairs({floor(q/16),q%16}) do local r,g,b,a=palColor(palette,palFmt or 2,idx);set(px,w,h,bx+x+k-1,by+y,r,g,b,a) end end end;return o end)
    elseif fmt==9 then
      blockLoop(w,h,8,4,function(bx,by,o)for y=0,3 do for x=0,7 do local idx=data:byte(o+1) or 0;o=o+1;local r,g,b,a=palColor(palette,palFmt or 2,idx);set(px,w,h,bx+x,by+y,r,g,b,a) end end;return o end)
    else
      blockLoop(w,h,4,4,function(bx,by,o)for y=0,3 do for x=0,3 do local idx=be16(data,o+1)%16384;o=o+2;local r,g,b,a=palColor(palette,palFmt or 2,idx);set(px,w,h,bx+x,by+y,r,g,b,a) end end;return o end)
    end
  elseif fmt==14 then -- CMPR / GC tiled DXT1
    blockLoop(w,h,8,8,function(bx,by,o)
      for sub=0,3 do
        local sx=(sub%2)*4;local sy=floor(sub/2)*4
        local c0=be16(data,o+1);local c1=be16(data,o+3);local r0,g0,b0=rgb565(c0);local r1,g1,b1=rgb565(c1);local cs={{r0,g0,b0,255},{r1,g1,b1,255}}
        if c0>c1 then cs[3]={floor((2*r0+r1)/3),floor((2*g0+g1)/3),floor((2*b0+b1)/3),255};cs[4]={floor((r0+2*r1)/3),floor((g0+2*g1)/3),floor((b0+2*b1)/3),255}
        else cs[3]={floor((r0+r1)/2),floor((g0+g1)/2),floor((b0+b1)/2),255};cs[4]={0,0,0,0} end
        for y=0,3 do local bits=data:byte(o+5+y) or 0;for x=0,3 do local idx=floor(bits/(2^(6-2*x)))%4+1;local c=cs[idx];set(px,w,h,bx+sx+x,by+sy+y,c[1],c[2],c[3],c[4]) end end
        o=o+8
      end
      return o
    end)
  else error("unsupported GX texture format "..tostring(fmt)) end
  return table.concat(px)
end
return G
