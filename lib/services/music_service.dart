import 'package:audioplayers/audioplayers.dart';

/// Trình phát nhạc nền dùng chung cho cả app (singleton), để nhạc không bị
/// dừng khi chuyển qua lại giữa các màn hình.
class MusicService {
  static final MusicService instance = MusicService._internal();
  MusicService._internal();

  final AudioPlayer _player = AudioPlayer();
  bool _isPlaying = false;
  bool get isPlaying => _isPlaying;

  Future<void> play(String url, {required double volume}) async {
    if (url.trim().isEmpty) return;
    try {
      await _player.setReleaseMode(ReleaseMode.loop);
      await _player.setVolume(volume);
      await _player.play(UrlSource(url.trim()));
      _isPlaying = true;
    } catch (_) {
      _isPlaying = false;
    }
  }

  Future<void> pause() async {
    await _player.pause();
    _isPlaying = false;
  }

  Future<void> stop() async {
    await _player.stop();
    _isPlaying = false;
  }

  Future<void> setVolume(double volume) => _player.setVolume(volume);
}
