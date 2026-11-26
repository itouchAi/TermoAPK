#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniform slots (9 floats strictly sequential):
// [0..1] uRes      : Logical widget size (width, height)
// [2]    uTime     : Continuous elapsed seconds
// [3]    uFill     : Normalized liquid height (0.15 .. 0.90)
// [4]    uFlame    : Thermal agitation / bubble velocity (0..1)
// [5..7] uFluidRgb : Target thermal fluid tint RGB (0..1)
// [8]    uIsLight  : 0.0 dark UI, 1.0 light UI
uniform vec2 uRes;
uniform float uTime;
uniform float uFill;
uniform float uFlame;
uniform vec3 uFluidRgb;
uniform float uIsLight;

out vec4 fragColor;

float invSmooth(float lo, float hi, float x) {
  return 1.0 - smoothstep(lo, max(hi, lo + 0.0001), x);
}

float hash21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float causticPattern(vec2 p, float t) {
  vec2 q = p * 5.5;
  float c1 = sin(q.x + sin(q.y * 1.3 + t * 1.4) + t * 0.9);
  float c2 = cos(q.y * 1.2 - cos(q.x * 1.1 - t * 1.1) + t * 0.7);
  float ridge = 1.0 - clamp(abs(c1 + c2) * 0.5, 0.0, 1.0);
  return pow(max(0.0, ridge), 4.0);
}

void main() {
  vec2 uv = FlutterFragCoord().xy / max(uRes, vec2(1.0));
  vec2 p = vec2(uv.x - 0.5, 0.5 - uv.y); // yUp: -0.5 bottom .. +0.5 top
  float rDist = length(p);
  float y01 = clamp(1.0 - uv.y, 0.0, 1.0); // 0 bottom .. 1 top

  // Translucent dark/light spherical chamber backdrop
  float domeHl = invSmooth(0.0, 0.5, length(p - vec2(-0.14, 0.18)));
  vec3 bgDark = mix(vec3(0.032, 0.042, 0.068), vec3(0.075, 0.095, 0.135), domeHl);
  vec3 bgLight = mix(vec3(0.84, 0.89, 0.95), vec3(0.97, 0.99, 1.0), domeHl);
  vec3 bg = mix(bgDark, bgLight, uIsLight);

  // Dual interfering sloshing wave surfaces (back layer gives 3D depth)
  float amp = 0.020 + 0.014 * uFlame;
  float speed = 2.2 + 2.4 * uFlame;
  float wBack = uFill + amp * 0.85 * cos(p.x * 9.5 - uTime * speed * 0.90)
                      + amp * 0.35 * sin(p.x * 16.0 + uTime * speed * 1.35);
  float wFront = uFill + amp * sin(p.x * 8.2 + uTime * speed)
                       + amp * 0.42 * cos(p.x * 15.0 - uTime * speed * 1.25);

  float aa = 0.012;
  float inBack = invSmooth(wBack - aa, wBack + aa, y01);
  float inFront = invSmooth(wFront - aa, wFront + aa, y01);

  vec3 deepFluid = uFluidRgb * mix(0.28, 0.52, uIsLight);
  vec3 midFluid = uFluidRgb * 0.88;
  vec3 brightFluid = mix(uFluidRgb, vec3(1.0), 0.52);

  // Back fluid meniscus shadow
  vec3 col = mix(bg, deepFluid * 0.82, inBack * 0.65);

  // Front volumetric liquid body with depth absorption & animated thermal caustics
  if (inFront > 0.001) {
    float depthFrac = clamp((wFront - y01) / max(wFront, 0.05), 0.0, 1.0);
    vec3 liquid = mix(midFluid, deepFluid, smoothstep(0.0, 0.85, depthFrac));

    // Subsurface thermal caustics rippling upward
    float caust = causticPattern(p + vec2(0.0, -uTime * (0.12 + 0.18 * uFlame)), uTime * (1.0 + 0.8 * uFlame));
    liquid += brightFluid * caust * (0.28 + 0.32 * uFlame) * (1.0 - depthFrac * 0.45);

    // Rising translucent micro-bubbles when heating
    if (uFlame > 0.04) {
      vec2 bp = vec2(p.x * 14.0, (y01 - uTime * (0.24 + 0.30 * uFlame)) * 14.0);
      bp.x += sin(bp.y * 0.9 + uTime * 3.0) * 0.32;
      vec2 bid = floor(bp);
      vec2 bgv = fract(bp) - 0.5;
      float rnd = hash21(bid);
      float hasBubble = step(0.76 - 0.18 * uFlame, rnd);
      vec2 bOff = (vec2(hash21(bid + 4.3), hash21(bid + 9.1)) - 0.5) * 0.48;
      float bDist = length(bgv - bOff);
      float bRadius = 0.12 + 0.10 * hash21(bid + 19.7);
      float bubbleRing = invSmooth(bRadius, bRadius + 0.05, bDist) * smoothstep(bRadius * 0.35, bRadius * 0.88, bDist);
      float belowSurface = invSmooth(wFront - 0.04, wFront, y01);
      liquid += vec3(0.95, 0.98, 1.0) * hasBubble * bubbleRing * belowSurface * 0.55;
    }

    // Warm/cool ambient glow under surface
    liquid += uFluidRgb * exp(-depthFrac * 4.5) * 0.22;
    col = mix(col, liquid, inFront * mix(0.90, 0.84, uIsLight));
  }

  // Luminous refractive meniscus highlight line right along wave front
  float meniscus = exp(-pow(abs(y01 - wFront) * 95.0, 2.0));
  col += mix(brightFluid, vec3(1.0), 0.45) * meniscus * 0.85;

  // Spherical glass dome specular & Fresnel rim reflection
  float glassRim = smoothstep(0.39, 0.495, rDist);
  col += mix(uFluidRgb, vec3(1.0), 0.65) * glassRim * mix(0.28, 0.42, uIsLight);
  float topArcSpec = pow(max(0.0, 1.0 - length(p - vec2(-0.16, 0.28)) * 2.7), 3.0);
  col += vec3(1.0) * topArcSpec * mix(0.18, 0.40, uIsLight);

  // Soft legibility shield behind center temperature text
  float shield = invSmooth(0.03, 0.30, length(p - vec2(0.0, 0.01)));
  vec3 shieldTint = mix(vec3(0.04, 0.05, 0.08), vec3(0.95, 0.97, 1.0), uIsLight);
  col = mix(col, col * 0.62 + shieldTint * 0.38, shield * mix(0.45, 0.58, uIsLight));

  fragColor = vec4(clamp(col, 0.0, 1.0), 1.0);
}
