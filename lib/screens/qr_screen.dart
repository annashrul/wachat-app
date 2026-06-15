import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/chat_service.dart';
import '../theme.dart';
import '../widgets/avatar.dart';

/// Kode QR kontak: tab "Kode saya" (tampilkan QR) + "Pindai" (scan kamera).
class QrScreen extends StatefulWidget {
  const QrScreen({super.key});

  @override
  State<QrScreen> createState() => _QrScreenState();
}

class _QrScreenState extends State<QrScreen> {
  final _service = ChatService();
  late final Future<({String link, AppUser user})> _myQr = _service.myQr();
  final _scanner = MobileScannerController();
  bool _handled = false;

  @override
  void dispose() {
    _scanner.dispose();
    super.dispose();
  }

  Future<void> _onDetect(BarcodeCapture capture) async {
    if (_handled || capture.barcodes.isEmpty) return;
    final code = capture.barcodes.first.rawValue;
    if (code == null || code.isEmpty) return;
    _handled = true;
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      final user = await _service.scanContact(code);
      messenger.showSnackBar(
          SnackBar(content: Text('${user.displayName} ditambahkan ke kontak')));
      nav.pop(true);
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
      _handled = false; // izinkan coba lagi
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return DefaultTabController(
      length: 2,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('Kode QR'),
          bottom: const TabBar(
            tabs: [Tab(text: 'Kode saya'), Tab(text: 'Pindai')],
          ),
        ),
        body: TabBarView(
          children: [
            // --- Kode QR saya ---
            FutureBuilder<({String link, AppUser user})>(
              future: _myQr,
              builder: (_, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snap.hasError) {
                  return Center(
                      child: Text(ApiClient.errorMessage(snap.error!),
                          style: TextStyle(color: palette.muted)));
                }
                final d = snap.data!;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Avatar(
                          url: d.user.avatarUrl,
                          name: d.user.displayName,
                          radius: 40),
                      const SizedBox(height: 12),
                      Text(d.user.displayName,
                          style: const TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      Text(d.user.phone,
                          style: TextStyle(color: palette.muted)),
                      const SizedBox(height: 24),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: QrImageView(
                          data: d.link,
                          size: 240,
                          backgroundColor: Colors.white,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text('Pindai kode ini untuk menambahkan saya',
                          style: TextStyle(color: palette.muted, fontSize: 13)),
                    ],
                  ),
                );
              },
            ),
            // --- Pindai kode ---
            Stack(
              children: [
                MobileScanner(controller: _scanner, onDetect: _onDetect),
                Center(
                  child: Container(
                    width: 240,
                    height: 240,
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.white, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                  ),
                ),
                const Align(
                  alignment: Alignment.bottomCenter,
                  child: Padding(
                    padding: EdgeInsets.all(24),
                    child: Text(
                      'Arahkan ke kode QR kontak',
                      style: TextStyle(
                          color: Colors.white,
                          backgroundColor: Colors.black54),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
