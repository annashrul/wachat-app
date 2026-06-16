import 'package:socket_io_client/socket_io_client.dart' as io;
import '../config.dart';

/// Pengelola koneksi Socket.IO ke backend (singleton).
class SocketService {
  SocketService._();
  static final SocketService instance = SocketService._();

  io.Socket? _socket;

  io.Socket? get socket => _socket;
  bool get connected => _socket?.connected ?? false;

  void connect(String token) {
    if (_socket != null) disconnect();
    _socket = io.io(
      AppConfig.socketUrl,
      io.OptionBuilder()
          .setTransports(['websocket'])
          .disableAutoConnect()
          // Penting: paksa Manager baru tiap connect. Tanpa ini socket_io_client
          // me-reuse Manager yang di-cache per-URL beserta auth handshake LAMA,
          // sehingga setelah ganti akun socket masih memakai token akun lama
          // (pesan tercatat atas nama user sebelumnya). forceNew = identitas
          // selalu ikut token terbaru.
          .enableForceNew()
          .setAuth({'token': token})
          .build(),
    );
    _socket!.connect();
  }

  void on(String event, void Function(dynamic) handler) =>
      _socket?.on(event, handler);

  void off(String event) => _socket?.off(event);

  void emit(String event, dynamic data) => _socket?.emit(event, data);

  void disconnect() {
    _socket?.dispose();
    _socket = null;
  }
}
