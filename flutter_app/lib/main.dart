import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/thermostat_state.dart';
import 'screens/secondary_screens.dart';
import 'screens/settings_sheet.dart';
import 'screens/theme_effects_sheet.dart';
import 'screens/thermostat_screen.dart';
import 'screens/widget_order_sheet.dart';
import 'services/ambient_audio_service.dart';
import 'services/firebase_sync_service.dart';
import 'services/hardware_service.dart';
import 'services/notification_service.dart';
import 'widgets/boot_ceremony_overlay.dart';
import 'widgets/flow_tab_bar.dart';
import 'widgets/overlays.dart';
import 'widgets/termo_bot.dart';
import 'widgets/weather_effects_layer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(
    const SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: Brightness.light,
      systemNavigationBarColor: Colors.transparent,
      systemNavigationBarIconBrightness: Brightness.light,
    ),
  );
  runApp(const TermostatFlowApp());
}

class TermostatFlowApp extends StatelessWidget {
  const TermostatFlowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Termostat Flow',
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark(useMaterial3: true).copyWith(
        scaffoldBackgroundColor: const Color(0xFF040406),
      ),
      home: const TermostatHomeShell(),
    );
  }
}

class TermostatHomeShell extends StatefulWidget {
  const TermostatHomeShell({super.key});

  @override
  State<TermostatHomeShell> createState() => _TermostatHomeShellState();
}

class _TermostatHomeShellState extends State<TermostatHomeShell> {
  static const _storageKey = 'termostat_flow_flutter_v2';

  final PageController _pageController = PageController(viewportFraction: 1.0);
  TabId _activeTab = TabId.termo;
  final double _roomTemp = 21.8;
  double _targetTemp = 22.5;
  PresetId? _activePreset = PresetId.konfor;
  LangCode _lang = LangCode.tr;
  String _locationName = 'Ev · İstanbul';
  List<ScheduleSlot> _schedule = ThermostatMath.defaultSchedule;
  SystemSettingsState _settings = SystemSettingsState.defaults();
  VisualCustomizationState _visual = VisualCustomizationState.defaults();
  bool _savedNotice = false;
  bool _ambientMode = false;
  bool _screensaverPreview = false;
  bool _voiceOpen = false;
  bool _showBootCeremony = false;
  bool _termoBotIdle = false;
  DateTime _now = DateTime.now();
  int _slideIndex = 0;
  int _slideTicks = 0;
  int _ambientElapsedSeconds = 0;

  Timer? _clockTimer;
  Timer? _idleTimer;
  Timer? _automationTimer;
  DateTime? _lastWheelNavAt;
  bool _activeTabCanVertScroll = false;

