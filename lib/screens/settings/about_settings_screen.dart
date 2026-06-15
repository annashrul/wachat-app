import 'package:flutter/material.dart';
import '../../theme.dart';
import 'settings_common.dart';

const String kAppVersion = '1.0.0';

class AboutSettingsScreen extends StatelessWidget {
  const AboutSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);

    return Scaffold(
      appBar: AppBar(title: const Text('Tentang')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Column(
              children: [
                Container(
                  width: 76,
                  height: 76,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded,
                      color: Colors.white, size: 40),
                ),
                const SizedBox(height: 14),
                const Text('WAChat',
                    style:
                        TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                const SizedBox(height: 4),
                Text('Versi $kAppVersion',
                    style: TextStyle(color: palette.muted, fontSize: 13)),
              ],
            ),
          ),
          const SizedBox(height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Text(
              'Aplikasi chat real-time mirip WhatsApp yang dibuat dengan '
              'Flutter (Android & Web) dan NestJS. Mendukung chat pribadi & '
              'grup, media, status, panggilan suara, dan notifikasi.',
              textAlign: TextAlign.center,
              style: TextStyle(
                  color: palette.muted, fontSize: 13.5, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),

          const SettingsSectionHeader('Informasi'),
          SettingsNavTile(
            icon: Icons.tag_rounded,
            title: 'Versi aplikasi',
            subtitle: kAppVersion,
            trailing: const SizedBox.shrink(),
          ),
          SettingsNavTile(
            icon: Icons.code_rounded,
            title: 'Dibuat dengan',
            subtitle: 'Flutter • NestJS • Supabase',
            trailing: const SizedBox.shrink(),
          ),
          SettingsNavTile(
            icon: Icons.article_outlined,
            title: 'Lisensi sumber terbuka',
            subtitle: 'Lihat lisensi pustaka pihak ketiga',
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => showLicensePage(
              context: context,
              applicationName: 'WAChat',
              applicationVersion: kAppVersion,
              applicationIcon: Padding(
                padding: const EdgeInsets.all(8),
                child: Container(
                  width: 44,
                  height: 44,
                  decoration: BoxDecoration(
                    color: scheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.chat_bubble_rounded,
                      color: Colors.white),
                ),
              ),
            ),
          ),
          const SizedBox(height: 28),
          Center(
            child: Text('© 2026 WAChat',
                style: TextStyle(color: palette.muted, fontSize: 12)),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
