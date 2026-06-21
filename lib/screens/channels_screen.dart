import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/channel.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

/// Daftar saluran (channel): yang diikuti + temukan saluran baru, buat saluran.
class ChannelsScreen extends StatefulWidget {
  const ChannelsScreen({super.key});

  @override
  State<ChannelsScreen> createState() => _ChannelsScreenState();
}

class _ChannelsScreenState extends State<ChannelsScreen> {
  List<ChannelSummary> _channels = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<ChatProvider>().service.listChannels();
      if (mounted) setState(() => _channels = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChannel(String id) async {
    final chat = context.read<ChatProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conv = await chat.service.getConversation(id);
      await nav.push(MaterialPageRoute(
          builder: (_) => ChatScreen(conversation: conv)));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  Future<void> _follow(ChannelSummary c) async {
    final chat = context.read<ChatProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conv = await chat.service.followChannel(c.id);
      await nav.push(MaterialPageRoute(
          builder: (_) => ChatScreen(conversation: conv)));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  Future<void> _unfollow(ChannelSummary c) async {
    try {
      await context.read<ChatProvider>().service.unfollowChannel(c.id);
      _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }

  Future<void> _createChannel() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buat saluran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama saluran'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Deskripsi (opsional)'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Buat')),
        ],
      ),
    );
    if (ok != true || nameCtrl.text.trim().isEmpty) return;
    if (!mounted) return;
    final chat = context.read<ChatProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conv = await chat.service.createChannel(
        nameCtrl.text.trim(),
        description: descCtrl.text.trim(),
      );
      await nav.push(MaterialPageRoute(
          builder: (_) => ChatScreen(conversation: conv)));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final following = _channels.where((c) => c.following).toList();
    final discover = _channels.where((c) => !c.following).toList();

    return Scaffold(
      appBar: AppBar(title: const Text('Saluran')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _createChannel,
        icon: const Icon(Icons.add_rounded),
        label: const Text('Buat saluran'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  if (following.isNotEmpty) ...[
                    _header('Saluran yang diikuti', palette),
                    ...following.map((c) => _tile(c, palette)),
                  ],
                  _header('Temukan saluran', palette),
                  if (discover.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Center(
                        child: Text('Belum ada saluran lain',
                            style: TextStyle(color: palette.muted)),
                      ),
                    ),
                  ...discover.map((c) => _tile(c, palette)),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }

  Widget _header(String text, AppPalette palette) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 6),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.w700)),
      );

  Widget _tile(ChannelSummary c, AppPalette palette) {
    return ListTile(
      leading: Stack(
        children: [
          Avatar(url: c.avatarUrl, name: c.title, radius: 24),
          Positioned(
            right: 0,
            bottom: 0,
            child: Container(
              padding: const EdgeInsets.all(2),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primary,
                shape: BoxShape.circle,
                border: Border.all(color: palette.chatBackground, width: 1.5),
              ),
              child: const Icon(Icons.campaign_rounded,
                  size: 11, color: Colors.white),
            ),
          ),
        ],
      ),
      title: Text(c.title, style: const TextStyle(fontWeight: FontWeight.w600)),
      subtitle: Text(
        c.description?.isNotEmpty == true
            ? c.description!
            : '${c.followerCount} pengikut',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      trailing: c.following
          ? OutlinedButton(
              onPressed: () => _unfollow(c),
              child: const Text('Diikuti'),
            )
          : FilledButton(
              onPressed: () => _follow(c),
              child: const Text('Ikuti'),
            ),
      onTap: c.following ? () => _openChannel(c.id) : () => _follow(c),
    );
  }
}
