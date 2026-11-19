import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:termostat_flow/models/thermostat_state.dart';
import 'package:termostat_flow/services/ambient_audio_service.dart';
import 'package:termostat_flow/services/vault_crypto_service.dart';

void main() {
  test('ThermostatMath snaps temperatures to 0.5C bounds', () {
    expect(ThermostatMath.snapTemperature(22.34), 22.5);
    expect(ThermostatMath.snapTemperature(5.0), ThermostatMath.minTemp);
    expect(ThermostatMath.snapTemperature(40.0), ThermostatMath.maxTemp);
  });

  test('Boiler telemetry modulates when target exceeds room temp', () {
    final heating = ThermostatMath.computeBoilerTelemetry(21.8, 22.5);
    expect(heating.isHeating, isTrue);
    expect(heating.flamePercent, greaterThanOrEqualTo(20));

    final standby = ThermostatMath.computeBoilerTelemetry(22.5, 22.0);
    expect(standby.isHeating, isFalse);
    expect(standby.flamePercent, 0);
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
      mascotCharacter: MascotCharacter.mirnav,
      screensaverIdleSeconds: 120,
      screensaverBackdrop: ScreensaverBackdrop.termoLab,
      screensaverBlurBg: true,
      mascotSoundsEnabled: false,
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
    expect(restored.mascotCharacter, MascotCharacter.mirnav);
    expect(restored.screensaverIdleSeconds, 120);
    expect(restored.screensaverBackdrop, ScreensaverBackdrop.termoLab);
    expect(restored.screensaverBlurBg, isTrue);
    expect(restored.mascotSoundsEnabled, isFalse);
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

  test('AmbientAudioService generates valid RIFF/WAVE PCM headers for soundtracks', () {
    for (final track in AmbientSoundtrack.values) {
      final bytes = AmbientAudioService.generateAmbientWavBytes(track);
      expect(bytes.length, greaterThan(44));
      expect(String.fromCharCodes(bytes.sublist(0, 4)), 'RIFF');
      expect(String.fromCharCodes(bytes.sublist(8, 12)), 'WAVE');
    }
  });
}
