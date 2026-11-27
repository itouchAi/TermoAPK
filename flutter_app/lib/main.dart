import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'models/house_plan_model.dart';
import 'models/thermostat_state.dart';
import 'screens/home_3d_screen.dart';
import 'screens/secondary_screens.dart';
import 'screens/settings_sheet.dart';
import 'screens/theme_effects_sheet.dart';
import 'screens/thermostat_screen.dart';
import 'screens/widget_order_sheet.dart';
import 'services/ai_call_service.dart';
import 'services/ambient_audio_service.dart';
import 'services/esp_log_service.dart';
import 'services/firebase_sync_service.dart';
import 'services/hardware_service.dart';
import 'services/home_widget_bridge.dart';
import 'services/media_storage_service.dart';
import 'services/notification_service.dart';
import 'services/schedule_engine.dart';
import 'services/voice_speech_service.dart';
import 'services/weather_service.dart';
import 'widgets/ai_phone_call_overlay.dart';
import 'widgets/boot_ceremony_overlay.dart';
import 'widgets/flow_tab_bar.dart';
import 'widgets/missed_call_alert.dart';
import 'widgets/overlays.dart';
import 'widgets/smart_display_overlay.dart';
import 'widgets/tactile_button.dart';
import 'widgets/termo_bot.dart';
import 'widgets/weather_effects_layer.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
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
      builder: (context, child) => TactileMotionScope(
        notifier: TactileMotionScope.globalEnabled,
        child: TactileFocusBlurHost(
          child: child ?? const SizedBox.shrink(),
        ),
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

class _TermostatHomeShellState extends State<TermostatHomeShell> with WidgetsBindingObserver {
  static const _storageKey = 'termostat_flow_flutter_v2';
  static const int _virtualCenterBase = 4000;

  final PageController _pageController = PageController(
    initialPage: _virtualCenterBase,
    viewportFraction: 1.0,
  );
  int _virtualPageIndex = _virtualCenterBase;
  TabId _activeTab = TabId.termo;
  double? _roomTemp;
  double _targetTemp = 22.5;
  PresetId? _activePreset = PresetId.konfor;
  LangCode _lang = LangCode.tr;
  String _locationName = 'Ev · İstanbul';
  List<ScheduleSlot> _schedule = ThermostatMath.defaultSchedule;
  List<CustomScheduleRule> _customScheduleRules = const [];
  SystemSettingsState _settings = SystemSettingsState.defaults();
  VisualCustomizationState _visual = VisualCustomizationState.defaults();
  bool _savedNotice = false;
  bool _ambientMode = false;
  bool _ambientForcedAod = false;
  bool _screensaverPreview = false;
  bool _aiCallOpen = false;
  AiCallReason _aiCallReason = AiCallReason.ignition;
  bool _aiCallUrgent = false;
  DateTime? _lastAiCallAt;
  DateTime? _lastPassiveEventNotifyAt;
  DateTime? _lastOfflineWarnAt;
  List<AiCallLogEntry> _unreadAlerts = const [];
  bool _alertsExpanded = false;
  String? _activeCallScheduleTr;
  String? _activeCallScheduleEn;
  bool _voiceOpen = false;
  bool _modalSheetOpen = false;
  bool _reopenSettingsToSmartDisplay = false;
  bool _showBootCeremony = false;
  bool _persistedLoaded = false;
  DateTime _now = DateTime.now();
  int _slideIndex = 0;
  int _slideTicks = 0;
  int _ambientElapsedSeconds = 0;
  int _thermalTicks = 0;
  Map<String, DailyThermalLog> _dailyLogs = const {};
  double _gasUnitPriceTl = 10.25;
  BoilerHardwareSensors _hardwareSensors = const BoilerHardwareSensors.disconnected();
  bool _remoteRoomTempActive = false;
  HouseFloorPlan _floorPlan = HouseFloorPlan.defaults();
  Map<String, RoomEspTelemetry> _roomTelemetries = const {};
  WeatherReport? _weatherReport;
  bool _weatherLoading = false;
  String? _weatherError;
  int _weatherFetchSeq = 0;

  Timer? _clockTimer;
  Timer? _idleTimer;
  Timer? _automationTimer;
  Timer? _aiCallDebounceTimer;
  bool? _pendingCallBaselineHeating;
  double? _pendingCallBaselineTarget;
  String? _pendingScheduleTitleTr;
  String? _pendingScheduleTitleEn;
  String _lastScheduleMinuteKey = '';
  DateTime? _heatingCycleStartedAt;
  DateTime? _lastWheelNavAt;
  bool _activeTabCanVertScroll = false;

  Future<void> _fetchWeather(String locationName, {bool force = false}) async {
    final seq = ++_weatherFetchSeq;
    final coords = WeatherService.coordinatesForLocation(locationName);
    final cached = !force ? WeatherService.getCached(locationName) : null;
    if (mounted) {
      setState(() {
        _weatherReport = cached ?? (_weatherReport?.cityName == coords.displayCity ? _weatherReport : null);
        _weatherLoading = true;
        _weatherError = null;
      });
    }
    final res = await WeatherService.fetchForecast(locationName, lang: _lang);
    if (!mounted || seq != _weatherFetchSeq) return;
    if (WeatherService.coordinatesForLocation(_locationName).cityKey != coords.cityKey) return;
    setState(() {
      _weatherLoading = false;
      if (res.ok) {
        _weatherReport = res.report;
        _weatherError = null;
      } else {
        _weatherError = _lang == LangCode.tr ? res.errorTr : res.errorEn;
      }
    });
  }

  void _enqueueUnreadAlert(AiCallLogEntry entry) {
    if (!mounted) return;
    final next = AiCallService.appendCallHistory(
      _unreadAlerts,
      entry,
      maxEntries: 20,
    );
    setState(() => _unreadAlerts = next);
    _persist();
  }

  void _markAlertRead(String id) {
    if (!mounted) return;
    final next = _unreadAlerts.where((e) => e.id != id).toList();
    setState(() {
      _unreadAlerts = next;
      if (next.length <= 1) {
        _alertsExpanded = false;
      }
    });
    _persist();
  }

  void _syncPreferredVoices(SystemSettingsState s) {
    VoiceSpeechService.preferredFemaleVoice = s.femaleVoiceName;
    VoiceSpeechService.preferredMaleVoice = s.maleVoiceName;
  }

  void _applyImmersiveFullscreen() {
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  void _syncHomeWidget() {
    unawaited(
      HomeWidgetBridge.syncFromApp(
        targetTemp: _targetTemp,
        lang: _lang,
        floorPlan: _floorPlan,
        roomTelemetries: _roomTelemetries,
        mainRoomTemp: _roomTemp,
        espOnline: _settings.espOnline,
        mainEspDeviceId: _settings.espDeviceId,
      ),
    );
  }

  Future<void> _consumeHomeWidgetPendingTarget() async {
    final pending = await HomeWidgetBridge.consumePendingTarget();
    if (pending != null && mounted && (pending - _targetTemp).abs() >= 0.05) {
      setState(() {
        _targetTemp = pending;
        _activePreset = ThermostatMath.findMatchingPreset(pending)?.id;
      });
      await _persist();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _applyImmersiveFullscreen();
      unawaited(_consumeHomeWidgetPendingTarget());
      _syncHomeWidget();
    }
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _applyImmersiveFullscreen();
    _activeTab = _visual.startupTab;
    _syncPreferredVoices(_settings);
    TactileMotionScope.globalEnabled.value = _visual.buttonTactileFeedback;
    if (ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp).isHeating) {
      _heatingCycleStartedAt = DateTime.now();
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _syncPageIndexToActiveTab(jump: true);
    });
    _loadPersisted();
    VoiceSpeechService.warmup();
    _resetIdleTimer();
    _clockTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) return;
      _thermalTicks++;
      final tickNow = DateTime.now();
      final activeRoom = _roomTemp;
      final tickBoiler = ThermostatMath.computeBoilerTelemetry(activeRoom, _targetTemp);
      Map<String, DailyThermalLog>? updatedLogs;
      if (_persistedLoaded && activeRoom != null && _settings.espOnline) {
        updatedLogs = ThermalLogAggregator.recordSample(
          logs: _dailyLogs,
          timestamp: tickNow,
          roomTemp: activeRoom,
          boiler: tickBoiler,
          seconds: 1,
        );
      }

      final shouldRefreshUi = _ambientMode ||
          _visual.theme == AppThemeMode.autoSmart ||
          (_persistedLoaded &&
              (_activeTab == TabId.rapor || _activeTab == TabId.prog || _thermalTicks % 5 == 0));

      if (shouldRefreshUi) {
        setState(() {
          if (updatedLogs != null) {
            _dailyLogs = updatedLogs;
          }
          _now = tickNow;
          if (_ambientMode) {
            _ambientElapsedSeconds++;
            final sleepMinutes = _settings.displaySleepMinutes;
            if (!_ambientForcedAod &&
                _settings.smartDisplayMode != SmartDisplayMode.aod &&
                sleepMinutes > 0 &&
                _ambientElapsedSeconds >= sleepMinutes * 60) {
              _ambientForcedAod = true;
              AmbientAudioService.stop();
            }
            if (!_ambientForcedAod && _settings.smartDisplayMode == SmartDisplayMode.slideshow) {
              _slideTicks++;
              final slideCount = _settings.slideImages.isNotEmpty ? _settings.slideImages.length : 5;
              if (_slideTicks >= _settings.slideDurationSeconds) {
                _slideTicks = 0;
                _slideIndex = (_slideIndex + 1) % slideCount;
              }
            }
          }
        });
      } else if (updatedLogs != null) {
        _dailyLogs = updatedLogs;
      }

      if (_persistedLoaded && _thermalTicks % 15 == 0) {
        _persist();
      }

      if (_persistedLoaded) {
        final minuteKey = ScheduleEngine.minuteKey(tickNow);
        if (minuteKey != _lastScheduleMinuteKey) {
          _lastScheduleMinuteKey = minuteKey;
          _evaluateScheduledActions(tickNow);
        }
      }

      final syncInterval = _settings.cloudSyncIntervalSeconds;
      if (_settings.cloudSyncEnabled && syncInterval > 0 && _thermalTicks % syncInterval == 0) {
        _syncFirebaseBackground(
          _targetTemp,
          allowAutoPull: _settings.cloudAutoPullEnabled,
          pushCommand: !_settings.cloudAutoPullEnabled,
        );
      }
    });
    _automationTimer = Timer.periodic(const Duration(hours: 3), (_) {
      if (!mounted || !_settings.notifications3hEnabled) return;
      final b = ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp);
      final roomStr = _roomTemp != null ? '${AiCallService.formatSpokenNumber(_roomTemp!)}°C' : '--';
      final targetStr = AiCallService.formatSpokenNumber(_targetTemp);
      final summaryTr = !b.hasSensorReading
          ? '3 saatlik durum özeti: ESP32 / kombi bağlantısı yok (Oda --, Hedef $targetStr°C).'
          : (b.isHeating
              ? '3 saatlik durum özeti: Oda $roomStr, kombi $targetStr°C hedefte aktif. Eko 20°C\'ye alalım mı yoksa kapatalım mı?'
              : '3 saatlik durum özeti: Oda $roomStr, kombi şu an kapalı. İsterseniz 22.5°C ile açalım mı?');
      final summaryEn = !b.hasSensorReading
          ? '3h status summary: ESP32 / boiler offline (Room --, Target $targetStr°C).'
          : (b.isHeating
              ? '3h status summary: Room is $roomStr with boiler active at $targetStr°C. Lower to Eco 20°C or turn off?'
              : '3h status summary: Room is $roomStr and boiler is off. Should I turn it on at 22.5°C?');
      _enqueueUnreadAlert(
        AiCallLogEntry(
          id: 'periodic_${DateTime.now().microsecondsSinceEpoch}',
          timestamp: NotificationService.formatNowTime(),
          character: _settings.mascotCharacter,
          reason: AiCallReason.manualTest,
          status: AiCallStatus.missed,
          durationSeconds: 0,
          summaryTr: summaryTr,
          summaryEn: summaryEn,
          actionTakenTr: '',
          actionTakenEn: '',
          roomTemp: _roomTemp,
          targetTemp: _targetTemp,
          boilerHeating: b.isHeating,
          urgent: false,
          isSystemAlert: true,
          badgeLabelTr: '3 Saatlik Rapor',
          badgeLabelEn: '3h Summary',
        ),
      );
      NotificationService.dispatchNotification(
        context: context,
        lang: _lang,
        locationName: _locationName,
        roomTemp: _roomTemp,
        targetTemp: _targetTemp,
        outsideTemp: _weatherReport?.currentTempC,
        boiler: b,
        sensors: _hardwareSensors,
        settings: _settings,
        customTitle: _lang == LangCode.tr ? '⏱ 3 Saatlik Asistan Özeti' : '⏱ 3h Assistant Summary',
        customBody: _lang == LangCode.tr ? summaryTr : summaryEn,
        showOverlayBanner: false,
      ).then((res) {
        if (!mounted) return;
        setState(() => _settings = _settings.copyWith(lastNotificationAt: res.timestampLabel));
        _persist();
      });
    });
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    if (_settings.smartDisplayEnabled &&
        _settings.smartDisplayAutoMinutes > 0 &&
        !_ambientMode &&
        !_aiCallOpen) {
      _idleTimer = Timer(Duration(minutes: _settings.smartDisplayAutoMinutes), () {
        if (mounted &&
            _settings.smartDisplayEnabled &&
            !_ambientMode &&
            !_voiceOpen &&
            !_modalSheetOpen &&
            !_showBootCeremony &&
            !_aiCallOpen &&
            !_screensaverPreview) {
          _enterAmbientMode();
        }
      });
    } else if (_settings.termoBotEnabled && !_screensaverPreview && !_aiCallOpen) {
      _idleTimer = Timer(Duration(seconds: _settings.screensaverIdleSeconds), () {
        if (mounted &&
            _settings.termoBotEnabled &&
            !_ambientMode &&
            !_voiceOpen &&
            !_modalSheetOpen &&
            !_showBootCeremony &&
            !_aiCallOpen &&
            !_screensaverPreview) {
          setState(() => _screensaverPreview = true);
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
        final loadedFloorPlan = map['floorPlan'] is Map<String, dynamic>
            ? HouseFloorPlan.fromJson(map['floorPlan'] as Map<String, dynamic>)
            : _floorPlan;
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
          _activeTab = loadedVisual.startupTab;
          _floorPlan = loadedFloorPlan;
          TactileMotionScope.globalEnabled.value = loadedVisual.buttonTactileFeedback;
          _syncPreferredVoices(loadedSettings);
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
                    time: byId[s.id]!['time'] as String? ?? s.time,
                    enabled: byId[s.id]!['enabled'] as bool? ?? s.enabled,
                    targetTemp: (byId[s.id]!['targetTemp'] as num?)?.toDouble() != null
                        ? ThermostatMath.snapTemperature((byId[s.id]!['targetTemp'] as num).toDouble())
                        : s.targetTemp,
                  )
                else
                  s,
            ];
          }
          final rawCustom = map['customScheduleRules'];
          if (rawCustom is List) {
            _customScheduleRules = [
              for (final item in rawCustom)
                if (item is Map<String, dynamic>) CustomScheduleRule.fromJson(item),
            ];
          }
          final rawUnread = map['unreadAlerts'];
          if (rawUnread is List) {
            _unreadAlerts = [
              for (final item in rawUnread)
                if (item is Map<String, dynamic>) AiCallLogEntry.fromJson(item),
            ];
          }
          final rawRate = (map['gasUnitPriceTl'] as num?)?.toDouble();
          if (rawRate != null && rawRate.isFinite && rawRate > 0 && rawRate <= 500) {
            _gasUnitPriceTl = rawRate;
          }
          final rawLogs = map['dailyLogs'];
          if (rawLogs is Map) {
            _dailyLogs = ThermalLogAggregator.decodeLogs(rawLogs);
          }
        });
        if (ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp).isHeating) {
          _heatingCycleStartedAt ??= DateTime.now();
        } else {
          _heatingCycleStartedAt = null;
        }
        _syncPageIndexToActiveTab(jump: true);
        _resetIdleTimer();
        unawaited(
          MediaStorageService.hydrateSettingsMedia(loadedSettings).then((_) {
            if (mounted) setState(() {});
          }),
        );
      } catch (_) {
        // Ignore malformed stored state
      }
    } else {
      _syncPageIndexToActiveTab(jump: true);
    }

    _persistedLoaded = true;
    final nowTick = DateTime.now();
    _lastScheduleMinuteKey = ScheduleEngine.minuteKey(nowTick);
    _evaluateScheduledActions(nowTick);
    unawaited(_fetchWeather(_locationName));
    if (_settings.cloudSyncEnabled && _settings.cloudAutoPullEnabled) {
      _syncFirebaseBackground(_targetTemp, allowAutoPull: true, pushCommand: false);
    }

    if (bootOn && mounted) {
      setState(() => _showBootCeremony = true);
    }
    unawaited(_consumeHomeWidgetPendingTarget());
    _syncHomeWidget();
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
        'gasUnitPriceTl': _gasUnitPriceTl,
        'dailyLogs': ThermalLogAggregator.encodeLogs(_dailyLogs),
        'schedule': _schedule.map((s) => s.toJson()).toList(),
        'customScheduleRules': _customScheduleRules.map((r) => r.toJson()).toList(),
        'unreadAlerts': _unreadAlerts.map((a) => a.toJson()).toList(),
        'settings': _settings.toJson(),
        'visual': _visual.toJson(),
        'floorPlan': _floorPlan.toJson(),
      }),
    );
    _syncHomeWidget();
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
    final targetVirtual = jump
        ? (_virtualCenterBase - (_virtualCenterBase % ordered.length) + idx)
        : ThermostatMath.nearestCircularVirtualIndex(
            currentVirtualIndex: _virtualPageIndex,
            targetRealIndex: idx,
            length: ordered.length,
          );
    _virtualPageIndex = targetVirtual;
    if (jump) {
      _pageController.jumpToPage(targetVirtual);
    } else {
      _pageController.animateToPage(
        targetVirtual,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _enterAmbientMode() {
    _idleTimer?.cancel();
    setState(() {
      _now = DateTime.now();
      _slideTicks = 0;
      _ambientElapsedSeconds = 0;
      _ambientForcedAod = false;
      _ambientMode = true;
    });
    final hasCustomAudio = _settings.customAudioSource.trim().isNotEmpty ||
        _settings.customAudioLabel.trim().isNotEmpty;
    if (_settings.smartDisplayMode != SmartDisplayMode.aod &&
        _settings.ambientSoundtrack == AmbientSoundtrack.customMp3 &&
        hasCustomAudio &&
        _settings.ambientVolume > 0.01) {
      AmbientAudioService.start(
        track: AmbientSoundtrack.customMp3,
        customSource: _settings.customAudioSource.isNotEmpty
            ? _settings.customAudioSource
            : _settings.customAudioLabel,
        volume: _settings.ambientVolume,
      );
    } else {
      AmbientAudioService.stop();
    }
    _applyImmersiveFullscreen();
    HardwareService.enterSmartDisplayHardware(
      brightnessPercent: _settings.displayBrightness,
      keepAwake: _settings.displaySleepMinutes == 0,
    );
  }

  void _exitAmbientMode() {
    final shouldReopenSettings = _reopenSettingsToSmartDisplay;
    _reopenSettingsToSmartDisplay = false;
    if (_ambientMode) {
      setState(() {
        _ambientMode = false;
        _ambientForcedAod = false;
        _ambientElapsedSeconds = 0;
      });
    } else {
      _ambientForcedAod = false;
      _ambientElapsedSeconds = 0;
    }
    AmbientAudioService.stop();
    HardwareService.exitSmartDisplayHardware();
    _applyImmersiveFullscreen();
    if (shouldReopenSettings && mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_ambientMode) {
          _openSettingsSheet(initialExpandedId: SettingsItemId.smartDisplay);
        }
      });
    } else {
      _resetIdleTimer();
    }
  }

  Future<void> _openSettingsSheet({SettingsItemId? initialExpandedId}) async {
    if (_modalSheetOpen || !mounted) return;
    _modalSheetOpen = true;
    _idleTimer?.cancel();
    final boiler = ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp);
    final orderedTabs = _visual.orderedTabs;
    final activeTabMeta = orderedTabs.firstWhere(
      (t) => t.id == _activeTab,
      orElse: () => orderedTabs.first,
    );
    final baseAccent = _activeTab == TabId.termo
        ? ThermostatMath.resolveThermostatAccent(_targetTemp, _activePreset)
        : activeTabMeta.accent;
    final activeColor = (_visual.resolvePalette(_now).themeOverrideAccent ?? baseAccent).toColor();

    await showSystemSettingsSheet(
      context: context,
      lang: _lang,
      locationName: _locationName,
      accentColor: activeColor,
      roomTemp: _roomTemp,
      targetTemp: _targetTemp,
      outsideTemp: _weatherReport?.currentTempC,
      boiler: boiler,
      sensors: _hardwareSensors,
      initialSettings: _settings,
      initialExpandedId: initialExpandedId,
      onChangeLang: (l) {
        setState(() => _lang = l);
        _persist();
        _fetchWeather(_locationName);
      },
      onChangeLocation: (loc) {
        setState(() => _locationName = loc);
        _persist();
        _fetchWeather(loc);
      },
      onChangeTargetTemp: _changeTarget,
      onSaveSettings: (updated) {
        setState(() {
          _settings = updated;
          _syncPreferredVoices(updated);
        });
        _resetIdleTimer();
        _persist();
      },
      onOpenAmbient: () {
        _reopenSettingsToSmartDisplay = true;
        _enterAmbientMode();
      },
      onOpenScreensaverPreview: () => setState(() {
        _screensaverPreview = true;
      }),
      onTestAiCall: (reason) => _launchAiCall(
        reason: reason,
        urgent: reason == AiCallReason.safetyAlert || reason == AiCallReason.hotRoom,
        trackCooldown: false,
      ),
      onReplayBootCeremony: () => setState(() {
        _showBootCeremony = true;
      }),
      onApplyRemoteRoomTemp: (rt) {
        if (!mounted) return;
        setState(() {
          _roomTemp = rt;
          _remoteRoomTempActive = true;
        });
        _persist();
      },
      onApplyRemoteSensors: (s) {
        if (!mounted) return;
        setState(() => _hardwareSensors = s);
      },
      onResetTelemetryHistory: () {
        setState(() {
          _schedule = ThermostatMath.defaultSchedule;
          _customScheduleRules = const [];
          _dailyLogs = const {};
          _hardwareSensors = const BoilerHardwareSensors.disconnected();
          _roomTemp = null;
          _remoteRoomTempActive = false;
          _roomTelemetries = const {};
          _heatingCycleStartedAt = null;
          _targetTemp = 22.5;
          _activePreset = PresetId.konfor;
          _settings = _settings.copyWith(
            espLogs: const [],
            espOfflineBurnMinutes: 0,
            espWdtResetCount: 0,
            cloudLastSyncAt: '',
            cloudLastSyncOk: false,
            cloudLastSyncMessage: '',
          );
        });
        _persist();
      },
    );
    _modalSheetOpen = false;
    if (mounted && !_ambientMode && !_screensaverPreview) {
      _resetIdleTimer();
    }
  }

  void _appendEspLog(
    EspLogEntry entry, {
    bool? espOnline,
    String? espLastPingAt,
    int addBurnMinutes = 0,
    int addWdtCount = 0,
  }) {
    if (!mounted) return;
    setState(() {
      _settings = _settings.copyWith(
        espOnline: espOnline ?? _settings.espOnline,
        espLastPingAt: espLastPingAt ?? _settings.espLastPingAt,
        espOfflineBurnMinutes: _settings.espOfflineBurnMinutes + addBurnMinutes,
        espWdtResetCount: _settings.espWdtResetCount + addWdtCount,
        espLogs: EspLogService.appendLog(_settings.espLogs, entry),
      );
    });
    _persist();
  }

  void _recordBoilerTransitionEspLog({
    required bool prevHeating,
    required double nextTargetTemp,
  }) {
    final currentRoom = _roomTemp;
    if (currentRoom == null) {
      _heatingCycleStartedAt = null;
      return;
    }
    final nextBoiler = ThermostatMath.computeBoilerTelemetry(currentRoom, nextTargetTemp);
    final tr = _lang == LangCode.tr;
    if (!prevHeating && nextBoiler.isHeating) {
      _heatingCycleStartedAt = DateTime.now();
      if (_settings.espOfflineBufferEnabled) {
        _appendEspLog(
          EspLogEntry(
            timestamp: NotificationService.formatNowTime(),
            event: tr ? 'Brülör Ateşleme' : 'Boiler Ignition',
            detail: '${currentRoom.toStringAsFixed(1)}°C → ${nextTargetTemp.toStringAsFixed(1)}°C · %${nextBoiler.flamePercent}',
            category: EspLogCategory.burner,
          ),
        );
      }
    } else if (prevHeating && !nextBoiler.isHeating) {
      final started = _heatingCycleStartedAt;
      _heatingCycleStartedAt = null;
      final elapsedSec = started != null
          ? DateTime.now().difference(started).inSeconds.clamp(1, 86400)
          : 0;
      final addedMin = elapsedSec >= 60 ? (elapsedSec / 60).round() : 0;
      final pressureSuffix = (_hardwareSensors.isConnected && _hardwareSensors.waterPressureBar != null)
          ? ' · ${_hardwareSensors.waterPressureBar!.toStringAsFixed(1)} Bar'
          : '';
      if (_settings.espOfflineBufferEnabled) {
        _appendEspLog(
          EspLogEntry(
            timestamp: NotificationService.formatNowTime(),
            event: tr ? 'Yanma Döngüsü Tamamlandı' : 'Burn Cycle Completed',
            detail: '${currentRoom.toStringAsFixed(1)}°C → ${nextTargetTemp.toStringAsFixed(1)}°C$pressureSuffix',
            category: EspLogCategory.burner,
            durationSeconds: elapsedSec,
          ),
          addBurnMinutes: addedMin,
        );
      }
    }
  }

  void _maybeShowDisconnectedWarning(
    double targetTemp, {
    bool bypassCooldown = false,
    String? reasonOverrideTr,
    String? reasonOverrideEn,
  }) {
    if (!mounted) return;
    final hasLink = _settings.espOnline &&
        _roomTemp != null &&
        (_settings.cloudSyncEnabled || _settings.googleHomeLinked);
    if (hasLink && reasonOverrideTr == null) return;
    final now = DateTime.now();
    if (!bypassCooldown &&
        _lastOfflineWarnAt != null &&
        now.difference(_lastOfflineWarnAt!) < const Duration(seconds: 5)) {
      return;
    }
    if (Overlay.maybeOf(context, rootOverlay: true) == null) return;
    _lastOfflineWarnAt = now;
    final tr = _lang == LangCode.tr;
    final targetStr = targetTemp.toStringAsFixed(1);
    final String body;
    if (reasonOverrideTr != null || reasonOverrideEn != null) {
      body = tr
          ? (reasonOverrideTr ?? reasonOverrideEn!)
          : (reasonOverrideEn ?? reasonOverrideTr!);
    } else if (!_settings.cloudSyncEnabled && !_settings.googleHomeLinked) {
      body = tr
          ? 'Hedef $targetStr°C yerel olarak ayarlandı. Bulut ve ESP32 bağlantısı kapalı olduğu için kombiye iletilemedi.'
          : 'Target $targetStr°C saved locally. Cloud & ESP32 sync is disabled, so command was not sent to boiler.';
    } else if (!_settings.espOnline) {
      body = tr
          ? 'Hedef $targetStr°C yerel olarak ayarlandı ancak ESP32, kombi veya internet bağlantısı yok.'
          : 'Target $targetStr°C saved locally, but ESP32, boiler, or internet connection is unavailable.';
    } else {
      body = tr
          ? 'Hedef $targetStr°C ayarlandı ancak ESP32 oda sensörü verisi okunamıyor (--).'
          : 'Target $targetStr°C set, but ESP32 room sensor reading is unavailable (--).';
    }
    NotificationService.showFloatingBanner(
      context: context,
      title: tr ? '⚠️ ESP32 / Kombi Bağlantısı Yok' : '⚠️ ESP32 / Boiler Disconnected',
      body: body,
      severity: AlertSeverity.warning,
    );
  }

  void _recordSyncFailure(FirebaseSyncResult res, {bool notifyUser = false}) {
    if (!mounted) return;
    final nowLabel = NotificationService.formatNowTime();
    final wasOnline = _settings.espOnline;
    final syncMsg = _lang == LangCode.tr ? res.messageTr : res.messageEn;
    setState(() {
      _roomTelemetries = const {};
      _settings = _settings.copyWith(
        espOnline: false,
        cloudLastSyncAt: nowLabel,
        cloudLastSyncOk: false,
        cloudLastSyncMessage: syncMsg,
      );
    });
    _persist();
    if (notifyUser) {
      _maybeShowDisconnectedWarning(
        _targetTemp,
        reasonOverrideTr: 'İnternet veya Firebase RTDB bağlantısı yok — hedef kombiye iletilemedi (${res.messageTr}).',
        reasonOverrideEn: 'Internet or Firebase RTDB unavailable — target could not reach boiler (${res.messageEn}).',
      );
    }
    if (wasOnline) {
      _appendEspLog(
        EspLogEntry(
          timestamp: nowLabel,
          event: _lang == LangCode.tr ? 'WDT Bulut Bağlantı Kesintisi' : 'WDT Cloud Link Drop',
          detail: res.messageTr,
          isWarning: true,
          category: EspLogCategory.watchdog,
        ),
        espOnline: false,
        addWdtCount: _settings.espWdtEnabled ? 1 : 0,
      );
    }
  }

  void _applyPullSyncResult(FirebaseSyncResult pullRes) {
    if (!mounted) return;
    final nowLabel = NotificationService.formatNowTime();
    final wasOnline = _settings.espOnline;
    final syncMsg = _lang == LangCode.tr ? pullRes.messageTr : pullRes.messageEn;
    final remoteTarget = pullRes.remoteTargetTemp;
    final remoteTargetChanged = remoteTarget != null && (remoteTarget - _targetTemp).abs() >= 0.05;
    final remoteRoom = pullRes.remoteRoomTemp;
    final remoteRoomChanged = remoteRoom != null &&
        (_roomTemp == null || (remoteRoom - _roomTemp!).abs() >= 0.05 || !_remoteRoomTempActive);
    final hasSensorUpdate = pullRes.remoteSensors != null;

    if (!wasOnline) {
      _appendEspLog(
        EspLogEntry(
          timestamp: nowLabel,
          event: _lang == LangCode.tr ? 'RTDB Senkronizasyon Sağlandı' : 'RTDB Sync Restored',
          detail: '${_settings.espDeviceId} · ${(remoteTarget ?? _targetTemp).toStringAsFixed(1)}°C',
          category: EspLogCategory.sync,
        ),
        espOnline: true,
        espLastPingAt: nowLabel,
      );
    }
    setState(() {
      if (remoteTargetChanged) {
        _targetTemp = remoteTarget;
        _activePreset = ThermostatMath.findMatchingPreset(remoteTarget)?.id;
      }
      if (remoteRoomChanged) {
        _roomTemp = remoteRoom;
        _remoteRoomTempActive = true;
      }
      if (hasSensorUpdate) {
        _hardwareSensors = pullRes.remoteSensors!;
      }
      _roomTelemetries = pullRes.remoteRooms;
      _settings = _settings.copyWith(
        espOnline: true,
        espLastPingAt: nowLabel,
        cloudLastSyncAt: nowLabel,
        cloudLastSyncOk: true,
        cloudLastSyncMessage: syncMsg,
      );
    });
    _persist();
  }

  void _syncFirebaseBackground(
    double target, {
    bool allowAutoPull = false,
    bool pushCommand = true,
    bool notifyUserOnFailure = false,
  }) {
    if (!_settings.googleHomeLinked && !_settings.cloudSyncEnabled) return;

    if (allowAutoPull && _settings.cloudAutoPullEnabled && !pushCommand) {
      FirebaseSyncService.pullState(
        baseUrl: _settings.firebaseRtdbUrl,
        apiKey: _settings.firebaseApiKey,
        nodePath: _settings.firebaseNodePath,
      ).then((pullRes) {
        if (!mounted) return;
        if (pullRes.ok) {
          _applyPullSyncResult(pullRes);
        } else {
          _recordSyncFailure(pullRes, notifyUser: notifyUserOnFailure);
        }
      });
      return;
    }

    final b = ThermostatMath.computeBoilerTelemetry(_roomTemp, target);
    FirebaseSyncService.pushState(
      baseUrl: _settings.firebaseRtdbUrl,
      apiKey: _settings.firebaseApiKey,
      nodePath: _settings.firebaseNodePath,
      roomName: _settings.googleHomeRoom,
      espDeviceId: _settings.espDeviceId,
      targetTemp: target,
      boiler: b,
    ).then((res) {
      if (!mounted) return;
      final nowLabel = NotificationService.formatNowTime();
      final wasOnline = _settings.espOnline;
      final syncMsg = _lang == LangCode.tr ? res.messageTr : res.messageEn;
      if (res.ok) {
        if (!wasOnline) {
          _appendEspLog(
            EspLogEntry(
              timestamp: nowLabel,
              event: _lang == LangCode.tr ? 'RTDB Senkronizasyon Sağlandı' : 'RTDB Sync Restored',
              detail: '${_settings.espDeviceId} · ${target.toStringAsFixed(1)}°C',
              category: EspLogCategory.sync,
            ),
            espOnline: true,
            espLastPingAt: nowLabel,
          );
        }
        setState(() {
          _settings = _settings.copyWith(
            espOnline: true,
            espLastPingAt: nowLabel,
            cloudLastSyncAt: nowLabel,
            cloudLastSyncOk: true,
            cloudLastSyncMessage: syncMsg,
          );
        });
        _persist();

        if (allowAutoPull && _settings.cloudAutoPullEnabled) {
          FirebaseSyncService.pullState(
            baseUrl: _settings.firebaseRtdbUrl,
            apiKey: _settings.firebaseApiKey,
            nodePath: _settings.firebaseNodePath,
          ).then((pullRes) {
            if (!mounted || !pullRes.ok) return;
            _applyPullSyncResult(pullRes);
          });
        }
      } else {
        _recordSyncFailure(res, notifyUser: notifyUserOnFailure);
      }
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    NotificationService.dismissActiveBanner();
    _clockTimer?.cancel();
    _idleTimer?.cancel();
    _automationTimer?.cancel();
    _aiCallDebounceTimer?.cancel();
    _pageController.dispose();
    AmbientAudioService.stop();
    AmbientAudioService.stopRingtone();
    VoiceSpeechService.stopSpeaking();
    VoiceSpeechService.stopListening();
    HardwareService.exitSmartDisplayHardware();
    super.dispose();
  }

  void _stepTab(int dir) {
    if (dir == 0) return;
    final ordered = _visual.orderedTabs;
    if (ordered.isEmpty) return;
    _triggerHaptic();
    _resetIdleTimer();
    final nextVirtual = _virtualPageIndex + dir;
    final nextReal = ThermostatMath.wrapRealIndex(nextVirtual, ordered.length);
    setState(() {
      _virtualPageIndex = nextVirtual;
      _activeTab = ordered[nextReal].id;
      _activeTabCanVertScroll = false;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        nextVirtual,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _selectTab(TabId tab) {
    final ordered = _visual.orderedTabs;
    final idx = ordered.indexWhere((t) => t.id == tab);
    if (idx < 0) return;
    _triggerHaptic();
    _resetIdleTimer();
    final targetVirtual = ThermostatMath.nearestCircularVirtualIndex(
      currentVirtualIndex: _virtualPageIndex,
      targetRealIndex: idx,
      length: ordered.length,
    );
    setState(() {
      _virtualPageIndex = targetVirtual;
      _activeTab = tab;
      _activeTabCanVertScroll = false;
    });
    if (_pageController.hasClients) {
      _pageController.animateToPage(
        targetVirtual,
        duration: const Duration(milliseconds: 380),
        curve: Curves.easeOutCubic,
      );
    }
  }

  void _handlePagePointerSignal(PointerSignalEvent event) {
    if (event is! PointerScrollEvent) return;
    if (TactileMotionScope.wasScrollEventConsumed(event)) return;
    if (_ambientMode || _screensaverPreview || _showBootCeremony || _voiceOpen) return;
    // ReportScreen & ScheduleScreen manage sub-tab wheeling first and invoke boundary callbacks.
    if (_activeTab == TabId.rapor || _activeTab == TabId.prog) return;
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
    _lastWheelNavAt = now;
    _stepTab(dir);
  }

  void _launchAiCall({
    required AiCallReason reason,
    required bool urgent,
    bool trackCooldown = true,
    String? scheduleTitleTr,
    String? scheduleTitleEn,
  }) {
    if (!mounted || _aiCallOpen) return;
    _idleTimer?.cancel();
    if (_screensaverPreview) {
      HardwareService.exitSmartDisplayHardware();
    }
    setState(() {
      _screensaverPreview = false;
      _aiCallReason = reason;
      _aiCallUrgent = urgent;
      _activeCallScheduleTr = scheduleTitleTr;
      _activeCallScheduleEn = scheduleTitleEn;
      _aiCallOpen = true;
      if (trackCooldown) {
        _lastAiCallAt = DateTime.now();
      }
    });
  }

  void _evaluateScheduledActions(DateTime tickNow) {
    if (!mounted) return;
    final eval = ScheduleEngine.evaluateAtMinute(
      now: tickNow,
      slots: _schedule,
      customRules: _customScheduleRules,
    );
    if (eval.completedOnceRuleIds.isNotEmpty) {
      setState(() {
        _customScheduleRules = [
          for (final r in _customScheduleRules)
            if (eval.completedOnceRuleIds.contains(r.id))
              r.copyWith(enabled: false)
            else
              r,
        ];
      });
      _persist();
    }
    if (eval.hasTriggered && eval.nextTargetTemp != null) {
      _changeTarget(
        eval.nextTargetTemp!,
        scheduleTitleTr: eval.triggeredTitleTr,
        scheduleTitleEn: eval.triggeredTitleEn,
      );
    }
  }

  void _evaluateBoilerAlertsAndCalls({
    required bool wasHeating,
    required double nextTargetTemp,
    double? prevTargetTemp,
    bool isUserChange = false,
    String? scheduleTitleTr,
    String? scheduleTitleEn,
  }) {
    final nextBoiler = ThermostatMath.computeBoilerTelemetry(_roomTemp, nextTargetTemp);
    final safety = NotificationService.evaluateSafetyThresholds(
      roomTemp: _roomTemp,
      outsideTemp: _weatherReport?.currentTempC,
      boiler: nextBoiler,
      sensors: _hardwareSensors,
    );

    bool callLaunched = false;
    if (!_aiCallOpen && !_modalSheetOpen && !_showBootCeremony) {
      final decision = AiCallService.evaluateTrigger(
        enabled: _settings.aiPhoneCallEnabled,
        triggerMode: _settings.aiCallTriggerMode,
        wasHeating: wasHeating,
        nextBoiler: nextBoiler,
        safety: safety,
        roomTemp: _roomTemp,
        targetTemp: nextTargetTemp,
        prevTargetTemp: prevTargetTemp,
        isUserChange: isUserChange,
        lastCallAt: _lastAiCallAt,
      );
      if (decision.shouldCall && decision.reason != null) {
        callLaunched = true;
        _launchAiCall(
          reason: decision.reason!,
          urgent: decision.urgent,
          scheduleTitleTr: scheduleTitleTr,
          scheduleTitleEn: scheduleTitleEn,
        );
      }
    }

    final eventDecision = AiCallService.evaluateBoilerEventNotification(
      enabled: _settings.boilerEventNotificationsEnabled,
      wasHeating: wasHeating,
      nextBoiler: nextBoiler,
      safety: safety,
      locationName: _locationName,
      roomTemp: _roomTemp,
      targetTemp: nextTargetTemp,
      prevTargetTemp: prevTargetTemp,
      isUserChange: isUserChange,
      scheduleTitleTr: scheduleTitleTr,
      scheduleTitleEn: scheduleTitleEn,
      lastPassiveNotifyAt: _lastPassiveEventNotifyAt,
    );
    if (eventDecision.shouldNotify) {
      final isPassiveEvent = eventDecision.kind == BoilerEventAlertKind.coldRoom ||
          eventDecision.kind == BoilerEventAlertKind.hotRoom ||
          (eventDecision.kind == BoilerEventAlertKind.safetyAlert && !isUserChange);
      if (isPassiveEvent) {
        _lastPassiveEventNotifyAt = DateTime.now();
      }
      if (!callLaunched) {
        _enqueueUnreadAlert(
          eventDecision.toAlertEntry(
            id: 'alert_${DateTime.now().microsecondsSinceEpoch}',
            character: _settings.mascotCharacter,
            roomTemp: _roomTemp,
            targetTemp: nextTargetTemp,
            boilerHeating: nextBoiler.isHeating,
            timestamp: NotificationService.formatNowTime(),
          ),
        );
      }
      final tr = _lang == LangCode.tr;
      unawaited(
        NotificationService.dispatchNotification(
          context: context,
          lang: _lang,
          locationName: _locationName,
          roomTemp: _roomTemp,
          targetTemp: nextTargetTemp,
          outsideTemp: _weatherReport?.currentTempC,
          boiler: nextBoiler,
          sensors: _hardwareSensors,
          settings: _settings,
          severityOverride: eventDecision.severity,
          customTitle: tr ? eventDecision.titleTr : eventDecision.titleEn,
          customBody: tr ? eventDecision.bodyTr : eventDecision.bodyEn,
          suppressChime: callLaunched,
          showOverlayBanner: false,
        ).then((res) {
          if (!mounted) return;
          setState(() => _settings = _settings.copyWith(lastNotificationAt: res.timestampLabel));
          _persist();
        }),
      );
    }
  }

  void _scheduleSettledAiCallEvaluation({
    required bool prevHeating,
    required double prevTarget,
    Duration delay = const Duration(milliseconds: 900),
    String? scheduleTitleTr,
    String? scheduleTitleEn,
  }) {
    _pendingCallBaselineHeating ??= prevHeating;
    _pendingCallBaselineTarget ??= prevTarget;
    if (scheduleTitleTr != null) _pendingScheduleTitleTr = scheduleTitleTr;
    if (scheduleTitleEn != null) _pendingScheduleTitleEn = scheduleTitleEn;
    _aiCallDebounceTimer?.cancel();
    _aiCallDebounceTimer = Timer(delay, () {
      final baselineHeating = _pendingCallBaselineHeating ?? prevHeating;
      final baselineTarget = _pendingCallBaselineTarget ?? prevTarget;
      final schedTr = _pendingScheduleTitleTr;
      final schedEn = _pendingScheduleTitleEn;
      _pendingCallBaselineHeating = null;
      _pendingCallBaselineTarget = null;
      _pendingScheduleTitleTr = null;
      _pendingScheduleTitleEn = null;
      if (!mounted) return;
      _evaluateBoilerAlertsAndCalls(
        wasHeating: baselineHeating,
        nextTargetTemp: _targetTemp,
        prevTargetTemp: baselineTarget,
        isUserChange: true,
        scheduleTitleTr: schedTr,
        scheduleTitleEn: schedEn,
      );
    });
  }

  void _changeTarget(
    double next, {
    bool suppressAiCall = false,
    String? scheduleTitleTr,
    String? scheduleTitleEn,
  }) {
    final prevHeating = ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp).isHeating;
    final prevTarget = _targetTemp;
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
    _recordBoilerTransitionEspLog(prevHeating: prevHeating, nextTargetTemp: snapped);
    _syncFirebaseBackground(snapped, pushCommand: true, notifyUserOnFailure: true);
    final isScheduleEvent =
        scheduleTitleTr != null && scheduleTitleTr.trim().isNotEmpty;
    if ((snapped - prevTarget).abs() >= 0.05 && !isScheduleEvent) {
      _maybeShowDisconnectedWarning(snapped);
    }
    if (!suppressAiCall &&
        (isScheduleEvent || (snapped - prevTarget).abs() >= 0.05)) {
      _scheduleSettledAiCallEvaluation(
        prevHeating: prevHeating,
        prevTarget: prevTarget,
        scheduleTitleTr: scheduleTitleTr,
        scheduleTitleEn: scheduleTitleEn,
      );
    }
  }

  void _selectPreset(ThermostatPreset preset) {
    final prevHeating = ThermostatMath.computeBoilerTelemetry(_roomTemp, _targetTemp).isHeating;
    final prevTarget = _targetTemp;
    _triggerHaptic();
    _resetIdleTimer();
    setState(() {
      _targetTemp = preset.temp;
      _activePreset = preset.id;
    });
    _persist();
    _recordBoilerTransitionEspLog(prevHeating: prevHeating, nextTargetTemp: preset.temp);
    _syncFirebaseBackground(preset.temp, pushCommand: true, notifyUserOnFailure: true);
    _maybeShowDisconnectedWarning(preset.temp);
    _scheduleSettledAiCallEvaluation(
      prevHeating: prevHeating,
      prevTarget: prevTarget,
      delay: const Duration(milliseconds: 280),
    );
  }

  void _updateVisual(VisualCustomizationState next) {
    final orderChanged = !_listEquals(next.tabOrder, _visual.tabOrder);
    TactileMotionScope.globalEnabled.value = next.buttonTactileFeedback;
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
      case TabId.ev:
        return KeyedSubtree(
          key: const ValueKey(TabId.ev),
          child: Home3dScreen(
            lang: _lang,
            palette: palette,
            accentColor: activeColor,
            floorPlan: _floorPlan,
            roomTelemetries: _roomTelemetries,
            mainRoomTemp: _roomTemp,
            targetTemp: _targetTemp,
            boiler: boiler,
            espOnline: _settings.espOnline,
            mainEspDeviceId: _settings.espDeviceId,
            performanceMode: _visual.performanceMode,
            onUpdateFloorPlan: (nextPlan) {
              setState(() => _floorPlan = nextPlan);
              _persist();
            },
          ),
        );
      case TabId.termo:
        return KeyedSubtree(
          key: const ValueKey(TabId.termo),
          child: ThermostatScreen(
            roomTemp: _roomTemp,
            targetTemp: _targetTemp,
            activePreset: _activePreset,
            accentColor: activeColor,
            boiler: boiler,
            sensors: _hardwareSensors,
            espOnline: _settings.espOnline,
            lang: _lang,
            palette: palette,
            dialRingStyle: _visual.dialRingStyle,
            performanceMode: _visual.performanceMode,
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
            sensors: _hardwareSensors,
            settings: _settings,
            performanceMode: _visual.performanceMode,
            weatherReport: _weatherReport,
            isLoadingWeather: _weatherLoading,
            weatherError: _weatherError,
            onRefreshWeather: () => _fetchWeather(_locationName, force: true),
            onToggleWeatherAlerts: (v) {
              _triggerHaptic();
              setState(() => _settings = _settings.copyWith(weatherAlertsEnabled: v));
              _persist();
            },
            onChangeLocation: (loc) {
              _triggerHaptic();
              setState(() => _locationName = loc);
              _persist();
              _fetchWeather(loc);
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
            sensors: _hardwareSensors,
            dailyLogs: _dailyLogs,
            gasUnitPriceTl: _gasUnitPriceTl,
            onUpdateGasUnitPrice: (nextRate) {
              _triggerHaptic();
              setState(() => _gasUnitPriceTl = nextRate);
              _persist();
            },
            subTabOrder: _visual.reportSubTabOrder,
            palette: palette,
            performanceMode: _visual.performanceMode,
            onBoundaryPrevMainTab: () => _stepTab(-1),
            onBoundaryNextMainTab: () => _stepTab(1),
          ),
        );
      case TabId.prog:
        return KeyedSubtree(
          key: const ValueKey(TabId.prog),
          child: ScheduleScreen(
            lang: _lang,
            slots: _schedule,
            customRules: _customScheduleRules,
            subTabOrder: _visual.scheduleSubTabOrder,
            palette: palette,
            boiler: boiler,
            sensors: _hardwareSensors,
            todayLog: _dailyLogs[ThermalLogAggregator.formatDateIso(_now)],
            gasUnitPriceTl: _gasUnitPriceTl,
            performanceMode: _visual.performanceMode,
            savedNotice: _savedNotice,
            onBoundaryPrevMainTab: () => _stepTab(-1),
            onBoundaryNextMainTab: () => _stepTab(1),
            onUpdateSlot: (slotId, {time, enabled, targetTemp}) {
              _triggerHaptic();
              setState(() {
                _schedule = [
                  for (final s in _schedule)
                    if (s.id == slotId)
                      s.copyWith(time: time, enabled: enabled, targetTemp: targetTemp)
                    else
                      s,
                ];
              });
              _persist();
            },
            onAddCustomRule: (rule) {
              _triggerHaptic();
              setState(() => _customScheduleRules = [..._customScheduleRules, rule]);
              _persist();
            },
            onUpdateCustomRule: (rule) {
              _triggerHaptic();
              setState(() {
                _customScheduleRules = [
                  for (final r in _customScheduleRules)
                    if (r.id == rule.id) rule else r,
                ];
              });
              _persist();
            },
            onDeleteCustomRule: (ruleId) {
              _triggerHaptic();
              setState(() {
                _customScheduleRules = _customScheduleRules.where((r) => r.id != ruleId).toList();
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
        if (!_screensaverPreview) _resetIdleTimer();
      },
      onPointerUp: (_) {
        if (!_screensaverPreview) _resetIdleTimer();
      },
      child: Scaffold(
        backgroundColor: palette.scaffoldBg,
        body: Stack(
          children: [
            FlowTabBarShell(
              activeTab: _activeTab,
              orderedTabs: orderedTabs,
              startupTab: _visual.startupTab,
              onSelectTab: _selectTab,
              onStepTab: _stepTab,
              onReorderTabs: (nextOrder, {nextStartupTab}) {
                _triggerHaptic();
                _updateVisual(
                  _visual.copyWith(
                    tabOrder: nextOrder,
                    startupTab: nextStartupTab ?? _visual.startupTab,
                  ),
                );
              },
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
                  currentTargetTemp: _targetTemp,
                  character: _settings.mascotCharacter,
                  ttsEnabled: _settings.aiCallVoiceBriefEnabled,
                  onExecute: (res) {
                    if (res.newTargetTemp != null) {
                      _changeTarget(res.newTargetTemp!, suppressAiCall: true);
                    }
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
                                  // Flag Language Quick Toggle (TR / EN)
                                  _TopActionButton(
                                    palette: palette,
                                      onTap: () {
                                        _triggerHaptic();
                                        setState(() {
                                          _lang = _lang == LangCode.tr ? LangCode.en : LangCode.tr;
                                        });
                                        _persist();
                                        _fetchWeather(_locationName);
                                      },
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        _MiniFlagBadge(lang: _lang),
                                        const SizedBox(width: 5),
                                        Text(
                                          _lang == LangCode.tr ? 'TR' : 'EN',
                                          style: TextStyle(
                                            fontSize: 10.5,
                                            fontWeight: FontWeight.w800,
                                            color: palette.textPrimary,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 5),

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
                                    onTap: () async {
                                      _triggerHaptic();
                                      _modalSheetOpen = true;
                                      _idleTimer?.cancel();
                                      await showThemeEffectsSheet(
                                        context: context,
                                        lang: _lang,
                                        accentColor: activeColor,
                                        hapticEnabled: _settings.hapticEnabled,
                                        initialVisual: _visual,
                                        onUpdateVisual: _updateVisual,
                                      );
                                      _modalSheetOpen = false;
                                      if (mounted) _resetIdleTimer();
                                    },
                                    child: Icon(Icons.palette_outlined, size: 17, color: palette.textPrimary),
                                  ),
                                  const SizedBox(width: 5),

                                  // Widget & Screen Order Sheet
                                  _TopActionButton(
                                    palette: palette,
                                    onTap: () async {
                                      _triggerHaptic();
                                      _modalSheetOpen = true;
                                      _idleTimer?.cancel();
                                      await showWidgetOrderSheet(
                                        context: context,
                                        lang: _lang,
                                        accentColor: activeColor,
                                        hapticEnabled: _settings.hapticEnabled,
                                        initialVisual: _visual,
                                        onUpdateVisual: _updateVisual,
                                      );
                                      _modalSheetOpen = false;
                                      if (mounted) _resetIdleTimer();
                                    },
                                    child: Icon(Icons.dashboard_customize_outlined, size: 17, color: palette.textPrimary),
                                  ),

                                  const SizedBox(width: 5),
                                  // Always-available Manual Smart Display TV Launch Button
                                  _TopActionButton(
                                    palette: palette,
                                    onTap: () {
                                      _triggerHaptic();
                                      _reopenSettingsToSmartDisplay = false;
                                      _enterAmbientMode();
                                    },
                                    child: Icon(
                                      Icons.tv_rounded,
                                      size: 17,
                                      color: _settings.smartDisplayEnabled ? activeColor : palette.textPrimary,
                                    ),
                                  ),
                                  const SizedBox(width: 5),

                                    // System Settings Sheet
                                    _TopActionButton(
                                      palette: palette,
                                      onTap: () {
                                        _triggerHaptic();
                                        _openSettingsSheet();
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
                                   child: LayoutBuilder(
                                     builder: (context, viewportConstraints) {
                                       final viewportWidth = viewportConstraints.maxWidth;
                                       return PageView.builder(
                                         controller: _pageController,
                                         physics: const BouncingScrollPhysics(
                                           parent: AlwaysScrollableScrollPhysics(),
                                         ),
                                         onPageChanged: (virtualIdx) {
                                           final realIdx = ThermostatMath.wrapRealIndex(
                                             virtualIdx,
                                             orderedTabs.length,
                                           );
                                           setState(() {
                                             _virtualPageIndex = virtualIdx;
                                             _activeTab = orderedTabs[realIdx].id;
                                             _activeTabCanVertScroll = false;
                                           });
                                         },
                                         itemBuilder: (context, virtualIdx) {
                                           final realIdx = ThermostatMath.wrapRealIndex(
                                             virtualIdx,
                                             orderedTabs.length,
                                           );
                                           final meta = orderedTabs[realIdx];
                                           return AnimatedBuilder(
                                             animation: _pageController,
                                             builder: (context, child) {
                                               double currentPage = _virtualPageIndex.toDouble();
                                               if (_pageController.hasClients &&
                                                   _pageController.position.haveDimensions) {
                                                 currentPage = _pageController.page ?? currentPage;
                                               }
                                               final signedDelta = currentPage - virtualIdx;
                                               final absDelta = signedDelta.abs();
                                               if (absDelta < 0.004 || absDelta > 1.25) {
                                                 return child!;
                                               }
                                               // Flat directional depth+blur transition (zero rotateY tilt):
                                               // - signedDelta <= 0: incoming right page glides cleanly & flat.
                                               // - signedDelta > 0: left page softly recedes backward, fades & blurs.
                                               if (signedDelta <= 0.0) {
                                                 return child!;
                                               }
                                               final p = signedDelta.clamp(0.0, 1.0);
                                               final scale = (1.0 - p * 0.075).clamp(0.90, 1.0);
                                               final opacity = (1.0 - p * 0.90).clamp(0.0, 1.0);
                                               final driftX = signedDelta * viewportWidth * 0.65;

                                               Widget content = Opacity(
                                                 opacity: opacity,
                                                 child: Transform.translate(
                                                   offset: Offset(driftX, 0.0),
                                                   child: Transform.scale(
                                                     scale: scale,
                                                     alignment: Alignment.center,
                                                     child: child,
                                                   ),
                                                 ),
                                               );
                                               if (!isEco) {
                                                 final sigma = (p * 6.5).clamp(0.0, 7.0);
                                                 if (sigma >= 0.25) {
                                                   content = ImageFiltered(
                                                     imageFilter: ui.ImageFilter.blur(
                                                       sigmaX: sigma,
                                                       sigmaY: sigma,
                                                     ),
                                                     child: content,
                                                   );
                                                 }
                                               }
                                               return content;
                                             },
                                             child: _buildTabPage(meta.id, boiler, activeColor, palette),
                                           );
                                         },
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

              // Fullscreen Screensaver (auto-launches after idle seconds or on Preview)
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
                    setState(() => _screensaverPreview = false);
                    _resetIdleTimer();
                  },
                ),

             // Enhanced Smart Display / Dynamic Ambient Mode Fullscreen View
             if (_ambientMode)
               Positioned.fill(
                 child: SmartDisplayOverlay(
                   settings: _settings,
                   slideIndex: _slideIndex,
                   now: _now,
                   locationName: _locationName,
                   roomTemp: _roomTemp,
                   targetTemp: _targetTemp,
                   boiler: boiler,
                   weatherReport: _weatherReport,
                   accentColor: activeColor,
                   palette: palette,
                   lang: _lang,
                   paletteTag: _visual.theme.name,
                   dialRingStyle: _visual.dialRingStyle,
                   performanceMode: _visual.performanceMode,
                   forcedAod: _ambientForcedAod,
                   onWakeFromAutoAod: () {
                     setState(() {
                       _ambientForcedAod = false;
                       _ambientElapsedSeconds = 0;
                     });
                     final hasCustomAudio = _settings.customAudioSource.trim().isNotEmpty ||
                         _settings.customAudioLabel.trim().isNotEmpty;
                     if (_settings.ambientSoundtrack == AmbientSoundtrack.customMp3 &&
                         hasCustomAudio &&
                         _settings.ambientVolume > 0.01) {
                       AmbientAudioService.start(
                         track: AmbientSoundtrack.customMp3,
                         customSource: _settings.customAudioSource.isNotEmpty
                             ? _settings.customAudioSource
                             : _settings.customAudioLabel,
                         volume: _settings.ambientVolume,
                       );
                     }
                   },
                   onChangeTargetTemp: (next) => _changeTarget(next),
                   onSelectPreset: _selectPreset,
                   onUpdateSettings: (next) {
                     setState(() {
                       _settings = next;
                       _ambientForcedAod = false;
                       _ambientElapsedSeconds = 0;
                     });
                     _persist();
                   },
                   onStepSlideIndex: (delta) {
                     final total = _settings.slideImages.isNotEmpty ? _settings.slideImages.length : 5;
                     setState(() {
                       _slideTicks = 0;
                       _slideIndex = ((_slideIndex + delta) % total + total) % total;
                     });
                   },
                   onClose: _exitAmbientMode,
                 ),
               ),

            // AI Voice Phone Call Assistant Fullscreen Overlay
            if (_aiCallOpen)
              AiPhoneCallOverlay(
                character: _settings.mascotCharacter,
                reason: _aiCallReason,
                urgent: _aiCallUrgent,
                ringSeconds: _settings.aiCallRingSeconds,
                voiceBriefEnabled: _settings.aiCallVoiceBriefEnabled,
                missedAlertEnabled: _settings.aiCallMissedAlertEnabled,
                hapticEnabled: _settings.hapticEnabled,
                hapticStrength: _settings.hapticStrength,
                locationName: _locationName,
                espDeviceId: _settings.espDeviceId,
                roomTemp: _roomTemp,
                targetTemp: _targetTemp,
                boiler: boiler,
                safety: NotificationService.evaluateSafetyThresholds(
                  roomTemp: _roomTemp,
                  outsideTemp: _weatherReport?.currentTempC,
                  boiler: boiler,
                  sensors: _hardwareSensors,
                ),
                lang: _lang,
                scheduleTitleTr: _activeCallScheduleTr,
                scheduleTitleEn: _activeCallScheduleEn,
                onAdjustTargetTemp: (t) => _changeTarget(t, suppressAiCall: true),
                onMissedCallNotify: () {
                  final tr = _lang == LangCode.tr;
                  final meta = MascotMeta.of(_settings.mascotCharacter);
                  NotificationService.dispatchNotification(
                    context: context,
                    lang: _lang,
                    locationName: _locationName,
                    roomTemp: _roomTemp,
                    targetTemp: _targetTemp,
                    outsideTemp: _weatherReport?.currentTempC,
                    boiler: boiler,
                    sensors: _hardwareSensors,
                    settings: _settings,
                    severityOverride: _aiCallUrgent ? AlertSeverity.critical : AlertSeverity.warning,
                    customTitle: tr
                        ? '📵 Cevapsız AI Asistan Araması (${meta.name})'
                        : '📵 Missed AI Assistant Call (${meta.name})',
                    customBody: tr
                        ? '$_locationName · Oda ${_roomTemp != null ? '${_roomTemp!.toStringAsFixed(1)}°C' : '--'} / Hedef ${_targetTemp.toStringAsFixed(1)}°C · ${boiler.statusTextTr}'
                        : '$_locationName · Room ${_roomTemp != null ? '${_roomTemp!.toStringAsFixed(1)}°C' : '--'} / Target ${_targetTemp.toStringAsFixed(1)}°C · ${boiler.statusTextEn}',
                    showOverlayBanner: false,
                  );
                },
                onFinishCall: (entry) {
                  final nextHistory = AiCallService.appendCallHistory(
                    _settings.aiCallHistory,
                    entry,
                    maxEntries: 10,
                  );
                  setState(() {
                    _settings = _settings.copyWith(aiCallHistory: nextHistory);
                  });
                  if (entry.status == AiCallStatus.missed ||
                      entry.status == AiCallStatus.declined) {
                    _enqueueUnreadAlert(entry);
                  }
                },
                onCloseWithOutcome: (outcome) {
                  setState(() {
                    _aiCallOpen = false;
                    _activeCallScheduleTr = null;
                    _activeCallScheduleEn = null;
                    _settings = _settings.copyWith(aiCallLastOutcome: outcome);
                  });
                  _persist();
                  _resetIdleTimer();
                },
              ),

            // Persistent Top Notification Queue: Single, Stepped Stack, or Telegram-style Capsules
            // Shown both on normal screens and on top of active Smart Display.
            if (_unreadAlerts.isNotEmpty &&
                !_aiCallOpen &&
                !_screensaverPreview &&
                !_showBootCeremony)
              Builder(
                builder: (context) {
                  final isExpanded = _alertsExpanded && _unreadAlerts.length > 1;
                  final stackWidget = TopAlertStack(
                    alerts: _unreadAlerts,
                    expanded: isExpanded,
                    lang: _lang,
                    onToggleExpand: () {
                      _triggerHaptic();
                      setState(() => _alertsExpanded = !_alertsExpanded);
                    },
                    onDismissAlert: (id) {
                      _triggerHaptic();
                      _markAlertRead(id);
                    },
                    onDismissAll: () {
                      _triggerHaptic();
                      setState(() {
                        _unreadAlerts = const [];
                        _alertsExpanded = false;
                      });
                      _persist();
                    },
                    onTapAlert: (entry) {
                      _triggerHaptic();
                      _modalSheetOpen = true;
                      _idleTimer?.cancel();
                      showMissedCallActionDialog(
                        context: context,
                        entry: entry,
                        lang: _lang,
                        onApplyAction: (act) {
                          _changeTarget(act.targetTemp, suppressAiCall: true);
                          if (!entry.isSystemAlert) {
                            setState(() {
                              _settings = _settings.copyWith(
                                aiCallHistory: AiCallService.updateCallHistoryAction(
                                  _settings.aiCallHistory,
                                  entry.id,
                                  actionTr: act.logActionTr,
                                  actionEn: act.logActionEn,
                                ),
                              );
                            });
                          }
                          _markAlertRead(entry.id);
                        },
                        onDismissWithoutAction: () {
                          _markAlertRead(entry.id);
                        },
                      ).whenComplete(() {
                        _modalSheetOpen = false;
                        if (mounted) _resetIdleTimer();
                      });
                    },
                  );

                  if (isExpanded) {
                    return Positioned.fill(child: stackWidget);
                  }
                  return Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: SafeArea(
                      bottom: false,
                      child: stackWidget,
                    ),
                  );
                },
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
                  sensors: _hardwareSensors,
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
    return TactilePress(
      child: GestureDetector(
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
      ),
    );
  }
}

class _MiniFlagBadge extends StatelessWidget {
  final LangCode lang;

  const _MiniFlagBadge({required this.lang});

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(3),
      child: SizedBox(
        width: 17,
        height: 12,
        child: CustomPaint(painter: _MiniFlagPainter(isTr: lang == LangCode.tr)),
      ),
    );
  }
}

class _MiniFlagPainter extends CustomPainter {
  final bool isTr;

  const _MiniFlagPainter({required this.isTr});

  @override
  void paint(Canvas canvas, Size size) {
    if (isTr) {
      // Crisp Turkish Flag (#E30A17 + White Crescent & 5-Point Star)
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFFE30A17));
      final outerCenter = Offset(size.width * 0.38, size.height * 0.50);
      final outerR = size.height * 0.29;
      canvas.drawCircle(outerCenter, outerR, Paint()..color = Colors.white);
      canvas.drawCircle(
        Offset(size.width * 0.44, size.height * 0.50),
        outerR * 0.80,
        Paint()..color = const Color(0xFFE30A17),
      );
      final starCx = size.width * 0.65;
      final starCy = size.height * 0.50;
      final starR = size.height * 0.14;
      final starInner = starR * 0.42;
      final starPath = Path();
      for (int i = 0; i < 10; i++) {
        final r = i.isEven ? starR : starInner;
        final a = -math.pi / 2 + (i * math.pi / 5);
        final px = starCx + math.cos(a) * r;
        final py = starCy + math.sin(a) * r;
        if (i == 0) {
          starPath.moveTo(px, py);
        } else {
          starPath.lineTo(px, py);
        }
      }
      starPath.close();
      canvas.drawPath(starPath, Paint()..color = Colors.white);
    } else {
      // Crisp UK Union Flag for English
      canvas.drawRect(Offset.zero & size, Paint()..color = const Color(0xFF012169));
      final whiteDiag = Paint()
        ..color = Colors.white
        ..strokeWidth = 2.4;
      final redDiag = Paint()
        ..color = const Color(0xFFC8102E)
        ..strokeWidth = 1.1;
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), whiteDiag);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), whiteDiag);
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), redDiag);
      canvas.drawLine(Offset(size.width, 0), Offset(0, size.height), redDiag);

      canvas.drawRect(
        Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: size.width, height: 3.8),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 3.8, height: size.height),
        Paint()..color = Colors.white,
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: size.width, height: 2.1),
        Paint()..color = const Color(0xFFC8102E),
      );
      canvas.drawRect(
        Rect.fromCenter(center: Offset(size.width / 2, size.height / 2), width: 2.1, height: size.height),
        Paint()..color = const Color(0xFFC8102E),
      );
    }
  }

  @override
  bool shouldRepaint(covariant _MiniFlagPainter oldDelegate) => oldDelegate.isTr != isTr;
}
