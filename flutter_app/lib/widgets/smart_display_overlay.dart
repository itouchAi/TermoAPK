import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/thermostat_state.dart';
import '../services/ambient_audio_service.dart';
import '../services/hardware_service.dart';
import '../services/video_source_bridge.dart';

class SmartDisplayOverlay extends StatefulWidget {
  final SystemSettingsState settings;
  final int slideIndex;
  final DateTime now;
  final String locationName;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final Color accentColor;
  final LangCode lang;
  final String paletteTag;
  final bool forcedAod;
  final VoidCallback? onWakeFromAutoAod;
  final ValueChanged<double> onChangeTargetTemp;
  final ValueChanged<ThermostatPreset> onSelectPreset;
  final ValueChanged<SystemSettingsState> onUpdateSettings;
  final ValueChanged<int> onStepSlideIndex;
  final VoidCallback onClose;

  const SmartDisplayOverlay({
    super.key,
    required this.settings,
    required this.slideIndex,
    required this.now,
    required this.locationName,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.accentColor,
    required this.lang,
    required this.paletteTag,
    this.forcedAod = false,
    this.onWakeFromAutoAod,
    required this.onChangeTargetTemp,
    required this.onSelectPreset,
    required this.onUpdateSettings,
    required this.onStepSlideIndex,
    required this.onClose,
  });

  @override
  State<SmartDisplayOverlay> createState() => _SmartDisplayOverlayState();
}

