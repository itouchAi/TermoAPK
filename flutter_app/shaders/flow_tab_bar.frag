#version 460 core
#include <flutter/runtime_effect.glsl>

// Uniform slots (total 20 floats, strictly sequential):
// [0..1]   uRes   : Canvas logical size (width, height)
// [2]      uT     : Elapsed time in seconds
// [3..5]   uView  : (barCenterX, barCenterY - 60.0 * scale, scale)
// [6..8]   uB     : (beadX, rise, stretchX)
// [9..11]  uAcc   : Active accent RGB (0..1)
// [12..14] uTap   : (tapX, tapAgeSec, 0.0)
// [15]     uSw    : Sweep progress (0..1)
// [16..17] uFocal : Normalized dial focal center (0..1, 0..1)
// [18..19] uTheme : (daylightMix 0..1, tactileWarmth 0..1)
uniform vec2 uRes;
uniform float uT;
uniform vec3 uView;
uniform vec3 uB;
uniform vec3 uAcc;
uniform vec3 uTap;
uniform float uSw;
uniform vec2 uFocal;
uniform vec2 uTheme;

out vec4 fragColor;

const float TAU = 6.2831853;

float sq(float x) {
  return x * x;
}

float h21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p);
  vec2 f = fract(p);
  f = f * f * (3.0 - 2.0 * f);
  return mix(
    mix(h21(i), h21(i + vec2(1.0, 0.0)), f.x),
    mix(h21(i + vec2(0.0, 1.0)), h21(i + 1.0), f.x),
    f.y
  );
}

float fbm(vec2 p) {
  float s = 0.0;
  float a = 0.5;
  for (int i = 0; i < 4; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p + 7.1;
    a *= 0.5;
  }
  return s;
}

float sdBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

float smin(float a, float b, float k) {
  float h = clamp(0.5 + 0.5 * (b - a) / k, 0.0, 1.0);
  return mix(b, a, h) - k * h * (1.0 - h);
}

vec2 bead() {
  return vec2(uB.x, 572.0 - uB.y * 46.0);
}

float shape(vec2 p) {
  float bar = sdBox(p - vec2(540.0, 600.0), vec2(404.0, 62.0), 46.0);
  vec2 q = p - bead();
  float sx = max(uB.z, 0.001);
  q.x /= sx;
  q.y *= mix(1.0, sx, 0.35);
  float bd = (length(q) - 46.0) * min(1.0, 1.0 / mix(1.0, sx, 0.35));
  return smin(bar, bd, 38.0);
}

vec3 bg(vec2 p, vec2 uv) {
  float ph = TAU * uT / 10.0;
  float day = clamp(uTheme.x, 0.0, 1.0);
  float warm = clamp(uTheme.y, 0.0, 1.0);

  vec3 darkBase = mix(vec3(0.014, 0.014, 0.022), vec3(0.028, 0.022, 0.018), warm);
  vec3 dayBase = vec3(0.76, 0.84, 0.94);
  vec3 c = mix(darkBase, dayBase, day);

  float aspect = uRes.x / max(uRes.y, 1.0);
  vec2 auv = vec2((uv.x - 0.5) * aspect, uv.y - 0.5);

  float n = fbm(auv * 2.1 + vec2(cos(ph), sin(ph)) * 0.16);
  vec3 darkMist = mix(vec3(0.045, 0.055, 0.105), vec3(0.085, 0.060, 0.035), warm);
  vec3 dayMist = vec3(0.14, 0.18, 0.24);
  c += mix(darkMist, dayMist, day) * smoothstep(0.32, 0.86, n) * mix(0.75, 0.45, day);

  vec2 fd = (uv - uFocal) * vec2(aspect, 1.0);
  c += uAcc * exp(-dot(fd, fd) / (2.0 * 0.38 * 0.38)) * mix(0.24, 0.15, day);

  vec2 d2 = (uv - vec2(1.0 - uFocal.x, 0.80)) * vec2(aspect, 1.0);
  c += uAcc.zxy * exp(-dot(d2, d2) / (2.0 * 0.44 * 0.44)) * 0.08;

  vec2 d = p - vec2(uB.x, 650.0);
  c += uAcc * exp(-dot(d * vec2(1.0, 1.5), d * vec2(1.0, 1.5)) / (2.0 * 230.0 * 230.0)) * mix(0.44, 0.25, day);
  return c;
}

