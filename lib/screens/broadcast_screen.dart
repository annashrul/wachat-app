import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/chat_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

/// Pesan siaran (broadcast): kirim satu pesan ke banyak kontak sekaligus.
/// Tiap penerima menerimanya sebagai chat pribadi biasa (seperti WhatsApp).
class BroadcastScreen extends StatefulWidget {
  const BroadcastScreen({super.key});

  @override
  State<BroadcastScreen> createState() => _BroadcastScreenState();
}

class _BroadcastScreenState extends State<BroadcastScreen> {
  final _text = TextEditingController();
  final _selected = <String>{}; // userId terpilih
  bool _sending = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _send(List<AppUser> targets) async {
    final text = _text.text.trim();
    if (text.isEmpty || _selected.isEmpty || _sending) return;
    setState(() => _sending = true);
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    var sent = 0;
    try {
      for (final u in targets) {
        if (!_selected.contains(u.id)) continue;
        final conv = await chat.service.createDirect(u.id);
        chat.sendText(conv.id, text);
        sent++;
      }
      await chat.loadConversations();
      messenger.showSnackBar(
        SnackBar(content: Text('Pesan siaran terkirim ke $sent kontak')),
      );
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(ApiClient.errorMessage(e))),
      );
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final contacts = context.watch<ChatProvider>().contacts;
    final targets = contacts.map((c) => c.user).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Pesan siaran'),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(20),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('${_selected.length} penerima dipilih',
                style: TextStyle(color: palette.muted, fontSize: 12)),
          ),
        ),
      ),
      body: Column(
        children: [
          if (_sending) const LinearProgressIndicator(minHeight: 2),
          Expanded(
            child: targets.isEmpty
                ? Center(
                    child: Text('Belum ada kontak',
                        style: TextStyle(color: palette.muted)),
                  )
                : ListView.builder(
                    itemCount: targets.length,
                    itemBuilder: (_, i) {
                      final u = targets[i];
                      return CheckboxListTile(
                        value: _selected.contains(u.id),
                        onChanged: (v) => setState(() {
                          if (v == true) {
                            _selected.add(u.id);
                          } else {
                            _selected.remove(u.id);
                          }
                        }),
                        secondary: Avatar(
                            url: u.avatarUrl, name: u.displayName, radius: 22),
                        title: Text(u.displayName),
                        subtitle: Text(u.phone,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      );
                    },
                  ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 8, 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: TextField(
                      controller: _text,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(
                        hintText: 'Ketik pesan siaran…',
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  FloatingActionButton(
                    onPressed:
                        _sending ? null : () => _send(targets),
                    child: const Icon(Icons.send_rounded),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
