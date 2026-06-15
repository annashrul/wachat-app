import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:just_audio/just_audio.dart';

/// Visual gelombang suara ala WhatsApp: deretan bar dengan tinggi pseudo-acak
/// (stabil per [seed]). Bagian yang sudah diputar berwarna [active].
/// Ketuk/geser untuk seek → [onSeek] menerima fraksi 0..1.
class VoiceWaveform extends StatelessWidget {
  final double progress; // 0..1
  final Color active;
  final Color inactive;
  final int seed;
  final ValueChanged<double>? onSeek;
  final double height;
  final int barCount;

  const VoiceWaveform({
    super.key,
    required this.progress,
    required this.active,
    required this.inactive,
    this.seed = 7,
    this.onSeek,
    this.height = 26,
    this.barCount = 28,
  });

  double _barFactor(int i) {
    final v = ((i * 929 + seed * 53) % 97) / 97.0; // 0..1 stabil
    return 0.25 + 0.75 * v;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        void seek(double dx) {
          if (onSeek != null) onSeek!((dx / w).clamp(0.0, 1.0));
        }

        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => seek(d.localPosition.dx),
          onHorizontalDragUpdate: (d) => seek(d.localPosition.dx),
          child: SizedBox(
            height: height,
            width: double.infinity,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: List.generate(barCount, (i) {
                final filled = (i + 0.5) / barCount <= progress;
                return Container(
                  width: 3,
                  height: height * _barFactor(i),
                  decoration: BoxDecoration(
                    color: filled ? active : inactive,
                    borderRadius: BorderRadius.circular(2),
                  ),
                );
              }),
            ),
          ),
        );
      },
    );
  }
}

String _fmt(Duration d) {
  final m = d.inMinutes;
  final s = d.inSeconds % 60;
  return '$m:${s.toString().padLeft(2, '0')}';
}

/// Tombol play/pause bulat dengan indikator loading.
class _PlayButton extends StatelessWidget {
  final bool loading;
  final bool playing;
  final Color color;
  final VoidCallback? onTap;
  const _PlayButton({
    required this.loading,
    required this.playing,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: loading ? null : onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        child: loading
            ? const Padding(
                padding: EdgeInsets.all(10),
                child: CircularProgressIndicator(
                    strokeWidth: 2, color: Colors.white),
              )
            : Icon(
                playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: Colors.white,
                size: 24,
              ),
      ),
    );
  }
}

/// Gelembung pesan suara (URL remote). Player dibuat lazy saat pertama diputar.
class VoiceMessage extends StatefulWidget {
  final String url;
  final int durationSeconds;
  final Color accent;
  final Color trackColor;
  final Color textColor;
  final int seed;

  const VoiceMessage({
    super.key,
    required this.url,
    required this.durationSeconds,
    required this.accent,
    required this.trackColor,
    required this.textColor,
    this.seed = 7,
  });

  @override
  State<VoiceMessage> createState() => _VoiceMessageState();
}

class _VoiceMessageState extends State<VoiceMessage> {
  AudioPlayer? _player;
  bool _loading = false;
  bool _ready = false;

  @override
  void dispose() {
    _player?.dispose();
    super.dispose();
  }

  Future<void> _toggle() async {
    var p = _player;
    if (p == null) {
      p = AudioPlayer();
      _player = p;
      setState(() => _loading = true);
      try {
        await p.setUrl(widget.url);
        _ready = true;
        p.playerStateStream.listen((s) {
          if (s.processingState == ProcessingState.completed) {
            p?.seek(Duration.zero);
            p?.pause();
          }
        });
      } catch (_) {
      } finally {
        if (mounted) setState(() => _loading = false);
      }
    }
    if (!_ready) return;
    p.playing ? await p.pause() : await p.play();
  }

