import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/status.dart';
import '../models/user.dart';
import '../providers/status_provider.dart';
import '../services/status_service.dart';
import '../widgets/avatar.dart';

class StatusViewScreen extends StatefulWidget {
  final AppUser user;
  final List<StatusItem> statuses;
  final bool isMine;
  const StatusViewScreen({
    super.key,
    required this.user,
    required this.statuses,
    this.isMine = false,
  });

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen>
    with SingleTickerProviderStateMixin {
  final _service = StatusService();
  late final AnimationController _ctrl;
  int _i = 0;

  static const _imageDuration = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: _imageDuration)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      })
      ..addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (_i >= widget.statuses.length) return;
    if (!widget.isMine) _service.markViewed(widget.statuses[_i].id);
    _ctrl
      ..reset()
      ..forward();
  }

  void _next() {
    if (_i < widget.statuses.length - 1) {
      setState(() => _i++);
      _start();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _start();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  static String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
    return '${d.inHours} jam lalu';
  }

  Color _parseColor(String? hex) {
    if (hex == null) return const Color(0xFF075E54);
    final h = hex.replaceFirst('#', '');
    final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
    return v == null ? const Color(0xFF075E54) : Color(v);
  }

  Future<void> _deleteCurrent() async {
    final s = widget.statuses[_i];
    try {
      await context.read<StatusProvider>().deleteStatus(s.id);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.statuses[_i];
    final isText = s.type == 'TEXT';
    return Scaffold(
      backgroundColor: isText ? _parseColor(s.bgColor) : Colors.black,
      body: GestureDetector(
        onTapUp: (d) {
          final w = MediaQuery.of(context).size.width;
          if (d.globalPosition.dx < w * 0.33) {
            _prev();
          } else {
            _next();
          }
        },
        child: Stack(
          children: [
            // Konten
            Positioned.fill(
              child: Center(
                child: isText
                    ? Padding(
                        padding: const EdgeInsets.all(32),
                        child: Text(
                          s.text ?? '',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      )
                    : CachedNetworkImage(
                        imageUrl: s.mediaUrl ?? '',
                        fit: BoxFit.contain,
                        placeholder: (_, _) => const Center(
                            child: CircularProgressIndicator(
                                color: Colors.white)),
                        errorWidget: (_, _, _) => const Icon(
                            Icons.broken_image,
                            color: Colors.white54,
                            size: 48),
                      ),
              ),
            ),
            // Header: progress + info
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        for (var k = 0; k < widget.statuses.length; k++)
                          Expanded(
                            child: Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 2),
                              child: LinearProgressIndicator(
                                value: k < _i
                                    ? 1.0
                                    : k == _i
                                        ? _ctrl.value
                                        : 0.0,
                                minHeight: 2.5,
                                backgroundColor: Colors.white38,
                                valueColor: const AlwaysStoppedAnimation(
                                    Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: Avatar(
                        url: widget.user.avatarUrl,
                        name: widget.user.displayName,
                        radius: 18),
                    title: Text(
                      widget.isMine ? 'Status saya' : widget.user.displayName,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_ago(s.createdAt),
                        style: const TextStyle(color: Colors.white70)),
                    trailing: IconButton(
                      icon: const Icon(Icons.close_rounded,
                          color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
            // Caption + (untuk status sendiri) jumlah dilihat & hapus
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (!isText && (s.caption?.isNotEmpty ?? false))
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Text(s.caption!,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.white)),
                        ),
                      if (widget.isMine)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Row(
                              children: [
                                const Icon(Icons.visibility_rounded,
                                    color: Colors.white70, size: 18),
                                const SizedBox(width: 6),
                                Text(
                                    '${context.watch<StatusProvider>().viewCountById(s.id) ?? s.viewCount} dilihat',
                                    style: const TextStyle(
                                        color: Colors.white70)),
                              ],
                            ),
                            TextButton.icon(
                              onPressed: _deleteCurrent,
                              icon: const Icon(Icons.delete_rounded,
                                  color: Colors.white),
                              label: const Text('Hapus',
                                  style: TextStyle(color: Colors.white)),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
