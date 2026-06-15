import 'dart:async';
import 'package:flutter/foundation.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../services/chat_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';

/// Mengelola daftar percakapan + pesan percakapan aktif, status koneksi,
/// indikator mengetik (per percakapan), dan tanda terima (centang).
class ChatProvider extends ChangeNotifier {
  final _chat = ChatService();
  final _socket = SocketService.instance;

  String? _myUserId;
  bool _listenersAttached = false;
  int _tempCounter = 0;

  bool connected = false;

  List<Conversation> conversations = [];
  bool loadingConversations = false;

  String? activeConversationId;
  List<Message> messages = [];
  bool loadingMessages = false;

  // Pagination (muat pesan lama saat scroll ke atas).
  static const int _pageSize = 30;
  bool hasMore = true;
  bool loadingMore = false;

  Future<void> loadMore(String convId) async {
    if (loadingMore ||
        !hasMore ||
        messages.isEmpty ||
        convId != activeConversationId) {
      return;
    }
    loadingMore = true;
    notifyListeners();
    try {
      final oldest = messages.first.id;
      final older = await _chat.getMessages(convId, before: oldest);
      if (older.length < _pageSize) hasMore = false;
      if (older.isNotEmpty) {
        messages = [...older, ...messages];
        _messageCache[convId] = List.of(messages);
      }
    } catch (_) {
      // biarkan; bisa dicoba lagi saat scroll
    } finally {
      loadingMore = false;
      notifyListeners();
    }
  }

  // Pesan yang sedang dibalas (reply).
  Message? replyingTo;
  void setReplyingTo(Message? m) {
    replyingTo = m;
    notifyListeners();
  }

  // conversationId -> userId yang sedang mengetik (semua percakapan).
  final Map<String, Set<String>> typingByConv = {};
  final Map<String, Timer> _typingTimers = {};

  // Cache pesan & draft input per percakapan.
  final Map<String, List<Message>> _messageCache = {};
  final Map<String, String> _drafts = {};

  // Presence: status online & terakhir dilihat per user.
  final Map<String, bool> _online = {};
  final Map<String, DateTime> _lastSeen = {};

  bool isOnline(String userId) => _online[userId] ?? false;
  DateTime? lastSeenOf(String userId) => _lastSeen[userId];

  String getDraft(String convId) => _drafts[convId] ?? '';

  void setDraft(String convId, String text) {
    if (text.trim().isEmpty) {
      _drafts.remove(convId);
    } else {
      _drafts[convId] = text;
    }
  }

  /// User yang mengetik di percakapan yang sedang dibuka.
  Set<String> get typingUsers =>
      typingByConv[activeConversationId] ?? <String>{};

  Set<String> typingFor(String convId) => typingByConv[convId] ?? <String>{};

