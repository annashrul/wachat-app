import 'package:flutter/material.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/chat_service.dart';
import '../theme.dart';

/// Kartu preview link (judul, deskripsi, gambar, domain) dari metadata OG.
class LinkPreviewCard extends StatefulWidget {
  final String url;
  final bool mine;
  const LinkPreviewCard({super.key, required this.url, required this.mine});

  // Cache hasil agar tidak fetch ulang tiap rebuild/scroll.
  static final Map<String, Future<Map<String, dynamic>>> _cache = {};

  @override
  State<LinkPreviewCard> createState() => _LinkPreviewCardState();
}

class _LinkPreviewCardState extends State<LinkPreviewCard> {
  late final Future<Map<String, dynamic>> _future;

  @override
  void initState() {
    super.initState();
    _future = LinkPreviewCard._cache.putIfAbsent(
      widget.url,
      () => ChatService().linkPreview(widget.url),
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    return FutureBuilder<Map<String, dynamic>>(
      future: _future,
      builder: (context, snap) {
        if (!snap.hasData) return const SizedBox.shrink();
        final m = snap.data!;
        final title = m['title'] as String?;
        final desc = m['description'] as String?;
        final image = m['image'] as String?;
        final site = m['siteName'] as String?;
        // Tidak ada metadata berarti tak perlu kartu.
        if ((title == null || title.isEmpty) &&
            (image == null || image.isEmpty)) {
          return const SizedBox.shrink();
        }
        return InkWell(
          onTap: () {
            final uri = Uri.tryParse(widget.url);
            if (uri != null) {
              launchUrl(uri, mode: LaunchMode.externalApplication);
            }
          },
          child: Container(
            margin: const EdgeInsets.only(bottom: 6),
            width: 240,
            decoration: BoxDecoration(
              color: Colors.black.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(10),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (image != null && image.isNotEmpty)
                  CachedNetworkImage(
                    imageUrl: image,
                    width: 240,
                    height: 130,
                    fit: BoxFit.cover,
                    errorWidget: (_, _, _) => const SizedBox.shrink(),
                  ),
                Padding(
                  padding: const EdgeInsets.all(8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (site != null && site.isNotEmpty)
                        Text(
                          site.toUpperCase(),
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w700,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                      if (title != null && title.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 13.5,
                              color: widget.mine
                                  ? palette.outgoingText
                                  : palette.incomingText,
                            ),
                          ),
                        ),
                      if (desc != null && desc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(
                            desc,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 12,
                              color: palette.muted,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
