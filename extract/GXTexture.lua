local G={}
local floor=math.floor
local byte=string.byte
local char=string.char
local concat=table.concat

-- Pre-interned single-byte strings. `string.char` is a C call plus a hash
-- lookup for every channel; an array index is neither.
local CHR={} for i=0,255 do CHR[i]=char(i) end
-- Pre-expanded 4-bit -> 8-bit ramps and grayscale/alpha strings.
local E4={} for i=0,15 do E4[i]=i*17 end
local E5={} for i=0,31 do E5[i]=floor(i*255/31+.5) end
local E6={} for i=0,63 do E6[i]=floor(i*255/63+.5) end
-- Opaque grayscale pixel for every intensity value (I4/I8 fast path).
local GREY={} for i=0,255 do GREY[i]=char(i,i,i,255) end

local function be16(s,p)local a,b=s:byte(p,p+1);if not b then return 0 end;return a*256+b end
local function expand4(v)return v*17 end
local function expand5(v)return floor(v*255/31+.5) end
local function expand6(v)return floor(v*255/63+.5) end
local function rgb565(v)return E5[floor(v/2048)%32],E6[floor(v/32)%64],E5[v%32],255 end
local function rgb5a3c(v)
  if v>=32768 then return E5[floor((v-32768)/1024)%32],E5[floor(v/32)%32],E5[v%32],255 end
  local a=floor(v/4096)%8;local r=floor(v/256)%16;local g=floor(v/16)%16;local b=v%16
  return r*17,g*17,b*17,floor(a*255/7+.5)
end
local function palColor(pal,fmt,idx)
  local v=be16(pal,idx*2+1)
  if fmt==0 then local a=floor(v/256);local i=v%256;return i,i,i,a
  elseif fmt==1 then return rgb565(v)
  else return rgb5a3c(v) end
end

