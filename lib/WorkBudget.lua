-- Cooperative CPU preparation. No battle state, input or settings are owned
-- here. Deadlines are best-effort: a host read/write or GPU call cannot yield.
local W={version=1}
local contexts=setmetatable({}, {__mode="k"})
local stats={resumes=0,yields=0,completed=0,failed=0,maxMs=0,totalMs=0,lastMs=0}
local function clock()
  if love and love.timer and love.timer.getTime then return love.timer.getTime() end
  return os.clock()
end
local function context()
  local co,main=coroutine.running()
  return co and not main and contexts[co] or nil
end
function W.checkpoint(label)
  local c=context();if not c then return end
  if label then c.label=tostring(label) end
  if clock()>=c.deadline then
    stats.yields=stats.yields+1
    coroutine.yield("working",c.label)
  end
end
function W.onCancel(fn)
  local c=context()
  if not c then return function() end end
  local token={fn=fn};c.cleanup[#c.cleanup+1]=token
  return function() token.fn=nil end
end
function W.new(fn,label)
  local co=coroutine.create(fn)
  contexts[co]={deadline=0,label=label or "Preparing model",cleanup={}}
  return co
end
function W.cancel(co)
  local c=contexts[co]
  if c then
    for _,token in ipairs(c.cleanup) do if token.fn then pcall(token.fn) end end
  end
  contexts[co]=nil
end
function W.resume(co,milliseconds)
  local c=contexts[co]
  if not c then return false,"task cancelled" end
  local start=clock();c.deadline=start+math.max(0.25,tonumber(milliseconds) or 3)/1000
  local ok,a,b=coroutine.resume(co)
  local ms=math.max(0,(clock()-start)*1000)
  stats.resumes=stats.resumes+1;stats.lastMs=ms;stats.totalMs=stats.totalMs+ms;stats.maxMs=math.max(stats.maxMs,ms)
  if not ok then stats.failed=stats.failed+1;W.cancel(co);return false,a end
  if coroutine.status(co)=="dead" then
    if a==false or a==nil then W.cancel(co) else contexts[co]=nil end
    stats.completed=stats.completed+1
    return true,"done",a,b
  end
  return true,"working",c.label
end
function W.label(co) local c=contexts[co];return c and c.label end
function W.status()
  local out={};for k,v in pairs(stats) do out[k]=v end;return out
end
return W
