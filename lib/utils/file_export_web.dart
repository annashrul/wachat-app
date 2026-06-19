import 'dart:convert';
// ignore: avoid_web_libraries_in_flutter, deprecated_member_use
import 'dart:html' as html;

/// Unduh [content] sebagai file teks di browser.
Future<void> exportTextFile(String filename, String content,
    {String? subject}) async {
  final bytes = utf8.encode(content);
  final blob = html.Blob([bytes], 'text/plain');
  final url = html.Url.createObjectUrlFromBlob(blob);
  html.AnchorElement(href: url)
    ..download = filename
    ..click();
  html.Url.revokeObjectUrl(url);
}
