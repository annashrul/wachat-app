import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/call_log.dart';
import '../providers/auth_provider.dart';
import '../providers/call_provider.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

class CallHistoryScreen extends StatefulWidget {
  const CallHistoryScreen({super.key});

  @override
  State<CallHistoryScreen> createState() => _CallHistoryScreenState();
}

class _CallHistoryScreenState extends State<CallHistoryScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<CallProvider>().loadCalls();
    });
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus riwayat panggilan?'),
        content: const Text('Semua riwayat panggilan akan dihapus.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Hapus')),
        ],
      ),
    );
    if (ok == true && mounted) {
      await context.read<CallProvider>().clearCalls();
    }
  }

  static String _time(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final hm =
        '${dt.hour.toString().padLeft(2, '0')}.${dt.minute.toString().padLeft(2, '0')}';
    final days = today.difference(d).inDays;
    if (days == 0) return 'Hari ini $hm';
    if (days == 1) return 'Kemarin $hm';
    return '${dt.day}/${dt.month}/${dt.year} $hm';
  }

  static String _dur(int sec) {
    final m = (sec ~/ 60).toString().padLeft(2, '0');
    final s = (sec % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final myId = context.read<AuthProvider>().userId ?? '';
    final call = context.watch<CallProvider>();
    final calls = call.callLogs;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Panggilan',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
        toolbarHeight: 64,
        titleSpacing: 20,
        actions: [
          if (calls.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded),
              tooltip: 'Hapus riwayat',
              onPressed: _clear,
            ),
        ],
      ),
      body: call.loadingCalls && calls.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : calls.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.call_outlined, size: 56, color: palette.muted),
                      const SizedBox(height: 12),
                      Text('Belum ada panggilan',
                          style:
                              TextStyle(color: palette.muted, fontSize: 15)),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: () => context.read<CallProvider>().loadCalls(),
                  child: ListView.separated(
                    itemCount: calls.length,
                    separatorBuilder: (_, _) => Padding(
                      padding: const EdgeInsets.only(left: 84),
                      child: Divider(height: 1, color: palette.cardBorder),
                    ),
                    itemBuilder: (_, i) => _tile(calls[i], myId, palette),
                  ),
                ),
    );
  }

  Widget _tile(CallLog c, String myId, AppPalette palette) {
    final other = c.other(myId);
    final outgoing = c.outgoing(myId);
    final missed = c.status == 'MISSED' ||
        c.status == 'REJECTED' ||
        (c.status == 'CANCELED' && !outgoing);

    IconData icon;
    if (missed) {
      icon = outgoing
          ? Icons.call_missed_outgoing_rounded
          : Icons.call_missed_rounded;
    } else {
      icon = outgoing ? Icons.call_made_rounded : Icons.call_received_rounded;
    }
    final iconColor = missed ? const Color(0xFFEF4444) : const Color(0xFF22C55E);

    String label;
    switch (c.status) {
      case 'COMPLETED':
        label = '${outgoing ? 'Keluar' : 'Masuk'} · ${_dur(c.durationSec)}';
        break;
      case 'REJECTED':
        label = outgoing ? 'Ditolak' : 'Panggilan ditolak';
        break;
      case 'CANCELED':
        label = outgoing ? 'Dibatalkan' : 'Tak terjawab';
        break;
      default:
        label = outgoing ? 'Tidak dijawab' : 'Tak terjawab';
    }

    return ListTile(
      leading: Avatar(url: other.avatarUrl, name: other.displayName, radius: 24),
      title: Text(
        other.displayName,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          color: missed ? const Color(0xFFEF4444) : null,
        ),
      ),
      subtitle: Row(
        children: [
          Icon(icon, size: 15, color: iconColor),
          const SizedBox(width: 5),
          Expanded(
            child: Text(
              '$label · ${_time(c.createdAt)}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
          ),
        ],
      ),
      trailing: IconButton(
        icon: Icon(Icons.call_rounded,
            color: Theme.of(context).colorScheme.primary),
        onPressed: () => context
            .read<CallProvider>()
            .startCallUser(other, conversationId: c.conversationId),
      ),
    );
  }
}
