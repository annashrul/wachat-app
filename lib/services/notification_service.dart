import 'dart:convert';
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
import 'app_badge.dart';

/// Channel notifikasi pesan (dipakai di main & background isolate).
const AndroidNotificationChannel _messagesChannel = AndroidNotificationChannel(
  'messages',
  'Pesan',
  description: 'Notifikasi pesan masuk',
  importance: Importance.high,
);

/// Channel khusus panggilan (prioritas maksimum + tampil di atas layar kunci).
const AndroidNotificationChannel _callsChannel = AndroidNotificationChannel(
  'calls',
  'Panggilan',
  description: 'Panggilan suara masuk',
  importance: Importance.max,
);

/// Satu instance plugin dipakai bersama (tiap isolate punya salinannya sendiri).
final FlutterLocalNotificationsPlugin _plugin =
    FlutterLocalNotificationsPlugin();
bool _pluginReady = false;

/// Pastikan plugin lokal siap (idempoten) — aman dipanggil di kedua isolate.
Future<void> _ensurePlugin() async {
  if (_pluginReady) return;
  await _plugin.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    ),
    onDidReceiveNotificationResponse: (resp) {
      if (resp.actionId == 'call_decline') return; // tolak: cukup ditutup
      final p = resp.payload;
      if (p != null && p.isNotEmpty) _routePayload(p);
    },
  );
  final android = _plugin.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  await android?.createNotificationChannel(_messagesChannel);
  await android?.createNotificationChannel(_callsChannel);
  _pluginReady = true;
}

/// Arahkan aksi tap notifikasi. Payload pesan = conversationId (string biasa);
/// payload panggilan = JSON {type:'call', ...}.
void _routePayload(String payload) {
  if (payload.startsWith('{')) {
    try {
      final m = jsonDecode(payload) as Map<String, dynamic>;
      if (m['type'] == 'call') {
        NotificationService.instance.routeCallPush(m);
        return;
      }
    } catch (_) {}
  }
  NotificationService.instance.openConversation(payload);
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

/// Bangun & tampilkan notifikasi gaya WhatsApp (avatar + nama + pesan + waktu)
/// dari payload data FCM. Top-level agar bisa dipanggil dari background isolate.
Future<void> showWhatsAppNotification(Map<String, dynamic> data,
    {int? badgeNumber}) async {
  final convId = (data['conversationId'] as String?) ?? '';
  final title = (data['title'] as String?) ?? 'Pesan baru';
  final fallbackBody = (data['body'] as String?) ?? '';
  final senderName = (data['senderName'] as String?) ?? title;
  // 'preview' = teks pesan mentah; di grup MessagingStyle menambah nama sendiri.
  final messageText = (data['preview'] as String?) ?? fallbackBody;
  final avatarUrl = (data['avatarUrl'] as String?) ?? '';
  final isGroup = (data['isGroup'] as String?) == 'true';
  final sentAt = int.tryParse((data['sentAt'] as String?) ?? '');

  await _ensurePlugin();

  Uint8List? avatarBytes;
  if (avatarUrl.isNotEmpty) {
    avatarBytes = await _downloadBytes(avatarUrl);
  }
  final avatarIcon =
      avatarBytes == null ? null : ByteArrayAndroidIcon(avatarBytes);

  // "me" berbeda dari pengirim → pesan dianggap masuk (tampil avatar+nama).
  const me = Person(key: 'me', name: 'Saya');
  final sender = Person(key: senderName, name: senderName, icon: avatarIcon);
  final when = sentAt != null
      ? DateTime.fromMillisecondsSinceEpoch(sentAt)
      : DateTime.now();

  final style = MessagingStyleInformation(
    me,
    conversationTitle: isGroup ? title : null,
    groupConversation: isGroup,
    messages: [Message(messageText, when, sender)],
  );

  final android = AndroidNotificationDetails(
    'messages',
    'Pesan',
    channelDescription: 'Notifikasi pesan masuk',
    importance: Importance.high,
    priority: Priority.high,
    icon: 'ic_notification',
    color: const Color(0xFF2563EB),
    category: AndroidNotificationCategory.message,
    styleInformation: style,
    number: badgeNumber, // jumlah untuk badge ikon launcher
    largeIcon:
        avatarBytes == null ? null : ByteArrayAndroidBitmap(avatarBytes),
  );

  await _plugin.show(
    id: convId.isEmpty ? 0 : convId.hashCode,
    title: title,
    body: fallbackBody,
    notificationDetails: NotificationDetails(android: android),
    payload: convId,
  );
}

/// Notifikasi panggilan masuk (layar penuh, prioritas maksimum) saat app
/// di background/mati. Ketuk → buka app & tampilkan layar panggilan masuk.
Future<void> showCallNotification(Map<String, dynamic> data) async {
  await _ensurePlugin();
  final callerName =
      (data['senderName'] as String?) ?? (data['title'] as String?) ?? 'Seseorang';
  final avatarUrl = (data['avatarUrl'] as String?) ?? '';
  Uint8List? bytes;
  if (avatarUrl.isNotEmpty) bytes = await _downloadBytes(avatarUrl);

  final payload = jsonEncode({
    'type': 'call',
    'callerId': data['callerId'] ?? '',
    'name': callerName,
    'avatar': avatarUrl,
    'conversationId': data['conversationId'] ?? '',
  });

  final android = AndroidNotificationDetails(
    'calls',
    'Panggilan',
    channelDescription: 'Panggilan suara masuk',
    importance: Importance.max,
    priority: Priority.max,
    category: AndroidNotificationCategory.call,
    fullScreenIntent: true,
    ongoing: true,
    autoCancel: false,
    icon: 'ic_notification',
    color: const Color(0xFF2563EB),
    largeIcon: bytes == null ? null : ByteArrayAndroidBitmap(bytes),
    actions: const [
      AndroidNotificationAction('call_decline', 'Tolak',
          cancelNotification: true),
      AndroidNotificationAction('call_accept', 'Terima',
          showsUserInterface: true, cancelNotification: true),
    ],
  );

  await _plugin.show(
    id: 'call'.hashCode,
    title: callerName,
    body: 'Panggilan suara masuk',
    notificationDetails: NotificationDetails(android: android),
    payload: payload,
  );
}

/// Handler pesan FCM saat app di background/mati — bangun notifikasi kaya.
@pragma('vm:entry-point')
Future<void> _firebaseBgHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
  if (message.data['type'] == 'call') {
    await showCallNotification(message.data);
  } else {
    // Naikkan badge ikon launcher (app tertutup → hitung sendiri).
    final n = await AppBadge.increment();
    await showWhatsAppNotification(message.data, badgeNumber: n);
  }
}

