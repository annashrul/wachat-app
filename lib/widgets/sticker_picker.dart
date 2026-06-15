import 'package:flutter/material.dart';
import '../theme.dart';

/// Daftar stiker (emoji besar). Ringan, tanpa aset/gambar eksternal.
const List<String> kStickers = [
  '😀', '😂', '🤣', '😍', '😎', '🥳', '😭', '😡',
  '👍', '👎', '👏', '🙏', '💪', '🤝', '👌', '✌️',
  '❤️', '🔥', '🎉', '✅', '❌', '⭐', '💯', '👀',
  '😴', '🤔', '😅', '😘', '🤗', '😇', '🥺', '😱',
  '🍕', '☕', '🎂', '⚽', '🚀', '🌈', '🌙', '💀',
];

/// Bottom sheet pemilih stiker. Panggil [onSelected] saat stiker dipilih.
class StickerPicker extends StatelessWidget {
  final void Function(String sticker) onSelected;
  const StickerPicker({super.key, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(8, 4, 8, 10),
              child: Text(
                'Stiker',
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: palette.muted,
                ),
              ),
            ),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 320),
              child: GridView.builder(
                shrinkWrap: true,
                gridDelegate:
                    const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 5,
                  mainAxisSpacing: 4,
                  crossAxisSpacing: 4,
                ),
                itemCount: kStickers.length,
                itemBuilder: (_, i) {
                  final s = kStickers[i];
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () {
                      Navigator.pop(context);
                      onSelected(s);
                    },
                    child: Center(
                      child: Text(s, style: const TextStyle(fontSize: 40)),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}
