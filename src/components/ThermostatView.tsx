import React from 'react';
import { Flame, Leaf, Moon, Zap, Droplets, Gauge } from 'lucide-react';
import {
  BoilerTelemetry,
  LangCode,
  PRESETS,
  PresetId,
  ThermostatPreset,
} from '../logic/thermostat';
import { RotaryDial } from './RotaryDial';

interface ThermostatViewProps {
  roomTemp: number;
  targetTemp: number;
  activePreset: PresetId | null;
  accentHex: string;
  boiler: BoilerTelemetry;
  lang: LangCode;
  isLandscape: boolean;
  viewportHeight: number;
  onChangeTarget: (next: number) => void;
  onSelectPreset: (preset: ThermostatPreset) => void;
}

const PRESET_ICONS: Record<PresetId, React.ReactNode> = {
  eko: <Leaf className="w-4 h-4" />,
  konfor: <Flame className="w-4 h-4" />,
  gece: <Moon className="w-4 h-4" />,
  boost: <Zap className="w-4 h-4" />,
};

export const ThermostatView: React.FC<ThermostatViewProps> = ({
  roomTemp,
  targetTemp,
  activePreset,
  accentHex,
  boiler,
  lang,
  isLandscape,
  viewportHeight,
  onChangeTarget,
  onSelectPreset,
}) => {
  const matchedPreset = PRESETS.find((p) => p.id === activePreset);
  const modeName = matchedPreset
    ? lang === 'tr'
      ? matchedPreset.modeNameTr
      : matchedPreset.modeNameEn
    : lang === 'tr'
      ? 'MANUEL MOD'
      : 'MANUAL MODE';

  // Responsive dial sizing so portrait and compact landscape phones both breathe cleanly
  const compactLandscape = isLandscape && viewportHeight < 480;
  const dialSize = isLandscape
    ? compactLandscape
      ? Math.max(140, Math.min(162, viewportHeight - 218))
      : Math.min(248, Math.max(196, viewportHeight - 230))
    : viewportHeight < 700
      ? 202
      : viewportHeight > 880
        ? 258
        : 228;

  const TelemetryStrip = (
    <div
      data-testid="telemetry-strip"
      className="w-full rounded-2xl bg-white/[0.045] backdrop-blur-md border border-white/10 shadow-[0_8px_24px_rgba(0,0,0,0.4),inset_0_1px_0_rgba(255,255,255,0.08)] px-3.5 py-2.5 flex items-center justify-between gap-2 text-xs"
    >
      <div className="flex items-center gap-1.5 whitespace-nowrap">
        <span className="text-white/45 font-medium">{lang === 'tr' ? 'ODA' : 'ROOM'}:</span>
        <span className="font-mono-num font-semibold text-white">{roomTemp.toFixed(1)}°C</span>
      </div>
      <span className="text-white/20" aria-hidden="true">|</span>
      <div className="flex items-center gap-1.5 whitespace-nowrap">
        <span className="text-white/45 font-medium">{lang === 'tr' ? 'BASINÇ' : 'PRESS'}:</span>
        <span className="font-mono-num font-semibold text-white">{boiler.waterPressureBar.toFixed(1)} Bar</span>
      </div>
      <span className="text-white/20" aria-hidden="true">|</span>
      <div className="flex items-center gap-1.5 whitespace-nowrap">
        <span className="text-white/45 font-medium">{lang === 'tr' ? 'HEDEF' : 'TARGET'}:</span>
        <span className="font-mono-num font-bold" style={{ color: accentHex }}>
          {targetTemp.toFixed(1)}°
        </span>
      </div>
    </div>
  );

  const PresetButtons = (gridColsClass: string) => (
    <div className={`grid ${gridColsClass} gap-2.5 w-full`} role="group" aria-label={lang === 'tr' ? 'Hazır Sıcaklık Modları' : 'Preset Modes'}>
      {PRESETS.map((preset) => {
        const isSelected = activePreset === preset.id;
        const label = lang === 'tr' ? preset.labelTr : preset.labelEn;
        return (
          <button
            key={preset.id}
            type="button"
            onClick={() => onSelectPreset(preset)}
            aria-pressed={isSelected}
            style={
              isSelected
                ? {
                    background: `linear-gradient(160deg, ${preset.accentHex}dd 0%, ${preset.accentHex}99 100%)`,
                    boxShadow: `0 8px 24px ${preset.accentHex}45, inset 0 1px 0 rgba(255,255,255,0.35)`,
                    borderColor: `${preset.accentHex}`,
                  }
                : undefined
            }
            className={`min-h-[58px] rounded-[20px] px-2 py-2.5 flex flex-col items-center justify-center gap-0.5 border transition-all duration-150 active:scale-[0.97] cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60 ${
              isSelected
                ? 'text-white font-semibold'
                : 'bg-white/[0.05] hover:bg-white/[0.09] border-white/10 text-white/80 shadow-[inset_0_1px_0_rgba(255,255,255,0.08)]'
            }`}
          >
            <span
              className="transition-colors"
              style={{ color: isSelected ? '#ffffff' : preset.accentHex }}
            >
              {PRESET_ICONS[preset.id]}
            </span>
            <span className="text-[11px] font-bold tracking-wider whitespace-nowrap">{label}</span>
            <span className="font-mono-num text-[11px] opacity-85">{preset.temp.toFixed(1)}°</span>
          </button>
        );
      })}
    </div>
  );

  // ---- LANDSCAPE MODE: Dynamic 2-Column Split Ergonomic Layout ----
  if (isLandscape) {
    return (
      <section
        aria-label={lang === 'tr' ? 'Termostat ve Kombi Ana Kontrol' : 'Thermostat Main Control'}
        className="w-full h-full max-w-5xl mx-auto px-4 md:px-8 flex items-center justify-center"
      >
        <div className="w-full grid grid-cols-12 gap-4 md:gap-8 items-center">
          {/* Left Stage: Rotary Dial + Stepper */}
          <div className="col-span-5 flex flex-col items-center justify-center">
            <RotaryDial
              targetTemp={targetTemp}
              onChangeTarget={onChangeTarget}
              modeName={modeName}
              accentHex={accentHex}
              boiler={boiler}
              lang={lang}
              sizePx={dialSize}
              compact={compactLandscape}
            />
          </div>

          {/* Right Stage: Telemetry Strip, 2x2 Presets, Boiler Micro-Metrics */}
          <div className="col-span-7 flex flex-col gap-3 max-w-lg w-full mx-auto">
            <div className="flex items-center justify-between px-0.5">
              <h2 className="text-sm md:text-base font-semibold tracking-tight text-white/95">
                {lang === 'tr' ? 'Termostat & Kombi Ana Kontrol' : 'Thermostat & Boiler Control'}
              </h2>
              <span className="text-xs text-white/45 font-mono-num">
                {boiler.isHeating ? (lang === 'tr' ? 'Kombi Aktif' : 'Heating') : lang === 'tr' ? 'Beklemede' : 'Idle'}
              </span>
            </div>

            {TelemetryStrip}

            {PresetButtons('grid-cols-2')}

            <div className="flex items-center justify-between px-3 py-2 rounded-xl bg-white/[0.03] border border-white/8 text-[11px] text-white/60">
              <div className="flex items-center gap-1.5">
                <Droplets className="w-3.5 h-3.5 text-sky-400/80" />
                <span>{lang === 'tr' ? 'Ortam Nemi' : 'Humidity'}:</span>
                <span className="font-mono-num text-white/90 font-semibold">%48</span>
              </div>
              <span className="text-white/20" aria-hidden="true">·</span>
              <div className="flex items-center gap-1.5">
                <Gauge className="w-3.5 h-3.5 text-amber-400/80" />
                <span>{lang === 'tr' ? 'Pompa' : 'Pump'}:</span>
                <span className="font-mono-num text-white/90 font-semibold">
                  {boiler.isHeating ? `${boiler.pumpRpm} RPM` : '0 RPM'}
                </span>
              </div>
            </div>
          </div>
        </div>
      </section>
    );
  }

  // ---- PORTRAIT MODE: Thumb-Zone Vertical Mobile Layout ----
  return (
    <section
      aria-label={lang === 'tr' ? 'Termostat ve Kombi Ana Kontrol' : 'Thermostat Main Control'}
      className="w-full h-full max-w-[440px] mx-auto px-4 flex flex-col justify-between py-2"
    >
      {/* Top Section Title & Live Telemetry Strip */}
      <div className="flex flex-col gap-2.5 shrink-0">
        <div className="flex items-center justify-between px-0.5">
          <h2 className="text-[15px] font-semibold tracking-tight text-white/95">
            {lang === 'tr' ? 'Termostat & Kombi Ana Kontrol' : 'Thermostat & Boiler Control'}
          </h2>
          <span className="text-[11px] text-white/45 font-mono-num">
            {boiler.isHeating ? (lang === 'tr' ? 'Kombi Aktif' : 'Heating') : lang === 'tr' ? 'Beklemede' : 'Idle'}
          </span>
        </div>

        {TelemetryStrip}
      </div>

      {/* Center Hero: Rotary Dial + Stepper */}
      <div className="flex-1 flex flex-col items-center justify-center min-h-0 py-1">
        <RotaryDial
          targetTemp={targetTemp}
          onChangeTarget={onChangeTarget}
          modeName={modeName}
          accentHex={accentHex}
          boiler={boiler}
          lang={lang}
          sizePx={dialSize}
          compact={viewportHeight < 700}
        />
      </div>

      {/* Lower Thumb Zone: 4 Preset Buttons + Subtle Hint */}
      <div className="flex flex-col gap-2 shrink-0 pb-1">
        {PresetButtons('grid-cols-4')}
        <p className="text-center text-[11px] text-white/45 leading-snug px-2">
          {lang === 'tr'
            ? 'Kadran üzerindeki renkli halkayı çevirerek veya +/- ile hedefi ayarlayın.'
            : 'Drag the colored ring on the dial or tap +/- to set target temperature.'}
        </p>
      </div>
    </section>
  );
};
