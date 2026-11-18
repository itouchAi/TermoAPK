import React, { useEffect, useRef } from 'react';
import { Mic } from 'lucide-react';
import {
  TAB_META,
  TAB_XS,
  TabId,
  LangCode,
  FlowMove,
  clamp,
  lerp,
  computeFlowState,
  moveLength,
} from '../logic/thermostat';

interface FlowTabBarProps {
  activeTab: TabId;
  onSelectTab: (tab: TabId) => void;
  activeAccentRgb: [number, number, number];
  lang: LangCode;
  isLandscape: boolean;
  onOpenVoice: () => void;
  voiceOpen: boolean;
}

// Custom minimalist stroke icons matching Flow Tab Bar's pathLength draw animation
const TAB_ICONS: Record<TabId, React.ReactNode> = {
  termo: (
    <svg viewBox="0 0 44 44" aria-hidden="true">
      <path d="M10 34V20a12 12 0 0 1 24 0v14" pathLength={1} className="d" />
      <path d="M22 34v-8" pathLength={1} className="d" />
    </svg>
  ),
  hava: (
    <svg viewBox="0 0 44 44" aria-hidden="true">
      <path d="M15 28a7 7 0 0 1-.4-13.98A9 9 0 0 1 31.8 16a5.5 5.5 0 0 1 .2 11H15z" pathLength={1} className="d" />
      <path d="M14 34h16" pathLength={1} className="d" />
    </svg>
  ),
  rapor: (
    <svg viewBox="0 0 44 44" aria-hidden="true">
      <path d="M22 10a12 12 0 1 0 12 12" pathLength={1} className="d" />
      <path d="M26 8a10 10 0 0 1 10 10H26z" pathLength={1} className="d" />
    </svg>
  ),
  prog: (
    <svg viewBox="0 0 44 44" aria-hidden="true">
      <path d="M10 22a12 12 0 1 1 12 12" pathLength={1} className="d" />
      <path d="M22 15v7l5 4" pathLength={1} className="d" />
      <circle cx="12" cy="32" r="2" fill="currentColor" stroke="none" />
    </svg>
  ),
};

const VS = `#version 300 es
in vec2 a;
void main() {
  gl_Position = vec4(a, 0., 1.);
}`;

