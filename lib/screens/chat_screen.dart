import 'dart:async';
import 'package:flutter/foundation.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:image_picker/image_picker.dart';
import 'package:file_picker/file_picker.dart';
import 'package:record/record.dart';
import 'package:path_provider/path_provider.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/user.dart';
import '../providers/settings_provider.dart';
import 'forward_screen.dart';
import 'profile_view_screen.dart';
import 'group_info_screen.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../providers/call_provider.dart';
import '../services/api_client.dart';
import '../theme.dart';
import '../widgets/avatar.dart';
import '../widgets/message_bubble.dart';
import '../widgets/typing_indicator.dart';
import '../widgets/sticker_picker.dart';
import '../widgets/voice_message.dart';

class ChatScreen extends StatefulWidget {
  final Conversation conversation;
  const ChatScreen({super.key, required this.conversation});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _input = TextEditingController();
  Message? _editing; // pesan yang sedang diedit
  List<AppUser> _mentionSuggestions = []; // autocomplete @mention (grup)
  int _mentionAt = -1; // posisi '@' yang sedang aktif
  final _scroll = ScrollController();
  late final ChatProvider _chatProv;
  bool _typingSent = false;
  bool _uploading = false;
  bool _hasText = false;
  int _initialUnread = 0;
  String? _lastBottomId;

  // Sticky date header.
  final _listKey = GlobalKey();
  final Map<String, GlobalKey> _dateChipKeys = {};
  final Map<String, String> _dateLabels = {};
  String? _stickyDate;

  // Back-to-bottom + pencarian dalam chat.
  bool _showJump = false;
  bool _searching = false;
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  List<Message> _searchResults = []; // hasil cari ke backend (semua pesan)
  int _matchPos = -1;
  bool _searchLoading = false;
  Timer? _searchDebounce;
  final Map<String, GlobalKey> _msgKeys = {};

  // Rekam pesan suara.
  final _recorder = AudioRecorder();
  bool _recording = false;
  bool _recordBlink = false;
  int _recordSecs = 0;
  Timer? _recordTimer;
  // Preview sebelum kirim (ala WhatsApp): hasil rekaman yang siap didengar.
  String? _recordedPath;
  int _recordedSecs = 0;

  // Sorot sementara pesan tujuan (saat kutipan reply diketuk).
  String? _flashId;
  Timer? _flashTimer;
  bool _scrollingToMsg = false; // cegah lompatan tumpang-tindih

  String get _convId => widget.conversation.id;

  @override
  void initState() {
    super.initState();
    _chatProv = context.read<ChatProvider>();
    // Tangkap jumlah unread SEBELUM ditandai terbaca (untuk penanda "pesan baru").
    _initialUnread = widget.conversation.unreadCount;
    // Pulihkan draft yang belum terkirim.
    final draft = _chatProv.getDraft(_convId);
    if (draft.isNotEmpty) {
      _input.text = draft;
      _hasText = true;
    }
    _input.addListener(() {
      final has = _input.text.trim().isNotEmpty;
      if (has != _hasText) setState(() => _hasText = has);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _chatProv.openConversation(_convId);
      _scrollToBottom();
      _updateSticky();
    });
  }

  @override
  void dispose() {
    // Simpan teks yang belum terkirim sebagai draft.
    _chatProv.setDraft(_convId, _input.text);
    _chatProv.closeConversation();
    _input.dispose();
    _searchCtrl.dispose();
    _searchDebounce?.cancel();
    _recordTimer?.cancel();
    _flashTimer?.cancel();
    _recorder.dispose();
    _scroll.dispose();
    super.dispose();
  }

