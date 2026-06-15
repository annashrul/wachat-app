import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Siapa yang boleh melihat sebuah informasi (status, terakhir dilihat, dll).
enum Audience { everyone, contacts, nobody }

extension AudienceLabel on Audience {
  String get label => switch (this) {
        Audience.everyone => 'Semua orang',
        Audience.contacts => 'Kontak saya',
        Audience.nobody => 'Tidak ada',
      };

  String get icon => name; // dipakai bila perlu

  static Audience fromName(String? name) => Audience.values.firstWhere(
        (a) => a.name == name,
        orElse: () => Audience.everyone,
      );
}

/// Pengaturan aplikasi (tema, privasi, notifikasi) — disimpan di perangkat
/// memakai SharedPreferences sehingga bertahan antar sesi.
class SettingsProvider extends ChangeNotifier {
  // ---- Tema ----
  static const _kTheme = 'theme_mode';
  ThemeMode themeMode = ThemeMode.system;

  // ---- Privasi ----
  static const _kStatusAudience = 'privacy_status';
  static const _kLastSeenAudience = 'privacy_last_seen';
  static const _kPhotoAudience = 'privacy_photo';
  static const _kAboutAudience = 'privacy_about';
  static const _kReadReceipts = 'privacy_read_receipts';

  Audience statusAudience = Audience.contacts;
  Audience lastSeenAudience = Audience.everyone;
  Audience profilePhotoAudience = Audience.everyone;
  Audience aboutAudience = Audience.everyone;
  bool readReceipts = true;

  // ---- Notifikasi ----
  static const _kMsgNotif = 'notif_messages';
  static const _kNotifSound = 'notif_sound';
  static const _kNotifVibrate = 'notif_vibrate';
  static const _kNotifPreview = 'notif_preview';
  static const _kGroupNotif = 'notif_groups';
  static const _kCallNotif = 'notif_calls';
  static const _kStatusNotif = 'notif_status';
  static const _kInAppSounds = 'notif_in_app';

  bool messageNotifications = true;
  bool notificationSound = true;
  bool notificationVibrate = true;
  bool showPreview = true;
  bool groupNotifications = true;
  bool callNotifications = true;
  bool statusNotifications = true;
  bool inAppSounds = true;

  Future<void> load() async {
    final prefs = await SharedPreferences.getInstance();

    // Tema
    switch (prefs.getString(_kTheme)) {
      case 'light':
        themeMode = ThemeMode.light;
        break;
      case 'dark':
        themeMode = ThemeMode.dark;
        break;
      default:
        themeMode = ThemeMode.system;
    }

    // Privasi
    statusAudience = AudienceLabel.fromName(prefs.getString(_kStatusAudience));
    lastSeenAudience =
        AudienceLabel.fromName(prefs.getString(_kLastSeenAudience));
    profilePhotoAudience =
        AudienceLabel.fromName(prefs.getString(_kPhotoAudience));
    aboutAudience = AudienceLabel.fromName(prefs.getString(_kAboutAudience));
    readReceipts = prefs.getBool(_kReadReceipts) ?? true;

    // Notifikasi
    messageNotifications = prefs.getBool(_kMsgNotif) ?? true;
    notificationSound = prefs.getBool(_kNotifSound) ?? true;
    notificationVibrate = prefs.getBool(_kNotifVibrate) ?? true;
    showPreview = prefs.getBool(_kNotifPreview) ?? true;
    groupNotifications = prefs.getBool(_kGroupNotif) ?? true;
    callNotifications = prefs.getBool(_kCallNotif) ?? true;
    statusNotifications = prefs.getBool(_kStatusNotif) ?? true;
    inAppSounds = prefs.getBool(_kInAppSounds) ?? true;

    notifyListeners();
  }

  // ---- Tema ----
  Future<void> setThemeMode(ThemeMode mode) async {
    themeMode = mode;
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kTheme, mode.name);
  }

  String get themeLabel => switch (themeMode) {
        ThemeMode.light => 'Terang',
        ThemeMode.dark => 'Gelap',
        ThemeMode.system => 'Ikuti sistem',
      };

  // ---- Privasi ----
  Future<void> setStatusAudience(Audience a) =>
      _setAudience(_kStatusAudience, a, (v) => statusAudience = v);
  Future<void> setLastSeenAudience(Audience a) =>
      _setAudience(_kLastSeenAudience, a, (v) => lastSeenAudience = v);
  Future<void> setProfilePhotoAudience(Audience a) =>
      _setAudience(_kPhotoAudience, a, (v) => profilePhotoAudience = v);
  Future<void> setAboutAudience(Audience a) =>
      _setAudience(_kAboutAudience, a, (v) => aboutAudience = v);

  Future<void> setReadReceipts(bool v) =>
      _setBool(_kReadReceipts, v, (x) => readReceipts = x);

  // ---- Notifikasi ----
  Future<void> setMessageNotifications(bool v) =>
      _setBool(_kMsgNotif, v, (x) => messageNotifications = x);
  Future<void> setNotificationSound(bool v) =>
      _setBool(_kNotifSound, v, (x) => notificationSound = x);
  Future<void> setNotificationVibrate(bool v) =>
      _setBool(_kNotifVibrate, v, (x) => notificationVibrate = x);
  Future<void> setShowPreview(bool v) =>
      _setBool(_kNotifPreview, v, (x) => showPreview = x);
  Future<void> setGroupNotifications(bool v) =>
      _setBool(_kGroupNotif, v, (x) => groupNotifications = x);
  Future<void> setCallNotifications(bool v) =>
      _setBool(_kCallNotif, v, (x) => callNotifications = x);
  Future<void> setStatusNotifications(bool v) =>
      _setBool(_kStatusNotif, v, (x) => statusNotifications = x);
  Future<void> setInAppSounds(bool v) =>
      _setBool(_kInAppSounds, v, (x) => inAppSounds = x);

  // ---- Helper ----
  Future<void> _setAudience(
      String key, Audience value, void Function(Audience) assign) async {
    assign(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(key, value.name);
  }

  Future<void> _setBool(
      String key, bool value, void Function(bool) assign) async {
    assign(value);
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(key, value);
  }
}
