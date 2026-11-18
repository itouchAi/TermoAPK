import React, { useRef, useState } from 'react';
import { Flame, Minus, Plus } from 'lucide-react';
import {
  MAX_TEMP,
  MIN_TEMP,
  TEMP_STEP,
  BoilerTelemetry,
  LangCode,
  pointerOffsetToTemp,
  snapTemperature,
  tempToAngleDeg,
} from '../logic/thermostat';

interface RotaryDialProps {
  targetTemp: number;
  onChangeTarget: (next: number) => void;
  modeName: string;
  accentHex: string;
  boiler: BoilerTelemetry;
  lang: LangCode;
  sizePx?: number;
  compact?: boolean;
}

const TOTAL_TICKS = 45;

export const RotaryDial: React.FC<RotaryDialProps> = ({
  targetTemp,
  onChangeTarget,
  modeName,
  accentHex,
  boiler,
  lang,
  sizePx = 236,
  compact = false,
}) => {
  const dialRef = useRef<HTMLDivElement | null>(null);
  const [isDragging, setIsDragging] = useState(false);

  const activeAngle = tempToAngleDeg(targetTemp);

  const updateFromPointer = (clientX: number, clientY: number) => {
    const el = dialRef.current;
    if (!el) return;
    const rect = el.getBoundingClientRect();
    const cx = rect.left + rect.width / 2;
    const cy = rect.top + rect.height / 2;
    const next = pointerOffsetToTemp(clientX - cx, clientY - cy);
    if (Math.abs(next - targetTemp) >= 0.05) {
      onChangeTarget(next);
    }
  };

  const handlePointerDown = (e: React.PointerEvent<HTMLDivElement>) => {
    e.preventDefault();
    e.currentTarget.setPointerCapture(e.pointerId);
    setIsDragging(true);
    updateFromPointer(e.clientX, e.clientY);
  };

  const handlePointerMove = (e: React.PointerEvent<HTMLDivElement>) => {
    if (!isDragging) return;
    updateFromPointer(e.clientX, e.clientY);
  };

  const handlePointerUp = (e: React.PointerEvent<HTMLDivElement>) => {
    if (isDragging) {
      setIsDragging(false);
      if (e.currentTarget.hasPointerCapture(e.pointerId)) {
        e.currentTarget.releasePointerCapture(e.pointerId);
      }
    }
  };

  const handleKeyDown = (e: React.KeyboardEvent<HTMLDivElement>) => {
    if (e.key === 'ArrowUp' || e.key === 'ArrowRight') {
      e.preventDefault();
      onChangeTarget(snapTemperature(targetTemp + TEMP_STEP));
    } else if (e.key === 'ArrowDown' || e.key === 'ArrowLeft') {
      e.preventDefault();
      onChangeTarget(snapTemperature(targetTemp - TEMP_STEP));
    }
  };

  const innerDiameter = Math.round(sizePx * 0.76);
  const tickRadius = sizePx * 0.455;
  const knobRadius = innerDiameter * 0.39;

  return (
    <div className="flex flex-col items-center select-none">
      {/* Rotary Ring + Tactile Dial */}
      <div
        ref={dialRef}
        role="slider"
        tabIndex={0}
        aria-label={lang === 'tr' ? 'Hedef Termostat Sıcaklığı' : 'Target Thermostat Temperature'}
        aria-valuemin={MIN_TEMP}
        aria-valuemax={MAX_TEMP}
        aria-valuenow={targetTemp}
        aria-valuetext={`${targetTemp.toFixed(1)}°C, ${modeName}`}
        data-testid="thermostat-dial"
        onPointerDown={handlePointerDown}
        onPointerMove={handlePointerMove}
        onPointerUp={handlePointerUp}
        onPointerCancel={handlePointerUp}
        onKeyDown={handleKeyDown}
        style={{ width: sizePx, height: sizePx }}
        className="relative flex items-center justify-center touch-none cursor-grab active:cursor-grabbing rounded-full focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60"
      >
        {/* Ambient radial halo */}
        <div
          aria-hidden="true"
          className="absolute inset-2 rounded-full transition-colors duration-300 pointer-events-none"
          style={{
            background: `radial-gradient(circle at 50% 45%, ${accentHex}2a 0%, ${accentHex}0d 48%, transparent 72%)`,
            filter: 'blur(10px)',
          }}
        />

        {/* Segmented Perimeter Tick Ring */}
        <svg
          width={sizePx}
          height={sizePx}
          viewBox={`0 0 ${sizePx} ${sizePx}`}
          className="absolute inset-0 pointer-events-none"
          aria-hidden="true"
        >
          {Array.from({ length: TOTAL_TICKS }).map((_, idx) => {
            const tickDeg = -135 + (idx / (TOTAL_TICKS - 1)) * 270;
            const rad = ((tickDeg - 90) * Math.PI) / 180;
            const isLit = tickDeg <= activeAngle + 1.5;
            const isMajor = idx % 4 === 0;
            const len = isMajor ? 10 : 7;
            const rOuter = tickRadius;
            const rInner = tickRadius - len;
            const cx = sizePx / 2;
            const cy = sizePx / 2;
            const x1 = cx + Math.cos(rad) * rInner;
            const y1 = cy + Math.sin(rad) * rInner;
            const x2 = cx + Math.cos(rad) * rOuter;
            const y2 = cy + Math.sin(rad) * rOuter;

            return (
              <line
                key={idx}
                x1={x1}
                y1={y1}
                x2={x2}
                y2={y2}
                stroke={isLit ? accentHex : 'rgba(255,255,255,0.16)'}
                strokeWidth={isMajor ? 2.6 : 1.9}
                strokeLinecap="round"
                style={{
                  opacity: isLit ? 0.95 : 0.7,
                  transition: 'stroke 160ms ease',
                }}
              />
            );
          })}
        </svg>

        {/* Inner Brushed Dark Glass Dial Face */}
        <div
          style={{
            width: innerDiameter,
            height: innerDiameter,
            boxShadow: `0 18px 36px rgba(0,0,0,0.72), inset 0 1px 1px rgba(255,255,255,0.14), inset 0 -10px 24px rgba(0,0,0,0.65), 0 0 28px ${accentHex}22`,
          }}
          className="relative rounded-full bg-gradient-to-b from-[#23252d] via-[#17181f] to-[#0f1015] border border-white/10 flex flex-col items-center justify-center text-center pointer-events-none"
        >
          {/* Rotating Glowing Indicator Pill */}
          <div
            aria-hidden="true"
            className="absolute inset-0 flex items-center justify-center"
            style={{
              transform: `rotate(${activeAngle}deg)`,
              transition: isDragging ? 'none' : 'transform 220ms cubic-bezier(0.16, 1, 0.3, 1)',
            }}
          >
            <div
              style={{
                transform: `translateY(-${knobRadius}px)`,
                backgroundColor: accentHex,
                boxShadow: `0 0 12px ${accentHex}, 0 0 4px #ffffff`,
              }}
              className="w-[6px] h-[15px] rounded-full"
            />
          </div>

          <span
            className={`${
              compact ? 'text-[9px]' : 'text-[10px]'
            } font-semibold tracking-[0.14em] text-white/50 uppercase`}
          >
            {lang === 'tr' ? 'HEDEF TERMOSTAT' : 'TARGET THERMOSTAT'}
          </span>

          <span
            data-testid="dial-target-temp"
            className={`font-mono-num font-bold tracking-tight text-white leading-none my-1 ${
              compact ? 'text-[30px]' : 'text-[44px]'
            }`}
          >
            {targetTemp.toFixed(1)}°
          </span>

          <span
            data-testid="dial-mode-name"
            style={{ color: accentHex }}
            className={`${
              compact ? 'text-[9px]' : 'text-[11px]'
            } font-bold tracking-[0.1em] uppercase transition-colors duration-200`}
          >
            {modeName}
          </span>

          <div className="mt-1 flex items-center gap-1 text-[10px] font-medium text-white/55 font-mono-num">
            <Flame
              className="w-3 h-3 transition-colors"
              style={{ color: boiler.isHeating ? accentHex : 'rgba(255,255,255,0.32)' }}
            />
            <span>{lang === 'tr' ? boiler.statusTextTr : boiler.statusTextEn}</span>
          </div>
        </div>
      </div>

      {/* Tactile - / ±0.5°C / + Stepper Row */}
      <div className={`flex items-center justify-center gap-3.5 ${compact ? 'mt-1.5' : 'mt-3.5'}`}>
        <button
          type="button"
          onClick={() => onChangeTarget(snapTemperature(targetTemp - TEMP_STEP))}
          disabled={targetTemp <= MIN_TEMP}
          aria-label={lang === 'tr' ? 'Hedef sıcaklığı 0.5 derece azalt' : 'Decrease target temperature by 0.5°'}
          className={`${compact ? 'w-10 h-10' : 'w-11 h-11'} rounded-full bg-white/[0.06] hover:bg-white/[0.12] active:scale-95 disabled:opacity-35 border border-white/12 shadow-[0_6px_16px_rgba(0,0,0,0.45),inset_0_1px_0_rgba(255,255,255,0.14)] flex items-center justify-center text-white transition-all duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60`}
        >
          <Minus className="w-4 h-4" />
        </button>

        <span className="font-mono-num text-xs font-medium text-white/55 tracking-wide px-1 select-none">
          ±0.5°C
        </span>

        <button
          type="button"
          onClick={() => onChangeTarget(snapTemperature(targetTemp + TEMP_STEP))}
          disabled={targetTemp >= MAX_TEMP}
          aria-label={lang === 'tr' ? 'Hedef sıcaklığı 0.5 derece artır' : 'Increase target temperature by 0.5°'}
          className={`${compact ? 'w-10 h-10' : 'w-11 h-11'} rounded-full bg-white/[0.06] hover:bg-white/[0.12] active:scale-95 disabled:opacity-35 border border-white/12 shadow-[0_6px_16px_rgba(0,0,0,0.45),inset_0_1px_0_rgba(255,255,255,0.14)] flex items-center justify-center text-white transition-all duration-150 cursor-pointer focus-visible:outline-none focus-visible:ring-2 focus-visible:ring-white/60`}
        >
          <Plus className="w-4 h-4" />
        </button>
      </div>
    </div>
  );
};
