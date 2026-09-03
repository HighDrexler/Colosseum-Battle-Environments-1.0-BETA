local V = ...
local mod, Mat4, Trainer, PlayerTrainer =
  V.mod, V.Mat4, V.Trainer, V.PlayerTrainer
local CurrentSpriteModels=V.CurrentSpriteModels
local ArenaCatalog=V.ArenaCatalog
local GeneratedAssets=V.GeneratedAssets
local RuntimeMeshCache=V.RuntimeMeshCache
local A = {}

local function platformOS()
  if love and love.system and type(love.system.getOS)=="function" then
    local ok,v=pcall(love.system.getOS);if ok and v then return tostring(v) end
  end
  return "Unknown"
end
local ARENA_ANDROID=platformOS()=="Android"

local function cbePokemonModelsEnabled(ctx)
  local settings=V.BattleSettings
  if not (settings and type(settings.pokemonModelsEnabled)=="function") then return true end
  local game=(ctx and ctx.game) or (ctx and ctx.battle and ctx.battle.game) or mod.game
  local ok,value=pcall(settings.pokemonModelsEnabled,game)
  return (not ok) or value~=false
end

local function standaloneContext(ctx)
  return type(ctx)=="table" and type(ctx.services)=="table"
    and ctx.services.cbeStandalone==true
end

-- The projector reads its matrix and viewport from upvalues that are
-- refreshed each frame, so the closure and the renderSize table are allocated
-- once for the process instead of once per frame. Consumers still see the same
-- services.project(x,y,z) contract and the same live values.
local projVP,projW,projH=nil,0,0
local projectService=function(x,y,z)
  local m=projVP
  if not m then return nil end
  local cx=m[1]*x+m[2]*y+m[3]*z+m[4]
  local cy=m[5]*x+m[6]*y+m[7]*z+m[8]
  local cw=m[13]*x+m[14]*y+m[15]*z+m[16]
  if not cw or cw<=1e-6 then return nil end
  return (cx/cw*.5+.5)*projW,(cy/cw*.5+.5)*projH
end
local renderSizeService={width=0,height=0}
local function installActorServices(ctx,actorVP,stageVP,w,h,figure,pose)
  ctx.services=type(ctx.services)=="table" and ctx.services or {}
  ctx.services.vp=actorVP
  ctx.services.stageVP=stageVP
  ctx.services.figureScale=figure
  projVP,projW,projH=actorVP,w,h
  renderSizeService.width=w;renderSizeService.height=h
  ctx.services.renderSize=renderSizeService
  ctx.services.camera=ctx.services.camera or {}
  if pose then ctx.services.camera.pose=pose end
  ctx.services.project=projectService
end

