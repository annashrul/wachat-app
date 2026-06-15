import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../models/user.dart';
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
