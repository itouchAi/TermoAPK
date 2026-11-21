import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/thermostat_state.dart';
import '../services/ambient_audio_service.dart';
import '../services/hardware_service.dart';
import '../services/notification_service.dart';
import '../widgets/termo_bot.dart';
import 'google_home_sheet.dart';
import 'vault_center_sheet.dart';

Future<void> showSystemSettingsSheet({
  required BuildContext context,
  required LangCode lang,
  required String locationName,
  required Color accentColor,
  required double roomTemp,
  required double targetTemp,
  required BoilerTelemetry boiler,
  required SystemSettingsState initialSettings,
  required ValueChanged<LangCode> onChangeLang,
  required ValueChanged<String> onChangeLocation,
  required ValueChanged<double> onChangeTargetTemp,
  required ValueChanged<SystemSettingsState> onSaveSettings,
  required VoidCallback onOpenAmbient,
  required VoidCallback onOpenScreensaverPreview,
  required VoidCallback onReplayBootCeremony,
  required VoidCallback onResetTelemetryHistory,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) => _SystemSettingsModal(
      lang: lang,
      locationName: locationName,
      accentColor: accentColor,
      roomTemp: roomTemp,
      targetTemp: targetTemp,
      boiler: boiler,
      initialSettings: initialSettings,
      onChangeLang: onChangeLang,
      onChangeLocation: onChangeLocation,
      onChangeTargetTemp: onChangeTargetTemp,
      onSaveSettings: onSaveSettings,
      onOpenAmbient: onOpenAmbient,
      onOpenScreensaverPreview: onOpenScreensaverPreview,
      onReplayBootCeremony: onReplayBootCeremony,
      onResetTelemetryHistory: onResetTelemetryHistory,
    ),
  );
}

class _SystemSettingsModal extends StatefulWidget {
  final LangCode lang;
  final String locationName;
  final Color accentColor;
  final double roomTemp;
  final double targetTemp;
  final BoilerTelemetry boiler;
  final SystemSettingsState initialSettings;
  final ValueChanged<LangCode> onChangeLang;
  final ValueChanged<String> onChangeLocation;
  final ValueChanged<double> onChangeTargetTemp;
  final ValueChanged<SystemSettingsState> onSaveSettings;
  final VoidCallback onOpenAmbient;
  final VoidCallback onOpenScreensaverPreview;
  final VoidCallback onReplayBootCeremony;
  final VoidCallback onResetTelemetryHistory;

  const _SystemSettingsModal({
    required this.lang,
    required this.locationName,
    required this.accentColor,
    required this.roomTemp,
    required this.targetTemp,
    required this.boiler,
    required this.initialSettings,
    required this.onChangeLang,
    required this.onChangeLocation,
    required this.onChangeTargetTemp,
    required this.onSaveSettings,
    required this.onOpenAmbient,
    required this.onOpenScreensaverPreview,
    required this.onReplayBootCeremony,
    required this.onResetTelemetryHistory,
  });

  @override
  State<_SystemSettingsModal> createState() => _SystemSettingsModalState();
}

class _SystemSettingsModalState extends State<_SystemSettingsModal> {
  late SystemSettingsState _draft;
  late LangCode _lang;
  late String _location;
  late double _liveTargetTemp;
  bool _editOrderMode = false;
  bool _audioPreviewPlaying = false;
  bool _sendingTestNotification = false;
  SettingsItemId? _expandedId;
  String? _statusBanner;
  String? _notificationStatus;
  bool _notificationStatusIsSuccess = true;
  HapticCapabilityInfo? _hapticCap;
  int? _lastTestedHapticMs;
  MascotBehavior _previewBehavior = MascotBehavior.idle;

  final _firebaseUrlCtrl = TextEditingController();
  final _espIdCtrl = TextEditingController();
  final _customAudioCtrl = TextEditingController();
  final _screensaverBgUrlCtrl = TextEditingController();

