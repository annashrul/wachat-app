// dart:html dipakai sengaja untuk fitur khusus web (notifikasi & favicon badge).
// ignore_for_file: deprecated_member_use, avoid_web_libraries_in_flutter
import 'dart:html' as html;

/// Notifikasi browser + badge unread di favicon & judul tab (khusus web).
class WebNotify {
  static int _last = -1;

  static Future<void> requestPermission() async {
    try {
      if (html.Notification.supported &&
          html.Notification.permission != 'granted') {
        await html.Notification.requestPermission();
      }
    } catch (_) {}
  }

  static void notify({
    required String title,
    required String body,
    String? icon,
  }) {
    try {
      if (!html.Notification.supported) return;
      if (html.Notification.permission != 'granted') return;
      // Jangan ganggu kalau tab sedang aktif/terlihat.
      if (html.document.visibilityState == 'visible') return;
      html.Notification(title, body: body, icon: icon ?? 'favicon.svg');
    } catch (_) {}
  }

  static void setUnread(int count) {
    if (count == _last) return;
    _last = count;
    try {
      html.document.title = count > 0 ? '($count) WAChat' : 'WAChat';
      _drawFavicon(count);
    } catch (_) {}
  }

  static void _drawFavicon(int count) {
    final canvas = html.CanvasElement(width: 64, height: 64);
    final ctx = canvas.context2D;
    // Kotak biru membulat.
    ctx.setFillColorRgb(0x25, 0x63, 0xEB);
    _roundRect(ctx, 0, 0, 64, 64, 15);
    ctx.fill();
    // Gelembung chat putih.
    ctx.setFillColorRgb(255, 255, 255);
    _roundRect(ctx, 13, 15, 38, 27, 9);
    ctx.fill();
    ctx.beginPath();
    ctx.moveTo(22, 40);
    ctx.lineTo(18, 51);
    ctx.lineTo(31, 42);
    ctx.closePath();
    ctx.fill();
    // Badge merah berisi jumlah.
    if (count > 0) {
      ctx.setFillColorRgb(0xEF, 0x44, 0x44);
      ctx.beginPath();
      ctx.arc(49, 15, 15, 0, 6.2832);
      ctx.fill();
      ctx.setFillColorRgb(255, 255, 255);
      ctx.font = 'bold 24px sans-serif';
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText(count > 9 ? '9+' : '$count', 49, 17);
    }
    final url = canvas.toDataUrl('image/png');
    final link = html.document.getElementById('appicon');
    if (link is html.LinkElement) {
      link.type = 'image/png';
      link.href = url;
    }
  }

  static void _roundRect(html.CanvasRenderingContext2D ctx, num x, num y, num w,
      num h, num r) {
    ctx.beginPath();
    ctx.moveTo(x + r, y);
    ctx.arcTo(x + w, y, x + w, y + h, r);
    ctx.arcTo(x + w, y + h, x, y + h, r);
    ctx.arcTo(x, y + h, x, y, r);
    ctx.arcTo(x, y, x + w, y, r);
    ctx.closePath();
  }
}
