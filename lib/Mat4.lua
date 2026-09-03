local M = {}

local cos,sin,tan,sqrt=math.cos,math.sin,math.tan,math.sqrt

function M.identity()
  return {1,0,0,0, 0,1,0,0, 0,0,1,0, 0,0,0,1}
end

-- Row-major 4x4 multiply. Unrolled: the previous nested loop recomputed
-- r*4+c index arithmetic 16 times per call, and mul() is on the per-frame
-- path for the arena, both trainers and every visible Pokemon actor.
function M.mul(a,b)
  local a1,a2,a3,a4=a[1],a[2],a[3],a[4]
  local a5,a6,a7,a8=a[5],a[6],a[7],a[8]
  local a9,a10,a11,a12=a[9],a[10],a[11],a[12]
  local a13,a14,a15,a16=a[13],a[14],a[15],a[16]
  local b1,b2,b3,b4=b[1],b[2],b[3],b[4]
  local b5,b6,b7,b8=b[5],b[6],b[7],b[8]
  local b9,b10,b11,b12=b[9],b[10],b[11],b[12]
  local b13,b14,b15,b16=b[13],b[14],b[15],b[16]
  return {
    a1*b1+a2*b5+a3*b9+a4*b13,      a1*b2+a2*b6+a3*b10+a4*b14,     a1*b3+a2*b7+a3*b11+a4*b15,     a1*b4+a2*b8+a3*b12+a4*b16,
    a5*b1+a6*b5+a7*b9+a8*b13,      a5*b2+a6*b6+a7*b10+a8*b14,     a5*b3+a6*b7+a7*b11+a8*b15,     a5*b4+a6*b8+a7*b12+a8*b16,
    a9*b1+a10*b5+a11*b9+a12*b13,   a9*b2+a10*b6+a11*b10+a12*b14,  a9*b3+a10*b7+a11*b11+a12*b15,  a9*b4+a10*b8+a11*b12+a12*b16,
    a13*b1+a14*b5+a15*b9+a16*b13,  a13*b2+a14*b6+a15*b10+a16*b14, a13*b3+a14*b7+a15*b11+a16*b15, a13*b4+a14*b8+a15*b12+a16*b16,
  }
end

function M.translate(x,y,z)
  return {1,0,0,x, 0,1,0,y, 0,0,1,z, 0,0,0,1}
end

function M.scale(x,y,z)
  return {x,0,0,0, 0,y,0,0, 0,0,z,0, 0,0,0,1}
end

function M.rotateY(a)
  local c,s=cos(a),sin(a)
  return {c,0,s,0, 0,1,0,0, -s,0,c,0, 0,0,0,1}
end

function M.rotateX(a)
  local c,s=cos(a),sin(a)
  return {1,0,0,0, 0,c,-s,0, 0,s,c,0, 0,0,0,1}
end

function M.rotateZ(a)
  local c,s=cos(a),sin(a)
  return {c,-s,0,0, s,c,0,0, 0,0,1,0, 0,0,0,1}
end

function M.perspective(fovY,aspect,near,far)
  local f=1/tan(fovY/2)
  local d=near-far
  return {f/aspect,0,0,0, 0,f,0,0,
          0,0,(far+near)/d,(2*far*near)/d, 0,0,-1,0}
end

-- lookAt previously allocated four closures (sub/norm/cross/dot) on EVERY
-- call, i.e. every frame per camera, plus five intermediate vector tables.
-- Identical math, computed on scalars.
function M.lookAt(eye,target,up)
  local ex,ey,ez=eye[1],eye[2],eye[3]
  local fx,fy,fz=target[1]-ex,target[2]-ey,target[3]-ez
  local l=sqrt(fx*fx+fy*fy+fz*fz)
  if l<1e-9 then fx,fy,fz=0,0,0 else fx,fy,fz=fx/l,fy/l,fz/l end
  local px,py,pz=up[1],up[2],up[3]
  local sx,sy,sz=fy*pz-fz*py, fz*px-fx*pz, fx*py-fy*px
  l=sqrt(sx*sx+sy*sy+sz*sz)
  if l<1e-9 then sx,sy,sz=0,0,0 else sx,sy,sz=sx/l,sy/l,sz/l end
  local ux,uy,uz=sy*fz-sz*fy, sz*fx-sx*fz, sx*fy-sy*fx
  return {sx,sy,sz,-(sx*ex+sy*ey+sz*ez),
          ux,uy,uz,-(ux*ex+uy*ey+uz*ez),
          -fx,-fy,-fz,(fx*ex+fy*ey+fz*ez),
          0,0,0,1}
end

return M
