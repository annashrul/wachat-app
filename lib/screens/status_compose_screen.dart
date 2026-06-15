import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../services/status_service.dart';

class StatusComposeScreen extends StatefulWidget {
  final XFile? image; // null = mode teks
  const StatusComposeScreen({super.key, this.image});

  @override
  State<StatusComposeScreen> createState() => _StatusComposeScreenState();
}

class _StatusComposeScreenState extends State<StatusComposeScreen> {
  final _service = StatusService();
  final _ctrl = TextEditingController();
  bool _sending = false;
  int _colorIndex = 0;

  static const _colors = [
    Color(0xFF075E54),
    Color(0xFF128C7E),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFB91C1C),
    Color(0xFFD97706),
    Color(0xFF1F2937),
  ];

  bool get _isText => widget.image == null;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<void> _send() async {
    if (_isText && _ctrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    try {
      if (_isText) {
        await _service.create(
          type: 'TEXT',
          text: _ctrl.text.trim(),
          bgColor: _hex(_colors[_colorIndex]),
        );
      } else {
        final bytes = await widget.image!.readAsBytes();
        final url = await _service.uploadImage(bytes, widget.image!.name);
        await _service.create(
          type: 'IMAGE',
          mediaUrl: url,
          caption: _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim(),
        );
      }
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bg = _isText ? _colors[_colorIndex] : Colors.black;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(_isText ? 'Status teks' : 'Pratinjau',
            style: const TextStyle(color: Colors.white)),
        actions: [
          if (_isText)
            IconButton(
              tooltip: 'Ganti warna',
              icon: const Icon(Icons.palette_rounded, color: Colors.white),
              onPressed: () => setState(
                  () => _colorIndex = (_colorIndex + 1) % _colors.length),
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _isText
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Center(
                      child: TextField(
                        controller: _ctrl,
                        autofocus: true,
                        maxLines: null,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w600),
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Ketik status…',
                          hintStyle: TextStyle(color: Colors.white60),
                        ),
                      ),
                    ),
                  )
                : Center(
                    child: Image.network(widget.image!.path,
                        fit: BoxFit.contain,
                        errorBuilder: (_, _, _) => FutureBuilder(
                              future: widget.image!.readAsBytes(),
                              builder: (_, snap) => snap.hasData
                                  ? Image.memory(snap.data!,
                                      fit: BoxFit.contain)
                                  : const SizedBox(),
                            )),
                  ),
          ),
          // Bilah caption (gambar) + tombol kirim
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
                  if (!_isText)
                    Expanded(
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14),
                        decoration: BoxDecoration(
                          color: Colors.white24,
                          borderRadius: BorderRadius.circular(24),
                        ),
                        child: TextField(
                          controller: _ctrl,
                          style: const TextStyle(color: Colors.white),
                          decoration: const InputDecoration(
                            border: InputBorder.none,
                            hintText: 'Tambah keterangan…',
                            hintStyle: TextStyle(color: Colors.white70),
                          ),
                        ),
                      ),
                    )
                  else
                    const Spacer(),
                  const SizedBox(width: 10),
                  GestureDetector(
                    onTap: _sending ? null : _send,
                    child: Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        color: Theme.of(context).colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(15),
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white),
                            )
                          : const Icon(Icons.send_rounded,
                              color: Colors.white),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
