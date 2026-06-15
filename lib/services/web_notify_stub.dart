/// Implementasi non-web (no-op).
class WebNotify {
  static Future<void> requestPermission() async {}
  static void notify({required String title, required String body, String? icon}) {}
  static void setUnread(int count) {}
}
