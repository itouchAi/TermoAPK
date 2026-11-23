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

  static double _lastSigmaPx = 0.0;
  static int _blurApplyGen = 0;

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

  static void _styleVideoElement(JSObject el, String filterVal, String transformVal) {
    try {
      el.setProperty('muted'.toJS, true.toJS);
      el.setProperty('playsInline'.toJS, true.toJS);
      el.setProperty('preload'.toJS, 'auto'.toJS);
    } catch (_) {}
    final style = el.getProperty<JSObject?>('style'.toJS);
    if (style != null) {
      style.setProperty('filter'.toJS, filterVal.toJS);
      style.setProperty('webkitFilter'.toJS, filterVal.toJS);
      style.setProperty('transformOrigin'.toJS, 'center center'.toJS);
      style.setProperty('transform'.toJS, transformVal.toJS);
      style.setProperty('transition'.toJS, 'filter 180ms ease, transform 180ms ease'.toJS);
    }
  }

  static void _applyBlurNow(double sigmaPx) {
    try {
      final doc = globalContext.getProperty<JSObject?>('document'.toJS);
      if (doc == null) return;
      final filterVal = sigmaPx > 0.1 ? 'blur(${sigmaPx.toStringAsFixed(1)}px)' : 'none';
      final transformVal = sigmaPx > 0.1 ? 'scale(1.08)' : 'none';

      void walkNode(JSObject? node) {
        if (node == null) return;
        try {
          final tagAny = node.getProperty<JSAny?>('tagName'.toJS);
          if (tagAny != null && tagAny.isA<JSString>()) {
            final tag = (tagAny as JSString).toDart.toUpperCase();
            if (tag == 'VIDEO') {
              _styleVideoElement(node, filterVal, transformVal);
            }
          }
          final shadow = node.getProperty<JSObject?>('shadowRoot'.toJS);
          if (shadow != null) {
            walkNode(shadow);
          }
          final children = node.getProperty<JSObject?>('children'.toJS);
          if (children != null) {
            final lenAny = children.getProperty<JSAny?>('length'.toJS);
            final len = (lenAny != null && lenAny.isA<JSNumber>()) ? (lenAny as JSNumber).toDartInt : 0;
            for (int i = 0; i < len; i++) {
              final child = children.callMethod<JSAny?>('item'.toJS, i.toJS);
              if (child != null && child.isA<JSObject>()) {
                walkNode(child as JSObject);
              }
            }
          }
        } catch (_) {}
      }

      // 1. Standard document query
      final directList = doc.callMethod<JSObject?>('querySelectorAll'.toJS, 'video'.toJS);
      if (directList != null) {
        final lenAny = directList.getProperty<JSAny?>('length'.toJS);
        final len = (lenAny != null && lenAny.isA<JSNumber>()) ? (lenAny as JSNumber).toDartInt : 0;
        for (int i = 0; i < len; i++) {
          final elAny = directList.callMethod<JSAny?>('item'.toJS, i.toJS);
          if (elAny != null && elAny.isA<JSObject>()) {
            _styleVideoElement(elAny as JSObject, filterVal, transformVal);
          }
        }
      }

      // 2. Recursive traversal across DOM & nested Flutter PlatformView shadowRoots
      final rootEl = doc.getProperty<JSObject?>('documentElement'.toJS);
      walkNode(rootEl);
    } catch (_) {}
  }

  static void applyDomVideoBlur(double sigmaPx) {
    _lastSigmaPx = sigmaPx;
    final gen = ++_blurApplyGen;
    _applyBlurNow(sigmaPx);
    for (final delayMs in const [40, 150, 420, 950, 1800]) {
      Future<void>.delayed(Duration(milliseconds: delayMs), () {
        if (_blurApplyGen == gen) {
          _applyBlurNow(_lastSigmaPx);
        }
      });
    }
  }
}
