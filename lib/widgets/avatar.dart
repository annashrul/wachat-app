import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';

/// Avatar minimalis: foto kalau ada, kalau tidak inisial di atas
/// satu warna solid yang ditentukan dari nama (deterministik).
class Avatar extends StatelessWidget {
  final String? url;
  final String name;
  final double radius;
  const Avatar({super.key, this.url, required this.name, this.radius = 24});

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
    if (url != null && url!.isNotEmpty) {
      return CircleAvatar(
        radius: radius,
        backgroundColor: Colors.black12,
        backgroundImage: CachedNetworkImageProvider(url!),
      );
    }
    final initial = name.isNotEmpty ? name.characters.first.toUpperCase() : '?';
    return Container(
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
}
