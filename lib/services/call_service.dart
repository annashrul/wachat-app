import '../models/call_log.dart';
import 'api_client.dart';

class CallService {
  final _api = ApiClient.instance;

  Future<List<CallLog>> getCalls() async {
    final res = await _api.dio.get('/calls');
    return (res.data as List)
        .map((e) => CallLog.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> recordCall({
    required String calleeId,
    required String status,
    int durationSec = 0,
    String? conversationId,
    bool video = false,
  }) async {
    await _api.dio.post('/calls', data: {
      'calleeId': calleeId,
      'status': status,
      'durationSec': durationSec,
      'conversationId': ?conversationId,
      'video': video,
    });
  }

  Future<void> clear() async {
    await _api.dio.delete('/calls');
  }
}
