/// Ringkasan komunitas untuk daftar.
class CommunitySummary {
  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String? announcementId;

  CommunitySummary({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    this.announcementId,
  });

  factory CommunitySummary.fromJson(Map<String, dynamic> j) => CommunitySummary(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Komunitas',
        description: j['description'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        announcementId: j['announcementId'] as String?,
      );
}

/// Satu grup di dalam komunitas.
class CommunityGroup {
  final String id;
  final String title;
  final bool isAnnouncement;
  final int memberCount;
  final bool joined;

  CommunityGroup({
    required this.id,
    required this.title,
    this.isAnnouncement = false,
    this.memberCount = 0,
    this.joined = false,
  });

  factory CommunityGroup.fromJson(Map<String, dynamic> j) => CommunityGroup(
        id: j['id'] as String,
        title: j['title'] as String? ?? 'Grup',
        isAnnouncement: j['isAnnouncement'] == true,
        memberCount: (j['memberCount'] as num?)?.toInt() ?? 0,
        joined: j['joined'] == true,
      );
}

/// Detail komunitas + daftar grup.
class CommunityDetail {
  final String id;
  final String name;
  final String? description;
  final String? avatarUrl;
  final String? announcementId;
  final bool isAdmin;
  final List<CommunityGroup> groups;

  CommunityDetail({
    required this.id,
    required this.name,
    this.description,
    this.avatarUrl,
    this.announcementId,
    this.isAdmin = false,
    this.groups = const [],
  });

  factory CommunityDetail.fromJson(Map<String, dynamic> j) => CommunityDetail(
        id: j['id'] as String,
        name: j['name'] as String? ?? 'Komunitas',
        description: j['description'] as String?,
        avatarUrl: j['avatarUrl'] as String?,
        announcementId: j['announcementId'] as String?,
        isAdmin: j['isAdmin'] == true,
        groups: ((j['groups'] as List?) ?? [])
            .map((e) => CommunityGroup.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
}