local FORMAT = {
  {"VertexPosition","float",3},
  {"VertexTexCoord","float",2},
  {"VertexTint","float",4},
  {"VertexNormal","float",3},
}
local VERTEX = [[
uniform mat4 vp;
uniform mat4 model;
uniform float materialMode;
uniform float materialFlow;
uniform float sceneTime;
attribute vec4 VertexTint;
attribute vec3 VertexNormal;
varying vec4 tint;
varying vec3 worldPos;
varying vec3 worldNormal;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  tint = VertexTint;
  vec4 localPos = vertex_position;
  vec3 localNormal = VertexNormal;
  if (materialMode > 0.5 && materialMode < 1.5) {
    if (materialFlow < 0.5) {
      /* Horizontal pools carry true cross-wave displacement and normals. */
      float p1 = vertex_position.x * 0.052 + sceneTime * 1.12;
      float p2 = vertex_position.z * 0.067 - sceneTime * 0.87;
      float w1 = sin(p1);
      float w2 = sin(p2);
      localPos.y += w1 * 0.34 + w2 * 0.22;
      float dhdx = 0.34 * 0.052 * cos(p1);
      float dhdz = 0.22 * 0.067 * cos(p2);
      vec3 waveNormal = normalize(vec3(-dhdx,1.0,-dhdz));
      localNormal = normalize(mix(VertexNormal,waveNormal,0.82));
    } else {
      /* Vertical waterfall sheets stay anchored to their stone channels; a
         tiny lateral ripple keeps the silhouette from reading as a glass pane. */
      localPos.x += sin(vertex_position.y*0.045 + sceneTime*1.36) * 0.10;
    }
  } else if (materialMode > 3.5 && materialMode < 4.5) {
    /* Source crowd cards keep their original seats, but each disconnected card
       receives a stable phase from VertexTint. This breaks the synchronized
       cardboard-wall look without creating any new floating geometry. UV.y is
       bottom=1/top=0 so feet stay planted behind the balcony lip. */
    float tip = 1.0-clamp(VertexTexCoord.y,0.0,1.0);
    float cardPhase=clamp((tint.r-.80)*5.0,0.0,1.0);
    float cp=cardPhase*6.2831853 + floor(vertex_position.y*.035)*.43;
    float tempo=.54+cardPhase*.31;
    float sway=sin(sceneTime*tempo+cp);
    float sway2=sin(sceneTime*(.39+cardPhase*.17)-cp*1.37);
    float cheerBase=max(0.0,sin(sceneTime*.31+cp*1.91));
    float cheer=pow(cheerBase,14.0);
    localPos.y += (sway*.105+sway2*.035+cheer*.34)*tip;
    localPos.x += (sway2*.050+cheer*(cardPhase-.5)*.085)*tip;
    localPos.z += (sway*.028+cheer*.030)*tip;
  } else if (materialMode > 3.10 && materialMode < 3.40) {
    /* Wildland foliage cards: very restrained summit/field wind.  UV.y is
       authored bottom=1/top=0, so trunks/grass roots stay planted while leaf
       tips and grass crowns move just enough to keep the biome alive. */
    float tip = 1.0-clamp(VertexTexCoord.y,0.0,1.0);
    float gust = sin(sceneTime*1.18 + vertex_position.x*0.033 + vertex_position.z*0.027)
               + 0.42*sin(sceneTime*0.63 - vertex_position.x*0.019 + vertex_position.z*0.041);
    float amp = materialFlow > 0.75 ? 0.42 : 0.20;
    localPos.x += gust*amp*tip;
    localPos.z += sin(sceneTime*0.91 + vertex_position.z*0.035)*amp*0.42*tip;
  } else if (materialMode > 4.5) {
    /* Platform 100 lava needs actual geometry motion, not just a scrolling
       picture. Horizontal magma rolls in two directions; vertical falls whip
       slightly inside their rock channels. Source units are quarter-scaled
       later, so these amplitudes remain controlled in world space. */
    if (materialFlow < 0.5) {
      float l1 = vertex_position.x*0.057 + vertex_position.z*0.027 + sceneTime*2.72;
      float l2 = vertex_position.z*0.074 - vertex_position.x*0.024 - sceneTime*2.03;
      float l3 = (vertex_position.x+vertex_position.z)*0.031 + sceneTime*3.48;
      float radial = length(vertex_position.xz)*0.035 - sceneTime*1.92;
      /* Keep the molten surface visibly alive, but damp physical displacement
         where it meets the Platform 100 ring and the outer crater rock. This
         prevents the rolling mesh from periodically poking through authored
         steel/rock while texture transport continues at full speed. */
      float lavaR = length(vertex_position.xz);
      float innerSafe = smoothstep(155.0,205.0,lavaR);
      float outerSafe = 1.0-smoothstep(320.0,382.0,lavaR);
      float geomLife = mix(0.12,1.0,clamp(innerSafe*outerSafe,0.0,1.0));
      float h1 = sin(l1)*2.45;
      float h2 = sin(l2)*1.55;
      float h3 = sin(l3)*0.62;
      float h4 = sin(radial)*0.82;
      localPos.y += (h1+h2+h3+h4)*geomLife;
      float dx = (2.45*0.057*cos(l1) - 1.55*0.024*cos(l2) + 0.62*0.031*cos(l3)
                 + 0.82*0.035*cos(radial)*(vertex_position.x/max(lavaR,1.0)))*geomLife;
      float dz = (2.45*0.027*cos(l1) + 1.55*0.074*cos(l2) + 0.62*0.031*cos(l3)
                 + 0.82*0.035*cos(radial)*(vertex_position.z/max(lavaR,1.0)))*geomLife;
      localNormal = normalize(mix(VertexNormal,normalize(vec3(-dx,1.0,-dz)),0.92));
    } else {
      /* Waterfall mesh is now subdivided, so small phase differences between
         rows/columns create a rolling molten sheet instead of translating one
         rigid quad. Keep the lip almost fixed and let instability build toward
         the receiving pool. */
      float f = vertex_position.y*0.071 + VertexTexCoord.x*5.7 + sceneTime*3.18;
      float f2 = vertex_position.y*0.033 - VertexTexCoord.x*8.2 - sceneTime*1.67;
      float amp = 0.18 + 0.82*clamp(abs(VertexTexCoord.y)*0.22,0.0,1.0);
      localPos.x += (sin(f)*0.82 + sin(f2)*0.31)*amp;
      localPos.z += (cos(f*0.73)*0.38 + sin(f2*1.17)*0.16)*amp;
      localNormal = normalize(mix(VertexNormal,normalize(VertexNormal + vec3(sin(f)*.16,0.0,cos(f2)*.14)),0.48));
    }
  }
  vec4 world = model * localPos;
  worldPos = world.xyz;
  worldNormal = normalize((model * vec4(localNormal,0.0)).xyz);
  return vp * world;
}
]]
local MOBILE_VERTEX = [[
uniform mat4 vp;
uniform mat4 model;
attribute vec4 VertexTint;
attribute vec3 VertexNormal;
varying vec4 tint;
varying vec3 worldNormal;
vec4 position(mat4 transform_projection, vec4 vertex_position) {
  tint = VertexTint;
  worldNormal = normalize((model * vec4(VertexNormal,0.0)).xyz);
  return vp * (model * vertex_position);
}
]]
local MOBILE_PIXEL = [[
uniform float materialAlpha;
uniform float sceneProfile;
uniform vec3 materialDiffuse;
uniform vec3 materialAmbient;
varying vec4 tint;
varying vec3 worldNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  vec4 tex = Texel(texture,uv) * color * tint;
  if (tex.a <= 0.012) discard;
  float ndl = max(dot(normalize(worldNormal),normalize(vec3(0.34,0.83,0.44))),0.0);
  if (sceneProfile < 0.5) {
    /* Phenac / Water Colosseum: the source HSD already carries bright diffuse
       and ambient values. Adding both at full strength on the GLES fast path
       clipped the limestone floor/walls almost completely white. Keep the
       authentic pale stone, but restore the grey joints, water recesses and
       shaded wall faces visible in the GameCube arena. */
    vec3 light = materialAmbient * 0.22
      + materialDiffuse * (0.39 + ndl * 0.31);
    light = clamp(light,vec3(0.16),vec3(0.84));
    vec3 shaded = tex.rgb * light;
    float luma = dot(shaded,vec3(0.299,0.587,0.114));
    shaded = mix(vec3(luma)*vec3(0.965,0.990,1.015),shaded,0.90);
    shaded = clamp((shaded-vec3(0.46))*0.95+vec3(0.43),vec3(0.0),vec3(0.88));
    return vec4(shaded,tex.a * materialAlpha);
  }
  vec3 light = clamp(materialAmbient + materialDiffuse * (0.42 + ndl*0.58),0.0,1.65);
  return vec4(tex.rgb * light, tex.a * materialAlpha);
}
]]
local PIXEL = [[
uniform float materialAlpha;
uniform float materialMode;
uniform float materialFlow;
uniform float sceneTime;
uniform float sceneRadiusWorld;
uniform float sceneProfile;
uniform vec3 cameraEye;
uniform vec3 materialDiffuse;
uniform vec3 materialAmbient;
uniform vec3 materialSpecular;
uniform float materialShininess;
uniform float materialDetail;
uniform vec2 texelStep;
varying vec4 tint;
varying vec3 worldPos;
varying vec3 worldNormal;
vec4 effect(vec4 color, Image texture, vec2 uv, vec2 screen) {
  float arenaRadius = length(worldPos.xz);
  if (arenaRadius > sceneRadiusWorld) discard;

  vec2 sampleUV = uv;
  if (materialMode > 0.5 && materialMode < 1.5) {
    /* Pools drift; vertical waterfall bodies stream downward. */
    sampleUV += materialFlow > 0.5
      ? vec2(sceneTime*0.0025,-sceneTime*0.070)
      : vec2(sceneTime*0.0092,sceneTime*0.0054);
  } else if (materialMode > 1.5 && materialMode < 2.5) {
    /* The extracted waterfall glint is a vertical energy streak. */
    sampleUV += vec2(sin(sceneTime*0.31)*0.006,-sceneTime*0.115);
  } else if (materialMode > 4.5) {
    /* D2 magma: obvious directional transport plus irregular distortion.
       The prior .010 horizontal scroll was technically animated but visually
       indistinguishable from a static texture at battle distance. */
    vec2 lavaWarp=vec2(
      sin(sceneTime*1.03 + uv.y*18.0 + worldPos.z*.018)*.012,
      cos(sceneTime*.87 + uv.x*16.0 + worldPos.x*.015)*.009);
    sampleUV += materialFlow > 0.5
      ? vec2(sin(sceneTime*.91)*.026,-sceneTime*.445)
      : vec2(sceneTime*.094,sceneTime*.049);
    sampleUV += lavaWarp;
  }
  vec4 texel = Texel(texture, sampleUV);
  if (materialMode > 4.5) {
    vec2 lavaUV2 = uv + (materialFlow > 0.5
      ? vec2(-sceneTime*.027,-sceneTime*.258)
      : vec2(-sceneTime*.061,sceneTime*.074));
    vec4 lava2=Texel(texture,lavaUV2);
    float lavaMix=.42+.18*sin(sceneTime*2.02+worldPos.x*.026-worldPos.z*.021);
    texel.rgb=mix(texel.rgb,lava2.rgb,clamp(lavaMix,0.22,0.56));
    texel.a=max(texel.a,lava2.a*.82);
  }
  if (materialMode > 0.5 && materialMode < 1.5) {
    /* A second low-amplitude scroll from the SAME extracted Colosseum water
       texture restores some of the source surface breakup without adding any
       cache assets. This is presentation detail, not another translucent
       geometry sheet. */
    vec2 sampleUV2 = uv + (materialFlow > 0.5
      ? vec2(-sceneTime*0.0018,-sceneTime*0.044)
      : vec2(-sceneTime*0.0042,sceneTime*0.0064));
    vec4 water2 = Texel(texture, sampleUV2);
    texel.rgb = mix(texel.rgb, water2.rgb, 0.22);
    texel.a = max(texel.a, water2.a * 0.72);
  }

  /* Modes 3/4 are binary-alpha GameCube scenery (rails/banners and the
     surviving seated crowd cards). Treat them like alpha-test hardware:
     either the pixel exists and writes depth, or it does not. */
  if (materialMode > 2.5) {
    float a = texel.a * tint.a * materialAlpha * color.a;
    if (a < 0.34) discard;
    texel.a = 1.0;
  }

  if (materialDetail > 0.5 && materialMode < 0.5) {
    float closeDetail = 1.0 - smoothstep(34.0,68.0,length(worldPos-cameraEye));
    if (closeDetail > 0.001) {
      vec3 around = (
        Texel(texture,sampleUV+vec2(texelStep.x,0.0)).rgb +
        Texel(texture,sampleUV-vec2(texelStep.x,0.0)).rgb +
        Texel(texture,sampleUV+vec2(0.0,texelStep.y)).rgb +
        Texel(texture,sampleUV-vec2(0.0,texelStep.y)).rgb
      ) * 0.25;
      vec3 sharpened = clamp(texel.rgb * 1.27 - around * 0.27,vec3(0.0),vec3(1.0));
      texel.rgb = mix(texel.rgb,sharpened,closeDetail*0.45);
    }
  }

  float a = texel.a * tint.a * materialAlpha * color.a;

  /* Extracted waterfall glints are energy layers, not translucent cards. Keep
     only their bright strokes and dramatically reduce their intensity. */
  if (materialMode > 1.5 && materialMode < 2.5) {
    float lum = dot(texel.rgb, vec3(0.299,0.587,0.114));
    float cascade = 0.84 + 0.16*sin(sceneTime*1.46 + worldPos.y*0.20 + worldPos.x*0.035);
    float spray = 0.88 + 0.12*sin(sceneTime*2.15 + worldPos.z*0.11);
    a *= smoothstep(0.12,0.70,lum) * 0.44 * cascade;
    if (a < 0.016) discard;
    vec3 fx = mix(vec3(0.07,0.28,0.44),vec3(0.63,0.88,0.98),clamp(lum*1.22,0.0,1.0));
    fx *= spray;
    return vec4(fx,a);
  }

  if (a < 0.025) discard;

  vec3 n = normalize(worldNormal);
  vec3 lightDir = normalize(vec3(-0.36,0.82,0.44));
  /* Colosseum's scene is full of two-sided GX surfaces. A purely one-sided
     Lambert term made adjacent source polygons flip between bright and dead
     dark depending on winding. This keeps shape while making those surfaces
     visually continuous. */
  float ndl = max(dot(n,lightDir),0.0);
  float twoSide = abs(dot(n,lightDir));
  float hemi = clamp(n.y * 0.5 + 0.5,0.0,1.0);
  vec3 srcMat = mix(vec3(1.0), clamp(materialDiffuse * 1.48, vec3(0.30), vec3(1.15)), 0.24);
  srcMat *= mix(vec3(1.0), clamp(materialAmbient * 1.10, vec3(0.42), vec3(1.14)), 0.10);
  float light = 0.75 + ndl * 0.18 + twoSide * 0.10 + hemi * 0.055;
  vec3 shaded = texel.rgb * mix(vec3(1.0),tint.rgb,0.58) * color.rgb * srcMat * light;

  /* Crowd billboards are already pre-lit artwork in the Colosseum atlas.
     Running them through stone-style normals/specular was bleaching faces and
     making adjacent cards vary wildly. Keep their source colors punchy and
     stable while retaining depth-test occlusion against the stadium. */
  if (materialMode > 3.5 && materialMode < 4.5) {
    vec3 crowd = clamp((texel.rgb - vec3(0.47)) * 1.09 + vec3(0.49),vec3(0.0),vec3(1.0));
    float cardPhase=clamp((tint.r-.80)*5.0,0.0,1.0);
    float crowdLife = 0.982 + 0.028 * sin(sceneTime * (.72+cardPhase*.36) + cardPhase*12.0);
    float footShade=1.0-.075*smoothstep(.68,.98,uv.y);
    float edgeCoverage=(
      Texel(texture,uv+vec2(texelStep.x,0.0)).a+
      Texel(texture,uv-vec2(texelStep.x,0.0)).a+
      Texel(texture,uv+vec2(0.0,texelStep.y)).a+
      Texel(texture,uv-vec2(0.0,texelStep.y)).a)*.25;
    float edgeDepth=.88+.12*smoothstep(.08,.90,edgeCoverage);
    float faceDepth=.93+.07*abs(dot(normalize(worldNormal),normalize(cameraEye-worldPos)));
    crowd *= vec3(1.015,1.010,1.005) * crowdLife * footShade * edgeDepth * faceDepth;
    shaded = crowd * mix(vec3(1.0),tint.rgb,0.10) * color.rgb;
  }

  if (materialMode > 4.5) {
    float lum = dot(texel.rgb,vec3(.299,.587,.114));
    float broad = .80 + .20*sin(sceneTime*2.05 + worldPos.y*.071 + worldPos.x*.022);
    float hotBand = .5+.5*sin(worldPos.x*.104 + worldPos.z*.083 - sceneTime*3.65);
    float boil = .5+.5*sin(worldPos.x*.205 - worldPos.z*.151 + sceneTime*4.45);
    float vein = .5+.5*sin(uv.x*24.0 + uv.y*3.7 - sceneTime*4.8 + worldPos.y*.035);
    float pulse = .5+.5*sin(sceneTime*2.73 + uv.y*5.3);
    vec3 hot = mix(vec3(.28,.018,.004),vec3(1.0,.63,.060),clamp(lum*1.38+hotBand*.14+vein*.10,0.0,1.0));
    hot += vec3(.26,.062,.003)*smoothstep(.35,.88,lum);
    hot += vec3(.16,.032,.001)*hotBand*boil;
    if (materialFlow > .5) {
      /* Vertical falls: a dark cooling edge and fast internal bright veins
         make the sheet read as thick molten material even in a still frame. */
      float edge=min(clamp(uv.x,0.0,1.0),1.0-clamp(uv.x,0.0,1.0));
      float core=smoothstep(.035,.24,edge);
      hot *= mix(vec3(.54,.38,.30),vec3(1.08,1.01,.86),core);
      hot += vec3(.28,.070,.002)*vein*core*(.35+.65*pulse);
      float emission=1.19+.24*vein+.13*pulse;
      return vec4(clamp(hot*broad*emission*mix(vec3(1.0),tint.rgb,.14),vec3(0.0),vec3(1.0)),a);
    }
    float emission=1.07+.28*boil;
    return vec4(clamp(hot*broad*emission*mix(vec3(1.0),tint.rgb,.18),vec3(0.0),vec3(1.0)),a);
  }

  /* Summit surface separation. Procedural Mt. Battle geometry previously sent
     rock, deck and trim through one neutral opaque grade, flattening the whole
     venue even though its architecture was present. These modes use the same
     source textures and normals, but give natural geology broken strata and
     manufactured steel a cleaner directional response. */
  if (sceneProfile > 1.5 && sceneProfile < 2.5) {
    if (materialMode > .10 && materialMode < .20) {
      float strata=.5+.5*sin(worldPos.y*.29 + worldPos.x*.021 - worldPos.z*.017
        + sin(worldPos.x*.013 + worldPos.z*.019)*1.65);
      // Sparse warped fracture bands. Do not multiply independent X/Z waves:
      // that cross-hatches into a visible grid over the distant mountains.
      float rockWarp=sin(worldPos.z*.029+worldPos.y*.013)*1.35
        + sin(worldPos.x*.017-worldPos.y*.011)*.85;
      float fractureA=abs(sin(worldPos.x*.049+worldPos.z*.031+worldPos.y*.014+rockWarp));
      float fractureB=abs(sin(worldPos.x*.023-worldPos.z*.057+worldPos.y*.008-rockWarp*.47));
      float fracture=max(smoothstep(.935,.995,fractureA),
        smoothstep(.965,.999,fractureB)*.58);
      float rockKey=clamp(.5+.5*dot(n,normalize(vec3(.64,.42,-.55))),0.0,1.0);
      float lowRock=1.0-smoothstep(8.0,52.0,worldPos.y);
      /* Platform 100 reference geology is dark, hard and sharply separated.
         The old mauve grade inflated every procedural lobe into a soft cloudy
         mass. Pull the midrange down, keep warm lava bounce only on low faces,
         and let flat triangle normals carry the cliff facets. */
      float sunsetRock=clamp(.5+.5*dot(n,normalize(vec3(.72,.18,-.42))),0.0,1.0);
      float faceBreak=.5+.5*sin(worldPos.x*.109+worldPos.z*.077-worldPos.y*.043);
      // Dark neutral basalt in shade; warm late-day light lives on exposed planes
      // instead of tinting the whole formation brown. Extra contrast keeps each
      // triangulated cliff face legible at wide battle-camera distance.
      shaded *= vec3(.70,.69,.70)*(.76+.25*rockKey+.055*strata+.035*faceBreak);
      shaded=clamp((shaded-vec3(.34))*1.31+vec3(.34),vec3(0.0),vec3(1.0));
      shaded -= vec3(.064,.058,.062)*fracture*(.42+.58*(1.0-rockKey));
      shaded += vec3(.070,.026,.008)*sunsetRock*(.30+.70*rockKey);
      shaded += vec3(.035,.010,.003)*lowRock*(.20+.80*rockKey);
      shaded += vec3(.004,.009,.018)*(1.0-sunsetRock)*(1.0-lowRock);
    } else if (materialMode > .20 && materialMode < .30) {
      float steelKey=clamp(.5+.5*dot(n,normalize(vec3(-.48,.77,.42))),0.0,1.0);
      float brushed=.5+.5*sin(worldPos.x*.39-worldPos.z*.31+worldPos.y*.12);
      float panelSeam=smoothstep(.91,.995,abs(sin(worldPos.x*.245)*sin(worldPos.z*.245)));
      shaded *= .925+.105*steelKey+.025*brushed;
      shaded += vec3(.010,.014,.021)*steelKey;
      shaded -= vec3(.019,.016,.014)*panelSeam;
    }
  }

  vec3 viewDir = normalize(cameraEye - worldPos);
  vec3 halfDir = normalize(lightDir + viewDir);
  float specPower = max(4.0, materialShininess * 0.28);
  float spec = pow(max(abs(dot(n,halfDir)),0.0),specPower) * 0.075;
  if (materialMode < 3.5) shaded += materialSpecular * spec;

  if (materialMode > 0.5 && materialMode < 1.5) {
    /* Water gets its own saturated treatment instead of sharing the pale scene
       fog. It remains transparent, but now reads as a deliberate blue layer
       instead of a white duplicate of the wall behind it. */
    /* Cross-wave normal perturbation gives the water a changing highlight
       rather than merely scrolling its diffuse texture. */
    float wx = cos(worldPos.x*0.29 + sceneTime*1.05)*0.10 + cos(worldPos.z*0.18-sceneTime*.73)*0.055;
    float wz = sin(worldPos.z*0.31 - sceneTime*.92)*0.10 + sin(worldPos.x*0.16+sceneTime*.61)*0.050;
    vec3 waterN = normalize(n + vec3(wx,0.0,wz));
    float fresnel = pow(1.0 - clamp(abs(dot(waterN,viewDir)),0.0,1.0),2.15);
    float ripple = 0.5 + 0.5*sin(worldPos.x*0.23 + worldPos.z*0.17 + sceneTime*1.18);
    float sparkle = smoothstep(0.78,0.995,0.5+0.5*sin(worldPos.x*1.31 + worldPos.z*1.77 + sceneTime*2.30));
    float glint = pow(max(dot(waterN,halfDir),0.0),18.0) * (0.17 + 0.22*fresnel);
    /* Source Water Colosseum is steel/cool-gray first and blue second. Keep
       the water reflective without turning the entire venue cyan-white. */
    vec3 waterTint = mix(vec3(0.040,0.145,0.195),vec3(0.115,0.315,0.375),0.26+0.28*fresnel);
    float flowBright = materialFlow > 0.5 ? 1.035 : 0.985;
    shaded = mix(shaded * vec3(0.60,0.76,0.82),waterTint,0.39+0.09*ripple) * flowBright;
    shaded += vec3(0.30,0.47,0.52)*(glint + sparkle*0.022*fresnel);
    a *= materialFlow > 0.5 ? 0.72 : 0.66;
  } else {
    float dNear = length(worldPos - cameraEye);
    float detail = 1.0 - smoothstep(44.0,78.0,dNear);
    vec3 crisp = clamp((shaded - vec3(0.50))*1.09 + vec3(0.50),0.0,1.0);
    shaded = mix(shaded,crisp,detail*0.60);

    if (materialMode < 0.5) {
      float outer = sceneProfile < .5
        ? smoothstep(34.0,92.0,arenaRadius)
        : smoothstep(sceneRadiusWorld*.22,sceneRadiusWorld*.70,arenaRadius);
      float venueSweep = 0.5 + 0.5*sin(sceneTime*0.19 + worldPos.x*0.024 - worldPos.z*0.018);
      if (sceneProfile < .5) {
        /* Water Colosseum keeps its restrained cool water bounce. */
        float waterBounce = 0.5 + 0.5*sin(sceneTime*0.29 + worldPos.z*0.027 + worldPos.y*0.012);
        shaded *= 0.994 + outer*(0.006 + 0.010*venueSweep);
        shaded += vec3(0.004,0.010,0.015) * outer * (0.30 + 0.70*waterBounce);
      } else if (sceneProfile > 1.5 && sceneProfile < 2.5) {
        /* Source-backed Platform 100: do not add authored sunset/lava tint to
           ordinary D2 surfaces. Exact GX textures + source material colors own
           the rock, bridge and deck; only the common neutral light remains. */
        shaded *= 1.0;
      } else if (sceneProfile > 2.5 && sceneProfile < 3.5) {
        /* Orre Colosseum: ancient sun-baked stone. Warm low-angle desert key
           reveals masonry relief while a cool blue sky fill prevents the bowl
           from collapsing into monochrome orange. */
        float desertFace=clamp(.5+.5*dot(n,normalize(vec3(-.746,.431,.517))),0.0,1.0);
        float ageBreak=.5+.5*sin(worldPos.x*.071+worldPos.z*.053+worldPos.y*.029);
        shaded *= .985 + .018*desertFace;
        shaded += vec3(.042,.019,.006)*desertFace*(.42+.58*outer);
        shaded += vec3(.004,.009,.019)*(1.0-desertFace);
        shaded *= .985 + ageBreak*.018;
      } else if (sceneProfile > 3.5) {
        /* Realgam: neutral-cool industrial key.  Keep the architecture darker
           than 0.0.59 so recesses, panel seams and cyan technology survive
           instead of bleaching into one white mass. */
        float metalFace=clamp(.5+.5*dot(n,normalize(vec3(-.42,.78,.46))),0.0,1.0);
        float machineBreak=.5+.5*sin(worldPos.y*.103+worldPos.x*.031-worldPos.z*.027);
        shaded *= .950 + .060*metalFace + .022*machineBreak;
        shaded += vec3(.002,.010,.016)*metalFace;
        shaded += vec3(.001,.006,.010)*(1.0-metalFace);
      } else {
        /* Generic Orre wild field: filtered warm sunlight through a
           green canopy, with cool open-sky fill. Keep the source rock honest
           while letting grass and foliage read lush instead of desert-brown. */
        float forestFace=clamp(.5+.5*dot(n,normalize(vec3(.48,.74,-.34))),0.0,1.0);
        shaded *= .996 + outer*.007*venueSweep;
        shaded += vec3(.018,.028,.006)*forestFace*(.34+.66*outer);
        shaded += vec3(.004,.012,.018)*(1.0-forestFace);
      }
    }
  }

  /* Continuous background fidelity pass. These are profile-specific material
     refinements applied to the established geometry so every build improves
     arenas beyond the one currently under active testing. */
  if (sceneProfile > .5 && sceneProfile < 1.5) {
    if (materialMode > 3.10 && materialMode < 3.40) {
      float forestNoise=.5+.5*sin(worldPos.x*.19+worldPos.z*.13+worldPos.y*.071);
      float sunLeaf=clamp(.5+.5*dot(n,normalize(vec3(-.36,.83,.42))),0.0,1.0);
      if (materialFlow > .75) {
        shaded *= vec3(.88+.10*forestNoise,1.00+.045*sunLeaf,.86+.035*forestNoise);
      } else {
        shaded *= vec3(.82+.12*forestNoise,.96+.09*sunLeaf,.80+.06*forestNoise);
        shaded += vec3(.008,.020,.004)*sunLeaf;
      }
    } else if (materialMode < .5) {
      float meadowBreak=.5+.5*sin(worldPos.x*.073+sin(worldPos.z*.021)*2.1)*cos(worldPos.z*.061-worldPos.x*.013);
      shaded *= vec3(.97+.025*meadowBreak,1.0,.965+.018*meadowBreak);
    }
  } else if (sceneProfile < .5 && materialMode < .5) {
    float wetStone=1.0-smoothstep(18.0,70.0,abs(worldPos.y));
    float coolFace=clamp(.5+.5*dot(n,normalize(vec3(-.20,.72,.66))),0.0,1.0);
    shaded += vec3(.002,.006,.009)*wetStone*coolFace;
    /* Venue-wide source grade: darker mineral/steel undertones, restrained
       saturation and protected highlights. This only affects Water profile. */
    float waterLuma=dot(shaded,vec3(.299,.587,.114));
    vec3 sourceGray=vec3(waterLuma*.88,waterLuma*.92,waterLuma*.94);
    shaded=mix(shaded,sourceGray,.27);
    shaded*=.895;
  } else if (sceneProfile > 1.5 && sceneProfile < 2.5 && materialMode < .5) {
    /* Source-backed D2 opaque materials stay ungraded. */
    shaded *= 1.0;
  }

  /* 0.0.49 all-arena fidelity sweep.  These are low-amplitude, world-space
     material breaks so every venue gains surface depth even when another arena
     is the current test target.  No extra floating geometry is introduced. */
  if (materialMode < .5) {
    float macroA=.5+.5*sin(worldPos.x*.047+worldPos.z*.061+worldPos.y*.019);
    float macroB=.5+.5*sin(worldPos.x*.113-worldPos.z*.037+worldPos.y*.071);
    float micro=clamp(macroA*.62+macroB*.38,0.0,1.0);
    if (sceneProfile < .5) {
      /* Water: wet mineral variation and faint cool reflected light on stone. */
      float lowStone=1.0-smoothstep(22.0,74.0,abs(worldPos.y));
      float wetFace=clamp(.5+.5*dot(n,normalize(vec3(-.24,.78,.58))),0.0,1.0);
      shaded *= .982+.025*micro;
      shaded += vec3(.004,.010,.016)*lowStone*wetFace*(.35+.65*micro);
    } else if (sceneProfile > .5 && sceneProfile < 1.5) {
      /* Wildlands: irregular meadow light and cool canopy shadow instead of a
         single green exposure across the entire field. */
      float canopy=.5+.5*sin(worldPos.x*.029+sin(worldPos.z*.018)*2.4);
      shaded *= .975+.032*micro;
      shaded += vec3(.007,.014,.003)*canopy*(.35+.65*hemi);
      shaded -= vec3(.004,.002,0.0)*(1.0-canopy);
    } else if (sceneProfile > 1.5 && sceneProfile < 2.5) {
      /* No procedural ash/tint pass on source D2 materials. */
      shaded *= 1.0;
    } else if (sceneProfile > 2.5 && sceneProfile < 3.5) {
      /* Orre Colosseum: layered sandstone tone, age-darkened seams, and sun
         bleaching.  This keeps the ancient bowl from reading as one flat tan. */
      float strata=.5+.5*sin(worldPos.y*.31+worldPos.x*.021-worldPos.z*.017);
      float sunAge=clamp(.5+.5*dot(n,normalize(vec3(-.746,.431,.517))),0.0,1.0);
      shaded *= .958+.040*micro+.018*strata;
      shaded += vec3(.020,.009,.002)*sunAge*(.35+.65*strata);
      shaded -= vec3(.009,.006,.004)*(1.0-sunAge)*(1.0-micro);
    }
  }

  /* 0.0.49 continuity pass: keep improving every venue while Orre is the
     active test. This is intentionally low amplitude and world-space only. */
  if (materialMode < .5) {
    float upFace=clamp(dot(n,vec3(0.0,1.0,0.0)),0.0,1.0);
    if (sceneProfile < .5) {
      // Water: cool reflected sky on upward wet stone, darker protected walls.
      shaded += vec3(.003,.008,.013)*upFace*(.35+.65*hemi);
      shaded *= .987+.013*upFace;
    } else if (sceneProfile > .5 && sceneProfile < 1.5) {
      // Wildlands: mottled canopy light without changing the authored geometry.
      float leafShadow=.5+.5*sin(worldPos.x*.035+worldPos.z*.047+sin(worldPos.z*.013)*1.9);
      shaded *= .982+.022*leafShadow;
      shaded += vec3(.004,.009,.002)*upFace*leafShadow;
    } else if (sceneProfile > 1.5 && sceneProfile < 2.5) {
      // Source D2 texture/material state owns Mt. Battle's local colour.
      shaded *= 1.0;
    } else if (sceneProfile > 2.5 && sceneProfile < 3.5) {
      // Orre: one physically consistent late-day key from the world-space sun,
      // warm desert bounce below, blue fill above. This same vector is used by
      // the visible sun projection in drawBackdrop.
      vec3 orreSun=normalize(vec3(-.746,.431,.517));
      float key=clamp(dot(n,orreSun)*.5+.5,0.0,1.0);
      float lowOrre=1.0-smoothstep(18.0,70.0,worldPos.y);
      shaded *= .970+.038*key;
      shaded += vec3(.022,.009,.0025)*key;
      shaded += vec3(.010,.004,.0015)*lowOrre*(1.0-key);
      shaded += vec3(.002,.005,.011)*upFace*(1.0-key);
    } else if (sceneProfile > 3.5) {
      // Realgam: cool architectural key, cyan technology bounce and clean
      // high-metal fill. Keep it brighter than the crowd cavities.
      vec3 keyDir=normalize(vec3(-.42,.78,.46));
      float key=clamp(dot(n,keyDir)*.5+.5,0.0,1.0);
      float tech=.5+.5*sin(worldPos.y*.105+worldPos.x*.014-worldPos.z*.017);
      shaded *= .965+.046*key;
      shaded += vec3(.003,.012,.018)*upFace;
      shaded += vec3(.002,.010,.016)*tech*(1.0-key);
    }
  }

  /* 0.0.51 whole-suite finishing grade.  The reconstructed venues mix source
     textures from different lighting conditions; a restrained profile grade
     pulls them back into one photographed scene without erasing material detail. */
  float luma=dot(shaded,vec3(.299,.587,.114));
  if (sceneProfile < .5) {
    vec3 neutral=mix(vec3(luma),shaded,.93);
    shaded=mix(neutral,neutral*vec3(.96,1.01,1.055),.34);
  } else if (sceneProfile > .5 && sceneProfile < 1.5) {
    vec3 neutral=mix(vec3(luma),shaded,.84);
    shaded=neutral*vec3(.99,1.00,.97);
    float canopyShade=1.0-smoothstep(20.0,100.0,length(worldPos.xz));
    shaded += vec3(.006,.008,.004)*canopyShade;
  } else if (sceneProfile > 1.5 && sceneProfile < 2.5) {
    vec3 neutral=mix(vec3(luma),shaded,.90);
    shaded=neutral*vec3(1.035,.985,.955);
    shaded += vec3(.008,.003,.001)*(1.0-hemi);
  } else if (sceneProfile > 2.5 && sceneProfile < 3.5) {
    vec3 neutral=mix(vec3(luma),shaded,.91);
    shaded=neutral*vec3(1.035,.992,.955);
    shaded += vec3(.006,.0025,0.0)*(1.0-hemi);
  } else if (sceneProfile > 3.5) {
    vec3 neutral=mix(vec3(luma),shaded,.965);
    shaded=neutral*vec3(.96,.995,1.025);
    shaded += vec3(.002,.008,.014)*(1.0-hemi);
    // Preserve dark machine cavities while letting the silver shell live in a
    // brighter midrange like the source Realgam battle floor/towers.
    shaded=clamp((shaded-vec3(.44))*1.075+vec3(.47),vec3(0.0),vec3(1.0));
  }
  shaded=clamp((shaded-vec3(.5))*1.025+vec3(.5),vec3(0.0),vec3(1.0));
  /* Source-arena exposure trim. The authentic HSD materials were being
     lit by both their authored diffuse/ambient values and CBE's venue grade,
     pushing pale Water/Orre masonry into clipped white. Preserve contrast while
     bringing the midrange back toward the reference footage. */
  if (sceneProfile < .5) {
    // Phenac is pale limestone, not emissive white. Roll the source highlights
    // back into the photographed midrange while preserving grout and wall shade.
    shaded *= .78;
    shaded=clamp((shaded-vec3(.46))*.94+vec3(.43),vec3(0.0),vec3(.90));
  } else if (sceneProfile > 2.5 && sceneProfile < 3.5) shaded *= .915;
  else if (sceneProfile > 3.5) shaded *= .930;

  /* Only the very outer shell blends into atmosphere. The old blue fog began
     inside the usable bowl and washed the whole arena into a translucent-looking
     haze. */
  float d = length(worldPos - cameraEye);
  bool summitProfile = sceneProfile > 1.5 && sceneProfile < 2.5;
  bool orreProfile = sceneProfile > 2.5 && sceneProfile < 3.5;
  bool realgamProfile = sceneProfile > 3.5;
  /* Keep Mt. Battle's deck, pylons and first crater wall crisp. The former
     175..275 range put a grey veil over architecture that was still close
     enough to read as part of the arena; haze now begins beyond that shell. */
  float fogNear = summitProfile ? 318.0 : (orreProfile ? 168.0 : (realgamProfile ? 205.0 : 150.0));
  float fogFar  = summitProfile ? 520.0 : (orreProfile ? 292.0 : (realgamProfile ? 330.0 : 225.0));
  float distanceFog = smoothstep(fogNear,fogFar,d);
  float edgeFog = sceneProfile < .5
    ? smoothstep(98.0,106.0,arenaRadius)
    : smoothstep(sceneRadiusWorld*.82,sceneRadiusWorld*.98,arenaRadius);
  float fog = max(distanceFog,edgeFog);
  vec3 fogColor = summitProfile ? vec3(.50,.52,.54)
    : (orreProfile ? vec3(.63,.46,.31)
    : (realgamProfile ? vec3(.64,.47,.25)
    : (sceneProfile > .5 ? vec3(.52,.64,.64) : vec3(.10,.19,.27))));
  if (materialMode > 3.5 && materialMode < 4.5)
    shaded = mix(shaded,fogColor,fog*.10);
  else if (!(materialMode > .5 && materialMode < 1.5))
    shaded = mix(shaded,fogColor,fog*(summitProfile ? .055 : (orreProfile ? .27 : (realgamProfile ? .22 : (sceneProfile > .5 ? .36 : .42)))));

  if (materialMode > 2.5) a = 1.0;
  return vec4(clamp(shaded,vec3(0.0),vec3(1.0)),clamp(a,0.0,1.0));
}
]]

