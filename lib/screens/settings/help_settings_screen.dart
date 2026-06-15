import 'package:flutter/material.dart';
import '../../theme.dart';
import 'settings_common.dart';
import 'about_settings_screen.dart';

class HelpSettingsScreen extends StatelessWidget {
  const HelpSettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Bantuan')),
      body: ListView(
        children: [
          const SettingsSectionHeader('Dukungan'),
          SettingsNavTile(
            icon: Icons.help_center_rounded,
            title: 'Pusat bantuan',
            subtitle: 'Pertanyaan umum & panduan',
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => _openFaq(context),
          ),
          SettingsNavTile(
            icon: Icons.support_agent_rounded,
            title: 'Hubungi kami',
            subtitle: 'Kirim masukan atau laporkan masalah',
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => _contactUs(context),
          ),

          const SettingsSectionHeader('Legal'),
          SettingsNavTile(
            icon: Icons.description_rounded,
            title: 'Ketentuan layanan',
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => _legal(context, 'Ketentuan Layanan',
                'Dengan menggunakan WAChat, Anda setuju memakai aplikasi '
                'secara wajar dan tidak menyalahgunakannya untuk mengganggu '
                'pengguna lain. Layanan disediakan "sebagaimana adanya".'),
          ),
          SettingsNavTile(
            icon: Icons.privacy_tip_rounded,
            title: 'Kebijakan privasi',
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => _legal(context, 'Kebijakan Privasi',
                'Kami hanya menyimpan data yang diperlukan agar layanan '
                'berjalan: profil, kontak, dan pesan Anda. Data tidak dijual '
                'ke pihak ketiga. Anda dapat menghapus akun kapan saja dari '
                'menu Akun.'),
          ),

          const SettingsSectionHeader('Aplikasi'),
          SettingsNavTile(
            icon: Icons.info_rounded,
            title: 'Tentang WAChat',
            trailing: Icon(Icons.chevron_right_rounded, color: palette.muted),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const AboutSettingsScreen()),
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  void _openFaq(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.9,
        builder: (_, controller) => ListView(
          controller: controller,
          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
          children: const [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 8),
              child: Text('Pertanyaan umum',
                  style:
                      TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
            ),
            _Faq(
              q: 'Bagaimana cara memulai chat baru?',
              a: 'Tekan tombol pensil/chat di kanan bawah halaman utama, '
                  'cari kontak, lalu mulai mengetik.',
            ),
            _Faq(
              q: 'Bagaimana cara membuat grup?',
              a: 'Di layar "Chat Baru" tekan ikon grup di kanan atas, pilih '
                  'anggota, beri nama grup, lalu tekan Buat.',
            ),
            _Faq(
              q: 'Siapa yang bisa melihat status saya?',
              a: 'Atur di Pengaturan → Privasi → Status. Anda bisa memilih '
                  'Semua orang, Kontak saya, atau Tidak ada.',
            ),
            _Faq(
              q: 'Bagaimana cara memblokir seseorang?',
              a: 'Buka profil kontak lalu pilih Blokir, atau kelola daftar '
                  'di Pengaturan → Privasi → Kontak diblokir.',
            ),
            _Faq(
              q: 'Bagaimana mengubah atau menghapus akun?',
              a: 'Buka Pengaturan → Akun. Di sana ada Ganti password dan '
                  'Hapus akun permanen.',
            ),
          ],
        ),
      ),
    );
  }

  void _contactUs(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hubungi kami'),
        content: const Text(
          'Punya pertanyaan atau menemukan masalah?\n\n'
          'Email: support@wachat.app\n\n'
          'Kami akan membalas secepatnya.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Tutup'),
          ),
        ],
      ),
    );
  }

  void _legal(BuildContext context, String title, String body) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => Scaffold(
          appBar: AppBar(title: Text(title)),
          body: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Text(body, style: const TextStyle(fontSize: 14.5, height: 1.6)),
          ),
        ),
      ),
    );
  }
}

class _Faq extends StatelessWidget {
  final String q;
  final String a;
  const _Faq({required this.q, required this.a});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Theme(
      data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
      child: ExpansionTile(
        tilePadding: EdgeInsets.zero,
        childrenPadding: const EdgeInsets.only(bottom: 12),
        title: Text(q,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 14.5)),
        children: [
          Align(
            alignment: Alignment.centerLeft,
            child: Text(a,
                style: TextStyle(
                    color: palette.muted, fontSize: 13.5, height: 1.5)),
          ),
        ],
      ),
    );
  }
}