  static const _locations = ['Ev · İstanbul', 'Yazlık · İzmir', 'Ofis · Ankara'];

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSettings;
    _lang = widget.lang;
    _location = widget.locationName;
    _liveTargetTemp = widget.targetTemp;
    _firebaseUrlCtrl.text = _draft.firebaseRtdbUrl;
    _espIdCtrl.text = _draft.espDeviceId;
    _customAudioCtrl.text = _draft.customAudioLabel;
    if (_draft.screensaverCustomBgSource.startsWith('http')) {
      _screensaverBgUrlCtrl.text = _draft.screensaverCustomBgSource;
    }
    HardwareService.detectHapticCapability().then((info) {
      if (mounted) setState(() => _hapticCap = info);
    });
  }

  @override
  void dispose() {
    if (_audioPreviewPlaying) {
      AmbientAudioService.stop();
    }
    _firebaseUrlCtrl.dispose();
    _espIdCtrl.dispose();
    _customAudioCtrl.dispose();
    _screensaverBgUrlCtrl.dispose();
    super.dispose();
  }

  void _hapticTap() {
    if (_draft.hapticEnabled) {
      HardwareService.vibrateMs(
        40,
        amplitude: HardwareService.scaledAmplitude(135, _draft.hapticStrength),
      );
    }
  }

  Future<void> _testHapticPulse(int durationMs, int baseAmplitude) async {
    final scaled = HardwareService.scaledAmplitude(baseAmplitude, _draft.hapticStrength);
    await HardwareService.vibrateMs(durationMs, amplitude: scaled);
    if (!mounted) return;
    setState(() => _lastTestedHapticMs = durationMs);
  }

  String _resolveAudioSource() {
    final typed = _customAudioCtrl.text.trim();
    if (typed.startsWith('http://') || typed.startsWith('https://')) {
      return typed;
    }
    if (_draft.customAudioSource.trim().isNotEmpty) {
      return _draft.customAudioSource.trim();
    }
    return typed;
  }

  Future<void> _pickLocalMp3() async {
    _hapticTap();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.audio,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      AmbientAudioService.setCustomAudioBytes(picked.bytes);
      final source = kIsWeb ? picked.name : (picked.path ?? picked.name);
      if (!mounted) return;
      setState(() {
        _customAudioCtrl.text = picked.name;
        _draft = _draft.copyWith(
          ambientSoundtrack: AmbientSoundtrack.customMp3,
          customAudioLabel: picked.name,
          customAudioSource: source,
        );
      });
      if (_audioPreviewPlaying) {
        await AmbientAudioService.start(
          track: AmbientSoundtrack.customMp3,
          customSource: source,
          volume: _draft.ambientVolume,
        );
      }
    } catch (_) {}
  }

  Future<void> _toggleAudioPreview() async {
    _hapticTap();
    if (_audioPreviewPlaying) {
      await AmbientAudioService.stop();
      if (mounted) setState(() => _audioPreviewPlaying = false);
      return;
    }
    await AmbientAudioService.start(
      track: _draft.ambientSoundtrack,
      customSource: _resolveAudioSource(),
      volume: _draft.ambientVolume,
    );
    if (mounted) setState(() => _audioPreviewPlaying = true);
  }

  Future<void> _sendTestNotification() async {
    if (_sendingTestNotification) return;
    setState(() {
      _sendingTestNotification = true;
      _notificationStatus = null;
    });
    final res = await NotificationService.dispatchNotification(
      context: context,
      lang: _lang,
      locationName: _location,
      roomTemp: widget.roomTemp,
      targetTemp: _liveTargetTemp,
      boiler: ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp),
      settings: _draft,
    );
    if (!mounted) return;
    final next = _draft.copyWith(lastNotificationAt: res.timestampLabel);
    setState(() {
      _sendingTestNotification = false;
      _draft = next;
      _notificationStatus = _lang == LangCode.tr ? res.statusTextTr : res.statusTextEn;
      _notificationStatusIsSuccess = !res.telegramAttempted || res.telegramDelivered;
    });
    widget.onSaveSettings(next);
  }

  void _openVaultCenter() {
    _hapticTap();
    showVaultCenterSheet(
      context: context,
      lang: _lang,
      locationName: _location,
      initialSettings: _draft,
      onUpdateSettings: (next) {
        if (mounted) setState(() => _draft = next);
        widget.onSaveSettings(next);
      },
    );
  }

  void _openGoogleHome() {
    _hapticTap();
    showGoogleHomeSheet(
      context: context,
      lang: _lang,
      roomTemp: widget.roomTemp,
      targetTemp: _liveTargetTemp,
      boiler: ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp),
      initialSettings: _draft,
      onUpdateSettings: (next) {
        if (mounted) setState(() => _draft = next);
        widget.onSaveSettings(next);
      },
      onApplyTargetTemp: (t) {
        if (mounted) setState(() => _liveTargetTemp = t);
        widget.onChangeTargetTemp(t);
      },
    );
  }

  void _moveItem(int oldIdx, int newIdx) {
    _hapticTap();
    setState(() {
      final list = List<SettingsItemId>.from(_draft.menuOrder);
      final item = list.removeAt(oldIdx);
      list.insert(newIdx.clamp(0, list.length), item);
      _draft = _draft.copyWith(menuOrder: list);
    });
  }

  void _shiftItem(int idx, int delta) {
    final target = idx + delta;
    if (target < 0 || target >= _draft.menuOrder.length) return;
    _hapticTap();
    setState(() {
      final list = List<SettingsItemId>.from(_draft.menuOrder);
      final item = list.removeAt(idx);
      list.insert(target, item);
      _draft = _draft.copyWith(menuOrder: list);
    });
  }

  void _toggleExpand(SettingsItemId id) {
    _hapticTap();
    setState(() {
      _expandedId = _expandedId == id ? null : id;
    });
  }

  void _confirmResetHistory() {
    _hapticTap();
    showDialog<void>(
      context: context,
      builder: (dCtx) => AlertDialog(
        backgroundColor: const Color(0xFF14151D),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          _lang == LangCode.tr ? 'Geçmiş Verileri Sıfırla?' : 'Reset History Data?',
          style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w700),
        ),
        content: Text(
          _lang == LangCode.tr
              ? 'Hafızadaki tüm geçmiş tüketim, sıcaklık kayıtları ve fatura telemetrisi sıfırlanacak.'
              : 'All stored usage logs, hourly temperature records, and billing telemetry will be cleared.',
          style: const TextStyle(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dCtx).pop(),
            child: Text(_lang == LangCode.tr ? 'Vazgeç' : 'Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444)),
            onPressed: () {
              Navigator.of(dCtx).pop();
              widget.onResetTelemetryHistory();
              setState(() {
                _draft = _draft.copyWith(espLogs: const []);
                _statusBanner = _lang == LangCode.tr
                    ? 'Tüm geçmiş tüketim ve telemetri kayıtları sıfırlandı.'
                    : 'All usage history and telemetry cleared.';
              });
            },
            child: Text(_lang == LangCode.tr ? 'Sıfırla' : 'Reset'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.size.width > media.size.height;

    return Container(
      height: media.size.height * (isLandscape ? 0.94 : 0.90),
      alignment: Alignment.bottomCenter,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isLandscape ? 680 : 480),
        child: Container(
          decoration: BoxDecoration(
            color: const Color(0xFF0D0E14).withValues(alpha: 0.97),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
            border: Border.all(color: Colors.white.withValues(alpha: 0.12)),
            boxShadow: [
              BoxShadow(color: Colors.black.withValues(alpha: 0.75), blurRadius: 36, offset: const Offset(0, -10)),
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
                        color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                        border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                      ),
                      child: const Icon(Icons.cloud_outlined, color: Color(0xFFFBBF24), size: 21),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _lang == LangCode.tr ? 'Ayarlar & Sistem Tercihleri' : 'Settings & System Preferences',
                            style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white),
                          ),
                          Text(
                            _lang == LangCode.tr
                                ? 'Bulut bağlantısı, şifreli kasa ve veri yönetimi'
                                : 'Cloud sync, encrypted vault & device preferences',
                            style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.white.withValues(alpha: 0.06),
                        side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                      ),
                      icon: const Icon(Icons.close_rounded, color: Color(0xFFFBBF24), size: 19),
                    ),
                  ],
                ),
              ),

              // Reorder & Edit Bar + Location / Language Quick Bar
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Column(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.035),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                      ),
                      child: Row(
                        children: [
                          Icon(Icons.drag_indicator_rounded, size: 16, color: Colors.amber.shade400),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _lang == LangCode.tr
                                  ? 'Menüleri sürükle veya oklarla sırala'
                                  : 'Drag or use arrows to reorder',
                              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.65)),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          TextButton.icon(
                            onPressed: () {
                              _hapticTap();
                              setState(() {
                                _draft = _draft.copyWith(menuOrder: SystemSettingsState.defaultMenuOrder);
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 14),
                            label: Text(_lang == LangCode.tr ? 'Sıfırla' : 'Reset', style: const TextStyle(fontSize: 11)),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.white70,
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                          const SizedBox(width: 4),
                          OutlinedButton.icon(
                            onPressed: () {
                              _hapticTap();
                              setState(() => _editOrderMode = !_editOrderMode);
                            },
                            icon: Icon(_editOrderMode ? Icons.check_rounded : Icons.edit_outlined, size: 13),
                            label: Text(
                              _editOrderMode
                                  ? (_lang == LangCode.tr ? 'Bitti' : 'Done')
                                  : (_lang == LangCode.tr ? 'Düzenle' : 'Edit'),
                              style: const TextStyle(fontSize: 11),
                            ),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: const Color(0xFFFBBF24),
                              backgroundColor: _editOrderMode
                                  ? const Color(0xFFF59E0B).withValues(alpha: 0.18)
                                  : Colors.transparent,
                              side: BorderSide(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (_statusBanner != null) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFF10B981).withValues(alpha: 0.16),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                        ),
                        child: Text(_statusBanner!, style: const TextStyle(fontSize: 11.5, color: Color(0xFFA7F3D0))),
                      ),
                    ],
                  ],
                ),
              ),

              const SizedBox(height: 8),

              // Scrollable / Reorderable 11 Settings Cards + Device Profile Strip
              Expanded(
                child: ReorderableListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  buildDefaultDragHandles: false,
                  onReorderItem: _moveItem,
                  header: _buildLocationLanguageBar(),
                  itemCount: _draft.menuOrder.length,
                  itemBuilder: (context, idx) {
                    final id = _draft.menuOrder[idx];
                    return Padding(
                      key: ValueKey(id),
                      padding: const EdgeInsets.only(bottom: 10),
                      child: _buildSettingCard(id, idx),
                    );
                  },
                ),
              ),

              // Sticky Bottom Action Bar
              Container(
                padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + media.padding.bottom),
                decoration: BoxDecoration(
                  color: const Color(0xFF0A0B10),
                  border: Border(top: BorderSide(color: Colors.white.withValues(alpha: 0.08))),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: Text(_lang == LangCode.tr ? 'Kapat' : 'Close'),
                    ),
                    const SizedBox(width: 10),
                    Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(14),
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF59E0B), Color(0xFFEA580C)],
                        ),
                        boxShadow: [
                          BoxShadow(color: const Color(0xFFEA580C).withValues(alpha: 0.40), blurRadius: 16),
                        ],
                      ),
                      child: FilledButton(
                        onPressed: () {
                          _hapticTap();
                          final updated = _draft.copyWith(
                            firebaseRtdbUrl: _firebaseUrlCtrl.text.trim(),
                            espDeviceId: _espIdCtrl.text.trim(),
                            customAudioLabel: _customAudioCtrl.text.trim(),
                            customAudioSource: _resolveAudioSource(),
                          );
                          widget.onChangeLang(_lang);
                          widget.onChangeLocation(_location);
                          widget.onSaveSettings(updated);
                          Navigator.of(context).pop();
                        },
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          shadowColor: Colors.transparent,
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text(
                          _lang == LangCode.tr ? 'Ayarları Kaydet' : 'Save Settings',
                          style: const TextStyle(fontWeight: FontWeight.w700, color: Colors.white),
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

  Widget _buildLocationLanguageBar() {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.035),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _lang == LangCode.tr ? 'Cihaz Konumu & Arayüz Dili' : 'Location & Language',
                style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.85)),
              ),
              Row(
                children: [
                  for (final code in LangCode.values) ...[
                    const SizedBox(width: 4),
                    ChoiceChip(
                      label: Text(code.name.toUpperCase(), style: const TextStyle(fontSize: 11)),
                      selected: _lang == code,
                      visualDensity: VisualDensity.compact,
                      selectedColor: widget.accentColor.withValues(alpha: 0.35),
                      onSelected: (_) {
                        _hapticTap();
                        setState(() => _lang = code);
                      },
                    ),
                  ],
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              for (int i = 0; i < _locations.length; i++) ...[
                if (i > 0) const SizedBox(width: 6),
                Expanded(
                  child: GestureDetector(
                    onTap: () {
                      _hapticTap();
                      setState(() => _location = _locations[i]);
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: _location == _locations[i]
                            ? Colors.white.withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.04),
                        borderRadius: BorderRadius.circular(11),
                        border: Border.all(
                          color: _location == _locations[i]
                              ? Colors.white.withValues(alpha: 0.30)
                              : Colors.white.withValues(alpha: 0.08),
                        ),
                      ),
                      child: Text(
                        _locations[i],
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSettingCard(SettingsItemId id, int index) {
    final isExpanded = _expandedId == id;
    final meta = _describeItem(id);

    return Container(
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.045),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: isExpanded
              ? meta.iconColor.withValues(alpha: 0.45)
              : Colors.white.withValues(alpha: 0.09),
        ),
      ),
      child: Column(
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(20),
            onTap: () => _toggleExpand(id),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
              child: Row(
                children: [
                  if (_editOrderMode) ...[
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Icon(Icons.drag_handle_rounded, color: Colors.white.withValues(alpha: 0.55), size: 20),
                      ),
                    ),
                  ],
                  Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      color: meta.iconColor.withValues(alpha: 0.12),
                      border: Border.all(color: meta.iconColor.withValues(alpha: 0.30)),
                    ),
                    child: Icon(meta.icon, color: meta.iconColor, size: 19),
                  ),
                  const SizedBox(width: 11),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                meta.title,
                                style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Colors.white),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              meta.tag,
                              style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: meta.iconColor.withValues(alpha: 0.90)),
                            ),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          meta.subtitle,
                          style: TextStyle(fontSize: 11, color: Colors.white.withValues(alpha: 0.55)),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  if (_editOrderMode)
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          onPressed: index > 0 ? () => _shiftItem(index, -1) : null,
                          icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                        IconButton(
                          onPressed: index < _draft.menuOrder.length - 1 ? () => _shiftItem(index, 1) : null,
                          icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                        ),
                      ],
                    )
                  else ...[
                    meta.trailingAction,
                    const SizedBox(width: 4),
                    Icon(
                      isExpanded ? Icons.keyboard_arrow_up_rounded : Icons.keyboard_arrow_down_rounded,
                      color: Colors.white54,
                      size: 19,
                    ),
                  ],
                ],
              ),
            ),
          ),

          // Expandable Sub-Panel Body
          AnimatedCrossFade(
            duration: const Duration(milliseconds: 200),
            crossFadeState: isExpanded ? CrossFadeState.showSecond : CrossFadeState.showFirst,
            firstChild: const SizedBox.shrink(),
            secondChild: Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Divider(height: 14, color: Colors.white.withValues(alpha: 0.08)),
                  _buildExpandedPanel(id),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  _CardMeta _describeItem(SettingsItemId id) {
    final tr = _lang == LangCode.tr;
    switch (id) {
      case SettingsItemId.vault:
        return _CardMeta(
          icon: Icons.lock_outline_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Şifreli Kasa & Bildirimler' : 'Encrypted Vault & Alerts',
          tag: 'AES-256',
          subtitle: tr ? 'PIN korumalı kasa kilidi ve Telegram bot bildirimleri' : 'PIN vault lock and Telegram bot alerts',
          trailingAction: _ActionPill(
            label: _draft.vaultUnlocked ? (tr ? 'Açık ✓' : 'Open ✓') : (tr ? 'Aç →' : 'Open →'),
            active: _draft.vaultUnlocked,
            color: const Color(0xFFF59E0B),
            onTap: _openVaultCenter,
          ),
        );
      case SettingsItemId.googleHome:
        return _CardMeta(
          icon: Icons.home_outlined,
          iconColor: const Color(0xFF38BDF8),
          title: tr ? 'Google Home & Asistan' : 'Google Home & Assistant',
          tag: tr ? 'Google ile Uyumlu' : 'Works with Google',
          subtitle: tr ? 'Firebase üzerinden Google Asistan sesli kontrol' : 'Google Assistant voice sync via Firebase',
          trailingAction: _ActionPill(
            label: _draft.googleHomeLinked ? (tr ? 'Bağlı ✓' : 'Linked ✓') : (tr ? 'Yönet →' : 'Manage →'),
            active: _draft.googleHomeLinked,
            color: const Color(0xFF38BDF8),
            onTap: _openGoogleHome,
          ),
        );
      case SettingsItemId.smartDisplay:
        return _CardMeta(
          icon: Icons.tv_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: 'Smart Display & Ambiyans',
          tag: 'Tablet / PC',
          subtitle: tr ? 'Masaüstü veya duvarda canlı saat ve ambiyans ekranı' : 'Wall-mount clock & ambient display',
          trailingAction: _ActionPill(
            label: _draft.smartDisplayEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.smartDisplayEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(smartDisplayEnabled: !_draft.smartDisplayEnabled));
            },
          ),
        );
      case SettingsItemId.notifications:
        return _CardMeta(
          icon: Icons.notifications_none_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Bildirim Ayarları & Otomasyon' : 'Notifications & Automation',
          tag: tr ? '3 Saatlik & Acil' : '3h & Critical',
          subtitle: tr ? '3 saatlik durum özeti ve kritik kombi emniyet uyarıları' : '3-hour summary and critical safety alerts',
          trailingAction: _ActionPill(
            label: _draft.notifications3hEnabled ? (tr ? 'Devrede' : 'Active') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.notifications3hEnabled,
            color: const Color(0xFFF59E0B),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(notifications3hEnabled: !_draft.notifications3hEnabled));
            },
          ),
        );
      case SettingsItemId.haptic:
        return _CardMeta(
          icon: Icons.vibration_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Haptik Titreşim & Dokunma' : 'Haptic Touch Feedback',
          tag: tr ? 'Titreşim' : 'Haptic',
          subtitle: tr ? 'Tüm butonlar, kadran ve Flow Bar için titreşim' : 'Tactile feedback on dial, buttons and Flow Bar',
          trailingAction: _ActionPill(
            label: _draft.hapticEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.hapticEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              setState(() => _draft = _draft.copyWith(hapticEnabled: !_draft.hapticEnabled));
              if (_draft.hapticEnabled) HapticFeedback.mediumImpact();
            },
          ),
        );
      case SettingsItemId.bootCeremony:
        return _CardMeta(
          icon: Icons.local_fire_department_outlined,
          iconColor: const Color(0xFFF97316),
          title: tr ? 'Açılış Seremonisi (Boot Efekti)' : 'Boot Ceremony Animation',
          tag: 'Boot',
          subtitle: tr ? 'Uygulama açılırken akıllı termostat kalibrasyonu' : 'Smart calibration animation on launch',
          trailingAction: _ActionPill(
            label: _draft.bootCeremonyEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.bootCeremonyEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(bootCeremonyEnabled: !_draft.bootCeremonyEnabled));
            },
          ),
        );
      case SettingsItemId.termoBot:
        return _CardMeta(
          icon: Icons.smart_toy_outlined,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Sanal Asistan & Ekran Koruyucu' : 'Virtual Assistant Screensaver',
          tag: 'TermoBot',
          subtitle: tr ? 'Boşta kalınca tam ekran açılan ve 3 döngü sonra uyuyan koruyucu' : 'Idle fullscreen screensaver & 3-cycle sleep mode',
          trailingAction: _ActionPill(
            label: _draft.termoBotEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.termoBotEnabled,
            color: const Color(0xFFEA580C),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(termoBotEnabled: !_draft.termoBotEnabled));
            },
          ),
        );
      case SettingsItemId.aiPhoneCall:
        return _CardMeta(
          icon: Icons.phone_in_talk_outlined,
          iconColor: const Color(0xFF10B981),
          title: tr ? 'AI Sesli Telefon Araması (Asistan)' : 'AI Voice Call Assistant',
          tag: '${_draft.aiCallRingSeconds} sn',
          subtitle: tr ? 'Kombi ateşlendiğinde arar, sesli bilgi verir' : 'Calls on boiler ignition, alerts if missed',
          trailingAction: _ActionPill(
            label: _draft.aiPhoneCallEnabled ? (tr ? 'Açık ✓' : 'On ✓') : (tr ? 'Kapalı' : 'Off'),
            active: _draft.aiPhoneCallEnabled,
            color: const Color(0xFF10B981),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(aiPhoneCallEnabled: !_draft.aiPhoneCallEnabled));
            },
          ),
        );
      case SettingsItemId.espLog:
        return _CardMeta(
          icon: Icons.memory_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'ESP Donanım Günlüğü & Raporlama' : 'ESP Hardware & Offline Logs',
          tag: 'ESP32 / WDT',
          subtitle: tr ? 'Çevrimdışı yanma süreleri ve kilitlenme logları' : 'Offline burn cycles & watchdog logs',
          trailingAction: _ActionPill(
            label: _draft.espOnline ? (tr ? 'Çevrimiçi' : 'Online') : (tr ? 'Çevrimdışı' : 'Offline'),
            active: _draft.espOnline,
            color: _draft.espOnline ? const Color(0xFF10B981) : const Color(0xFFE11D48),
            onTap: () => _toggleExpand(id),
          ),
        );
      case SettingsItemId.cloudSync:
        return _CardMeta(
          icon: Icons.sync_rounded,
          iconColor: const Color(0xFF38BDF8),
          title: tr ? 'Bulut Senkronizasyon & Veritabanı' : 'Cloud Sync & Database',
          tag: 'Firebase RTDB',
          subtitle: tr ? 'Firebase gerçek zamanlı veri senkronizasyonu' : 'Firebase realtime telemetry sync',
          trailingAction: _ActionPill(
            label: _draft.cloudSyncEnabled ? (tr ? 'Bağlı' : 'Synced') : (tr ? 'Çevrimdışı' : 'Offline'),
            active: _draft.cloudSyncEnabled,
            color: _draft.cloudSyncEnabled ? const Color(0xFF10B981) : const Color(0xFFE11D48),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(cloudSyncEnabled: !_draft.cloudSyncEnabled));
            },
          ),
        );
      case SettingsItemId.resetHistory:
        return _CardMeta(
          icon: Icons.delete_sweep_outlined,
          iconColor: const Color(0xFFF87171),
          title: tr ? 'Geçmiş Verileri & Kayıtları Sıfırla' : 'Reset History & Usage Logs',
          tag: tr ? 'Sıfırlama' : 'Reset',
          subtitle: tr ? 'Sıcaklık saatlik kayıtları ve fatura telemetrisi' : 'Hourly heat records and billing telemetry',
          trailingAction: _ActionPill(
            label: tr ? 'Sıfırla' : 'Reset',
            active: false,
            color: const Color(0xFFEF4444),
            onTap: _confirmResetHistory,
          ),
        );
    }
  }

  Widget _buildExpandedPanel(SettingsItemId id) {
    final tr = _lang == LangCode.tr;
    switch (id) {
      case SettingsItemId.vault:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr
                  ? 'Telegram acil bildirim botu anahtarları, emniyet parametreleri ve alarm kontakları AES-256 CBC şifreleme ve PBKDF2 anahtar türetme ile saklanır.'
                  : 'Telegram alert bot keys, safety parameters, and alarm contacts are stored with PBKDF2 + AES-256 encryption.',
              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72), height: 1.4),
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    tr ? '✓ PIN Koruması Devrede' : '✓ PIN Protection Active',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFFCD34D)),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                  ),
                  child: Text(
                    tr ? '✓ 256-Bit Donanım Seviyesi Şifreleme' : '✓ 256-Bit Hardware Encryption',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF6EE7B7)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _openVaultCenter,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.lock_open_rounded, size: 17),
              label: Text(
                tr ? 'Şifreli Kasa ve Bildirim Merkezini Aç' : 'Open Encrypted Vault & Alerts Center',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );

      case SettingsItemId.googleHome:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr
                  ? 'Google Home ekosistemi ve Google Asistan ile sesli kombi kontrolü sağlayın. Firebase Realtime Database köprüsü üzerinden çift yönlü telemetri senkronizasyonu yapılır.'
                  : 'Control your boiler via Google Home & Google Assistant with bidirectional Firebase Realtime Database sync.',
              style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.72), height: 1.4),
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFF38BDF8).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(13),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr ? '🎙️ Örnek Sesli Komutlar:' : '🎙️ Sample Voice Commands:',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr
                        ? '• "Hey Google, ${_draft.googleHomeRoom.toLowerCase()} termostatını 22.5 derece yap"'
                        : '• "Hey Google, set ${_draft.googleHomeRoom.toLowerCase()} thermostat to 22.5 degrees"',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                  Text(
                    tr ? '• "Hey Google, kombi açık mı?"' : '• "Hey Google, is the boiler on?"',
                    style: const TextStyle(fontSize: 11, color: Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            FilledButton.icon(
              onPressed: _openGoogleHome,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFF0284C7),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: const Icon(Icons.home_outlined, size: 17),
              label: Text(
                tr ? 'Google Home & Asistan Entegrasyonunu Yönet' : 'Manage Google Home & Assistant Integration',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );

      case SettingsItemId.smartDisplay:
        final displayModes = [
          (
            SmartDisplayMode.aod,
            'Always-On Display (AOD)',
            tr ? 'Siyah Ekran + Büyük Saat + Donma Koruması' : 'Black OLED + Clock + Anti-Burn-In',
            Icons.nights_stay_outlined,
          ),
          (
            SmartDisplayMode.silentVideoMp3,
            tr ? 'Sessiz Video + MP3' : 'Silent Video + MP3',
            tr ? 'Canlı arka plan + ortam müziği' : 'Live background + ambient audio',
            Icons.music_video_outlined,
          ),
          (
            SmartDisplayMode.liveNature,
            tr ? 'Canlı Video / Doğa' : 'Live Video / Nature',
            tr ? 'Şömine & canlı doğa döngüsü' : 'Fireplace & live nature loop',
            Icons.local_fire_department_outlined,
          ),
          (
            SmartDisplayMode.slideshow,
            tr ? 'Slayt Gösterisi' : 'Slideshow',
            tr ? 'Fotoğraflar arası otomatik geçiş' : 'Automatic photo transitions',
            Icons.collections_outlined,
          ),
          (
            SmartDisplayMode.singlePhoto,
            tr ? 'Tekli Görsel' : 'Single Photo',
            tr ? 'Sakin sabit fotoğraf' : 'Calm static backdrop',
            Icons.photo_outlined,
          ),
        ];
        const slideDurations = [5, 10, 15, 30];
        final slideEffects = [
          (SlideTransitionEffect.fade, 'Fade'),
          (SlideTransitionEffect.slide, tr ? 'Kayma' : 'Slide'),
          (SlideTransitionEffect.zoom, 'Zoom'),
        ];
        final layoutModes = [
          (VisualLayoutMode.cover, tr ? 'Tam Ekran' : 'Cover'),
          (VisualLayoutMode.contain, tr ? 'Sığdır' : 'Contain'),
          (VisualLayoutMode.framed, tr ? 'Kare Kart' : 'Framed'),
        ];

        final audioTracks = [
          (AmbientSoundtrack.fireplaceCrackling, '🔥 ${tr ? 'Şömine' : 'Hearth'}'),
          (AmbientSoundtrack.nightRain, '🌧️ ${tr ? 'Yağmur' : 'Rain'}'),
          (AmbientSoundtrack.cozyJazzLofi, '🎷 Lo-Fi'),
          (AmbientSoundtrack.deepSpace, '🌌 ${tr ? 'Uzay' : 'Space'}'),
          (AmbientSoundtrack.forestBreeze, '🌲 ${tr ? 'Orman' : 'Forest'}'),
          (AmbientSoundtrack.customMp3, '🎵 ${tr ? 'Özel MP3' : 'Custom MP3'}'),
        ];
        final eqStyles = [
          (EqualizerStyle.bars, '📊 ${tr ? 'Çubuklar' : 'Bars'}', tr ? 'Neon spektrum' : 'Neon spectrum'),
          (EqualizerStyle.wave, '🌊 ${tr ? 'Dalga' : 'Wave'}', tr ? 'Siber dalga boyu' : 'Cyber waveform'),
          (EqualizerStyle.pulse, '💓 ${tr ? 'Nabız' : 'Pulse'}', tr ? 'Radyal vuruş' : 'Radial beat'),
        ];
        final brightnessPresets = [
          (20, '🌙 ${tr ? 'Gece' : 'Night'} %20'),
          (50, '🌇 ${tr ? 'Loş' : 'Dim'} %50'),
          (85, '☀️ ${tr ? 'Normal' : 'Normal'} %85'),
          (100, '⚡ ${tr ? 'Tam' : 'Full'} %100'),
        ];
        final sleepOptions = [
          (0, tr ? 'Sürekli Açık' : 'Always On'),
          (1, tr ? '1 Dk' : '1 Min'),
          (5, tr ? '5 Dk' : '5 Min'),
          (15, tr ? '15 Dk' : '15 Min'),
          (30, tr ? '30 Dk' : '30 Min'),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
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
                  final updated = _draft.copyWith(
                    customAudioLabel: _customAudioCtrl.text.trim(),
                    customAudioSource: _resolveAudioSource(),
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
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              tr ? 'Ekran Modu:' : 'Display Mode:',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.35,
              children: [
                for (final m in displayModes)
                  GestureDetector(
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(smartDisplayMode: m.$1));
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _draft.smartDisplayMode == m.$1
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.14)
                            : Colors.white.withValues(alpha: 0.03),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: _draft.smartDisplayMode == m.$1
                              ? const Color(0xFFFBBF24)
                              : Colors.white.withValues(alpha: 0.10),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              Icon(m.$4, size: 14, color: const Color(0xFFFBBF24)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  m.$2,
                                  style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_draft.smartDisplayMode == m.$1)
                                const Icon(Icons.check_rounded, size: 13, color: Color(0xFFFBBF24)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            m.$3,
                            style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.55)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF7C3AED).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF8B5CF6).withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr ? 'Slayt Süresi & Geçiş Efekti' : 'Slide Duration & Transition',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFC4B5FD)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final sec in slideDurations) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _hapticTap();
                              setState(() => _draft = _draft.copyWith(slideDurationSeconds: sec));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _draft.slideDurationSeconds == sec
                                    ? const Color(0xFF9333EA)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                '${sec}s',
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final eff in slideEffects) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _hapticTap();
                              setState(() => _draft = _draft.copyWith(slideEffect: eff.$1));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _draft.slideEffect == eff.$1
                                    ? const Color(0xFF9333EA)
                                    : Colors.white.withValues(alpha: 0.06),
                                borderRadius: BorderRadius.circular(9),
                              ),
                              child: Text(
                                eff.$2,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
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
            const SizedBox(height: 10),
            Container(
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
                    tr ? 'Görsel Yerleşim Modu' : 'Visual Layout Mode',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF93C5FD)),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      for (final lay in layoutModes) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _hapticTap();
                              setState(() => _draft = _draft.copyWith(smartDisplayLayout: lay.$1));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(vertical: 6),
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: _draft.smartDisplayLayout == lay.$1
                                    ? const Color(0xFF2563EB).withValues(alpha: 0.45)
                                    : Colors.white.withValues(alpha: 0.05),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: _draft.smartDisplayLayout == lay.$1
                                      ? const Color(0xFF60A5FA)
                                      : Colors.transparent,
                                ),
                              ),
                              child: Text(
                                lay.$2,
                                style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
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
            const SizedBox(height: 10),

            // Ambient Audio, Volume, External MP3 & Track Marquee
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFF0EA5E9).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFF38BDF8).withValues(alpha: 0.28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr ? '🎵 Varsayılan Temalar & Ambiyans Sesleri' : '🎵 Ambient Soundtracks & External MP3',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final track in audioTracks)
                        GestureDetector(
                          onTap: () {
                            _hapticTap();
                            setState(() => _draft = _draft.copyWith(ambientSoundtrack: track.$1));
                            if (_audioPreviewPlaying) {
                              AmbientAudioService.start(
                                track: track.$1,
                                customSource: _resolveAudioSource(),
                                volume: _draft.ambientVolume,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 6),
                            decoration: BoxDecoration(
                              color: _draft.ambientSoundtrack == track.$1
                                  ? const Color(0xFF0284C7).withValues(alpha: 0.48)
                                  : Colors.white.withValues(alpha: 0.05),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _draft.ambientSoundtrack == track.$1
                                    ? const Color(0xFF38BDF8)
                                    : Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Text(
                              track.$2,
                              style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                  if (_draft.ambientSoundtrack == AmbientSoundtrack.customMp3) ...[
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _DarkTextField(
                            controller: _customAudioCtrl,
                            hint: tr ? 'MP3 URL veya dosya adı' : 'MP3 URL or filename',
                          ),
                        ),
                        const SizedBox(width: 8),
                        FilledButton.tonalIcon(
                          onPressed: _pickLocalMp3,
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF0284C7).withValues(alpha: 0.30),
                            foregroundColor: const Color(0xFF7DD3FC),
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 11),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(11)),
                          ),
                          icon: const Icon(Icons.audio_file_outlined, size: 16),
                          label: Text(
                            tr ? 'MP3 Seç' : 'Pick MP3',
                            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700),
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          tr ? 'Ortam Sesi Seviyesi' : 'Ambient Audio Volume',
                          style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                        ),
                      ),
                      GestureDetector(
                        onTap: _toggleAudioPreview,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                          decoration: BoxDecoration(
                            color: _audioPreviewPlaying
                                ? const Color(0xFFEF4444).withValues(alpha: 0.25)
                                : const Color(0xFF0284C7).withValues(alpha: 0.25),
                            borderRadius: BorderRadius.circular(9),
                            border: Border.all(
                              color: _audioPreviewPlaying ? const Color(0xFFFCA5A5) : const Color(0xFF38BDF8),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                _audioPreviewPlaying ? Icons.stop_rounded : Icons.volume_up_rounded,
                                size: 13,
                                color: Colors.white,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                _audioPreviewPlaying ? (tr ? 'Durdur' : 'Stop') : (tr ? 'Sesi Dinle' : 'Test Audio'),
                                style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '%${(_draft.ambientVolume * 100).round()}',
                        style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFF7DD3FC)),
                      ),
                    ],
                  ),
                  Slider(
                    value: _draft.ambientVolume,
                    min: 0.0,
                    max: 1.0,
                    divisions: 20,
                    activeColor: const Color(0xFF38BDF8),
                    onChanged: (v) {
                      setState(() => _draft = _draft.copyWith(ambientVolume: v));
                      if (_audioPreviewPlaying) {
                        AmbientAudioService.setVolume(v);
                      }
                    },
                  ),
                  _MiniToggleTile(
                    label: tr ? 'Üst Kayan Yazı Şarkı İsmi' : 'Top Marquee Track Name',
                    value: _draft.marqueeTrackEnabled,
                    activeColor: const Color(0xFF38BDF8),
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(marqueeTrackEnabled: !_draft.marqueeTrackEnabled));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

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
                  _MiniToggleTile(
                    label: tr ? '🎚️ Canlı Müzik Ekolayzır Modu' : '🎚️ Live Music Equalizer Mode',
                    value: _draft.equalizerEnabled,
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(equalizerEnabled: !_draft.equalizerEnabled));
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    tr ? 'Ekolayzır Görsel Tipi:' : 'Equalizer Visual Style:',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.72)),
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      for (final eq in eqStyles) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _hapticTap();
                              setState(() => _draft = _draft.copyWith(equalizerStyle: eq.$1, equalizerEnabled: true));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 5),
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
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
                                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
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
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Built-in Display Brightness Slider + Live Preview + 4 Presets
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
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: (1.0 - (_draft.displayBrightness / 100.0)) * 0.72),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.45)),
                        ),
                        child: Text(
                          '21:45 · ${_liveTargetTemp.toStringAsFixed(1)}° (%${_draft.displayBrightness})',
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Colors.white.withValues(alpha: 0.35 + (_draft.displayBrightness / 100.0) * 0.65),
                          ),
                        ),
                      ),
                    ],
                  ),
                  Slider(
                    value: _draft.displayBrightness.toDouble(),
                    min: 10,
                    max: 100,
                    divisions: 18,
                    activeColor: const Color(0xFFF59E0B),
                    onChanged: (v) => setState(() => _draft = _draft.copyWith(displayBrightness: v.round())),
                  ),
                  Row(
                    children: [
                      for (final bp in brightnessPresets) ...[
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _hapticTap();
                              setState(() => _draft = _draft.copyWith(displayBrightness: bp.$1));
                            },
                            child: Container(
                              margin: const EdgeInsets.only(right: 4),
                              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 3),
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
                                style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700, color: Colors.white),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
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
            const SizedBox(height: 10),

            // Screen Sleep / Auto-Off Timeout + OLED Pixel Protection
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
                  Text(
                    tr ? '⏱️ Ekran Uyku / Kapanma Süresi' : '⏱️ Display Sleep Timeout',
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final sl in sleepOptions)
                        GestureDetector(
                          onTap: () {
                            _hapticTap();
                            setState(() => _draft = _draft.copyWith(displaySleepMinutes: sl.$1));
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
                    ],
                  ),
                  const SizedBox(height: 10),
                  _MiniToggleTile(
                    label: tr ? '🛡️ OLED Piksel Koruma (60 sn Kaydırma)' : '🛡️ OLED Pixel Protection (60s Drift)',
                    value: _draft.oledPixelShiftEnabled,
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(oledPixelShiftEnabled: !_draft.oledPixelShiftEnabled));
                    },
                  ),
                ],
              ),
            ),
          ],
        );

      case SettingsItemId.notifications:
        final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
        final safety = NotificationService.evaluateSafetyThresholds(
          roomTemp: widget.roomTemp,
          outsideTemp: 17.7,
          boiler: liveBoiler,
        );
        final guardOk = !safety.hasCriticalAlert;

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Period Badge + Last Dispatched Timestamp
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF59E0B).withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.42)),
                  ),
                  child: Text(
                    tr ? '⏱️ Periyot: 3 Saatte Bir (Otomatik)' : '⏱️ Interval: Every 3 Hours (Auto)',
                    style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFFCD34D)),
                  ),
                ),
                if (_draft.lastNotificationAt.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
                    decoration: BoxDecoration(
                      color: const Color(0xFF10B981).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF10B981).withValues(alpha: 0.35)),
                    ),
                    child: Text(
                      tr ? 'Son Gönderim: ${_draft.lastNotificationAt}' : 'Last Sent: ${_draft.lastNotificationAt}',
                      style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w600, color: Color(0xFF6EE7B7)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 10),

            // Live Pressure & Freeze Protection Guard Monitor Card
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: (guardOk ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.09),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: (guardOk ? const Color(0xFF10B981) : const Color(0xFFEF4444)).withValues(alpha: 0.36),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        guardOk ? Icons.verified_user_outlined : Icons.warning_amber_rounded,
                        size: 17,
                        color: guardOk ? const Color(0xFF34D399) : const Color(0xFFFCA5A5),
                      ),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          safety.headline(_lang),
                          style: TextStyle(
                            fontSize: 11.5,
                            fontWeight: FontWeight.w700,
                            color: guardOk ? const Color(0xFF6EE7B7) : const Color(0xFFFCA5A5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    tr
                        ? '• Basınç İzleme: ${liveBoiler.waterPressureBar.toStringAsFixed(1)} Bar (Eşik: < 1.0 Bar acil uyarı)\n'
                            '• Donma Koruması: Oda ${widget.roomTemp.toStringAsFixed(1)}°C (Eşik: < 5.0°C otomatik ateşleme)\n'
                            '• Alev & Brülör: ${liveBoiler.statusTextTr}'
                        : '• Pressure Guard: ${liveBoiler.waterPressureBar.toStringAsFixed(1)} Bar (Threshold: < 1.0 Bar)\n'
                            '• Freeze Guard: Room ${widget.roomTemp.toStringAsFixed(1)}°C (Threshold: < 5.0°C)\n'
                            '• Flame & Burner: ${liveBoiler.statusTextEn}',
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.76), height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // 4 Interactive Automation Switches
            _MiniToggleTile(
              label: tr ? '📊 3 Saatlik Tüketim & Durum Özeti' : '📊 3-Hour Usage & Status Summary',
              value: _draft.notifications3hEnabled,
              activeColor: const Color(0xFFF59E0B),
              onTap: () {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(notifications3hEnabled: !_draft.notifications3hEnabled));
              },
            ),
            const SizedBox(height: 6),
            _MiniToggleTile(
              label: tr ? '🚨 Kritik Basınç (<1.0 Bar) & Alev Kesintisi' : '🚨 Critical Pressure (<1.0 Bar) & Flame Loss',
              value: _draft.emergencyBoilerAlerts,
              activeColor: const Color(0xFFEF4444),
              onTap: () {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(emergencyBoilerAlerts: !_draft.emergencyBoilerAlerts));
              },
            ),
            const SizedBox(height: 6),
            _MiniToggleTile(
              label: tr ? '🌧️ Dış Hava & Ani Soğuma Bildirimleri' : '🌧️ Weather & Sudden Drop Alerts',
              value: _draft.weatherAlertsEnabled,
              activeColor: const Color(0xFF38BDF8),
              onTap: () {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(weatherAlertsEnabled: !_draft.weatherAlertsEnabled));
              },
            ),
            const SizedBox(height: 6),
            _MiniToggleTile(
              label: tr ? '🔔 Bildirim Sesi & Haptik Uyarısı' : '🔔 Alert Chime & Haptic Pulse',
              value: _draft.notifyChimeEnabled,
              activeColor: const Color(0xFF10B981),
              onTap: () {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(notifyChimeEnabled: !_draft.notifyChimeEnabled));
              },
            ),
            const SizedBox(height: 11),

            // Real Test Notification Dispatcher Button
            FilledButton.icon(
              onPressed: _sendingTestNotification ? null : _sendTestNotification,
              style: FilledButton.styleFrom(
                backgroundColor: const Color(0xFFF59E0B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              icon: _sendingTestNotification
                  ? const SizedBox(
                      width: 15,
                      height: 15,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.notifications_active_outlined, size: 17),
              label: Text(
                tr ? 'Test Bildirimi Gönder' : 'Send Test Notification',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
              ),
            ),
            if (_notificationStatus != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (_notificationStatusIsSuccess ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                      .withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_notificationStatusIsSuccess ? const Color(0xFF10B981) : const Color(0xFFF59E0B))
                        .withValues(alpha: 0.40),
                  ),
                ),
                child: Text(
                  _notificationStatus!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _notificationStatusIsSuccess ? const Color(0xFFA7F3D0) : const Color(0xFFFCD34D),
                  ),
                ),
              ),
            ],
          ],
        );

      case SettingsItemId.haptic:
        final cap = _hapticCap;
        final capLabel = cap == null
            ? (tr ? 'Donanım kontrol ediliyor...' : 'Checking hardware...')
            : cap.hasVibrator
                ? (cap.hasAmplitudeControl
                    ? (tr ? '✓ Titreşim Motoru + Genişlik Kontrolü Aktif' : '✓ Vibration Motor + Amplitude Control')
                    : (tr ? '✓ Standart Titreşim Motoru Aktif' : '✓ Standard Vibration Motor'))
                : (tr ? 'ℹ️ Sistem Dokunma Haptiği / Tarayıcı Modu' : 'ℹ️ System Haptic Fallback / Web Mode');

        final testProfiles = [
          (40, 120, tr ? '40ms · Hafif' : '40ms · Light', tr ? 'Kadran tıkı' : 'Dial tick'),
          (55, 155, tr ? '55ms · Orta' : '55ms · Medium', tr ? 'Flow Bar geçiş' : 'Tab transition'),
          (80, 195, tr ? '80ms · Güçlü' : '80ms · Strong', tr ? 'Kaydet & onay' : 'Save & confirm'),
          (140, 245, tr ? '140ms · Kritik' : '140ms · Alert', tr ? 'Acil uyarı' : 'Critical alert'),
        ];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Detected Hardware Capability Badge
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
              decoration: BoxDecoration(
                color: (cap?.hasVibrator == true ? const Color(0xFF10B981) : const Color(0xFF38BDF8))
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(11),
                border: Border.all(
                  color: (cap?.hasVibrator == true ? const Color(0xFF10B981) : const Color(0xFF38BDF8))
                      .withValues(alpha: 0.35),
                ),
              ),
              child: Text(
                capLabel,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: cap?.hasVibrator == true ? const Color(0xFF6EE7B7) : const Color(0xFF7DD3FC),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // Toggle + Vibration Intensity Slider
            _MiniToggleTile(
              label: tr ? '📳 Dokunsal Titreşim Motoru' : '📳 Haptic Feedback Motor',
              value: _draft.hapticEnabled,
              activeColor: const Color(0xFFF59E0B),
              onTap: () {
                final nextVal = !_draft.hapticEnabled;
                setState(() => _draft = _draft.copyWith(hapticEnabled: nextVal));
                if (nextVal) _testHapticPulse(55, 155);
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr ? 'Titreşim Şiddeti (Genişlik):' : 'Vibration Intensity:',
                  style: const TextStyle(fontSize: 11.5, color: Colors.white70),
                ),
                Text(
                  '%${_draft.hapticStrength}',
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
                ),
              ],
            ),
            Slider(
              value: _draft.hapticStrength.toDouble(),
              min: 40,
              max: 100,
              divisions: 6,
              activeColor: const Color(0xFFF59E0B),
              onChanged: (v) => setState(() => _draft = _draft.copyWith(hapticStrength: v.round())),
              onChangeEnd: (_) {
                if (_draft.hapticEnabled) _testHapticPulse(55, 160);
              },
            ),
            const SizedBox(height: 4),

            // 4 Live Haptic Test Buttons (40ms, 55ms, 80ms, 140ms)
            Text(
              tr ? 'Canlı Titreşim Test Profilleri (Dokunarak Test Et):' : 'Live Haptic Test Profiles (Tap to Trigger):',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFBBF24)),
            ),
            const SizedBox(height: 8),
            GridView.count(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 2.35,
              children: [
                for (final p in testProfiles)
                  GestureDetector(
                    onTap: () => _testHapticPulse(p.$1, p.$2),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 160),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                      decoration: BoxDecoration(
                        color: _lastTestedHapticMs == p.$1
                            ? const Color(0xFFF59E0B).withValues(alpha: 0.20)
                            : Colors.white.withValues(alpha: 0.045),
                        borderRadius: BorderRadius.circular(13),
                        border: Border.all(
                          color: _lastTestedHapticMs == p.$1
                              ? const Color(0xFFFBBF24)
                              : Colors.white.withValues(alpha: 0.11),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.vibration_rounded, size: 14, color: Color(0xFFFBBF24)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  p.$3,
                                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Colors.white),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (_lastTestedHapticMs == p.$1)
                                const Icon(Icons.check_circle_outline_rounded, size: 13, color: Color(0xFF6EE7B7)),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            p.$4,
                            style: TextStyle(fontSize: 9.5, color: Colors.white.withValues(alpha: 0.58)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
            if (_lastTestedHapticMs != null) ...[
              const SizedBox(height: 8),
              Text(
                tr
                    ? '✓ ${_lastTestedHapticMs}ms (%${_draft.hapticStrength} güç) titreşim sinyali gönderildi.'
                    : '✓ Dispatched ${_lastTestedHapticMs}ms (${_draft.hapticStrength}% strength) haptic pulse.',
                style: const TextStyle(fontSize: 11, color: Color(0xFF6EE7B7), fontWeight: FontWeight.w600),
              ),
            ],
            const SizedBox(height: 10),

            // Android / Xiaomi / HyperOS Troubleshooting Card
            Container(
              padding: const EdgeInsets.all(11),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0xFFF59E0B).withValues(alpha: 0.30)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    tr ? '🛠️ Android / Xiaomi / HyperOS Titreşim İpuçları' : '🛠️ Android / Xiaomi / HyperOS Haptic Tips',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Color(0xFFFCD34D)),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    tr
                        ? '• Xiaomi / HyperOS cihazlarda titreşim hissedilmiyorsa: Ayarlar → Ses ve Titreşim → Dokunsal Geri Bildirim seçeneğini açın.\n'
                            '• Pil Tasarrufu veya Rahatsız Etmeyin modu sistem titreşim motorunu geçici olarak susturabilir.'
                        : '• On Xiaomi / HyperOS devices, enable Settings → Sound & Vibration → Haptic Feedback.\n'
                            '• Battery Saver or Do Not Disturb mode may suppress system vibration pulses.',
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.72), height: 1.4),
                  ),
                ],
              ),
            ),
          ],
        );

      case SettingsItemId.bootCeremony:
        final bootStyles = [
          (BootCeremonyStyle.thermalPulse, tr ? 'Termal Nabız' : 'Thermal Pulse', Icons.waves_rounded),
          (BootCeremonyStyle.precisionSweep, tr ? 'Kadran Tarama' : 'Dial Sweep', Icons.speed_rounded),
          (BootCeremonyStyle.minimalRadar, tr ? 'Minimal Radar' : 'Minimal Radar', Icons.radar_rounded),
        ];
        final secLabel = '${(_draft.bootCeremonyDurationMs / 1000.0).toStringAsFixed(1)} sn';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _InfoBadge(
                  text: '⏱️ ${tr ? 'Süre' : 'Duration'}: $secLabel',
                  color: const Color(0xFFF97316),
                ),
                _InfoBadge(
                  text: _draft.bootCeremonyEnabled
                      ? (tr ? 'Açılışta Aktif' : 'Active on Launch')
                      : (tr ? 'Açılışta Kapalı' : 'Disabled on Launch'),
                  color: _draft.bootCeremonyEnabled ? const Color(0xFF10B981) : const Color(0xFF94A3B8),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              tr ? 'Kalibrasyon Animasyon Stili:' : 'Calibration Animation Style:',
              style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFF97316)),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                for (int i = 0; i < bootStyles.length; i++) ...[
                  if (i > 0) const SizedBox(width: 6),
                  Expanded(
                    child: GestureDetector(
                      onTap: () {
                        _hapticTap();
                        setState(() => _draft = _draft.copyWith(bootCeremonyStyle: bootStyles[i].$1));
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
                        decoration: BoxDecoration(
                          color: _draft.bootCeremonyStyle == bootStyles[i].$1
                              ? const Color(0xFFF97316).withValues(alpha: 0.18)
                              : Colors.white.withValues(alpha: 0.04),
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _draft.bootCeremonyStyle == bootStyles[i].$1
                                ? const Color(0xFFF97316)
                                : Colors.white.withValues(alpha: 0.10),
                          ),
                        ),
                        child: Column(
                          children: [
                            Icon(
                              bootStyles[i].$3,
                              size: 18,
                              color: _draft.bootCeremonyStyle == bootStyles[i].$1
                                  ? const Color(0xFFFDBA74)
                                  : Colors.white70,
                            ),
                            const SizedBox(height: 4),
                            Text(
                              bootStyles[i].$2,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.w600,
                                color: _draft.bootCeremonyStyle == bootStyles[i].$1 ? Colors.white : Colors.white70,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  tr ? 'Seremoni Süresi' : 'Ceremony Duration',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.80)),
                ),
                Text(
                  secLabel,
                  style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700, color: Color(0xFFFDBA74)),
                ),
              ],
            ),
            Slider(
              value: _draft.bootCeremonyDurationMs.toDouble(),
              min: 900,
              max: 3500,
              divisions: 13,
              activeColor: const Color(0xFFF97316),
              onChanged: (v) {
                setState(() => _draft = _draft.copyWith(bootCeremonyDurationMs: v.round()));
              },
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.04),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.music_note_outlined, size: 17, color: Color(0xFFF97316)),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          tr ? 'Kalibrasyon Tamamlama Sesi' : 'Calibration Completion Chime',
                          style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                        ),
                        Text(
                          tr ? 'Kadran hazır olduğunda kısa harmonik ton çalar' : 'Plays short harmonic chime when dial is ready',
                          style: TextStyle(fontSize: 10, color: Colors.white.withValues(alpha: 0.55)),
                        ),
                      ],
                    ),
                  ),
                  Switch(
                    value: _draft.bootSoundChimeEnabled,
                    activeThumbColor: const Color(0xFFF97316),
                    onChanged: (v) {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(bootSoundChimeEnabled: v));
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () {
                _hapticTap();
                widget.onSaveSettings(_draft);
                Navigator.of(context).pop();
                widget.onReplayBootCeremony();
              },
              icon: const Icon(Icons.replay_rounded, size: 18, color: Color(0xFFF97316)),
              label: Text(
                tr ? 'Seremoniyi Şimdi Başlat (Önizle)' : 'Replay Boot Ceremony Now',
                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFFFDBA74)),
              ),
              style: OutlinedButton.styleFrom(
                backgroundColor: const Color(0xFFF97316).withValues(alpha: 0.14),
                side: BorderSide(color: const Color(0xFFF97316).withValues(alpha: 0.45)),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
            ),
          ],
        );

      case SettingsItemId.termoBot:
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
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _InfoBadge(
                  text: '${activeMascotMeta.name} (${tr ? activeMascotMeta.roleTr : activeMascotMeta.roleEn})',
                  color: activeMascotMeta.color,
                ),
                _InfoBadge(
                  text: tr ? 'Bekleme: ${_draft.screensaverIdleSeconds} sn' : 'Idle: ${_draft.screensaverIdleSeconds}s',
                  color: const Color(0xFFF59E0B),
                ),
                _InfoBadge(
                  text: tr ? 'Boyut: %${(_draft.mascotScale * 100).round()}' : 'Size: ${(_draft.mascotScale * 100).round()}%',
                  color: const Color(0xFF10B981),
                ),
                _InfoBadge(
                  text: _draft.screensaverBlurBg ? (tr ? 'Cam Blur: Açık' : 'Glass Blur: On') : (tr ? 'Cam Blur: Kapalı' : 'Glass Blur: Off'),
                  color: _draft.screensaverBlurBg ? const Color(0xFF38BDF8) : const Color(0xFF9CA3AF),
                ),
              ],
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
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
                  return GestureDetector(
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(mascotCharacter: ch));
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
                    child: GestureDetector(
                      onTap: () {
                        _hapticTap();
                        setState(() => _draft = _draft.copyWith(screensaverIdleSeconds: opt.$1));
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
                  return GestureDetector(
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(screensaverBackdrop: bg.$1));
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
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniToggleTile(
                    label: tr ? 'Arka Plan Blur' : 'Blur Background',
                    value: _draft.screensaverBlurBg,
                    activeColor: const Color(0xFFF59E0B),
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(screensaverBlurBg: !_draft.screensaverBlurBg));
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniToggleTile(
                    label: tr ? 'Maskot Sesleri' : 'Mascot Sounds',
                    value: _draft.mascotSoundsEnabled,
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      _hapticTap();
                      final next = !_draft.mascotSoundsEnabled;
                      setState(() => _draft = _draft.copyWith(mascotSoundsEnabled: next));
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
                            final dataUri = 'data:$mime;base64,${base64Encode(file.bytes!)}';
                            if (!mounted) return;
                            setState(() {
                              _screensaverBgUrlCtrl.clear();
                              _draft = _draft.copyWith(
                                screensaverBackdrop: ScreensaverBackdrop.custom,
                                screensaverCustomBgSource: dataUri,
                                screensaverCustomBgLabel: file.name,
                              );
                              _statusBanner = tr ? 'Duvar kağıdı seçildi: ${file.name}' : 'Wallpaper selected: ${file.name}';
                            });
                          }
                        }
                      } catch (_) {
                        if (mounted) {
                          setState(() {
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
                ElevatedButton(
                  onPressed: () {
                    _hapticTap();
                    final url = _screensaverBgUrlCtrl.text.trim();
                    if (url.startsWith('http://') || url.startsWith('https://')) {
                      final host = Uri.tryParse(url)?.host ?? 'URL';
                      setState(() {
                        _draft = _draft.copyWith(
                          screensaverBackdrop: ScreensaverBackdrop.custom,
                          screensaverCustomBgSource: url,
                          screensaverCustomBgLabel: host.isNotEmpty ? host : 'Özel URL',
                        );
                        _statusBanner = tr ? 'Özel görsel URL uygulandı.' : 'Custom wallpaper URL applied.';
                      });
                    } else if (url.isEmpty && _draft.screensaverCustomBgSource.isNotEmpty) {
                      setState(() {
                        _draft = _draft.copyWith(
                          screensaverCustomBgSource: '',
                          screensaverCustomBgLabel: '',
                        );
                        _statusBanner = tr ? 'Özel duvar kağıdı temizlendi.' : 'Custom wallpaper cleared.';
                      });
                    } else {
                      setState(() {
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
                  GestureDetector(
                    onTap: () {
                      _hapticTap();
                      _screensaverBgUrlCtrl.clear();
                      setState(() {
                        _draft = _draft.copyWith(
                          screensaverCustomBgSource: '',
                          screensaverCustomBgLabel: '',
                        );
                      });
                    },
                    child: Text(
                      tr ? 'Kaldır' : 'Clear',
                      style: const TextStyle(fontSize: 10.5, color: Color(0xFFF87171), fontWeight: FontWeight.w700),
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
              onChanged: (v) => setState(() => _draft = _draft.copyWith(mascotScale: v)),
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
                if (mounted) setState(() => _previewBehavior = MascotBehavior.idle);
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
                  return GestureDetector(
                    onTap: () {
                      _hapticTap();
                      setState(() => _previewBehavior = b.$1);
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
                  );
                },
              ),
            ),
          ],
        );

      case SettingsItemId.aiPhoneCall:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(tr ? 'Çalma Süresi' : 'Ring Duration', style: const TextStyle(fontSize: 12, color: Colors.white70)),
                Text('${_draft.aiCallRingSeconds} sn', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF10B981))),
              ],
            ),
            Slider(
              value: _draft.aiCallRingSeconds.toDouble(),
              min: 5,
              max: 30,
              divisions: 5,
              activeColor: const Color(0xFF10B981),
              onChanged: (v) => setState(() => _draft = _draft.copyWith(aiCallRingSeconds: v.round())),
            ),
          ],
        );

      case SettingsItemId.espLog:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DarkTextField(controller: _espIdCtrl, hint: 'ESP32 Cihaz Kimliği'),
            const SizedBox(height: 8),
            if (_draft.espLogs.isEmpty)
              Text(tr ? 'Kayıtlı donanım günlüğü yok.' : 'No hardware logs stored.', style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.50)))
            else
              for (final log in _draft.espLogs)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Row(
                    children: [
                      Text(log.timestamp, style: const TextStyle(fontSize: 11, color: Colors.white54)),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '${log.event} · ${log.detail}',
                          style: TextStyle(fontSize: 11, color: log.isWarning ? Colors.amber.shade300 : Colors.white70),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
          ],
        );

      case SettingsItemId.cloudSync:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _DarkTextField(controller: _firebaseUrlCtrl, hint: 'Firebase RTDB URL'),
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              value: _draft.cloudSyncEnabled,
              title: Text(tr ? 'Gerçek Zamanlı Bulut Senkronizasyonu' : 'Realtime Cloud Sync', style: const TextStyle(fontSize: 12.5, color: Colors.white)),
              onChanged: (v) {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(cloudSyncEnabled: v));
              },
            ),
          ],
        );

      case SettingsItemId.resetHistory:
        return FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.25), foregroundColor: const Color(0xFFFCA5A5)),
          onPressed: _confirmResetHistory,
          icon: const Icon(Icons.delete_forever_outlined, size: 17),
          label: Text(tr ? 'Tüm Tüketim & Telemetriyi Sıfırla' : 'Clear All Usage & Telemetry'),
        );
    }
  }
}