local scene, shader, white
-- Cache of which uniforms the currently compiled arena shader actually
-- declares. Invalidated whenever `shader` is rebuilt or released.
local uniformCache,uniformCacheShader=nil,nil
-- Baked static sky. See ensureBackdrop().
local backdropCanvas,backdropKey=nil,nil
local backdropBakes=0
local canvas, cw, ch
local depthCanvas, depthMode, depthActive
local errorText
local renderErrors={}
-- Keep a very small LRU of fully materialized arena scenes on mobile. The old
-- single-scene policy made AUTO alternate between a resident trainer arena and
-- a cold wild arena, so one of those two battle types always paid Lua parsing,
-- texture decode and GPU upload after the transition. Two resident scenes are
-- enough to cover AUTO without recreating the high-memory "keep everything"
-- experiment from 1.7.2.
local residentScenes={}
local residentUse={}
local residentSerial=0
local RESIDENT_LIMIT=ARENA_ANDROID and 2 or 3
local activeDef=nil
local STAGE_SCALE = 0.25
local STAGE_YAW = 0
local activeArenaId="water"
-- The source map contains much more world geometry than a battle camera needs.
-- 0.0.8 uses the FULL decoded Water Colosseum cache again, but keeps only the
-- coherent arena shell. The key difference from 0.0.7 is that the giant authored
-- stone-wall mesh is allowed through intact; remote Phenac geometry is still
-- rejected by radial/span checks and GameCube no-depth effect sheets are dropped.
local BATTLE_SCENE_RADIUS_RAW = 430
-- IMPORTANT: the authored outer wall is one large HSD mesh (roughly 802 raw
-- units across). 0.0.7 accidentally rejected that WHOLE mesh as "oversize",
-- which is why the remaining balconies/waterfalls looked like floating islands.
-- Keep that coherent wall, while the truly remote Phenac map pieces still fail
-- the radial test or exceed this much larger safety bound.
local BATTLE_MAX_GROUP_SPAN_RAW = 920
local BATTLE_VERTEX_RADIUS_RAW = 415

