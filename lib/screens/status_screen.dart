import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import '../models/status.dart';
import '../models/user.dart';
import '../providers/auth_provider.dart';
import '../providers/status_provider.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import 'status_compose_screen.dart';
import 'status_view_screen.dart';

class StatusScreen extends StatefulWidget {
  const StatusScreen({super.key});

  @override
  State<StatusScreen> createState() => _StatusScreenState();
}

class _StatusScreenState extends State<StatusScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<StatusProvider>().loadFeed();
    });
  }

  Future<void> _addImage() async {
    final picked = await ImagePicker().pickImage(source: ImageSource.gallery);
    if (picked == null || !mounted) return;
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => StatusComposeScreen(image: picked)),
    );
    // Feed diperbarui otomatis lewat socket; muat ulang sebagai cadangan.
    if (mounted) context.read<StatusProvider>().loadFeed();
  }

  Future<void> _addText() async {
    await Navigator.of(context).push<bool>(
      MaterialPageRoute(builder: (_) => const StatusComposeScreen()),
    );
    if (mounted) context.read<StatusProvider>().loadFeed();
  }

  void _viewMine(AppUser me, List<StatusItem> mine) {
    if (mine.isEmpty) {
      _addImage();
      return;
    }
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => StatusViewScreen(
            stories: [StatusStory(user: me, statuses: mine, isMine: true)],
          ),
        ))
        .then((_) {
      if (mounted) context.read<StatusProvider>().loadFeed();
    });
  }

  void _viewEntry(StatusEntry e) {
    final others = context.read<StatusProvider>().feed.others;
    final stories = others
        .map((x) => StatusStory(user: x.user, statuses: x.statuses))
        .toList();
    final start = others.indexWhere((x) => x.user.id == e.user.id);
    Navigator.of(context)
        .push(MaterialPageRoute(
          builder: (_) => StatusViewScreen(
            stories: stories,
            startIndex: start < 0 ? 0 : start,
          ),
        ))
        .then((_) {
      if (mounted) context.read<StatusProvider>().loadFeed();
    });
  }

  static String _ago(DateTime dt) {
    final d = DateTime.now().difference(dt);
    if (d.inMinutes < 1) return 'Baru saja';
    if (d.inMinutes < 60) return '${d.inMinutes} mnt lalu';
    if (d.inHours < 24) return '${d.inHours} jam lalu';
    return 'Kemarin';
  }

  @override
  Widget build(BuildContext context) {
    final palette = AppPalette.of(context);
    final scheme = Theme.of(context).colorScheme;
    final me = context.read<AuthProvider>().user;
    final status = context.watch<StatusProvider>();
    final mine = status.feed.mine;
    final others = status.feed.others;

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        toolbarHeight: 64,
        titleSpacing: 20,
        title: const Text('Status',
            style: TextStyle(fontWeight: FontWeight.w800, fontSize: 24)),
      ),
      floatingActionButton: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton.small(
            heroTag: 'status_text',
            onPressed: _addText,
            child: const Icon(Icons.edit_rounded),
          ),
          const SizedBox(height: 12),
          FloatingActionButton(
            heroTag: 'status_cam',
            onPressed: _addImage,
            child: const Icon(Icons.photo_camera_rounded),
          ),
        ],
      ),
      body: status.loading && mine.isEmpty && others.isEmpty
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () => context.read<StatusProvider>().loadFeed(),
              child: ListView(
                children: [
                  ListTile(
                    leading: _ringedAvatar(
                      url: me?.avatarUrl,
                      name: me?.displayName ?? 'Saya',
                      ringColor: mine.isEmpty ? null : scheme.primary,
                      showAdd: mine.isEmpty,
                    ),
                    title: const Text('Status saya',
                        style: TextStyle(fontWeight: FontWeight.w700)),
                    subtitle: Text(
                      mine.isEmpty
                          ? 'Ketuk untuk menambah pembaruan status'
                          : '${mine.length} pembaruan · ${_ago(mine.last.createdAt)}',
                      style: TextStyle(color: palette.muted, fontSize: 12.5),
                    ),
                    onTap: me == null ? null : () => _viewMine(me, mine),
                  ),
                  Divider(height: 1, color: palette.cardBorder),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(18, 14, 18, 6),
                    child: Text('Pembaruan terkini',
                        style: TextStyle(
                            color: palette.muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5)),
                  ),
                  if (others.isEmpty)
                    Padding(
                      padding: const EdgeInsets.all(28),
                      child: Center(
                        child: Text('Belum ada pembaruan',
                            style: TextStyle(color: palette.muted)),
                      ),
                    )
                  else
                    ...others.map((e) => ListTile(
                          leading: _ringedAvatar(
                            url: e.user.avatarUrl,
                            name: e.user.displayName,
                            ringColor: e.hasUnseen
                                ? scheme.primary
                                : palette.muted.withValues(alpha: 0.5),
                          ),
                          title: Text(e.user.displayName,
                              style:
                                  const TextStyle(fontWeight: FontWeight.w600)),
                          subtitle: Text(_ago(e.lastAt),
                              style: TextStyle(
                                  color: palette.muted, fontSize: 12.5)),
                          onTap: () => _viewEntry(e),
                        )),
                ],
              ),
            ),
    );
  }

  Widget _ringedAvatar({
    required String? url,
    required String name,
    Color? ringColor,
    bool showAdd = false,
  }) {
    return SizedBox(
      width: 52,
      height: 52,
      child: Stack(
        children: [
          Container(
            padding: const EdgeInsets.all(2.5),
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                color: ringColor ?? Colors.transparent,
                width: 2.2,
              ),
            ),
            child: Avatar(url: url, name: name, radius: 21),
          ),
          if (showAdd)
            Positioned(
              right: 0,
              bottom: 0,
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.primary,
                  shape: BoxShape.circle,
                  border: Border.all(
                      color: Theme.of(context).colorScheme.surface, width: 2),
                ),
                child: const Icon(Icons.add_rounded,
                    color: Colors.white, size: 16),
              ),
            ),
        ],
      ),
    );
  }
}