  Conversation? conversationById(String id) {
    for (final c in conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  void init(String myUserId) {
    _myUserId = myUserId;
    connected = _socket.connected;
    if (!_listenersAttached) {
      _attachListeners();
      _listenersAttached = true;
    }
  }

  void _attachListeners() {
    _socket.on('connect', (_) {
      connected = true;
      notifyListeners();
    });
    _socket.on('disconnect', (_) {
      connected = false;
      notifyListeners();
    });
    _socket.on('message:new', (data) {
      _onIncomingMessage(
        Message.fromJson(Map<String, dynamic>.from(data as Map)),
      );
    });
    _socket.on('typing', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _onTyping(
        map['conversationId'] as String,
        map['userId'] as String,
        map['isTyping'] == true,
      );
    });
    _socket.on('message:read', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _applyReceipt(map, read: true);
    });
    _socket.on('message:delivered', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _applyReceipt(map, read: false);
    });
    _socket.on('message:deleted', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _onMessageDeleted(
        map['conversationId'] as String,
        map['messageId'] as String,
      );
    });
    _socket.on('presence', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final uid = map['userId'] as String;
      _online[uid] = map['online'] == true;
      final ls = map['lastSeen'] as String?;
      if (ls != null) {
        final dt = DateTime.tryParse(ls);
        if (dt != null) _lastSeen[uid] = dt.toLocal();
      }
      notifyListeners();
    });
  }

  void _onMessageDeleted(String convId, String messageId) {
    if (convId == activeConversationId) {
      final i = messages.indexWhere((m) => m.id == messageId);
      if (i >= 0) messages[i] = messages[i].asDeleted();
    }
    final cached = _messageCache[convId];
    if (cached != null) {
      final i = cached.indexWhere((m) => m.id == messageId);
      if (i >= 0) cached[i] = cached[i].asDeleted();
    }
    // Update preview daftar bila pesan terakhir yang dihapus.
    final c = conversationById(convId);
    if (c?.lastMessage?.id == messageId) {
      c!.lastMessage = c.lastMessage!.asDeleted();
    }
    notifyListeners();
  }

  void deleteMessage(String messageId) {
    _socket.emit('message:delete', {'messageId': messageId});
  }

  Future<void> deleteConversation(String conversationId) async {
    await _chat.deleteConversation(conversationId);
    conversations.removeWhere((c) => c.id == conversationId);
    _messageCache.remove(conversationId);
    _drafts.remove(conversationId);
    notifyListeners();
  }

  void forwardTo(List<String> conversationIds, Message m) {
    for (final id in conversationIds) {
      _socket.emit('message:send', {
        'conversationId': id,
        'type': m.type,
        if (m.content != null) 'content': m.content,
        if (m.mediaUrl != null) 'mediaUrl': m.mediaUrl,
        if (m.mediaName != null) 'mediaName': m.mediaName,
        'forwarded': true,
      });
    }
  }

  void _applyReceipt(Map<String, dynamic> map, {required bool read}) {
    final convId = map['conversationId'] as String;
    final userId = map['userId'] as String;
    final at = DateTime.tryParse(map['at'] as String? ?? '')?.toLocal();
    if (at == null) return;
    final c = conversationById(convId);
    if (c == null) return;
    if (read) {
      c.readAt[userId] = at;
      c.deliveredAt[userId] = at; // dibaca ⇒ pasti sampai
    } else {
      c.deliveredAt[userId] = at;
    }
    notifyListeners();
  }

  void _onTyping(String convId, String userId, bool isTyping) {
    if (userId == _myUserId) return;
    final key = '$convId|$userId';
    _typingTimers[key]?.cancel();
    final set = typingByConv.putIfAbsent(convId, () => <String>{});
    if (isTyping) {
      set.add(userId);
      // Auto-hapus kalau tidak ada update lagi (anti "typing nyangkut").
      _typingTimers[key] = Timer(const Duration(seconds: 6), () {
        typingByConv[convId]?.remove(userId);
        _typingTimers.remove(key);
        notifyListeners();
      });
    } else {
      set.remove(userId);
      _typingTimers.remove(key);
    }
    notifyListeners();
  }

  void _onIncomingMessage(Message msg) {
    final isActive = msg.conversationId == activeConversationId;
    final isMine = msg.senderId == _myUserId;

    if (isActive) {
      // Ganti pesan optimistic kalau cocok clientTempId.
      var replaced = false;
      if (msg.clientTempId != null) {
        final ti = messages.indexWhere((m) => m.id == msg.clientTempId);
        if (ti >= 0) {
          messages[ti] = msg;
          replaced = true;
        }
      }
      if (!replaced && !messages.any((m) => m.id == msg.id)) {
        messages.add(msg);
      }
      typingByConv[msg.conversationId]?.remove(msg.senderId);
      if (!isMine) {
        _chat.markRead(msg.conversationId);
        _socket.emit('message:read', {'conversationId': msg.conversationId});
      }
    }

    // Tanda "sampai" untuk pesan masuk (walau tidak sedang dibuka).
    if (!isMine) {
      _socket.emit('message:delivered', {
        'conversationId': msg.conversationId,
      });
    }

    final idx = conversations.indexWhere((c) => c.id == msg.conversationId);
    if (idx >= 0) {
      final c = conversations.removeAt(idx);
      c.lastMessage = msg;
      c.updatedAt = msg.createdAt;
      if (!isActive && !isMine) c.unreadCount += 1;
      conversations.insert(0, c);
    } else if (!isMine) {
      loadConversations();
    }
    notifyListeners();
  }

  Future<void> loadConversations() async {
    loadingConversations = true;
    notifyListeners();
    try {
      conversations = await _chat.getConversations();
      for (final c in conversations) {
        final p = c.peer;
        if (p?.lastSeen != null) {
          _lastSeen.putIfAbsent(p!.id, () => p.lastSeen!);
        }
      }
    } finally {
      loadingConversations = false;
      notifyListeners();
    }
  }

  /// Teks presence untuk header chat DIRECT ("online" / "terakhir dilihat …").
  String? presenceText(Conversation c) {
    if (c.isGroup) return null;
    final peer = c.peer;
    if (peer == null) return null;
    if (isOnline(peer.id)) return 'online';
    final ls = lastSeenOf(peer.id) ?? peer.lastSeen;
    if (ls == null) return null;
    return 'terakhir dilihat ${_relativeTime(ls)}';
  }

  String _relativeTime(DateTime dt) {
    final now = DateTime.now();
    if (now.difference(dt).inMinutes < 1) return 'baru saja';
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final days = today.difference(d).inDays;
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}.${dt.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'pukul $hm';
    if (days == 1) return 'kemarin $hm';
    return '${dt.day}/${dt.month} $hm';
  }

  Future<void> openConversation(String conversationId) async {
    activeConversationId = conversationId;
    NotificationService.instance.activeConversationId = conversationId;
    hasMore = true;
    loadingMore = false;
    // Kalau sudah pernah dibuka, tampilkan dari cache (tanpa spinner) lalu
    // refresh diam-diam di belakang.
    final cached = _messageCache[conversationId];
    if (cached != null) {
      messages = List.of(cached);
      loadingMessages = false;
    } else {
      messages = [];
      loadingMessages = true;
    }
    notifyListeners();

    _socket.emit('conversation:join', {'conversationId': conversationId});
    try {
      final fresh = await _chat.getMessages(conversationId);
      messages = fresh;
      hasMore = fresh.length >= _pageSize;
      _messageCache[conversationId] = List.of(fresh);
      await _chat.markRead(conversationId);
      _socket.emit('message:read', {'conversationId': conversationId});
      final idx = conversations.indexWhere((c) => c.id == conversationId);
      if (idx >= 0) conversations[idx].unreadCount = 0;
    } finally {
      loadingMessages = false;
      notifyListeners();
    }
  }

  void closeConversation() {
    // Simpan pesan ke cache supaya buka ulang langsung tampil.
    if (activeConversationId != null) {
      _messageCache[activeConversationId!] = List.of(messages);
    }
    activeConversationId = null;
    NotificationService.instance.activeConversationId = null;
    messages = [];
    replyingTo = null;
  }

  // ===== Kirim pesan (optimistic) =====
  Message _optimistic(String convId, String type,
      {String? content, String? mediaUrl, String? mediaName, Message? reply}) {
    final tempId =
        'temp_${DateTime.now().microsecondsSinceEpoch}_${_tempCounter++}';
    return Message(
      id: tempId,
      conversationId: convId,
      senderId: _myUserId ?? '',
      type: type,
      content: content,
      mediaUrl: mediaUrl,
      mediaName: mediaName,
      createdAt: DateTime.now(),
      pending: true,
      clientTempId: tempId,
      replyToId: reply?.id,
      replyTo: reply == null
          ? null
          : ReplyPreview(
              id: reply.id,
              type: reply.type,
              content: reply.content,
              mediaName: reply.mediaName,
              senderName: reply.senderName ?? 'Pengguna',
            ),
    );
  }

  void _emitSend(Message m) {
    _socket.emit('message:send', {
      'conversationId': m.conversationId,
      'type': m.type,
      if (m.content != null) 'content': m.content,
      if (m.mediaUrl != null) 'mediaUrl': m.mediaUrl,
      if (m.mediaName != null) 'mediaName': m.mediaName,
      if (m.replyToId != null) 'replyToId': m.replyToId,
      'clientTempId': m.clientTempId,
    });
  }

  void _addOptimistic(Message m) {
    if (m.conversationId == activeConversationId) messages.add(m);
    final idx = conversations.indexWhere((c) => c.id == m.conversationId);
    if (idx >= 0) {
      final c = conversations.removeAt(idx);
      c.lastMessage = m;
      c.updatedAt = m.createdAt;
      conversations.insert(0, c);
    }
    replyingTo = null; // selesai membalas
    notifyListeners();
    _emitSend(m);
  }

  void sendText(String conversationId, String text) {
    _addOptimistic(
        _optimistic(conversationId, 'TEXT', content: text, reply: replyingTo));
  }

  void sendSticker(String conversationId, String sticker) {
    _addOptimistic(_optimistic(conversationId, 'STICKER',
        content: sticker, reply: replyingTo));
  }

  void sendMedia(
    String conversationId, {
    required String type,
    required String mediaUrl,
    required String mediaName,
  }) {
    _addOptimistic(_optimistic(conversationId, type,
        mediaUrl: mediaUrl, mediaName: mediaName, reply: replyingTo));
  }

  void setTyping(String conversationId, bool isTyping) {
    _socket.emit('typing', {
      'conversationId': conversationId,
      'isTyping': isTyping,
    });
  }

  /// Status centang untuk pesan saya.
  MessageStatus statusOf(Message m, Conversation conv) {
    if (m.pending) return MessageStatus.pending;
    if (conv.isReadByOthers(m.createdAt, _myUserId ?? '')) {
      return MessageStatus.read;
    }
    if (conv.isDeliveredToOthers(m.createdAt, _myUserId ?? '')) {
      return MessageStatus.delivered;
    }
    return MessageStatus.sent;
  }

  ChatService get service => _chat;

  void reset() {
    conversations = [];
    messages = [];
    activeConversationId = null;
    replyingTo = null;
    _messageCache.clear();
    _drafts.clear();
    typingByConv.clear();
    for (final t in _typingTimers.values) {
      t.cancel();
    }
    _typingTimers.clear();
    _listenersAttached = false;
    _socket.off('connect');
    _socket.off('disconnect');
    _socket.off('message:new');
    _socket.off('typing');
    _socket.off('message:read');
    _socket.off('message:delivered');
    notifyListeners();
  }
}
