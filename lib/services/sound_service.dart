import 'package:flutter/foundation.dart';
import 'package:just_audio/just_audio.dart';

/// Memutar suara notifikasi pesan masuk (foreground/in-app).
class SoundService {
  SoundService._();
  static final SoundService instance = SoundService._();

  final AudioPlayer _player = AudioPlayer();
  bool _ready = false;

  Future<void> _ensure() async {
    if (_ready) return;
    try {
      await _player.setAsset('assets/sounds/notify.wav');
      _ready = true;
    } catch (e) {
      debugPrint('SoundService gagal memuat aset: $e');
    }
  }

  /// Putar nada notifikasi sekali. Aman dipanggil berulang.
  Future<void> playNotify() async {
    try {
      await _ensure();
      if (!_ready) return;
      await _player.seek(Duration.zero);
      await _player.play();
    } catch (e) {
      // Di web, autoplay bisa diblokir sebelum ada interaksi pengguna — abaikan.
      debugPrint('SoundService gagal memutar: $e');
    }
  }
}
