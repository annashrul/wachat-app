import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/group_call_provider.dart';
import '../widgets/avatar.dart';

/// Layar panggilan grup (mesh, suara). Menampilkan UI panggilan masuk
/// (ringing) atau panel peserta saat aktif.
class GroupCallScreen extends StatefulWidget {
  const GroupCallScreen({super.key});

  @override
  State<GroupCallScreen> createState() => _GroupCallScreenState();
}

class _GroupCallScreenState extends State<GroupCallScreen> {
  bool _popped = false;

  AppUser? _member(String userId) {
    final convId = context.read<GroupCallProvider>().conversationId ??
        context.read<GroupCallProvider>().incomingConversationId;
    if (convId == null) return null;
    final conv = context.read<ChatProvider>().conversationById(convId);
    for (final m in conv?.members ?? const <AppUser>[]) {
      if (m.id == userId) return m;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<GroupCallProvider>();

    // Panggilan selesai → tutup layar.
    if (call.state == GroupCallState.idle && !_popped) {
      _popped = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).maybePop();
      });
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0B141A),
      body: SafeArea(
        child: call.state == GroupCallState.ringing
            ? _incoming(call)
            : _active(call),
      ),
    );
  }

  Widget _incoming(GroupCallProvider call) {
    return Column(
      children: [
        const Spacer(),
        Avatar(
          url: call.incomingFromAvatar,
          name: call.incomingFromName ?? 'Grup',
          radius: 56,
        ),
        const SizedBox(height: 20),
        Text(
          call.incomingFromName ?? 'Seseorang',
          style: const TextStyle(
              color: Colors.white, fontSize: 22, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 6),
        const Text('Panggilan grup masuk…',
            style: TextStyle(color: Colors.white70)),
        const Spacer(),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _circleBtn(
              icon: Icons.call_end_rounded,
              color: Colors.red,
              label: 'Tolak',
              onTap: () => context.read<GroupCallProvider>().declineIncoming(),
            ),
            _circleBtn(
              icon: Icons.call_rounded,
              color: const Color(0xFF22C55E),
              label: 'Terima',
              onTap: () {
                final convId = call.incomingConversationId;
                final title = convId == null
                    ? 'Grup'
                    : (context
                            .read<ChatProvider>()
                            .conversationById(convId)
                            ?.title ??
                        'Grup');
                context.read<GroupCallProvider>().accept(title);
              },
            ),
          ],
        ),
        const SizedBox(height: 40),
      ],
    );
  }

  Widget _active(GroupCallProvider call) {
    final myId = context.read<AuthProvider>().userId ?? '';
    // Peserta = saya + remote peers.
    final ids = <String>[myId, ...call.participantIds];
    return Column(
      children: [
        const SizedBox(height: 16),
        Text(
          call.conversationTitle ?? 'Panggilan grup',
          style: const TextStyle(
              color: Colors.white, fontSize: 20, fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 4),
        Text('${ids.length} peserta',
            style: const TextStyle(color: Colors.white70)),
        const SizedBox(height: 20),
        Expanded(
          child: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(16),
            mainAxisSpacing: 16,
            crossAxisSpacing: 16,
            children: [
              for (final id in ids) _tile(id, id == myId, call),
            ],
          ),
        ),
        // Kontrol bawah.
        Padding(
          padding: const EdgeInsets.only(bottom: 30, top: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceEvenly,
            children: [
              _circleBtn(
                icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                color: call.muted ? Colors.white24 : Colors.white24,
                label: call.muted ? 'Bisu' : 'Mic',
                onTap: () => context.read<GroupCallProvider>().toggleMute(),
              ),
              _circleBtn(
                icon: Icons.call_end_rounded,
                color: Colors.red,
                label: 'Keluar',
                onTap: () => context.read<GroupCallProvider>().leave(),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _tile(String userId, bool isMe, GroupCallProvider call) {
    final u = isMe ? null : _member(userId);
    final name = isMe ? 'Anda' : (u?.displayName ?? 'Peserta');
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF1F2C33),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Avatar(url: u?.avatarUrl, name: name, radius: 36),
          const SizedBox(height: 10),
          Text(name,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600)),
          if (isMe && call.muted)
            const Padding(
              padding: EdgeInsets.only(top: 4),
              child: Icon(Icons.mic_off_rounded,
                  color: Colors.white54, size: 18),
            ),
        ],
      ),
    );
  }

  Widget _circleBtn({
    required IconData icon,
    required Color color,
    required String label,
    required VoidCallback onTap,
  }) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: CircleAvatar(
            radius: 32,
            backgroundColor: color,
            child: Icon(icon, color: Colors.white, size: 30),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70)),
      ],
    );
  }
}
