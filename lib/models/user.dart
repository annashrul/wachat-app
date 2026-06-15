class AppUser {
  final String id;
  final String phone;
  final String displayName;
  final String? avatarUrl;
  final String? about;
  final DateTime? lastSeen;

  AppUser({
    required this.id,
    required this.phone,
    required this.displayName,
    this.avatarUrl,
    this.about,
    this.lastSeen,
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
    );
  }
}
