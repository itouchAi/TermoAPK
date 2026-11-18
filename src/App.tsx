import React, { useEffect, useMemo, useState } from 'react';
import { Flame, Monitor, Settings } from 'lucide-react';
import {
  DEFAULT_SCHEDULE,
  LangCode,
  PresetId,
  ScheduleSlot,
  TAB_META,
  TabId,
  ThermostatPreset,
  VoiceCommandResult,
  computeBoilerTelemetry,
  findMatchingPreset,
  resolveThermostatAccent,
  resolveThermostatAccentHex,
  snapTemperature,
} from './logic/thermostat';
import { FlowTabBar } from './components/FlowTabBar';
import { ThermostatView } from './components/ThermostatView';
import { ReportView, ScheduleView, WeatherView } from './components/SecondaryViews';
import { AmbientOverlay, SettingsSheet, VoiceSheet } from './components/Overlays';

const STORAGE_KEY = 'termostat_flow_state_v1';

interface PersistedState {
  targetTemp: number;
  activePreset: PresetId | null;
  lang: LangCode;
  locationName: string;
  schedule: ScheduleSlot[];
}

function loadInitialState(): PersistedState {
  try {
    const raw = localStorage.getItem(STORAGE_KEY);
    if (raw) {
      const parsed = JSON.parse(raw) as Partial<PersistedState>;
      return {
        targetTemp: typeof parsed.targetTemp === 'number' ? snapTemperature(parsed.targetTemp) : 22.5,
        activePreset: parsed.activePreset !== undefined ? parsed.activePreset : 'konfor',
        lang: parsed.lang === 'en' ? 'en' : 'tr',
        locationName: typeof parsed.locationName === 'string' ? parsed.locationName : 'Ev · İstanbul',
        schedule: Array.isArray(parsed.schedule) && parsed.schedule.length === 4 ? parsed.schedule : DEFAULT_SCHEDULE,
      };
    }
  } catch {
    // Ignore storage read issues
  }
  return {
    targetTemp: 22.5,
    activePreset: 'konfor',
    lang: 'tr',
    locationName: 'Ev · İstanbul',
    schedule: DEFAULT_SCHEDULE,
  };
}

