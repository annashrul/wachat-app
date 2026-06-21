import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import '../screens/group_call_screen.dart';

enum GroupCallState { idle, ringing, active }

/// Panggilan grup berbasis mesh (setiap peserta terhubung langsung ke peserta
/// lain). Tahap 1: hanya suara. Sinyal lewat event `group-call:*` & `gcall:*`.
class GroupCallProvider extends ChangeNotifier {
  final _socket = SocketService.instance;

  GroupCallState state = GroupCallState.idle;
  String? conversationId;
  String? conversationTitle;

  // Panggilan masuk (sebelum diterima).
  String? incomingConversationId;
  String? incomingFromName;
  String? incomingFromAvatar;

  bool muted = false;
  bool _screenOpen = false;

  MediaStream? _localStream;
  final Map<String, RTCPeerConnection> _peers = {};
  final Map<String, RTCVideoRenderer> remoteRenderers = {};
  final Map<String, List<RTCIceCandidate>> _pendingIce = {};

  /// userId peserta lain yang sedang terhubung (untuk UI).
  List<String> get participantIds => remoteRenderers.keys.toList();
  bool get inCall => state != GroupCallState.idle;

  static const Map<String, dynamic> _config = {
    'iceServers': [
      {'urls': 'stun:stun.l.google.com:19302'},
      {'urls': 'stun:stun1.l.google.com:19302'},
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

  void init() {
    for (final e in const [
      'group-call:incoming',
      'group-call:participants',
      'group-call:peer-joined',
      'group-call:peer-left',
      'gcall:offer',
      'gcall:answer',
      'gcall:ice',
    ]) {
      _socket.off(e);
    }
    _socket.on('group-call:incoming', (d) {
      final m = Map<String, dynamic>.from(d as Map);
      // Abaikan kalau sedang dalam panggilan.
      if (state != GroupCallState.idle) return;
      final from = m['from'] as Map?;
      incomingConversationId = m['conversationId'] as String?;
      incomingFromName = from?['displayName'] as String?;
      incomingFromAvatar = from?['avatarUrl'] as String?;
      state = GroupCallState.ringing;
      notifyListeners();
      _openScreen();
    });
    _socket.on('group-call:participants', (d) async {
      final m = Map<String, dynamic>.from(d as Map);
      if (m['conversationId'] != conversationId) return;
      final list = (m['participants'] as List?)?.cast<String>() ?? [];
      // Peserta lama akan membuat offer ke kita → cukup siapkan slot.
      for (final id in list) {
        await _ensureRenderer(id);
      }
    });
    _socket.on('group-call:peer-joined', (d) async {
      final m = Map<String, dynamic>.from(d as Map);
      if (m['conversationId'] != conversationId) return;
      final uid = m['userId'] as String?;
      if (uid == null) return;
      // Aturan: peserta lama (kita) yang membuat offer ke peserta baru.
      await _createOfferTo(uid);
    });
    _socket.on('group-call:peer-left', (d) {
      final m = Map<String, dynamic>.from(d as Map);
      if (m['conversationId'] != conversationId) return;
      _removePeer(m['userId'] as String?);
    });
    _socket.on('gcall:offer', (d) async {
      final m = Map<String, dynamic>.from(d as Map);
      if (m['conversationId'] != conversationId) return;
      await _onOffer(m['from'] as String, m['offer'] as Map);
    });
    _socket.on('gcall:answer', (d) async {
      final m = Map<String, dynamic>.from(d as Map);
      if (m['conversationId'] != conversationId) return;
      await _onAnswer(m['from'] as String, m['answer'] as Map);
    });
    _socket.on('gcall:ice', (d) async {
      final m = Map<String, dynamic>.from(d as Map);
      if (m['conversationId'] != conversationId) return;
      await _onIce(m['from'] as String, m['candidate'] as Map);
    });
  }

  Future<void> _ensureLocalStream() async {
    _localStream ??= await navigator.mediaDevices.getUserMedia({
      'audio': true,
      'video': false,
    });
  }

  Future<RTCVideoRenderer> _ensureRenderer(String uid) async {
    var r = remoteRenderers[uid];
    if (r == null) {
      r = RTCVideoRenderer();
      await r.initialize();
      remoteRenderers[uid] = r;
      notifyListeners();
    }
    return r;
  }

  /// Buat (atau ambil) peer connection ke [uid].
  Future<RTCPeerConnection> _peerFor(String uid) async {
    final existing = _peers[uid];
    if (existing != null) return existing;
    await _ensureLocalStream();
    final pc = await createPeerConnection(_config);
    _peers[uid] = pc;

    for (final track in _localStream!.getTracks()) {
      await pc.addTrack(track, _localStream!);
    }

    pc.onIceCandidate = (c) {
      if (c.candidate == null) return;
      _socket.emit('gcall:ice', {
        'to': uid,
        'conversationId': conversationId,
        'candidate': {
          'candidate': c.candidate,
          'sdpMid': c.sdpMid,
          'sdpMLineIndex': c.sdpMLineIndex,
        },
      });
    };
    pc.onTrack = (event) async {
      final r = await _ensureRenderer(uid);
      if (event.streams.isNotEmpty) {
        r.srcObject = event.streams[0];
      } else {
        final ms = await createLocalMediaStream('remote_$uid');
        await ms.addTrack(event.track);
        r.srcObject = ms;
      }
      notifyListeners();
    };
    await _ensureRenderer(uid);
    return pc;
  }

  Future<void> _createOfferTo(String uid) async {
    final pc = await _peerFor(uid);
    final offer = await pc.createOffer({});
    await pc.setLocalDescription(offer);
    _socket.emit('gcall:offer', {
      'to': uid,
      'conversationId': conversationId,
      'offer': {'sdp': offer.sdp, 'type': offer.type},
    });
  }

  Future<void> _onOffer(String from, Map offer) async {
    final pc = await _peerFor(from);
    await pc.setRemoteDescription(
      RTCSessionDescription(offer['sdp'] as String, offer['type'] as String),
    );
    await _flushIce(from);
    final answer = await pc.createAnswer({});
    await pc.setLocalDescription(answer);
    _socket.emit('gcall:answer', {
      'to': from,
      'conversationId': conversationId,
      'answer': {'sdp': answer.sdp, 'type': answer.type},
    });
  }

  Future<void> _onAnswer(String from, Map answer) async {
    final pc = _peers[from];
    if (pc == null) return;
    await pc.setRemoteDescription(
      RTCSessionDescription(answer['sdp'] as String, answer['type'] as String),
    );
    await _flushIce(from);
  }

  Future<void> _onIce(String from, Map cand) async {
    final candidate = RTCIceCandidate(
      cand['candidate'] as String?,
      cand['sdpMid'] as String?,
      (cand['sdpMLineIndex'] as num?)?.toInt(),
    );
    final pc = _peers[from];
    if (pc == null || (await pc.getRemoteDescription()) == null) {
      (_pendingIce[from] ??= []).add(candidate);
      return;
    }
    await pc.addCandidate(candidate);
  }

  Future<void> _flushIce(String from) async {
    final pc = _peers[from];
    final list = _pendingIce.remove(from);
    if (pc == null || list == null) return;
    for (final c in list) {
      await pc.addCandidate(c);
    }
  }

  void _removePeer(String? uid) {
    if (uid == null) return;
    _peers.remove(uid)?.close();
    final r = remoteRenderers.remove(uid);
    r?.srcObject = null;
    r?.dispose();
    _pendingIce.remove(uid);
    notifyListeners();
  }

  // ===== Aksi publik =====

  /// Mulai panggilan grup baru di percakapan [convId].
  Future<void> start(String convId, String title) async {
    conversationId = convId;
    conversationTitle = title;
    state = GroupCallState.active;
    muted = false;
    notifyListeners();
    _openScreen();
    await _ensureLocalStream();
    _socket.emit('group-call:start', {'conversationId': convId});
  }

  /// Terima panggilan grup yang masuk.
  Future<void> accept(String title) async {
    final convId = incomingConversationId;
    if (convId == null) return;
    conversationId = convId;
    conversationTitle = title;
    state = GroupCallState.active;
    muted = false;
    incomingConversationId = null;
    notifyListeners();
    await _ensureLocalStream();
    _socket.emit('group-call:join', {'conversationId': convId});
  }

  void declineIncoming() {
    incomingConversationId = null;
    incomingFromName = null;
    incomingFromAvatar = null;
    state = GroupCallState.idle;
    notifyListeners();
  }

  void _openScreen() {
    if (_screenOpen) return;
    final ctx = NotificationService.navigatorKey.currentContext;
    if (ctx == null) return;
    _screenOpen = true;
    Navigator.of(ctx).push(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => const GroupCallScreen(),
    )).then((_) => _screenOpen = false);
  }

  void toggleMute() {
    muted = !muted;
    for (final t in _localStream?.getAudioTracks() ?? const []) {
      t.enabled = !muted;
    }
    notifyListeners();
  }

  Future<void> leave() async {
    final convId = conversationId;
    if (convId != null) {
      _socket.emit('group-call:leave', {'conversationId': convId});
    }
    for (final pc in _peers.values) {
      await pc.close();
    }
    _peers.clear();
    for (final r in remoteRenderers.values) {
      r.srcObject = null;
      await r.dispose();
    }
    remoteRenderers.clear();
    _pendingIce.clear();
    for (final t in _localStream?.getTracks() ?? const []) {
      await t.stop();
    }
    await _localStream?.dispose();
    _localStream = null;
    state = GroupCallState.idle;
    conversationId = null;
    conversationTitle = null;
    muted = false;
    notifyListeners();
  }
}
