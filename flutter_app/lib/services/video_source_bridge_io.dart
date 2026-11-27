import 'dart:io';
import 'dart:typed_data';
import 'package:video_player/video_player.dart';

class VideoSourceBridge {
  VideoSourceBridge._();

  static String createObjectUrlFromBytes(Uint8List bytes, {String mimeType = 'video/mp4'}) {
    return '';
  }

  static void revokeObjectUrl(String url) {}

  static const Map<String, String> _defaultVideoHeaders = {
    'User-Agent': 'TermostatFlow/1.0 (https://github.com/termostat-flow; Android)',
    'Accept': '*/*',
  };

  static VideoPlayerController? createController(String source) {
    final trimmed = source.trim();
    if (trimmed.isEmpty) return null;
    if (trimmed.startsWith('http://') ||
        trimmed.startsWith('https://') ||
        trimmed.startsWith('content://')) {
      final uri = Uri.tryParse(trimmed);
      if (uri == null) return null;
      return VideoPlayerController.networkUrl(
        uri,
        httpHeaders: trimmed.startsWith('content://') ? const {} : _defaultVideoHeaders,
        videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
      );
    }
    return VideoPlayerController.file(
      File(trimmed),
      videoPlayerOptions: VideoPlayerOptions(mixWithOthers: true),
    );
  }

  static void applyDomVideoBlur(double sigmaPx) {}
}
