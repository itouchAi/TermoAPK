import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../models/thermostat_state.dart';
import '../services/ambient_audio_service.dart';
import '../services/hardware_service.dart';
import '../services/video_source_bridge.dart';
import 'rotary_dial.dart';

class SmartDisplayOverlay extends StatefulWidget {
  final SystemSettingsState settings;
  final int slideIndex;
  final DateTime now;
  final String locationName;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final Color accentColor;
  final ThemePaletteSpec palette;
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
    required this.palette,
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

  /// Gentle 12-minute OLED burn-in drift (max +/- 1.5 px) without 1-second micro jitter.
  static Offset computeGentleBurnInShift(DateTime now, {required bool enabled}) {
    if (!enabled) return Offset.zero;
    final window = ((now.hour * 60 + now.minute) ~/ 12) % 4;
    switch (window) {
      case 0:
        return const Offset(-1.5, -1.0);
      case 1:
        return const Offset(1.5, -1.0);
      case 2:
        return const Offset(1.5, 1.5);
      default:
        return const Offset(-1.5, 1.5);
    }
  }

  @override
  State<SmartDisplayOverlay> createState() => _SmartDisplayOverlayState();
}

class _SmartDisplayOverlayState extends State<SmartDisplayOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;
  bool _hudHidden = false;
  bool _controlsIdleHidden = false;
  bool _paused = false;
  bool _muted = false;
  bool _shuffleEnabled = false;
  bool _leftExpanded = false;
  bool _rightExpanded = false;
  bool _volumePopupOpen = false;
  bool _draggingBrightness = false;
  bool _leftDrawerOpen = false;
  bool _thermostatModalOpen = false;
  int _thermostatCountdown = 5;
  Timer? _thermostatTimer;
  Timer? _idleControlsTimer;
  Timer? _leftCollapseTimer;
  Timer? _rightCollapseTimer;
  String? _hudHintBanner;
  Timer? _hintTimer;
  final math.Random _rng = math.Random();

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

  double get _effectiveBlurSigma => _effectiveMode == SmartDisplayMode.aod ? 0.0 : widget.settings.smartDisplayBlur;

  void _syncDomVideoBlur() {
    VideoSourceBridge.applyDomVideoBlur(_effectiveBlurSigma);
  }

  void _wakeBottomControls() {
    _idleControlsTimer?.cancel();
    if (mounted && _controlsIdleHidden) {
      setState(() => _controlsIdleHidden = false);
    }
    _idleControlsTimer = Timer(const Duration(seconds: 10), () {
      if (!mounted) return;
      if (_thermostatModalOpen || _volumePopupOpen || _draggingBrightness || _leftDrawerOpen) {
        _wakeBottomControls();
        return;
      }
      setState(() {
        _controlsIdleHidden = true;
        _leftExpanded = false;
        _rightExpanded = false;
      });
    });
  }

  void _scheduleLeftCollapse() {
    _leftCollapseTimer?.cancel();
    if (!_leftExpanded || _volumePopupOpen) return;
    _leftCollapseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (_leftExpanded && !_volumePopupOpen) {
        setState(() => _leftExpanded = false);
      }
    });
  }

  void _scheduleRightCollapse() {
    _rightCollapseTimer?.cancel();
    if (!_rightExpanded || _draggingBrightness) return;
    _rightCollapseTimer = Timer(const Duration(milliseconds: 1500), () {
      if (!mounted) return;
      if (_rightExpanded && !_draggingBrightness) {
        setState(() => _rightExpanded = false);
      }
    });
  }

  @override
  void initState() {
    super.initState();
    _muted = widget.settings.ambientSoundtrack == AmbientSoundtrack.silent ||
        widget.settings.ambientVolume <= 0.01;
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 12))..repeat();
    _syncVideoController();
    _wakeBottomControls();
    WidgetsBinding.instance.addPostFrameCallback((_) => _syncDomVideoBlur());
  }

  @override
  void didUpdateWidget(covariant SmartDisplayOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.settings.ambientSoundtrack != widget.settings.ambientSoundtrack) {
      _muted = widget.settings.ambientSoundtrack == AmbientSoundtrack.silent;
    }
    if (oldWidget.settings.customVideoSource != widget.settings.customVideoSource ||
        oldWidget.settings.smartDisplayMode != widget.settings.smartDisplayMode ||
        oldWidget.settings.smartDisplayVisualTheme != widget.settings.smartDisplayVisualTheme ||
        oldWidget.settings.slideImages.isEmpty != widget.settings.slideImages.isEmpty ||
        (widget.settings.slideImages.isEmpty &&
            _effectiveMode == SmartDisplayMode.slideshow &&
            oldWidget.slideIndex != widget.slideIndex) ||
        oldWidget.forcedAod != widget.forcedAod) {
      _syncVideoController();
    }
    if (oldWidget.settings.smartDisplayBlur != widget.settings.smartDisplayBlur ||
        oldWidget.forcedAod != widget.forcedAod ||
        oldWidget.settings.smartDisplayMode != widget.settings.smartDisplayMode) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _syncDomVideoBlur());
    }
  }

  @override
  void dispose() {
    _thermostatTimer?.cancel();
    _idleControlsTimer?.cancel();
    _leftCollapseTimer?.cancel();
    _rightCollapseTimer?.cancel();
    _hintTimer?.cancel();
    VideoSourceBridge.applyDomVideoBlur(0.0);
    _videoCtrl?.dispose();
    _animCtrl.dispose();
    super.dispose();
  }

  SmartDisplayVisualTheme _activeThemeForMode(SystemSettingsState s, SmartDisplayMode mode) {
    if (mode == SmartDisplayMode.slideshow) {
      const cycle = [
        SmartDisplayVisualTheme.sunset,
        SmartDisplayVisualTheme.fireplace,
        SmartDisplayVisualTheme.aurora,
        SmartDisplayVisualTheme.winterSnow,
        SmartDisplayVisualTheme.rainy,
      ];
      return cycle[widget.slideIndex % cycle.length];
    }
    return s.smartDisplayVisualTheme;
  }

  String _resolveWantedVideoSource(SystemSettingsState s, SmartDisplayMode mode) {
    if (mode == SmartDisplayMode.aod) return '';
    if (mode == SmartDisplayMode.silentVideoMp3) {
      final custom = s.customVideoSource.trim();
      if (custom.isNotEmpty) return custom;
      return smartDisplayThemeVideoUrl(s.smartDisplayVisualTheme) ?? '';
    }
    if (mode == SmartDisplayMode.liveNature) {
      return smartDisplayThemeVideoUrl(s.smartDisplayVisualTheme) ?? '';
    }
    if (mode == SmartDisplayMode.slideshow && s.slideImages.isEmpty) {
      return smartDisplayThemeVideoUrl(_activeThemeForMode(s, mode)) ?? '';
    }
    return '';
  }

  Future<void> _syncVideoController() async {
    final mode = _effectiveMode;
    final wanted = _resolveWantedVideoSource(widget.settings, mode);

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
      await ctrl.setVolume(0.0); // Video stays muted; user MP3 / ambient playlist supplies audio
      if (!_paused) {
        await ctrl.play();
      }
      if (mounted) {
        setState(() => _videoReady = true);
        WidgetsBinding.instance.addPostFrameCallback((_) => _syncDomVideoBlur());
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
        AmbientAudioService.pause();
      } else {
        _animCtrl.repeat();
        if (_videoReady) {
          _videoCtrl?.setVolume(0.0);
          _videoCtrl?.play();
        }
        AmbientAudioService.resume();
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

  void _stepSlideAndAudio(int delta) {
    _haptic();
    _wakeBottomControls();
    final s = widget.settings;
    final slideStep = _shuffleEnabled
        ? (s.slideImages.length > 1 ? 1 + _rng.nextInt(s.slideImages.length - 1) : 1 + _rng.nextInt(4))
        : delta;
    widget.onStepSlideIndex(slideStep);

    final hasCustom = s.customAudioSource.trim().isNotEmpty || s.customAudioLabel.trim().isNotEmpty;
    final nextTrack = AmbientAudioService.stepPlaylistTrack(
      s.ambientSoundtrack,
      delta,
      hasCustomAudio: hasCustom,
      shuffle: _shuffleEnabled,
    );
    final nextSettings = s.copyWith(ambientSoundtrack: nextTrack);
    widget.onUpdateSettings(nextSettings);
    if (!_muted && nextTrack != AmbientSoundtrack.silent) {
      AmbientAudioService.start(
        track: nextTrack,
        customSource: s.customAudioSource.isNotEmpty ? s.customAudioSource : s.customAudioLabel,
        volume: s.ambientVolume <= 0.05 ? 0.5 : s.ambientVolume,
      );
    }
    _scheduleLeftCollapse();
  }

  void _toggleHudHidden() {
    _haptic();
    _wakeBottomControls();
    final next = !_hudHidden;
    _hintTimer?.cancel();
    setState(() {
      _hudHidden = next;
      _leftDrawerOpen = false;
      _leftExpanded = false;
      _rightExpanded = false;
      _volumePopupOpen = false;
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
    _wakeBottomControls();
    setState(() {
      _thermostatModalOpen = true;
      _thermostatCountdown = 5;
      _leftDrawerOpen = false;
      _leftExpanded = false;
      _rightExpanded = false;
      _volumePopupOpen = false;
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

    // Gentle 12-minute OLED burn-in drift (max +/-1.5px, no 1s jitter)
    final aodShift = SmartDisplayOverlay.computeGentleBurnInShift(
      widget.now,
      enabled: s.oledPixelShiftEnabled || mode == SmartDisplayMode.aod,
    );

    final hh = widget.now.hour.toString().padLeft(2, '0');
    final mm = widget.now.minute.toString().padLeft(2, '0');
    final ss = widget.now.second.toString().padLeft(2, '0');
    final (cityName, outdoorTemp, weatherIcon) = _resolveOutdoorWeather();

    final dimAlpha = ((1.0 - (s.displayBrightness / 100.0)) * 0.72).clamp(0.0, 0.72);
    final isAudioActive = !_muted && !widget.forcedAod && s.ambientSoundtrack != AmbientSoundtrack.silent;

    final targetHeightFont = compactHeight
        ? size.height * 0.23
        : (isLandscape ? (size.height * 0.22).clamp(64.0, 156.0) : (size.width * 0.23).clamp(58.0, 128.0));
    final maxByWidth = ((size.width - 48) / 4.35).clamp(44.0, 168.0);
    final clockFontSize = math.min(targetHeightFont, maxByWidth);
    final secFontSize = (clockFontSize * 0.26).clamp(15.0, 38.0);
    final bottomControlsHidden = _hudHidden || _controlsIdleHidden;

    return Material(
      color: Colors.black,
      child: MouseRegion(
        onHover: (_) => _wakeBottomControls(),
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: (_) => _wakeBottomControls(),
          onPointerMove: (_) => _wakeBottomControls(),
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: () {
              _wakeBottomControls();
              if (widget.forcedAod) {
                widget.onWakeFromAutoAod?.call();
              }
            },
            child: Stack(
              fit: StackFit.expand,
              children: [
                // 1. Dynamic Full-Screen Visual / Video / Slide / Theme Backdrop Layer (+ Configurable Blur)
                Positioned.fill(
                  child: ClipRect(
                    child: (mode != SmartDisplayMode.aod && s.smartDisplayBlur > 0.1)
                        ? Transform.scale(
                            scale: 1.0 + s.smartDisplayBlur / 140.0,
                            child: ImageFiltered(
                              imageFilter: ui.ImageFilter.blur(
                                sigmaX: s.smartDisplayBlur,
                                sigmaY: s.smartDisplayBlur,
                                tileMode: ui.TileMode.clamp,
                              ),
                              child: _buildBackgroundLayer(s),
                            ),
                          )
                        : _buildBackgroundLayer(s),
                  ),
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

                // 3. Main Animated HUD Content (Header, Center Clock & Target Pill, Bottom Marquee & Floating Toolbars)
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
                                          // Huge Dynamic Crisp Clock HH : MM  ss
                                          FittedBox(
                                            fit: BoxFit.scaleDown,
                                            child: Row(
                                              mainAxisSize: MainAxisSize.min,
                                              crossAxisAlignment: CrossAxisAlignment.baseline,
                                              textBaseline: TextBaseline.alphabetic,
                                              children: [
                                                Text(
                                                  '$hh : $mm',
                                                  style: TextStyle(
                                                    fontSize: clockFontSize,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white.withValues(alpha: 0.94),
                                                    letterSpacing: 3.0,
                                                    height: 0.95,
                                                    fontFeatures: const [FontFeature.tabularFigures()],
                                                    shadows: [
                                                      Shadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 18),
                                                    ],
                                                  ),
                                                ),
                                                const SizedBox(width: 10),
                                                Text(
                                                  ss,
                                                  style: TextStyle(
                                                    fontSize: secFontSize,
                                                    fontWeight: FontWeight.w600,
                                                    color: Colors.white.withValues(alpha: 0.54),
                                                    fontFeatures: const [FontFeature.tabularFigures()],
                                                  ),
                                                ),
                                              ],
                                            ),
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
                                                  style: TextStyle(
                                                    color: Colors.white.withValues(alpha: 0.24),
                                                    fontSize: 14,
                                                  ),
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
                                            const SizedBox(height: 18),
                                            SizedBox(
                                              width: 268,
                                              height: 54,
                                              child: AnimatedBuilder(
                                                animation: _animCtrl,
                                                builder: (_, __) {
                                                  final pausedNow = _paused || !AmbientAudioService.isPlaying;
                                                  return CustomPaint(
                                                    painter: _SmartEqualizerPainter(
                                                      bands: AmbientAudioService.currentSpectrumBands(bandCount: 18),
                                                      beatPulse: AmbientAudioService.currentBeatPulse(),
                                                      paused: pausedNow,
                                                      style: s.equalizerStyle,
                                                      color: widget.accentColor,
                                                      intensity: s.ambientVolume.clamp(0.25, 1.0),
                                                    ),
                                                  );
                                                },
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

                        // Quick Upward Drawers / Volume Slider Popup
                        if (!bottomControlsHidden && (_leftDrawerOpen || _volumePopupOpen))
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: Align(
                              alignment: Alignment.bottomLeft,
                              child: _volumePopupOpen ? _buildUpwardVolumePopup(tr) : _buildLeftQuickDrawer(tr),
                            ),
                          ),

                        // BOTTOM-CENTER MARQUEE TRACK PILL (Img 10)
                        if (!_hudHidden && s.marqueeTrackEnabled && isAudioActive)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Center(
                              child: Container(
                                constraints: const BoxConstraints(maxWidth: 256),
                                padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.46),
                                  borderRadius: BorderRadius.circular(20),
                                  border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.36)),
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.music_note_rounded, size: 13, color: Color(0xFF7DD3FC)),
                                    const SizedBox(width: 6),
                                    Flexible(
                                      child: _ScrollingMarqueeText(
                                        text: '${s.ambientTrackTitle(widget.lang)} · %${(s.ambientVolume * 100).round()}',
                                        style: const TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: Color(0xFFE0F2FE),
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),

                        // BOTTOM TOOLBAR ROW (Auto-hides after 10s idle; Paintbrush stays clickable when HUD cleaned)
                        AnimatedOpacity(
                          opacity: _controlsIdleHidden ? 0.0 : 1.0,
                          duration: const Duration(milliseconds: 300),
                          child: IgnorePointer(
                            ignoring: _controlsIdleHidden,
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.end,
                              children: [
                                // Bottom-Left Collapsible Pill Bar (Img 3)
                                Flexible(
                                  child: AnimatedSlide(
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
                                ),

                                // Bottom-Right Collapsible Pill + Paintbrush Clean Toggle (Img 4)
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
                                            color: const Color(0xFFF59E0B).withValues(alpha: _hudHidden ? 0.45 : 0.55),
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
                          ),
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

                // 4. Embedded Termostat Kontrolü Modal (Img 9 - Theme Matched & Real RotaryDial)
                if (_thermostatModalOpen)
                  Positioned.fill(
                    child: _EmbeddedThermostatModal(
                      targetTemp: widget.targetTemp,
                      roomTemp: widget.roomTemp,
                      boiler: widget.boiler,
                      accentColor: widget.accentColor,
                      palette: widget.palette,
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

    // 1. Real Muted Video Backdrop (User Video in silentVideoMp3, or Wikimedia .webm Theme Video)
    if ((mode == SmartDisplayMode.silentVideoMp3 ||
            mode == SmartDisplayMode.liveNature ||
            (mode == SmartDisplayMode.slideshow && s.slideImages.isEmpty)) &&
        _videoCtrl != null &&
        _videoReady &&
        _videoCtrl!.value.isInitialized) {
      final vSize = _videoCtrl!.value.size;
      final vw = vSize.width > 0 ? vSize.width : 1280.0;
      final vh = vSize.height > 0 ? vSize.height : 720.0;
      return wrapTransition(
        ValueKey('video_bg_${_activeVideoSource.hashCode}'),
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

    // 2. Uploaded Slideshow Photos (clean static presentation with slide transitions; no zoom drift)
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
            child: Image.memory(
              bytes,
              fit: fit,
              width: double.infinity,
              height: double.infinity,
              gaplessPlayback: true,
            ),
          ),
        );
      }
    }

    // 3. Clean Dark Loader While Wikimedia / Custom Video Buffers (No Old Static Theme Images)
    final effectiveTheme = _activeThemeForMode(s, mode);
    if (effectiveTheme != SmartDisplayVisualTheme.minimalist &&
        (mode == SmartDisplayMode.silentVideoMp3 ||
            mode == SmartDisplayMode.liveNature ||
            (mode == SmartDisplayMode.slideshow && s.slideImages.isEmpty))) {
      return wrapTransition(
        ValueKey('video_loading_${mode.name}_${effectiveTheme.name}'),
        Container(
          color: const Color(0xFF07080D),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 24,
            height: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.0,
              valueColor: AlwaysStoppedAnimation<Color>(Color(0xFF38BDF8)),
            ),
          ),
        ),
      );
    }

    return wrapTransition(
      ValueKey('theme_${mode.name}_${effectiveTheme.name}_${widget.slideIndex}'),
      Container(
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.15),
            radius: 1.15,
            colors: [Color(0xFF1A1B24), Color(0xFF09090D)],
          ),
        ),
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
    final mutedNow = _muted || s.ambientSoundtrack == AmbientSoundtrack.silent;

    Widget circleIcon({
      required IconData icon,
      required VoidCallback onTap,
      Color? bgColor,
      Gradient? gradient,
      Color? borderColor,
      Color iconColor = Colors.white,
      double size = 34,
      double iconSize = 17,
      List<BoxShadow>? shadows,
    }) {
      return GestureDetector(
        onTap: onTap,
        child: Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: gradient == null ? bgColor : null,
            gradient: gradient,
            border: borderColor != null ? Border.all(color: borderColor) : null,
            boxShadow: shadows,
          ),
          child: Icon(icon, size: iconSize, color: iconColor),
        ),
      );
    }

    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B10).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14),
        ],
      ),
      child: ClipRect(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerLeft,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Music Note badge (opens Quick Mode/Theme/Ambience/Blur drawer)
              circleIcon(
                icon: Icons.music_note_rounded,
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFFF97316), Color(0xFFE11D48)],
                ),
                shadows: [
                  BoxShadow(color: const Color(0xFFF97316).withValues(alpha: 0.45), blurRadius: 10),
                ],
                onTap: () {
                  _haptic();
                  _wakeBottomControls();
                  setState(() {
                    _leftDrawerOpen = !_leftDrawerOpen;
                    _volumePopupOpen = false;
                  });
                  _scheduleLeftCollapse();
                },
              ),

              if (_leftExpanded) ...[
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(width: 1, height: 18, color: Colors.white.withValues(alpha: 0.14)),
                ),
                // Previous Track + Previous Slide
                circleIcon(
                  icon: Icons.skip_previous_rounded,
                  bgColor: Colors.white.withValues(alpha: 0.08),
                  onTap: () => _stepSlideAndAudio(-1),
                ),
                const SizedBox(width: 5),
                // Play / Pause Gradient Pill
                circleIcon(
                  icon: _paused ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFF59E0B), Color(0xFFE11D48)],
                  ),
                  shadows: [
                    BoxShadow(color: const Color(0xFFF59E0B).withValues(alpha: 0.42), blurRadius: 10),
                  ],
                  onTap: () {
                    _wakeBottomControls();
                    _togglePause();
                    _scheduleLeftCollapse();
                  },
                ),
                const SizedBox(width: 5),
                // Next Track + Next Slide
                circleIcon(
                  icon: Icons.skip_next_rounded,
                  bgColor: Colors.white.withValues(alpha: 0.08),
                  onTap: () => _stepSlideAndAudio(1),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6),
                  child: Container(width: 1, height: 18, color: Colors.white.withValues(alpha: 0.14)),
                ),
                // Shuffle Toggle
                circleIcon(
                  icon: Icons.shuffle_rounded,
                  bgColor: _shuffleEnabled
                      ? const Color(0xFFF59E0B).withValues(alpha: 0.24)
                      : Colors.white.withValues(alpha: 0.08),
                  borderColor: _shuffleEnabled ? const Color(0xFFF59E0B).withValues(alpha: 0.65) : null,
                  iconColor: _shuffleEnabled ? const Color(0xFFFBBF24) : Colors.white70,
                  onTap: () {
                    _haptic();
                    _wakeBottomControls();
                    setState(() => _shuffleEnabled = !_shuffleEnabled);
                    _scheduleLeftCollapse();
                  },
                ),
                const SizedBox(width: 5),
                // Upward Vertical Volume Slider & Mute Popup Trigger
                circleIcon(
                  icon: mutedNow ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                  bgColor: mutedNow
                      ? const Color(0xFFEF4444).withValues(alpha: 0.18)
                      : (_volumePopupOpen
                          ? const Color(0xFF38BDF8).withValues(alpha: 0.28)
                          : Colors.white.withValues(alpha: 0.08)),
                  borderColor: _volumePopupOpen ? const Color(0xFF38BDF8).withValues(alpha: 0.65) : null,
                  iconColor: mutedNow ? const Color(0xFFFCA5A5) : const Color(0xFF7DD3FC),
                  onTap: () {
                    _haptic();
                    _wakeBottomControls();
                    setState(() {
                      _volumePopupOpen = !_volumePopupOpen;
                      _leftDrawerOpen = false;
                    });
                    if (!_volumePopupOpen) {
                      _scheduleLeftCollapse();
                    } else {
                      _leftCollapseTimer?.cancel();
                    }
                  },
                ),
              ],

              const SizedBox(width: 4),
              // Expand Right '>' or Collapse Left '<' Arrow (Img 3)
              GestureDetector(
                onTap: () {
                  _haptic();
                  _wakeBottomControls();
                  setState(() {
                    _leftExpanded = !_leftExpanded;
                    if (!_leftExpanded) _volumePopupOpen = false;
                  });
                  if (_leftExpanded) {
                    _scheduleLeftCollapse();
                  } else {
                    _leftCollapseTimer?.cancel();
                  }
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                  child: Icon(
                    _leftExpanded ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                    size: 19,
                    color: Colors.white70,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomRightPill(bool tr) {
    final s = widget.settings;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 240),
      curve: Curves.easeOutCubic,
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
      decoration: BoxDecoration(
        color: const Color(0xFF0B0B10).withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.45), blurRadius: 14),
        ],
      ),
      child: ClipRect(
        child: AnimatedSize(
          duration: const Duration(milliseconds: 240),
          curve: Curves.easeOutCubic,
          alignment: Alignment.centerRight,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!_rightExpanded) ...[
                // Expand Left '<' Arrow (Img 4)
                GestureDetector(
                  onTap: () {
                    _haptic();
                    _wakeBottomControls();
                    setState(() => _rightExpanded = true);
                    _scheduleRightCollapse();
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Icon(Icons.chevron_left_rounded, size: 19, color: Colors.white70),
                  ),
                ),
                // Brightness Badge
                GestureDetector(
                  onTap: () {
                    _haptic();
                    _wakeBottomControls();
                    setState(() => _rightExpanded = true);
                    _scheduleRightCollapse();
                  },
                  child: Container(
                    width: 34,
                    height: 34,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFF59E0B).withValues(alpha: 0.22),
                      border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.42)),
                    ),
                    child: const Icon(Icons.wb_sunny_outlined, size: 17, color: Color(0xFFFCD34D)),
                  ),
                ),
              ] else ...[
                // Inline Brightness Slider Pill (Img 4: [ ☀️ ━━━━●━ %85 ])
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.wb_sunny_outlined, size: 16, color: Color(0xFFF59E0B)),
                      SizedBox(
                        width: 96,
                        height: 28,
                        child: SliderTheme(
                          data: SliderThemeData(
                            trackHeight: 4,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                            activeTrackColor: const Color(0xFFF59E0B),
                            inactiveTrackColor: Colors.white.withValues(alpha: 0.18),
                            thumbColor: const Color(0xFFFBBF24),
                          ),
                          child: Slider(
                            value: s.displayBrightness.clamp(10, 100).toDouble(),
                            min: 10,
                            max: 100,
                            onChangeStart: (_) {
                              _draggingBrightness = true;
                              _rightCollapseTimer?.cancel();
                              _wakeBottomControls();
                            },
                            onChanged: (val) {
                              final nextB = val.round().clamp(10, 100);
                              widget.onUpdateSettings(s.copyWith(displayBrightness: nextB));
                              HardwareService.enterSmartDisplayHardware(
                                brightnessPercent: nextB,
                                keepAwake: s.displaySleepMinutes == 0,
                              );
                            },
                            onChangeEnd: (_) {
                              _draggingBrightness = false;
                              _scheduleRightCollapse();
                            },
                          ),
                        ),
                      ),
                      Text(
                        '%${s.displayBrightness}',
                        style: const TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFFFBBF24),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ),
              ],

              const SizedBox(width: 6),
              // Red X Button (Completely exits Smart Display)
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

              if (_rightExpanded) ...[
                const SizedBox(width: 4),
                GestureDetector(
                  onTap: () {
                    _haptic();
                    _wakeBottomControls();
                    _rightCollapseTimer?.cancel();
                    setState(() => _rightExpanded = false);
                  },
                  child: const Padding(
                    padding: EdgeInsets.symmetric(horizontal: 6, vertical: 6),
                    child: Icon(Icons.chevron_right_rounded, size: 19, color: Colors.white70),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildUpwardVolumePopup(bool tr) {
    final s = widget.settings;
    final mutedNow = _muted || s.ambientSoundtrack == AmbientSoundtrack.silent;
    final vol = mutedNow ? 0.0 : s.ambientVolume.clamp(0.0, 1.0);

    return Container(
      width: 68,
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF101018).withValues(alpha: 0.94),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.55), blurRadius: 18),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '%${(vol * 100).round()}',
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w800,
              color: Color(0xFF7DD3FC),
              fontFeatures: [FontFeature.tabularFigures()],
            ),
          ),
          const SizedBox(height: 6),
          SizedBox(
            height: 120,
            child: RotatedBox(
              quarterTurns: -1,
              child: SliderTheme(
                data: SliderThemeData(
                  trackHeight: 4.5,
                  thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 7),
                  overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                  activeTrackColor: const Color(0xFF38BDF8),
                  inactiveTrackColor: Colors.white.withValues(alpha: 0.16),
                  thumbColor: Colors.white,
                ),
                child: Slider(
                  value: vol,
                  min: 0.0,
                  max: 1.0,
                  onChanged: (v) {
                    _wakeBottomControls();
                    final nextTrack = (v > 0.02 && s.ambientSoundtrack == AmbientSoundtrack.silent)
                        ? AmbientSoundtrack.fireplaceCrackling
                        : s.ambientSoundtrack;
                    setState(() => _muted = v <= 0.01);
                    widget.onUpdateSettings(s.copyWith(ambientVolume: v, ambientSoundtrack: nextTrack));
                    if (v <= 0.01) {
                      AmbientAudioService.stop();
                    } else if (!AmbientAudioService.isPlaying) {
                      AmbientAudioService.start(
                        track: nextTrack,
                        customSource: s.customAudioSource.isNotEmpty ? s.customAudioSource : s.customAudioLabel,
                        volume: v,
                      );
                    } else {
                      AmbientAudioService.setVolume(v);
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () {
              _wakeBottomControls();
              _toggleMute();
            },
            child: Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: mutedNow
                    ? const Color(0xFFEF4444).withValues(alpha: 0.24)
                    : const Color(0xFF0EA5E9).withValues(alpha: 0.24),
              ),
              child: Icon(
                mutedNow ? Icons.volume_off_rounded : Icons.volume_up_rounded,
                size: 16,
                color: mutedNow ? const Color(0xFFFCA5A5) : const Color(0xFF7DD3FC),
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
                  tr ? 'Hızlı Mod, Blur & Ambiyans' : 'Quick Mode, Blur & Ambience',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
                ),
                GestureDetector(
                  onTap: () => setState(() => _leftDrawerOpen = false),
                  child: const Icon(Icons.close_rounded, size: 16, color: Colors.white54),
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
            const SizedBox(height: 8),
            Row(
              children: [
                Text(
                  tr ? 'Blur:' : 'Blur:',
                  style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF93C5FD)),
                ),
                const SizedBox(width: 6),
                for (final bl in [0.0, 4.0, 10.0, 18.0])
                  Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: _QuickPill(
                      label: bl == 0 ? (tr ? 'Net' : 'Clear') : '${bl.toInt()}px',
                      active: (s.smartDisplayBlur - bl).abs() < 1.5,
                      activeColor: const Color(0xFF38BDF8),
                      onTap: () => widget.onUpdateSettings(s.copyWith(smartDisplayBlur: bl)),
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

/// Smooth Horizontal Marquee when text overflows capsule width
class _ScrollingMarqueeText extends StatefulWidget {
  final String text;
  final TextStyle style;

  const _ScrollingMarqueeText({
    required this.text,
    required this.style,
  });

  @override
  State<_ScrollingMarqueeText> createState() => _ScrollingMarqueeTextState();
}

class _ScrollingMarqueeTextState extends State<_ScrollingMarqueeText> with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(seconds: 6))..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final maxW = constraints.maxWidth.isFinite ? constraints.maxWidth : 210.0;
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: TextDirection.ltr,
        )..layout();
        final textW = painter.width;
        if (textW <= maxW) {
          return Text(widget.text, style: widget.style, maxLines: 1);
        }
        const gap = 36.0;
        final spanW = textW + gap;
        return ClipRect(
          child: SizedBox(
            width: maxW,
            height: painter.height,
            child: AnimatedBuilder(
              animation: _ctrl,
              builder: (_, __) {
                final dx = -(_ctrl.value * spanW);
                return Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Positioned(
                      left: dx,
                      top: 0,
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(widget.text, style: widget.style, maxLines: 1),
                          const SizedBox(width: gap),
                          Text(widget.text, style: widget.style, maxLines: 1),
                        ],
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }
}

/// Embedded Thermostat Popup inside Smart Display (Img 9: theme-matched & genuine RotaryDial)
class _EmbeddedThermostatModal extends StatelessWidget {
  final double targetTemp;
  final double roomTemp;
  final BoilerTelemetry boiler;
  final Color accentColor;
  final ThemePaletteSpec palette;
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
    required this.palette,
    required this.paletteTag,
    required this.countdownSeconds,
    required this.lang,
    required this.onInteract,
    required this.onChangeTarget,
    required this.onSelectPreset,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final tr = lang == LangCode.tr;
    final size = MediaQuery.of(context).size;
    final dialSize = math.min(220.0, math.max(166.0, size.height * 0.28));
    final diff = targetTemp - roomTemp;
    final diffText = '${diff >= 0 ? '+' : ''}${diff.toStringAsFixed(1)}°C';
    final isLight = palette.isLight;
    final themeAccent = palette.themeOverrideAccent?.toColor() ?? accentColor;
    final matchedPreset = ThermostatMath.findMatchingPreset(targetTemp);
    final modeName = matchedPreset != null
        ? (tr ? matchedPreset.modeNameTr : matchedPreset.modeNameEn)
        : (tr ? 'ÖZEL SICAKLIK' : 'CUSTOM TEMP');

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
        color: Colors.black.withValues(alpha: isLight ? 0.56 : 0.72),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: palette.sheetBg,
              borderRadius: BorderRadius.circular(24),
              border: Border.all(
                width: palette.isTactileDeck ? 1.5 : 1.0,
                color: palette.cardBorder,
              ),
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: isLight ? 0.25 : 0.65), blurRadius: 32, offset: const Offset(0, 14)),
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
                          color: themeAccent.withValues(alpha: 0.14),
                          border: Border.all(color: themeAccent.withValues(alpha: 0.45)),
                        ),
                        child: Icon(Icons.local_fire_department_outlined, size: 19, color: themeAccent),
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
                                  style: TextStyle(
                                    fontSize: 16.5,
                                    fontWeight: FontWeight.w800,
                                    color: palette.textPrimary,
                                  ),
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: themeAccent.withValues(alpha: 0.14),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(color: themeAccent.withValues(alpha: 0.42)),
                                  ),
                                  child: Text(
                                    paletteTag.toUpperCase(),
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.w800,
                                      color: themeAccent,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              tr ? 'Hassas dokunmatik sıcaklık ayarı' : 'Precision touch temperature control',
                              style: TextStyle(fontSize: 11, color: palette.textSecondary),
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
                            color: palette.cardBg,
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(color: palette.cardBorder),
                          ),
                          child: Icon(Icons.close_rounded, size: 18, color: palette.textSecondary),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // 5-second Inactivity Countdown Banner
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                    decoration: BoxDecoration(
                      color: palette.cardBg,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: palette.cardBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr ? 'Dokunulmazsa otomatik ambiyansa döner' : 'Auto-returns to ambient mode if idle',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w600,
                              color: themeAccent,
                            ),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: themeAccent.withValues(alpha: 0.14),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: themeAccent.withValues(alpha: 0.45)),
                          ),
                          child: Text(
                            tr ? '$countdownSeconds sn' : '${countdownSeconds}s',
                            style: TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w800,
                              color: themeAccent,
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),

                  // Real Main-Screen RotaryDial (45 segmented ticks + 3D bevel + circular - / + steppers)
                  RotaryDial(
                    targetTemp: targetTemp,
                    onChangeTarget: (t) {
                      onInteract();
                      onChangeTarget(t);
                    },
                    modeName: modeName,
                    accentColor: themeAccent,
                    boiler: boiler,
                    lang: lang,
                    palette: palette,
                    sizePx: dialSize,
                    compact: true,
                  ),
                  const SizedBox(height: 8),

                  // Room Temp & Delta Badge
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                    decoration: BoxDecoration(
                      color: palette.cardBg,
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: palette.cardBorder),
                    ),
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(fontSize: 11.5, fontFeatures: [FontFeature.tabularFigures()]),
                        children: [
                          TextSpan(
                            text: tr ? 'Oda: ' : 'Room: ',
                            style: TextStyle(color: palette.textSecondary),
                          ),
                          TextSpan(
                            text: '${roomTemp.toStringAsFixed(1)}°C ',
                            style: const TextStyle(color: Color(0xFF10B981), fontWeight: FontWeight.w700),
                          ),
                          TextSpan(
                            text: '($diffText)',
                            style: TextStyle(color: palette.textSecondary),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Divider(color: palette.cardBorder, height: 1),
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
                                      : palette.cardBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: (targetTemp - p.temp).abs() < 0.05
                                        ? colorFor(p.id)
                                        : palette.cardBorder,
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
                                        color: (targetTemp - p.temp).abs() < 0.05
                                            ? colorFor(p.id)
                                            : palette.textPrimary,
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
                                            : palette.textSecondary,
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
                        foregroundColor: themeAccent,
                        side: BorderSide(color: palette.cardBorder),
                        backgroundColor: palette.cardBg,
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

class _SmartEqualizerPainter extends CustomPainter {
  final List<double> bands;
  final double beatPulse;
  final bool paused;
  final EqualizerStyle style;
  final Color color;
  final double intensity;

  const _SmartEqualizerPainter({
    required this.bands,
    required this.beatPulse,
    required this.paused,
    required this.style,
    required this.color,
    required this.intensity,
  });

  double _bandAt(int i) {
    if (paused || bands.isEmpty) return 0.0;
    final idx = i.clamp(0, bands.length - 1);
    return bands[idx].clamp(0.0, 1.0);
  }

  @override
  void paint(Canvas canvas, Size size) {
    final count = bands.isEmpty ? 18 : bands.length;
    switch (style) {
      case EqualizerStyle.bars:
        final step = size.width / count;
        final barW = step * 0.58;
        for (int i = 0; i < count; i++) {
          final energy = _bandAt(i);
          final h = paused
              ? 3.0
              : (4.0 + size.height * 0.88 * energy * (0.85 + beatPulse * 0.22)).clamp(4.0, size.height - 4);
          final left = i * step + (step - barW) / 2;
          final barRect = Rect.fromLTWH(left, size.height - h, barW, h);
          final tipColor = Color.lerp(const Color(0xFF38BDF8), const Color(0xFFFBBF24), i / math.max(1, count - 1))!;
          final baseColor = color.withValues(alpha: paused ? 0.25 : 0.72);
          final paint = Paint()
            ..shader = LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [baseColor, tipColor.withValues(alpha: paused ? 0.35 : 0.96)],
            ).createShader(barRect);
          canvas.drawRRect(
            RRect.fromRectAndRadius(barRect, const Radius.circular(3.5)),
            paint,
          );
          if (!paused) {
            final capY = math.max(0.0, size.height - h - 4.0);
            canvas.drawRRect(
              RRect.fromRectAndRadius(Rect.fromLTWH(left, capY, barW, 2.4), const Radius.circular(1.5)),
              Paint()..color = tipColor.withValues(alpha: 0.95),
            );
          }
        }
        break;
      case EqualizerStyle.wave:
        final midY = size.height / 2;
        if (paused) {
          canvas.drawLine(
            Offset(0, midY),
            Offset(size.width, midY),
            Paint()
              ..color = const Color(0xFF38BDF8).withValues(alpha: 0.35)
              ..strokeWidth = 2.0,
          );
        } else {
          final topPoints = <Offset>[];
          final botPoints = <Offset>[];
          final steps = count * 3;
          for (int s = 0; s <= steps; s++) {
            final norm = s / steps;
            final x = norm * size.width;
            final bandFloat = norm * (count - 1);
            final b0 = bandFloat.floor().clamp(0, count - 1);
            final b1 = (b0 + 1).clamp(0, count - 1);
            final frac = bandFloat - b0;
            final energy = _bandAt(b0) * (1.0 - frac) + _bandAt(b1) * frac;
            final taper = math.sin(norm * math.pi);
            final ripple = 0.72 + 0.28 * math.sin(norm * math.pi * count);
            final amp = (2.5 + size.height * 0.44 * (energy * 0.85 + beatPulse * 0.18) * intensity) * taper * ripple;
            topPoints.add(Offset(x, midY - amp));
            botPoints.add(Offset(x, midY + amp));
          }
          final fillPath = Path()..moveTo(topPoints.first.dx, topPoints.first.dy);
          for (final p in topPoints.skip(1)) {
            fillPath.lineTo(p.dx, p.dy);
          }
          for (final p in botPoints.reversed) {
            fillPath.lineTo(p.dx, p.dy);
          }
          fillPath.close();

          canvas.drawPath(
            fillPath,
            Paint()
              ..shader = LinearGradient(
                begin: Alignment.centerLeft,
                end: Alignment.centerRight,
                colors: [
                  color.withValues(alpha: 0.36),
                  const Color(0xFF38BDF8).withValues(alpha: 0.44),
                  const Color(0xFFF59E0B).withValues(alpha: 0.36),
                ],
              ).createShader(Offset.zero & size),
          );

          final strokeTop = Path()..moveTo(topPoints.first.dx, topPoints.first.dy);
          for (final p in topPoints.skip(1)) {
            strokeTop.lineTo(p.dx, p.dy);
          }
          final strokeBot = Path()..moveTo(botPoints.first.dx, botPoints.first.dy);
          for (final p in botPoints.skip(1)) {
            strokeBot.lineTo(p.dx, p.dy);
          }
          final contour = Paint()
            ..color = const Color(0xFF7DD3FC).withValues(alpha: 0.94)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2.1
            ..strokeCap = StrokeCap.round;
          canvas.drawPath(strokeTop, contour);
          canvas.drawPath(strokeBot, contour);
        }
        break;
      case EqualizerStyle.pulse:
        final center = Offset(size.width / 2, size.height / 2);
        if (paused) {
          canvas.drawCircle(
            center,
            8,
            Paint()..color = color.withValues(alpha: 0.32),
          );
        } else {
          // Stereo center-outward harmonic beat bars + pulsing central reactor orb + shockwave arcs
          final halfPairs = 8;
          final orbRadius = 9.0 + beatPulse * 11.0;

          // Center orb aura
          canvas.drawCircle(
            center,
            orbRadius * 1.65,
            Paint()
              ..shader = RadialGradient(
                colors: [
                  const Color(0xFFFBBF24).withValues(alpha: 0.38 + beatPulse * 0.35),
                  color.withValues(alpha: 0.16),
                  Colors.transparent,
                ],
              ).createShader(Rect.fromCircle(center: center, radius: orbRadius * 1.65)),
          );
          canvas.drawCircle(
            center,
            orbRadius,
            Paint()..color = Color.lerp(color, const Color(0xFFFBBF24), beatPulse)!.withValues(alpha: 0.95),
          );

          // Left & Right symmetric shockwave arcs
          for (int arcIdx = 0; arcIdx < 2; arcIdx++) {
            final spread = 24.0 + arcIdx * 16.0 + beatPulse * 14.0;
            final arcRect = Rect.fromCenter(center: center, width: spread * 2, height: size.height * 0.72);
            final arcPaint = Paint()
              ..color = const Color(0xFF38BDF8).withValues(alpha: (0.65 - arcIdx * 0.25).clamp(0.15, 0.8))
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.0;
            canvas.drawArc(arcRect, -0.58, 1.16, false, arcPaint);
            canvas.drawArc(arcRect, math.pi - 0.58, 1.16, false, arcPaint);
          }

          // Center-outward stereo beat columns
          for (int i = 0; i < halfPairs; i++) {
            final e = (_bandAt(i * 2) * 0.75 + beatPulse * 0.32).clamp(0.08, 1.0);
            final xOff = 36.0 + i * 11.5;
            final h = (8.0 + e * (size.height - 10)).clamp(8.0, size.height);
            final barColor = Color.lerp(const Color(0xFF38BDF8), const Color(0xFFF59E0B), i / (halfPairs - 1))!;
            final p = Paint()..color = barColor.withValues(alpha: 0.88);
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(center.dx - xOff, center.dy), width: 6.5, height: h),
                const Radius.circular(3.5),
              ),
              p,
            );
            canvas.drawRRect(
              RRect.fromRectAndRadius(
                Rect.fromCenter(center: Offset(center.dx + xOff, center.dy), width: 6.5, height: h),
                const Radius.circular(3.5),
              ),
              p,
            );
          }
        }
        break;
    }
  }

  @override
  bool shouldRepaint(covariant _SmartEqualizerPainter oldDelegate) {
    if (oldDelegate.paused != paused ||
        oldDelegate.style != style ||
        oldDelegate.color != color ||
        oldDelegate.intensity != intensity ||
        oldDelegate.beatPulse != beatPulse ||
        oldDelegate.bands.length != bands.length) {
      return true;
    }
    for (int i = 0; i < bands.length; i++) {
      if ((oldDelegate.bands[i] - bands[i]).abs() > 0.004) return true;
    }
    return false;
  }
}
