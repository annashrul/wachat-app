import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

/// Editor foto status: gambar/pen, teks, stiker emoji, filter — lalu hasilnya
/// "dibakar" jadi satu gambar PNG (dikembalikan lewat Navigator.pop).
class StatusPhotoEditorScreen extends StatefulWidget {
  final Uint8List source;
  const StatusPhotoEditorScreen({super.key, required this.source});

  @override
  State<StatusPhotoEditorScreen> createState() =>
      _StatusPhotoEditorScreenState();
}

class _Stroke {
  final List<Offset> points;
  final Color color;
  final double width;
  _Stroke(this.color, this.width) : points = [];
}

class _TextItem {
  String text;
  Color color;
  Offset offset;
  double scale = 1;
  _TextItem(this.text, this.color, this.offset);
}

class _StickerItem {
  final String emoji;
  Offset offset;
  double scale = 1;
  _StickerItem(this.emoji, this.offset);
}

class _StatusPhotoEditorScreenState extends State<StatusPhotoEditorScreen> {
  final _key = GlobalKey();
  bool _exporting = false;

  int _filter = 0;
  bool _drawing = false;
  Color _color = Colors.white;
  final List<_Stroke> _strokes = [];
  final List<_TextItem> _texts = [];
  final List<_StickerItem> _stickers = [];

  static const _palette = [
    Colors.white,
    Colors.black,
    Color(0xFFEF4444),
    Color(0xFFF59E0B),
    Color(0xFF22C55E),
    Color(0xFF2563EB),
    Color(0xFF8B5CF6),
    Color(0xFFEC4899),
  ];

  static const _emojis = [
    '😀', '😍', '🔥', '❤️', '👍', '🎉', '😎', '😂',
    '✨', '🥳', '💯', '🙏', '😮', '😢', '⭐', '🌈',
  ];

  // (label, ColorFilter?) — null = tanpa filter.
  static final _filters = <(String, ColorFilter?)>[
    ('Asli', null),
    ('Mono', _matrix([
      0.33, 0.59, 0.11, 0, 0, 0.33, 0.59, 0.11, 0, 0, //
      0.33, 0.59, 0.11, 0, 0, 0, 0, 0, 1, 0,
    ])),
    ('Sepia', _matrix([
      0.39, 0.77, 0.19, 0, 0, 0.35, 0.69, 0.17, 0, 0, //
      0.27, 0.53, 0.13, 0, 0, 0, 0, 0, 1, 0,
    ])),
    ('Cerah', _matrix([
      1.2, 0, 0, 0, 10, 0, 1.2, 0, 0, 10, //
      0, 0, 1.2, 0, 10, 0, 0, 0, 1, 0,
    ])),
    ('Dingin', _matrix([
      1, 0, 0, 0, 0, 0, 1, 0, 0, 0, //
      0, 0, 1.25, 0, 12, 0, 0, 0, 1, 0,
    ])),
    ('Hangat', _matrix([
      1.25, 0, 0, 0, 14, 0, 1.05, 0, 0, 6, //
      0, 0, 0.9, 0, 0, 0, 0, 0, 1, 0,
    ])),
  ];

  static ColorFilter _matrix(List<double> m) => ColorFilter.matrix(m);

