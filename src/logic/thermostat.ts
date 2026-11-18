export type PresetId = 'eko' | 'konfor' | 'gece' | 'boost';
export type TabId = 'termo' | 'hava' | 'rapor' | 'prog';
export type LangCode = 'tr' | 'en';

export interface ThermostatPreset {
  id: PresetId;
  labelTr: string;
  labelEn: string;
  modeNameTr: string;
  modeNameEn: string;
  temp: number;
  accentRgb: [number, number, number];
  accentHex: string;
}

export interface ScheduleSlot {
  id: string;
  labelTr: string;
  labelEn: string;
  time: string;
  targetTemp: number;
  enabled: boolean;
}

export interface BoilerTelemetry {
  isHeating: boolean;
  flamePercent: number;
  pumpRpm: number;
  waterPressureBar: number;
  modulationActive: boolean;
  statusTextTr: string;
  statusTextEn: string;
}

export interface FlowMove {
  ts: number;
  a: number;
  b: number;
  d: number;
  fromAcc: [number, number, number];
  toAcc: [number, number, number];
}

export interface FlowTabState {
  x: number;
  rise: number;
  sx: number;
  acc: [number, number, number];
  tap: [number, number];
  sw: number;
  cur: number;
  draw: number;
}

export const MIN_TEMP = 10.0;
export const MAX_TEMP = 30.0;
export const TEMP_STEP = 0.5;
export const DIAL_START_DEG = -135;
export const DIAL_END_DEG = 135;

export const PRESETS: ThermostatPreset[] = [
  {
    id: 'eko',
    labelTr: 'EKO',
    labelEn: 'ECO',
    modeNameTr: 'EKO MODU',
    modeNameEn: 'ECO MODE',
    temp: 20.0,
    accentRgb: [0.22, 0.85, 0.58],
    accentHex: '#38d994',
  },
  {
    id: 'konfor',
    labelTr: 'KONFOR',
    labelEn: 'COMFORT',
    modeNameTr: 'KONFOR MODU',
    modeNameEn: 'COMFORT MODE',
    temp: 22.5,
    accentRgb: [1.0, 0.48, 0.14],
    accentHex: '#ff7a24',
  },
  {
    id: 'gece',
    labelTr: 'GECE',
    labelEn: 'NIGHT',
    modeNameTr: 'GECE MODU',
    modeNameEn: 'NIGHT MODE',
    temp: 18.5,
    accentRgb: [0.46, 0.48, 1.0],
    accentHex: '#757aff',
  },
  {
    id: 'boost',
    labelTr: 'BOOST',
    labelEn: 'BOOST',
    modeNameTr: 'BOOST MODU',
    modeNameEn: 'BOOST MODE',
    temp: 25.0,
    accentRgb: [1.0, 0.3, 0.28],
    accentHex: '#ff4d47',
  },
];

// Four tabs aligned to termostat.vercel.app bottom navigation
export const TAB_XS = [240, 440, 640, 840] as const;

export const TAB_META: Array<{
  id: TabId;
  labelTr: string;
  labelEn: string;
  accentRgb: [number, number, number];
  accentHex: string;
}> = [
  {
    id: 'termo',
    labelTr: 'Termo.',
    labelEn: 'Thermo',
    accentRgb: [1.0, 0.48, 0.14],
    accentHex: '#ff7a24',
  },
  {
    id: 'hava',
    labelTr: 'Hava',
    labelEn: 'Weather',
    accentRgb: [0.2, 0.72, 1.0],
    accentHex: '#33b8ff',
  },
  {
    id: 'rapor',
    labelTr: 'Rapor',
    labelEn: 'Report',
    accentRgb: [0.55, 0.4, 1.0],
    accentHex: '#8c66ff',
  },
  {
    id: 'prog',
    labelTr: 'Prog.',
    labelEn: 'Sched.',
    accentRgb: [0.25, 0.92, 0.65],
    accentHex: '#40eb9e',
  },
];

export const DEFAULT_SCHEDULE: ScheduleSlot[] = [
  { id: 'night', labelTr: 'Gece Modu', labelEn: 'Night Mode', time: '23:00', targetTemp: 19.0, enabled: true },
  { id: 'morning', labelTr: 'Sabah Modu', labelEn: 'Morning Mode', time: '06:30', targetTemp: 23.0, enabled: true },
  { id: 'away', labelTr: 'Dışarıda Modu', labelEn: 'Away Mode', time: '08:00', targetTemp: 17.5, enabled: true },
  { id: 'evening', labelTr: 'Akşam Konforu', labelEn: 'Evening Comfort', time: '18:30', targetTemp: 22.5, enabled: true },
];

export function clamp(v: number, a = 0, b = 1): number {
  return Math.min(b, Math.max(a, v));
}

export function lerp(a: number, b: number, u: number): number {
  return a + (b - a) * u;
}

export function snapTemperature(temp: number): number {
  const clamped = clamp(temp, MIN_TEMP, MAX_TEMP);
  return Math.round(clamped * 2) / 2;
}

