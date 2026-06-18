import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import 'package:app_links/app_links.dart';
import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/call_provider.dart';
import '../providers/status_provider.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../services/web_notify.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/status_tick.dart';
import 'chat_screen.dart';
import 'archived_screen.dart';
import 'starred_screen.dart';
import 'status_screen.dart';
import 'status_view_screen.dart';
import 'call_history_screen.dart';
import 'contacts_screen.dart';
import 'new_chat_screen.dart';
import 'profile_edit_screen.dart';
import 'settings_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  int _tab = 0;
  bool _searching = false;
  String _filter = 'all'; // all | unread | favorite | group
  final Set<String> _selected = {}; // mode pilih banyak chat
  Conversation? _selectedConv; // chat aktif di panel kanan (layar lebar)
  final _searchCtrl = TextEditingController();
  String _query = '';
  final _appLinks = AppLinks();
  StreamSubscription<Uri>? _linkSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final auth = context.read<AuthProvider>();
      final chat = context.read<ChatProvider>();
      if (auth.userId != null) {
        chat.init(auth.userId!);
        context.read<CallProvider>().init(auth.userId!);
        context.read<StatusProvider>().init(auth.userId!);
      }
      chat.loadConversations();
      // Buka chat jika app dibuka dari tap notifikasi (saat app sebelumnya mati).
      NotificationService.instance.consumePending();
      // Web: minta izin notifikasi browser.
      WebNotify.requestPermission();
      _initDeepLinks();
    });
  }

  // Tangani deep link kontak (App Links https / skema wachat://contact).
  Future<void> _initDeepLinks() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handleLink(initial);
    } catch (_) {}
    _linkSub = _appLinks.uriLinkStream.listen(_handleLink, onError: (_) {});
  }

  Future<void> _handleLink(Uri uri) async {
    final token = uri.queryParameters['token'];
    if (token == null || token.isEmpty || !mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final chat = context.read<ChatProvider>();
    final isGroupInvite =
        uri.host == 'group' || uri.pathSegments.contains('join');
    try {
      if (isGroupInvite) {
        final conv = await chat.service.joinGroup(token);
        await chat.loadConversations();
        if (!mounted) return;
        messenger.showSnackBar(
            SnackBar(content: Text('Bergabung ke "${conv.title}"')));
        _openChat(conv);
      } else {
        final user = await chat.service.scanContact(token);
        messenger.showSnackBar(SnackBar(
            content: Text('${user.displayName} ditambahkan ke kontak')));
      }
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    _linkSub?.cancel();
    super.dispose();
  }

  String _preview(Conversation c) {
    final m = c.lastMessage;
    if (m == null) return 'Belum ada pesan';
    switch (m.type) {
      case 'IMAGE':
        return '📷 Foto';
      case 'FILE':
        return '📎 ${m.mediaName ?? 'File'}';
      case 'VOICE':
        return '🎤 Pesan suara';
      case 'CALL':
        return (m.content ?? '').split('|').elementAtOrNull(2) == '1'
            ? 'Panggilan video'
            : 'Panggilan suara';
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

  String _typingPreview(Conversation c, Set<String> ids) {
    if (!c.isGroup) return 'mengetik…';
    final names = ids.map((id) {
      final m = c.members.where((u) => u.id == id);
      return m.isNotEmpty ? m.first.displayName : 'Seseorang';
    }).toList();
    if (names.length == 1) return '${names[0]} mengetik…';
    return '${names.length} orang mengetik…';
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();
    final unread = context.watch<ChatProvider>().totalUnread;
    WebNotify.setUnread(unread); // badge favicon + judul tab (web)
    // Layar lebar (web/desktop) → dua panel ala WhatsApp Web.
    final wide = MediaQuery.of(context).size.width >= 900;
    final palette = AppPalette.of(context);

    final tabContent = IndexedStack(
      index: _tab,
      children: [
        _buildChatsTab(context),
        const StatusScreen(),
        const CallHistoryScreen(),
        ContactsScreen(onOpen: _openChat),
      ],
    );

    // Layar sempit (HP) → bottom navigation seperti biasa.
    if (!wide) {
      return Scaffold(
        body: tabContent,
        bottomNavigationBar: NavigationBar(
          selectedIndex: _tab,
          onDestinationSelected: _selectTab,
          destinations: [
            NavigationDestination(
              icon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_outline_rounded),
              ),
              selectedIcon: Badge(
                isLabelVisible: unread > 0,
                label: Text('$unread'),
                child: const Icon(Icons.chat_bubble_rounded),
              ),
              label: 'Chat',
            ),
            const NavigationDestination(
              icon: Icon(Icons.donut_large_outlined),
              selectedIcon: Icon(Icons.donut_large_rounded),
              label: 'Status',
            ),
            NavigationDestination(
              icon: Badge(
                isLabelVisible: call.missedCount > 0,
                label: Text('${call.missedCount}'),
                child: const Icon(Icons.call_outlined),
              ),
              selectedIcon: const Icon(Icons.call_rounded),
              label: 'Panggilan',
            ),
            const NavigationDestination(
              icon: Icon(Icons.people_outline_rounded),
              selectedIcon: Icon(Icons.people_rounded),
              label: 'Kontak',
            ),
          ],
        ),
      );
    }

    // Layar lebar (web/desktop) → rail kiri (ala WhatsApp Web) + daftar + room.
    return Scaffold(
      body: Row(
        children: [
          _navRail(context, unread, call.missedCount),
          VerticalDivider(width: 1, color: palette.cardBorder),
          SizedBox(width: 400, child: tabContent),
          VerticalDivider(width: 1, color: palette.cardBorder),
          Expanded(
            child: _selectedConv == null
                ? _chatPlaceholder(palette)
                : ChatScreen(
                    key: ValueKey(_selectedConv!.id),
                    conversation: _selectedConv!,
                  ),
          ),
        ],
      ),
    );
  }

  void _selectTab(int i) {
    setState(() => _tab = i);
    if (i == 2) {
      final c = context.read<CallProvider>();
      c.loadCalls();
      c.markCallsSeen();
    }
  }

  /// Rail navigasi vertikal kiri (web/desktop). Ikon menu di atas, avatar bawah.
  Widget _navRail(BuildContext context, int unread, int missed) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);
    final auth = context.watch<AuthProvider>();

    Widget item(int i, IconData icon, IconData selected, String tip,
        {int badge = 0}) {
      final active = _tab == i;
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: IconButton(
          tooltip: tip,
          onPressed: () => _selectTab(i),
          icon: Badge(
            isLabelVisible: badge > 0,
            label: Text('$badge'),
            child: Icon(active ? selected : icon),
          ),
          style: IconButton.styleFrom(
            backgroundColor:
                active ? scheme.primary.withValues(alpha: 0.14) : null,
            foregroundColor: active ? scheme.primary : palette.muted,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Container(
      width: 66,
      color: palette.cardBorder.withValues(alpha: 0.12),
      child: Column(
        children: [
          const SizedBox(height: 12),
          item(0, Icons.chat_bubble_outline_rounded, Icons.chat_bubble_rounded,
              'Chat', badge: unread),
          item(1, Icons.donut_large_outlined, Icons.donut_large_rounded,
              'Status'),
          item(2, Icons.call_outlined, Icons.call_rounded, 'Panggilan',
              badge: missed),
          item(3, Icons.people_outline_rounded, Icons.people_rounded,
              'Kontak'),
          const Spacer(),
          IconButton(
            tooltip: 'Setelan',
            icon: const Icon(Icons.settings_outlined),
            color: palette.muted,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SettingsScreen()),
            ),
          ),
          const SizedBox(height: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
            ),
            child: Avatar(
              url: auth.user?.avatarUrl,
              name: auth.user?.displayName ?? '?',
              radius: 18,
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _chatPlaceholder(AppPalette palette) {
    return Container(
      color: palette.chatBackground,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline_rounded, size: 72, color: palette.muted),
          const SizedBox(height: 16),
          Text('Pilih chat untuk mulai mengobrol',
              style: TextStyle(color: palette.muted, fontSize: 15)),
        ],
      ),
    );
  }

  Widget _buildChatsTab(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final status = context.watch<StatusProvider>();
    final auth = context.read<AuthProvider>();
    final myId = auth.userId;
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);

    final base = _query.isEmpty
        ? chat.conversations
        : chat.conversations
            .where((c) => c.title.toLowerCase().contains(_query.toLowerCase()))
            .toList();
    final visible = base.where((c) {
      if (chat.isArchived(c.id)) return false; // arsip disembunyikan dari daftar
      switch (_filter) {
        case 'unread':
          return c.unreadCount > 0;
        case 'favorite':
          return chat.isFavorite(c.id);
        case 'group':
          return c.isGroup;
        default:
          return true;
      }
    }).toList();
    // Chat tersemat (pin) tampil di atas, sisanya tetap urut waktu.
    final filtered = [
      ...visible.where((c) => chat.isPinned(c.id)),
      ...visible.where((c) => !chat.isPinned(c.id)),
    ];

    return PopScope(
      canPop: _selected.isEmpty,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _selected.isNotEmpty) _clearSelection();
      },
      child: Scaffold(
      appBar: _selected.isNotEmpty
          ? _selectionBar(scheme)
          : AppBar(
        titleSpacing: _searching ? 8 : 20,
        toolbarHeight: 64,
        leading: _searching
            ? IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                onPressed: () => setState(() {
                  _searching = false;
                  _query = '';
                  _searchCtrl.clear();
                }),
              )
            : null,
        title: _searching
            ? TextField(
                controller: _searchCtrl,
                autofocus: true,
                onChanged: (v) => setState(() => _query = v),
                decoration: const InputDecoration(
                  hintText: 'Cari chat…',
                  filled: false,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                ),
                style: const TextStyle(fontSize: 18),
              )
            : const Text(
                'Chats',
                style: TextStyle(fontWeight: FontWeight.w800, fontSize: 26),
              ),
        actions: [
          if (!_searching)
            IconButton(
              icon: const Icon(Icons.search_rounded),
              onPressed: () => setState(() => _searching = true),
            ),
          Padding(
            padding: const EdgeInsets.only(right: 12, left: 4),
            child: PopupMenuButton<String>(
              offset: const Offset(0, 48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              onSelected: (v) async {
                if (v == 'profile') {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const ProfileEditScreen(),
                    ),
                  );
                } else if (v == 'starred') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const StarredScreen()),
                  );
                } else if (v == 'settings') {
                  Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const SettingsScreen()),
                  );
                } else if (v == 'logout') {
                  context.read<ChatProvider>().reset();
                  await auth.logout();
                }
              },
              itemBuilder: (_) => [
                PopupMenuItem(
                  enabled: false,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        auth.user?.displayName ?? '',
                        style: const TextStyle(fontWeight: FontWeight.w700),
                      ),
                      Text(
                        auth.user?.phone ?? '',
                        style: TextStyle(color: palette.muted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
                const PopupMenuDivider(),
                const PopupMenuItem(
                  value: 'profile',
                  child: Row(
                    children: [
                      Icon(Icons.person_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Profil saya'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'starred',
                  child: Row(
                    children: [
                      Icon(Icons.star_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Pesan berbintang'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'settings',
                  child: Row(
                    children: [
                      Icon(Icons.settings_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Setelan'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'logout',
                  child: Row(
                    children: [
                      Icon(Icons.logout_rounded, size: 20),
                      SizedBox(width: 10),
                      Text('Keluar'),
                    ],
                  ),
                ),
              ],
              icon: const Icon(Icons.more_vert_rounded),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          final chatProv = context.read<ChatProvider>();
          final created = await Navigator.of(context).push<Conversation>(
            MaterialPageRoute(builder: (_) => const NewChatScreen()),
          );
          if (created != null) {
            await chatProv.loadConversations();
            if (mounted) _openChat(created);
          }
        },
        child: const Icon(Icons.add_comment_rounded),
      ),
      body: Column(
        children: [
          if (!_searching) _filterChips(palette),
          if (!_searching && _filter == 'all' && chat.archivedCount > 0)
            ListTile(
              leading: Icon(Icons.archive_rounded, color: palette.muted),
              title: const Text('Diarsipkan',
                  style: TextStyle(fontWeight: FontWeight.w600)),
              trailing: Text('${chat.archivedCount}',
                  style: TextStyle(color: palette.muted)),
              onTap: _openArchived,
            ),
          Expanded(
            child: RefreshIndicator(
        onRefresh: () => chat.loadConversations(),
        child: chat.loadingConversations && chat.conversations.isEmpty
            ? const Center(child: CircularProgressIndicator())
            : filtered.isEmpty
                ? (_query.isNotEmpty
                    ? Center(
                        child: Text('Tidak ada hasil untuk "$_query"',
                            style: TextStyle(color: palette.muted)),
                      )
                    : _filter != 'all'
                        ? Center(
                            child: Text('Tidak ada chat di filter ini',
                                style: TextStyle(color: palette.muted)),
                          )
                        : _emptyState(palette))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    itemCount: filtered.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 84),
                      child: Divider(height: 1, color: palette.cardBorder),
                    ),
                    itemBuilder: (_, i) {
                      final c = filtered[i];
                      final hasUnread = c.unreadCount > 0;
                      final typingSet = chat.typingFor(c.id);
                      final isTyping = typingSet.isNotEmpty;
                      final lastMine = c.lastMessage != null &&
                          c.lastMessage!.senderId == myId;
                      final showTick = lastMine && !isTyping;
                      final inSelection = _selected.contains(c.id);
                      final active = _selectedConv?.id == c.id &&
                          MediaQuery.of(context).size.width >= 900;
                      final selected = inSelection;
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        selected: selected || active,
                        selectedTileColor:
                            scheme.primary.withValues(alpha: 0.08),
                        leading: selected
                            ? CircleAvatar(
                                radius: 27,
                                backgroundColor: scheme.primary,
                                child: const Icon(Icons.check_rounded,
                                    color: Colors.white),
                              )
                            : _chatLeading(c, status, myId, scheme, palette),
                        title: Text(
                          c.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 15.5,
                          ),
                        ),
                        subtitle: Padding(
                          padding: const EdgeInsets.only(top: 3),
                          child: Row(
                            children: [
                              if (showTick) ...[
                                statusTick(
                                  chat.statusOf(c.lastMessage!, c),
                                  normal: palette.muted,
                                  read: scheme.primary,
                                  size: 16,
                                ),
                                const SizedBox(width: 4),
                              ],
                              // Ikon tipe panggilan (seragam dengan room/tab).
                              if (!isTyping && c.lastMessage?.type == 'CALL') ...[
                                Icon(
                                  (c.lastMessage!.content ?? '')
                                              .split('|')
                                              .elementAtOrNull(2) ==
                                          '1'
                                      ? Icons.videocam_rounded
                                      : Icons.call_rounded,
                                  size: 14,
                                  color: palette.muted,
                                ),
                                const SizedBox(width: 4),
                              ],
                              Expanded(
                                child: Text(
                                  isTyping
                                      ? _typingPreview(c, typingSet)
                                      : _preview(c),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    color: isTyping
                                        ? scheme.primary
                                        : hasUnread
                                            ? Theme.of(context)
                                                .colorScheme
                                                .onSurface
                                            : palette.muted,
                                    fontWeight: (isTyping || hasUnread)
                                        ? FontWeight.w600
                                        : FontWeight.w400,
                                    fontSize: 13.5,
                                    fontStyle: isTyping
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                                ),
                              ),
                              if (c.muted)
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.notifications_off_rounded,
                                      size: 15, color: palette.muted),
                                ),
                              if (chat.isPinned(c.id))
                                Padding(
                                  padding: const EdgeInsets.only(left: 6),
                                  child: Icon(Icons.push_pin_rounded,
                                      size: 14, color: palette.muted),
                                ),
                            ],
                          ),
                        ),
                        trailing: Column(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              DateFormat('HH:mm').format(c.updatedAt),
                              style: TextStyle(
                                fontSize: 11.5,
                                color: hasUnread ? scheme.primary : palette.muted,
                                fontWeight:
                                    hasUnread ? FontWeight.w700 : FontWeight.w400,
                              ),
                            ),
                            const SizedBox(height: 6),
                            if (hasUnread)
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: scheme.primary,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  '${c.unreadCount}',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              )
                            else
                              const SizedBox(height: 20),
                          ],
                        ),
                        onTap: () => _selected.isNotEmpty
                            ? _toggleSelect(c.id)
                            : _openChat(c),
                        onLongPress: () => _toggleSelect(c.id),
                      );
                    },
                  ),
            ),
          ),
        ],
      ),
      ),
    );
  }

  Widget _filterChips(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    const filters = [
      ('all', 'Semua'),
      ('unread', 'Belum dibaca'),
      ('favorite', 'Favorit'),
      ('group', 'Grup'),
    ];
    return SizedBox(
      height: 48,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
        children: [
          for (final f in filters)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(f.$2),
                selected: _filter == f.$1,
                showCheckmark: false,
                onSelected: (_) => setState(() => _filter = f.$1),
                labelStyle: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: _filter == f.$1 ? scheme.primary : palette.muted,
                ),
                selectedColor: scheme.primary.withValues(alpha: 0.15),
                backgroundColor: Theme.of(context).colorScheme.surface,
                side: BorderSide(
                  color: _filter == f.$1 ? scheme.primary : palette.cardBorder,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(20),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ===== Mode pilih banyak chat (ala WhatsApp) =====
  void _toggleSelect(String id) {
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  void _clearSelection() => setState(_selected.clear);

  PreferredSizeWidget _selectionBar(ColorScheme scheme) {
    final chat = context.read<ChatProvider>();
    final allFav = _selected.every(chat.isFavorite);
    final allMuted = _selected.every(chat.isMuted);
    final allPinned = _selected.every(chat.isPinned);
    final single = _selected.length == 1;
    final one = single ? chat.conversationById(_selected.first) : null;
    final canBlock = one != null && !one.isGroup && one.peer != null;
    return AppBar(
      leading: IconButton(
        icon: const Icon(Icons.close_rounded),
        onPressed: _clearSelection,
      ),
      title: Text('${_selected.length}'),
      actions: [
        IconButton(
          tooltip: 'Tandai dibaca',
          icon: const Icon(Icons.mark_chat_read_outlined),
          onPressed: _markReadSelected,
        ),
        IconButton(
          tooltip: allFav ? 'Hapus dari favorit' : 'Tambah ke favorit',
          icon: Icon(allFav ? Icons.star_rounded : Icons.star_outline_rounded),
          onPressed: () => _favoriteSelected(!allFav),
        ),
        IconButton(
          tooltip: allPinned ? 'Lepas pin' : 'Sematkan',
          icon: Icon(
              allPinned ? Icons.push_pin_rounded : Icons.push_pin_outlined),
          onPressed: () {
            for (final id in _selected) {
              chat.setPinned(id, !allPinned);
            }
            _clearSelection();
          },
        ),
        IconButton(
          tooltip: allMuted ? 'Bunyikan' : 'Bisukan',
          icon: Icon(allMuted
              ? Icons.notifications_off_rounded
              : Icons.notifications_active_outlined),
          onPressed: () => _muteSelected(!allMuted),
        ),
        IconButton(
          tooltip: 'Arsipkan',
          icon: const Icon(Icons.archive_outlined),
          onPressed: _archiveSelected,
        ),
        IconButton(
          tooltip: 'Hapus',
          icon: const Icon(Icons.delete_outline_rounded),
          onPressed: _deleteSelected,
        ),
        if (canBlock)
          PopupMenuButton<String>(
            onSelected: (v) {
              if (v == 'block') _blockSelected(one);
            },
            itemBuilder: (_) => [
              const PopupMenuItem(
                value: 'block',
                child: Row(children: [
                  Icon(Icons.block_rounded, size: 20),
                  SizedBox(width: 10),
                  Text('Blokir'),
                ]),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _muteSelected(bool value) async {
    final chat = context.read<ChatProvider>();
    for (final id in _selected) {
      chat.setMuted(id, value);
    }
    _clearSelection();
  }

  Future<void> _archiveSelected() async {
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ids = _selected.toList();
    for (final id in ids) {
      chat.setArchived(id, true);
    }
    _clearSelection();
    messenger.showSnackBar(SnackBar(
      content: Text('${ids.length} chat diarsipkan'),
      action: SnackBarAction(
        label: 'Urungkan',
        onPressed: () {
          for (final id in ids) {
            chat.setArchived(id, false);
          }
        },
      ),
    ));
  }

  Future<void> _markReadSelected() async {
    final chat = context.read<ChatProvider>();
    for (final id in _selected) {
      chat.markConvRead(id);
    }
    _clearSelection();
  }

  Future<void> _favoriteSelected(bool value) async {
    final chat = context.read<ChatProvider>();
    for (final id in _selected) {
      chat.setFavorite(id, value);
    }
    _clearSelection();
  }

  Future<void> _deleteSelected() async {
    final chat = context.read<ChatProvider>();
    final ids = _selected.toList();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Hapus ${ids.length} chat?'),
        content: const Text('Percakapan terpilih akan dihapus dari daftar.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok != true) return;
    _clearSelection();
    for (final id in ids) {
      try {
        await chat.deleteConversation(id);
      } catch (_) {}
    }
  }

  Future<void> _blockSelected(Conversation c) async {
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final peer = c.peer;
    if (peer == null) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Blokir ${peer.displayName}?'),
        content: const Text(
            'Anda tidak akan menerima pesan dari kontak ini lagi.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Blokir')),
        ],
      ),
    );
    if (ok != true) return;
    _clearSelection();
    try {
      await chat.service.blockUser(peer.id);
      messenger.showSnackBar(
          SnackBar(content: Text('${peer.displayName} diblokir')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  Widget _emptyState(AppPalette palette) {
    return ListView(
      children: [
        const SizedBox(height: 140),
        Icon(Icons.forum_outlined, size: 72, color: palette.muted),
        const SizedBox(height: 16),
        Center(
          child: Text(
            'Belum ada percakapan',
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Center(
          child: Text(
            'Ketuk tombol tulis untuk memulai chat',
            style: TextStyle(color: palette.muted),
          ),
        ),
      ],
    );
  }

  /// Avatar di daftar chat + cincin status tersegmentasi (1 busur/status,
  /// hijau=belum dilihat, abu=sudah). Ketuk avatar bercincin → buka statusnya.
  Widget _chatLeading(Conversation c, StatusProvider status, String? myId,
      ColorScheme scheme, AppPalette palette) {
    final peer = c.peer;
    List<bool>? segs;
    if (!c.isGroup && peer != null && myId != null) {
      segs = status.seenSegments(peer.id, myId);
    }
    final avatar = Avatar(
        url: c.avatarUrl, name: c.avatarName, radius: 27, ringSegments: segs);
    if (segs != null && peer != null) {
      return GestureDetector(
          onTap: () => _openPeerStatus(peer.id), child: avatar);
    }
    return avatar;
  }

  void _openPeerStatus(String userId) {
    final entry = context.read<StatusProvider>().entryFor(userId);
    if (entry == null) return;
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => StatusViewScreen(
            stories: [StatusStory(user: entry.user, statuses: entry.statuses)],
          ),
        ))
        .then((_) {
      if (mounted) context.read<StatusProvider>().loadFeed();
    });
  }

  void _openArchived() {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const ArchivedScreen()),
    );
  }

  void _openChat(Conversation c) {
    if (MediaQuery.of(context).size.width >= 900) {
      // Layar lebar: tampilkan di panel kanan, bukan halaman baru.
      setState(() => _selectedConv = c);
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
      );
    }
  }

}