class _CardMeta {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String tag;
  final String subtitle;
  final Widget trailingAction;

  const _CardMeta({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.tag,
    required this.subtitle,
    required this.trailingAction,
  });
}

class _ActionPill extends StatelessWidget {
  final String label;
  final bool active;
  final Color color;
  final VoidCallback onTap;

  const _ActionPill({
    required this.label,
    required this.active,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          gradient: active
              ? LinearGradient(colors: [color, color.withValues(alpha: 0.72)])
              : null,
          color: active ? null : Colors.white.withValues(alpha: 0.06),
          border: Border.all(color: active ? color : Colors.white.withValues(alpha: 0.14)),
        ),
        child: Text(
          label,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: Colors.white),
        ),
      ),
    );
  }
}

class _DarkTextField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final bool obscure;
  final TextInputType? keyboardType;

  const _DarkTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: const TextStyle(fontSize: 13, color: Colors.white),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: TextStyle(fontSize: 12, color: Colors.white.withValues(alpha: 0.40)),
        isDense: true,
        filled: true,
        fillColor: Colors.white.withValues(alpha: 0.05),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
        ),
      ),
    );
  }
}

class _MiniToggleTile extends StatelessWidget {
  final String label;
  final bool value;
  final Color activeColor;
  final VoidCallback onTap;

  const _MiniToggleTile({
    required this.label,
    required this.value,
    required this.activeColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.04),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: value ? activeColor.withValues(alpha: 0.45) : Colors.white.withValues(alpha: 0.10),
          ),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w600, color: Colors.white),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: value ? activeColor : Colors.white.withValues(alpha: 0.08),
                borderRadius: BorderRadius.circular(9),
              ),
              child: Text(
                value ? 'Açık' : 'Kapalı',
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: value ? Colors.white : Colors.white60,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoBadge extends StatelessWidget {
  final String text;
  final Color color;

  const _InfoBadge({
    required this.text,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.35)),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

