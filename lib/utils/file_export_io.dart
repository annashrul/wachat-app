import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Tulis [content] ke file sementara dan buka share sheet sistem.
Future<void> exportTextFile(String filename, String content,
    {String? subject}) async {
  final dir = await getTemporaryDirectory();
  final file = File('${dir.path}/$filename');
  await file.writeAsString(content);
  await SharePlus.instance.share(
    ShareParams(
      files: [XFile(file.path, mimeType: 'text/plain', name: filename)],
      subject: subject,
    ),
  );
}
