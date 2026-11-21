import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../services/ai_call_service.dart';
import '../services/ambient_audio_service.dart';
import '../services/hardware_service.dart';
import '../services/notification_service.dart';
import '../services/voice_speech_service.dart';
import 'termo_bot.dart';

enum _CallPhase {
  ringing,
  answered,
  missed,
}

class AiPhoneCallOverlay extends StatefulWidget {
  final MascotCharacter character;
  final AiCallReason reason;
  final bool urgent;
  final int ringSeconds;
  final bool voiceBriefEnabled;
  final bool missedAlertEnabled;
  final bool hapticEnabled;
  final int hapticStrength;
  final String locationName;
  final String espDeviceId;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final SafetyGuardStatus safety;
  final LangCode lang;
  final ValueChanged<double> onAdjustTargetTemp;
  final VoidCallback onMissedCallNotify;
  final ValueChanged<String> onCloseWithOutcome;

  const AiPhoneCallOverlay({
    super.key,
    required this.character,
    required this.reason,
    required this.urgent,
    required this.ringSeconds,
    required this.voiceBriefEnabled,
    required this.missedAlertEnabled,
    required this.hapticEnabled,
    required this.hapticStrength,
    required this.locationName,
    required this.espDeviceId,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.safety,
    required this.lang,
    required this.onAdjustTargetTemp,
    required this.onMissedCallNotify,
    required this.onCloseWithOutcome,
  });

  @override
  State<AiPhoneCallOverlay> createState() => _AiPhoneCallOverlayState();
}

