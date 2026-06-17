import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../providers/call_provider.dart';
import '../widgets/avatar.dart';

/// Layar panggilan (suara & video). Mengikuti state dari [CallProvider] dan
/// menutup dirinya sendiri saat panggilan kembali idle.
class CallScreen extends StatelessWidget {
  const CallScreen({super.key});

  static String _fmt(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = (d.inSeconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _status(CallProvider c) {
    switch (c.state) {
      case CallState.outgoing:
        return 'Memanggil…';
      case CallState.incoming:
        return c.isVideo ? 'Panggilan video masuk' : 'Panggilan suara masuk';
      case CallState.connecting:
        return 'Menyambungkan…';
      case CallState.active:
        return _fmt(c.callDuration);
      case CallState.ended:
        return c.endReason ?? 'Panggilan berakhir';
      case CallState.idle:
        return '';
    }
  }

  @override
  Widget build(BuildContext context) {
    final call = context.watch<CallProvider>();

    if (call.state == CallState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      });
    }

    final isVideo = call.isVideo;
    // Tampilkan video remote penuh layar bila ada; jika belum, tampilkan
    // pratinjau kamera sendiri (saat memanggil/menyambungkan).
    final showSelfFull = isVideo && !call.hasRemote && !call.cameraOff;

    return PopScope(
      canPop: call.state == CallState.idle,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && call.inCall) call.hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1621),
        body: Stack(
          children: [
            // Video remote penuh layar.
            if (isVideo && call.hasRemote)
              Positioned.fill(
                child: RTCVideoView(
                  call.remoteRenderer,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            // Pratinjau kamera sendiri penuh layar saat belum tersambung.
            if (showSelfFull)
              Positioned.fill(
                child: RTCVideoView(
                  call.localRenderer,
                  mirror: true,
                  objectFit:
                      RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                ),
              ),
            // Audio: renderer kecil tak terlihat agar audio lawan diputar (web).
            if (!isVideo && call.hasRemote)
              Opacity(
                opacity: 0.0,
                child: SizedBox(
                  width: 1,
                  height: 1,
                  child: RTCVideoView(call.remoteRenderer),
                ),
              ),
            // Lapisan gelap agar teks terbaca di atas video.
            if (isVideo)
              const Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [Color(0x99000000), Colors.transparent, Color(0xAA000000)],
                      stops: [0.0, 0.4, 1.0],
                    ),
                  ),
                ),
              ),

            // Self-view kecil (PiP) saat video remote sudah tampil.
            if (isVideo && call.hasRemote && !call.cameraOff)
              Positioned(
                top: MediaQuery.of(context).padding.top + 12,
                right: 12,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    width: 104,
                    height: 150,
                    child: RTCVideoView(
                      call.localRenderer,
                      mirror: true,
                      objectFit:
                          RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                    ),
                  ),
                ),
              ),

            SafeArea(
              child: Column(
                children: [
                  const SizedBox(height: 16),
                  // Info: avatar hanya untuk audio / saat belum ada video.
                  if (!isVideo) ...[
                    const Spacer(flex: 2),
                    Avatar(
                      url: call.peerAvatar,
                      name: call.peerName ?? 'Pengguna',
                      radius: 64,
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    call.peerName ?? 'Pengguna',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                          size: 15, color: Colors.white54),
                      const SizedBox(width: 6),
                      Text(
                        _status(call),
                        style: const TextStyle(
                          color: Colors.white70,
                          fontSize: 15,
                          fontFeatures: [FontFeature.tabularFigures()],
                        ),
                      ),
                    ],
                  ),
                  const Spacer(flex: 3),
                  _controls(context, call),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, CallProvider call) {
    if (call.state == CallState.incoming) {
      return Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _RoundButton(
            icon: Icons.call_end_rounded,
            bg: const Color(0xFFEF4444),
            label: 'Tolak',
            onTap: call.reject,
          ),
          _RoundButton(
            icon: call.isVideo ? Icons.videocam_rounded : Icons.call_rounded,
            bg: const Color(0xFF22C55E),
            label: 'Terima',
            onTap: call.accept,
          ),
        ],
      );
    }

    if (call.state == CallState.ended) {
      return const SizedBox(height: 72);
    }

    // Outgoing / connecting / active.
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        _RoundButton(
          icon: call.muted ? Icons.mic_off_rounded : Icons.mic_rounded,
          bg: call.muted ? Colors.white : Colors.white24,
          fg: call.muted ? Colors.black : Colors.white,
          label: 'Bisukan',
          onTap: call.toggleMute,
        ),
        if (call.isVideo)
          _RoundButton(
            icon: call.cameraOff
                ? Icons.videocam_off_rounded
                : Icons.videocam_rounded,
            bg: call.cameraOff ? Colors.white : Colors.white24,
            fg: call.cameraOff ? Colors.black : Colors.white,
            label: 'Kamera',
            onTap: call.toggleCamera,
          )
        else
          _RoundButton(
            icon: call.speakerOn
                ? Icons.volume_up_rounded
                : Icons.volume_down_rounded,
            bg: call.speakerOn ? Colors.white : Colors.white24,
            fg: call.speakerOn ? Colors.black : Colors.white,
            label: 'Speaker',
            onTap: call.toggleSpeaker,
          ),
        if (call.isVideo)
          _RoundButton(
            icon: Icons.cameraswitch_rounded,
            bg: Colors.white24,
            label: 'Balik',
            onTap: call.switchCamera,
          ),
        _RoundButton(
          icon: Icons.call_end_rounded,
          bg: const Color(0xFFEF4444),
          label: 'Akhiri',
          onTap: () => call.hangUp(),
        ),
      ],
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final Color bg;
  final Color fg;
  final String label;
  final VoidCallback onTap;
  const _RoundButton({
    required this.icon,
    required this.bg,
    required this.label,
    required this.onTap,
    this.fg = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: onTap,
          child: Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 26),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