export function tempToAngleDeg(temp: number): number {
  const norm = clamp((temp - MIN_TEMP) / (MAX_TEMP - MIN_TEMP), 0, 1);
  return lerp(DIAL_START_DEG, DIAL_END_DEG, norm);
}

export function pointerOffsetToTemp(dx: number, dy: number): number {
  // Angle in degrees where 0 = top (12 o'clock), +90 = right, -90 = left
  let deg = (Math.atan2(dx, -dy) * 180) / Math.PI;
  // Dead zone at the very bottom: clamp to nearest limit (-135 or +135)
  if (deg > DIAL_END_DEG) deg = DIAL_END_DEG;
  if (deg < DIAL_START_DEG) deg = DIAL_START_DEG;
  const norm = (deg - DIAL_START_DEG) / (DIAL_END_DEG - DIAL_START_DEG);
  return snapTemperature(lerp(MIN_TEMP, MAX_TEMP, norm));
}

export function findMatchingPreset(targetTemp: number): ThermostatPreset | null {
  return PRESETS.find((p) => Math.abs(p.temp - targetTemp) < 0.05) ?? null;
}

export function resolveThermostatAccent(targetTemp: number, activePreset: PresetId | null): [number, number, number] {
  if (activePreset) {
    const found = PRESETS.find((p) => p.id === activePreset);
    if (found) return found.accentRgb;
  }
  // Smooth thermal gradient for custom manual temperatures
  if (targetTemp <= 19.0) return [0.46, 0.48, 1.0];
  if (targetTemp <= 21.0) return [0.22, 0.85, 0.58];
  if (targetTemp <= 23.5) return [1.0, 0.48, 0.14];
  return [1.0, 0.3, 0.28];
}

export function resolveThermostatAccentHex(targetTemp: number, activePreset: PresetId | null): string {
  if (activePreset) {
    const found = PRESETS.find((p) => p.id === activePreset);
    if (found) return found.accentHex;
  }
  if (targetTemp <= 19.0) return '#757aff';
  if (targetTemp <= 21.0) return '#38d994';
  if (targetTemp <= 23.5) return '#ff7a24';
  return '#ff4d47';
}

export function computeBoilerTelemetry(roomTemp: number, targetTemp: number): BoilerTelemetry {
  const delta = targetTemp - roomTemp;
  if (delta <= 0.1) {
    return {
      isHeating: false,
      flamePercent: 0,
      pumpRpm: 0,
      waterPressureBar: 1.6,
      modulationActive: false,
      statusTextTr: 'Beklemede',
      statusTextEn: 'Standby',
    };
  }
  // Modulating boiler scales flame cleanly from 20% (fine maintenance) to 100% (boost delta >= 3.5°C)
  const flamePercent = Math.round(clamp(20 + (delta / 3.5) * 80, 20, 100));
  const pumpRpm = Math.round(1280 + (flamePercent / 100) * 1120);
  const modulationActive = flamePercent < 75;
  return {
    isHeating: true,
    flamePercent,
    pumpRpm,
    waterPressureBar: 1.6,
    modulationActive,
    statusTextTr: modulationActive ? `Modülasyon · %${flamePercent}` : `Yüksek Alev · %${flamePercent}`,
    statusTextEn: modulationActive ? `Modulating · ${flamePercent}%` : `High Flame · ${flamePercent}%`,
  };
}

export interface VoiceCommandResult {
  handled: boolean;
  newTargetTemp?: number;
  newPreset?: PresetId;
  navigateTab?: TabId;
  replyTr: string;
  replyEn: string;
}