const FS = `#version 300 es
precision highp float;
uniform vec2 uRes;
uniform float uDpr;
uniform float uT;
uniform vec3 uView;
uniform vec3 uB;
uniform vec3 uAcc;
uniform vec3 uTap;
uniform float uSw;
uniform vec2 uFocal;
out vec4 o;

const float TAU = 6.2831853;
float sq(float x) { return x * x; }

float h21(vec2 p) {
  p = fract(p * vec2(123.34, 456.21));
  p += dot(p, p + 45.32);
  return fract(p.x * p.y);
}

float noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  f = f * f * (3. - 2. * f);
  return mix(
    mix(h21(i), h21(i + vec2(1., 0.)), f.x),
    mix(h21(i + vec2(0., 1.)), h21(i + 1.), f.x),
    f.y
  );
}

float fbm(vec2 p) {
  float s = 0., a = .5;
  for (int i = 0; i < 4; i++) {
    s += a * noise(p);
    p = mat2(1.6, 1.2, -1.2, 1.6) * p + 7.1;
    a *= .5;
  }
  return s;
}

float sdBox(vec2 p, vec2 b, float r) {
  vec2 q = abs(p) - b + r;
  return length(max(q, 0.)) + min(max(q.x, q.y), 0.) - r;
}

float smin(float a, float b, float k) {
  float h = clamp(.5 + .5 * (b - a) / k, 0., 1.);
  return mix(b, a, h) - k * h * (1. - h);
}

vec2 bead() {
  return vec2(uB.x, 572. - uB.y * 46.);
}

float shape(vec2 p) {
  float bar = sdBox(p - vec2(540., 600.), vec2(404., 62.), 46.);
  vec2 q = p - bead();
  float sx = uB.z;
  q.x /= sx;
  q.y *= mix(1., sx, .35);
  float bd = (length(q) - 46.) * min(1., 1. / mix(1., sx, .35));
  return smin(bar, bd, 38.);
}

vec3 bg(vec2 p, vec2 uv) {
  float ph = TAU * uT / 10.;
  vec3 c = vec3(.014, .014, .022);
  float aspect = uRes.x / max(uRes.y, 1.);
  vec2 auv = vec2((uv.x - .5) * aspect, uv.y - .5);

  float n = fbm(auv * 2.1 + vec2(cos(ph), sin(ph)) * .16);
  c += vec3(.045, .055, .105) * smoothstep(.32, .86, n) * .75;

  // Ambient thermal focal glow behind thermostat dial / main stage
  vec2 fd = (uv - uFocal) * vec2(aspect, 1.);
  c += uAcc * exp(-dot(fd, fd) / (2. * .32 * .32)) * .17;

  // Secondary opposing depth wash
  vec2 d2 = (uv - vec2(1. - uFocal.x, .82)) * vec2(aspect, 1.);
  c += uAcc.zxy * exp(-dot(d2, d2) / (2. * .42 * .42)) * .06;

  // Active bead underglow
  vec2 d = p - vec2(uB.x, 650.);
  c += uAcc * exp(-dot(d * vec2(1., 1.5), d * vec2(1., 1.5)) / (2. * 230. * 230.)) * .42;
  return c;
}

void main() {
  vec2 uv = vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y) / uRes;
  vec2 p = (vec2(gl_FragCoord.x, uRes.y - gl_FragCoord.y) / uDpr - uView.xy) / uView.z + vec2(540.);
  float d = shape(p);
  float e = 1.5;
  vec2 g = vec2(shape(p + vec2(e, 0.)) - d, shape(p + vec2(0., e)) - d) / e;
  float inM = smoothstep(.8, -.8, d);
  vec3 col = bg(p, uv);

  // Subtle shadow under the bar
  col *= 1. - .5 * exp(-max(d, 0.) / 34.) * (1. - inM) * smoothstep(520., 640., p.y + 40.);

  if (inM > 0.) {
    float edge = exp(d / 15.);
    vec2 off = -g * edge * 46.;
    vec3 fr = vec3(0.);
    for (int i = 0; i < 4; i++) {
      float an = float(i) * 1.5708 + .6;
      vec2 sp = p + off + vec2(cos(an), sin(an)) * 40.;
      fr += bg(sp, uv);
    }
    fr *= .25;
    vec3 glass = fr * .52 + vec3(.032, .032, .044);
    glass += fr * edge * .4;

    // Light source living inside the liquid glass bead
    vec2 b = bead();
    vec2 q = p - vec2(b.x, b.y + 10.);
    float l = length(q * vec2(1. / uB.z, 1.15));
    glass += uAcc * (exp(-l / 78.) * .52 + exp(-l / 26.) * .58 * uB.y) + vec3(1.) * exp(-l / 12.) * .14 * uB.y;

    // Tap ripple
    float r = length(p - vec2(uTap.x, 600.));
    glass += (uAcc * .6 + .2) * exp(-sq((r - 20. - uTap.y * 90.) / 3.)) * max(0., 1. - uTap.y / .45) * .22 * step(0., uTap.y);

    // Specular rim
    float rim = exp(-sq((d + 1.3) / 1.1));
    float lit = .2 + .8 * pow(clamp(dot(normalize(g + 1e-4), normalize(vec2(-.35, -.94))), 0., 1.), 1.4);
    glass += (vec3(1.) * .55 + uAcc * .35) * rim * lit;
    float ang = atan(g.y, g.x);
    glass += (.5 + .5 * cos(ang * 2. + p.x * .006 + vec3(0., 2.1, 4.2))) * rim * .16;

    // Soft light sweep across the glass after landing
    float sx = 136. + 808. * uSw + (p.y - 600.) * .7;
    glass += vec3(1.) * exp(-sq((p.x - sx) / 46.)) * sin(3.14159 * uSw) * .06;
    glass += vec3(1.) * .05 * smoothstep(-30., -4., d) * clamp((600. - p.y) / 62., 0., 1.);

    // Bead cap specular
    vec2 s = p - (b + vec2(-14., -20.) * uB.y);
    glass += vec3(1.) * exp(-dot(s * vec2(.6, 1.4), s * vec2(.6, 1.4)) / 60.) * .22 * uB.y;
    glass += (h21(p) - .5) * .012;
    col = mix(col, glass, inM);
  }

  // Balanced screen-space vignette
  float aspect = uRes.x / max(uRes.y, 1.);
  float distCenter = length((uv - .5) * vec2(aspect, 1.));
  col *= 1. - .28 * smoothstep(.42, 1.05, distCenter);
  col = 1. - exp(-col * 1.28);
  col += (h21(p + fract(uT * 7.)) - .5) / 255.;
  o = vec4(col, 1.);
}`;

