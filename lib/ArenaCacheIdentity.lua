-- Canonical arena identity; generated off the battle-entry path.
local I={version=1}
function I.fingerprint(bytes)
 assert(type(bytes)=='string','arena source bytes required')
 if love and love.data and love.data.hash then
  local raw=love.data.hash('sha256',bytes)
  return 'sha256:'..(raw:gsub('.',function(c)return string.format('%02x',c:byte())end))
 end
 -- Deterministic headless fallback; production LÖVE always uses SHA-256.
 local a,b=1,0
 for i=1,#bytes do a=(a+bytes:byte(i))%65521;b=(b+a)%65521 end
 return ('adler32:%08x:%d'):format(b*65536+a,#bytes)
end
return I
