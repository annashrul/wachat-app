import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../providers/settings_provider.dart';
import 'settings_common.dart';

class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SettingsProvider>();
    // Detail bunyi/getar/pratinjau hanya relevan bila notifikasi pesan aktif.
    final msgOn = s.messageNotifications;

    return Scaffold(
      appBar: AppBar(title: const Text('Notifikasi')),
      body: ListView(
        children: [
          const SettingsSectionHeader('Pesan'),
          SettingsSwitchTile(
            icon: Icons.notifications_active_rounded,
            title: 'Notifikasi pesan',
            subtitle: 'Tampilkan notifikasi untuk pesan masuk',
            value: s.messageNotifications,
            onChanged: s.setMessageNotifications,
          ),
          SettingsSwitchTile(
            icon: Icons.volume_up_rounded,
            title: 'Suara',
            value: s.notificationSound,
            onChanged: msgOn ? s.setNotificationSound : null,
          ),
          SettingsSwitchTile(
            icon: Icons.vibration_rounded,
            title: 'Getar',
            value: s.notificationVibrate,
            onChanged: msgOn ? s.setNotificationVibrate : null,
          ),
          SettingsSwitchTile(
            icon: Icons.remove_red_eye_rounded,
            title: 'Tampilkan pratinjau',
            subtitle: 'Perlihatkan isi pesan di notifikasi',
            value: s.showPreview,
            onChanged: msgOn ? s.setShowPreview : null,
          ),

          const SettingsSectionHeader('Grup'),
          SettingsSwitchTile(
            icon: Icons.groups_rounded,
            title: 'Notifikasi grup',
            subtitle: 'Notifikasi untuk pesan grup',
            value: s.groupNotifications,
            onChanged: s.setGroupNotifications,
          ),

          const SettingsSectionHeader('Panggilan & status'),
          SettingsSwitchTile(
            icon: Icons.call_rounded,
            title: 'Notifikasi panggilan',
            subtitle: 'Pemberitahuan panggilan masuk',
            value: s.callNotifications,
            onChanged: s.setCallNotifications,
          ),
          SettingsSwitchTile(
            icon: Icons.donut_large_rounded,
            title: 'Notifikasi status',
            subtitle: 'Saat kontak memperbarui status',
            value: s.statusNotifications,
            onChanged: s.setStatusNotifications,
          ),

          const SettingsSectionHeader('Dalam aplikasi'),
          SettingsSwitchTile(
            icon: Icons.notifications_none_rounded,
            title: 'Suara dalam aplikasi',
            subtitle: 'Nada saat aplikasi sedang dibuka',
            value: s.inAppSounds,
            onChanged: s.setInAppSounds,
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}
