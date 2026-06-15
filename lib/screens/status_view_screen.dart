import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import '../models/status.dart';
import '../models/user.dart';
import '../providers/status_provider.dart';
import '../services/status_service.dart';
import '../widgets/avatar.dart';

/// Satu "cerita" status milik seorang user.
class StatusStory {
  final AppUser user;
  final List<StatusItem> statuses;
  final bool isMine;
  StatusStory({required this.user, required this.statuses, this.isMine = false});
}

class StatusViewScreen extends StatefulWidget {
  final List<StatusStory> stories;
  final int startIndex;
  const StatusViewScreen({
    super.key,
    required this.stories,
    this.startIndex = 0,
  });

  @override
  State<StatusViewScreen> createState() => _StatusViewScreenState();
}

class _StatusViewScreenState extends State<StatusViewScreen>
    with SingleTickerProviderStateMixin {
  final _service = StatusService();
  late final AnimationController _ctrl;
  late int _s; // index cerita (user)
  int _i = 0; // index status dalam cerita

  static const _dur = Duration(seconds: 5);

  StatusStory get _story => widget.stories[_s];
  StatusItem get _status => _story.statuses[_i];

  @override
  void initState() {
    super.initState();
    _s = widget.startIndex;
    _ctrl = AnimationController(vsync: this, duration: _dur)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      })
      ..addListener(() => setState(() {}));
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  void _start() {
    if (!_story.isMine) _service.markViewed(_status.id);
    _ctrl
      ..reset()
      ..forward();
  }

  void _next() {
    if (_i < _story.statuses.length - 1) {
      setState(() => _i++);
      _start();
    } else if (_s < widget.stories.length - 1) {
      setState(() {
        _s++;
        _i = 0;
      });
      _start();
    } else {
      Navigator.of(context).pop();
    }
  }

  void _prev() {
    if (_i > 0) {
      setState(() => _i--);
      _start();
    } else if (_s > 0) {
      setState(() {
        _s--;
        _i = _story.statuses.length - 1;
      });
      _start();
    } else {
      _start(); // ulang dari awal
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
    final id = _status.id;
    try {
      await context.read<StatusProvider>().deleteStatus(id);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop(true);
  }

  void _showViewers() {
    _ctrl.stop(); // jeda saat melihat daftar
    final id = _status.id;
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (_) => FutureBuilder<List<AppUser>>(
        future: _service.getViewers(id),
        builder: (_, snap) {
          final viewers = snap.data ?? [];
          if (snap.connectionState == ConnectionState.waiting) {
            return const SizedBox(
                height: 160,
                child: Center(child: CircularProgressIndicator()));
          }
          if (viewers.isEmpty) {
            return const SizedBox(
              height: 160,
              child: Center(child: Text('Belum ada yang melihat')),
            );
          }
          return ListView(
            shrinkWrap: true,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 4, 18, 10),
                child: Row(
                  children: [
                    const Icon(Icons.visibility_rounded, size: 18),
                    const SizedBox(width: 8),
                    Text('Dilihat oleh ${viewers.length}',
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              ...viewers.map((u) => ListTile(
                    leading: Avatar(url: u.avatarUrl, name: u.displayName, radius: 20),
                    title: Text(u.displayName),
                  )),
            ],
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) _ctrl.forward(); // lanjutkan setelah sheet ditutup
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final isText = s.type == 'TEXT';
    final liveCount =
        context.watch<StatusProvider>().viewCountById(s.id) ?? s.viewCount;
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
                            child:
                                CircularProgressIndicator(color: Colors.white)),
                        errorWidget: (_, _, _) => const Icon(Icons.broken_image,
                            color: Colors.white54, size: 48),
                      ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    child: Row(
                      children: [
                        for (var k = 0; k < _story.statuses.length; k++)
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
                                valueColor:
                                    const AlwaysStoppedAnimation(Colors.white),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  ListTile(
                    leading: Avatar(
                        url: _story.user.avatarUrl,
                        name: _story.user.displayName,
                        radius: 18),
                    title: Text(
                      _story.isMine ? 'Status saya' : _story.user.displayName,
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.w700),
                    ),
                    subtitle: Text(_ago(s.createdAt),
                        style: const TextStyle(color: Colors.white70)),
                    trailing: IconButton(
                      icon:
                          const Icon(Icons.close_rounded, color: Colors.white),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ],
              ),
            ),
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
                      if (_story.isMine)
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Ketuk untuk melihat siapa saja yang melihat.
                            InkWell(
                              onTap: _showViewers,
                              borderRadius: BorderRadius.circular(8),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 6, vertical: 6),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.visibility_rounded,
                                        color: Colors.white70, size: 18),
                                    const SizedBox(width: 6),
                                    Text('$liveCount dilihat',
                                        style: const TextStyle(
                                            color: Colors.white70)),
                                  ],
                                ),
                              ),
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
