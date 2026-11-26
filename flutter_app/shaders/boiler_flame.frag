#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniform slots (6 floats strictly sequential):
// [0..1] uRes      : Logical widget size (width, height)
// [2]    uTime     : Continuous elapsed seconds
// [3]    uFlame    : Boiler modulation intensity (0.0 = pilot, 0.15..1.0 = active combustion)
// [4]    uTempNorm : Normalized target temp (0..1)
// [5]    uIsLight  : 0.0 dark UI, 1.0 light UI
uniform vec2 uRes;
uniform float uTime;
uniform float uFlame;
uniform float uTempNorm;
uniform float uIsLight;

out vec4 fragColor;

float invSmooth(float lo, float hi, float x) {
  return 1.0 - smoothstep(lo, max(hi, lo + 0.0001), x);
}

float hash21(vec2 p) {
  p = fract(p * vec2(127.1, 311.7));
  p += dot(p, p + 34.45);
  return fract(p.x * p.y);
}

float vnoise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(hash21(i), hash21(i + vec2(1.0, 0.0)), u.x),
    mix(hash21(i + vec2(0.0, 1.0)), hash21(i + vec2(1.0, 1.0)), u.x),
    u.y
  );
}

// 5-octave directional turbulent FBM
float fbm5(vec2 p) {
  float sum = 0.0;
  float amp = 0.50;
  mat2 rot = mat2(0.80, 0.60, -0.60, 0.80);
  for (int i = 0; i < 5; i++) {
    sum += amp * vnoise(p);
    p = rot * p * 2.05 + vec2(11.3, 17.7);
    amp *= 0.50;
  }
  return sum;
}

// Domain-warped volumetric flame plume density
float plumeTurbulence(vec2 p, float t, float speed) {
  vec2 q = vec2(
    fbm5(p * 1.35 + vec2(0.0, -t * speed * 0.85)),
    fbm5(p * 1.35 + vec2(5.2, -t * speed * 1.10 + 1.3))
  );
  vec2 r = vec2(
    fbm5(p * 1.9 + 1.8 * q + vec2(1.7, -t * speed * 1.35)),
    fbm5(p * 1.9 + 1.8 * q + vec2(8.3, -t * speed * 1.55))
  );
  return fbm5(p * 1.45 + 1.65 * r + vec2(0.0, -t * speed * 1.25));
}

