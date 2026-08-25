local T={}
local function clamp(v)return v<0 and 0 or (v>255 and 255 or math.floor(v+.5)) end
local function mask(kind)
  local w,h=256,256;local out={};local n=0
  for y=0,h-1 do for x=0,w-1 do
    local dx=(x-127.5)/127.5;local dy=(y-127.5)/127.5;local r=math.sqrt(dx*dx+dy*dy)
    local a=0
    if kind==1 then
      local shell=(r<.94 and r>.69);local bar=(math.abs(dy)<.075 and r<.72);local button=(r<.235 and r>.145);local center=(r<.115)
      if shell or bar or button or center then a=255 end
    else
      local shell=r<.94;local inner=r<.52;local bar=math.abs(dy)<.105 and r<.92;local button=r<.22
      if shell then a=230 end;if inner then a=185 end;if bar or button then a=255 end
    end
    n=n+1;out[n]=string.char(255,255,255,clamp(a))
  end end
  return table.concat(out)
end
local function write(mod,path,data,generated)local ok,err=mod.cache:write(path,data);assert(ok,err or ("cache write failed: "..path));generated[#generated+1]=path end
function T.run(mod,disc,progress,generated)
  progress("TRANSITION MASK A",0,2);write(mod,"assets/transition/wipe_ball00.rgba",mask(1),generated)
  progress("TRANSITION MASK B",1,2);write(mod,"assets/transition/wipe_ball01.rgba",mask(2),generated)
  progress("TRANSITION READY",2,2)
  return true
end
return T
