import 'dart:convert';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:termostat_flow/main.dart';
import 'package:termostat_flow/models/house_plan_model.dart';
import 'package:termostat_flow/models/thermostat_state.dart';
import 'package:termostat_flow/screens/home_3d_screen.dart';
import 'package:termostat_flow/screens/secondary_screens.dart';
import 'package:termostat_flow/screens/theme_effects_sheet.dart';
import 'package:termostat_flow/screens/thermostat_screen.dart';
import 'package:termostat_flow/services/ai_call_service.dart';
import 'package:termostat_flow/services/ambient_audio_service.dart';
import 'package:termostat_flow/services/audio_tempo_analyzer.dart';
import 'package:termostat_flow/services/esp_log_service.dart';
import 'package:termostat_flow/services/firebase_sync_service.dart';
import 'package:termostat_flow/services/hardware_service.dart';
import 'package:termostat_flow/services/media_storage_service.dart';
import 'package:termostat_flow/services/notification_service.dart';
import 'package:termostat_flow/services/schedule_engine.dart';
import 'package:termostat_flow/services/vault_crypto_service.dart';
import 'package:termostat_flow/services/voice_gender_classifier.dart';
import 'package:termostat_flow/services/voice_speech_service.dart';
import 'package:termostat_flow/services/weather_service.dart';
import 'package:termostat_flow/widgets/boot_ceremony_overlay.dart';
import 'package:termostat_flow/widgets/dial_ring_effects.dart';
import 'package:termostat_flow/widgets/flow_tab_bar.dart';
import 'package:termostat_flow/widgets/missed_call_alert.dart';
import 'package:termostat_flow/widgets/rotary_dial.dart';
import 'package:termostat_flow/widgets/smart_display_overlay.dart';
import 'package:termostat_flow/widgets/tactile_button.dart';
import 'package:termostat_flow/widgets/termo_bot.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('ThermostatMath snaps temperatures to 0.5C bounds', () {
    expect(ThermostatMath.snapTemperature(22.34), 22.5);
    expect(ThermostatMath.snapTemperature(5.0), ThermostatMath.minTemp);
    expect(ThermostatMath.snapTemperature(40.0), ThermostatMath.maxTemp);
  });

  test('Boiler telemetry modulates when target exceeds room temp', () {
    final heating = ThermostatMath.computeBoilerTelemetry(21.8, 22.5);
    expect(heating.isHeating, isTrue);
    expect(heating.flamePercent, greaterThanOrEqualTo(20));
    expect(heating.waterPressureBar, 1.6);

    final standby = ThermostatMath.computeBoilerTelemetry(22.5, 22.0);
    expect(standby.isHeating, isFalse);
    expect(standby.flamePercent, 0);
    expect(standby.waterPressureBar, 1.6);
  });

  test('VisualCustomizationState round-trips theme, 5-tab order, and startupTab', () {
    final initial = VisualCustomizationState.defaults().copyWith(
      theme: AppThemeMode.obsidianLavender,
      obsidianPalette: ObsidianPalette.royalViolet,
      performanceMode: PerformanceMode.ecoBattery,
      weatherPreview: WeatherEffectPreview.rainy,
      tabOrder: [TabId.hava, TabId.ev, TabId.termo, TabId.prog, TabId.rapor],
      startupTab: TabId.ev,
    );
    final restored = VisualCustomizationState.fromJson(initial.toJson());
    expect(restored.theme, AppThemeMode.obsidianLavender);
    expect(restored.obsidianPalette, ObsidianPalette.royalViolet);
    expect(restored.performanceMode, PerformanceMode.ecoBattery);
    expect(restored.weatherPreview, WeatherEffectPreview.rainy);
    expect(restored.tabOrder, [TabId.hava, TabId.ev, TabId.termo, TabId.prog, TabId.rapor]);
    expect(restored.startupTab, TabId.ev);
  });

  test('SystemSettingsState round-trips Smart Display, TermoBot and Weather fields', () {
    final initial = SystemSettingsState.defaults().copyWith(
      smartDisplayMode: SmartDisplayMode.liveNature,
      slideDurationSeconds: 10,
      slideEffect: SlideTransitionEffect.zoom,
      smartDisplayLayout: VisualLayoutMode.framed,
      ambientSoundtrack: AmbientSoundtrack.customMp3,
      customAudioLabel: 'Lo-Fi Chill.mp3',
      customAudioSource: '/storage/emulated/0/Music/Lo-Fi Chill.mp3',
      customVideoLabel: 'fireplace_loop.mp4',
      customVideoSource: 'https://example.com/fireplace_loop.mp4',
      ambientVolume: 0.75,
      marqueeTrackEnabled: false,
      equalizerEnabled: true,
      equalizerStyle: EqualizerStyle.wave,
      displayBrightness: 50,
      smartDisplayAutoMinutes: 15,
      displaySleepMinutes: 60,
      oledPixelShiftEnabled: false,
      weatherAlertsEnabled: false,
      notifyChimeEnabled: false,
      lastNotificationAt: '21:45',
      hapticStrength: 95,
      bootCeremonyStyle: BootCeremonyStyle.precisionSweep,
      bootCeremonyDurationMs: 2400,
      bootSoundChimeEnabled: false,
      mascotCharacter: MascotCharacter.mirnav,
      screensaverIdleSeconds: 120,
      screensaverBackdrop: ScreensaverBackdrop.termoLab,
      screensaverBlurBg: true,
      mascotSoundsEnabled: false,
      screensaverCustomBgSource: 'https://example.com/hearth.jpg',
      screensaverCustomBgLabel: 'example.com',
      mascotScale: 1.35,
    );
    final restored = SystemSettingsState.fromJson(initial.toJson());
    expect(restored.smartDisplayMode, SmartDisplayMode.liveNature);
    expect(restored.slideDurationSeconds, 10);
    expect(restored.slideEffect, SlideTransitionEffect.zoom);
    expect(restored.smartDisplayLayout, VisualLayoutMode.framed);
    expect(restored.ambientSoundtrack, AmbientSoundtrack.customMp3);
    expect(restored.customAudioLabel, 'Lo-Fi Chill.mp3');
    expect(restored.customAudioSource, '/storage/emulated/0/Music/Lo-Fi Chill.mp3');
    expect(restored.customVideoLabel, 'fireplace_loop.mp4');
    expect(restored.customVideoSource, 'https://example.com/fireplace_loop.mp4');
    expect(restored.ambientTrackTitle(LangCode.tr), 'Lo-Fi Chill.mp3');
    expect(restored.ambientVolume, 0.75);
    expect(restored.marqueeTrackEnabled, isFalse);
    expect(restored.equalizerEnabled, isTrue);
    expect(restored.equalizerStyle, EqualizerStyle.wave);
    expect(restored.displayBrightness, 50);
    expect(restored.smartDisplayAutoMinutes, 15);
    expect(restored.displaySleepMinutes, 60);
    expect(restored.oledPixelShiftEnabled, isFalse);
    expect(restored.weatherAlertsEnabled, isFalse);
    expect(restored.notifyChimeEnabled, isFalse);
    expect(restored.lastNotificationAt, '21:45');
    expect(restored.hapticStrength, 95);
    expect(restored.bootCeremonyStyle, BootCeremonyStyle.precisionSweep);
    expect(restored.bootCeremonyDurationMs, 2400);
    expect(restored.bootSoundChimeEnabled, isFalse);
    expect(restored.mascotCharacter, MascotCharacter.mirnav);
    expect(restored.screensaverIdleSeconds, 120);
    expect(restored.screensaverBackdrop, ScreensaverBackdrop.termoLab);
    expect(restored.screensaverBlurBg, isTrue);
    expect(restored.mascotSoundsEnabled, isFalse);
    expect(restored.screensaverCustomBgSource, 'https://example.com/hearth.jpg');
    expect(restored.screensaverCustomBgLabel, 'example.com');
    expect(restored.mascotScale, 1.35);

    final clamped = initial.copyWith(
      bootCeremonyDurationMs: 9000,
      mascotScale: 3.0,
      smartDisplayAutoMinutes: 99,
      displaySleepMinutes: 200,
    );
    expect(clamped.bootCeremonyDurationMs, 3500);
    expect(clamped.mascotScale, 1.60);
    expect(clamped.smartDisplayAutoMinutes, 60);
    expect(clamped.displaySleepMinutes, 120);
    expect(initial.copyWith(mascotScale: 0.10).mascotScale, 0.60);
  });

  test('DailyWeatherForecast.sample5Days includes 5 days with hourly slots', () {
    expect(DailyWeatherForecast.sample5Days.length, 5);
    for (final day in DailyWeatherForecast.sample5Days) {
      expect(day.hourly.length, greaterThanOrEqualTo(6));
    }
  });

  test('VaultCryptoService encrypts and decrypts real PBKDF2 AES-256-GCM backups', () async {
    final settings = SystemSettingsState.defaults().copyWith(
      vaultPin: '4820',
      telegramChatId: '99887766',
      googleHomeRoom: 'Mutfak',
    );
    final encryptedRaw = await VaultCryptoService.encryptBackupJson(
      settings: settings,
      locationName: 'Yazlık · İzmir',
      pin: '4820',
    );

    final envelope = jsonDecode(encryptedRaw) as Map<String, dynamic>;
    expect(envelope['format'], 'termostat-vault-aes256-v2');
    expect(envelope['cipher'], 'AES-256-GCM');
    expect(envelope['kdf'], 'PBKDF2-HMAC-SHA256');

    final decrypted = await VaultCryptoService.decryptBackupJson(
      rawJson: encryptedRaw,
      pin: '4820',
    );
    expect(decrypted.locationName, 'Yazlık · İzmir');
    expect(decrypted.settings.telegramChatId, '99887766');
    expect(decrypted.settings.googleHomeRoom, 'Mutfak');

    await expectLater(
      () => VaultCryptoService.decryptBackupJson(rawJson: encryptedRaw, pin: '0000'),
      throwsA(anything),
    );
  });

  test('AmbientAudioService generates valid RIFF/WAVE PCM headers for soundtracks and chimes', () {
    for (final track in AmbientSoundtrack.values) {
      final bytes = AmbientAudioService.generateAmbientWavBytes(track);
      expect(bytes.length, greaterThan(44));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    }
    final chime = AmbientAudioService.generateChimeWavBytes();
    final urgentChime = AmbientAudioService.generateChimeWavBytes(urgent: true);
    expect(String.fromCharCodes(chime.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(urgentChime.sublist(8, 12)), 'WAVE');
  });

  test('NotificationService detects low pressure and freeze risk thresholds accurately', () {
    final safeBoiler = ThermostatMath.computeBoilerTelemetry(21.8, 22.5);
    final safeGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 21.8,
      outsideTemp: 15.0,
      boiler: safeBoiler,
    );
    expect(safeGuard.hasCriticalAlert, isFalse);
    expect(safeGuard.lowPressure, isFalse);
    expect(safeGuard.freezeRisk, isFalse);

    const lowBarBoiler = BoilerTelemetry(
      isHeating: false,
      flamePercent: 0,
      pumpRpm: 0,
      waterPressureBar: 0.8,
      modulationActive: false,
      statusTextTr: 'Düşük Basınç',
      statusTextEn: 'Low Pressure',
    );
    final lowBarGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 21.0,
      outsideTemp: 12.0,
      boiler: lowBarBoiler,
    );
    expect(lowBarGuard.hasCriticalAlert, isTrue);
    expect(lowBarGuard.lowPressure, isTrue);

    final freezeGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 4.5,
      outsideTemp: 2.0,
      boiler: safeBoiler,
    );
    expect(freezeGuard.hasCriticalAlert, isTrue);
    expect(freezeGuard.freezeRisk, isTrue);
  });

  test('AmbientAudioService generates valid mascot WAV audio for all characters and sleepy mode', () {
    for (final mascot in MascotCharacter.values) {
      final awakeBytes = AmbientAudioService.generateMascotSoundWavBytes(mascot);
      final sleepyBytes = AmbientAudioService.generateMascotSoundWavBytes(mascot, sleepy: true);
      expect(awakeBytes.length, greaterThan(44));
      expect(sleepyBytes.length, greaterThan(44));
      expect(String.fromCharCodes(awakeBytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(awakeBytes.sublist(8, 12)), 'WAVE');
      expect(String.fromCharCodes(sleepyBytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(sleepyBytes.sublist(8, 12)), 'WAVE');
    }
  });

  test('MascotBehavior covers 6 modes and all 3D mascot asset paths exist cleanly', () {
    expect(MascotBehavior.values.length, 6);
    for (final mascot in MascotCharacter.values) {
      final meta = MascotMeta.of(mascot);
      expect(meta.assetPath.startsWith('assets/mascots/'), isTrue);
      expect(meta.assetPath.endsWith('.jpg'), isTrue);
    }
  });

  test('FullscreenScreensaverOverlay.buildBehaviorSequence schedules 3 cycles of non-sleep animations', () {
    final plan = FullscreenScreensaverOverlay.buildBehaviorSequence();
    expect(plan.length, 12);
    expect(plan.contains(MascotBehavior.deepSleep), isFalse);
    expect(plan.contains(MascotBehavior.idle), isFalse);
    for (final active in [
      MascotBehavior.patrol,
      MascotBehavior.knock,
      MascotBehavior.think,
      MascotBehavior.read,
    ]) {
      expect(plan.where((b) => b == active).length, 3);
    }
    for (int i = 1; i < plan.length; i++) {
      expect(plan[i] != plan[i - 1], isTrue);
    }
  });

  test('HardwareService scales haptic vibration amplitude within valid 1-255 bounds', () {
    expect(HardwareService.scaledAmplitude(200, 100), 200);
    expect(HardwareService.scaledAmplitude(200, 50), 100);
    expect(HardwareService.scaledAmplitude(200, 10), 80); // clamped min 40%
    expect(HardwareService.scaledAmplitude(255, 100), 255);
  });

  test('SystemSettingsState round-trips and clamps AI Phone Call settings', () {
    final initial = SystemSettingsState.defaults().copyWith(
      aiPhoneCallEnabled: false,
      aiCallRingSeconds: 20,
      aiCallTriggerMode: AiCallTriggerMode.ignitionAndSafety,
      aiCallMissedAlertEnabled: false,
      aiCallVoiceBriefEnabled: false,
      aiCallLastOutcome: '14:22 · Cevaplandı (00:18)',
    );
    final restored = SystemSettingsState.fromJson(initial.toJson());
    expect(restored.aiPhoneCallEnabled, isFalse);
    expect(restored.aiCallRingSeconds, 20);
    expect(restored.aiCallTriggerMode, AiCallTriggerMode.ignitionAndSafety);
    expect(restored.aiCallMissedAlertEnabled, isFalse);
    expect(restored.aiCallVoiceBriefEnabled, isFalse);
    expect(restored.aiCallLastOutcome, '14:22 · Cevaplandı (00:18)');

    expect(initial.copyWith(aiCallRingSeconds: 2).aiCallRingSeconds, 5);
    expect(initial.copyWith(aiCallRingSeconds: 99).aiCallRingSeconds, 30);
  });

  test('AiCallService evaluates ignition, critical safety, and cooldown accurately', () {
    final heatingBoiler = ThermostatMath.computeBoilerTelemetry(21.0, 23.0);
    final standbyBoiler = ThermostatMath.computeBoilerTelemetry(22.0, 21.5);
    final safeGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 21.0,
      outsideTemp: 15.0,
      boiler: heatingBoiler,
    );
    final freezeGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 4.0,
      outsideTemp: 1.0,
      boiler: standbyBoiler,
    );
    final t0 = DateTime(2026, 11, 21, 14, 0, 0);

    // Ignition transition triggers call
    final onIgn = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.onIgnition,
      wasHeating: false,
      nextBoiler: heatingBoiler,
      safety: safeGuard,
      now: t0,
    );
    expect(onIgn.shouldCall, isTrue);
    expect(onIgn.reason, AiCallReason.ignition);
    expect(onIgn.urgent, isFalse);

    // Already heating does NOT re-trigger
    final alreadyHeating = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.onIgnition,
      wasHeating: true,
      nextBoiler: heatingBoiler,
      safety: safeGuard,
      now: t0,
    );
    expect(alreadyHeating.shouldCall, isFalse);

    // Cooldown suppresses immediate repeat call
    final cooledDown = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.onIgnition,
      wasHeating: false,
      nextBoiler: heatingBoiler,
      safety: safeGuard,
      lastCallAt: t0.subtract(const Duration(seconds: 20)),
      now: t0,
    );
    expect(cooledDown.shouldCall, isFalse);

    // criticalOnly ignores normal ignition and fires urgent call on safety threshold breach
    final critIgnored = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.criticalOnly,
      wasHeating: false,
      nextBoiler: heatingBoiler,
      safety: safeGuard,
      now: t0,
    );
    expect(critIgnored.shouldCall, isFalse);

    final critFired = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.criticalOnly,
      wasHeating: true,
      nextBoiler: standbyBoiler,
      safety: freezeGuard,
      now: t0,
    );
    expect(critFired.shouldCall, isTrue);
    expect(critFired.reason, AiCallReason.safetyAlert);
    expect(critFired.urgent, isTrue);
  });

  test('AmbientAudioService synthesizes valid ringtone, call chime, and voice brief WAV headers', () {
    for (final urgent in [false, true]) {
      final ring = AmbientAudioService.generateRingtoneWavBytes(urgent: urgent);
      expect(ring.length, greaterThan(44));
      expect(String.fromCharCodes(ring.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(ring.sublist(8, 12)), 'WAVE');
    }
    for (final ans in [false, true]) {
      final chime = AmbientAudioService.generateCallChimeWavBytes(answered: ans);
      expect(chime.length, greaterThan(44));
      expect(String.fromCharCodes(chime.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(chime.sublist(8, 12)), 'WAVE');
    }
    final voiceCue = AmbientAudioService.generateVoiceBriefCueWavBytes();
    expect(voiceCue.length, greaterThan(44));
    expect(String.fromCharCodes(voiceCue.sublist(0, 4)), 'RIFF');
    expect(String.fromCharCodes(voiceCue.sublist(8, 12)), 'WAVE');
  });

  test('ThermostatMath.parseVoiceCommand handles boiler shutoff, relative deltas, and modes', () {
    final off = ThermostatMath.parseVoiceCommand('kombiyi kapat', currentTargetTemp: 23.0);
    expect(off.handled, isTrue);
    expect(off.newTargetTemp, ThermostatMath.minTemp);

    final up5 = ThermostatMath.parseVoiceCommand('kombiyi 5 derece arttır', currentTargetTemp: 20.0);
    expect(up5.handled, isTrue);
    expect(up5.newTargetTemp, 25.0);

    final down2 = ThermostatMath.parseVoiceCommand('2 derece azalt', currentTargetTemp: 22.5);
    expect(down2.handled, isTrue);
    expect(down2.newTargetTemp, 20.5);

    final wordUp = ThermostatMath.parseVoiceCommand('beş derece yükselt', currentTargetTemp: 19.0);
    expect(wordUp.handled, isTrue);
    expect(wordUp.newTargetTemp, 24.0);

    final eco = ThermostatMath.parseVoiceCommand('eko mod');
    expect(eco.handled, isTrue);
    expect(eco.newTargetTemp, 20.0);
    expect(eco.newPreset, PresetId.eko);

    final boost = ThermostatMath.parseVoiceCommand('boost modunu aktif et');
    expect(boost.handled, isTrue);
    expect(boost.newTargetTemp, 25.0);
    expect(boost.newPreset, PresetId.boost);
  });

  test('VoiceSpeechService assigns female/male voices and formats derece naturally', () {
    expect(VoiceSpeechService.isFemaleCharacter(MascotCharacter.ela), isTrue);
    expect(VoiceSpeechService.isFemaleCharacter(MascotCharacter.mirnav), isTrue);
    expect(VoiceSpeechService.isFemaleCharacter(MascotCharacter.puki), isTrue);
    expect(VoiceSpeechService.isFemaleCharacter(MascotCharacter.termoBot), isFalse);
    expect(VoiceSpeechService.isFemaleCharacter(MascotCharacter.mert), isFalse);

    expect(
      VoiceSpeechService.formatForSpeech('Hedef 20.0°C, oda 21.8°C.', lang: LangCode.tr),
      'Hedef 20 derece, oda 21.8 derece.',
    );

    expect(VoiceGenderClassifier.classify('Google Türkçe'), VoiceGenderHint.female);
    expect(
      VoiceGenderClassifier.classify('Microsoft Emel Online (Natural) - Turkish (Turkey)'),
      VoiceGenderHint.female,
    );
    expect(
      VoiceGenderClassifier.classify('Microsoft Tolga - Turkish (Turkey)'),
      VoiceGenderHint.male,
    );
    expect(
      VoiceGenderClassifier.classify('Microsoft Ahmet Online (Natural) - Turkish (Turkey)'),
      VoiceGenderHint.male,
    );
    // Word-boundary check: 'female' / 'samantha' must NOT be blocked by 'male' / 'man'
    expect(VoiceGenderClassifier.classify('Turkish Female'), VoiceGenderHint.female);
    expect(VoiceGenderClassifier.classify('Samantha'), VoiceGenderHint.female);

    // Android Google TTS Turkish IDs
    expect(VoiceGenderClassifier.classify('tr-tr-x-ama-local'), VoiceGenderHint.male);
    expect(VoiceGenderClassifier.classify('tr-tr-x-tmc-network'), VoiceGenderHint.male);
    expect(VoiceGenderClassifier.classify('tr-tr-x-cfs-local'), VoiceGenderHint.female);
    expect(VoiceGenderClassifier.classify('tr-tr-x-efu-local'), VoiceGenderHint.female);
    expect(VoiceGenderClassifier.classify('tr-tr-x-mfm-local'), VoiceGenderHint.female);

    final androidVoices = [
      VoiceOptionInfo(
        name: 'tr-tr-x-ama-local',
        locale: 'tr-TR',
        gender: VoiceGenderClassifier.classify('tr-tr-x-ama-local'),
      ),
      VoiceOptionInfo(
        name: 'tr-tr-x-cfs-local',
        locale: 'tr-TR',
        gender: VoiceGenderClassifier.classify('tr-tr-x-cfs-local'),
      ),
    ];
    final femalePick = VoiceGenderClassifier.pickBestIndex(
      androidVoices,
      lang: LangCode.tr,
      female: true,
    );
    expect(femalePick?.index, 1);
    expect(femalePick?.matchedExpectedGender, isTrue);

    final malePick = VoiceGenderClassifier.pickBestIndex(
      androidVoices,
      lang: LangCode.tr,
      female: false,
    );
    expect(malePick?.index, 0);
    expect(malePick?.matchedExpectedGender, isTrue);

    final onlyTolga = [
      VoiceOptionInfo(
        name: 'Microsoft Tolga - Turkish (Turkey)',
        locale: 'tr-TR',
        gender: VoiceGenderClassifier.classify('Microsoft Tolga - Turkish (Turkey)'),
      ),
    ];
    final tolgaFemaleFallback = VoiceGenderClassifier.pickBestIndex(
      onlyTolga,
      lang: LangCode.tr,
      female: true,
    );
    expect(tolgaFemaleFallback?.index, 0);
    expect(tolgaFemaleFallback?.matchedExpectedGender, isFalse);
  });

  test('AiCallService detects boiler shutdown, room temp questions, and closing thank-you replies', () {
    final heatingBoiler = ThermostatMath.computeBoilerTelemetry(21.0, 23.0);
    final standbyBoiler = ThermostatMath.computeBoilerTelemetry(21.0, 15.0);
    final safeGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 21.0,
      outsideTemp: 15.0,
      boiler: standbyBoiler,
    );
    final t0 = DateTime(2026, 11, 21, 14, 0, 0);

    final offTrigger = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.onIgnition,
      wasHeating: true,
      nextBoiler: standbyBoiler,
      safety: safeGuard,
      roomTemp: 21.0,
      now: t0,
    );
    expect(offTrigger.shouldCall, isTrue);
    expect(offTrigger.reason, AiCallReason.boilerOff);

    final coldTrigger = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.ignitionAndSafety,
      wasHeating: false,
      nextBoiler: standbyBoiler,
      safety: safeGuard,
      roomTemp: 16.5,
      now: t0,
    );
    expect(coldTrigger.shouldCall, isTrue);
    expect(coldTrigger.reason, AiCallReason.coldRoom);

    final hotTrigger = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.ignitionAndSafety,
      wasHeating: true,
      nextBoiler: heatingBoiler,
      safety: safeGuard,
      roomTemp: 27.0,
      now: t0,
    );
    expect(hotTrigger.shouldCall, isTrue);
    expect(hotTrigger.reason, AiCallReason.hotRoom);

    final closeResp = AiCallService.evaluateCallResponse(
      rawInput: 'kombiyi kapat',
      callReason: AiCallReason.manualTest,
      boiler: heatingBoiler,
      currentTargetTemp: 23.0,
      lang: LangCode.tr,
    );
    expect(closeResp.handled, isTrue);
    expect(closeResp.newTargetTemp, ThermostatMath.minTemp);
    expect(closeResp.replyTr.contains('Teşekkürler'), isTrue);

    final yesOpenResp = AiCallService.evaluateCallResponse(
      rawInput: 'evet',
      callReason: AiCallReason.coldRoom,
      boiler: standbyBoiler,
      currentTargetTemp: 18.0,
      lang: LangCode.tr,
    );
    expect(yesOpenResp.handled, isTrue);
    expect(yesOpenResp.newTargetTemp, 22.5);
    expect(yesOpenResp.replyTr.contains('Teşekkürler'), isTrue);

    final explicitClose = AiCallService.evaluateCallResponse(
      rawInput: 'evet kapat',
      callReason: AiCallReason.coldRoom,
      boiler: heatingBoiler,
      currentTargetTemp: 23.0,
      lang: LangCode.tr,
    );
    expect(explicitClose.handled, isTrue);
    expect(explicitClose.newTargetTemp, ThermostatMath.minTemp);
    expect(explicitClose.replyTr.contains('Teşekkürler'), isTrue);

    final noKeep = AiCallService.evaluateCallResponse(
      rawInput: 'hayır',
      callReason: AiCallReason.hotRoom,
      boiler: heatingBoiler,
      currentTargetTemp: 23.0,
      lang: LangCode.tr,
    );
    expect(noKeep.handled, isTrue);
    expect(noKeep.newTargetTemp, isNull);
    expect(noKeep.replyTr.contains('Teşekkürler'), isTrue);

    // User-initiated boiler ON -> OFF within 10s works without 60s lock
    final userOff = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.ignitionAndSafety,
      wasHeating: true,
      nextBoiler: standbyBoiler,
      safety: safeGuard,
      roomTemp: 21.8,
      targetTemp: 18.0,
      prevTargetTemp: 24.0,
      isUserChange: true,
      lastCallAt: t0.subtract(const Duration(seconds: 10)),
      now: t0,
    );
    expect(userOff.shouldCall, isTrue);
    expect(userOff.reason, AiCallReason.boilerOff);

    // Cranking target temp to MAX (29.0C) triggers urgent high-heat warning
    final maxBoiler = ThermostatMath.computeBoilerTelemetry(21.8, 29.0);
    final maxPush = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.ignitionAndSafety,
      wasHeating: true,
      nextBoiler: maxBoiler,
      safety: safeGuard,
      roomTemp: 21.8,
      targetTemp: 29.0,
      prevTargetTemp: 24.0,
      isUserChange: true,
      lastCallAt: t0.subtract(const Duration(seconds: 10)),
      now: t0,
    );
    expect(maxPush.shouldCall, isTrue);
    expect(maxPush.reason, AiCallReason.hotRoom);
    expect(maxPush.urgent, isTrue);

    final lowerResp = AiCallService.evaluateCallResponse(
      rawInput: 'düşür',
      callReason: AiCallReason.hotRoom,
      boiler: maxBoiler,
      currentTargetTemp: 29.0,
      lang: LangCode.tr,
    );
    expect(lowerResp.handled, isTrue);
    expect(lowerResp.newTargetTemp, 22.5);
    expect(lowerResp.replyTr.contains('Teşekkürler'), isTrue);
  });

  test('AiCallLogEntry and AiCallService maintain last 10 calls and suggested actions', () {
    List<AiCallLogEntry> history = const [];
    for (int i = 1; i <= 12; i++) {
      history = AiCallService.appendCallHistory(
        history,
        AiCallLogEntry(
          id: 'call_$i',
          timestamp: '14:${i.toString().padLeft(2, '0')}',
          character: MascotCharacter.ela,
          reason: i % 2 == 0 ? AiCallReason.hotRoom : AiCallReason.boilerOff,
          status: i == 12 ? AiCallStatus.missed : AiCallStatus.answered,
          durationSeconds: i == 12 ? 0 : i * 3,
          summaryTr: AiCallService.buildAlertHeadline(
            i % 2 == 0 ? AiCallReason.hotRoom : AiCallReason.boilerOff,
            roomTemp: 21.8,
            targetTemp: i % 2 == 0 ? 29.0 : 16.0,
            boilerHeating: i % 2 == 0,
            lang: LangCode.tr,
          ),
          summaryEn: 'Summary $i',
          actionTakenTr: i == 12 ? 'Cevapsız bırakıldı' : 'Komut: Kombi kapatıldı',
          actionTakenEn: 'Action $i',
          roomTemp: 21.8,
          targetTemp: i % 2 == 0 ? 29.0 : 16.0,
          boilerHeating: i % 2 == 0,
          urgent: i % 2 == 0,
        ),
        maxEntries: 10,
      );
    }

    // Keeps at most 10 entries, newest first
    expect(history.length, 10);
    expect(history.first.id, 'call_12');
    expect(history.last.id, 'call_3');

    // JSON round-trip via SystemSettingsState
    final settings = SystemSettingsState.defaults().copyWith(aiCallHistory: history);
    final restored = SystemSettingsState.fromJson(settings.toJson());
    expect(restored.aiCallHistory.length, 10);
    expect(restored.aiCallHistory.first.status, AiCallStatus.missed);
    expect(restored.aiCallHistory.first.character, MascotCharacter.ela);
    expect(restored.aiCallHistory.first.summaryTr.contains('maksimum'), isTrue);

    // Suggested actions for high-target missed call include lower to 22.5, Eco, and turn off
    final actions = AiCallService.suggestedActionsForEntry(restored.aiCallHistory.first);
    expect(actions.length, 3);
    expect(actions.first.targetTemp, 22.5);
    expect(actions.last.targetTemp, ThermostatMath.minTemp);

    // Updating recorded action from top notification banner updates matching entry
    final updated = AiCallService.updateCallHistoryAction(
      restored.aiCallHistory,
      'call_12',
      actionTr: actions.last.logActionTr,
      actionEn: actions.last.logActionEn,
    );
    expect(updated.first.actionTakenTr, 'Bildirimden: Kombi kapatıldı');
  });

  test('EspLogEntry and EspLogService persist hardware logs, filter categories, and export reports', () {
    List<EspLogEntry> logs = const [];
    for (int i = 1; i <= 45; i++) {
      logs = EspLogService.appendLog(
        logs,
        EspLogEntry(
          timestamp: '12:${(i % 60).toString().padLeft(2, '0')}',
          event: i % 5 == 0 ? 'WDT Kontrolü #$i' : 'Brülör Döngüsü #$i',
          detail: 'Detay $i',
          isWarning: i % 5 == 0,
          category: i % 5 == 0
              ? EspLogCategory.watchdog
              : (i % 3 == 0 ? EspLogCategory.sync : EspLogCategory.burner),
          durationSeconds: i % 5 == 0 ? 0 : 900,
        ),
        maxEntries: 40,
      );
    }

    expect(logs.length, 40);
    expect(logs.first.event, 'WDT Kontrolü #45');
    expect(EspLogService.filterLogs(logs, category: EspLogCategory.watchdog).length, 8);
    expect(EspLogService.countWatchdogEvents(logs), 8);
    expect(EspLogService.formatDurationBadge(45, LangCode.tr), '45 sn');
    expect(EspLogService.formatDurationBadge(900, LangCode.tr), '15 dk');
    expect(EspLogService.formatDurationBadge(3900, LangCode.tr), '1 sa 5 dk');

    final settings = SystemSettingsState.defaults().copyWith(
      espDeviceId: 'ESP32-TEST-99',
      espOnline: true,
      espWdtEnabled: false,
      espOfflineBufferEnabled: true,
      espLastPingAt: '14:05',
      espWdtResetCount: 4,
      espOfflineBurnMinutes: 120,
      espLogs: logs,
    );
    final restored = SystemSettingsState.fromJson(settings.toJson());
    expect(restored.espDeviceId, 'ESP32-TEST-99');
    expect(restored.espOnline, isTrue);
    expect(restored.espWdtEnabled, isFalse);
    expect(restored.espOfflineBufferEnabled, isTrue);
    expect(restored.espLastPingAt, '14:05');
    expect(restored.espWdtResetCount, 4);
    expect(restored.espOfflineBurnMinutes, 120);
    expect(restored.espLogs.length, 40);
    expect(restored.espLogs.first.category, EspLogCategory.watchdog);
    expect(restored.espLogs.first.isWarning, isTrue);

    final boiler = ThermostatMath.computeBoilerTelemetry(21.8, 22.5);
    final report = EspLogService.exportLogsReport(
      settings: restored,
      roomTemp: 21.8,
      targetTemp: 22.5,
      boiler: boiler,
      lang: LangCode.tr,
    );
    expect(report.contains('ESP32-TEST-99'), isTrue);
    expect(report.contains('Çevrimiçi (14:05)'), isTrue);
    expect(report.contains('120 dk yanma'), isTrue);
    expect(report.contains('WDT Kontrolü #45'), isTrue);
    expect(report.contains('| --'), isTrue);
    expect(report.contains('1.6 Bar'), isFalse);

    final connectedReport = EspLogService.exportLogsReport(
      settings: restored,
      roomTemp: 21.8,
      targetTemp: 22.5,
      boiler: boiler,
      sensors: const BoilerHardwareSensors(isConnected: true, waterPressureBar: 1.7),
      lang: LangCode.tr,
    );
    expect(connectedReport.contains('1.7 Bar'), isTrue);
  });

  test('FirebaseSyncService validates URLs, sanitizes node paths, builds command-only JSON, and parses bidirectional pull telemetry', () {
    expect(FirebaseSyncService.sanitizeNodePath(' /kombi.json '), 'kombi');
    expect(FirebaseSyncService.sanitizeNodePath('/ev/salon/'), 'ev/salon');
    expect(FirebaseSyncService.sanitizeNodePath('   '), 'kombi');

    expect(
      SystemSettingsState.defaults().firebaseRtdbUrl,
      'https://kombi-kontrol-babd5-default-rtdb.firebaseio.com',
    );
    expect(FirebaseSyncService.validateRtdbUrl('https://kombi-kontrol-babd5-default-rtdb.firebaseio.com'), isTrue);
    expect(FirebaseSyncService.validateRtdbUrl('ftp://invalid-host'), isFalse);
    expect(FirebaseSyncService.validateRtdbUrl(''), isFalse);
    expect(FirebaseSyncService.isWebApiKey('AIzaSyDummyKeyExample1234567890123456789'), isTrue);
    expect(FirebaseSyncService.isWebApiKey('legacy-db-secret-token'), isFalse);

    final boiler = ThermostatMath.computeBoilerTelemetry(21.8, 22.5);
    final preview = FirebaseSyncService.buildPayloadPreviewJson(
      roomName: 'Salon',
      espDeviceId: 'ESP32-KOMBI-01',
      targetTemp: 22.5,
      boiler: boiler,
      timestamp: DateTime.utc(2026, 11, 22, 12, 0, 0),
    );
    final parsed = jsonDecode(preview) as Map<String, dynamic>;
    expect(parsed.containsKey('roomTemp'), isFalse);
    expect(parsed.containsKey('pressureBar'), isFalse);
    expect(parsed['targetTemp'], 22.5);
    expect(parsed['boilerActive'], isTrue);
    expect(parsed['roomName'], 'Salon');
    expect(parsed['espDeviceId'], 'ESP32-KOMBI-01');

    final pulled = FirebaseSyncService.parsePullResponseBody(
      jsonEncode({
        'targetTemp': 23.0,
        'roomTemp': 21.4,
        'hardwareConnected': true,
        'supplyTemp': 52.3,
        'returnTemp': 44.8,
        'pressureBar': 1.5,
        'pumpRpm': 2100,
        'ionizationUa': 4.1,
      }),
      safeNode: 'kombi',
      statusCode: 200,
      latencyMs: 42,
    );
    expect(pulled.ok, isTrue);
    expect(pulled.remoteTargetTemp, 23.0);
    expect(pulled.remoteRoomTemp, 21.4);
    expect(pulled.remoteSensors?.isConnected, isTrue);
    expect(pulled.remoteSensors?.supplyTempC, 52.3);
    expect(pulled.remoteSensors?.waterPressureBar, 1.5);

    final disconnectedGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 21.4,
      outsideTemp: null,
      boiler: boiler,
      sensors: const BoilerHardwareSensors.disconnected(),
    );
    expect(disconnectedGuard.lowPressure, isFalse);
    expect(disconnectedGuard.freezeRisk, isFalse);

    final settings = SystemSettingsState.defaults().copyWith(
      firebaseApiKey: 'secret-token-123',
      firebaseNodePath: 'ev/kombi',
      cloudSyncEnabled: true,
      cloudSyncIntervalSeconds: 60,
      cloudAutoPullEnabled: true,
      cloudLastSyncAt: '14:32',
      cloudLastSyncOk: true,
      cloudLastSyncMessage: 'RTDB /ev/kombi senkronize edildi',
    );
    final restored = SystemSettingsState.fromJson(settings.toJson());
    expect(restored.firebaseApiKey, 'secret-token-123');
    expect(restored.firebaseNodePath, 'ev/kombi');
    expect(restored.cloudSyncEnabled, isTrue);
    expect(restored.cloudSyncIntervalSeconds, 60);
    expect(restored.cloudAutoPullEnabled, isTrue);
    expect(restored.cloudLastSyncAt, '14:32');
    expect(restored.cloudLastSyncOk, isTrue);
    expect(restored.cloudLastSyncMessage, 'RTDB /ev/kombi senkronize edildi');

    expect(settings.copyWith(cloudSyncIntervalSeconds: 9999).cloudSyncIntervalSeconds, 3600);
    expect(settings.copyWith(cloudSyncIntervalSeconds: -10).cloudSyncIntervalSeconds, 0);
  });

  test('SmartDisplaySlideImage, VisualLayoutMode.stretch, SmartDisplayVisualTheme, and city helper round-trip cleanly', () {
    final sampleImg = SmartDisplaySlideImage(
      id: 'img_1',
      name: 'sunset_beach.png',
      dataBase64: base64Encode([137, 80, 78, 71, 13, 10, 26, 10]),
      filePath: '',
    );
    final singleImg = SmartDisplaySlideImage(
      id: 'img_single',
      name: 'living_room.png',
      dataBase64: base64Encode([1, 2, 3, 4]),
    );

    final settings = SystemSettingsState.defaults().copyWith(
      smartDisplayMode: SmartDisplayMode.slideshow,
      smartDisplayLayout: VisualLayoutMode.stretch,
      smartDisplayVisualTheme: SmartDisplayVisualTheme.aurora,
      ambientSoundtrack: AmbientSoundtrack.relaxPiano,
      slideImages: [sampleImg],
      singleDisplayImage: singleImg,
    );

    final restored = SystemSettingsState.fromJson(settings.toJson());
    expect(restored.smartDisplayLayout, VisualLayoutMode.stretch);
    expect(restored.smartDisplayVisualTheme, SmartDisplayVisualTheme.aurora);
    expect(restored.ambientSoundtrack, AmbientSoundtrack.relaxPiano);
    expect(restored.slideImages.length, 1);
    expect(restored.slideImages.first.name, 'sunset_beach.png');
    expect(restored.slideImages.first.decodeBytes(), [137, 80, 78, 71, 13, 10, 26, 10]);
    expect(restored.singleDisplayImage?.id, 'img_single');
    expect(restored.singleDisplayImage?.decodeBytes(), [1, 2, 3, 4]);

    final cleared = restored.copyWith(clearSingleDisplayImage: true);
    expect(cleared.singleDisplayImage, isNull);

    final silentSettings = restored.copyWith(ambientSoundtrack: AmbientSoundtrack.silent);
    expect(silentSettings.ambientTrackTitle(LangCode.tr).contains('Sessiz'), isTrue);
    expect(restored.ambientTrackTitle(LangCode.tr).contains('Piyano'), isTrue);
    expect(SystemSettingsState.defaults().ambientSoundtrack, AmbientSoundtrack.silent);

    expect(SystemSettingsState.extractCityName('Ev · İstanbul'), 'İstanbul');
    expect(SystemSettingsState.extractCityName('Ev (Kadıköy)'), 'Kadıköy');
    expect(SystemSettingsState.extractCityName('Yazlık · İzmir'), 'İzmir');
    expect(SystemSettingsState.extractCityName('Ankara'), 'Ankara');
  });

  test('Smart Display static theme asset path is empty, singlePhoto migrates, and Smart Display vs Maskot mutual exclusion holds', () {
    expect(smartDisplayThemeAssetPath(SmartDisplayVisualTheme.fireplace), isEmpty);
    expect(smartDisplayThemeAssetPath(SmartDisplayVisualTheme.rainy), isEmpty);
    expect(smartDisplayThemeAssetPath(SmartDisplayVisualTheme.winterSnow), isEmpty);
    expect(smartDisplayThemeAssetPath(SmartDisplayVisualTheme.sunset), isEmpty);
    expect(smartDisplayThemeAssetPath(SmartDisplayVisualTheme.aurora), isEmpty);
    expect(smartDisplayThemeAssetPath(SmartDisplayVisualTheme.minimalist), isEmpty);

    // Legacy singlePhoto + singleDisplayImage cleanly migrate to slideshow + slideImages,
    // and simultaneous smartDisplayEnabled + termoBotEnabled resolves in favor of Maskot
    final legacyMap = SystemSettingsState.defaults().toJson();
    legacyMap['smartDisplayEnabled'] = true;
    legacyMap['termoBotEnabled'] = true;
    legacyMap['smartDisplayMode'] = 'singlePhoto';
    legacyMap['slideImages'] = [];
    legacyMap['singleDisplayImage'] = SmartDisplaySlideImage(
      id: 'legacy_1',
      name: 'legacy_wall.png',
      dataBase64: base64Encode([9, 8, 7, 6]),
    ).toJson();

    final migrated = SystemSettingsState.fromJson(legacyMap);
    expect(migrated.smartDisplayMode, SmartDisplayMode.slideshow);
    expect(migrated.slideImages.length, 1);
    expect(migrated.slideImages.first.id, 'legacy_1');
    expect(migrated.termoBotEnabled, isTrue);
    expect(migrated.smartDisplayEnabled, isFalse);
  });

  test('Wikimedia .webm theme videos, adjustable smartDisplayBlur, and tempo-locked AudioTempoAnalyzer work cleanly', () {
    expect(
      smartDisplayThemeVideoUrl(SmartDisplayVisualTheme.fireplace),
      'https://upload.wikimedia.org/wikipedia/commons/transcoded/0/04/Fireplace_1_2021-02-14.webm/Fireplace_1_2021-02-14.webm.480p.vp9.webm',
    );
    expect(
      smartDisplayThemeVideoUrl(SmartDisplayVisualTheme.rainy),
      'https://upload.wikimedia.org/wikipedia/commons/transcoded/2/2e/Radevormwald_-_Raindrops_on_a_window_10_%281%29_ies.webm/Radevormwald_-_Raindrops_on_a_window_10_%281%29_ies.webm.480p.vp9.webm',
    );
    expect(
      smartDisplayThemeVideoUrl(SmartDisplayVisualTheme.winterSnow),
      'https://upload.wikimedia.org/wikipedia/commons/transcoded/f/f3/Snow_falling_in_Tuntorp.webm/Snow_falling_in_Tuntorp.webm.480p.vp9.webm',
    );
    expect(
      smartDisplayThemeVideoUrl(SmartDisplayVisualTheme.sunset),
      'https://upload.wikimedia.org/wikipedia/commons/transcoded/e/e5/Sunset_timelapse_in_Funchal_-_2014.webm/Sunset_timelapse_in_Funchal_-_2014.webm.480p.vp9.webm',
    );
    expect(
      smartDisplayThemeVideoUrl(SmartDisplayVisualTheme.aurora),
      'https://upload.wikimedia.org/wikipedia/commons/transcoded/d/df/Aurora_borealis_timelapse.webm/Aurora_borealis_timelapse.webm.480p.vp9.webm',
    );
    expect(
      smartDisplayThemeVideoUrl(SmartDisplayVisualTheme.minimalist),
      'https://upload.wikimedia.org/wikipedia/commons/transcoded/7/72/Waves_off_of_Hurricane_Point_Vista_Point%2C_Big_Sur.webm/Waves_off_of_Hurricane_Point_Vista_Point%2C_Big_Sur.webm.480p.vp9.webm',
    );

    final withBlur = SystemSettingsState.defaults().copyWith(smartDisplayBlur: 12.0);
    final restoredBlur = SystemSettingsState.fromJson(withBlur.toJson());
    expect(restoredBlur.smartDisplayBlur, 12.0);
    expect(withBlur.copyWith(smartDisplayBlur: -5.0).smartDisplayBlur, 0.0);
    expect(withBlur.copyWith(smartDisplayBlur: 99.0).smartDisplayBlur, 24.0);

    // Real WAV DSP extraction: piano & lofi loops produce valid 18-band tempo frames
    final pianoWav = AmbientAudioService.generateAmbientWavBytes(AmbientSoundtrack.relaxPiano);
    final profile = AudioTempoAnalyzer.analyzeWavBytes(pianoWav);
    expect(profile, isNotNull);
    expect(profile!.fromRealAudioPcm, isTrue);
    expect(profile.bandCount, 18);
    expect(profile.bpm, inInclusiveRange(55.0, 175.0));
    expect(profile.frames.length, greaterThanOrEqualTo(60));

    // At note transient (~60ms into beat) energy exceeds late decay (~450ms)
    final attackBands = AudioTempoAnalyzer.sampleBandsAtPosition(
      profile,
      const Duration(milliseconds: 60),
      playing: true,
    );
    final decayBands = AudioTempoAnalyzer.sampleBandsAtPosition(
      profile,
      const Duration(milliseconds: 450),
      playing: true,
    );
    final attackSum = attackBands.fold<double>(0.0, (a, b) => a + b);
    final decaySum = decayBands.fold<double>(0.0, (a, b) => a + b);
    expect(attackSum, greaterThan(decaySum));

    // Per-band percentile normalization preserves frequency contrast across bands
    double maxAttack = 0.0;
    double minAttack = 1.0;
    for (final v in attackBands) {
      if (v > maxAttack) maxAttack = v;
      if (v < minAttack) minAttack = v;
    }
    expect(maxAttack - minAttack, greaterThan(0.25));

    // When paused/muted, all equalizer bands & beat pulse drop cleanly to zero
    final pausedBands = AudioTempoAnalyzer.sampleBandsAtPosition(
      profile,
      const Duration(milliseconds: 60),
      playing: false,
    );
    expect(pausedBands.every((v) => v == 0.0), isTrue);
    expect(
      AudioTempoAnalyzer.beatPulseAtPosition(
        profile,
        const Duration(milliseconds: 60),
        playing: false,
      ),
      0.0,
    );
  });

  test('SmartDisplayOverlay.computeGentleBurnInShift shifts <= 2px cleanly on 12-min boundaries', () {
    expect(
      SmartDisplayOverlay.computeGentleBurnInShift(DateTime(2026, 11, 23, 18, 10), enabled: false),
      Offset.zero,
    );
    final w0a = SmartDisplayOverlay.computeGentleBurnInShift(DateTime(2026, 11, 23, 0, 0), enabled: true);
    final w0b = SmartDisplayOverlay.computeGentleBurnInShift(DateTime(2026, 11, 23, 0, 11, 59), enabled: true);
    final w1 = SmartDisplayOverlay.computeGentleBurnInShift(DateTime(2026, 11, 23, 0, 12, 0), enabled: true);
    final w2 = SmartDisplayOverlay.computeGentleBurnInShift(DateTime(2026, 11, 23, 0, 24, 0), enabled: true);

    expect(w0a, w0b); // No 1-second micro jitter inside the same 12-minute window
    expect(w0a, isNot(w1));
    expect(w1, isNot(w2));
    for (final o in [w0a, w1, w2]) {
      expect(o.dx.abs(), lessThanOrEqualTo(2.0));
      expect(o.dy.abs(), lessThanOrEqualTo(2.0));
    }
  });

  test('AmbientAudioService.stepPlaylistTrack wraps sequentially and avoids current track in shuffle', () {
    expect(
      AmbientAudioService.stepPlaylistTrack(
        AmbientSoundtrack.fireplaceCrackling,
        1,
      ),
      AmbientSoundtrack.nightRain,
    );
    expect(
      AmbientAudioService.stepPlaylistTrack(
        AmbientSoundtrack.fireplaceCrackling,
        -1,
        hasCustomAudio: false,
      ),
      AmbientSoundtrack.forestBreeze,
    );
    expect(
      AmbientAudioService.stepPlaylistTrack(
        AmbientSoundtrack.fireplaceCrackling,
        -1,
        hasCustomAudio: true,
      ),
      AmbientSoundtrack.customMp3,
    );
    final shuffled = AmbientAudioService.stepPlaylistTrack(
      AmbientSoundtrack.relaxPiano,
      1,
      hasCustomAudio: true,
      shuffle: true,
    );
    expect(shuffled, isNot(AmbientSoundtrack.silent));
    expect(shuffled, isNot(AmbientSoundtrack.relaxPiano));
  });

  test('ThermostatMath circular tab wrapping loops infinitely across Termo and Prog', () {
    expect(ThermostatMath.wrapRealIndex(4000, 4), 0);
    expect(ThermostatMath.wrapRealIndex(4001, 4), 1);
    expect(ThermostatMath.wrapRealIndex(4003, 4), 3);
    expect(ThermostatMath.wrapRealIndex(4004, 4), 0);
    expect(ThermostatMath.wrapRealIndex(3999, 4), 3);
    expect(ThermostatMath.wrapRealIndex(-1, 4), 3);

    // Nearest virtual target wraps smoothly across 3 <-> 0 boundary
    expect(
      ThermostatMath.nearestCircularVirtualIndex(
        currentVirtualIndex: 4003,
        targetRealIndex: 0,
        length: 4,
      ),
      4004,
    );
    expect(
      ThermostatMath.nearestCircularVirtualIndex(
        currentVirtualIndex: 4000,
        targetRealIndex: 3,
        length: 4,
      ),
      3999,
    );
  });

  test('MediaStorageService keys persist cleanly and strip heavy base64 when persisted by key', () {
    expect(MediaStorageService.isPersistedKey(MediaStorageService.customVideoKey), isTrue);
    expect(MediaStorageService.isPersistedKey(MediaStorageService.customAudioKey), isTrue);
    expect(MediaStorageService.isPersistedKey(MediaStorageService.screensaverBgKey), isTrue);
    expect(MediaStorageService.isPersistedKey(MediaStorageService.slideImageKey('abc')), isTrue);
    expect(MediaStorageService.isPersistedKey('https://example.com/clip.mp4'), isFalse);

    final persistedSlide = SmartDisplaySlideImage(
      id: 's1',
      name: 'photo.jpg',
      dataBase64: 'AAAA',
      filePath: MediaStorageService.slideImageKey('s1'),
    );
    final json = persistedSlide.toJson();
    expect(json['filePath'], MediaStorageService.slideImageKey('s1'));
    expect(json['dataBase64'], '');

    // Verify DailyWeatherForecast replaces umbrella icon with water_drop_outlined
    final rainyToday = DailyWeatherForecast.sample5Days.first;
    expect(rainyToday.icon, Icons.water_drop_outlined);
    expect(rainyToday.icon, isNot(Icons.umbrella_outlined));
    for (final d in DailyWeatherForecast.sample5Days) {
      for (final h in d.hourly) {
        expect(h.icon, isNot(Icons.umbrella_outlined));
      }
    }
  });

  test('CustomScheduleRule & ScheduleEngine execute default slots and independent Open/Close/Both plans', () {
    final baseRule = CustomScheduleRule(
      id: 'rule_open_only',
      title: 'Sabah Isıt',
      actionType: ScheduleActionType.openOnly,
      openTime: '07:15',
      openTargetTemp: 23.5,
      repeatMode: ScheduleRepeatMode.specificDate,
      specificDateIso: '2026-11-24',
    );
    final restoredRule = CustomScheduleRule.fromJson(baseRule.toJson());
    expect(restoredRule.id, 'rule_open_only');
    expect(restoredRule.actionType, ScheduleActionType.openOnly);
    expect(restoredRule.hasOpenAction, isTrue);
    expect(restoredRule.hasCloseAction, isFalse);
    expect(restoredRule.openTargetTemp, 23.5);
    expect(restoredRule.specificDateIso, '2026-11-24');

    // Default morning slot triggers at 06:30
    final defaultEval = ScheduleEngine.evaluateAtMinute(
      now: DateTime(2026, 11, 24, 6, 30),
      slots: ThermostatMath.defaultSchedule,
      customRules: const [],
    );
    expect(defaultEval.hasTriggered, isTrue);
    expect(defaultEval.nextTargetTemp, 23.0);
    expect(defaultEval.isCloseAction, isFalse);

    // Independent Open Only triggers on specific date and marks itself complete
    final openOnlyEval = ScheduleEngine.evaluateAtMinute(
      now: DateTime(2026, 11, 24, 7, 15),
      slots: ThermostatMath.defaultSchedule,
      customRules: [restoredRule],
    );
    expect(openOnlyEval.hasTriggered, isTrue);
    expect(openOnlyEval.nextTargetTemp, 23.5);
    expect(openOnlyEval.isCloseAction, isFalse);
    expect(openOnlyEval.completedOnceRuleIds, contains('rule_open_only'));

    // Independent Close Only on custom days (Tue/Thu) triggers standby minTemp
    final closeOnlyRule = CustomScheduleRule(
      id: 'rule_close_only',
      title: 'İş Çıkışı Kapat',
      actionType: ScheduleActionType.closeOnly,
      closeTime: '09:00',
      repeatMode: ScheduleRepeatMode.customDays,
      specificDateIso: '2026-11-24',
      repeatWeekdays: const [2, 4], // Tue, Thu
    );
    expect(closeOnlyRule.hasOpenAction, isFalse);
    expect(closeOnlyRule.hasCloseAction, isTrue);

    // Tuesday 2026-11-24 09:00 matches
    final closeTue = ScheduleEngine.evaluateAtMinute(
      now: DateTime(2026, 11, 24, 9, 0),
      slots: const [],
      customRules: [closeOnlyRule],
    );
    expect(closeTue.hasTriggered, isTrue);
    expect(closeTue.nextTargetTemp, ThermostatMath.minTemp);
    expect(closeTue.isCloseAction, isTrue);
    expect(closeTue.completedOnceRuleIds, isEmpty); // periodic stays enabled

    // Wednesday 2026-11-25 09:00 does NOT match
    final closeWed = ScheduleEngine.evaluateAtMinute(
      now: DateTime(2026, 11, 25, 9, 0),
      slots: const [],
      customRules: [closeOnlyRule],
    );
    expect(closeWed.hasTriggered, isFalse);

    // Overnight Open & Close (22:30 -> 06:45 next morning) on specificDate
    final overnightRule = CustomScheduleRule(
      id: 'rule_overnight',
      title: 'Gece Konfor',
      actionType: ScheduleActionType.openAndClose,
      openTime: '22:30',
      openTargetTemp: 21.5,
      closeTime: '06:45',
      repeatMode: ScheduleRepeatMode.specificDate,
      specificDateIso: '2026-11-24',
    );
    final nightOpen = ScheduleEngine.evaluateAtMinute(
      now: DateTime(2026, 11, 24, 22, 30),
      slots: const [],
      customRules: [overnightRule],
    );
    expect(nightOpen.nextTargetTemp, 21.5);
    expect(nightOpen.completedOnceRuleIds, isEmpty);

    final nextMorningClose = ScheduleEngine.evaluateAtMinute(
      now: DateTime(2026, 11, 25, 6, 45),
      slots: const [],
      customRules: [overnightRule],
    );
    expect(nextMorningClose.nextTargetTemp, ThermostatMath.minTemp);
    expect(nextMorningClose.isCloseAction, isTrue);
    expect(nextMorningClose.completedOnceRuleIds, contains('rule_overnight'));
  });

  test('SystemSettingsState.boilerEventNotificationsEnabled & evaluateBoilerEventNotification work independently of AI calls', () {
    final s = SystemSettingsState.defaults().copyWith(
      aiPhoneCallEnabled: false,
      boilerEventNotificationsEnabled: true,
    );
    final restored = SystemSettingsState.fromJson(s.toJson());
    expect(restored.aiPhoneCallEnabled, isFalse);
    expect(restored.boilerEventNotificationsEnabled, isTrue);

    final heating = ThermostatMath.computeBoilerTelemetry(21.0, 23.0);
    final lowered = ThermostatMath.computeBoilerTelemetry(21.0, 21.5);
    final standby = ThermostatMath.computeBoilerTelemetry(21.0, 10.0);
    final maxBoiler = ThermostatMath.computeBoilerTelemetry(21.0, 29.0);
    final safeGuard = NotificationService.evaluateSafetyThresholds(
      roomTemp: 21.0,
      outsideTemp: 15.0,
      boiler: heating,
    );

    final evOn = AiCallService.evaluateBoilerEventNotification(
      enabled: restored.boilerEventNotificationsEnabled,
      wasHeating: false,
      nextBoiler: heating,
      safety: safeGuard,
      locationName: 'Ev · İstanbul',
      roomTemp: 21.0,
      targetTemp: 23.0,
      prevTargetTemp: 18.0,
      isUserChange: true,
    );
    expect(evOn.shouldNotify, isTrue);
    expect(evOn.kind, BoilerEventAlertKind.ignition);
    expect(evOn.titleTr, contains('Açıldı'));

    final evLower = AiCallService.evaluateBoilerEventNotification(
      enabled: restored.boilerEventNotificationsEnabled,
      wasHeating: true,
      nextBoiler: lowered,
      safety: safeGuard,
      locationName: 'Ev · İstanbul',
      roomTemp: 21.0,
      targetTemp: 21.5,
      prevTargetTemp: 24.0,
      isUserChange: true,
    );
    expect(evLower.shouldNotify, isTrue);
    expect(evLower.kind, BoilerEventAlertKind.boilerLowered);
    expect(evLower.titleTr, contains('Kısıldı'));

    final evOff = AiCallService.evaluateBoilerEventNotification(
      enabled: restored.boilerEventNotificationsEnabled,
      wasHeating: true,
      nextBoiler: standby,
      safety: safeGuard,
      locationName: 'Ev · İstanbul',
      roomTemp: 21.0,
      targetTemp: 10.0,
      prevTargetTemp: 23.0,
      isUserChange: true,
    );
    expect(evOff.shouldNotify, isTrue);
    expect(evOff.kind, BoilerEventAlertKind.boilerOff);
    expect(evOff.titleTr, contains('Kapandı'));

    final evMax = AiCallService.evaluateBoilerEventNotification(
      enabled: restored.boilerEventNotificationsEnabled,
      wasHeating: true,
      nextBoiler: maxBoiler,
      safety: safeGuard,
      locationName: 'Ev · İstanbul',
      roomTemp: 21.0,
      targetTemp: 29.0,
      prevTargetTemp: 23.0,
      isUserChange: true,
    );
    expect(evMax.shouldNotify, isTrue);
    expect(evMax.kind, BoilerEventAlertKind.highTarget);
    expect(evMax.titleTr, contains('En Yüksekte'));

    final evCold = AiCallService.evaluateBoilerEventNotification(
      enabled: restored.boilerEventNotificationsEnabled,
      wasHeating: false,
      nextBoiler: standby,
      safety: safeGuard,
      locationName: 'Ev · İstanbul',
      roomTemp: 16.5,
      targetTemp: 15.0,
      isUserChange: false,
    );
    expect(evCold.shouldNotify, isTrue);
    expect(evCold.kind, BoilerEventAlertKind.coldRoom);
    expect(evCold.titleTr, contains('Düşük'));

    final evDisabled = AiCallService.evaluateBoilerEventNotification(
      enabled: false,
      wasHeating: false,
      nextBoiler: heating,
      safety: safeGuard,
      locationName: 'Ev · İstanbul',
      roomTemp: 21.0,
      targetTemp: 23.0,
      isUserChange: true,
    );
    expect(evDisabled.shouldNotify, isFalse);

    // Interactive assistant-question phrasing & schedule provenance
    expect(evOn.bodyTr, contains('mı?'));
    expect(evLower.bodyTr, contains('mı?'));
    expect(evOff.bodyTr, contains('mı?'));
    expect(evMax.bodyTr, contains('mı?'));
    expect(evCold.bodyTr, contains('mı?'));

    final evSched = AiCallService.evaluateBoilerEventNotification(
      enabled: true,
      wasHeating: false,
      nextBoiler: heating,
      safety: safeGuard,
      locationName: 'Ev · İstanbul',
      roomTemp: 21.0,
      targetTemp: 23.0,
      prevTargetTemp: 18.0,
      isUserChange: true,
      scheduleTitleTr: 'Sabah Modu (06:30)',
      scheduleTitleEn: 'Morning Mode (06:30)',
    );
    expect(evSched.shouldNotify, isTrue);
    expect(evSched.scheduleInfoTr, contains('Sabah Modu (06:30)'));
    expect(evSched.bodyTr, contains('Takvim ayarına (Sabah Modu (06:30)) göre'));
    expect(evSched.bodyTr, contains('mı?'));

    final schedEntry = evSched.toAlertEntry(
      id: 'sched_alert_1',
      character: MascotCharacter.ela,
      roomTemp: 21.0,
      targetTemp: 23.0,
      boilerHeating: true,
      timestamp: '06:30',
    );
    final restoredAlert = AiCallLogEntry.fromJson(schedEntry.toJson());
    expect(restoredAlert.isSystemAlert, isTrue);
    expect(restoredAlert.badgeLabelTr, contains('Takvim'));
    expect(restoredAlert.scheduleInfoTr, contains('Sabah Modu (06:30)'));
    expect(restoredAlert.reason, AiCallReason.ignition);

    // boilerLowered context actions adapt cleanly
    final loweredEntry = evLower.toAlertEntry(
      id: 'lowered_1',
      character: MascotCharacter.ela,
      roomTemp: 21.0,
      targetTemp: 21.5,
      boilerHeating: true,
      timestamp: '15:10',
    );
    expect(loweredEntry.reason, AiCallReason.boilerLowered);
    final loweredActions = AiCallService.suggestedActionsForEntry(loweredEntry);
    expect(loweredActions.length, 3);
    expect(loweredActions.first.targetTemp, 22.5);
    expect(loweredActions.last.targetTemp, ThermostatMath.minTemp);
  });

  testWidgets('TopAlertStack renders stepped pile and expands into Telegram-style capsules opening action dialog', (tester) async {
    final alerts = [
      AiCallLogEntry(
        id: 'a1',
        timestamp: '15:09',
        character: MascotCharacter.ela,
        reason: AiCallReason.hotRoom,
        status: AiCallStatus.missed,
        durationSeconds: 0,
        summaryTr: 'Hedef sıcaklık 30°C ile maksimum seviyeye alındı. Kapatalım mı?',
        summaryEn: 'High temp',
        actionTakenTr: '',
        actionTakenEn: '',
        roomTemp: 20.8,
        targetTemp: 30.0,
        boilerHeating: true,
        urgent: true,
        isSystemAlert: true,
        badgeLabelTr: 'Yüksek Hedef',
        badgeLabelEn: 'High Target',
      ),
      AiCallLogEntry(
        id: 'a2',
        timestamp: '15:05',
        character: MascotCharacter.ela,
        reason: AiCallReason.ignition,
        status: AiCallStatus.missed,
        durationSeconds: 0,
        summaryTr: 'Takvim ayarına (Sabah Modu) göre: Kombi açıldı (23°C). Kısalım mı?',
        summaryEn: 'Schedule on',
        actionTakenTr: '',
        actionTakenEn: '',
        roomTemp: 20.5,
        targetTemp: 23.0,
        boilerHeating: true,
        isSystemAlert: true,
        badgeLabelTr: 'Takvim · Isıtma Aktif',
        badgeLabelEn: 'Schedule · Heating On',
        scheduleInfoTr: 'Takvim ayarına (Sabah Modu) göre işlem yapıldı.',
        scheduleInfoEn: 'Executed per calendar schedule (Morning Mode).',
      ),
    ];

    bool expanded = false;
    AiCallLogEntry? opened;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (context, setState) {
              return Stack(
                children: [
                  Positioned.fill(
                    child: TopAlertStack(
                      alerts: alerts,
                      expanded: expanded,
                      lang: LangCode.tr,
                      onToggleExpand: () => setState(() => expanded = !expanded),
                      onTapAlert: (item) => opened = item,
                      onDismissAlert: (_) {},
                      onDismissAll: () {},
                    ),
                  ),
                ],
              );
            },
          ),
        ),
      ),
    );

    // Collapsed stepped stack shows +1 pill and expandable prompt
    expect(find.text('+1'), findsOneWidget);
    expect(find.textContaining('2 okunmamış mesajı'), findsOneWidget);

    // Tapping stepped stack expands into Telegram-style individual capsules
    await tester.tap(find.text('+1'));
    await tester.pumpAndSettle();

    expect(find.text('Okunmamış Mesajlar (2)'), findsOneWidget);
    expect(find.textContaining('Takvim ayarına (Sabah Modu)'), findsOneWidget);

    // Tapping second capsule selects that specific entry
    await tester.tap(find.text('Takvim · Isıtma Aktif'));
    await tester.pump();
    expect(opened?.id, 'a2');
  });

  test('VisualCustomizationState.buttonTactileFeedback defaults true and round-trips false', () {
    final defaults = VisualCustomizationState.defaults();
    expect(defaults.buttonTactileFeedback, isTrue);

    final disabled = defaults.copyWith(buttonTactileFeedback: false);
    final restored = VisualCustomizationState.fromJson(disabled.toJson());
    expect(restored.buttonTactileFeedback, isFalse);

    final reenabled = restored.copyWith(buttonTactileFeedback: true);
    expect(VisualCustomizationState.fromJson(reenabled.toJson()).buttonTactileFeedback, isTrue);
  });

  testWidgets('TactilePress swells on hover, depresses on press, springs back, and respects TactileMotionScope toggle', (tester) async {
    TactileMotionScope.globalEnabled.value = true;
    addTearDown(() => TactileMotionScope.globalEnabled.value = true);

    double currentScale() {
      final transforms = tester.widgetList<Transform>(
        find.descendant(
          of: find.byType(TactilePress),
          matching: find.byType(Transform),
        ),
      );
      for (final t in transforms) {
        final sx = t.transform.getMaxScaleOnAxis();
        if ((sx - 1.0).abs() > 0.0001) return sx;
      }
      return 1.0;
    }

    int taps = 0;
    TactileMotionScope.activeFocus.value = null;
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TactileMotionScope(
          notifier: TactileMotionScope.globalEnabled,
          child: TactileFocusBlurHost(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: Scaffold(
          body: Center(
            child: TactilePress(
              child: ElevatedButton(
                onPressed: () => taps++,
                child: const Text('Test Butonu'),
              ),
            ),
          ),
        ),
      ),
    );

    expect(currentScale(), 1.0);

    // Hover swell (> 1.0) without triggering surrounding focus blur
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.text('Test Butonu')));
    await tester.pumpAndSettle();
    expect(currentScale(), greaterThan(1.0));
    expect(TactileMotionScope.activeFocus.value, isNull);
    expect(find.byType(BackdropFilter), findsNothing);

    // Press-in (< 1.0) without triggering surrounding focus blur
    final pointer = await tester.startGesture(tester.getCenter(find.text('Test Butonu')));
    await tester.pump(const Duration(milliseconds: 90));
    expect(currentScale(), lessThan(1.0));
    expect(TactileMotionScope.activeFocus.value, isNull);
    expect(find.byType(BackdropFilter), findsNothing);

    // Release triggers button tap & settles cleanly back to hover scale
    await pointer.up();
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(currentScale(), greaterThan(1.0));

    // Disabling TactileMotionScope stops transform scaling immediately
    TactileMotionScope.globalEnabled.value = false;
    await tester.pumpAndSettle();
    expect(currentScale(), 1.0);
  });

  testWidgets('RotaryDial enforces circular tick-tip touch/wheel boundary, adjusts temp via mouse wheel, and triggers tactile focus blur', (tester) async {
    TactileMotionScope.globalEnabled.value = true;
    TactileMotionScope.activeFocus.value = null;
    addTearDown(() {
      TactileMotionScope.globalEnabled.value = true;
      TactileMotionScope.activeFocus.value = null;
    });

    double targetTemp = 22.5;
    int outerWheelCount = 0;
    const dialSize = 220.0;
    final outerTickRadius = RotaryDial.outerTickRadiusForSize(dialSize);
    final palette = VisualCustomizationState.defaults().resolvePalette();
    final boiler = ThermostatMath.computeBoilerTelemetry(21.0, 22.5);
    final pageController = PageController();
    addTearDown(pageController.dispose);

    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => TactileMotionScope(
          notifier: TactileMotionScope.globalEnabled,
          child: TactileFocusBlurHost(
            child: child ?? const SizedBox.shrink(),
          ),
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.only(top: 40),
            child: Listener(
              behavior: HitTestBehavior.translucent,
              onPointerSignal: (event) {
                if (event is PointerScrollEvent &&
                    !TactileMotionScope.wasScrollEventConsumed(event)) {
                  outerWheelCount++;
                }
              },
              child: PageView(
                controller: pageController,
                children: [
                  StatefulBuilder(
                    builder: (context, setState) {
                      return Center(
                        child: Transform.translate(
                          offset: const Offset(12, 24),
                          child: RotaryDial(
                            targetTemp: targetTemp,
                            onChangeTarget: (next) =>
                                setState(() => targetTemp = next),
                            modeName: 'KONFOR MODU',
                            accentColor: const Color(0xFFFF7A24),
                            boiler: boiler,
                            lang: LangCode.tr,
                            palette: palette,
                            sizePx: dialSize,
                          ),
                        ),
                      );
                    },
                  ),
                  const Center(child: Text('Second Page')),
                ],
              ),
            ),
          ),
        ),
      ),
    );

    final dialBoxRect = tester.getRect(find.byType(RotaryDial));
    // Center of the SizedBox(dialSize, dialSize) at the top of RotaryDial's Column
    final dialCenter = Offset(
      dialBoxRect.center.dx,
      dialBoxRect.top + dialSize / 2.0,
    );

    // 1. Touch inside outer tick tips (tick tip radius - 3px) updates targetTemp and activates circular focus blur
    final insideTickPoint = dialCenter + Offset(outerTickRadius - 3.0, 0.0);
    final insideTouch = await tester.startGesture(insideTickPoint);
    await tester.pump(const Duration(milliseconds: 120));
    expect(targetTemp, isNot(22.5));
    expect(TactileMotionScope.activeFocus.value, isNotNull);
    expect(TactileMotionScope.activeFocus.value!.isCircle, isTrue);
    expect(find.byType(BackdropFilter), findsOneWidget);

    await insideTouch.up();
    await tester.pumpAndSettle();
    expect(TactileMotionScope.activeFocus.value, isNull);
    expect(find.byType(BackdropFilter), findsNothing);

    // Reset temperature baseline
    final prevTemp = targetTemp;

    // 2. Touch inside the square corner OUTSIDE outerTickRadius does NOT hit RotaryDial
    final cornerOutsideTick =
        dialCenter + Offset(dialSize * 0.48, -dialSize * 0.48);
    expect(
      (cornerOutsideTick - dialCenter).distance,
      greaterThan(outerTickRadius),
    );
    final outsideTouch = await tester.startGesture(cornerOutsideTick);
    await tester.pump(const Duration(milliseconds: 80));
    expect(targetTemp, prevTemp);
    expect(TactileMotionScope.activeFocus.value, isNull);
    await outsideTouch.up();
    await tester.pumpAndSettle();

    // 3. Hovering cursor inside the dial circle activates surrounding focus blur,
    //    and mouse wheel (vertical & horizontal) raises/lowers temp without scrolling PageView.
    final hoverMouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hoverMouse.addPointer(location: Offset.zero);
    addTearDown(hoverMouse.removePointer);
    await tester.pump();
    await hoverMouse.moveTo(dialCenter);
    await tester.pumpAndSettle();
    expect(TactileMotionScope.activeFocus.value, isNotNull);
    expect(TactileMotionScope.activeFocus.value!.isCircle, isTrue);
    expect(TactileMotionScope.activeFocus.value!.isPressed, isFalse);
    expect(find.byType(BackdropFilter), findsOneWidget);

    final mouse = TestPointer(7, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(mouse.hover(dialCenter));
    await tester.pump();
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(targetTemp, ThermostatMath.snapTemperature(prevTemp + 0.5));
    expect(outerWheelCount, 0);
    expect(pageController.page, 0.0);

    await tester.sendEventToBinding(mouse.scroll(const Offset(0, 100)));
    await tester.pump();
    expect(targetTemp, prevTemp);
    expect(outerWheelCount, 0);
    expect(pageController.page, 0.0);

    await tester.sendEventToBinding(mouse.scroll(const Offset(80, 0)));
    await tester.pumpAndSettle();
    expect(targetTemp, ThermostatMath.snapTemperature(prevTemp + 0.5));
    expect(outerWheelCount, 0);
    expect(pageController.page, 0.0);

    // 4. Moving cursor outside outerTickRadius clears hover focus blur,
    //    and mouse wheel passes to outer wheel listener without changing temp.
    await hoverMouse.moveTo(cornerOutsideTick);
    await tester.pumpAndSettle();
    expect(TactileMotionScope.activeFocus.value, isNull);
    expect(find.byType(BackdropFilter), findsNothing);

    final afterWheelTemp = targetTemp;
    await tester.sendEventToBinding(mouse.hover(cornerOutsideTick));
    await tester.pump();
    await tester.sendEventToBinding(mouse.scroll(const Offset(0, -100)));
    await tester.pump();
    expect(targetTemp, afterWheelTemp);
    expect(outerWheelCount, 1);

    // 5. Tactile disabled -> pressing inside dial keeps focus blur off
    TactileMotionScope.globalEnabled.value = false;
    await tester.pumpAndSettle();
    final offTouch = await tester.startGesture(insideTickPoint);
    await tester.pump(const Duration(milliseconds: 100));
    expect(TactileMotionScope.activeFocus.value, isNull);
    expect(find.byType(BackdropFilter), findsNothing);
    await offTouch.up();
    await tester.pumpAndSettle();
  });

  test('DialRingStyle exposes 3 curated dynamic styles, resolves dynamic accents, and safely migrates removed themes', () {
    expect(DialRingStyleInfo.dynamicThemes.length, 3);
    expect(VisualCustomizationState.defaults().dialRingStyle, DialRingStyle.classic);

    for (final style in DialRingStyle.values) {
      final state = VisualCustomizationState.defaults().copyWith(dialRingStyle: style);
      final restored = VisualCustomizationState.fromJson(state.toJson());
      expect(restored.dialRingStyle, style);
    }

    for (final removedName in ['chronoRadar', 'magneticFlux', 'non_existent_ring_theme']) {
      final fallback = VisualCustomizationState.fromJson({
        ...VisualCustomizationState.defaults().toJson(),
        'dialRingStyle': removedName,
      });
      expect(fallback.dialRingStyle, DialRingStyle.classic);
    }

    // Boiler flame accent: standby pilot is cool sky-blue; roaring flame warms to amber-orange
    final pilotAccent = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.boilerFlame,
      baseAccent: const Color(0xFFFF7A24),
      targetTemp: 18.0,
      flameIntensity: 0.0,
    );
    expect(pilotAccent, const Color(0xFF38BDF8));

    final roarAccent = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.boilerFlame,
      baseAccent: const Color(0xFF38BDF8),
      targetTemp: 28.5,
      flameIntensity: 1.0,
    );
    expect(roarAccent, const Color(0xFFFF7A24));

    // Motorsport tachometer hits redline crimson >= 26°C
    final redlineAccent = DialRingStyleInfo.resolveDialAccent(
      style: DialRingStyle.autoTacho,
      baseAccent: const Color(0xFFFF7A24),
      targetTemp: 28.5,
      flameIntensity: 0.9,
    );
    expect(redlineAccent, const Color(0xFFEF4444));
  });

  testWidgets('RotaryDial renders all curated dial styles smoothly across standby/heating and dark/light themes', (tester) async {
    final standbyBoiler = ThermostatMath.computeBoilerTelemetry(22.0, 18.0);
    final roaringBoiler = ThermostatMath.computeBoilerTelemetry(18.0, 28.5);
    final darkPalette = VisualCustomizationState.defaults().resolvePalette();
    final lightPalette = VisualCustomizationState.defaults()
        .copyWith(theme: AppThemeMode.lightDay)
        .resolvePalette();

    for (final palette in [darkPalette, lightPalette]) {
      for (final boiler in [standbyBoiler, roaringBoiler]) {
        final target = boiler.isHeating ? 28.5 : 18.0;
        for (final style in DialRingStyle.values) {
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: Center(
                  child: RotaryDial(
                    targetTemp: target,
                    onChangeTarget: (_) {},
                    modeName: 'KONFOR MODU',
                    accentColor: const Color(0xFFFF7A24),
                    boiler: boiler,
                    lang: LangCode.tr,
                    palette: palette,
                    dialRingStyle: style,
                    performanceMode: style == DialRingStyle.thermoMercury
                        ? PerformanceMode.ecoBattery
                        : PerformanceMode.ultra60fps,
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 120));
          expect(find.text('${target.toStringAsFixed(1)}°'), findsOneWidget);
          if (style != DialRingStyle.classic) {
            expect(find.byType(DialRingEffectLayer), findsOneWidget);
            expect(find.byType(DialInteriorEffectLayer), findsOneWidget);
          } else {
            expect(find.byType(DialRingEffectLayer), findsNothing);
            expect(find.byType(DialInteriorEffectLayer), findsNothing);
          }
        }
      }
    }
  });

  testWidgets('ThemeEffectsSheet shows live previews & heat test chips for the 3 curated dial styles and updates state on tap', (tester) async {
    VisualCustomizationState latestVisual = VisualCustomizationState.defaults();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => ElevatedButton(
              onPressed: () {
                showThemeEffectsSheet(
                  context: context,
                  lang: LangCode.tr,
                  accentColor: const Color(0xFFFF7A24),
                  hapticEnabled: false,
                  initialVisual: latestVisual,
                  onUpdateVisual: (v) => latestVisual = v,
                );
              },
              child: const Text('Tema Aç'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Tema Aç'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));

    final listScroll = find.byType(Scrollable).first;
    await tester.scrollUntilVisible(
      find.text('Harlı / Redline (28.5°)'),
      160.0,
      scrollable: listScroll,
    );
    await tester.tap(find.text('Harlı / Redline (28.5°)'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('28.5°'), findsWidgets);

    for (final info in DialRingStyleInfo.dynamicThemes) {
      await tester.scrollUntilVisible(
        find.text(info.titleTr),
        200.0,
        scrollable: listScroll,
      );
      expect(find.text(info.titleTr), findsWidgets);
      expect(find.byType(DialRingPreviewThumb), findsWidgets);
    }

    await tester.ensureVisible(find.text('Süper Oto Kadranı (10–30)').last);
    await tester.pump();
    await tester.tap(find.text('Süper Oto Kadranı (10–30)').last);
    await tester.pump(const Duration(milliseconds: 120));
    expect(latestVisual.dialRingStyle, DialRingStyle.autoTacho);

    await tester.scrollUntilVisible(
      find.text('Gerçekçi Kombi Alevi').first,
      -200.0,
      scrollable: listScroll,
    );
    await tester.tap(find.text('Gerçekçi Kombi Alevi').last);
    await tester.pump(const Duration(milliseconds: 120));
    expect(latestVisual.dialRingStyle, DialRingStyle.boilerFlame);

    await tester.ensureVisible(find.text('Sıvı Termal Hazne').last);
    await tester.pump();
    await tester.tap(find.text('Sıvı Termal Hazne').last);
    await tester.pump(const Duration(milliseconds: 120));
    expect(latestVisual.dialRingStyle, DialRingStyle.thermoMercury);
  });

  test('WeatherService maps Izmir & Ankara to distinct coordinates and parses Open-Meteo forecasts', () {
    final izmirCoords = WeatherService.coordinatesForLocation('Yazlık · İzmir');
    final ankaraCoords = WeatherService.coordinatesForLocation('Ofis · Ankara');
    expect(izmirCoords.cityKey, 'izmir');
    expect(ankaraCoords.cityKey, 'ankara');
    expect(izmirCoords.latitude, isNot(ankaraCoords.latitude));

    Map<String, dynamic> buildPayload(double currentTemp, int code, int maxTemp, int minTemp) => {
          'current': {
            'temperature_2m': currentTemp,
            'relative_humidity_2m': 61,
            'wind_speed_10m': 14.2,
            'weather_code': code,
            'is_day': 1,
          },
          'hourly': {
            'time': ['2026-11-26T00:00', '2026-11-26T03:00', '2026-11-26T06:00'],
            'temperature_2m': [currentTemp - 2, currentTemp - 1, currentTemp],
            'precipitation_probability': [10, 20, 65],
            'wind_speed_10m': [11.0, 12.5, 14.2],
            'weather_code': [code, code, code],
          },
          'daily': {
            'time': ['2026-11-26', '2026-11-27', '2026-11-28', '2026-11-29', '2026-11-30'],
            'weather_code': [code, 1, 2, 3, 61],
            'temperature_2m_max': [maxTemp, maxTemp + 1, maxTemp - 1, maxTemp, maxTemp - 2],
            'temperature_2m_min': [minTemp, minTemp, minTemp - 1, minTemp + 1, minTemp - 2],
            'precipitation_probability_max': [15, 20, 30, 40, 80],
          },
        };

    final izmirReport = WeatherService.parseOpenMeteoJson(
      buildPayload(19.4, 0, 22, 13),
      locationName: 'Yazlık · İzmir',
      lang: LangCode.tr,
    );
    final ankaraReport = WeatherService.parseOpenMeteoJson(
      buildPayload(4.2, 71, 6, -2),
      locationName: 'Ofis · Ankara',
      lang: LangCode.tr,
    );

    expect(izmirReport.currentTempC, 19.4);
    expect(izmirReport.conditionTr, 'Güneşli');
    expect(ankaraReport.currentTempC, 4.2);
    expect(ankaraReport.conditionTr, 'Karlı');
    expect(izmirReport.days.length, 5);
    expect(izmirReport.days.first.hourly.length, 3);
  });

  test('ThermalLogAggregator records ticks, round-trips JSON, and distinguishes Daily/Weekly/Monthly summaries', () {
    const heating = BoilerTelemetry(
      isHeating: true,
      flamePercent: 50,
      pumpRpm: 1450,
      waterPressureBar: 1.6,
      modulationActive: true,
      statusTextTr: 'Aktif',
      statusTextEn: 'Active',
    );
    const standby = BoilerTelemetry(
      isHeating: false,
      flamePercent: 0,
      pumpRpm: 0,
      waterPressureBar: 1.6,
      modulationActive: false,
      statusTextTr: 'Bekleme',
      statusTextEn: 'Standby',
    );

    var logs = <String, DailyThermalLog>{};
    // Today: 1800s active burn at 50% flame
    logs = ThermalLogAggregator.recordSample(
      logs: logs,
      timestamp: DateTime(2026, 11, 26, 9, 0),
      roomTemp: 21.8,
      boiler: heating,
      seconds: 1800,
    );
    logs = ThermalLogAggregator.recordSample(
      logs: logs,
      timestamp: DateTime(2026, 11, 26, 13, 0),
      roomTemp: 22.4,
      boiler: standby,
      seconds: 600,
    );
    // 3 days earlier (inside weekly & monthly)
    logs = ThermalLogAggregator.recordSample(
      logs: logs,
      timestamp: DateTime(2026, 11, 23, 20, 0),
      roomTemp: 20.5,
      boiler: heating,
      seconds: 3600,
    );
    // 16 days earlier (outside 7-day weekly window, inside November monthly)
    logs = ThermalLogAggregator.recordSample(
      logs: logs,
      timestamp: DateTime(2026, 11, 10, 8, 0),
      roomTemp: 19.5,
      boiler: heating,
      seconds: 3600,
    );

    final decoded = ThermalLogAggregator.decodeLogs(ThermalLogAggregator.encodeLogs(logs));
    expect(decoded.length, 3);

    final anchor = DateTime(2026, 11, 26);
    final daily = ThermalLogAggregator.summarize(
      logs: decoded,
      anchorDate: anchor,
      periodIndex: 0,
      gasUnitPriceTl: 12.0,
    );
    final weekly = ThermalLogAggregator.summarize(
      logs: decoded,
      anchorDate: anchor,
      periodIndex: 1,
      gasUnitPriceTl: 12.0,
    );
    final monthly = ThermalLogAggregator.summarize(
      logs: decoded,
      anchorDate: anchor,
      periodIndex: 2,
      gasUnitPriceTl: 12.0,
    );

    expect(daily.activeBurnSeconds, 1800);
    expect(weekly.activeBurnSeconds, 5400);
    expect(monthly.activeBurnSeconds, 9000);
    expect(daily.gasM3, lessThan(weekly.gasM3));
    expect(weekly.gasM3, lessThan(monthly.gasM3));
    expect(monthly.costTl, closeTo(monthly.gasM3 * 12.0, 0.001));
    expect(daily.singleDayLog!.buckets[2].avgTemp, 21.8);
    expect(daily.singleDayLog!.buckets[3].avgTemp, 22.4);
  });

  testWidgets('ReportScreen, ScheduleScreen, and ThermostatScreen show empty sensors (--), date picker, and editable monthly gas bill', (tester) async {
    final palette = VisualCustomizationState.defaults().resolvePalette();
    const boiler = BoilerTelemetry(
      isHeating: true,
      flamePercent: 65,
      pumpRpm: 1850,
      waterPressureBar: 1.6,
      modulationActive: true,
      statusTextTr: 'Aktif',
      statusTextEn: 'Active',
    );
    final now = DateTime.now();
    final todayIso = ThermalLogAggregator.formatDateIso(now);
    final logs = ThermalLogAggregator.recordSample(
      logs: const {},
      timestamp: DateTime(now.year, now.month, now.day, 10, 0),
      roomTemp: 21.8,
      boiler: boiler,
      seconds: 3600,
    );

    // 1. ThermostatScreen shows '--' for disconnected sensors
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThermostatScreen(
            roomTemp: 21.8,
            targetTemp: 22.5,
            activePreset: PresetId.konfor,
            accentColor: const Color(0xFFFF7A24),
            boiler: boiler,
            sensors: const BoilerHardwareSensors.disconnected(),
            lang: LangCode.tr,
            palette: palette,
            onChangeTarget: (_) {},
            onSelectPreset: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('--'), findsNWidgets(3));
    expect(find.text('1.6 Bar'), findsNothing);

    // 2. ScheduleScreen Daily Savings shows real burn duration & '--' bottom sensors
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ScheduleScreen(
            lang: LangCode.tr,
            slots: ThermostatMath.defaultSchedule,
            subTabOrder: const [ScheduleSubTab.dailySavings, ScheduleSubTab.smartSchedule],
            palette: palette,
            boiler: boiler,
            sensors: const BoilerHardwareSensors.disconnected(),
            todayLog: logs[todayIso],
            gasUnitPriceTl: 10.25,
            onUpdateSlot: (_, {time, enabled, targetTemp}) {},
            onSaveSchedule: () {},
            savedNotice: false,
          ),
        ),
      ),
    );
    expect(find.text('1s 0d'), findsOneWidget);
    expect(find.text('1s 30d'), findsNothing);
    expect(find.text('--'), findsNWidgets(2));

    // 3. ReportScreen: date picker, weekly/monthly tabs, gas rate editor, empty sensors
    double updatedRate = 10.25;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ReportScreen(
            lang: LangCode.tr,
            roomTemp: 21.8,
            targetTemp: 22.5,
            boiler: boiler,
            sensors: const BoilerHardwareSensors.disconnected(),
            dailyLogs: logs,
            gasUnitPriceTl: updatedRate,
            onUpdateGasUnitPrice: (v) => updatedRate = v,
            subTabOrder: const [
              ReportSubTab.heatMap,
              ReportSubTab.usageBill,
              ReportSubTab.boilerSensors,
            ],
            palette: palette,
          ),
        ),
      ),
    );
    expect(find.text('İncelenen Gün:'), findsOneWidget);
    await tester.tap(find.text('Haftalık'));
    await tester.pumpAndSettle();
    expect(find.text('Haftalık Log Analizi'), findsOneWidget);
    await tester.tap(find.text('Aylık'));
    await tester.pumpAndSettle();
    expect(find.text('Aylık Hafta Dağılımı'), findsOneWidget);

    await tester.tap(find.text('💰 Tüketim ve Fatura'));
    await tester.pumpAndSettle();
    expect(find.text('Düzenle'), findsOneWidget);
    await tester.tap(find.text('Düzenle'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '14.50');
    await tester.tap(find.text('Kaydet'));
    await tester.pumpAndSettle();
    expect(updatedRate, 14.5);

    await tester.tap(find.text('🔥 Kombi & Sensörler'));
    await tester.pumpAndSettle();
    expect(find.text('Sensör Bağlı Değil'), findsOneWidget);
    expect(find.text('--'), findsNWidgets(6));
    expect(find.text('54.2°C'), findsNothing);

    await tester.tap(find.text('🌡️ Sıcaklık Haritası'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Günlük'));
    await tester.pumpAndSettle();
    await tester.tap(find.byIcon(Icons.calendar_month_rounded));
    await tester.pumpAndSettle();
    expect(find.byType(DatePickerDialog), findsOneWidget);
  });

  testWidgets('WeatherScreen renders live city forecasts and error/retry state without hardcoded 17.7C', (tester) async {
    final palette = VisualCustomizationState.defaults().resolvePalette();
    final izmirReport = WeatherReport(
      locationName: 'Yazlık · İzmir',
      cityName: 'İzmir',
      currentTempC: 24.6,
      humidityPercent: 52,
      windKmh: 16.4,
      weatherCode: 0,
      conditionTr: 'Güneşli',
      conditionEn: 'Sunny',
      icon: Icons.wb_sunny_outlined,
      days: const [
        DailyWeatherForecast(
          dayTr: 'Bugün',
          dayEn: 'Today',
          dateLabel: '26 Kas',
          conditionTr: 'Güneşli',
          conditionEn: 'Sunny',
          highTemp: 26,
          lowTemp: 15,
          rainChance: '%5',
          icon: Icons.wb_sunny_outlined,
          hourly: [],
        ),
      ],
      fetchedAt: DateTime(2026, 11, 26, 12, 0),
    );

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeatherScreen(
            lang: LangCode.tr,
            locationName: 'Yazlık · İzmir',
            palette: palette,
            weatherReport: izmirReport,
            onApplyEcoCompensation: () {},
          ),
        ),
      ),
    );
    expect(find.text('24.6°C'), findsOneWidget);
    expect(find.text('17.7°C'), findsNothing);

    var retried = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: WeatherScreen(
            lang: LangCode.tr,
            locationName: 'Ofis · Ankara',
            palette: palette,
            weatherReport: null,
            weatherError: 'Ankara canlı hava raporu alınamadı',
            onRefreshWeather: () => retried = true,
            onApplyEcoCompensation: () {},
          ),
        ),
      ),
    );
    expect(find.text('Ankara canlı hava raporu alınamadı'), findsOneWidget);
    await tester.tap(find.text('Tekrar Dene'));
    expect(retried, isTrue);
  });

  test('Disconnected ESP32 yields zero fake defaults, no fake heating comparisons, and -- reports', () {
    final defaults = SystemSettingsState.defaults();
    expect(defaults.espOnline, isFalse);
    expect(defaults.espWdtResetCount, 0);
    expect(defaults.espOfflineBurnMinutes, 0);
    expect(defaults.espLogs, isEmpty);

    final disconnected = ThermostatMath.computeBoilerTelemetry(null, 28.0);
    expect(disconnected.hasSensorReading, isFalse);
    expect(disconnected.isHeating, isFalse);
    expect(disconnected.flamePercent, 0);
    expect(disconnected.pumpRpm, 0);
    expect(disconnected.statusTextTr, contains('--'));

    final guard = NotificationService.evaluateSafetyThresholds(
      roomTemp: null,
      boiler: disconnected,
      sensors: const BoilerHardwareSensors.disconnected(),
    );
    expect(guard.lowPressure, isFalse);
    expect(guard.overheat, isFalse);
    expect(guard.freezeRisk, isFalse);

    final callDecision = AiCallService.evaluateTrigger(
      enabled: true,
      triggerMode: AiCallTriggerMode.ignitionAndSafety,
      wasHeating: false,
      nextBoiler: disconnected,
      safety: guard,
      roomTemp: null,
      targetTemp: 28.5,
      isUserChange: true,
    );
    expect(callDecision.shouldCall, isFalse);

    final eventDecision = AiCallService.evaluateBoilerEventNotification(
      enabled: true,
      wasHeating: false,
      nextBoiler: disconnected,
      safety: guard,
      locationName: 'Ev · İstanbul',
      roomTemp: null,
      targetTemp: 25.0,
      isUserChange: true,
    );
    expect(eventDecision.shouldNotify, isFalse);

    final report = EspLogService.exportLogsReport(
      settings: defaults,
      roomTemp: null,
      targetTemp: 22.5,
      boiler: disconnected,
      lang: LangCode.tr,
    );
    expect(report, contains('-- → 22.5°C'));
    expect(report, contains('Alev --'));
    expect(report, isNot(contains('21.8')));
  });

  testWidgets('Screens and SmartDisplay show -- when roomTemp or weatherReport is null, and warn on offline target change', (tester) async {
    final palette = VisualCustomizationState.defaults().resolvePalette();
    final disconnected = ThermostatMath.computeBoilerTelemetry(null, 25.0);

    // 1. ThermostatScreen shows -- & offline hardware strip
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ThermostatScreen(
            roomTemp: null,
            targetTemp: 25.0,
            activePreset: PresetId.boost,
            accentColor: const Color(0xFFF59E0B),
            boiler: disconnected,
            espOnline: false,
            lang: LangCode.tr,
            palette: palette,
            onChangeTarget: (_) {},
            onSelectPreset: (_) {},
          ),
        ),
      ),
    );
    expect(find.text('--'), findsNWidgets(4));
    expect(find.text('ESP32 Bağlı Değil'), findsOneWidget);
    expect(find.textContaining('21.8'), findsNothing);

    // 2. SmartDisplayOverlay shows -- outdoor & -- room without hardcoded 16.4/7.2/11.9
    await tester.pumpWidget(
      MaterialApp(
        home: SmartDisplayOverlay(
          settings: SystemSettingsState.defaults().copyWith(
            smartDisplayMode: SmartDisplayMode.aod,
          ),
          slideIndex: 0,
          now: DateTime(2026, 11, 26, 12, 30),
          locationName: 'Yazlık · İzmir',
          roomTemp: null,
          targetTemp: 22.5,
          boiler: disconnected,
          weatherReport: null,
          accentColor: const Color(0xFFF59E0B),
          palette: palette,
          lang: LangCode.tr,
          paletteTag: 'obsidian',
          onChangeTargetTemp: (_) {},
          onSelectPreset: (_) {},
          onUpdateSettings: (_) {},
          onStepSlideIndex: (_) {},
          onClose: () {},
        ),
      ),
    );
    expect(find.text('--'), findsWidgets);
    expect(find.text('16.4°C'), findsNothing);
    expect(find.text('21.8°C'), findsNothing);
    expect(find.text('⚡ Bağlı Değil'), findsOneWidget);

    // 3. BootCeremonyOverlay renders Oda: -- & ESP32: --
    await tester.pumpWidget(
      MaterialApp(
        home: BootCeremonyOverlay(
          style: BootCeremonyStyle.thermalPulse,
          durationMs: 1200,
          soundChimeEnabled: false,
          hapticEnabled: false,
          hapticStrength: 50,
          roomTemp: null,
          targetTemp: 22.5,
          boiler: disconnected,
          locationName: 'Ev · İstanbul',
          accentColor: const Color(0xFFF59E0B),
          palette: palette,
          lang: LangCode.tr,
          onComplete: () {},
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Oda: --'), findsOneWidget);
    expect(find.text('ESP32: --'), findsOneWidget);

    // 4. Full app shell boots with null roomTemp (shows --) and shows offline warning banner when target changes
    SharedPreferences.setMockInitialValues({
      'termostat_flow_flutter_v2': jsonEncode({
        'settings': {'bootCeremonyEnabled': false, 'cloudSyncEnabled': false},
      }),
    });
    await tester.pumpWidget(const TermostatFlowApp());
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('21.8°C'), findsNothing);

    await tester.tap(find.byIcon(Icons.add_rounded).first);
    await tester.pump();
    expect(find.textContaining('ESP32 / Kombi Bağlantısı Yok'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });

  test('5-tab dock math, HouseFloorPlan templates, RoomEspTelemetry defaults, and RTDB rooms parser work accurately', () {
    expect(ThermostatMath.tabs.length, 5);
    expect(ThermostatMath.tabs.first.id, TabId.ev);
    expect(ThermostatMath.tabs.first.labelTr, 'Ev');
    expect(ThermostatMath.tabXs.length, 5);
    expect(VisualCustomizationState.defaults().tabOrder.first, TabId.ev);
    expect(VisualCustomizationState.defaults().startupTab, TabId.termo);

    final voiceToHome = ThermostatMath.parseVoiceCommand('ev haritasını aç');
    expect(voiceToHome.handled, isTrue);
    expect(voiceToHome.navigateTab, TabId.ev);

    expect(HouseFloorPlan.readyTemplates.length, 4);
    final tpl11 = HouseFloorPlan.fromTemplate('1+1');
    final tplDuplex = HouseFloorPlan.fromTemplate('duplex');
    expect(tpl11.rooms.length, 4);
    expect(tplDuplex.rooms.length, greaterThan(tpl11.rooms.length));

    final restoredPlan = HouseFloorPlan.fromJson(tplDuplex.toJson());
    expect(restoredPlan.templateId, 'duplex');
    expect(restoredPlan.rooms.length, tplDuplex.rooms.length);
    expect(restoredPlan.rooms.first.name, tplDuplex.rooms.first.name);

    const offlineTel = RoomEspTelemetry.offline('esp-salon');
    expect(offlineTel.online, isFalse);
    expect(offlineTel.roomTempC, isNull);
    expect(offlineTel.radiatorTempC, isNull);
    expect(offlineTel.wifiRssiDbm, isNull);
    expect(offlineTel.wifiQualityLabel(tr: true), '--');

    final pulled = FirebaseSyncService.parsePullResponseBody(
      jsonEncode({
        'targetTemp': 23.0,
        'roomTemp': 22.1,
        'rooms': {
          'esp-salon': {'online': true, 'roomTemp': 22.4, 'radiatorTemp': 48.2, 'wifiRssi': -58},
          'esp-yatak': {'online': true, 'roomTemp': 19.6, 'radiatorTemp': 41.0, 'wifiRssi': -74},
        },
      }),
      safeNode: 'kombi',
      statusCode: 200,
      latencyMs: 38,
    );
    expect(pulled.ok, isTrue);
    expect(pulled.remoteRooms['esp-salon']?.roomTempC, 22.4);
    expect(pulled.remoteRooms['esp-salon']?.radiatorTempC, 48.2);
    expect(pulled.remoteRooms['esp-salon']?.wifiRssiDbm, -58);
    expect(pulled.remoteRooms['esp-yatak']?.wifiBars, 2);
  });

  testWidgets('FlowTabBarShell renders 5 tabs with Ev first and Home3dScreen supports templates, editor, and -- telemetry', (tester) async {
    final palette = VisualCustomizationState.defaults().resolvePalette();
    final orderedTabs = VisualCustomizationState.defaults().orderedTabs;
    TabId activeTab = TabId.termo;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) => FlowTabBarShell(
              activeTab: activeTab,
              orderedTabs: orderedTabs,
              startupTab: TabId.termo,
              onSelectTab: (next) => setState(() => activeTab = next),
              onReorderTabs: (_, {nextStartupTab}) {},
              activeAccent: const RgbAccent(1.0, 0.48, 0.14),
              lang: LangCode.tr,
              isLandscape: false,
              performanceMode: PerformanceMode.ecoBattery,
              palette: palette,
              onOpenVoice: () {},
              voiceOpen: false,
              child: const Center(child: Text('Body')),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Ev'), findsOneWidget);
    expect(find.text('Termo.'), findsOneWidget);
    expect(find.text('Hava'), findsOneWidget);
    expect(find.text('Rapor'), findsOneWidget);
    expect(find.text('Prog.'), findsOneWidget);

    await tester.tap(find.text('Ev'));
    await tester.pump();
    expect(activeTab, TabId.ev);

    // Home3dScreen renders 3D map with strict '--' when ESP32s are offline, plus template & editor actions
    HouseFloorPlan plan = HouseFloorPlan.defaults();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: StatefulBuilder(
            builder: (ctx, setState) => Home3dScreen(
              lang: LangCode.tr,
              palette: palette,
              accentColor: const Color(0xFF2ED6C7),
              floorPlan: plan,
              mainRoomTemp: null,
              targetTemp: 22.5,
              boiler: ThermostatMath.computeBoilerTelemetry(null, 22.5),
              espOnline: false,
              onUpdateFloorPlan: (next) => setState(() => plan = next),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('3D Ev Haritası'), findsOneWidget);
    expect(find.text('Planı Çiz / Düzenle'), findsOneWidget);
    expect(find.text('Döndür · Odaya dokun · 60 FPS'), findsOneWidget);
    expect(find.text('--'), findsWidgets);

    // Switch to Planı Çiz / Düzenle, switch to 1+1 Daire template, then add a room
    await tester.tap(find.text('Planı Çiz / Düzenle'));
    await tester.pumpAndSettle();
    expect(find.text('1+1 Daire'), findsOneWidget);
    await tester.tap(find.text('1+1 Daire'));
    await tester.pumpAndSettle();
    expect(plan.templateId, '1+1');
    final countBeforeAdd = plan.rooms.length;

    await tester.tap(find.text('+ Oda Ekle'));
    await tester.pumpAndSettle();
    expect(plan.rooms.length, countBeforeAdd + 1);

    // Verify ECO battery mode LOD renders cleanly
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Home3dScreen(
            lang: LangCode.tr,
            palette: palette,
            accentColor: const Color(0xFF2ED6C7),
            floorPlan: plan,
            mainRoomTemp: null,
            targetTemp: 22.5,
            boiler: ThermostatMath.computeBoilerTelemetry(null, 22.5),
            espOnline: false,
            performanceMode: PerformanceMode.ecoBattery,
            onUpdateFloorPlan: (_) {},
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.text('Döndür · Odaya dokun · Eko'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
  });
}
