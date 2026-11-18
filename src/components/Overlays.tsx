import React, { useState } from 'react';
import { Mic, Send, X, MapPin, Globe, MoonStar } from 'lucide-react';
import { LangCode, parseVoiceCommand, VoiceCommandResult } from '../logic/thermostat';

interface VoiceSheetProps {
  open: boolean;
  onClose: () => void;
  lang: LangCode;
  accentHex: string;
  onExecuteResult: (res: VoiceCommandResult) => void;
}

const QUICK_COMMANDS_TR = [
  'Sıcaklığı 24 derece yap',
  'Eko moda geç',
  'Gece modu 18.5 derece',
  'Hava durumunu aç',
];

const QUICK_COMMANDS_EN = [
  'Set temperature to 24°',
  'Switch to Eco mode',
  'Comfort mode',
  'Open weather',
];

export const VoiceSheet: React.FC<VoiceSheetProps> = ({
  open,
  onClose,
  lang,
  accentHex,
  onExecuteResult,
}) => {
  const [input, setInput] = useState('');
  const [feedback, setFeedback] = useState<string | null>(null);

  if (!open) return null;

  const submitCommand = (cmd: string) => {
    const res = parseVoiceCommand(cmd);
    setFeedback(lang === 'tr' ? res.replyTr : res.replyEn);
    if (res.handled) {
      onExecuteResult(res);
    }
    setInput('');
  };

  return (
    <div
      className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-end justify-center p-3"
      role="dialog"
      aria-modal="true"
      aria-label={lang === 'tr' ? 'Sesli Komut Asistanı' : 'Voice Command Assistant'}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-[440px] max-h-[88dvh] overflow-y-auto rounded-3xl bg-[#111218]/95 border border-white/12 p-4 shadow-2xl flex flex-col gap-3"
      >
        <div className="flex items-center justify-between">
          <div className="flex items-center gap-2">
            <span
              className="w-8 h-8 rounded-full flex items-center justify-center"
              style={{ backgroundColor: `${accentHex}28`, color: accentHex }}
            >
              <Mic className="w-4 h-4" />
            </span>
            <h3 className="text-sm font-semibold text-white">
              {lang === 'tr' ? 'Sesli Komut Asistanı' : 'Voice Command Assistant'}
            </h3>
          </div>
          <button
            type="button"
            onClick={onClose}
            aria-label={lang === 'tr' ? 'Kapat' : 'Close'}
            className="w-9 h-9 rounded-full bg-white/[0.06] hover:bg-white/[0.12] flex items-center justify-center text-white/75 cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="flex flex-wrap gap-1.5">
          {(lang === 'tr' ? QUICK_COMMANDS_TR : QUICK_COMMANDS_EN).map((cmd) => (
            <button
              key={cmd}
              type="button"
              onClick={() => submitCommand(cmd)}
              className="px-3 py-1.5 rounded-xl bg-white/[0.06] hover:bg-white/[0.12] border border-white/10 text-xs text-white/85 cursor-pointer transition-colors"
            >
              {cmd}
            </button>
          ))}
        </div>

        {feedback && (
          <div className="rounded-xl bg-white/[0.05] border border-white/10 px-3 py-2 text-xs text-white/90">
            {feedback}
          </div>
        )}

        <form
          onSubmit={(e) => {
            e.preventDefault();
            submitCommand(input);
          }}
          className="flex items-center gap-2"
        >
          <input
            type="text"
            value={input}
            onChange={(e) => setInput(e.target.value)}
            placeholder={lang === 'tr' ? 'Örn: 23.5 derece yap...' : 'e.g. Set 23.5 degrees...'}
            aria-label={lang === 'tr' ? 'Komut metni' : 'Command text'}
            className="flex-1 h-11 rounded-xl bg-white/[0.06] border border-white/12 px-3 text-sm text-white placeholder:text-white/35 focus:outline-none focus:border-white/30"
          />
          <button
            type="submit"
            aria-label={lang === 'tr' ? 'Komutu uygula' : 'Apply command'}
            className="h-11 px-4 rounded-xl text-white font-semibold text-xs flex items-center gap-1.5 cursor-pointer"
            style={{ backgroundColor: accentHex }}
          >
            <Send className="w-3.5 h-3.5" />
            <span>{lang === 'tr' ? 'Uygula' : 'Run'}</span>
          </button>
        </form>
      </div>
    </div>
  );
};

interface SettingsSheetProps {
  open: boolean;
  onClose: () => void;
  lang: LangCode;
  onChangeLang: (lang: LangCode) => void;
  locationName: string;
  onChangeLocation: (loc: string) => void;
}

const LOCATIONS = ['Ev · İstanbul', 'Yazlık · İzmir', 'Ofis · Ankara'];

export const SettingsSheet: React.FC<SettingsSheetProps> = ({
  open,
  onClose,
  lang,
  onChangeLang,
  locationName,
  onChangeLocation,
}) => {
  if (!open) return null;

  return (
    <div
      className="fixed inset-0 z-50 bg-black/60 backdrop-blur-sm flex items-end justify-center p-3"
      role="dialog"
      aria-modal="true"
      aria-label={lang === 'tr' ? 'Sistem Ayarları' : 'System Settings'}
      onClick={onClose}
    >
      <div
        onClick={(e) => e.stopPropagation()}
        className="w-full max-w-[440px] max-h-[88dvh] overflow-y-auto rounded-3xl bg-[#111218]/95 border border-white/12 p-4 shadow-2xl flex flex-col gap-3.5"
      >
        <div className="flex items-center justify-between">
          <h3 className="text-sm font-semibold text-white">
            {lang === 'tr' ? 'Sistem & Cihaz Ayarları' : 'Device Settings'}
          </h3>
          <button
            type="button"
            onClick={onClose}
            aria-label={lang === 'tr' ? 'Kapat' : 'Close'}
            className="w-9 h-9 rounded-full bg-white/[0.06] hover:bg-white/[0.12] flex items-center justify-center text-white/75 cursor-pointer"
          >
            <X className="w-4 h-4" />
          </button>
        </div>

        <div className="flex flex-col gap-1.5">
          <span className="text-xs text-white/55 flex items-center gap-1.5">
            <MapPin className="w-3.5 h-3.5" />
            {lang === 'tr' ? 'Cihaz Konumu' : 'Location'}
          </span>
          <div className="grid grid-cols-3 gap-2">
            {LOCATIONS.map((loc) => (
              <button
                key={loc}
                type="button"
                onClick={() => onChangeLocation(loc)}
                className={`py-2 px-2 rounded-xl text-xs font-medium border cursor-pointer transition-colors ${
                  locationName === loc
                    ? 'bg-white/15 border-white/30 text-white'
                    : 'bg-white/[0.04] border-white/10 text-white/65 hover:text-white'
                }`}
              >
                {loc}
              </button>
            ))}
          </div>
        </div>

        <div className="flex items-center justify-between pt-2 border-t border-white/10">
          <span className="text-xs text-white/75 flex items-center gap-1.5">
            <Globe className="w-3.5 h-3.5" />
            {lang === 'tr' ? 'Arayüz Dili' : 'Language'}
          </span>
          <div className="flex items-center gap-1 p-0.5 rounded-xl bg-white/[0.06] border border-white/10">
            {(['tr', 'en'] as const).map((code) => (
              <button
                key={code}
                type="button"
                onClick={() => onChangeLang(code)}
                className={`px-3 py-1 rounded-lg text-xs font-semibold uppercase cursor-pointer ${
                  lang === code ? 'bg-white/20 text-white' : 'text-white/55'
                }`}
              >
                {code}
              </button>
            ))}
          </div>
        </div>
      </div>
    </div>
  );
};

interface AmbientOverlayProps {
  open: boolean;
  onClose: () => void;
  roomTemp: number;
  targetTemp: number;
  accentHex: string;
  lang: LangCode;
}

export const AmbientOverlay: React.FC<AmbientOverlayProps> = ({
  open,
  onClose,
  roomTemp,
  targetTemp,
  accentHex,
  lang,
}) => {
  if (!open) return null;

  return (
    <button
      type="button"
      onClick={onClose}
      aria-label={lang === 'tr' ? 'Ambiyans modundan çık' : 'Exit ambient mode'}
      className="fixed inset-0 z-50 bg-[#040406]/95 backdrop-blur-2xl flex flex-col items-center justify-center gap-3 text-center cursor-pointer"
    >
      <MoonStar className="w-7 h-7" style={{ color: accentHex }} />
      <div className="font-mono-num text-6xl font-bold text-white">{targetTemp.toFixed(1)}°</div>
      <div className="text-sm text-white/60 font-mono-num">
        {lang === 'tr' ? 'Oda Sıcaklığı' : 'Room'}: {roomTemp.toFixed(1)}°C
      </div>
      <span className="mt-4 text-xs text-white/40">
        {lang === 'tr' ? 'Çıkmak için ekrana dokunun' : 'Tap anywhere to return'}
      </span>
    </button>
  );
};