  // Mode reverse: bawah (terbaru) = offset 0, atas (terlama) = maxScrollExtent.
  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  /// Muat pesan lama saat mendekati atas. Karena list reverse, menambah item
  /// di atas TIDAK menggeser tampilan → mulus tanpa kompensasi.
  void _onScrollCheck() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    if (pos.pixels >= pos.maxScrollExtent - 400 &&
        _chatProv.hasMore &&
        !_chatProv.loadingMore) {
      _chatProv.loadMore(_convId);
    }
  }

  /// Scroll ke bawah hanya jika user sedang dekat bawah, atau dia pengirimnya.
  void _maybeAutoScroll(bool lastMine) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      final pos = _scroll.position;
      final nearBottom = pos.pixels < 250; // dekat offset 0 = dekat bawah
      if (lastMine || nearBottom) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onInputChanged(String v) {
    final chat = context.read<ChatProvider>();
    final typing = v.trim().isNotEmpty;
    if (typing != _typingSent) {
      _typingSent = typing;
      chat.setTyping(_convId, typing);
    }
    _updateMentions(v, chat);
  }

  void _updateMentions(String v, ChatProvider chat) {
    final conv = chat.conversationById(_convId);
    List<AppUser> sugg = [];
    int at = -1;
    if (conv != null && conv.isGroup) {
      final sel = _input.selection.baseOffset;
      final cursor = (sel < 0 || sel > v.length) ? v.length : sel;
      final upto = v.substring(0, cursor);
      final i = upto.lastIndexOf('@');
      // '@' di awal atau didahului spasi, dan query tanpa spasi.
      if (i >= 0 && (i == 0 || upto[i - 1] == ' ')) {
        final query = upto.substring(i + 1);
        if (!query.contains(' ') && !query.contains('\n')) {
          final myId = context.read<AuthProvider>().userId;
          final q = query.toLowerCase();
          sugg = conv.members
              .where((u) =>
                  u.id != myId &&
                  u.displayName.toLowerCase().contains(q))
              .take(6)
              .toList();
          at = i;
        }
      }
    }
    final changed = sugg.length != _mentionSuggestions.length ||
        at != _mentionAt ||
        (sugg.isNotEmpty &&
            _mentionSuggestions.isNotEmpty &&
            sugg.first.id != _mentionSuggestions.first.id);
    if (changed) {
      setState(() {
        _mentionSuggestions = sugg;
        _mentionAt = at;
      });
    }
  }

  void _insertMention(AppUser u) {
    final v = _input.text;
    final sel = _input.selection.baseOffset;
    final cursor = (sel < 0 || sel > v.length) ? v.length : sel;
    if (_mentionAt < 0) return;
    final before = v.substring(0, _mentionAt);
    final after = v.substring(cursor);
    final inserted = '@${u.displayName} ';
    final newText = '$before$inserted$after';
    _input.value = TextEditingValue(
      text: newText,
      selection:
          TextSelection.collapsed(offset: (before + inserted).length),
    );
    setState(() {
      _mentionSuggestions = [];
      _mentionAt = -1;
    });
  }

  void _sendText() {
    final text = _input.text.trim();
    if (text.isEmpty) return;
    final chat = context.read<ChatProvider>();
    if (_editing != null) {
      chat.editMessage(_editing!.id, text);
      setState(() => _editing = null);
      _input.clear();
      return;
    }
    chat.sendText(_convId, text);
    _input.clear();
    _chatProv.setDraft(_convId, '');
    _typingSent = false;
    chat.setTyping(_convId, false);
    if (_mentionSuggestions.isNotEmpty) {
      setState(() {
        _mentionSuggestions = [];
        _mentionAt = -1;
      });
    }
    _scrollToBottom();
  }

  void _startEditing(Message m) {
    setState(() => _editing = m);
    _input.text = m.content ?? '';
    _input.selection =
        TextSelection.collapsed(offset: _input.text.length);
  }

  void _cancelEditing() {
    setState(() => _editing = null);
    _input.clear();
  }

  Future<void> _takePhoto() async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      final picker = ImagePicker();
      final picked = await picker.pickImage(
          source: ImageSource.camera, imageQuality: 85);
      if (picked == null) return;
      final bytes = await picked.readAsBytes();
      await _uploadAndSend(bytes, picked.name, 'IMAGE');
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Tidak bisa membuka kamera')));
    }
  }

  Future<void> _sendImage({bool viewOnce = false}) async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    await _uploadAndSend(bytes, picked.name, 'IMAGE', viewOnce: viewOnce);
  }

  /// Galeri: bisa pilih banyak foto → 1 foto kirim biasa, >1 jadi album.
  Future<void> _sendGallery() async {
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final picker = ImagePicker();
    final picks = await picker.pickMultiImage();
    if (picks.isEmpty) return;
    if (picks.length == 1) {
      final bytes = await picks.first.readAsBytes();
      await _uploadAndSend(bytes, picks.first.name, 'IMAGE');
      return;
    }
    setState(() => _uploading = true);
    try {
      final urls = <String>[];
      for (final p in picks.take(10)) {
        final up = await chat.service.uploadFile(await p.readAsBytes(), p.name);
        urls.add(up.url);
      }
      chat.sendAlbum(_convId, urls);
      _scrollToBottom();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _sendFile() async {
    final result = await FilePicker.pickFiles(withData: true);
    if (result == null || result.files.isEmpty) return;
    final f = result.files.first;
    if (f.bytes == null) return;
    await _uploadAndSend(f.bytes!, f.name, 'FILE');
  }

  Future<void> _uploadAndSend(
    List<int> bytes,
    String name,
    String type, {
    bool viewOnce = false,
  }) async {
    setState(() => _uploading = true);
    try {
      final chat = context.read<ChatProvider>();
      final up = await chat.service.uploadFile(bytes, name);
      chat.sendMedia(_convId,
          type: type,
          mediaUrl: up.url,
          mediaName: up.name,
          viewOnce: viewOnce);
      _scrollToBottom();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ===== Pesan suara =====
  Future<void> _startRecording() async {
    try {
      if (!await _recorder.hasPermission()) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Izin mikrofon ditolak')),
          );
        }
        return;
      }
      String path;
      if (kIsWeb) {
        path = 'voice.m4a'; // di web diabaikan (rekam ke memori)
      } else {
        final dir = await getTemporaryDirectory();
        path =
            '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      }
      await _recorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordSecs = 0;
        _recordBlink = true;
      });
      _recordTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) {
          setState(() {
            _recordSecs++;
            _recordBlink = !_recordBlink;
          });
        }
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal merekam: $e')));
      }
    }
  }

  /// Batal merekam (buang rekaman).
  Future<void> _cancelRecording() async {
    _recordTimer?.cancel();
    try {
      await _recorder.stop();
    } catch (_) {}
    if (mounted) setState(() => _recording = false);
  }

  /// Stop merekam → masuk mode PREVIEW (bisa didengarkan dulu sebelum kirim).
  Future<void> _stopRecording() async {
    _recordTimer?.cancel();
    final secs = _recordSecs;
    final messenger = ScaffoldMessenger.of(context);
    String? path;
    try {
      path = await _recorder.stop();
    } catch (_) {}
    if (!mounted) return;
    if (path == null || secs < 1) {
      setState(() => _recording = false);
      messenger.showSnackBar(
        const SnackBar(content: Text('Rekaman terlalu pendek')),
      );
      return;
    }
    setState(() {
      _recording = false;
      _recordedPath = path;
      _recordedSecs = secs;
    });
  }

  /// Buang hasil rekaman di preview.
  void _discardRecorded() {
    setState(() {
      _recordedPath = null;
      _recordedSecs = 0;
    });
  }

  /// Kirim rekaman dari preview.
  Future<void> _sendRecorded() async {
    final path = _recordedPath;
    final secs = _recordedSecs;
    if (path == null) return;
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _recordedPath = null;
      _recordedSecs = 0;
      _uploading = true;
    });
    try {
      final bytes = await XFile(path).readAsBytes();
      final name = 'voice_${DateTime.now().millisecondsSinceEpoch}.m4a';
      final up = await chat.service.uploadFile(bytes, name);
      chat.sendMedia(
        _convId,
        type: 'VOICE',
        mediaUrl: up.url,
        mediaName: name,
        content: secs.toString(),
      );
      _scrollToBottom();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showDisappearingDialog(Conversation conv) async {
    const opts = <(String, int)>[
      ('Mati', 0),
      ('24 jam', 86400),
      ('7 hari', 604800),
      ('90 hari', 7776000),
    ];
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final picked = await showDialog<int>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Pesan sementara'),
        children: [
          for (final o in opts)
            ListTile(
              title: Text(o.$1),
              trailing: conv.disappearingSeconds == o.$2
                  ? const Icon(Icons.check_rounded)
                  : null,
              onTap: () => Navigator.pop(context, o.$2),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await chat.setDisappearing(conv.id, picked);
    messenger.showSnackBar(SnackBar(
      content: Text(picked == 0
          ? 'Pesan sementara dimatikan'
          : 'Pesan baru akan hilang otomatis'),
    ));
  }

  Future<void> _openContact(String userId, String name) async {
    final chat = context.read<ChatProvider>();
    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      final conv = await chat.service.createDirect(userId);
      if (!mounted) return;
      navigator.push(
          MaterialPageRoute(builder: (_) => ChatScreen(conversation: conv)));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  Future<void> _createPoll() async {
    final qCtrl = TextEditingController();
    final opts = <TextEditingController>[
      TextEditingController(),
      TextEditingController(),
    ];
    final chat = context.read<ChatProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => StatefulBuilder(
        builder: (_, setDlg) => AlertDialog(
          title: const Text('Buat polling'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextField(
                  controller: qCtrl,
                  decoration: const InputDecoration(labelText: 'Pertanyaan'),
                ),
                const SizedBox(height: 8),
                for (var i = 0; i < opts.length; i++)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: TextField(
                      controller: opts[i],
                      decoration:
                          InputDecoration(labelText: 'Opsi ${i + 1}'),
                    ),
                  ),
                if (opts.length < 8)
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      icon: const Icon(Icons.add_rounded),
                      label: const Text('Tambah opsi'),
                      onPressed: () =>
                          setDlg(() => opts.add(TextEditingController())),
                    ),
                  ),
              ],
            ),
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('Batal')),
            TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('Kirim')),
          ],
        ),
      ),
    );
    if (ok != true) return;
    final q = qCtrl.text.trim();
    final options =
        opts.map((c) => c.text.trim()).where((t) => t.isNotEmpty).toList();
    if (q.isEmpty || options.length < 2) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Isi pertanyaan & minimal 2 opsi')));
      }
      return;
    }
    chat.sendPoll(_convId, q, options);
    _scrollToBottom();
  }

  Future<void> _sendContact() async {
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    List<({String id, String? alias, AppUser user})> contacts = [];
    try {
      contacts = await chat.service.getContacts();
    } catch (_) {}
    if (!mounted) return;
    if (contacts.isEmpty) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Belum ada kontak')));
      return;
    }
    final picked = await showModalBottomSheet<AppUser>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.6,
        builder: (_, controller) => ListView(
          controller: controller,
          children: [
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text('Kirim kontak',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
            ),
            for (final c in contacts)
              ListTile(
                leading: Avatar(
                    url: c.user.avatarUrl,
                    name: c.user.displayName,
                    radius: 20),
                title: Text(c.alias ?? c.user.displayName),
                subtitle: Text(c.user.phone),
                onTap: () => Navigator.pop(context, c.user),
              ),
          ],
        ),
      ),
    );
    if (picked == null) return;
    final json = jsonEncode({
      'name': picked.displayName,
      'phone': picked.phone,
      'userId': picked.id,
    });
    chat.sendContact(_convId, json);
    _scrollToBottom();
  }

  Future<void> _sendLocation() async {
    final messenger = ScaffoldMessenger.of(context);
    final chat = context.read<ChatProvider>();
    try {
      if (!await Geolocator.isLocationServiceEnabled()) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Aktifkan GPS/lokasi dulu')));
        return;
      }
      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
      }
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        messenger.showSnackBar(
            const SnackBar(content: Text('Izin lokasi ditolak')));
        return;
      }
      final pos = await Geolocator.getCurrentPosition();
      chat.sendLocation(_convId, pos.latitude, pos.longitude);
    } catch (_) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Gagal mengambil lokasi')));
    }
  }

  void _showAttachMenu() {
    final scheme = Theme.of(context).colorScheme;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Wrap(
            alignment: WrapAlignment.spaceEvenly,
            runSpacing: 8,
            children: [
              _attachOption(
                icon: Icons.photo_camera_rounded,
                label: 'Kamera',
                color: const Color(0xFFEC4899),
                onTap: () {
                  Navigator.pop(context);
                  _takePhoto();
                },
              ),
              _attachOption(
                icon: Icons.image_rounded,
                label: 'Galeri',
                color: scheme.primary,
                onTap: () {
                  Navigator.pop(context);
                  _sendGallery();
                },
              ),
              _attachOption(
                icon: Icons.description_rounded,
                label: 'Dokumen',
                color: const Color(0xFF8B5CF6),
                onTap: () {
                  Navigator.pop(context);
                  _sendFile();
                },
              ),
              _attachOption(
                icon: Icons.location_on_rounded,
                label: 'Lokasi',
                color: const Color(0xFF22C55E),
                onTap: () {
                  Navigator.pop(context);
                  _sendLocation();
                },
              ),
              _attachOption(
                icon: Icons.timer_rounded,
                label: 'Sekali lihat',
                color: const Color(0xFFF59E0B),
                onTap: () {
                  Navigator.pop(context);
                  _sendImage(viewOnce: true);
                },
              ),
              _attachOption(
                icon: Icons.person_rounded,
                label: 'Kontak',
                color: const Color(0xFF0EA5E9),
                onTap: () {
                  Navigator.pop(context);
                  _sendContact();
                },
              ),
              _attachOption(
                icon: Icons.poll_rounded,
                label: 'Polling',
                color: const Color(0xFF14B8A6),
                onTap: () {
                  Navigator.pop(context);
                  _createPoll();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachOption({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                color: color.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Icon(icon, color: color, size: 28),
            ),
            const SizedBox(height: 8),
            Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chat = context.watch<ChatProvider>();
    final myId = context.read<AuthProvider>().userId;
    final isGroup = widget.conversation.isGroup;
    final palette = AppPalette.of(context);

    // Auto-scroll HANYA saat pesan TERBAWAH (terbaru) berubah — yaitu ada
    // pesan baru masuk/terkirim. Memuat pesan lama (prepend di atas) TIDAK
    // mengubah pesan terbawah → tidak memicu scroll ke bawah.
    final newest = chat.messages.isNotEmpty ? chat.messages.last : null;
    if (newest != null && newest.id != _lastBottomId) {
      final hadPrevious = _lastBottomId != null;
      _lastBottomId = newest.id;
      if (hadPrevious) _maybeAutoScroll(newest.senderId == myId);
    }
    final typing = chat.typingUsers.isNotEmpty;

    // Pakai instance percakapan terbaru dari provider (status baca/sampai
    // diperbarui di sini secara live).
    final liveConv = chat.conversationById(_convId) ?? widget.conversation;

    // Nama-nama user yang sedang mengetik (untuk grup).
    final typingNames = chat.typingUsers.map((id) {
      final m = widget.conversation.members.where((u) => u.id == id);
      return m.isNotEmpty ? m.first.displayName : 'Seseorang';
    }).toList();

    // Posisi penanda "pesan baru": sebelum pesan ke-(_initialUnread) dari
    // bawah yang berasal dari orang lain.
    int? unreadStart;
    if (_initialUnread > 0 && chat.messages.isNotEmpty) {
      var count = 0;
      for (var i = chat.messages.length - 1; i >= 0; i--) {
        if (chat.messages[i].senderId != myId) {
          count++;
          if (count == _initialUnread) {
            unreadStart = i;
            break;
          }
        }
      }
    }

    return Scaffold(
      backgroundColor: context.watch<SettingsProvider>().chatWallpaperColor ??
          palette.chatBackground,
      appBar: _searching
          ? _buildSearchAppBar(palette)
          : AppBar(
              titleSpacing: 0,
              toolbarHeight: 64,
              title: InkWell(
                onTap: _openInfo,
                child: Row(
                  children: [
                    Avatar(
                      url: liveConv.avatarUrl,
                      name: liveConv.avatarName,
                      radius: 19,
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            liveConv.title,
                            style: const TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (typing)
                            Text(
                              _appBarTypingText(typingNames, isGroup),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                fontSize: 12,
                                color: Theme.of(context).colorScheme.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            )
                          else if (isGroup)
                            Text(
                              '${widget.conversation.members.length} anggota',
                              style:
                                  TextStyle(fontSize: 12, color: palette.muted),
                            )
                          else if (chat.presenceText(liveConv) != null)
                            Text(
                              chat.presenceText(liveConv)!,
                              style: TextStyle(
                                fontSize: 12,
                                color: chat.presenceText(liveConv) == 'online'
                                    ? Theme.of(context).colorScheme.primary
                                    : palette.muted,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              actions: [
                if (!isGroup)
                  IconButton(
                    icon: const Icon(Icons.videocam_rounded),
                    tooltip: 'Panggilan video',
                    onPressed: () => context
                        .read<CallProvider>()
                        .startCall(liveConv, video: true),
                  ),
                if (!isGroup)
                  IconButton(
                    icon: const Icon(Icons.call_rounded),
                    tooltip: 'Panggilan suara',
                    onPressed: () =>
                        context.read<CallProvider>().startCall(liveConv),
                  ),
                IconButton(
                  icon: const Icon(Icons.search_rounded),
                  onPressed: () => setState(() => _searching = true),
                ),
                PopupMenuButton<String>(
                  onSelected: (v) {
                    if (v == 'disappearing') _showDisappearingDialog(liveConv);
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'disappearing',
                      child: Row(
                        children: [
                          Icon(
                            liveConv.disappearingSeconds > 0
                                ? Icons.timer_rounded
                                : Icons.timer_outlined,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          const Text('Pesan sementara'),
                        ],
                      ),
                    ),
                  ],
                ),
              ],
            ),
      body: Column(
        children: [
          if (!chat.connected) _connectionBanner(),
          if (!isGroup &&
              liveConv.peer != null &&
              !liveConv.peerIsContact)
            _unknownContactBanner(liveConv, palette),
          if (liveConv.pinnedMessageId != null)
            _pinnedBanner(liveConv.pinnedMessageId!, palette),
          Expanded(
            child: chat.loadingMessages
                ? const Center(child: CircularProgressIndicator())
                : chat.messages.isEmpty
                    ? Center(
                        child: Text(
                          'Mulai percakapan 👋',
                          style: TextStyle(color: palette.muted, fontSize: 15),
                        ),
                      )
                    : Stack(
                        children: [
                          NotificationListener<ScrollNotification>(
                            onNotification: (_) {
                              _updateSticky();
                              _onScrollCheck();
                              final show = _scroll.hasClients &&
                                  _scroll.position.pixels > 600;
                              if (show != _showJump) {
                                setState(() => _showJump = show);
                              }
                              return false;
                            },
                            child: ListView.builder(
                              key: _listKey,
                              controller: _scroll,
                              reverse: true,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              itemCount:
                                  chat.messages.length + (typing ? 1 : 0),
                              itemBuilder: (_, i) {
                                // reverse: index 0 = paling bawah (terbaru).
                                if (typing && i == 0) {
                                  return TypingIndicator(
                                    name: isGroup
                                        ? _bubbleTypingName(typingNames)
                                        : null,
                                  );
                                }
                                final di = chat.messages.length -
                                    1 -
                                    (typing ? i - 1 : i);
                                final m = chat.messages[di];
                                final mine = m.senderId == myId;
                                final msgKey = _msgKeys.putIfAbsent(
                                    m.id, () => GlobalKey());
                                Widget item = KeyedSubtree(
                                  key: msgKey,
                                  child: GestureDetector(
                                    onLongPress: () =>
                                        _showMessageMenu(m, mine),
                                    child: MessageBubble(
                                      message: m,
                                      isMine: mine,
                                      showSender: isGroup,
                                      status: mine
                                          ? chat.statusOf(m, liveConv)
                                          : null,
                                      highlight:
                                          _searching ? _searchQuery : null,
                                      starred: chat.isStarred(m.id),
                                      mentionNames: isGroup
                                          ? liveConv.members
                                              .map((u) => u.displayName)
                                              .toList()
                                          : const [],
                                      onViewOnce: (id) =>
                                          context.read<ChatProvider>()
                                              .markViewOnce(id),
                                      onOpenContact: _openContact,
                                      myUserId: myId,
                                      onPollVote: (id, opt) => context
                                          .read<ChatProvider>()
                                          .votePoll(id, opt),
                                      onQuoteTap: (id) =>
                                          _scrollToMessage(id, flash: true),
                                      onCallBack: isGroup
                                          ? null
                                          : () => context
                                              .read<CallProvider>()
                                              .startCall(liveConv),
                                    ),
                                  ),
                                );
                                // Kedip sorot saat pesan ini jadi tujuan lompat.
                                if (m.id == _flashId) {
                                  item = AnimatedContainer(
                                    duration:
                                        const Duration(milliseconds: 300),
                                    color: Theme.of(context)
                                        .colorScheme
                                        .primary
                                        .withValues(alpha: 0.12),
                                    child: item,
                                  );
                                }
                                if (!m.deleted && m.type != 'CALL') {
                                  // Geser kanan = balas (semua pesan);
                                  // geser kiri = hapus (hanya pesan sendiri).
                                  item = Dismissible(
                                    key: ValueKey(m.id),
                                    direction: mine
                                        ? DismissDirection.horizontal
                                        : DismissDirection.startToEnd,
                                    dismissThresholds: const {
                                      DismissDirection.startToEnd: 0.25,
                                      DismissDirection.endToStart: 0.3,
                                    },
                                    background: Container(
                                      alignment: Alignment.centerLeft,
                                      padding: const EdgeInsets.only(left: 28),
                                      child: Icon(Icons.reply_rounded,
                                          color: Theme.of(context)
                                              .colorScheme
                                              .primary),
                                    ),
                                    secondaryBackground: Container(
                                      alignment: Alignment.centerRight,
                                      padding: const EdgeInsets.only(right: 28),
                                      child: const Icon(Icons.delete_rounded,
                                          color: Color(0xFFEF4444)),
                                    ),
                                    confirmDismiss: (dir) async {
                                      if (dir == DismissDirection.startToEnd) {
                                        context
                                            .read<ChatProvider>()
                                            .setReplyingTo(m);
                                      } else if (mine) {
                                        await _confirmDeleteMessage(m);
                                      }
                                      return false;
                                    },
                                    child: item,
                                  );
                                }
                                // Chip tanggal di atas pesan pertama tiap hari.
                                final showDate = di == 0 ||
                                    !_sameDay(
                                      chat.messages[di - 1].createdAt,
                                      m.createdAt,
                                    );
                                if (!showDate && di != unreadStart) return item;
                                GlobalKey? dateKey;
                                if (showDate) {
                                  final dt = m.createdAt;
                                  final dayKey =
                                      '${dt.year}-${dt.month}-${dt.day}';
                                  dateKey = _dateChipKeys.putIfAbsent(
                                      dayKey, () => GlobalKey());
                                  _dateLabels[dayKey] = _dateLabel(dt);
                                }
                                return Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.stretch,
                                  children: [
                                    if (showDate)
                                      _dateChip(_dateLabel(m.createdAt),
                                          palette,
                                          key: dateKey),
                                    if (di == unreadStart)
                                      _unreadDivider(palette),
                                    item,
                                  ],
                                );
                              },
                            ),
                          ),
                          Positioned(
                            top: 6,
                            left: 0,
                            right: 0,
                            child: IgnorePointer(
                              child: Center(
                                child: chat.loadingMore
                                    ? Container(
                                        margin: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        padding: const EdgeInsets.all(8),
                                        decoration: BoxDecoration(
                                          color: Theme.of(context)
                                              .colorScheme
                                              .surface,
                                          shape: BoxShape.circle,
                                          border: Border.all(
                                              color: palette.cardBorder),
                                        ),
                                        child: const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              strokeWidth: 2),
                                        ),
                                      )
                                    : (_stickyDate != null
                                        ? _dateChip(_stickyDate!, palette)
                                        : const SizedBox.shrink()),
                              ),
                            ),
                          ),
                          if (_showJump)
                            Positioned(
                              bottom: 12,
                              right: 12,
                              child: Material(
                                color: Theme.of(context).colorScheme.surface,
                                elevation: 2,
                                shape: const CircleBorder(),
                                child: InkWell(
                                  customBorder: const CircleBorder(),
                                  onTap: () {
                                    _scrollToBottom();
                                    setState(() => _showJump = false);
                                  },
                                  child: Padding(
                                    padding: const EdgeInsets.all(9),
                                    child: Icon(
                                      Icons.keyboard_double_arrow_down_rounded,
                                      color: Theme.of(context)
                                          .colorScheme
                                          .primary,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
          if (_uploading)
            Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
                  const SizedBox(width: 8),
                  Text('Mengunggah…', style: TextStyle(color: palette.muted)),
                ],
              ),
            ),
          if (_mentionSuggestions.isNotEmpty) _mentionList(palette),
          if (_editing != null) _editingBar(palette),
          if (chat.replyingTo != null) _replyBar(chat.replyingTo!, palette),
          _buildInputBar(palette),
        ],
      ),
    );
  }

  Widget _mentionList(AppPalette palette) {
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        border: Border(top: BorderSide(color: palette.cardBorder)),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final u in _mentionSuggestions)
            ListTile(
              dense: true,
              leading:
                  Avatar(url: u.avatarUrl, name: u.displayName, radius: 18),
              title: Text(u.displayName),
              onTap: () => _insertMention(u),
            ),
        ],
      ),
    );
  }

  Widget _unknownContactBanner(Conversation conv, AppPalette palette) {
    final peer = conv.peer!;
    return Container(
      color: const Color(0xFFFFF4D6),
      padding: const EdgeInsets.fromLTRB(14, 10, 10, 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.info_outline_rounded,
                  size: 18, color: Color(0xFF8A6D00)),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Belum di kontak Anda • nama profil: ${peer.displayName}',
                  style: const TextStyle(
                      color: Color(0xFF8A6D00), fontSize: 12.5),
                ),
              ),
            ],
          ),
          Row(
            children: [
              TextButton.icon(
                icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                label: const Text('Tambah ke kontak'),
                onPressed: () => _addContactFromChat(peer),
              ),
              TextButton.icon(
                icon: const Icon(Icons.block_rounded,
                    size: 18, color: Color(0xFFEF4444)),
                label: const Text('Blokir',
                    style: TextStyle(color: Color(0xFFEF4444))),
                onPressed: () => _blockFromChat(peer),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _addContactFromChat(AppUser peer) async {
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    try {
      await chat.addContact(peer.id); // segarkan kontak + percakapan (realtime)
      messenger.showSnackBar(SnackBar(
          content: Text('${peer.displayName} ditambahkan ke kontak')));
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  Future<void> _blockFromChat(AppUser peer) async {
    final chat = context.read<ChatProvider>();
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text('Blokir ${peer.displayName}?'),
        content: const Text('Anda tidak akan menerima pesan dari kontak ini.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('Blokir')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await chat.service.blockUser(peer.id);
      messenger.showSnackBar(const SnackBar(content: Text('Kontak diblokir')));
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text(ApiClient.errorMessage(e))));
    }
  }

  Widget _pinnedBanner(String messageId, AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    final chat = context.read<ChatProvider>();
    Message? m;
    for (final x in chat.messages) {
      if (x.id == messageId) {
        m = x;
        break;
      }
    }
    final preview = m == null
        ? 'Pesan disematkan'
        : m.deleted
            ? 'Pesan dihapus'
            : (m.type == 'TEXT' ? (m.content ?? '') : '📎 Media');
    return Material(
      color: scheme.primary.withValues(alpha: 0.06),
      child: InkWell(
        onTap: () => _scrollToMessage(messageId, flash: true),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 4, 8),
          child: Row(
            children: [
              Icon(Icons.push_pin_rounded, size: 16, color: scheme.primary),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Pesan tersemat',
                        style: TextStyle(
                            color: scheme.primary,
                            fontWeight: FontWeight.w700,
                            fontSize: 12)),
                    Text(preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: palette.muted, fontSize: 12.5)),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Lepas sematan',
                icon: const Icon(Icons.close_rounded, size: 18),
                onPressed: () => chat.pinMessage(_convId, null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _editingBar(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.primary.withValues(alpha: 0.08),
      padding: const EdgeInsets.fromLTRB(14, 8, 6, 8),
      child: Row(
        children: [
          Icon(Icons.edit_rounded, size: 18, color: scheme.primary),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Edit pesan',
                    style: TextStyle(
                        color: scheme.primary, fontWeight: FontWeight.w700,
                        fontSize: 12.5)),
                Text(_editing?.content ?? '',
                    maxLines: 1, overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted, fontSize: 12.5)),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: _cancelEditing,
          ),
        ],
      ),
    );
  }

  /// Teks indikator typing di app bar.
  /// Direct: "mengetik…". Grup: sertakan nama yang mengetik.
  String _appBarTypingText(List<String> names, bool isGroup) {
    if (!isGroup) return 'mengetik…';
    if (names.isEmpty) return 'mengetik…';
    if (names.length == 1) return '${names[0]} sedang mengetik…';
    if (names.length == 2) {
      return '${names[0]} & ${names[1]} sedang mengetik…';
    }
    return '${names[0]}, ${names[1]} +${names.length - 2} sedang mengetik…';
  }

  /// Nama yang ditampilkan di atas gelembung titik-titik (grup).
  String _bubbleTypingName(List<String> names) {
    if (names.isEmpty) return '';
    if (names.length <= 2) return names.join(', ');
    return '${names[0]}, ${names[1]} +${names.length - 2}';
  }

  static const _days = [
    'Senin', 'Selasa', 'Rabu', 'Kamis', 'Jumat', 'Sabtu', 'Minggu',
  ];
  static const _months = [
    'Januari', 'Februari', 'Maret', 'April', 'Mei', 'Juni',
    'Juli', 'Agustus', 'September', 'Oktober', 'November', 'Desember',
  ];

  bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  /// Tentukan tanggal yang "menempel" di atas berdasar chip terdekat di atas.
  void _updateSticky() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final listBox =
          _listKey.currentContext?.findRenderObject() as RenderBox?;
      if (listBox == null) return;
      final topY = listBox.localToGlobal(Offset.zero).dy;
      final msgs = _chatProv.messages;

      // 1) Tanggal dari PESAN teratas yang terlihat (key per-pesan selalu ada
      //    untuk item yang ter-render → akurat, tak bergantung chip).
      DateTime? topDate;
      var bestDy = -1e9;
      var minDy = 1e9;
      DateTime? topmost;
      for (final m in msgs) {
        final ctx = _msgKeys[m.id]?.currentContext;
        if (ctx == null) continue;
        final box = ctx.findRenderObject() as RenderBox?;
        if (box == null) continue;
        final dy = box.localToGlobal(Offset.zero).dy;
        if (dy <= topY + 8 && dy > bestDy) {
          bestDy = dy;
          topDate = m.createdAt;
        }
        if (dy < minDy) {
          minDy = dy;
          topmost = m.createdAt;
        }
      }
      topDate ??= topmost; // kalau di paling atas (semua pesan di bawah garis)

      // 2) Sembunyikan floating bila chip inline hari itu sedang terlihat di
      //    dekat atas (anti-dobel).
      var inlineAtTop = false;
      if (topDate != null) {
        final dayKey =
            '${topDate.year}-${topDate.month}-${topDate.day}';
        final ck = _dateChipKeys[dayKey]?.currentContext;
        if (ck != null) {
          final cbox = ck.findRenderObject() as RenderBox?;
          if (cbox != null) {
            final cdy = cbox.localToGlobal(Offset.zero).dy;
            if (cdy >= topY - 4 && cdy <= topY + 64) inlineAtTop = true;
          }
        }
      }

      final next =
          (topDate == null || inlineAtTop) ? null : _dateLabel(topDate);
      if (next != _stickyDate && mounted) {
        setState(() => _stickyDate = next);
      }
    });
  }

  String _dateLabel(DateTime dt) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final d = DateTime(dt.year, dt.month, dt.day);
    final diff = today.difference(d).inDays;
    if (diff == 0) return 'Hari ini';
    if (diff == 1) return 'Kemarin';
    if (diff > 1 && diff < 7) return _days[dt.weekday - 1];
    return '${dt.day} ${_months[dt.month - 1]} ${dt.year}';
  }

  Widget _dateChip(String label, AppPalette palette, {Key? key}) {
    return Center(
      child: Container(
        key: key,
        margin: const EdgeInsets.symmetric(vertical: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: palette.cardBorder),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
            color: palette.muted,
          ),
        ),
      ),
    );
  }

  String _snippet(Message m) {
    if (m.deleted) return 'Pesan dihapus';
    switch (m.type) {
      case 'IMAGE':
        return '📷 Foto';
      case 'FILE':
        return '📎 ${m.mediaName ?? 'File'}';
      case 'STICKER':
        return '${m.content ?? '🙂'} Stiker';
      case 'VOICE':
        return '🎤 Pesan suara';
      case 'CALL':
        return '📞 Panggilan suara';
      default:
        return m.content ?? '';
    }
  }

  static const List<String> _quickReactions = [
    '👍', '❤️', '😂', '😮', '😢', '🙏',
  ];

  void _showMessageMenu(Message m, bool mine) {
    if (m.type == 'CALL') return; // event panggilan: tak ada aksi
    final scheme = Theme.of(context).colorScheme;
    final myId = context.read<AuthProvider>().userId;
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Bilah reaksi cepat (ala WhatsApp).
            if (!m.deleted)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceAround,
                  children: [
                    for (final e in _quickReactions)
                      InkWell(
                        borderRadius: BorderRadius.circular(24),
                        onTap: () {
                          Navigator.pop(context);
                          context.read<ChatProvider>().react(m.id, e);
                        },
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: m.myReaction(myId) == e
                                ? scheme.primary.withValues(alpha: 0.18)
                                : Colors.transparent,
                          ),
                          child: Text(e, style: const TextStyle(fontSize: 26)),
                        ),
                      ),
                  ],
                ),
              ),
            if (!m.deleted) const Divider(height: 1),
            if (!m.deleted)
              ListTile(
                leading: const Icon(Icons.reply_rounded),
                title: const Text('Balas'),
                onTap: () {
                  Navigator.pop(context);
                  context.read<ChatProvider>().setReplyingTo(m);
                },
              ),
            if (!m.deleted)
              ListTile(
                leading: const Icon(Icons.shortcut_rounded),
                title: const Text('Teruskan'),
                onTap: () {
                  Navigator.pop(context);
                  _forward(m);
                },
              ),
            if (!m.deleted)
              Builder(builder: (_) {
                final starred = context.read<ChatProvider>().isStarred(m.id);
                return ListTile(
                  leading: Icon(starred
                      ? Icons.star_rounded
                      : Icons.star_outline_rounded),
                  title: Text(starred ? 'Hapus bintang' : 'Bintangi'),
                  onTap: () {
                    Navigator.pop(context);
                    context.read<ChatProvider>().toggleStar(m.id, !starred);
                  },
                );
              }),
            if (mine && !m.deleted && m.type == 'TEXT')
              ListTile(
                leading: const Icon(Icons.edit_rounded),
                title: const Text('Edit'),
                onTap: () {
                  Navigator.pop(context);
                  _startEditing(m);
                },
              ),
            if (!m.deleted)
              Builder(builder: (_) {
                final pinned = context
                        .read<ChatProvider>()
                        .conversationById(_convId)
                        ?.pinnedMessageId ==
                    m.id;
                return ListTile(
                  leading: Icon(pinned
                      ? Icons.push_pin_rounded
                      : Icons.push_pin_outlined),
                  title: Text(pinned ? 'Lepas sematan' : 'Sematkan'),
                  onTap: () {
                    Navigator.pop(context);
                    context
                        .read<ChatProvider>()
                        .pinMessage(_convId, pinned ? null : m.id);
                  },
                );
              }),
            if (!m.deleted && m.type == 'TEXT' && m.content != null)
              ListTile(
                leading: const Icon(Icons.copy_rounded),
                title: const Text('Salin'),
                onTap: () {
                  Navigator.pop(context);
                  Clipboard.setData(ClipboardData(text: m.content!));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Disalin')),
                  );
                },
              ),
            if (mine && !m.deleted)
              ListTile(
                leading: const Icon(Icons.info_outline_rounded),
                title: const Text('Info'),
                onTap: () {
                  Navigator.pop(context);
                  _showMessageInfo(m);
                },
              ),
            if (mine && !m.deleted)
              ListTile(
                leading: Icon(Icons.delete_rounded, color: scheme.error),
                title: Text('Hapus', style: TextStyle(color: scheme.error)),
                onTap: () {
                  Navigator.pop(context);
                  _confirmDeleteMessage(m);
                },
              ),
          ],
          ),
        ),
      ),
    );
  }

  /// Tampilkan detail "Info" untuk pesan yang saya kirim: kapan dibaca dan
  /// diterima oleh tiap anggota lain. Memakai readAt/deliveredAt percakapan.
  void _showMessageInfo(Message m) {
    final chat = context.read<ChatProvider>();
    final conv = chat.conversationById(_convId) ?? widget.conversation;
    final myId = context.read<AuthProvider>().user?.id ?? '';
    final others = conv.members.where((u) => u.id != myId).toList();
    final scheme = Theme.of(context).colorScheme;
    final palette = AppPalette.of(context);

    String fmt(DateTime? dt) =>
        dt == null ? '—' : DateFormat('d MMM, HH:mm').format(dt);

    Widget stateRow(IconData icon, Color color, String label, DateTime? dt) =>
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Row(
            children: [
              Icon(icon, size: 20, color: color),
              const SizedBox(width: 12),
              Text(label,
                  style: const TextStyle(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text(fmt(dt), style: TextStyle(color: palette.muted)),
            ],
          ),
        );

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8),
                  child: Text('Info pesan',
                      style:
                          TextStyle(fontWeight: FontWeight.w700, fontSize: 16)),
                ),
                // Ringkasan pesan.
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: scheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    _infoPreview(m),
                    maxLines: 3,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: palette.muted),
                  ),
                ),
                const SizedBox(height: 16),
                if (!conv.isGroup) ...[
                  Builder(builder: (_) {
                    final o = others.isNotEmpty ? others.first : null;
                    final read = o == null ? null : conv.readAt[o.id];
                    final delivered =
                        o == null ? null : conv.deliveredAt[o.id];
                    final readOk =
                        read != null && !read.isBefore(m.createdAt);
                    final delivOk = delivered != null &&
                        !delivered.isBefore(m.createdAt);
                    return Column(
                      children: [
                        stateRow(Icons.done_all_rounded, scheme.primary,
                            'Dibaca', readOk ? read : null),
                        stateRow(Icons.done_all_rounded, palette.muted,
                            'Terkirim', delivOk ? delivered : null),
                      ],
                    );
                  }),
                ] else ...[
                  Text('Dibaca oleh',
                      style: TextStyle(
                          color: palette.muted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ..._infoMemberRows(others, conv, m, read: true, palette: palette),
                  const SizedBox(height: 12),
                  Text('Terkirim ke',
                      style: TextStyle(
                          color: palette.muted,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  ..._infoMemberRows(others, conv, m,
                      read: false, palette: palette),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _infoPreview(Message m) {
    switch (m.type) {
      case 'IMAGE':
        return '📷 Foto';
      case 'VIDEO':
        return '🎬 Video';
      case 'VOICE':
        return '🎤 Pesan suara';
      case 'FILE':
        return '📎 ${m.mediaName ?? 'Dokumen'}';
      case 'STICKER':
        return 'Stiker';
      case 'LOCATION':
        return '📍 Lokasi';
      case 'CONTACT':
        return '👤 Kontak';
      case 'ALBUM':
        return '🖼️ Album';
      case 'POLL':
        return '📊 Polling';
      default:
        return m.content ?? '';
    }
  }

  List<Widget> _infoMemberRows(
    List<AppUser> others,
    Conversation conv,
    Message m, {
    required bool read,
    required AppPalette palette,
  }) {
    if (others.isEmpty) {
      return [Text('—', style: TextStyle(color: palette.muted))];
    }
    final rows = <Widget>[];
    for (final o in others) {
      final dt = read ? conv.readAt[o.id] : conv.deliveredAt[o.id];
      final ok = dt != null && !dt.isBefore(m.createdAt);
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: 5),
        child: Row(
          children: [
            Avatar(url: o.avatarUrl, name: o.displayName, radius: 16),
            const SizedBox(width: 10),
            Expanded(
                child: Text(o.displayName,
                    overflow: TextOverflow.ellipsis)),
            Text(
              ok ? DateFormat('d MMM, HH:mm').format(dt) : 'Menunggu',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ],
        ),
      ));
    }
    return rows;
  }

  Future<void> _confirmDeleteMessage(Message m) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hapus pesan?'),
        content: const Text('Pesan akan dihapus untuk semua orang.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Hapus'),
          ),
        ],
      ),
    );
    if (ok == true && mounted) {
      context.read<ChatProvider>().deleteMessage(m.id);
    }
  }

  Future<void> _forward(Message m) async {
    final ids = await Navigator.of(context).push<List<String>>(
      MaterialPageRoute(builder: (_) => const ForwardScreen()),
    );
    if (ids != null && ids.isNotEmpty && mounted) {
      context.read<ChatProvider>().forwardTo(ids, m);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Diteruskan ke ${ids.length} chat')),
      );
    }
  }

  Widget _replyBar(Message m, AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: Theme.of(context).colorScheme.surface,
      padding: const EdgeInsets.fromLTRB(12, 6, 8, 0),
      child: Container(
        decoration: BoxDecoration(
          color: scheme.primary.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(width: 3, color: scheme.primary),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Membalas ${m.senderName ?? ''}'.trim(),
                        style: TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 12,
                          color: scheme.primary,
                        ),
                      ),
                      Text(
                        _snippet(m),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(fontSize: 12.5, color: palette.muted),
                      ),
                    ],
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded, size: 20),
                onPressed: () =>
                    context.read<ChatProvider>().setReplyingTo(null),
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _openInfo() {
    final conv = _chatProv.conversationById(_convId) ?? widget.conversation;
    if (conv.isGroup) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => GroupInfoScreen(conversation: conv)),
      );
    } else {
      final peer = conv.peer ?? widget.conversation.peer;
      if (peer != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) => ProfileViewScreen(user: peer, canMessage: false),
          ),
        );
      }
    }
  }

  PreferredSizeWidget _buildSearchAppBar(AppPalette palette) {
    return AppBar(
      titleSpacing: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_rounded),
        onPressed: () => setState(() {
          _searching = false;
          _searchCtrl.clear();
          _searchQuery = '';
          _searchResults = [];
          _matchPos = -1;
        }),
      ),
      title: TextField(
        controller: _searchCtrl,
        autofocus: true,
        onChanged: _onSearchChanged,
        decoration: const InputDecoration(
          hintText: 'Cari di chat ini…',
          filled: false,
          border: InputBorder.none,
          enabledBorder: InputBorder.none,
          focusedBorder: InputBorder.none,
        ),
      ),
      actions: [
        if (_searchLoading)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 8),
            child: Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2),
              ),
            ),
          )
        else if (_searchQuery.trim().isNotEmpty)
          Center(
            child: Text(
              _searchResults.isEmpty
                  ? '0'
                  : '${_matchPos + 1}/${_searchResults.length}',
              style: TextStyle(color: palette.muted, fontSize: 12),
            ),
          ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
          onPressed: _searchResults.isEmpty ? null : () => _gotoMatch(-1),
        ),
        IconButton(
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
          onPressed: _searchResults.isEmpty ? null : () => _gotoMatch(1),
        ),
      ],
    );
  }

  void _onSearchChanged(String q) {
    setState(() => _searchQuery = q);
    _searchDebounce?.cancel();
    _searchDebounce =
        Timer(const Duration(milliseconds: 350), () => _runSearch(q));
  }

  Future<void> _runSearch(String q) async {
    final query = q.trim();
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _matchPos = -1;
      });
      return;
    }
    setState(() => _searchLoading = true);
    try {
      // Cari ke backend → SEMUA pesan cocok (bukan hanya yang ter-load).
      final res = await _chatProv.service.searchMessages(_convId, query);
      if (!mounted) return;
      setState(() {
        _searchResults = res;
        _matchPos = res.isNotEmpty ? res.length - 1 : -1; // mulai dari terbaru
      });
      if (_matchPos >= 0) await _scrollToMatchMessage();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(ApiClient.errorMessage(e))),
        );
      }
    } finally {
      if (mounted) setState(() => _searchLoading = false);
    }
  }

  Future<void> _gotoMatch(int delta) async {
    if (_searchResults.isEmpty) return;
    setState(() =>
        _matchPos = (_matchPos + delta).clamp(0, _searchResults.length - 1));
    await _scrollToMatchMessage();
  }

  Future<void> _scrollToMatchMessage() async {
    if (_matchPos < 0 || _matchPos >= _searchResults.length) return;
    await _scrollToMessage(_searchResults[_matchPos].id);
  }

  /// Sorot sementara pesan (efek kedip ala WhatsApp saat lompat ke pesan).
  void _flash(String id) {
    _flashTimer?.cancel();
    setState(() => _flashId = id);
    _flashTimer = Timer(const Duration(milliseconds: 1400), () {
      if (mounted) setState(() => _flashId = null);
    });
  }

  /// Lompat ke pesan [targetId] (memuat pesan lama bila perlu) dengan transisi
  /// mulus. Bila [flash] true, pesan disorot sebentar setelah terlihat.
  Future<void> _scrollToMessage(String targetId, {bool flash = false}) async {
    if (_scrollingToMsg) return;
    _scrollingToMsg = true;
    try {
      // 1) Muat pesan lama sampai target benar-benar ada (lewati pagination).
      //    Batas tinggi + berhenti saat hasMore habis → pesan terlama pun
      //    pasti ikut ter-load.
      var guard = 0;
      while (!_chatProv.messages.any((m) => m.id == targetId) &&
          _chatProv.hasMore &&
          guard < 400) {
        await _chatProv.loadMore(_convId);
        guard++;
      }
      if (!mounted || !_scroll.hasClients) return;
      if (!_chatProv.messages.any((m) => m.id == targetId)) return;

      // Beri 1 frame agar daftar (yang baru di-prepend) selesai layout.
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted || !_scroll.hasClients) return;

      // 2) Animasi bertahap menuju estimasi posisi sampai widget target
      //    ter-render, lalu ensureVisible untuk presisi + transisi halus.
      //    (ListView malas: item jauh belum dibangun → animasikan mendekat
      //    sambil estimasi maxScrollExtent ikut menajam tiap langkah.)
      for (var attempt = 0; attempt < 60; attempt++) {
        final ctx = _msgKeys[targetId]?.currentContext;
        if (ctx != null) {
          // ignore: use_build_context_synchronously
          await Scrollable.ensureVisible(ctx, alignment: 0.35, duration: const Duration(milliseconds: 320), curve: Curves.easeInOut);
          if (flash) _flash(targetId);
          return;
        }
        final msgs = _chatProv.messages;
        final di = msgs.indexWhere((m) => m.id == targetId);
        if (di < 0) return;
        final pos = _scroll.position;
        final listIndex = msgs.length - 1 - di; // reverse: makin lama makin atas
        final frac = msgs.length <= 1 ? 0.0 : listIndex / (msgs.length - 1);
        final target = frac * pos.maxScrollExtent;
        // Melangkah 70% mendekat tiap iterasi → konvergen & terlihat bergerak.
        final next = pos.pixels + (target - pos.pixels) * 0.7;
        await _scroll.animateTo(
          next.clamp(0.0, pos.maxScrollExtent),
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeInOut,
        );
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted || !_scroll.hasClients) return;
      }
    } finally {
      _scrollingToMsg = false;
    }
  }

  Widget _connectionBanner() {
    return Container(
      width: double.infinity,
      color: const Color(0xFF4B5563),
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: const Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          SizedBox(
            width: 13,
            height: 13,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.white,
            ),
          ),
          SizedBox(width: 8),
          Text(
            'Menghubungkan…',
            style: TextStyle(color: Colors.white, fontSize: 12.5),
          ),
        ],
      ),
    );
  }

  Widget _unreadDivider(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    final label = _initialUnread == 1
        ? '1 pesan baru'
        : '$_initialUnread pesan baru';
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.symmetric(vertical: 6),
      color: scheme.primary.withValues(alpha: 0.10),
      alignment: Alignment.center,
      child: Text(
        label,
        style: TextStyle(
          color: scheme.primary,
          fontWeight: FontWeight.w700,
          fontSize: 12,
          letterSpacing: 0.3,
        ),
      ),
    );
  }

  void _sendSticker(String sticker) {
    context.read<ChatProvider>().sendSticker(_convId, sticker);
    _scrollToBottom();
  }

  void _showStickers() {
    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (_) => StickerPicker(onSelected: _sendSticker),
    );
  }

  Widget _buildInputBar(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    if (_recordedPath != null) return _buildReviewBar(palette);
    if (_recording) return _buildRecordingBar(palette);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Container(
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: palette.cardBorder),
                ),
                child: Row(
                  children: [
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.add_rounded),
                      color: palette.muted,
                      onPressed: _uploading ? null : _showAttachMenu,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _input,
                        onChanged: _onInputChanged,
                        minLines: 1,
                        maxLines: 5,
                        textInputAction: TextInputAction.newline,
                        decoration: const InputDecoration(
                          hintText: 'Pesan',
                          filled: false,
                          border: InputBorder.none,
                          enabledBorder: InputBorder.none,
                          focusedBorder: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.emoji_emotions_outlined),
                      color: palette.muted,
                      onPressed: _showStickers,
                    ),
                    const SizedBox(width: 4),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Ada teks → kirim. Kosong → mikrofon (rekam pesan suara).
            GestureDetector(
              onTap: _hasText
                  ? _sendText
                  : (_uploading ? null : _startRecording),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  _hasText ? Icons.send_rounded : Icons.mic_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bilah saat sedang merekam pesan suara: hapus • timer • kirim.
  Widget _buildRecordingBar(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    final mm = (_recordSecs ~/ 60).toString();
    final ss = (_recordSecs % 60).toString().padLeft(2, '0');
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.delete_rounded, color: scheme.error),
              tooltip: 'Batal',
              onPressed: _cancelRecording,
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: palette.cardBorder),
                ),
                child: Row(
                  children: [
                    AnimatedOpacity(
                      opacity: _recordBlink ? 1 : 0.25,
                      duration: const Duration(milliseconds: 400),
                      child: const Icon(Icons.fiber_manual_record,
                          color: Color(0xFFEF4444), size: 14),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      '$mm:$ss',
                      style: TextStyle(
                        color: palette.muted,
                        fontWeight: FontWeight.w600,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('Merekam…',
                        style: TextStyle(color: palette.muted, fontSize: 12.5)),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 8),
            // Stop → masuk mode preview (dengarkan dulu sebelum kirim).
            GestureDetector(
              onTap: _stopRecording,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.stop_rounded,
                    color: Colors.white, size: 26),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Bilah PREVIEW rekaman: hapus • dengarkan (waveform) • kirim — ala WhatsApp.
  Widget _buildReviewBar(AppPalette palette) {
    final scheme = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
        child: Row(
          children: [
            IconButton(
              icon: Icon(Icons.delete_rounded, color: scheme.error),
              tooltip: 'Hapus',
              onPressed: _discardRecorded,
            ),
            Expanded(
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.surface,
                  borderRadius: BorderRadius.circular(26),
                  border: Border.all(color: palette.cardBorder),
                ),
                child: VoiceReviewPlayer(
                  // key per-rekaman agar player ter-reset tiap rekaman baru.
                  key: ValueKey(_recordedPath),
                  path: _recordedPath!,
                  seconds: _recordedSecs,
                  accent: scheme.primary,
                  trackColor: palette.muted.withValues(alpha: 0.35),
                  textColor: palette.muted,
                ),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _sendRecorded,
              child: Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: scheme.primary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.send_rounded,
                    color: Colors.white, size: 22),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