class _AiPhoneCallOverlayState extends State<AiPhoneCallOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulseCtrl;
  final TextEditingController _voiceCmdCtrl = TextEditingController();
  Timer? _tickTimer;
  Timer? _closeDelayTimer;

  _CallPhase _phase = _CallPhase.ringing;
  late int _ringRemaining;
  int _callSeconds = 0;
  int _spokenChars = 0;
  bool _speakerMuted = false;
  bool _listeningCommand = false;
  bool _ttsPlaying = false;
  String? _quickActionAck;
  String? _heardPreview;

  @override
  void initState() {
    super.initState();
    _ringRemaining = widget.ringSeconds.clamp(5, 30);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _startRingingHardware();
    _tickTimer = Timer.periodic(const Duration(seconds: 1), (_) => _onSecondTick());
  }

  void _startRingingHardware() {
    AmbientAudioService.startRingtone(urgent: widget.urgent);
    _pulseRingHaptic();
  }

  void _pulseRingHaptic() {
    if (!widget.hapticEnabled || _phase != _CallPhase.ringing) return;
    HardwareService.vibrateMs(
      widget.urgent ? 260 : 180,
      amplitude: HardwareService.scaledAmplitude(widget.urgent ? 240 : 195, widget.hapticStrength),
    );
  }

  String _fullTranscript(MascotMeta meta) {
    final base = AiCallService.buildVoiceScript(
      reason: widget.reason,
      assistantName: meta.name,
      locationName: widget.locationName,
      roomTemp: widget.roomTemp,
      targetTemp: widget.targetTemp,
      boiler: widget.boiler,
      safety: widget.safety,
      lang: widget.lang,
    );
    if (_quickActionAck != null && _quickActionAck!.isNotEmpty) {
      return '$base\n\n$_quickActionAck';
    }
    return base;
  }

  void _speakAloud(String text) {
    if (_speakerMuted) return;
    setState(() => _ttsPlaying = true);
    VoiceSpeechService.speak(
      text,
      lang: widget.lang,
      onComplete: () {
        if (mounted) setState(() => _ttsPlaying = false);
      },
    );
  }

  void _onSecondTick() {
    if (!mounted) return;
    if (_phase == _CallPhase.ringing) {
      if (_ringRemaining <= 1) {
        _handleMissedTimeout();
      } else {
        setState(() => _ringRemaining--);
        _pulseRingHaptic();
      }
      return;
    }

    if (_phase == _CallPhase.answered) {
      final meta = MascotMeta.of(widget.character);
      final totalLen = _fullTranscript(meta).length;
      setState(() {
        _callSeconds++;
        if (widget.voiceBriefEnabled && _spokenChars < totalLen) {
          _spokenChars = math.min(totalLen, _spokenChars + 38);
        }
      });
    }
  }

  void _handleMissedTimeout() {
    AmbientAudioService.stopRingtone();
    VoiceSpeechService.stopSpeaking();
    VoiceSpeechService.stopListening();
    _tickTimer?.cancel();
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        140,
        amplitude: HardwareService.scaledAmplitude(210, widget.hapticStrength),
      );
    }
    setState(() {
      _ringRemaining = 0;
      _phase = _CallPhase.missed;
      _listeningCommand = false;
      _ttsPlaying = false;
    });

    if (widget.missedAlertEnabled) {
      widget.onMissedCallNotify();
    }

    final tr = widget.lang == LangCode.tr;
    final ts = NotificationService.formatNowTime();
    final outcome = tr
        ? (widget.missedAlertEnabled ? '$ts · Cevapsız (Uyarı gönderildi)' : '$ts · Cevapsız')
        : (widget.missedAlertEnabled ? '$ts · Missed (Alert sent)' : '$ts · Missed');

    _closeDelayTimer = Timer(const Duration(milliseconds: 2100), () {
      if (mounted) widget.onCloseWithOutcome(outcome);
    });
  }

  void _answerCall() {
    if (_phase != _CallPhase.ringing) return;
    AmbientAudioService.stopRingtone();
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        60,
        amplitude: HardwareService.scaledAmplitude(170, widget.hapticStrength),
      );
    }
    AmbientAudioService.playCallChime(answered: true);

    final meta = MascotMeta.of(widget.character);
    final brief = AiCallService.buildVoiceScript(
      reason: widget.reason,
      assistantName: meta.name,
      locationName: widget.locationName,
      roomTemp: widget.roomTemp,
      targetTemp: widget.targetTemp,
      boiler: widget.boiler,
      safety: widget.safety,
      lang: widget.lang,
    );

    setState(() {
      _phase = _CallPhase.answered;
      _callSeconds = 0;
      _spokenChars = widget.voiceBriefEnabled ? 34 : 9999;
    });

    if (widget.voiceBriefEnabled && !_speakerMuted) {
      _speakAloud(brief);
    }
  }

  void _declineOrHangup() {
    AmbientAudioService.stopRingtone();
    VoiceSpeechService.stopSpeaking();
    VoiceSpeechService.stopListening();
    _tickTimer?.cancel();
    _closeDelayTimer?.cancel();
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        50,
        amplitude: HardwareService.scaledAmplitude(150, widget.hapticStrength),
      );
    }
    AmbientAudioService.playCallChime(answered: false);
    final tr = widget.lang == LangCode.tr;
    final ts = NotificationService.formatNowTime();
    final String outcome;
    if (_phase == _CallPhase.answered) {
      final dur = AiCallService.formatCallDuration(_callSeconds);
      outcome = tr ? '$ts · Cevaplandı ($dur)' : '$ts · Answered ($dur)';
    } else if (_phase == _CallPhase.missed) {
      outcome = tr
          ? (widget.missedAlertEnabled ? '$ts · Cevapsız (Uyarı gönderildi)' : '$ts · Cevapsız')
          : (widget.missedAlertEnabled ? '$ts · Missed (Alert sent)' : '$ts · Missed');
    } else {
      outcome = tr ? '$ts · Reddedildi' : '$ts · Declined';
    }
    widget.onCloseWithOutcome(outcome);
  }

  void _applyCallQuickTemp(double nextTemp, String ackTr, String ackEn) {
    final snapped = ThermostatMath.snapTemperature(nextTemp);
    widget.onAdjustTargetTemp(snapped);
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        45,
        amplitude: HardwareService.scaledAmplitude(145, widget.hapticStrength),
      );
    }
    final msg = widget.lang == LangCode.tr ? ackTr : ackEn;
    setState(() {
      _quickActionAck = msg;
      _spokenChars = 9999;
    });
    if (!_speakerMuted) {
      _speakAloud(msg.replaceAll('✓', '').trim());
    }
  }

  void _executeSpokenOrTypedCommand(String raw) {
    final res = ThermostatMath.parseVoiceCommand(
      raw,
      currentTargetTemp: widget.targetTemp,
    );
    final reply = widget.lang == LangCode.tr ? res.replyTr : res.replyEn;
    if (res.handled && res.newTargetTemp != null) {
      widget.onAdjustTargetTemp(res.newTargetTemp!);
      if (widget.hapticEnabled) {
        HardwareService.vibrateMs(
          50,
          amplitude: HardwareService.scaledAmplitude(155, widget.hapticStrength),
        );
      }
    }
    setState(() {
      _heardPreview = raw.trim().isNotEmpty ? '"${raw.trim()}"' : null;
      _quickActionAck = res.handled ? '✓ $reply' : reply;
      _spokenChars = 9999;
    });
    _voiceCmdCtrl.clear();
    if (!_speakerMuted) {
      _speakAloud(reply);
    }
  }

  Future<void> _toggleCallMic() async {
    if (_listeningCommand) {
      await VoiceSpeechService.stopListening();
      if (mounted) setState(() => _listeningCommand = false);
      return;
    }
    setState(() {
      _listeningCommand = true;
      _ttsPlaying = false;
      _heardPreview = widget.lang == LangCode.tr ? 'Dinleniyor...' : 'Listening...';
    });
    final ok = await VoiceSpeechService.startListening(
      lang: widget.lang,
      onResultText: (words) {
        if (mounted) {
          setState(() {
            _heardPreview = '"$words"';
            _voiceCmdCtrl.text = words;
          });
        }
      },
      onFinalResult: (words) {
        if (mounted) {
          setState(() => _listeningCommand = false);
          _executeSpokenOrTypedCommand(words);
        }
      },
      onStatusError: (err) {
        if (mounted) {
          setState(() {
            _listeningCommand = false;
            _quickActionAck = err;
          });
        }
      },
      onDone: () {
        if (mounted) setState(() => _listeningCommand = false);
      },
    );
    if (!ok && mounted) {
      setState(() => _listeningCommand = false);
    }
  }

  @override
  void dispose() {
    _tickTimer?.cancel();
    _closeDelayTimer?.cancel();
    _pulseCtrl.dispose();
    _voiceCmdCtrl.dispose();
    AmbientAudioService.stopRingtone();
    VoiceSpeechService.stopSpeaking();
    VoiceSpeechService.stopListening();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.lang == LangCode.tr;
    final meta = MascotMeta.of(widget.character);
    final accent = widget.urgent
        ? const Color(0xFFEF4444)
        : (_phase == _CallPhase.missed ? const Color(0xFFF59E0B) : const Color(0xFF10B981));
    final reasonText = AiCallService.reasonBadge(
      widget.reason,
      widget.boiler,
      widget.safety,
      widget.lang,
    );
    final fullScript = _fullTranscript(meta);
    final visibleScript = _phase == _CallPhase.answered
        ? (widget.voiceBriefEnabled
            ? fullScript.substring(0, math.min(_spokenChars, fullScript.length))
            : fullScript)
        : '';

    // Solid opaque radial gradient stops so nothing behind the call screen bleeds through
    final topGlowSolid = Color.alphaBlend(
      accent.withValues(alpha: 0.22),
      const Color(0xFF070C14),
    );

    return Positioned.fill(
      child: Material(
        color: const Color(0xFF04070D),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF04070D),
            gradient: RadialGradient(
              center: const Alignment(0, -0.35),
              radius: 1.2,
              colors: [
                topGlowSolid,
                const Color(0xFF070B12),
                const Color(0xFF030407),
              ],
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
                  child: Column(
                    children: [
                      // Top Header Status & Countdown Pill
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.wifi_calling_3_rounded, size: 14, color: accent),
                                const SizedBox(width: 6),
                                Text(
                                  widget.espDeviceId,
                                  style: const TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white70,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                            decoration: BoxDecoration(
                              color: accent.withValues(alpha: 0.18),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: accent.withValues(alpha: 0.45)),
                            ),
                            child: Text(
                              _phase == _CallPhase.ringing
                                  ? (tr ? 'Çalıyor · $_ringRemaining sn' : 'Ringing · ${_ringRemaining}s')
                                  : _phase == _CallPhase.answered
                                      ? (tr
                                          ? 'Görüşme · ${AiCallService.formatCallDuration(_callSeconds)}'
                                          : 'Connected · ${AiCallService.formatCallDuration(_callSeconds)}')
                                      : (tr ? 'Cevapsız Arama' : 'Missed Call'),
                              style: TextStyle(
                                fontSize: 11.5,
                                fontWeight: FontWeight.w800,
                                color: accent,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ),

                      Expanded(
                        child: SingleChildScrollView(
                          padding: const EdgeInsets.symmetric(vertical: 12),
                          child: Column(
                            children: [
                              const SizedBox(height: 6),
                              // Pulsing Caller Avatar
                              AnimatedBuilder(
                                animation: _pulseCtrl,
                                builder: (_, __) {
                                  final t = _pulseCtrl.value;
                                  return SizedBox(
                                    width: 148,
                                    height: 148,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (_phase != _CallPhase.missed)
                                          for (int r = 0; r < 2; r++)
                                            Transform.scale(
                                              scale: 0.88 + (((t + r * 0.5) % 1.0) * 0.52),
                                              child: Container(
                                                width: 108,
                                                height: 108,
                                                decoration: BoxDecoration(
                                                  shape: BoxShape.circle,
                                                  border: Border.all(
                                                    color: accent.withValues(
                                                      alpha: (1.0 - ((t + r * 0.5) % 1.0)) * 0.65,
                                                    ),
                                                    width: 2.2,
                                                  ),
                                                ),
                                              ),
                                            ),
                                        Container(
                                          width: 102,
                                          height: 102,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF0A0F1A),
                                            border: Border.all(color: accent, width: 2.5),
                                            boxShadow: [
                                              BoxShadow(
                                                color: accent.withValues(alpha: 0.35),
                                                blurRadius: 24,
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: Image.asset(
                                              meta.assetPath,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                color: meta.color.withValues(alpha: 0.22),
                                                child: Icon(meta.icon, size: 46, color: meta.color),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 10),
                              Text(
                                '${meta.name} · ${tr ? 'AI Kombi Asistanı' : 'AI Boiler Assistant'}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 21,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                widget.locationName,
                                style: TextStyle(
                                  fontSize: 13,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Call Reason Banner
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(color: accent.withValues(alpha: 0.42)),
                                ),
                                child: Text(
                                  reasonText,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w700,
                                    color: widget.urgent
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFF6EE7B7),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 12),

                              // Live Telemetry Snapshot Strip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1420),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                ),
                                child: Row(
                                  children: [
                                    _CallStatTile(
                                      label: tr ? 'ODA' : 'ROOM',
                                      value: '${widget.roomTemp.toStringAsFixed(1)}°',
                                      color: Colors.white,
                                    ),
                                    _CallStatTile(
                                      label: tr ? 'HEDEF' : 'TARGET',
                                      value: '${widget.targetTemp.toStringAsFixed(1)}°',
                                      color: const Color(0xFF38BDF8),
                                    ),
                                    _CallStatTile(
                                      label: tr ? 'ALEV' : 'FLAME',
                                      value: widget.boiler.isHeating
                                          ? '%${widget.boiler.flamePercent}'
                                          : (tr ? 'KAPALI/BEKLEME' : 'IDLE'),
                                      color: widget.boiler.isHeating ? const Color(0xFFFB923C) : Colors.white54,
                                    ),
                                    _CallStatTile(
                                      label: tr ? 'BASINÇ' : 'PRESS.',
                                      value: '${widget.boiler.waterPressureBar.toStringAsFixed(1)} Bar',
                                      color: widget.safety.lowPressure ? const Color(0xFFEF4444) : const Color(0xFF10B981),
                                    ),
                                  ],
                                ),
                              ),

                              // Answered Voice Equalizer + Transcript + Live Mic Voice Commands
                              if (_phase == _CallPhase.answered) ...[
                                const SizedBox(height: 12),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1524),
                                    borderRadius: BorderRadius.circular(18),
                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.42)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.graphic_eq_rounded, size: 17, color: Color(0xFF34D399)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              widget.voiceBriefEnabled
                                                  ? (tr ? 'Canlı AI Sesli Özet' : 'Live AI Voice Briefing')
                                                  : (tr ? 'Asistan Durum Raporu' : 'Assistant Status Briefing'),
                                              style: const TextStyle(
                                                fontSize: 12,
                                                fontWeight: FontWeight.w700,
                                                color: Color(0xFF6EE7B7),
                                              ),
                                            ),
                                          ),
                                          GestureDetector(
                                            onTap: () {
                                              final nextMuted = !_speakerMuted;
                                              setState(() => _speakerMuted = nextMuted);
                                              if (nextMuted) {
                                                VoiceSpeechService.stopSpeaking();
                                                setState(() => _ttsPlaying = false);
                                              } else {
                                                _speakAloud(fullScript.replaceAll('✓', '').trim());
                                              }
                                            },
                                            child: Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                              decoration: BoxDecoration(
                                                color: Colors.white.withValues(alpha: 0.06),
                                                borderRadius: BorderRadius.circular(10),
                                              ),
                                              child: Row(
                                                mainAxisSize: MainAxisSize.min,
                                                children: [
                                                  Icon(
                                                    _speakerMuted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                                                    size: 16,
                                                    color: _speakerMuted ? Colors.white38 : const Color(0xFF34D399),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _speakerMuted
                                                        ? (tr ? 'Sessiz' : 'Muted')
                                                        : (tr ? 'Sesli' : 'Voice'),
                                                    style: TextStyle(
                                                      fontSize: 10.5,
                                                      fontWeight: FontWeight.w700,
                                                      color: _speakerMuted ? Colors.white54 : const Color(0xFF6EE7B7),
                                                    ),
                                                  ),
                                                ],
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 10),
                                      AnimatedBuilder(
                                        animation: _pulseCtrl,
                                        builder: (_, __) {
                                          final phase = _pulseCtrl.value * math.pi * 2;
                                          final speaking = !_speakerMuted &&
                                              (_ttsPlaying || _listeningCommand || _spokenChars < fullScript.length);
                                          return SizedBox(
                                            height: 24,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                              children: List.generate(18, (idx) {
                                                final amp = speaking
                                                    ? 0.28 + 0.72 * (0.5 + 0.5 * math.sin(phase * 2.2 + idx * 0.7))
                                                    : 0.20;
                                                return Container(
                                                  width: 4,
                                                  height: 4 + amp * 18,
                                                  decoration: BoxDecoration(
                                                    color: (_listeningCommand
                                                            ? const Color(0xFFF87171)
                                                            : const Color(0xFF10B981))
                                                        .withValues(alpha: 0.85),
                                                    borderRadius: BorderRadius.circular(3),
                                                  ),
                                                );
                                              }),
                                            ),
                                          );
                                        },
                                      ),
                                      const SizedBox(height: 10),
                                      Text(
                                        visibleScript,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.white,
                                          height: 1.45,
                                        ),
                                      ),
                                      const SizedBox(height: 12),

                                      // In-Call Voice Command Mic + Text Bar
                                      GestureDetector(
                                        onTap: _toggleCallMic,
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                          decoration: BoxDecoration(
                                            color: _listeningCommand
                                                ? const Color(0xFFEF4444).withValues(alpha: 0.22)
                                                : const Color(0xFF10B981).withValues(alpha: 0.14),
                                            borderRadius: BorderRadius.circular(13),
                                            border: Border.all(
                                              color: _listeningCommand
                                                  ? const Color(0xFFF87171)
                                                  : const Color(0xFF10B981).withValues(alpha: 0.48),
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Icon(
                                                _listeningCommand ? Icons.stop_circle_rounded : Icons.mic_rounded,
                                                size: 20,
                                                color: _listeningCommand
                                                    ? const Color(0xFFF87171)
                                                    : const Color(0xFF34D399),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  _listeningCommand
                                                      ? (_heardPreview ?? (tr ? 'Dinleniyor...' : 'Listening...'))
                                                      : (tr
                                                          ? 'Sesle Komut Ver (örn. "Kombiyi kapat", "5 derece arttır")'
                                                          : 'Speak Command (e.g. "Turn off boiler", "Raise 5°")'),
                                                  style: const TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: Colors.white,
                                                  ),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: TextField(
                                              controller: _voiceCmdCtrl,
                                              style: const TextStyle(fontSize: 12, color: Colors.white),
                                              decoration: InputDecoration(
                                                isDense: true,
                                                hintText: tr
                                                    ? 'Veya yaz: Kombiyi kapat / Eko / Boost / +5°...'
                                                    : 'Or type: Boiler off / Eco / Boost...',
                                                hintStyle: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white.withValues(alpha: 0.42),
                                                ),
                                                filled: true,
                                                fillColor: Colors.white.withValues(alpha: 0.05),
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 9,
                                                ),
                                                border: OutlineInputBorder(
                                                  borderRadius: BorderRadius.circular(11),
                                                  borderSide: BorderSide(
                                                    color: Colors.white.withValues(alpha: 0.14),
                                                  ),
                                                ),
                                              ),
                                              onSubmitted: _executeSpokenOrTypedCommand,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          FilledButton(
                                            onPressed: () => _executeSpokenOrTypedCommand(_voiceCmdCtrl.text),
                                            style: FilledButton.styleFrom(
                                              backgroundColor: const Color(0xFF10B981),
                                              foregroundColor: Colors.white,
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                              shape: RoundedRectangleBorder(
                                                borderRadius: BorderRadius.circular(11),
                                              ),
                                            ),
                                            child: Text(
                                              tr ? 'Uygula' : 'Apply',
                                              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(
                                      child: _InCallQuickButton(
                                        icon: Icons.eco_rounded,
                                        label: tr ? 'Eko (20°C)' : 'Eco (20°C)',
                                        accent: const Color(0xFF38D994),
                                        onTap: () => _applyCallQuickTemp(
                                          20.0,
                                          '✓ Hedef sıcaklık Eko (20.0°C) moduna çekildi.',
                                          '✓ Target temperature set to Eco (20.0°C).',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _InCallQuickButton(
                                        icon: Icons.remove_rounded,
                                        label: '-0.5°C',
                                        accent: const Color(0xFF38BDF8),
                                        onTap: () => _applyCallQuickTemp(
                                          widget.targetTemp - 0.5,
                                          '✓ Hedef ${(widget.targetTemp - 0.5).toStringAsFixed(1)}°C olarak düşürüldü.',
                                          '✓ Target lowered to ${(widget.targetTemp - 0.5).toStringAsFixed(1)}°C.',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _InCallQuickButton(
                                        icon: Icons.add_rounded,
                                        label: '+0.5°C',
                                        accent: const Color(0xFFFB923C),
                                        onTap: () => _applyCallQuickTemp(
                                          widget.targetTemp + 0.5,
                                          '✓ Hedef ${(widget.targetTemp + 0.5).toStringAsFixed(1)}°C olarak yükseltildi.',
                                          '✓ Target raised to ${(widget.targetTemp + 0.5).toStringAsFixed(1)}°C.',
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              if (_phase == _CallPhase.missed) ...[
                                const SizedBox(height: 18),
                                Container(
                                  padding: const EdgeInsets.all(14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF1A140B),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.notifications_active_rounded, color: Color(0xFFFBBF24), size: 22),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: Text(
                                          widget.missedAlertEnabled
                                              ? (tr
                                                  ? 'Arama yanıtlanmadı; acil durum bildirimi ve Telegram bot uyarısı tetiklendi.'
                                                  : 'Call unanswered; push banner & Telegram alert dispatched.')
                                              : (tr
                                                  ? 'Arama süresi doldu ve cevapsız olarak kaydedildi.'
                                                  : 'Ring timed out and logged as missed call.'),
                                          style: const TextStyle(fontSize: 12, color: Colors.white, height: 1.35),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),

                      // Bottom Call Action Buttons
                      Padding(
                        padding: const EdgeInsets.only(top: 10, bottom: 6),
                        child: _phase == _CallPhase.ringing
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                children: [
                                  _CircularCallButton(
                                    icon: Icons.call_end_rounded,
                                    label: tr ? 'Reddet' : 'Decline',
                                    color: const Color(0xFFEF4444),
                                    onTap: _declineOrHangup,
                                  ),
                                  _CircularCallButton(
                                    icon: Icons.call_rounded,
                                    label: tr ? 'Cevapla' : 'Answer',
                                    color: const Color(0xFF10B981),
                                    onTap: _answerCall,
                                  ),
                                ],
                              )
                            : SizedBox(
                                width: double.infinity,
                                child: FilledButton.icon(
                                  onPressed: _declineOrHangup,
                                  style: FilledButton.styleFrom(
                                    backgroundColor: const Color(0xFFEF4444),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 14),
                                    shape: RoundedRectangleBorder(
                                      borderRadius: BorderRadius.circular(24),
                                    ),
                                  ),
                                  icon: const Icon(Icons.call_end_rounded, size: 20),
                                  label: Text(
                                    _phase == _CallPhase.answered
                                        ? (tr ? 'Görüşmeyi Bitir' : 'End Call')
                                        : (tr ? 'Kapat' : 'Dismiss'),
                                    style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w800),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CallStatTile extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _CallStatTile({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: TextStyle(
              fontSize: 9.5,
              fontWeight: FontWeight.w700,
              color: Colors.white.withValues(alpha: 0.48),
              letterSpacing: 0.6,
            ),
          ),
          const SizedBox(height: 3),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.w800,
              color: color,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _CircularCallButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _CircularCallButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 68,
            height: 68,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color,
              boxShadow: [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 22,
                  offset: const Offset(0, 6),
                ),
              ],
            ),
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
      ],
    );
  }
}

class _InCallQuickButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color accent;
  final VoidCallback onTap;

  const _InCallQuickButton({
    required this.icon,
    required this.label,
    required this.accent,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          color: accent.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: accent.withValues(alpha: 0.38)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 15, color: accent),
            const SizedBox(width: 4),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
