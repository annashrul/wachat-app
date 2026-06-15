import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import '../services/api_client.dart';
import '../services/status_service.dart';

/// Langkah akhir membuat status: pratinjau + keterangan + tambah musik + kirim.
/// Foto: hasil editor (bytes). Video: file mentah (untuk sekarang dikirim apa
/// adanya; editor video server-side menyusul).
class StatusFinalizeScreen extends StatefulWidget {
  final Uint8List? imageBytes;
  final XFile? video;
  const StatusFinalizeScreen({super.key, this.imageBytes, this.video});

  @override
  State<StatusFinalizeScreen> createState() => _StatusFinalizeScreenState();
}

class _StatusFinalizeScreenState extends State<StatusFinalizeScreen> {
  final _service = StatusService();
  final _ctrl = TextEditingController();
  bool _sending = false;
  XFile? _music;

  bool get _isVideo => widget.video != null;

  static String _mime(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.mp4') || n.endsWith('.m4v')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.m4a')) return 'audio/mp4';
    if (n.endsWith('.aac')) return 'audio/aac';
    if (n.endsWith('.wav')) return 'audio/wav';
    if (n.endsWith('.ogg')) return 'audio/ogg';
    return 'application/octet-stream';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _pickMusic() async {
    final res =
        await FilePicker.pickFiles(type: FileType.audio, withData: kIsWeb);
    if (res == null || res.files.isEmpty || !mounted) return;
    final pf = res.files.first;
    setState(() {
      if (kIsWeb) {
        if (pf.bytes != null) {
          _music = XFile.fromData(pf.bytes!, name: pf.name);
        }
      } else if (pf.path != null) {
        _music = XFile(pf.path!);
      }
    });
  }

  Future<void> _send() async {
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final caption = _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim();
    try {
      String? musicUrl;
      if (_music != null) {
        musicUrl = await _service.uploadMedia(
            await _music!.readAsBytes(), _music!.name,
            mime: _mime(_music!.name));
      }
      if (_isVideo) {
        final v = widget.video!;
        final url = await _service.uploadMedia(await v.readAsBytes(), v.name,
            mime: _mime(v.name));
        await _service.create(
            type: 'VIDEO', mediaUrl: url, caption: caption);
      } else {
        final url = await _service.uploadMedia(
            widget.imageBytes!, 'status.jpg',
            mime: 'image/jpeg');
        await _service.create(
          type: 'IMAGE',
          mediaUrl: url,
          musicUrl: musicUrl,
          caption: caption,
        );
      }
      nav.pop(true);
    } catch (e) {
      if (mounted) {
        messenger
            .showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
        setState(() => _sending = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (!_isVideo)
            IconButton(
              tooltip: 'Tambah musik',
              icon: Icon(Icons.music_note_rounded,
                  color: _music != null ? Colors.amber : Colors.white),
              onPressed: _pickMusic,
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: Center(
              child: _isVideo
                  ? const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_outline_rounded,
                            color: Colors.white, size: 90),
                        SizedBox(height: 12),
                        Text('Video siap dikirim',
                            style: TextStyle(color: Colors.white70)),
                      ],
                    )
                  : Image.memory(widget.imageBytes!, fit: BoxFit.contain),
            ),
          ),
          if (_music != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                children: [
                  const Icon(Icons.music_note_rounded,
                      color: Colors.amber, size: 18),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(_music!.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70)),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded,
                        color: Colors.white70, size: 18),
                    onPressed: () => setState(() => _music = null),
                  ),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 6, 12, 12),
              child: Row(
                children: [
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
                  ),
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
                          : const Icon(Icons.send_rounded, color: Colors.white),
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
