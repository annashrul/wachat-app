import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';

/// Helper UI untuk fitur "Kunci chat" berbasis PIN lokal.
///
/// PIN disimpan ter-hash di perangkat (lihat [ChatProvider]). Chat terkunci
/// butuh PIN untuk dibuka, dan terkunci lagi saat keluar dari ruang chat.
class ChatLock {
  /// Pastikan chat [convId] boleh dibuka. Mengembalikan true bila tidak
  /// terkunci, sudah dibuka di sesi ini, atau PIN benar.
  static Future<bool> ensureUnlocked(
      BuildContext context, String convId) async {
    final chat = context.read<ChatProvider>();
    if (!chat.isChatLocked(convId)) return true;
    if (chat.isChatUnlockedNow(convId)) return true;

    final pin = await _askPin(context,
        title: 'Chat terkunci', subtitle: 'Masukkan PIN untuk membuka');
    if (pin == null) return false;
    if (chat.verifyLockPin(pin)) {
      chat.markChatUnlocked(convId);
      return true;
    }
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PIN salah')),
      );
    }
    return false;
  }

  /// Kunci chat. Bila PIN belum pernah dibuat, minta buat dulu.
  static Future<bool> lock(BuildContext context, String convId) async {
    final chat = context.read<ChatProvider>();
    if (!chat.hasLockPin) {
      final pin = await _setupPin(context);
      if (pin == null) return false;
      await chat.setLockPin(pin);
    }
    await chat.setChatLocked(convId, true);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Chat dikunci')),
      );
    }
    return true;
  }

  /// Buka kunci (hapus status terkunci). Minta PIN untuk verifikasi.
  static Future<bool> unlock(BuildContext context, String convId) async {
    final chat = context.read<ChatProvider>();
    final pin = await _askPin(context,
        title: 'Buka kunci chat', subtitle: 'Masukkan PIN');
    if (pin == null) return false;
    if (!chat.verifyLockPin(pin)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('PIN salah')),
        );
      }
      return false;
    }
    await chat.setChatLocked(convId, false);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Kunci chat dibuka')),
      );
    }
    return true;
  }

  /// Dialog masuk PIN (satu kali). Mengembalikan PIN atau null bila batal.
  static Future<String?> _askPin(BuildContext context,
      {required String title, required String subtitle}) {
    return showDialog<String>(
      context: context,
      builder: (_) => _PinDialog(title: title, subtitle: subtitle),
    );
  }

  /// Dialog buat PIN baru (masukkan + konfirmasi).
  static Future<String?> _setupPin(BuildContext context) {
    return showDialog<String>(
      context: context,
      builder: (_) => const _PinDialog(
        title: 'Buat PIN kunci chat',
        subtitle: 'PIN 4–6 digit untuk membuka chat terkunci',
        confirm: true,
      ),
    );
  }
}

class _PinDialog extends StatefulWidget {
  const _PinDialog({
    required this.title,
    required this.subtitle,
    this.confirm = false,
  });

  final String title;
  final String subtitle;
  final bool confirm; // minta konfirmasi (untuk buat PIN baru)

  @override
  State<_PinDialog> createState() => _PinDialogState();
}

class _PinDialogState extends State<_PinDialog> {
  final _pin = TextEditingController();
  final _pin2 = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _pin.dispose();
    _pin2.dispose();
    super.dispose();
  }

  void _submit() {
    final p = _pin.text.trim();
    if (p.length < 4 || p.length > 6) {
      setState(() => _error = 'PIN harus 4–6 digit');
      return;
    }
    if (widget.confirm && p != _pin2.text.trim()) {
      setState(() => _error = 'Konfirmasi PIN tidak cocok');
      return;
    }
    Navigator.pop(context, p);
  }

  @override
  Widget build(BuildContext context) {
    Widget field(TextEditingController c, String label) => TextField(
          controller: c,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          autofocus: c == _pin,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(
            labelText: label,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
          onSubmitted: (_) => _submit(),
        );

    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitle),
          const SizedBox(height: 16),
          field(_pin, 'PIN'),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            field(_pin2, 'Konfirmasi PIN'),
          ],
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        FilledButton(onPressed: _submit, child: const Text('OK')),
      ],
    );
  }
}
