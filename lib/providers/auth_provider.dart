import 'package:flutter/foundation.dart';
import '../models/user.dart';
import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/socket_service.dart';
import '../services/notification_service.dart';
import '../services/app_badge.dart';

enum AuthStatus { unknown, authenticated, unauthenticated }

class AuthProvider extends ChangeNotifier {
  final _auth = AuthService();
  final _socket = SocketService.instance;

  AuthStatus status = AuthStatus.unknown;
  AppUser? user;

  String? get userId => user?.id;

  /// Dipanggil saat app start: cek token tersimpan.
  Future<void> bootstrap() async {
    await ApiClient.instance.loadToken();
    final token = ApiClient.instance.token;
    if (token == null) {
      status = AuthStatus.unauthenticated;
      notifyListeners();
      return;
    }
    try {
      user = await _auth.me();
      _socket.connect(token);
      status = AuthStatus.authenticated;
      NotificationService.instance.init();
    } catch (_) {
      await _auth.logout();
      status = AuthStatus.unauthenticated;
    }
    notifyListeners();
  }

  Future<void> login(String phone, String password) async {
    final res = await _auth.login(phone: phone, password: password);
    user = res.user;
    _socket.connect(res.token);
    status = AuthStatus.authenticated;
    notifyListeners();
    NotificationService.instance.init();
  }

  Future<void> register(
    String phone,
    String displayName,
    String password,
  ) async {
    final res = await _auth.register(
      phone: phone,
      displayName: displayName,
      password: password,
    );
    user = res.user;
    _socket.connect(res.token);
    status = AuthStatus.authenticated;
    notifyListeners();
    NotificationService.instance.init();
  }

  Future<void> updateProfile({
    String? displayName,
    String? about,
    String? avatarUrl,
  }) async {
    final updated = await _auth.updateProfile({
      'displayName': ?displayName,
      'about': ?about,
      'avatarUrl': ?avatarUrl,
    });
    user = updated;
    notifyListeners();
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _auth.changePassword(
      currentPassword: currentPassword,
      newPassword: newPassword,
    );
  }

  /// Hapus akun permanen di server lalu bersihkan sesi lokal.
  Future<void> deleteAccount(String password) async {
    await _auth.deleteAccount(password);
    await NotificationService.instance.unregister();
    _socket.disconnect();
    await _auth.logout();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }

  Future<void> logout() async {
    await AppBadge.set(0);
    await NotificationService.instance.unregister();
    _socket.disconnect();
    await _auth.logout();
    user = null;
    status = AuthStatus.unauthenticated;
    notifyListeners();
  }
}
