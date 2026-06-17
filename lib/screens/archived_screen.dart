import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/chat_provider.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

/// Daftar chat yang diarsipkan. Ketuk untuk membuka, geser untuk batal arsip.
class ArchivedScreen extends StatelessWidget {
  const ArchivedScreen({super.key});

  String _preview(Conversation c) {
    final m = c.lastMessage;
    if (m == null) return '';
    if (m.deleted) return 'Pesan dihapus';
    switch (m.type) {
      case 'IMAGE':
        return '📷 Foto';
      case 'VIDEO':
        return '📹 Video';
      case 'VOICE':
        return '🎤 Pesan suara';
      case 'FILE':
        return '📎 ${m.mediaName ?? 'File'}';
      case 'STICKER':
        return m.content ?? '🙂';
      case 'CALL':
        return '📞 Panggilan';
      default:
        return m.content ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final items =
        chat.conversations.where((c) => chat.isArchived(c.id)).toList();
    return Scaffold(
      appBar: AppBar(title: const Text('Diarsipkan')),
      body: items.isEmpty
          ? const Center(child: Text('Tidak ada chat diarsipkan'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1, indent: 84),
              itemBuilder: (_, i) {
                final c = items[i];
                return Dismissible(
                  key: ValueKey('arch_${c.id}'),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Theme.of(context).colorScheme.primary
                        .withValues(alpha: 0.12),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 24),
                    child: const Icon(Icons.unarchive_rounded),
                  ),
                  confirmDismiss: (_) async {
                    await chat.setArchived(c.id, false);
                    return false;
                  },
                  child: ListTile(
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 18, vertical: 6),
                    leading:
                        Avatar(url: c.avatarUrl, name: c.title, radius: 27),
                    title: Text(c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(_preview(c),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: IconButton(
                      tooltip: 'Batal arsip',
                      icon: const Icon(Icons.unarchive_outlined),
                      onPressed: () => chat.setArchived(c.id, false),
                    ),
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(
                          builder: (_) => ChatScreen(conversation: c)),
                    ),
                  ),
                );
              },
            ),
    );
  }
}
