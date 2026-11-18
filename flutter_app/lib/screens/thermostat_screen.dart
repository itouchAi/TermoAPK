import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../widgets/rotary_dial.dart';

class ThermostatScreen extends StatelessWidget {
  final double roomTemp;
  final double targetTemp;
  final PresetId? activePreset;
  final Color accentColor;
  final BoilerTelemetry boiler;
  final LangCode lang;
  final ThemePaletteSpec palette;
  final ValueChanged<double> onChangeTarget;
  final ValueChanged<ThermostatPreset> onSelectPreset;

  const ThermostatScreen({
    super.key,
    required this.roomTemp,
    required this.targetTemp,
    required this.activePreset,
    required this.accentColor,
    required this.boiler,
    required this.lang,
    required this.palette,
    required this.onChangeTarget,
    required this.onSelectPreset,
  });

  IconData _iconForPreset(PresetId id) {
    switch (id) {
      case PresetId.eko:
        return Icons.eco_outlined;
      case PresetId.konfor:
        return Icons.local_fire_department_rounded;
      case PresetId.gece:
        return Icons.nightlight_round;
      case PresetId.boost:
        return Icons.bolt_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    return OrientationBuilder(
      builder: (context, orientation) {
        return LayoutBuilder(
          builder: (context, constraints) {
            final isLandscape = orientation == Orientation.landscape || constraints.maxWidth > constraints.maxHeight;
            final compactLandscape = isLandscape && constraints.maxHeight < 360;
            final dialSize = isLandscape
                ? math.max(140.0, math.min(220.0, constraints.maxHeight - 95.0))
                : math.max(196.0, math.min(256.0, constraints.maxHeight * 0.40));

            ThermostatPreset? matched;
            for (final p in ThermostatMath.presets) {
              if (p.id == activePreset) matched = p;
            }
            final modeName = matched != null
                ? (lang == LangCode.tr ? matched.modeNameTr : matched.modeNameEn)
                : (lang == LangCode.tr ? 'MANUEL MOD' : 'MANUAL MODE');

            final telemetryStrip = Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: palette.cardBg,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: palette.cardBorder),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TelemetryCell(
                    label: lang == LangCode.tr ? 'ODA:' : 'ROOM:',
                    value: '${roomTemp.toStringAsFixed(1)}°C',
                    palette: palette,
                  ),
                  Text('|', style: TextStyle(color: palette.cardBorder)),
                  _TelemetryCell(
                    label: lang == LangCode.tr ? 'BASINÇ:' : 'PRESS:',
                    value: '${boiler.waterPressureBar.toStringAsFixed(1)} Bar',
                    palette: palette,
                  ),
                  Text('|', style: TextStyle(color: palette.cardBorder)),
                  _TelemetryCell(
                    label: lang == LangCode.tr ? 'HEDEF:' : 'TARGET:',
                    value: '${targetTemp.toStringAsFixed(1)}°',
                    valueColor: accentColor,
                    palette: palette,
                  ),
                ],
              ),
            );

            if (isLandscape) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 920),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        Expanded(
                          flex: 5,
                          child: Center(
                            child: RotaryDial(
                              targetTemp: targetTemp,
                              onChangeTarget: onChangeTarget,
                              modeName: modeName,
                              accentColor: accentColor,
                              boiler: boiler,
                              lang: lang,
                              palette: palette,
                              sizePx: dialSize,
                              compact: compactLandscape,
                            ),
                          ),
                        ),
                        const SizedBox(width: 20),
                        Expanded(
                          flex: 7,
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    lang == LangCode.tr
                                        ? 'Termostat & Kombi Ana Kontrol'
                                        : 'Thermostat & Boiler Control',
                                    style: TextStyle(
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      color: palette.textPrimary,
                                    ),
                                  ),
                                  Text(
                                    boiler.isHeating
                                        ? (lang == LangCode.tr ? 'Kombi Aktif' : 'Heating')
                                        : (lang == LangCode.tr ? 'Beklemede' : 'Idle'),
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              telemetryStrip,
                              const SizedBox(height: 10),
                              GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 2,
                                crossAxisSpacing: 10,
                                mainAxisSpacing: 10,
                                childAspectRatio: compactLandscape ? 3.1 : 2.6,
                                children: [
                                  for (final preset in ThermostatMath.presets)
                                    _PresetCard(
                                      preset: preset,
                                      icon: _iconForPreset(preset.id),
                                      selected: activePreset == preset.id,
                                      lang: lang,
                                      palette: palette,
                                      onTap: () => onSelectPreset(preset),
                                    ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: palette.cardBg,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(color: palette.cardBorder),
                                ),
                                child: Row(
                                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      '${lang == LangCode.tr ? 'Ortam Nemi' : 'Humidity'}: %48',
                                      style: TextStyle(fontSize: 11, color: palette.textSecondary),
                                    ),
                                    Text(
                                      '${lang == LangCode.tr ? 'Pompa' : 'Pump'}: ${boiler.isHeating ? '${boiler.pumpRpm} RPM' : '0 RPM'}',
                                      style: TextStyle(fontSize: 11, color: palette.textSecondary),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }

            // PORTRAIT MODE
            return Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 440),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                lang == LangCode.tr
                                    ? 'Termostat & Kombi Ana Kontrol'
                                    : 'Thermostat & Boiler Control',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: palette.textPrimary,
                                ),
                              ),
                              Text(
                                boiler.isHeating
                                    ? (lang == LangCode.tr ? 'Kombi Aktif' : 'Heating')
                                    : (lang == LangCode.tr ? 'Beklemede' : 'Idle'),
                                style: TextStyle(
                                  fontSize: 11,
                                  color: palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          telemetryStrip,
                        ],
                      ),

