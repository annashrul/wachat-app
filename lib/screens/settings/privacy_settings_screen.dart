import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
import '../../providers/auth_provider.dart';
import '../../providers/chat_provider.dart';
import '../../providers/settings_provider.dart';
import '../../services/api_client.dart';
import '../../theme.dart';
import '../../widgets/avatar.dart';
import 'settings_common.dart';

class PrivacySettingsScreen extends StatelessWidget {
  const PrivacySettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Privasi')),
      body: ListView(
        children: [
          const SettingsSectionHeader('Siapa yang dapat melihat'),
          SettingsNavTile(
            icon: Icons.donut_large_rounded,
            title: 'Status',
            subtitle: settings.statusAudience.label,
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => pickAudience(
              context,
              title: 'Siapa yang melihat status saya',
              current: settings.statusAudience,
              onSelected: settings.setStatusAudience,
            ),
          ),
          SettingsNavTile(
            icon: Icons.access_time_rounded,
            title: 'Terakhir dilihat',
            subtitle: settings.lastSeenAudience.label,
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => pickAudience(
              context,
              title: 'Siapa yang melihat "terakhir dilihat"',
              current: settings.lastSeenAudience,
              onSelected: settings.setLastSeenAudience,
            ),
          ),
          SettingsNavTile(
            icon: Icons.account_circle_rounded,
            title: 'Foto profil',
            subtitle: settings.profilePhotoAudience.label,
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => pickAudience(
              context,
              title: 'Siapa yang melihat foto profil',
              current: settings.profilePhotoAudience,
              onSelected: settings.setProfilePhotoAudience,
            ),
          ),
          SettingsNavTile(
            icon: Icons.info_outline_rounded,
            title: 'Tentang',
            subtitle: settings.aboutAudience.label,
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => pickAudience(
              context,
              title: 'Siapa yang melihat "tentang"',
              current: settings.aboutAudience,
              onSelected: settings.setAboutAudience,
            ),
          ),

          const SettingsSectionHeader('Pesan'),
          SettingsSwitchTile(
            icon: Icons.done_all_rounded,
            title: 'Laporan dibaca',
            subtitle:
                'Bila dimatikan, Anda tak mengirim/menerima tanda dibaca. '
                'Tanda dibaca grup tetap aktif.',
            value: settings.readReceipts,
            onChanged: settings.setReadReceipts,
          ),

          const SettingsSectionHeader('Keamanan'),
          Builder(builder: (context) {
            final on =
                context.watch<AuthProvider>().user?.twoFactorEnabled ?? false;
            return SettingsNavTile(
              icon: Icons.shield_rounded,
              title: 'Verifikasi dua langkah',
              subtitle: on ? 'Aktif' : 'Nonaktif',
              trailing:
                  Icon(Icons.chevron_right_rounded, color: palette.muted),
              onTap: () => _twoFactorFlow(context, on),
            );
          }),

          const SettingsSectionHeader('Kontak'),
          SettingsNavTile(
            icon: Icons.block_rounded,
            title: 'Kontak diblokir',
            subtitle: 'Kelola pengguna yang Anda blokir',
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const BlockedContactsScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _twoFactorFlow(BuildContext context, bool currentlyOn) async {
    final auth = context.read<AuthProvider>();
    final messenger = ScaffoldMessenger.of(context);
    if (!currentlyOn) {
      // Aktifkan: minta PIN baru + konfirmasi.
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => const _PinSetupDialog(
          title: 'Aktifkan verifikasi dua langkah',
          subtitle: 'Buat PIN 6 digit. Diminta saat login di perangkat baru.',
          confirm: true,
        ),
      );
      if (pin == null) return;
      try {
        await auth.enableTwoFactor(pin);
        messenger.showSnackBar(
            const SnackBar(content: Text('Verifikasi dua langkah aktif')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    } else {
      // Nonaktifkan: minta PIN saat ini.
      final pin = await showDialog<String>(
        context: context,
        builder: (_) => const _PinSetupDialog(
          title: 'Nonaktifkan verifikasi dua langkah',
          subtitle: 'Masukkan PIN Anda untuk menonaktifkan.',
        ),
      );
      if (pin == null) return;
      try {
        await auth.disableTwoFactor(pin);
        messenger.showSnackBar(
            const SnackBar(content: Text('Verifikasi dua langkah dinonaktifkan')));
      } catch (e) {
        messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      }
    }
  }
}

/// Dialog buat/masukkan PIN 6 digit untuk verifikasi dua langkah.
class _PinSetupDialog extends StatefulWidget {
  const _PinSetupDialog({
    required this.title,
    required this.subtitle,
    this.confirm = false,
  });
  final String title;
  final String subtitle;
  final bool confirm;

  @override
  State<_PinSetupDialog> createState() => _PinSetupDialogState();
}

class _PinSetupDialogState extends State<_PinSetupDialog> {
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
    if (!RegExp(r'^\d{4,6}$').hasMatch(p)) {
      setState(() => _error = 'PIN harus 4–6 digit angka');
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
    Widget field(TextEditingController c, String label, bool autofocus) =>
        TextField(
          controller: c,
          autofocus: autofocus,
          obscureText: true,
          keyboardType: TextInputType.number,
          maxLength: 6,
          decoration: InputDecoration(
            labelText: label,
            counterText: '',
            border: const OutlineInputBorder(),
          ),
        );
    return AlertDialog(
      title: Text(widget.title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(widget.subtitle),
          const SizedBox(height: 16),
          field(_pin, 'PIN', true),
          if (widget.confirm) ...[
            const SizedBox(height: 12),
            field(_pin2, 'Konfirmasi PIN', false),
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

/// Daftar kontak yang diblokir + tombol buka blokir.
class BlockedContactsScreen extends StatefulWidget {
  const BlockedContactsScreen({super.key});

  @override
  State<BlockedContactsScreen> createState() => _BlockedContactsScreenState();
}

class _BlockedContactsScreenState extends State<BlockedContactsScreen> {
  List<AppUser> _blocked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final list = await context.read<ChatProvider>().service.blockedUsers();
      if (mounted) setState(() => _blocked = list);
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

  Future<void> _unblock(AppUser u) async {
    try {
      await context.read<ChatProvider>().service.unblockUser(u.id);
      if (mounted) {
        setState(() => _blocked.removeWhere((b) => b.id == u.id));
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${u.displayName} dibuka blokirnya')),
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

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Kontak diblokir')),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _blocked.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.block_rounded,
                          size: 56, color: palette.muted),
                      const SizedBox(height: 12),
                      Text('Tidak ada kontak yang diblokir',
                          style: TextStyle(color: palette.muted)),
                    ],
                  ),
                )
              : ListView.builder(
                  itemCount: _blocked.length,
                  itemBuilder: (_, i) {
                    final u = _blocked[i];
                    return ListTile(
                      leading: Avatar(
                          url: u.avatarUrl, name: u.displayName, radius: 22),
                      title: Text(u.displayName),
                      subtitle: Text(u.phone),
                      trailing: TextButton(
                        onPressed: () => _unblock(u),
                        child: const Text('Buka blokir'),
                      ),
                    );
                  },
                ),
    );
  }
}
