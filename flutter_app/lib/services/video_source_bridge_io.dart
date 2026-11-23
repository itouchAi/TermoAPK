import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

class VideoSourceBridge {
  VideoSourceBridge._();

  static String createObjectUrlFromBytes(Uint8List bytes, {String mimeType = 'video/mp4'}) {
    return '';
  }

  static void revokeObjectUrl(String url) {}

  static VideoPlayerController? createController(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('content://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      return VideoPlayerController.networkUrl(uri);
    }
    return VideoPlayerController.file(File(trimmed));
  }

  static void applyDomVideoBlur(double sigmaPx) {}
}
