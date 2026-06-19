import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../widgets/avatar.dart';
import 'profile_view_screen.dart';

/// Info & pengaturan grup: deskripsi, anggota, peran admin, undangan.
class GroupInfoScreen extends StatefulWidget {
  final Conversation conversation;
  const GroupInfoScreen({super.key, required this.conversation});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late Conversation _conv = widget.conversation;
  bool _loading = false;

  ChatProvider get _chat => context.read<ChatProvider>();
  String get _myId => context.read<AuthProvider>().userId ?? '';
  bool get _amAdmin => _conv.isAdmin(_myId);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
  }

  Future<void> _refresh() async {
    try {
      final fresh = await _chat.service.getConversation(_conv.id);
      if (mounted) setState(() => _conv = fresh);
    } catch (_) {}
  }

  Future<void> _run(Future<Conversation> Function() op) async {
    setState(() => _loading = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final updated = await op();
      if (mounted) setState(() => _conv = updated);
      _chat.loadConversations();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _editInfo() async {
    final nameCtrl = TextEditingController(text: _conv.title);
    final descCtrl = TextEditingController(text: _conv.description ?? '');
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Edit info grup'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(labelText: 'Nama grup'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: descCtrl,
              maxLines: 3,
              decoration: const InputDecoration(labelText: 'Deskripsi'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Simpan')),
        ],
      ),
    );
    if (ok == true) {
      await _run(() => _chat.service.updateGroup(_conv.id,
          name: nameCtrl.text.trim(), description: descCtrl.text.trim()));
    }
  }

  bool get _canEditInfo => _amAdmin || !_conv.adminOnlyEdit;

  /// Ganti foto grup: pilih gambar → upload → updateGroup avatarUrl.
  Future<void> _changePhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picked = await ImagePicker()
          .pickImage(source: ImageSource.gallery, imageQuality: 80);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      setState(() => _loading = true);
      final up = await _chat.service.uploadFile(bytes, picked.name);
      await _run(() => _chat.service.updateGroup(_conv.id, avatarUrl: up.url));
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _setAdminOnlyMessages(bool v) =>
      _run(() => _chat.service.setGroupPermissions(_conv.id, adminOnlyMessages: v));

  Future<void> _setAdminOnlyEdit(bool v) =>
      _run(() => _chat.service.setGroupPermissions(_conv.id, adminOnlyEdit: v));

  Future<void> _addMembers() async {
    final existing = _conv.members.map((m) => m.id).toSet();
    List<({String id, String? alias, AppUser user})> contacts = [];
    try {
      contacts = await _chat.service.getContacts();
    } catch (_) {}
    final candidates =
        contacts.where((c) => !existing.contains(c.user.id)).toList();
    if (!mounted) return;
    if (candidates.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Semua kontak sudah jadi anggota')));
      return;
    }
    final selected = <String>{};
    final ok = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (_, setSheet) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.6,
          builder: (_, controller) => Column(
            children: [
              const Padding(
                padding: EdgeInsets.all(12),
                child: Text('Tambah anggota',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
              ),
              Expanded(
                child: ListView(
                  controller: controller,
                  children: [
                    for (final c in candidates)
                      CheckboxListTile(
                        value: selected.contains(c.user.id),
                        title: Text(c.alias ?? c.user.displayName),
                        secondary: Avatar(
                            url: c.user.avatarUrl,
                            name: c.user.displayName,
                            radius: 20),
                        onChanged: (v) => setSheet(() => v == true
                            ? selected.add(c.user.id)
                            : selected.remove(c.user.id)),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(12),
                child: SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: selected.isEmpty
                        ? null
                        : () => Navigator.pop(context, true),
                    child: Text('Tambah (${selected.length})'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (ok == true && selected.isNotEmpty) {
      await _run(() => _chat.service.addMembers(_conv.id, selected.toList()));
    }
  }

  Future<void> _shareInvite() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final inv = await _chat.service.createInvite(_conv.id);
      if (!mounted) return;
      final shareLink = inv.webLink ?? inv.link;
      await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Link undangan grup'),
          content: SelectableText(shareLink),
          actions: [
            TextButton(
              onPressed: () {
                Clipboard.setData(ClipboardData(text: shareLink));
                Navigator.pop(context);
                messenger.showSnackBar(
                    const SnackBar(content: Text('Link disalin')));
              },
              child: const Text('Salin'),
            ),
            TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Tutup')),
          ],
        ),
      );
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  void _memberActions(AppUser u) {
    if (u.id == _myId) return;
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.person_rounded),
              title: const Text('Lihat profil'),
              onTap: () {
                Navigator.pop(context);
                Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ProfileViewScreen(user: u)));
              },
            ),
            if (_amAdmin) ...[
              ListTile(
                leading: Icon(_conv.isAdmin(u.id)
                    ? Icons.remove_moderator_rounded
                    : Icons.add_moderator_rounded),
                title: Text(
                    _conv.isAdmin(u.id) ? 'Hapus admin' : 'Jadikan admin'),
                onTap: () {
                  Navigator.pop(context);
                  _run(() => _chat.service
                      .setMemberRole(_conv.id, u.id, !_conv.isAdmin(u.id)));
                },
              ),
              ListTile(
                leading: const Icon(Icons.person_remove_rounded,
                    color: Color(0xFFEF4444)),
                title: const Text('Keluarkan dari grup',
                    style: TextStyle(color: Color(0xFFEF4444))),
                onTap: () {
                  Navigator.pop(context);
                  _run(() => _chat.service.removeMember(_conv.id, u.id));
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final members = _conv.members;
    return Scaffold(
      appBar: AppBar(
        title: const Text('Info grup'),
        actions: [
          if (_canEditInfo)
            IconButton(
                icon: const Icon(Icons.edit_rounded), onPressed: _editInfo),
        ],
      ),
      body: Column(
        children: [
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: ListView(
              children: [
                const SizedBox(height: 16),
                Center(
                  child: Stack(
                    children: [
                      Avatar(
                          url: _conv.avatarUrl, name: _conv.title, radius: 48),
                      if (_canEditInfo)
                        Positioned(
                          right: 0,
                          bottom: 0,
                          child: GestureDetector(
                            onTap: _changePhoto,
                            child: CircleAvatar(
                              radius: 16,
                              backgroundColor:
                                  Theme.of(context).colorScheme.primary,
                              child: const Icon(Icons.camera_alt_rounded,
                                  size: 18, color: Colors.white),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Center(
                  child: Text(_conv.title,
                      style: const TextStyle(
                          fontSize: 20, fontWeight: FontWeight.w700)),
                ),
                Center(
                  child: Text('${members.length} anggota',
                      style: Theme.of(context).textTheme.bodySmall),
                ),
                if ((_conv.description ?? '').isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Text(_conv.description!),
                  ),
                const Divider(),
                ListTile(
                  leading: const Icon(Icons.link_rounded),
                  title: const Text('Bagikan link undangan'),
                  onTap: _shareInvite,
                ),
                if (_amAdmin)
                  ListTile(
                    leading: const Icon(Icons.person_add_rounded),
                    title: const Text('Tambah anggota'),
                    onTap: _addMembers,
                  ),
                if (_amAdmin) ...[
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
                    child: Text('Pengaturan grup',
                        style: TextStyle(
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary)),
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.campaign_rounded),
                    title: const Text('Hanya admin yang dapat mengirim pesan'),
                    subtitle: const Text('Jadikan grup mode pengumuman'),
                    value: _conv.adminOnlyMessages,
                    onChanged: _loading ? null : _setAdminOnlyMessages,
                  ),
                  SwitchListTile(
                    secondary: const Icon(Icons.lock_rounded),
                    title:
                        const Text('Hanya admin yang dapat mengubah info grup'),
                    subtitle: const Text('Nama, foto, dan deskripsi'),
                    value: _conv.adminOnlyEdit,
                    onChanged: _loading ? null : _setAdminOnlyEdit,
                  ),
                ],
                const Divider(),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
                  child: Text('Anggota',
                      style: TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Theme.of(context).colorScheme.primary)),
                ),
                for (final u in members)
                  ListTile(
                    leading: Avatar(
                        url: u.avatarUrl, name: u.displayName, radius: 22),
                    title: Text(u.id == _myId ? 'Anda' : u.displayName),
                    subtitle: Text(u.about ?? u.phone,
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                    trailing: _conv.isAdmin(u.id)
                        ? const Chip(
                            label: Text('Admin'),
                            visualDensity: VisualDensity.compact)
                        : null,
                    onTap: () => _memberActions(u),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