-- StadiumBattleFX's models are authored for its own much smaller default
-- arenas.  We shrink the complete actor world before projection instead of
-- editing StadiumBattleFX or any individual model.  Raw actor anchors are
-- inversely compensated so their *visible* positions stay on the Colosseum
-- battle disc.
local DEFAULT_FIGURE_SCALE = 0.38
local figureScale = DEFAULT_FIGURE_SCALE
local VIS_PLAYER = {0, 14.5}
local VIS_ENEMY  = {0,-14.5}
local sceneTime = 0

local function clamp(v,a,b) if v<a then return a elseif v>b then return b else return v end end
local function log(ctx,level,msg,...)
  local l=ctx and ctx.services and ctx.services.log
  if l and type(l[level])=="function" then pcall(l[level],l,"[ColosseumEnv] "..msg,...) end
end
local function readLua(path)
  local src,readErr=GeneratedAssets.read(path); if not src then return nil,readErr or ("missing "..path) end
  local chunk,err=load(src,"@"..tostring(mod.path or mod.id).."/"..path)
  if not chunk then return nil,err end
  local ok,value=pcall(chunk); if not ok then return nil,value end
  return value
end
local function alphaInfo(bytes)
  local hasZero, hasFraction = false, false
  for i=4,#bytes,4 do
    local a=bytes:byte(i)
    if a==0 then hasZero=true elseif a and a<255 then hasFraction=true; break end
  end
  return hasZero and not hasFraction, hasFraction
end
local function texture(spec,textures)
  if not spec then
    if white then return {image=white,binaryAlpha=false} end
    local data=love.image.newImageData(1,1); data:setPixel(0,0,1,1,1,1)
    white=love.graphics.newImage(data); return {image=white,binaryAlpha=false}
  end
  local prior=textures[spec.path]; if prior then return prior end
  local bytes,readErr=GeneratedAssets.read(spec.path); if not bytes then return nil,readErr or ("missing "..spec.path) end
  local binaryAlpha, fractionalAlpha = alphaInfo(bytes)
  local ok,data=pcall(love.image.newImageData,spec.w,spec.h,"rgba8",bytes)
  if not ok then return nil,data end
  local ok2,img=pcall(love.graphics.newImage,data)
  if not ok2 then return nil,img end
  local path=tostring(spec.path or "")
  local crowd=path:find("tex_0d5b60_",1,true) or path:find("tex_0ddb60_",1,true) or path:find("cache/stages/orre/crowd_",1,true)
    or path:find("cache/stages/orre/source/tex_10f240_",1,true) or path:find("cache/stages/orre/source/tex_111240_",1,true)
    or path:find("cache/stages/realgam/source/tex_0bed60_",1,true) or path:find("cache/stages/realgam/source/tex_0c0d60_",1,true)
  local d2stage=path:find("cache/stages/d2_crater/textures/",1,true)
  local wildRepeat=path:find("cache/stages/wildlands/ground_",1,true) or path:find("cache/stages/wildlands/bark_",1,true)
  local orreRepeat=path:find("cache/stages/orre/",1,true)
  local realgamRepeat=path:find("cache/stages/realgam/",1,true)
  if img.setFilter then
    -- Crowd cards are small authored billboard sprites. Preserve their pixel
    -- silhouettes when magnified, but keep linear minification/anisotropy so
    -- the full audience does not shimmer when the camera moves.
    local minf,magf="linear",crowd and "nearest" or "linear"
    local okFilter=pcall(img.setFilter,img,minf,magf,16)
    if not okFilter then pcall(img.setFilter,img,minf,magf) end
  end
  if img.setWrap then
    local function gxWrap(v)
      v=tonumber(v)
      if v==1 then return "repeat" end
      if v==2 then return "mirroredrepeat" end
      return "clamp"
    end
    -- Source HSD arenas retain the exact GX WrapS/WrapT state from HSD_TOBJ.
    -- Only authored/procedural CBE textures fall back to the older heuristics.
    if spec.wrapS~=nil or spec.wrapT~=nil then
      pcall(img.setWrap,img,gxWrap(spec.wrapS),gxWrap(spec.wrapT))
    elseif path:find("cache/stages/d2_crater/textures/tex_0ce920_",1,true)
        or path:find("cache/stages/d2_crater/textures/tex_061ec0_",1,true) then
      -- Procedural summit rock is intentionally sampled as mirrored repeat.
      -- This keeps every atlas boundary continuous even when a huge ridge
      -- spans several UV tiles; normal repeat exposed the procedural texture's
      -- opposite edges as a regular square seam/grid at battle distance.
      pcall(img.setWrap,img,"mirroredrepeat","mirroredrepeat")
    elseif crowd or d2stage or wildRepeat or orreRepeat or realgamRepeat or path:find("tex_0cdb60_",1,true) or path:find("tex_081b60_",1,true) then
      pcall(img.setWrap,img,"repeat","repeat")
    else
      pcall(img.setWrap,img,"clamp","clamp")
    end
  end
  local entry={image=img,binaryAlpha=binaryAlpha,fractionalAlpha=fractionalAlpha}
  textures[spec.path]=entry; return entry
end
local function groupStats(vertices)
  local x,y,z,n=0,0,0,0
  local minx,maxx,miny,maxy,minz,maxz=math.huge,-math.huge,math.huge,-math.huge,math.huge,-math.huge
  for _,v in ipairs(vertices or {}) do
    local vx,vy,vz=tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0
    x=x+vx;y=y+vy;z=z+vz;n=n+1
    minx=math.min(minx,vx);maxx=math.max(maxx,vx);miny=math.min(miny,vy);maxy=math.max(maxy,vy);minz=math.min(minz,vz);maxz=math.max(maxz,vz)
  end
  if n==0 then return {0,0,0},0,{0,0,0} end
  local extent={maxx-minx,maxy-miny,maxz-minz}
  return {x/n,y/n,z/n},math.max(extent[1],extent[2],extent[3]),extent
