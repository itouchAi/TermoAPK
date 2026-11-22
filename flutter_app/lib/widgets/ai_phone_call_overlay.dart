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
  final ValueChanged<AiCallLogEntry>? onFinishCall;

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
    this.onFinishCall,
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
  bool _closingAfterReply = false;
  bool _emittedFinish = false;
  String? _quickActionAck;
  String? _heardPreview;
  String? _commandSummaryTr;
  String? _commandSummaryEn;
  double? _updatedTargetTemp;

  @override
  void initState() {
    super.initState();
    _ringRemaining = widget.ringSeconds.clamp(5, 30);
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1600),
    )..repeat();

    _startRingingHardware();
    VoiceSpeechService.warmup();
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

  void _speakAloud(String text, {VoidCallback? onDone}) {
    if (_speakerMuted) {
      onDone?.call();
      return;
    }
    setState(() => _ttsPlaying = true);
    VoiceSpeechService.speak(
      text,
      lang: widget.lang,
      character: widget.character,
      onComplete: () {
        if (mounted) {
          setState(() => _ttsPlaying = false);
          onDone?.call();
        }
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
          _spokenChars = math.min(totalLen, _spokenChars + 42);
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
      if (mounted) {
        _emitFinishAndClose(
          status: AiCallStatus.missed,
          durationSeconds: 0,
          outcomeText: outcome,
        );
      }
    });
  }

  void _emitFinishAndClose({
    required AiCallStatus status,
    required int durationSeconds,
    required String outcomeText,
  }) {
    if (_emittedFinish) return;
    _emittedFinish = true;

    final effectiveTarget = _updatedTargetTemp ?? widget.targetTemp;
    final summaryTr = AiCallService.buildAlertHeadline(
      widget.reason,
      roomTemp: widget.roomTemp,
      targetTemp: widget.targetTemp,
      boilerHeating: widget.boiler.isHeating,
      lang: LangCode.tr,
    );
    final summaryEn = AiCallService.buildAlertHeadline(
      widget.reason,
      roomTemp: widget.roomTemp,
      targetTemp: widget.targetTemp,
      boilerHeating: widget.boiler.isHeating,
      lang: LangCode.en,
    );

    final String actionTr;
    final String actionEn;
    if (status == AiCallStatus.answered) {
      actionTr = _commandSummaryTr ?? 'Görüşme yapıldı (ayar değiştirilmedi)';
      actionEn = _commandSummaryEn ?? 'Call answered (no changes)';
    } else if (status == AiCallStatus.declined) {
      actionTr = 'Meşgule atıldı (işlem yapılmadı)';
      actionEn = 'Declined / busy (no action taken)';
    } else {
      actionTr = 'Cevapsız bırakıldı';
      actionEn = 'Missed call';
    }

    final entry = AiCallLogEntry(
      id: DateTime.now().microsecondsSinceEpoch.toString(),
      timestamp: NotificationService.formatNowTime(),
      character: widget.character,
      reason: widget.reason,
      status: status,
      durationSeconds: durationSeconds,
      summaryTr: summaryTr,
      summaryEn: summaryEn,
      actionTakenTr: actionTr,
      actionTakenEn: actionEn,
      roomTemp: widget.roomTemp,
      targetTemp: effectiveTarget,
      boilerHeating: widget.boiler.isHeating,
      urgent: widget.urgent,
    );

    widget.onFinishCall?.call(entry);
    widget.onCloseWithOutcome(outcomeText);
  }

  String? _micPermissionError;

  Future<void> _unlockMicPermissionOnAnswer() async {
    final err = await VoiceSpeechService.ensureMicPermission(widget.lang);
    if (mounted && err != null) {
      setState(() {
        _micPermissionError = err;
        _heardPreview = err;
      });
    }
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

    // Pre-request microphone permission synchronously within the `Cevapla` tap gesture
    unawaited(_unlockMicPermissionOnAnswer());

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
      _spokenChars = widget.voiceBriefEnabled ? 38 : 9999;
    });

    if (widget.voiceBriefEnabled && !_speakerMuted) {
      _speakAloud(
        brief,
        onDone: () {
          if (mounted && !_closingAfterReply && _phase == _CallPhase.answered) {
            unawaited(_startHandsFreeListening(skipPermissionPrompt: true));
          }
        },
      );
    } else {
      Future<void>.delayed(const Duration(milliseconds: 350), () {
        if (mounted && !_closingAfterReply && _phase == _CallPhase.answered) {
          unawaited(_startHandsFreeListening(skipPermissionPrompt: true));
        }
      });
    }
  }

  void _declineOrHangup() {
    if (!mounted) return;
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
    final AiCallStatus status;
    final int durationSeconds;
    final String outcome;
    if (_phase == _CallPhase.answered) {
      status = AiCallStatus.answered;
      durationSeconds = _callSeconds;
      final dur = AiCallService.formatCallDuration(_callSeconds);
      outcome = tr ? '$ts · Cevaplandı ($dur)' : '$ts · Answered ($dur)';
    } else if (_phase == _CallPhase.missed) {
      status = AiCallStatus.missed;
      durationSeconds = 0;
      outcome = tr
          ? (widget.missedAlertEnabled ? '$ts · Cevapsız (Uyarı gönderildi)' : '$ts · Cevapsız')
          : (widget.missedAlertEnabled ? '$ts · Missed (Alert sent)' : '$ts · Missed');
    } else {
      status = AiCallStatus.declined;
      durationSeconds = 0;
      outcome = tr ? '$ts · Meşgule atıldı' : '$ts · Declined';
    }
    _emitFinishAndClose(
      status: status,
      durationSeconds: durationSeconds,
      outcomeText: outcome,
    );
  }

  void _speakConfirmationAndAutoHangup(String spokenReply) {
    if (_closingAfterReply) return;
    setState(() => _closingAfterReply = true);

    _closeDelayTimer?.cancel();
    if (_speakerMuted) {
      _closeDelayTimer = Timer(const Duration(milliseconds: 1100), () {
        if (mounted) _declineOrHangup();
      });
      return;
    }

    final startedAt = DateTime.now();
    final minSpeechMs = (spokenReply.length * 72 + 900).clamp(2400, 6800);

    // Guaranteed max fail-safe close if browser engine stalls
    _closeDelayTimer = Timer(Duration(milliseconds: minSpeechMs + 3200), () {
      if (mounted) _declineOrHangup();
    });

    _speakAloud(
      spokenReply,
      onDone: () {
        if (!mounted) return;
        final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
        final remainingMs = math.max(750, minSpeechMs - elapsedMs);
        _closeDelayTimer?.cancel();
        _closeDelayTimer = Timer(Duration(milliseconds: remainingMs), () {
          if (mounted) _declineOrHangup();
        });
      },
    );
  }

  void _applyCallQuickTemp(double nextTemp, String replyTr, String replyEn) {
    if (_closingAfterReply) return;
    VoiceSpeechService.stopListening();
    final snapped = ThermostatMath.snapTemperature(nextTemp);
    _updatedTargetTemp = snapped;
    if (snapped <= ThermostatMath.minTemp) {
      _commandSummaryTr = 'Komut: Kombi kapatıldı';
      _commandSummaryEn = 'Command: Boiler turned off';
    } else {
      final tStr = AiCallService.formatSpokenNumber(snapped);
      _commandSummaryTr = 'Komut: Hedef $tStr°C ayarlandı';
      _commandSummaryEn = 'Command: Target set to $tStr°C';
    }
    widget.onAdjustTargetTemp(snapped);
    if (widget.hapticEnabled) {
      HardwareService.vibrateMs(
        45,
        amplitude: HardwareService.scaledAmplitude(145, widget.hapticStrength),
      );
    }
    final msg = widget.lang == LangCode.tr ? replyTr : replyEn;
    setState(() {
      _listeningCommand = false;
      _quickActionAck = '✓ $msg';
      _spokenChars = 9999;
    });
    _speakConfirmationAndAutoHangup(msg);
  }

  void _executeSpokenOrTypedCommand(String raw) {
    if (_closingAfterReply) return;
    VoiceSpeechService.stopListening();
    final res = AiCallService.evaluateCallResponse(
      rawInput: raw,
      callReason: widget.reason,
      boiler: widget.boiler,
      currentTargetTemp: widget.targetTemp,
      lang: widget.lang,
    );
    final reply = widget.lang == LangCode.tr ? res.replyTr : res.replyEn;
    if (res.handled) {
      final spoken = raw.trim();
      final prefixTr = spoken.isNotEmpty ? 'Komut ("$spoken"): ' : 'Komut: ';
      final prefixEn = spoken.isNotEmpty ? 'Command ("$spoken"): ' : 'Command: ';
      if (res.newTargetTemp != null) {
        _updatedTargetTemp = res.newTargetTemp;
        if (res.newTargetTemp! <= ThermostatMath.minTemp) {
          _commandSummaryTr = '${prefixTr}Kombi kapatıldı';
          _commandSummaryEn = '${prefixEn}Boiler turned off';
        } else {
          final tStr = AiCallService.formatSpokenNumber(res.newTargetTemp!);
          _commandSummaryTr = '${prefixTr}Hedef $tStr°C';
          _commandSummaryEn = '${prefixEn}Target $tStr°C';
        }
        widget.onAdjustTargetTemp(res.newTargetTemp!);
        if (widget.hapticEnabled) {
          HardwareService.vibrateMs(
            50,
            amplitude: HardwareService.scaledAmplitude(155, widget.hapticStrength),
          );
        }
      } else {
        _commandSummaryTr = '${prefixTr}Mevcut ayar korundu';
        _commandSummaryEn = '${prefixEn}Kept current settings';
      }
    }
    setState(() {
      _listeningCommand = false;
      _heardPreview = raw.trim().isNotEmpty ? '"${raw.trim()}"' : null;
      _quickActionAck = res.handled ? '✓ $reply' : reply;
      _spokenChars = 9999;
    });
    _voiceCmdCtrl.clear();

    if (res.handled) {
      _speakConfirmationAndAutoHangup(reply);
    } else if (!_speakerMuted) {
      _speakAloud(
        reply,
        onDone: () {
          if (mounted && !_closingAfterReply && _phase == _CallPhase.answered) {
            unawaited(_startHandsFreeListening(skipPermissionPrompt: true));
          }
        },
      );
    }
  }

  Future<void> _startHandsFreeListening({bool skipPermissionPrompt = false}) async {
    if (_closingAfterReply || _listeningCommand || _phase != _CallPhase.answered) return;
    if (_micPermissionError != null && skipPermissionPrompt) return;

    setState(() {
      _listeningCommand = true;
      _ttsPlaying = false;
      _heardPreview = widget.lang == LangCode.tr
          ? 'Sizi dinliyorum... Konuşabilirsiniz'
          : 'Listening... Please speak';
    });

    final ok = await VoiceSpeechService.startListening(
      lang: widget.lang,
      skipPermissionPrompt: skipPermissionPrompt,
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
            _heardPreview = err;
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

  Future<void> _toggleCallMic() async {
    if (_closingAfterReply) return;
    if (_listeningCommand) {
      await VoiceSpeechService.stopListening();
      if (mounted) setState(() => _listeningCommand = false);
      return;
    }
    _micPermissionError = null;
    await _startHandsFreeListening(skipPermissionPrompt: false);
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
      targetTemp: widget.targetTemp,
    );
    final fullScript = _fullTranscript(meta);
    final visibleScript = _phase == _CallPhase.answered
        ? (widget.voiceBriefEnabled
            ? fullScript.substring(0, math.min(_spokenChars, fullScript.length))
            : fullScript)
        : '';

    final topGlowSolid = Color.alphaBlend(
      accent.withValues(alpha: 0.22),
      const Color(0xFF070C14),
    );
    final genderTag = VoiceSpeechService.isFemaleCharacter(widget.character)
        ? (tr ? 'Kadın Ses' : 'Female')
        : (tr ? 'Erkek Ses' : 'Male');

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
                  padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
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
                                  '${widget.espDeviceId} · $genderTag',
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
                          padding: const EdgeInsets.symmetric(vertical: 8),
                          child: Column(
                            children: [
                              // Pulsing Caller Avatar
                              AnimatedBuilder(
                                animation: _pulseCtrl,
                                builder: (_, __) {
                                  final t = _pulseCtrl.value;
                                  return SizedBox(
                                    width: 126,
                                    height: 126,
                                    child: Stack(
                                      alignment: Alignment.center,
                                      children: [
                                        if (_phase != _CallPhase.missed)
                                          for (int r = 0; r < 2; r++)
                                            Transform.scale(
                                              scale: 0.88 + (((t + r * 0.5) % 1.0) * 0.48),
                                              child: Container(
                                                width: 94,
                                                height: 94,
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
                                          width: 90,
                                          height: 90,
                                          decoration: BoxDecoration(
                                            shape: BoxShape.circle,
                                            color: const Color(0xFF0A0F1A),
                                            border: Border.all(color: accent, width: 2.5),
                                            boxShadow: [
                                              BoxShadow(
                                                color: accent.withValues(alpha: 0.35),
                                                blurRadius: 22,
                                              ),
                                            ],
                                          ),
                                          child: ClipOval(
                                            child: Image.asset(
                                              meta.assetPath,
                                              fit: BoxFit.cover,
                                              errorBuilder: (_, __, ___) => Container(
                                                color: meta.color.withValues(alpha: 0.22),
                                                child: Icon(meta.icon, size: 42, color: meta.color),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  );
                                },
                              ),
                              const SizedBox(height: 6),
                              Text(
                                '${meta.name} · ${tr ? 'AI Kombi Asistanı' : 'AI Boiler Assistant'}',
                                textAlign: TextAlign.center,
                                style: const TextStyle(
                                  fontSize: 19,
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                widget.locationName,
                                style: TextStyle(
                                  fontSize: 12,
                                  color: Colors.white.withValues(alpha: 0.65),
                                ),
                              ),
                              const SizedBox(height: 8),

                              // Call Reason Banner
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
                                decoration: BoxDecoration(
                                  color: accent.withValues(alpha: 0.16),
                                  borderRadius: BorderRadius.circular(13),
                                  border: Border.all(color: accent.withValues(alpha: 0.42)),
                                ),
                                child: Text(
                                  reasonText,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                    color: widget.urgent
                                        ? const Color(0xFFFCA5A5)
                                        : const Color(0xFF6EE7B7),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 10),

                              // Concise Temperature & Boiler State Strip
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF0D1420),
                                  borderRadius: BorderRadius.circular(16),
                                  border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                                ),
                                child: Row(
                                  children: [
                                    _CallStatTile(
                                      label: tr ? 'ODA' : 'ROOM',
                                      value: '${AiCallService.formatSpokenNumber(widget.roomTemp)}°',
                                      color: Colors.white,
                                    ),
                                    _CallStatTile(
                                      label: tr ? 'HEDEF' : 'TARGET',
                                      value: '${AiCallService.formatSpokenNumber(widget.targetTemp)}°',
                                      color: const Color(0xFF38BDF8),
                                    ),
                                    _CallStatTile(
                                      label: tr ? 'KOMBİ' : 'BOILER',
                                      value: widget.boiler.isHeating
                                          ? (tr ? 'AKTİF' : 'ACTIVE')
                                          : (tr ? 'KAPALI' : 'OFF'),
                                      color: widget.boiler.isHeating
                                          ? const Color(0xFFFB923C)
                                          : Colors.white54,
                                    ),
                                  ],
                                ),
                              ),

                              // Answered Voice Equalizer + Transcript + Live Mic Voice Commands
                              if (_phase == _CallPhase.answered) ...[
                                const SizedBox(height: 10),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF0D1524),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.42)),
                                  ),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.graphic_eq_rounded, size: 16, color: Color(0xFF34D399)),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: Text(
                                              _closingAfterReply
                                                  ? (tr ? 'İşlem Uygulanıyor · Görüşme Kapanıyor...' : 'Applying · Ending Call...')
                                                  : (tr ? 'Asistan Konuşması' : 'Assistant Speech'),
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
                                                    size: 15,
                                                    color: _speakerMuted ? Colors.white38 : const Color(0xFF34D399),
                                                  ),
                                                  const SizedBox(width: 4),
                                                  Text(
                                                    _speakerMuted ? (tr ? 'Sessiz' : 'Muted') : (tr ? 'Sesli' : 'Voice'),
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
                                      const SizedBox(height: 8),
                                      AnimatedBuilder(
                                        animation: _pulseCtrl,
                                        builder: (_, __) {
                                          final phase = _pulseCtrl.value * math.pi * 2;
                                          final speaking = !_speakerMuted &&
                                              (_ttsPlaying || _listeningCommand || _spokenChars < fullScript.length);
                                          return SizedBox(
                                            height: 20,
                                            child: Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                                              children: List.generate(18, (idx) {
                                                final amp = speaking
                                                    ? 0.28 + 0.72 * (0.5 + 0.5 * math.sin(phase * 2.2 + idx * 0.7))
                                                    : 0.20;
                                                return Container(
                                                  width: 4,
                                                  height: 4 + amp * 15,
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
                                      const SizedBox(height: 8),
                                      Text(
                                        visibleScript,
                                        style: const TextStyle(
                                          fontSize: 12.5,
                                          color: Colors.white,
                                          height: 1.4,
                                        ),
                                      ),
                                      const SizedBox(height: 10),

                                      // Direct Microphone Permission & Voice Command Button
                                      GestureDetector(
                                        behavior: HitTestBehavior.opaque,
                                        onTap: _toggleCallMic,
                                        child: AnimatedContainer(
                                          duration: const Duration(milliseconds: 200),
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                                          decoration: BoxDecoration(
                                            color: _listeningCommand
                                                ? const Color(0xFFEF4444).withValues(alpha: 0.22)
                                                : const Color(0xFF10B981).withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _listeningCommand
                                                  ? const Color(0xFFF87171)
                                                  : const Color(0xFF10B981).withValues(alpha: 0.55),
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
                                                  _heardPreview ??
                                                      (_ttsPlaying
                                                          ? (tr
                                                              ? 'Asistan konuşuyor, bitince otomatik dinlenecek...'
                                                              : 'Speaking, mic starts automatically next...')
                                                          : (tr
                                                              ? 'Dinlenmediyse tekrar başlatmak için dokunun ("Kombiyi kapat", "Evet")'
                                                              : 'Tap to re-listen ("Turn off boiler", "Yes")')),
                                                  style: TextStyle(
                                                    fontSize: 11.5,
                                                    fontWeight: FontWeight.w700,
                                                    color: _listeningCommand ? const Color(0xFFFCA5A5) : Colors.white,
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
                                                    ? 'Veya yaz: Kombiyi kapat / 5 derece arttır / Eko...'
                                                    : 'Or type: Turn off boiler / Raise 5 / Eco...',
                                                hintStyle: TextStyle(
                                                  fontSize: 11,
                                                  color: Colors.white.withValues(alpha: 0.42),
                                                ),
                                                filled: true,
                                                fillColor: Colors.white.withValues(alpha: 0.05),
                                                contentPadding: const EdgeInsets.symmetric(
                                                  horizontal: 10,
                                                  vertical: 8,
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
                                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
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
                                if (widget.reason == AiCallReason.coldRoom ||
                                    widget.reason == AiCallReason.hotRoom) ...[
                                  Row(
                                    children: [
                                      Expanded(
                                        child: _InCallQuickButton(
                                          icon: widget.reason == AiCallReason.hotRoom &&
                                                  widget.targetTemp >= AiCallService.highTargetTempThresholdC
                                              ? Icons.thermostat_rounded
                                              : Icons.check_circle_outline_rounded,
                                          label: widget.reason == AiCallReason.coldRoom
                                              ? (tr ? 'Evet, Kombiyi Aç' : 'Yes, Turn On')
                                              : (widget.targetTemp >= AiCallService.highTargetTempThresholdC
                                                  ? (tr ? "22.5°'ye Düşür" : 'Lower to 22.5°')
                                                  : (tr ? 'Evet, Kapat' : 'Yes, Turn Off')),
                                          accent: const Color(0xFF10B981),
                                          onTap: () => _executeSpokenOrTypedCommand(
                                            widget.reason == AiCallReason.hotRoom &&
                                                    widget.targetTemp >= AiCallService.highTargetTempThresholdC
                                                ? 'düşür'
                                                : 'evet',
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: _InCallQuickButton(
                                          icon: Icons.close_rounded,
                                          label: tr ? 'Hayır, Kalsın' : 'No, Keep',
                                          accent: const Color(0xFFF59E0B),
                                          onTap: () => _executeSpokenOrTypedCommand('hayır'),
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                ],
                                Row(
                                  children: [
                                    Expanded(
                                      child: _InCallQuickButton(
                                        icon: widget.boiler.isHeating || widget.reason == AiCallReason.hotRoom
                                            ? Icons.power_settings_new_rounded
                                            : Icons.local_fire_department_rounded,
                                        label: widget.boiler.isHeating || widget.reason == AiCallReason.hotRoom
                                            ? (tr ? 'Kombiyi Kapat' : 'Boiler Off')
                                            : (tr ? 'Kombiyi Aç' : 'Boiler On'),
                                        accent: widget.boiler.isHeating || widget.reason == AiCallReason.hotRoom
                                            ? const Color(0xFFEF4444)
                                            : const Color(0xFFFB923C),
                                        onTap: () {
                                          if (widget.boiler.isHeating || widget.reason == AiCallReason.hotRoom) {
                                            _applyCallQuickTemp(
                                              ThermostatMath.minTemp,
                                              'Kombi kapatılıyor. Teşekkürler.',
                                              'Turning off the boiler. Thank you.',
                                            );
                                          } else {
                                            _applyCallQuickTemp(
                                              22.5,
                                              'Kombi açılıyor ve sıcaklık 22.5 dereceye ayarlanıyor. Teşekkürler.',
                                              'Turning on the boiler at 22.5 degrees. Thank you.',
                                            );
                                          }
                                        },
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _InCallQuickButton(
                                        icon: Icons.eco_rounded,
                                        label: tr ? 'Eko (20°)' : 'Eco (20°)',
                                        accent: const Color(0xFF38D994),
                                        onTap: () => _applyCallQuickTemp(
                                          20.0,
                                          'Eko modu 20 dereceye ayarlanıyor. Teşekkürler.',
                                          'Setting Eco mode to 20 degrees. Thank you.',
                                        ),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: _InCallQuickButton(
                                        icon: Icons.add_rounded,
                                        label: '+1°',
                                        accent: const Color(0xFF38BDF8),
                                        onTap: () {
                                          final next = ThermostatMath.snapTemperature(widget.targetTemp + 1.0);
                                          final numStr = AiCallService.formatSpokenNumber(next);
                                          _applyCallQuickTemp(
                                            next,
                                            'Sıcaklık $numStr dereceye yükseltiliyor. Teşekkürler.',
                                            'Raising target to $numStr degrees. Thank you.',
                                          );
                                        },
                                      ),
                                    ),
                                  ],
                                ),
                              ],

                              if (_phase == _CallPhase.missed) ...[
                                const SizedBox(height: 16),
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
                        padding: const EdgeInsets.only(top: 8, bottom: 4),
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
                                    padding: const EdgeInsets.symmetric(vertical: 13),
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
                  fontSize: 11,
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