-- Decode the TLUT once into ready-made 4-byte pixel strings instead of
-- re-deriving a colour for every single texel that references it.
local function palTable(pal,fmt,count)
  local t={}
  local n=math.min(count,floor(#pal/2))
  for i=0,n-1 do
    local r,g,b,a=palColor(pal,fmt,i)
    t[i]=char(r,g,b,a)
  end
  local blank=char(0,0,0,0)
  for i=n,count-1 do t[i]=blank end
  return t
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
  local px={};local blank="\0\0\0\0"
  for i=1,w*h do px[i]=blank end

  if fmt==0 then -- I4
    local o=0
    for by=0,h-1,8 do for bx=0,w-1,8 do
      for y=0,7 do
        local ry=by+y
        if ry<h then
          local row=ry*w
          for x=0,7,2 do
            local q=byte(data,o+1) or 0;o=o+1
            local cx=bx+x
            if cx<w then px[row+cx+1]=GREY[E4[floor(q/16)]] end
            if cx+1<w then px[row+cx+2]=GREY[E4[q%16]] end
          end
        else o=o+4 end
      end
    end end
  elseif fmt==1 then -- I8
    local o=0
    for by=0,h-1,4 do for bx=0,w-1,8 do
      for y=0,3 do
        local ry=by+y
        if ry<h then
          local row=ry*w
          for x=0,7 do
            local q=byte(data,o+1) or 0;o=o+1
            local cx=bx+x
            if cx<w then px[row+cx+1]=GREY[q] end
          end
        else o=o+8 end
      end
    end end
  elseif fmt==2 then -- IA4
    local o=0
    for by=0,h-1,4 do for bx=0,w-1,8 do
      for y=0,3 do
        local ry=by+y
        if ry<h then
          local row=ry*w
          for x=0,7 do
            local q=byte(data,o+1) or 0;o=o+1
            local cx=bx+x
            if cx<w then
              local a=E4[floor(q/16)];local i=E4[q%16]
              px[row+cx+1]=CHR[i]..CHR[i]..CHR[i]..CHR[a]
            end
          end
        else o=o+8 end
      end
    end end
  elseif fmt==3 then -- IA8
    local o=0
    for by=0,h-1,4 do for bx=0,w-1,4 do
      for y=0,3 do
        local ry=by+y
        if ry<h then
          local row=ry*w
          for x=0,3 do
            local a=byte(data,o+1) or 0;local i=byte(data,o+2) or 0;o=o+2
            local cx=bx+x
            if cx<w then px[row+cx+1]=CHR[i]..CHR[i]..CHR[i]..CHR[a] end
          end
        else o=o+8 end
      end
    end end
  elseif fmt==4 or fmt==5 then
    local five=(fmt==4)
    local o=0
    for by=0,h-1,4 do for bx=0,w-1,4 do
      for y=0,3 do
        local ry=by+y
        if ry<h then
          local row=ry*w
          for x=0,3 do
            local v=be16(data,o+1);o=o+2
            local cx=bx+x
            if cx<w then
              local r,g,b,a
              if five then r,g,b,a=rgb565(v) else r,g,b,a=rgb5a3c(v) end
              px[row+cx+1]=char(r,g,b,a)
            end
          end
        else o=o+8 end
      end
    end end
  elseif fmt==6 then -- RGBA8: 32-byte AR plane + 32-byte GB plane per 4x4 block
    local o=0
    for by=0,h-1,4 do for bx=0,w-1,4 do
      local ar=o;local gb=o+32
      for y=0,3 do
        local ry=by+y
        if ry<h then
          local row=ry*w
          for x=0,3 do
            local a=byte(data,ar+1) or 0;local r=byte(data,ar+2) or 0
            local g=byte(data,gb+1) or 0;local b=byte(data,gb+2) or 0
            ar=ar+2;gb=gb+2
            local cx=bx+x
            if cx<w then px[row+cx+1]=char(r,g,b,a) end
          end
        else ar=ar+8;gb=gb+8 end
      end
      o=o+64
    end end
  elseif fmt==8 or fmt==9 or fmt==10 then
    assert(type(palette)=="string","paletted GX texture without TLUT")
    local pf=palFmt or 2
    if fmt==8 then
      local LUT=palTable(palette,pf,16)
      local o=0
      for by=0,h-1,8 do for bx=0,w-1,8 do
        for y=0,7 do
          local ry=by+y
          if ry<h then
            local row=ry*w
            for x=0,7,2 do
              local q=byte(data,o+1) or 0;o=o+1
              local cx=bx+x
              if cx<w then px[row+cx+1]=LUT[floor(q/16)] end
              if cx+1<w then px[row+cx+2]=LUT[q%16] end
            end
          else o=o+4 end
        end
      end end
    elseif fmt==9 then
      local LUT=palTable(palette,pf,256)
      local o=0
      for by=0,h-1,4 do for bx=0,w-1,8 do
        for y=0,3 do
          local ry=by+y
          if ry<h then
            local row=ry*w
            for x=0,7 do
              local idx=byte(data,o+1) or 0;o=o+1
              local cx=bx+x
              if cx<w then px[row+cx+1]=LUT[idx] end
            end
          else o=o+8 end
        end
      end end
    else
      -- C14X2 addresses up to 16384 entries but a real texture touches only a
      -- handful, so this palette is memoized on demand instead of eagerly.
      local LUT={}
      local o=0
      for by=0,h-1,4 do for bx=0,w-1,4 do
        for y=0,3 do
          local ry=by+y
          if ry<h then
            local row=ry*w
            for x=0,3 do
              local idx=be16(data,o+1)%16384;o=o+2
              local cx=bx+x
              if cx<w then
                local e=LUT[idx]
                if not e then
                  local r,g,b,a=palColor(palette,pf,idx);e=char(r,g,b,a);LUT[idx]=e
                end
                px[row+cx+1]=e
              end
            end
          else o=o+8 end
        end
      end end
    end
  elseif fmt==14 then -- CMPR / GC tiled DXT1
    local o=0
    for by=0,h-1,8 do for bx=0,w-1,8 do
      for sub=0,3 do
        local sx=(sub%2)*4;local sy=floor(sub/2)*4
        local c0=be16(data,o+1);local c1=be16(data,o+3)
        local r0,g0,b0=rgb565(c0);local r1,g1,b1=rgb565(c1)
        local p1=char(r0,g0,b0,255)
        local p2=char(r1,g1,b1,255)
        local p3,p4
        if c0>c1 then
          p3=char(floor((2*r0+r1)/3),floor((2*g0+g1)/3),floor((2*b0+b1)/3),255)
          p4=char(floor((r0+2*r1)/3),floor((g0+2*g1)/3),floor((b0+2*b1)/3),255)
        else
          p3=char(floor((r0+r1)/2),floor((g0+g1)/2),floor((b0+b1)/2),255)
          p4="\0\0\0\0"
        end
        for y=0,3 do
          local ry=by+sy+y
          if ry<h then
            local row=ry*w
            local bits=byte(data,o+5+y) or 0
            local i0=floor(bits/64)%4
            local i1=floor(bits/16)%4
            local i2=floor(bits/4)%4
            local i3=bits%4
            local cx=bx+sx
            if cx<w   then px[row+cx+1]=(i0==0 and p1) or (i0==1 and p2) or (i0==2 and p3) or p4 end
            if cx+1<w then px[row+cx+2]=(i1==0 and p1) or (i1==1 and p2) or (i1==2 and p3) or p4 end
            if cx+2<w then px[row+cx+3]=(i2==0 and p1) or (i2==1 and p2) or (i2==2 and p3) or p4 end
            if cx+3<w then px[row+cx+4]=(i3==0 and p1) or (i3==1 and p2) or (i3==2 and p3) or p4 end
          end
        end
        o=o+8
      end
    end end
  else error("unsupported GX texture format "..tostring(fmt)) end
  return concat(px)
end
return G