end
local function crowdCardPhases(vertices)
  local n=#(vertices or {});if n<3 then return nil end
  local parent={};for i=1,n do parent[i]=i end
  local function find(a)
    while parent[a]~=a do parent[a]=parent[parent[a]];a=parent[a] end
    return a
  end
  local function union(a,b)a,b=find(a),find(b);if a~=b then parent[b]=a end end
  local first={}
  local function key(v)
    return ("%.3f|%.3f|%.3f"):format(tonumber(v[1]) or 0,tonumber(v[2]) or 0,tonumber(v[3]) or 0)
  end
  for i,v in ipairs(vertices or {}) do local k=key(v);if first[k] then union(i,first[k]) else first[k]=i end end
  for i=1,n,3 do if vertices[i+2] then union(i,i+1);union(i,i+2) end end
  local comps={}
  for i,v in ipairs(vertices or {}) do
    local r=find(i);local c=comps[r]
    if not c then c={sx=0,sy=0,sz=0,n=0,idx={}};comps[r]=c end
    c.sx=c.sx+(tonumber(v[1]) or 0);c.sy=c.sy+(tonumber(v[2]) or 0);c.sz=c.sz+(tonumber(v[3]) or 0);c.n=c.n+1;c.idx[#c.idx+1]=i
  end
  local phase={}
  for _,c in pairs(comps) do
    local cx,cy,cz=c.sx/math.max(1,c.n),c.sy/math.max(1,c.n),c.sz/math.max(1,c.n)
    -- Deterministic per-card/per-cluster phase. No random state means the
    -- audience remains stable across frames and battle restarts.
    local h=math.sin(cx*.173+cy*.311+cz*.137)*43758.5453
    local q=h-math.floor(h)
    for _,i in ipairs(c.idx) do phase[i]=q end
  end
  return phase
end

local function withNormals(vertices,mode)
  local out={}
  local v=vertices or {}
  local crowdPhase=(mode==4) and crowdCardPhases(v) or nil
  for i=1,#v,3 do
    local a,b,c=v[i],v[i+1],v[i+2]
    if a and b and c then
      local ar=math.sqrt((a[1] or 0)^2+(a[3] or 0)^2)
      local br=math.sqrt((b[1] or 0)^2+(b[3] or 0)^2)
      local cr=math.sqrt((c[1] or 0)^2+(c[3] or 0)^2)
      if math.min(ar,br,cr)<=BATTLE_VERTEX_RADIUS_RAW then
        local abx,aby,abz=(b[1] or 0)-(a[1] or 0),(b[2] or 0)-(a[2] or 0),(b[3] or 0)-(a[3] or 0)
        local acx,acy,acz=(c[1] or 0)-(a[1] or 0),(c[2] or 0)-(a[2] or 0),(c[3] or 0)-(a[3] or 0)
        local nx=aby*acz-abz*acy
        local ny=abz*acx-abx*acz
        local nz=abx*acy-aby*acx
        local len=math.sqrt(nx*nx+ny*ny+nz*nz)
        if len<0.000001 then nx,ny,nz=0,1,0 else nx,ny,nz=nx/len,ny/len,nz/len end
        for j,src in ipairs({a,b,c}) do
          -- Extract/HSD emits 8-field rows: XYZ, UV, source normal XYZ.
          -- Legacy/procedural recipes emit 9-field rows: XYZ, UV, RGBA.
          local r,g,bv,av=1,1,1,1
          local vnx,vny,vnz=nx,ny,nz
          if #src>=9 then
            r,g,bv,av=src[6] or 1,src[7] or 1,src[8] or 1,src[9] or 1
          elseif #src==8 then
            vnx,vny,vnz=src[6] or nx,src[7] or ny,src[8] or nz
            local nl=math.sqrt(vnx*vnx+vny*vny+vnz*vnz)
            if nl>0.000001 then vnx,vny,vnz=vnx/nl,vny/nl,vnz/nl else vnx,vny,vnz=nx,ny,nz end
          end
          if crowdPhase then
            local srcIndex=i+j-1
            local ph=crowdPhase[srcIndex] or 0.5
            -- Encode a stable per-card animation phase in a very small tint
            -- variation. The pixel shader decodes it, while the visible color
            -- shift stays subtle enough to preserve the source crowd atlas.
            r=.80+.20*ph;g=.965+.035*((ph*.61803398875)%1);bv=.975+.025*((ph*.38196601125)%1);av=1
          end
          out[#out+1]={src[1] or 0,src[2] or 0,src[3] or 0,src[4] or 0,src[5] or 0,r,g,bv,av,vnx,vny,vnz}
        end
      end
    end
  end
  return out
end

local function materialDetail(g)
  local path=g and g.texture and tostring(g.texture.path or "") or ""
  -- These are the extracted architectural atlases: stone, floor, rails and
  -- banner-on-stone sheets. Crowd sprites, water and effects stay untouched.
  if path:find("tex_05c560_",1,true) or path:find("tex_05db60_",1,true) or
     path:find("tex_08bb60_",1,true) or path:find("tex_0abb60_",1,true) or
     path:find("cache/stages/wildlands/ground_",1,true) or path:find("cache/stages/wildlands/bark_",1,true) or
     path:find("cache/stages/orre/",1,true) or path:find("cache/stages/realgam/",1,true) then
    return 1
  end
  return 0
end
local function materialMode(g,tex)
  local path=g and g.texture and tostring(g.texture.path or "") or ""
  -- The decoded D2 truss atlas is 81% binary transparency. Treat it as real
  -- alpha-tested GameCube structure so the metal towers read as open lattice,
  -- not as the opaque grey slabs seen in the previous Mt. Battle build.
  if tex and tex.binaryAlpha and path:find("cache/stages/d2_crater/textures/tex_0fd8e0_",1,true) then
    return 3
  end
  if tex and tex.binaryAlpha and (path:find("cache/stages/wildlands/leaf_cluster_",1,true) or path:find("cache/stages/wildlands/grass_tuft_",1,true)) then
    return 3.25 -- authored wildland foliage/grass cutout cards + restrained wind
  end
  if path:find("cache/stages/d2_crater/textures/tex_0ca920_",1,true)
      or path:find("cache/stages/d2_crater/textures/tex_0be120_",1,true)
      or path:find("cache/stages/d2_crater/textures/tex_0ea920_",1,true) then
    return 5 -- authentic D2 crater lava / lava-fall material
  end
  -- D2 rock/deck/bridge surfaces now come from the exact HSD scene with their
  -- source diffuse/ambient/material state. Do not re-grade those atlases with
  -- the old procedural "basalt" and "steel" looks; normal mode lets the source
  -- textures, UVs and material colors define the venue. Lava/cutout helpers
  -- below still get portable runtime equivalents for GameCube-only TEV effects.
  if path:find("cache/stages/d2_crater/textures/tex_0ce920_",1,true)
      or path:find("cache/stages/d2_crater/textures/tex_061ec0_",1,true)
      or path:find("cache/stages/d2_crater/textures/tex_0f4120_",1,true)
      or path:find("cache/stages/d2_crater/textures/tex_07cec0_",1,true) then
    return 0
  end
  if path:find("tex_0cbb60_",1,true) then return 2 end -- waterfall glint
  if path:find("tex_0cdb60_",1,true) or path:find("tex_081b60_",1,true) then return 1 end -- water
  local sourceCrowd =
    path:find("cache/stages/orre/source/tex_10f240_",1,true) or path:find("cache/stages/orre/source/tex_111240_",1,true)
    or path:find("cache/stages/realgam/source/tex_0bed60_",1,true) or path:find("cache/stages/realgam/source/tex_0c0d60_",1,true)
  if tex and tex.binaryAlpha and (path:find("tex_0d5b60_",1,true) or path:find("tex_0ddb60_",1,true)
      or path:find("cache/stages/orre/crowd_",1,true) or sourceCrowd) then
    return 4 -- source crowd atlas: exact placement + alpha-tested depth
  end
  if tex and tex.binaryAlpha and (path:find("tex_05c560_",1,true) or path:find("/source/",1,true)) then
    return 3 -- hard alpha-test source rails/cards/effects
  end
  return 0
end
local function sourcePath(g)
  return g and g.texture and tostring(g.texture.path or "") or ""
end
local function dropGhostLayer(g)
  local path=sourcePath(g)
  -- These textureless NO_ZUPDATE sheets are paired GameCube effect planes.
  -- Without the original TEV combiner they become literal translucent copies
  -- of nearby surfaces, i.e. the ghosting visible in the v5 recording.
  if not g.texture and g.xlu and g.noz then return true end
  -- One giant translucent 512x512 source sheet sits across the high bowl. It is
  -- a compositing layer, not useful battle geometry in our flattened renderer.
  if path:find("tex_05db60_",1,true) and g.xlu and g.noz then return true end
  -- T1's 055ec0 group is the giant authored sky card. We already render the
  -- exact source texture as the arena backdrop; retaining the 4k-unit world
  -- card after lifting Orre's distance limits would double the sky and can pass
  -- through the camera. Keep the texture, omit only that world-space carrier.
  if path:find("cache/stages/orre/source/tex_055ec0_",1,true) then return true end
  -- D4's 0d4560 sheet is a TEV/shadow-composite silhouette. In CBE's
  -- flattened material path it becomes a huge translucent floating decal, so
  -- omit that effect plane while preserving the surrounding source structure.
  if path:find("cache/stages/realgam/source/tex_0d4560_",1,true) and g.xlu and g.noz then return true end
  return false
end
local function releaseArenaScene(s)
  if type(s)~="table" then return end
  local seen={}
  local function release(obj)
    if not obj or seen[obj] then return end
    seen[obj]=true
    pcall(function() if type(obj.release)=="function" then obj:release() end end)
  end
  for _,bucket in ipairs({s.opaque,s.cutout,s.crowd,s.translucent,s.additive}) do
    for _,g in ipairs(bucket or {}) do if type(g)=="table" then release(g.mesh) end end
  end
  for _,tex in pairs(s.textures or {}) do if type(tex)=="table" then release(tex.image) end end
end
local function residentCount()
  local n=0;for _ in pairs(residentScenes) do n=n+1 end;return n
end
local function touchResident(id,s)
  if not (id and s) then return s end
  residentSerial=residentSerial+1
  residentScenes[id]=s;residentUse[id]=residentSerial
  while residentCount()>RESIDENT_LIMIT do
    local victim,vstamp
    for rid,stamp in pairs(residentUse) do
      if rid~=activeArenaId and residentScenes[rid] and (not vstamp or stamp<vstamp) then victim,vstamp=rid,stamp end
    end
    if not victim then break end
    local old=residentScenes[victim]
    residentScenes[victim]=nil;residentUse[victim]=nil
    if old~=scene then releaseArenaScene(old) end
  end
  return s
end
local function selectResident(id)
  local s=id and residentScenes[id] or nil
  if s and activeDef and s.cachePath and s.cachePath~=activeDef.cache then
    releaseArenaScene(s);residentScenes[id]=nil;residentUse[id]=nil;s=nil
  end
  if s then
    residentSerial=residentSerial+1;residentUse[id]=residentSerial
  end
  scene=s
  return s
end

-- Arena source caches are intentionally human-readable Lua because they are
-- extraction/debug artifacts. That format is extremely expensive to parse on
-- mobile once it contains hundreds of thousands of numeric vertices. Build a
-- compact runtime sidecar the first time an arena is materialized: tiny Lua
-- metadata plus tightly-packed float32 vertex streams. Subsequent sessions can
-- skip both the giant Lua vertex parse and normal reconstruction. The source
-- cache remains authoritative and any sidecar failure falls back to it.
local ARENA_RUNTIME_MESH_VERSION=2
local arenaRuntimeHits,arenaRuntimeWrites=0,0
local function safeArenaId(id) return tostring(id or "water"):gsub("[^%w_%-]","_") end
local function arenaRuntimeRoot(id) return "cache/runtime_mesh_v2/arenas/"..safeArenaId(id) end
local function arenaRuntimeMetaPath(id) return arenaRuntimeRoot(id).."/scene.lua" end
local function arenaRuntimeBinPath(id,bucket,i)
  return arenaRuntimeRoot(id)..("/%s_%03d.f32"):format(tostring(bucket or "group"),tonumber(i) or 0)
end
local function arenaSourceSize(def)
  local info=GeneratedAssets and GeneratedAssets.info and GeneratedAssets.info(def and def.cache) or nil
  return info and tonumber(info.size) or nil
end
local function arenaRuntimeUsable(meta,def,sourceSize)
  if type(meta)~="table" or tonumber(meta.runtimeMeshVersion)~=ARENA_RUNTIME_MESH_VERSION then return false end
  if not sourceSize or tonumber(meta.sourceSize)~=sourceSize or tostring(meta.sourceCache or "")~=tostring(def and def.cache or "") then return false end
  local total=0
  for _,bucket in ipairs({"opaque","cutout","crowd","translucent","additive"}) do
    local rows=meta[bucket]
    if type(rows)~="table" then return false end
    for i,g in ipairs(rows) do
      local path=type(g)=="table" and (g.runtimeBin or arenaRuntimeBinPath(def.id,bucket,i)) or nil
      local info=path and GeneratedAssets.info and GeneratedAssets.info(path) or nil
      local size=info and tonumber(info.size)
      if not size or size<144 or size%48~=0 then return false end
      total=total+1
    end
  end
  return total>0
end
local function compactArenaEntry(g,textureSpec,runtimeBin)
  return {runtimeBin=runtimeBin,texture=textureSpec,alpha=g.alpha,noz=g.noz,center=g.center,mode=g.mode,flow=g.flow,detail=g.detail,texelStep=g.texelStep,
    diffuse=g.diffuse,ambient=g.ambient,specular=g.specular,shininess=g.shininess}
end
local function ensureArenaShader(ctx)
  if shader then return shader end
  local ok,sh
  if ARENA_ANDROID then
    ok,sh=pcall(love.graphics.newShader,MOBILE_VERTEX,MOBILE_PIXEL)
    if not ok then
      local mobileErr=sh
      local okFull,full=pcall(love.graphics.newShader,VERTEX,PIXEL)
      if okFull then ok,sh=true,full
      else sh=("mobile=%s; full=%s"):format(tostring(mobileErr),tostring(full)) end
    else
      log(ctx,"info","Android GLES-safe arena shader active")
    end
  else
    ok,sh=pcall(love.graphics.newShader,VERTEX,PIXEL)
  end
  if not ok then return nil,"shader: "..tostring(sh) end
  shader=sh
  uniformCache=nil;uniformCacheShader=nil
  return shader
end
local function loadRuntimeArena(ctx,meta,def)
  local textures={}
  local out={opaque={},cutout={},crowd={},translucent={},additive={},bounds=meta.bounds,source=meta.source,textures=textures,
    culled=tonumber(meta.culled) or 0,oversizeCulled=tonumber(meta.oversizeCulled) or 0,crowdOutliers=tonumber(meta.crowdOutliers) or 0,
    crowdOriginal=tonumber(meta.crowdOriginal) or 0,crowdKept=tonumber(meta.crowdKept) or 0,crowdPolicy=meta.crowdPolicy,cachePath=def.cache,runtimeSidecar=true}
  for _,bucket in ipairs({"opaque","cutout","crowd","translucent","additive"}) do
    for i,g in ipairs(meta[bucket] or {}) do
      local tex,terr=texture(g.texture,textures);if not tex then releaseArenaScene(out);return nil,terr end
      local path=g.runtimeBin or arenaRuntimeBinPath(def.id,bucket,i)
      local mesh,merr=RuntimeMeshCache.meshFromPath(FORMAT,path,12,"static")
      if not mesh then releaseArenaScene(out);return nil,merr end
      mesh:setTexture(tex.image)
      out[bucket][#out[bucket]+1]={mesh=mesh,alpha=tonumber(g.alpha) or 1,noz=g.noz and true or false,center=g.center or {0,0,0},
        mode=tonumber(g.mode) or 0,flow=tonumber(g.flow) or 0,detail=g.detail,texelStep=g.texelStep or {1,1},diffuse=g.diffuse or {1,1,1},
        ambient=g.ambient or {1,1,1},specular=g.specular or {0,0,0},shininess=tonumber(g.shininess) or 0}
    end
  end
  arenaRuntimeHits=arenaRuntimeHits+1
  log(ctx,"info","loaded arena runtime sidecar %s (%d material groups)",tostring(def.id),#out.opaque+#out.cutout+#out.crowd+#out.translucent+#out.additive)
  return out
end
local function loadScene(ctx)
  if not scene then selectResident(activeArenaId) end
  if scene then return scene end
  if errorText then return nil,errorText end
  if not (love and love.graphics and love.image and love.graphics.newMesh and love.graphics.newShader) then
    errorText="LÖVE 3D graphics API unavailable"; return nil,errorText
  end
  local def=activeDef or (ArenaCatalog and ArenaCatalog.definition and ArenaCatalog.definition("water")) or {id="water",cache="cache/M1_water_cache.lua"}
  local cachePath=def.cache or "cache/M1_water_cache.lua"
  local sourceSize=arenaSourceSize(def)
  if RuntimeMeshCache and type(RuntimeMeshCache.readLua)=="function" and type(RuntimeMeshCache.meshFromPath)=="function" then
    local rt=select(1,RuntimeMeshCache.readLua(arenaRuntimeMetaPath(def.id)))
    if arenaRuntimeUsable(rt,def,sourceSize) then
      local runtimeScene,rerr=loadRuntimeArena(ctx,rt,def)
      if runtimeScene then
        local sh,serr=ensureArenaShader(ctx);if not sh then releaseArenaScene(runtimeScene);errorText=tostring(serr);return nil,errorText end
        scene=runtimeScene;touchResident(activeArenaId,scene);errorText=nil
        return scene
      end
      log(ctx,"warn","arena runtime sidecar %s unusable at load (%s); falling back to source cache",tostring(def.id),tostring(rerr))
    end
  end
  local cache,err=readLua(cachePath)
  if not cache then errorText=tostring(err);return nil,errorText end
  local textures={}; local opaque, cutout, crowd, translucent, additive = {}, {}, {}, {}, {}
  local runtimeRows={opaque={},cutout={},crowd={},translucent={},additive={}}
  local runtimeWritable=sourceSize and RuntimeMeshCache and RuntimeMeshCache.supported and RuntimeMeshCache.supported() and type(RuntimeMeshCache.writeRows)=="function"
  local runtimeAll=runtimeWritable and true or false
  local culled,oversizeCulled,crowdOutliers=0,0,0
  for i,g in ipairs(cache.groups or {}) do
    local center,span,extent=groupStats(g.vertices)
    local radial=math.sqrt((center[1] or 0)^2+(center[3] or 0)^2)
    if radial>BATTLE_SCENE_RADIUS_RAW or span>BATTLE_MAX_GROUP_SPAN_RAW or dropGhostLayer(g) then
      culled=culled+1
      if span>BATTLE_MAX_GROUP_SPAN_RAW then oversizeCulled=oversizeCulled+1 end
    else
      local tex,terr=texture(g.texture,textures)
      if not tex then errorText=tostring(terr);return nil,errorText end
      local alpha=tonumber(g.alpha) or 1
      local mode=materialMode(g,tex)
      local meshVertices=withNormals(g.vertices,mode)
      if #meshVertices==0 then
        culled=culled+1
      else
        local ok,mesh=pcall(love.graphics.newMesh,FORMAT,meshVertices,"triangles","static")
        if not ok then errorText="mesh "..i..": "..tostring(mesh);return nil,errorText end
        mesh:setTexture(tex.image)
        local detail=materialDetail(g)
        local tw=(g.texture and tonumber(g.texture.w)) or 1
        local th=(g.texture and tonumber(g.texture.h)) or 1
        local maxXZ=math.max((extent and extent[1]) or 0,(extent and extent[3]) or 0)
        local inferredFlow=((mode==1 or mode==5) and extent and (extent[2] or 0)>math.max(35,maxXZ*1.30)) and 1 or 0
        -- Procedural rebuild groups can state their intended transport axis.
        -- This matters for Mt. Battle because pools and waterfalls share the
        -- same source texture; group-wide extents cannot reliably infer which
        -- one is vertical once several lava features are batched together.
        local flow=(g.flow~=nil) and tonumber(g.flow) or inferredFlow
        flow=flow or 0
        if mode>3.10 and mode<3.40 then
          local wp=tostring(g.texture and g.texture.path or "")
          flow=wp:find("grass_tuft_",1,true) and 1 or 0.35
        end
        local entry={mesh=mesh,alpha=alpha,noz=g.noz and true or false,center=center,mode=mode,flow=flow,detail=detail,texelStep={1/math.max(1,tw),1/math.max(1,th)},
          diffuse=g.diffuse or {1,1,1},ambient=g.ambient or {1,1,1},specular=g.specular or {0,0,0},shininess=tonumber(g.shininess) or 0}
        local bucketName,bucket
        if mode==2 then
          bucketName,bucket="additive",additive
        elseif mode==1 then
          -- Force all water through the transparent pass, even when the source
          -- material happened to be marked opaque for its original TEV setup.
          bucketName,bucket="translucent",translucent
        elseif mode==4 then
          -- The prior support test still admitted four isolated cards high in
          -- empty space (the tiny spectators visibly hanging over waterfalls in
          -- the v21 recording).  The real seated bank in this extraction lives
          -- below raw Y=80; the four strays begin above Y=95.  Cull that clean
          -- gap rather than using a camera-dependent screen heuristic.
          local cpath=tostring(g.texture and g.texture.path or "")
          if cpath:find("cache/stages/orre/crowd_",1,true) or (center[2] or 0) <= 84.0 then
            bucketName,bucket="crowd",crowd
          else
            culled=culled+1;crowdOutliers=crowdOutliers+1
          end
        elseif mode>=3 and mode<3.5 then
          bucketName,bucket="cutout",cutout
        elseif not g.xlu then
          bucketName,bucket="opaque",opaque
        else
          bucketName,bucket="translucent",translucent
        end
        if bucket then
          bucket[#bucket+1]=entry
          if runtimeWritable then
            local ri=#runtimeRows[bucketName]+1
            local bin=arenaRuntimeBinPath(def.id,bucketName,ri)
            local wok=RuntimeMeshCache.writeRows(bin,meshVertices,12)
            if wok then runtimeRows[bucketName][ri]=compactArenaEntry(entry,g.texture,bin) else runtimeAll=false end
          end
        end
      end -- non-empty mesh
    end
  end
  local sh,serr=ensureArenaShader(ctx)
  if not sh then errorText=tostring(serr);return nil,errorText end
  scene={opaque=opaque,cutout=cutout,crowd=crowd,translucent=translucent,additive=additive,bounds=cache.bounds,source=cache.source,textures=textures,culled=culled,oversizeCulled=oversizeCulled,crowdOutliers=crowdOutliers,
    crowdOriginal=tonumber(cache.crowdOriginal) or 0,crowdKept=#crowd,crowdPolicy=cache.crowdPolicy or ((activeDef and activeDef.crowd) or "none"),cachePath=cachePath,runtimeSidecar=false }
  if runtimeAll and RuntimeMeshCache and type(RuntimeMeshCache.writeLua)=="function" then
    local meta={runtimeMeshVersion=ARENA_RUNTIME_MESH_VERSION,sourceSize=sourceSize,sourceCache=cachePath,bounds=cache.bounds,source=cache.source,
      culled=culled,oversizeCulled=oversizeCulled,crowdOutliers=crowdOutliers,crowdOriginal=tonumber(cache.crowdOriginal) or 0,crowdKept=#crowd,
      crowdPolicy=cache.crowdPolicy or ((activeDef and activeDef.crowd) or "none"),opaque=runtimeRows.opaque,cutout=runtimeRows.cutout,crowd=runtimeRows.crowd,
      translucent=runtimeRows.translucent,additive=runtimeRows.additive}
    local wok=RuntimeMeshCache.writeLua(arenaRuntimeMetaPath(def.id),meta)
    if wok then arenaRuntimeWrites=arenaRuntimeWrites+1;log(ctx,"info","wrote compact runtime arena sidecar for %s",tostring(def.id)) end
  end
  cache=nil
  touchResident(activeArenaId,scene);errorText=nil
  log(ctx,"info","loaded arena: %d opaque + %d cutout + %d animated crowd + %d translucent + %d additive groups (%d remote/effect groups omitted); crowd cards %d/%d (%s, %d hanging outliers removed) from %s",#opaque,#cutout,#crowd,#translucent,#additive,culled,
    scene.crowdKept,scene.crowdOriginal,tostring(scene.crowdPolicy or "legacy"),scene.crowdOutliers or 0,tostring(scene.source))
  return scene
end
-- love.graphics.getSystemLimits() is a driver query, and pixelSize() called
-- this on Android for EVERY frame. Both the texture limit and the derived
-- canvas size are fixed for a given window size, so both are cached.
local sysTextureLimit=nil
local mcsW,mcsH,mcsOutW,mcsOutH=nil,nil,nil,nil
local function mobileCanvasSize(w,h)
  w,h=tonumber(w) or 0,tonumber(h) or 0
  if w<=0 or h<=0 then return w,h end
  if mcsW==w and mcsH==h then return mcsOutW,mcsOutH end
  -- A full physical-resolution RGBA canvas plus depth buffer is an unnecessary
  -- GPU-memory multiplier on 1440p/4K-density phones. Keep the same aspect/FOV
  -- but cap Android's offscreen 3D surface to roughly 720p / 1280 max axis.
  local maxPixels=1280*720;local maxAxis=1280
  local scale=math.min(1,maxAxis/math.max(w,h),math.sqrt(maxPixels/(w*h)))
  if sysTextureLimit==nil and love.graphics.getSystemLimits then
    local ok,limits=pcall(love.graphics.getSystemLimits)
    sysTextureLimit=(ok and type(limits)=="table" and tonumber(limits.texturesize)) or false
  end
  if sysTextureLimit and sysTextureLimit>0 then scale=math.min(scale,sysTextureLimit/math.max(w,h)) end
  local inW,inH=w,h
  if scale<1 then
    w=math.max(320,math.floor(w*scale+0.5));h=math.max(180,math.floor(h*scale+0.5))
  end
  mcsW,mcsH,mcsOutW,mcsOutH=inW,inH,w,h
  return w,h
end
local function pixelSize()
  if ARENA_ANDROID then
    local w,h=love.graphics.getDimensions();return mobileCanvasSize(w,h)
  end
  if love.graphics.getPixelDimensions then
    local w,h=love.graphics.getPixelDimensions(); if w and h and w>0 and h>0 then return w,h end
  end
  return love.graphics.getDimensions()
end
local function canvasFormats()
  if not (love.graphics and type(love.graphics.getCanvasFormats)=="function") then return {} end
  local ok,v=pcall(love.graphics.getCanvasFormats)
  return ok and type(v)=="table" and v or {}
end
local function ensureCanvas(w,h)
  if canvas and cw==w and ch==h then return canvas end
  canvas=nil;depthCanvas=nil;depthMode=nil;depthActive=false
  local colorOpts={dpiscale=1,msaa=0}
  local okColor,out=pcall(love.graphics.newCanvas,w,h,colorOpts)
  if not okColor then
    -- Some mobile LÖVE forks reject newer option keys. Retry the oldest common
    -- signature before declaring the arena unavailable.
    okColor,out=pcall(love.graphics.newCanvas,w,h)
  end
  if not okColor then error(out) end
  canvas=out;cw,ch=w,h
  if ARENA_ANDROID then
    local formats=canvasFormats()
    for _,fmt in ipairs({"depth24stencil8","depth16"}) do
      if formats[fmt]~=false then
        local okDepth,d=pcall(love.graphics.newCanvas,w,h,{format=fmt,readable=false,dpiscale=1,msaa=0})
        if okDepth then depthCanvas=d;depthMode="explicit";break end
      end
    end
    if not depthMode then depthMode="auto" end
  else
    depthMode="auto"
  end
  return canvas
end
local function bindArenaCanvas(out)
  if depthMode=="explicit" and depthCanvas then
    local ok,err=pcall(love.graphics.setCanvas,{out,depthstencil=depthCanvas})
    if ok then depthActive=true;return true end
    log(nil,"warn","explicit Android depth attachment rejected; retrying temporary depth: %s",tostring(err))
    depthCanvas=nil;depthMode="auto"
  end
  if depthMode=="auto" then
    local ok,err=pcall(love.graphics.setCanvas,{out,depth=true})
    if ok then depthActive=true;return true end
    log(nil,"warn","temporary arena depth attachment rejected; using ordered no-depth mobile fallback: %s",tostring(err))
    depthMode="none"
  end
  local ok,err=pcall(love.graphics.setCanvas,out)
  if not ok then return false,err end
  depthActive=false
  return true
end
-- Uniform presence is a property of the compiled shader, not of the frame.
-- The old path ran TWO pcalls (hasUniform + send) for every uniform of every
-- material group of every frame; drawGroups alone sends nine per group. The
-- lookup is resolved once per shader object and cached.
local function sendShader(name,...)
  local sh=shader
  if not sh then return false end
  if uniformCacheShader~=sh then uniformCacheShader=sh;uniformCache={} end
  local has=uniformCache[name]
  if has==nil then
    has=true
    if type(sh.hasUniform)=="function" then
      local ok,v=pcall(sh.hasUniform,sh,name)
      if ok and not v then has=false end
    end
    uniformCache[name]=has
  end
  if not has then return false end
  return pcall(sh.send,sh,name,...)
end
local UP_Y={0,1,0}
local function viewProjection(ctx,w,h)
  local camera=ctx and ctx.services and ctx.services.camera
  local pose=camera and camera.pose
  if not (pose and pose.eye and pose.focus and pose.fov) then
    -- Deliberately a fresh table: consumers receive this pose through
    -- ctx.services.camera.pose and must never share a module-level default.
    pose={eye={54,24,13},focus={0,6,0},fov=math.rad(40)}
  end
  local eye,focus=pose.eye,pose.focus
  local dx,dy,dz=eye[1]-focus[1],eye[2]-focus[2],eye[3]-focus[3]
  local dist=math.max(2,math.sqrt(dx*dx+dy*dy+dz*dz))
  local near=math.max(0.40,dist*0.007)
  -- D2's source stage carries crater/background geometry much farther from the
  -- battle disc than the old procedural Platform 100 rebuild. Give that exact
  -- scenery enough depth range instead of clipping it at the generic 345-unit
  -- arena plane.
  local profile=(activeDef and activeDef.profile) or "water"
  local baseFar=(profile=="summit" and 1450)
    or (profile=="realgam" and 1200)
    or (profile=="orre" and 760)
    or 345
  local tail=(profile=="summit" and 1320)
    or (profile=="realgam" and 1050)
    or (profile=="orre" and 650)
    or 265
  local far=math.max(baseFar,dist+tail)
  local p=Mat4.perspective(pose.fov,w/h,near,far)
  -- scale(1,-1,1) * p only negates the second row of p; doing that directly
  -- avoids building a scale matrix and running a full 4x4 multiply per frame.
  p[5],p[6],p[7],p[8]=-p[5],-p[6],-p[7],-p[8]
  return Mat4.mul(p,Mat4.lookAt(eye,focus,UP_Y)), pose
end
local function setStageState(vp,model,writeDepth,pose)
  if depthActive then love.graphics.setDepthMode("lequal",writeDepth and true or false) else love.graphics.setDepthMode() end
  if love.graphics.setMeshCullMode then love.graphics.setMeshCullMode("none") end
  love.graphics.setBlendMode("alpha","alphamultiply")
  love.graphics.setColor(1,1,1,1)
  love.graphics.setShader(shader)
  sendShader("vp","row",vp);sendShader("model","row",model)
  sendShader("sceneTime",sceneTime)
  sendShader("sceneRadiusWorld",math.max(20,(BATTLE_VERTEX_RADIUS_RAW or 415)*(STAGE_SCALE or 0.25)+8))
  local profile=(activeDef and activeDef.profile) or "water"
  sendShader("sceneProfile",profile=="realgam" and 4 or (profile=="orre" and 3 or (profile=="summit" and 2 or (profile=="outdoor" and 1 or 0))))
  sendShader("cameraEye",pose and pose.eye or {54,24,13})
end
-- Shared immutable fallbacks. These were allocated fresh for every material
-- group that omitted the field, on every frame.
local WHITE3={1,1,1}
local BLACK3={0,0,0}
local UNIT2={1,1}
local function drawGroup(g)
  sendShader("materialAlpha",g.alpha or 1)
  sendShader("materialMode",g.mode or 0)
  sendShader("materialFlow",g.flow or 0)
  sendShader("materialDiffuse",g.diffuse or WHITE3)
  sendShader("materialAmbient",g.ambient or WHITE3)
  sendShader("materialSpecular",g.specular or BLACK3)
  sendShader("materialShininess",g.shininess or 0)
  sendShader("materialDetail",g.detail or 0)
  sendShader("texelStep",g.texelStep or UNIT2)
  love.graphics.draw(g.mesh)
end
local function drawGroups(groups)
  for i=1,#groups do drawGroup(groups[i]) end
end
local function drawCrowd(groups,vp,baseModel,pose)
  if not groups then return end
  -- Both of these are constant for the whole crowd pass; they used to be
  -- re-derived inside the per-sector loop.
  local exactSourceCrowd=scene and scene.crowdPolicy=="source-hsd-crowd"
  local profile=activeDef and activeDef.profile
  local cull=(not exactSourceCrowd) and pose and pose.eye
    and (profile=="orre" or profile=="realgam")
  local ex,ey,ez
  if cull then ex,ey,ez=pose.eye[1] or 0,pose.eye[2] or 0,pose.eye[3] or 0 end
  local sc=STAGE_SCALE or 0.25
  for i=1,#groups do
    local g=groups[i]
    local c=g.center or BLACK3
    -- Sector batches retain a meaningful center, so the whole camera-side
    -- gallery sector can be hidden behind its architecture in one decision.
    local skip=false
    if cull then
      local wx,wz=(c[1] or 0)*sc,(c[3] or 0)*sc
      local dx=wx-ex
      local dy=(c[2] or 0)*sc-ey
      local dz=wz-ez
      local sameCameraHemisphere=(wx*ex+wz*ez)>0
      skip=sameCameraHemisphere or (dx*dx+dy*dy+dz*dz)<34*34
    end
    if not skip then
      setStageState(vp,baseModel,true,pose)
      -- Was drawGroups({g}): one throwaway table per visible crowd sector
      -- per frame.
      drawGroup(g)
    end
  end
end
local function drawAdditive(groups)
  if not groups or #groups==0 then return end
  love.graphics.setBlendMode("add","alphamultiply")
  drawGroups(groups)
  love.graphics.setBlendMode("alpha","alphamultiply")
end
local function projectWorldToBackdrop(vp,x,y,z,w,h)
  if not vp then return nil end
  local cx=vp[1]*x+vp[2]*y+vp[3]*z+vp[4]
  local cy=vp[5]*x+vp[6]*y+vp[7]*z+vp[8]
  local cw=vp[13]*x+vp[14]*y+vp[15]*z+vp[16]
  if not cw or cw<=0.0001 then return nil end
  local nx,ny=cx/cw,cy/cw
  return (nx*.5+.5)*w,(ny*.5+.5)*h
end

-- ---------------------------------------------------------------------------
-- BACKDROP
--
-- Every profile below painted its sky as 40-72 individually filled screen-wide
-- rectangles, plus source card draws, on EVERY frame -- for artwork that does
-- not change between frames at all. On a phone that is 40-72 extra draw calls
-- and state changes per frame before a single piece of arena geometry is
-- submitted, which is a large part of why Colosseum models felt heavy next to
-- the UI.
--
-- paintBackdropStatic() below is the ORIGINAL painter, unchanged in what it
-- draws. It is now rendered once into a cached canvas keyed by
-- profile/size/scene and blitted thereafter. The only genuinely per-frame
-- elements -- Outdoor Wild's drifting cloud cards and its vp-projected sun --
-- are split out into paintBackdropDynamic() and still drawn live every frame.
-- Nothing about the resulting image changes.
-- ---------------------------------------------------------------------------
local function paintBackdropStatic(w,h)
  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.setBlendMode("alpha","alphamultiply")
  local profile=(activeDef and activeDef.profile) or "water"
  local bg=activeDef and activeDef.backdrop
  local top=(bg and bg.top) or {0.025,0.075,0.145}
  local bottom=(bg and bg.bottom) or {0.13,0.25,0.34}
  local bands=72

  -- Platform 100 source reference: the summit sits above an active volcanic
  -- mouth under a pale, cloud-heavy Orre sky.  The previous flat charcoal
  -- gradient made the extracted crater feel like a model viewer.  Build a
  -- quiet layered sky/cloud deck in screen space so the 3D stage still owns
  -- all silhouettes and depth.
  if profile=="water" then
    -- Phenac / Water Colosseum is an enclosed limestone stadium. The previous
    -- pass borrowed Mt. Battle sky/cloud textures behind it, which could turn
    -- gaps in the authentic source shell into an outdoor blue-sky scene. Keep
    -- the backdrop purely neutral and architectural; the extracted M1 HSD owns
    -- every visible wall, balcony, banner, fountain and water surface.
    local a={.075,.105,.115};local b={.205,.235,.235}
    for i=0,55 do
      local t=i/55;local u=t*t*(3-2*t);local y=i*h/55
      love.graphics.setColor(a[1]+(b[1]-a[1])*u,a[2]+(b[2]-a[2])*u,a[3]+(b[3]-a[3])*u,1)
      love.graphics.rectangle("fill",0,y,w,math.ceil(h/55)+2)
    end
    love.graphics.setColor(.12,.17,.18,.08);love.graphics.rectangle("fill",0,h*.76,w,h*.24)
    love.graphics.setColor(1,1,1,1)
    return
  elseif profile=="summit" then
    -- Mt. Battle is source-backed now. The HSD stage itself owns the mountain,
    -- bridge, crater silhouettes, sky-facing cards and every decoded GX texture.
    -- Keep screen-space background treatment deliberately neutral so it cannot
    -- recolour the source venue into the invented sunset used by the procedural
    -- rebuild. This gradient exists only behind holes/open horizon in the stage.
    local a={.30,.38,.49};local b={.72,.72,.69}
    for i=0,bands-1 do
      local t=(i+.5)/bands;local q=t*t*(3-2*t)
      local y=math.floor(i*h/bands);local y2=math.ceil((i+1)*h/bands)
      love.graphics.setColor(a[1]+(b[1]-a[1])*q,a[2]+(b[2]-a[2])*q,a[3]+(b[3]-a[3])*q,1)
      love.graphics.rectangle("fill",0,y,w,math.max(1,y2-y+1))
    end
    love.graphics.setColor(1,1,1,1)
    return
  elseif profile=="realgam" then
    -- Realgam's own D4 source atlas contains the pale-blue cloud deck visible
    -- around the suspended tower arena. An earlier invented amber sky changed
    -- the venue identity even when the geometry was correct.
    local skyEntry
    if scene and scene.textures then
      skyEntry=texture({path="cache/stages/realgam/source/sky_512x176.rgba",w=512,h=176,wrapS=0,wrapT=0},scene.textures)
    end
    if skyEntry and skyEntry.image then
      -- Cool upper atmosphere, followed by the exact source cloud band.
      for i=0,39 do
        local t=i/39;local y=i*h*.40/39
        love.graphics.setColor(.43+.24*t,.64+.20*t,.82+.13*t,1)
        love.graphics.rectangle("fill",0,y,w,math.ceil(h*.40/39)+2)
      end
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(skyEntry.image,0,h*.34,0,w/512,(h*.66)/176)
      love.graphics.setColor(.92,.96,1.0,.035);love.graphics.rectangle("fill",0,h*.50,w,h*.50)
    else
      local a={.39,.59,.79};local b={.72,.84,.93}
      for i=0,63 do local t=i/63;local y=i*h/63
        love.graphics.setColor(a[1]+(b[1]-a[1])*t,a[2]+(b[2]-a[2])*t,a[3]+(b[3]-a[3])*t,1)
        love.graphics.rectangle("fill",0,y,w,math.ceil(h/63)+2)
      end
    end
    love.graphics.setColor(1,1,1,1)
    return
  elseif profile=="orre" then
    -- T1_ancient_colo ships a dedicated 256x128 blue-sky/cloud texture.
    -- Use that exact source artwork instead of the hand-authored orange/blue
    -- gradient so arena stone, crowd and horizon share the original palette.
    local skyEntry
    if scene and scene.textures then
      skyEntry=texture({path="cache/stages/orre/source/tex_055ec0_256x128_f14.rgba",w=256,h=128,wrapS=0,wrapT=0},scene.textures)
    end
    if skyEntry and skyEntry.image then
      love.graphics.setColor(1,1,1,1)
      love.graphics.draw(skyEntry.image,0,0,0,w/256,h/128)
      -- Very light desert haze at the bottom; all actual architecture remains
      -- source geometry and is never painted into the backdrop.
      love.graphics.setColor(.78,.72,.62,.035);love.graphics.rectangle("fill",0,h*.78,w,h*.22)
    else
      for i=0,63 do
        local t=i/63;local y=i*h/63
        love.graphics.setColor(.10+.42*t,.31+.37*t,.63+.25*t,1)
        love.graphics.rectangle("fill",0,y,w,math.ceil(h/63)+2)
      end
    end
    love.graphics.setColor(1,1,1,1)
    return
  elseif profile=="outdoor" then
    -- Wild Outdoor is a generic lush wild-battle pocket of Orre,
    -- not a construction/desert lot.  Reuse the decoded Colosseum sky card
    -- and grade it into a clear highland blue with soft forest haze.
    local skyEntry,cloudEntry
    if scene and scene.textures then
      skyEntry=texture({path="cache/stages/d2_crater/textures/tex_0c2120_256x256_f14.rgba",w=256,h=256},scene.textures)
      cloudEntry=texture({path="cache/stages/d2_crater/textures/tex_0d6920_128x128_f1.rgba",w=128,h=128},scene.textures)
    end
    -- Clear blue overhead fading toward a bright humid forest horizon.
    -- Paint this opaquely first so Outdoor Wild can never fall back to the
    -- old grey/brown D2 card as its dominant read.
    for i=0,55 do
      local t=i/55;local y=i*h/55
      local r=.10+t*.40;local g=.30+t*.41;local b=.57+t*.20
      love.graphics.setColor(r,g,b,1)
      love.graphics.rectangle("fill",0,y,w,math.ceil(h/55)+2)
    end
    -- The decoded Colosseum sky card becomes cloud/weather detail rather than
    -- the base color of the entire sky.
    if skyEntry and skyEntry.image then
      love.graphics.setColor(.95,.98,1.00,.08)
      love.graphics.draw(skyEntry.image,0,0,0,w/256,h/256)
    end
    -- The sun and the drifting cloud cards depend on the live camera and on
    -- sceneTime, so they are NOT baked; paintBackdropDynamic draws them every
    -- frame, in exactly this position in the layer order.
    love.graphics.setColor(1,1,1,1)
    return
  end

  for i=0,bands-1 do
    local t=(i+0.5)/bands; local u=t*t*(3-2*t)
    love.graphics.setColor(top[1]+(bottom[1]-top[1])*u,top[2]+(bottom[2]-top[2])*u,top[3]+(bottom[3]-top[3])*u,1)
    local y=math.floor(i*h/bands); local y2=math.ceil((i+1)*h/bands)
    love.graphics.rectangle("fill",0,y,w,math.max(1,y2-y+1))
  end
  love.graphics.setColor(1,1,1,1)
end

-- Per-frame backdrop elements. Only Outdoor Wild has any: the camera-projected
-- sun and the two drifting cloud bands, followed by its haze. Byte-for-byte
-- the same draw sequence that used to sit inline in the outdoor branch.
local function paintBackdropDynamic(w,h,vp)
  local profile=(activeDef and activeDef.profile) or "water"
  if profile~="outdoor" then return end
  love.graphics.setShader()
  love.graphics.setDepthMode()
  love.graphics.setBlendMode("alpha","alphamultiply")
  local cloudEntry
  if scene and scene.textures then
    cloudEntry=texture({path="cache/stages/d2_crater/textures/tex_0d6920_128x128_f1.rgba",w=128,h=128},scene.textures)
  end
  -- Fixed late-afternoon sun filtering through the forest edge.
  local sx,sy=projectWorldToBackdrop(vp,-210.0,118.0,145.0,w,h)
  if sx and sy and sx>-w*.18 and sx<w*1.18 and sy>-h*.16 and sy<h*.72 then
    love.graphics.setColor(1.00,.68,.28,.035);love.graphics.ellipse("fill",sx,sy,w*.12,h*.11)
    love.graphics.setColor(1.00,.84,.48,.080);love.graphics.ellipse("fill",sx,sy,w*.060,h*.056)
    love.graphics.setColor(1.00,.95,.74,.20);love.graphics.ellipse("fill",sx,sy,w*.020,h*.019)
  end
  if cloudEntry and cloudEntry.image then
    local d=(sceneTime*2.3)%(w*.66)
    love.graphics.setColor(.96,.98,1.00,.075)
    love.graphics.draw(cloudEntry.image,-w*.28-d,h*.10,0,w/128*.94,h/128*.25)
    love.graphics.draw(cloudEntry.image, w*.46-d,h*.16,0,w/128*.86,h/128*.23)
    local d2=(sceneTime*1.7)%(w*.74)
    love.graphics.setColor(.86,.94,.89,.045)
    love.graphics.draw(cloudEntry.image,-w*.18+d2,h*.53,0,w/128*.78,h/128*.15)
  end
  -- Pale blue-green distance haze behind the tree line, never brown dust.
  love.graphics.setColor(.67,.82,.75,.055);love.graphics.rectangle("fill",0,h*.73,w,h*.27)
  love.graphics.setColor(.32,.50,.37,.025);love.graphics.rectangle("fill",0,h*.90,w,h*.10)
  love.graphics.setColor(1,1,1,1)
end

-- Bake the static sky once per (profile, framebuffer size, loaded scene).
-- Must be called with no arena canvas bound; A:render does this immediately
-- before it binds the arena framebuffer.
local function ensureBackdrop(w,h)
  local key=tostring(activeDef and activeDef.profile or "water").."|"..tostring(w).."x"..tostring(h)
    .."|"..tostring(scene).."|"..tostring(activeDef)
  if backdropCanvas and backdropKey==key then return backdropCanvas end
  if backdropCanvas then pcall(function() if backdropCanvas.release then backdropCanvas:release() end end) end
  backdropCanvas=nil;backdropKey=nil
  local okNew,bc=pcall(love.graphics.newCanvas,w,h,{dpiscale=1,msaa=0})
  if not okNew then okNew,bc=pcall(love.graphics.newCanvas,w,h) end
  if not okNew or not bc then return nil end
  local prior=love.graphics.getCanvas()
  local ok=pcall(function()
    love.graphics.push("all")
    if love.graphics.origin then love.graphics.origin() end
    if love.graphics.setScissor then love.graphics.setScissor() end
    love.graphics.setCanvas(bc)
    love.graphics.clear(0,0,0,0)
    paintBackdropStatic(w,h)
    love.graphics.setCanvas(prior)
    love.graphics.pop()
  end)
  if not ok then
    pcall(love.graphics.setCanvas,prior)
    pcall(function() if bc.release then bc:release() end end)
    return nil
  end
  backdropCanvas=bc;backdropKey=key
  backdropBakes=backdropBakes+1
  return backdropCanvas
end

local function drawBackdrop(w,h,vp,baked)
  if baked then
    love.graphics.setShader()
    love.graphics.setDepthMode()
    love.graphics.setBlendMode("alpha","alphamultiply")
    love.graphics.setColor(1,1,1,1)
    love.graphics.draw(baked,0,0)
  else
    -- Canvas unavailable on this backend: fall back to the original
    -- immediate-mode painter so the arena still renders correctly.
    paintBackdropStatic(w,h)
  end
  paintBackdropDynamic(w,h,vp)
end

local function worldCenter(c)
  local x,y,z=(c[1] or 0)*STAGE_SCALE,(c[2] or 0)*STAGE_SCALE,(c[3] or 0)*STAGE_SCALE
  if STAGE_YAW~=0 then
    local cs,sn=math.cos(STAGE_YAW),math.sin(STAGE_YAW)
    x,z=cs*x+sn*z,-sn*x+cs*z
  end
  return x,y,z
end
-- Back-to-front sort for the no-depth-write transparency pass.
--
-- The comparator used to call worldCenter() twice per comparison, and
-- worldCenter runs math.cos/math.sin whenever the stage is yawed. That is
-- O(n log n) trig every frame. Each group's squared eye distance is now
-- computed exactly once per frame and the sort compares plain numbers.
-- Ordering is identical.
local sortKey=setmetatable({},{__mode="k"})
local function drawTransparent(groups,eye)
  local n=#groups
  if n<2 then return drawGroups(groups) end
  local ex,ey,ez=eye[1],eye[2],eye[3]
  local cs,sn=1,0
  local yawed=STAGE_YAW~=0
  if yawed then cs,sn=math.cos(STAGE_YAW),math.sin(STAGE_YAW) end
  for i=1,n do
    local g=groups[i]
    local c=g.center or BLACK3
    local x,y,z=(c[1] or 0)*STAGE_SCALE,(c[2] or 0)*STAGE_SCALE,(c[3] or 0)*STAGE_SCALE
    if yawed then x,z=cs*x+sn*z,-sn*x+cs*z end
    local dx,dy,dz=x-ex,y-ey,z-ez
    sortKey[g]=dx*dx+dy*dy+dz*dz
  end
  table.sort(groups,function(a,b) return sortKey[a]>sortKey[b] end)
  drawGroups(groups)
end
local function updateAnchors(arena)
  local k=math.max(0.001,figureScale)
  arena.visualPlayer={VIS_PLAYER[1],VIS_PLAYER[2]}
  arena.visualEnemy={VIS_ENEMY[1],VIS_ENEMY[2]}
  arena.player={VIS_PLAYER[1]/k,VIS_PLAYER[2]/k}
  arena.enemy={VIS_ENEMY[1]/k,VIS_ENEMY[2]/k}
  arena.mid={0,0}
  arena.figureScale=k
end


local function cacheAvailable(def)
  return def and def.cache and GeneratedAssets.exists(def.cache) or false
end
function A:available(ctx)
  local battle=ctx and ctx.battle
  local game=(ctx and ctx.game) or (battle and battle.game)
  if ArenaCatalog and ArenaCatalog.enabled and not ArenaCatalog.enabled(game) then return false end
  local def=ArenaCatalog and ArenaCatalog.resolve and select(1,ArenaCatalog.resolve(game,battle)) or nil
  if def and not cacheAvailable(def) then return false end
  return love and love.graphics and love.graphics.newCanvas and true or false
end
local function activateDefinition(ctx,def,selected)
  if not def then return nil end
  if not cacheAvailable(def) then
    log(ctx,"warn","arena cache unavailable: %s",tostring(def and def.cache))
    return nil
  end
  local nextId=def.id or "water"
  if activeArenaId~=nextId or (activeDef and activeDef.cache~=def.cache) then
    scene=nil;errorText=nil
  end
  activeDef=def
  activeArenaId=nextId
  selectResident(activeArenaId)
  if def.pokemon then
    VIS_PLAYER={def.pokemon.player[1],def.pokemon.player[2]}
    VIS_ENEMY={def.pokemon.enemy[1],def.pokemon.enemy[2]}
  end
  STAGE_SCALE=tonumber(def.stageScale) or 0.25
  STAGE_YAW=tonumber(def.stageYaw) or 0
  BATTLE_SCENE_RADIUS_RAW=tonumber(def.sceneRadiusRaw) or 430
  BATTLE_MAX_GROUP_SPAN_RAW=tonumber(def.maxGroupSpanRaw) or 920
  BATTLE_VERTEX_RADIUS_RAW=tonumber(def.vertexRadiusRaw) or 415
  figureScale=tonumber(def.figureScale) or DEFAULT_FIGURE_SCALE
  if PlayerTrainer and type(PlayerTrainer.setArenaProfile)=="function" then PlayerTrainer:setArenaProfile(def) end
  if Trainer and type(Trainer.setArenaProfile)=="function" then Trainer:setArenaProfile(def) end
  local arena={
    id="COLOSSEUM_BATTLE_ENVIRONMENTS:"..tostring(activeArenaId),
    selectedArena=selected or activeArenaId,
    cachePath=def.cache,
    profile=def.profile,
    portable=true,replacesMap=true,discs=false,
    camera=def.camera or {side=58,back=14,height=24,lookX=0,lookY=6,frameH=50},
    _cbeArenaId=activeArenaId,
  }
  updateAnchors(arena)
  return arena
end

function A:arena(ctx)
  local battle=ctx and ctx.battle
  local game=(ctx and ctx.game) or (battle and battle.game)
  local def,selected
  if ArenaCatalog and ArenaCatalog.resolve then def,selected=ArenaCatalog.resolve(game,battle) end
  def=def or (ArenaCatalog and ArenaCatalog.definition and ArenaCatalog.definition("water")) or {id="water",cache="cache/M1_water_cache.lua",stageScale=0.25,stageYaw=0,sceneRadiusRaw=430,maxGroupSpanRaw=920,vertexRadiusRaw=415,camera={side=58,back=14,height=24,lookX=0,lookY=6,frameH=50},pokemon={player={0,14.5},enemy={0,-14.5}},figureScale=0.38}
  local arena=activateDefinition(ctx,def,selected)
  if arena then log(ctx,"info","arena acquire selected=%s resolved=%s cache=%s",tostring(selected),tostring(activeArenaId),tostring(def.cache)) end
  return arena
end

-- Materialize a specific arena definition without consuming/binding a battle.
-- This is the game-ready path used by AUTO to keep both Water (trainer) and
-- Wildlands (wild/safari) resident. The active presentation profile is restored
-- afterwards so prewarming cannot change the user's next selection.
function A:prewarmDefinition(ctx,id)
  ctx=type(ctx)=="table" and ctx or {}
  local def=ArenaCatalog and ArenaCatalog.definition and ArenaCatalog.definition(id) or nil
  if not def then return false,"unknown arena "..tostring(id) end
  local oldDef=activeDef
  local oldId=activeArenaId
  local oldError=errorText
  local arena=activateDefinition(ctx,def,id)
  if not arena then return false,"arena unavailable" end
  local warmed,err=loadScene(ctx)
  local restore=oldDef or (ArenaCatalog and ArenaCatalog.definition and ArenaCatalog.definition(oldId or "water"))
  if restore then activateDefinition(ctx,restore,oldId) else scene=nil;activeDef=nil;activeArenaId=oldId or "water";errorText=oldError end
  if not warmed then return false,err end
  return true,arena
end

function A:prewarmAutoPair(ctx)
  ctx=type(ctx)=="table" and ctx or {}
  local okWater,errWater=self:prewarmDefinition(ctx,"water")
  local okWild,errWild=self:prewarmDefinition(ctx,"outdoor_wild")
  if not okWater then return false,errWater end
  if not okWild then return false,errWild end
  return true,{water=true,outdoor_wild=true}
end

function A:prewarmResident(ctx)
  ctx=type(ctx)=="table" and ctx or {}
  local arena=self:arena(ctx)
  if not arena then return false,"arena unavailable" end
  local scene0,err=loadScene(ctx)
  if not scene0 then return false,err end
  -- Android wants the expensive generated-cache parse, texture decode, mesh
  -- upload and trainer construction paid while the overworld is already live,
  -- but not a depth/color framebuffer sitting around before battle. The canvas
  -- remains battle-lazy; the reusable arena/trainer GPU scene stays resident.
  if Trainer and type(Trainer.prewarm)=="function" then pcall(Trainer.prewarm,Trainer,ctx) end
  if PlayerTrainer and type(PlayerTrainer.prewarm)=="function" then pcall(PlayerTrainer.prewarm,PlayerTrainer,ctx) end
  return true,arena
end

function A:prewarmFramebuffer()
  if not (love and love.graphics) then return false,"graphics unavailable" end
  local w,h=pixelSize()
  if not (w and h and w>0 and h>0) then return false,"invalid framebuffer size" end
  local ok,out=pcall(ensureCanvas,w,h)
  if not ok then return false,tostring(out) end
  return out~=nil,{width=w,height=h,mode=depthMode}
end

function A:prewarm(ctx)
  local ok,arenaOrErr=self:prewarmResident(ctx)
  if not ok then return false,arenaOrErr end
  self:prewarmFramebuffer()
  return true,arenaOrErr
end

function A:begin(ctx,arena)
  sceneTime=0
  if arena and arena._cbeArenaId and arena._cbeArenaId~=activeArenaId then
    return false
  end
  local s,err=loadScene(ctx)
  if not s then log(ctx,"error","arena load failed: %s",tostring(err));return false end
  if Trainer then
    local okTrainer,trainerErr=Trainer:begin(ctx)
    if okTrainer==false then log(ctx,"error","enemy trainer actor unavailable: %s",tostring(trainerErr)) end
  end
  if PlayerTrainer then
    local okPlayer,playerErr=PlayerTrainer:begin(ctx)
    if okPlayer==false then log(ctx,"error","Red actor unavailable: %s",tostring(playerErr)) end
  end
  -- Gold already reaches CurrentSpriteModels through CBE's standalone host.
  -- StadiumBattleFX's Gen 1 compositor historically selected its own model
  -- provider first, which let Battle Art suddenly replace CBE at 1x speed.
  -- In the delegated host, initialize the exact same CBE actor session here;
  -- Arena.render owns the draw pass below whenever COLOSSEUM MODELS is ON.
  if CurrentSpriteModels and cbePokemonModelsEnabled(ctx) and not standaloneContext(ctx) then
    local okModels,accepted=pcall(CurrentSpriteModels.begin,CurrentSpriteModels,ctx)
    if not okModels or accepted==false then
      log(ctx,"warn","delegated CBE Pokemon actor begin failed open: %s",tostring(accepted))
    end
  end
  updateAnchors(arena)
  return true
end
function A:update(ctx,dt,arena)
  sceneTime=sceneTime+(tonumber(dt) or 0)
  if Trainer then Trainer:update(ctx,dt) end
  if PlayerTrainer then PlayerTrainer:update(ctx,dt) end
  if CurrentSpriteModels and cbePokemonModelsEnabled(ctx) and not standaloneContext(ctx) then
    pcall(CurrentSpriteModels.update,CurrentSpriteModels,ctx,dt)
  end
  updateAnchors(arena)
end
function A:render(ctx,arena,drawActors)
  local s=loadScene(ctx); if not s then return V.FALLBACK end
  local w,h=pixelSize(); if not (w and h and w>0 and h>0) then return V.FALLBACK end
  local ok,out=pcall(ensureCanvas,w,h); if not ok then error(out) end
  local vp,pose=viewProjection(ctx,w,h)
  local model=Mat4.mul(Mat4.rotateY(STAGE_YAW),Mat4.scale(STAGE_SCALE,STAGE_SCALE,STAGE_SCALE))
  local actorVP=Mat4.mul(vp,Mat4.scale(figureScale,figureScale,figureScale))
  local prior=love.graphics.getCanvas(); local pushed=false
  local good,why=pcall(function()
    love.graphics.push("all"); pushed=true
    -- UI mods are allowed to draw in a scaled logical coordinate space. A
    -- Mobile Battle UI 0.5x transform leaking into this offscreen world pass
    -- shrinks CBE to exactly one quarter of the viewport at the top-left.
    -- Render the 3D environment from a clean pixel-space transform/scissor;
    -- push/pop restores the caller's HUD state immediately afterward.
    if love.graphics.origin then love.graphics.origin() end
    if love.graphics.setScissor then love.graphics.setScissor() end
    -- Bake the static sky BEFORE the arena framebuffer is bound, so the
    -- one-off canvas render never disturbs the live depth attachment.
    local baked=ensureBackdrop(w,h)
    local bound,bindErr=bindArenaCanvas(out)
    if not bound then error("arena framebuffer bind: "..tostring(bindErr)) end
    if depthActive then love.graphics.clear(0.025,0.075,0.145,1,true,true)
    else love.graphics.clear(0.025,0.075,0.145,1) end
    drawBackdrop(w,h,vp,baked)

    -- 1) True solid geometry and binary-alpha cutouts establish scene depth.
    setStageState(vp,model,true,pose)
    drawGroups(s.opaque)
    drawGroups(s.cutout)
    drawCrowd(s.crowd,vp,model,pose)

    -- 2) The boss trainer shadow is authored directly onto the Colosseum
    -- floor before any figures draw. It is deliberately separate from the
    -- StadiumBattleFX figure scale so a human actor never inherits Pokemon
    -- sizing.
    love.graphics.setShader()
    love.graphics.setColor(1,1,1,1)
    if PlayerTrainer then PlayerTrainer:drawShadow(ctx,vp,pose) end
    if Trainer then Trainer:drawShadow(ctx,vp,pose) end

    -- 3) StadiumBattleFX Pokemon are projected into this SAME depth buffer.
    -- actorVP applies their global figure scale without touching the trainer.
    love.graphics.setShader()
    love.graphics.setColor(1,1,1,1)
    local actorOk,actorErr
    if CurrentSpriteModels and cbePokemonModelsEnabled(ctx) then
      -- CBE model ownership is absolute inside a CBE arena.  Render the same
      -- CurrentSpriteModels service in both generations instead of accepting
      -- whichever model provider StadiumBattleFX happened to select for Gen 1.
      -- This decision depends only on battle/settings state, never battle speed.
      installActorServices(ctx,actorVP,vp,w,h,figureScale,pose)
      actorOk,actorErr=pcall(CurrentSpriteModels.drawWorld,CurrentSpriteModels,ctx)
    else
      actorOk,actorErr=pcall(drawActors,{vp=actorVP,stageVP=vp,figureScale=figureScale,groundY=0,width=w,height=h})
    end
    if actorOk then renderErrors.actors=nil else
      renderErrors.actors=tostring(actorErr)
      -- Actor/MoveFX presentation must fail open INSIDE the already-rendered
      -- arena.  Aborting the whole canvas here exposed Gen2's black/native
      -- battle layer for one frame and turned transient FX faults into flashes.
      pcall(love.graphics.setShader);pcall(love.graphics.setDepthMode,"lequal",true)
      log(ctx,"warn","actor/MoveFX pass failed open: %s",tostring(actorErr))
    end

    -- 4) Boss trainer model: independent human scale, shared scene depth.
    local function safeTrainer(label,obj,method,...)
      if not (obj and type(obj[method])=="function") then return end
      local okT,errT=pcall(obj[method],obj,...)
      if okT then renderErrors[label]=nil else
        renderErrors[label]=tostring(errT);pcall(love.graphics.setShader);pcall(love.graphics.setDepthMode,"lequal",true)
        log(ctx,"warn","%s failed open: %s",label,tostring(errT))
      end
    end
    safeTrainer("playerTrainer",PlayerTrainer,"draw",ctx,vp,pose)
    safeTrainer("playerBall",PlayerTrainer,"drawBall",ctx,vp,pose)
    safeTrainer("enemyTrainer",Trainer,"draw",ctx,vp,pose)
    safeTrainer("enemyBall",Trainer,"drawBall",ctx,vp,pose)

    -- 5) Water/glass/NO_ZUPDATE material groups are camera-sorted and then
    -- composited without depth writes, preserving actors behind transparency.
    setStageState(vp,model,false,pose)
    drawTransparent(s.translucent,pose.eye)
    -- Source waterfall/highlight layers use additive energy. Treating their
    -- black background as alpha in 0.0.3 produced dark cards/slabs.
    drawAdditive(s.additive)

    love.graphics.setShader()
    love.graphics.setDepthMode()
    love.graphics.setCanvas(prior)
    love.graphics.pop(); pushed=false
  end)
  if not good then
    pcall(love.graphics.setCanvas,prior); pcall(love.graphics.setShader); pcall(love.graphics.setDepthMode)
    if pushed then pcall(love.graphics.pop) end
    error(why)
  end
  return out
