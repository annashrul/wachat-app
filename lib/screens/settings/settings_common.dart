import 'package:flutter/material.dart';
import '../../providers/settings_provider.dart';
import '../../theme.dart';

/// Judul kecil pemisah grup pengaturan.
class SettingsSectionHeader extends StatelessWidget {
  final String title;
  const SettingsSectionHeader(this.title, {super.key});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          color: scheme.primary,
          fontSize: 12,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.6,
        ),
      ),
    );
  }
}

/// Baris pengaturan yang membuka layar/aksi lain.
class SettingsNavTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final Widget? trailing;
  final Color? color;
  final VoidCallback? onTap;

  const SettingsNavTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.trailing,
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final fg = color;
    return ListTile(
      leading: Icon(icon, color: fg ?? palette.muted),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w600,
          fontSize: 15.5,
          color: fg,
        ),
      ),
      subtitle: (subtitle == null || subtitle!.isEmpty)
          ? null
          : Text(
              subtitle!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: palette.muted, fontSize: 12.5),
            ),
      trailing: trailing,
      onTap: onTap,
    );
  }
}

/// Baris pengaturan dengan saklar on/off.
class SettingsSwitchTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;

  const SettingsSwitchTile({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    required this.value,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final enabled = onChanged != null;
    return SwitchListTile(
      secondary: Icon(icon,
          color: enabled ? palette.muted : palette.muted.withValues(alpha: 0.4)),
      title: Text(title,
          style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15.5)),
      subtitle: (subtitle == null || subtitle!.isEmpty)
          ? null
          : Text(subtitle!,
              style: TextStyle(color: palette.muted, fontSize: 12.5)),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Pilih audiens (Semua / Kontak / Tidak ada) lewat bottom sheet.
Future<void> pickAudience(
  BuildContext context, {
  required String title,
  required Audience current,
  required ValueChanged<Audience> onSelected,
}) {
  final scheme = Theme.of(context).colorScheme;
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (sheetCtx) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(title,
                style: const TextStyle(
                    fontWeight: FontWeight.w700, fontSize: 16)),
          ),
          for (final a in Audience.values)
            ListTile(
              leading: Icon(
                switch (a) {
                  Audience.everyone => Icons.public_rounded,
                  Audience.contacts => Icons.contacts_rounded,
                  Audience.nobody => Icons.lock_rounded,
                },
                color: a == current ? scheme.primary : null,
              ),
              title: Text(a.label),
              trailing: a == current
                  ? Icon(Icons.check_circle_rounded, color: scheme.primary)
                  : null,
              onTap: () {
                onSelected(a);
                Navigator.pop(sheetCtx);
              },
            ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}
