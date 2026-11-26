import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/thermostat_state.dart';
import '../widgets/dial_ring_effects.dart';
import '../widgets/rotary_dial.dart';
import '../widgets/tactile_button.dart';

Future<void> showThemeEffectsSheet({
  required BuildContext context,
  required LangCode lang,
  required Color accentColor,
  required bool hapticEnabled,
  required VisualCustomizationState initialVisual,
  required ValueChanged<VisualCustomizationState> onUpdateVisual,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _ThemeEffectsModal(
      lang: lang,
      accentColor: accentColor,
      hapticEnabled: hapticEnabled,
      initialVisual: initialVisual,
      onUpdateVisual: onUpdateVisual,
    ),
  );
}

class _ThemeEffectsModal extends StatefulWidget {
  final LangCode lang;
  final Color accentColor;
  final bool hapticEnabled;
  final VisualCustomizationState initialVisual;
  final ValueChanged<VisualCustomizationState> onUpdateVisual;

  const _ThemeEffectsModal({
    required this.lang,
    required this.accentColor,
    required this.hapticEnabled,
    required this.initialVisual,
    required this.onUpdateVisual,
  });

  @override
  State<_ThemeEffectsModal> createState() => _ThemeEffectsModalState();
}

class _ThemeEffectsModalState extends State<_ThemeEffectsModal>
    with SingleTickerProviderStateMixin {
  late VisualCustomizationState _visual;
  late final AnimationController _dialPreviewCtrl;
  double _previewTemp = 23.5;

  @override
  void initState() {
    super.initState();
    _visual = widget.initialVisual;
    _dialPreviewCtrl = AnimationController(
      vsync: this,
      duration: _previewDuration(_visual.performanceMode),
    )..repeat();
  }

  Duration _previewDuration(PerformanceMode mode) =>
      mode == PerformanceMode.ecoBattery
          ? const Duration(seconds: 10)
          : const Duration(seconds: 6);

  @override
  void dispose() {
    _dialPreviewCtrl.dispose();
    super.dispose();
  }

  void _apply(VisualCustomizationState next) {
    if (widget.hapticEnabled) HapticFeedback.selectionClick();
    TactileMotionScope.globalEnabled.value = next.buttonTactileFeedback;
    final wantedDur = _previewDuration(next.performanceMode);
    if (_dialPreviewCtrl.duration != wantedDur) {
      _dialPreviewCtrl.duration = wantedDur;
      _dialPreviewCtrl.repeat();
    }
    setState(() => _visual = next);
    widget.onUpdateVisual(next);
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;
    final tr = widget.lang == LangCode.tr;
    final palette = _visual.resolvePalette();
    final sheetBg = palette.sheetBg;
    final textMain = palette.textPrimary;
    final textSub = palette.textSecondary;

    final themeItems = [
      (
        AppThemeMode.liquidGlass,
        tr ? 'Canlı Cam (Liquid Glass)' : 'Liquid Glass',
        tr ? 'Saydam Buzlu Cam' : 'Translucent Glass',
        tr
            ? 'Yarı saydam buzlu cam yüzeyler, kenar kırılımı ve arkadaki canlı hava efektleri.'
            : 'Translucent frosted surfaces, prismatic rim refraction, and live weather aura.',
        Icons.auto_awesome_rounded,
        const Color(0xFF38BDF8),
      ),
      (
        AppThemeMode.darkNight,
        tr ? 'Karanlık Gece Modu' : 'Dark Night Mode',
        tr ? 'OLED Siyah' : 'OLED Black',
        tr
            ? 'Derin siyah ve lacivert tonlarıyla gece kullanımı, göz konforu ve enerji tasarrufu.'
            : 'Deep obsidian black & navy palette for eye comfort and AMOLED battery savings.',
        Icons.nightlight_round,
        const Color(0xFF6366F1),
      ),
      (
        AppThemeMode.lightDay,
        tr ? 'Aydınlık Gündüz Modu' : 'Light Day Mode',
        tr ? 'Gün Işığı' : 'Daylight',
        tr
            ? 'Gündüz yüksek okunabilirlik, kristal beyaz & gökyüzü mavisi ferah estetik.'
            : 'High daylight legibility with crisp crystal white & sky blue accents.',
        Icons.wb_sunny_rounded,
        const Color(0xFF0EA5E9),
      ),
      (
        AppThemeMode.autoSmart,
        tr ? 'Akıllı Otomatik Mod (Sistem & Saat)' : 'Smart Auto Mode (Clock)',
        tr ? 'Gün Doğumu/Batımı' : 'Auto Day/Night',
        tr
            ? 'Günün saatine ve gün batımına göre otomatik yumuşak gece/gündüz geçişi.'
            : 'Automatic smooth transition between daylight and night based on clock hours.',
        Icons.brightness_auto_rounded,
        const Color(0xFF10B981),
      ),
      (
        AppThemeMode.obsidianLavender,
        'Obsidian Lavender (Pastel Lila & Kadife)',
        tr ? 'Deneysel Lüks' : 'Experimental Luxury',
        tr
            ? 'Obsidyen siyahı üzerine kadife lila cam yüzeyler ve yumuşak pastel aksan ışığı.'
            : 'Velvet lavender glass layers over obsidian black with soft pastel highlights.',
        Icons.diamond_outlined,
        const Color(0xFFC084FC),
      ),
      (
        AppThemeMode.tactileDeck,
        'Tactile Deck (Hi-Fi Donanım Konsolu)',
        tr ? 'Özel • 3D Donanım' : 'Special • 3D Hardware',
        tr
            ? 'Fiziksel metal kadran, 3D mekanik dokunuşlar ve sıcak akkor ışık halesi.'
            : 'Brushed metallic dial, tactile mechanical contrast, and warm incandescent aura.',
        Icons.radio_button_checked_rounded,
        const Color(0xFFF59E0B),
      ),
    ];

    final obsidianSwatches = [
      (ObsidianPalette.pastelLavender, tr ? 'Pastel Lavanta' : 'Pastel Lavender', const Color(0xFFC084FC)),
      (ObsidianPalette.dustyLilac, tr ? 'Kül Leylak' : 'Dusty Lilac', const Color(0xFFAD8AE0)),
      (ObsidianPalette.royalViolet, tr ? 'Kraliyet İndigo' : 'Royal Violet', const Color(0xFF8B5CF6)),
      (ObsidianPalette.deepObsidian, tr ? 'Derin Obsidyen' : 'Deep Obsidian', const Color(0xFF9490B8)),
    ];

    final weatherChips = [
      (WeatherEffectPreview.live, tr ? 'Canlı (İstanbul)' : 'Live (Istanbul)', Icons.my_location_rounded),
      (WeatherEffectPreview.sunny, tr ? 'Güneşli' : 'Sunny', Icons.wb_sunny_outlined),
      (WeatherEffectPreview.partlyCloudy, tr ? 'Parçalı Bulut' : 'Partly Cloudy', Icons.wb_cloudy_outlined),
      (WeatherEffectPreview.rainy, tr ? 'Yağmurlu' : 'Rainy', Icons.umbrella_outlined),
      (WeatherEffectPreview.snowy, tr ? 'Karlı' : 'Snowy', Icons.ac_unit_rounded),
      (WeatherEffectPreview.foggy, tr ? 'Sisli' : 'Foggy', Icons.blur_on_rounded),
    ];

    return Container(
      height: media.size.height * (isLandscape ? 0.94 : 0.90),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 700 : 480),
        child: Container(
          decoration: BoxDecoration(
            color: sheetBg.withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: palette.cardBorder),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.65), blurRadius: 36, offset: const Offset(0, -10)),
            ],
          ),
          child: Column(
            children: [
              // Sticky Header
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 16, 14, 10),
                child: Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        color: widget.accentColor.withValues(alpha: 0.16),
                        border: Border.all(color: widget.accentColor.withValues(alpha: 0.40)),
                      ),
                      child: Icon(Icons.palette_outlined, color: widget.accentColor, size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  tr ? 'Tema & Görsel Efektler' : 'Themes & Visual Effects',
                                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: textMain),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                decoration: BoxDecoration(
                                  color: const Color(0xFF10B981).withValues(alpha: 0.18),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                                ),
                                child: Text(
                                  tr ? 'anlık canlı uygulanır' : 'live preview',
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Color(0xFF10B981)),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr
                                ? 'Arayüz atmosferini, FPS performansını ve hava efektlerini seçin'
                                : 'Customize theme atmosphere, FPS mode & live weather effects',
                            style: TextStyle(fontSize: 11.5, color: textSub),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    TactilePress(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: palette.cardBg,
                          side: BorderSide(color: palette.cardBorder),
                        ),
                        icon: Icon(Icons.close_rounded, color: textMain, size: 19),
                      ),
                    ),
                  ],
                ),
              ),

              Divider(height: 1, color: palette.cardBorder),

              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                  children: [
                    Text(
                      tr ? 'ARAYÜZ TEMASI' : 'INTERFACE THEME',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: textSub),
                    ),
                    const SizedBox(height: 8),

                    for (final item in themeItems) ...[
                      _ThemeCard(
                        title: item.$2,
                        badge: item.$3,
                        description: item.$4,
                        icon: item.$5,
                        swatchColor: item.$6,
                        selected: _visual.theme == item.$1,
                        palette: palette,
                        onTap: () => _apply(_visual.copyWith(theme: item.$1)),
                      ),
                      if (item.$1 == AppThemeMode.obsidianLavender &&
                          _visual.theme == AppThemeMode.obsidianLavender)
                        Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            color: const Color(0xFFC084FC).withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: const Color(0xFFC084FC).withValues(alpha: 0.30)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                tr ? 'Alt Renk Paleti (Obsidian Lavender)' : 'Sub-Color Palette (Obsidian Lavender)',
                                style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: textMain),
                              ),
                              const SizedBox(height: 8),
                              GridView.count(
                                shrinkWrap: true,
                                physics: const NeverScrollableScrollPhysics(),
                                crossAxisCount: 2,
                                crossAxisSpacing: 8,
                                mainAxisSpacing: 8,
                                childAspectRatio: 3.3,
                                children: [
                                  for (final sw in obsidianSwatches)
                                    TactilePress(
                                      child: GestureDetector(
                                        onTap: () => _apply(_visual.copyWith(obsidianPalette: sw.$1)),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10),
                                          decoration: BoxDecoration(
                                            color: _visual.obsidianPalette == sw.$1
                                                ? sw.$3.withValues(alpha: 0.22)
                                                : palette.cardBg,
                                            borderRadius: BorderRadius.circular(12),
                                            border: Border.all(
                                              color: _visual.obsidianPalette == sw.$1 ? sw.$3 : palette.cardBorder,
                                            ),
                                          ),
                                          child: Row(
                                            children: [
                                              Container(
                                                width: 14,
                                                height: 14,
                                                decoration: BoxDecoration(shape: BoxShape.circle, color: sw.$3),
                                              ),
                                              const SizedBox(width: 8),
                                              Expanded(
                                                child: Text(
                                                  sw.$2,
                                                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: textMain),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),
                                ],
                              ),
                            ],
                          ),
                        ),
                    ],

                    const SizedBox(height: 14),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Text(
                            tr
                                ? 'TERMOSTAT ÇEMBERİ TEMALARI (CANLI ÖNİZLEME)'
                                : 'DIAL RING THEMES (LIVE PREVIEW)',
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.0,
                              color: textSub,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        TactilePress(
                          child: GestureDetector(
                            onTap: () => _apply(
                              _visual.copyWith(
                                dialRingStyle: DialRingStyle.classic,
                              ),
                            ),
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 9,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: _visual.dialRingStyle ==
                                        DialRingStyle.classic
                                    ? widget.accentColor.withValues(alpha: 0.20)
                                    : palette.cardBg,
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: _visual.dialRingStyle ==
                                          DialRingStyle.classic
                                      ? widget.accentColor
                                      : palette.cardBorder,
                                ),
                              ),
                              child: Text(
                                tr ? 'Klasik' : 'Classic',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: _visual.dialRingStyle ==
                                          DialRingStyle.classic
                                      ? widget.accentColor
                                      : textSub,
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Interactive Large Stage Preview of the Active Dial Theme
                    () {
                      final activeAccent =
                          palette.themeOverrideAccent?.toColor() ??
                              widget.accentColor;
                      final activeMeta =
                          DialRingStyleInfo.findDynamic(_visual.dialRingStyle);
                      final stageBoiler =
                          ThermostatMath.computeBoilerTelemetry(
                        21.0,
                        _previewTemp,
                      );
                      final stageFlame = stageBoiler.isHeating
                          ? (stageBoiler.flamePercent / 100.0).clamp(0.18, 1.0)
                          : 0.0;
                      final testPresets = [
                        (tr ? 'Sönük (18°)' : 'Pilot (18°)', 18.0),
                        (tr ? 'Mavi Alev (22.5°)' : 'Blue Gas (22.5°)', 22.5),
                        (tr ? 'Harlı / Redline (28.5°)' : 'Roar (28.5°)', 28.5),
                      ];

                      return Column(
                        children: [
                          Container(
                            margin: const EdgeInsets.only(bottom: 10),
                            padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
                            decoration: BoxDecoration(
                              color: palette.cardBg,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                color: activeMeta != null
                                    ? activeMeta.swatchColor
                                        .withValues(alpha: 0.45)
                                    : palette.cardBorder,
                              ),
                            ),
                            child: Column(
                              children: [
                                Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Flexible(
                                      child: Text(
                                        activeMeta != null
                                            ? (tr
                                                ? activeMeta.titleTr
                                                : activeMeta.titleEn)
                                            : (tr
                                                ? 'Klasik Kadran (Standart)'
                                                : 'Classic Dial (Standard)'),
                                        style: TextStyle(
                                          fontSize: 12.5,
                                          fontWeight: FontWeight.w700,
                                          color: textMain,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      tr
                                          ? 'Sürükle veya dene'
                                          : 'Drag or test below',
                                      style: TextStyle(
                                        fontSize: 10.5,
                                        color: textSub,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Center(
                                  child: RotaryDial(
                                    targetTemp: _previewTemp,
                                    onChangeTarget: (t) =>
                                        setState(() => _previewTemp = t),
                                    modeName: tr
                                        ? 'CANLI ÖNİZLEME'
                                        : 'LIVE PREVIEW',
                                    accentColor: activeMeta?.swatchColor ??
                                        activeAccent,
                                    boiler: stageBoiler,
                                    lang: widget.lang,
                                    palette: palette,
                                    sizePx: isLandscape ? 186.0 : 178.0,
                                    compact: true,
                                    dialRingStyle: _visual.dialRingStyle,
                                    performanceMode: _visual.performanceMode,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    for (int p = 0; p < testPresets.length; p++) ...[
                                      if (p > 0) const SizedBox(width: 6),
                                      Expanded(
                                        child: TactilePress(
                                          child: GestureDetector(
                                            onTap: () => setState(() =>
                                                _previewTemp = testPresets[p].$2),
                                            child: Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                horizontal: 6,
                                                vertical: 6,
                                              ),
                                              decoration: BoxDecoration(
                                                color: (_previewTemp -
                                                                testPresets[p]
                                                                    .$2)
                                                            .abs() <
                                                        0.3
                                                    ? (activeMeta?.swatchColor ??
                                                            activeAccent)
                                                        .withValues(alpha: 0.22)
                                                    : palette.scaffoldBg
                                                        .withValues(alpha: 0.45),
                                                borderRadius:
                                                    BorderRadius.circular(10),
                                                border: Border.all(
                                                  color: (_previewTemp -
                                                                  testPresets[p]
                                                                      .$2)
                                                              .abs() <
                                                          0.3
                                                      ? (activeMeta
                                                              ?.swatchColor ??
                                                          activeAccent)
                                                      : palette.cardBorder,
                                                ),
                                              ),
                                              child: Text(
                                                testPresets[p].$1,
                                                textAlign: TextAlign.center,
                                                maxLines: 1,
                                                overflow: TextOverflow.ellipsis,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700,
                                                  color: textMain,
                                                ),
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ],
                                ),
                              ],
                            ),
                          ),

                          // Live Animated Full-Dial Theme Cards (Boiler Flame, Motorsport Gauge, Liquid Chamber)
                          for (final ringInfo in DialRingStyleInfo.dynamicThemes)
                            _DialRingStyleCard(
                              info: ringInfo,
                              lang: widget.lang,
                              selected:
                                  _visual.dialRingStyle == ringInfo.style,
                              palette: palette,
                              animation: _dialPreviewCtrl,
                              previewTemp: _previewTemp,
                              flameIntensity: stageFlame,
                              onTap: () => _apply(
                                _visual.copyWith(dialRingStyle: ringInfo.style),
                              ),
                            ),
                        ],
                      );
                    }(),

                    const SizedBox(height: 10),
                    Text(
                      tr ? 'CİHAZ PERFORMANSI & FPS MODU' : 'DEVICE PERFORMANCE & FPS MODE',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: textSub),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _PerfCard(
                            title: tr ? 'Ultra Canavar Modu' : 'Ultra Smooth Mode',
                            badge: '60 FPS',
                            subtitle: tr ? 'Tam akışkan shader ve canlı hava partikülleri' : 'Full GLSL shader & weather particles',
                            selected: _visual.performanceMode == PerformanceMode.ultra60fps,
                            color: const Color(0xFF38BDF8),
                            palette: palette,
                            onTap: () => _apply(_visual.copyWith(performanceMode: PerformanceMode.ultra60fps)),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: _PerfCard(
                            title: tr ? 'Eco Tasarruf (Sıfır Kasma)' : 'Eco Battery (Zero Lag)',
                            badge: tr ? 'PİL KORUMA' : 'BATTERY',
                            subtitle: tr ? 'Düşük GPU yükü ve durağan arka plan' : 'Throttled FPS & lightweight backdrop',
                            selected: _visual.performanceMode == PerformanceMode.ecoBattery,
                            color: const Color(0xFF10B981),
                            palette: palette,
                            onTap: () => _apply(_visual.copyWith(performanceMode: PerformanceMode.ecoBattery)),
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Text(
                      tr ? 'ARKA PLAN HAVA EFEKTİNİ ÖNİZLE' : 'PREVIEW BACKGROUND WEATHER EFFECT',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: textSub),
                    ),
                    const SizedBox(height: 8),
                    GridView.count(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      crossAxisCount: isLandscape ? 3 : 2,
                      crossAxisSpacing: 8,
                      mainAxisSpacing: 8,
                      childAspectRatio: 3.1,
                      children: [
                        for (final w in weatherChips)
                          TactilePress(
                            child: GestureDetector(
                              onTap: () => _apply(_visual.copyWith(weatherPreview: w.$1)),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: _visual.weatherPreview == w.$1
                                      ? widget.accentColor.withValues(alpha: 0.20)
                                      : palette.cardBg,
                                  borderRadius: BorderRadius.circular(14),
                                  border: Border.all(
                                    color: _visual.weatherPreview == w.$1 ? widget.accentColor : palette.cardBorder,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      w.$3,
                                      size: 16,
                                      color: _visual.weatherPreview == w.$1 ? widget.accentColor : textSub,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        w.$2,
                                        style: TextStyle(
                                          fontSize: 11.5,
                                          fontWeight: FontWeight.w600,
                                          color: textMain,
                                        ),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),

                    const SizedBox(height: 16),
                    Text(
                      tr ? 'ETKİLEŞİM & HOVER ANİMASYONU (DENEYSEL)' : 'TACTILE HOVER & PRESS (EXPERIMENTAL)',
                      style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, letterSpacing: 1.0, color: textSub),
                    ),
                    const SizedBox(height: 8),
                    TactilePress.card(
                      child: GestureDetector(
                        onTap: () => _apply(
                          _visual.copyWith(buttonTactileFeedback: !_visual.buttonTactileFeedback),
                        ),
                        child: AnimatedContainer(
                          duration: const Duration(milliseconds: 180),
                          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 11),
                          decoration: BoxDecoration(
                            color: _visual.buttonTactileFeedback
                                ? widget.accentColor.withValues(alpha: 0.14)
                                : palette.cardBg,
                            borderRadius: BorderRadius.circular(18),
                            border: Border.all(
                              color: _visual.buttonTactileFeedback ? widget.accentColor : palette.cardBorder,
                              width: _visual.buttonTactileFeedback ? 1.4 : 1.0,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 38,
                                height: 38,
                                decoration: BoxDecoration(
                                  borderRadius: BorderRadius.circular(12),
                                  color: widget.accentColor.withValues(alpha: 0.18),
                                  border: Border.all(color: widget.accentColor.withValues(alpha: 0.38)),
                                ),
                                child: Icon(
                                  Icons.touch_app_rounded,
                                  color: widget.accentColor,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        Flexible(
                                          child: Text(
                                            tr ? 'Kabarma & Odak Blur Hissi' : 'Tactile Swell & Focus Blur',
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: textMain),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                                            borderRadius: BorderRadius.circular(6),
                                          ),
                                          child: Text(
                                            tr ? 'Deneysel' : 'Test',
                                            style: const TextStyle(
                                              fontSize: 9.5,
                                              fontWeight: FontWeight.w700,
                                              color: Color(0xFFFBBF24),
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      tr
                                          ? 'Butonlarda kabarma/basma hissi; termostat kadranına gelince veya basınca çevreye hafif blur.'
                                          : 'Button swell/press feedback plus subtle surrounding blur when hovering or pressing the thermostat dial.',
                                      style: TextStyle(fontSize: 11, color: textSub),
                                      maxLines: 2,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                              const SizedBox(width: 8),
                              Switch(
                                value: _visual.buttonTactileFeedback,
                                activeColor: widget.accentColor,
                                onChanged: (v) => _apply(_visual.copyWith(buttonTactileFeedback: v)),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // Footer
              Container(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + media.padding.bottom),
                decoration: BoxDecoration(
                  color: sheetBg,
                  border: Border(top: BorderSide(color: palette.cardBorder)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      _visual.performanceMode == PerformanceMode.ultra60fps
                          ? '60 FPS • ${tr ? 'Canlı Efektler' : 'Live Effects'}'
                          : 'ECO • ${tr ? 'Pil Korumalı' : 'Battery Saver'}',
                      style: TextStyle(fontSize: 11.5, color: textSub),
                    ),
                    TactilePress(
                      child: FilledButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: FilledButton.styleFrom(
                          backgroundColor: widget.accentColor,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 11),
                        ),
                        child: Text(
                          tr ? 'Tamam & Kapat' : 'Done & Close',
                          style: const TextStyle(fontWeight: FontWeight.w700),
                        ),
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
}

class _ThemeCard extends StatelessWidget {
  final String title;
  final String badge;
  final String description;
  final IconData icon;
  final Color swatchColor;
  final bool selected;
  final ThemePaletteSpec palette;
  final VoidCallback onTap;

  const _ThemeCard({
    required this.title,
    required this.badge,
    required this.description,
    required this.icon,
    required this.swatchColor,
    required this.selected,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TactilePress.card(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? swatchColor.withValues(alpha: 0.14) : palette.cardBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
            color: selected ? swatchColor : palette.cardBorder,
            width: selected ? 1.5 : 1.0,
          ),
        ),
        child: Row(
          children: [
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                color: swatchColor.withValues(alpha: 0.16),
                border: Border.all(color: swatchColor.withValues(alpha: 0.35)),
              ),
              child: Icon(icon, color: swatchColor, size: 19),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          title,
                          style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: palette.textPrimary),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: swatchColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: swatchColor),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    description,
                    style: TextStyle(fontSize: 11, color: palette.textSecondary),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Icon(
              selected ? Icons.check_circle_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? swatchColor : palette.textSecondary,
              size: 20,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _PerfCard extends StatelessWidget {
  final String title;
  final String badge;
  final String subtitle;
  final bool selected;
  final Color color;
  final ThemePaletteSpec palette;
  final VoidCallback onTap;

  const _PerfCard({
    required this.title,
    required this.badge,
    required this.subtitle,
    required this.selected,
    required this.color,
    required this.palette,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return TactilePress.card(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: selected ? color.withValues(alpha: 0.16) : palette.cardBg,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: selected ? color : palette.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.20),
                    borderRadius: BorderRadius.circular(7),
                  ),
                  child: Text(badge, style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: color)),
                ),
                if (selected) Icon(Icons.check_circle_rounded, size: 16, color: color),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              title,
              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: palette.textPrimary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              style: TextStyle(fontSize: 10.5, color: palette.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

class _DialRingStyleCard extends StatelessWidget {
  final DialRingStyleInfo info;
  final LangCode lang;
  final bool selected;
  final ThemePaletteSpec palette;
  final Animation<double> animation;
  final double previewTemp;
  final double flameIntensity;
  final VoidCallback onTap;

  const _DialRingStyleCard({
    required this.info,
    required this.lang,
    required this.selected,
    required this.palette,
    required this.animation,
    required this.previewTemp,
    required this.flameIntensity,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final tr = lang == LangCode.tr;
    return TactilePress.card(
      child: GestureDetector(
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.only(bottom: 9),
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: selected
                ? info.swatchColor.withValues(alpha: 0.14)
                : palette.cardBg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? info.swatchColor : palette.cardBorder,
              width: selected ? 1.5 : 1.0,
            ),
          ),
          child: Row(
            children: [
              DialRingPreviewThumb(
                style: info.style,
                animation: animation,
                sizePx: 76.0,
                accentColor: info.swatchColor,
                palette: palette,
                targetTemp: previewTemp,
                flameIntensity: flameIntensity,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            tr ? info.titleTr : info.titleEn,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: palette.textPrimary,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: info.swatchColor.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            tr ? info.badgeTr : info.badgeEn,
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w700,
                              color: info.swatchColor,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      tr ? info.descriptionTr : info.descriptionEn,
                      style: TextStyle(
                        fontSize: 11,
                        color: palette.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(
                selected
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: selected ? info.swatchColor : palette.textSecondary,
                size: 20,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
