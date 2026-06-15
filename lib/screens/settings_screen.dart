import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'profile_edit_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final auth = context.watch<AuthProvider>();
    final settings = context.watch<SettingsProvider>();
    final palette = AppPalette.of(context);
    final user = auth.user;

    return Scaffold(
      appBar: AppBar(title: const Text('Setelan')),
      body: ListView(
        children: [
          // Header profil.
          InkWell(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const ProfileEditScreen()),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 16, 16),
              child: Row(
                children: [
                  Avatar(
                    url: user?.avatarUrl,
                    name: user?.displayName ?? '?',
                    radius: 32,
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName ?? '',
                          style: const TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          user?.about ?? '',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: palette.muted, fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.qr_code_rounded, color: palette.muted),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: palette.cardBorder),
          const SizedBox(height: 8),

          _item(context, Icons.key_rounded, 'Akun',
              'Nomor: ${user?.phone ?? '-'}', () {
            _info(context, 'Akun', 'Nomor telepon: ${user?.phone ?? '-'}');
          }),
          _item(context, Icons.lock_rounded, 'Privasi',
              'Terakhir dilihat, blokir', () {
            _soon(context);
          }),
          _item(context, Icons.chat_rounded, 'Chat',
              'Tema: ${settings.themeLabel}', () {
            _chooseTheme(context, settings);
          }),
          _item(context, Icons.notifications_rounded, 'Notifikasi',
              'Nada, getaran', () {
            _soon(context);
          }),
          _item(context, Icons.data_usage_rounded, 'Penyimpanan & data',
              'Pemakaian jaringan', () {
            _soon(context);
          }),
          _item(context, Icons.help_rounded, 'Bantuan',
              'Pusat bantuan, tentang aplikasi', () {
            showAboutDialog(
              context: context,
              applicationName: 'WAChat',
              applicationVersion: '1.0.0',
              applicationIcon: Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.chat_bubble_rounded,
                    color: Colors.white),
              ),
              children: const [
                Text('Aplikasi chat real-time dibuat dengan Flutter & NestJS.'),
              ],
            );
          }),
          _item(context, Icons.group_add_rounded, 'Undang teman', '', () {
            _soon(context);
          }),
          const SizedBox(height: 8),
          Divider(height: 1, color: palette.cardBorder),
          ListTile(
            leading: Icon(Icons.logout_rounded,
                color: Theme.of(context).colorScheme.error),
            title: Text('Keluar',
                style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                    fontWeight: FontWeight.w600)),
            onTap: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('Keluar?'),
                  content: const Text('Anda akan keluar dari akun ini.'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Batal'),
                    ),
                    TextButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Keluar'),
                    ),
                  ],
                ),
              );
              if (ok == true && context.mounted) {
                context.read<ChatProvider>().reset();
                await context.read<AuthProvider>().logout();
              }
            },
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Widget _item(BuildContext context, IconData icon, String title,
      String subtitle, VoidCallback onTap) {
    final palette = AppPalette.of(context);
    return ListTile(
      leading: Icon(icon, color: palette.muted),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: 12.5)),
      onTap: onTap,
    );
  }

  void _soon(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Segera hadir')),
    );
  }

  void _info(BuildContext context, String title, String body) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _chooseTheme(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Tema',
                  style:
                      TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            _themeOption(context, settings, ThemeMode.light, 'Terang',
                Icons.light_mode_rounded),
            _themeOption(context, settings, ThemeMode.dark, 'Gelap',
                Icons.dark_mode_rounded),
            _themeOption(context, settings, ThemeMode.system, 'Ikuti sistem',
                Icons.brightness_auto_rounded),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _themeOption(BuildContext context, SettingsProvider settings,
      ThemeMode mode, String label, IconData icon) {
    final selected = settings.themeMode == mode;
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: selected ? scheme.primary : null),
      title: Text(label),
      trailing: selected
          ? Icon(Icons.check_circle_rounded, color: scheme.primary)
          : null,
      onTap: () {
        settings.setThemeMode(mode);
        Navigator.pop(context);
      },
    );
  }
}
