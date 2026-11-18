import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/thermostat_state.dart';
import 'screens/secondary_screens.dart';
import 'screens/settings_sheet.dart';
import 'screens/theme_effects_sheet.dart';
import 'screens/thermostat_screen.dart';
import 'screens/widget_order_sheet.dart';
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

  final PageController _pageController = PageController();
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
  bool _voiceOpen = false;
  bool _showBootCeremony = false;
  bool _termoBotIdle = false;
  DateTime _now = DateTime.now();

  Timer? _clockTimer;
  Timer? _idleTimer;

  @override
  void initState() {
    super.initState();
    _loadPersisted();
    _resetIdleTimer();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted && (_ambientMode || _visual.theme == AppThemeMode.autoSmart)) {
        setState(() => _now = DateTime.now());
      }
    });
  }

  void _resetIdleTimer() {
    if (_termoBotIdle) {
      setState(() => _termoBotIdle = false);
    }
    _idleTimer?.cancel();
    if (_settings.termoBotEnabled) {
      _idleTimer = Timer(const Duration(seconds: 12), () {
        if (mounted && !_ambientMode && !_voiceOpen) {
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
      } catch (_) {
        // Ignore malformed stored state
      }
    }

    if (bootOn && mounted) {
      setState(() => _showBootCeremony = true);
      Future.delayed(const Duration(milliseconds: 1100), () {
        if (mounted) setState(() => _showBootCeremony = false);
      });
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
      HapticFeedback.selectionClick();
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

  @override
  void dispose() {
    _clockTimer?.cancel();
    _idleTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  void _selectTab(TabId tab) {
    final ordered = _visual.orderedTabs;
    final idx = ordered.indexWhere((t) => t.id == tab);
    if (idx < 0) return;
    _triggerHaptic();
    _resetIdleTimer();
    setState(() => _activeTab = tab);
    _pageController.animateToPage(
      idx,
      duration: const Duration(milliseconds: 380),
      curve: Curves.easeOutCubic,
    );
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
  }

  void _selectPreset(ThermostatPreset preset) {
    _triggerHaptic();
    _resetIdleTimer();
    setState(() {
      _targetTemp = preset.temp;
      _activePreset = preset.id;
    });
    _persist();
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
      onPointerDown: (_) => _resetIdleTimer(),
      onPointerMove: (_) => _resetIdleTimer(),
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
                            color: palette.scaffoldBg.withValues(alpha: palette.isLight ? 0.55 : 0.35),
                            border: Border(bottom: BorderSide(color: palette.cardBorder)),
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
                                        setState(() {
                                          _now = DateTime.now();
                                          _ambientMode = true;
                                        });
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
                                        initialSettings: _settings,
                                        onChangeLang: (l) => setState(() => _lang = l),
                                        onChangeLocation: (loc) => setState(() => _locationName = loc),
                                        onSaveSettings: (updated) {
                                          setState(() => _settings = updated);
                                          _resetIdleTimer();
                                          _persist();
                                        },
                                        onOpenAmbient: () => setState(() {
                                          _now = DateTime.now();
                                          _ambientMode = true;
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

                        // Fluid 4-page horizontal PageView synchronized with orderedTabs
                        Expanded(
                          child: Padding(
                            padding: EdgeInsets.only(bottom: (compactLandscape ? 68.0 : 78.0) + media.padding.bottom),
                            child: PageView(
                              controller: _pageController,
                              onPageChanged: (idx) {
                                if (idx >= 0 && idx < orderedTabs.length) {
                                  setState(() => _activeTab = orderedTabs[idx].id);
                                }
                              },
                              children: [
                                for (final meta in orderedTabs)
                                  _buildTabPage(meta.id, boiler, activeColor, palette),
                              ],
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
              enabled: _settings.termoBotEnabled && !_ambientMode,
              isSleeping: _termoBotIdle,
              lang: _lang,
              accentColor: activeColor,
              bottomOffset: (compactLandscape ? 72.0 : 88.0) + media.padding.bottom,
              onWake: _resetIdleTimer,
            ),

            // Enhanced Smart Display / Ambient Mode Fullscreen Clock & Telemetry
            if (_ambientMode)
              Positioned.fill(
                child: GestureDetector(
                  onTap: () => setState(() => _ambientMode = false),
                  child: Container(
                    color: const Color(0xFF040406).withValues(alpha: 0.96),
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.nights_stay_outlined, size: 22, color: activeColor),
                            const SizedBox(width: 8),
                            Text(
                              _locationName,
                              style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.68)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),
                        Text(
                          _formatClock(_now),
                          style: const TextStyle(
                            fontSize: 44,
                            fontWeight: FontWeight.w300,
                            letterSpacing: 2.0,
                            color: Colors.white,
                            fontFeatures: [FontFeature.tabularFigures()],
                          ),
                        ),
                        Text(
                          _formatDate(_now, _lang),
                          style: TextStyle(fontSize: 13, color: Colors.white.withValues(alpha: 0.55)),
                        ),
                        const SizedBox(height: 22),
                        Text(
                          '${_targetTemp.toStringAsFixed(1)}°',
                          style: TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.w700,
                            color: activeColor,
                            height: 1.0,
                            fontFeatures: const [FontFeature.tabularFigures()],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          '${_lang == LangCode.tr ? 'Oda' : 'Room'}: ${_roomTemp.toStringAsFixed(1)}°C  ·  ${_lang == LangCode.tr ? boiler.statusTextTr : boiler.statusTextEn}',
                          style: TextStyle(fontSize: 14, color: Colors.white.withValues(alpha: 0.70)),
                        ),
                        const SizedBox(height: 28),
                        Text(
                          _lang == LangCode.tr ? 'Çıkmak için ekrana dokunun' : 'Tap anywhere to return',
                          style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.42)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            // Boot Calibration Ceremony
            if (_showBootCeremony)
              Positioned.fill(
                child: Container(
                  color: const Color(0xFF040406),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        width: 64,
                        height: 64,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: activeColor,
                          boxShadow: [BoxShadow(color: activeColor.withValues(alpha: 0.55), blurRadius: 28)],
                        ),
                        child: const Icon(Icons.local_fire_department_rounded, color: Colors.white, size: 34),
                      ),
                      const SizedBox(height: 18),
                      const Text(
                        'Termostat Flow',
                        style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _lang == LangCode.tr ? 'Sistem kalibre ediliyor...' : 'Calibrating thermostat...',
                        style: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.55)),
                      ),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
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
        constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: palette.cardBg,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.cardBorder),
        ),
        child: child,
      ),
    );
  }
}