// Glowing rising incandescent micro-embers inside convection draft
float emberLayer(vec2 p, float t, float speed, float gridScale, float density) {
  vec2 sp = p * gridScale + vec2(sin(p.y * 5.0 + t * 2.1) * 0.35, -t * speed);
  vec2 id = floor(sp);
  vec2 gv = fract(sp) - 0.5;
  float rnd = hash21(id);
  float gate = step(1.0 - density, rnd);
  vec2 jitter = vec2(hash21(id + 13.7), hash21(id + 29.1)) - 0.5;
  float d = length(gv - jitter * 0.55);
  float flicker = 0.55 + 0.45 * sin(t * (7.0 + rnd * 9.0) + rnd * 40.0);
  return gate * exp(-d * d * 95.0) * flicker;
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uRes, vec2(1.0));
  // Centered coordinates: (-0.5..0.5), yUp positive upward, x right
  vec2 p = vec2(uv.x - 0.5, 0.5 - uv.y);
  float rDist = length(p);

  float isHeating = smoothstep(0.03, 0.14, uFlame);
  float heat = clamp(uFlame * 0.72 + uTempNorm * 0.28, 0.0, 1.0) * isHeating;
  float roar = smoothstep(0.28, 0.92, heat);

  // Dark brushed cast-iron boiler combustion chamber with subtle spherical reflection
  vec3 chamber = mix(vec3(0.012, 0.015, 0.024), vec3(0.030, 0.035, 0.048), invSmooth(0.0, 0.5, rDist));
  float glassSpec = pow(max(0.0, 1.0 - length(p - vec2(-0.18, 0.26)) * 2.8), 3.0) * mix(0.09, 0.18, uIsLight);
  chamber += vec3(0.70, 0.84, 1.0) * glassSpec;

  // Curved cast-iron multi-nozzle burner grate near bottom of dial
  float grateCurveY = -0.345 + 0.26 * p.x * p.x;
  float grateBand = exp(-pow(max(0.0, abs(p.y - grateCurveY)) * 68.0, 2.0)) * invSmooth(0.34, 0.42, abs(p.x));
  vec3 grateCol = vec3(0.11, 0.14, 0.20) + vec3(0.32, 0.14, 0.05) * heat * 0.55;
  chamber = mix(chamber, grateCol, grateBand * 0.85);

  // Height above the curved burner manifold
  float h = p.y - grateCurveY;

  vec3 fireCol = vec3(0.0);

  // 1. Standby Pilot Light (soft breathing cobalt-blue micro-flame when boiler is off)
  float pilotFade = 1.0 - isHeating;
  if (pilotFade > 0.01) {
    vec2 pp = vec2(p.x * 6.2, h * 4.4);
    float sway = sin(uTime * 3.8 + h * 12.0) * 0.06 * smoothstep(0.0, 0.5, h);
    pp.x += sway;
    float pMask = step(0.0, h) * exp(-pp.x * pp.x * 2.4) * invSmooth(0.04, 0.44, h + vnoise(pp * 3.0 - vec2(0.0, uTime * 3.2)) * 0.12);
    float pCore = exp(-dot(pp - vec2(0.0, 0.18), pp - vec2(0.0, 0.18)) * 5.0);
    vec3 pilotBlue = mix(vec3(0.06, 0.34, 0.96), vec3(0.28, 0.86, 1.0), clamp(pMask * 1.2, 0.0, 1.0));
    fireCol += pilotBlue * pMask * 1.15 * pilotFade;
    fireCol += vec3(0.86, 0.96, 1.0) * pCore * 0.85 * pilotFade;
    // Ambient cool pilot glow in dark chamber
    float pGlow = exp(-dot(p - vec2(0.0, -0.26), p - vec2(0.0, -0.26)) * 18.0);
    chamber += vec3(0.08, 0.38, 0.88) * pGlow * 0.30 * pilotFade;
  }

  // 2. Active Gas Burner (Blue Bunsen Nozzle Cones -> Roaring Volumetric Orange/Amber/White Fire)
  if (isHeating > 0.01) {
    // 9 individual premixed gas ports along the curved burner
    float portPattern = 0.55 + 0.45 * cos(p.x * 74.0);
    float manifoldWidth = invSmooth(0.14, 0.41, abs(p.x));

    // Inner Premixed Blue-Cyan Bunsen Cones anchored to burner grate
    float blueHeight = 0.14 + 0.16 * heat;
    float blueTurb = plumeTurbulence(vec2(p.x * 6.5, h * 4.5), uTime, 2.2 + heat * 1.8);
    float blueField = smoothstep(-0.02, 0.03, h) *
        invSmooth(0.0, blueHeight + 0.09 * blueTurb, h) *
        manifoldWidth *
        (0.50 + 0.50 * portPattern);
    float blueCore = blueField * (0.45 + 0.85 * blueTurb);

    vec3 bunsenOuter = vec3(0.05, 0.36, 1.0);
    vec3 bunsenInner = vec3(0.28, 0.88, 1.0);
    vec3 bunsenWhite = vec3(0.86, 0.97, 1.0);
    fireCol += mix(bunsenOuter, bunsenInner, smoothstep(0.15, 0.65, blueCore)) * blueCore * 1.15 * isHeating;
    fireCol += bunsenWhite * pow(max(0.0, blueCore), 2.3) * 0.72 * isHeating;

    // Volumetric Roaring Plume (grows rapidly as temperature / modulation increases)
    float plumeMaxH = 0.24 + 0.62 * heat;
    float taper = mix(0.39, 0.17, clamp(h / max(plumeMaxH, 0.01), 0.0, 1.0));
    float envX = invSmooth(taper * 0.25, taper + 0.10, abs(p.x));

    // Buoyant domain-warped turbulence rising upward
    float turb = plumeTurbulence(vec2(p.x * 3.8, h * 2.2), uTime, 1.8 + roar * 2.2);
    float fineTurb = fbm5(vec2(p.x * 8.5, h * 5.2 - uTime * (3.0 + roar * 2.8)));

    float vertFalloff = smoothstep(0.01, 0.12, h) * invSmooth(0.04, plumeMaxH + 0.20 * turb, h);
    float density = vertFalloff * envX * (0.42 + 0.92 * turb) * (0.65 + 0.55 * fineTurb);
    density = clamp(density * (0.45 + 1.15 * roar), 0.0, 1.45);

    // Physical Blackbody Fire Gradient: crimson wisps -> fiery orange -> golden amber -> white core
    vec3 colCrimson = vec3(0.68, 0.08, 0.01);
    vec3 colOrange = vec3(1.00, 0.36, 0.03);
    vec3 colAmber = vec3(1.00, 0.72, 0.14);
    vec3 colWhite = vec3(1.00, 0.96, 0.80);

    // Blue-to-amber thermal transition at burner root
    float rootBlueBlend = invSmooth(0.02, 0.18, h) * (1.0 - roar * 0.55);
    vec3 plumeCol = mix(colCrimson, colOrange, smoothstep(0.12, 0.45, density));
    plumeCol = mix(plumeCol, colAmber, smoothstep(0.42, 0.78, density));
    plumeCol = mix(plumeCol, colWhite, smoothstep(0.75, 1.15, density));
    plumeCol = mix(plumeCol, bunsenInner, rootBlueBlend * 0.72);

    // Roaring orange flames emerge cleanly when heat rises
    float flameMask = smoothstep(0.12, 0.82, density);
    fireCol += plumeCol * flameMask * (0.35 + 1.15 * roar) * isHeating;

    // Swirling Rising Incandescent Embers inside the chamber
    if (roar > 0.10) {
      float e1 = emberLayer(p - vec2(0.0, grateCurveY), uTime, 1.4 + roar * 1.4, 15.0, 0.18 * roar);
      float e2 = emberLayer(p - vec2(0.2, grateCurveY), uTime + 4.1, 2.0 + roar * 1.8, 22.0, 0.14 * roar);
      float sparkEnv = smoothstep(0.02, 0.15, h) * invSmooth(0.25, 0.84, h) * invSmooth(0.15, 0.45, abs(p.x));
      vec3 sparkCol = mix(vec3(1.0, 0.42, 0.08), vec3(1.0, 0.88, 0.45), clamp(e1 + e2, 0.0, 1.0));
      fireCol += sparkCol * (e1 * 1.3 + e2 * 1.1) * sparkEnv * roar * 1.6;
    }

    // Chamber optical heat bloom illuminating dark metal surroundings
    vec2 heatOrigin = vec2(0.0, -0.18 + 0.08 * roar);
    float chamberBloom = exp(-dot(p - heatOrigin, p - heatOrigin) * mix(9.0, 4.5, roar));
    vec3 bloomCol = mix(vec3(0.06, 0.42, 0.95), vec3(0.95, 0.34, 0.06), roar);
    chamber += bloomCol * chamberBloom * (0.28 + 0.32 * heat) * isHeating;
  }

  vec3 col = chamber + fireCol;

  // Soft smoky center legibility shield right behind target temperature text
  float textShield = invSmooth(0.04, 0.32, length(p - vec2(0.0, 0.02)));
  col = mix(col, col * 0.48 + vec3(0.015, 0.018, 0.025), textShield * 0.62);

  // Filmic tone compression (keeps luminous cores crisp without harsh clipping)
  col = 1.0 - exp(-col * 1.35);

  // Subtle recessed inner bevel shadow near edge of dial circle
  float bevelShadow = smoothstep(0.41, 0.50, rDist);
  col *= 1.0 - bevelShadow * 0.45;

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
