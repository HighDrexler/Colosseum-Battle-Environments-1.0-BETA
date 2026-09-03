local V=...
local Assets=V.GeneratedAssets
local R={version=1}
local unpackArgs=table.unpack or unpack

function R.supported()
  return love and love.data and type(love.data.pack)=="function" and type(love.data.newByteData)=="function"
    and love.graphics and type(love.graphics.newMesh)=="function"
end

local function finite(n)
  n=tonumber(n) or 0
  if n~=n or n==math.huge or n==-math.huge then return 0 end
  return n
end

-- Rows are packed in batches rather than one love.data.pack call (plus one
-- scratch table and one intermediate string) per vertex. A single arena or
-- Pokemon body is tens of thousands of rows, so this removes the dominant
-- allocation cost of writing a runtime sidecar. Output bytes are unchanged.
local PACK_BATCH=64

function R.packRows(rows,stride)
  stride=math.max(1,math.floor(tonumber(stride) or 0))
  if stride<=0 or not R.supported() then return nil,"runtime binary mesh API unavailable" end
  rows=rows or {}
  local count=#rows
  if count==0 then return nil,"no vertex rows" end
  local rowFmt=string.rep("f",stride)
  local batchFmt=string.rep(rowFmt,PACK_BATCH)
  local buf={}
  local chunks,chunkCount={},0
  local i=1
  while i<=count do
    local take=count-i+1;if take>PACK_BATCH then take=PACK_BATCH end
    local k=0
    for r=i,i+take-1 do
      local row=rows[r]
      if type(row)~="table" then return nil,"vertex row missing" end
      for j=1,stride do
        local v=tonumber(row[j]) or 0
        if v~=v or v==math.huge or v==-math.huge then v=0 end
        k=k+1;buf[k]=v
      end
    end
    local ok,bytes=pcall(love.data.pack,"string",
      take==PACK_BATCH and batchFmt or string.rep(rowFmt,take),unpackArgs(buf,1,k))
    if not ok or type(bytes)~="string" then return nil,tostring(bytes or "love.data.pack failed") end
    chunkCount=chunkCount+1;chunks[chunkCount]=bytes
    i=i+take
  end
  return table.concat(chunks,"",1,chunkCount)
end

function R.writeRows(path,rows,stride)
  if not (Assets and Assets.write) then return false,"generated cache writer unavailable" end
  local bytes,err=R.packRows(rows,stride);if not bytes then return false,err end
  local ok,why=Assets.write(path,bytes)
  return ok~=false and ok~=nil,why,#bytes
end

function R.meshFromBytes(format,bytes,stride,usage)
  if not (R.supported() and type(bytes)=="string") then return nil,"runtime binary mesh unavailable" end
  stride=math.max(1,math.floor(tonumber(stride) or 0))
  local bytesPerVertex=stride*4
  if bytesPerVertex<=0 or #bytes<bytesPerVertex or (#bytes%bytesPerVertex)~=0 then
    return nil,"runtime binary mesh byte count/stride mismatch"
  end
  local count=math.floor(#bytes/bytesPerVertex)
  local okMesh,mesh=pcall(love.graphics.newMesh,format,count,"triangles",usage or "static")
  if not okMesh or not mesh then return nil,tostring(mesh or "newMesh failed") end
  local okData,data=pcall(love.data.newByteData,bytes)
  if not okData or not data then pcall(function() if mesh.release then mesh:release() end end);return nil,tostring(data or "newByteData failed") end
  local okSet,setErr=pcall(mesh.setVertices,mesh,data,1,count)
  if not okSet then pcall(function() if mesh.release then mesh:release() end end);return nil,tostring(setErr) end
  return mesh,nil,count
end

function R.meshFromPath(format,path,stride,usage)
  if not (Assets and Assets.read) then return nil,"generated cache reader unavailable" end
  local bytes,err=Assets.read(path);if type(bytes)~="string" then return nil,err end
  return R.meshFromBytes(format,bytes,stride,usage)
end

local function keySort(a,b)
  local ta,tb=type(a),type(b)
  if ta==tb then return tostring(a)<tostring(b) end
  return ta<tb
end
local function serialize(v,seen,depth)
  local t=type(v)
  if t=="nil" then return "nil" end
  if t=="boolean" then return v and "true" or "false" end
  if t=="number" then return string.format("%.17g",finite(v)) end
  if t=="string" then return string.format("%q",v) end
  if t~="table" then return "nil" end
  depth=(depth or 0)+1;if depth>24 then return "nil" end
  seen=seen or {};if seen[v] then return "nil" end;seen[v]=true
  local keys={};for k in pairs(v) do if type(k)=="string" or type(k)=="number" then keys[#keys+1]=k end end
  table.sort(keys,keySort)
  local out={"{"}
  for _,k in ipairs(keys) do
    local ks=type(k)=="number" and ("["..string.format("%.17g",k).."]") or ("["..string.format("%q",k).."]")
    out[#out+1]=ks.."="..serialize(v[k],seen,depth).."," 
  end
  out[#out+1]="}";seen[v]=nil
  return table.concat(out)
end
function R.writeLua(path,value)
  if not (Assets and Assets.write) then return false,"generated cache writer unavailable" end
  local ok,err=Assets.write(path,"return "..serialize(value).."\n")
  return ok~=false and ok~=nil,err
end
function R.readLua(path)
  if not (Assets and Assets.read) then return nil,"generated cache reader unavailable" end
  local src,err=Assets.read(path);if type(src)~="string" then return nil,err end
  local f,e=load(src,"@generated/"..tostring(path));if not f then return nil,e end
  local ok,v=pcall(f);if not ok then return nil,v end
  return v
end
function R.read(path)
  return Assets and Assets.read and Assets.read(path) or nil
end
function R.exists(path)
  return Assets and Assets.exists and Assets.exists(path) or false
end
return R