class _SmartDisplayOverlayState extends State<SmartDisplayOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  bool _hudHidden = false;
  bool _paused = false;
  bool _muted = false;
  bool _leftDrawerOpen = false;
  bool _rightDrawerOpen = false;
  bool _thermostatModalOpen = false;
  int _thermostatCountdown = 5;
  Timer? _thermostatTimer;
  String? _hudHintBanner;
  Timer? _hintTimer;

  // Lightweight memory cache for base64 slide photos to avoid re-decoding every 1s clock tick
  final Map<String, Uint8List> _decodedImageCache = {};

  VideoPlayerController? _videoCtrl;
  String _activeVideoSource = '';
  bool _videoReady = false;

  SmartDisplayMode get _effectiveMode {
    if (widget.forcedAod) return SmartDisplayMode.aod;
    final raw = widget.settings.smartDisplayMode;
    return raw == SmartDisplayMode.singlePhoto ? SmartDisplayMode.slideshow : raw;
  }

  @override
  void initState() {
    super.initState();
    _muted = widget.settings.ambientSoundtrack == AmbientSoundtrack.silent ||
        widget.settings.ambientVolume <= 0.01;
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _syncVideoController();
  }

  @override
  void didUpdateWidget(covariant SmartDisplayOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.ambientSoundtrack != widget.settings.ambientSoundtrack) {
      _muted = widget.settings.ambientSoundtrack == AmbientSoundtrack.silent;
    }
    if (oldWidget.settings.customVideoSource != widget.settings.customVideoSource ||
        oldWidget.settings.smartDisplayMode != widget.settings.smartDisplayMode ||
        oldWidget.forcedAod != widget.forcedAod) {
      _syncVideoController();
    }
  }

  @override
  void dispose() {
    _thermostatTimer?.cancel();
    _hintTimer?.cancel();
    _videoCtrl?.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  Future<void> _syncVideoController() async {
    final mode = _effectiveMode;
    final wanted = (mode == SmartDisplayMode.silentVideoMp3 &&
            widget.settings.customVideoSource.trim().isNotEmpty)
        ? widget.settings.customVideoSource.trim()
        : '';

    if (wanted == _activeVideoSource) {
      final ctrl = _videoCtrl;
      if (ctrl != null && _videoReady) {
        try {
          await ctrl.setVolume(0.0);
          if (_paused) {
            await ctrl.pause();
          } else {
            await ctrl.play();
          }
        } catch (_) {}
      }
      return;
    }

    final old = _videoCtrl;
    _videoCtrl = null;
    _videoReady = false;
    _activeVideoSource = wanted;
    if (old != null) {
      unawaited(old.dispose());
    }
    if (wanted.isEmpty) {
      if (mounted) setState(() {});
      return;
    }

    try {
      final ctrl = VideoSourceBridge.createController(wanted);
      if (ctrl == null) return;
      _videoCtrl = ctrl;
      await ctrl.initialize();
      if (!mounted || _activeVideoSource != wanted) {
        await ctrl.dispose();
        return;
      }
      await ctrl.setLooping(true);
      await ctrl.setVolume(0.0); // Video track stays muted; user MP3/ambient provides audio
      if (!_paused) {
        await ctrl.play();
      }
      if (mounted) {
        setState(() => _videoReady = true);
      }
    } catch (_) {
      if (mounted && _activeVideoSource == wanted) {
        setState(() => _videoReady = false);
      }
    }
  }

  void _haptic() {
    if (widget.settings.hapticEnabled) {
      HardwareService.vibrateMs(
        35,
        amplitude: HardwareService.scaledAmplitude(120, widget.settings.hapticStrength),
      );
    }
  }

  Uint8List? _bytesForImage(SmartDisplaySlideImage img) {
    final key = '${img.id}_${img.dataBase64.length}';
    final cached = _decodedImageCache[key];
    if (cached != null) return cached;
    final decoded = img.decodeBytes();
    if (decoded != null) {
      _decodedImageCache[key] = decoded;
    }
    return decoded;
  }

  void _togglePause() {
    _haptic();
    setState(() {
      _paused = !_paused;
      if (_paused) {
        _animCtrl.stop();
        _videoCtrl?.pause();
      } else {
        _animCtrl.repeat();
        if (_videoReady) {
          _videoCtrl?.setVolume(0.0);
          _videoCtrl?.play();
        }
      }
    });
  }

  void _toggleMute() {
    _haptic();
    final nextMuted = !_muted;
    setState(() => _muted = nextMuted);
    if (nextMuted) {
      AmbientAudioService.stop();
    } else {
      final track = widget.settings.ambientSoundtrack == AmbientSoundtrack.silent
          ? AmbientSoundtrack.fireplaceCrackling
          : widget.settings.ambientSoundtrack;
      if (widget.settings.ambientSoundtrack == AmbientSoundtrack.silent) {
        widget.onUpdateSettings(widget.settings.copyWith(ambientSoundtrack: track));
      }
      AmbientAudioService.start(
        track: track,
        customSource: widget.settings.customAudioSource.isNotEmpty
            ? widget.settings.customAudioSource
            : widget.settings.customAudioLabel,
        volume: widget.settings.ambientVolume <= 0.05 ? 0.5 : widget.settings.ambientVolume,
      );
    }
  }

  void _cycleBrightness() {
    _haptic();
    const steps = [25, 50, 75, 100];
    final cur = widget.settings.displayBrightness;
    var next = steps.first;
    for (final s in steps) {
      if (s > cur + 4) {
        next = s;
        break;
      }
    }
    widget.onUpdateSettings(widget.settings.copyWith(displayBrightness: next));
    HardwareService.enterSmartDisplayHardware(
      brightnessPercent: next,
      keepAwake: widget.settings.displaySleepMinutes == 0,
    );
  }

  void _toggleHudHidden() {
    _haptic();
    final next = !_hudHidden;
    _hintTimer?.cancel();
    setState(() {
      _hudHidden = next;
      _leftDrawerOpen = false;
      _rightDrawerOpen = false;
      _hudHintBanner = next
          ? (widget.lang == LangCode.tr
              ? 'Ekran temizlendi · Geri getirmek için sağ alttaki fırçaya dokunun'
              : 'HUD hidden · Tap bottom-right brush to restore')
          : null;
    });
    if (next) {
      _hintTimer = Timer(const Duration(milliseconds: 2200), () {
        if (mounted) setState(() => _hudHintBanner = null);
      });
    }
  }

  void _openThermostatModal() {
    _haptic();
    setState(() {
      _thermostatModalOpen = true;
      _thermostatCountdown = 5;
      _leftDrawerOpen = false;
      _rightDrawerOpen = false;
    });
    _startThermostatCountdown();
  }

  void _closeThermostatModal() {
    _thermostatTimer?.cancel();
    if (!mounted) return;
    setState(() => _thermostatModalOpen = false);
  }

  void _resetThermostatCountdown() {
    if (!_thermostatModalOpen) return;
    setState(() => _thermostatCountdown = 5);
  }

  void _startThermostatCountdown() {
    _thermostatTimer?.cancel();
    _thermostatTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || !_thermostatModalOpen) {
        _thermostatTimer?.cancel();
        return;
      }
      if (_thermostatCountdown <= 1) {
        _closeThermostatModal();
      } else {
        setState(() => _thermostatCountdown--);
      }
    });
  }

  String _formatFullUppercaseDate(DateTime dt, LangCode lang) {
    const daysTr = ['PAZARTESİ', 'SALI', 'ÇARŞAMBA', 'PERŞEMBE', 'CUMA', 'CUMARTESİ', 'PAZAR'];
    const daysEn = ['MONDAY', 'TUESDAY', 'WEDNESDAY', 'THURSDAY', 'FRIDAY', 'SATURDAY', 'SUNDAY'];
    const monthsTr = [
      'OCAK',
      'ŞUBAT',
      'MART',
      'NİSAN',
      'MAYIS',
      'HAZİRAN',
      'TEMMUZ',
      'AĞUSTOS',
      'EYLÜL',
      'EKİM',
      'KASIM',
      'ARALIK',
    ];
    const monthsEn = [
      'JANUARY',
      'FEBRUARY',
      'MARCH',
      'APRIL',
      'MAY',
      'JUNE',
      'JULY',
      'AUGUST',
      'SEPTEMBER',
      'OCTOBER',
      'NOVEMBER',
      'DECEMBER',
    ];
    final d = lang == LangCode.tr ? daysTr[dt.weekday - 1] : daysEn[dt.weekday - 1];
    final m = lang == LangCode.tr ? monthsTr[dt.month - 1] : monthsEn[dt.month - 1];
    return '${dt.day} $m ${dt.year} $d';
  }

  (String, double, IconData) _resolveOutdoorWeather() {
    final city = SystemSettingsState.extractCityName(widget.locationName);
    final lower = city.toLowerCase();
    if (lower.contains('izmir')) {
      return (city, 16.4, Icons.wb_sunny_outlined);
    }
    if (lower.contains('ankara')) {
      return (city, 7.2, Icons.ac_unit_rounded);
    }
    return (city, 11.9, Icons.cloud_outlined);
  }

  BoxFit _boxFitForLayout(VisualLayoutMode layout) {
    switch (layout) {
      case VisualLayoutMode.cover:
        return BoxFit.cover;
      case VisualLayoutMode.contain:
      case VisualLayoutMode.framed:
        return BoxFit.contain;
      case VisualLayoutMode.stretch:
        return BoxFit.fill;
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.lang == LangCode.tr;
    final media = MediaQuery.of(context);
    final size = media.size;
    final isLandscape = size.width > size.height;
    final compactHeight = size.height < 460;
    final s = widget.settings;
    final mode = _effectiveMode;

    // Subtle OLED pixel-shift drift
    final aodShift = (s.oledPixelShiftEnabled || mode == SmartDisplayMode.aod)
        ? Offset(((widget.now.minute % 5) - 2) * 3.0, ((widget.now.second % 3) - 1) * 2.0)
        : Offset.zero;

    final hh = widget.now.hour.toString().padLeft(2, '0');
    final mm = widget.now.minute.toString().padLeft(2, '0');
    final ss = widget.now.second.toString().padLeft(2, '0');
    final (cityName, outdoorTemp, weatherIcon) = _resolveOutdoorWeather();

    final dimAlpha = ((1.0 - (s.displayBrightness / 100.0)) * 0.72).clamp(0.0, 0.72);
    final isAudioActive = !_muted && !widget.forcedAod && s.ambientSoundtrack != AmbientSoundtrack.silent;

    final clockFontSize = compactHeight
        ? 54.0
        : (isLandscape ? math.min(92.0, size.height * 0.19) : math.min(82.0, size.width * 0.19));
    final secFontSize = (clockFontSize * 0.28).clamp(16.0, 26.0);

    return Material(
      color: Colors.black,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: widget.forcedAod ? widget.onWakeFromAutoAod : null,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // 1. Dynamic Full-Screen Visual / Video / Slide / Theme Backdrop Layer
            Positioned.fill(
              child: _buildBackgroundLayer(s),
            ),

            // Readability dark gradient scrim (except pure black AOD)
            if (mode != SmartDisplayMode.aod)
              Positioned.fill(
                child: IgnorePointer(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.42),
                          Colors.black.withValues(alpha: 0.16),
                          Colors.black.withValues(alpha: 0.56),
                        ],
                      ),
                    ),
                  ),
                ),
              ),

          // 2. Display Brightness Dimming Overlay
          if (dimAlpha > 0.01)
            Positioned.fill(
              child: IgnorePointer(
                child: Container(color: Colors.black.withValues(alpha: dimAlpha)),
              ),
            ),

          // 3. Main Animated HUD Content (Header, Center Clock & Target Pill, Bottom Floating Toolbars)
          SafeArea(
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: isLandscape ? 22 : 16,
                vertical: compactHeight ? 10 : 14,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // TOP BAR (Slides smoothly UP off-screen when HUD hidden)
                  AnimatedSlide(
                    offset: _hudHidden ? const Offset(0, -1.8) : Offset.zero,
                    duration: const Duration(milliseconds: 420),
                    curve: Curves.easeInOutCubic,
                    child: AnimatedOpacity(
                      opacity: _hudHidden ? 0.0 : 1.0,
                      duration: const Duration(milliseconds: 300),
                      child: IgnorePointer(
                        ignoring: _hudHidden,
                        child: _buildTopHeader(
                          tr: tr,
                          cityName: cityName,
                          outdoorTemp: outdoorTemp,
                          weatherIcon: weatherIcon,
                          compact: size.width < 430,
                        ),
                      ),
                    ),
                  ),

                  // CENTER CLOCK, DATE, ROOM/TARGET PILL & EQUALIZER
                  Expanded(
                    child: Center(
                      child: AnimatedSlide(
                        offset: _hudHidden ? const Offset(0, -0.35) : Offset.zero,
                        duration: const Duration(milliseconds: 440),
                        curve: Curves.easeInOutCubic,
                        child: AnimatedOpacity(
                          opacity: _hudHidden ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 320),
                          child: IgnorePointer(
                            ignoring: _hudHidden,
                            child: Transform.translate(
                              offset: aodShift,
                              child: SingleChildScrollView(
                                physics: const NeverScrollableScrollPhysics(),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (s.marqueeTrackEnabled && isAudioActive)
                                      Container(
                                        margin: const EdgeInsets.only(bottom: 10),
                                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                                        decoration: BoxDecoration(
                                          color: Colors.black.withValues(alpha: 0.42),
                                          borderRadius: BorderRadius.circular(20),
                                          border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            const Icon(Icons.music_note_rounded, size: 13, color: Color(0xFF7DD3FC)),
                                            const SizedBox(width: 6),
                                            Flexible(
                                              child: Text(
                                                '${s.ambientTrackTitle(widget.lang)} · %${(s.ambientVolume * 100).round()}',
                                                style: const TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.w600,
                                                  color: Color(0xFFE0F2FE),
                                                ),
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                    // Huge Crisp Clock HH : MM  ss
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      crossAxisAlignment: CrossAxisAlignment.baseline,
                                      textBaseline: TextBaseline.alphabetic,
                                      children: [
                                        Text(
                                          '$hh : $mm',
                                          style: TextStyle(
                                            fontSize: clockFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withValues(alpha: 0.92),
                                            letterSpacing: 3.0,
                                            height: 0.95,
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                            shadows: [
                                              Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 18),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 8),
                                        Text(
                                          ss,
                                          style: TextStyle(
                                            fontSize: secFontSize,
                                            fontWeight: FontWeight.w600,
                                            color: Colors.white.withValues(alpha: 0.52),
                                            fontFeatures: const [FontFeature.tabularFigures()],
                                          ),
                                        ),
                                      ],
                                    ),
                                    SizedBox(height: compactHeight ? 6 : 10),

                                    // Uppercase Full Date
                                    Text(
                                      _formatFullUppercaseDate(widget.now, widget.lang),
                                      textAlign: TextAlign.center,
                                      style: TextStyle(
                                        fontSize: compactHeight ? 11.5 : 13.5,
                                        fontWeight: FontWeight.w600,
                                        letterSpacing: 2.8,
                                        color: Colors.white.withValues(alpha: 0.68),
                                      ),
                                    ),
                                    SizedBox(height: compactHeight ? 12 : 20),

                                    // Glassmorphic Inline Pill: Oda: 21.8°C | Hedef: (-) 20°C (+)
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      decoration: BoxDecoration(
                                        color: Colors.black.withValues(alpha: 0.36),
                                        borderRadius: BorderRadius.circular(999),
                                        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
                                        boxShadow: [
                                          BoxShadow(color: Colors.black.withValues(alpha: 0.30), blurRadius: 16),
                                        ],
                                      ),
                                      child: Wrap(
                                        spacing: 10,
                                        runSpacing: 6,
                                        alignment: WrapAlignment.center,
                                        crossAxisAlignment: WrapCrossAlignment.center,
                                        children: [
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                tr ? 'Oda: ' : 'Room: ',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: Colors.white.withValues(alpha: 0.65),
                                                ),
                                              ),
                                              Text(
                                                '${widget.roomTemp.toStringAsFixed(1)}°C',
                                                style: const TextStyle(
                                                  fontSize: 14,
                                                  fontWeight: FontWeight.w800,
                                                  color: Color(0xFF10B981),
                                                  fontFeatures: [FontFeature.tabularFigures()],
                                                ),
                                              ),
                                            ],
                                          ),
                                          Text(
                                            '|',
                                            style: TextStyle(color: Colors.white.withValues(alpha: 0.24), fontSize: 14),
                                          ),
                                          Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Text(
                                                tr ? 'Hedef: ' : 'Target: ',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  color: Colors.white.withValues(alpha: 0.65),
                                                ),
                                              ),
                                              const SizedBox(width: 4),
                                              _CircleMiniBtn(
                                                icon: Icons.remove_rounded,
                                                enabled: widget.targetTemp > ThermostatMath.minTemp,
                                                onTap: () {
                                                  _haptic();
                                                  widget.onChangeTargetTemp(
                                                    ThermostatMath.snapTemperature(
                                                      widget.targetTemp - ThermostatMath.tempStep,
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 8),
                                              GestureDetector(
                                                onTap: _openThermostatModal,
                                                child: Text(
                                                  '${widget.targetTemp % 1 == 0 ? widget.targetTemp.toStringAsFixed(0) : widget.targetTemp.toStringAsFixed(1)}°C',
                                                  style: const TextStyle(
                                                    fontSize: 14.5,
                                                    fontWeight: FontWeight.w800,
                                                    color: Color(0xFFF59E0B),
                                                    fontFeatures: [FontFeature.tabularFigures()],
                                                  ),
                                                ),
                                              ),
                                              const SizedBox(width: 8),
                                              _CircleMiniBtn(
                                                icon: Icons.add_rounded,
                                                enabled: widget.targetTemp < ThermostatMath.maxTemp,
                                                onTap: () {
                                                  _haptic();
                                                  widget.onChangeTargetTemp(
                                                    ThermostatMath.snapTemperature(
                                                      widget.targetTemp + ThermostatMath.tempStep,
                                                    ),
                                                  );
                                                },
                                              ),
                                            ],
                                          ),
                                        ],
                                      ),
                                    ),

                                    if (s.equalizerEnabled && isAudioActive && !compactHeight) ...[
                                      const SizedBox(height: 16),
                                      SizedBox(
                                        width: 210,
                                        height: 30,
                                        child: AnimatedBuilder(
                                          animation: _animCtrl,
                                          builder: (_, __) => CustomPaint(
                                            painter: _SmartEqualizerPainter(
                                              phase: _animCtrl.value * math.pi * 6,
                                              style: s.equalizerStyle,
                                              color: widget.accentColor,
                                              intensity: s.ambientVolume.clamp(0.20, 1.0),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Quick Upward Drawers (left gallery/mode/audio or right brightness)
                  if (!_hudHidden && (_leftDrawerOpen || _rightDrawerOpen))
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: Align(
                        alignment: _leftDrawerOpen ? Alignment.bottomLeft : Alignment.bottomRight,
                        child: _leftDrawerOpen ? _buildLeftQuickDrawer(tr) : _buildRightQuickDrawer(tr),
                      ),
                    ),

                  // BOTTOM TOOLBAR ROW (Left pill + Right pill slide DOWN; Paintbrush stays interactive!)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      // Bottom-Left Floating Pill Bar
                      AnimatedSlide(
                        offset: _hudHidden ? const Offset(0, 2.2) : Offset.zero,
                        duration: const Duration(milliseconds: 420),
                        curve: Curves.easeInOutCubic,
                        child: AnimatedOpacity(
                          opacity: _hudHidden ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 280),
                          child: IgnorePointer(
                            ignoring: _hudHidden,
                            child: _buildBottomLeftPill(tr),
                          ),
                        ),
                      ),

                      // Bottom-Right Floating Pill + Paintbrush Clean Toggle
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          AnimatedSlide(
                            offset: _hudHidden ? const Offset(0, 2.2) : Offset.zero,
                            duration: const Duration(milliseconds: 420),
                            curve: Curves.easeInOutCubic,
                            child: AnimatedOpacity(
                              opacity: _hudHidden ? 0.0 : 1.0,
                              duration: const Duration(milliseconds: 280),
                              child: IgnorePointer(
                                ignoring: _hudHidden,
                                child: _buildBottomRightPill(tr),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          // Animated Paintbrush HUD Hide/Show Toggle
                          GestureDetector(
                            onTap: _toggleHudHidden,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 260),
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: _hudHidden
                                    ? Colors.black.withValues(alpha: 0.42)
                                    : const Color(0xFF14121B).withValues(alpha: 0.88),
                                border: Border.all(
                                  color: _hudHidden
                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.45)
                                      : const Color(0xFFF59E0B).withValues(alpha: 0.55),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withValues(alpha: 0.45),
                                    blurRadius: 12,
                                  ),
                                ],
                              ),
                              child: AnimatedOpacity(
                                duration: const Duration(milliseconds: 250),
                                opacity: _hudHidden ? 0.55 : 1.0,
                                child: Icon(
                                  _hudHidden ? Icons.visibility_outlined : Icons.brush_rounded,
                                  size: 19,
                                  color: const Color(0xFFFBBF24),
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),

          // Brief HUD-hidden restoration toast
          if (_hudHintBanner != null)
            Positioned(
              bottom: 72,
              left: 20,
              right: 20,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.72),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                    ),
                    child: Text(
                      _hudHintBanner!,
                      style: const TextStyle(fontSize: 11.5, color: Colors.white70, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

          // Brief auto-AOD sleep pill indicator
          if (widget.forcedAod)
            Positioned(
              bottom: 72,
              left: 20,
              right: 20,
              child: IgnorePointer(
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.06),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                    ),
                    child: Text(
                      tr
                          ? '🌙 Otomatik Uyku AOD Modu · Uyandırmak için ekrana dokunun'
                          : '🌙 Auto-Sleep AOD · Tap anywhere to wake',
                      style: const TextStyle(fontSize: 11, color: Colors.white60, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ),
            ),

          // 4. Embedded Termostat Kontrolü Modal (Image 7)
          if (_thermostatModalOpen)
            Positioned.fill(
              child: _EmbeddedThermostatModal(
                targetTemp: widget.targetTemp,
                roomTemp: widget.roomTemp,
                boiler: widget.boiler,
                accentColor: widget.accentColor,
                paletteTag: widget.paletteTag,
                countdownSeconds: _thermostatCountdown,
                lang: widget.lang,
                onInteract: _resetThermostatCountdown,
                onChangeTarget: (t) {
                  _resetThermostatCountdown();
                  widget.onChangeTargetTemp(t);
                },
                onSelectPreset: (p) {
                  _resetThermostatCountdown();
                  widget.onSelectPreset(p);
                },
                onClose: _closeThermostatModal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBackgroundLayer(SystemSettingsState s) {
    final mode = _effectiveMode;
    if (mode == SmartDisplayMode.aod) {
      return Container(color: Colors.black);
    }

    final fit = _boxFitForLayout(s.smartDisplayLayout);
    final isFramed = s.smartDisplayLayout == VisualLayoutMode.framed;

    Widget wrapTransition(Key key, Widget child) {
      final padded = isFramed
          ? Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 54),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(26),
                  child: child,
                ),
              ),
            )
          : child;
      return AnimatedSwitcher(
        duration: const Duration(milliseconds: 620),
        transitionBuilder: (c, anim) {
          switch (s.slideEffect) {
            case SlideTransitionEffect.fade:
              return FadeTransition(opacity: anim, child: c);
            case SlideTransitionEffect.slide:
              return SlideTransition(
                position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(anim),
                child: FadeTransition(opacity: anim, child: c),
              );
            case SlideTransitionEffect.zoom:
              return ScaleTransition(
                scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
                child: FadeTransition(opacity: anim, child: c),
              );
          }
        },
        child: KeyedSubtree(key: key, child: padded),
      );
    }

    // 1. Muted Custom Video Loop in Sessiz Video + MP3 Mode
    if (mode == SmartDisplayMode.silentVideoMp3 &&
        _videoCtrl != null &&
        _videoReady &&
        _videoCtrl!.value.isInitialized) {
      final vSize = _videoCtrl!.value.size;
      final vw = vSize.width > 0 ? vSize.width : 1280.0;
      final vh = vSize.height > 0 ? vSize.height : 720.0;
      return wrapTransition(
        ValueKey('silent_video_${_activeVideoSource.hashCode}'),
        Container(
          color: Colors.black,
          width: double.infinity,
          height: double.infinity,
          child: FittedBox(
            fit: fit,
            clipBehavior: Clip.hardEdge,
            child: SizedBox(
              width: vw,
              height: vh,
              child: VideoPlayer(_videoCtrl!),
            ),
          ),
        ),
      );
    }

    // 2. Uploaded Slideshow Photos (1 or more photos)
    if (mode == SmartDisplayMode.slideshow && s.slideImages.isNotEmpty) {
      final safeIdx = widget.slideIndex % s.slideImages.length;
      final img = s.slideImages[safeIdx];
      final bytes = _bytesForImage(img);
      if (bytes != null) {
        return wrapTransition(
          ValueKey('slide_photo_${img.id}_$safeIdx'),
          Container(
            color: Colors.black,
            width: double.infinity,
            height: double.infinity,
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, child) {
                final kenBurns = s.smartDisplayLayout == VisualLayoutMode.cover
                    ? (1.0 + 0.04 * (0.5 - 0.5 * math.cos(_animCtrl.value * math.pi * 2)))
                    : 1.0;
                return Transform.scale(scale: kenBurns, child: child);
              },
              child: Image.memory(
                bytes,
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
              ),
            ),
          ),
        );
      }
    }

    // 3. Built-in Live Photorealistic Themes + Real-time Animated Atmospheric Particles
    final effectiveTheme = mode == SmartDisplayMode.slideshow
        ? [
            SmartDisplayVisualTheme.sunset,
            SmartDisplayVisualTheme.fireplace,
            SmartDisplayVisualTheme.aurora,
            SmartDisplayVisualTheme.winterSnow,
            SmartDisplayVisualTheme.rainy,
          ][widget.slideIndex % 5]
        : s.smartDisplayVisualTheme;
    final themeAsset = smartDisplayThemeAssetPath(effectiveTheme);

    return wrapTransition(
      ValueKey('theme_${mode.name}_${effectiveTheme.name}_${widget.slideIndex}'),
      Stack(
        fit: StackFit.expand,
        children: [
          if (themeAsset.isNotEmpty)
            AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, child) {
                final t = _animCtrl.value * math.pi * 2;
                final scale = 1.03 + 0.035 * (0.5 - 0.5 * math.cos(t));
                final dx = math.sin(t) * 10.0;
                final dy = math.cos(t * 0.5) * 6.0;
                return Transform.translate(
                  offset: Offset(dx, dy),
                  child: Transform.scale(scale: scale, child: child),
                );
              },
              child: Image.asset(
                themeAsset,
                fit: fit,
                width: double.infinity,
                height: double.infinity,
                gaplessPlayback: true,
                errorBuilder: (_, __, ___) => CustomPaint(
                  painter: _SmartDisplayScenePainter(
                    theme: effectiveTheme,
                    phase: _animCtrl.value,
                    drawBackdrop: true,
                  ),
                  size: Size.infinite,
                ),
              ),
            )
          else
            Container(color: const Color(0xFF0A0A10)),

          // Real-time 60fps weather/ember/aurora/droplet motion layer on top of backdrop
          IgnorePointer(
            child: AnimatedBuilder(
              animation: _animCtrl,
              builder: (_, __) => CustomPaint(
                painter: _SmartDisplayScenePainter(
                  theme: effectiveTheme,
                  phase: _animCtrl.value,
                  drawBackdrop: themeAsset.isEmpty,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopHeader({
    required bool tr,
    required String cityName,
    required double outdoorTemp,
    required IconData weatherIcon,
    required bool compact,
  }) {
    final s = widget.settings;
    final room = s.googleHomeRoom.trim().isEmpty ? (tr ? 'Oturma Odası' : 'Living Room') : s.googleHomeRoom;
    final statusTxt = widget.boiler.isHeating
        ? (tr ? '🔥 Isıtma %${widget.boiler.flamePercent}' : '🔥 Heating ${widget.boiler.flamePercent}%')
        : (tr ? '❄️ Bekleme' : '❄️ Standby');

    final thermoBadge = GestureDetector(
      onTap: _openThermostatModal,
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: compact ? 9 : 12, vertical: 6),
        decoration: BoxDecoration(
          color: const Color(0xFF14121D).withValues(alpha: 0.78),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
          boxShadow: [
            BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.14), blurRadius: 14),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.black.withValues(alpha: 0.45),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.6),
              ),
              child: const Icon(Icons.local_fire_department_outlined, size: 15, color: Color(0xFFFBBF24)),
            ),
            const SizedBox(width: 8),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  tr ? 'TERMOSTAT' : 'THERMOSTAT',
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.8,
                    color: Colors.white.withValues(alpha: 0.60),
                  ),
                ),
                Text(
                  '${widget.targetTemp.toStringAsFixed(1)}°C',
                  style: const TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                    color: Color(0xFFFBBF24),
                    fontFeatures: [FontFeature.tabularFigures()],
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    final weatherPill = Container(
      padding: EdgeInsets.symmetric(horizontal: compact ? 10 : 14, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFF14121D).withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(weatherIcon, size: 22, color: Colors.white.withValues(alpha: 0.78)),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '${outdoorTemp.toStringAsFixed(1)}°C',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                  height: 1.05,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                cityName,
                style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.65)),
              ),
            ],
          ),
        ],
      ),
    );

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Flexible(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: Colors.white.withValues(alpha: 0.12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                ),
                child: const Icon(Icons.local_fire_department_outlined, size: 19, color: Colors.white70),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      tr ? 'Kombi3D Akıllı Termostat' : 'Kombi3D Smart Thermostat',
                      style: const TextStyle(fontSize: 13.5, fontWeight: FontWeight.w700, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '$room · $statusTxt',
                      style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.72)),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Flexible(
          child: Wrap(
            spacing: 8,
            runSpacing: 6,
            alignment: WrapAlignment.end,
            children: [
              thermoBadge,
              weatherPill,
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildBottomLeftPill(bool tr) {
    final s = widget.settings;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF101018).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Visual Mode / Theme Quick Picker Button (orange badge matching Image 6)
          GestureDetector(
            onTap: () {
              _haptic();
              setState(() {
                _leftDrawerOpen = !_leftDrawerOpen;
                _rightDrawerOpen = false;
              });
            },
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFEA580C),
                boxShadow: [
                  BoxShadow(color: const Color(0xFFEA580C).withValues(alpha: 0.45), blurRadius: 10),
                ],
              ),
              child: const Icon(Icons.photo_library_outlined, size: 17, color: Colors.white),
            ),
          ),
          const SizedBox(width: 6),
          // 2. Play / Pause Button
          GestureDetector(
            onTap: _togglePause,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _paused ? const Color(0xFF6366F1).withValues(alpha: 0.36) : Colors.white.withValues(alpha: 0.10),
              ),
              child: Icon(
                _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                size: 18,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 6),
          // 3. Mute / Unmute Audio Button
          GestureDetector(
            onTap: _toggleMute,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _muted || s.ambientSoundtrack == AmbientSoundtrack.silent
                    ? const Color(0xFFEF4444).withValues(alpha: 0.24)
                    : const Color(0xFF0EA5E9).withValues(alpha: 0.28),
              ),
              child: Icon(
                _muted || s.ambientSoundtrack == AmbientSoundtrack.silent
                    ? Icons.volume_off_rounded
                    : Icons.volume_up_rounded,
                size: 17,
                color: _muted || s.ambientSoundtrack == AmbientSoundtrack.silent
                    ? const Color(0xFFFCA5A5)
                    : const Color(0xFF7DD3FC),
              ),
            ),
          ),
          const SizedBox(width: 4),
          // 4. Expand Upward Drawer Chevron
          GestureDetector(
            onTap: () {
              _haptic();
              setState(() {
                _leftDrawerOpen = !_leftDrawerOpen;
                _rightDrawerOpen = false;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                _leftDrawerOpen ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBottomRightPill(bool tr) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF101018).withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Brightness Cycle Button
          GestureDetector(
            onTap: _cycleBrightness,
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
              ),
              child: const Icon(Icons.wb_sunny_outlined, size: 17, color: Color(0xFFFCD34D)),
            ),
          ),
          const SizedBox(width: 6),
          // 2. Red Close / Exit Smart Display Button
          GestureDetector(
            onTap: () {
              _haptic();
              widget.onClose();
            },
            child: Container(
              width: 34,
              height: 34,
              decoration: const BoxDecoration(
                shape: BoxShape.circle,
                color: Color(0xFFE11D48),
              ),
              child: const Icon(Icons.close_rounded, size: 18, color: Colors.white),
            ),
          ),
          const SizedBox(width: 4),
          // 3. Expand Right Drawer Chevron
          GestureDetector(
            onTap: () {
              _haptic();
              setState(() {
                _rightDrawerOpen = !_rightDrawerOpen;
                _leftDrawerOpen = false;
              });
            },
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
              child: Icon(
                _rightDrawerOpen ? Icons.keyboard_arrow_down_rounded : Icons.keyboard_arrow_up_rounded,
                size: 18,
                color: Colors.white70,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLeftQuickDrawer(bool tr) {
    final s = widget.settings;
    final modes = [
      (SmartDisplayMode.aod, 'AOD'),
      (SmartDisplayMode.silentVideoMp3, 'Video+MP3'),
      (SmartDisplayMode.liveNature, tr ? 'Canlı Doğa' : 'Live Nature'),
      (SmartDisplayMode.slideshow, tr ? 'Slayt' : 'Slideshow'),
    ];
    final themes = [
      (SmartDisplayVisualTheme.fireplace, '🔥 ${tr ? 'Şömine' : 'Fire'}'),
      (SmartDisplayVisualTheme.rainy, '🌧️ ${tr ? 'Yağmur' : 'Rain'}'),
      (SmartDisplayVisualTheme.winterSnow, '❄️ ${tr ? 'Kar' : 'Snow'}'),
      (SmartDisplayVisualTheme.sunset, '🌲 ${tr ? 'Gün Batımı' : 'Sunset'}'),
      (SmartDisplayVisualTheme.aurora, '🌌 ${tr ? 'Kutup' : 'Aurora'}'),
      (SmartDisplayVisualTheme.minimalist, '🌚 ${tr ? 'Minimal' : 'Minimal'}'),
    ];
    final tracks = [
      (AmbientSoundtrack.silent, '🚫 ${tr ? 'Sessiz' : 'Mute'}'),
      (AmbientSoundtrack.fireplaceCrackling, '🔥 ${tr ? 'Şömine' : 'Fire'}'),
      (AmbientSoundtrack.nightRain, '🌧️ ${tr ? 'Yağmur' : 'Rain'}'),
      (AmbientSoundtrack.cozyJazzLofi, '🎧 Lo-Fi'),
      (AmbientSoundtrack.relaxPiano, '🎹 ${tr ? 'Piyano' : 'Piano'}'),
      (AmbientSoundtrack.forestBreeze, '🌲 ${tr ? 'Doğa' : 'Nature'}'),
    ];

    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 380),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFF101018).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr ? 'Hızlı Mod & Ambiyans Kontrolü' : 'Quick Mode & Ambience',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
                ),
                if (s.smartDisplayMode == SmartDisplayMode.slideshow)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _MiniChipAction(
                        label: '‹',
                        onTap: () => widget.onStepSlideIndex(-1),
                      ),
                      const SizedBox(width: 4),
                      _MiniChipAction(
                        label: '›',
                        onTap: () => widget.onStepSlideIndex(1),
                      ),
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 7),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final m in modes)
                  _QuickPill(
                    label: m.$2,
                    active: s.smartDisplayMode == m.$1,
                    activeColor: const Color(0xFFF59E0B),
                    onTap: () => widget.onUpdateSettings(s.copyWith(smartDisplayMode: m.$1)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final th in themes)
                  _QuickPill(
                    label: th.$2,
                    active: s.smartDisplayVisualTheme == th.$1,
                    activeColor: const Color(0xFF0EA5E9),
                    onTap: () => widget.onUpdateSettings(s.copyWith(smartDisplayVisualTheme: th.$1)),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 5,
              runSpacing: 5,
              children: [
                for (final tk in tracks)
                  _QuickPill(
                    label: tk.$2,
                    active: s.ambientSoundtrack == tk.$1 && !_muted,
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      setState(() => _muted = tk.$1 == AmbientSoundtrack.silent);
                      widget.onUpdateSettings(s.copyWith(ambientSoundtrack: tk.$1));
                      if (tk.$1 == AmbientSoundtrack.silent) {
                        AmbientAudioService.stop();
                      } else {
                        AmbientAudioService.start(
                          track: tk.$1,
                          customSource: s.customAudioSource,
                          volume: s.ambientVolume <= 0.05 ? 0.5 : s.ambientVolume,
                        );
                      }
                    },
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRightQuickDrawer(bool tr) {
    final s = widget.settings;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 270),
      child: Container(
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: const Color(0xFF101018).withValues(alpha: 0.92),
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr ? 'Ekran Parlaklığı: %${s.displayBrightness}' : 'Brightness: ${s.displayBrightness}%',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFCD34D)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (final b in [20, 50, 85, 100])
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: _QuickPill(
                        label: '%$b',
                        active: s.displayBrightness == b,
                        activeColor: const Color(0xFFF59E0B),
                        onTap: () {
                          widget.onUpdateSettings(s.copyWith(displayBrightness: b));
                          HardwareService.enterSmartDisplayHardware(
                            brightnessPercent: b,
                            keepAwake: s.displaySleepMinutes == 0,
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _CircleMiniBtn extends StatelessWidget {
  final IconData icon;
  final bool enabled;
  final VoidCallback onTap;

  const _CircleMiniBtn({
    required this.icon,
    required this.enabled,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1.0 : 0.35,
        child: Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: Colors.white.withValues(alpha: 0.14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
          ),
          child: Icon(icon, size: 15, color: Colors.white),
        ),
      ),
    );
  }
}

class _QuickPill extends StatelessWidget {
  final String label;
  final bool active;
  final Color activeColor;
  final VoidCallback onTap;

  const _QuickPill({
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
        decoration: BoxDecoration(
          color: active ? activeColor.withValues(alpha: 0.28) : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: active ? activeColor : Colors.white.withValues(alpha: 0.12),
          ),
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Colors.white),
        ),
      ),
    );
  }
}

class _MiniChipAction extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _MiniChipAction({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white)),
      ),
    );
  }
}