export default function App() {
  const initial = useMemo(() => loadInitialState(), []);

  const [activeTab, setActiveTab] = useState<TabId>('termo');
  const [roomTemp] = useState<number>(21.8);
  const [targetTemp, setTargetTemp] = useState<number>(initial.targetTemp);
  const [activePreset, setActivePreset] = useState<PresetId | null>(initial.activePreset);
  const [lang, setLang] = useState<LangCode>(initial.lang);
  const [locationName, setLocationName] = useState<string>(initial.locationName);
  const [schedule, setSchedule] = useState<ScheduleSlot[]>(initial.schedule);
  const [savedNotice, setSavedNotice] = useState(false);

  const [voiceOpen, setVoiceOpen] = useState(false);
  const [settingsOpen, setSettingsOpen] = useState(false);
  const [ambientOpen, setAmbientOpen] = useState(false);

  const [viewport, setViewport] = useState(() => ({
    w: typeof window !== 'undefined' ? window.innerWidth : 390,
    h: typeof window !== 'undefined' ? window.innerHeight : 844,
  }));

  useEffect(() => {
    const onResize = () => {
      setViewport({ w: window.innerWidth, h: window.innerHeight });
    };
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);

  useEffect(() => {
    try {
      const payload: PersistedState = {
        targetTemp,
        activePreset,
        lang,
        locationName,
        schedule,
      };
      localStorage.setItem(STORAGE_KEY, JSON.stringify(payload));
    } catch {
      // Ignore storage write issues
    }
  }, [targetTemp, activePreset, lang, locationName, schedule]);

  const isLandscape = viewport.w > viewport.h;
  const compactLandscape = isLandscape && viewport.h < 480;

  const boiler = useMemo(() => computeBoilerTelemetry(roomTemp, targetTemp), [roomTemp, targetTemp]);

  const activeTabMeta = TAB_META.find((t) => t.id === activeTab) ?? TAB_META[0];
  const activeTabIndex = Math.max(0, TAB_META.findIndex((t) => t.id === activeTab));

  // On Termo tab, the WebGL background & Flow Tab Bar glow adapt to the active thermal mode;
  // on secondary tabs, they smoothly transition to that tab's signature color.
  const activeAccentRgb = useMemo<[number, number, number]>(() => {
    if (activeTab === 'termo') {
      return resolveThermostatAccent(targetTemp, activePreset);
    }
    return activeTabMeta.accentRgb;
  }, [activeTab, targetTemp, activePreset, activeTabMeta]);

  const activeAccentHex = useMemo(() => {
    if (activeTab === 'termo') {
      return resolveThermostatAccentHex(targetTemp, activePreset);
    }
    return activeTabMeta.accentHex;
  }, [activeTab, targetTemp, activePreset, activeTabMeta]);

  const handleChangeTarget = (next: number) => {
    const snapped = snapTemperature(next);
    setTargetTemp(snapped);
    const matched = findMatchingPreset(snapped);
    setActivePreset(matched ? matched.id : null);
  };

  const handleSelectPreset = (preset: ThermostatPreset) => {
    setTargetTemp(preset.temp);
    setActivePreset(preset.id);
  };

  const handleUpdateSlot = (id: string, patch: Partial<ScheduleSlot>) => {
    setSchedule((prev) => prev.map((s) => (s.id === id ? { ...s, ...patch } : s)));
  };

  const handleSaveSchedule = () => {
    setSavedNotice(true);
    setTimeout(() => setSavedNotice(false), 1800);
  };

  const handleVoiceExecute = (res: VoiceCommandResult) => {
    if (typeof res.newTargetTemp === 'number') {
      setTargetTemp(res.newTargetTemp);
      setActivePreset(res.newPreset ?? findMatchingPreset(res.newTargetTemp)?.id ?? null);
    }
    if (res.navigateTab) {
      setActiveTab(res.navigateTab);
    }
  };

  const bottomClearancePx = compactLandscape ? 68 : 76;

  return (
    <div
      data-active-tab={activeTab}
      data-orientation={isLandscape ? 'landscape' : 'portrait'}
      data-target-temp={targetTemp.toFixed(1)}
      className="relative w-full h-[100dvh] flex flex-col overflow-hidden text-white select-none"
    >
      {/* WebGL2 Flow Tab Bar & Unified Atmospheric Background */}
      <FlowTabBar
        activeTab={activeTab}
        onSelectTab={setActiveTab}
        activeAccentRgb={activeAccentRgb}
        lang={lang}
        isLandscape={isLandscape}
        onOpenVoice={() => setVoiceOpen(true)}
        voiceOpen={voiceOpen}
      />

      {/* Compact Mobile App Top Bar */}
      <header
        className={`relative z-20 w-full shrink-0 border-b border-white/8 bg-[#040406]/35 backdrop-blur-md ${
          compactLandscape ? 'h-10 px-4' : 'h-12 px-4'
        }`}
      >
        <div className="w-full h-full max-w-5xl mx-auto flex items-center justify-between gap-4">
          <div className="flex items-center gap-2.5 min-w-0">
            <div
              className={`${
                compactLandscape ? 'w-7 h-7' : 'w-8 h-8'
              } rounded-full flex items-center justify-center shrink-0 transition-colors duration-300`}
              style={{
                background: `linear-gradient(145deg, ${activeAccentHex}, ${activeAccentHex}aa)`,
                boxShadow: `0 0 16px ${activeAccentHex}55`,
              }}
              aria-hidden="true"
            >
              <Flame className="w-4 h-4 text-white" />
            </div>
            <div className="flex items-baseline gap-2 min-w-0 truncate">
              <h1 className="text-sm font-bold tracking-tight text-white whitespace-nowrap">
                Termostat
              </h1>
              <span className="text-xs text-white/50 truncate">{locationName}</span>
            </div>
          </div>

          <div className="flex items-center gap-1.5 shrink-0">
            <button
              type="button"
              onClick={() => setLang((prev) => (prev === 'tr' ? 'en' : 'tr'))}
              aria-label={lang === 'tr' ? 'Dili İngilizce yap' : 'Switch language to Turkish'}
              className="min-w-[44px] min-h-[38px] px-2.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.12] border border-white/10 text-xs font-semibold uppercase tracking-wide text-white/90 transition-colors cursor-pointer"
            >
              {lang.toUpperCase()}
            </button>

            <button
              type="button"
              onClick={() => setAmbientOpen(true)}
              aria-label={lang === 'tr' ? 'Ambiyans Ekran Modu' : 'Ambient Display Mode'}
              className="min-w-[40px] min-h-[38px] rounded-xl bg-white/[0.06] hover:bg-white/[0.12] border border-white/10 flex items-center justify-center text-white/80 hover:text-white transition-colors cursor-pointer"
            >
              <Monitor className="w-4 h-4" />
            </button>

            <button
              type="button"
              onClick={() => setSettingsOpen(true)}
              aria-label={lang === 'tr' ? 'Ayarlar' : 'Settings'}
              className="min-w-[40px] min-h-[38px] rounded-xl bg-white/[0.06] hover:bg-white/[0.12] border border-white/10 flex items-center justify-center text-white/80 hover:text-white transition-colors cursor-pointer"
            >
              <Settings className="w-4 h-4" />
            </button>
          </div>
        </div>
      </header>

      {/* Smooth Horizontal Sliding Page Container */}
      <main
        className="relative z-10 flex-1 min-h-0 overflow-hidden"
        style={{ paddingBottom: `${bottomClearancePx}px` }}
      >
        <div
          className="flex w-full h-full will-change-transform transition-transform duration-[380ms] ease-[cubic-bezier(0.22,1,0.36,1)]"
          style={{ transform: `translate3d(-${activeTabIndex * 100}%, 0, 0)` }}
        >
          <div className="w-full h-full shrink-0">
            <ThermostatView
              roomTemp={roomTemp}
              targetTemp={targetTemp}
              activePreset={activePreset}
              accentHex={activeAccentHex}
              boiler={boiler}
              lang={lang}
              isLandscape={isLandscape}
              viewportHeight={viewport.h}
              onChangeTarget={handleChangeTarget}
              onSelectPreset={handleSelectPreset}
            />
          </div>

          <div className="w-full h-full shrink-0">
            <WeatherView
              lang={lang}
              locationName={locationName}
              isLandscape={isLandscape}
              onApplyEcoCompensation={() => {
                setTargetTemp(20.0);
                setActivePreset('eko');
              }}
            />
          </div>

          <div className="w-full h-full shrink-0">
            <ReportView
              lang={lang}
              roomTemp={roomTemp}
              targetTemp={targetTemp}
              boiler={boiler}
              isLandscape={isLandscape}
            />
          </div>

          <div className="w-full h-full shrink-0">
            <ScheduleView
              lang={lang}
              slots={schedule}
              onUpdateSlot={handleUpdateSlot}
              onSaveSchedule={handleSaveSchedule}
              savedNotice={savedNotice}
              isLandscape={isLandscape}
            />
          </div>
        </div>
      </main>

      {/* Bottom Sheets & Ambient Mode */}
      <VoiceSheet
        open={voiceOpen}
        onClose={() => setVoiceOpen(false)}
        lang={lang}
        accentHex={activeAccentHex}
        onExecuteResult={handleVoiceExecute}
      />

      <SettingsSheet
        open={settingsOpen}
        onClose={() => setSettingsOpen(false)}
        lang={lang}
        onChangeLang={setLang}
        locationName={locationName}
        onChangeLocation={setLocationName}
      />

      <AmbientOverlay
        open={ambientOpen}
        onClose={() => setAmbientOpen(false)}
        roomTemp={roomTemp}
        targetTemp={targetTemp}
        accentHex={activeAccentHex}
        lang={lang}
      />
    </div>
  );
}
