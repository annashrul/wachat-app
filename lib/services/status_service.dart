import 'package:dio/dio.dart';
import '../models/status.dart';
import '../models/user.dart';
import 'api_client.dart';

class StatusService {
  final _api = ApiClient.instance;

  Future<StatusFeed> getFeed() async {
    final res = await _api.dio.get('/status');
    return StatusFeed.fromJson(Map<String, dynamic>.from(res.data as Map));
  }

  /// Daftar user yang melihat sebuah status (hanya pemilik).
  Future<List<AppUser>> getViewers(String statusId) async {
    final res = await _api.dio.get('/status/$statusId/viewers');
    return (res.data as List)
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> create({
    required String type,
    String? mediaUrl,
    String? musicUrl,
    String? text,
    String? bgColor,
    String? caption,
  }) async {
    await _api.dio.post('/status', data: {
      'type': type,
      'mediaUrl': ?mediaUrl,
      'musicUrl': ?musicUrl,
      'text': ?text,
      'bgColor': ?bgColor,
      'caption': ?caption,
    });
  }

  Future<void> markViewed(String id) async {
    try {
      await _api.dio.post('/status/$id/view');
    } catch (_) {}
  }

  Future<void> delete(String id) async {
    await _api.dio.delete('/status/$id');
  }

  /// Upload media status (gambar/video/audio) via endpoint /upload.
  Future<String> uploadMedia(List<int> bytes, String filename,
      {String? mime}) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(
        bytes,
        filename: filename,
        contentType: mime != null ? DioMediaType.parse(mime) : null,
      ),
    });
    final res = await _api.dio.post('/upload', data: form);
    return (res.data as Map<String, dynamic>)['url'] as String;
  }
}