end
function A:finish(ctx,reason)
  if Trainer then Trainer:finish(ctx,reason) end
  if PlayerTrainer then PlayerTrainer:finish(ctx,reason) end
end
function A:invalidate()
  canvas=nil;depthCanvas=nil;depthMode=nil;depthActive=false;cw=nil;ch=nil
  if backdropCanvas then pcall(function() if backdropCanvas.release then backdropCanvas:release() end end) end
  backdropCanvas=nil;backdropKey=nil
end
function A:resetRuntime()
  local released={}
  for id,s in pairs(residentScenes) do
    if s and not released[s] then releaseArenaScene(s);released[s]=true end
    residentScenes[id]=nil;residentUse[id]=nil
  end
  if scene and not released[scene] then releaseArenaScene(scene) end
  pcall(function() if shader and shader.release then shader:release() end end)
  pcall(function() if white and white.release then white:release() end end)
  pcall(function() if canvas and canvas.release then canvas:release() end end)
  pcall(function() if depthCanvas and depthCanvas.release then depthCanvas:release() end end)
  pcall(function() if backdropCanvas and backdropCanvas.release then backdropCanvas:release() end end)
  backdropCanvas=nil;backdropKey=nil
  scene=nil;shader=nil;white=nil;canvas=nil;depthCanvas=nil;depthMode=nil;depthActive=false;cw=nil;ch=nil;errorText=nil;renderErrors={};sceneTime=0
  uniformCache=nil;uniformCacheShader=nil
  residentScenes={};residentUse={};residentSerial=0;activeDef=nil;activeArenaId="water"
  if Trainer and type(Trainer.resetRuntime)=="function" then pcall(Trainer.resetRuntime,Trainer) end
  if PlayerTrainer and type(PlayerTrainer.resetRuntime)=="function" then pcall(PlayerTrainer.resetRuntime,PlayerTrainer) end
  return true
