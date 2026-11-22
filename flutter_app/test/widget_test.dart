import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:termostat_flow/models/thermostat_state.dart';
import 'package:termostat_flow/services/ai_call_service.dart';
import 'package:termostat_flow/services/ambient_audio_service.dart';
import 'package:termostat_flow/services/esp_log_service.dart';
import 'package:termostat_flow/services/firebase_sync_service.dart';
import 'package:termostat_flow/services/hardware_service.dart';
import 'package:termostat_flow/services/notification_service.dart';
import 'package:termostat_flow/services/vault_crypto_service.dart';
import 'package:termostat_flow/services/voice_gender_classifier.dart';
import 'package:termostat_flow/services/voice_speech_service.dart';
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

  test('VisualCustomizationState round-trips theme and tab order', () {
    final initial = VisualCustomizationState.defaults().copyWith(
      theme: AppThemeMode.obsidianLavender,
      obsidianPalette: ObsidianPalette.royalViolet,
      performanceMode: PerformanceMode.ecoBattery,
      weatherPreview: WeatherEffectPreview.rainy,
      tabOrder: [TabId.hava, TabId.termo, TabId.prog, TabId.rapor],
    );
    final restored = VisualCustomizationState.fromJson(initial.toJson());
    expect(restored.theme, AppThemeMode.obsidianLavender);
    expect(restored.obsidianPalette, ObsidianPalette.royalViolet);
    expect(restored.performanceMode, PerformanceMode.ecoBattery);
    expect(restored.weatherPreview, WeatherEffectPreview.rainy);
    expect(restored.tabOrder, [TabId.hava, TabId.termo, TabId.prog, TabId.rapor]);
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
      ambientVolume: 0.75,
      marqueeTrackEnabled: false,
      equalizerEnabled: true,
      equalizerStyle: EqualizerStyle.wave,
      displayBrightness: 50,
      displaySleepMinutes: 15,
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
    expect(restored.ambientTrackTitle(LangCode.tr), 'Lo-Fi Chill.mp3');
    expect(restored.ambientVolume, 0.75);
    expect(restored.marqueeTrackEnabled, isFalse);
    expect(restored.equalizerEnabled, isTrue);
    expect(restored.equalizerStyle, EqualizerStyle.wave);
    expect(restored.displayBrightness, 50);
    expect(restored.displaySleepMinutes, 15);
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

    final clamped = initial.copyWith(bootCeremonyDurationMs: 9000, mascotScale: 3.0);
    expect(clamped.bootCeremonyDurationMs, 3500);
    expect(clamped.mascotScale, 1.60);
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
  });

  test('FirebaseSyncService validates URLs, sanitizes node paths, builds JSON preview, and persists Cloud Sync settings', () {
    expect(FirebaseSyncService.sanitizeNodePath(' /kombi.json '), 'kombi');
    expect(FirebaseSyncService.sanitizeNodePath('/ev/salon/'), 'ev/salon');
    expect(FirebaseSyncService.sanitizeNodePath('   '), 'kombi');

    expect(FirebaseSyncService.validateRtdbUrl('https://kombi-kontrol-default-rtdb.firebaseio.com'), isTrue);
    expect(FirebaseSyncService.validateRtdbUrl('ftp://invalid-host'), isFalse);
    expect(FirebaseSyncService.validateRtdbUrl(''), isFalse);

    final boiler = ThermostatMath.computeBoilerTelemetry(21.8, 22.5);
    final preview = FirebaseSyncService.buildPayloadPreviewJson(
      roomName: 'Salon',
      espDeviceId: 'ESP32-KOMBI-01',
      roomTemp: 21.8,
      targetTemp: 22.5,
      boiler: boiler,
      timestamp: DateTime.utc(2026, 11, 22, 12, 0, 0),
    );
    final parsed = jsonDecode(preview) as Map<String, dynamic>;
    expect(parsed['roomTemp'], 21.8);
    expect(parsed['targetTemp'], 22.5);
    expect(parsed['boilerActive'], isTrue);
    expect(parsed['roomName'], 'Salon');
    expect(parsed['espDeviceId'], 'ESP32-KOMBI-01');

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
}