export function parseVoiceCommand(rawText: string): VoiceCommandResult {
  const text = rawText.trim().toLocaleLowerCase('tr-TR');
  if (!text) {
    return {
      handled: false,
      replyTr: 'Bir komut yazın veya aşağıdan seçin.',
      replyEn: 'Type or choose a command below.',
    };
  }

  // Check temperature numeric command (e.g. "24 derece", "22.5 yap", "set 21")
  const tempMatch = text.match(/(\d{2}(?:[.,]\d)?)/);
  if (tempMatch && (text.includes('derece') || text.includes('yap') || text.includes('ayar') || text.includes('temp') || text.includes('set') || text.includes('°'))) {
    const parsed = parseFloat(tempMatch[1].replace(',', '.'));
    const snapped = snapTemperature(parsed);
    const preset = findMatchingPreset(snapped);
    return {
      handled: true,
      newTargetTemp: snapped,
      newPreset: preset?.id,
      navigateTab: 'termo',
      replyTr: `Hedef sıcaklık ${snapped.toFixed(1)}°C olarak ayarlandı.`,
      replyEn: `Target temperature set to ${snapped.toFixed(1)}°C.`,
    };
  }

  if (text.includes('eko') || text.includes('eco')) {
    return {
      handled: true,
      newTargetTemp: 20.0,
      newPreset: 'eko',
      navigateTab: 'termo',
      replyTr: 'Eko modu (20.0°C) etkinleştirildi.',
      replyEn: 'Eco mode (20.0°C) activated.',
    };
  }
  if (text.includes('konfor') || text.includes('comfort')) {
    return {
      handled: true,
      newTargetTemp: 22.5,
      newPreset: 'konfor',
      navigateTab: 'termo',
      replyTr: 'Konfor modu (22.5°C) etkinleştirildi.',
      replyEn: 'Comfort mode (22.5°C) activated.',
    };
  }
  if (text.includes('gece') || text.includes('night')) {
    return {
      handled: true,
      newTargetTemp: 18.5,
      newPreset: 'gece',
      navigateTab: 'termo',
      replyTr: 'Gece modu (18.5°C) etkinleştirildi.',
      replyEn: 'Night mode (18.5°C) activated.',
    };
  }
  if (text.includes('boost') || text.includes('hızlı') || text.includes('yüksek')) {
    return {
      handled: true,
      newTargetTemp: 25.0,
      newPreset: 'boost',
      navigateTab: 'termo',
      replyTr: 'Boost modu (25.0°C) etkinleştirildi.',
      replyEn: 'Boost mode (25.0°C) activated.',
    };
  }

  if (text.includes('hava') || text.includes('weather')) {
    return {
      handled: true,
      navigateTab: 'hava',
      replyTr: 'Hava durumu ekranına geçiliyor.',
      replyEn: 'Opening weather forecast.',
    };
  }
  if (text.includes('rapor') || text.includes('analiz') || text.includes('tüketim') || text.includes('report')) {
    return {
      handled: true,
      navigateTab: 'rapor',
      replyTr: 'Tüketim ve analiz raporuna geçiliyor.',
      replyEn: 'Opening consumption report.',
    };
  }
  if (text.includes('program') || text.includes('zaman') || text.includes('schedule')) {
    return {
      handled: true,
      navigateTab: 'prog',
      replyTr: 'Haftalık zaman programına geçiliyor.',
      replyEn: 'Opening weekly schedule.',
    };
  }

  return {
    handled: false,
    replyTr: 'Anlaşılamadı. Örnek: "23 derece yap", "Eko mod" veya "Hava durumu".',
    replyEn: 'Not recognized. Try "Set 23°", "Eco mode", or "Weather".',
  };
}

// ---- Flow Tab Bar liquid glass interpolation math (adapted from Flow_Tab_Bar_2fcaa832.html for 4 tabs)
const eOut = (u: number) => 1 - Math.pow(1 - clamp(u), 5);
const eIO = (u: number) => {
  const c = clamp(u);
  return c < 0.5 ? 4 * c * c * c : 1 - Math.pow(-2 * c + 2, 3) / 2;
};

export function moveLength(deltaTabs: number): number {
  const n = Math.abs(deltaTabs);
  return n <= 1 ? 0.65 : n <= 2 ? 0.8 : 0.95;
}

export function computeFlowState(
  t: number,
  moves: FlowMove[],
  activeIndex: number,
  liveAccent: [number, number, number]
): FlowTabState {
  if (moves.length === 0) {
    return {
      x: TAB_XS[activeIndex] ?? TAB_XS[0],
      rise: 1,
      sx: 1,
      acc: liveAccent,
      tap: [0, -1],
      sw: 0,
      cur: activeIndex,
      draw: 1,
    };
  }

  let x: number = TAB_XS[activeIndex] ?? TAB_XS[0];
  let rise = 1;
  let sx = 1;
  let acc: [number, number, number] = liveAccent;
  let tap: [number, number] = [0, -1];
  let sw = 0;
  let cur = activeIndex;
  let draw = 1;

  for (const m of moves) {
    if (t < m.ts) break;
    const rawK = (t - m.ts) / m.d;
    const u = eIO(rawK);
    const k = clamp(rawK);
    x = lerp(TAB_XS[m.a], TAB_XS[m.b], u);
    const dive = Math.sin(Math.PI * Math.min(1, k * 1.08));
    rise = 1 - 0.9 * Math.pow(dive, 0.7);
    if (k >= 1) {
      rise = 1 + 0.06 * Math.exp(-(t - m.ts - m.d) * 9) * Math.sin((t - m.ts - m.d) * 22);
    }
    sx = 1 + 0.55 * Math.sin(Math.PI * k) * (Math.abs(m.b - m.a) > 1 ? 1.25 : 1);
    acc = [
      lerp(m.fromAcc[0], m.toAcc[0], u),
      lerp(m.fromAcc[1], m.toAcc[1], u),
      lerp(m.fromAcc[2], m.toAcc[2], u),
    ];
    tap = [TAB_XS[m.b], t - m.ts];
    sw = clamp((t - m.ts - m.d * 0.9) / 0.9);
    cur = m.b;
    draw = k < 0.5 ? 1 - eIO((k - 0.25) / 0.25) : eOut((t - m.ts - m.d * 0.5) / 0.6);
  }

  // Once settled, keep acc synced smoothly to liveAccent (for thermostat mode changes on Tab 0)
  const last = moves[moves.length - 1];
  if (last && t >= last.ts + last.d + 0.25) {
    acc = liveAccent;
  }

  return { x, rise, sx, acc, tap, sw, cur, draw };
}
