import 'dart:convert';

/// Status pengiriman pesan (untuk centang ala WhatsApp).
enum MessageStatus { pending, sent, delivered, read }

/// Konteks status yang dibalas (kutipan thumbnail di gelembung).
class StatusRef {
  final String type; // IMAGE | VIDEO | TEXT | AUDIO
  final String? mediaUrl;
  final String? text;
  final String? bgColor;
  const StatusRef({required this.type, this.mediaUrl, this.text, this.bgColor});

  factory StatusRef.fromJson(Map<String, dynamic> j) => StatusRef(
        type: j['type'] as String? ?? 'IMAGE',
        mediaUrl: j['mediaUrl'] as String?,
        text: j['text'] as String?,
        bgColor: j['bgColor'] as String?,
      );

  static StatusRef? tryParse(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      return StatusRef.fromJson(jsonDecode(raw) as Map<String, dynamic>);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() => {
        'type': type,
        if (mediaUrl != null) 'mediaUrl': mediaUrl,
        if (text != null) 'text': text,
        if (bgColor != null) 'bgColor': bgColor,
      };

  String encode() => jsonEncode(toJson());
}

/// Ringkasan pesan yang dibalas (untuk kutipan reply).
class ReplyPreview {
  final String id;
  final String type;
  final String? content;
  final String? mediaName;
  final String senderName;
  final bool deleted;

  ReplyPreview({
    required this.id,
    required this.type,
    required this.senderName,
    this.content,
    this.mediaName,
    this.deleted = false,
  });

  factory ReplyPreview.fromJson(Map<String, dynamic> j) {
    final s = j['sender'] as Map<String, dynamic>?;
    return ReplyPreview(
      id: j['id'] as String,
      type: j['type'] as String? ?? 'TEXT',
      content: j['content'] as String?,
      mediaName: j['mediaName'] as String?,
      senderName: s?['displayName'] as String? ?? 'Pengguna',
      deleted: j['deletedAt'] != null,
    );
  }
}

/// Satu reaksi emoji pada pesan.
class MessageReaction {
  final String userId;
  final String emoji;
  const MessageReaction({required this.userId, required this.emoji});

  factory MessageReaction.fromJson(Map<String, dynamic> j) => MessageReaction(
        userId: j['userId'] as String? ?? '',
        emoji: j['emoji'] as String? ?? '',
      );

  static List<MessageReaction> listFrom(dynamic raw) {
    if (raw is! List) return [];
    return raw
        .whereType<Map>()
        .map((e) => MessageReaction.fromJson(Map<String, dynamic>.from(e)))
        .toList();
  }
}

class Message {
  final String id;
  final String conversationId;
  final String senderId;
  final String type; // TEXT | IMAGE | FILE | STICKER
  final String? content;
  final String? mediaUrl;
  final String? mediaName;
  final DateTime createdAt;
  final String? senderName;
  final String? senderAvatar;
  final bool pending;
  final String? clientTempId;
  final bool forwarded;
  final bool deleted;
  final String? replyToId;
  final ReplyPreview? replyTo;
  final StatusRef? statusRef;
  final DateTime? expiresAt; // disappearing
  final DateTime? editedAt; // null = belum pernah diedit
  final bool viewOnce;
  bool viewOnceSeen; // mutable: jadi true saat dibuka
  // Reaksi emoji (mutable agar bisa diperbarui in-place saat event socket).
  List<MessageReaction> reactions;

  bool get isExpired =>
      expiresAt != null && expiresAt!.isBefore(DateTime.now());

  Message({
    required this.id,
    required this.conversationId,
    required this.senderId,
    required this.type,
    required this.createdAt,
    this.content,
    this.mediaUrl,
    this.mediaName,
    this.senderName,
    this.senderAvatar,
    this.pending = false,
    this.clientTempId,
    this.forwarded = false,
    this.deleted = false,
    this.replyToId,
    this.replyTo,
    this.statusRef,
    this.expiresAt,
    this.editedAt,
    this.viewOnce = false,
    this.viewOnceSeen = false,
    this.reactions = const [],
  });

  factory Message.fromJson(Map<String, dynamic> json) {
    final sender = json['sender'] as Map<String, dynamic>?;
    return Message(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      senderId: json['senderId'] as String,
      type: json['type'] as String? ?? 'TEXT',
      content: json['content'] as String?,
      mediaUrl: json['mediaUrl'] as String?,
      mediaName: json['mediaName'] as String?,
      createdAt:
          DateTime.tryParse(json['createdAt'] as String? ?? '')?.toLocal() ??
          DateTime.now(),
      senderName: sender?['displayName'] as String?,
      senderAvatar: sender?['avatarUrl'] as String?,
      clientTempId: json['clientTempId'] as String?,
      forwarded: json['forwarded'] == true,
      deleted: json['deletedAt'] != null,
      replyToId: json['replyToId'] as String?,
      replyTo: json['replyTo'] != null
          ? ReplyPreview.fromJson(json['replyTo'] as Map<String, dynamic>)
          : null,
      statusRef: StatusRef.tryParse(json['statusRef'] as String?),
      expiresAt:
          DateTime.tryParse(json['expiresAt'] as String? ?? '')?.toLocal(),
      editedAt:
          DateTime.tryParse(json['editedAt'] as String? ?? '')?.toLocal(),
      viewOnce: json['viewOnce'] == true,
      viewOnceSeen: json['viewOnceSeen'] == true,
      reactions: MessageReaction.listFrom(json['reactions']),
    );
  }

  /// Reaksi dikelompokkan per emoji -> jumlah (untuk ditampilkan di bubble).
  Map<String, int> get reactionCounts {
    final m = <String, int>{};
    for (final r in reactions) {
      m[r.emoji] = (m[r.emoji] ?? 0) + 1;
    }
    return m;
  }

  /// Emoji reaksi milik [userId] (null jika belum bereaksi).
  String? myReaction(String? userId) {
    for (final r in reactions) {
      if (r.userId == userId) return r.emoji;
    }
    return null;
  }

  /// Salinan dengan teks diedit (untuk update optimistic saat edit).
  Message editedCopy(String newContent) => Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        createdAt: createdAt,
        content: newContent,
        mediaUrl: mediaUrl,
        mediaName: mediaName,
        senderName: senderName,
        senderAvatar: senderAvatar,
        pending: pending,
        clientTempId: clientTempId,
        forwarded: forwarded,
        deleted: deleted,
        replyToId: replyToId,
        replyTo: replyTo,
        statusRef: statusRef,
        expiresAt: expiresAt,
        editedAt: DateTime.now(),
        viewOnce: viewOnce,
        viewOnceSeen: viewOnceSeen,
        reactions: reactions,
      );

  /// Salinan dengan status dihapus (untuk update lokal saat message:deleted).
  Message asDeleted() => Message(
        id: id,
        conversationId: conversationId,
        senderId: senderId,
        type: type,
        createdAt: createdAt,
        senderName: senderName,
        deleted: true,
      );
}
