class AppUser {
  final String id;
  final String phone;
  final String displayName;
  final String? avatarUrl;
  final String? about;
  final DateTime? lastSeen;
  final bool twoFactorEnabled;

  AppUser({
    required this.id,
    required this.phone,
    required this.displayName,
    this.avatarUrl,
    this.about,
    this.lastSeen,
    this.twoFactorEnabled = false,
  });

  factory AppUser.fromJson(Map<String, dynamic> json) {
    return AppUser(
      id: json['id'] as String,
      phone: json['phone'] as String? ?? '',
      displayName: json['displayName'] as String? ?? 'Pengguna',
      avatarUrl: json['avatarUrl'] as String?,
      about: json['about'] as String?,
      lastSeen: json['lastSeen'] != null
          ? DateTime.tryParse(json['lastSeen'] as String)
          : null,
      twoFactorEnabled: json['twoFactorEnabled'] == true,
    );
  }

  AppUser copyWithTwoFactor(bool enabled) => AppUser(
        id: id,
        phone: phone,
        displayName: displayName,
        avatarUrl: avatarUrl,
        about: about,
        lastSeen: lastSeen,
        twoFactorEnabled: enabled,
      );
}
