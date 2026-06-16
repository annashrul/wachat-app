import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:video_player/video_player.dart';
import 'package:just_audio/just_audio.dart';
import '../models/status.dart';
import '../models/user.dart';
import '../providers/status_provider.dart';
import '../providers/chat_provider.dart';
import '../services/status_service.dart';
import '../services/api_client.dart';
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
  late final AnimationController _ctrl; // untuk IMAGE/TEXT (durasi tetap)
  VideoPlayerController? _video;
  AudioPlayer? _audio;
  late int _s;
  int _i = 0;
  bool _advanced = false; // cegah maju ganda
  final _replyCtrl = TextEditingController();
  final _replyFocus = FocusNode();
  bool _sendingReply = false;

  static const _staticDur = Duration(seconds: 5);

  StatusStory get _story => widget.stories[_s];
  StatusItem get _status => _story.statuses[_i];

  @override
  void initState() {
    super.initState();
    _s = widget.startIndex;
    _ctrl = AnimationController(vsync: this, duration: _staticDur)
      ..addStatusListener((s) {
        if (s == AnimationStatus.completed) _next();
      })
      ..addListener(() => setState(() {}));
    // Saat mengetik balasan, jeda status agar tidak keburu pindah.
    _replyFocus.addListener(() {
      if (_replyFocus.hasFocus) {
        _pause();
      } else {
        _resume();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  Future<void> _sendReply() async {
    final text = _replyCtrl.text.trim();
    if (text.isEmpty || _sendingReply) return;
    setState(() => _sendingReply = true);
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final userId = _story.user.id;
    try {
      final conv = await chat.service.createDirect(userId);
      // Sertakan konteks status singkat agar penerima paham ini balasan status.
      chat.sendText(conv.id, text);
      _replyCtrl.clear();
      _replyFocus.unfocus();
      messenger.showSnackBar(const SnackBar(content: Text('Balasan terkirim')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _sendingReply = false);
    }
  }

  Future<void> _disposeMedia() async {
    _ctrl.stop();
    final v = _video;
    _video = null;
    if (v != null) {
      v.removeListener(_videoTick);
      await v.dispose();
    }
    final a = _audio;
    _audio = null;
    if (a != null) await a.dispose();
  }

  Future<void> _start() async {
    await _disposeMedia();
    _advanced = false;
    if (!mounted) return;
    final s = _status;
    if (!_story.isMine) _service.markViewed(s.id);

    final hasMusic = s.musicUrl != null && s.musicUrl!.isNotEmpty;
    if (s.type == 'VIDEO') {
      await _startVideo(s);
    } else if (s.type == 'AUDIO') {
      await _startAudio(s.mediaUrl);
    } else if (s.type == 'IMAGE' && hasMusic) {
      setState(() {});
      await _startAudio(s.musicUrl); // foto + musik latar
    } else {
      setState(() {});
      _ctrl
        ..reset()
        ..forward();
    }
  }

  bool get _usesAudio {
    final s = _status;
    return s.type == 'AUDIO' ||
        (s.type == 'IMAGE' && (s.musicUrl?.isNotEmpty ?? false));
  }

  Future<void> _startVideo(StatusItem s) async {
    final c = VideoPlayerController.networkUrl(Uri.parse(s.mediaUrl ?? ''));
    _video = c;
    try {
      await c.initialize();
      if (!identical(_video, c)) return; // sudah pindah status
      c.addListener(_videoTick);
      await c.play();
      if (mounted) setState(() {});
    } catch (_) {
      _next(); // gagal muat → lanjut
    }
  }

  void _videoTick() {
    final c = _video;
    if (c == null || !c.value.isInitialized) return;
    if (mounted) setState(() {});
    final dur = c.value.duration;
    if (dur > Duration.zero && c.value.position >= dur && !_advanced) {
      _advanced = true;
      _next();
    }
  }

  Future<void> _startAudio(String? url) async {
    final p = AudioPlayer();
    _audio = p;
    try {
      await p.setUrl(url ?? '');
      if (!identical(_audio, p)) return;
      p.positionStream.listen((_) {
        if (mounted) setState(() {});
      });
      p.playerStateStream.listen((st) {
        if (st.processingState == ProcessingState.completed && !_advanced) {
          _advanced = true;
          _next();
        }
      });
      await p.play();
      if (mounted) setState(() {});
    } catch (_) {
      _next();
    }
  }

  double _segmentProgress() {
    final s = _status;
    if (s.type == 'VIDEO') {
      final c = _video;
      if (c != null && c.value.isInitialized) {
        final d = c.value.duration.inMilliseconds;
        return d == 0 ? 0 : (c.value.position.inMilliseconds / d).clamp(0, 1);
      }
      return 0;
    }
    if (_usesAudio) {
      final p = _audio;
      final d = p?.duration?.inMilliseconds ?? 0;
      final pos = p?.position.inMilliseconds ?? 0;
      return d == 0 ? 0 : (pos / d).clamp(0, 1);
    }
    return _ctrl.value;
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
      _start();
    }
  }

  void _pause() {
    _ctrl.stop();
    _video?.pause();
    _audio?.pause();
  }

  void _resume() {
    final s = _status;
    if (s.type == 'VIDEO') {
      _video?.play();
    } else if (_usesAudio) {
      _audio?.play();
    } else {
      _ctrl.forward();
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    _video?.dispose();
    _audio?.dispose();
    _replyCtrl.dispose();
    _replyFocus.dispose();
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
    _pause();
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
                child: Center(child: Text('Belum ada yang melihat')));
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
                    leading: Avatar(
                        url: u.avatarUrl, name: u.displayName, radius: 20),
                    title: Text(u.displayName),
                  )),
            ],
          );
        },
      ),
    ).whenComplete(() {
      if (mounted) _resume();
    });
  }

  Widget _navButton(IconData icon, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 4),
        padding: const EdgeInsets.all(6),
        decoration: const BoxDecoration(
          color: Colors.black38,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Colors.white, size: 30),
      ),
    );
  }

  Widget _content(StatusItem s) {
    switch (s.type) {
      case 'TEXT':
        return Padding(
          padding: const EdgeInsets.all(32),
          child: Text(s.text ?? '',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w600)),
        );
      case 'AUDIO':
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.music_note_rounded, color: Colors.white, size: 96),
            if (s.caption?.isNotEmpty ?? false)
              Padding(
                padding: const EdgeInsets.fromLTRB(32, 18, 32, 0),
                child: Text(s.caption!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 18)),
              ),
          ],
        );
      case 'VIDEO':
        final c = _video;
        if (c != null && c.value.isInitialized) {
          return AspectRatio(
              aspectRatio: c.value.aspectRatio, child: VideoPlayer(c));
        }
        return const CircularProgressIndicator(color: Colors.white);
      default: // IMAGE
        return CachedNetworkImage(
          imageUrl: s.mediaUrl ?? '',
          fit: BoxFit.contain,
          placeholder: (_, _) =>
              const CircularProgressIndicator(color: Colors.white),
          errorWidget: (_, _, _) =>
              const Icon(Icons.broken_image, color: Colors.white54, size: 48),
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = _status;
    final colored = s.type == 'TEXT' || s.type == 'AUDIO';
    final liveCount =
        context.watch<StatusProvider>().viewCountById(s.id) ?? s.viewCount;
    return Scaffold(
      backgroundColor: colored ? _parseColor(s.bgColor) : Colors.black,
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
            Positioned.fill(child: Center(child: _content(s))),
            // Tombol navigasi prev/next.
            if (!(_s == 0 && _i == 0))
              Positioned(
                left: 4,
                top: 0,
                bottom: 0,
                child: Center(child: _navButton(Icons.chevron_left_rounded, _prev)),
              ),
            Positioned(
              right: 4,
              top: 0,
              bottom: 0,
              child:
                  Center(child: _navButton(Icons.chevron_right_rounded, _next)),
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
                                        ? _segmentProgress().toDouble()
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
                  padding: EdgeInsets.only(
                      left: 16,
                      right: 16,
                      top: 8,
                      bottom: 16 + MediaQuery.of(context).viewInsets.bottom),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (s.type != 'TEXT' &&
                          s.type != 'AUDIO' &&
                          (s.caption?.isNotEmpty ?? false))
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
                        )
                      else
                        // Balas status (ala WhatsApp) → kirim pesan ke pemilik.
                        Row(
                          children: [
                            Expanded(
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 16),
                                decoration: BoxDecoration(
                                  color: Colors.white24,
                                  borderRadius: BorderRadius.circular(24),
                                ),
                                child: TextField(
                                  controller: _replyCtrl,
                                  focusNode: _replyFocus,
                                  style: const TextStyle(color: Colors.white),
                                  textInputAction: TextInputAction.send,
                                  onSubmitted: (_) => _sendReply(),
                                  decoration: const InputDecoration(
                                    border: InputBorder.none,
                                    hintText: 'Balas…',
                                    hintStyle: TextStyle(color: Colors.white70),
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            GestureDetector(
                              onTap: _sendReply,
                              child: Container(
                                width: 46,
                                height: 46,
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.primary,
                                  shape: BoxShape.circle,
                                ),
                                child: _sendingReply
                                    ? const Padding(
                                        padding: EdgeInsets.all(13),
                                        child: CircularProgressIndicator(
                                            strokeWidth: 2,
                                            color: Colors.white),
                                      )
                                    : const Icon(Icons.send_rounded,
                                        color: Colors.white, size: 20),
                              ),
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
