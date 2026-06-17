import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../models/message.dart';
import '../providers/chat_provider.dart';
import 'chat_screen.dart';

/// Daftar pesan yang diberi bintang (lintas percakapan).
class StarredScreen extends StatefulWidget {
  const StarredScreen({super.key});

  @override
  State<StarredScreen> createState() => _StarredScreenState();
}

class _StarredScreenState extends State<StarredScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback(
      (_) => context.read<ChatProvider>().loadStarred(),
    );
  }

  String _preview(Message m) {
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
      case 'LOCATION':
        return '📍 Lokasi';
      default:
        return m.content ?? '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final items = chat.starredMessages;
    return Scaffold(
      appBar: AppBar(title: const Text('Pesan berbintang')),
      body: items.isEmpty
          ? const Center(child: Text('Belum ada pesan berbintang'))
          : ListView.separated(
              itemCount: items.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (_, i) {
                final m = items[i];
                final conv = chat.conversationById(m.conversationId);
                return ListTile(
                  leading: const Icon(Icons.star_rounded, color: Colors.amber),
                  title: Text(
                    m.senderName ?? conv?.title ?? 'Pesan',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  subtitle: Text(_preview(m),
                      maxLines: 2, overflow: TextOverflow.ellipsis),
                  trailing: Text(
                    DateFormat('dd/MM HH:mm').format(m.createdAt),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  onTap: conv == null
                      ? null
                      : () => Navigator.of(context).push(
                            MaterialPageRoute(
                                builder: (_) =>
                                    ChatScreen(conversation: conv)),
                          ),
                );
              },
            ),
    );
  }
}
