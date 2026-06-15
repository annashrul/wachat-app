import 'user.dart';

/// Satu entri riwayat panggilan.
class CallLog {
  final String id;
  final String callerId;
  final String calleeId;
  final String status; // COMPLETED | MISSED | REJECTED | CANCELED
  final int durationSec;
  final DateTime createdAt;
  final String? conversationId;
  final AppUser caller;
  final AppUser callee;

  CallLog({
    required this.id,
    required this.callerId,
    required this.calleeId,
    required this.status,
    required this.durationSec,
    required this.createdAt,
    required this.caller,
    required this.callee,
    this.conversationId,
  });

  /// Lawan bicara relatif terhadap [myId].
  AppUser other(String myId) => callerId == myId ? callee : caller;

  /// Apakah panggilan keluar (saya yang memanggil).
  bool outgoing(String myId) => callerId == myId;

  factory CallLog.fromJson(Map<String, dynamic> j) {
    return CallLog(
      id: j['id'] as String,
      callerId: j['callerId'] as String,
      calleeId: j['calleeId'] as String,
      status: j['status'] as String? ?? 'COMPLETED',
      durationSec: j['durationSec'] as int? ?? 0,
      conversationId: j['conversationId'] as String?,
      createdAt:
          DateTime.tryParse(j['createdAt'] as String? ?? '')?.toLocal() ??
              DateTime.now(),
      caller: AppUser.fromJson(j['caller'] as Map<String, dynamic>),
      callee: AppUser.fromJson(j['callee'] as Map<String, dynamic>),
    );
  }
}
