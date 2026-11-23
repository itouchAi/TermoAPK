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

  static void applyDomVideoBlur(double sigmaPx) {
    try {
      final doc = globalContext.getProperty<JSObject?>('document'.toJS);
      if (doc == null) return;
      final filterVal = sigmaPx > 0.1 ? 'blur(${sigmaPx.toStringAsFixed(1)}px)' : '';
      final transformVal = sigmaPx > 0.1 ? 'scale(1.06)' : '';

      void styleVideoList(JSObject? nodeList) {
        if (nodeList == null) return;
        final lenAny = nodeList.getProperty<JSAny?>('length'.toJS);
        final len = (lenAny != null && lenAny.isA<JSNumber>()) ? (lenAny as JSNumber).toDartInt : 0;
        for (int i = 0; i < len; i++) {
          final elAny = nodeList.callMethod<JSAny?>('item'.toJS, i.toJS);
          if (elAny != null && elAny.isA<JSObject>()) {
            final el = elAny as JSObject;
            final style = el.getProperty<JSObject?>('style'.toJS);
            if (style != null) {
              style.setProperty('filter'.toJS, filterVal.toJS);
              style.setProperty('webkitFilter'.toJS, filterVal.toJS);
              style.setProperty('transform'.toJS, transformVal.toJS);
              style.setProperty('transition'.toJS, 'filter 180ms ease, transform 180ms ease'.toJS);
            }
          }
        }
      }

      styleVideoList(doc.callMethod<JSObject?>('querySelectorAll'.toJS, 'video'.toJS));

      // Also inspect Flutter glass-pane shadowRoot if present
      final glassPane = doc.callMethod<JSObject?>('querySelector'.toJS, 'flt-glass-pane'.toJS);
      if (glassPane != null) {
        final shadow = glassPane.getProperty<JSObject?>('shadowRoot'.toJS);
        if (shadow != null) {
          styleVideoList(shadow.callMethod<JSObject?>('querySelectorAll'.toJS, 'video'.toJS));
        }
      }
    } catch (_) {}
  }
}
