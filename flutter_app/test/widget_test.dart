import 'package:flutter_test/flutter_test.dart';
import 'package:termostat_flow/models/thermostat_state.dart';

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
}