class NotificationService {
  NotificationService._();
  static final NotificationService instance = NotificationService._();

  /// Dipakai MaterialApp agar bisa navigasi dari luar widget tree.
  static final navigatorKey = GlobalKey<NavigatorState>();

  bool _inited = false;
  String? _token;

  /// Percakapan yang sedang dibuka — notif untuk chat ini di-skip (foreground).
  String? activeConversationId;

  /// conversationId yang menunggu dibuka (mis. app baru dibuka dari notif).
  String? _pendingConversationId;

  /// Panggilan yang menunggu ditampilkan (app dibuka dari notif panggilan).
  Map<String, dynamic>? _pendingCall;

  /// Dipasang oleh CallProvider — menampilkan layar panggilan masuk dari push.
  void Function(Map<String, dynamic> call)? onIncomingCall;

  Future<void> init() async {
    if (kIsWeb) return; // FCM web butuh setup terpisah — lewati untuk sekarang
    try {
      if (!_inited) {
        await Firebase.initializeApp();
        await _ensurePlugin();

        FirebaseMessaging.onBackgroundMessage(_firebaseBgHandler);
        await FirebaseMessaging.instance.requestPermission();

        // Foreground: panggilan ditangani via socket (UI in-app), jadi push
        // call diabaikan. Pesan biasa tetap ditampilkan (kecuali chat aktif).
        FirebaseMessaging.onMessage.listen((m) async {
          if (m.data['type'] == 'call') return;
          final convId = m.data['conversationId'] as String?;
          if (convId != null && convId == activeConversationId) return;
          await showWhatsAppNotification(m.data);
        });

        // Tap notif (FLN) saat app sebelumnya MATI → buka chat / panggilan.
        final launch = await _plugin.getNotificationAppLaunchDetails();
        if (launch?.didNotificationLaunchApp == true &&
            launch!.notificationResponse?.actionId != 'call_decline') {
          final p = launch.notificationResponse?.payload;
          if (p != null && p.isNotEmpty) {
            if (p.startsWith('{')) {
              try {
                final m = jsonDecode(p) as Map<String, dynamic>;
                if (m['type'] == 'call') _pendingCall = m;
              } catch (_) {}
            } else {
              _pendingConversationId = p;
            }
          }
        }

        _inited = true;
      }
      // Bila app dibuka dari notif panggilan & CallProvider sudah siap.
      consumePendingCall();
      await _registerToken();
    } catch (_) {
      // abaikan (mis. tanpa google-services / belum dikonfigurasi)
    }
  }

  /// Dipanggil HomeScreen saat siap — buka chat yang tertunda (dari notif).
  void consumePending() {
    final id = _pendingConversationId;
    if (id != null) {
      _pendingConversationId = null;
      openConversation(id);
    }
  }

  /// Dipanggil CallProvider saat siap — tampilkan panggilan tertunda (dari push).
  void consumePendingCall() {
    final c = _pendingCall;
    if (c != null && onIncomingCall != null) {
      _pendingCall = null;
      onIncomingCall!(c);
    }
  }

  /// Tampilkan panggilan masuk dari push (app hidup). Jika belum siap, simpan.
  void routeCallPush(Map<String, dynamic> call) {
    if (onIncomingCall != null) {
      onIncomingCall!(call);
    } else {
      _pendingCall = call;
    }
  }

  Future<void> openConversation(String conversationId) async {
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
