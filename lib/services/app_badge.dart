import 'package:flutter/foundation.dart';
import 'package:app_badge_plus/app_badge_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Badge angka di ikon launcher (ala WhatsApp). Aman dipanggil di web (no-op)
/// dan di isolate background.
class AppBadge {
  static const _key = 'badge_count';

  /// Set badge = [count]; 0 menghapus badge.
  static Future<void> set(int count) async {
    await _persist(count);
    if (kIsWeb) return;
    try {
      if (await AppBadgePlus.isSupported()) {
        await AppBadgePlus.updateBadge(count);
      }
    } catch (_) {}
  }

  /// Tambah 1 (dipakai handler notifikasi background) → total baru.
  static Future<int> increment() async {
    final n = await _read() + 1;
    await set(n);
    return n;
  }

  static Future<int> _read() async {
    try {
      final p = await SharedPreferences.getInstance();
      return p.getInt(_key) ?? 0;
    } catch (_) {
      return 0;
    }
  }

  static Future<void> _persist(int n) async {
    try {
      final p = await SharedPreferences.getInstance();
      await p.setInt(_key, n);
    } catch (_) {}
  }
}
