import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/conversation.dart';
import '../models/user.dart';
import '../models/call_log.dart';
import '../services/socket_service.dart';
import '../services/call_service.dart';
import '../services/notification_service.dart';
import '../screens/call_screen.dart';

enum CallState { idle, outgoing, incoming, connecting, active, ended }

/// Panggilan suara 1-lawan-1 berbasis WebRTC. Signaling lewat Socket.IO,
/// NAT traversal pakai STUN gratis Google.
class CallProvider extends ChangeNotifier {
  final _socket = SocketService.instance;
  final _calls = CallService();
  String? _myId;
  bool _attached = false;
  bool _isCaller = false; // true = saya yang memanggil (perekam riwayat)
  bool _wasActive = false; // pernah tersambung

  // Riwayat panggilan + badge "tak terjawab".
  static const _seenKey = 'calls_seen_at';
  List<CallLog> callLogs = [];
  bool loadingCalls = false;
  int missedCount = 0;
  DateTime? _callsSeenAt;

  CallState state = CallState.idle;
  String? peerId;
  String? peerName;
  String? peerAvatar;
  String? conversationId;
  bool muted = false;
  bool speakerOn = false;
  Duration callDuration = Duration.zero;
  String? endReason; // mis. "Tidak dijawab", "Tidak tersedia"

  RTCPeerConnection? _pc;
  MediaStream? _localStream;
  final RTCVideoRenderer remoteRenderer = RTCVideoRenderer();
  bool _rendererReady = false;
  bool _remoteSet = false;
  final List<RTCIceCandidate> _pendingCandidates = [];
  Timer? _durationTimer;
  Timer? _ringTimeout;
  bool _screenOpen = false;

