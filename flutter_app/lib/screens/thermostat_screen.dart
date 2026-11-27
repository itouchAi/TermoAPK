import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/thermostat_state.dart';
import '../widgets/rotary_dial.dart';
import '../widgets/tactile_button.dart';

class ThermostatScreen extends StatelessWidget {
  final double? roomTemp;
  final double targetTemp;
  final PresetId? activePreset;
  final Color accentColor;
  final BoilerTelemetry boiler;
  final BoilerHardwareSensors sensors;
  final bool espOnline;
  final LangCode lang;
  final ThemePaletteSpec palette;
  final DialRingStyle dialRingStyle;
  final PerformanceMode performanceMode;
  final ValueChanged<double> onChangeTarget;
  final ValueChanged<ThermostatPreset> onSelectPreset;

  const ThermostatScreen({
    super.key,
    required this.roomTemp,
    required this.targetTemp,
    required this.activePreset,
    required this.accentColor,
    required this.boiler,
    this.sensors = const BoilerHardwareSensors.disconnected(),
    this.espOnline = false,
    required this.lang,
    required this.palette,
    this.dialRingStyle = DialRingStyle.classic,
    this.performanceMode = PerformanceMode.ultra60fps,
    required this.onChangeTarget,
    required this.onSelectPreset,
  });

