import React, { useState } from 'react';
import {
  CloudRain,
  CloudSun,
  Sun,
  Cloud,
  Wind,
  Droplets,
  Flame,
  Gauge,
  Check,
  ShieldCheck,
} from 'lucide-react';
import {
  BoilerTelemetry,
  LangCode,
  ScheduleSlot,
  snapTemperature,
} from '../logic/thermostat';

interface WeatherViewProps {
  lang: LangCode;
  locationName: string;
  isLandscape: boolean;
  onApplyEcoCompensation: () => void;
}

const FORECAST = [
  { dayTr: 'Bugün', dayEn: 'Today', date: '18 Kas', condTr: 'Parçalı Bulutlu', condEn: 'Partly Cloudy', high: 19, low: 12, rain: '—', icon: 'partly' },
  { dayTr: 'Yarın', dayEn: 'Tomorrow', date: '19 Kas', condTr: 'Güneşli', condEn: 'Sunny', high: 21, low: 13, rain: '—', icon: 'sun' },
  { dayTr: 'Cmt', dayEn: 'Sat', date: '20 Kas', condTr: 'Sağanak Yağış', condEn: 'Showers', high: 15, low: 9, rain: '%75', icon: 'rain' },
  { dayTr: 'Paz', dayEn: 'Sun', date: '21 Kas', condTr: 'Çok Bulutlu', condEn: 'Cloudy', high: 14, low: 8, rain: '%30', icon: 'cloud' },
  { dayTr: 'Pzt', dayEn: 'Mon', date: '22 Kas', condTr: 'Açık & Serin', condEn: 'Clear', high: 17, low: 10, rain: '—', icon: 'partly' },
] as const;

export const WeatherView: React.FC<WeatherViewProps> = ({
  lang,
  locationName,
  isLandscape,
  onApplyEcoCompensation,
}) => {
  const [selectedDay, setSelectedDay] = useState(0);
  const [autoCompensate, setAutoCompensate] = useState(true);

  const renderWeatherIcon = (kind: string) => {
    if (kind === 'sun') return <Sun className="w-5 h-5 text-amber-300" />;
    if (kind === 'rain') return <CloudRain className="w-5 h-5 text-sky-400" />;
    if (kind === 'cloud') return <Cloud className="w-5 h-5 text-slate-300" />;
    return <CloudSun className="w-5 h-5 text-sky-300" />;
  };

  return (
    <section
      aria-label={lang === 'tr' ? 'Bölgesel Hava Durumu' : 'Regional Weather Forecast'}
      className={`w-full h-full mx-auto px-4 py-2 overflow-y-auto no-scrollbar ${
        isLandscape ? 'max-w-5xl' : 'max-w-[440px]'
      }`}
    >
      <div className={`grid gap-3 ${isLandscape ? 'grid-cols-12 items-start' : 'grid-cols-1'}`}>
        {/* Current Conditions Summary */}
        <div
          className={`rounded-2xl bg-white/[0.05] backdrop-blur-md border border-white/10 p-4 flex flex-col gap-3 ${
            isLandscape ? 'col-span-5' : ''
          }`}
        >
          <div className="flex items-start justify-between">
            <div>
              <p className="text-xs text-sky-300/80 font-medium">{locationName}</p>
              <h2 className="text-base font-semibold text-white mt-0.5">
                {lang === 'tr' ? 'Dış Ortam & Hava Tahmini' : 'Outdoor Weather'}
              </h2>
            </div>
            <span className="font-mono-num text-3xl font-bold text-white">18.5°C</span>
          </div>

          <div className="flex items-center gap-4 text-xs text-white/70">
            <span className="flex items-center gap-1.5">
              <Droplets className="w-3.5 h-3.5 text-sky-400" />
              <span className="font-mono-num">%62</span>
            </span>
            <span className="text-white/20" aria-hidden="true">·</span>
            <span className="flex items-center gap-1.5">
              <Wind className="w-3.5 h-3.5 text-sky-300" />
              <span className="font-mono-num">14 km/s</span>
            </span>
          </div>

          <div className="pt-2 border-t border-white/10 flex items-center justify-between gap-2">
            <div className="text-xs text-white/70">
              {lang === 'tr' ? 'Dış Isı Kompanzasyonu' : 'Weather Compensation'}
            </div>
            <button
              type="button"
              onClick={() => {
                setAutoCompensate((v) => !v);
                onApplyEcoCompensation();
              }}
              aria-pressed={autoCompensate}
              className={`min-h-[36px] px-3 rounded-xl text-xs font-semibold transition-colors cursor-pointer ${
                autoCompensate
                  ? 'bg-sky-500/25 text-sky-200 border border-sky-400/40'
                  : 'bg-white/[0.06] text-white/60 border border-white/10'
              }`}
            >
              {autoCompensate ? (lang === 'tr' ? 'Aktif' : 'Active') : lang === 'tr' ? 'Kapalı' : 'Off'}
            </button>
          </div>
        </div>

        {/* 5-Day Forecast List */}
        <div
          className={`rounded-2xl bg-white/[0.045] backdrop-blur-md border border-white/10 divide-y divide-white/8 ${
            isLandscape ? 'col-span-7' : ''
          }`}
        >
          {FORECAST.map((item, idx) => {
            const active = selectedDay === idx;
            return (
              <button
                key={item.date}
                type="button"
                onClick={() => setSelectedDay(idx)}
                className={`w-full px-3.5 py-2.5 flex items-center justify-between text-left transition-colors cursor-pointer first:rounded-t-2xl last:rounded-b-2xl ${
                  active ? 'bg-sky-500/12' : 'hover:bg-white/[0.04]'
                }`}
              >
                <div className="flex items-center gap-3 min-w-0">
                  {renderWeatherIcon(item.icon)}
                  <div className="min-w-0">
                    <div className="text-xs font-semibold text-white truncate">
                      {lang === 'tr' ? item.dayTr : item.dayEn} · <span className="text-white/45 font-normal">{item.date}</span>
                    </div>
                    <div className="text-[11px] text-white/55 truncate">
                      {lang === 'tr' ? item.condTr : item.condEn}
                    </div>
                  </div>
                </div>
                <div className="flex items-center gap-3 font-mono-num text-xs shrink-0">
                  <span className="text-sky-300/75 w-8 text-right">{item.rain}</span>
                  <span className="text-white font-semibold">{item.high}°</span>
                  <span className="text-white/45">{item.low}°</span>
                </div>
              </button>
            );
          })}
        </div>
      </div>
    </section>
  );
};

