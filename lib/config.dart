import 'package:flutter/foundation.dart';

/// Konfigurasi alamat backend.
///
/// - Web (Chrome)            -> http://localhost:3000
/// - Android Emulator        -> http://10.0.2.2:3000  (10.0.2.2 = host dari emulator)
/// - HP fisik / device lain  -> ganti [lanHost] dengan IP LAN komputer Anda,
///                              mis. http://192.168.1.10:3000, lalu set [useLan] = true.
class AppConfig {
  static const bool useLan = true;
  // HP fisik via USB/WiFi-debug + `adb reverse tcp:4100 tcp:4100`:
  //   localhost di HP diteruskan ke localhost komputer (tanpa WiFi/firewall).
  // Kalau mau lewat WiFi langsung: ganti ke 'http://192.168.11.231:4100'.
  static const String lanHost = 'http://localhost:4100';

  static String get baseUrl {
    if (useLan) return lanHost;
    if (kIsWeb) return 'http://localhost:3000';
    // Default platform mobile (Android emulator).
    return 'http://10.0.2.2:3000';
  }

  static String get apiUrl => '$baseUrl/api';
  static String get socketUrl => baseUrl;
}