                      RotaryDial(
                        targetTemp: targetTemp,
                        onChangeTarget: onChangeTarget,
                        modeName: modeName,
                        accentColor: accentColor,
                        boiler: boiler,
                        lang: lang,
                        palette: palette,
                        sizePx: dialSize,
                        compact: constraints.maxHeight < 520,
                      ),

                      Column(
                        children: [
                          Row(
                            children: [
                              for (int i = 0; i < ThermostatMath.presets.length; i++) ...[
                                if (i > 0) const SizedBox(width: 8),
                                Expanded(
                                  child: _PresetCard(
                                    preset: ThermostatMath.presets[i],
                                    icon: _iconForPreset(ThermostatMath.presets[i].id),
                                    selected: activePreset == ThermostatMath.presets[i].id,
                                    lang: lang,
                                    palette: palette,
                                    onTap: () => onSelectPreset(ThermostatMath.presets[i]),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            lang == LangCode.tr
                                ? 'Kadran üzerindeki renkli halkayı çevirerek veya +/- ile hedefi ayarlayın.'
                                : 'Drag the colored ring on the dial or tap +/- to set target.',
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              fontSize: 11,
                              color: palette.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}

class _TelemetryCell extends StatelessWidget {
  final String label;
  final String value;
  final Color? valueColor;
  final ThemePaletteSpec palette;

  const _TelemetryCell({
    required this.label,
    required this.value,
    this.valueColor,
    required this.palette,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: TextStyle(fontSize: 11, color: palette.textSecondary)),
        const SizedBox(width: 4),
        Text(
          value,
          style: TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w700,
            color: valueColor ?? palette.textPrimary,
            fontFeatures: const [FontFeature.tabularFigures()],
          ),
        ),
      ],
    );
  }
}

class _PresetCard extends StatelessWidget {
  final ThermostatPreset preset;
  final IconData icon;
  final bool selected;
  final LangCode lang;
  final ThemePaletteSpec palette;
  final VoidCallback onTap;

  const _PresetCard({
    required this.preset,
    required this.icon,
    required this.selected,
    required this.lang,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final fg = selected ? Colors.white : palette.textPrimary;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [preset.color, preset.color.withValues(alpha: 0.72)],
                )
              : null,
          color: selected ? null : palette.cardBg,
          border: Border.all(
            color: selected ? preset.color : palette.cardBorder,
          ),
          boxShadow: selected
              ? [BoxShadow(color: preset.color.withValues(alpha: 0.30), blurRadius: 18)]
              : null,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 17, color: selected ? Colors.white : preset.color),
            const SizedBox(height: 3),
            Text(
              lang == LangCode.tr ? preset.labelTr : preset.labelEn,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w700,
                letterSpacing: 0.8,
                color: fg,
              ),
            ),
            Text(
              '${preset.temp.toStringAsFixed(1)}°',
              style: TextStyle(
                fontSize: 11,
                color: fg.withValues(alpha: 0.85),
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
