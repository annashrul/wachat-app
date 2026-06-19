// Ekspor teks ke file. Implementasi berbeda per platform:
// - non-web: tulis file sementara lalu buka share sheet (share_plus)
// - web: unduh sebagai file via blob
export 'file_export_io.dart' if (dart.library.html) 'file_export_web.dart';
