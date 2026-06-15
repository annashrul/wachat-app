import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import '../services/api_client.dart';
import '../services/status_service.dart';

/// Compose status: teks, audio (musik), atau media (gambar/video, bisa banyak).
class StatusComposeScreen extends StatefulWidget {
  final List<XFile>? media; // gambar/video (boleh lebih dari satu)
  final XFile? audio; // file audio/musik
  const StatusComposeScreen({super.key, this.media, this.audio});

  @override
  State<StatusComposeScreen> createState() => _StatusComposeScreenState();
}

class _StatusComposeScreenState extends State<StatusComposeScreen> {
  final _service = StatusService();
  final _ctrl = TextEditingController();
  final _page = PageController();
  bool _sending = false;
  int _colorIndex = 0;
  int _current = 0;

  static const _colors = [
    Color(0xFF075E54),
    Color(0xFF128C7E),
    Color(0xFF2563EB),
    Color(0xFF7C3AED),
    Color(0xFFB91C1C),
    Color(0xFFD97706),
    Color(0xFF1F2937),
  ];

  bool get _isText => widget.media == null && widget.audio == null;
  bool get _isAudio => widget.audio != null;

  static bool _isVideo(String name) {
    final n = name.toLowerCase();
    return n.endsWith('.mp4') ||
        n.endsWith('.mov') ||
        n.endsWith('.webm') ||
        n.endsWith('.mkv') ||
        n.endsWith('.avi') ||
        n.endsWith('.3gp') ||
        n.endsWith('.m4v');
  }

  static String _mimeFor(String name) {
    final n = name.toLowerCase();
    if (n.endsWith('.mp4') || n.endsWith('.m4v')) return 'video/mp4';
    if (n.endsWith('.mov')) return 'video/quicktime';
    if (n.endsWith('.webm')) return 'video/webm';
    if (n.endsWith('.mkv')) return 'video/x-matroska';
    if (n.endsWith('.3gp')) return 'video/3gpp';
    if (n.endsWith('.avi')) return 'video/x-msvideo';
    if (n.endsWith('.mp3')) return 'audio/mpeg';
    if (n.endsWith('.m4a')) return 'audio/mp4';
    if (n.endsWith('.aac')) return 'audio/aac';
    if (n.endsWith('.wav')) return 'audio/wav';
    if (n.endsWith('.ogg')) return 'audio/ogg';
    if (n.endsWith('.png')) return 'image/png';
    if (n.endsWith('.webp')) return 'image/webp';
    if (n.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _page.dispose();
    super.dispose();
  }

  String _hex(Color c) =>
      '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0')}';

  Future<void> _send() async {
    if (_isText && _ctrl.text.trim().isEmpty) return;
    setState(() => _sending = true);
    final messenger = ScaffoldMessenger.of(context);
    final nav = Navigator.of(context);
    final caption = _ctrl.text.trim().isEmpty ? null : _ctrl.text.trim();
    try {
      if (_isText) {
        await _service.create(
          type: 'TEXT',
          text: _ctrl.text.trim(),
          bgColor: _hex(_colors[_colorIndex]),
        );
      } else if (_isAudio) {
        final f = widget.audio!;
        final url = await _service.uploadMedia(
            await f.readAsBytes(), f.name,
            mime: _mimeFor(f.name));
        await _service.create(
          type: 'AUDIO',
          mediaUrl: url,
          caption: caption,
          bgColor: _hex(_colors[_colorIndex]),
        );
      } else {
        // Banyak media → satu status per item.
        for (final f in widget.media!) {
          final url = await _service.uploadMedia(
              await f.readAsBytes(), f.name,
              mime: _mimeFor(f.name));
          await _service.create(
            type: _isVideo(f.name) ? 'VIDEO' : 'IMAGE',
            mediaUrl: url,
            caption: caption,
          );
        }
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
    final bg = (_isText || _isAudio) ? _colors[_colorIndex] : Colors.black;
    final count = widget.media?.length ?? 0;
    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          _isText
              ? 'Status teks'
              : _isAudio
                  ? 'Status musik'
                  : (count > 1 ? 'Pratinjau ($count)' : 'Pratinjau'),
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          if (_isText || _isAudio)
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
          Expanded(child: _preview()),
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

  Widget _preview() {
    if (_isText) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(
          child: TextField(
            controller: _ctrl,
            autofocus: true,
            maxLines: null,
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 26, fontWeight: FontWeight.w600),
            decoration: const InputDecoration(
              border: InputBorder.none,
              hintText: 'Ketik status…',
              hintStyle: TextStyle(color: Colors.white60),
            ),
          ),
        ),
      );
    }
    if (_isAudio) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note_rounded, color: Colors.white, size: 90),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(widget.audio!.name,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
    }
    // Media (gambar/video), bisa banyak → PageView.
    final items = widget.media!;
    return Column(
      children: [
        Expanded(
          child: PageView.builder(
            controller: _page,
            itemCount: items.length,
            onPageChanged: (i) => setState(() => _current = i),
            itemBuilder: (_, i) => _mediaPreview(items[i]),
          ),
        ),
        if (items.length > 1)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (var i = 0; i < items.length; i++)
                  Container(
                    width: 7,
                    height: 7,
                    margin: const EdgeInsets.symmetric(horizontal: 3),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i == _current ? Colors.white : Colors.white38,
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _mediaPreview(XFile f) {
    if (_isVideo(f.name)) {
      // Pratinjau video: placeholder (video diputar penuh setelah dikirim).
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.play_circle_outline_rounded,
                color: Colors.white, size: 90),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Text(f.name,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      );
    }
    // Gambar: network (web/blob) dengan fallback memory (mobile).
    return Center(
      child: Image.network(
        f.path,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) => FutureBuilder(
          future: f.readAsBytes(),
          builder: (_, snap) => snap.hasData
              ? Image.memory(snap.data!, fit: BoxFit.contain)
              : const SizedBox(),
        ),
      ),
    );
  }
}
