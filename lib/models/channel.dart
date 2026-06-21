/// Ringkasan saluran (channel) untuk daftar temukan/diikuti.
class ChannelSummary {
  final String id;
  final String title;
  final String? description;
  final String? avatarUrl;
  final int followerCount;
  final bool following;
  final bool isAdmin;

  ChannelSummary({
    required this.id,
    required this.title,
    this.description,
    this.avatarUrl,
    this.followerCount = 0,
    this.following = false,
    this.isAdmin = false,
  });

  factory ChannelSummary.fromJson(Map<String, dynamic> j) => ChannelSummary(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Saluran',
        description: j['description'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        followerCount: (j['followerCount'] as num?)?.toInt() ?? 0,
        following: j['following'] == true,
        isAdmin: j['isAdmin'] == true,
      );
}
