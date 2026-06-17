import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/message.dart';
import '../theme.dart';
import 'status_tick.dart';
import 'link_preview.dart';
import 'voice_message.dart';

final _urlReg = RegExp(r'(https?:\/\/[^\s]+)');

class MessageBubble extends StatelessWidget {
  final Message message;
  final bool isMine;
  final bool showSender; // tampilkan nama pengirim (grup)
  final MessageStatus? status; // centang (untuk pesan sendiri)
  final String? highlight; // sorot teks saat pencarian
  final bool starred; // pesan diberi bintang
  // Ketuk kutipan reply → lompat ke pesan asli.
  final void Function(String messageId)? onQuoteTap;
  // Ketuk event panggilan → telepon balik.
  final VoidCallback? onCallBack;
  // Ketuk media sekali-lihat → tandai sudah dibuka.
  final void Function(String messageId)? onViewOnce;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMine,
    this.showSender = false,
    this.status,
    this.highlight,
    this.starred = false,
    this.onQuoteTap,
    this.onCallBack,
    this.onViewOnce,
  });

  Widget _highlightedText(Color textColor, String query) {
    final text = message.content ?? '';
    final lower = text.toLowerCase();
    final q = query.toLowerCase();
    final spans = <InlineSpan>[];
    var start = 0;
    var idx = lower.indexOf(q, start);
    while (idx >= 0) {
      if (idx > start) spans.add(TextSpan(text: text.substring(start, idx)));
      spans.add(TextSpan(
        text: text.substring(idx, idx + q.length),
        style: const TextStyle(
          backgroundColor: Color(0xFFFFE08A),
          color: Color(0xFF1A1A1A),
          fontWeight: FontWeight.w700,
        ),
      ));
      start = idx + q.length;
      idx = lower.indexOf(q, start);
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return Text.rich(
      TextSpan(
        style: TextStyle(fontSize: 15, height: 1.3, color: textColor),
        children: spans,
      ),
    );
  }

  String? get _firstUrl =>
      message.type == 'TEXT' && message.content != null && !message.deleted
          ? _urlReg.firstMatch(message.content!)?.group(0)
          : null;

  Widget _linkifiedText(BuildContext context, Color textColor) {
    final scheme = Theme.of(context).colorScheme;
    final base = TextStyle(fontSize: 15, height: 1.3, color: textColor);
    final text = message.content ?? '';
    // Pisahkan URL dulu (URL tidak diformat), sisanya diberi format markdown.
    final spans = <InlineSpan>[];
    var last = 0;
    for (final m in _urlReg.allMatches(text)) {
      if (m.start > last) {
        spans.addAll(_formatSpans(text.substring(last, m.start), base));
      }
      final url = m.group(0)!;
      spans.add(
        TextSpan(
          text: url,
          style: base.copyWith(
            color: scheme.primary,
            decoration: TextDecoration.underline,
            decorationColor: scheme.primary,
          ),
          recognizer: TapGestureRecognizer()..onTap = () => _open(url),
        ),
      );
      last = m.end;
    }
    if (last < text.length) {
      spans.addAll(_formatSpans(text.substring(last), base));
    }
    return Text.rich(TextSpan(style: base, children: spans));
  }

  /// Parser format ala WhatsApp: *tebal* _miring_ ~coret~ `monospace`.
  /// Mendukung nested (kecuali monospace yang literal).
  static List<InlineSpan> _formatSpans(String text, TextStyle base) {
    final spans = <InlineSpan>[];
    final buf = StringBuffer();
    void flush() {
      if (buf.isNotEmpty) {
        spans.add(TextSpan(text: buf.toString(), style: base));
        buf.clear();
      }
    }

    var i = 0;
    while (i < text.length) {
      final c = text[i];
      // Monospace inline: `kode` (isi literal, tak diformat lagi).
      if (c == '`') {
        final end = text.indexOf('`', i + 1);
        if (end > i + 1) {
          flush();
          spans.add(TextSpan(
            text: text.substring(i + 1, end),
            style: base.copyWith(
              fontFamily: 'monospace',
              fontFeatures: const [],
            ),
          ));
          i = end + 1;
          continue;
        }
      }
      if (c == '*' || c == '_' || c == '~') {
        final end = text.indexOf(c, i + 1);
        // Butuh isi tak kosong & tak diawali/diakhiri spasi (ala WhatsApp).
        if (end > i + 1 &&
            text[i + 1] != ' ' &&
            text[end - 1] != ' ') {
          final inner = text.substring(i + 1, end);
          final style = c == '*'
              ? base.copyWith(fontWeight: FontWeight.bold)
              : c == '_'
                  ? base.copyWith(fontStyle: FontStyle.italic)
                  : base.copyWith(decoration: TextDecoration.lineThrough);
          flush();
          spans.addAll(_formatSpans(inner, style)); // nested
          i = end + 1;
          continue;
        }
      }
      buf.write(c);
      i++;
    }
    flush();
    return spans;
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final time = DateFormat('HH:mm').format(message.createdAt);
    // Warna jam/centang menyesuaikan latar gelembung.
    final metaColor =
        isMine ? palette.outgoingText.withValues(alpha: 0.55) : palette.muted;

    // Pesan yang sudah dihapus.
    if (message.deleted) {
      return _deletedBubble(palette, metaColor, time);
    }

    // Event panggilan (ala WhatsApp): ikon telepon + status + durasi.
    if (message.type == 'CALL') {
      return _callBubble(context, palette, time);
    }

    // Stiker: tampil sebagai emoji besar tanpa gelembung.
    if (message.type == 'STICKER') {
      return Align(
        alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          child: Column(
            crossAxisAlignment:
                isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (showSender && !isMine)
                Padding(
                  padding: const EdgeInsets.only(bottom: 2, left: 2),
                  child: Text(
                    message.senderName ?? 'Pengguna',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                      fontSize: 12.5,
                    ),
                  ),
                ),
              Text(
                message.content ?? '🙂',
                style: const TextStyle(fontSize: 64),
              ),
              Padding(
                padding: const EdgeInsets.only(top: 2, left: 2, right: 2),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      time,
                      style: TextStyle(fontSize: 10.5, color: palette.muted),
                    ),
                    if (isMine && status != null) ...[
                      const SizedBox(width: 4),
                      statusTick(status!,
                          normal: palette.muted, read: scheme.primary),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    const radius = Radius.circular(18);

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.76,
        ),
        decoration: BoxDecoration(
          color: isMine ? palette.outgoingBubble : palette.incomingBubble,
          borderRadius: BorderRadius.only(
            topLeft: radius,
            topRight: radius,
            bottomLeft: Radius.circular(isMine ? 18 : 4),
            bottomRight: Radius.circular(isMine ? 4 : 18),
          ),
          border: isMine
              ? null
              : Border.all(color: palette.cardBorder, width: 1),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            if (showSender && !isMine)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Text(
                  message.senderName ?? 'Pengguna',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: Theme.of(context).colorScheme.primary,
                    fontSize: 12.5,
                  ),
                ),
              ),
            if (message.forwarded)
              Padding(
                padding: const EdgeInsets.only(bottom: 3),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.shortcut_rounded, size: 14, color: metaColor),
                    const SizedBox(width: 4),
                    Text(
                      'Diteruskan',
                      style: TextStyle(
                        fontSize: 12,
                        fontStyle: FontStyle.italic,
                        color: metaColor,
                      ),
                    ),
                  ],
                ),
              ),
            if (message.statusRef != null) _statusQuote(context, palette),
            if (message.replyTo != null) _replyQuote(context, palette),
            if (_firstUrl != null)
              LinkPreviewCard(url: _firstUrl!, mine: isMine),
            _buildContent(context, palette),
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (starred) ...[
                  Icon(Icons.star_rounded, size: 13, color: metaColor),
                  const SizedBox(width: 4),
                ],
                Text(
                  time,
                  style: TextStyle(fontSize: 10.5, color: metaColor),
                ),
                if (isMine && status != null) ...[
                  const SizedBox(width: 4),
                  statusTick(status!, normal: metaColor, read: scheme.primary),
                ],
              ],
            ),
          ],
        ),
          ),
          if (message.reactions.isNotEmpty) _reactionsBar(context),
        ],
      ),
    );
  }

  /// Pil reaksi (emoji + jumlah) yang menempel di bawah gelembung.
  Widget _reactionsBar(BuildContext context) {
    final counts = message.reactionCounts;
    if (counts.isEmpty) return const SizedBox.shrink();
    final palette = AppPalette.of(context);
    final emojis = counts.keys.take(3).join();
    final total = message.reactions.length;
    return Transform.translate(
      offset: const Offset(0, -8),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 14),
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
        decoration: BoxDecoration(
          color: palette.incomingBubble,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emojis, style: const TextStyle(fontSize: 13)),
            if (total > 1) ...[
              const SizedBox(width: 3),
              Text(
                '$total',
                style: TextStyle(fontSize: 12, color: palette.muted),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _callBubble(BuildContext context, AppPalette palette, String time) {
    final scheme = Theme.of(context).colorScheme;
    final textColor = isMine ? palette.outgoingText : palette.incomingText;
    // content = "STATUS|durasiDetik"
    final parts = (message.content ?? '').split('|');
    final status = parts.isNotEmpty ? parts[0] : 'COMPLETED';
    final dur = parts.length > 1 ? (int.tryParse(parts[1]) ?? 0) : 0;
    final missed = status == 'MISSED' ||
        status == 'REJECTED' ||
        (status == 'CANCELED' && !isMine);

    IconData icon;
    if (missed) {
      icon = isMine
          ? Icons.call_missed_outgoing_rounded
          : Icons.call_missed_rounded;
    } else {
      icon = isMine ? Icons.call_made_rounded : Icons.call_received_rounded;
    }
    final iconColor =
        missed ? const Color(0xFFEF4444) : const Color(0xFF22C55E);

    String sub;
    if (missed) {
      sub = isMine ? 'Tidak dijawab' : 'Panggilan tak terjawab';
    } else {
      final m = (dur ~/ 60).toString();
      final s = (dur % 60).toString().padLeft(2, '0');
      sub = '$time · $m:$s';
    }

    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 10, 14, 10),
        decoration: BoxDecoration(
          color: isMine ? palette.outgoingBubble : palette.incomingBubble,
          borderRadius: BorderRadius.circular(16),
          border: isMine ? null : Border.all(color: palette.cardBorder),
        ),
        child: InkWell(
          onTap: onCallBack,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 22, color: iconColor),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text('Panggilan suara',
                      style: TextStyle(
                          color: textColor, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  Text(sub,
                      style: TextStyle(
                          fontSize: 12,
                          color: missed
                              ? const Color(0xFFEF4444)
                              : textColor.withValues(alpha: 0.7))),
                ],
              ),
              const SizedBox(width: 14),
              Icon(Icons.call_rounded, size: 20, color: scheme.primary),
            ],
          ),
        ),
      ),
    );
  }

  Widget _deletedBubble(AppPalette palette, Color metaColor, String time) {
    return Align(
      alignment: isMine ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 3),
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
        decoration: BoxDecoration(
          color: isMine ? palette.outgoingBubble : palette.incomingBubble,
          borderRadius: BorderRadius.circular(14),
          border: isMine ? null : Border.all(color: palette.cardBorder),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.block_rounded, size: 15, color: metaColor),
            const SizedBox(width: 6),
            Text(
              'Pesan ini dihapus',
              style: TextStyle(
                fontStyle: FontStyle.italic,
                color: metaColor,
                fontSize: 14,
              ),
            ),
            const SizedBox(width: 8),
            Text(time, style: TextStyle(fontSize: 10.5, color: metaColor)),
          ],
        ),
      ),
    );
  }

  Widget _replyQuote(BuildContext context, AppPalette palette) {
    final r = message.replyTo!;
    final scheme = Theme.of(context).colorScheme;
    final textColor = isMine ? palette.outgoingText : palette.incomingText;
    String snippet;
    if (r.deleted) {
      snippet = 'Pesan dihapus';
    } else {
      switch (r.type) {
        case 'IMAGE':
          snippet = '📷 Foto';
          break;
        case 'FILE':
          snippet = '📎 ${r.mediaName ?? 'File'}';
          break;
        case 'STICKER':
          snippet = '${r.content ?? '🙂'} Stiker';
          break;
        case 'VOICE':
          snippet = '🎤 Pesan suara';
          break;
        case 'CALL':
          snippet = '📞 Panggilan suara';
          break;
        default:
          snippet = r.content ?? '';
      }
    }
    return GestureDetector(
      onTap: onQuoteTap == null ? null : () => onQuoteTap!(r.id),
      child: Container(
      margin: const EdgeInsets.only(bottom: 5),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: scheme.primary),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 8, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      r.senderName,
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 12,
                        color: scheme.primary,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      snippet,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: textColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      ),
    );
  }

  /// Kutipan status yang dibalas (mini thumbnail ala WhatsApp).
  Widget _statusQuote(BuildContext context, AppPalette palette) {
    final s = message.statusRef!;
    final scheme = Theme.of(context).colorScheme;
    final textColor = isMine ? palette.outgoingText : palette.incomingText;

    String label;
    Widget thumb;
    switch (s.type) {
      case 'VIDEO':
        label = '📹 Video';
        thumb = _quadThumb(
          child: s.mediaUrl != null
              ? CachedNetworkImage(
                  imageUrl: s.mediaUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.videocam, size: 18),
                )
              : const Icon(Icons.videocam, size: 18),
          overlay: const Icon(Icons.play_arrow, color: Colors.white, size: 16),
        );
        break;
      case 'AUDIO':
        label = '🎵 Audio';
        thumb = _quadThumb(
          color: scheme.primary,
          child: const Icon(Icons.music_note, color: Colors.white, size: 18),
        );
        break;
      case 'TEXT':
        label = s.text != null && s.text!.trim().isNotEmpty
            ? s.text!
            : 'Status teks';
        thumb = _quadThumb(
          color: _parseColor(s.bgColor) ?? scheme.primary,
          child: const Icon(Icons.title, color: Colors.white, size: 18),
        );
        break;
      default: // IMAGE
        label = '📷 Foto';
        thumb = _quadThumb(
          child: s.mediaUrl != null
              ? CachedNetworkImage(
                  imageUrl: s.mediaUrl!,
                  fit: BoxFit.cover,
                  errorWidget: (_, _, _) =>
                      const Icon(Icons.image, size: 18),
                )
              : const Icon(Icons.image, size: 18),
        );
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 5),
      // Lebar mengikuti konten (tidak full), dengan batas atas agar label
      // panjang tetap ringkas — jadi gelembung tidak melebar penuh.
      constraints: const BoxConstraints(maxWidth: 230),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(8),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 3, color: scheme.primary),
            Flexible(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 5, 6, 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.auto_awesome,
                            size: 12, color: scheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          'Status',
                          style: TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                            color: scheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 1),
                    Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12.5,
                        color: textColor.withValues(alpha: 0.85),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(4),
              child: thumb,
            ),
          ],
        ),
      ),
    );
  }

  Widget _quadThumb({Widget? child, Color? color, Widget? overlay}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: Container(
        width: 38,
        height: 38,
        color: color ?? Colors.black12,
        alignment: Alignment.center,
        child: Stack(
          fit: StackFit.expand,
          children: [
            ?child,
            if (overlay != null) Center(child: overlay),
          ],
        ),
      ),
    );
  }

  /// Konten media "sekali lihat".
  Widget _viewOnceContent(Color textColor) {
    final seen = message.viewOnceSeen;
    final canOpen = !seen && !isMine && message.mediaUrl != null;
    final label = seen
        ? 'Dibuka'
        : isMine
            ? 'Foto • sekali lihat'
            : 'Buka sekali lihat';
    final body = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: textColor, width: 1.5),
          ),
          child: Icon(
            seen ? Icons.check_rounded : Icons.looks_one_rounded,
            size: 18,
            color: textColor,
          ),
        ),
        const SizedBox(width: 8),
        Text(label,
            style: TextStyle(
                color: textColor,
                fontStyle: seen ? FontStyle.italic : FontStyle.normal)),
      ],
    );
    if (!canOpen) return body;
    return GestureDetector(
      onTap: () {
        _open(message.mediaUrl); // buka gambar
        onViewOnce?.call(message.id); // tandai sudah dibuka
      },
      child: body,
    );
  }

  /// Konten pesan lokasi: peta statis (OSM) + tombol buka di aplikasi peta.
  Widget _locationContent(BuildContext context, Color textColor) {
    final parts = (message.content ?? '').split(',');
    final lat = parts.isNotEmpty ? double.tryParse(parts[0].trim()) : null;
    final lng = parts.length > 1 ? double.tryParse(parts[1].trim()) : null;
    if (lat == null || lng == null) {
      return Text('📍 Lokasi', style: TextStyle(color: textColor));
    }
    final staticMap =
        'https://staticmap.openstreetmap.de/staticmap.php?center=$lat,$lng'
        '&zoom=15&size=260x150&markers=$lat,$lng,red-pushpin';
    final mapsUrl =
        'https://www.google.com/maps/search/?api=1&query=$lat,$lng';
    return GestureDetector(
      onTap: () => _open(mapsUrl),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            CachedNetworkImage(
              imageUrl: staticMap,
              width: 260,
              height: 150,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 260,
                height: 150,
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, _, _) => Container(
                width: 260,
                height: 150,
                color: Colors.black12,
                alignment: Alignment.center,
                child: const Icon(Icons.map_rounded, size: 40),
              ),
            ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_on_rounded,
                      size: 16, color: textColor),
                  const SizedBox(width: 4),
                  Text('Lokasi — buka peta',
                      style: TextStyle(color: textColor, fontSize: 13)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Color? _parseColor(String? hex) {
    if (hex == null) return null;
    var h = hex.replaceAll('#', '').trim();
    if (h.length == 6) h = 'FF$h';
    final v = int.tryParse(h, radix: 16);
    return v == null ? null : Color(v);
  }

  Widget _buildContent(BuildContext context, AppPalette palette) {
    final textColor = isMine ? palette.outgoingText : palette.incomingText;
    switch (message.type) {
      case 'LOCATION':
        return _locationContent(context, textColor);
      case 'IMAGE':
        if (message.viewOnce) return _viewOnceContent(textColor);
        return ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: GestureDetector(
            onTap: () => _open(message.mediaUrl),
            child: CachedNetworkImage(
              imageUrl: message.mediaUrl ?? '',
              width: 230,
              fit: BoxFit.cover,
              placeholder: (_, _) => Container(
                width: 230,
                height: 170,
                color: Colors.black12,
                child: const Center(child: CircularProgressIndicator()),
              ),
              errorWidget: (_, _, _) => const Icon(Icons.broken_image),
            ),
          ),
        );
      case 'FILE':
        return InkWell(
          onTap: () => _open(message.mediaUrl),
          borderRadius: BorderRadius.circular(10),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: (isMine ? Colors.white : textColor).withValues(
                    alpha: 0.15,
                  ),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Icons.insert_drive_file_rounded,
                  color: textColor,
                  size: 22,
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message.mediaName ?? 'File',
                  style: TextStyle(
                    color: textColor,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        );
      case 'VOICE':
        final scheme = Theme.of(context).colorScheme;
        return VoiceMessage(
          url: message.mediaUrl ?? '',
          durationSeconds: int.tryParse(message.content ?? '') ?? 0,
          accent: scheme.primary,
          trackColor: textColor.withValues(alpha: 0.25),
          textColor: textColor,
          seed: message.id.hashCode,
        );
      default:
        if (highlight != null && highlight!.trim().isNotEmpty) {
          return _highlightedText(textColor, highlight!.trim());
        }
        return _linkifiedText(context, textColor);
    }
  }

  Future<void> _open(String? url) async {
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
