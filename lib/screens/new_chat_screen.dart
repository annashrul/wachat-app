import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../models/user.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

class NewChatScreen extends StatefulWidget {
  const NewChatScreen({super.key});

  @override
  State<NewChatScreen> createState() => _NewChatScreenState();
}

class _NewChatScreenState extends State<NewChatScreen> {
  final _search = TextEditingController();
  Timer? _debounce;
  List<AppUser> _results = [];
  bool _loading = false;

  bool _groupMode = false;
  final Map<String, AppUser> _selected = {};
  final _groupName = TextEditingController();

  @override
  void initState() {
    super.initState();
    // Tampilkan semua user terdaftar saat dibuka.
    WidgetsBinding.instance.addPostFrameCallback((_) => _doSearch(''));
  }

  @override
  void dispose() {
    _search.dispose();
    _groupName.dispose();
    _debounce?.cancel();
    super.dispose();
  }

  void _onSearchChanged(String q) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () => _doSearch(q));
  }

  Future<void> _doSearch(String q) async {
    setState(() => _loading = true);
    try {
      final res = await context.read<ChatProvider>().service.searchUsers(q);
      if (mounted) setState(() => _results = res);
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

  Future<void> _startDirect(AppUser u) async {
    try {
      final c = await context.read<ChatProvider>().service.createDirect(u.id);
      if (mounted) Navigator.of(context).pop<Conversation>(c);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    }
  }

  Future<void> _createGroup() async {
    if (_groupName.text.trim().isEmpty || _selected.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Isi nama grup & pilih minimal 1 anggota'),
        ),
      );
      return;
    }
    try {
      final c = await context.read<ChatProvider>().service.createGroup(
            _groupName.text.trim(),
            _selected.keys.toList(),
          );
      if (mounted) Navigator.of(context).pop<Conversation>(c);
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
        title: Text(_groupMode ? 'Grup baru' : 'Chat baru'),
        actions: [
          IconButton(
            tooltip: _groupMode ? 'Mode chat biasa' : 'Buat grup',
            icon: Icon(
              _groupMode ? Icons.person_rounded : Icons.group_add_rounded,
            ),
            onPressed: () => setState(() {
              _groupMode = !_groupMode;
              _selected.clear();
            }),
          ),
          const SizedBox(width: 4),
        ],
      ),
      floatingActionButton: _groupMode
          ? FloatingActionButton.extended(
              onPressed: _createGroup,
              icon: const Icon(Icons.check_rounded),
              label: const Text('Buat grup'),
            )
          : null,
      body: Column(
        children: [
          if (_groupMode)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
              child: TextField(
                controller: _groupName,
                decoration: const InputDecoration(
                  hintText: 'Nama grup',
                  prefixIcon: Icon(Icons.group_rounded),
                ),
              ),
            ),
          if (_groupMode && _selected.isNotEmpty)
            SizedBox(
              height: 56,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 12),
                children: _selected.values
                    .map(
                      (u) => Padding(
                        padding: const EdgeInsets.all(4),
                        child: Chip(
                          avatar: Avatar(
                            url: u.avatarUrl,
                            name: u.displayName,
                            radius: 12,
                          ),
                          label: Text(u.displayName),
                          onDeleted: () =>
                              setState(() => _selected.remove(u.id)),
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _search,
              onChanged: _onSearchChanged,
              decoration: const InputDecoration(
                hintText: 'Cari nama atau nomor telepon',
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
          if (_loading) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: _results.isEmpty
                ? Center(
                    child: Text(
                      'Ketik untuk mencari pengguna',
                      style: TextStyle(color: palette.muted),
                    ),
                  )
                : ListView.builder(
                    itemCount: _results.length,
                    itemBuilder: (_, i) {
                      final u = _results[i];
                      final selected = _selected.containsKey(u.id);
                      return ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
                        ),
                        leading: Avatar(
                          url: u.avatarUrl,
                          name: u.displayName,
                          radius: 24,
                        ),
                        title: Text(
                          u.displayName,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        subtitle: Text(u.phone),
                        trailing: _groupMode
                            ? Checkbox(
                                value: selected,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                onChanged: (_) => _toggle(u, selected),
                              )
                            : const Icon(Icons.chevron_right_rounded),
                        onTap: () {
                          if (_groupMode) {
                            _toggle(u, selected);
                          } else {
                            _startDirect(u);
                          }
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  void _toggle(AppUser u, bool selected) {
    setState(() {
      if (selected) {
        _selected.remove(u.id);
      } else {
        _selected[u.id] = u;
      }
    });
  }
}