  @override
  Widget build(BuildContext context) {
    final p = _player;
    final total = (p?.duration != null && p!.duration!.inMilliseconds > 0)
        ? p.duration!
        : Duration(seconds: widget.durationSeconds);
    return SizedBox(
      width: 218,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          StreamBuilder<bool>(
            stream: p?.playingStream,
            initialData: false,
            builder: (_, snap) => _PlayButton(
              loading: _loading,
              playing: snap.data ?? false,
              color: widget.accent,
              onTap: _toggle,
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: StreamBuilder<Duration>(
              stream: p?.positionStream,
              initialData: Duration.zero,
              builder: (_, snap) {
                final pos = snap.data ?? Duration.zero;
                final progress = total.inMilliseconds == 0
                    ? 0.0
                    : (pos.inMilliseconds / total.inMilliseconds)
                        .clamp(0.0, 1.0);
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    VoiceWaveform(
                      progress: progress,
                      active: widget.accent,
                      inactive: widget.trackColor,
                      seed: widget.seed,
                      onSeek: _ready
                          ? (f) => p?.seek(Duration(
                              milliseconds:
                                  (f * total.inMilliseconds).round()))
                          : null,
                    ),
                    const SizedBox(height: 4),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(Icons.mic_rounded,
                            size: 13,
                            color: widget.textColor.withValues(alpha: 0.6)),
                        Text(
                          (p?.playing ?? false) ? _fmt(pos) : _fmt(total),
                          style: TextStyle(
                            fontSize: 11,
                            color: widget.textColor.withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Pemutar untuk PREVIEW rekaman (file lokal) sebelum dikirim — ala WhatsApp.
class VoiceReviewPlayer extends StatefulWidget {
  final String path; // file lokal (mobile) atau blob URL (web)
  final int seconds;
  final Color accent;
  final Color trackColor;
  final Color textColor;

  const VoiceReviewPlayer({
    super.key,
    required this.path,
    required this.seconds,
    required this.accent,
    required this.trackColor,
    required this.textColor,
  });

  @override
  State<VoiceReviewPlayer> createState() => _VoiceReviewPlayerState();
}

class _VoiceReviewPlayerState extends State<VoiceReviewPlayer> {
  final _player = AudioPlayer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      if (kIsWeb) {
        await _player.setUrl(widget.path);
      } else {
        await _player.setFilePath(widget.path);
      }
      _player.playerStateStream.listen((s) {
        if (s.processingState == ProcessingState.completed) {
          _player.seek(Duration.zero);
          _player.pause();
        }
      });
      if (mounted) setState(() => _ready = true);
    } catch (_) {}
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final total =
        (_player.duration != null && _player.duration!.inMilliseconds > 0)
            ? _player.duration!
            : Duration(seconds: widget.seconds);
    return Row(
      children: [
        StreamBuilder<bool>(
          stream: _player.playingStream,
          initialData: false,
          builder: (_, snap) => _PlayButton(
            loading: !_ready,
            playing: snap.data ?? false,
            color: widget.accent,
            onTap: () =>
                _player.playing ? _player.pause() : _player.play(),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: StreamBuilder<Duration>(
            stream: _player.positionStream,
            initialData: Duration.zero,
            builder: (_, snap) {
              final pos = snap.data ?? Duration.zero;
              final progress = total.inMilliseconds == 0
                  ? 0.0
                  : (pos.inMilliseconds / total.inMilliseconds)
                      .clamp(0.0, 1.0);
              return VoiceWaveform(
                progress: progress,
                active: widget.accent,
                inactive: widget.trackColor,
                onSeek: _ready
                    ? (f) => _player.seek(Duration(
                        milliseconds: (f * total.inMilliseconds).round()))
                    : null,
              );
            },
          ),
        ),
        const SizedBox(width: 10),
        StreamBuilder<Duration>(
          stream: _player.positionStream,
          initialData: Duration.zero,
          builder: (_, snap) {
            final pos = snap.data ?? Duration.zero;
            return Text(
              _player.playing ? _fmt(pos) : _fmt(total),
              style: TextStyle(
                fontSize: 12,
                color: widget.textColor.withValues(alpha: 0.75),
                fontWeight: FontWeight.w600,
              ),
            );
          },
        ),
      ],
    );
  }
}
