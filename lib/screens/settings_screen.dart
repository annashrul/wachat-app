import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/settings_provider.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'profile_edit_screen.dart';
import 'qr_screen.dart';
import 'settings/account_settings_screen.dart';
import 'settings/privacy_settings_screen.dart';
import 'settings/notification_settings_screen.dart';
import 'settings/help_settings_screen.dart';
import 'settings/about_settings_screen.dart';

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
                  IconButton(
                    icon: Icon(Icons.qr_code_rounded, color: palette.muted),
                    tooltip: 'Kode QR',
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const QrScreen()),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Divider(height: 1, color: palette.cardBorder),
          const SizedBox(height: 8),

          // 1. Akun
          _item(context, Icons.key_rounded, 'Akun',
              'Ganti password, hapus akun', () {
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const AccountSettingsScreen()),
            );
          }),

          // 2. Privasi
          _item(context, Icons.lock_rounded, 'Privasi',
              'Penonton status, blokir, terakhir dilihat', () {
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const PrivacySettingsScreen()),
            );
          }),

          // 3. Notifikasi
          _item(context, Icons.notifications_rounded, 'Notifikasi',
              'Pesan, grup, panggilan, nada', () {
            Navigator.of(context).push(
              MaterialPageRoute(
                  builder: (_) => const NotificationSettingsScreen()),
            );
          }),

          // Chat / tema (tetap dipertahankan).
          _item(context, Icons.chat_rounded, 'Chat',
              'Tema: ${settings.themeLabel}', () {
            _chooseTheme(context, settings);
          }),

          // Wallpaper chat
          _item(context, Icons.wallpaper_rounded, 'Wallpaper chat',
              _wallpaperLabel(settings.chatWallpaper), () {
            _chooseWallpaper(context, settings);
          }),

          // 4. Bantuan
          _item(context, Icons.help_rounded, 'Bantuan',
              'Pusat bantuan, hubungi kami, legal', () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const HelpSettingsScreen()),
            );
          }),

          // 5. Tentang
          _item(context, Icons.info_rounded, 'Tentang',
              'Versi aplikasi & lisensi', () {
            Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutSettingsScreen()),
            );
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
      trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
      onTap: onTap,
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

  static const List<String> _wallpaperNames = [
    'Default',
    'Krem',
    'Hijau muda',
    'Biru muda',
    'Pink muda',
    'Ungu muda',
    'Gelap',
    'Gelap kebiruan',
  ];

  String _wallpaperLabel(int index) =>
      (index >= 0 && index < _wallpaperNames.length)
          ? _wallpaperNames[index]
          : 'Default';

  void _chooseWallpaper(BuildContext context, SettingsProvider settings) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) {
        final scheme = Theme.of(context).colorScheme;
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Wallpaper chat',
                      style: TextStyle(
                          fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    for (var i = 0;
                        i < SettingsProvider.chatWallpapers.length;
                        i++)
                      _wallpaperSwatch(context, settings, i, scheme),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _wallpaperSwatch(BuildContext context, SettingsProvider settings,
      int index, ColorScheme scheme) {
    final color = SettingsProvider.chatWallpapers[index];
    final selected = settings.chatWallpaper == index;
    return GestureDetector(
      onTap: () {
        settings.setChatWallpaper(index);
        Navigator.pop(context);
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: color ?? scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: selected ? scheme.primary : scheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: index == 0
                ? Icon(Icons.format_color_reset_rounded,
                    color: scheme.onSurfaceVariant)
                : (selected
                    ? const Icon(Icons.check_rounded, color: Colors.white)
                    : null),
          ),
          const SizedBox(height: 4),
          SizedBox(
            width: 64,
            child: Text(_wallpaperLabel(index),
                textAlign: TextAlign.center,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11)),
          ),
        ],
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
