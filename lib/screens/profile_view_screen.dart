import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

/// Halaman info/profil seorang user (dibuka dari header chat / kontak).
class ProfileViewScreen extends StatelessWidget {
  final AppUser user;
  final bool canMessage;
  const ProfileViewScreen({
    super.key,
    required this.user,
    this.canMessage = true,
  });

  String _lastSeenText(ChatProvider chat) {
    if (chat.isOnline(user.id)) return 'online';
    final ls = chat.lastSeenOf(user.id) ?? user.lastSeen;
    if (ls == null) return '';
    return 'terakhir dilihat ${_rel(ls)}';
  }

  String _rel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final days = today.difference(d).inDays;
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}.${dt.minute.toString().padLeft(2, '0')}';
    if (days == 0) return 'pukul $hm';
    if (days == 1) return 'kemarin $hm';
    return '${dt.day}/${dt.month}/${dt.year} $hm';
  }

  Future<void> _message(BuildContext context) async {
    try {
      final chat = context.read<ChatProvider>();
      final c = await chat.service.createDirect(user.id);
      await chat.loadConversations();
      if (!context.mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    }
  }

  Future<void> _addContact(BuildContext context) async {
    try {
      await context.read<ChatProvider>().service.addContact(user.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${user.displayName} ditambahkan ke kontak')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final palette = AppPalette.of(context);
    final status = _lastSeenText(chat);
    return Scaffold(
      appBar: AppBar(title: const Text('Info Kontak')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(child: Avatar(url: user.avatarUrl, name: user.displayName, radius: 60)),
          const SizedBox(height: 16),
          Center(
            child: Text(
              user.displayName,
              style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
            ),
          ),
          if (status.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Center(
                child: Text(
                  status,
                  style: TextStyle(
                    color: status == 'online'
                        ? Theme.of(context).colorScheme.primary
                        : palette.muted,
                  ),
                ),
              ),
            ),
          const SizedBox(height: 28),
          if (canMessage)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _action(context, Icons.chat_bubble_rounded, 'Pesan',
                      () => _message(context)),
                  const SizedBox(width: 28),
                  _action(context, Icons.person_add_alt_1_rounded, 'Tambah',
                      () => _addContact(context)),
                ],
              ),
            ),
          const SizedBox(height: 28),
          _tile(palette, Icons.phone_rounded, 'Telepon', user.phone),
          _tile(palette, Icons.info_outline_rounded, 'Tentang',
              user.about ?? '-'),
        ],
      ),
    );
  }

  Widget _action(
      BuildContext context, IconData icon, String label, VoidCallback onTap) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(40),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: scheme.primary),
          ),
        ),
        const SizedBox(height: 6),
        Text(label, style: const TextStyle(fontSize: 12.5)),
      ],
    );
  }

  Widget _tile(AppPalette palette, IconData icon, String label, String value) {
    return ListTile(
      leading: Icon(icon, color: palette.muted),
      title: Text(label,
          style: TextStyle(fontSize: 12.5, color: palette.muted)),
      subtitle: Text(value, style: const TextStyle(fontSize: 15.5)),
    );
  }
}
