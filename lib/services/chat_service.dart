import 'package:dio/dio.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import 'api_client.dart';

class ChatService {
  final _api = ApiClient.instance;

  Future<List<Conversation>> getConversations() async {
    final res = await _api.dio.get('/conversations');
    return (res.data as List)
        .map((e) => Conversation.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<Conversation> createDirect(String otherUserId) async {
    final res = await _api.dio.post('/conversations', data: {
      'type': 'DIRECT',
      'memberIds': [otherUserId],
    });
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Conversation> createGroup(
    String name,
    List<String> memberIds,
  ) async {
    final res = await _api.dio.post('/conversations', data: {
      'type': 'GROUP',
      'name': name,
      'memberIds': memberIds,
    });
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<List<Message>> getMessages(String conversationId,
      {String? before}) async {
    final res = await _api.dio.get(
      '/conversations/$conversationId/messages',
      queryParameters: {'before': ?before},
    );
    return (res.data as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<List<Message>> searchMessages(
      String conversationId, String q) async {
    final res = await _api.dio.get(
      '/conversations/$conversationId/messages/search',
      queryParameters: {'q': q},
    );
    return (res.data as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> markRead(String conversationId) async {
    await _api.dio.post('/conversations/$conversationId/read');
  }

  Future<void> deleteConversation(String conversationId) async {
    await _api.dio.delete('/conversations/$conversationId');
  }

  Future<Conversation> getConversation(String id) async {
    final res = await _api.dio.get('/conversations/$id');
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Conversation> updateGroup(String id,
      {String? name, String? description, String? avatarUrl}) async {
    final res = await _api.dio.patch('/conversations/$id', data: {
      'name': ?name,
      'description': ?description,
      'avatarUrl': ?avatarUrl,
    });
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Conversation> addMembers(String id, List<String> userIds) async {
    final res = await _api.dio
        .post('/conversations/$id/members', data: {'userIds': userIds});
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Conversation> removeMember(String id, String userId) async {
    final res = await _api.dio.delete('/conversations/$id/members/$userId');
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<Conversation> setMemberRole(
      String id, String userId, bool admin) async {
    final res = await _api.dio
        .post('/conversations/$id/members/$userId/role', data: {'admin': admin});
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<({String token, String link, String? webLink})> createInvite(
      String id) async {
    final res = await _api.dio.post('/conversations/$id/invite');
    final d = res.data as Map<String, dynamic>;
    return (
      token: d['token'] as String,
      link: d['link'] as String,
      webLink: d['webLink'] as String?,
    );
  }

  Future<Conversation> joinGroup(String token) async {
    final res =
        await _api.dio.post('/conversations/join', data: {'token': token});
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> setMuted(String conversationId, bool muted) async {
    await _api.dio.post('/conversations/$conversationId/mute',
        data: {'muted': muted});
  }

  Future<Conversation> pinMessage(
      String conversationId, String? messageId) async {
    final res = await _api.dio.post('/conversations/$conversationId/pin',
        data: {'messageId': messageId});
    return Conversation.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> setDisappearing(String conversationId, int seconds) async {
    await _api.dio.post('/conversations/$conversationId/disappearing',
        data: {'seconds': seconds});
  }

  Future<List<Message>> getStarred() async {
    final res = await _api.dio.get('/messages/starred');
    return (res.data as List)
        .map((e) => Message.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> setStarred(String messageId, bool starred) async {
    await _api.dio.post('/messages/$messageId/star', data: {'starred': starred});
  }

  Future<List<AppUser>> searchUsers(String query) async {
    final res = await _api.dio.get('/users/search',
        queryParameters: {'q': query});
    return (res.data as List)
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  /// Kontak tersimpan: [{id, alias, user}].
  Future<List<({String id, String? alias, AppUser user})>> getContacts() async {
    final res = await _api.dio.get('/contacts');
    return (res.data as List).map((e) {
      final m = e as Map<String, dynamic>;
      return (
        id: m['id'] as String,
        alias: m['alias'] as String?,
        user: AppUser.fromJson(m['user'] as Map<String, dynamic>),
      );
    }).toList();
  }

  Future<void> addContact(String userId, {String? alias}) async {
    await _api.dio.post('/contacts',
        data: {'userId': userId, 'alias': ?alias});
  }

  /// QR kontak milik sendiri: kembalikan link (untuk di-encode jadi QR) + profil.
  Future<({String link, AppUser user})> myQr() async {
    final res = await _api.dio.get('/users/me/qr');
    final m = res.data as Map<String, dynamic>;
    return (
      link: m['link'] as String,
      user: AppUser.fromJson(m['user'] as Map<String, dynamic>),
    );
  }

  /// Tambah kontak dari hasil scan QR (token/link). Kembalikan profil kontak.
  Future<AppUser> scanContact(String code) async {
    final res = await _api.dio.post('/contacts/scan', data: {'code': code});
    final m = res.data as Map<String, dynamic>;
    return AppUser.fromJson(m['user'] as Map<String, dynamic>);
  }

  Future<void> deleteContact(String contactId) async {
    await _api.dio.delete('/contacts/$contactId');
  }

  Future<void> blockUser(String userId) async {
    await _api.dio.post('/contacts/block', data: {'userId': userId});
  }

  /// Daftar pengguna yang sedang diblokir.
  Future<List<AppUser>> blockedUsers() async {
    final res = await _api.dio.get('/contacts/blocked');
    return (res.data as List)
        .map((e) => AppUser.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> unblockUser(String userId) async {
    await _api.dio.delete('/contacts/block/$userId');
  }

  Future<Map<String, dynamic>> linkPreview(String url) async {
    final res = await _api.dio.get('/link-preview',
        queryParameters: {'url': url});
    return Map<String, dynamic>.from(res.data as Map);
  }

  /// Upload file ke backend (Supabase Storage), kembalikan url + nama.
  Future<({String url, String name})> uploadFile(
    List<int> bytes,
    String filename,
  ) async {
    final form = FormData.fromMap({
      'file': MultipartFile.fromBytes(bytes, filename: filename),
    });
    final res = await _api.dio.post('/upload', data: form);
    final data = res.data as Map<String, dynamic>;
    return (url: data['url'] as String, name: data['name'] as String);
  }
}
