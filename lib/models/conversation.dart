import 'message.dart';
import 'user.dart';

class Conversation {
  final String id;
  final String type; // DIRECT | GROUP
  final String title;
  final String? avatarUrl;
  final AppUser? peer;
  final List<AppUser> members;
  Message? lastMessage;
  int unreadCount;
  DateTime updatedAt;
  bool muted; // notifikasi dibisukan untuk user ini
  int disappearingSeconds; // 0 = nonaktif
  final String? description; // deskripsi grup
  final Map<String, String> roles; // userId -> 'ADMIN' | 'MEMBER'

  bool isAdmin(String userId) => roles[userId] == 'ADMIN';

  // userId -> kapan terakhir membaca / menerima (untuk centang).
  final Map<String, DateTime> readAt;
  final Map<String, DateTime> deliveredAt;

  Conversation({
    required this.id,
    required this.type,
    required this.title,
    required this.members,
    this.avatarUrl,
    this.peer,
    this.lastMessage,
    this.unreadCount = 0,
    required this.updatedAt,
    this.muted = false,
    this.disappearingSeconds = 0,
    this.description,
    Map<String, String>? roles,
    Map<String, DateTime>? readAt,
    Map<String, DateTime>? deliveredAt,
  })  : roles = roles ?? {},
        readAt = readAt ?? {},
        deliveredAt = deliveredAt ?? {};

  bool get isGroup => type == 'GROUP';

  /// Sudah dibaca oleh SEMUA anggota lain (untuk centang biru).
  bool isReadByOthers(DateTime msgTime, String myId) {
    final others = members.where((u) => u.id != myId).toList();
    if (others.isEmpty) return false;
    for (final o in others) {
      final r = readAt[o.id];
      if (r == null || r.isBefore(msgTime)) return false;
    }
    return true;
  }

  /// Sudah sampai ke SEMUA anggota lain (centang dua abu).
  bool isDeliveredToOthers(DateTime msgTime, String myId) {
    final others = members.where((u) => u.id != myId).toList();
    if (others.isEmpty) return false;
    for (final o in others) {
      final d = deliveredAt[o.id];
      if (d == null || d.isBefore(msgTime)) return false;
    }
    return true;
  }

  static Map<String, DateTime> _parseStates(
    List? states,
    String field,
  ) {
    final map = <String, DateTime>{};
    for (final s in states ?? []) {
      final m = s as Map<String, dynamic>;
      final v = m[field] as String?;
      if (v != null) {
        final dt = DateTime.tryParse(v);
        if (dt != null) map[m['userId'] as String] = dt.toLocal();
      }
    }
    return map;
  }

  factory Conversation.fromJson(Map<String, dynamic> json) {
    final states = json['memberStates'] as List?;
    return Conversation(
      id: json['id'] as String,
      type: json['type'] as String? ?? 'DIRECT',
      title: json['title'] as String? ?? 'Chat',
      avatarUrl: json['avatarUrl'] as String?,
      peer: json['peer'] != null
          ? AppUser.fromJson(json['peer'] as Map<String, dynamic>)
          : null,
      members: ((json['members'] as List?) ?? [])
          .map((m) => AppUser.fromJson(m as Map<String, dynamic>))
          .toList(),
      lastMessage: json['lastMessage'] != null
          ? Message.fromJson(json['lastMessage'] as Map<String, dynamic>)
          : null,
      unreadCount: json['unreadCount'] as int? ?? 0,
      muted: json['muted'] == true,
      disappearingSeconds: json['disappearingSeconds'] as int? ?? 0,
      description: json['description'] as String?,
      roles: {
        for (final s in (json['memberStates'] as List? ?? []))
          (s as Map<String, dynamic>)['userId'] as String:
              s['role'] as String? ?? 'MEMBER',
      },
      updatedAt:
          DateTime.tryParse(json['updatedAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      readAt: _parseStates(states, 'lastReadAt'),
      deliveredAt: _parseStates(states, 'lastDeliveredAt'),
    );
  }
}
