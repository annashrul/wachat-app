import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../../providers/auth_provider.dart';
import '../../services/api_client.dart';
import '../../services/auth_service.dart';
import '../../theme.dart';

/// "Perangkat tertaut" — daftar sesi perangkat & cabut (logout jarak jauh).
class LinkedDevicesScreen extends StatefulWidget {
  const LinkedDevicesScreen({super.key});

  @override
  State<LinkedDevicesScreen> createState() => _LinkedDevicesScreenState();
}

class _LinkedDevicesScreenState extends State<LinkedDevicesScreen> {
  List<DeviceSession> _devices = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<AuthProvider>().listDevices();
      if (mounted) setState(() => _devices = list);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _revoke(DeviceSession d) async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(d.current ? 'Keluar dari perangkat ini?' : 'Keluarkan perangkat?'),
        content: Text(d.current
            ? 'Anda akan keluar dari akun di perangkat ini.'
            : 'Perangkat "${d.label}" akan keluar dari akun Anda.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Keluarkan')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await auth.revokeDevice(d.id);
      if (d.current) {
        await auth.logout(); // cabut sesi sendiri → keluar
        return;
      }
      messenger.showSnackBar(
          SnackBar(content: Text('${d.label} dikeluarkan')));
      _load();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  IconData _icon(String platform) {
    switch (platform) {
      case 'web':
        return Icons.language_rounded;
      case 'android':
        return Icons.phone_android_rounded;
      case 'ios':
        return Icons.phone_iphone_rounded;
      case 'desktop':
        return Icons.computer_rounded;
      default:
        return Icons.devices_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Perangkat tertaut')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Text(
                      'Akun Anda aktif di ${_devices.length} perangkat. '
                      'Ketuk untuk mengeluarkan.',
                      style: TextStyle(color: palette.muted),
                    ),
                  ),
                  for (final d in _devices)
                    ListTile(
                      leading: CircleAvatar(
                        backgroundColor:
                            Theme.of(context).colorScheme.primaryContainer,
                        child: Icon(_icon(d.platform),
                            color:
                                Theme.of(context).colorScheme.onPrimaryContainer),
                      ),
                      title: Text(d.label +
                          (d.current ? ' (perangkat ini)' : '')),
                      subtitle: Text(
                        d.lastActiveAt != null
                            ? 'Terakhir aktif: ${DateFormat('d MMM, HH:mm').format(d.lastActiveAt!.toLocal())}'
                            : d.platform,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.logout_rounded),
                        tooltip: 'Keluarkan',
                        onPressed: () => _revoke(d),
                      ),
                    ),
                  if (_devices.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(32),
                      child: Center(
                        child: Text('Tidak ada perangkat lain',
                            style: TextStyle(color: palette.muted)),
                      ),
                    ),
                ],
              ),
      ),
    );
  }
}
