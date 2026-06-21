import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/community.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';

/// Daftar komunitas + buat komunitas baru.
class CommunitiesScreen extends StatefulWidget {
  const CommunitiesScreen({super.key});

  @override
  State<CommunitiesScreen> createState() => _CommunitiesScreenState();
}

class _CommunitiesScreenState extends State<CommunitiesScreen> {
  List<CommunitySummary> _items = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<ChatProvider>().service.listCommunities();
      if (mounted) setState(() => _items = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _create() async {
    final nameCtrl = TextEditingController();
    final descCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buat komunitas'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
                controller: nameCtrl,
                decoration: const InputDecoration(labelText: 'Nama komunitas')),
            const SizedBox(height: 12),
            TextField(
                controller: descCtrl,
                maxLines: 3,
                decoration:
                    const InputDecoration(labelText: 'Deskripsi (opsional)')),
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
    if (ok != true || nameCtrl.text.trim().isEmpty || !mounted) return;
    final chat = context.read<ChatProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final c = await chat.service
          .createCommunity(nameCtrl.text.trim(), description: descCtrl.text.trim());
      await nav.push(MaterialPageRoute(
          builder: (_) => CommunityScreen(communityId: c.id)));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Komunitas')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _create,
        icon: const Icon(Icons.groups_rounded),
        label: const Text('Buat komunitas'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: _items.isEmpty
                  ? ListView(children: [
                      const SizedBox(height: 80),
                      Icon(Icons.groups_2_rounded,
                          size: 64, color: palette.muted),
                      const SizedBox(height: 12),
                      Center(
                        child: Text('Belum ada komunitas',
                            style: TextStyle(color: palette.muted)),
                      ),
                    ])
                  : ListView(
                      children: _items
                          .map((c) => ListTile(
                                leading: Avatar(
                                    url: c.avatarUrl, name: c.name, radius: 26),
                                title: Text(c.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                subtitle: c.description?.isNotEmpty == true
                                    ? Text(c.description!,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis)
                                    : null,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                      builder: (_) =>
                                          CommunityScreen(communityId: c.id)),
                                ),
                              ))
                          .toList(),
                    ),
            ),
    );
  }
}

/// Detail komunitas: grup pengumuman + daftar grup + (admin) buat grup.
class CommunityScreen extends StatefulWidget {
  final String communityId;
  const CommunityScreen({super.key, required this.communityId});

  @override
  State<CommunityScreen> createState() => _CommunityScreenState();
}

class _CommunityScreenState extends State<CommunityScreen> {
  CommunityDetail? _c;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final c =
          await context.read<ChatProvider>().service.getCommunity(widget.communityId);
      if (mounted) setState(() => _c = c);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openGroup(CommunityGroup g) async {
    final chat = context.read<ChatProvider>();
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conv = g.joined
          ? await chat.service.getConversation(g.id)
          : await chat.service.joinCommunityGroup(g.id);
      await nav.push(
          MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  Future<void> _createGroup() async {
    final nameCtrl = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Buat grup di komunitas'),
        content: TextField(
            controller: nameCtrl,
            decoration: const InputDecoration(labelText: 'Nama grup')),
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
    if (ok != true || nameCtrl.text.trim().isEmpty || !mounted) return;
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      final c = await chat.service
          .createGroupInCommunity(widget.communityId, nameCtrl.text.trim(), []);
      if (mounted) setState(() => _c = c);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final c = _c;
    return Scaffold(
      appBar: AppBar(title: Text(c?.name ?? 'Komunitas')),
      floatingActionButton: (c?.isAdmin ?? false)
          ? FloatingActionButton.extended(
              onPressed: _createGroup,
              icon: const Icon(Icons.add_rounded),
              label: const Text('Buat grup'),
            )
          : null,
      body: _loading || c == null
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                children: [
                  const SizedBox(height: 16),
                  Center(
                      child:
                          Avatar(url: c.avatarUrl, name: c.name, radius: 44)),
                  const SizedBox(height: 12),
                  Center(
                    child: Text(c.name,
                        style: const TextStyle(
                            fontSize: 20, fontWeight: FontWeight.w700)),
                  ),
                  if ((c.description ?? '').isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
                      child: Text(c.description!,
                          textAlign: TextAlign.center,
                          style: TextStyle(color: palette.muted)),
                    ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 4),
                    child: Text('Grup',
                        style: TextStyle(
                            color: Theme.of(context).colorScheme.primary,
                            fontWeight: FontWeight.w700)),
                  ),
                  for (final g in c.groups)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor: g.isAnnouncement
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(
                          g.isAnnouncement
                              ? Icons.campaign_rounded
                              : Icons.group_rounded,
                          color: g.isAnnouncement
                              ? Colors.white
                              : Theme.of(context).colorScheme.onPrimaryContainer,
                        ),
                      ),
                      title: Text(
                          g.isAnnouncement ? '${g.title} (Pengumuman)' : g.title,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text('${g.memberCount} anggota',
                          style: TextStyle(
                              color: palette.muted, fontSize: 12.5)),
                      trailing: g.joined
                          ? const Icon(Icons.chevron_right_rounded)
                          : FilledButton(
                              onPressed: () => _openGroup(g),
                              child: const Text('Gabung')),
                      onTap: () => _openGroup(g),
                    ),
                  const SizedBox(height: 80),
                ],
              ),
            ),
    );
  }
}
