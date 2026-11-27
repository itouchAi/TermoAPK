import 'dart:async';
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
import '../services/media_storage_service.dart';
import '../services/notification_service.dart';
import '../services/video_source_bridge.dart';
import '../services/voice_gender_classifier.dart';
import '../services/voice_speech_service.dart';
import '../widgets/missed_call_alert.dart';
import '../widgets/termo_bot.dart';
import 'google_home_sheet.dart';
import 'vault_center_sheet.dart';
import '../widgets/tactile_button.dart';
import 'settings/settings_widgets.dart';
part 'settings/assistant_settings_sections.dart';
part 'settings/cloud_esp_settings_sections.dart';
part 'settings/smart_display_settings_section.dart';

Future<void> showSystemSettingsSheet({
  required BuildContext context,
  required LangCode lang,
  required String locationName,
  required Color accentColor,
  required double? roomTemp,
  required double targetTemp,
  double? outsideTemp,
  required BoilerTelemetry boiler,
  BoilerHardwareSensors sensors = const BoilerHardwareSensors.disconnected(),
  required SystemSettingsState initialSettings,
  SettingsItemId? initialExpandedId,
  required ValueChanged<LangCode> onChangeLang,
  required ValueChanged<String> onChangeLocation,
  required ValueChanged<double> onChangeTargetTemp,
  ValueChanged<double>? onApplyRemoteRoomTemp,
  ValueChanged<BoilerHardwareSensors>? onApplyRemoteSensors,
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
      outsideTemp: outsideTemp,
      boiler: boiler,
      sensors: sensors,
      initialSettings: initialSettings,
      initialExpandedId: initialExpandedId,
      onChangeLang: onChangeLang,
      onChangeLocation: onChangeLocation,
      onChangeTargetTemp: onChangeTargetTemp,
      onApplyRemoteRoomTemp: onApplyRemoteRoomTemp,
      onApplyRemoteSensors: onApplyRemoteSensors,
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
  final double? roomTemp;
  final double targetTemp;
  final double? outsideTemp;
  final BoilerTelemetry boiler;
  final BoilerHardwareSensors sensors;
  final SystemSettingsState initialSettings;
  final SettingsItemId? initialExpandedId;
  final ValueChanged<LangCode> onChangeLang;
  final ValueChanged<String> onChangeLocation;
  final ValueChanged<double> onChangeTargetTemp;
  final ValueChanged<double>? onApplyRemoteRoomTemp;
  final ValueChanged<BoilerHardwareSensors>? onApplyRemoteSensors;
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
    this.outsideTemp,
    required this.boiler,
    this.sensors = const BoilerHardwareSensors.disconnected(),
    required this.initialSettings,
    this.initialExpandedId,
    required this.onChangeLang,
    required this.onChangeLocation,
    required this.onChangeTargetTemp,
    this.onApplyRemoteRoomTemp,
    this.onApplyRemoteSensors,
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
  void _updateState(VoidCallback fn) {
    if (mounted) setState(fn);
  }
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
            targetTemp: _liveTargetTemp,
            boiler: liveBoiler,
          );
    if (!mounted) return;
    final nowLabel = NotificationService.formatNowTime();
    final msg = _lang == LangCode.tr ? res.messageTr : res.messageEn;

    if (pullInstead && res.ok) {
      if (res.remoteRoomTemp != null) {
        widget.onApplyRemoteRoomTemp?.call(res.remoteRoomTemp!);
      }
      if (res.remoteTargetTemp != null) {
        _liveTargetTemp = res.remoteTargetTemp!;
        widget.onChangeTargetTemp(res.remoteTargetTemp!);
      }
      if (res.remoteSensors != null) {
        widget.onApplyRemoteSensors?.call(res.remoteSensors!);
      }
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
    _expandedId = widget.initialExpandedId;
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
        withData: true,
      );
      if (result == null || result.files.isEmpty) return;
      final picked = result.files.first;
      final bytes = picked.bytes;
      if (bytes != null && bytes.isNotEmpty) {
        AmbientAudioService.setCustomAudioBytes(bytes);
      }
      final persisted = await MediaStorageService.persistPickedFile(
        key: MediaStorageService.customAudioKey,
        sourcePath: kIsWeb ? null : picked.path,
        bytes: bytes,
        mimeType: 'audio/mpeg',
        fileName: picked.name,
      );
      final source = persisted.isNotEmpty ? persisted : (kIsWeb ? MediaStorageService.customAudioKey : (picked.path ?? picked.name));
      if (!mounted) return;
      setState(() {
        _customAudioCtrl.text = picked.name;
        _draft = _draft.copyWith(
          ambientSoundtrack: AmbientSoundtrack.customMp3,
          customAudioLabel: picked.name,
          customAudioSource: source,
        );
      });
      widget.onSaveSettings(_draft);
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
    final source = _resolveAudioSource();
    if (typed.startsWith('http://') || typed.startsWith('https://')) {
      if (mounted) {
        setState(() {
          _draft = _draft.copyWith(
            ambientSoundtrack: AmbientSoundtrack.customMp3,
            customAudioLabel: typed,
            customAudioSource: typed,
          );
        });
      }
      await AmbientAudioService.start(
        track: AmbientSoundtrack.customMp3,
        customSource: typed,
        volume: _draft.ambientVolume,
      );
      if (mounted) setState(() => _audioPreviewPlaying = true);
      return;
    }
    if (source.isEmpty) {
      await AmbientAudioService.stop();
      if (mounted) {
        setState(() {
          _audioPreviewPlaying = false;
          _statusBanner = _lang == LangCode.tr
              ? 'Dinlemek için MP3 dosyası seçin veya geçerli bir MP3 URL girin.'
              : 'Pick an MP3 file or enter an MP3 URL to preview.';
        });
      }
      return;
    }
    if (MediaStorageService.isPersistedKey(source) && !AmbientAudioService.canPlayCustomAudio(source)) {
      final restored = await MediaStorageService.loadBytes(source);
      if (restored != null && restored.isNotEmpty) {
        AmbientAudioService.setCustomAudioBytes(restored);
      }
    }
    if (!AmbientAudioService.canPlayCustomAudio(source)) {
      await AmbientAudioService.stop();
      if (mounted) {
        setState(() {
          _audioPreviewPlaying = false;
          _statusBanner = _lang == LangCode.tr
              ? 'Ses dosyası bulunamadı. Yeni MP3 seçin veya URL girin.'
              : 'Audio file missing. Pick an MP3 file or enter a URL.';
        });
      }
      return;
    }
    if (_draft.ambientSoundtrack != AmbientSoundtrack.customMp3 && mounted) {
      setState(() {
        _draft = _draft.copyWith(ambientSoundtrack: AmbientSoundtrack.customMp3);
      });
    }
    await AmbientAudioService.start(
      track: AmbientSoundtrack.customMp3,
      customSource: source,
      volume: _draft.ambientVolume,
    );
    if (mounted) setState(() => _audioPreviewPlaying = AmbientAudioService.isPlaying);
  }

  Uint8List? _resolveSlideBytes(SmartDisplaySlideImage item) {
    if (item.filePath.isNotEmpty) {
      final cached = MediaStorageService.getCachedBytes(item.filePath);
      if (cached != null && cached.isNotEmpty) return cached;
      if (MediaStorageService.isPersistedKey(item.filePath)) {
        unawaited(
          MediaStorageService.loadBytes(item.filePath).then((loaded) {
            if (loaded != null && loaded.isNotEmpty && mounted) {
              setState(() {});
            }
          }),
        );
      }
    }
    return item.decodeBytes();
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
        final id = '${DateTime.now().microsecondsSinceEpoch}_${seq++}';
        final ext = (file.extension ?? 'jpg').toLowerCase();
        final mime = ext == 'png'
            ? 'image/png'
            : (ext == 'webp' ? 'image/webp' : 'image/jpeg');
        final persistedRef = await MediaStorageService.persistPickedFile(
          key: MediaStorageService.slideImageKey(id),
          sourcePath: kIsWeb ? null : file.path,
          bytes: bytes,
          mimeType: mime,
          fileName: file.name,
        );
        nextList.add(
          SmartDisplaySlideImage(
            id: id,
            name: file.name,
            dataBase64: persistedRef.isEmpty ? base64Encode(bytes) : '',
            filePath: persistedRef,
          ),
        );
      }
      if (!mounted) return;
      setState(() => _draft = _draft.copyWith(slideImages: nextList));
      widget.onSaveSettings(_draft);
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
        source = await MediaStorageService.persistPickedFile(
          key: MediaStorageService.customVideoKey,
          bytes: bytes,
          mimeType: mime,
          fileName: picked.name,
        );
      } else {
        source = await MediaStorageService.persistPickedFile(
          key: MediaStorageService.customVideoKey,
          sourcePath: picked.path,
          fileName: picked.name,
        );
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
            ? 'Sessiz video kalıcı olarak kaydedildi: ${picked.name}'
            : 'Muted video saved persistently: ${picked.name}';
      });
      widget.onSaveSettings(_draft);
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
    final prev = _draft.customVideoSource;
    VideoSourceBridge.revokeObjectUrl(prev);
    unawaited(MediaStorageService.deleteMedia(prev));
    _customVideoUrlCtrl.clear();
    setState(() {
      _draft = _draft.copyWith(
        customVideoLabel: '',
        customVideoSource: '',
      );
    });
    widget.onSaveSettings(_draft);
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
                TactilePress(
                  child: TextButton(
                    onPressed: () => Navigator.of(dCtx).pop(),
                    child: Text(tr ? 'Kapat' : 'Close'),
                  ),
                ),
              ],
            );
          }
          if (currentIdx >= currentList.length) {
            currentIdx = currentList.length - 1;
          }
          final item = currentList[currentIdx];
          final bytes = _resolveSlideBytes(item);

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
                        TactilePress(
                          child: IconButton(
                            onPressed: () => Navigator.of(dCtx).pop(),
                            icon: const Icon(Icons.close_rounded, color: Colors.white70, size: 20),
                            tooltip: tr ? 'Kapat' : 'Close',
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
                          ),
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
                              TactilePress(
                                child: OutlinedButton(
                                  onPressed: () => setModalState(
                                    () => currentIdx = (currentIdx - 1 + currentList.length) % currentList.length,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(38, 34),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  child: const Icon(Icons.chevron_left_rounded, size: 18, color: Colors.white),
                                ),
                              ),
                              const SizedBox(width: 6),
                              TactilePress(
                                child: OutlinedButton(
                                  onPressed: () => setModalState(
                                    () => currentIdx = (currentIdx + 1) % currentList.length,
                                  ),
                                  style: OutlinedButton.styleFrom(
                                    minimumSize: const Size(38, 34),
                                    padding: const EdgeInsets.symmetric(horizontal: 10),
                                  ),
                                  child: const Icon(Icons.chevron_right_rounded, size: 18, color: Colors.white),
                                ),
                              ),
                            ],
                          )
                        else
                          const SizedBox.shrink(),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            TactilePress(
                              child: TextButton.icon(
                                onPressed: () {
                                  _hapticTap();
                                  final updated = List<SmartDisplaySlideImage>.from(_draft.slideImages);
                                  final removed = updated.removeAt(currentIdx);
                                  unawaited(MediaStorageService.deleteMedia(removed.filePath));
                                  setState(() => _draft = _draft.copyWith(slideImages: updated));
                                  widget.onSaveSettings(_draft);
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
                            ),
                            const SizedBox(width: 6),
                            TactilePress(
                              child: FilledButton(
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
      outsideTemp: widget.outsideTemp,
      boiler: ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp),
      sensors: widget.sensors,
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
      onApplyRemoteRoomTemp: widget.onApplyRemoteRoomTemp,
      onApplyRemoteSensors: widget.onApplyRemoteSensors,
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
          TactilePress(
            child: TextButton(
              onPressed: () => Navigator.of(dCtx).pop(),
              child: Text(_lang == LangCode.tr ? 'Vazgeç' : 'Cancel'),
            ),
          ),
          TactilePress(
            child: FilledButton(
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
                    TactilePress(
                      child: IconButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.06),
                          side: BorderSide(color: Colors.white.withValues(alpha: 0.10)),
                        ),
                        icon: const Icon(Icons.close_rounded, color: Color(0xFFFBBF24), size: 19),
                      ),
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
                          TactilePress(
                            child: TextButton.icon(
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
                          ),
                          const SizedBox(width: 4),
                          TactilePress(
                            child: OutlinedButton.icon(
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
                    TactilePress(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        style: TextButton.styleFrom(foregroundColor: Colors.white70),
                        child: Text(_lang == LangCode.tr ? 'Kapat' : 'Close'),
                      ),
                    ),
                    const SizedBox(width: 10),
                    TactilePress(
                      child: Container(
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
                            final resolvedAudioSource = _resolveAudioSource();
                            final resolvedAudioLabel = _customAudioCtrl.text.trim();
                            final resolvedTrack = (resolvedAudioSource.isNotEmpty || resolvedAudioLabel.isNotEmpty)
                                ? AmbientSoundtrack.customMp3
                                : AmbientSoundtrack.silent;
                            final updated = _draft.copyWith(
                              firebaseRtdbUrl: _firebaseUrlCtrl.text.trim(),
                              firebaseApiKey: _firebaseApiKeyCtrl.text.trim(),
                              firebaseNodePath: sanitizedNode,
                              espDeviceId: typedEspId.isEmpty ? _draft.espDeviceId : typedEspId,
                              ambientSoundtrack: resolvedTrack,
                              customAudioLabel: resolvedAudioLabel,
                              customAudioSource: resolvedAudioSource,
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
                    TactilePress(
                      child: ChoiceChip(
                        label: Text(code.name.toUpperCase(), style: const TextStyle(fontSize: 11)),
                        selected: _lang == code,
                        visualDensity: VisualDensity.compact,
                        selectedColor: widget.accentColor.withValues(alpha: 0.35),
                        onSelected: (_) {
                          _hapticTap();
                          setState(() => _lang = code);
                        },
                      ),
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
                  child: TactilePress(
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
                        TactilePress(
                          enabled: index > 0,
                          child: IconButton(
                            onPressed: index > 0 ? () => _shiftItem(index, -1) : null,
                            icon: const Icon(Icons.keyboard_arrow_up_rounded, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
                        ),
                        TactilePress(
                          enabled: index < _draft.menuOrder.length - 1,
                          child: IconButton(
                            onPressed: index < _draft.menuOrder.length - 1 ? () => _shiftItem(index, 1) : null,
                            icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                          ),
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

  SettingsCardMeta _describeItem(SettingsItemId id) {
    final tr = _lang == LangCode.tr;
    switch (id) {
      case SettingsItemId.vault:
        return SettingsCardMeta(
          icon: Icons.lock_outline_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Şifreli Kasa & Bildirimler' : 'Encrypted Vault & Alerts',
          tag: 'AES-256',
          subtitle: tr ? 'PIN korumalı kasa kilidi ve Telegram bot bildirimleri' : 'PIN vault lock and Telegram bot alerts',
          trailingAction: SettingsActionPill(
            label: _draft.vaultUnlocked ? (tr ? 'Açık ✓' : 'Open ✓') : (tr ? 'Aç →' : 'Open →'),
            active: _draft.vaultUnlocked,
            color: const Color(0xFFF59E0B),
            onTap: _openVaultCenter,
          ),
        );
      case SettingsItemId.googleHome:
        return SettingsCardMeta(
          icon: Icons.home_outlined,
          iconColor: const Color(0xFF38BDF8),
          title: tr ? 'Google Home & Asistan' : 'Google Home & Assistant',
          tag: tr ? 'Google ile Uyumlu' : 'Works with Google',
          subtitle: tr ? 'Firebase üzerinden Google Asistan sesli kontrol' : 'Google Assistant voice sync via Firebase',
          trailingAction: SettingsActionPill(
            label: _draft.googleHomeLinked ? (tr ? 'Bağlı ✓' : 'Linked ✓') : (tr ? 'Yönet →' : 'Manage →'),
            active: _draft.googleHomeLinked,
            color: const Color(0xFF38BDF8),
            onTap: _openGoogleHome,
          ),
        );
      case SettingsItemId.smartDisplay:
        return SettingsCardMeta(
          icon: Icons.tv_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: 'Smart Display & Ambiyans',
          tag: 'Tablet / PC',
          subtitle: tr ? 'Masaüstü veya duvarda canlı saat ve ambiyans ekranı' : 'Wall-mount clock & ambient display',
          trailingAction: SettingsActionPill(
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
        final anyNotifyOn = _draft.notifications3hEnabled || _draft.boilerEventNotificationsEnabled;
        return SettingsCardMeta(
          icon: Icons.notifications_none_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Bildirim Ayarları & Otomasyon' : 'Notifications & Automation',
          tag: tr ? '3 Saatlik & Olay' : '3h & Events',
          subtitle: tr
              ? '3 saatlik özet, kombi durum mesajları ve acil emniyet uyarıları'
              : '3-hour summary, boiler status messages, and safety alerts',
          trailingAction: SettingsActionPill(
            label: anyNotifyOn ? (tr ? 'Devrede' : 'Active') : (tr ? 'Kapalı' : 'Off'),
            active: anyNotifyOn,
            color: const Color(0xFFF59E0B),
            onTap: () {
              _hapticTap();
              setState(() => _draft = _draft.copyWith(notifications3hEnabled: !_draft.notifications3hEnabled));
            },
          ),
        );
      case SettingsItemId.haptic:
        return SettingsCardMeta(
          icon: Icons.vibration_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Haptik Titreşim & Dokunma' : 'Haptic Touch Feedback',
          tag: tr ? 'Titreşim' : 'Haptic',
          subtitle: tr ? 'Tüm butonlar, kadran ve Flow Bar için titreşim' : 'Tactile feedback on dial, buttons and Flow Bar',
          trailingAction: SettingsActionPill(
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
        return SettingsCardMeta(
          icon: Icons.local_fire_department_outlined,
          iconColor: const Color(0xFFF97316),
          title: tr ? 'Açılış Seremonisi (Boot Efekti)' : 'Boot Ceremony Animation',
          tag: 'Boot',
          subtitle: tr ? 'Uygulama açılırken akıllı termostat kalibrasyonu' : 'Smart calibration animation on launch',
          trailingAction: SettingsActionPill(
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
        return SettingsCardMeta(
          icon: Icons.smart_toy_outlined,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'Sanal Asistan & Ekran Koruyucu' : 'Virtual Assistant Screensaver',
          tag: 'TermoBot',
          subtitle: tr ? 'Boşta kalınca tam ekran açılan ve 3 döngü sonra uyuyan koruyucu' : 'Idle fullscreen screensaver & 3-cycle sleep mode',
          trailingAction: SettingsActionPill(
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
        return SettingsCardMeta(
          icon: Icons.phone_in_talk_outlined,
          iconColor: const Color(0xFF10B981),
          title: tr ? 'AI Sesli Telefon Araması (Asistan)' : 'AI Voice Call Assistant',
          tag: '${_draft.aiCallRingSeconds} sn · $callModeShort',
          subtitle: _draft.aiCallLastOutcome.isNotEmpty
              ? (tr ? 'Son arama: ${_draft.aiCallLastOutcome}' : 'Last call: ${_draft.aiCallLastOutcome}')
              : (tr ? 'Kombi ateşlendiğinde arar, sesli bilgi verir' : 'Calls on boiler ignition, alerts if missed'),
          trailingAction: SettingsActionPill(
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
        return SettingsCardMeta(
          icon: Icons.memory_rounded,
          iconColor: const Color(0xFFFBBF24),
          title: tr ? 'ESP Donanım Günlüğü & Raporlama' : 'ESP Hardware & Offline Logs',
          tag: tr ? 'ESP32 / WDT · ${_draft.espLogs.length} kayıt' : 'ESP32 / WDT · ${_draft.espLogs.length} logs',
          subtitle: tr
              ? '${_draft.espOfflineBurnMinutes} dk çevrimdışı yanma · ${_draft.espWdtResetCount} WDT'
              : '${_draft.espOfflineBurnMinutes} min offline burn · ${_draft.espWdtResetCount} WDT',
          trailingAction: SettingsActionPill(
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
        return SettingsCardMeta(
          icon: Icons.sync_rounded,
          iconColor: const Color(0xFF38BDF8),
          title: tr ? 'Bulut Senkronizasyon & Veritabanı' : 'Cloud Sync & Database',
          tag: 'RTDB · /$safeNode · $intervalShort',
          subtitle: _draft.cloudLastSyncAt.isNotEmpty
              ? (tr
                  ? 'Son eşitleme ${_draft.cloudLastSyncAt} · ${_draft.cloudLastSyncOk ? 'Başarılı' : 'Hatalı'}'
                  : 'Last sync ${_draft.cloudLastSyncAt} · ${_draft.cloudLastSyncOk ? 'OK' : 'Error'}')
              : (tr ? 'Firebase gerçek zamanlı veri senkronizasyonu' : 'Firebase realtime telemetry sync'),
          trailingAction: SettingsActionPill(
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
        return SettingsCardMeta(
          icon: Icons.delete_sweep_outlined,
          iconColor: const Color(0xFFF87171),
          title: tr ? 'Geçmiş Verileri & Kayıtları Sıfırla' : 'Reset History & Usage Logs',
          tag: tr ? 'Sıfırlama' : 'Reset',
          subtitle: tr ? 'Sıcaklık saatlik kayıtları ve fatura telemetrisi' : 'Hourly heat records and billing telemetry',
          trailingAction: SettingsActionPill(
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
            TactilePress(
              child: FilledButton.icon(
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
            TactilePress(
              child: FilledButton.icon(
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
            ),
          ],
        );

      case SettingsItemId.smartDisplay:
        return _buildSmartDisplayPanel(tr);
      case SettingsItemId.notifications:
        final liveBoiler = ThermostatMath.computeBoilerTelemetry(widget.roomTemp, _liveTargetTemp);
        final safety = NotificationService.evaluateSafetyThresholds(
          roomTemp: widget.roomTemp,
          outsideTemp: widget.outsideTemp,
          boiler: liveBoiler,
          sensors: widget.sensors,
        );
        final pressureLabel = (widget.sensors.isConnected && widget.sensors.waterPressureBar != null)
            ? '${widget.sensors.waterPressureBar!.toStringAsFixed(1)} Bar'
            : '--';
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
                        ? '• Basınç İzleme: $pressureLabel (Eşik: < 1.0 Bar acil uyarı)\n'
                            '• Donma Koruması: Oda ${widget.roomTemp != null ? '${widget.roomTemp!.toStringAsFixed(1)}°C' : '--'} (Eşik: < 5.0°C otomatik ateşleme)\n'
                            '• Alev & Brülör: ${liveBoiler.statusTextTr}'
                        : '• Pressure Guard: $pressureLabel (Threshold: < 1.0 Bar)\n'
                            '• Freeze Guard: Room ${widget.roomTemp != null ? '${widget.roomTemp!.toStringAsFixed(1)}°C' : '--'} (Threshold: < 5.0°C)\n'
                            '• Flame & Burner: ${liveBoiler.statusTextEn}',
                    style: TextStyle(fontSize: 10.5, color: Colors.white.withValues(alpha: 0.76), height: 1.45),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),

            // Interactive Automation Switches
            SettingsMiniToggleTile(
              label: tr ? '📊 3 Saatlik Tüketim & Durum Özeti' : '📊 3-Hour Usage & Status Summary',
              value: _draft.notifications3hEnabled,
              activeColor: const Color(0xFFF59E0B),
              onTap: () {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(notifications3hEnabled: !_draft.notifications3hEnabled));
              },
            ),
            const SizedBox(height: 6),
            SettingsMiniToggleTile(
              label: tr
                  ? '🔥 Kombi & Sıcaklık Olay Bildirimleri (Açıldı / Kısıldı / Kapandı)'
                  : '🔥 Boiler & Temp Event Alerts (On / Lowered / Off / High / Cold)',
              value: _draft.boilerEventNotificationsEnabled,
              activeColor: const Color(0xFFFB923C),
              onTap: () {
                _hapticTap();
                setState(
                  () => _draft = _draft.copyWith(
                    boilerEventNotificationsEnabled: !_draft.boilerEventNotificationsEnabled,
                  ),
                );
              },
            ),
            if (_draft.boilerEventNotificationsEnabled) ...[
              const SizedBox(height: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                decoration: BoxDecoration(
                  color: const Color(0xFFFB923C).withValues(alpha: 0.09),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: const Color(0xFFFB923C).withValues(alpha: 0.30)),
                ),
                child: Text(
                  tr
                      ? '• Sesli asistan aramasını kapatsanız bile veya aramayla paralel olarak şu mesajlar gönderilir: Kombi açıldı, Kombi kısıldı, Kombi kapandı, Derece en yüksekte, Ev sıcaklığı düşük.'
                      : '• Works without Voice Assistant calls or in parallel alongside calls: Boiler turned on, Boiler lowered, Boiler turned off, Target temp at max, Low room temperature.',
                  style: TextStyle(
                    fontSize: 10,
                    color: Colors.white.withValues(alpha: 0.78),
                    height: 1.38,
                  ),
                ),
              ),
            ],
            const SizedBox(height: 6),
            SettingsMiniToggleTile(
              label: tr ? '🚨 Kritik Basınç (<1.0 Bar) & Alev Kesintisi' : '🚨 Critical Pressure (<1.0 Bar) & Flame Loss',
              value: _draft.emergencyBoilerAlerts,
              activeColor: const Color(0xFFEF4444),
              onTap: () {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(emergencyBoilerAlerts: !_draft.emergencyBoilerAlerts));
              },
            ),
            const SizedBox(height: 6),
            SettingsMiniToggleTile(
              label: tr ? '🌧️ Dış Hava & Ani Soğuma Bildirimleri' : '🌧️ Weather & Sudden Drop Alerts',
              value: _draft.weatherAlertsEnabled,
              activeColor: const Color(0xFF38BDF8),
              onTap: () {
                _hapticTap();
                setState(() => _draft = _draft.copyWith(weatherAlertsEnabled: !_draft.weatherAlertsEnabled));
              },
            ),
            const SizedBox(height: 6),
            SettingsMiniToggleTile(
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
            TactilePress(
              enabled: !_sendingTestNotification,
              child: FilledButton.icon(
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
            SettingsMiniToggleTile(
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
                  TactilePress.card(
                    child: GestureDetector(
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
                SettingsInfoBadge(
                  text: '⏱️ ${tr ? 'Süre' : 'Duration'}: $secLabel',
                  color: const Color(0xFFF97316),
                ),
                SettingsInfoBadge(
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
                    child: TactilePress.card(
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
            TactilePress.card(
              child: OutlinedButton.icon(
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
            ),
          ],
        );

      case SettingsItemId.termoBot:
        return _buildTermoBotPanel(tr);
      case SettingsItemId.aiPhoneCall:
        return _buildAiPhoneCallPanel(tr);
      case SettingsItemId.espLog:
        return _buildEspLogPanel(tr);
      case SettingsItemId.cloudSync:
        return _buildCloudSyncPanel(tr);
      case SettingsItemId.resetHistory:
        return TactilePress.card(
          child: FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: const Color(0xFFEF4444).withValues(alpha: 0.25), foregroundColor: const Color(0xFFFCA5A5)),
            onPressed: _confirmResetHistory,
            icon: const Icon(Icons.delete_forever_outlined, size: 17),
            label: Text(tr ? 'Tüm Tüketim & Telemetriyi Sıfırla' : 'Clear All Usage & Telemetry'),
          ),
        );
    }
  }
}

