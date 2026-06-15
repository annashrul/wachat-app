import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../providers/call_provider.dart';
import '../widgets/avatar.dart';

/// Layar panggilan suara (penuh). Mengikuti state dari [CallProvider] dan
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
        return 'Panggilan suara masuk';
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

    // Tutup layar otomatis ketika panggilan selesai.
    if (call.state == CallState.idle) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final nav = Navigator.of(context);
        if (nav.canPop()) nav.pop();
      });
    }

    return PopScope(
      canPop: call.state == CallState.idle,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && call.inCall) call.hangUp();
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E1621),
        body: SafeArea(
          child: Column(
            children: [
              // Renderer tersembunyi untuk memutar audio lawan (penting di web).
              if (call.hasRemote)
                SizedBox(
                  width: 0,
                  height: 0,
                  child: RTCVideoView(call.remoteRenderer),
                ),
              const Spacer(flex: 2),
              Avatar(
                url: call.peerAvatar,
                name: call.peerName ?? 'Pengguna',
                radius: 64,
              ),
              const SizedBox(height: 24),
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
                  const Icon(Icons.call_rounded,
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
      ),
    );
  }

  Widget _controls(BuildContext context, CallProvider call) {
    // Panggilan masuk → tombol Tolak & Terima.
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
            icon: Icons.call_rounded,
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

    // Outgoing / connecting / active → mute, speaker, akhiri.
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
        _RoundButton(
          icon:
              call.speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
          bg: call.speakerOn ? Colors.white : Colors.white24,
          fg: call.speakerOn ? Colors.black : Colors.white,
          label: 'Speaker',
          onTap: call.toggleSpeaker,
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
            width: 64,
            height: 64,
            decoration: BoxDecoration(color: bg, shape: BoxShape.circle),
            child: Icon(icon, color: fg, size: 28),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white70, fontSize: 12)),
      ],
    );
  }
}
