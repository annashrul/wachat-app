import 'package:flutter/foundation.dart';
import '../models/status.dart';
import '../services/socket_service.dart';
import '../services/status_service.dart';

/// Mengelola feed status + pembaruan real-time (status baru & jumlah dilihat).
class StatusProvider extends ChangeNotifier {
  final _service = StatusService();
  final _socket = SocketService.instance;
  bool _attached = false;

  StatusFeed feed = StatusFeed(mine: [], others: []);
  bool loading = false;

  void init(String myUserId) {
    if (!_attached) {
      _attach();
      _attached = true;
    }
    loadFeed();
  }

  void _attach() {
    // Ada status baru dari orang lain (atau perangkat lain kita) → muat ulang.
    _socket.on('status:new', (_) => loadFeed());
    // Status kita dilihat seseorang → perbarui jumlah "dilihat" seketika.
    _socket.on('status:viewed',
        (d) => _onViewed(Map<String, dynamic>.from(d as Map)));
  }

  Future<void> loadFeed() async {
    loading = true;
    notifyListeners();
    try {
      feed = await _service.getFeed();
    } catch (_) {
      // pertahankan feed lama
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  void _onViewed(Map<String, dynamic> m) {
    final id = m['statusId'] as String?;
    final count = m['viewCount'] as int?;
    if (id == null || count == null) return;
    final i = feed.mine.indexWhere((s) => s.id == id);
    if (i >= 0) {
      feed.mine[i] = feed.mine[i].copyWith(viewCount: count);
      notifyListeners();
    }
  }

  /// Jumlah "dilihat" terbaru untuk status milik sendiri (live).
  int? viewCountById(String id) {
    final i = feed.mine.indexWhere((s) => s.id == id);
    return i >= 0 ? feed.mine[i].viewCount : null;
  }

  /// Status cincin avatar untuk [userId]: 'unseen' | 'seen' | null (tak ada).
  String? ringState(String userId) {
    for (final e in feed.others) {
      if (e.user.id == userId) return e.hasUnseen ? 'unseen' : 'seen';
    }
    return null;
  }

  StatusEntry? entryFor(String userId) {
    for (final e in feed.others) {
      if (e.user.id == userId) return e;
    }
    return null;
  }

  Future<void> create({
    required String type,
    String? mediaUrl,
    String? text,
    String? bgColor,
    String? caption,
  }) async {
    await _service.create(
      type: type,
      mediaUrl: mediaUrl,
      text: text,
      bgColor: bgColor,
      caption: caption,
    );
    await loadFeed();
  }

  Future<String> uploadImage(List<int> bytes, String name) =>
      _service.uploadImage(bytes, name);

  void markViewed(String id) => _service.markViewed(id);

  Future<void> deleteStatus(String id) async {
    await _service.delete(id);
    feed.mine.removeWhere((s) => s.id == id);
    notifyListeners();
  }
}
