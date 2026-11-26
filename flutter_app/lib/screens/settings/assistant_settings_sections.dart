part of '../settings_sheet.dart';

extension _AssistantSettingsBuilders on _SystemSettingsModalState {
  Widget _buildTermoBotPanel(bool tr) {
    const idleOptions = [(15, '15 sn'), (30, '30 sn'), (60, '1 dk'), (120, '2 dk'), (300, '5 dk')];
    final bgOptions = [
      (ScreensaverBackdrop.oledBlack, tr ? 'Saf OLED Siyah' : 'Pure OLED Black', tr ? 'Tam karanlık' : 'True dark', const Color(0xFF18181B)),
      (ScreensaverBackdrop.termoLab, 'Termo Lab', tr ? 'Siber mavi grid' : 'Cyber blue grid', const Color(0xFF0C4A6E)),
      (ScreensaverBackdrop.warmHearth, tr ? 'Sıcak Köşe' : 'Warm Hearth', tr ? 'Köz ve şömine' : 'Embers & hearth', const Color(0xFF7C2D12)),
      (ScreensaverBackdrop.nightNebula, 'Gece Nebula', tr ? 'Derin obsidyen' : 'Deep obsidian', const Color(0xFF3B0764)),
      (ScreensaverBackdrop.custom, tr ? 'Özel / Cihaz' : 'Custom / Accent', tr ? 'Resim & URL' : 'Image & URL', widget.accentColor),
    ];
    final behaviorOptions = [
      (MascotBehavior.idle, tr ? 'Boşta' : 'Idle', Icons.circle, const Color(0xFF22C55E)),
      (MascotBehavior.patrol, tr ? 'Gezinme' : 'Patrol', Icons.directions_walk_rounded, const Color(0xFF38BDF8)),
      (MascotBehavior.knock, tr ? 'Tık Tık' : 'Knock', Icons.touch_app_rounded, const Color(0xFFFBBF24)),
      (MascotBehavior.think, tr ? 'Düşünme' : 'Think', Icons.lightbulb_outline_rounded, const Color(0xFFF59E0B)),
      (MascotBehavior.read, tr ? 'Kitap' : 'Read', Icons.menu_book_rounded, const Color(0xFFA78BFA)),
      (MascotBehavior.deepSleep, tr ? 'Derin Uyku' : 'Deep Sleep', Icons.nightlight_round, const Color(0xFF60A5FA)),
    ];
    final activeMascotMeta = MascotMeta.of(_draft.mascotCharacter);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SettingsMiniToggleTile(
          label: tr
              ? '🤖 Maskot Ekran Koruyucu (Otomatik Mod)'
              : '🤖 Mascot Screensaver (Auto Mode)',
          value: _draft.termoBotEnabled,
          activeColor: const Color(0xFFEA580C),
          onTap: () {
            _hapticTap();
            final nextBot = !_draft.termoBotEnabled;
            _updateState(() => _draft = _draft.copyWith(
              termoBotEnabled: nextBot,
              smartDisplayEnabled: nextBot ? false : _draft.smartDisplayEnabled,
            ));
          },
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            SettingsInfoBadge(
              text: '${activeMascotMeta.name} (${tr ? activeMascotMeta.roleTr : activeMascotMeta.roleEn})',
              color: activeMascotMeta.color,
            ),
            SettingsInfoBadge(
              text: tr ? 'Bekleme: ${_draft.screensaverIdleSeconds} sn' : 'Idle: ${_draft.screensaverIdleSeconds}s',
              color: const Color(0xFFF59E0B),
            ),
            SettingsInfoBadge(
              text: tr ? 'Boyut: %${(_draft.mascotScale * 100).round()}' : 'Size: ${(_draft.mascotScale * 100).round()}%',
              color: const Color(0xFF10B981),
            ),
            SettingsInfoBadge(
              text: _draft.screensaverBlurBg ? (tr ? 'Cam Blur: Açık' : 'Glass Blur: On') : (tr ? 'Cam Blur: Kapalı' : 'Glass Blur: Off'),
              color: _draft.screensaverBlurBg ? const Color(0xFF38BDF8) : const Color(0xFF9CA3AF),
            ),
          ],
        ),
        const SizedBox(height: 10),
        TactilePress.card(
          child: OutlinedButton.icon(
            onPressed: () {
              _hapticTap();
              widget.onSaveSettings(_draft);
              Navigator.of(context).pop();
              widget.onOpenScreensaverPreview();
            },
            icon: const Icon(Icons.play_arrow_rounded, size: 18, color: Color(0xFFFBBF24)),
            label: Text(
              tr ? 'Ekran Koruyucuyu Şimdi Başlat (Önizle)' : 'Launch Screensaver Preview',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: Colors.white.withValues(alpha: 0.05),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
              padding: const EdgeInsets.symmetric(vertical: 10),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr ? 'Maskot Karakteri Seçimi (3D Unreal):' : 'Mascot Character (3D Unreal):',
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 102,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: MascotCharacter.values.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              final ch = MascotCharacter.values[idx];
              final meta = MascotMeta.of(ch);
              final selected = _draft.mascotCharacter == ch;
              return TactilePress.card(
                child: GestureDetector(
                  onTap: () {
                    _hapticTap();
                    _updateState(() => _draft = _draft.copyWith(mascotCharacter: ch));
                    if (_draft.mascotSoundsEnabled) {
                      AmbientAudioService.playMascotSound(ch);
                    }
                  },
                  child: Container(
                    width: 92,
                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                    decoration: BoxDecoration(
                      color: selected ? meta.color.withValues(alpha: 0.18) : Colors.white.withValues(alpha: 0.04),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? meta.color : Colors.white.withValues(alpha: 0.10),
                      ),
                    ),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        MascotAvatar(
                          character: ch,
                          size: 46,
                          happy: selected,
                          showBehaviorOverlay: false,
                          frameless: false,
                        ),
                        const SizedBox(height: 5),
                        Text(meta.name, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white)),
                        Text(
                          tr ? meta.roleTr : meta.roleEn,
                          style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.58)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 12),
        Text(
          tr ? 'Otomatik Devreye Girme Süresi (Boşta Kalma):' : 'Idle Timeout:',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.80)),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            for (final opt in idleOptions) ...[
              Expanded(
                child: TactilePress(
                  child: GestureDetector(
                    onTap: () {
                      _hapticTap();
                      _updateState(() => _draft = _draft.copyWith(screensaverIdleSeconds: opt.$1));
                    },
                    child: Container(
                      margin: const EdgeInsets.only(right: 4),
                      padding: const EdgeInsets.symmetric(vertical: 7),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _draft.screensaverIdleSeconds == opt.$1
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.22)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: _draft.screensaverIdleSeconds == opt.$1
                              ? const Color(0xFFF59E0B)
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Text(
                        opt.$2,
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 12),
        Text(
          tr ? 'Ekran Koruyucu Arka Planı (Önizlemeli):' : 'Screensaver Backdrop:',
          style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.80)),
        ),
        const SizedBox(height: 7),
        SizedBox(
          height: 78,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: bgOptions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 8),
            itemBuilder: (_, idx) {
              final bg = bgOptions[idx];
              final selected = _draft.screensaverBackdrop == bg.$1;
              return TactilePress.card(
                child: GestureDetector(
                  onTap: () {
                    _hapticTap();
                    _updateState(() => _draft = _draft.copyWith(screensaverBackdrop: bg.$1));
                  },
                  child: Container(
                    width: 96,
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: bg.$4.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: selected ? const Color(0xFFFBBF24) : Colors.white.withValues(alpha: 0.12),
                        width: selected ? 1.6 : 1.0,
                      ),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          bg.$2,
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 2),
                        Text(
                          bg.$3,
                          style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.65)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SettingsMiniToggleTile(
                label: tr ? 'Arka Plan Blur' : 'Blur Background',
                value: _draft.screensaverBlurBg,
                activeColor: const Color(0xFFF59E0B),
                onTap: () {
                  _hapticTap();
                  _updateState(() => _draft = _draft.copyWith(screensaverBlurBg: !_draft.screensaverBlurBg));
                },
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: SettingsMiniToggleTile(
                label: tr ? 'Maskot Sesleri' : 'Mascot Sounds',
                value: _draft.mascotSoundsEnabled,
                activeColor: const Color(0xFF10B981),
                onTap: () {
                  _hapticTap();
                  final next = !_draft.mascotSoundsEnabled;
                  _updateState(() => _draft = _draft.copyWith(mascotSoundsEnabled: next));
                  if (next) {
                    AmbientAudioService.playMascotSound(_draft.mascotCharacter);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        // Custom wallpaper upload (device image + https URL)
        Row(
          children: [
            Expanded(
              flex: 11,
              child: TactilePress.card(
                child: ElevatedButton.icon(
                  onPressed: () async {
                    _hapticTap();
                    try {
                      final res = await FilePicker.platform.pickFiles(
                        type: FileType.image,
                        withData: true,
                      );
                      if (res != null && res.files.isNotEmpty) {
                        final file = res.files.first;
                        if (file.bytes != null && file.bytes!.isNotEmpty) {
                          final ext = (file.extension ?? 'jpg').toLowerCase();
                          final mime = ext == 'png'
                              ? 'image/png'
                              : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
                          final persistedBg = await MediaStorageService.persistPickedFile(
                            key: MediaStorageService.screensaverBgKey,
                            sourcePath: kIsWeb ? null : file.path,
                            bytes: file.bytes!,
                            mimeType: mime,
                            fileName: file.name,
                          );
                          final source = persistedBg.isNotEmpty
                              ? persistedBg
                              : 'data:$mime;base64,${base64Encode(file.bytes!)}';
                          if (!mounted) return;
                          _updateState(() {
                            _screensaverBgUrlCtrl.clear();
                            _draft = _draft.copyWith(
                              screensaverBackdrop: ScreensaverBackdrop.custom,
                              screensaverCustomBgSource: source,
                              screensaverCustomBgLabel: file.name,
                            );
                            _statusBanner = tr ? 'Duvar kağıdı kalıcı kaydedildi: ${file.name}' : 'Wallpaper saved: ${file.name}';
                          });
                          widget.onSaveSettings(_draft);
                        }
                      }
                    } catch (_) {
                      if (mounted) {
                        _updateState(() {
                          _statusBanner = tr ? 'Görsel seçilemedi.' : 'Could not pick image.';
                        });
                      }
                    }
                  },
                  icon: const Icon(Icons.upload_rounded, size: 16),
                  label: Text(
                    tr ? 'Cihazdan Resim / Duvar Kağıdı Seç' : 'Pick Wallpaper Image',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF4F6BFF),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              flex: 10,
              child: TextField(
                controller: _screensaverBgUrlCtrl,
                style: const TextStyle(fontSize: 11, color: Colors.white),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: tr ? 'Veya Görsel URL (https://..)' : 'Or Image URL (https://..)',
                  hintStyle: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.45)),
                  filled: true,
                  fillColor: Colors.white.withValues(alpha: 0.05),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            TactilePress(
              child: ElevatedButton(
                onPressed: () {
                  _hapticTap();
                  final url = _screensaverBgUrlCtrl.text.trim();
                  if (url.startsWith('http://') || url.startsWith('https://')) {
                    final host = Uri.tryParse(url)?.host ?? 'URL';
                    _updateState(() {
                      _draft = _draft.copyWith(
                        screensaverBackdrop: ScreensaverBackdrop.custom,
                        screensaverCustomBgSource: url,
                        screensaverCustomBgLabel: host.isNotEmpty ? host : 'Özel URL',
                      );
                      _statusBanner = tr ? 'Özel görsel URL uygulandı.' : 'Custom wallpaper URL applied.';
                    });
                  } else if (url.isEmpty && _draft.screensaverCustomBgSource.isNotEmpty) {
                    _updateState(() {
                      _draft = _draft.copyWith(
                        screensaverCustomBgSource: '',
                        screensaverCustomBgLabel: '',
                      );
                      _statusBanner = tr ? 'Özel duvar kağıdı temizlendi.' : 'Custom wallpaper cleared.';
                    });
                  } else {
                    _updateState(() {
                      _statusBanner = tr ? 'Geçerli bir https:// URL girin.' : 'Enter a valid https:// URL.';
                    });
                  }
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFF59E0B),
                  foregroundColor: const Color(0xFF18181B),
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  tr ? 'Uygula' : 'Apply',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                ),
              ),
            ),
          ],
        ),
        if (_draft.screensaverCustomBgSource.isNotEmpty) ...[
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  '✓ ${_draft.screensaverCustomBgLabel.isNotEmpty ? _draft.screensaverCustomBgLabel : (tr ? 'Özel duvar kağıdı aktif' : 'Custom wallpaper active')}',
                  style: const TextStyle(fontSize: 10.5, color: Color(0xFF34D399), fontWeight: FontWeight.w600),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              TactilePress(
                child: GestureDetector(
                  onTap: () {
                    _hapticTap();
                    unawaited(MediaStorageService.deleteMedia(_draft.screensaverCustomBgSource));
                    _screensaverBgUrlCtrl.clear();
                    _updateState(() {
                      _draft = _draft.copyWith(
                        screensaverCustomBgSource: '',
                        screensaverCustomBgLabel: '',
                      );
                    });
                    widget.onSaveSettings(_draft);
                  },
                  child: Text(
                    tr ? 'Kaldır' : 'Clear',
                    style: const TextStyle(fontSize: 10.5, color: Color(0xFFF87171), fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ],
          ),
        ],
        const SizedBox(height: 12),
        // Mascot Scale Slider (live-updates preview stage, main screen & screensaver)
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr ? 'Maskot Boyutu (Canlı Boyutlandırma)' : 'Mascot Size (Live Scale)',
              style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85)),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: activeMascotMeta.color.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: activeMascotMeta.color.withValues(alpha: 0.45)),
              ),
              child: Text(
                '%${(_draft.mascotScale * 100).round()}',
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: activeMascotMeta.color),
              ),
            ),
          ],
        ),
        Slider(
          value: _draft.mascotScale.clamp(0.60, 1.60),
          min: 0.60,
          max: 1.60,
          divisions: 20,
          activeColor: activeMascotMeta.color,
          onChanged: (v) => _updateState(() => _draft = _draft.copyWith(mascotScale: v)),
        ),
        // Live Preview & 6-Behavior Test Stage
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              tr ? '✨ Canlı Önizleme & Davranış Testi' : '✨ Live Preview & Behavior Test',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
            ),
            Text(
              tr ? "Dokununca 1.5 sn'de uyanır" : 'Wakes in 1.5s on tap',
              style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.52)),
            ),
          ],
        ),
        const SizedBox(height: 8),
        MascotBehaviorStage(
          character: _draft.mascotCharacter,
          behavior: _previewBehavior,
          mascotScale: _draft.mascotScale,
          backdrop: _draft.screensaverBackdrop,
          blurBackground: _draft.screensaverBlurBg,
          customBgSource: _draft.screensaverCustomBgSource,
          customBgLabel: _draft.screensaverCustomBgLabel,
          soundsEnabled: _draft.mascotSoundsEnabled,
          hapticEnabled: _draft.hapticEnabled,
          hapticStrength: _draft.hapticStrength,
          accentColor: widget.accentColor,
          lang: _lang,
          onWakeToIdle: () {
            if (mounted) _updateState(() => _previewBehavior = MascotBehavior.idle);
          },
        ),
        const SizedBox(height: 8),
        SizedBox(
          height: 34,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: behaviorOptions.length,
            separatorBuilder: (_, __) => const SizedBox(width: 6),
            itemBuilder: (_, idx) {
              final b = behaviorOptions[idx];
              final active = _previewBehavior == b.$1;
              return TactilePress(
                child: GestureDetector(
                  onTap: () {
                    _hapticTap();
                    _updateState(() => _previewBehavior = b.$1);
                    if (_draft.mascotSoundsEnabled) {
                      AmbientAudioService.playMascotSound(
                        _draft.mascotCharacter,
                        sleepy: b.$1 == MascotBehavior.deepSleep,
                      );
                    }
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: active ? b.$4.withValues(alpha: 0.24) : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: active ? b.$4 : Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(b.$3, size: 13, color: active ? b.$4 : Colors.white.withValues(alpha: 0.7)),
                        const SizedBox(width: 5),
                        Text(
                          b.$2,
                          style: TextStyle(
                            fontSize: 10.5,
                            fontWeight: FontWeight.w700,
                            color: active ? Colors.white : Colors.white.withValues(alpha: 0.78),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          decoration: BoxDecoration(
            color: const Color(0xFFF59E0B).withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(11),
            border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.32)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.swap_horiz_rounded, size: 15, color: Color(0xFFFBBF24)),
              const SizedBox(width: 7),
              Expanded(
                child: Text(
                  tr
                      ? 'Not: Maskot Ekran Koruyucu ile Smart Display otomatik modu aynı anda aktif olamaz. Maskotu aktif ettiğinizde Smart Display otomatik aktivasyonu pasife alınır (üst bardaki TV butonundan manuel açılış devam eder).'
                      : 'Note: Mascot Screensaver and Smart Display auto-mode cannot run together. Enabling Mascot sets Smart Display auto-mode to inactive (manual TV launch stays available).',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.35,
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildAiPhoneCallPanel(bool tr) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          tr
              ? 'Kombi ateşlendiğinde veya kritik güvenlik eşiği aşıldığında asistan tam ekran telefon araması başlatır; cevaplarsanız sesli özet sunar ve arama ekranından sıcaklığı anında değiştirebilirsiniz. İsterseniz aramayı kapatıp aynı görevleri Bildirim Ayarları üzerinden yalnızca yazılı bildirim olarak da alabilirsiniz.'
              : 'Starts a fullscreen assistant phone call when boiler ignition or a critical safety alert triggers; answer for a voice summary and quick thermostat controls. You can also turn calls off and keep receiving these events via Notifications & Automation.',
          style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72), height: 1.4),
        ),
        const SizedBox(height: 12),
        Text(
          tr ? 'Tetikleme Koşulu:' : 'Call Trigger Condition:',
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final mode in AiCallTriggerMode.values)
              TactilePress(
                child: GestureDetector(
                  onTap: () {
                    _hapticTap();
                    _updateState(() => _draft = _draft.copyWith(aiCallTriggerMode: mode));
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                    decoration: BoxDecoration(
                      color: _draft.aiCallTriggerMode == mode
                          ? const Color(0xFF10B981).withValues(alpha: 0.24)
                          : Colors.white.withValues(alpha: 0.05),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _draft.aiCallTriggerMode == mode
                            ? const Color(0xFF34D399)
                            : Colors.white.withValues(alpha: 0.14),
                      ),
                    ),
                    child: Text(
                      AiCallService.triggerModeLabel(mode, _lang),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _draft.aiCallTriggerMode == mode ? Colors.white : Colors.white70,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(tr ? 'Çalma Süresi (Zaman Aşımı)' : 'Ring Timeout', style: const TextStyle(fontSize: 12, color: Colors.white70)),
            Text('${_draft.aiCallRingSeconds} sn', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
          ],
        ),
        Slider(
          value: _draft.aiCallRingSeconds.toDouble(),
          min: 5,
          max: 30,
          divisions: 5,
          activeColor: const Color(0xFF10B981),
          onChanged: (v) => _updateState(() => _draft = _draft.copyWith(aiCallRingSeconds: v.round())),
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _draft.aiCallVoiceBriefEnabled,
          activeColor: const Color(0xFF10B981),
          title: Text(
            tr ? 'Cevaplandığında Sesli Özet Okuma' : 'Voice Briefing When Answered',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
          subtitle: Text(
            tr ? 'Ses tonuyla oda, hedef ve modülasyon brifingi' : 'Acoustic cue & live room/flame briefing readout',
            style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.56)),
          ),
          onChanged: (v) {
            _hapticTap();
            _updateState(() => _draft = _draft.copyWith(aiCallVoiceBriefEnabled: v));
          },
        ),
        SwitchListTile(
          contentPadding: EdgeInsets.zero,
          value: _draft.aiCallMissedAlertEnabled,
          activeColor: const Color(0xFFF59E0B),
          title: Text(
            tr ? 'Cevapsızda Bildirim & Telegram Gönder' : 'Send Alert & Telegram if Missed',
            style: const TextStyle(fontSize: 12, color: Colors.white),
          ),
          subtitle: Text(
            tr ? 'Arama açılmazsa acil bildirim ve Telegram bot uyarısı' : 'Dispatches alert banner & Telegram bot if unanswered',
            style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.56)),
          ),
          onChanged: (v) {
            _hapticTap();
            _updateState(() => _draft = _draft.copyWith(aiCallMissedAlertEnabled: v));
          },
        ),
        if (_draft.aiCallLastOutcome.isNotEmpty) ...[
          const SizedBox(height: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.04),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                const Icon(Icons.history_rounded, size: 14, color: Color(0xFF34D399)),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr ? 'Son Arama Özeti: ${_draft.aiCallLastOutcome}' : 'Last Call Log: ${_draft.aiCallLastOutcome}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white70),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr
                        ? 'Son 10 Arama Kaydı (${_draft.aiCallHistory.length}/10)'
                        : 'Last 10 Call Records (${_draft.aiCallHistory.length}/10)',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
                  ),
                  if (_draft.aiCallHistory.isNotEmpty)
                    TactilePress(
                      child: GestureDetector(
                        onTap: () {
                          _hapticTap();
                          final cleared = _draft.copyWith(aiCallHistory: const [], aiCallLastOutcome: '');
                          _updateState(() => _draft = cleared);
                          widget.onSaveSettings(cleared);
                        },
                        child: Text(
                          tr ? 'Temizle' : 'Clear',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFF87171)),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              if (_draft.aiCallHistory.isEmpty)
                Text(
                  tr
                      ? 'Henüz kayıtlı arama yok. Cevaplanan, cevapsız kalan ve meşgule atılan son 10 çağrı burada listelenir.'
                      : 'No call records yet. Your last 10 answered, missed, or declined calls appear here.',
                  style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.56), height: 1.35),
                )
              else
                for (final entry in _draft.aiCallHistory) ...[
                  Builder(
                    builder: (_) {
                      final m = MascotMeta.of(entry.character);
                      final badgeColor = entry.status == AiCallStatus.answered
                          ? const Color(0xFF10B981)
                          : (entry.status == AiCallStatus.declined
                              ? const Color(0xFFEF4444)
                              : const Color(0xFFF59E0B));
                      final summary = tr ? entry.summaryTr : entry.summaryEn;
                      final actionText = tr ? entry.actionTakenTr : entry.actionTakenEn;
                      return TactilePress.card(
                        child: GestureDetector(
                          onTap: () {
                            _hapticTap();
                            showMissedCallActionDialog(
                              context: context,
                              entry: entry,
                              lang: _lang,
                              onApplyAction: (act) {
                                widget.onChangeTargetTemp(act.targetTemp);
                                final updatedHistory = AiCallService.updateCallHistoryAction(
                                  _draft.aiCallHistory,
                                  entry.id,
                                  actionTr: act.logActionTr,
                                  actionEn: act.logActionEn,
                                );
                                final nextSettings = _draft.copyWith(aiCallHistory: updatedHistory);
                                _updateState(() {
                                  _liveTargetTemp = act.targetTemp;
                                  _draft = nextSettings;
                                });
                                widget.onSaveSettings(nextSettings);
                              },
                            );
                          },
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 6),
                            padding: const EdgeInsets.all(9),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.035),
                              borderRadius: BorderRadius.circular(11),
                              border: Border.all(color: badgeColor.withValues(alpha: 0.28)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: badgeColor.withValues(alpha: 0.16),
                                        borderRadius: BorderRadius.circular(7),
                                      ),
                                      child: Text(
                                        entry.statusLabel(_lang),
                                        style: TextStyle(fontSize: 9.5, fontWeight: FontWeight.w800, color: badgeColor),
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        '${m.name} · ${entry.timestamp}',
                                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                    Text(
                                      '${entry.durationSeconds} sn',
                                      style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white.withValues(alpha: 0.65)),
                                    ),
                                  ],
                                ),
                                if (summary.isNotEmpty) ...[
                                  const SizedBox(height: 4),
                                  Text(
                                    summary,
                                    style: const TextStyle(fontSize: 11, color: Colors.white, height: 1.3),
                                  ),
                                ],
                                if (actionText.isNotEmpty) ...[
                                  const SizedBox(height: 3),
                                  Text(
                                    '${tr ? 'İşlem' : 'Action'}: $actionText',
                                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF93C5FD)),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ],
            ],
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.04),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr ? 'Kadın / Erkek Ses Testi & Seçimi' : 'Female / Male Voice Test & Selector',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
                  ),
                  TactilePress(
                    child: GestureDetector(
                      onTap: () {
                        _hapticTap();
                        _refreshTurkishVoices();
                      },
                      child: Text(
                        tr ? '↻ Sesleri Yenile' : '↻ Refresh Voices',
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF38BDF8)),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Row(
                children: [
                  Expanded(
                    child: TactilePress(
                      child: OutlinedButton(
                        onPressed: () async {
                          _hapticTap();
                          VoiceSpeechService.preferredFemaleVoice = _draft.femaleVoiceName;
                          await VoiceSpeechService.speak(
                            tr ? 'Merhaba, ben Ela. Kadın ses testidir.' : 'Hello, this is Ela.',
                            lang: _lang,
                            character: MascotCharacter.ela,
                          );
                          if (!mounted) return;
                          final used = VoiceSpeechService.lastSpokenVoiceName;
                          final matched = VoiceSpeechService.lastSpokenMatchedGender;
                          _updateState(() {
                            _voiceTestStatus = used.isEmpty
                                ? (tr ? 'Ela: Tarayıcı varsayılan sesi' : 'Ela: Browser default')
                                : (matched
                                    ? 'Ela → $used'
                                    : (tr
                                        ? 'Ela → $used (Tarayıcıda kadın Türkçe ses yok, erkek yedeği kullanıldı)'
                                        : 'Ela → $used (No female Turkish voice in browser)'));
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFFEC4899).withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(
                          tr ? '👩 Kadın (Ela)' : '👩 Female (Ela)',
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: TactilePress(
                      child: OutlinedButton(
                        onPressed: () async {
                          _hapticTap();
                          VoiceSpeechService.preferredMaleVoice = _draft.maleVoiceName;
                          await VoiceSpeechService.speak(
                            tr ? 'Merhaba, ben Mert. Erkek ses testidir.' : 'Hello, this is Mert.',
                            lang: _lang,
                            character: MascotCharacter.mert,
                          );
                          if (!mounted) return;
                          final used = VoiceSpeechService.lastSpokenVoiceName;
                          _updateState(() {
                            _voiceTestStatus = used.isEmpty
                                ? (tr ? 'Mert: Tarayıcı varsayılan sesi' : 'Mert: Browser default')
                                : 'Mert → $used';
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.5)),
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                        child: Text(
                          tr ? '👨 Erkek (Mert)' : '👨 Male (Mert)',
                          style: const TextStyle(fontSize: 11, color: Colors.white),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              if (_voiceTestStatus != null) ...[
                const SizedBox(height: 6),
                Text(
                  _voiceTestStatus!,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w600,
                    color: _voiceTestStatus!.contains('yok') || _voiceTestStatus!.contains('No female')
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF6EE7B7),
                  ),
                ),
              ],
              if (_voicesLoaded) ...[
                const SizedBox(height: 6),
                if (_trVoices.isEmpty)
                  Text(
                    tr
                        ? 'Cihaz/Tarayıcıda Türkçe ses paketi algılanamadı.'
                        : 'No Turkish voice pack detected in this browser.',
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.65)),
                  )
                else ...[
                  if (!_trVoices.any((v) => v.gender == VoiceGenderHint.female)) ...[
                    Container(
                      margin: const EdgeInsets.only(bottom: 6),
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                      ),
                      child: Text(
                        tr
                            ? '⚠️ Bu tarayıcı yalnızca erkek Türkçe ses (${_trVoices.map((v) => v.name).join(', ')}) sunuyor. Windows\'ta Chrome yerine Microsoft Edge (Emel Online içerir) veya Android APK kullanırsanız Ela gerçek kadın sesiyle konuşur.'
                            : '⚠️ This browser only exposes male Turkish voice(s): ${_trVoices.map((v) => v.name).join(', ')}. Use Microsoft Edge (includes Emel Online) or Android APK for native female speech.',
                        style: const TextStyle(fontSize: 10, color: Color(0xFFFDE68A), height: 1.35),
                      ),
                    ),
                  ],
                  Text(
                    tr
                        ? 'Kadın (Ela) ses paketi (${_trVoices.length} Türkçe ses):'
                        : 'Female (Ela) voice (${_trVoices.length} Turkish voices):',
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.72)),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      TactilePress(
                        child: ChoiceChip(
                          label: Text(tr ? 'Otomatik' : 'Auto', style: const TextStyle(fontSize: 10, color: Colors.white)),
                          selected: _draft.femaleVoiceName.isEmpty,
                          selectedColor: const Color(0xFFEC4899).withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          onSelected: (_) {
                            VoiceSpeechService.preferredFemaleVoice = '';
                            _updateState(() => _draft = _draft.copyWith(femaleVoiceName: ''));
                          },
                        ),
                      ),
                      for (final v in _trVoices)
                        TactilePress(
                          child: ChoiceChip(
                            label: Text(v.labelTr(), style: const TextStyle(fontSize: 10, color: Colors.white)),
                            selected: _draft.femaleVoiceName == v.name,
                            selectedColor: const Color(0xFFEC4899).withValues(alpha: 0.35),
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            onSelected: (_) {
                              VoiceSpeechService.preferredFemaleVoice = v.name;
                              _updateState(() => _draft = _draft.copyWith(femaleVoiceName: v.name));
                            },
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr ? 'Erkek (Mert) ses paketi:' : 'Male (Mert) voice:',
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.72)),
                  ),
                  const SizedBox(height: 4),
                  Wrap(
                    spacing: 5,
                    runSpacing: 5,
                    children: [
                      TactilePress(
                        child: ChoiceChip(
                          label: Text(tr ? 'Otomatik' : 'Auto', style: const TextStyle(fontSize: 10, color: Colors.white)),
                          selected: _draft.maleVoiceName.isEmpty,
                          selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          onSelected: (_) {
                            VoiceSpeechService.preferredMaleVoice = '';
                            _updateState(() => _draft = _draft.copyWith(maleVoiceName: ''));
                          },
                        ),
                      ),
                      for (final v in _trVoices)
                        TactilePress(
                          child: ChoiceChip(
                            label: Text(v.labelTr(), style: const TextStyle(fontSize: 10, color: Colors.white)),
                            selected: _draft.maleVoiceName == v.name,
                            selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            onSelected: (_) {
                              VoiceSpeechService.preferredMaleVoice = v.name;
                              _updateState(() => _draft = _draft.copyWith(maleVoiceName: v.name));
                            },
                          ),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
        const SizedBox(height: 12),
        TactilePress.card(
          child: OutlinedButton.icon(
            onPressed: () {
              _hapticTap();
              widget.onSaveSettings(_draft);
              Navigator.of(context).pop();
              widget.onTestAiCall(AiCallReason.manualTest);
            },
            icon: const Icon(Icons.phone_forwarded_rounded, size: 18, color: Color(0xFF34D399)),
            label: Text(
              tr ? 'Gelen Aramayı Şimdi Test Et (Önizle)' : 'Test Incoming AI Call Now',
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
            ),
            style: OutlinedButton.styleFrom(
              backgroundColor: const Color(0xFF10B981).withValues(alpha: 0.14),
              side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.45)),
              padding: const EdgeInsets.symmetric(vertical: 11),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(13)),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            for (final sc in [
              (AiCallReason.ignition, tr ? '🔥 Ateşleme Testi' : '🔥 Ignition'),
              (AiCallReason.boilerOff, tr ? '⏸ Kapanma Testi' : '⏸ Boiler Off'),
              (AiCallReason.coldRoom, tr ? '❄️ Ev Soğuk (Açalım mı?)' : '❄️ Cold Room'),
              (AiCallReason.hotRoom, tr ? '☀️ Ev Sıcak (Kapatalım mı?)' : '☀️ Hot Room'),
            ])
              TactilePress(
                child: ActionChip(
                  label: Text(sc.$2, style: const TextStyle(fontSize: 10.5, color: Colors.white)),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  onPressed: () {
                    _hapticTap();
                    widget.onSaveSettings(_draft);
                    Navigator.of(context).pop();
                    widget.onTestAiCall(sc.$1);
                  },
                ),
              ),
          ],
        ),
      ],
    );
  }
}
