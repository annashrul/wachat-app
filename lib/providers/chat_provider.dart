import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../services/chat_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import '../services/web_notify.dart';
import '../services/app_badge.dart';

/// Mengelola daftar percakapan + pesan percakapan aktif, status koneksi,
/// indikator mengetik (per percakapan), dan tanda terima (centang).
class ChatProvider extends ChangeNotifier {
  final _chat = ChatService();
  final _socket = SocketService.instance;

  String? _myUserId;
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
  Timer? _expiryTimer; // buang pesan disappearing yang kedaluwarsa

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

  /// Total pesan belum dibaca di seluruh percakapan (untuk badge tab Chat).
  int get totalUnread =>
      conversations.fold(0, (sum, c) => sum + c.unreadCount);

  /// Perbarui badge web (judul tab + favicon) langsung dari lapisan data.
  ///
  /// Penting: jangan mengandalkan `build()` HomeScreen untuk ini. Flutter web
  /// membekukan render loop saat tab di latar belakang, sehingga badge tidak
  /// akan ter-update sampai tab kembali aktif. Memanggilnya di sini (dari
  /// handler event socket) memastikan badge naik/turun seketika walau tab
  /// sedang tidak terlihat.
  void _syncWebBadge() {
    WebNotify.setUnread(totalUnread); // badge web (judul tab + favicon)
    AppBadge.set(totalUnread); // badge ikon launcher (Android)
  }

  Conversation? conversationById(String id) {
    for (final c in conversations) {
      if (c.id == id) return c;
    }
    return null;
  }

  void init(String myUserId) {
    _myUserId = myUserId;
    connected = _socket.connected;
    // Selalu pasang ulang: tiap login membuat socket baru (forceNew), jadi
    // listener harus mengikuti socket akun terbaru, bukan socket lama.
    _attachListeners();
    _loadFavorites();
    _loadArchived();
    _loadPinned();
    loadStarred();
    loadContacts();
    _expiryTimer ??=
        Timer.periodic(const Duration(seconds: 20), (_) => purgeExpiredLocal());
  }

  // ===== Favorit (disimpan lokal per perangkat) =====
  static const _favKey = 'favorite_convs';
  final Set<String> _favorites = {};

  bool isFavorite(String id) => _favorites.contains(id);

  Future<void> _loadFavorites() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _favorites
        ..clear()
        ..addAll(prefs.getStringList(_favKey) ?? []);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleFavorite(String id) async {
    if (!_favorites.add(id)) _favorites.remove(id);
    await _persistFavorites();
  }

  Future<void> setFavorite(String id, bool value) async {
    if (value) {
      _favorites.add(id);
    } else {
      _favorites.remove(id);
    }
    await _persistFavorites();
  }

