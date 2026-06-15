import 'user.dart';

/// Satu unggahan status (gambar atau teks), berlaku 24 jam.
class StatusItem {
  final String id;
  final String userId;
  final String type; // IMAGE | TEXT | VIDEO | AUDIO
  final String? mediaUrl;
  final String? musicUrl; // audio latar untuk status gambar
  final String? text;
  final String? bgColor;
  final String? caption;
  final List<String> viewers;
  final int viewCount;
  final DateTime createdAt;

  StatusItem({
    required this.id,
    required this.userId,
    required this.type,
    required this.viewers,
    required this.viewCount,
    required this.createdAt,
    this.mediaUrl,
    this.musicUrl,
    this.text,
    this.bgColor,
    this.caption,
  });

  StatusItem copyWith({int? viewCount, List<String>? viewers}) => StatusItem(
        id: id,
        userId: userId,
        type: type,
        mediaUrl: mediaUrl,
        musicUrl: musicUrl,
        text: text,
        bgColor: bgColor,
        caption: caption,
        viewers: viewers ?? this.viewers,
        viewCount: viewCount ?? this.viewCount,
        createdAt: createdAt,
      );

  factory StatusItem.fromJson(Map<String, dynamic> j) {
    return StatusItem(
      id: j['id'] as String,
      userId: j['userId'] as String,
      type: j['type'] as String? ?? 'IMAGE',
      mediaUrl: j['mediaUrl'] as String?,
      musicUrl: j['musicUrl'] as String?,
      text: j['text'] as String?,
      bgColor: j['bgColor'] as String?,
      caption: j['caption'] as String?,
      viewers: ((j['viewers'] as List?) ?? []).map((e) => e as String).toList(),
      viewCount: j['viewCount'] as int? ?? 0,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
    );
  }
}

/// Kumpulan status milik satu pengguna (untuk daftar "Pembaruan terkini").
class StatusEntry {
  final AppUser user;
  final List<StatusItem> statuses;
  final bool hasUnseen;

  StatusEntry({
    required this.user,
    required this.statuses,
    required this.hasUnseen,
  });

  DateTime get lastAt => statuses.isEmpty
      ? DateTime.fromMillisecondsSinceEpoch(0)
      : statuses.last.createdAt;

  factory StatusEntry.fromJson(Map<String, dynamic> j) {
    return StatusEntry(
      user: AppUser.fromJson(j['user'] as Map<String, dynamic>),
      statuses: ((j['statuses'] as List?) ?? [])
          .map((e) => StatusItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      hasUnseen: j['hasUnseen'] == true,
    );
  }
}

class StatusFeed {
  final List<StatusItem> mine;
  final List<StatusEntry> others;
  StatusFeed({required this.mine, required this.others});

  factory StatusFeed.fromJson(Map<String, dynamic> j) {
    return StatusFeed(
      mine: ((j['mine'] as List?) ?? [])
          .map((e) => StatusItem.fromJson(e as Map<String, dynamic>))
          .toList(),
      others: ((j['others'] as List?) ?? [])
          .map((e) => StatusEntry.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }
}
