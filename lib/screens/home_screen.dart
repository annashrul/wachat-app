import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/call_provider.dart';
import '../providers/status_provider.dart';
import '../services/api_client.dart';
import '../services/notification_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/status_tick.dart';
import 'chat_screen.dart';
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
  final _searchCtrl = TextEditingController();
  String _query = '';

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
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
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
        return '📞 Panggilan suara';
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
    return Scaffold(
      body: IndexedStack(
        index: _tab,
        children: [
          _buildChatsTab(context),
          const StatusScreen(),
          const CallHistoryScreen(),
          const ContactsScreen(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _tab,
        onDestinationSelected: (i) {
          setState(() => _tab = i);
          if (i == 2) {
            final c = context.read<CallProvider>();
            c.loadCalls();
            c.markCallsSeen();
          }
        },
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
    final filtered = base.where((c) {
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

    return Scaffold(
      appBar: AppBar(
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
              child: Avatar(
                url: auth.user?.avatarUrl,
                name: auth.user?.displayName ?? '?',
                radius: 19,
              ),
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
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 6,
                        ),
                        leading: _chatLeading(c, status, scheme, palette),
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
                        onTap: () => _openChat(c),
                        onLongPress: () => _showChatMenu(c),
                      );
                    },
                  ),
            ),
          ),
        ],
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

  void _showChatMenu(Conversation c) {
    final chat = context.read<ChatProvider>();
    final fav = chat.isFavorite(c.id);
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(fav ? Icons.star_rounded : Icons.star_outline_rounded),
              title: Text(fav ? 'Hapus dari favorit' : 'Tambah ke favorit'),
              onTap: () {
                Navigator.pop(context);
                chat.toggleFavorite(c.id);
              },
            ),
            ListTile(
              leading: Icon(Icons.delete_rounded,
                  color: Theme.of(context).colorScheme.error),
              title: Text('Hapus chat',
                  style:
                      TextStyle(color: Theme.of(context).colorScheme.error)),
              onTap: () {
                Navigator.pop(context);
                _confirmDeleteChat(c);
              },
            ),
          ],
        ),
      ),
    );
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

  /// Avatar di daftar chat + cincin status (hijau=belum dilihat, abu=sudah).
  /// Ketuk avatar yang bercincin → buka status orang itu.
  Widget _chatLeading(Conversation c, StatusProvider status,
      ColorScheme scheme, AppPalette palette) {
    String? ring;
    final peer = c.peer;
    if (!c.isGroup && peer != null) ring = status.ringState(peer.id);
    Color? ringColor;
    if (ring == 'unseen') {
      ringColor = scheme.primary;
    } else if (ring == 'seen') {
      ringColor = palette.muted.withValues(alpha: 0.5);
    }
    final avatar =
        Avatar(url: c.avatarUrl, name: c.title, radius: 27, ringColor: ringColor);
    if (ring != null && peer != null) {
      return GestureDetector(onTap: () => _openPeerStatus(peer.id), child: avatar);
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

  void _openChat(Conversation c) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
    );
  }

  Future<void> _confirmDeleteChat(Conversation c) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus chat?'),
        content: Text('Hapus percakapan dengan "${c.title}" dari daftar Anda?'),
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
      try {
        await context.read<ChatProvider>().deleteConversation(c.id);
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(ApiClient.errorMessage(e))),
          );
        }
      }
    }
  }
}