  Future<void> _persistFavorites() async {
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_favKey, _favorites.toList());
    } catch (_) {}
  }

  // ===== Arsip (disimpan lokal per perangkat, seperti favorit) =====
  static const _archiveKey = 'archived_convs';
  final Set<String> _archived = {};

  bool isArchived(String id) => _archived.contains(id);
  int get archivedCount =>
      conversations.where((c) => _archived.contains(c.id)).length;

  Future<void> _loadArchived() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _archived
        ..clear()
        ..addAll(prefs.getStringList(_archiveKey) ?? []);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setArchived(String id, bool value) async {
    if (value) {
      _archived.add(id);
    } else {
      _archived.remove(id);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_archiveKey, _archived.toList());
    } catch (_) {}
  }

  // ===== Pin chat (lokal per perangkat) =====
  static const _pinKey = 'pinned_convs';
  final Set<String> _pinned = {};

  bool isPinned(String id) => _pinned.contains(id);

  Future<void> _loadPinned() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _pinned
        ..clear()
        ..addAll(prefs.getStringList(_pinKey) ?? []);
      notifyListeners();
    } catch (_) {}
  }

  Future<void> setPinned(String id, bool value) async {
    if (value) {
      _pinned.add(id);
    } else {
      _pinned.remove(id);
    }
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setStringList(_pinKey, _pinned.toList());
    } catch (_) {}
  }

  // ===== Kontak (shared, agar realtime lintas layar) =====
  List<({String id, String? alias, AppUser user})> contacts = [];
  final Set<String> _contactUserIds = {};

  bool isSavedContact(String userId) => _contactUserIds.contains(userId);

  Future<void> loadContacts() async {
    try {
      contacts = await _chat.getContacts();
      _contactUserIds
        ..clear()
        ..addAll(contacts.map((c) => c.user.id));
      notifyListeners();
    } catch (_) {}
  }

  /// Tambah kontak lalu segarkan daftar kontak & percakapan (realtime).
  Future<void> addContact(String userId, {String? alias}) async {
    await _chat.addContact(userId, alias: alias);
    await loadContacts();
    await loadConversations();
  }

  Future<void> deleteContact(String contactId) async {
    await _chat.deleteContact(contactId);
    await loadContacts();
    await loadConversations(); // judul/peerIsContact ikut update (→ nomor)
  }

  // ===== Pesan berbintang (server-side) =====
  final Set<String> _starredIds = {};
  List<Message> starredMessages = [];

  bool isStarred(String messageId) => _starredIds.contains(messageId);

  Future<void> loadStarred() async {
    try {
      starredMessages = await _chat.getStarred();
      _starredIds
        ..clear()
        ..addAll(starredMessages.map((m) => m.id));
      notifyListeners();
    } catch (_) {}
  }

  Future<void> toggleStar(String messageId, bool starred) async {
    if (starred) {
      _starredIds.add(messageId);
    } else {
      _starredIds.remove(messageId);
      starredMessages.removeWhere((m) => m.id == messageId);
    }
    notifyListeners();
    try {
      await _chat.setStarred(messageId, starred);
      if (starred) await loadStarred(); // segarkan daftar berbintang
    } catch (_) {
      // revert
      if (starred) {
        _starredIds.remove(messageId);
      } else {
        _starredIds.add(messageId);
      }
      notifyListeners();
    }
  }

  // ===== Bisukan notifikasi (server-side) =====
  /// Set bisukan untuk dipakai handler notifikasi foreground (FCM).
  bool isMuted(String id) => conversationById(id)?.muted ?? false;

  Future<void> setMuted(String id, bool value) async {
    final c = conversationById(id);
    if (c != null) c.muted = value;
    notifyListeners();
    _syncMutedToNotif();
    try {
      await _chat.setMuted(id, value);
    } catch (_) {
      // gagal: kembalikan state
      if (c != null) c.muted = !value;
      notifyListeners();
      _syncMutedToNotif();
    }
  }

  /// Sinkronkan daftar conv yang dibisukan ke NotificationService agar
  /// notifikasi foreground (FCM) untuk chat tsb tidak ditampilkan.
  void _syncMutedToNotif() {
    NotificationService.instance.mutedConversations = conversations
        .where((c) => c.muted)
        .map((c) => c.id)
        .toSet();
  }

  /// Tandai sebuah percakapan sudah dibaca (reset badge + kabari server).
  Future<void> markConvRead(String id) async {
    final c = conversationById(id);
    if (c != null) c.unreadCount = 0;
    _syncWebBadge();
    notifyListeners();
    try {
      await _chat.markRead(id);
      _socket.emit('message:read', {'conversationId': id});
    } catch (_) {}
  }

  void _attachListeners() {
    // Lepas dulu agar tidak terdaftar ganda bila init dipanggil pada socket sama.
    for (final e in const [
      'connect',
      'disconnect',
      'message:new',
      'typing',
      'message:read',
      'message:delivered',
      'message:deleted',
      'message:edited',
      'message:reaction',
      'message:viewonce',
      'poll:results',
      'presence',
    ]) {
      _socket.off(e);
    }
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
      // Sinkron lintas perangkat: kalau yang membaca adalah SAYA (di perangkat
      // lain, mis. web ↔ apk), reset badge unread percakapan ini di sini juga.
      if (map['userId'] == _myUserId) {
        final convId = map['conversationId'] as String?;
        final c = convId == null ? null : conversationById(convId);
        if (c != null && c.unreadCount != 0) {
          c.unreadCount = 0;
          _syncWebBadge();
          notifyListeners();
        }
      }
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
    _socket.on('message:reaction', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _onReaction(
        map['conversationId'] as String?,
        map['messageId'] as String,
        MessageReaction.listFrom(map['reactions']),
      );
    });
    _socket.on('message:viewonce', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      _onViewOnce(
        map['conversationId'] as String?,
        map['messageId'] as String,
      );
    });
    _socket.on('poll:results', (data) {
      final map = Map<String, dynamic>.from(data as Map);
      final votes = ((map['votes'] as List?) ?? [])
          .whereType<Map>()
          .map((e) => (
                userId: e['userId'] as String? ?? '',
                option: (e['optionIndex'] as num?)?.toInt() ?? 0,
              ))
          .toList();
      _onPollResults(map['conversationId'] as String?,
          map['messageId'] as String, votes);
    });
    _socket.on('message:edited', (data) {
      _onMessageEdited(
        Message.fromJson(Map<String, dynamic>.from(data as Map)),
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

  /// Terapkan daftar reaksi terbaru ke pesan terkait (in-place).
  void _onReaction(
      String? convId, String messageId, List<MessageReaction> reactions) {
    for (final m in messages) {
      if (m.id == messageId) m.reactions = reactions;
    }
    if (convId != null) {
      final cached = _messageCache[convId];
      if (cached != null) {
        for (final m in cached) {
          if (m.id == messageId) m.reactions = reactions;
        }
      }
    }
    notifyListeners();
  }

  /// Toggle reaksi emoji pada sebuah pesan (kirim ke server).
  void react(String messageId, String emoji) {
    _socket.emit('message:react', {'messageId': messageId, 'emoji': emoji});
  }

  /// Kirim editan teks pesan + tampilkan langsung (optimistic).
  void editMessage(String messageId, String content) {
    _socket.emit('message:edit', {'messageId': messageId, 'content': content});
    // Optimistic: langsung tampilkan editan tanpa menunggu echo server.
    final i = messages.indexWhere((m) => m.id == messageId);
    if (i >= 0) {
      _onMessageEdited(messages[i].editedCopy(content));
    } else {
      notifyListeners();
    }
  }

  void _onMessageEdited(Message msg) {
    final i = messages.indexWhere((m) => m.id == msg.id);
    if (i >= 0) messages[i] = msg;
    final cached = _messageCache[msg.conversationId];
    if (cached != null) {
      final ci = cached.indexWhere((m) => m.id == msg.id);
      if (ci >= 0) cached[ci] = msg;
    }
    final c = conversationById(msg.conversationId);
    if (c?.lastMessage?.id == msg.id) c!.lastMessage = msg;
    notifyListeners();
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
    _syncWebBadge();
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
    String convTitle = msg.senderName ?? 'Pesan baru';
    if (idx >= 0) {
      final c = conversations.removeAt(idx);
      c.lastMessage = msg;
      c.updatedAt = msg.createdAt;
      if (!isActive && !isMine) c.unreadCount += 1;
      convTitle = c.isGroup ? c.title : (msg.senderName ?? c.title);
      conversations.insert(0, c);
    } else if (!isMine) {
      loadConversations();
    }
    // Notifikasi browser (web) untuk pesan masuk dari orang lain (kecuali bisu).
    if (!isMine && !(conversationById(msg.conversationId)?.muted ?? false)) {
      final c = conversationById(msg.conversationId);
      final body = c != null && c.isGroup
          ? '${msg.senderName ?? ''}: ${_previewText(msg)}'
          : _previewText(msg);
      WebNotify.notify(title: convTitle, body: body);
    }
    // Update badge seketika (tab latar belakang tidak menunggu rebuild).
    _syncWebBadge();
    notifyListeners();
  }

  String _previewText(Message m) {
    switch (m.type) {
      case 'IMAGE':
        return '📷 Foto';
      case 'FILE':
        return '📎 ${m.mediaName ?? 'File'}';
      case 'VOICE':
        return '🎤 Pesan suara';
      case 'STICKER':
        return '🙂 Stiker';
      case 'CALL':
        return (m.content ?? '').split('|').elementAtOrNull(2) == '1'
            ? '📹 Panggilan video'
            : '📞 Panggilan suara';
      case 'LOCATION':
        return '📍 Lokasi';
      case 'CONTACT':
        return '👤 Kontak';
      case 'ALBUM':
        return '🖼️ Foto';
      case 'POLL':
        return '📊 Polling';
      default:
        return m.content ?? '';
    }
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
      _syncMutedToNotif();
    } finally {
      loadingConversations = false;
      _syncWebBadge();
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
      _syncWebBadge();
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
      {String? content,
      String? mediaUrl,
      String? mediaName,
      Message? reply,
      StatusRef? statusRef,
      bool viewOnce = false}) {
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
      statusRef: statusRef,
      viewOnce: viewOnce,
    );
  }

  void _emitSend(Message m) {
    _socket.emit('message:send', {
      'conversationId': m.conversationId,
      'type': m.type,
      if (m.viewOnce) 'viewOnce': true,
      if (m.content != null) 'content': m.content,
      if (m.mediaUrl != null) 'mediaUrl': m.mediaUrl,
      if (m.mediaName != null) 'mediaName': m.mediaName,
      if (m.replyToId != null) 'replyToId': m.replyToId,
      if (m.statusRef != null) 'statusRef': m.statusRef!.encode(),
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

  void sendText(String conversationId, String text, {StatusRef? statusRef}) {
    _addOptimistic(_optimistic(conversationId, 'TEXT',
        content: text, reply: replyingTo, statusRef: statusRef));
  }

  void sendSticker(String conversationId, String sticker,
      {StatusRef? statusRef}) {
    _addOptimistic(_optimistic(conversationId, 'STICKER',
        content: sticker, reply: replyingTo, statusRef: statusRef));
  }

  /// Kirim lokasi sebagai pesan (content = "lat,lng").
  void sendLocation(String conversationId, double lat, double lng) {
    _addOptimistic(_optimistic(conversationId, 'LOCATION',
        content: '$lat,$lng', reply: replyingTo));
  }

  /// Kirim polling — content = JSON {q, options:[...]}.
  void sendPoll(String conversationId, String question, List<String> options) {
    _addOptimistic(_optimistic(conversationId, 'POLL',
        content: jsonEncode({'q': question, 'options': options}),
        reply: replyingTo));
  }

  /// Voting polling (pilihan tunggal) → kirim ke server.
  void votePoll(String messageId, int optionIndex) {
    _socket.emit('poll:vote', {'messageId': messageId, 'optionIndex': optionIndex});
  }

  void _onPollResults(String? convId, String messageId,
      List<({String userId, int option})> votes) {
    for (final m in messages) {
      if (m.id == messageId) m.pollVotes = votes;
    }
    if (convId != null) {
      for (final m in (_messageCache[convId] ?? <Message>[])) {
        if (m.id == messageId) m.pollVotes = votes;
      }
    }
    notifyListeners();
  }

  /// Kirim album (beberapa foto) — content = JSON array of url.
  void sendAlbum(String conversationId, List<String> urls) {
    _addOptimistic(_optimistic(conversationId, 'ALBUM',
        content: jsonEncode(urls), reply: replyingTo));
  }

  /// Kirim kartu kontak (content = JSON {name, phone, userId?}).
  void sendContact(String conversationId, String contactJson) {
    _addOptimistic(_optimistic(conversationId, 'CONTACT',
        content: contactJson, reply: replyingTo));
  }

  void sendMedia(
    String conversationId, {
    required String type,
    required String mediaUrl,
    required String mediaName,
    String? content,
    bool viewOnce = false,
  }) {
    _addOptimistic(_optimistic(conversationId, type,
        mediaUrl: mediaUrl,
        mediaName: mediaName,
        content: content,
        reply: replyingTo,
        viewOnce: viewOnce));
  }

  /// Sematkan / lepas pesan tersemat di percakapan.
  Future<void> pinMessage(String conversationId, String? messageId) async {
    final c = conversationById(conversationId);
    final prev = c?.pinnedMessageId;
    if (c != null) c.pinnedMessageId = messageId;
    notifyListeners();
    try {
      await _chat.pinMessage(conversationId, messageId);
    } catch (_) {
      if (c != null) c.pinnedMessageId = prev;
      notifyListeners();
    }
  }

  /// Atur timer disappearing untuk percakapan.
  Future<void> setDisappearing(String conversationId, int seconds) async {
    final c = conversationById(conversationId);
    final prev = c?.disappearingSeconds ?? 0;
    if (c != null) c.disappearingSeconds = seconds;
    notifyListeners();
    try {
      await _chat.setDisappearing(conversationId, seconds);
    } catch (_) {
      if (c != null) c.disappearingSeconds = prev;
      notifyListeners();
    }
  }

  /// Tandai pesan sekali-lihat sudah dibuka (kirim ke server + lokal).
  void markViewOnce(String messageId) {
    _socket.emit('message:viewonce', {'messageId': messageId});
  }

  void _onViewOnce(String? convId, String messageId) {
    for (final m in messages) {
      if (m.id == messageId) m.viewOnceSeen = true;
    }
    if (convId != null) {
      for (final m in (_messageCache[convId] ?? <Message>[])) {
        if (m.id == messageId) m.viewOnceSeen = true;
      }
    }
    notifyListeners();
  }

  /// Buang pesan yang sudah kedaluwarsa dari tampilan & cache (disappearing).
  void purgeExpiredLocal() {
    var changed = messages.any((m) => m.isExpired);
    messages.removeWhere((m) => m.isExpired);
    for (final list in _messageCache.values) {
      if (list.any((m) => m.isExpired)) {
        list.removeWhere((m) => m.isExpired);
        changed = true;
      }
    }
    if (changed) notifyListeners();
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
    _socket.off('connect');
    _socket.off('disconnect');
    _socket.off('message:new');
    _socket.off('typing');
    _socket.off('message:read');
    _socket.off('message:delivered');
    notifyListeners();
  }
}
