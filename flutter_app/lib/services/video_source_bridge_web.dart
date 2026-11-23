import 'dart:js_interop';
import 'dart:js_interop_unsafe';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

class VideoSourceBridge {
  VideoSourceBridge._();

  static String createObjectUrlFromBytes(Uint8List bytes, {String mimeType = 'video/mp4'}) {
    try {
      final blobCtor = globalContext.getProperty<JSFunction?>('Blob'.toJS);
      final urlObj = globalContext.getProperty<JSObject?>('URL'.toJS);
      if (blobCtor == null || urlObj == null) return '';

      final jsBytes = bytes.toJS;
      final parts = <JSAny>[jsBytes].toJS;
      final opts = JSObject();
      opts.setProperty('type'.toJS, mimeType.toJS);
      final blob = blobCtor.callAsConstructor<JSObject>(parts, opts);
      final created = urlObj.callMethod<JSAny?>('createObjectURL'.toJS, blob);
      if (created != null && created.isA<JSString>()) {
        return (created as JSString).toDart;
      }
    } catch (_) {}
    return '';
  }

  static void revokeObjectUrl(String url) {
    if (!url.startsWith('blob:')) return;
    try {
      final urlObj = globalContext.getProperty<JSObject?>('URL'.toJS);
      urlObj?.callMethod<JSAny?>('revokeObjectURL'.toJS, url.toJS);
    } catch (_) {}
  }

  static VideoPlayerController? createController(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('blob:') ||
        trimmed.startsWith('data:')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      return VideoPlayerController.networkUrl(uri);
    }
    return null;
  }
}
