import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/conversation.dart';
import '../providers/auth_provider.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'profile_view_screen.dart';

/// Info grup: nama, jumlah anggota, daftar anggota (tap → profil anggota).
class GroupInfoScreen extends StatelessWidget {
  final Conversation conversation;
  const GroupInfoScreen({super.key, required this.conversation});

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final myId = context.read<AuthProvider>().userId;
    final members = conversation.members;
    return Scaffold(
      appBar: AppBar(title: const Text('Info Grup')),
      body: ListView(
        children: [
          const SizedBox(height: 24),
          Center(
            child: Avatar(
              url: conversation.avatarUrl,
              name: conversation.title,
              radius: 56,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              conversation.title,
              style: const TextStyle(fontSize: 21, fontWeight: FontWeight.w700),
            ),
          ),
          const SizedBox(height: 4),
          Center(
            child: Text(
              'Grup · ${members.length} anggota',
              style: TextStyle(color: palette.muted),
            ),
          ),
          const SizedBox(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: Text(
              '${members.length} ANGGOTA',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: palette.muted,
              ),
            ),
          ),
          ...members.map((u) {
            final isMe = u.id == myId;
            return ListTile(
              leading: Avatar(url: u.avatarUrl, name: u.displayName),
              title: Text(isMe ? 'Anda' : u.displayName,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              subtitle: Text(u.about ?? u.phone,
                  maxLines: 1, overflow: TextOverflow.ellipsis),
              onTap: isMe
                  ? null
                  : () => Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => ProfileViewScreen(user: u),
                        ),
                      ),
            );
          }),
        ],
      ),
    );
  }
}