  @override
  void initState() {
    super.initState();
    _loadPersisted();
    _resetIdleTimer();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      if (_ambientMode || _visual.theme == AppThemeMode.autoSmart) {
        setState(() {
          _now = DateTime.now();
          if (_ambientMode) {
            _ambientElapsedSeconds++;
            final sleepMinutes = _settings.displaySleepMinutes;
            if (sleepMinutes > 0 && _ambientElapsedSeconds >= sleepMinutes * 60) {
              _exitAmbientMode();
            }
            if (_settings.smartDisplayMode == SmartDisplayMode.slideshow) {
              _slideTicks++;
              if (_slideTicks >= _settings.slideDurationSeconds) {
                _slideTicks = 0;
                _slideIndex = (_slideIndex + 1) % 4;
              }
            }
          }
        });
      }
    });
    _automationTimer = Timer.periodic(const Duration(hours: 3), (_) {
      if (!mounted || !_settings.notifications3hEnabled) return;
      final b = ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp);
      NotificationService.dispatchNotification(
        context: context,
        lang: _lang,
        locationName: _locationName,
        roomTemp: _roomTemp,
        targetTemp: _targetTemp,
        boiler: b,
        settings: _settings,
      ).then((res) {
        if (!mounted) return;
        setState(() => _settings = _settings.copyWith(lastNotificationAt: res.timestampLabel));
        _persist();
      });
    });
  }

  void _resetIdleTimer() {
    if (_termoBotIdle) {
      setState(() => _termoBotIdle = false);
    }
    _idleTimer?.cancel();
    if (_settings.termoBotEnabled) {
      _idleTimer = Timer(Duration(seconds: _settings.screensaverIdleSeconds), () {
        if (mounted && !_ambientMode && !_voiceOpen && !_screensaverPreview) {
          setState(() => _termoBotIdle = true);
        }
      });
    }
  }

  Future<void> _loadPersisted() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_storageKey);
    var bootOn = _settings.bootCeremonyEnabled;

    if (raw != null) {
      try {
        final map = jsonDecode(raw) as Map<String, dynamic>;
        if (!mounted) return;
        final loadedSettings = map['settings'] is Map<String, dynamic>
            ? SystemSettingsState.fromJson(map['settings'] as Map<String, dynamic>)
            : _settings;
        final loadedVisual = map['visual'] is Map<String, dynamic>
            ? VisualCustomizationState.fromJson(map['visual'] as Map<String, dynamic>)
            : _visual;
        bootOn = loadedSettings.bootCeremonyEnabled;
        setState(() {
          final t = (map['targetTemp'] as num?)?.toDouble();
          if (t != null) _targetTemp = ThermostatMath.snapTemperature(t);
          final pIdx = map['presetIndex'] as int?;
          _activePreset = (pIdx != null && pIdx >= 0 && pIdx < PresetId.values.length)
              ? PresetId.values[pIdx]
              : ThermostatMath.findMatchingPreset(_targetTemp)?.id;
          _lang = map['lang'] == 'en' ? LangCode.en : LangCode.tr;
          _locationName = (map['locationName'] as String?) ?? _locationName;
          _settings = loadedSettings;
          _visual = loadedVisual;
          final rawSched = map['schedule'];
          if (rawSched is List) {
            final byId = <String, Map<String, dynamic>>{};
            for (final item in rawSched) {
              if (item is Map<String, dynamic> && item['id'] is String) {
                byId[item['id'] as String] = item;
              }
            }
            _schedule = [
              for (final s in ThermostatMath.defaultSchedule)
                if (byId.containsKey(s.id))
                  s.copyWith(
                    enabled: byId[s.id]!['enabled'] as bool? ?? s.enabled,
                    targetTemp: (byId[s.id]!['targetTemp'] as num?)?.toDouble() != null
                        ? ThermostatMath.snapTemperature((byId[s.id]!['targetTemp'] as num).toDouble())
                        : s.targetTemp,
                  )
                else
                  s,
            ];
          }
        });
        _syncPageIndexToActiveTab(jump: true);
        _resetIdleTimer();
      } catch (_) {
        // Ignore malformed stored state
      }
    }

    if (bootOn && mounted) {
      setState(() => _showBootCeremony = true);
    }
  }

  Future<void> _persist() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(
      _storageKey,
      jsonEncode({
        'targetTemp': _targetTemp,
        'presetIndex': _activePreset?.index,
        'lang': _lang == LangCode.en ? 'en' : 'tr',
        'locationName': _locationName,
        'schedule': _schedule.map((s) => s.toJson()).toList(),
        'settings': _settings.toJson(),
        'visual': _visual.toJson(),
      }),
    );
  }

  void _triggerHaptic() {
    if (_settings.hapticEnabled) {
      HardwareService.vibrateMs(
        40,
        amplitude: HardwareService.scaledAmplitude(135, _settings.hapticStrength),
      );
    }
  }

  void _syncPageIndexToActiveTab({bool jump = false}) {
    final ordered = _visual.orderedTabs;
    final idx = ordered.indexWhere((t) => t.id == _activeTab);
    if (idx < 0 || !_pageController.hasClients) return;
    if (jump) {
      _pageController.jumpToPage(idx);
    } else {
      _pageController.animateToPage(
        idx,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _enterAmbientMode() {
    setState(() {
      _now = DateTime.now();
      _slideTicks = 0;
      _ambientElapsedSeconds = 0;
      _ambientMode = true;
    });
    if (_settings.ambientVolume > 0.01) {
      AmbientAudioService.start(
        track: _settings.ambientSoundtrack,
        customSource: _settings.customAudioSource.isNotEmpty
            ? _settings.customAudioSource
            : _settings.customAudioLabel,
        volume: _settings.ambientVolume,
      );
    }
    HardwareService.enterSmartDisplayHardware(
      brightnessPercent: _settings.displayBrightness,
      keepAwake: _settings.displaySleepMinutes == 0,
    );
  }

  void _exitAmbientMode() {
    if (_ambientMode) {
      setState(() {
        _ambientMode = false;
        _ambientElapsedSeconds = 0;
      });
    } else {
      _ambientElapsedSeconds = 0;
    }
    AmbientAudioService.stop();
    HardwareService.exitSmartDisplayHardware();
  }

  void _syncFirebaseBackground(double target) {
    if (!_settings.googleHomeLinked && !_settings.cloudSyncEnabled) return;
    final b = ThermostatMath.computeBoilerTelemetry(_roomTemp, target);
    FirebaseSyncService.pushState(
      baseUrl: _settings.firebaseRtdbUrl,
      roomName: _settings.googleHomeRoom,
      espDeviceId: _settings.espDeviceId,
      roomTemp: _roomTemp,
      targetTemp: target,
      boiler: b,
    );
  }

  @override
  void dispose() {
    _clockTimer?.cancel();
    _idleTimer?.cancel();
    _automationTimer?.cancel();
    _pageController.dispose();
    AmbientAudioService.stop();
    HardwareService.exitSmartDisplayHardware();
    super.dispose();
  }

  void _selectTab(TabId tab) {
    final ordered = _visual.orderedTabs;
    final idx = ordered.indexWhere((t) => t.id == tab);
    if (idx < 0) return;
    _triggerHaptic();
    _resetIdleTimer();
    setState(() {
      _activeTab = tab;
      _activeTabCanVertScroll = false;
    });
    _pageController.animateToPage(
      idx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
  }

  void _handlePagePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (_ambientMode || _screensaverPreview || _showBootCeremony || _voiceOpen) return;
    final now = DateTime.now();
    if (_lastWheelNavAt != null && now.difference(_lastWheelNavAt!).inMilliseconds < 240) {
      return;
    }
    final dx = event.scrollDelta.dx;
    final dy = event.scrollDelta.dy;
    var dir = 0;
    if (dx.abs() > dy.abs() && dx.abs() >= 6.0) {
      dir = dx > 0 ? 1 : -1;
    } else if (dy.abs() >= 8.0 && (_activeTab == TabId.termo || !_activeTabCanVertScroll)) {
      dir = dy > 0 ? 1 : -1;
    }
    if (dir == 0) return;
    final ordered = _visual.orderedTabs;
    final cur = ordered.indexWhere((t) => t.id == _activeTab);
    final nextIdx = cur + dir;
    if (nextIdx >= 0 && nextIdx < ordered.length) {
      _lastWheelNavAt = now;
      _selectTab(ordered[nextIdx].id);
    }
  }

  void _changeTarget(double next) {
    final snapped = ThermostatMath.snapTemperature(next);
    if ((snapped - _targetTemp).abs() >= 0.05) {
      _triggerHaptic();
    }
    _resetIdleTimer();
    setState(() {
      _targetTemp = snapped;
      _activePreset = ThermostatMath.findMatchingPreset(snapped)?.id;
    });
    _persist();
    _syncFirebaseBackground(snapped);
  }

  void _selectPreset(ThermostatPreset preset) {
    _triggerHaptic();
    _resetIdleTimer();
    setState(() {
      _targetTemp = preset.temp;
      _activePreset = preset.id;
    });
    _persist();
    _syncFirebaseBackground(preset.temp);
  }

  void _updateVisual(VisualCustomizationState next) {
    final orderChanged = !_listEquals(next.tabOrder, _visual.tabOrder);
    setState(() => _visual = next);
    if (orderChanged) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _syncPageIndexToActiveTab(jump: true);
      });
    }
    _persist();
  }

  bool _listEquals<T>(List<T> a, List<T> b) {
    if (a.length != b.length) return false;
    for (int i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }

  Widget _buildTabPage(TabId id, BoilerTelemetry boiler, Color activeColor, ThemePaletteSpec palette) {
    switch (id) {
      case TabId.termo:
        return KeyedSubtree(
          key: const ValueKey(TabId.termo),
          child: ThermostatScreen(
            roomTemp: _roomTemp,
            targetTemp: _targetTemp,
            activePreset: _activePreset,
            accentColor: activeColor,
            boiler: boiler,
            lang: _lang,
            palette: palette,
            onChangeTarget: _changeTarget,
            onSelectPreset: _selectPreset,
          ),
        );
      case TabId.hava:
        return KeyedSubtree(
          key: const ValueKey(TabId.hava),
          child: WeatherScreen(
            lang: _lang,
            locationName: _locationName,
            palette: palette,
            weatherAlertsEnabled: _settings.weatherAlertsEnabled,
            roomTemp: _roomTemp,
            targetTemp: _targetTemp,
            boiler: boiler,
            settings: _settings,
            onToggleWeatherAlerts: (v) {
              _triggerHaptic();
              setState(() => _settings = _settings.copyWith(weatherAlertsEnabled: v));
              _persist();
            },
            onChangeLocation: (loc) {
              _triggerHaptic();
              setState(() => _locationName = loc);
              _persist();
            },
            onApplyEcoCompensation: () => _selectPreset(ThermostatMath.presets.first),
          ),
        );
      case TabId.rapor:
        return KeyedSubtree(
          key: const ValueKey(TabId.rapor),
          child: ReportScreen(
            lang: _lang,
            roomTemp: _roomTemp,
            targetTemp: _targetTemp,
            boiler: boiler,
            subTabOrder: _visual.reportSubTabOrder,
            palette: palette,
          ),
        );
      case TabId.prog:
        return KeyedSubtree(
          key: const ValueKey(TabId.prog),
          child: ScheduleScreen(
            lang: _lang,
            slots: _schedule,
            subTabOrder: _visual.scheduleSubTabOrder,
            palette: palette,
            savedNotice: _savedNotice,
            onUpdateSlot: (slotId, {enabled, targetTemp}) {
              _triggerHaptic();
              setState(() {
                _schedule = [
                  for (final s in _schedule)
                    if (s.id == slotId)
                      s.copyWith(enabled: enabled, targetTemp: targetTemp)
                    else
                      s,
                ];
              });
              _persist();
            },
            onSaveSchedule: () {
              _triggerHaptic();
              _persist();
              setState(() => _savedNotice = true);
              Future.delayed(const Duration(milliseconds: 1800), () {
                if (mounted) setState(() => _savedNotice = false);
              });
            },
          ),
        );
    }
  }

  String _formatClock(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h:$m:$s';
  }

  String _formatDate(DateTime dt, LangCode lang) {
    const daysTr = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
    const daysEn = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    const monthsTr = ['Oca', 'Şub', 'Mar', 'Nis', 'May', 'Haz', 'Tem', 'Ağu', 'Eyl', 'Eki', 'Kas', 'Ara'];
    const monthsEn = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final d = lang == LangCode.tr ? daysTr[dt.weekday - 1] : daysEn[dt.weekday - 1];
    final mon = lang == LangCode.tr ? monthsTr[dt.month - 1] : monthsEn[dt.month - 1];
    return '$d, ${dt.day} $mon ${dt.year}';
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final compactLandscape = isLandscape && media.size.height < 480;
    final boiler = ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp);
    final palette = _visual.resolvePalette(_now);
    final orderedTabs = _visual.orderedTabs;

    final activeTabMeta = orderedTabs.firstWhere(
      (t) => t.id == _activeTab,
      orElse: () => orderedTabs.first,
    );
    final baseAccent = _activeTab == TabId.termo
        ? ThermostatMath.resolveThermostatAccent(_targetTemp, _activePreset)
        : activeTabMeta.accent;
    final activeAccent = palette.themeOverrideAccent ?? baseAccent;
    final activeColor = activeAccent.toColor();
    final isEco = _visual.performanceMode == PerformanceMode.ecoBattery;

    return Listener(
      onPointerDown: (_) {
        if (!_termoBotIdle) _resetIdleTimer();
      },
      onPointerUp: (_) {
        if (_termoBotIdle) {
          Future.microtask(() {
            if (mounted && _termoBotIdle) _resetIdleTimer();
          });
        } else {
          _resetIdleTimer();
        }
      },
      child: Scaffold(
        backgroundColor: palette.scaffoldBg,
        body: Stack(
          children: [
            FlowTabBarShell(
              activeTab: _activeTab,
              orderedTabs: orderedTabs,
              onSelectTab: _selectTab,
              activeAccent: activeAccent,
              lang: _lang,
              isLandscape: isLandscape,
              performanceMode: _visual.performanceMode,
              palette: palette,
              voiceOpen: _voiceOpen,
              onOpenVoice: () async {
                _triggerHaptic();
                _resetIdleTimer();
                setState(() => _voiceOpen = true);
                await showVoiceCommandSheet(
                  context: context,
                  lang: _lang,
                  accentColor: activeColor,
                  onExecute: (res) {
                    if (res.newTargetTemp != null) _changeTarget(res.newTargetTemp!);
                    if (res.navigateTab != null) _selectTab(res.navigateTab!);
                  },
                );
                if (mounted) setState(() => _voiceOpen = false);
              },
              child: Stack(
                children: [
                  // Subtle Weather Particle / Mist Layer
                  Positioned.fill(
                    child: WeatherEffectsLayer(
                      preview: _visual.weatherPreview,
                      performanceMode: _visual.performanceMode,
                      isLightTheme: palette.isLight,
                    ),
                  ),

                  SafeArea(
                    bottom: false,
                    child: Column(
                      children: [
                        // Top App Bar
                        Container(
                          height: compactLandscape ? 42 : 52,
                          padding: const EdgeInsets.symmetric(horizontal: 14),
                          decoration: BoxDecoration(
                            color: palette.isLight
                                ? Colors.white.withValues(alpha: 0.42)
                                : const Color(0xFF040406).withValues(alpha: 0.22),
                            border: Border(
                              bottom: BorderSide(
                                color: palette.isLight
                                    ? palette.cardBorder
                                    : Colors.white.withValues(alpha: 0.08),
                              ),
                            ),
                          ),
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Expanded(
                                child: Row(
                                  children: [
                                    Container(
                                      width: compactLandscape ? 28 : 32,
                                      height: compactLandscape ? 28 : 32,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: activeColor,
                                        boxShadow: [
                                          BoxShadow(color: activeColor.withValues(alpha: 0.4), blurRadius: 14),
                                        ],
                                      ),
                                      child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 17),
                                    ),
                                    const SizedBox(width: 9),
                                    Flexible(
                                      child: Column(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'Termostat',
                                            style: TextStyle(
                                              fontSize: 14.5,
                                              fontWeight: FontWeight.w700,
                                              color: palette.textPrimary,
                                              height: 1.1,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          Text(
                                            _locationName,
                                            style: TextStyle(
                                              fontSize: 10.5,
                                              color: palette.textSecondary,
                                              height: 1.1,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),

                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  // Performance Quick Toggle (60 FPS / ECO)
                                  _TopActionButton(
                                    palette: palette,
                                    onTap: () {
                                      _triggerHaptic();
                                      _updateVisual(
                                        _visual.copyWith(
                                          performanceMode: isEco
                                              ? PerformanceMode.ultra60fps
                                              : PerformanceMode.ecoBattery,
                                        ),
                                      );
                                    },
                                    child: Text(
                                      isEco ? 'ECO' : '60',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.w800,
                                        color: isEco ? const Color(0xFF10B981) : activeColor,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 5),

                                  // Theme & Visual Effects Sheet
                                  _TopActionButton(
                                    palette: palette,
                                    onTap: () {
                                      _triggerHaptic();
                                      showThemeEffectsSheet(
                                        context: context,
                                        lang: _lang,
                                        accentColor: activeColor,
                                        hapticEnabled: _settings.hapticEnabled,
                                        initialVisual: _visual,
                                        onUpdateVisual: _updateVisual,
                                      );
                                    },
                                    child: Icon(Icons.palette_outlined, size: 17, color: palette.textPrimary),
                                  ),
                                  const SizedBox(width: 5),

                                  // Widget & Screen Order Sheet
                                  _TopActionButton(
                                    palette: palette,
                                    onTap: () {
                                      _triggerHaptic();
                                      showWidgetOrderSheet(
                                        context: context,
                                        lang: _lang,
                                        accentColor: activeColor,
                                        hapticEnabled: _settings.hapticEnabled,
                                        initialVisual: _visual,
                                        onUpdateVisual: _updateVisual,
                                      );
                                    },
                                    child: Icon(Icons.dashboard_customize_outlined, size: 17, color: palette.textPrimary),
                                  ),

                                  if (_settings.smartDisplayEnabled) ...[
                                    const SizedBox(width: 5),
                                    _TopActionButton(
                                      palette: palette,
                                        onTap: () {
                                          _triggerHaptic();
                                          _enterAmbientMode();
                                        },
                                        child: Icon(Icons.tv_rounded, size: 17, color: palette.textPrimary),
                                      ),
                                    ],
                                    const SizedBox(width: 5),

                                    // System Settings Sheet
                                    _TopActionButton(
                                      palette: palette,
                                      onTap: () {
                                        _triggerHaptic();
                                        showSystemSettingsSheet(
                                          context: context,
                                          lang: _lang,
                                          locationName: _locationName,
                                          accentColor: activeColor,
                                          roomTemp: _roomTemp,
                                          targetTemp: _targetTemp,
                                          boiler: boiler,
                                          initialSettings: _settings,
                                          onChangeLang: (l) => setState(() => _lang = l),
                                          onChangeLocation: (loc) => setState(() => _locationName = loc),
                                          onChangeTargetTemp: _changeTarget,
                                          onSaveSettings: (updated) {
                                            setState(() => _settings = updated);
                                            _resetIdleTimer();
                                            _persist();
                                          },
                                          onOpenAmbient: _enterAmbientMode,
                                         onOpenScreensaverPreview: () => setState(() {
                                           _termoBotIdle = false;
                                           _screensaverPreview = true;
                                         }),
                                         onReplayBootCeremony: () => setState(() {
                                           _showBootCeremony = true;
                                         }),
                                         onResetTelemetryHistory: () {
                                           setState(() {
                                             _schedule = ThermostatMath.defaultSchedule;
                                             _targetTemp = 22.5;
                                             _activePreset = PresetId.konfor;
                                           });
                                           _persist();
                                         },
                                       );
                                     },
                                     child: Icon(Icons.settings_outlined, size: 17, color: palette.textPrimary),
                                   ),
                                 ],
                               ),
                             ],
                           ),
                         ),

                         // Frameless Wheel-Arc Horizontal Carousel (supports touch, mouse drag & mouse wheel)
                         Expanded(
                           child: Padding(
                             padding: EdgeInsets.only(bottom: (compactLandscape ? 66.0 : 76.0) + media.padding.bottom),
                             child: Listener(
                               behavior: HitTestBehavior.translucent,
                               onPointerSignal: _handlePagePointerSignal,
                               child: NotificationListener<ScrollMetricsNotification>(
                                 onNotification: (notification) {
                                   if (notification.depth > 0 && notification.metrics.axis == Axis.vertical) {
                                     final canScroll = notification.metrics.maxScrollExtent > 4.0;
                                     if (canScroll != _activeTabCanVertScroll) {
                                       _activeTabCanVertScroll = canScroll;
                                     }
                                   }
                                   return false;
                                 },
                                 child: ScrollConfiguration(
                                   behavior: const _UniversalFlowScrollBehavior(),
                                   child: PageView.builder(
                                     controller: _pageController,
                                     physics: const BouncingScrollPhysics(
                                       parent: AlwaysScrollableScrollPhysics(),
                                     ),
                                     itemCount: orderedTabs.length,
                                     onPageChanged: (idx) {
                                       if (idx >= 0 && idx < orderedTabs.length) {
                                         setState(() {
                                           _activeTab = orderedTabs[idx].id;
                                           _activeTabCanVertScroll = false;
                                         });
                                       }
                                     },
                                     itemBuilder: (context, idx) {
                                       final meta = orderedTabs[idx];
                                       return AnimatedBuilder(
                                         animation: _pageController,
                                         builder: (context, child) {
                                           double currentPage = orderedTabs.indexWhere((t) => t.id == _activeTab).toDouble();
                                           if (_pageController.hasClients && _pageController.position.haveDimensions) {
                                             currentPage = _pageController.page ?? currentPage;
                                           }
                                           final signedDelta = currentPage - idx;
                                           final absDelta = signedDelta.abs().clamp(0.0, 1.0);
                                           if (absDelta < 0.004) {
                                             return child!;
                                           }
                                           final opacity = (1.0 - absDelta * 0.48).clamp(0.32, 1.0);
                                           final scale = (1.0 - absDelta * 0.07).clamp(0.92, 1.0);
                                           final wheelArcY = absDelta * absDelta * 22.0;
                                           final tiltY = (signedDelta * 0.24).clamp(-0.35, 0.35);
                                           final perspective = Matrix4.identity()
                                             ..setEntry(3, 2, 0.0011)
                                             ..rotateY(tiltY);

                                           return Opacity(
                                             opacity: opacity,
                                             child: Transform.translate(
                                               offset: Offset(0, wheelArcY),
                                               child: Transform(
                                                 alignment: signedDelta > 0 ? Alignment.centerRight : Alignment.centerLeft,
                                                 transform: perspective,
                                                 child: Transform.scale(
                                                   scale: scale,
                                                   child: child,
                                                 ),
                                               ),
                                             ),
                                           );
                                         },
                                         child: _buildTabPage(meta.id, boiler, activeColor, palette),
                                       );
                                     },
                                   ),
                                 ),
                               ),
                             ),
                           ),
                         ),
                       ],
                     ),
                   ),
                 ],
               ),
             ),

             // TermoBot Idle Companion Mascot
             TermoBotOverlay(
               enabled: _settings.termoBotEnabled && !_ambientMode && !_screensaverPreview,
               isSleeping: _termoBotIdle,
               character: _settings.mascotCharacter,
               mascotScale: _settings.mascotScale,
               soundsEnabled: _settings.mascotSoundsEnabled,
               hapticEnabled: _settings.hapticEnabled,
               hapticStrength: _settings.hapticStrength,
               roomTemp: _roomTemp,
               targetTemp: _targetTemp,
               boiler: boiler,
               lang: _lang,
               accentColor: activeColor,
               bottomOffset: (compactLandscape ? 72.0 : 88.0) + media.padding.bottom,
               onWake: _resetIdleTimer,
               onOpenScreensaver: () => setState(() {
                 _termoBotIdle = false;
                 _screensaverPreview = true;
               }),
             ),

             // Fullscreen Screensaver Preview Overlay
             if (_screensaverPreview)
               FullscreenScreensaverOverlay(
                 character: _settings.mascotCharacter,
                 mascotScale: _settings.mascotScale,
                 backdrop: _settings.screensaverBackdrop,
                 blurBackground: _settings.screensaverBlurBg,
                 customBgSource: _settings.screensaverCustomBgSource,
                 soundsEnabled: _settings.mascotSoundsEnabled,
                 hapticEnabled: _settings.hapticEnabled,
                 hapticStrength: _settings.hapticStrength,
                 roomTemp: _roomTemp,
                 targetTemp: _targetTemp,
                 boiler: boiler,
                 locationName: _locationName,
                 accentColor: activeColor,
                 lang: _lang,
                 onExit: () {
                   _resetIdleTimer();
                   setState(() => _screensaverPreview = false);
                 },
               ),

             // Enhanced Smart Display / Ambient Mode Fullscreen Clock & Telemetry
             if (_ambientMode)
               Positioned.fill(
                 child: GestureDetector(
                   onTap: _exitAmbientMode,
                   child: _SmartDisplayAmbientView(
                     mode: _settings.smartDisplayMode,
                     layoutMode: _settings.smartDisplayLayout,
                     slideEffect: _settings.slideEffect,
                     slideIndex: _slideIndex,
                     now: _now,
                     clockText: _formatClock(_now),
                     dateText: _formatDate(_now, _lang),
                     locationName: _locationName,
                     roomTemp: _roomTemp,
                     targetTemp: _targetTemp,
                     boiler: boiler,
                     accentColor: activeColor,
                     lang: _lang,
                     trackTitle: _settings.ambientTrackTitle(_lang),
                     ambientVolume: _settings.ambientVolume,
                     marqueeTrackEnabled: _settings.marqueeTrackEnabled,
                     equalizerEnabled: _settings.equalizerEnabled,
                     equalizerStyle: _settings.equalizerStyle,
                     displayBrightness: _settings.displayBrightness,
                     oledPixelShiftEnabled: _settings.oledPixelShiftEnabled,
                   ),
                 ),
               ),

            // Interactive Multi-Stage Boot Calibration Ceremony
            if (_showBootCeremony)
              Positioned.fill(
                child: BootCeremonyOverlay(
                  style: _settings.bootCeremonyStyle,
                  durationMs: _settings.bootCeremonyDurationMs,
                  soundChimeEnabled: _settings.bootSoundChimeEnabled,
                  hapticEnabled: _settings.hapticEnabled,
                  hapticStrength: _settings.hapticStrength,
                  roomTemp: _roomTemp,
                  targetTemp: _targetTemp,
                  boiler: boiler,
                  locationName: _locationName,
                  accentColor: activeColor,
                  palette: palette,
                  lang: _lang,
                  onComplete: () {
                    if (mounted) setState(() => _showBootCeremony = false);
                  },
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _UniversalFlowScrollBehavior extends MaterialScrollBehavior {
  const _UniversalFlowScrollBehavior();

  @override
  Set<PointerDeviceKind> get dragDevices => const {
        PointerDeviceKind.touch,
        PointerDeviceKind.mouse,
        PointerDeviceKind.trackpad,
        PointerDeviceKind.stylus,
        PointerDeviceKind.invertedStylus,
      };
}

class _TopActionButton extends StatelessWidget {
  final ThemePaletteSpec palette;
  final VoidCallback onTap;
  final Widget child;

  const _TopActionButton({
    required this.palette,
    required this.onTap,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.isLight ? palette.cardBg : Colors.white.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(11),
          border: Border.all(
            color: palette.isLight ? palette.cardBorder : Colors.white.withValues(alpha: 0.11),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: palette.isLight ? 0.08 : 0.28),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: child,
      ),
    );
  }
}

class _SmartDisplayAmbientView extends StatefulWidget {
  final SmartDisplayMode mode;
  final VisualLayoutMode layoutMode;
  final SlideTransitionEffect slideEffect;
  final int slideIndex;
  final DateTime now;
  final String clockText;
  final String dateText;
  final String locationName;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final Color accentColor;
  final LangCode lang;
  final String trackTitle;
  final double ambientVolume;
  final bool marqueeTrackEnabled;
  final bool equalizerEnabled;
  final EqualizerStyle equalizerStyle;
  final int displayBrightness;
  final bool oledPixelShiftEnabled;

  const _SmartDisplayAmbientView({
    required this.mode,
    required this.layoutMode,
    required this.slideEffect,
    required this.slideIndex,
    required this.now,
    required this.clockText,
    required this.dateText,
    required this.locationName,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.accentColor,
    required this.lang,
    required this.trackTitle,
    required this.ambientVolume,
    required this.marqueeTrackEnabled,
    required this.equalizerEnabled,
    required this.equalizerStyle,
    required this.displayBrightness,
    required this.oledPixelShiftEnabled,
  });

  @override
  State<_SmartDisplayAmbientView> createState() => _SmartDisplayAmbientViewState();
}

class _SmartDisplayAmbientViewState extends State<_SmartDisplayAmbientView> with SingleTickerProviderStateMixin {
  late final AnimationController _animCtrl;

  @override
  void initState() {
    super.initState();
    _animCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  @override
  void dispose() {
    _animCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final tr = widget.lang == LangCode.tr;

    const slidePalettes = [
      [Color(0xFF1E293B), Color(0xFF090D16)],
      [Color(0xFF431407), Color(0xFF140704)],
      [Color(0xFF1E1B4B), Color(0xFF09071A)],
      [Color(0xFF064E3B), Color(0xFF041410)],
    ];

    List<Color> bgColors;
    IconData modeIcon;
    String modeBadge;
    switch (widget.mode) {
      case SmartDisplayMode.aod:
        bgColors = const [Colors.black, Colors.black];
        modeIcon = Icons.nights_stay_outlined;
        modeBadge = 'Always-On Display (AOD)';
        break;
      case SmartDisplayMode.silentVideoMp3:
        bgColors = const [Color(0xFF0C2A45), Color(0xFF050A14)];
        modeIcon = Icons.music_video_outlined;
        modeBadge = tr ? 'Sessiz Video + MP3' : 'Silent Video + MP3';
        break;
      case SmartDisplayMode.liveNature:
        bgColors = const [Color(0xFF5C1D0C), Color(0xFF0E0504)];
        modeIcon = Icons.local_fire_department_outlined;
        modeBadge = tr ? 'Canlı Doğa / Şömine' : 'Live Nature / Hearth';
        break;
      case SmartDisplayMode.slideshow:
        bgColors = slidePalettes[widget.slideIndex % slidePalettes.length];
        modeIcon = Icons.collections_outlined;
        modeBadge = tr ? 'Slayt Gösterisi (${widget.slideIndex + 1}/4)' : 'Slideshow (${widget.slideIndex + 1}/4)';
        break;
      case SmartDisplayMode.singlePhoto:
        bgColors = const [Color(0xFF1B1932), Color(0xFF07070D)];
        modeIcon = Icons.photo_outlined;
        modeBadge = tr ? 'Tekli Görsel' : 'Single Backdrop';
        break;
    }

    // Subtle OLED pixel-shift offset when OLED Pixel Protection is enabled
    final aodShift = (widget.oledPixelShiftEnabled || widget.mode == SmartDisplayMode.aod)
        ? Offset(((widget.now.minute % 5) - 2) * 3.0, ((widget.now.second % 3) - 1) * 2.0)
        : Offset.zero;

    final insetPadding = switch (widget.layoutMode) {
      VisualLayoutMode.cover => EdgeInsets.zero,
      VisualLayoutMode.contain => const EdgeInsets.all(20),
      VisualLayoutMode.framed => const EdgeInsets.symmetric(horizontal: 28, vertical: 44),
    };

    final innerContent = AnimatedSwitcher(
      duration: const Duration(milliseconds: 520),
      transitionBuilder: (child, anim) {
        switch (widget.slideEffect) {
          case SlideTransitionEffect.fade:
            return FadeTransition(opacity: anim, child: child);
          case SlideTransitionEffect.slide:
            return SlideTransition(
              position: Tween<Offset>(begin: const Offset(0.08, 0), end: Offset.zero).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            );
          case SlideTransitionEffect.zoom:
            return ScaleTransition(
              scale: Tween<double>(begin: 0.94, end: 1.0).animate(anim),
              child: FadeTransition(opacity: anim, child: child),
            );
        }
      },
      child: Container(
        key: ValueKey('${widget.mode.name}_${widget.slideIndex}'),
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          borderRadius: widget.layoutMode == VisualLayoutMode.cover ? BorderRadius.zero : BorderRadius.circular(26),
          gradient: widget.mode == SmartDisplayMode.aod
              ? null
              : RadialGradient(
                  center: const Alignment(0, -0.15),
                  radius: 1.15,
                  colors: bgColors,
                ),
          color: widget.mode == SmartDisplayMode.aod ? Colors.black : null,
          border: widget.layoutMode == VisualLayoutMode.cover
              ? null
              : Border.all(color: Colors.white.withValues(alpha: 0.16), width: 1.4),
        ),
        padding: const EdgeInsets.all(24),
        child: Transform.translate(
          offset: aodShift,
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (widget.marqueeTrackEnabled)
                Container(
                  margin: const EdgeInsets.only(bottom: 10),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF0EA5E9).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.35)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.music_note_rounded, size: 14, color: Color(0xFF7DD3FC)),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          '${widget.trackTitle} · %${(widget.ambientVolume * 100).round()}',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFFE0F2FE)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(modeIcon, size: 15, color: widget.accentColor),
                    const SizedBox(width: 6),
                    Text(
                      '$modeBadge · ${widget.locationName}',
                      style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.80)),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.clockText,
                style: const TextStyle(
                  fontSize: 48,
                  fontWeight: FontWeight.w300,
                  letterSpacing: 2.0,
                  color: Colors.white,
                  fontFeatures: [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                widget.dateText,
                style: TextStyle(fontSize: 13.5, color: Colors.white.withValues(alpha: 0.58)),
              ),
              const SizedBox(height: 22),
              Text(
                '${widget.targetTemp.toStringAsFixed(1)}°',
                style: TextStyle(
                  fontSize: 74,
                  fontWeight: FontWeight.w700,
                  color: widget.accentColor,
                  height: 1.0,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '${tr ? 'Oda' : 'Room'}: ${widget.roomTemp.toStringAsFixed(1)}°C  ·  ${tr ? widget.boiler.statusTextTr : widget.boiler.statusTextEn}',
                style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.72)),
              ),
              if (widget.equalizerEnabled) ...[
                const SizedBox(height: 18),
                SizedBox(
                  width: 220,
                  height: 36,
                  child: AnimatedBuilder(
                    animation: _animCtrl,
                    builder: (_, __) => CustomPaint(
                      painter: _AmbientEqualizerPainter(
                        phase: _animCtrl.value * math.pi * 2,
                        style: widget.equalizerStyle,
                        color: widget.accentColor,
                        intensity: widget.ambientVolume.clamp(0.15, 1.0),
                      ),
                    ),
                  ),
                ),
              ],
              const SizedBox(height: 20),
              Text(
                tr ? 'Çıkmak için ekrana dokunun' : 'Tap anywhere to return',
                style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.44)),
              ),
            ],
          ),
        ),
      ),
    );

    final dimAlpha = ((1.0 - (widget.displayBrightness / 100.0)) * 0.72).clamp(0.0, 0.72);

    return Stack(
      children: [
        Container(
          color: Colors.black,
          padding: insetPadding,
          child: widget.layoutMode == VisualLayoutMode.framed
              ? Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 440, maxHeight: 440),
                    child: innerContent,
                  ),
                )
              : innerContent,
        ),
        if (dimAlpha > 0.01)
          Positioned.fill(
            child: IgnorePointer(
              child: Container(color: Colors.black.withValues(alpha: dimAlpha)),
            ),
          ),
      ],
    );
  }
}

class _AmbientEqualizerPainter extends CustomPainter {
  final double phase;
  final EqualizerStyle style;
  final Color color;
  final double intensity;

  const _AmbientEqualizerPainter({
    required this.phase,
    required this.style,
    required this.color,
    required this.intensity,
  });

  @override
  void paint(Canvas canvas, Size size) {
    switch (style) {
      case EqualizerStyle.bars:
        const count = 16;
        final barW = (size.width / count) * 0.56;
        final step = size.width / count;
        final paint = Paint()..style = PaintingStyle.fill;
        for (int i = 0; i < count; i++) {
          final wave = 0.25 + 0.75 * (0.5 + 0.5 * math.sin(phase * 2.0 + i * 0.65));
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
              math.sin(norm * math.pi * 4 + phase * 2.0) * (size.height * 0.36 * intensity) * math.sin(norm * math.pi);
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
  bool shouldRepaint(covariant _AmbientEqualizerPainter oldDelegate) =>
      oldDelegate.phase != phase || oldDelegate.style != style || oldDelegate.intensity != intensity;
}
