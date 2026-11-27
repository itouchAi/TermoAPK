part of '../settings_sheet.dart';

extension _SmartDisplaySettingsBuilder on _SystemSettingsModalState {
  Widget _buildSmartDisplayPanel(bool tr) {
    final displayModes = [
      (
        SmartDisplayMode.aod,
        '🌙 Always-On Display (AOD)',
        tr ? 'Siyah Ekran + Büyük Saat + Donma Koruması' : 'Black OLED + Clock + Anti-Burn-In',
      ),
      (
        SmartDisplayMode.silentVideoMp3,
        '🎬 ${tr ? 'Sessiz Video + MP3' : 'Silent Video + MP3'}',
        tr ? 'Videonun sesi kapalı + MP3 çalma' : 'Muted loop video + MP3 audio',
      ),
      (
        SmartDisplayMode.liveNature,
        '🔥 ${tr ? 'Canlı Video / Doğa' : 'Live Video / Nature'}',
        tr ? 'Şömine & canlı doğa sahneleri' : 'Fireplace & live nature scenes',
      ),
      (
        SmartDisplayMode.slideshow,
        '🖼️ ${tr ? 'Slayt Gösterisi' : 'Slideshow'}',
        tr ? 'Tekli veya çoklu görsel akışı' : 'Single or multi-photo stream',
      ),
    ];
    const slideDurations = [5, 10, 15, 30];
    final slideEffects = [
      (SlideTransitionEffect.fade, 'Fade'),
      (SlideTransitionEffect.slide, tr ? 'Kayma' : 'Slide'),
      (SlideTransitionEffect.zoom, 'Zoom'),
    ];
    final layoutModes = [
      (
        VisualLayoutMode.cover,
        '🖼️ Oto (Cover)',
        tr ? 'Ekranı doldur' : 'Fill screen',
      ),
      (
        VisualLayoutMode.contain,
        '📐 Fit (Sığdır)',
        tr ? 'Orantılı tam boy' : 'Fit proportional',
      ),
      (
        VisualLayoutMode.stretch,
        '↔️ Stretch',
        tr ? 'Ekran boyu esnet' : 'Stretch to fill',
      ),
    ];

    final visualThemes = [
      (SmartDisplayVisualTheme.fireplace, '🔥 ${tr ? 'Şömine' : 'Fireplace'}'),
      (SmartDisplayVisualTheme.rainy, '🌧️ ${tr ? 'Yağmurlu Pencere' : 'Rainy Window'}'),
      (SmartDisplayVisualTheme.winterSnow, '❄️ ${tr ? 'Kış & Kar' : 'Winter & Snow'}'),
      (SmartDisplayVisualTheme.sunset, '🌅 ${tr ? 'Gün Batımı' : 'Sunset'}'),
      (SmartDisplayVisualTheme.aurora, '🌌 ${tr ? 'Kutup Işıkları' : 'Aurora'}'),
      (SmartDisplayVisualTheme.minimalist, '🌊 ${tr ? 'Okyanus Dalgaları' : 'Ocean Waves'}'),
    ];

    final eqStyles = [
      (EqualizerStyle.bars, '📊 ${tr ? 'Çubuklar' : 'Bars'}', tr ? 'Neon spektrum' : 'Neon spectrum'),
      (EqualizerStyle.wave, '🌊 ${tr ? 'Dalga' : 'Wave'}', tr ? 'Siber dalga boyu' : 'Cyber waveform'),
      (EqualizerStyle.pulse, '💓 ${tr ? 'Nabız' : 'Pulse'}', tr ? 'Radyal vuruş' : 'Radial beat'),
    ];
    final brightnessPresets = [
      (20, '🌙 ${tr ? 'Gece' : 'Night'} (%20)'),
      (50, '🌇 ${tr ? 'Loş' : 'Dim'} (%50)'),
      (85, '☀️ ${tr ? 'Normal' : 'Normal'} (%85)'),
      (100, '⚡ ${tr ? 'Tam' : 'Full'} (%100)'),
    ];
    final autoStartOptions = [
      (0, tr ? 'Manuel (Kapalı)' : 'Manual (Off)'),
      (1, tr ? '1 Dk' : '1 Min'),
      (5, tr ? '5 Dk' : '5 Min'),
      (15, tr ? '15 Dk' : '15 Min'),
      (30, tr ? '30 Dk' : '30 Min'),
    ];
    final aodSleepOptions = [
      (0, tr ? 'Sürekli Açık' : 'Always On'),
      (5, tr ? '5 Dk' : '5 Min'),
      (15, tr ? '15 Dk' : '15 Min'),
      (30, tr ? '30 Dk' : '30 Min'),
      (60, tr ? '1 Saat' : '1 Hour'),
    ];

    final activeMode = _draft.smartDisplayMode == SmartDisplayMode.singlePhoto
        ? SmartDisplayMode.slideshow
        : _draft.smartDisplayMode;
    final isAod = activeMode == SmartDisplayMode.aod;
    final isSilentVideo = activeMode == SmartDisplayMode.silentVideoMp3;
    final isLiveNature = activeMode == SmartDisplayMode.liveNature;
    final isSlideshow = activeMode == SmartDisplayMode.slideshow;
    final brightnessFactor = (_draft.displayBrightness / 100.0).clamp(0.10, 1.0);

    Widget buildModeCard((SmartDisplayMode, String, String) m) {
      final selected = activeMode == m.$1;
      return TactilePress.card(
        child: GestureDetector(
          onTap: () {
            _hapticTap();
            _updateState(() {
              _draft = _draft.copyWith(smartDisplayMode: m.$1);
              if (m.$1 == SmartDisplayMode.liveNature) {
                _themesAudioAccordionExpanded = true;
              }
            });
          },
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: selected
                  ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                  : Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(
                color: selected
                    ? const Color(0xFFFBBF24)
                    : Colors.white.withValues(alpha: 0.10),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        m.$2,
                        style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (selected)
                      const Icon(Icons.check_rounded, size: 13, color: Color(0xFFFBBF24)),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  m.$3,
                  style: TextStyle(fontSize: 9.0, color: Colors.white.withValues(alpha: 0.56)),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      );
    }

    Widget buildLayoutSelectorCard({Widget? trailingChild}) {
      return Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.03),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              tr ? '📚 Görsel Yerleşim Modu:' : '📚 Visual Layout Mode:',
              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF93C5FD)),
            ),
            const SizedBox(height: 7),
            Row(
              children: [
                for (int idx = 0; idx < layoutModes.length; idx++) ...[
                  Expanded(
                    child: TactilePress.card(
                      child: GestureDetector(
                        onTap: () {
                          _hapticTap();
                          _updateState(() => _draft = _draft.copyWith(smartDisplayLayout: layoutModes[idx].$1));
                        },
                        child: Container(
                          margin: EdgeInsets.only(right: idx == layoutModes.length - 1 ? 0 : 6),
                          padding: const EdgeInsets.symmetric(vertical: 7, horizontal: 4),
                          decoration: BoxDecoration(
                            color: _draft.smartDisplayLayout == layoutModes[idx].$1
                                ? const Color(0xFF4F46E5).withValues(alpha: 0.50)
                                : Colors.white.withValues(alpha: 0.04),
                            borderRadius: BorderRadius.circular(11),
                            border: Border.all(
                              color: _draft.smartDisplayLayout == layoutModes[idx].$1
                                  ? const Color(0xFF818CF8)
                                  : Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                layoutModes[idx].$2,
                                style: const TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.white,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 2),
                              Text(
                                layoutModes[idx].$3,
                                style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.62)),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            if (trailingChild != null) ...[
              const SizedBox(height: 10),
              Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
              const SizedBox(height: 10),
              trailingChild,
            ],
          ],
        ),
      );
    }

    Widget buildExternalAudioSection() {
      final hasCustomAudio = _customAudioCtrl.text.trim().isNotEmpty ||
          _draft.customAudioSource.trim().isNotEmpty;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  tr ? '🔊 Ses Seviyesi & Dışarıdan MP3:' : '🔊 Volume & External MP3:',
                  style: const TextStyle(
                    fontSize: 10.5,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFFFCD34D),
                  ),
                ),
              ),
              Text(
                '${tr ? 'Ses' : 'Vol'}: %${(_draft.ambientVolume * 100).round()}',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  color: Color(0xFFFBBF24),
                ),
              ),
            ],
          ),
          Slider(
            value: _draft.ambientVolume,
            min: 0.0,
            max: 1.0,
            divisions: 20,
            activeColor: const Color(0xFFF59E0B),
            onChanged: (v) {
              _updateState(() => _draft = _draft.copyWith(ambientVolume: v));
              if (_audioPreviewPlaying) {
                AmbientAudioService.setVolume(v);
              }
            },
          ),
          Row(
            children: [
              Expanded(
                child: SettingsDarkTextField(
                  controller: _customAudioCtrl,
                  hint: tr ? 'MP3 URL veya dosya adı' : 'MP3 URL or filename',
                ),
              ),
              const SizedBox(width: 6),
              TactilePress(
                child: FilledButton.tonalIcon(
                  onPressed: _pickLocalMp3,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.30),
                    foregroundColor: const Color(0xFF7DD3FC),
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  icon: const Icon(Icons.audio_file_outlined, size: 15),
                  label: Text(
                    tr ? 'MP3 Seç' : 'MP3',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(width: 6),
              TactilePress(
                child: GestureDetector(
                  onTap: _toggleAudioPreview,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 10),
                    decoration: BoxDecoration(
                      color: _audioPreviewPlaying
                          ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                          : const Color(0xFF0284C7).withValues(alpha: 0.25),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: _audioPreviewPlaying
                            ? const Color(0xFFFCA5A5)
                            : const Color(0xFF38BDF8),
                      ),
                    ),
                    child: Icon(
                      _audioPreviewPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (hasCustomAudio) ...[
                const SizedBox(width: 6),
                TactilePress(
                  child: GestureDetector(
                    onTap: () {
                      _hapticTap();
                      AmbientAudioService.stop();
                      AmbientAudioService.setCustomAudioBytes(null);
                      unawaited(MediaStorageService.deleteMedia(_draft.customAudioSource));
                      _customAudioCtrl.clear();
                      _updateState(() {
                        _audioPreviewPlaying = false;
                        _draft = _draft.copyWith(
                          ambientSoundtrack: AmbientSoundtrack.silent,
                          customAudioLabel: '',
                          customAudioSource: '',
                        );
                      });
                      widget.onSaveSettings(_draft);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.55)),
                      ),
                      child: const Icon(Icons.close_rounded, size: 16, color: Color(0xFFFCA5A5)),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 8),
          SettingsMiniToggleTile(
            label: tr ? 'Alt Kayan Yazı Şarkı İsmi' : 'Bottom Marquee Track Name',
            value: _draft.marqueeTrackEnabled,
            activeColor: const Color(0xFF38BDF8),
            onTap: () {
              _hapticTap();
              _updateState(() => _draft = _draft.copyWith(marqueeTrackEnabled: !_draft.marqueeTrackEnabled));
            },
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Launch Smart Display Fullscreen CTA
        TactilePress.card(
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              gradient: const LinearGradient(colors: [Color(0xFFEA580C), Color(0xFFB45309)]),
              boxShadow: [BoxShadow(color: const Color(0xFFEA580C).withValues(alpha: 0.35), blurRadius: 14)],
            ),
            child: FilledButton.icon(
              onPressed: () {
                _hapticTap();
                if (_audioPreviewPlaying) {
                  AmbientAudioService.stop();
                  _audioPreviewPlaying = false;
                }
                final resolvedVideoSource = _resolveVideoSource();
                final typedVideo = _customVideoUrlCtrl.text.trim();
                final videoHost = Uri.tryParse(typedVideo)?.host ?? '';
                final resolvedVideoLabel = resolvedVideoSource.isEmpty
                    ? ''
                    : (typedVideo.startsWith('http://') || typedVideo.startsWith('https://'))
                        ? (videoHost.isNotEmpty ? videoHost : 'Video URL')
                        : (_draft.customVideoLabel.isNotEmpty ? _draft.customVideoLabel : typedVideo);
                final resolvedAudioSource = _resolveAudioSource();
                final resolvedAudioLabel = _customAudioCtrl.text.trim();
                final resolvedTrack = (resolvedAudioSource.isNotEmpty || resolvedAudioLabel.isNotEmpty)
                    ? AmbientSoundtrack.customMp3
                    : AmbientSoundtrack.silent;
                final updated = _draft.copyWith(
                  ambientSoundtrack: resolvedTrack,
                  customAudioLabel: resolvedAudioLabel,
                  customAudioSource: resolvedAudioSource,
                  customVideoLabel: resolvedVideoLabel,
                  customVideoSource: resolvedVideoSource,
                );
                widget.onSaveSettings(updated);
                Navigator.of(context).pop();
                widget.onOpenAmbient();
              },
              icon: const Icon(Icons.play_arrow_rounded, size: 19, color: Colors.white),
              label: Text(
                tr ? 'Smart Display\'i Şimdi Başlat (Tam Ekran)' : 'Launch Smart Display (Fullscreen)',
                style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: Colors.transparent,
                shadowColor: Colors.transparent,
                padding: const EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
        ),
        const SizedBox(height: 11),

        // 1. Compact Fixed-Height 2x2 Display Mode Grid (No Tekli Görsel!)
        Text(
          tr ? '📺 Ekran Modu:' : '📺 Display Mode:',
          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(child: buildModeCard(displayModes[0])),
            const SizedBox(width: 7),
            Expanded(child: buildModeCard(displayModes[1])),
          ],
        ),
        const SizedBox(height: 7),
        Row(
          children: [
            Expanded(child: buildModeCard(displayModes[2])),
            const SizedBox(width: 7),
            Expanded(child: buildModeCard(displayModes[3])),
          ],
        ),
        const SizedBox(height: 10),

        // 2. Context-Sensitive Panels per Selected Mode
        if (isAod) ...[
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
            ),
            child: Row(
              children: [
                const Icon(Icons.nights_stay_outlined, size: 16, color: Color(0xFFFBBF24)),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    tr
                        ? 'AOD Modu Aktif: Saf OLED siyah ekran, büyük saat ve piksel yanma koruması çalışır.'
                        : 'AOD Active: True black OLED screen with large clock and burn-in pixel shift.',
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.72), height: 1.35),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        if (isSilentVideo) ...[
          // Muted Video Picker & URL Card + Layout + MP3 Playlist
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF0284C7).withValues(alpha: 0.09),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr ? '🎬 Video Seçimi (Sessiz Döngü)' : '🎬 Video Source (Muted Loop)',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFF7DD3FC),
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr
                                ? 'Yüklenen videonun kendi sesi otomatik kapatılır; seçtiğiniz MP3 veya ortam sesi çalar.'
                                : 'The video\'s own audio track is always muted while your selected MP3 or ambient audio plays.',
                            style: TextStyle(
                              fontSize: 9.8,
                              color: Colors.white.withValues(alpha: 0.68),
                              height: 1.3,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    TactilePress(
                      child: FilledButton.icon(
                        onPressed: _pickCustomVideo,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        icon: const Icon(Icons.video_library_outlined, size: 15),
                        label: Text(
                          tr ? 'Video Seç' : 'Pick Video',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: SettingsDarkTextField(
                        controller: _customVideoUrlCtrl,
                        hint: tr ? 'Veya Video URL (https://...mp4 / webm)' : 'Or Video URL (https://...mp4)',
                      ),
                    ),
                    const SizedBox(width: 6),
                    TactilePress(
                      child: FilledButton(
                        onPressed: () {
                          _hapticTap();
                          final raw = _customVideoUrlCtrl.text.trim();
                          if (raw.startsWith('http://') || raw.startsWith('https://')) {
                            final host = Uri.tryParse(raw)?.host ?? '';
                            _updateState(() {
                              _draft = _draft.copyWith(
                                smartDisplayMode: SmartDisplayMode.silentVideoMp3,
                                customVideoSource: raw,
                                customVideoLabel: host.isNotEmpty ? host : 'Video URL',
                              );
                              _statusBanner = tr ? 'Video URL uygulandı.' : 'Video URL applied.';
                            });
                          } else {
                            _updateState(() {
                              _statusBanner = tr
                                  ? 'Geçerli bir https:// video URL girin veya Video Seç kullanın.'
                                  : 'Enter a valid https:// video URL or pick a local video.';
                            });
                          }
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFFF59E0B),
                          foregroundColor: const Color(0xFF18181B),
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 11),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        ),
                        child: Text(
                          tr ? 'Uygula' : 'Apply',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 7),
                Row(
                  children: [
                    Icon(
                      _draft.customVideoSource.isNotEmpty
                          ? Icons.check_circle_outline_rounded
                          : Icons.info_outline_rounded,
                      size: 14,
                      color: _draft.customVideoSource.isNotEmpty
                          ? const Color(0xFF34D399)
                          : Colors.white54,
                    ),
                    const SizedBox(width: 6),
                    Expanded(
                      child: Text(
                        _draft.customVideoSource.isNotEmpty
                            ? (tr
                                ? 'Aktif Video (Sessiz): ${_draft.customVideoLabel.isNotEmpty ? _draft.customVideoLabel : 'Video Yüklendi'}'
                                : 'Active Muted Video: ${_draft.customVideoLabel}')
                            : (tr
                                ? 'Henüz video seçilmedi (boşken aktif tema sahnesi sessiz akar).'
                                : 'No video selected yet (falls back to active ambient backdrop).'),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: _draft.customVideoSource.isNotEmpty
                              ? const Color(0xFF6EE7B7)
                              : Colors.white60,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (_draft.customVideoSource.isNotEmpty)
                      TactilePress(
                        child: GestureDetector(
                          onTap: _clearCustomVideo,
                          child: Text(
                            tr ? 'Temizle' : 'Clear',
                            style: const TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFF87171),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          buildLayoutSelectorCard(),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: buildExternalAudioSection(),
          ),
          const SizedBox(height: 10),
        ],

        if (isLiveNature) ...[
          buildLayoutSelectorCard(),
          const SizedBox(height: 10),
          // Image 7: Default Visual Themes (ONLY visible in Canlı Video / Doğa, NO robotic preset audio!)
          Container(
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.03),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: () {
                    _hapticTap();
                    _updateState(() => _themesAudioAccordionExpanded = !_themesAudioAccordionExpanded);
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            tr ? '🎨 Varsayılan Temalar' : '🎨 Default Themes',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Color(0xFFFCD34D),
                            ),
                          ),
                        ),
                        Icon(
                          _themesAudioAccordionExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: Colors.white70,
                        ),
                      ],
                    ),
                  ),
                ),
                if (_themesAudioAccordionExpanded)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(11, 0, 11, 11),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Divider(color: Colors.white.withValues(alpha: 0.08), height: 1),
                        const SizedBox(height: 10),
                        Text(
                          tr ? '🖼️ Görsel / Video Teması:' : '🖼️ Visual / Video Theme:',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF38BDF8),
                          ),
                        ),
                        const SizedBox(height: 7),
                        Row(
                          children: [
                            for (int idx = 0; idx < 3; idx++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: idx < 2 ? 6 : 0),
                                  child: TactilePress.card(
                                    child: GestureDetector(
                                      onTap: () {
                                        _hapticTap();
                                        _updateState(() => _draft = _draft.copyWith(
                                              smartDisplayVisualTheme: visualThemes[idx].$1,
                                            ));
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: _draft.smartDisplayVisualTheme == visualThemes[idx].$1
                                              ? const Color(0xFF0284C7).withValues(alpha: 0.42)
                                              : Colors.white.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _draft.smartDisplayVisualTheme == visualThemes[idx].$1
                                                ? const Color(0xFF38BDF8)
                                                : Colors.white.withValues(alpha: 0.10),
                                          ),
                                        ),
                                        child: Text(
                                          visualThemes[idx].$2,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            for (int idx = 3; idx < 6; idx++)
                              Expanded(
                                child: Padding(
                                  padding: EdgeInsets.only(right: idx < 5 ? 6 : 0),
                                  child: TactilePress.card(
                                    child: GestureDetector(
                                      onTap: () {
                                        _hapticTap();
                                        _updateState(() => _draft = _draft.copyWith(
                                              smartDisplayVisualTheme: visualThemes[idx].$1,
                                            ));
                                      },
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 9),
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: _draft.smartDisplayVisualTheme == visualThemes[idx].$1
                                              ? const Color(0xFF0284C7).withValues(alpha: 0.42)
                                              : Colors.white.withValues(alpha: 0.04),
                                          borderRadius: BorderRadius.circular(10),
                                          border: Border.all(
                                            color: _draft.smartDisplayVisualTheme == visualThemes[idx].$1
                                                ? const Color(0xFF38BDF8)
                                                : Colors.white.withValues(alpha: 0.10),
                                          ),
                                        ),
                                        child: Text(
                                          visualThemes[idx].$2,
                                          style: const TextStyle(
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            color: Colors.white,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
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
            ),
          ),
          const SizedBox(height: 10),
        ],

        if (isSlideshow) ...[
          // Compact Slide Duration & Transition Effect Card
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: const Color(0xFF7C3AED).withValues(alpha: 0.11),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.30)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  tr ? 'Slayt Süresi & Geçiş Efekti' : 'Slide Duration & Transition',
                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFC4B5FD)),
                ),
                const SizedBox(height: 7),
                LayoutBuilder(
                  builder: (_, c) {
                    final durationGroup = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr ? 'Slayt Değişim Süresi:' : 'Slide Interval:',
                          style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.65)),
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            for (final sec in slideDurations)
                              Expanded(
                                child: TactilePress(
                                  child: GestureDetector(
                                    onTap: () {
                                      _hapticTap();
                                      _updateState(() => _draft = _draft.copyWith(slideDurationSeconds: sec));
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _draft.slideDurationSeconds == sec
                                            ? const Color(0xFF9333EA)
                                            : Colors.white.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        '${sec}s',
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );
                    final effectGroup = Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr ? 'Geçiş Efekti (Fade / Kayma / Zoom):' : 'Transition Effect:',
                          style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.65)),
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            for (final eff in slideEffects)
                              Expanded(
                                child: TactilePress(
                                  child: GestureDetector(
                                    onTap: () {
                                      _hapticTap();
                                      _updateState(() => _draft = _draft.copyWith(slideEffect: eff.$1));
                                    },
                                    child: Container(
                                      margin: const EdgeInsets.only(right: 4),
                                      padding: const EdgeInsets.symmetric(vertical: 5),
                                      alignment: Alignment.center,
                                      decoration: BoxDecoration(
                                        color: _draft.slideEffect == eff.$1
                                            ? const Color(0xFF9333EA)
                                            : Colors.white.withValues(alpha: 0.06),
                                        borderRadius: BorderRadius.circular(8),
                                      ),
                                      child: Text(
                                        eff.$2,
                                        style: const TextStyle(
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w700,
                                          color: Colors.white,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ],
                    );

                    if (c.maxWidth >= 330) {
                      return Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(flex: 10, child: durationGroup),
                          const SizedBox(width: 8),
                          Expanded(flex: 10, child: effectGroup),
                        ],
                      );
                    }
                    return Column(
                      children: [
                        durationGroup,
                        const SizedBox(height: 7),
                        effectGroup,
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          buildLayoutSelectorCard(
            trailingChild: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            tr ? 'Çoklu Görsel & Slayt Listesi' : 'Multi-Photo Slideshow List',
                            style: const TextStyle(
                              fontSize: 11.5,
                              fontWeight: FontWeight.w700,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            tr
                                ? '${_draft.slideImages.length} Görsel Yüklendi (1 veya daha fazla seçebilirsiniz)'
                                : '${_draft.slideImages.length} Images Loaded (pick 1 or more)',
                            style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.60)),
                          ),
                        ],
                      ),
                    ),
                    TactilePress(
                      child: FilledButton.icon(
                        onPressed: _pickMultipleSlideImages,
                        style: FilledButton.styleFrom(
                          backgroundColor: const Color(0xFF0284C7),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 8),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                        ),
                        icon: const Icon(Icons.upload_rounded, size: 15),
                        label: Text(
                          tr ? 'Çoklu Görsel Seç' : 'Select Images',
                          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                        ),
                      ),
                    ),
                  ],
                ),
                if (_draft.slideImages.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      TactilePress(
                        child: OutlinedButton.icon(
                          onPressed: () => _showSlidePhotoPreviewDialog(
                            images: _draft.slideImages,
                            initialIndex: 0,
                          ),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFF7DD3FC),
                            side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            minimumSize: const Size(0, 30),
                          ),
                          icon: const Icon(Icons.visibility_outlined, size: 14),
                          label: Text(
                            tr ? 'Önizle' : 'Preview',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 7),
                      TactilePress(
                        child: OutlinedButton.icon(
                          onPressed: () {
                            _hapticTap();
                            for (final s in _draft.slideImages) {
                              unawaited(MediaStorageService.deleteMedia(s.filePath));
                            }
                            _updateState(() => _draft = _draft.copyWith(slideImages: const []));
                            widget.onSaveSettings(_draft);
                          },
                          style: OutlinedButton.styleFrom(
                            foregroundColor: const Color(0xFFFCA5A5),
                            side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.45)),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                            minimumSize: const Size(0, 30),
                          ),
                          icon: const Icon(Icons.delete_sweep_outlined, size: 14),
                          label: Text(
                            tr ? 'Tümünü Sil' : 'Delete All',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    height: 76,
                    child: ListView.separated(
                      scrollDirection: Axis.horizontal,
                      itemCount: _draft.slideImages.length,
                      separatorBuilder: (_, __) => const SizedBox(width: 8),
                      itemBuilder: (_, idx) {
                        final item = _draft.slideImages[idx];
                        final bytes = _resolveSlideBytes(item);
                        return Stack(
                          children: [
                            TactilePress.card(
                              child: GestureDetector(
                                onTap: () => _showSlidePhotoPreviewDialog(
                                  images: _draft.slideImages,
                                  initialIndex: idx,
                                ),
                                child: Container(
                                  width: 76,
                                  height: 76,
                                  decoration: BoxDecoration(
                                    color: Colors.black,
                                    borderRadius: BorderRadius.circular(11),
                                    border: Border.all(color: Colors.white.withValues(alpha: 0.16)),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(10),
                                    child: bytes != null
                                        ? Image.memory(bytes, fit: BoxFit.cover)
                                        : const Icon(Icons.image_outlined, color: Colors.white38),
                                  ),
                                ),
                              ),
                            ),
                            Positioned(
                              top: 3,
                              right: 3,
                              child: TactilePress(
                                child: GestureDetector(
                                  onTap: () {
                                    _hapticTap();
                                    final updated = List<SmartDisplaySlideImage>.from(_draft.slideImages);
                                    final removed = updated.removeAt(idx);
                                    unawaited(MediaStorageService.deleteMedia(removed.filePath));
                                    _updateState(() => _draft = _draft.copyWith(slideImages: updated));
                                    widget.onSaveSettings(_draft);
                                  },
                                  child: Container(
                                    width: 20,
                                    height: 20,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.black.withValues(alpha: 0.78),
                                      border: Border.all(color: const Color(0xFFFCA5A5).withValues(alpha: 0.75)),
                                    ),
                                    child: const Icon(Icons.close_rounded, size: 12, color: Color(0xFFFCA5A5)),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        if (isSilentVideo || isLiveNature) ...[
          // Live Music Equalizer Mode + 3 Visual Types
          Container(
            padding: const EdgeInsets.all(11),
            decoration: BoxDecoration(
              color: const Color(0xFF10B981).withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.28)),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SettingsMiniToggleTile(
                  label: tr ? '🎚️ Canlı Müzik Ekolayzır Modu' : '🎚️ Live Music Equalizer Mode',
                  value: _draft.equalizerEnabled,
                  activeColor: const Color(0xFF10B981),
                  onTap: () {
                    _hapticTap();
                    _updateState(() => _draft = _draft.copyWith(equalizerEnabled: !_draft.equalizerEnabled));
                  },
                ),
                const SizedBox(height: 8),
                Text(
                  tr ? 'Ekolayzır Görsel Tipi:' : 'Equalizer Visual Style:',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: Colors.white.withValues(alpha: 0.72),
                  ),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    for (final eq in eqStyles)
                      Expanded(
                        child: TactilePress.card(
                          child: GestureDetector(
                            onTap: () {
                              _hapticTap();
                              _updateState(() => _draft = _draft.copyWith(equalizerStyle: eq.$1, equalizerEnabled: true));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 5),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 7),
                              decoration: BoxDecoration(
                                color: _draft.equalizerStyle == eq.$1 && _draft.equalizerEnabled
                                    ? const Color(0xFF10B981).withValues(alpha: 0.22)
                                    : Colors.white.withValues(alpha: 0.04),
                                borderRadius: BorderRadius.circular(11),
                                border: Border.all(
                                  color: _draft.equalizerStyle == eq.$1 && _draft.equalizerEnabled
                                      ? const Color(0xFF34D399)
                                      : Colors.white.withValues(alpha: 0.10),
                                ),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    eq.$2,
                                    style: const TextStyle(
                                      fontSize: 11,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    eq.$3,
                                    style: TextStyle(fontSize: 9, color: Colors.white.withValues(alpha: 0.62)),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
        ],

        // Fixed Video & Image Background Blur Card + Live Interactive Preview
        Builder(
          builder: (_) {
            final blurPresets = [
              (0.0, tr ? 'Net (0px)' : 'Clear (0px)'),
              (4.0, tr ? 'Hafif (4px)' : 'Light (4px)'),
              (10.0, tr ? 'Orta (10px)' : 'Med (10px)'),
              (18.0, tr ? 'Yoğun (18px)' : 'Heavy (18px)'),
            ];
            final firstSlideBytes = _draft.slideImages.isNotEmpty
                ? _resolveSlideBytes(_draft.slideImages.first)
                : null;

            Widget buildBlurSampleBackdrop() {
              if (isSlideshow && firstSlideBytes != null) {
                return Image.memory(
                  firstSlideBytes,
                  fit: BoxFit.cover,
                  width: double.infinity,
                  height: double.infinity,
                );
              }
              final colors = switch (_draft.smartDisplayVisualTheme) {
                SmartDisplayVisualTheme.fireplace => const [
                    Color(0xFFF97316),
                    Color(0xFF9A3412),
                    Color(0xFF1C0F0A),
                  ],
                SmartDisplayVisualTheme.rainy => const [
                    Color(0xFF38BDF8),
                    Color(0xFF1E3A5F),
                    Color(0xFF0A111A),
                  ],
                SmartDisplayVisualTheme.winterSnow => const [
                    Color(0xFFE0F2FE),
                    Color(0xFF3B82F6),
                    Color(0xFF0B1324),
                  ],
                SmartDisplayVisualTheme.sunset => const [
                    Color(0xFFF59E0B),
                    Color(0xFF9333EA),
                    Color(0xFF130B1E),
                  ],
                SmartDisplayVisualTheme.aurora => const [
                    Color(0xFF10B981),
                    Color(0xFF6366F1),
                    Color(0xFF070B16),
                  ],
                SmartDisplayVisualTheme.minimalist => const [
                    Color(0xFF334155),
                    Color(0xFF1E293B),
                    Color(0xFF09090D),
                  ],
              };
              return Stack(
                fit: StackFit.expand,
                children: [
                  DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                        colors: colors,
                      ),
                    ),
                  ),
                  Positioned(
                    left: 28,
                    top: 16,
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white.withValues(alpha: 0.45),
                      ),
                    ),
                  ),
                  Positioned(
                    right: 48,
                    bottom: 12,
                    child: Container(
                      width: 34,
                      height: 34,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: colors.first.withValues(alpha: 0.72),
                      ),
                    ),
                  ),
                ],
              );
            }

            return Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.24)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        tr ? '🌫️ Video & Görsel Bulanıklık (Blur)' : '🌫️ Video & Image Blur',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                      ),
                      Text(
                        '${_draft.smartDisplayBlur.round()} px',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: Color(0xFF38BDF8),
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: SizedBox(
                      height: 86,
                      width: double.infinity,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          ClipRect(
                            child: _draft.smartDisplayBlur > 0.1
                                ? ImageFiltered(
                                    imageFilter: ui.ImageFilter.blur(
                                      sigmaX: _draft.smartDisplayBlur,
                                      sigmaY: _draft.smartDisplayBlur,
                                      tileMode: ui.TileMode.mirror,
                                    ),
                                    child: buildBlurSampleBackdrop(),
                                  )
                                : buildBlurSampleBackdrop(),
                          ),
                          DecoratedBox(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                begin: Alignment.topCenter,
                                end: Alignment.bottomCenter,
                                colors: [
                                  Colors.black.withValues(alpha: 0.28),
                                  Colors.black.withValues(alpha: 0.45),
                                ],
                              ),
                            ),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Column(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      '22 : 45',
                                      style: TextStyle(
                                        fontSize: 22,
                                        fontWeight: FontWeight.w700,
                                        color: Colors.white,
                                        height: 1.0,
                                        fontFeatures: [FontFeature.tabularFigures()],
                                        shadows: [Shadow(color: Colors.black54, blurRadius: 8)],
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Text(
                                      tr
                                          ? 'Oda ${widget.roomTemp != null ? '${widget.roomTemp!.toStringAsFixed(1)}°C' : '--'} · Hedef ${_liveTargetTemp.toStringAsFixed(1)}°C'
                                          : 'Room ${widget.roomTemp != null ? '${widget.roomTemp!.toStringAsFixed(1)}°C' : '--'} · Target ${_liveTargetTemp.toStringAsFixed(1)}°C',
                                      style: const TextStyle(
                                        fontSize: 10,
                                        fontWeight: FontWeight.w600,
                                        color: Colors.white70,
                                      ),
                                    ),
                                  ],
                                ),
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(alpha: 0.56),
                                    borderRadius: BorderRadius.circular(10),
                                    border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
                                  ),
                                  child: Text(
                                    _draft.smartDisplayBlur <= 0.1
                                        ? (tr ? 'Önizleme: Net' : 'Preview: Clear')
                                        : 'Blur: ${_draft.smartDisplayBlur.round()} px',
                                    style: const TextStyle(
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      color: Color(0xFFE0F2FE),
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
                  Slider(
                    value: _draft.smartDisplayBlur,
                    min: 0.0,
                    max: 24.0,
                    divisions: 24,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (v) => _updateState(() => _draft = _draft.copyWith(smartDisplayBlur: v)),
                  ),
                  Row(
                    children: [
                      for (int idx = 0; idx < blurPresets.length; idx++)
                        Expanded(
                          child: TactilePress(
                            child: GestureDetector(
                              onTap: () {
                                _hapticTap();
                                _updateState(() => _draft = _draft.copyWith(smartDisplayBlur: blurPresets[idx].$1));
                              },
                              child: Container(
                                margin: EdgeInsets.only(right: idx < blurPresets.length - 1 ? 4 : 0),
                                padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                                alignment: Alignment.center,
                                decoration: BoxDecoration(
                                  color: (_draft.smartDisplayBlur - blurPresets[idx].$1).abs() < 0.8
                                      ? const Color(0xFF0284C7).withValues(alpha: 0.35)
                                      : Colors.white.withValues(alpha: 0.05),
                                  borderRadius: BorderRadius.circular(9),
                                  border: Border.all(
                                    color: (_draft.smartDisplayBlur - blurPresets[idx].$1).abs() < 0.8
                                        ? const Color(0xFF38BDF8)
                                        : Colors.transparent,
                                  ),
                                ),
                                child: Text(
                                  blurPresets[idx].$2,
                                  style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        ),
        const SizedBox(height: 10),

        // 5. Built-in Display Brightness Live Mini Preview + Slider + 4 Presets
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.035),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    tr ? '☀️ Dahili Ekran Aydınlık Ayarı' : '☀️ Built-In Display Brightness',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFCD34D)),
                  ),
                  Text(
                    '%${_draft.displayBrightness}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                      color: Color(0xFFFBBF24),
                      fontFeatures: [FontFeature.tabularFigures()],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                decoration: BoxDecoration(
                  color: const Color(0xFF07070B),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: Opacity(
                  opacity: (0.28 + brightnessFactor * 0.72).clamp(0.28, 1.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Text(
                            '22:45',
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.92),
                              fontFeatures: const [FontFeature.tabularFigures()],
                            ),
                          ),
                          const SizedBox(width: 5),
                          Text(
                            '00',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Colors.white.withValues(alpha: 0.50),
                            ),
                          ),
                        ],
                      ),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.white.withValues(alpha: 0.08),
                              borderRadius: BorderRadius.circular(999),
                              border: Border.all(color: Colors.white.withValues(alpha: 0.14)),
                            ),
                            child: Text(
                              '☀️ ${widget.roomTemp != null ? '${widget.roomTemp!.toStringAsFixed(0)}°C' : '--'} - ${_liveTargetTemp.toStringAsFixed(1)}°C',
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                color: Color(0xFFFBBF24),
                              ),
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            tr
                                ? 'Canlı Aydınlık: %${_draft.displayBrightness}'
                                : 'Live Brightness: ${_draft.displayBrightness}%',
                            style: TextStyle(
                              fontSize: 9.5,
                              fontWeight: FontWeight.w600,
                              color: const Color(0xFFF59E0B).withValues(alpha: 0.85),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Slider(
                value: _draft.displayBrightness.toDouble(),
                min: 10,
                max: 100,
                divisions: 18,
                activeColor: const Color(0xFFF59E0B),
                onChanged: (v) => _updateState(() => _draft = _draft.copyWith(displayBrightness: v.round())),
              ),
              Row(
                children: [
                  for (final bp in brightnessPresets)
                    Expanded(
                      child: TactilePress(
                        child: GestureDetector(
                          onTap: () {
                            _hapticTap();
                            _updateState(() => _draft = _draft.copyWith(displayBrightness: bp.$1));
                          },
                          child: Container(
                            margin: const EdgeInsets.only(right: 4),
                            padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 2),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _draft.displayBrightness == bp.$1
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.25)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(9),
                              border: Border.all(
                                color: _draft.displayBrightness == bp.$1
                                    ? const Color(0xFFFBBF24)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              bp.$2,
                              style: const TextStyle(fontSize: 9.5, fontWeight: FontWeight.w700, color: Colors.white),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 10),

        // 6. Auto-Activation Timeout + Auto-AOD Sleep + Mutual Exclusion Notice (Image 8)
        Container(
          padding: const EdgeInsets.all(11),
          decoration: BoxDecoration(
            color: Colors.white.withValues(alpha: 0.03),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SettingsMiniToggleTile(
                label: tr
                    ? '📺 Smart Display Otomatik Başlatma'
                    : '📺 Smart Display Auto-Activation',
                value: _draft.smartDisplayEnabled,
                activeColor: const Color(0xFFEA580C),
                onTap: () {
                  _hapticTap();
                  final nextSmart = !_draft.smartDisplayEnabled;
                  _updateState(() => _draft = _draft.copyWith(
                    smartDisplayEnabled: nextSmart,
                    termoBotEnabled: nextSmart ? false : _draft.termoBotEnabled,
                    smartDisplayAutoMinutes: nextSmart && _draft.smartDisplayAutoMinutes == 0
                        ? 5
                        : _draft.smartDisplayAutoMinutes,
                  ));
                },
              ),
              const SizedBox(height: 10),
              Text(
                tr
                    ? '⏱️ Otomatik Aktivasyon Süresi (Boşta Kalma):'
                    : '⏱️ Auto-Activation Delay (Idle):',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final autoOpt in autoStartOptions)
                    TactilePress(
                      child: GestureDetector(
                        onTap: () {
                          _hapticTap();
                          final val = autoOpt.$1;
                          _updateState(() => _draft = _draft.copyWith(
                            smartDisplayAutoMinutes: val,
                            smartDisplayEnabled: val > 0,
                            termoBotEnabled: val > 0 ? false : _draft.termoBotEnabled,
                          ));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: (_draft.smartDisplayEnabled ? _draft.smartDisplayAutoMinutes : 0) == autoOpt.$1
                                ? const Color(0xFFEA580C).withValues(alpha: 0.28)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: (_draft.smartDisplayEnabled ? _draft.smartDisplayAutoMinutes : 0) == autoOpt.$1
                                  ? const Color(0xFFFB923C)
                                  : Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Text(
                            autoOpt.$2,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 12),
              Text(
                tr
                    ? '🌙 Aktif Olduktan Sonra AOD\'a Geçiş Süresi:'
                    : '🌙 Auto-Switch to AOD After Active:',
                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
              ),
              const SizedBox(height: 7),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  for (final sl in aodSleepOptions)
                    TactilePress(
                      child: GestureDetector(
                        onTap: () {
                          _hapticTap();
                          _updateState(() => _draft = _draft.copyWith(displaySleepMinutes: sl.$1));
                        },
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: _draft.displaySleepMinutes == sl.$1
                                ? const Color(0xFFF59E0B).withValues(alpha: 0.26)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _draft.displaySleepMinutes == sl.$1
                                  ? const Color(0xFFFBBF24)
                                  : Colors.white.withValues(alpha: 0.10),
                            ),
                          ),
                          child: Text(
                            sl.$2,
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              SettingsMiniToggleTile(
                label: tr ? '🛡️ OLED Piksel Koruma (60 sn Kaydırma)' : '🛡️ OLED Pixel Protection (60s Drift)',
                value: _draft.oledPixelShiftEnabled,
                activeColor: const Color(0xFF10B981),
                onTap: () {
                  _hapticTap();
                  _updateState(() => _draft = _draft.copyWith(oledPixelShiftEnabled: !_draft.oledPixelShiftEnabled));
                },
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
                            ? 'Not: Smart Display otomatik modu ile Sanal Asistan (Maskot) ekran koruyucusu aynı anda aktif olamaz. Smart Display\'i açtığınızda Maskot pasife düşer; ana ekrandaki TV butonundan manuel açılış her zaman aktiftir.'
                            : 'Note: Smart Display auto-activation and Mascot Screensaver are mutually exclusive. Enabling Smart Display disables Mascot; manual launch via the TV button always remains available.',
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
          ),
        ),
      ],
    );
  }
}
