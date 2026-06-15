import 'package:flutter/material.dart';
import '../theme.dart';

/// Gelembung "sedang mengetik" dengan 3 titik beranimasi (ala WhatsApp).
/// [name] diisi untuk grup → menampilkan nama yang sedang mengetik.
class TypingIndicator extends StatefulWidget {
  final String? name;
  const TypingIndicator({super.key, this.name});

  @override
  State<TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: palette.incomingBubble,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(18),
          ),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.name != null && widget.name!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(
                  widget.name!,
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12,
                  ),
                ),
              ),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: List.generate(3, (i) => _dot(i, palette.muted)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dot(int index, Color color) {
    return AnimatedBuilder(
      animation: _c,
      builder: (context, _) {
        // Tiap titik naik-turun bergantian.
        final t = (_c.value + index * 0.2) % 1.0;
        final scale = 0.6 + 0.4 * (1 - (2 * t - 1).abs());
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2.5),
          child: Transform.translate(
            offset: Offset(0, -3 * (1 - (2 * t - 1).abs())),
            child: Container(
              width: 8 * scale + 2,
              height: 8 * scale + 2,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
              ),
            ),
          ),
        );
      },
    );
  }
}
