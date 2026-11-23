import 'dart:convert';
import 'dart:ui' as ui;
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../models/thermostat_state.dart';
import '../services/ai_call_service.dart';
import '../services/ambient_audio_service.dart';
import '../services/esp_log_service.dart';
import '../services/firebase_sync_service.dart';
import '../services/hardware_service.dart';
import '../services/notification_service.dart';
import '../services/video_source_bridge.dart';
import '../services/voice_gender_classifier.dart';
import '../services/voice_speech_service.dart';
import '../widgets/missed_call_alert.dart';
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
  required ValueChanged<AiCallReason> onTestAiCall,
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
      onTestAiCall: onTestAiCall,
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
  final ValueChanged<AiCallReason> onTestAiCall;
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
    required this.onTestAiCall,
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
  List<VoiceOptionInfo> _trVoices = const [];
  bool _voicesLoaded = false;
  String? _voiceTestStatus;
  EspLogCategory? _espLogFilter;
  bool _espPingBusy = false;
  String? _espPingStatus;
  bool _espPingOk = true;
  bool _cloudSyncBusy = false;
  String? _cloudSyncStatus;
  bool _cloudSyncOk = true;
  bool _showCloudPayloadPreview = false;
  bool _themesAudioAccordionExpanded = true;
  bool _savedToastVisible = false;

  final _firebaseUrlCtrl = TextEditingController();
  final _firebaseApiKeyCtrl = TextEditingController();
  final _firebaseNodeCtrl = TextEditingController();
  final _espIdCtrl = TextEditingController();
  final _customAudioCtrl = TextEditingController();
  final _customVideoUrlCtrl = TextEditingController();
  final _screensaverBgUrlCtrl = TextEditingController();

  static const _locations = ['Ev · İstanbul', 'Yazlık · İzmir', 'Ofis · Ankara'];

  Future<void> _runCloudPush({bool pullInstead = false}) async {
    if (_cloudSyncBusy) return;
    _hapticTap();
    final rtdbUrl = _firebaseUrlCtrl.text.trim().isEmpty
        ? _draft.firebaseRtdbUrl
        : _firebaseUrlCtrl.text.trim();
    final apiKey = _firebaseApiKeyCtrl.text.trim();
    final nodePath = FirebaseSyncService.sanitizeNodePath(
      _firebaseNodeCtrl.text.trim().isEmpty ? _draft.firebaseNodePath : _firebaseNodeCtrl.text.trim(),
    );
    setState(() {
      _cloudSyncBusy = true;
      _cloudSyncStatus = null;
    });

    final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
    final res = pullInstead
        ? await FirebaseSyncService.pullState(
            baseUrl: rtdbUrl,
            apiKey: apiKey,
            nodePath: nodePath,
          )
        : await FirebaseSyncService.pushState(
            baseUrl: rtdbUrl,
            apiKey: apiKey,
            nodePath: nodePath,
            roomName: _draft.googleHomeRoom,
            espDeviceId: _espIdCtrl.text.trim().isEmpty ? _draft.espDeviceId : _espIdCtrl.text.trim(),
            roomTemp: widget.roomTemp,
            targetTemp: _liveTargetTemp,
            boiler: liveBoiler,
          );
    if (!mounted) return;
    final nowLabel = NotificationService.formatNowTime();
    final msg = _lang == LangCode.tr ? res.messageTr : res.messageEn;

    if (pullInstead && res.ok && res.remoteTargetTemp != null) {
      _liveTargetTemp = res.remoteTargetTemp!;
      widget.onChangeTargetTemp(res.remoteTargetTemp!);
    }

    final nextDraft = _draft.copyWith(
      firebaseRtdbUrl: rtdbUrl,
      firebaseApiKey: apiKey,
      firebaseNodePath: nodePath,
      cloudLastSyncAt: nowLabel,
      cloudLastSyncOk: res.ok,
      cloudLastSyncMessage: msg,
      espOnline: res.ok ? true : _draft.espOnline,
      espLastPingAt: res.ok ? nowLabel : _draft.espLastPingAt,
      espLogs: EspLogService.appendLog(
        _draft.espLogs,
        EspLogEntry(
          timestamp: nowLabel,
          event: res.ok
              ? (pullInstead
                  ? (_lang == LangCode.tr ? 'RTDB Manuel Çekme' : 'RTDB Manual Pull')
                  : (_lang == LangCode.tr ? 'RTDB Manuel Gönderim' : 'RTDB Manual Push'))
              : (_lang == LangCode.tr ? 'RTDB Senkronizasyon Hatası' : 'RTDB Sync Error'),
          detail: msg,
          isWarning: !res.ok,
          category: res.ok ? EspLogCategory.sync : EspLogCategory.watchdog,
        ),
      ),
    );
    setState(() {
      _cloudSyncBusy = false;
      _cloudSyncOk = res.ok;
      _cloudSyncStatus = msg;
      _draft = nextDraft;
    });
    widget.onSaveSettings(nextDraft);
  }

  Future<void> _runEspConnectionTest() async {
    if (_espPingBusy) return;
    _hapticTap();
    final deviceId = _espIdCtrl.text.trim().isEmpty
        ? _draft.espDeviceId
        : _espIdCtrl.text.trim();
    final rtdbUrl = _firebaseUrlCtrl.text.trim().isEmpty
        ? _draft.firebaseRtdbUrl
        : _firebaseUrlCtrl.text.trim();
    final apiKey = _firebaseApiKeyCtrl.text.trim();
    final nodePath = FirebaseSyncService.sanitizeNodePath(
      _firebaseNodeCtrl.text.trim().isEmpty ? _draft.firebaseNodePath : _firebaseNodeCtrl.text.trim(),
    );
    setState(() {
      _espPingBusy = true;
      _espPingStatus = null;
    });
    final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
    final res = await EspLogService.testDeviceConnection(
      baseUrl: rtdbUrl,
      apiKey: apiKey,
      nodePath: nodePath,
      espDeviceId: deviceId,
      roomName: _draft.googleHomeRoom,
      roomTemp: widget.roomTemp,
      targetTemp: _liveTargetTemp,
      boiler: liveBoiler,
      lang: _lang,
    );
    if (!mounted) return;
    final nextDraft = _draft.copyWith(
      espDeviceId: deviceId,
      firebaseRtdbUrl: rtdbUrl,
      espOnline: res.ok,
      espLastPingAt: res.timestampLabel,
      espWdtResetCount: !res.ok && _draft.espWdtEnabled
          ? _draft.espWdtResetCount + 1
          : _draft.espWdtResetCount,
      espLogs: EspLogService.appendLog(_draft.espLogs, res.logEntry),
    );
    setState(() {
      _espPingBusy = false;
      _espPingOk = res.ok;
      _espPingStatus = _lang == LangCode.tr ? res.messageTr : res.messageEn;
      _draft = nextDraft;
    });
    widget.onSaveSettings(nextDraft);
  }

  Future<void> _refreshTurkishVoices() async {
    VoiceSpeechService.warmup();
    final list = await VoiceSpeechService.listTurkishVoicesDetailed();
    if (mounted) {
      setState(() {
        _trVoices = list;
        _voicesLoaded = true;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    _draft = widget.initialSettings;
    _lang = widget.lang;
    _location = widget.locationName;
    _liveTargetTemp = widget.targetTemp;
    _firebaseUrlCtrl.text = _draft.firebaseRtdbUrl;
    _firebaseApiKeyCtrl.text = _draft.firebaseApiKey;
    _firebaseNodeCtrl.text = _draft.firebaseNodePath;
    _espIdCtrl.text = _draft.espDeviceId;
    _customAudioCtrl.text = _draft.customAudioLabel;
    _customVideoUrlCtrl.text = _draft.customVideoSource.startsWith('http')
        ? _draft.customVideoSource
        : _draft.customVideoLabel;
    _themesAudioAccordionExpanded = _draft.smartDisplayMode == SmartDisplayMode.liveNature;
    if (_draft.screensaverCustomBgSource.startsWith('http')) {
      _screensaverBgUrlCtrl.text = _draft.screensaverCustomBgSource;
    }
    HardwareService.detectHapticCapability().then((info) {
      if (mounted) setState(() => _hapticCap = info);
    });
    _refreshTurkishVoices();
  }

  @override
  void dispose() {
    if (_audioPreviewPlaying) {
      AmbientAudioService.stop();
    }
    _firebaseUrlCtrl.dispose();
    _firebaseApiKeyCtrl.dispose();
    _firebaseNodeCtrl.dispose();
    _espIdCtrl.dispose();
    _customAudioCtrl.dispose();
    _customVideoUrlCtrl.dispose();
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
    final typed = _customAudioCtrl.text.trim();
    var targetTrack = _draft.ambientSoundtrack;
    if (typed.startsWith('http://') || typed.startsWith('https://')) {
      targetTrack = AmbientSoundtrack.customMp3;
      if (mounted) {
        setState(() {
          _draft = _draft.copyWith(
            ambientSoundtrack: AmbientSoundtrack.customMp3,
            customAudioLabel: typed,
            customAudioSource: typed,
          );
        });
      }
    } else if (targetTrack == AmbientSoundtrack.silent) {
      await AmbientAudioService.stop();
      if (mounted) {
        setState(() {
          _audioPreviewPlaying = false;
          _statusBanner = _lang == LangCode.tr
              ? 'Sessiz mod seçili — dinlemek için bir ortam sesi seçin.'
              : 'Muted selected — pick an ambient soundtrack to preview.';
        });
      }
      return;
    }
    await AmbientAudioService.start(
      track: targetTrack,
      customSource: _resolveAudioSource(),
      volume: _draft.ambientVolume,
    );
    if (mounted) setState(() => _audioPreviewPlaying = true);
  }

  Future<void> _pickMultipleSlideImages() async {
    _hapticTap();
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        allowMultiple: true,
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final nextList = List<SmartDisplaySlideImage>.from(_draft.slideImages);
      var seq = 0;
      for (final file in result.files) {
        if (nextList.length >= 12) break;
        final bytes = file.bytes;
        if (bytes == null || bytes.isEmpty) continue;
        nextList.add(
          SmartDisplaySlideImage(
            id: '${DateTime.now().microsecondsSinceEpoch}_${seq++}',
            name: file.name,
            dataBase64: base64Encode(bytes),
            filePath: kIsWeb ? '' : (file.path ?? ''),
          ),
        );
      }
      if (!mounted) return;
      setState(() => _draft = _draft.copyWith(slideImages: nextList));
    } catch (_) {}
  }

  String _resolveVideoSource() {
    final typed = _customVideoUrlCtrl.text.trim();
    if (typed.startsWith('http://') ||
        typed.startsWith('https://') ||
        typed.startsWith('blob:') ||
        typed.startsWith('data:')) {
      return typed;
    }
    return _draft.customVideoSource.trim();
  }

  Future<void> _pickCustomVideo() async {
    _hapticTap();
    final tr = _lang == LangCode.tr;
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.video,
        allowMultiple: false,
        withData: kIsWeb,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      String source = '';
      if (kIsWeb) {
        final bytes = picked.bytes;
        if (bytes == null || bytes.isEmpty) {
          if (mounted) {
            setState(() {
              _statusBanner = tr
                  ? 'Video dosyası tarayıcıda okunamadı.'
                  : 'Could not read video bytes in browser.';
            });
          }
          return;
        }
        final ext = (picked.extension ?? '').toLowerCase();
        final mime = ext == 'webm'
            ? 'video/webm'
            : (ext == 'mov' ? 'video/quicktime' : 'video/mp4');
        VideoSourceBridge.revokeObjectUrl(_draft.customVideoSource);
        source = VideoSourceBridge.createObjectUrlFromBytes(bytes, mimeType: mime);
      } else {
        source = picked.path ?? '';
      }
      if (source.isEmpty || !mounted) return;
      setState(() {
        _customVideoUrlCtrl.text = picked.name;
        _draft = _draft.copyWith(
          smartDisplayMode: SmartDisplayMode.silentVideoMp3,
          customVideoLabel: picked.name,
          customVideoSource: source,
        );
        _statusBanner = tr
            ? 'Sessiz video yüklendi: ${picked.name}'
            : 'Muted video loaded: ${picked.name}';
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _statusBanner = tr ? 'Video seçilemedi.' : 'Could not select video.';
        });
      }
    }
  }

  void _clearCustomVideo() {
    _hapticTap();
    VideoSourceBridge.revokeObjectUrl(_draft.customVideoSource);
    _customVideoUrlCtrl.clear();
    setState(() {
      _draft = _draft.copyWith(
        customVideoLabel: '',
        customVideoSource: '',
      );
    });
  }

  void _showSlidePhotoPreviewDialog({
    required List<SmartDisplaySlideImage> images,
    int initialIndex = 0,
  }) {
    if (images.isEmpty) return;
    final tr = _lang == LangCode.tr;
    var currentIdx = initialIndex.clamp(0, images.length - 1);

    showDialog<void>(
      context: context,
      builder: (dCtx) => StatefulBuilder(
        builder: (dCtx, setModalState) {
          final currentList = _draft.slideImages;
          if (currentList.isEmpty) {
            return AlertDialog(
              backgroundColor: const Color(0xFF13131A),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
              content: Text(
                tr ? 'Görsel kalmadı.' : 'No images left.',
                style: const TextStyle(color: Colors.white70),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dCtx).pop(),
                  child: Text(tr ? 'Kapat' : 'Close'),
                ),
              ],
            );
          }
          if (currentIdx >= currentList.length) {
            currentIdx = currentList.length - 1;
          }
          final item = currentList[currentIdx];
          final bytes = item.decodeBytes();

          return Dialog(
            backgroundColor: const Color(0xFF12121A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
              side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 460, maxHeight: 540),
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.photo_size_select_actual_outlined, size: 17, color: Color(0xFF60A5FA)),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            '${item.name} (${currentIdx + 1}/${currentList.length})',
                            style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w700, color: Colors.white),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        IconButton(
                          onPressed: () => Navigator.of(dCtx).pop(),
                          icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                          tooltip: tr ? 'Kapat' : 'Close',
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Flexible(
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(14),
                        child: Container(
                          color: Colors.black,
                          constraints: const BoxConstraints(minHeight: 200, maxHeight: 340),
                          child: bytes != null
                              ? Image.memory(bytes, fit: BoxFit.contain)
                              : const Center(
                                  child: Icon(Icons.broken_image_outlined, size: 42, color: Colors.white38),
                                ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (currentList.length > 1)
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              OutlinedButton(
                                onPressed: () => setModalState(
                                  () => currentIdx = (currentIdx - 1 + currentList.length) % currentList.length,
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(38, 34),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                child: const Icon(Icons.chevron_left_rounded, size: 18, color: Colors.white),
                              ),
                              const SizedBox(width: 6),
                              OutlinedButton(
                                onPressed: () => setModalState(
                                  () => currentIdx = (currentIdx + 1) % currentList.length,
                                ),
                                style: OutlinedButton.styleFrom(
                                  minimumSize: const Size(38, 34),
                                  padding: const EdgeInsets.symmetric(horizontal: 10),
                                ),
                                child: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
                              ),
                            ],
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TextButton.icon(
                              onPressed: () {
                                _hapticTap();
                                final updated = List<SmartDisplaySlideImage>.from(_draft.slideImages)
                                  ..removeAt(currentIdx);
                                setState(() => _draft = _draft.copyWith(slideImages: updated));
                                if (updated.isEmpty) {
                                  Navigator.of(dCtx).pop();
                                } else {
                                  setModalState(() {});
                                }
                              },
                              icon: const Icon(Icons.delete_outline_rounded, size: 16, color: Color(0xFFFCA5A5)),
                              label: Text(
                                tr ? 'Sil' : 'Delete',
                                style: const TextStyle(color: Color(0xFFFCA5A5), fontWeight: FontWeight.w700),
                              ),
                            ),
                            const SizedBox(width: 6),
                            FilledButton(
                              onPressed: () => Navigator.of(dCtx).pop(),
                              style: FilledButton.styleFrom(
                                backgroundColor: const Color(0xFF2563EB),
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                              ),
                              child: Text(
                                tr ? 'Kapat' : 'Close',
                                style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Colors.white),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
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
                    if (_savedToastVisible)
                      Expanded(
                        child: Text(
                          _lang == LangCode.tr ? '✓ Ayarlar kaydedildi' : '✓ Settings saved',
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: Color(0xFF34D399),
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
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
                          final typedEspId = _espIdCtrl.text.trim();
                          final sanitizedNode = FirebaseSyncService.sanitizeNodePath(
                            _firebaseNodeCtrl.text.trim().isEmpty
                                ? _draft.firebaseNodePath
                                : _firebaseNodeCtrl.text.trim(),
                          );
                          final resolvedVideoSource = _resolveVideoSource();
                          final typedVideo = _customVideoUrlCtrl.text.trim();
                          final videoHost = Uri.tryParse(typedVideo)?.host ?? '';
                          final resolvedVideoLabel = resolvedVideoSource.isEmpty
                              ? ''
                              : (typedVideo.startsWith('http://') || typedVideo.startsWith('https://'))
                                  ? (videoHost.isNotEmpty ? videoHost : 'Video URL')
                                  : (_draft.customVideoLabel.isNotEmpty ? _draft.customVideoLabel : typedVideo);
                          final updated = _draft.copyWith(
                            firebaseRtdbUrl: _firebaseUrlCtrl.text.trim(),
                            firebaseApiKey: _firebaseApiKeyCtrl.text.trim(),
                            firebaseNodePath: sanitizedNode,
                            espDeviceId: typedEspId.isEmpty ? _draft.espDeviceId : typedEspId,
                            customAudioLabel: _customAudioCtrl.text.trim(),
                            customAudioSource: _resolveAudioSource(),
                            customVideoLabel: resolvedVideoLabel,
                            customVideoSource: resolvedVideoSource,
                          );
                          widget.onChangeLang(_lang);
                          widget.onChangeLocation(_location);
                          widget.onSaveSettings(updated);
                          setState(() {
                            _draft = updated;
                            _savedToastVisible = true;
                            _statusBanner = _lang == LangCode.tr
                                ? '✓ Tüm ayarlar kaydedildi.'
                                : '✓ All settings saved.';
                          });
                          Future.delayed(const Duration(seconds: 3), () {
                            if (mounted) {
                              setState(() => _savedToastVisible = false);
                            }
                          });
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

          // Expandable Sub-Panel Body (pure vertical slide down/up, zero horizontal squish)
          ClipRect(
            child: AnimatedSize(
              duration: const Duration(milliseconds: 220),
              curve: Curves.easeOutCubic,
              alignment: Alignment.topCenter,
              child: isExpanded
                  ? Container(
                      width: double.infinity,
                      padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Divider(height: 14, color: Colors.white.withValues(alpha: 0.08)),
                          _buildExpandedPanel(id),
                        ],
                      ),
                    )
                  : const SizedBox(width: double.infinity, height: 0),
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
              final nextSmart = !_draft.smartDisplayEnabled;
              setState(() => _draft = _draft.copyWith(
                smartDisplayEnabled: nextSmart,
                termoBotEnabled: nextSmart ? false : _draft.termoBotEnabled,
                smartDisplayAutoMinutes: nextSmart && _draft.smartDisplayAutoMinutes == 0
                    ? 5
                    : _draft.smartDisplayAutoMinutes,
              ));
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
              final nextBot = !_draft.termoBotEnabled;
              setState(() => _draft = _draft.copyWith(
                termoBotEnabled: nextBot,
                smartDisplayEnabled: nextBot ? false : _draft.smartDisplayEnabled,
              ));
            },
          ),
        );
      case SettingsItemId.aiPhoneCall:
        final callModeShort = switch (_draft.aiCallTriggerMode) {
          AiCallTriggerMode.onIgnition => tr ? 'Ateşleme' : 'Ignition',
          AiCallTriggerMode.ignitionAndSafety => tr ? 'Ateş+Emniyet' : 'Ign+Safety',
          AiCallTriggerMode.criticalOnly => tr ? 'Kritik' : 'Critical',
        };
        return _CardMeta(
          icon: Icons.phone_in_talk_outlined,
          iconColor: const Color(0xFF10B981),
          title: tr ? 'AI Sesli Telefon Araması (Asistan)' : 'AI Voice Call Assistant',
          tag: '${_draft.aiCallRingSeconds} sn · $callModeShort',
          subtitle: _draft.aiCallLastOutcome.isNotEmpty
              ? (tr ? 'Son arama: ${_draft.aiCallLastOutcome}' : 'Last call: ${_draft.aiCallLastOutcome}')
              : (tr ? 'Kombi ateşlendiğinde arar, sesli bilgi verir' : 'Calls on boiler ignition, alerts if missed'),
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
          tag: tr ? 'ESP32 / WDT · ${_draft.espLogs.length} kayıt' : 'ESP32 / WDT · ${_draft.espLogs.length} logs',
          subtitle: tr
              ? '${_draft.espOfflineBurnMinutes} dk çevrimdışı yanma · ${_draft.espWdtResetCount} WDT'
              : '${_draft.espOfflineBurnMinutes} min offline burn · ${_draft.espWdtResetCount} WDT',
          trailingAction: _ActionPill(
            label: _draft.espOnline ? (tr ? 'Çevrimiçi' : 'Online') : (tr ? 'Çevrimdışı' : 'Offline'),
            active: _draft.espOnline,
            color: _draft.espOnline ? const Color(0xFF10B981) : const Color(0xFFE11D48),
            onTap: () => _toggleExpand(id),
          ),
        );
      case SettingsItemId.cloudSync:
        final safeNode = FirebaseSyncService.sanitizeNodePath(_draft.firebaseNodePath);
        final intervalShort = _draft.cloudSyncIntervalSeconds == 0
            ? (tr ? 'Manuel' : 'Manual')
            : '${_draft.cloudSyncIntervalSeconds}sn';
        return _CardMeta(
          icon: Icons.sync_rounded,
          iconColor: const Color(0xFF38BDF8),
          title: tr ? 'Bulut Senkronizasyon & Veritabanı' : 'Cloud Sync & Database',
          tag: 'RTDB · /$safeNode · $intervalShort',
          subtitle: _draft.cloudLastSyncAt.isNotEmpty
              ? (tr
                  ? 'Son eşitleme ${_draft.cloudLastSyncAt} · ${_draft.cloudLastSyncOk ? 'Başarılı' : 'Hatalı'}'
                  : 'Last sync ${_draft.cloudLastSyncAt} · ${_draft.cloudLastSyncOk ? 'OK' : 'Error'}')
              : (tr ? 'Firebase gerçek zamanlı veri senkronizasyonu' : 'Firebase realtime telemetry sync'),
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
          (SmartDisplayVisualTheme.minimalist, '🌚 Minimalist'),
        ];

        final audioTracks = [
          (AmbientSoundtrack.silent, '🚫 ${tr ? 'Sessiz' : 'Muted'}'),
          (AmbientSoundtrack.fireplaceCrackling, '🔥 ${tr ? 'Şömine Çıtırtısı' : 'Fireplace'}'),
          (AmbientSoundtrack.nightRain, '🌧️ ${tr ? 'Sakin Yağmur' : 'Calm Rain'}'),
          (AmbientSoundtrack.cozyJazzLofi, '🎧 ${tr ? 'Lofi Akustik' : 'Lo-Fi Acoustic'}'),
          (AmbientSoundtrack.relaxPiano, '🎹 ${tr ? 'Relax Piyano' : 'Relax Piano'}'),
          (AmbientSoundtrack.forestBreeze, '🌲 ${tr ? 'Doğa & Kuşlar' : 'Nature & Birds'}'),
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
          return GestureDetector(
            onTap: () {
              _hapticTap();
              setState(() {
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
                        child: GestureDetector(
                          onTap: () {
                            _hapticTap();
                            setState(() => _draft = _draft.copyWith(smartDisplayLayout: layoutModes[idx].$1));
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

        Widget buildAudioPlaylistSection() {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr ? '🎵 Ortam Sesi Çalma Listesi:' : '🎵 Ambient Sound Playlist:',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFFFBBF24),
                ),
              ),
              const SizedBox(height: 7),
              Row(
                children: [
                  for (int idx = 0; idx < 3; idx++)
                    Expanded(
                      child: Padding(
                        padding: EdgeInsets.only(right: idx < 2 ? 6 : 0),
                        child: GestureDetector(
                          onTap: () {
                            _hapticTap();
                            final t = audioTracks[idx].$1;
                            setState(() => _draft = _draft.copyWith(ambientSoundtrack: t));
                            if (t == AmbientSoundtrack.silent) {
                              AmbientAudioService.stop();
                              setState(() => _audioPreviewPlaying = false);
                            } else if (_audioPreviewPlaying) {
                              AmbientAudioService.start(
                                track: t,
                                customSource: _resolveAudioSource(),
                                volume: _draft.ambientVolume,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _draft.ambientSoundtrack == audioTracks[idx].$1
                                  ? const Color(0xFFF59E0B)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _draft.ambientSoundtrack == audioTracks[idx].$1
                                    ? const Color(0xFFFCD34D)
                                    : Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Text(
                              audioTracks[idx].$2,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _draft.ambientSoundtrack == audioTracks[idx].$1
                                    ? Colors.black
                                    : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
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
                        child: GestureDetector(
                          onTap: () {
                            _hapticTap();
                            final t = audioTracks[idx].$1;
                            setState(() => _draft = _draft.copyWith(ambientSoundtrack: t));
                            if (_audioPreviewPlaying) {
                              AmbientAudioService.start(
                                track: t,
                                customSource: _resolveAudioSource(),
                                volume: _draft.ambientVolume,
                              );
                            }
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: _draft.ambientSoundtrack == audioTracks[idx].$1
                                  ? const Color(0xFFF59E0B)
                                  : Colors.white.withValues(alpha: 0.04),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: _draft.ambientSoundtrack == audioTracks[idx].$1
                                    ? const Color(0xFFFCD34D)
                                    : Colors.white.withValues(alpha: 0.10),
                              ),
                            ),
                            child: Text(
                              audioTracks[idx].$2,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: _draft.ambientSoundtrack == audioTracks[idx].$1
                                    ? Colors.black
                                    : Colors.white,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      tr ? '🔊 Ortam Sesi Seviyesi & Dışarıdan MP3:' : '🔊 Volume & External MP3:',
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
                  setState(() => _draft = _draft.copyWith(ambientVolume: v));
                  if (_audioPreviewPlaying) {
                    AmbientAudioService.setVolume(v);
                  }
                },
              ),
              Row(
                children: [
                  Expanded(
                    child: _DarkTextField(
                      controller: _customAudioCtrl,
                      hint: tr ? 'MP3 URL veya dosya adı' : 'MP3 URL or filename',
                    ),
                  ),
                  const SizedBox(width: 6),
                  FilledButton.tonalIcon(
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
                  const SizedBox(width: 6),
                  GestureDetector(
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
                ],
              ),
              const SizedBox(height: 8),
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
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Launch Smart Display Fullscreen CTA
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
                  final resolvedVideoSource = _resolveVideoSource();
                  final typedVideo = _customVideoUrlCtrl.text.trim();
                  final videoHost = Uri.tryParse(typedVideo)?.host ?? '';
                  final resolvedVideoLabel = resolvedVideoSource.isEmpty
                      ? ''
                      : (typedVideo.startsWith('http://') || typedVideo.startsWith('https://'))
                          ? (videoHost.isNotEmpty ? videoHost : 'Video URL')
                          : (_draft.customVideoLabel.isNotEmpty ? _draft.customVideoLabel : typedVideo);
                  final updated = _draft.copyWith(
                    customAudioLabel: _customAudioCtrl.text.trim(),
                    customAudioSource: _resolveAudioSource(),
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
                        FilledButton.icon(
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
                      ],
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: _DarkTextField(
                            controller: _customVideoUrlCtrl,
                            hint: tr ? 'Veya Video URL (https://...mp4 / webm)' : 'Or Video URL (https://...mp4)',
                          ),
                        ),
                        const SizedBox(width: 6),
                        FilledButton(
                          onPressed: () {
                            _hapticTap();
                            final raw = _customVideoUrlCtrl.text.trim();
                            if (raw.startsWith('http://') || raw.startsWith('https://')) {
                              final host = Uri.tryParse(raw)?.host ?? '';
                              setState(() {
                                _draft = _draft.copyWith(
                                  smartDisplayMode: SmartDisplayMode.silentVideoMp3,
                                  customVideoSource: raw,
                                  customVideoLabel: host.isNotEmpty ? host : 'Video URL',
                                );
                                _statusBanner = tr ? 'Video URL uygulandı.' : 'Video URL applied.';
                              });
                            } else {
                              setState(() {
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
                          GestureDetector(
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
                child: buildAudioPlaylistSection(),
              ),
              const SizedBox(height: 10),
            ],

            if (isLiveNature) ...[
              buildLayoutSelectorCard(),
              const SizedBox(height: 10),
              // Image 7: Default Visual Themes & Ambient Audio Card (ONLY visible in Canlı Video / Doğa!)
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
                        setState(() => _themesAudioAccordionExpanded = !_themesAudioAccordionExpanded);
                      },
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                tr ? '🎨 Varsayılan Temalar & Ambiyans Sesleri' : '🎨 Default Themes & Ambient Audio',
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
                                      child: GestureDetector(
                                        onTap: () {
                                          _hapticTap();
                                          setState(() => _draft = _draft.copyWith(
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
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              children: [
                                for (int idx = 3; idx < 6; idx++)
                                  Expanded(
                                    child: Padding(
                                      padding: EdgeInsets.only(right: idx < 5 ? 6 : 0),
                                      child: GestureDetector(
                                        onTap: () {
                                          _hapticTap();
                                          setState(() => _draft = _draft.copyWith(
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
                              ],
                            ),
                            const SizedBox(height: 11),
                            buildAudioPlaylistSection(),
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
                                    child: GestureDetector(
                                      onTap: () {
                                        _hapticTap();
                                        setState(() => _draft = _draft.copyWith(slideDurationSeconds: sec));
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
                                    child: GestureDetector(
                                      onTap: () {
                                        _hapticTap();
                                        setState(() => _draft = _draft.copyWith(slideEffect: eff.$1));
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
                        FilledButton.icon(
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
                      ],
                    ),
                    if (_draft.slideImages.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          OutlinedButton.icon(
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
                          const SizedBox(width: 7),
                          OutlinedButton.icon(
                            onPressed: () {
                              _hapticTap();
                              setState(() => _draft = _draft.copyWith(slideImages: const []));
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
                            final bytes = item.decodeBytes();
                            return Stack(
                              children: [
                                GestureDetector(
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
                                Positioned(
                                  top: 3,
                                  right: 3,
                                  child: GestureDetector(
                                    onTap: () {
                                      _hapticTap();
                                      final updated = List<SmartDisplaySlideImage>.from(_draft.slideImages)
                                        ..removeAt(idx);
                                      setState(() => _draft = _draft.copyWith(slideImages: updated));
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
                            child: GestureDetector(
                              onTap: () {
                                _hapticTap();
                                setState(() => _draft = _draft.copyWith(equalizerStyle: eq.$1, equalizerEnabled: true));
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
                    ? _draft.slideImages.first.decodeBytes()
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
                                              ? 'Oda ${widget.roomTemp.toStringAsFixed(1)}°C · Hedef ${_liveTargetTemp.toStringAsFixed(1)}°C'
                                              : 'Room ${widget.roomTemp.toStringAsFixed(1)}°C · Target ${_liveTargetTemp.toStringAsFixed(1)}°C',
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
                        onChanged: (v) => setState(() => _draft = _draft.copyWith(smartDisplayBlur: v)),
                      ),
                      Row(
                        children: [
                          for (int idx = 0; idx < blurPresets.length; idx++)
                            Expanded(
                              child: GestureDetector(
                                onTap: () {
                                  _hapticTap();
                                  setState(() => _draft = _draft.copyWith(smartDisplayBlur: blurPresets[idx].$1));
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
                                  '☀️ ${widget.roomTemp.toStringAsFixed(0)}°C - ${_liveTargetTemp.toStringAsFixed(1)}°C',
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
                    onChanged: (v) => setState(() => _draft = _draft.copyWith(displayBrightness: v.round())),
                  ),
                  Row(
                    children: [
                      for (final bp in brightnessPresets)
                        Expanded(
                          child: GestureDetector(
                            onTap: () {
                              _hapticTap();
                              setState(() => _draft = _draft.copyWith(displayBrightness: bp.$1));
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
                  _MiniToggleTile(
                    label: tr
                        ? '📺 Smart Display Otomatik Başlatma'
                        : '📺 Smart Display Auto-Activation',
                    value: _draft.smartDisplayEnabled,
                    activeColor: const Color(0xFFEA580C),
                    onTap: () {
                      _hapticTap();
                      final nextSmart = !_draft.smartDisplayEnabled;
                      setState(() => _draft = _draft.copyWith(
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
                        GestureDetector(
                          onTap: () {
                            _hapticTap();
                            final val = autoOpt.$1;
                            setState(() => _draft = _draft.copyWith(
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
            _MiniToggleTile(
              label: tr
                  ? '🤖 Maskot Ekran Koruyucu (Otomatik Mod)'
                  : '🤖 Mascot Screensaver (Auto Mode)',
              value: _draft.termoBotEnabled,
              activeColor: const Color(0xFFEA580C),
              onTap: () {
                _hapticTap();
                final nextBot = !_draft.termoBotEnabled;
                setState(() => _draft = _draft.copyWith(
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

      case SettingsItemId.aiPhoneCall:
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              tr
                  ? 'Kombi ateşlendiğinde veya kritik güvenlik eşiği aşıldığında asistan tam ekran telefon araması başlatır; cevaplarsanız sesli özet sunar ve arama ekranından sıcaklığı anında değiştirebilirsiniz.'
                  : 'Starts a fullscreen assistant phone call when boiler ignition or a critical safety alert triggers; answer for a voice summary and quick thermostat controls.',
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
                  GestureDetector(
                    onTap: () {
                      _hapticTap();
                      setState(() => _draft = _draft.copyWith(aiCallTriggerMode: mode));
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
              onChanged: (v) => setState(() => _draft = _draft.copyWith(aiCallRingSeconds: v.round())),
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
                setState(() => _draft = _draft.copyWith(aiCallVoiceBriefEnabled: v));
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
                setState(() => _draft = _draft.copyWith(aiCallMissedAlertEnabled: v));
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
                        GestureDetector(
                          onTap: () {
                            _hapticTap();
                            final cleared = _draft.copyWith(aiCallHistory: const [], aiCallLastOutcome: '');
                            setState(() => _draft = cleared);
                            widget.onSaveSettings(cleared);
                          },
                          child: Text(
                            tr ? 'Temizle' : 'Clear',
                            style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFFF87171)),
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
                          return GestureDetector(
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
                                  setState(() {
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
                      GestureDetector(
                        onTap: () {
                          _hapticTap();
                          _refreshTurkishVoices();
                        },
                        child: Text(
                          tr ? '↻ Sesleri Yenile' : '↻ Refresh Voices',
                          style: const TextStyle(fontSize: 10.5, fontWeight: FontWeight.w700, color: Color(0xFF38BDF8)),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Expanded(
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
                            setState(() {
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
                      const SizedBox(width: 6),
                      Expanded(
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
                            setState(() {
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
                          ChoiceChip(
                            label: Text(tr ? 'Otomatik' : 'Auto', style: const TextStyle(fontSize: 10, color: Colors.white)),
                            selected: _draft.femaleVoiceName.isEmpty,
                            selectedColor: const Color(0xFFEC4899).withValues(alpha: 0.35),
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            onSelected: (_) {
                              VoiceSpeechService.preferredFemaleVoice = '';
                              setState(() => _draft = _draft.copyWith(femaleVoiceName: ''));
                            },
                          ),
                          for (final v in _trVoices)
                            ChoiceChip(
                              label: Text(v.labelTr(), style: const TextStyle(fontSize: 10, color: Colors.white)),
                              selected: _draft.femaleVoiceName == v.name,
                              selectedColor: const Color(0xFFEC4899).withValues(alpha: 0.35),
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              onSelected: (_) {
                                VoiceSpeechService.preferredFemaleVoice = v.name;
                                setState(() => _draft = _draft.copyWith(femaleVoiceName: v.name));
                              },
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
                          ChoiceChip(
                            label: Text(tr ? 'Otomatik' : 'Auto', style: const TextStyle(fontSize: 10, color: Colors.white)),
                            selected: _draft.maleVoiceName.isEmpty,
                            selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                            backgroundColor: Colors.white.withValues(alpha: 0.06),
                            onSelected: (_) {
                              VoiceSpeechService.preferredMaleVoice = '';
                              setState(() => _draft = _draft.copyWith(maleVoiceName: ''));
                            },
                          ),
                          for (final v in _trVoices)
                            ChoiceChip(
                              label: Text(v.labelTr(), style: const TextStyle(fontSize: 10, color: Colors.white)),
                              selected: _draft.maleVoiceName == v.name,
                              selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.35),
                              backgroundColor: Colors.white.withValues(alpha: 0.06),
                              onSelected: (_) {
                                VoiceSpeechService.preferredMaleVoice = v.name;
                                setState(() => _draft = _draft.copyWith(maleVoiceName: v.name));
                              },
                            ),
                        ],
                      ),
                    ],
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
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
                  ActionChip(
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
              ],
            ),
          ],
        );

      case SettingsItemId.espLog:
        final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
        final filteredEspLogs = EspLogService.filterLogs(
          _draft.espLogs,
          category: _espLogFilter,
        );
        final warningEvents = EspLogService.countWatchdogEvents(_draft.espLogs);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                _InfoBadge(
                  text: _draft.espOnline
                      ? (tr
                          ? 'Çevrimiçi${_draft.espLastPingAt.isNotEmpty ? ' · ${_draft.espLastPingAt}' : ''}'
                          : 'Online${_draft.espLastPingAt.isNotEmpty ? ' · ${_draft.espLastPingAt}' : ''}')
                      : (tr ? 'Çevrimdışı' : 'Offline'),
                  color: _draft.espOnline ? const Color(0xFF10B981) : const Color(0xFFE11D48),
                ),
                _InfoBadge(
                  text: tr
                      ? 'WDT: ${_draft.espWdtResetCount} (${warningEvents} uyarı)'
                      : 'WDT: ${_draft.espWdtResetCount} (${warningEvents} alerts)',
                  color: const Color(0xFFFBBF24),
                ),
                _InfoBadge(
                  text: tr
                      ? 'Yanma: ${_draft.espOfflineBurnMinutes} dk'
                      : 'Burn: ${_draft.espOfflineBurnMinutes} min',
                  color: const Color(0xFFF97316),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _DarkTextField(
                    controller: _espIdCtrl,
                    hint: tr ? 'ESP32 Cihaz Kimliği (ör. ESP32-KOMBI-01)' : 'ESP32 Device ID',
                  ),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: _espPingBusy ? null : _runEspConnectionTest,
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFFBBF24).withValues(alpha: 0.22),
                    foregroundColor: const Color(0xFFFDE68A),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: BorderSide(color: const Color(0xFFFBBF24).withValues(alpha: 0.45)),
                    ),
                  ),
                  icon: _espPingBusy
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFDE68A)),
                        )
                      : const Icon(Icons.wifi_tethering_rounded, size: 16),
                  label: Text(
                    tr ? 'Ping' : 'Ping',
                    style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
            if (_espPingStatus != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (_espPingOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (_espPingOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  _espPingStatus!,
                  style: TextStyle(
                    fontSize: 11,
                    color: _espPingOk ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniToggleTile(
                    label: tr ? 'WDT Kilitlenme İzleme' : 'WDT Lockup Watchdog',
                    value: _draft.espWdtEnabled,
                    activeColor: const Color(0xFFFBBF24),
                    onTap: () {
                      _hapticTap();
                      final next = _draft.copyWith(espWdtEnabled: !_draft.espWdtEnabled);
                      setState(() => _draft = next);
                      widget.onSaveSettings(next);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniToggleTile(
                    label: tr ? 'NVS Çevrimdışı Tampon' : 'NVS Offline Buffer',
                    value: _draft.espOfflineBufferEnabled,
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      _hapticTap();
                      final next = _draft.copyWith(
                        espOfflineBufferEnabled: !_draft.espOfflineBufferEnabled,
                      );
                      setState(() => _draft = next);
                      widget.onSaveSettings(next);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: const Icon(Icons.add_chart_rounded, size: 14, color: Color(0xFF38BDF8)),
                  label: Text(
                    tr ? 'Anlık Kayıt Al' : 'Log Snapshot',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  onPressed: () {
                    _hapticTap();
                    final nowLabel = NotificationService.formatNowTime();
                    final devId = _espIdCtrl.text.trim().isEmpty
                        ? _draft.espDeviceId
                        : _espIdCtrl.text.trim();
                    final entry = EspLogEntry(
                      timestamp: nowLabel,
                      event: liveBoiler.isHeating
                          ? (tr ? 'Modülasyon %${liveBoiler.flamePercent}' : 'Modulation %${liveBoiler.flamePercent}')
                          : (tr ? 'Bekleme Telemetrisi' : 'Standby Telemetry'),
                      detail:
                          '$devId · ${widget.roomTemp.toStringAsFixed(1)}°C → ${_liveTargetTemp.toStringAsFixed(1)}°C · ${liveBoiler.waterPressureBar.toStringAsFixed(1)} Bar',
                      category: liveBoiler.isHeating ? EspLogCategory.burner : EspLogCategory.system,
                    );
                    final next = _draft.copyWith(
                      espDeviceId: devId,
                      espLogs: EspLogService.appendLog(_draft.espLogs, entry),
                    );
                    setState(() {
                      _draft = next;
                      _espPingOk = true;
                      _espPingStatus = tr
                          ? 'Anlık telemetri kaydı NVS günlüğüne eklendi ($nowLabel).'
                          : 'Live telemetry snapshot appended ($nowLabel).';
                    });
                    widget.onSaveSettings(next);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.warning_amber_rounded, size: 14, color: Color(0xFFFBBF24)),
                  label: Text(
                    tr ? 'WDT Testi' : 'WDT Test',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  onPressed: () {
                    _hapticTap();
                    final nowLabel = NotificationService.formatNowTime();
                    final devId = _espIdCtrl.text.trim().isEmpty
                        ? _draft.espDeviceId
                        : _espIdCtrl.text.trim();
                    final entry = EspLogEntry(
                      timestamp: nowLabel,
                      event: tr ? 'WDT Tetikleme Testi' : 'WDT Reset Self-Test',
                      detail: tr
                          ? '$devId · Çekirdek güvenli kurtarma doğrulandı'
                          : '$devId · Core recovery verified',
                      isWarning: true,
                      category: EspLogCategory.watchdog,
                    );
                    final next = _draft.copyWith(
                      espDeviceId: devId,
                      espWdtResetCount: _draft.espWdtResetCount + 1,
                      espLogs: EspLogService.appendLog(_draft.espLogs, entry),
                    );
                    setState(() {
                      _draft = next;
                      _espPingOk = true;
                      _espPingStatus = tr
                          ? 'WDT kurtarma testi kaydedildi (#${next.espWdtResetCount}).'
                          : 'WDT recovery test logged (#${next.espWdtResetCount}).';
                    });
                    widget.onSaveSettings(next);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.copy_all_rounded, size: 14, color: Color(0xFF10B981)),
                  label: Text(
                    tr ? 'Raporu Kopyala' : 'Copy Report',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  onPressed: () async {
                    _hapticTap();
                    final report = EspLogService.exportLogsReport(
                      settings: _draft.copyWith(
                        espDeviceId: _espIdCtrl.text.trim().isEmpty
                            ? _draft.espDeviceId
                            : _espIdCtrl.text.trim(),
                      ),
                      roomTemp: widget.roomTemp,
                      targetTemp: _liveTargetTemp,
                      boiler: liveBoiler,
                      lang: _lang,
                    );
                    await Clipboard.setData(ClipboardData(text: report));
                    if (!mounted) return;
                    setState(() {
                      _espPingOk = true;
                      _espPingStatus = tr
                          ? 'ESP32 donanım raporu panoya kopyalandı (${_draft.espLogs.length} kayıt).'
                          : 'ESP32 hardware report copied (${_draft.espLogs.length} logs).';
                    });
                  },
                ),
                if (_draft.espLogs.isNotEmpty)
                  ActionChip(
                    avatar: const Icon(Icons.delete_outline_rounded, size: 14, color: Color(0xFFF87171)),
                    label: Text(
                      tr ? 'Temizle' : 'Clear',
                      style: const TextStyle(fontSize: 11, color: Colors.white),
                    ),
                    backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.12),
                    side: BorderSide(color: const Color(0xFFEF4444).withValues(alpha: 0.35)),
                    onPressed: () {
                      _hapticTap();
                      final next = _draft.copyWith(
                        espLogs: const [],
                        espOfflineBurnMinutes: 0,
                        espWdtResetCount: 0,
                      );
                      setState(() {
                        _draft = next;
                        _espPingOk = true;
                        _espPingStatus = tr
                            ? 'ESP32 donanım günlüğü ve sayaçlar temizlendi.'
                            : 'ESP32 hardware logs and counters cleared.';
                      });
                      widget.onSaveSettings(next);
                    },
                  ),
              ],
            ),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final filterOpt in <(EspLogCategory?, String)>[
                    (null, tr ? 'Tümü (${_draft.espLogs.length})' : 'All (${_draft.espLogs.length})'),
                    (EspLogCategory.burner, tr ? 'Yanma' : 'Burner'),
                    (EspLogCategory.watchdog, tr ? 'WDT / Uyarı' : 'WDT / Alert'),
                    (EspLogCategory.sync, tr ? 'Bulut' : 'Cloud'),
                  ]) ...[
                    ChoiceChip(
                      label: Text(filterOpt.$2, style: const TextStyle(fontSize: 10.5)),
                      selected: _espLogFilter == filterOpt.$1,
                      selectedColor: const Color(0xFFFBBF24).withValues(alpha: 0.25),
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      labelStyle: TextStyle(
                        color: _espLogFilter == filterOpt.$1 ? const Color(0xFFFDE68A) : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: _espLogFilter == filterOpt.$1
                            ? const Color(0xFFFBBF24).withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      onSelected: (_) {
                        _hapticTap();
                        setState(() => _espLogFilter = filterOpt.$1);
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (filteredEspLogs.isEmpty)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.03),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                ),
                child: Text(
                  tr ? 'Bu filtrede kayıtlı ESP32 donanım günlüğü yok.' : 'No ESP32 hardware logs match this filter.',
                  style: TextStyle(fontSize: 11.5, color: Colors.white.withValues(alpha: 0.55)),
                ),
              )
            else
              for (final log in filteredEspLogs) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: log.isWarning
                        ? const Color(0xFFF59E0B).withValues(alpha: 0.10)
                        : Colors.white.withValues(alpha: 0.04),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: log.isWarning
                          ? const Color(0xFFFBBF24).withValues(alpha: 0.35)
                          : Colors.white.withValues(alpha: 0.09),
                    ),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Icon(
                          log.category == EspLogCategory.burner
                              ? Icons.local_fire_department_rounded
                              : log.category == EspLogCategory.watchdog
                                  ? Icons.warning_amber_rounded
                                  : log.category == EspLogCategory.sync
                                      ? Icons.cloud_done_outlined
                                      : Icons.memory_rounded,
                          size: 15,
                          color: log.isWarning
                              ? const Color(0xFFFBBF24)
                              : log.category == EspLogCategory.burner
                                  ? const Color(0xFFFB923C)
                                  : log.category == EspLogCategory.sync
                                      ? const Color(0xFF34D399)
                                      : const Color(0xFF38BDF8),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    log.event,
                                    style: TextStyle(
                                      fontSize: 11.5,
                                      fontWeight: FontWeight.w700,
                                      color: log.isWarning ? Colors.amber.shade200 : Colors.white,
                                    ),
                                  ),
                                ),
                                if (log.durationSeconds > 0) ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFF97316).withValues(alpha: 0.18),
                                      borderRadius: BorderRadius.circular(7),
                                    ),
                                    child: Text(
                                      EspLogService.formatDurationBadge(log.durationSeconds, _lang),
                                      style: const TextStyle(
                                        fontSize: 9.5,
                                        fontWeight: FontWeight.w700,
                                        color: Color(0xFFFDBA74),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                ],
                                Text(
                                  log.timestamp,
                                  style: const TextStyle(fontSize: 10.5, color: Colors.white54),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Text(
                              log.detail,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.white.withValues(alpha: 0.68),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ],
          ],
        );

      case SettingsItemId.cloudSync:
        final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
        final activeNode = FirebaseSyncService.sanitizeNodePath(
          _firebaseNodeCtrl.text.trim().isEmpty ? _draft.firebaseNodePath : _firebaseNodeCtrl.text.trim(),
        );
        final urlValid = FirebaseSyncService.validateRtdbUrl(
          _firebaseUrlCtrl.text.trim().isEmpty ? _draft.firebaseRtdbUrl : _firebaseUrlCtrl.text.trim(),
        );
        final statusText = _cloudSyncStatus ??
            (_draft.cloudLastSyncMessage.isNotEmpty ? _draft.cloudLastSyncMessage : null);
        final statusIsOk = _cloudSyncStatus != null ? _cloudSyncOk : _draft.cloudLastSyncOk;
        final payloadPreview = FirebaseSyncService.buildPayloadPreviewJson(
          roomName: _draft.googleHomeRoom,
          espDeviceId: _espIdCtrl.text.trim().isEmpty ? _draft.espDeviceId : _espIdCtrl.text.trim(),
          roomTemp: widget.roomTemp,
          targetTemp: _liveTargetTemp,
          boiler: liveBoiler,
        );
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withValues(alpha: 0.09)),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Flexible(
                    child: Text(
                      tr ? 'Bulut Senkronizasyon Durumu:' : 'Cloud Sync Status:',
                      style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: (_draft.cloudSyncEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(
                        color: (_draft.cloudSyncEnabled ? const Color(0xFF10B981) : const Color(0xFFF59E0B)).withValues(alpha: 0.45),
                      ),
                    ),
                    child: Text(
                      _draft.cloudSyncEnabled
                          ? (tr ? '• Bağlı (Bulut Aktif)' : '• Connected (Cloud)')
                          : (tr ? '• Çevrimdışı (Yerel Mod)' : '• Offline (Local Mode)'),
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _draft.cloudSyncEnabled ? const Color(0xFF6EE7B7) : const Color(0xFFFCD34D),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.storage_rounded, size: 15, color: Color(0xFF38BDF8)),
                const SizedBox(width: 6),
                Text(
                  'Firebase Database URL:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.90)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _DarkTextField(
              controller: _firebaseUrlCtrl,
              hint: 'https://kombi-kontrol-babd5-default-rtdb.firebaseio.com',
              keyboardType: TextInputType.url,
              textColor: const Color(0xFFFCD34D),
              monospace: true,
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                const Icon(Icons.vpn_key_outlined, size: 15, color: Color(0xFFFBBF24)),
                const SizedBox(width: 6),
                Text(
                  'Firebase Web API Key:',
                  style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.90)),
                ),
              ],
            ),
            const SizedBox(height: 6),
            _DarkTextField(
              controller: _firebaseApiKeyCtrl,
              hint: tr ? 'Firebase Web API Key veya RTDB Gizli Anahtarı girin' : 'Enter Firebase Web API Key',
              obscure: true,
              textColor: const Color(0xFFFCD34D),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _DarkTextField(
                    controller: _firebaseNodeCtrl,
                    hint: tr ? 'RTDB Düğüm Yolu (kombi)' : 'RTDB Node Path (kombi)',
                  ),
                ),
                const SizedBox(width: 8),
                _InfoBadge(
                  text: '/$activeNode.json',
                  color: const Color(0xFF38BDF8),
                ),
                const SizedBox(width: 6),
                _InfoBadge(
                  text: urlValid
                      ? (tr ? 'URL Geçerli' : 'Valid')
                      : (tr ? 'URL Geçersiz' : 'Invalid'),
                  color: urlValid ? const Color(0xFF10B981) : const Color(0xFFF59E0B),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _MiniToggleTile(
                    label: tr ? 'Gerçek Zamanlı Sync' : 'Realtime Sync',
                    value: _draft.cloudSyncEnabled,
                    activeColor: const Color(0xFF38BDF8),
                    onTap: () {
                      _hapticTap();
                      final next = _draft.copyWith(cloudSyncEnabled: !_draft.cloudSyncEnabled);
                      setState(() => _draft = next);
                      widget.onSaveSettings(next);
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _MiniToggleTile(
                    label: tr ? 'Uzaktan Hedefi Çek' : 'Auto-Pull Target',
                    value: _draft.cloudAutoPullEnabled,
                    activeColor: const Color(0xFF10B981),
                    onTap: () {
                      _hapticTap();
                      final next = _draft.copyWith(
                        cloudAutoPullEnabled: !_draft.cloudAutoPullEnabled,
                      );
                      setState(() => _draft = next);
                      widget.onSaveSettings(next);
                    },
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              tr ? 'Otomatik Senkronizasyon Periyodu' : 'Auto Sync Interval',
              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Colors.white.withValues(alpha: 0.65)),
            ),
            const SizedBox(height: 6),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (final opt in <(int, String)>[
                    (0, tr ? 'Manuel' : 'Manual'),
                    (15, tr ? '15 sn' : '15s'),
                    (30, tr ? '30 sn' : '30s'),
                    (60, tr ? '60 sn' : '60s'),
                    (180, tr ? '3 dk' : '3m'),
                  ]) ...[
                    ChoiceChip(
                      label: Text(opt.$2, style: const TextStyle(fontSize: 10.5)),
                      selected: _draft.cloudSyncIntervalSeconds == opt.$1,
                      selectedColor: const Color(0xFF38BDF8).withValues(alpha: 0.25),
                      backgroundColor: Colors.white.withValues(alpha: 0.05),
                      labelStyle: TextStyle(
                        color: _draft.cloudSyncIntervalSeconds == opt.$1 ? const Color(0xFFBAE6FD) : Colors.white70,
                        fontWeight: FontWeight.w600,
                      ),
                      side: BorderSide(
                        color: _draft.cloudSyncIntervalSeconds == opt.$1
                            ? const Color(0xFF38BDF8).withValues(alpha: 0.55)
                            : Colors.white.withValues(alpha: 0.12),
                      ),
                      onSelected: (_) {
                        _hapticTap();
                        final next = _draft.copyWith(cloudSyncIntervalSeconds: opt.$1);
                        setState(() => _draft = next);
                        widget.onSaveSettings(next);
                      },
                    ),
                    const SizedBox(width: 6),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cloudSyncBusy ? null : () => _runCloudPush(pullInstead: false),
                    icon: _cloudSyncBusy
                        ? const SizedBox(
                            width: 14,
                            height: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF6EE7B7)),
                          )
                        : const Icon(Icons.cloud_upload_outlined, size: 16),
                    label: Text(
                      tr ? 'Buluta Gönder' : 'Push to RTDB',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF6EE7B7),
                      side: BorderSide(color: const Color(0xFF10B981).withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _cloudSyncBusy ? null : () => _runCloudPush(pullInstead: true),
                    icon: const Icon(Icons.cloud_download_outlined, size: 16),
                    label: Text(
                      tr ? 'Buluttan Çek' : 'Pull from RTDB',
                      style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.w700),
                    ),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFF7DD3FC),
                      side: BorderSide(color: const Color(0xFF38BDF8).withValues(alpha: 0.45)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    ),
                  ),
                ),
              ],
            ),
            if (statusText != null) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                decoration: BoxDecoration(
                  color: (statusIsOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: (statusIsOk ? const Color(0xFF10B981) : const Color(0xFFE11D48)).withValues(alpha: 0.35),
                  ),
                ),
                child: Text(
                  statusText,
                  style: TextStyle(
                    fontSize: 11,
                    color: statusIsOk ? const Color(0xFFA7F3D0) : const Color(0xFFFECDD3),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 10),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                ActionChip(
                  avatar: Icon(
                    _showCloudPayloadPreview ? Icons.code_off_rounded : Icons.data_object_rounded,
                    size: 14,
                    color: const Color(0xFF38BDF8),
                  ),
                  label: Text(
                    _showCloudPayloadPreview
                        ? (tr ? 'JSON Önizlemeyi Gizle' : 'Hide JSON Preview')
                        : (tr ? 'Canlı JSON Önizleme' : 'Live JSON Preview'),
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  onPressed: () {
                    _hapticTap();
                    setState(() => _showCloudPayloadPreview = !_showCloudPayloadPreview);
                  },
                ),
                ActionChip(
                  avatar: const Icon(Icons.copy_rounded, size: 14, color: Color(0xFF10B981)),
                  label: Text(
                    tr ? 'JSON Kopyala' : 'Copy JSON',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: BorderSide(color: Colors.white.withValues(alpha: 0.14)),
                  onPressed: () async {
                    _hapticTap();
                    await Clipboard.setData(ClipboardData(text: payloadPreview));
                    if (!mounted) return;
                    setState(() {
                      _cloudSyncOk = true;
                      _cloudSyncStatus = tr
                          ? '/$activeNode.json telemetri yükü panoya kopyalandı.'
                          : '/$activeNode.json telemetry payload copied.';
                    });
                  },
                ),
              ],
            ),
            if (_showCloudPayloadPreview) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.48),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white.withValues(alpha: 0.10)),
                ),
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Text(
                    payloadPreview,
                    style: const TextStyle(
                      fontSize: 10.5,
                      fontFamily: 'monospace',
                      color: Color(0xFFBAE6FD),
                      height: 1.35,
                    ),
                  ),
                ),
              ),
            ],
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
  final Color textColor;
  final bool monospace;

  const _DarkTextField({
    required this.controller,
    required this.hint,
    this.obscure = false,
    this.keyboardType,
    this.textColor = Colors.white,
    this.monospace = false,
  });

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      obscureText: obscure,
      keyboardType: keyboardType,
      style: TextStyle(
        fontSize: 12.5,
        color: textColor,
        fontFamily: monospace ? 'monospace' : null,
      ),
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