  static const Map<String, dynamic> _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
      // TURN (relay) — agar media tetap nyambung saat host/STUN gagal
      // (mis. web↔HP di NAT sama, atau beda jaringan). Open Relay (gratis).
      {
        'urls': 'turn:openrelay.metered.ca:80',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
      {
        'urls': 'turn:openrelay.metered.ca:443?transport=tcp',
        'username': 'openrelayproject',
        'credential': 'openrelayproject',
      },
    ],
  };

  bool get inCall => state != CallState.idle;
  bool get hasRemote => remoteRenderer.srcObject != null;

  void init(String myUserId) {
    _myId = myUserId;
    // Selalu pasang ulang listener: tiap login membuat socket baru (forceNew),
    // jadi listener panggilan harus mengikuti socket akun terbaru.
    _attach();
    if (!_attached) {
      // Notifikasi panggilan (app dibuka dari push) → tampilkan layar masuk.
      NotificationService.instance.onIncomingCall = (m) => showIncomingFromPush(
            callerId: (m['callerId'] as String?) ?? '',
            name: m['name'] as String?,
            avatar: m['avatar'] as String?,
            conversationId: m['conversationId'] as String?,
          );
      NotificationService.instance.consumePendingCall();
      _attached = true;
    }
    _loadSeenThenCalls();
  }

  Future<void> _loadSeenThenCalls() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final s = prefs.getString(_seenKey);
      if (s != null) _callsSeenAt = DateTime.tryParse(s);
    } catch (_) {}
    await loadCalls();
  }

  /// Ambil riwayat panggilan & hitung jumlah panggilan masuk tak terjawab
  /// yang belum dilihat (untuk badge tab Panggilan).
  Future<void> loadCalls() async {
    loadingCalls = true;
    notifyListeners();
    try {
      callLogs = await _calls.getCalls();
      _recomputeMissed();
    } catch (_) {
      // biarkan daftar lama
    } finally {
      loadingCalls = false;
      notifyListeners();
    }
  }

  void _recomputeMissed() {
    final me = _myId;
    if (me == null) {
      missedCount = 0;
      return;
    }
    missedCount = callLogs.where((c) {
      final incoming = c.callerId != me;
      final missed = c.status == 'MISSED' ||
          (c.status == 'CANCELED' && incoming);
      if (!incoming || !missed) return false;
      return _callsSeenAt == null || c.createdAt.isAfter(_callsSeenAt!);
    }).length;
  }

  /// Tandai semua panggilan sudah dilihat (badge direset).
  Future<void> markCallsSeen() async {
    _callsSeenAt = DateTime.now();
    missedCount = 0;
    notifyListeners();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_seenKey, _callsSeenAt!.toIso8601String());
    } catch (_) {}
  }

  Future<void> clearCalls() async {
    try {
      await _calls.clear();
    } catch (_) {}
    callLogs = [];
    missedCount = 0;
    notifyListeners();
  }

  void _attach() {
    // Lepas dulu agar tidak terdaftar ganda di socket yang sama.
    for (final e in const [
      'call:incoming',
      'call:accepted',
      'call:offer',
      'call:answered',
      'call:ice',
      'call:rejected',
      'call:ended',
      'call:unavailable',
    ]) {
      _socket.off(e);
    }
    _socket.on('call:incoming',
        (d) => _onIncoming(Map<String, dynamic>.from(d as Map)));
    _socket.on('call:accepted', (_) => _onAccepted());
    _socket.on(
        'call:offer', (d) => _onOffer(Map<String, dynamic>.from(d as Map)));
    _socket.on('call:answered',
        (d) => _onAnswered(Map<String, dynamic>.from(d as Map)));
    _socket.on(
        'call:ice', (d) => _onRemoteIce(Map<String, dynamic>.from(d as Map)));
    _socket.on('call:rejected',
        (_) => _finish(reason: 'Panggilan ditolak', status: 'REJECTED'));
    _socket.on('call:ended', (_) => _finish(reason: 'Panggilan berakhir'));
    _socket.on('call:unavailable',
        (_) => _finish(reason: 'Tidak tersedia', status: 'MISSED'));
  }

  Future<void> _ensureRenderer() async {
    if (!_rendererReady) {
      await remoteRenderer.initialize();
      _rendererReady = true;
    }
  }

  Future<void> _createPeer() async {
    await _ensureRenderer();
    _localStream = await navigator.mediaDevices
        .getUserMedia({'audio': true, 'video': false});
    final pc = await createPeerConnection(_config);
    _pc = pc;
    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }
    pc.onIceCandidate = (c) {
      if (c.candidate != null && peerId != null) {
        _socket.emit('call:ice', {
          'to': peerId,
          'candidate': {
            'candidate': c.candidate,
            'sdpMid': c.sdpMid,
            'sdpMLineIndex': c.sdpMLineIndex,
          },
        });
      }
    };
    pc.onTrack = (event) {
      if (event.streams.isNotEmpty) {
        remoteRenderer.srcObject = event.streams[0];
        notifyListeners(); // agar UI memasang RTCVideoView (audio web ikut main)
      }
    };
    pc.onConnectionState = (s) {
      if (s == RTCPeerConnectionState.RTCPeerConnectionStateConnected) {
        _setActive();
      } else if (s == RTCPeerConnectionState.RTCPeerConnectionStateFailed) {
        _finish(reason: 'Koneksi gagal');
      }
    };
  }

  // ===== Pemanggil =====
  Future<void> startCall(Conversation conv) async {
    final peer = conv.peer;
    if (peer == null || state != CallState.idle) return;
    await startCallUser(peer, conversationId: conv.id);
  }

  /// Panggil seorang pengguna langsung (mis. dari riwayat panggilan).
  Future<void> startCallUser(AppUser peer, {String? conversationId}) async {
    if (state != CallState.idle) return;
    peerId = peer.id;
    peerName = peer.displayName;
    peerAvatar = peer.avatarUrl;
    this.conversationId = conversationId;
    endReason = null;
    muted = false;
    speakerOn = false;
    _isCaller = true;
    _wasActive = false;
    state = CallState.outgoing;
    notifyListeners();
    _openScreen();
    try {
      // Siapkan mic + peer; offer dibuat nanti saat penerima menerima
      // (call:accepted) → tahan terhadap penerima yang sedang offline.
      await _createPeer();
      _socket.emit('call:invite', {
        'conversationId': conversationId,
        'to': peer.id,
      });
      // Timeout bila tak diangkat.
      _ringTimeout = Timer(const Duration(seconds: 45), () {
        if (state == CallState.outgoing) {
          hangUp(reason: 'Tidak dijawab', status: 'MISSED');
        }
      });
    } catch (_) {
      _finish(reason: 'Gagal memulai panggilan');
    }
  }

  /// Pemanggil: penerima sudah menerima → buat & kirim offer.
  Future<void> _onAccepted() async {
    if (!_isCaller || _pc == null) return;
    if (state == CallState.outgoing) {
      state = CallState.connecting;
      notifyListeners();
    }
    try {
      final offer = await _pc!.createOffer(
          {'offerToReceiveAudio': true, 'offerToReceiveVideo': false});
      await _pc!.setLocalDescription(offer);
      _socket.emit('call:offer', {
        'to': peerId,
        'offer': {'sdp': offer.sdp, 'type': offer.type},
      });
    } catch (_) {
      hangUp(reason: 'Gagal menyambungkan');
    }
  }

  /// Penerima: menerima offer dari pemanggil → buat answer.
  Future<void> _onOffer(Map<String, dynamic> data) async {
    if (_pc == null) return;
    try {
      final offer = Map<String, dynamic>.from(data['offer'] as Map);
      await _pc!.setRemoteDescription(RTCSessionDescription(
          offer['sdp'] as String, offer['type'] as String));
      _remoteSet = true;
      await _drainCandidates();
      final answer = await _pc!.createAnswer(
          {'offerToReceiveAudio': true, 'offerToReceiveVideo': false});
      await _pc!.setLocalDescription(answer);
      _socket.emit('call:answer', {
        'to': peerId,
        'answer': {'sdp': answer.sdp, 'type': answer.type},
      });
    } catch (_) {
      hangUp(reason: 'Gagal menyambungkan');
    }
  }

  // ===== Penerima =====
  void _onIncoming(Map<String, dynamic> data) {
    final from = Map<String, dynamic>.from(data['from'] as Map);
    _showIncoming(
      callerId: from['id'] as String?,
      name: from['displayName'] as String?,
      avatar: from['avatarUrl'] as String?,
      conversationId: data['conversationId'] as String?,
    );
  }

  /// Tampilkan panggilan masuk dari notifikasi (app dibuka dari push saat
  /// sebelumnya tertutup). Aman: no-op bila sudah ada panggilan berjalan.
  void showIncomingFromPush({
    required String callerId,
    String? name,
    String? avatar,
    String? conversationId,
  }) {
    _showIncoming(
      callerId: callerId,
      name: name,
      avatar: avatar,
      conversationId: conversationId,
    );
  }

  void _showIncoming({
    required String? callerId,
    String? name,
    String? avatar,
    String? conversationId,
  }) {
    if (callerId == null) return;
    if (state != CallState.idle) {
      // Sedang ada panggilan lain → tolak otomatis (anti-dobel dari push).
      if (callerId != peerId) _socket.emit('call:reject', {'to': callerId});
      return;
    }
    peerId = callerId;
    peerName = name;
    peerAvatar = avatar;
    this.conversationId = conversationId;
    endReason = null;
    muted = false;
    speakerOn = false;
    _isCaller = false;
    _wasActive = false;
    state = CallState.incoming;
    notifyListeners();
    _openScreen();
  }

  /// Penerima menerima → siapkan peer & beri tahu pemanggil (offer menyusul).
  Future<void> accept() async {
    if (state != CallState.incoming || peerId == null) return;
    state = CallState.connecting;
    notifyListeners();
    try {
      await _createPeer();
      _socket.emit('call:accept', {'to': peerId});
    } catch (_) {
      hangUp(reason: 'Gagal menyambungkan');
    }
  }

  void reject() {
    if (peerId != null) _socket.emit('call:reject', {'to': peerId});
    _finish();
  }

  // ===== Sinyal balasan =====
  Future<void> _onAnswered(Map<String, dynamic> data) async {
    if (_pc == null) return;
    final ans = Map<String, dynamic>.from(data['answer'] as Map);
    await _pc!.setRemoteDescription(
        RTCSessionDescription(ans['sdp'] as String, ans['type'] as String));
    _remoteSet = true;
    await _drainCandidates();
    if (state == CallState.outgoing) {
      state = CallState.connecting;
      notifyListeners();
    }
  }

  Future<void> _onRemoteIce(Map<String, dynamic> data) async {
    final c = Map<String, dynamic>.from(data['candidate'] as Map);
    final cand = RTCIceCandidate(
      c['candidate'] as String?,
      c['sdpMid'] as String?,
      c['sdpMLineIndex'] as int?,
    );
    if (_pc != null && _remoteSet) {
      await _pc!.addCandidate(cand);
    } else {
      _pendingCandidates.add(cand);
    }
  }

  Future<void> _drainCandidates() async {
    for (final c in _pendingCandidates) {
      await _pc?.addCandidate(c);
    }
    _pendingCandidates.clear();
  }

  void _setActive() {
    if (state == CallState.active) return;
    _wasActive = true;
    state = CallState.active;
    _ringTimeout?.cancel();
    callDuration = Duration.zero;
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      callDuration += const Duration(seconds: 1);
      notifyListeners();
    });
    notifyListeners();
  }

  // ===== Kontrol =====
  void toggleMute() {
    muted = !muted;
    for (final t in _localStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> toggleSpeaker() async {
    speakerOn = !speakerOn;
    if (!kIsWeb) {
      try {
        await Helper.setSpeakerphoneOn(speakerOn);
      } catch (_) {}
    }
    notifyListeners();
  }

  /// Tutup panggilan dari sisi kita (kirim sinyal ke lawan).
  void hangUp({String? reason, String? status}) {
    if (peerId != null) _socket.emit('call:end', {'to': peerId});
    _finish(reason: reason, status: status);
  }

  /// Catat riwayat — hanya pemanggil yang merekam (1 baris untuk kedua pihak).
  void _recordIfCaller(String? explicitStatus) {
    if (!_isCaller || peerId == null) return;
    final status =
        explicitStatus ?? (_wasActive ? 'COMPLETED' : 'CANCELED');
    final dur = _wasActive ? callDuration.inSeconds : 0;
    _calls
        .recordCall(
          calleeId: peerId!,
          status: status,
          durationSec: dur,
          conversationId: conversationId,
        )
        .catchError((_) {});
    // Tampilkan event panggilan di dalam chat room (ala WhatsApp).
    final conv = conversationId;
    if (conv != null) {
      _socket.emit('message:send', {
        'conversationId': conv,
        'type': 'CALL',
        'content': '$status|$dur',
      });
    }
  }

  /// Akhiri & bersihkan (baik diakhiri lokal maupun oleh lawan).
  Future<void> _finish({String? reason, String? status}) async {
    if (state == CallState.idle) return;
    _recordIfCaller(status);
    endReason = reason;
    state = CallState.ended;
    notifyListeners();
    // Bersihkan; apa pun yang gagal TIDAK boleh menghalangi kembali ke idle.
    try {
      await _cleanup();
    } catch (_) {}
    // Beri jeda agar layar sempat menampilkan "berakhir", lalu kembali idle.
    await Future<void>.delayed(const Duration(milliseconds: 700));
    state = CallState.idle;
    peerId = null;
    peerName = null;
    peerAvatar = null;
    conversationId = null;
    callDuration = Duration.zero;
    notifyListeners();
    // Segarkan riwayat & badge (beri jeda agar catatan server sempat tersimpan).
    Future<void>.delayed(const Duration(milliseconds: 1500), loadCalls);
  }

  Future<void> _cleanup() async {
    _ringTimeout?.cancel();
    _durationTimer?.cancel();
    _remoteSet = false;
    _pendingCandidates.clear();
    try {
      for (final t in _localStream?.getTracks() ?? <MediaStreamTrack>[]) {
        await t.stop();
      }
      await _localStream?.dispose();
    } catch (_) {}
    _localStream = null;
    // Hanya sentuh renderer bila sudah diinisialisasi (penerima yang belum
    // menerima panggilan belum punya renderer → menyetelnya akan error).
    if (_rendererReady) {
      try {
        remoteRenderer.srcObject = null;
      } catch (_) {}
    }
    try {
      await _pc?.close();
    } catch (_) {}
    _pc = null;
  }

  // ===== Navigasi layar panggilan =====
  void _openScreen() {
    if (_screenOpen) return;
    final ctx = NotificationService.navigatorKey.currentContext;
    if (ctx == null) return;
    _screenOpen = true;
    Navigator.of(ctx).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const CallScreen(),
    )).then((_) => _screenOpen = false);
  }

  @override
  void dispose() {
    _cleanup();
    remoteRenderer.dispose();
    super.dispose();
  }
}