  Future<void> _addText() async {
    final screen = MediaQuery.of(context).size;
    final ctrl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tambah teks'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLines: null,
          decoration: const InputDecoration(hintText: 'Tulis sesuatu…'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, ctrl.text.trim()),
              child: const Text('OK')),
        ],
      ),
    );
    if (text != null && text.isNotEmpty) {
      setState(() => _texts.add(_TextItem(
          text, _color, Offset(screen.width / 2 - 40, screen.height / 2))));
    }
  }

  void _addSticker() {
    showModalBottomSheet<void>(
      context: context,
      builder: (_) => GridView.count(
        crossAxisCount: 6,
        padding: const EdgeInsets.all(12),
        children: [
          for (final e in _emojis)
            GestureDetector(
              onTap: () {
                Navigator.pop(context);
                final size = MediaQuery.of(context).size;
                setState(() => _stickers.add(_StickerItem(
                    e, Offset(size.width / 2 - 24, size.height / 2 - 24))));
              },
              child: Center(child: Text(e, style: const TextStyle(fontSize: 30))),
            ),
        ],
      ),
    );
  }

  Future<void> _done() async {
    final nav = Navigator.of(context);
    setState(() => _exporting = true);
    try {
      final boundary =
          _key.currentContext!.findRenderObject() as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2.5);
      final data = await image.toByteData(format: ui.ImageByteFormat.png);
      if (!mounted) return;
      nav.pop(data?.buffer.asUint8List());
    } catch (_) {
      if (mounted) setState(() => _exporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final filter = _filters[_filter].$2;
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          // Kanvas yang diekspor.
          Positioned.fill(
            child: RepaintBoundary(
              key: _key,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Builder(builder: (_) {
                    final img = Image.memory(widget.source, fit: BoxFit.contain);
                    return Center(
                        child:
                            filter == null ? img : ColorFiltered(colorFilter: filter, child: img));
                  }),
                  // Coretan pen.
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(painter: _DrawPainter(_strokes)),
                    ),
                  ),
                  // Teks (geser/cubit saat tidak menggambar).
                  for (final t in _texts) _draggable(t.offset, t.scale,
                      onUpdate: (o, s) => setState(() {
                            t.offset = o;
                            t.scale = s;
                          }),
                      onDelete: () => setState(() => _texts.remove(t)),
                      child: Text(t.text,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                              color: t.color,
                              fontSize: 30,
                              fontWeight: FontWeight.w700,
                              shadows: const [
                                Shadow(blurRadius: 6, color: Colors.black54)
                              ]))),
                  for (final s in _stickers) _draggable(s.offset, s.scale,
                      onUpdate: (o, sc) => setState(() {
                            s.offset = o;
                            s.scale = sc;
                          }),
                      onDelete: () => setState(() => _stickers.remove(s)),
                      child: Text(s.emoji, style: const TextStyle(fontSize: 56))),
                  // Lapisan gambar (di atas) saat mode pen aktif.
                  if (_drawing)
                    Positioned.fill(
                      child: GestureDetector(
                        onPanStart: (d) => setState(() {
                          final st = _Stroke(_color, 5);
                          st.points.add(d.localPosition);
                          _strokes.add(st);
                        }),
                        onPanUpdate: (d) => setState(
                            () => _strokes.last.points.add(d.localPosition)),
                        behavior: HitTestBehavior.opaque,
                      ),
                    ),
                ],
              ),
            ),
          ),
          // Toolbar atas.
          SafeArea(
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.close_rounded, color: Colors.white),
                  onPressed: () => Navigator.of(context).pop(),
                ),
                const Spacer(),
                _tool(Icons.brush_rounded, _drawing,
                    () => setState(() => _drawing = !_drawing)),
                _tool(Icons.title_rounded, false, _addText),
                _tool(Icons.emoji_emotions_rounded, false, _addSticker),
              ],
            ),
          ),
          // Palet warna saat mode pen / setelah menambah teks.
          if (_drawing)
            Positioned(
              right: 8,
              top: 90,
              child: Column(
                children: [
                  for (final c in _palette)
                    GestureDetector(
                      onTap: () => setState(() => _color = c),
                      child: Container(
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: c,
                          shape: BoxShape.circle,
                          border: Border.all(
                              color: _color == c ? Colors.amber : Colors.white,
                              width: _color == c ? 3 : 1.5),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          // Strip filter + tombol kirim.
          Align(
            alignment: Alignment.bottomCenter,
            child: SafeArea(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox(
                    height: 40,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      children: [
                        for (var i = 0; i < _filters.length; i++)
                          GestureDetector(
                            onTap: () => setState(() => _filter = i),
                            child: Container(
                              margin: const EdgeInsets.symmetric(horizontal: 4),
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 12, vertical: 8),
                              decoration: BoxDecoration(
                                color: _filter == i
                                    ? Colors.white
                                    : Colors.white24,
                                borderRadius: BorderRadius.circular(16),
                              ),
                              child: Text(_filters[i].$1,
                                  style: TextStyle(
                                      color: _filter == i
                                          ? Colors.black
                                          : Colors.white,
                                      fontSize: 12)),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        GestureDetector(
                          onTap: _exporting ? null : _done,
                          child: Container(
                            width: 56,
                            height: 56,
                            decoration: BoxDecoration(
                              color: Theme.of(context).colorScheme.primary,
                              shape: BoxShape.circle,
                            ),
                            child: _exporting
                                ? const Padding(
                                    padding: EdgeInsets.all(16),
                                    child: CircularProgressIndicator(
                                        strokeWidth: 2, color: Colors.white),
                                  )
                                : const Icon(Icons.arrow_forward_rounded,
                                    color: Colors.white),
                          ),
                        ),
                      ],
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

  Widget _tool(IconData icon, bool active, VoidCallback onTap) {
    return IconButton(
      icon: Icon(icon, color: active ? Colors.amber : Colors.white),
      onPressed: onTap,
    );
  }

  /// Item (teks/stiker) yang bisa digeser & dicubit (skala). Ketuk dua kali
  /// untuk menghapus. Nonaktif saat mode pen agar tidak bentrok dengan coretan.
  Widget _draggable(
    Offset offset,
    double scale, {
    required void Function(Offset, double) onUpdate,
    required VoidCallback onDelete,
    required Widget child,
  }) {
    double startScale = scale;
    return Positioned(
      left: offset.dx,
      top: offset.dy,
      child: IgnorePointer(
        ignoring: _drawing,
        child: GestureDetector(
          onScaleStart: (_) => startScale = scale,
          onScaleUpdate: (d) => onUpdate(
              offset + d.focalPointDelta, (startScale * d.scale).clamp(0.5, 4)),
          onDoubleTap: onDelete,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.topLeft,
            child: child,
          ),
        ),
      ),
    );
  }
}

class _DrawPainter extends CustomPainter {
  final List<_Stroke> strokes;
  _DrawPainter(this.strokes);

  @override
  void paint(Canvas canvas, Size size) {
    for (final s in strokes) {
      final paint = Paint()
        ..color = s.color
        ..strokeWidth = s.width
        ..strokeCap = StrokeCap.round
        ..style = PaintingStyle.stroke;
      for (var i = 0; i < s.points.length - 1; i++) {
        canvas.drawLine(s.points[i], s.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DrawPainter old) => true;
}