export const FlowTabBar: React.FC<FlowTabBarProps> = ({
  activeTab,
  onSelectTab,
  activeAccentRgb,
  lang,
  isLandscape,
  onOpenVoice,
  voiceOpen,
}) => {
  const canvasRef = useRef<HTMLCanvasElement | null>(null);
  const stageRef = useRef<HTMLDivElement | null>(null);
  const voiceDockRef = useRef<HTMLDivElement | null>(null);
  const iconRefs = useRef<(HTMLDivElement | null)[]>([]);
  const labelRefs = useRef<(HTMLDivElement | null)[]>([]);

  const activeIndex = Math.max(0, TAB_META.findIndex((t) => t.id === activeTab));

  const stateRef = useRef<{
    cur: number;
    moves: FlowMove[];
    liveAccent: [number, number, number];
    smoothAccent: [number, number, number];
    isLandscape: boolean;
    lastInteractionTs: number;
  }>({
    cur: activeIndex,
    moves: [],
    liveAccent: activeAccentRgb,
    smoothAccent: activeAccentRgb,
    isLandscape,
    lastInteractionTs: 0,
  });

  // Track external activeTab or accent changes
  useEffect(() => {
    const st = stateRef.current;
    const now = performance.now() / 1000;
    if (activeIndex !== st.cur) {
      const fromAcc = [...st.smoothAccent] as [number, number, number];
      st.moves = [
        {
          ts: now,
          a: st.cur,
          b: activeIndex,
          d: moveLength(activeIndex - st.cur),
          fromAcc,
          toAcc: activeAccentRgb,
        },
      ];
      st.cur = activeIndex;
      st.lastInteractionTs = now;
    }
  }, [activeIndex, activeAccentRgb]);

  useEffect(() => {
    stateRef.current.liveAccent = activeAccentRgb;
    stateRef.current.lastInteractionTs = performance.now() / 1000;
  }, [activeAccentRgb]);

  useEffect(() => {
    stateRef.current.isLandscape = isLandscape;
  }, [isLandscape]);

  useEffect(() => {
    const canvas = canvasRef.current;
    const stage = stageRef.current;
    if (!canvas || !stage) return;

    const gl = canvas.getContext('webgl2', { antialias: false, preserveDrawingBuffer: false });
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    const DPR = Math.min(2, window.devicePixelRatio || 1);

    let program: WebGLProgram | null = null;
    const U: Record<string, WebGLUniformLocation | null> = {};

    if (gl) {
      const compileShader = (type: number, src: string) => {
        const shader = gl.createShader(type);
        if (!shader) return null;
        gl.shaderSource(shader, src);
        gl.compileShader(shader);
        if (!gl.getShaderParameter(shader, gl.COMPILE_STATUS)) {
          console.error(gl.getShaderInfoLog(shader));
        }
        return shader;
      };

      const vs = compileShader(gl.VERTEX_SHADER, VS);
      const fs = compileShader(gl.FRAGMENT_SHADER, FS);
      if (vs && fs) {
        program = gl.createProgram();
        if (program) {
          gl.attachShader(program, vs);
          gl.attachShader(program, fs);
          gl.linkProgram(program);
          gl.useProgram(program);
          const buf = gl.createBuffer();
          gl.bindBuffer(gl.ARRAY_BUFFER, buf);
          gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 3, -1, -1, 3]), gl.STATIC_DRAW);
          const al = gl.getAttribLocation(program, 'a');
          gl.enableVertexAttribArray(al);
          gl.vertexAttribPointer(al, 2, gl.FLOAT, false, 0, 0);
          ['uRes', 'uDpr', 'uT', 'uView', 'uB', 'uAcc', 'uTap', 'uSw', 'uFocal'].forEach((n) => {
            U[n] = gl.getUniformLocation(program!, n);
          });
        }
      }
    }

    let vw = window.innerWidth;
    let vh = window.innerHeight;
    let barCenterX = vw / 2;
    let barCenterY = vh - 40;
    let scale = 0.4;

    const computeLayout = () => {
      vw = window.innerWidth;
      vh = window.innerHeight;
      const landscape = vw > vh;
      const compactLandscape = landscape && vh < 480;
      const voiceSize = compactLandscape ? 42 : 50;
      const gap = landscape ? 12 : 10;
      const maxDockWidth = compactLandscape
        ? Math.min(vw - 40, 380)
        : landscape
          ? Math.min(vw - 40, 420)
          : Math.min(vw - 24, 430);
      const barPixelWidth = Math.max(220, maxDockWidth - voiceSize - gap);
      scale = barPixelWidth / 808;
      const barPixelHeight = 124 * scale;
      const bottomPad = compactLandscape ? 6 : 14;

      const dockStartX = (vw - (barPixelWidth + gap + voiceSize)) / 2;
      barCenterX = dockStartX + barPixelWidth / 2;
      barCenterY = vh - bottomPad - barPixelHeight / 2;

      const viewX = barCenterX;
      const viewY = barCenterY - 60 * scale;

      stage.style.transform = `translate(${viewX - 540}px, ${viewY - 540}px) scale(${scale})`;

      if (voiceDockRef.current) {
        const voiceLeft = dockStartX + barPixelWidth + gap;
        const voiceTop = barCenterY - voiceSize / 2;
        voiceDockRef.current.style.left = `${voiceLeft}px`;
        voiceDockRef.current.style.top = `${voiceTop}px`;
        voiceDockRef.current.style.width = `${voiceSize}px`;
        voiceDockRef.current.style.height = `${voiceSize}px`;
      }

      canvas.width = Math.round(vw * DPR);
      canvas.height = Math.round(vh * DPR);
    };

    computeLayout();
    window.addEventListener('resize', computeLayout);

    let rafId = 0;
    let lastDrawMs = 0;
    const startSec = performance.now() / 1000;

    const renderFrame = (nowMs: number) => {
      rafId = requestAnimationFrame(renderFrame);
      const st = stateRef.current;
      const nowSec = nowMs / 1000;
      const isAnimating =
        nowSec - st.lastInteractionTs < 1.8 ||
        (st.moves.length > 0 && nowSec < st.moves[st.moves.length - 1].ts + st.moves[st.moves.length - 1].d + 0.5);

      // Throttle idle nebula drift to ~20fps (zero frame drops on mobile/SwiftShader)
      if (!isAnimating && nowMs - lastDrawMs < 50) return;
      if (reduceMotion && lastDrawMs > 0 && !isAnimating) return;
      lastDrawMs = nowMs;

      // Smoothly converge live accent color
      st.smoothAccent = [
        lerp(st.smoothAccent[0], st.liveAccent[0], 0.14),
        lerp(st.smoothAccent[1], st.liveAccent[1], 0.14),
        lerp(st.smoothAccent[2], st.liveAccent[2], 0.14),
      ];

      const flow = computeFlowState(nowSec, st.moves, st.cur, st.smoothAccent);
      const t = reduceMotion ? 0 : nowSec - startSec;

      if (gl && program) {
        gl.viewport(0, 0, canvas.width, canvas.height);
        gl.uniform2f(U.uRes, canvas.width, canvas.height);
        gl.uniform1f(U.uDpr, DPR);
        gl.uniform1f(U.uT, t);
        gl.uniform3f(U.uView, barCenterX, barCenterY - 60 * scale, scale);
        gl.uniform3f(U.uB, flow.x, flow.rise, flow.sx);
        gl.uniform3fv(U.uAcc, flow.acc);
        gl.uniform3f(U.uTap, flow.tap[0], flow.tap[1], 0);
        gl.uniform1f(U.uSw, flow.sw);
        const focalX = st.isLandscape ? 0.28 : 0.5;
        const focalY = st.isLandscape ? 0.46 : 0.44;
        gl.uniform2f(U.uFocal, focalX, focalY);
        gl.drawArrays(gl.TRIANGLES, 0, 3);
      }

      // Synchronize SVG icons and labels inside the virtual 1080x1080 stage
      const BY = 600;
      TAB_META.forEach((_, i) => {
        const iconEl = iconRefs.current[i];
        const labelEl = labelRefs.current[i];
        const w = Math.pow(clamp(1 - Math.abs(flow.x - TAB_XS[i]) / 106), 1.5);
        const a = w * clamp(flow.rise);

        if (iconEl) {
          iconEl.style.transform = `translate(${TAB_XS[i] - 28}px, ${BY - 42 - 54 * a}px) scale(${1 + 0.12 * a})`;
          iconEl.style.opacity = String(lerp(0.52, 1, clamp(a * 1.3)));
          const dr = i === flow.cur ? flow.draw : 1;
          const strokes = iconEl.querySelectorAll<SVGElement>('.d');
          strokes.forEach((s) => {
            s.style.strokeDasharray = '1';
            s.style.strokeDashoffset = String(1 - dr);
          });
        }
        if (labelEl) {
          const la = Math.pow(clamp((a - 0.5) / 0.5), 1.4);
          const opacity = lerp(0.58, 1.0, la);
          const yOffset = BY + 14 - 16 * la;
          labelEl.style.opacity = String(opacity);
          labelEl.style.transform = `translate(${TAB_XS[i] - 85}px, ${yOffset}px)`;
          labelEl.style.filter = 'none';
        }
      });
    };

    rafId = requestAnimationFrame(renderFrame);

    return () => {
      cancelAnimationFrame(rafId);
      window.removeEventListener('resize', computeLayout);
    };
  }, []);

  const handleTabClick = (idx: number, id: TabId) => {
    const st = stateRef.current;
    const now = performance.now() / 1000;
    if (idx !== st.cur) {
      st.moves = [
        {
          ts: now,
          a: st.cur,
          b: idx,
          d: moveLength(idx - st.cur),
          fromAcc: [...st.smoothAccent] as [number, number, number],
          toAcc: TAB_META[idx].accentRgb,
        },
      ];
      st.cur = idx;
      st.lastInteractionTs = now;
    }
    onSelectTab(id);
  };

  return (
    <>
      {/* Full-screen WebGL2 atmospheric background + liquid glass Flow Tab Bar */}
      <canvas
        ref={canvasRef}
        data-testid="flow-tab-bar-canvas"
        className="fixed inset-0 w-full h-full pointer-events-none z-0"
        aria-hidden="true"
      />

      {/* Synchronized DOM Stage for Flow Tab Bar Icons, Labels & Accessible Touch Buttons */}
      <div
        ref={stageRef}
        className="fixed left-0 top-0 w-[1080px] h-[1080px] origin-[540px_540px] pointer-events-none z-30"
      >
        {TAB_META.map((tab, i) => (
          <div
            key={`label-${tab.id}`}
            ref={(el) => {
              labelRefs.current[i] = el;
            }}
            aria-hidden="true"
            className="absolute left-0 top-0 w-[170px] text-center font-semibold text-[26px] tracking-tight text-white whitespace-nowrap will-change-transform select-none"
          >
            {lang === 'tr' ? tab.labelTr : tab.labelEn}
          </div>
        ))}

        {TAB_META.map((tab, i) => (
          <div
            key={`icon-${tab.id}`}
            ref={(el) => {
              iconRefs.current[i] = el;
            }}
            aria-hidden="true"
            className="absolute left-0 top-0 w-[56px] h-[56px] text-white will-change-transform [&_svg]:w-[56px] [&_svg]:h-[56px] [&_svg]:fill-none [&_svg]:stroke-current [&_svg]:stroke-[2.5] [&_svg]:[stroke-linecap:round] [&_svg]:[stroke-linejoin:round]"
          >
            {TAB_ICONS[tab.id]}
          </div>
        ))}

        <nav aria-label={lang === 'tr' ? 'Sabit Alt Gezinme Barı' : 'Bottom Navigation Bar'}>
          {TAB_META.map((tab, i) => {
            const label = lang === 'tr' ? tab.labelTr : tab.labelEn;
            const isActive = tab.id === activeTab;
            return (
              <button
                key={tab.id}
                type="button"
                onClick={() => handleTabClick(i, tab.id)}
                aria-current={isActive ? 'page' : undefined}
                aria-label={label}
                style={{ left: `${TAB_XS[i] - 90}px`, top: '538px' }}
                className="pointer-events-auto absolute w-[180px] h-[124px] rounded-[46px] bg-transparent text-transparent cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
              >
                {label}
              </button>
            );
          })}
        </nav>
      </div>

      {/* Circular Voice Assistant Button matched next to the Flow Tab Bar (termostat.vercel.app layout) */}
      <div ref={voiceDockRef} className="fixed z-30 pointer-events-auto">
        <button
          type="button"
          onClick={onOpenVoice}
          aria-label={lang === 'tr' ? 'Sesli Komut Asistanı' : 'Voice Command Assistant'}
          aria-expanded={voiceOpen}
          className="w-full h-full rounded-full flex items-center justify-center bg-white/[0.07] hover:bg-white/[0.12] active:scale-95 backdrop-blur-xl border border-white/15 shadow-[0_8px_24px_rgba(0,0,0,0.45)] text-white/90 transition-all duration-150 focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60 cursor-pointer"
          style={{
            boxShadow: voiceOpen
              ? `0 0 20px rgba(${Math.round(activeAccentRgb[0] * 255)}, ${Math.round(activeAccentRgb[1] * 255)}, ${Math.round(activeAccentRgb[2] * 255)}, 0.45), inset 0 1px 0 rgba(255,255,255,0.22)`
              : '0 8px 24px rgba(0,0,0,0.45), inset 0 1px 0 rgba(255,255,255,0.16)',
          }}
        >
          <Mic className="w-5 h-5" />
        </button>
      </div>
    </>
  );
};