void main() {
  vec2 pos = FlutterFragCoord().xy;
  vec2 uv = pos / max(uRes, vec2(1.0));
  float vScale = max(uView.z, 0.001);
  vec2 p = (pos - uView.xy) / vScale + vec2(540.0);
  float day = clamp(uTheme.x, 0.0, 1.0);

  float d = shape(p);
  float e = 1.5;
  vec2 g = vec2(shape(p + vec2(e, 0.0)) - d, shape(p + vec2(0.0, e)) - d) / e;
  float inM = smoothstep(0.8, -0.8, d);
  vec3 col = bg(p, uv);

  col *= 1.0 - mix(0.5, 0.22, day) * exp(-max(d, 0.0) / 34.0) * (1.0 - inM) * smoothstep(520.0, 640.0, p.y + 40.0);

  if (inM > 0.0) {
    float edge = exp(d / 15.0);
    vec2 off = -g * edge * 46.0;
    vec3 fr = vec3(0.0);
    for (int i = 0; i < 4; i++) {
      float an = float(i) * 1.5708 + 0.6;
      vec2 sp = p + off + vec2(cos(an), sin(an)) * 40.0;
      fr += bg(sp, uv);
    }
    fr *= 0.25;
    vec3 glassTint = mix(vec3(0.032, 0.032, 0.044), vec3(0.24, 0.27, 0.34), day);
    vec3 glass = fr * mix(0.52, 0.68, day) + glassTint;
    glass += fr * edge * 0.4;

    vec2 b = bead();
    vec2 q = p - vec2(b.x, b.y + 10.0);
    float l = length(q * vec2(1.0 / max(uB.z, 0.001), 1.15));
    glass += uAcc * (exp(-l / 78.0) * 0.52 + exp(-l / 26.0) * 0.58 * uB.y) + vec3(1.0) * exp(-l / 12.0) * 0.14 * uB.y;

    float r = length(p - vec2(uTap.x, 600.0));
    glass += (uAcc * 0.6 + 0.2) * exp(-sq((r - 20.0 - uTap.y * 90.0) / 3.0)) * max(0.0, 1.0 - uTap.y / 0.45) * 0.22 * step(0.0, uTap.y);

    float rim = exp(-sq((d + 1.3) / 1.1));
    float lit = 0.2 + 0.8 * pow(clamp(dot(normalize(g + 1e-4), normalize(vec2(-0.35, -0.94))), 0.0, 1.0), 1.4);
    glass += (vec3(1.0) * 0.55 + uAcc * 0.35) * rim * lit;
    float ang = atan(g.y, g.x);
    glass += (0.5 + 0.5 * cos(ang * 2.0 + p.x * 0.006 + vec3(0.0, 2.1, 4.2))) * rim * 0.16;

    float sx = 136.0 + 808.0 * uSw + (p.y - 600.0) * 0.7;
    glass += vec3(1.0) * exp(-sq((p.x - sx) / 46.0)) * sin(3.14159 * uSw) * 0.06;
    glass += vec3(1.0) * 0.05 * smoothstep(-30.0, -4.0, d) * clamp((600.0 - p.y) / 62.0, 0.0, 1.0);

    vec2 s = p - (b + vec2(-14.0, -20.0) * uB.y);
    glass += vec3(1.0) * exp(-dot(s * vec2(0.6, 1.4), s * vec2(0.6, 1.4)) / 60.0) * 0.22 * uB.y;
    glass += (h21(p) - 0.5) * 0.012;
    col = mix(col, glass, inM);
  }

  float aspect = uRes.x / max(uRes.y, 1.0);
  float distCenter = length((uv - 0.5) * vec2(aspect, 1.0));
  col *= 1.0 - mix(0.28, 0.10, day) * smoothstep(0.42, 1.05, distCenter);
  col = mix(1.0 - exp(-col * 1.28), clamp(col, 0.0, 1.0), day * 0.45);
  col += (h21(p + fract(uT * 7.0)) - 0.5) / 255.0;
  fragColor = vec4(col, 1.0);
}
