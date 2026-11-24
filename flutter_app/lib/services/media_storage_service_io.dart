import 'dart:io';
import 'dart:typed_data';
import '../models/thermostat_state.dart';
import 'ambient_audio_service.dart';

class MediaStorageService {
  MediaStorageService._();

  static const String customAudioKey = 'idb://custom_audio';
  static const String customVideoKey = 'idb://custom_video';
  static const String screensaverBgKey = 'idb://screensaver_bg';

  static String slideImageKey(String id) => 'idb://slide_$id';

  static bool isPersistedKey(String source) => source.trim().startsWith('idb://');

  static final Map<String, Uint8List> _bytesCache = {};

  static Directory _mediaDir() {
    Directory candidate;
    try {
      final parent = Directory.systemTemp.parent;
      final appFiles = Directory('${parent.path}/files');
      if (appFiles.existsSync()) {
        candidate = Directory('${appFiles.path}/termostat_flow_media');
      } else {
        candidate = Directory('${Directory.systemTemp.path}/termostat_flow_media');
      }
    } catch (_) {
      candidate = Directory('${Directory.systemTemp.path}/termostat_flow_media');
    }
    if (!candidate.existsSync()) {
      candidate.createSync(recursive: true);
    }
    return candidate;
  }

  static String _safeFileName(String key, String fileName) {
    final sanitizedKey = key.replaceAll(RegExp(r'[^a-zA-Z0-9_-]'), '_');
    final extIdx = fileName.lastIndexOf('.');
    final ext = (extIdx >= 0 && extIdx < fileName.length - 1)
        ? fileName.substring(extIdx).replaceAll(RegExp(r'[^a-zA-Z0-9.]'), '')
        : '';
    return '$sanitizedKey$ext';
  }

  static Uint8List? getCachedBytes(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    final cached = _bytesCache[trimmed];
    if (cached != null) return cached;
    if (!trimmed.startsWith('http://') &&
        !trimmed.startsWith('https://') &&
        !trimmed.startsWith('data:') &&
        !trimmed.startsWith('idb://')) {
      try {
        final f = File(trimmed);
        if (f.existsSync()) {
          final data = f.readAsBytesSync();
          _bytesCache[trimmed] = data;
          return data;
        }
      } catch (_) {}
    }
    return null;
  }

  static String getPlayableVideoUrl(String source) => source.trim();

  static Future<String> resolveVideoPlayableUrl(String source) async => source.trim();

  static Future<String> saveMediaBytes({
    required String key,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String fileName = '',
  }) async {
    try {
      final dir = _mediaDir();
      final out = File('${dir.path}/${_safeFileName(key, fileName)}');
      await out.writeAsBytes(bytes, flush: true);
      _bytesCache[out.path] = bytes;
      _bytesCache[key] = bytes;
      return out.path;
    } catch (_) {
      _bytesCache[key] = bytes;
      return key;
    }
  }

  static Future<String> persistPickedFile({
    required String key,
    String? sourcePath,
    Uint8List? bytes,
    String mimeType = 'application/octet-stream',
    String fileName = '',
  }) async {
    try {
      final dir = _mediaDir();
      final dest = File('${dir.path}/${_safeFileName(key, fileName)}');
      if (bytes != null && bytes.isNotEmpty) {
        await dest.writeAsBytes(bytes, flush: true);
        _bytesCache[dest.path] = bytes;
        return dest.path;
      }
      if (sourcePath != null && sourcePath.isNotEmpty) {
        final src = File(sourcePath);
        if (await src.exists()) {
          await src.copy(dest.path);
          return dest.path;
        }
      }
    } catch (_) {}
    return sourcePath ?? '';
  }

  static Future<Uint8List?> loadBytes(String source) async {
    final cached = getCachedBytes(source);
    if (cached != null) return cached;
    return null;
  }

  static Future<void> deleteMedia(String source) async {
    final key = source.trim();
    if (key.isEmpty) return;
    _bytesCache.remove(key);
    if (!key.startsWith('http://') && !key.startsWith('https://') && !key.startsWith('idb://')) {
      try {
        final f = File(key);
        if (await f.exists()) {
          await f.delete();
        }
      } catch (_) {}
    }
  }

  static Future<void> hydrateSettingsMedia(SystemSettingsState settings) async {
    if (settings.customAudioSource.isNotEmpty) {
      final f = File(settings.customAudioSource);
      if (await f.exists()) {
        try {
          AmbientAudioService.setCustomAudioBytes(await f.readAsBytes());
        } catch (_) {}
      }
    }
    for (final slide in settings.slideImages) {
      if (slide.filePath.isNotEmpty) {
        getCachedBytes(slide.filePath);
      }
    }
    if (settings.screensaverCustomBgSource.isNotEmpty &&
        !settings.screensaverCustomBgSource.startsWith('http') &&
        !settings.screensaverCustomBgSource.startsWith('data:')) {
      getCachedBytes(settings.screensaverCustomBgSource);
    }
  }
}
