/// Konfigurasi alamat backend.
///
/// Default: server produksi (Cloud Run). Untuk dev lokal set [useLan] = true
/// (HP fisik perlu `adb reverse tcp:4100 tcp:4100`).
class AppConfig {
  // Diisi saat build: `flutter build web --dart-define=BACKEND_URL=https://...`
  // Kalau diisi, dipakai untuk SEMUA platform (mis. deploy Cloud Run).
  static const String _envBackend = String.fromEnvironment('BACKEND_URL');

  // Server produksi (Cloud Run) — dipakai sebagai DEFAULT untuk semua build,
  // termasuk APK rilis/debug & web, agar tidak pernah jatuh ke localhost.
  static const String _prodBackend =
      'https://wachat-backend-1018591685581.asia-southeast2.run.app';

  // Set true HANYA untuk dev lokal (HP via `adb reverse tcp:4100 tcp:4100`,
  // atau web di localhost). Default false → selalu ke server produksi.
  static const bool useLan = false;
  static const String lanHost = 'http://localhost:4100';

  static String get baseUrl {
    if (_envBackend.isNotEmpty) return _envBackend;
    if (useLan) return lanHost;
    return _prodBackend;
  }

  static String get apiUrl => '$baseUrl/api';
  static String get socketUrl => baseUrl;

  /// API key Tenor (GIF). Dirancang untuk dipakai sisi-klien; dibatasi ke
  /// tenor.googleapis.com. Bisa di-override saat build via --dart-define.
  static const String tenorApiKey = String.fromEnvironment(
    'TENOR_API_KEY',
    defaultValue: 'AIzaSyBGm5_VqdnwyP6cYFfkQfMAAPAmJqqDddM',
  );
}