end
function A:status()
  return {
    ready=scene~=nil,error=errorText,renderErrors=renderErrors,
    opaque=scene and #scene.opaque or 0,
    cutout=scene and #scene.cutout or 0,
    crowd=scene and #scene.crowd or 0,
    translucent=scene and #scene.translucent or 0,
    additive=scene and #scene.additive or 0,
    stageScale=STAGE_SCALE,figureScale=figureScale,triangleRadiusRaw=BATTLE_VERTEX_RADIUS_RAW,culled=scene and scene.culled or 0,
    oversizeCulled=scene and scene.oversizeCulled or 0,
    crowdKept=scene and scene.crowdKept or 0,
    crowdOriginal=scene and scene.crowdOriginal or 0,
    crowdPolicy=scene and scene.crowdPolicy or nil,
    crowdOutliers=scene and scene.crowdOutliers or 0,
    activeArena=activeArenaId,cache=activeDef and activeDef.cache or nil,profile=activeDef and activeDef.profile or nil,source=scene and scene.source or nil,framebufferMode=depthMode,depthActive=depthActive,android=ARENA_ANDROID,
    backdropBaked=backdropCanvas~=nil,backdropBakes=backdropBakes,
    residentScenes=residentCount(),residentLimit=RESIDENT_LIMIT,runtimeSidecar=scene and scene.runtimeSidecar==true or false,runtimeMeshHits=arenaRuntimeHits,runtimeMeshWrites=arenaRuntimeWrites,
  }
end
return A