  IconData _iconForPreset(PresetId id) {
    switch (id) {
      case PresetId.eko:
        return Icons.eco_outlined;
      case PresetId.konfor:
        return Icons.local_fire_department_outlined;
      case PresetId.gece:
        return Icons.nightlight_outlined;
      case PresetId.boost:
        return Icons.bolt_outlined;
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
                ? math.max(150.0, math.min(238.0, constraints.maxHeight - 88.0))
                : math.max(198.0, math.min(260.0, constraints.maxHeight * 0.42));

            ThermostatPreset? matched;
            for (final p in ThermostatMath.presets) {
              if (p.id == activePreset) matched = p;
            }
            final modeName = matched != null
                ? (lang == LangCode.tr ? matched.modeNameTr : matched.modeNameEn)
                : (lang == LangCode.tr ? 'MANUEL MOD' : 'MANUAL MODE');

            final glassFill = palette.isLight ? palette.cardBg : Colors.white.withValues(alpha: 0.045);
            final glassBorder = palette.isLight ? palette.cardBorder : Colors.white.withValues(alpha: 0.10);
            final dividerColor = palette.isLight ? palette.cardBorder : Colors.white.withValues(alpha: 0.20);

            final telemetryStrip = _TactileGlassBox(
              borderRadius: 16,
              fillColor: glassFill,
              borderColor: glassBorder,
              topSheenAlpha: palette.isLight ? 0.55 : 0.10,
              shadows: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: palette.isLight ? 0.08 : 0.40),
                  blurRadius: 24,
                  offset: const Offset(0, 8),
                ),
              ],
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _TelemetryCell(
                    label: lang == LangCode.tr ? 'ODA:' : 'ROOM:',
                    value: roomTemp != null ? '${roomTemp!.toStringAsFixed(1)}°C' : '--',
                    palette: palette,
                  ),
                  Text('|', style: TextStyle(color: dividerColor)),
                  _TelemetryCell(
                    label: lang == LangCode.tr ? 'BASINÇ:' : 'PRESS:',
                    value: sensors.isConnected && sensors.waterPressureBar != null
                        ? '${sensors.waterPressureBar!.toStringAsFixed(1)} Bar'
                        : '--',
                    palette: palette,
                  ),
                  Text('|', style: TextStyle(color: dividerColor)),
                  _TelemetryCell(
                    label: lang == LangCode.tr ? 'HEDEF:' : 'TARGET:',
                    value: '${targetTemp.toStringAsFixed(1)}°',
                    valueColor: accentColor,
                    palette: palette,
                  ),
                ],
              ),
            );

            final bool isHardwareLinked = espOnline && roomTemp != null && boiler.hasSensorReading;
            final String hardwareStatusText = !boiler.hasSensorReading || !espOnline
                ? (lang == LangCode.tr ? 'ESP32 Bağlı Değil' : 'ESP32 Offline')
                : (boiler.isHeating
                    ? (lang == LangCode.tr ? 'Kombi Aktif' : 'Heating')
                    : (lang == LangCode.tr ? 'Beklemede' : 'Idle'));
            final Widget? offlineStrip = !isHardwareLinked
                ? Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: palette.isLight ? 0.12 : 0.14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFFF59E0B).withValues(alpha: 0.38),
                        ),
                      ),
                      child: Row(
                        children: [
                          const Icon(
                            Icons.portable_wifi_off_rounded,
                            size: 13,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(
                              lang == LangCode.tr
                                  ? 'ESP32 / Kombi bağlantısı yok — canlı oda verisi okunamıyor (--)'
                                  : 'ESP32 / Boiler disconnected — live room sensor unavailable (--)',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: palette.isLight
                                    ? const Color(0xFF92400E)
                                    : const Color(0xFFFDE68A),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  )
                : null;

            final bottomMicroStrip = _TactileGlassBox(
              borderRadius: 12,
              fillColor: palette.isLight ? palette.cardBg : Colors.white.withValues(alpha: 0.032),
              borderColor: palette.isLight ? palette.cardBorder : Colors.white.withValues(alpha: 0.08),
              topSheenAlpha: palette.isLight ? 0.45 : 0.07,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.water_drop_outlined, size: 14, color: Color(0xFF38BDF8)),
                      const SizedBox(width: 6),
                      Text(
                        '${lang == LangCode.tr ? 'Ortam Nemi' : 'Humidity'}: ',
                        style: TextStyle(fontSize: 11, color: palette.textSecondary),
                      ),
                      Text(
                        sensors.roomHumidityPercent != null
                            ? '%${sensors.roomHumidityPercent!.round()}'
                            : '--',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  Text('·', style: TextStyle(color: dividerColor, fontWeight: FontWeight.w700)),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.speed_rounded, size: 14, color: Color(0xFFF59E0B)),
                      const SizedBox(width: 6),
                      Text(
                        '${lang == LangCode.tr ? 'Pompa' : 'Pump'}: ',
                        style: TextStyle(fontSize: 11, color: palette.textSecondary),
                      ),
                      Text(
                        sensors.pumpRpm != null ? '${sensors.pumpRpm} RPM' : '--',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          color: palette.textPrimary,
                          fontFeatures: const [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );

            if (isLandscape) {
              return Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 960),
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
                              dialRingStyle: dialRingStyle,
                              performanceMode: performanceMode,
                            ),
                          ),
                        ),
                        const SizedBox(width: 24),
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
                                    hardwareStatusText,
                                    style: TextStyle(
                                      fontSize: 11,
                                      fontWeight: !isHardwareLinked ? FontWeight.w600 : FontWeight.w400,
                                      color: !isHardwareLinked
                                          ? const Color(0xFFF59E0B)
                                          : palette.textSecondary,
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              telemetryStrip,
                              if (offlineStrip != null) offlineStrip,
                              const SizedBox(height: 12),
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
                              const SizedBox(height: 12),
                              bottomMicroStrip,
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
                                hardwareStatusText,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: !isHardwareLinked ? FontWeight.w600 : FontWeight.w400,
                                  color: !isHardwareLinked
                                      ? const Color(0xFFF59E0B)
                                      : palette.textSecondary,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          telemetryStrip,
                          if (offlineStrip != null) offlineStrip,
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
                        dialRingStyle: dialRingStyle,
                        performanceMode: performanceMode,
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

class _TactileGlassBox extends StatelessWidget {
  final double borderRadius;
  final Color? fillColor;
  final Gradient? gradient;
  final Color borderColor;
  final double topSheenAlpha;
  final List<BoxShadow>? shadows;
  final EdgeInsetsGeometry padding;
  final Widget child;

  const _TactileGlassBox({
    required this.borderRadius,
    this.fillColor,
    this.gradient,
    required this.borderColor,
    required this.topSheenAlpha,
    this.shadows,
    required this.padding,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    return Container(
      decoration: BoxDecoration(
        borderRadius: radius,
        color: gradient == null ? fillColor : null,
        gradient: gradient,
        border: Border.all(color: borderColor, width: 1.0),
        boxShadow: shadows,
      ),
      child: ClipRRect(
        borderRadius: radius,
        child: CustomPaint(
          painter: _TopRimHighlightPainter(
            radius: borderRadius,
            sheenAlpha: topSheenAlpha,
          ),
          child: Padding(
            padding: padding,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _TopRimHighlightPainter extends CustomPainter {
  final double radius;
  final double sheenAlpha;

  const _TopRimHighlightPainter({
    required this.radius,
    required this.sheenAlpha,
  });

  @override
  void paint(Canvas canvas, Size size) {
    if (sheenAlpha <= 0 || size.width <= 0 || size.height <= 0) return;
    final r = math.min(radius, math.min(size.width, size.height) / 2);

    // Subtle crisp inset top specular edge (simulates CSS inset 0 1px 0 rgba(255,255,255,...))
    final path = Path()
      ..moveTo(0.8, r)
      ..arcToPoint(Offset(r, 0.8), radius: Radius.circular(r), clockwise: true)
      ..lineTo(size.width - r, 0.8)
      ..arcToPoint(Offset(size.width - 0.8, r), radius: Radius.circular(r), clockwise: true);

    final rimPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.25
      ..shader = LinearGradient(
        begin: Alignment.centerLeft,
        end: Alignment.centerRight,
        colors: [
          Colors.white.withValues(alpha: sheenAlpha * 0.35),
          Colors.white.withValues(alpha: sheenAlpha),
          Colors.white.withValues(alpha: sheenAlpha * 0.35),
        ],
      ).createShader(Rect.fromLTWH(0, 0, size.width, 20));

    canvas.drawPath(path, rimPaint);

    // Soft top micro-wash for subtle tactile bevel depth
    final washRect = Rect.fromLTWH(0, 0, size.width, math.min(18.0, size.height * 0.35));
    final washPaint = Paint()
      ..shader = LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [
          Colors.white.withValues(alpha: sheenAlpha * 0.24),
          Colors.transparent,
        ],
      ).createShader(washRect);
    canvas.drawRect(washRect, washPaint);
  }

  @override
  bool shouldRepaint(covariant _TopRimHighlightPainter oldDelegate) =>
      oldDelegate.radius != radius || oldDelegate.sheenAlpha != sheenAlpha;
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
    final topColor = Color.lerp(preset.color, Colors.white, 0.08)!.withValues(alpha: 0.88);
    final bottomColor = Color.lerp(preset.color, Colors.black, 0.22)!.withValues(alpha: 0.68);
    final selectedBorder = Color.lerp(preset.color, Colors.white, 0.28)!.withValues(alpha: 0.92);

    return TactilePress.card(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(20),
          gradient: selected
              ? LinearGradient(
                  begin: const Alignment(-0.35, -1.0),
                  end: const Alignment(0.35, 1.0),
                  colors: [topColor, bottomColor],
                )
              : null,
          color: selected
              ? null
              : (palette.isLight ? palette.cardBg : Colors.white.withValues(alpha: 0.048)),
          border: Border.all(
            color: selected
                ? selectedBorder
                : (palette.isLight ? palette.cardBorder : Colors.white.withValues(alpha: 0.10)),
            width: 1.0,
          ),
          boxShadow: selected
              ? [
                  BoxShadow(
                    color: preset.color.withValues(alpha: 0.34),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.32),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ]
              : [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: palette.isLight ? 0.06 : 0.25),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(20),
          child: CustomPaint(
            painter: _TopRimHighlightPainter(
              radius: 20,
              sheenAlpha: selected ? 0.42 : (palette.isLight ? 0.55 : 0.10),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
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
                      color: fg.withValues(alpha: 0.86),
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
      ),
    );
  }
}