interface ReportViewProps {
  lang: LangCode;
  roomTemp: number;
  targetTemp: number;
  boiler: BoilerTelemetry;
  isLandscape: boolean;
}

const HEAT_BLOCKS = [
  { hour: '00:00', temp: 19.2, active: false },
  { hour: '04:00', temp: 18.8, active: false },
  { hour: '08:00', temp: 21.0, active: true },
  { hour: '12:00', temp: 21.4, active: false },
  { hour: '16:00', temp: 21.6, active: true },
  { hour: '20:00', temp: 21.8, active: true },
];

export const ReportView: React.FC<ReportViewProps> = ({
  lang,
  roomTemp,
  targetTemp,
  boiler,
  isLandscape,
}) => {
  const [period, setPeriod] = useState<'day' | 'week' | 'month'>('day');
  const multiplier = period === 'day' ? 1 : period === 'week' ? 7 : 30;
  const gasM3 = ((boiler.isHeating ? 1.85 : 1.12) * multiplier).toFixed(2);
  const costTl = (parseFloat(gasM3) * 10.25).toFixed(2);

  return (
    <section
      aria-label={lang === 'tr' ? 'Tüketim ve Kombi Analitiği' : 'Consumption & Boiler Analytics'}
      className={`w-full h-full mx-auto px-4 py-2 overflow-y-auto no-scrollbar ${
        isLandscape ? 'max-w-5xl' : 'max-w-[440px]'
      }`}
    >
      <div className="flex items-center justify-between mb-2.5">
        <h2 className="text-[15px] font-semibold text-white">
          {lang === 'tr' ? '24s Sıcaklık & Tüketim Raporu' : '24h Heat & Usage Report'}
        </h2>
        <div className="flex items-center gap-1 p-0.5 rounded-xl bg-white/[0.06] border border-white/10 text-[11px]">
          {(['day', 'week', 'month'] as const).map((p) => (
            <button
              key={p}
              type="button"
              onClick={() => setPeriod(p)}
              className={`px-2.5 py-1 rounded-lg font-medium transition-colors cursor-pointer ${
                period === p ? 'bg-violet-500/35 text-white' : 'text-white/55 hover:text-white'
              }`}
            >
              {p === 'day' ? (lang === 'tr' ? 'Günlük' : 'Day') : p === 'week' ? (lang === 'tr' ? 'Haftalık' : 'Week') : lang === 'tr' ? 'Aylık' : 'Month'}
            </button>
          ))}
        </div>
      </div>

      <div className={`grid gap-3 ${isLandscape ? 'grid-cols-12' : 'grid-cols-1'}`}>
        {/* Consumption & Sensors */}
        <div className={`grid grid-cols-2 gap-2.5 ${isLandscape ? 'col-span-6' : ''}`}>
          <div className="rounded-2xl bg-white/[0.05] border border-white/10 p-3.5">
            <span className="text-[11px] text-white/50">{lang === 'tr' ? 'Sayaç Tüketimi' : 'Gas Usage'}</span>
            <div className="font-mono-num text-xl font-bold text-white mt-1">{gasM3} m³</div>
            <span className="text-[11px] text-violet-300/80">{lang === 'tr' ? 'Modülasyonlu' : 'Modulated'}</span>
          </div>
          <div className="rounded-2xl bg-white/[0.05] border border-white/10 p-3.5">
            <span className="text-[11px] text-white/50">{lang === 'tr' ? 'Tahmini Tutar' : 'Est. Cost'}</span>
            <div className="font-mono-num text-xl font-bold text-white mt-1">{costTl} ₺</div>
            <span className="text-[11px] text-emerald-300/80">~%28 {lang === 'tr' ? 'tasarruf' : 'saved'}</span>
          </div>
          <div className="rounded-2xl bg-white/[0.045] border border-white/10 p-3.5 flex items-center justify-between">
            <div>
              <span className="text-[11px] text-white/50">{lang === 'tr' ? 'Alev Gücü' : 'Flame'}</span>
              <div className="font-mono-num text-base font-bold text-white">%{boiler.flamePercent}</div>
            </div>
            <Flame className="w-5 h-5 text-amber-400" />
          </div>
          <div className="rounded-2xl bg-white/[0.045] border border-white/10 p-3.5 flex items-center justify-between">
            <div>
              <span className="text-[11px] text-white/50">{lang === 'tr' ? 'Pompa / Basınç' : 'Pump / Press'}</span>
              <div className="font-mono-num text-sm font-bold text-white">
                {boiler.waterPressureBar} Bar · {boiler.pumpRpm}
              </div>
            </div>
            <Gauge className="w-5 h-5 text-violet-300" />
          </div>
        </div>

        {/* 24h Heat Map */}
        <div className={`rounded-2xl bg-white/[0.05] border border-white/10 p-3.5 ${isLandscape ? 'col-span-6' : ''}`}>
          <div className="flex items-center justify-between text-xs mb-2.5">
            <span className="font-medium text-white/85">{lang === 'tr' ? 'Saatlik Isı Dağılımı' : 'Hourly Heat Map'}</span>
            <span className="font-mono-num text-white/55">
              {roomTemp.toFixed(1)}° → {targetTemp.toFixed(1)}°
            </span>
          </div>
          <div className="grid grid-cols-3 gap-2">
            {HEAT_BLOCKS.map((blk) => (
              <div
                key={blk.hour}
                className={`rounded-xl p-2.5 border ${
                  blk.active ? 'bg-violet-500/18 border-violet-400/30' : 'bg-white/[0.03] border-white/8'
                }`}
              >
                <div className="font-mono-num text-[11px] text-white/55">{blk.hour}</div>
                <div className="font-mono-num text-sm font-bold text-white mt-0.5">{blk.temp.toFixed(1)}°</div>
                <div className="text-[10px] text-white/60 mt-0.5">
                  {blk.active ? (lang === 'tr' ? 'Aktif' : 'Active') : lang === 'tr' ? 'Bekleme' : 'Idle'}
                </div>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  );
};

interface ScheduleViewProps {
  lang: LangCode;
  slots: ScheduleSlot[];
  onUpdateSlot: (id: string, patch: Partial<ScheduleSlot>) => void;
  onSaveSchedule: () => void;
  savedNotice: boolean;
  isLandscape: boolean;
}

export const ScheduleView: React.FC<ScheduleViewProps> = ({
  lang,
  slots,
  onUpdateSlot,
  onSaveSchedule,
  savedNotice,
  isLandscape,
}) => {
  return (
    <section
      aria-label={lang === 'tr' ? 'Akıllı Haftalık Zaman Planı' : 'Smart Weekly Schedule'}
      className={`w-full h-full mx-auto px-4 py-2 overflow-y-auto no-scrollbar ${
        isLandscape ? 'max-w-5xl' : 'max-w-[440px]'
      }`}
    >
      <div className="flex items-center justify-between mb-2.5">
        <div>
          <h2 className="text-[15px] font-semibold text-white">
            {lang === 'tr' ? 'Akıllı Zamanlama' : 'Smart Schedule'}
          </h2>
          <p className="text-[11px] text-white/50 flex items-center gap-1">
            <ShieldCheck className="w-3.5 h-3.5 text-emerald-400" />
            <span>{lang === 'tr' ? 'Cihaz hafızasına otomatik kaydedilir' : 'Saved locally to device'}</span>
          </p>
        </div>

        <button
          type="button"
          onClick={onSaveSchedule}
          className="min-h-[38px] px-3.5 rounded-xl bg-emerald-500/25 hover:bg-emerald-500/35 border border-emerald-400/40 text-emerald-100 text-xs font-semibold flex items-center gap-1.5 transition-colors cursor-pointer"
        >
          {savedNotice && <Check className="w-3.5 h-3.5" />}
          <span>{savedNotice ? (lang === 'tr' ? 'Kaydedildi' : 'Saved') : lang === 'tr' ? 'Kaydet' : 'Save'}</span>
        </button>
      </div>

      <div className={`grid gap-2.5 ${isLandscape ? 'grid-cols-2' : 'grid-cols-1'}`}>
        {slots.map((slot) => (
          <div
            key={slot.id}
            className="rounded-2xl bg-white/[0.05] backdrop-blur-md border border-white/10 px-3.5 py-2.5 flex items-center justify-between gap-2"
          >
            <div className="flex items-center gap-2.5 min-w-0">
              <button
                type="button"
                role="switch"
                aria-checked={slot.enabled}
                aria-label={`${lang === 'tr' ? slot.labelTr : slot.labelEn} ${lang === 'tr' ? 'durumu' : 'toggle'}`}
                onClick={() => onUpdateSlot(slot.id, { enabled: !slot.enabled })}
                className={`w-10 h-6 rounded-full p-0.5 transition-colors cursor-pointer shrink-0 ${
                  slot.enabled ? 'bg-emerald-500/80' : 'bg-white/15'
                }`}
              >
                <div
                  className={`w-5 h-5 rounded-full bg-white transition-transform ${
                    slot.enabled ? 'translate-x-4' : 'translate-x-0'
                  }`}
                />
              </button>
              <div className="min-w-0">
                <div className="text-xs font-semibold text-white truncate">
                  {lang === 'tr' ? slot.labelTr : slot.labelEn}
                </div>
                <input
                  type="time"
                  aria-label={`${lang === 'tr' ? slot.labelTr : slot.labelEn} saat`}
                  value={slot.time}
                  onChange={(e) => onUpdateSlot(slot.id, { time: e.target.value })}
                  className="font-mono-num text-[11px] text-white/65 bg-transparent border-0 p-0 focus:outline-none cursor-pointer"
                />
              </div>
            </div>

            <div className="flex items-center gap-1.5 shrink-0">
              <button
                type="button"
                aria-label={`${lang === 'tr' ? slot.labelTr : slot.labelEn} sıcaklık azalt`}
                onClick={() => onUpdateSlot(slot.id, { targetTemp: snapTemperature(slot.targetTemp - 0.5) })}
                className="w-8 h-8 rounded-lg bg-white/[0.06] hover:bg-white/[0.12] text-white text-sm font-bold cursor-pointer"
              >
                -
              </button>
              <span className="font-mono-num text-xs font-bold text-white w-12 text-center">
                {slot.targetTemp.toFixed(1)}°
              </span>
              <button
                type="button"
                aria-label={`${lang === 'tr' ? slot.labelTr : slot.labelEn} sıcaklık artır`}
                onClick={() => onUpdateSlot(slot.id, { targetTemp: snapTemperature(slot.targetTemp + 0.5) })}
                className="w-8 h-8 rounded-lg bg-white/[0.06] hover:bg-white/[0.12] text-white text-sm font-bold cursor-pointer"
              >
                +
              </button>
            </div>
          </div>
        ))}
      </div>
    </section>
  );
};
