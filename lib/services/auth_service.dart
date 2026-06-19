import '../models/user.dart';
import 'api_client.dart';

class AuthResult {
  final AppUser user;
  final String token;
  AuthResult(this.user, this.token);
}

/// Hasil login: bisa sukses langsung, atau butuh verifikasi PIN (2FA).
class LoginResult {
  final AuthResult? auth; // null bila 2FA dibutuhkan
  final String? pendingToken; // diisi bila 2FA dibutuhkan
  LoginResult({this.auth, this.pendingToken});
  bool get twoFactorRequired => pendingToken != null;
}

class AuthService {
  final _api = ApiClient.instance;

  Future<AuthResult> register({
    required String phone,
    required String displayName,
    required String password,
  }) async {
    final res = await _api.dio.post('/auth/register', data: {
      'phone': phone,
      'displayName': displayName,
      'password': password,
    });
    return _handle(res.data as Map<String, dynamic>);
  }

  Future<LoginResult> login({
    required String phone,
    required String password,
  }) async {
    final res = await _api.dio.post('/auth/login', data: {
      'phone': phone,
      'password': password,
    });
    final data = res.data as Map<String, dynamic>;
    if (data['twoFactorRequired'] == true) {
      return LoginResult(pendingToken: data['pendingToken'] as String);
    }
    return LoginResult(auth: await _handle(data));
  }

  /// Selesaikan login 2FA dengan PIN.
  Future<AuthResult> verifyTwoFactor(String pendingToken, String pin) async {
    final res = await _api.dio.post('/auth/2fa/verify', data: {
      'pendingToken': pendingToken,
      'pin': pin,
    });
    return _handle(res.data as Map<String, dynamic>);
  }

  Future<void> enableTwoFactor(String pin) async {
    await _api.dio.post('/auth/2fa/enable', data: {'pin': pin});
  }

  Future<void> disableTwoFactor(String pin) async {
    await _api.dio.post('/auth/2fa/disable', data: {'pin': pin});
  }

  Future<AppUser> me() async {
    final res = await _api.dio.get('/auth/me');
    return AppUser.fromJson(res.data as Map<String, dynamic>);
  }

  Future<AppUser> updateProfile(Map<String, dynamic> data) async {
    final res = await _api.dio.patch('/users/me', data: data);
    return AppUser.fromJson(res.data as Map<String, dynamic>);
  }

  Future<void> changePassword({
    required String currentPassword,
    required String newPassword,
  }) async {
    await _api.dio.post('/auth/change-password', data: {
      'currentPassword': currentPassword,
      'newPassword': newPassword,
    });
  }

  Future<void> deleteAccount(String password) async {
    await _api.dio.delete('/auth/me', data: {'password': password});
  }

  Future<AuthResult> _handle(Map<String, dynamic> data) async {
    final token = data['accessToken'] as String;
    await _api.setToken(token);
    final user = AppUser.fromJson(data['user'] as Map<String, dynamic>);
    return AuthResult(user, token);
  }

  Future<void> logout() => _api.clearToken();
}
