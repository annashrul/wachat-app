import 'package:dio/dio.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:provider/provider.dart';
import '../providers/chat_provider.dart';
import '../screens/chat_screen.dart';
import 'api_client.dart';

/// Handler pesan FCM saat app di background/mati. Untuk payload "notification",
/// sistem menampilkan otomatis; handler ini cukup ada (no-op).
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage message) async {}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Dipakai MaterialApp agar bisa navigasi dari luar widget tree.
  static final navigatorKey = GlobalKey<NavigatorState>();

  final _fln = FlutterLocalNotificationsPlugin();
  bool _inited = false;
  String? _token;

  /// Percakapan yang sedang dibuka — notif untuk chat ini di-skip (foreground).
  String? activeConversationId;

  /// conversationId yang menunggu dibuka (mis. app baru dibuka dari notif).
  String? _pendingConversationId;

  static const _channel = AndroidNotificationChannel(
    'messages',
    'Pesan',
    description: 'Notifikasi pesan masuk',
    importance: Importance.high,
  );

  Future<void> init() async {
    if (kIsWeb) return; // FCM web butuh setup terpisah — lewati untuk sekarang
    try {
      if (!_inited) {
        await Firebase.initializeApp();
        await _fln.initialize(
          settings: const InitializationSettings(
            android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          ),
          onDidReceiveNotificationResponse: (resp) {
            final id = resp.payload;
            if (id != null && id.isNotEmpty) _openConversation(id);
          },
        );
        await _fln
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.createNotificationChannel(_channel);

        FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);
        await FirebaseMessaging.instance.requestPermission();

        // Foreground: tampilkan notif kecuali untuk chat yang sedang dibuka.
        FirebaseMessaging.onMessage.listen((m) async {
          final convId = m.data['conversationId'] as String?;
          if (convId != null && convId == activeConversationId) return;
          final n = m.notification;
          if (n == null) return;
          // Avatar pengirim sebagai large icon (ala WhatsApp).
          AndroidBitmap<Object>? largeIcon;
          final avatarUrl = m.data['avatarUrl'] as String?;
          if (avatarUrl != null && avatarUrl.isNotEmpty) {
            final bytes = await _downloadBytes(avatarUrl);
            if (bytes != null) largeIcon = ByteArrayAndroidBitmap(bytes);
          }
          _fln.show(
            id: n.hashCode,
            title: n.title,
            body: n.body,
            notificationDetails: NotificationDetails(
              android: AndroidNotificationDetails(
                'messages',
                'Pesan',
                importance: Importance.high,
                priority: Priority.high,
                icon: 'ic_notification',
                color: const Color(0xFF2563EB),
                largeIcon: largeIcon,
              ),
            ),
            payload: convId,
          );
        });

        // Tap notif saat app di background → buka chat.
        FirebaseMessaging.onMessageOpenedApp.listen(_handleTapMessage);

        // Tap notif saat app sebelumnya MATI → simpan untuk dibuka.
        final initial = await FirebaseMessaging.instance.getInitialMessage();
        if (initial != null) {
          final id = initial.data['conversationId'] as String?;
          if (id != null) _pendingConversationId = id;
        }

        _inited = true;
      }
      await _registerToken();
    } catch (_) {
      // abaikan (mis. tanpa google-services / belum dikonfigurasi)
    }
  }

  void _handleTapMessage(RemoteMessage m) {
    final id = m.data['conversationId'] as String?;
    if (id != null) _openConversation(id);
  }

  /// Dipanggil HomeScreen saat siap — buka chat yang tertunda (dari notif).
  void consumePending() {
    final id = _pendingConversationId;
    if (id != null) {
      _pendingConversationId = null;
      _openConversation(id);
    }
  }

  Future<void> _openConversation(String conversationId) async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      _pendingConversationId = conversationId; // app belum siap
      return;
    }
    try {
      final chat = ctx.read<ChatProvider>();
      var conv = chat.conversationById(conversationId);
      if (conv == null) {
        await chat.loadConversations();
        conv = chat.conversationById(conversationId);
      }
      if (conv != null) {
        navigatorKey.currentState?.push(
          MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv!)),
        );
      }
    } catch (_) {}
  }

  Future<Uint8List?> _downloadBytes(String url) async {
    try {
      final res = await Dio().get<List<int>>(
        url,
        options: Options(responseType: ResponseType.bytes),
      );
      final data = res.data;
      if (data != null) return Uint8List.fromList(data);
    } catch (_) {}
    return null;
  }

  Future<void> _registerToken() async {
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null && token != _token) {
        _token = token;
        await ApiClient.instance.dio
            .post('/notifications/token', data: {'token': token});
      }
    } catch (_) {}
  }

  Future<void> unregister() async {
    if (_token == null) return;
    try {
      await ApiClient.instance.dio
          .delete('/notifications/token', data: {'token': _token});
    } catch (_) {}
    _token = null;
  }
}
