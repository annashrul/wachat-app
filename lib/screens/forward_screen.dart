import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/avatar.dart';

/// Pilih percakapan tujuan untuk meneruskan pesan. Pop dengan daftar id.
class ForwardScreen extends StatefulWidget {
  const ForwardScreen({super.key});

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final Set<String> _selected = {};

  @override
  Widget build(BuildContext context) {
    final convs = context.read<ChatProvider>().conversations;
    return Scaffold(
      appBar: AppBar(title: const Text('Teruskan ke…')),
      floatingActionButton: _selected.isEmpty
          ? null
          : FloatingActionButton.extended(
              onPressed: () => Navigator.pop(context, _selected.toList()),
              icon: const Icon(Icons.send_rounded),
              label: Text('Kirim (${_selected.length})'),
            ),
      body: ListView.builder(
        itemCount: convs.length,
        itemBuilder: (_, i) {
          final c = convs[i];
          final sel = _selected.contains(c.id);
          return ListTile(
            leading: Avatar(url: c.avatarUrl, name: c.title, radius: 24),
            title: Text(c.title,
                style: const TextStyle(fontWeight: FontWeight.w600)),
            trailing: Checkbox(
              value: sel,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
              ),
              onChanged: (_) => setState(() {
                if (sel) {
                  _selected.remove(c.id);
                } else {
                  _selected.add(c.id);
                }
              }),
            ),
            onTap: () => setState(() {
              if (sel) {
                _selected.remove(c.id);
              } else {
                _selected.add(c.id);
              }
            }),
          );
        },
      ),
    );
  }
}
