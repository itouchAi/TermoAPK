import 'dart:async';
import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import '../models/thermostat_state.dart';
import 'ambient_audio_service.dart';
import 'video_source_bridge.dart';

class MediaStorageService {
  MediaStorageService._();

  static const String _dbName = 'termostat_flow_media_v1';
  static const String _storeName = 'media';

  static const String customAudioKey = 'idb://custom_audio';
  static const String customVideoKey = 'idb://custom_video';
  static const String screensaverBgKey = 'idb://screensaver_bg';

  static String slideImageKey(String id) => 'idb://slide_$id';

  static bool isPersistedKey(String source) => source.trim().startsWith('idb://');

  static final Map<String, Uint8List> _bytesCache = {};
  static final Map<String, String> _mimeCache = {};
  static final Map<String, String> _blobUrlCache = {};
  static Future<JSObject?>? _dbFuture;

  static Future<JSObject?> _openDb() {
    if (_dbFuture != null) return _dbFuture!;
    final completer = Completer<JSObject?>();
    try {
      final idb = globalContext.getProperty<JSObject?>('indexedDB'.toJS);
      if (idb == null) {
        completer.complete(null);
        return _dbFuture = completer.future;
      }
      final req = idb.callMethod<JSObject?>('open'.toJS, _dbName.toJS, 1.toJS);
      if (req == null) {
        completer.complete(null);
        return _dbFuture = completer.future;
      }

      req.setProperty(
        'onupgradeneeded'.toJS,
        ((JSAny? _) {
          try {
            final db = req.getProperty<JSObject?>('result'.toJS);
            if (db == null) return;
            final stores = db.getProperty<JSObject?>('objectStoreNames'.toJS);
            final hasStore = stores != null &&
                stores.callMethod<JSBoolean>('contains'.toJS, _storeName.toJS).toDart;
            if (!hasStore) {
              final opts = JSObject();
              opts.setProperty('keyPath'.toJS, 'key'.toJS);
              db.callMethod<JSAny?>('createObjectStore'.toJS, _storeName.toJS, opts);
            }
          } catch (_) {}
        }).toJS,
      );

      req.setProperty(
        'onsuccess'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) {
            completer.complete(req.getProperty<JSObject?>('result'.toJS));
          }
        }).toJS,
      );

      req.setProperty(
        'onerror'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }).toJS,
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    _dbFuture = completer.future;
    return _dbFuture!;
  }

  static Uint8List? getCachedBytes(String source) {
    final k = source.trim();
    if (k.isEmpty) return null;
    return _bytesCache[k];
  }

  static String getPlayableVideoUrl(String source) {
    final k = source.trim();
    if (k.isEmpty) return '';
    if (isPersistedKey(k)) {
      return _blobUrlCache[k] ?? '';
    }
    return k;
  }

  static Future<String> saveMediaBytes({
    required String key,
    required Uint8List bytes,
    String mimeType = 'application/octet-stream',
    String fileName = '',
  }) async {
    final normalizedKey = key.trim();
    _bytesCache[normalizedKey] = bytes;
    _mimeCache[normalizedKey] = mimeType;

    if (mimeType.startsWith('video/')) {
      final oldUrl = _blobUrlCache[normalizedKey];
      if (oldUrl != null && oldUrl.isNotEmpty) {
        VideoSourceBridge.revokeObjectUrl(oldUrl);
      }
      final newUrl = VideoSourceBridge.createObjectUrlFromBytes(bytes, mimeType: mimeType);
      if (newUrl.isNotEmpty) {
        _blobUrlCache[normalizedKey] = newUrl;
      }
    }

    final db = await _openDb();
    if (db == null) return normalizedKey;

    final completer = Completer<void>();
    try {
      final tx = db.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, 'readwrite'.toJS);
      final store = tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      final record = JSObject();
      record.setProperty('key'.toJS, normalizedKey.toJS);
      record.setProperty('bytes'.toJS, Uint8List.fromList(bytes).toJS);
      record.setProperty('mimeType'.toJS, mimeType.toJS);
      record.setProperty('fileName'.toJS, fileName.toJS);
      store.callMethod<JSAny?>('put'.toJS, record);

      tx.setProperty(
        'oncomplete'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) completer.complete();
        }).toJS,
      );
      tx.setProperty(
        'onerror'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) completer.complete();
        }).toJS,
      );
      tx.setProperty(
        'onabort'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) completer.complete();
        }).toJS,
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }
    await completer.future;
    return normalizedKey;
  }

  static Future<String> persistPickedFile({
    required String key,
    String? sourcePath,
    Uint8List? bytes,
    String mimeType = 'application/octet-stream',
    String fileName = '',
  }) async {
    if (bytes == null || bytes.isEmpty) return sourcePath ?? '';
    return saveMediaBytes(
      key: key,
      bytes: bytes,
      mimeType: mimeType,
      fileName: fileName,
    );
  }

  static Future<Uint8List?> loadBytes(String source) async {
    final key = source.trim();
    if (key.isEmpty || !isPersistedKey(key)) return null;
    final cached = _bytesCache[key];
    if (cached != null && cached.isNotEmpty) return cached;

    final db = await _openDb();
    if (db == null) return null;

    final completer = Completer<Uint8List?>();
    try {
      final tx = db.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, 'readonly'.toJS);
      final store = tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      final req = store.callMethod<JSObject>('get'.toJS, key.toJS);
      req.setProperty(
        'onsuccess'.toJS,
        ((JSAny? _) {
          try {
            final res = req.getProperty<JSAny?>('result'.toJS);
            if (res != null && res.isA<JSObject>()) {
              final obj = res as JSObject;
              final mimeAny = obj.getProperty<JSAny?>('mimeType'.toJS);
              if (mimeAny != null && mimeAny.isA<JSString>()) {
                _mimeCache[key] = (mimeAny as JSString).toDart;
              }
              final bytesAny = obj.getProperty<JSAny?>('bytes'.toJS);
              if (bytesAny != null && bytesAny.isA<JSUint8Array>()) {
                final data = (bytesAny as JSUint8Array).toDart;
                _bytesCache[key] = data;
                if (!completer.isCompleted) completer.complete(data);
                return;
              }
            }
          } catch (_) {}
          if (!completer.isCompleted) completer.complete(null);
        }).toJS,
      );
      req.setProperty(
        'onerror'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) completer.complete(null);
        }).toJS,
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete(null);
    }
    return completer.future;
  }

  static Future<String> resolveVideoPlayableUrl(String source) async {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return '';
    if (!isPersistedKey(trimmed)) return trimmed;

    final existing = _blobUrlCache[trimmed];
    if (existing != null && existing.isNotEmpty) return existing;

    final bytes = await loadBytes(trimmed);
    if (bytes == null || bytes.isEmpty) return '';
    final mime = _mimeCache[trimmed];
    final resolvedMime = (mime != null && mime.startsWith('video/')) ? mime : 'video/mp4';
    final url = VideoSourceBridge.createObjectUrlFromBytes(bytes, mimeType: resolvedMime);
    if (url.isNotEmpty) {
      _blobUrlCache[trimmed] = url;
    }
    return url;
  }

  static Future<void> deleteMedia(String source) async {
    final key = source.trim();
    if (key.isEmpty) return;
    _bytesCache.remove(key);
    _mimeCache.remove(key);
    final oldUrl = _blobUrlCache.remove(key);
    if (oldUrl != null && oldUrl.isNotEmpty) {
      VideoSourceBridge.revokeObjectUrl(oldUrl);
    }
    if (!isPersistedKey(key)) return;

    final db = await _openDb();
    if (db == null) return;
    final completer = Completer<void>();
    try {
      final tx = db.callMethod<JSObject>('transaction'.toJS, _storeName.toJS, 'readwrite'.toJS);
      final store = tx.callMethod<JSObject>('objectStore'.toJS, _storeName.toJS);
      store.callMethod<JSAny?>('delete'.toJS, key.toJS);
      tx.setProperty(
        'oncomplete'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) completer.complete();
        }).toJS,
      );
      tx.setProperty(
        'onerror'.toJS,
        ((JSAny? _) {
          if (!completer.isCompleted) completer.complete();
        }).toJS,
      );
    } catch (_) {
      if (!completer.isCompleted) completer.complete();
    }
    await completer.future;
  }

  static Future<void> hydrateSettingsMedia(SystemSettingsState settings) async {
    final tasks = <Future<void>>[];

    if (isPersistedKey(settings.customAudioSource)) {
      tasks.add(() async {
        final bytes = await loadBytes(settings.customAudioSource);
        if (bytes != null && bytes.isNotEmpty) {
          AmbientAudioService.setCustomAudioBytes(bytes);
        }
      }());
    }

    if (isPersistedKey(settings.customVideoSource)) {
      tasks.add(resolveVideoPlayableUrl(settings.customVideoSource).then((_) {}));
    }

    if (isPersistedKey(settings.screensaverCustomBgSource)) {
      tasks.add(loadBytes(settings.screensaverCustomBgSource).then((_) {}));
    }

    for (final slide in settings.slideImages) {
      final key = isPersistedKey(slide.filePath)
          ? slide.filePath
          : (slide.dataBase64.isEmpty ? slideImageKey(slide.id) : '');
      if (key.isNotEmpty) {
        tasks.add(loadBytes(key).then((_) {}));
      }
    }

    if (tasks.isNotEmpty) {
      await Future.wait(tasks);
    }
  }
}
