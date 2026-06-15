/// Status pengiriman pesan (untuk centang ala WhatsApp).
enum MessageStatus { pending, sent, delivered, read }

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
    );
  }

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
