import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import 'forward_screen.dart';
import 'profile_view_screen.dart';
import 'group_info_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/sticker_picker.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  late final ChatProvider _chatProv;
  bool _typingSent = false;
  bool _uploading = false;
  bool _hasText = false;
  int _initialUnread = 0;
  String? _lastBottomId;

  // Sticky date header.
  final _listKey = GlobalKey();
  final Map<String, GlobalKey> _dateChipKeys = {};
  final Map<String, String> _dateLabels = {};
  String? _stickyDate;

  // Back-to-bottom + pencarian dalam chat.
  bool _showJump = false;
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Message> _searchResults = []; // hasil cari ke backend (semua pesan)
  int _matchPos = -1;
  bool _searchLoading = false;
  Timer? _searchDebounce;
  final Map<String, GlobalKey> _msgKeys = {};

  String get _convId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _chatProv = context.read<ChatProvider>();
    // Tangkap jumlah unread SEBELUM ditandai terbaca (untuk penanda "pesan baru").
    _initialUnread = widget.conversation.unreadCount;
    // Pulihkan draft yang belum terkirim.
    final draft = _chatProv.getDraft(_convId);
    if (draft.isNotEmpty) {
      _input.text = draft;
      _hasText = true;
    }
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _chatProv.openConversation(_convId);
      _scrollToBottom();
      _updateSticky();
    });
  }

  @override
  void dispose() {
    // Simpan teks yang belum terkirim sebagai draft.
    _chatProv.setDraft(_convId, _input.text);
    _chatProv.closeConversation();
    _input.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _scroll.dispose();
    super.dispose();
  }

  // Mode reverse: bawah (terbaru) = offset 0, atas (terlama) = maxScrollExtent.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Muat pesan lama saat mendekati atas. Karena list reverse, menambah item
  /// di atas TIDAK menggeser tampilan → mulus tanpa kompensasi.
  void _onScrollCheck() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 &&
        _chatProv.hasMore &&
        !_chatProv.loadingMore) {
      _chatProv.loadMore(_convId);
    }
  }

  /// Scroll ke bawah hanya jika user sedang dekat bawah, atau dia pengirimnya.
  void _maybeAutoScroll(bool lastMine) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final nearBottom = pos.pixels < 250; // dekat offset 0 = dekat bawah
      if (lastMine || nearBottom) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onInputChanged(String v) {
    final chat = context.read<ChatProvider>();
    final typing = v.trim().isNotEmpty;
    if (typing != _typingSent) {
      _typingSent = typing;
      chat.setTyping(_convId, typing);
    }
  }

  void _sendText() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    context.read<ChatProvider>().sendText(_convId, text);
    _input.clear();
    _chatProv.setDraft(_convId, '');
    _typingSent = false;
    context.read<ChatProvider>().setTyping(_convId, false);
    _scrollToBottom();
  }

  Future<void> _sendImage() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _uploadAndSend(bytes, picked.name, 'IMAGE');
  }

  Future<void> _sendFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    await _uploadAndSend(f.bytes!, f.name, 'FILE');
  }

  Future<void> _uploadAndSend(
    List<int> bytes,
    String name,
    String type,
  ) async {
    setState(() => _uploading = true);
    try {
      final chat = context.read<ChatProvider>();
      final up = await chat.service.uploadFile(bytes, name);
      chat.sendMedia(_convId, type: type, mediaUrl: up.url, mediaName: up.name);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showAttachMenu() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _attachOption(
                icon: Icons.image_rounded,
                label: 'Galeri',
                color: scheme.primary,
                onTap: () {
                  Navigator.pop(context);
                  _sendImage();
                },
              ),
              _attachOption(
                icon: Icons.description_rounded,
                label: 'Dokumen',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(context);
                  _sendFile();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final myId = context.read<AuthProvider>().userId;
    final isGroup = widget.conversation.isGroup;
    final palette = AppPalette.of(context);

    // Auto-scroll HANYA saat pesan TERBAWAH (terbaru) berubah — yaitu ada
    // pesan baru masuk/terkirim. Memuat pesan lama (prepend di atas) TIDAK
    // mengubah pesan terbawah → tidak memicu scroll ke bawah.
    final newest = chat.messages.isNotEmpty ? chat.messages.last : null;
    if (newest != null && newest.id != _lastBottomId) {
      final hadPrevious = _lastBottomId != null;
      _lastBottomId = newest.id;
      if (hadPrevious) _maybeAutoScroll(newest.senderId == myId);
    }
    final typing = chat.typingUsers.isNotEmpty;

    // Pakai instance percakapan terbaru dari provider (status baca/sampai
    // diperbarui di sini secara live).
    final liveConv = chat.conversationById(_convId) ?? widget.conversation;

    // Nama-nama user yang sedang mengetik (untuk grup).
    final typingNames = chat.typingUsers.map((id) {
      final m = widget.conversation.members.where((u) => u.id == id);
      return m.isNotEmpty ? m.first.displayName : 'Seseorang';
    }).toList();

    // Posisi penanda "pesan baru": sebelum pesan ke-(_initialUnread) dari
    // bawah yang berasal dari orang lain.
    int? unreadStart;
    if (_initialUnread > 0 && chat.messages.isNotEmpty) {
      var count = 0;
      for (var i = chat.messages.length - 1; i >= 0; i--) {
        if (chat.messages[i].senderId != myId) {
          count++;
          if (count == _initialUnread) {
            unreadStart = i;
            break;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: palette.chatBackground,
      appBar: _searching
          ? _buildSearchAppBar(palette)
          : AppBar(
              titleSpacing: 0,
              title: InkWell(
                onTap: _openInfo,
                child: Row(
                  children: [
                    Avatar(
                      url: widget.conversation.avatarUrl,
                      name: widget.conversation.title,
                      radius: 19,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            widget.conversation.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (typing)
                            Text(
                              _appBarTypingText(typingNames, isGroup),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (isGroup)
                            Text(
                              '${widget.conversation.members.length} anggota',
                              style:
                                  TextStyle(fontSize: 12, color: palette.muted),
                            )
                          else if (chat.presenceText(liveConv) != null)
                            Text(
                              chat.presenceText(liveConv)!,
                              style: TextStyle(
                                fontSize: 12,
                                color: chat.presenceText(liveConv) == 'online'
                                    ? Theme.of(context).colorScheme.primary
                                    : palette.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => setState(() => _searching = true),
                ),
              ],
            ),
      body: Column(
        children: [
          if (!chat.connected) _connectionBanner(),
          Expanded(
            child: chat.loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : chat.messages.isEmpty
                    ? Center(
                        child: Text(
                          'Mulai percakapan 👋',
                          style: TextStyle(color: palette.muted, fontSize: 15),
                        ),
                      )
                    : Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              _updateSticky();
                              _onScrollCheck();
                              final show = _scroll.hasClients &&
                                  _scroll.position.pixels > 600;
                              if (show != _showJump) {
                                setState(() => _showJump = show);
                              }
                              return false;
                            },
                            child: ListView.builder(
                              key: _listKey,
                              controller: _scroll,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              itemCount:
                                  chat.messages.length + (typing ? 1 : 0),
                              itemBuilder: (_, i) {
                                // reverse: index 0 = paling bawah (terbaru).
                                if (typing && i == 0) {
                                  return TypingIndicator(
                                    name: isGroup
                                        ? _bubbleTypingName(typingNames)
                                        : null,
                                  );
                                }
                                final di = chat.messages.length -
                                    1 -
                                    (typing ? i - 1 : i);
                                final m = chat.messages[di];
                                final mine = m.senderId == myId;
                                final msgKey = _msgKeys.putIfAbsent(
                                    m.id, () => GlobalKey());
                                Widget item = KeyedSubtree(
                                  key: msgKey,
                                  child: GestureDetector(
                                    onLongPress: () =>
                                        _showMessageMenu(m, mine),
                                    child: MessageBubble(
                                      message: m,
                                      isMine: mine,
                                      showSender: isGroup,
                                      status: mine
                                          ? chat.statusOf(m, liveConv)
                                          : null,
                                      highlight:
                                          _searching ? _searchQuery : null,
                                    ),
                                  ),
                                );
                                if (mine && !m.deleted) {
                                  item = Dismissible(
                                    key: ValueKey(m.id),
                                    direction: DismissDirection.endToStart,
                                    background: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 28),
                                      child: const Icon(Icons.delete_rounded,
                                          color: Color(0xFFEF4444)),
                                    ),
                                    confirmDismiss: (_) async {
                                      await _confirmDeleteMessage(m);
                                      return false;
                                    },
                                    child: item,
                                  );
                                }
                                // Chip tanggal di atas pesan pertama tiap hari.
                                final showDate = di == 0 ||
                                    !_sameDay(
                                      chat.messages[di - 1].createdAt,
                                      m.createdAt,
                                    );
                                if (!showDate && di != unreadStart) return item;
                                GlobalKey? dateKey;
                                if (showDate) {
                                  final dt = m.createdAt;
                                  final dayKey =
                                      '${dt.year}-${dt.month}-${dt.day}';
                                  dateKey = _dateChipKeys.putIfAbsent(
                                      dayKey, () => GlobalKey());
                                  _dateLabels[dayKey] = _dateLabel(dt);
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showDate)
                                      _dateChip(_dateLabel(m.createdAt),
                                          palette,
                                          key: dateKey),
                                    if (di == unreadStart)
                                      _unreadDivider(palette),
                                    item,
                                  ],
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                child: chat.loadingMore
                                    ? Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: palette.cardBorder),
                                        ),
                                        child: const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : (_stickyDate != null
                                        ? _dateChip(_stickyDate!, palette)
                                        : const SizedBox.shrink()),
                              ),
                            ),
                          ),
                          if (_showJump)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: Material(
                                color: Theme.of(context).colorScheme.surface,
                                elevation: 2,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
                                    _scrollToBottom();
                                    setState(() => _showJump = false);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(9),
                                    child: Icon(
                                      Icons.keyboard_double_arrow_down_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
          if (_uploading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Mengunggah…', style: TextStyle(color: palette.muted)),
                ],
              ),
            ),
          if (chat.replyingTo != null) _replyBar(chat.replyingTo!, palette),
          _buildInputBar(palette),
        ],
      ),
    );
  }

  /// Teks indikator typing di app bar.
  /// Direct: "mengetik…". Grup: sertakan nama yang mengetik.
  String _appBarTypingText(List<String> names, bool isGroup) {
    if (!isGroup) return 'mengetik…';
    if (names.isEmpty) return 'mengetik…';
    if (names.length == 1) return '${names[0]} sedang mengetik…';
    if (names.length == 2) {
      return '${names[0]} & ${names[1]} sedang mengetik…';
    }
    return '${names[0]}, ${names[1]} +${names.length - 2} sedang mengetik…';
  }

  /// Nama yang ditampilkan di atas gelembung titik-titik (grup).
  String _bubbleTypingName(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length <= 2) return names.join(', ');
    return '${names[0]}, ${names[1]} +${names.length - 2}';
  }

  static const _days = [
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
  ];
  static const _months = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Tentukan tanggal yang "menempel" di atas berdasar chip terdekat di atas.
  void _updateSticky() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final listBox =
          _listKey.currentContext?.findRenderObject() as RenderBox?;
      if (listBox == null) return;
      final topY = listBox.localToGlobal(Offset.zero).dy;
      final msgs = _chatProv.messages;

      // 1) Tanggal dari PESAN teratas yang terlihat (key per-pesan selalu ada
      //    untuk item yang ter-render → akurat, tak bergantung chip).
      DateTime? topDate;
      var bestDy = -1e9;
      var minDy = 1e9;
      DateTime? topmost;
      for (final m in msgs) {
        final ctx = _msgKeys[m.id]?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null) continue;
        final dy = box.localToGlobal(Offset.zero).dy;
        if (dy <= topY + 8 && dy > bestDy) {
          bestDy = dy;
          topDate = m.createdAt;
        }
        if (dy < minDy) {
          minDy = dy;
          topmost = m.createdAt;
        }
      }
      topDate ??= topmost; // kalau di paling atas (semua pesan di bawah garis)

      // 2) Sembunyikan floating bila chip inline hari itu sedang terlihat di
      //    dekat atas (anti-dobel).
      var inlineAtTop = false;
      if (topDate != null) {
        final dayKey =
            '${topDate.year}-${topDate.month}-${topDate.day}';
        final ck = _dateChipKeys[dayKey]?.currentContext;
        if (ck != null) {
          final cbox = ck.findRenderObject() as RenderBox?;
          if (cbox != null) {
            final cdy = cbox.localToGlobal(Offset.zero).dy;
            if (cdy >= topY - 4 && cdy <= topY + 64) inlineAtTop = true;
          }
        }
      }

      final next =
          (topDate == null || inlineAtTop) ? null : _dateLabel(topDate);
      if (next != _stickyDate && mounted) {
        setState(() => _stickyDate = next);
      }
    });
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    if (diff > 1 && diff < 7) return _days[dt.weekday - 1];
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  Widget _dateChip(String label, AppPalette palette, {Key? key}) {
    return Center(
      child: Container(
        key: key,
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: palette.muted,
          ),
        ),
      ),
    );
  }

  String _snippet(Message m) {
    if (m.deleted) return 'Pesan dihapus';
    switch (m.type) {
      case 'IMAGE':
        return '📷 Foto';
      case 'FILE':
        return '📎 ${m.mediaName ?? 'File'}';
      case 'STICKER':
        return '${m.content ?? '🙂'} Stiker';
      default:
        return m.content ?? '';
    }
  }

  void _showMessageMenu(Message m, bool mine) {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (!m.deleted)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Balas'),
                onTap: () {
                  Navigator.pop(context);
                  context.read<ChatProvider>().setReplyingTo(m);
                },
              ),
            if (!m.deleted)
              ListTile(
                leading: const Icon(Icons.shortcut_rounded),
                title: const Text('Teruskan'),
                onTap: () {
                  Navigator.pop(context);
                  _forward(m);
                },
              ),
            if (!m.deleted && m.type == 'TEXT' && m.content != null)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Salin'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: m.content!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Disalin')),
                  );
                },
              ),
            if (mine && !m.deleted)
              ListTile(
                leading: Icon(Icons.delete_rounded, color: scheme.error),
                title: Text('Hapus', style: TextStyle(color: scheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteMessage(m);
                },
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDeleteMessage(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus pesan?'),
        content: const Text('Pesan akan dihapus untuk semua orang.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<ChatProvider>().deleteMessage(m.id);
    }
  }

  Future<void> _forward(Message m) async {
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const ForwardScreen()),
    );
    if (ids != null && ids.isNotEmpty && mounted) {
      context.read<ChatProvider>().forwardTo(ids, m);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Diteruskan ke ${ids.length} chat')),
      );
    }
  }

  Widget _replyBar(Message m, AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: scheme.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Membalas ${m.senderName ?? ''}'.trim(),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: scheme.primary,
                        ),
                      ),
                      Text(
                        _snippet(m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () =>
                    context.read<ChatProvider>().setReplyingTo(null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openInfo() {
    final conv = _chatProv.conversationById(_convId) ?? widget.conversation;
    if (conv.isGroup) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GroupInfoScreen(conversation: conv)),
      );
    } else {
      final peer = conv.peer ?? widget.conversation.peer;
      if (peer != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileViewScreen(user: peer, canMessage: false),
          ),
        );
      }
    }
  }

  PreferredSizeWidget _buildSearchAppBar(AppPalette palette) {
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => setState(() {
          _searching = false;
          _searchCtrl.clear();
          _searchQuery = '';
          _searchResults = [];
          _matchPos = -1;
        }),
      ),
      title: TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: _onSearchChanged,
        decoration: const InputDecoration(
          hintText: 'Cari di chat ini…',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
      actions: [
        if (_searchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_searchQuery.trim().isNotEmpty)
          Center(
            child: Text(
              _searchResults.isEmpty
                  ? '0'
                  : '${_matchPos + 1}/${_searchResults.length}',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: _searchResults.isEmpty ? null : () => _gotoMatch(-1),
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: _searchResults.isEmpty ? null : () => _gotoMatch(1),
        ),
      ],
    );
  }

  void _onSearchChanged(String q) {
    setState(() => _searchQuery = q);
    _searchDebounce?.cancel();
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _matchPos = -1;
      });
      return;
    }
    setState(() => _searchLoading = true);
    try {
      // Cari ke backend → SEMUA pesan cocok (bukan hanya yang ter-load).
      final res = await _chatProv.service.searchMessages(_convId, query);
      if (!mounted) return;
      setState(() {
        _searchResults = res;
        _matchPos = res.isNotEmpty ? res.length - 1 : -1; // mulai dari terbaru
      });
      if (_matchPos >= 0) await _scrollToMatchMessage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _gotoMatch(int delta) async {
    if (_searchResults.isEmpty) return;
    setState(() =>
        _matchPos = (_matchPos + delta).clamp(0, _searchResults.length - 1));
    await _scrollToMatchMessage();
  }

  Future<void> _scrollToMatchMessage() async {
    if (_matchPos < 0 || _matchPos >= _searchResults.length) return;
    final targetId = _searchResults[_matchPos].id;

    // Muat pesan lama dulu sampai pesan target ter-load (lewati pagination).
    var guard = 0;
    while (!_chatProv.messages.any((m) => m.id == targetId) &&
        _chatProv.hasMore &&
        guard < 30) {
      await _chatProv.loadMore(_convId);
      guard++;
    }
    if (!mounted) return;

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      final ctx = _msgKeys[targetId]?.currentContext;
      if (ctx != null) {
        // ignore: use_build_context_synchronously
        await Scrollable.ensureVisible(ctx,
            alignment: 0.4, duration: const Duration(milliseconds: 300));
        return;
      }
      // Belum ter-render walau sudah ter-load: lompat proporsional dulu.
      final msgs = _chatProv.messages;
      final di = msgs.indexWhere((m) => m.id == targetId);
      if (di < 0 || !_scroll.hasClients) return;
      final total = msgs.length;
      final listIndex = total - 1 - di;
      final frac = total <= 1 ? 0.0 : listIndex / (total - 1);
      _scroll.jumpTo(frac * _scroll.position.maxScrollExtent);
      await Future<void>.delayed(const Duration(milliseconds: 90));
      if (!mounted) return;
      final c2 = _msgKeys[targetId]?.currentContext;
      if (c2 != null) {
        // ignore: use_build_context_synchronously
        await Scrollable.ensureVisible(c2,
            alignment: 0.4, duration: const Duration(milliseconds: 200));
      }
    });
  }

  Widget _connectionBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF4B5563),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Menghubungkan…',
            style: TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _unreadDivider(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    final label = _initialUnread == 1
        ? '1 pesan baru'
        : '$_initialUnread pesan baru';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.primary.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  void _sendSticker(String sticker) {
    context.read<ChatProvider>().sendSticker(_convId, sticker);
    _scrollToBottom();
  }

  void _showStickers() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StickerPicker(onSelected: _sendSticker),
    );
  }

  Widget _buildInputBar(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: palette.cardBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.add_rounded),
                      color: palette.muted,
                      onPressed: _uploading ? null : _showAttachMenu,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onChanged: _onInputChanged,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Pesan',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      color: palette.muted,
                      onPressed: _showStickers,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _hasText ? _sendText : null,
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: _hasText
                      ? scheme.primary
                      : scheme.primary.withValues(alpha: 0.4),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.send_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
