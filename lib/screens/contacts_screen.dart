import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../models/user.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'chat_screen.dart';
import 'qr_screen.dart';

class ContactsScreen extends StatefulWidget {
  /// Bila diisi (mode dua panel/web), chat dibuka di panel kanan, bukan layar penuh.
  final void Function(Conversation conversation)? onOpen;
  const ContactsScreen({super.key, this.onOpen});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  List<({String id, String? alias, AppUser user})> _contacts = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<ChatProvider>().service.getContacts();
      if (mounted) setState(() => _contacts = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _openChatWith(AppUser u) async {
    try {
      final chat = context.read<ChatProvider>();
      final c = await chat.service.createDirect(u.id);
      await chat.loadConversations();
      if (!mounted) return;
      if (widget.onOpen != null) {
        widget.onOpen!(c); // dua panel (web) → buka di panel kanan
      } else {
        Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => ChatScreen(conversation: c)),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    }
  }

  Future<void> _removeContact(String id) async {
    try {
      await context.read<ChatProvider>().service.deleteContact(id);
      await _load();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Kontak'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_rounded),
            tooltip: 'Kode QR',
            onPressed: () async {
              final added = await Navigator.of(context).push<bool>(
                MaterialPageRoute(builder: (_) => const QrScreen()),
              );
              if (added == true) _load();
            },
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showAddSheet,
        icon: const Icon(Icons.person_add_alt_1_rounded),
        label: const Text('Tambah'),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _contacts.isEmpty
              ? Center(
                  child: Text(
                    'Belum ada kontak.\nTekan "Tambah" untuk menyimpan kontak.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: palette.muted),
                  ),
                )
              : ListView.builder(
                  itemCount: _contacts.length,
                  itemBuilder: (_, i) {
                    final c = _contacts[i];
                    final name = c.alias ?? c.user.displayName;
                    return ListTile(
                      leading: Avatar(url: c.user.avatarUrl, name: name),
                      title: Text(name,
                          style:
                              const TextStyle(fontWeight: FontWeight.w600)),
                      subtitle: Text(c.user.phone),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline_rounded),
                        onPressed: () => _removeContact(c.id),
                      ),
                      onTap: () => _openChatWith(c.user),
                    );
                  },
                ),
    );
  }

  void _showAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => _AddContactSheet(onAdded: _load),
    );
  }
}

/// Bottom sheet: cari semua pengguna terdaftar lalu tambahkan jadi kontak.
class _AddContactSheet extends StatefulWidget {
  final VoidCallback onAdded;
  const _AddContactSheet({required this.onAdded});

  @override
  State<_AddContactSheet> createState() => _AddContactSheetState();
}

class _AddContactSheetState extends State<_AddContactSheet> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<AppUser> _users = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _query('');
  }

  @override
  void dispose() {
    _search.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  Future<void> _query(String q) async {
    setState(() => _loading = true);
    try {
      final res = await context.read<ChatProvider>().service.searchUsers(q);
      if (mounted) setState(() => _users = res);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _add(AppUser u) async {
    try {
      await context.read<ChatProvider>().service.addContact(u.id);
      if (!mounted) return;
      Navigator.pop(context);
      widget.onAdded();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${u.displayName} ditambahkan ke kontak')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: Column(
          children: [
            // Tambah kontak via scan QR (ala WhatsApp).
            ListTile(
              leading: CircleAvatar(
                backgroundColor:
                    Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                child: Icon(Icons.qr_code_scanner_rounded,
                    color: Theme.of(context).colorScheme.primary),
              ),
              title: const Text('Pindai kode QR'),
              subtitle: const Text('Tambah kontak dengan memindai QR'),
              onTap: () async {
                final nav = Navigator.of(context);
                final onAdded = widget.onAdded;
                nav.pop();
                final added = await nav.push<bool>(MaterialPageRoute(
                    builder: (_) => const QrScreen(initialTab: 1)));
                if (added == true) onAdded();
              },
            ),
            const Divider(height: 1),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                controller: _search,
                autofocus: true,
                onChanged: (q) {
                  _debounce?.cancel();
                  _debounce = Timer(
                    const Duration(milliseconds: 350),
                    () => _query(q),
                  );
                },
                decoration: const InputDecoration(
                  hintText: 'Cari nama / nomor telepon',
                  prefixIcon: Icon(Icons.search_rounded),
                ),
              ),
            ),
            if (_loading) const LinearProgressIndicator(minHeight: 2),
            Expanded(
              child: ListView.builder(
                itemCount: _users.length,
                itemBuilder: (_, i) {
                  final u = _users[i];
                  return ListTile(
                    leading: Avatar(url: u.avatarUrl, name: u.displayName),
                    title: Text(u.displayName),
                    subtitle: Text(u.phone),
                    trailing: const Icon(Icons.add_circle_outline_rounded),
                    onTap: () => _add(u),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