/// Embedded Thermostat Popup inside Smart Display (Image 7)
class _EmbeddedThermostatModal extends StatelessWidget {
  final double targetTemp;
  final double roomTemp;
  final BoilerTelemetry boiler;
  final Color accentColor;
  final String paletteTag;
  final int countdownSeconds;
  final LangCode lang;
  final VoidCallback onInteract;
  final ValueChanged<double> onChangeTarget;
  final ValueChanged<ThermostatPreset> onSelectPreset;
  final VoidCallback onClose;

  const _EmbeddedThermostatModal({
    required this.targetTemp,
    required this.roomTemp,
    required this.boiler,
    required this.accentColor,
    required this.paletteTag,
    required this.countdownSeconds,
    required this.lang,
    required this.onInteract,
    required this.onChangeTarget,
    required this.onSelectPreset,
    required this.onClose,
  });

  void _updateFromOffset(Offset localPos, double dialSize) {
    final center = Offset(dialSize / 2, dialSize / 2);
    final dx = localPos.dx - center.dx;
    final dy = localPos.dy - center.dy;
    final next = ThermostatMath.pointerOffsetToTemp(dx, dy);
    onInteract();
    if ((next - targetTemp).abs() >= 0.05) {
      onChangeTarget(next);
    }
  }

  @override
  Widget build(BuildContext context) {
    final tr = lang == LangCode.tr;
    final size = MediaQuery.of(context).size;
    final dialSize = math.min(230.0, math.max(168.0, size.height * 0.30));
    final diff = targetTemp - roomTemp;
    final diffText = '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}°C';

    const presetOrder = [PresetId.gece, PresetId.eko, PresetId.konfor, PresetId.boost];
    final presets = [
      for (final id in presetOrder) ThermostatMath.presets.firstWhere((p) => p.id == id),
    ];

    IconData iconFor(PresetId id) {
      switch (id) {
        case PresetId.gece:
          return Icons.nights_stay_outlined;
        case PresetId.eko:
          return Icons.eco_outlined;
        case PresetId.konfor:
          return Icons.local_fire_department_outlined;
        case PresetId.boost:
          return Icons.bolt_rounded;
      }
    }

    Color colorFor(PresetId id) {
      switch (id) {
        case PresetId.gece:
          return const Color(0xFF60A5FA);
        case PresetId.eko:
          return const Color(0xFF34D399);
        case PresetId.konfor:
          return const Color(0xFFFBBF24);
        case PresetId.boost:
          return const Color(0xFFF43F5E);
      }
    }

    return Listener(
      onPointerDown: (_) => onInteract(),
      child: Container(
        color: Colors.black.withValues(alpha: 0.72),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF13101C),
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 32, offset: const Offset(0, 14)),
              ],
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Header
                  Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                        ),
                        child: const Icon(Icons.local_fire_department_outlined, size: 19, color: Color(0xFFFBBF24)),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Wrap(
                              spacing: 8,
                              crossAxisAlignment: WrapCrossAlignment.center,
                              children: [
                                Text(
                                  tr ? 'Termostat Kontrolü' : 'Thermostat Control',
                                  style: const TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.42)),
                                  ),
                                  child: Text(
                                    paletteTag.toUpperCase(),
                                    style: const TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: Color(0xFFFBBF24),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr ? 'Hassas dokunmatik sıcaklık ayarı' : 'Precision touch temperature control',
                              style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.56)),
                            ),
                          ],
                        ),
                      ),
                      GestureDetector(
                        onTap: onClose,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                          ),
                          child: const Icon(Icons.close_rounded, size: 18, color: Colors.white70),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5-second Inactivity Countdown Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr ? 'Dokunulmazsa otomatik ambiyansa döner' : 'Auto-returns to ambient mode if idle',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            tr ? '$countdownSeconds sn' : '${countdownSeconds}s',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFFFBBF24),
                              fontFeatures: [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Interactive Circular Arc Dial
                  GestureDetector(
                    onPanDown: (d) => _updateFromOffset(d.localPosition, dialSize),
                    onPanUpdate: (d) => _updateFromOffset(d.localPosition, dialSize),
                    child: SizedBox(
                      width: dialSize,
                      height: dialSize,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          CustomPaint(
                            size: Size(dialSize, dialSize),
                            painter: _ModalArcDialPainter(
                              angleDeg: ThermostatMath.tempToAngleDeg(targetTemp),
                            ),
                          ),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                tr ? 'Hedef Sıcaklık' : 'Target Temp',
                                style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: Color(0xFFFBBF24),
                                ),
                              ),
                              const SizedBox(height: 2),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    targetTemp.toStringAsFixed(1),
                                    style: const TextStyle(
                                      fontSize: 40,
                                      fontWeight: FontWeight.w800,
                                      color: Colors.white,
                                      height: 1.0,
                                      fontFeatures: [FontFeature.tabularFigures()],
                                    ),
                                  ),
                                  const Padding(
                                    padding: EdgeInsets.only(top: 4),
                                    child: Text(
                                      '°C',
                                      style: TextStyle(
                                        fontSize: 18,
                                        fontWeight: FontWeight.w800,
                                        color: Color(0xFFF59E0B),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                decoration: BoxDecoration(
                                  color: boiler.isHeating
                                      ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
                                      : Colors.white.withValues(alpha: 0.08),
                                  borderRadius: BorderRadius.circular(999),
                                  border: Border.all(
                                    color: boiler.isHeating
                                        ? const Color(0xFFF59E0B)
                                        : Colors.white.withValues(alpha: 0.14),
                                  ),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.local_fire_department_outlined,
                                      size: 13,
                                      color: boiler.isHeating ? const Color(0xFFFBBF24) : Colors.white70,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      boiler.isHeating
                                          ? (tr ? 'Isıtıyor %${boiler.flamePercent}' : 'Heating ${boiler.flamePercent}%')
                                          : (tr ? 'Beklemede' : 'Standby'),
                                      style: const TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(height: 7),
                              RichText(
                                text: TextSpan(
                                  style: const TextStyle(fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()]),
                                  children: [
                                    TextSpan(
                                      text: tr ? 'Oda: ' : 'Room: ',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.65)),
                                    ),
                                    TextSpan(
                                      text: '${roomTemp.toStringAsFixed(1)}°C ',
                                      style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700),
                                    ),
                                    TextSpan(
                                      text: '($diffText)',
                                      style: TextStyle(color: Colors.white.withValues(alpha: 0.56)),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),

                  // Stepper Row (- | HASSAS ADIM 0.5°C | +)
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      GestureDetector(
                        onTap: targetTemp > ThermostatMath.minTemp
                            ? () => onChangeTarget(
                                  ThermostatMath.snapTemperature(targetTemp - ThermostatMath.tempStep),
                                )
                            : null,
                        child: Container(
                          width: 46,
                          height: 44,
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                          ),
                          child: const Icon(Icons.remove_rounded, color: Color(0xFFFBBF24), size: 22),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.05),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                        ),
                        child: Column(
                          children: [
                            Text(
                              tr ? 'HASSAS ADIM' : 'PRECISION STEP',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 0.8,
                                color: Colors.white.withValues(alpha: 0.56),
                              ),
                            ),
                            const Text(
                              '0.5°C',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.w800,
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      GestureDetector(
                        onTap: targetTemp < ThermostatMath.maxTemp
                            ? () => onChangeTarget(
                                  ThermostatMath.snapTemperature(targetTemp + ThermostatMath.tempStep),
                                )
                            : null,
                        child: Container(
                          width: 46,
                          height: 44,
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(colors: [Color(0xFFF59E0B), Color(0xFFD97706)]),
                            borderRadius: BorderRadius.circular(14),
                            boxShadow: [
                              BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.45), blurRadius: 14),
                            ],
                          ),
                          child: const Icon(Icons.add_rounded, color: Colors.white, size: 22),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  Divider(color: Colors.white.withValues(alpha: 0.10), height: 1),
                  const SizedBox(height: 12),

                  // 4 Preset Cards (Gece 18.5°C, Eko 20°C, Konfor 22.5°C, Boost 25°C)
                  Row(
                    children: [
                      for (final p in presets) ...[
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(right: p.id == PresetId.boost ? 0 : 7),
                            child: GestureDetector(
                              onTap: () => onSelectPreset(p),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 4),
                                decoration: BoxDecoration(
                                  color: (targetTemp - p.temp).abs() < 0.05
                                      ? colorFor(p.id).withValues(alpha: 0.18)
                                      : Colors.white.withValues(alpha: 0.04),
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: (targetTemp - p.temp).abs() < 0.05
                                        ? colorFor(p.id)
                                        : Colors.white.withValues(alpha: 0.10),
                                  ),
                                ),
                                child: Column(
                                  children: [
                                    Icon(iconFor(p.id), size: 15, color: colorFor(p.id)),
                                    const SizedBox(height: 4),
                                    Text(
                                      tr ? p.labelTr : p.labelEn,
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                        color: (targetTemp - p.temp).abs() < 0.05 ? colorFor(p.id) : Colors.white,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      '${p.temp % 1 == 0 ? p.temp.toStringAsFixed(0) : p.temp.toStringAsFixed(1)}°C',
                                      style: TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: (targetTemp - p.temp).abs() < 0.05
                                            ? colorFor(p.id)
                                            : Colors.white.withValues(alpha: 0.56),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Bottom Return CTA
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: onClose,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: const Color(0xFFFBBF24),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                        backgroundColor: Colors.white.withValues(alpha: 0.04),
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: const Icon(Icons.auto_awesome_outlined, size: 16),
                      label: Text(
                        tr ? 'Sinematik Ambiyans Moduna Dön' : 'Return to Cinematic Ambient Mode',
                        style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ModalArcDialPainter extends CustomPainter {
  final double angleDeg; // -135 to +135 (0 deg = top 12 o'clock)

  const _ModalArcDialPainter({required this.angleDeg});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width * 0.43;
    final rect = Rect.fromCircle(center: center, radius: radius);

    // Track: from 135 deg (bottom-left) clockwise 270 deg
    const startRad = 135.0 * math.pi / 180.0;
    const fullSweep = 270.0 * math.pi / 180.0;

    final trackPaint = Paint()
      ..color = Colors.white.withValues(alpha: 0.10)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, startRad, fullSweep, false, trackPaint);

    // Normalized progress [0..1]
    final progress = ((angleDeg + 135.0) / 270.0).clamp(0.0, 1.0);
    final activeSweep = fullSweep * progress;
    if (activeSweep > 0.02) {
      final activePaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 10
        ..strokeCap = StrokeCap.round
        ..shader = const SweepGradient(
          startAngle: startRad,
          endAngle: startRad + fullSweep,
          colors: [
            Color(0xFF10B981),
            Color(0xFFF59E0B),
            Color(0xFFEA580C),
            Color(0xFFEF4444),
          ],
        ).createShader(rect);
      canvas.drawArc(rect, startRad, activeSweep, false, activePaint);
    }

    // Thumb knob at active position
    final thumbRad = (angleDeg - 90.0) * math.pi / 180.0;
    final thumbPos = Offset(
      center.dx + math.cos(thumbRad) * radius,
      center.dy + math.sin(thumbRad) * radius,
    );
    canvas.drawCircle(
      thumbPos,
      12,
      Paint()..color = const Color(0xFFF59E0B).withValues(alpha: 0.35),
    );
    canvas.drawCircle(
      thumbPos,
      8.5,
      Paint()..color = const Color(0xFFF59E0B),
    );
    canvas.drawCircle(
      thumbPos,
      6.0,
      Paint()..color = Colors.white.withValues(alpha: 0.92),
    );
  }

  @override
  bool shouldRepaint(covariant _ModalArcDialPainter oldDelegate) => oldDelegate.angleDeg != angleDeg;
}

class _SmartEqualizerPainter extends CustomPainter {
  final double phase;
  final EqualizerStyle style;
  final Color color;
  final double intensity;

  const _SmartEqualizerPainter({
    required this.phase,
    required this.style,
    required this.color,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case EqualizerStyle.bars:
        const count = 18;
        final barW = (size.width / count) * 0.56;
        final step = size.width / count;
        final paint = Paint()..style = PaintingStyle.fill;
        for (int i = 0; i < count; i++) {
          final wave = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(phase * 1.4 + i * 0.65));
          final h = (size.height * wave * intensity).clamp(4.0, size.height);
          paint.color = Color.lerp(color, const Color(0xFF38BDF8), i / count)!.withValues(alpha: 0.85);
          canvas.drawRRect(
            RRect.fromRectAndRadius(
              Rect.fromLTWH(i * step + (step - barW) / 2, size.height - h, barW, h),
              const Radius.circular(3),
            ),
            paint,
          );
        }
        break;
      case EqualizerStyle.wave:
        final path = Path();
        final midY = size.height / 2;
        for (double x = 0; x <= size.width; x += 4) {
          final norm = x / size.width;
          final y = midY +
              math.sin(norm * math.pi * 4 + phase * 1.6) *
                  (size.height * 0.36 * intensity) *
                  math.sin(norm * math.pi);
          if (x == 0) {
            path.moveTo(x, y);
          } else {
            path.lineTo(x, y);
          }
        }
        canvas.drawPath(
          path,
          Paint()
            ..color = const Color(0xFF38BDF8).withValues(alpha: 0.90)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.4
            ..strokeCap = StrokeCap.round,
        );
        break;
      case EqualizerStyle.pulse:
        final center = Offset(size.width / 2, size.height / 2);
        for (int r = 0; r < 3; r++) {
          final t = ((phase / (math.pi * 2)) + r * 0.33) % 1.0;
          final radius = 4.0 + t * (size.width * 0.38) * intensity;
          canvas.drawOval(
            Rect.fromCenter(center: center, width: radius * 2, height: (size.height * 0.85) * t + 4),
            Paint()
              ..color = color.withValues(alpha: (1.0 - t) * 0.75)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0,
          );
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SmartEqualizerPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.style != style || oldDelegate.intensity != intensity;
}

class _SmartDisplayScenePainter extends CustomPainter {
  final SmartDisplayVisualTheme theme;
  final double phase;
  final bool drawBackdrop;

  const _SmartDisplayScenePainter({
    required this.theme,
    required this.phase,
    this.drawBackdrop = true,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    switch (theme) {
      case SmartDisplayVisualTheme.fireplace:
        if (drawBackdrop) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF1A0905), Color(0xFF451306), Color(0xFF0E0402)],
              ).createShader(rect),
          );
        }
        // Flickering warm fire glow pulse & floating embers
        final emberCenter = Offset(size.width * 0.5, size.height * 0.72);
        final flicker = 0.5 + 0.5 * math.sin(phase * math.pi * 10);
        final glowR = size.shortestSide * (0.46 + 0.06 * flicker);
        canvas.drawCircle(
          emberCenter,
          glowR,
          Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFFEA580C).withValues(alpha: drawBackdrop ? 0.65 : (0.14 + 0.12 * flicker)),
                const Color(0xFF9A3412).withValues(alpha: drawBackdrop ? 0.25 : 0.06),
                Colors.transparent,
              ],
            ).createShader(Rect.fromCircle(center: emberCenter, radius: glowR)),
        );
        for (int i = 0; i < 28; i++) {
          final seed = i * 1.37;
          final progress = (phase * 1.6 + seed) % 1.0;
          final x = size.width * (0.22 + 0.56 * ((math.sin(seed * 7.1) + 1) / 2)) +
              math.sin(progress * math.pi * 3 + seed) * 16;
          final y = size.height * (0.90 - progress * 0.70);
          canvas.drawCircle(
            Offset(x, y),
            1.6 + (i % 3) * 0.7,
            Paint()..color = const Color(0xFFFBBF24).withValues(alpha: (1.0 - progress) * 0.72),
          );
        }
        break;

      case SmartDisplayVisualTheme.rainy:
        if (drawBackdrop) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0B1628), Color(0xFF162B47), Color(0xFF09111E)],
              ).createShader(rect),
          );
        }
        final rainPaint = Paint()
          ..color = const Color(0xFFBFDBFE).withValues(alpha: drawBackdrop ? 0.34 : 0.22)
          ..strokeWidth = 1.3
          ..strokeCap = StrokeCap.round;
        for (int i = 0; i < 42; i++) {
          final col = ((i * 29) % 100) / 100.0;
          final fall = (phase * 3.0 + i * 0.13) % 1.0;
          final x = col * size.width - fall * 24;
          final y = fall * (size.height + 60) - 30;
          canvas.drawLine(Offset(x, y), Offset(x - 5, y + 20), rainPaint);
        }
        // Slow sliding water droplets on window glass
        for (int d = 0; d < 12; d++) {
          final col = ((d * 41 + 13) % 100) / 100.0;
          final drip = (phase * 0.65 + d * 0.19) % 1.0;
          final x = col * size.width + math.sin(drip * math.pi * 4 + d) * 3;
          final y = drip * size.height;
          canvas.drawCircle(
            Offset(x, y),
            2.2 + (d % 2),
            Paint()..color = Colors.white.withValues(alpha: 0.28),
          );
        }
        break;

      case SmartDisplayVisualTheme.winterSnow:
        if (drawBackdrop) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF0C1A32), Color(0xFF1E3A5F), Color(0xFF0B1424)],
              ).createShader(rect),
          );
        }
        for (int i = 0; i < 52; i++) {
          final seed = i * 0.73;
          final fall = (phase * 1.3 + seed) % 1.0;
          final x = (((i * 37) % 100) / 100.0) * size.width + math.sin(fall * math.pi * 2 + seed) * 22;
          final y = fall * size.height;
          canvas.drawCircle(
            Offset(x, y),
            1.4 + (i % 4) * 0.75,
            Paint()..color = Colors.white.withValues(alpha: (0.62 - fall * 0.28).clamp(0.1, 0.7)),
          );
        }
        break;

      case SmartDisplayVisualTheme.sunset:
        if (drawBackdrop) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: [0.0, 0.42, 0.56, 0.78, 1.0],
                colors: [
                  Color(0xFF2E384E),
                  Color(0xFFB4785A),
                  Color(0xFFE09F67),
                  Color(0xFF174A54),
                  Color(0xFF1B242B),
                ],
              ).createShader(rect),
          );
        }
        final sunCenter = Offset(size.width * 0.62, size.height * 0.44);
        final pulse = 0.5 + 0.5 * math.sin(phase * math.pi * 2);
        final sunRadius = size.shortestSide * (0.28 + 0.04 * pulse);
        canvas.drawCircle(
          sunCenter,
          sunRadius,
          Paint()
            ..shader = RadialGradient(
              colors: [
                const Color(0xFFFDE68A).withValues(alpha: drawBackdrop ? 0.65 : (0.14 + 0.08 * pulse)),
                const Color(0xFFF59E0B).withValues(alpha: drawBackdrop ? 0.20 : 0.06),
                Colors.transparent,
              ],
            ).createShader(Rect.fromCircle(center: sunCenter, radius: sunRadius)),
        );
        final wavePaint = Paint()
          ..color = const Color(0xFFFDE68A).withValues(alpha: drawBackdrop ? 0.16 : 0.10)
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.4;
        for (int w = 0; w < 4; w++) {
          final baseY = size.height * (0.68 + w * 0.07);
          final path = Path();
          for (double x = 0; x <= size.width; x += 14) {
            final y = baseY + math.sin((x / size.width) * math.pi * 4 + phase * math.pi * 2 + w) * 4;
            if (x == 0) {
              path.moveTo(x, y);
            } else {
              path.lineTo(x, y);
            }
          }
          canvas.drawPath(path, wavePaint);
        }
        break;

      case SmartDisplayVisualTheme.aurora:
        if (drawBackdrop) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Color(0xFF040814), Color(0xFF0A1D2A), Color(0xFF070B16)],
              ).createShader(rect),
          );
        }
        for (int b = 0; b < 3; b++) {
          final bandY = size.height * (0.24 + b * 0.11);
          final ribbon = Path()..moveTo(0, bandY);
          for (double x = 0; x <= size.width; x += 16) {
            final y = bandY + math.sin((x / size.width) * math.pi * 2.5 + phase * math.pi * 2 + b * 1.4) * 28;
            ribbon.lineTo(x, y);
          }
          ribbon.lineTo(size.width, bandY + 85);
          ribbon.lineTo(0, bandY + 85);
          ribbon.close();
          canvas.drawPath(
            ribbon,
            Paint()
              ..shader = LinearGradient(
                colors: [
                  (b == 1 ? const Color(0xFF8B5CF6) : const Color(0xFF10B981))
                      .withValues(alpha: drawBackdrop ? 0.34 : 0.16),
                  Colors.transparent,
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ).createShader(Rect.fromLTWH(0, bandY - 40, size.width, 130)),
          );
        }
        // Subtle twinkling night stars
        for (int st = 0; st < 20; st++) {
          final sx = (((st * 53) % 97) / 97.0) * size.width;
          final sy = (((st * 31) % 45) / 100.0) * size.height;
          final tw = 0.25 + 0.55 * (0.5 + 0.5 * math.sin(phase * math.pi * 4 + st));
          canvas.drawCircle(Offset(sx, sy), 1.1, Paint()..color = Colors.white.withValues(alpha: tw));
        }
        break;

      case SmartDisplayVisualTheme.minimalist:
        if (drawBackdrop) {
          canvas.drawRect(
            rect,
            Paint()
              ..shader = const RadialGradient(
                center: Alignment(0, -0.1),
                radius: 1.1,
                colors: [Color(0xFF1B1C24), Color(0xFF09090D)],
              ).createShader(rect),
          );
        }
        final breathe = 0.25 + 0.04 * math.sin(phase * math.pi * 2);
        canvas.drawCircle(
          Offset(size.width / 2, size.height / 2),
          size.shortestSide * breathe,
          Paint()
            ..color = Colors.white.withValues(alpha: 0.05)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SmartDisplayScenePainter oldDelegate) =>
      oldDelegate.theme != theme || oldDelegate.phase != phase || oldDelegate.drawBackdrop != drawBackdrop;
}
