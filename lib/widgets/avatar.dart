import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Avatar minimalis: foto kalau ada, kalau tidak inisial di atas
/// satu warna solid yang ditentukan dari nama (deterministik).
class Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;
  // Cincin status (ala WhatsApp). null = tanpa cincin.
  final Color? ringColor;
  // Cincin status tersegmentasi: satu busur per status. true = sudah dilihat.
  // Diprioritaskan di atas [ringColor].
  final List<bool>? ringSegments;
  const Avatar({
    super.key,
    this.url,
    required this.name,
    this.radius = 24,
    this.ringColor,
    this.ringSegments,
  });

  static const _colors = <Color>[
    Color(0xFF2563EB), // blue
    Color(0xFF0EA5E9), // sky
    Color(0xFF14B8A6), // teal
    Color(0xFF22C55E), // green
    Color(0xFF8B5CF6), // violet
    Color(0xFFEC4899), // pink
    Color(0xFFF59E0B), // amber
    Color(0xFFEF4444), // red
  ];

  Color _colorFor(String s) {
    if (s.isEmpty) return _colors[0];
    var hash = 0;
    for (final c in s.codeUnits) {
      hash = (hash * 31 + c) & 0x7fffffff;
    }
    return _colors[hash % _colors.length];
  }

  @override
  Widget build(BuildContext context) {
    final size = radius * 2;
    Widget inner;
    if (url != null && url!.isNotEmpty) {
      inner = CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black12,
        backgroundImage: CachedNetworkImageProvider(url!),
      );
    } else {
      final initial =
          name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
      inner = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: _colorFor(name),
        ),
        alignment: Alignment.center,
        child: Text(
          initial,
          style: TextStyle(
            color: Colors.white,
            fontSize: radius * 0.82,
            fontWeight: FontWeight.w700,
          ),
        ),
      );
    }
    final segs = ringSegments;
    if (segs != null && segs.isNotEmpty) {
      const stroke = 2.8;
      const gap = 3.0; // jarak cincin ke avatar
      final outer = size + (stroke + gap) * 2;
      return SizedBox(
        width: outer,
        height: outer,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomPaint(
              size: Size(outer, outer),
              painter: _SegmentRingPainter(seen: segs, stroke: stroke),
            ),
            inner,
          ],
        ),
      );
    }
    if (ringColor == null) return inner;
    // Cincin solid + sedikit jarak (gap) ala WhatsApp.
    return Container(
      padding: const EdgeInsets.all(2.5),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: ringColor!, width: 2.2),
      ),
      child: inner,
    );
  }
}

/// Menggambar cincin status: 1 busur per status, dengan celah pemisah.
/// Busur hijau = belum dilihat, abu = sudah dilihat (ala WhatsApp).
class _SegmentRingPainter extends CustomPainter {
  final List<bool> seen;
  final double stroke;
  static const _unseen = Color(0xFF22C55E);
  static const _seen = Color(0xFF9CA3AF);

  _SegmentRingPainter({required this.seen, required this.stroke});

  @override
  void paint(Canvas canvas, Size size) {
    final n = seen.length;
    final r = (size.width - stroke) / 2;
    final center = Offset(size.width / 2, size.height / 2);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    if (n == 1) {
      p.color = seen[0] ? _seen : _unseen;
      canvas.drawCircle(center, r, p);
      return;
    }
    final rect = Rect.fromCircle(center: center, radius: r);
    const gap = 0.22; // radian celah antar segmen
    final sweep = (2 * math.pi - gap * n) / n;
    var start = -math.pi / 2 + gap / 2;
    for (var i = 0; i < n; i++) {
      p.color = seen[i] ? _seen : _unseen;
      canvas.drawArc(rect, start, sweep, false, p);
      start += sweep + gap;
    }
  }

  @override
  bool shouldRepaint(_SegmentRingPainter old) =>
      old.seen.length != seen.length ||
      !_listEq(old.seen, seen) ||
      old.stroke != stroke;

  static bool _listEq(List<bool> a, List<bool> b) {
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
